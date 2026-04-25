% =========================================================================
% TRAIN_ESTIMATOR.M  Neural Network Channel Estimator — Training
%
% Generates synthetic training data by simulating the channel and
% trains a fully connected neural network to estimate the channel
% from noisy pilot observations.
%
% RUN THIS ONCE before running main_sim.m
% Output: ml/channel_net.mat  (saved trained network)
%
% TRAINING TIME (approximate):
%   CPU only:  20-40 minutes
%   GPU:        2-5  minutes  (set 'ExecutionEnvironment','gpu' below)
%
% WHAT THE NETWORK LEARNS:
%   Input:  noisy LS channel estimate at pilot positions
%           [real(H_ls_pilots); imag(H_ls_pilots)]  -- 2*Npilots values
%   Output: clean channel estimate at ALL subcarriers
%           [real(H_true_all); imag(H_true_all)]    -- 2*Nsc values
%
%   The network learns to:
%     1. Denoise the LS estimate (suppress noise at pilot positions)
%     2. Interpolate to non-pilot subcarriers (better than linear interp)
%     3. Do both simultaneously in one forward pass
% =========================================================================

clear; clc;
addpath('../tx', '../channel', '../rx');

fprintf('=== Neural Network Channel Estimator Training ===\n\n');

%% =========================================================================
%% PARAMETERS (must match main_sim.m)
%% =========================================================================

Nsc          = 300;          % number of active subcarriers
pilotSpacing = 12;           % pilot every 12 subcarriers
pilotIdx     = (1:pilotSpacing:Nsc)';
Npilots      = length(pilotIdx);   % number of pilot subcarriers

% Training SNR range — train across the FULL operating range
% The network must handle all SNR levels, not just one
SNR_min_dB   = -5;           % minimum SNR during training (dB)
SNR_max_dB   = 25;           % maximum SNR during training (dB)

% Training dataset size
Ntrain       = 100000;       % number of training examples
Nval         = 5000;         % number of validation examples (held out)

% Channel model: 6-tap exponential power delay profile
% Same as used in main_sim.m for fair comparison
powers_dB    = [0, -3, -6, -9, -12, -15];
powers_lin   = 10.^(powers_dB / 10);
powers_lin   = powers_lin / sum(powers_lin);  % normalise

%% =========================================================================
%% GENERATE TRAINING DATA
%% =========================================================================
% For each training example we:
%   1. Draw a random SNR from the training range
%   2. Generate a random channel realisation (new channel every example)
%   3. Compute the noisy LS estimate at pilot positions --> INPUT
%   4. Store the true channel at all subcarriers --> LABEL (target output)
%
% This process simulates what the receiver experiences during operation.
% The network sees 100,000 different channels at 100,000 different SNRs.

fprintf('Generating %d training examples...\n', Ntrain + Nval);

% Preallocate data matrices
% Inputs:  [Ntotal x 2*Npilots]  -- real and imag of H_LS at pilots
% Outputs: [Ntotal x 2*Nsc]      -- real and imag of H_true at all SCs
Ntotal  = Ntrain + Nval;
X_all   = zeros(Ntotal, 2 * Npilots);   % inputs
Y_all   = zeros(Ntotal, 2 * Nsc);       % labels (targets)

