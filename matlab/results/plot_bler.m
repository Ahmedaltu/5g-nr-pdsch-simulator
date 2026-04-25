% =========================================================================
% PLOT_BLER.M  Generate BLER vs SNR comparison plot
%
% Loads simulation results from bler_results.mat and produces
% a publication-quality three-curve comparison plot.
%
% Run AFTER main_sim.m has completed.
% =========================================================================

clear; clc;

% Load results saved by main_sim.m
load('bler_results.mat', 'SNR_range', 'BLER_ls', 'BLER_mmse', 'BLER_nn');

%% ── Plot ────────────────────────────────────────────────────────────────

figure('Position', [100 100 800 560]);

% Plot three BLER curves on logarithmic y-axis
% semilogy uses log scale on y-axis — essential for BLER which spans
% several orders of magnitude (1.0 down to 0.001)
semilogy(SNR_range, BLER_ls,   'r-o', 'LineWidth', 2, 'MarkerSize', 7, ...
         'DisplayName', 'LS Estimation');
hold on;

semilogy(SNR_range, BLER_mmse, 'b-s', 'LineWidth', 2, 'MarkerSize', 7, ...
         'DisplayName', 'MMSE Estimation');

semilogy(SNR_range, BLER_nn,   'g-^', 'LineWidth', 2, 'MarkerSize', 7, ...
         'DisplayName', 'NN Estimation');

% 3GPP standard operating point reference line
% 10% BLER (0.1) is the target initial transmission error rate
% HARQ retransmissions handle the rest
yline(0.1, 'k--', 'LineWidth', 1.2, 'DisplayName', '10% BLER target (3GPP)');

%% ── Formatting ──────────────────────────────────────────────────────────

grid on;
xlabel('SNR (dB)',  'FontSize', 14, 'FontWeight', 'bold');
ylabel('BLER',      'FontSize', 14, 'FontWeight', 'bold');
title('5G NR PDSCH — Channel Estimation Comparison', ...
      'FontSize', 14, 'FontWeight', 'bold');
legend('Location', 'southwest', 'FontSize', 12);
xlim([SNR_range(1) SNR_range(end)]);
ylim([1e-3 1]);
ax = gca;
ax.FontSize   = 12;
ax.GridAlpha  = 0.3;
ax.GridColor  = [0.5 0.5 0.5];

%% ── SNR gain at 10% BLER ─────────────────────────────────────────────────

% Find the SNR where each curve crosses 10% BLER
% interp1 with reversed BLER (decreasing) finds the crossover point
snr_ls   = interp1(flip(BLER_ls),   flip(SNR_range), 0.1, 'linear', 'extrap');
snr_mmse = interp1(flip(BLER_mmse), flip(SNR_range), 0.1, 'linear', 'extrap');
snr_nn   = interp1(flip(BLER_nn),   flip(SNR_range), 0.1, 'linear', 'extrap');

fprintf('\n=== Results at 10%% BLER (3GPP operating point) ===\n');
fprintf('LS   estimator:  %.1f dB\n', snr_ls);
fprintf('MMSE estimator:  %.1f dB  (+%.1f dB gain over LS)\n', ...
        snr_mmse, snr_ls - snr_mmse);
fprintf('NN   estimator:  %.1f dB  (+%.1f dB gain over LS)\n', ...
        snr_nn, snr_ls - snr_nn);
fprintf('NN gain over MMSE:        +%.1f dB\n', snr_mmse - snr_nn);

%% ── Save figure ────────────────────────────────────────────────────────

saveas(gcf, 'bler_comparison.png');
fprintf('\nPlot saved to results/bler_comparison.png\n');
