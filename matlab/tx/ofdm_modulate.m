function txSignal = ofdm_modulate(grid, Nfft, Ncp)
% =========================================================================
% OFDM_MODULATE  CP-OFDM modulation for 5G NR
%
% INPUTS:
%   grid  - resource grid matrix [Nsc x Nsymbols] (complex)
%           rows = subcarriers (frequency dimension)
%           cols = OFDM symbols (time dimension)
%           contains QAM symbols at data positions and
%           known pilot symbols at pilot positions
%   Nfft  - FFT size (e.g. 512 for 30 kHz SCS, 25 RBs)
%   Ncp   - cyclic prefix length in samples
%           (e.g. 36 samples for normal CP, mu=1)
%
% OUTPUT:
%   txSignal - time-domain transmitted signal (complex column vector)
%              length = Nsymbols * (Nfft + Ncp)
%
% HOW IT WORKS:
%   For each OFDM symbol (column of the grid):
%     1. Place QAM symbols onto subcarrier positions in frequency domain
%     2. Take the IFFT to convert to time domain
%     3. Copy the last Ncp samples and prepend them (cyclic prefix)
%     4. Concatenate with the signal from previous symbols
%
%   The result is a time-domain waveform ready for transmission.
%   At the receiver, OFDM demodulation reverses this process:
%   strip CP, take FFT, read off QAM symbols.
%
% WHY OFDM:
%   Wireless channels cause multipath — signal reflections arrive at
%   different times, causing some frequencies to be boosted and others
%   cancelled (frequency selective fading). A single high-speed carrier
%   gets corrupted across its whole bandwidth by this effect.
%
%   OFDM splits the wideband signal into many NARROW subcarriers.
%   Each subcarrier is so narrow that it sees a FLAT channel — no
%   frequency selectivity — making the problem trivial to correct.
%
% WHY THE CYCLIC PREFIX:
%   Multipath means copies of the signal arrive slightly late.
%   Without the CP, a late copy of symbol N overlaps with symbol N+1
%   (intersymbol interference, ISI). The CP acts as a guard interval:
%   as long as the maximum multipath delay < CP duration, ISI is zero.
%   The receiver discards the CP samples before the FFT.
% =========================================================================

    % Initialise output as empty — we will concatenate symbols
    txSignal = [];

    % Process each OFDM symbol (each column of the resource grid)
    for sym = 1:size(grid, 2)

        % --- Step 1: Build frequency-domain vector ---
        % Create zero-padded vector of length Nfft
        % The subcarriers occupy the first Nsc positions
        % The remaining positions are zero (guard bands)
        freqDomain = zeros(Nfft, 1);
        freqDomain(1:size(grid, 1)) = grid(:, sym);

        % --- Step 2: IFFT shift + IFFT ---
        % ifftshift rearranges the subcarriers so DC is at the centre
        % of the FFT — this is the standard OFDM convention.
        % The IFFT converts frequency-domain symbols to time domain.
        % Multiply by sqrt(Nfft) to normalise signal power.
        timeDomain = ifft(ifftshift(freqDomain)) * sqrt(Nfft);

        % --- Step 3: Add cyclic prefix ---
        % Copy the LAST Ncp samples of the OFDM symbol
        % and paste them at the BEGINNING
        %
        % Without CP:  [ A B C D E F G H ]
        % With CP:     [ F G H | A B C D E F G H ]
        %               ^CP^^^   ^actual symbol^^^
        %
        % The CP length must exceed the maximum multipath delay spread.
        % For 5G NR mu=1 (30kHz): Ncp ≈ 36 samples at 15.36 MHz sampling
        cyclicPrefix = timeDomain(end - Ncp + 1 : end);

        % --- Step 4: Concatenate CP + symbol and append to output ---
        txSignal = [txSignal; cyclicPrefix; timeDomain];
        %           ^existing  ^CP prefix   ^new symbol
    end

    % txSignal is now a time-domain waveform
    % Its length = Nsymbols * (Nfft + Ncp)
    % In 5G NR: 14 symbols * (512 + 36) = 7672 samples per slot
end
