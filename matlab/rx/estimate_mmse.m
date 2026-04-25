function H_est = estimate_mmse(rxGrid, pilotIdx, pilotSymbols, R_hh, SNR_linear)
% =========================================================================
% ESTIMATE_MMSE  MMSE channel estimation for 5G NR PDSCH
%
% INPUTS:
%   rxGrid       - received resource grid [Nsc x Nsymbols] (complex)
%   pilotIdx     - vector of pilot subcarrier indices
%   pilotSymbols - vector of known pilot symbol values (complex)
%   R_hh         - channel covariance matrix [Nsc x Nsc] (complex)
%                  describes how correlated the channel is across subcarriers
%                  computed from the channel power delay profile
%   SNR_linear   - signal-to-noise ratio in linear scale (not dB)
%                  e.g. SNR_linear = 10 for 10 dB SNR
%
% OUTPUT:
%   H_est        - MMSE channel estimate at ALL subcarriers (complex vector)
%                  length = Nsc
%                  lower noise than LS estimate, especially at low SNR
%
% HOW IT WORKS:
%   Step 1: Get LS estimate at pilots (same as estimate_ls.m)
%   Step 2: Apply MMSE correction using channel statistics and noise power
%   Step 3: Interpolate to all subcarriers
%
%   The MMSE correction is a weighted average between:
%     - The noisy LS measurement (trust the measurement)
%     - The channel statistics from R_hh (trust what channels look like)
%   The weight is determined by the SNR — low SNR means trust stats more.
%
% FORMULA:
%   H_MMSE = R_pp * (R_pp + sigma^2 * I)^-1 * H_LS
%
%   Where:
%     R_pp   = channel covariance at pilot positions (submatrix of R_hh)
%     sigma^2 = noise variance = 1 / SNR_linear
%     I      = identity matrix
%     H_LS   = LS estimate at pilots
% =========================================================================

    % --- Step 1: LS estimate at pilot positions ---
    % Extract received pilots from first OFDM symbol
    rxPilots = rxGrid(pilotIdx, 1);

    % LS estimate: divide received by known pilot values
    % H_ls(i) = H_true(i) + noise(i)/pilot(i)
    H_ls = rxPilots ./ pilotSymbols(:);

    % --- Step 2: Extract pilot submatrix of covariance matrix ---
    % R_hh is Nsc x Nsc but we only need the rows/cols at pilot positions
    % R_pp is the channel covariance BETWEEN pilot subcarriers
    % It captures how similar the channel is at nearby pilot frequencies
    R_pp = R_hh(pilotIdx, pilotIdx);

    % --- Step 3: Compute noise variance ---
    % For unit-power signal: sigma^2 = 1 / SNR_linear
    sigma2 = 1 / SNR_linear;

    % --- Step 4: MMSE weight matrix ---
    % W = R_pp * (R_pp + sigma^2 * I)^-1
    %
    % This matrix balances trust between:
    %   - The LS measurement (distorted by noise)
    %   - The channel statistics (what we expect H to look like)
    %
    % At high SNR (sigma2 -> 0): W -> I  (trust measurement fully)
    % At low SNR (sigma2 -> inf): W -> 0 (trust statistics, ignore noise)
    %
    % The matrix inverse (R_pp + sigma2*I) \ R_pp is the key operation
    % We use the \ operator (left division) which is numerically more
    % stable than computing the inverse explicitly with inv()
    Np = length(pilotIdx);
    W  = R_pp / (R_pp + sigma2 * eye(Np));
    % Note: A/B = A * inv(B) in MATLAB — right division

    % --- Step 5: Apply MMSE correction ---
    % Multiply the LS estimate by the weight matrix
    % This suppresses the noise component in H_ls
    H_mmse_pilots = W * H_ls;

    % --- Step 6: Interpolate to all subcarriers ---
    % Same as LS: linear interpolation between pilot estimates
    % MMSE pilot estimates are cleaner than LS, so interpolation
    % result is also more accurate
    allIdx = (1 : size(rxGrid, 1))';
    H_est  = interp1(pilotIdx(:), H_mmse_pilots, allIdx, 'linear', 'extrap');

end
