% =========================================================================
% MAIN_SIM.M  5G NR PDSCH Link-Level Simulator — Master Script
%
% This script runs the full TX --> Channel --> RX pipeline for three
% channel estimators (LS, MMSE, NN) and measures BLER vs SNR.
%
% RUN ORDER:
%   1. First run: ml/train_estimator.m  (trains the NN, saves channel_net.mat)
%   2. Then run:  main_sim.m            (this file)
%   3. Then run:  results/plot_bler.m   (generates the BLER curves)
%
% OUTPUTS:
%   results/bler_results.mat  -- BLER data for all three estimators
%   Console output showing progress at each SNR point
%
% BLOCK DIAGRAM:
%
%  [random bits]
%       |
%  [CRC-24A attach]          tx/ldpc_encode.m
%       |
%  [LDPC encode BG1 r=1/2]   tx/ldpc_encode.m
%       |
%  [QPSK/16QAM modulate]     tx/modulate.m
%       |
%  [build resource grid]     (inline — place pilots + data)
%       |
%  [CP-OFDM modulate]        tx/ofdm_modulate.m
%       |
%  [multipath channel]       (inline — multiply by h_freq)
%       |
%  [AWGN noise]              channel/awgn_channel.m
%       |
%  [CP-OFDM demodulate]      rx/ofdm_demodulate.m
%       |
%  [channel estimation]      rx/estimate_ls.m / estimate_mmse.m / estimate_nn.m
%       |
%  [ZF equalization]         rx/equalize_zf.m
%       |
%  [soft QAM demodulate]     rx/demodulate.m
%       |
%  [LDPC decode]             rx/ldpc_decode.m
%       |
%  [CRC check --> BLER count]
% =========================================================================

clear; clc;
addpath('tx', 'channel', 'rx', 'ml', 'results');

%% =========================================================================
%% SIMULATION PARAMETERS
%% =========================================================================

% --- SNR sweep ---
SNR_range = -5 : 2 : 20;     % SNR points to test (dB)
                               % -5 dB = noisy, 20 dB = clean

% --- Modulation ---
modOrder  = 4;                 % 4=QPSK (2 bits/sym), 16=16QAM (4 bits/sym)
bitsPerSym = log2(modOrder);   % bits per QAM symbol

% --- LDPC ---
bgn       = 1;                 % base graph 1 (for large blocks, rate >= 1/3)
codeRate  = 0.5;               % code rate = k/n (1/2 means 50% parity)
maxIter   = 50;                % max belief propagation iterations

% --- Transport block ---
K         = 1000;              % information bits per transport block

% --- OFDM parameters (5G NR mu=1, 30 kHz SCS) ---
Nfft      = 512;               % FFT size
Ncp       = 36;                % cyclic prefix length (samples)
Nsc       = 300;               % active subcarriers (25 RBs x 12)
Nsymbols  = 14;                % OFDM symbols per slot (normal CP)

% --- Pilot configuration ---
pilotSpacing  = 12;            % one pilot every 12 subcarriers (1 per RB)
pilotIdx      = (1 : pilotSpacing : Nsc)';  % pilot subcarrier indices
pilotSymbols  = ones(length(pilotIdx), 1);  % pilot values = +1 (BPSK)
Npilots       = length(pilotIdx);           % number of pilots

% --- Statistical reliability ---
minErrors = 100;               % collect at least 100 block errors per SNR
minBlocks = 1000;              % collect at least 1000 blocks per SNR

%% =========================================================================
%% PRECOMPUTATION
%% =========================================================================

% Data subcarrier indices (all subcarriers that are NOT pilots)
dataIdx = setdiff(1:Nsc, pilotIdx)';
Ndata   = length(dataIdx);               % number of data subcarriers

% Number of data symbols per slot
% Symbol 1 = pilots, symbols 2 to Nsymbols = data
NdataSymbols = Nsymbols - 1;            % = 13 data symbols per slot

