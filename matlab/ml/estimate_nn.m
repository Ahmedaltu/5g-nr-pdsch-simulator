function H_est = estimate_nn(rxGrid, pilotIdx, pilotSymbols, net, Nsc)
% =========================================================================
% ESTIMATE_NN  Neural Network channel estimation for 5G NR PDSCH
%
% INPUTS:
%   rxGrid       - received resource grid [Nsc x Nsymbols] (complex)
%   pilotIdx     - vector of pilot subcarrier indices
%   pilotSymbols - vector of known pilot symbol values (complex)
%   net          - trained neural network (loaded from channel_net.mat)
%   Nsc          - number of active subcarriers
%
% OUTPUT:
%   H_est        - NN channel estimate at ALL subcarriers (complex vector)
%                  length = Nsc
%                  cleaner than LS and MMSE especially at low SNR
%
% HOW IT WORKS:
%   Step 1: Compute LS estimate at pilot positions (same as estimate_ls.m)
%   Step 2: Format as real-valued input vector [real(H_ls); imag(H_ls)]
%   Step 3: Forward pass through the trained neural network
%   Step 4: Reconstruct complex H_est from real+imag output
%
% WHY NO INTERPOLATION STEP:
%   Unlike LS and MMSE, the NN outputs estimates at ALL subcarriers
%   directly — not just at pilot positions. The network learned to
%   interpolate AND denoise simultaneously during training.
%   This is more powerful than linear interpolation applied after LS.
%
% COMPUTATIONAL COST:
%   One forward pass through the network = ~0.1 ms on CPU per block.
%   For real-time hardware, this would be implemented as a fixed-point
%   neural network accelerator in the modem SoC.
% =========================================================================

    % --- Step 1: LS estimate at pilot positions ---
    % Extract received pilot observations from first OFDM symbol
    rxPilots = rxGrid(pilotIdx, 1);

    % LS estimate: divide received by known pilot values
    % H_ls(k_p) = rx(k_p) / pilot(k_p) = H_true(k_p) + noise(k_p)/pilot
    H_ls_pilots = rxPilots ./ pilotSymbols(:);
    % This is the SAME computation as estimate_ls.m
    % The difference is what happens NEXT:
    %   LS: interpolate linearly (dumb, no noise suppression)
    %   NN: pass through trained network (smart, learned from data)

    % --- Step 2: Format input for neural network ---
    % The network expects a REAL-valued row vector as input
    % We represent the complex H_LS by splitting into real and imaginary parts
    %
    % Input format: [Re(H_ls_p1), Re(H_ls_p2), ..., Im(H_ls_p1), Im(H_ls_p2), ...]
    % Length: 2 * Npilots
    %
    % This must exactly match the format used during training in train_estimator.m
    Npilots = length(pilotIdx);
    input   = [real(H_ls_pilots)', imag(H_ls_pilots)'];
    % input is a [1 x 2*Npilots] real row vector

    % --- Step 3: Forward pass through the neural network ---
    % predict() runs the input through all layers:
    %   input -> FC256 -> ReLU -> FC256 -> ReLU -> FC128 -> ReLU -> FC(2*Nsc)
    %
    % Each layer applies: output = ReLU(W * input + b)
    % The weights W and biases b were learned during training to minimise
    % MSE between predicted and true channel
    %
    % The network implicitly:
    %   - Suppresses noise (learned what noisy pilots look like vs true channel)
    %   - Interpolates across subcarriers (learned channel frequency structure)
    %   - Adapts to different SNR levels (trained on random SNR examples)
    output = predict(net, input);
    % output is a [1 x 2*Nsc] real row vector
    % First Nsc values = real part of channel estimate at all subcarriers
    % Last  Nsc values = imaginary part of channel estimate at all subcarriers

    % --- Step 4: Reconstruct complex channel estimate ---
    % Recombine real and imaginary parts back into a complex vector
    H_est = output(1:Nsc)' + 1j * output(Nsc+1:end)';
    % H_est is a [Nsc x 1] complex column vector
    % Each element H_est(k) is the estimated channel at subcarrier k
    % Ready for use by equalize_zf.m

end
