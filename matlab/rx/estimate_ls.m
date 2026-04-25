function H_est = estimate_ls(rxGrid, pilotIdx, pilotSymbols)
% =========================================================================
% ESTIMATE_LS  Least Squares channel estimation for 5G NR PDSCH
%
% INPUTS:
%   rxGrid       - received resource grid [Nsc x Nsymbols] (complex)
%                  output of ofdm_demodulate.m
%   pilotIdx     - vector of subcarrier indices where pilots are placed
%                  e.g. [1, 13, 25, 37, ...] for every 12th subcarrier
%   pilotSymbols - vector of known pilot symbol values (complex)
%                  same length as pilotIdx
%                  e.g. ones(Npilots, 1) for BPSK pilots (+1)
%
% OUTPUT:
%   H_est        - estimated channel at ALL subcarriers (complex vector)
%                  length = Nsc (number of active subcarriers)
%                  interpolated between pilot positions
%
% HOW IT WORKS:
%   At each pilot subcarrier k_p:
%     received = H(k_p) * pilot + noise
%     --> H_LS(k_p) = received / pilot = H(k_p) + noise/pilot
%
%   This gives a noisy channel estimate at pilot positions only.
%   Linear interpolation fills in the channel estimate at all
%   subcarriers between pilots.
%
% LIMITATION:
%   The noise term (noise/pilot) never disappears.
%   At low SNR, noise dominates and the estimate is poor.
%   MMSE (estimate_mmse.m) and the NN (estimate_nn.m) address this.
% =========================================================================

    % --- Step 1: Extract received values at pilot subcarriers ---
    % We use only the first OFDM symbol for channel estimation
    % (symbol index 1 = the reference signal symbol in our grid)
    % In 5G NR this corresponds to the DMRS symbol position
    rxPilots = rxGrid(pilotIdx, 1);
    % rxPilots(i) = H(pilotIdx(i)) * pilotSymbols(i) + noise(i)

    % --- Step 2: LS estimate at pilot positions ---
    % Since we know the transmitted pilot symbols, we can divide:
    %   H_LS(k_p) = received(k_p) / pilot(k_p)
    %             = H(k_p) + noise(k_p) / pilot(k_p)
    %
    % This is called Least Squares because it minimises
    % the squared error |received - H * pilot|^2
    %
    % Element-wise division: each pilot divided by its known value
    H_pilots = rxPilots ./ pilotSymbols(:);
    % H_pilots contains the channel estimate at pilot positions only
    % It is the true channel + noise contamination

    % --- Step 3: Interpolate to all subcarriers ---
    % We have H_est only at pilotIdx positions (e.g. every 12th subcarrier)
    % We need H_est at ALL subcarrier positions for equalization
    %
    % interp1 performs 1D interpolation:
    %   - 'linear' = straight line between pilot estimates
    %   - 'extrap'  = extend linearly beyond edge pilots
    %
    % More sophisticated interpolation (spline, MMSE) is possible
    % but linear is sufficient for this baseline estimator
    allIdx = (1 : size(rxGrid, 1))';   % all subcarrier indices
    H_est  = interp1(pilotIdx(:), H_pilots, allIdx, 'linear', 'extrap');
    % H_est is now a vector of length Nsc
    % Contains channel estimate at every subcarrier
    % Ready to be used by equalize_zf.m

end