% Expected number of bits per transport block after encoding
% codeword length = K_crc / codeRate where K_crc = K + 24 (CRC bits)
K_crc    = K + 24;                       % info bits + CRC-24A
N_coded  = ceil(K_crc / codeRate);       % codeword length

% Channel covariance matrix for MMSE estimator
% Model: exponential power delay profile with 6 taps
% This approximates a typical urban multipath channel (TDL-C style)
delays   = (0:5) * 1e-6;                        % tap delays: 0 to 5 microseconds
powers_dB = [0, -3, -6, -9, -12, -15];          % tap powers in dB
powers_lin = 10.^(powers_dB / 10);              % convert to linear
powers_lin = powers_lin / sum(powers_lin);       % normalise total power = 1

% Build covariance matrix R_hh[i,j] = sum_l(p_l * exp(j2pi*(i-j)*delay_l*SCS))
% This captures frequency correlation: nearby subcarriers have similar H
SCS       = 30e3;                                % subcarrier spacing 30 kHz
R_hh      = zeros(Nsc, Nsc);
for l = 1:length(delays)
    for i = 1:Nsc
        for j = 1:Nsc
            R_hh(i,j) = R_hh(i,j) + powers_lin(l) * ...
                exp(1j * 2 * pi * (i-j) * delays(l) * SCS);
        end
    end
end

% Load trained neural network estimator
% (must run ml/train_estimator.m first)
if exist('ml/channel_net.mat', 'file')
    load('ml/channel_net.mat', 'net');
    useNN = true;
    fprintf('Neural network estimator loaded.\n');
else
    useNN = false;
    fprintf('WARNING: channel_net.mat not found. NN estimator disabled.\n');
    fprintf('Run ml/train_estimator.m first to enable NN estimation.\n\n');
end

%% =========================================================================
%% BLER MEASUREMENT LOOP
%% =========================================================================

% Preallocate result arrays
BLER_ls   = zeros(size(SNR_range));
BLER_mmse = zeros(size(SNR_range));
BLER_nn   = zeros(size(SNR_range));

fprintf('Starting BLER simulation...\n');
fprintf('Modulation: %d-QAM  Code rate: %.2f  Block size: %d bits\n\n', ...
        modOrder, codeRate, K);