for i = 1:Ntotal

    % --- Draw random SNR for this example ---
    % Uniform random between SNR_min and SNR_max
    % This ensures the network learns to handle all operating conditions
    SNR_dB  = SNR_min_dB + rand() * (SNR_max_dB - SNR_min_dB);
    SNR_lin = 10^(SNR_dB / 10);
    sigma2  = 1 / (2 * SNR_lin);   % noise variance per complex dimension

    % --- Generate random channel realisation ---
    % Each tap is an independent complex Gaussian random variable
    % Scaled by sqrt(power) to match the power delay profile
    % This is the standard Rayleigh fading channel model
    h_time = (randn(1, 6) + 1j * randn(1, 6)) .* sqrt(powers_lin);

    % Convert to frequency domain via FFT
    % h_freq(k) = sum_l h_time(l) * exp(-j2pi*k*l/Nsc)
    % Each subcarrier sees a different channel coefficient
    h_freq = fft(h_time, Nsc).';   % [Nsc x 1] complex vector

    % --- Simulate noisy pilot observations (LS estimate) ---
    % At each pilot position, the receiver observes:
    %   rx_pilot(k_p) = h_freq(k_p) * pilot + noise
    % Since pilot = 1 (BPSK), this simplifies to:
    %   rx_pilot(k_p) = h_freq(k_p) + noise
    % The LS estimate is then: H_LS(k_p) = rx_pilot(k_p) / pilot = rx_pilot(k_p)
    noise_pilots = sqrt(sigma2) * (randn(Npilots, 1) + 1j * randn(Npilots, 1));
    H_ls_pilots  = h_freq(pilotIdx) + noise_pilots;
    % H_ls_pilots = true channel at pilots + noise contamination
    % This is exactly what estimate_ls.m computes from real received signals

    % --- Store input: split complex into real and imaginary ---
    % Neural networks work with real numbers only
    % We represent the complex H_LS as two real vectors concatenated
    X_all(i, :) = [real(H_ls_pilots)', imag(H_ls_pilots)'];
    %              ^---- Npilots ----^  ^---- Npilots ----^
    %              total: 2*Npilots values per input

    % --- Store label: true channel at ALL subcarriers ---
    % This is what the network should output — the clean, full channel
    Y_all(i, :) = [real(h_freq)', imag(h_freq)'];
    %              ^--- Nsc ----^  ^--- Nsc ----^
    %              total: 2*Nsc values per output

    % Progress indicator every 10000 examples
    if mod(i, 10000) == 0
        fprintf('  Generated %d / %d examples\n', i, Ntotal);
    end
end

% Split into training and validation sets
% Training set: network learns from these
% Validation set: held out during training to monitor overfitting
X_train = X_all(1:Ntrain, :);
Y_train = Y_all(1:Ntrain, :);
X_val   = X_all(Ntrain+1:end, :);
Y_val   = Y_all(Ntrain+1:end, :);

fprintf('Data generation complete.\n');
fprintf('Training set:   %d examples\n', Ntrain);
fprintf('Validation set: %d examples\n\n', Nval);

