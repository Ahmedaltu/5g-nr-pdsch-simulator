function rxSignal = awgn_channel(txSignal, SNR_dB)
% =========================================================================
% AWGN_CHANNEL  Additive White Gaussian Noise channel model
%
% INPUTS:
%   txSignal - complex transmitted signal (column vector)
%              assumed to have normalised power before calling this function
%   SNR_dB   - signal-to-noise ratio in decibels (dB)
%              e.g. SNR_dB = 10 means signal power is 10x noise power
%
% OUTPUT:
%   rxSignal - received signal = txSignal + noise (complex column vector)
%              same length as txSignal
%
% WHAT AWGN MODELS:
%   AWGN stands for Additive White Gaussian Noise.
%   It models THERMAL NOISE — the random motion of electrons in the
%   receiver hardware. This noise is:
%     - ADDITIVE:  added to the signal, not multiplied
%     - WHITE:     equal power at all frequencies (flat spectrum)
%     - GAUSSIAN:  amplitude follows a normal distribution
%
%   This is the simplest and most fundamental channel model.
%   Real 5G channels also have multipath fading, Doppler shifts, etc.,
%   but AWGN is our baseline for validating the TX/RX chain.
%
% SNR AND NOISE VARIANCE:
%   SNR_linear = 10^(SNR_dB / 10)
%
%   For a complex signal with unit average power:
%     noise variance per complex sample = 1 / SNR_linear
%
%   Since complex noise has real and imaginary components:
%     sigma^2 per dimension = 1 / (2 * SNR_linear)
%
%   So each noise sample = sqrt(sigma^2) * (randn + j*randn)
%                        = sqrt(1/(2*SNR)) * (randn + j*randn)
% =========================================================================

    % --- Step 1: Normalise transmitted signal power to 1 ---
    % This ensures our SNR formula is correct:
    % if tx power != 1, the actual SNR will differ from SNR_dB
    txPower  = mean(abs(txSignal).^2);   % compute average power
    txSignal = txSignal / sqrt(txPower); % normalise to unit power

    % --- Step 2: Convert SNR from dB to linear scale ---
    % dB is a logarithmic scale: SNR_dB = 10 * log10(SNR_linear)
    % So: SNR_linear = 10^(SNR_dB / 10)
    %
    % Example:
    %   SNR_dB = 0  dB  --> SNR_linear = 1    (signal = noise power)
    %   SNR_dB = 10 dB  --> SNR_linear = 10   (signal 10x noise)
    %   SNR_dB = 20 dB  --> SNR_linear = 100  (signal 100x noise)
    SNR_linear = 10^(SNR_dB / 10);

    % --- Step 3: Compute noise variance ---
    % For unit-power signal with complex noise:
    %   sigma^2 = 1 / (2 * SNR_linear)
    % Factor of 2 because noise power splits equally between
    % real and imaginary components
    sigma2 = 1 / (2 * SNR_linear);

    % --- Step 4: Generate complex Gaussian noise ---
    % randn() generates real Gaussian samples ~ N(0,1)
    % We need noise ~ CN(0, sigma^2) — complex circular Gaussian
    % Scale each component by sqrt(sigma2) to get correct variance
    noise = sqrt(sigma2) * (randn(size(txSignal)) + ...
                            1j * randn(size(txSignal)));
    % Real component: sqrt(sigma2) * randn ~ N(0, sigma2)
    % Imag component: sqrt(sigma2) * randn ~ N(0, sigma2)
    % Total noise power: sigma2 + sigma2 = 2*sigma2 = 1/SNR_linear ✓

    % --- Step 5: Add noise to signal ---
    % rx = tx + noise   (the "additive" in AWGN)
    rxSignal = txSignal + noise;

    % At this point:
    %   Signal power: 1 (normalised)
    %   Noise power:  1/SNR_linear
    %   Actual SNR:   SNR_linear = 10^(SNR_dB/10) ✓
end