for snrIdx = 1:length(SNR_range)

    SNR_dB  = SNR_range(snrIdx);
    SNR_lin = 10^(SNR_dB / 10);
    noiseVar = 1 / SNR_lin;             % noise variance for demodulator

    fprintf('SNR = %3d dB ... ', SNR_dB);

    % Error and block counters for each estimator
    err_ls = 0;  blk_ls = 0;
    err_mm = 0;  blk_mm = 0;
    err_nn = 0;  blk_nn = 0;

    % Keep running until we have enough errors and blocks
    while (err_ls < minErrors || blk_ls < minBlocks) || ...
          (err_mm < minErrors || blk_mm < minBlocks) || ...
          (useNN && (err_nn < minErrors || blk_nn < minBlocks))

        %% ── TRANSMITTER ──────────────────────────────────────────────

        % Generate random information bits
        txBits   = randi([0 1], K, 1);

        % Attach CRC-24A (adds 24 bits for error detection at receiver)
        txCRC    = nrCRCEncode(txBits, '24A');

        % LDPC encode (adds parity bits for error correction)
        txCoded  = nrLDPCEncode(txCRC, bgn, codeRate);

        % QAM modulate (map bits to complex symbols)
        txSymbols = modulate(txCoded, modOrder);

        % Build resource grid [Nsc x Nsymbols]
        % Symbol 1: pilots at pilotIdx, zeros elsewhere
        % Symbols 2-14: data symbols at dataIdx
        grid = zeros(Nsc, Nsymbols);
        grid(pilotIdx, 1)         = pilotSymbols;      % pilot symbol
        grid(dataIdx,  2:end)     = reshape(txSymbols, Ndata, NdataSymbols);

        % CP-OFDM modulate (IFFT + add cyclic prefix)
        txSignal = ofdm_modulate(grid, Nfft, Ncp);

        %% ── CHANNEL ──────────────────────────────────────────────────

        % Generate random multipath channel (6-tap exponential PDP)
        % Each simulation block gets a NEW independent channel realisation
        h_time = (randn(1, 6) + 1j*randn(1, 6)) .* sqrt(powers_lin);
        h_freq = fft(h_time, Nsc).';   % channel in frequency domain [Nsc x 1]

        % Apply channel: each subcarrier multiplied by its channel coefficient
        % In time domain this is a convolution, in frequency domain it is
        % element-wise multiplication (this is what OFDM enables)
        txFaded = txSignal .* h_freq;  % simplified: apply channel in freq domain
        % Note: proper implementation convolves in time domain before OFDM demod
        % For the purposes of this simulator the frequency domain application
        % per subcarrier is equivalent when the CP absorbs the multipath delay

        % Add AWGN noise at specified SNR
        rxSignal = awgn_channel(txFaded, SNR_dB);

        %% ── RECEIVER ─────────────────────────────────────────────────

        % CP-OFDM demodulate (remove CP + FFT)
        rxGrid = ofdm_demodulate(rxSignal, Nfft, Ncp, Nsymbols);

        % Run all three estimators on the SAME received signal
        % This ensures fair comparison — same channel, same noise

        % Estimator 1: LS
        H_ls   = estimate_ls(rxGrid, pilotIdx, pilotSymbols);

        % Estimator 2: MMSE
        H_mmse = estimate_mmse(rxGrid, pilotIdx, pilotSymbols, R_hh, SNR_lin);

        % Estimator 3: NN (if trained model is available)
        if useNN
            H_nn = estimate_nn(rxGrid, pilotIdx, pilotSymbols, net, Nsc);
        end

        % Decode with each estimator independently
        for estIdx = 1 : (2 + useNN)

            % Select channel estimate for this estimator
            switch estIdx
                case 1,  H_est = H_ls;
                case 2,  H_est = H_mmse;
                case 3,  H_est = H_nn;
            end

            % Zero-forcing equalization (divide by channel estimate)
            rxEq  = equalize_zf(rxGrid, H_est, pilotIdx, Nsymbols);

            % Soft QAM demodulation (output LLRs)
            llrs  = demodulate(rxEq, modOrder, noiseVar);

            % LDPC decoding + CRC check
            [~, blockErr] = ldpc_decode(llrs, bgn, maxIter);

            % Update counters
            switch estIdx
                case 1
                    blk_ls = blk_ls + 1;
                    err_ls = err_ls + blockErr;
                case 2
                    blk_mm = blk_mm + 1;
                    err_mm = err_mm + blockErr;
                case 3
                    blk_nn = blk_nn + 1;
                    err_nn = err_nn + blockErr;
            end
        end
    end % while loop

    % Compute BLER for this SNR point
    BLER_ls(snrIdx)   = err_ls / blk_ls;
    BLER_mmse(snrIdx) = err_mm / blk_mm;
    if useNN
        BLER_nn(snrIdx) = err_nn / blk_nn;
    end

    fprintf('LS=%.4f  MMSE=%.4f', BLER_ls(snrIdx), BLER_mmse(snrIdx));
    if useNN
        fprintf('  NN=%.4f', BLER_nn(snrIdx));
    end
    fprintf('  (blocks: LS=%d MMSE=%d)\n', blk_ls, blk_mm);

end % SNR loop

%% =========================================================================
%% SAVE RESULTS
%% =========================================================================

save('results/bler_results.mat', 'SNR_range', 'BLER_ls', 'BLER_mmse', 'BLER_nn');
fprintf('\nSimulation complete. Results saved to results/bler_results.mat\n');
fprintf('Run results/plot_bler.m to generate the BLER curve plot.\n');
