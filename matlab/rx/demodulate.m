function llrs = demodulate(rxSymbols, M, noiseVar)
% =========================================================================
% DEMODULATE  Soft QAM demodulation for 5G NR PDSCH
%
% INPUTS:
%   rxSymbols - equalized received symbols (complex column vector)
%               output of equalize_zf.m
%   M         - modulation order: 4=QPSK, 16=16QAM, 64=64QAM
%   noiseVar  - noise variance after equalization
%               = sigma^2 = 1 / SNR_linear
%               used to compute accurate LLR values
%
% OUTPUT:
%   llrs      - Log-Likelihood Ratios for each bit (real column vector)
%               length = length(rxSymbols) * log2(M)
%               positive LLR --> bit is likely 0
%               negative LLR --> bit is likely 1
%               magnitude --> confidence of decision
%
% WHY SOFT OUTPUT (LLRs) INSTEAD OF HARD BITS:
%   We could just round each received symbol to the nearest constellation
%   point and output hard 0/1 bits. But this throws away information.
%
%   An LLR carries TWO pieces of information:
%     1. What the bit probably is (sign)
%     2. How confident we are (magnitude)
%
%   The LDPC decoder uses confidence information to correct errors much
%   more effectively. A certain 0 and an uncertain 0 are treated differently.
%   This is called SOFT-DECISION decoding and gives ~2-3 dB performance gain
%   over hard-decision decoding.
%
% LLR DEFINITION:
%   LLR(b) = log( P(b=0 | rx) / P(b=1 | rx) )
%
%   LLR > 0: bit 0 is more likely  (how much more: the magnitude)
%   LLR < 0: bit 1 is more likely
%   LLR = 0: both equally likely (maximum uncertainty)
% =========================================================================

    % Validate modulation order
    assert(ismember(M, [4, 16, 64, 256]), ...
        'Modulation order must be 4, 16, 64, or 256');

    % Compute soft LLR values using MATLAB's built-in QAM demodulator
    %
    % 'OutputType', 'llr'    -- output LLRs instead of hard bit decisions
    % 'UnitAveragePower', true -- must match the modulate.m setting
    %                            so the constellation points align correctly
    % 'NoiseVariance', noiseVar -- tells the demodulator how noisy the
    %                              channel is, used to scale the LLRs
    %                              correctly for the LDPC decoder
    llrs = qamdemod(rxSymbols, M, ...
                    'OutputType',        'llr', ...
                    'UnitAveragePower',  true, ...
                    'NoiseVariance',     noiseVar);

    % llrs is a real-valued column vector
    % Length = length(rxSymbols) * log2(M)
    % Example: 1000 QPSK symbols --> 2000 LLR values (2 bits per symbol)

    % Ensure column vector output for consistency with LDPC decoder input
    llrs = llrs(:);

end
