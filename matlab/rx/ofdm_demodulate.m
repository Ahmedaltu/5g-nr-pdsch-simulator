function grid = ofdm_demodulate(rxSignal, Nfft, Ncp, Nsymbols)
% =========================================================================
% OFDM_DEMODULATE  CP-OFDM demodulation for 5G NR
%
% INPUTS:
%   rxSignal  - received time-domain signal (complex column vector)
%               length must be >= Nsymbols * (Nfft + Ncp)
%   Nfft      - FFT size (must match transmitter)
%   Ncp       - cyclic prefix length in samples (must match transmitter)
%   Nsymbols  - number of OFDM symbols to demodulate (e.g. 14 per slot)
%
% OUTPUT:
%   grid      - resource grid matrix [Nfft x Nsymbols] (complex)
%               rows = subcarriers (frequency dimension)
%               cols = OFDM symbols (time dimension)
%               contains received QAM symbols + pilot observations
%               (corrupted by channel and noise — not yet equalized)
%
% HOW IT WORKS:
%   This is the exact reverse of ofdm_modulate.m:
%     TX: QAM symbols --> IFFT --> add CP --> transmit
%     RX: receive     --> remove CP --> FFT --> QAM symbols (noisy)
%
%   For each OFDM symbol:
%     1. Skip the cyclic prefix samples (discard first Ncp samples)
%     2. Take Nfft samples (the actual OFDM symbol)
%     3. Apply FFT to convert time domain back to frequency domain
%     4. Apply fftshift to put DC subcarrier back at centre
%     5. Store result as one column of the resource grid
%
% IMPORTANT:
%   The output grid contains RECEIVED symbols — they have been
%   distorted by the channel (multiplied by h) and corrupted by noise.
%   Channel estimation and equalization happen AFTER this function.
% =========================================================================

    % Initialise output resource grid
    % Rows = Nfft subcarriers, Cols = Nsymbols time slots
    grid = zeros(Nfft, Nsymbols);

    % Sample pointer — tracks our position in the received signal
    % Starts at 1 (first sample of the received signal)
    sampleIdx = 1;

    % Process each OFDM symbol one by one
    for sym = 1:Nsymbols

        % --- Step 1: Skip the cyclic prefix ---
        % The first Ncp samples of each symbol are the CP
        % They contain multipath interference and must be discarded
        % Simply advance the pointer past them
        sampleIdx = sampleIdx + Ncp;

        % --- Step 2: Extract the Nfft useful samples ---
        % After the CP, the next Nfft samples are the clean OFDM symbol
        % (clean in the sense that ISI has been eliminated by the CP)
        ofdmBlock = rxSignal(sampleIdx : sampleIdx + Nfft - 1);

        % --- Step 3: FFT to convert to frequency domain ---
        % FFT reverses the IFFT applied at the transmitter
        % Divide by sqrt(Nfft) to reverse the TX normalisation
        % This keeps signal power consistent end-to-end
        freqDomain = fft(ofdmBlock) / sqrt(Nfft);

        % --- Step 4: fftshift to restore subcarrier ordering ---
        % The TX applied ifftshift before the IFFT
        % fftshift here reverses that — puts DC back at centre
        % Without this, subcarrier indices would be scrambled
        grid(:, sym) = fftshift(freqDomain);

        % --- Step 5: Advance pointer to next symbol ---
        % Move past the Nfft samples we just processed
        sampleIdx = sampleIdx + Nfft;

    end

    % grid now contains the received frequency-domain resource grid
    % Each column is one OFDM symbol, each row is one subcarrier
    % Values are complex numbers = h * tx_symbol + noise
    % Next step: channel estimation using pilot subcarriers
end
