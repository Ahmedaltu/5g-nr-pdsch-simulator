function rxEqualized = equalize_zf(rxGrid, H_est, pilotIdx, Nsymbols)
% =========================================================================
% EQUALIZE_ZF  Zero-Forcing equalizer for 5G NR PDSCH
%
% INPUTS:
%   rxGrid     - received resource grid [Nsc x Nsymbols] (complex)
%                output of ofdm_demodulate.m
%   H_est      - channel estimate at all subcarriers (complex vector)
%                length = Nsc, output of estimate_ls/mmse/nn.m
%   pilotIdx   - pilot subcarrier indices (these are excluded from output)
%   Nsymbols   - number of data-carrying OFDM symbols
%                (total symbols minus pilot symbol = 13 in our setup)
%
% OUTPUT:
%   rxEqualized - equalized data symbols (complex column vector)
%                 channel effect removed — ready for QAM demodulation
%                 contains only DATA subcarriers (pilots excluded)
%
% HOW IT WORKS:
%   The received signal at each subcarrier is:
%     rx(k) = H(k) * tx(k) + noise(k)
%
%   Zero-Forcing equalisation divides by the channel estimate:
%     tx_est(k) = rx(k) / H_est(k)
%              = H(k)/H_est(k) * tx(k) + noise(k)/H_est(k)
%
%   If H_est = H exactly: tx_est(k) = tx(k) + noise(k)/H(k)
%   The channel effect is perfectly removed — only noise remains.
%
% LIMITATION (why it is called "zero-forcing"):
%   The equalizer forces the channel response to zero (flat).
%   When H_est(k) is small (deep fade), dividing by it AMPLIFIES noise.
%   This is called "noise enhancement" and degrades performance at low SNR.
%   More advanced equalizers (MMSE-EQ) balance channel inversion vs noise.
% =========================================================================

    % Identify data subcarrier indices
    % All subcarriers that are NOT pilots carry data
    allIdx  = 1 : size(rxGrid, 1);
    dataIdx = setdiff(allIdx, pilotIdx);  % remove pilot positions

    % Extract data symbols from all data-carrying OFDM symbols
    % Symbol 1 is the pilot symbol (used for channel estimation)
    % Symbols 2 to end carry data
    % In our 14-symbol slot: symbol 1 = pilots, symbols 2-14 = data
    rxData = rxGrid(dataIdx, 2:end);
    % rxData is [Ndata x (Nsymbols-1)] complex matrix
    % Each element = H(k) * QAM_symbol + noise

    % Apply Zero-Forcing equalization
    % Divide each data subcarrier by the channel estimate at that subcarrier
    % H_est(dataIdx) picks out the channel estimate at data positions only
    %
    % The division removes (inverts) the channel effect:
    %   rxData(k) / H_est(k) = H(k)/H_est(k) * tx(k) + noise(k)/H_est(k)
    %                        ≈ tx(k) + noise(k)/H(k)   (if H_est ≈ H)
    rxEqualized = rxData ./ H_est(dataIdx);
    % Broadcasting: H_est(dataIdx) is a column vector [Ndata x 1]
    % MATLAB divides each row of rxData by the corresponding H_est value

    % Reshape to column vector for QAM demodulator
    % The demodulator expects a 1D input
    rxEqualized = rxEqualized(:);
    % rxEqualized is now ready for qamdemod in demodulate.m

end