%% =========================================================================
%% DEFINE NETWORK ARCHITECTURE
%% =========================================================================
% Fully connected (dense) network:
%   Input layer:   2*Npilots neurons  (noisy LS estimate, real+imag)
%   Hidden layer 1: 256 neurons, ReLU activation
%   Hidden layer 2: 256 neurons, ReLU activation
%   Hidden layer 3: 128 neurons, ReLU activation
%   Output layer:  2*Nsc neurons, NO activation (regression output)
%
% WHY RELU:
%   ReLU(x) = max(0, x) -- simple, fast, avoids vanishing gradients.
%   Used in all hidden layers. The output layer has NO activation
%   because this is a regression problem (predict real values, not classes).
%
% WHY THIS SIZE:
%   256 neurons in hidden layers is enough capacity to learn the
%   channel denoising and interpolation mapping.
%   Too few neurons = underfitting (can't learn the pattern).
%   Too many neurons = overfitting (memorises training data, fails on new).

layers = [
    % Input layer — accepts our 2*Npilots dimensional input
    featureInputLayer(2 * Npilots, 'Name', 'input')

    % Hidden layer 1: 256 neurons
    % Each neuron computes: output = ReLU(W * input + b)
    % W and b are learned during training via backpropagation
    fullyConnectedLayer(256, 'Name', 'fc1')
    reluLayer('Name', 'relu1')

    % Hidden layer 2: 256 neurons
    % Deeper layers learn more abstract representations of the channel
    fullyConnectedLayer(256, 'Name', 'fc2')
    reluLayer('Name', 'relu2')

    % Hidden layer 3: 128 neurons
    % Bottleneck layer — compresses to essential channel features
    fullyConnectedLayer(128, 'Name', 'fc3')
    reluLayer('Name', 'relu3')

    % Output layer: 2*Nsc neurons, NO activation function
    % Raw linear output for regression (predict continuous values)
    % Output = estimated channel at all subcarriers (real + imag)
    fullyConnectedLayer(2 * Nsc, 'Name', 'output')

    % Regression output layer — uses MSE loss function:
    % Loss = mean( |H_true - H_predicted|^2 )
    regressionLayer('Name', 'regression')
];

%% =========================================================================
%% TRAINING OPTIONS
%% =========================================================================

options = trainingOptions('adam', ...
    ...
    % Adam optimizer: adaptive learning rate per parameter
    % More stable and faster than standard SGD
    ...
    'MaxEpochs',          50, ...
    % One epoch = one full pass through the training data
    % 50 epochs is usually enough to converge
    ...
    'MiniBatchSize',      512, ...
    % Process 512 examples at a time before updating weights
    % Larger batch = more stable gradients but more memory
    ...
    'InitialLearnRate',   1e-3, ...
    % Starting learning rate for Adam optimizer
    % 0.001 is the standard starting point for Adam
    ...
    'LearnRateSchedule',  'piecewise', ...
    'LearnRateDropFactor', 0.5, ...
    'LearnRateDropPeriod', 15, ...
    % Drop learning rate by 50% every 15 epochs
    % Fine-tunes the network as it gets closer to convergence
    % Epoch 1-15:  lr = 0.001
    % Epoch 16-30: lr = 0.0005
    % Epoch 31-45: lr = 0.00025
    % Epoch 46-50: lr = 0.000125
    ...
    'ValidationData',     {X_val, Y_val}, ...
    'ValidationFrequency', 100, ...
    % Evaluate on held-out validation set every 100 iterations
    % Used to detect overfitting: if val loss increases while train loss
    % decreases, the network is memorising instead of generalising
    ...
    'Plots',              'training-progress', ...
    % Show live training plot in MATLAB (loss vs iteration)
    % Watch for: training loss and validation loss both decreasing
    % Warning sign: training loss decreasing but validation loss increasing
    ...
    'Verbose',             true, ...
    'VerboseFrequency',    100, ...
    % Print progress every 100 iterations
    ...
    'ExecutionEnvironment', 'auto');
    % 'auto' = use GPU if available, otherwise CPU
    % Change to 'gpu' to force GPU (must have Parallel Computing Toolbox)
    % Change to 'cpu' to force CPU

%% =========================================================================
%% TRAIN THE NETWORK
%% =========================================================================

fprintf('Starting network training...\n');
fprintf('Architecture: %d --> 256 --> 256 --> 128 --> %d\n', ...
        2*Npilots, 2*Nsc);
fprintf('Training examples: %d  |  Epochs: 50  |  Batch size: 512\n\n');

tic;
net = trainNetwork(X_train, Y_train, layers, options);
trainTime = toc;

fprintf('\nTraining complete in %.1f minutes.\n', trainTime/60);

%% =========================================================================
%% EVALUATE TRAINING QUALITY
%% =========================================================================

% Predict on validation set
Y_pred = predict(net, X_val);

% Compute MSE on validation set (should be low if training succeeded)
mse_val = mean((Y_val(:) - Y_pred(:)).^2);
fprintf('Validation MSE: %.6f\n', mse_val);
fprintf('(Lower is better — typical good value: < 0.01)\n\n');

% Compare NN vs LS on validation set
% LS estimate just interpolates the noisy input — we can compute it here
Y_ls_interp = zeros(Nval, 2*Nsc);
allIdx = (1:Nsc)';
for i = 1:Nval
    H_ls_r = X_val(i, 1:Npilots)';
    H_ls_i = X_val(i, Npilots+1:end)';
    H_ls   = H_ls_r + 1j * H_ls_i;
    H_int  = interp1(pilotIdx, H_ls, allIdx, 'linear', 'extrap');
    Y_ls_interp(i,:) = [real(H_int)', imag(H_int)'];
end
mse_ls = mean((Y_val(:) - Y_ls_interp(:)).^2);

fprintf('LS  interpolation MSE: %.6f\n', mse_ls);
fprintf('NN  estimation    MSE: %.6f\n', mse_val);
fprintf('NN improvement:        %.1fx lower MSE than LS\n\n', mse_ls/mse_val);

%% =========================================================================
%% SAVE TRAINED NETWORK
%% =========================================================================

save('channel_net.mat', 'net', 'Npilots', 'Nsc', 'pilotIdx');
fprintf('Trained network saved to ml/channel_net.mat\n');
fprintf('Now run matlab/main_sim.m to evaluate BLER performance.\n');
