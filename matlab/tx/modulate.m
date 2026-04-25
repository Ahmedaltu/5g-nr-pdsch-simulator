function symbols = modulate(bits, M)
% =========================================================================
% MODULATE  QAM modulation for 5G NR PDSCH
%
% INPUTS:
%   bits - column vector of bits to modulate
%          length must be a multiple of log2(M)
%   M    - modulation order
%            4  = QPSK   (2 bits per symbol)
%            16 = 16QAM  (4 bits per symbol)
%            64 = 64QAM  (6 bits per symbol)
%           256 = 256QAM (8 bits per symbol)
%
% OUTPUT:
%   symbols - complex column vector of QAM symbols
%             length = length(bits) / log2(M)
%             each symbol is a complex number (real + imaginary)
%
% HOW IT WORKS:
%   Groups of log2(M) bits are mapped to a single complex number.
%   The complex number represents a point in the constellation diagram —
%   a 2D plane where the x-axis is the real (in-phase) component and
%   the y-axis is the imaginary (quadrature) component.
%
%   Example for QPSK (M=4, 2 bits per symbol):
%     bits 00 --> symbol at (+1, +1)  i.e.  1 + 1j
%     bits 01 --> symbol at (+1, -1)  i.e.  1 - 1j
%     bits 10 --> symbol at (-1, +1)  i.e. -1 + 1j
%     bits 11 --> symbol at (-1, -1)  i.e. -1 - 1j
%
% GRAY CODING:
%   Adjacent constellation points differ by only 1 bit.
%   This means a symbol error (noise pushes to wrong point)
%   usually only causes 1 bit error, not multiple.
%   5G NR requires Gray coding — MATLAB's qammod uses it by default.
%
% UNIT AVERAGE POWER:
%   'UnitAveragePower', true normalises the constellation so the
%   average symbol energy = 1. This is standard in 5G NR and keeps
%   SNR calculations consistent regardless of modulation order.
% =========================================================================

    % Calculate bits per symbol
    % QPSK: k=2, 16QAM: k=4, 64QAM: k=6, 256QAM: k=8
    k = log2(M);

    % Validate input length is a multiple of bits per symbol
    assert(mod(length(bits), k) == 0, ...
        'Number of bits must be a multiple of log2(M)=%d', k);

    % Perform QAM modulation
    % 'InputType','bit'  -- input is raw bits, not symbol indices
    % 'UnitAveragePower' -- normalise so mean(|symbols|^2) = 1
    %                       this is required for consistent SNR
    symbols = qammod(bits, M, ...
                     'InputType',        'bit', ...
                     'UnitAveragePower', true);

    % Output is a complex vector
    % Real part = in-phase component (I)
    % Imaginary part = quadrature component (Q)
    % These map directly to the two dimensions of the RF signal
end
