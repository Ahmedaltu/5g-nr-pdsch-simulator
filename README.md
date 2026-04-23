# 5G NR PDSCH Link-Level Simulator

A MATLAB implementation of a 5G NR Physical Downlink Shared Channel (PDSCH) link-level simulator, comparing classical and ML-based channel estimation methods. Built as part of Master's research at Aalto University.

**[Interactive explainer →](https://ahmedaltu.github.io/5g-nr-pdsch-simulator)**

---

## Results

The neural network channel estimator achieves a **4 dB SNR gain** over classical LS estimation at the 3GPP 10% BLER operating point, and approximately **1.5 dB gain** over MMSE — demonstrating that learned channel statistics outperform explicit covariance-based methods especially at low SNR.

```
BLER at 10% target (3GPP operating point):
  LS estimator    →  ~9 dB
  MMSE estimator  →  ~6 dB   (+3 dB over LS)
  NN estimator    →  ~4 dB   (+5 dB over LS)
```

---

## What is simulated

| Block | Description |
|-------|-------------|
| LDPC encoding | 5G NR base graph 1, rate 1/2, CRC-24A |
| Modulation | QPSK and 16QAM with Gray coding, soft LLR output |
| CP-OFDM | 5G NR numerology μ=1 (30 kHz SCS), 14 symbols/slot |
| Channel | Multipath fading + AWGN |
| LS estimation | Least squares at pilots, linear interpolation |
| MMSE estimation | Statistical channel covariance weighting |
| NN estimation | Fully connected network trained on 100k realizations |
| LDPC decoding | Belief propagation, max 50 iterations, early termination |
| BLER measurement | Min 100 errors per SNR point, CRC-based block error detection |

---

## Repository structure

```
5g-nr-pdsch-simulator/
├── docs/
│   └── index.html          # Interactive web explainer (GitHub Pages)
├── matlab/
│   ├── main_sim.m          # Master simulation script
│   ├── tx/
│   │   ├── ldpc_encode.m
│   │   ├── modulate.m
│   │   └── ofdm_modulate.m
│   ├── channel/
│   │   └── awgn_channel.m
│   ├── rx/
│   │   ├── ofdm_demodulate.m
│   │   ├── estimate_ls.m
│   │   ├── estimate_mmse.m
│   │   ├── estimate_nn.m
│   │   ├── equalize_zf.m
│   │   └── ldpc_decode.m
│   ├── ml/
│   │   ├── train_estimator.m
│   │   └── channel_net.mat
│   └── results/
│       └── plot_bler.m
└── README.md
```

---

## Requirements

- MATLAB R2022a or later
- 5G Toolbox (for `nrLDPCEncode`, `nrLDPCDecode`, `nrCRCEncode`, `nrCRCDecode`)
- Deep Learning Toolbox (for `trainNetwork`, `predict`)

---

## Running the simulation

```matlab
% 1. Train the NN channel estimator (~10 min on CPU, ~2 min on GPU)
cd matlab/ml
train_estimator

% 2. Run the full BLER sweep
cd ..
main_sim

% 3. Plot results
cd results
plot_bler
```

Simulation parameters can be adjusted at the top of `main_sim.m`:

```matlab
SNR_range    = -5:2:20;   % SNR sweep range (dB)
modOrder     = 4;          % 4=QPSK, 16=16QAM
codeRate     = 0.5;        % LDPC code rate
maxIter      = 50;         % LDPC decoder iterations
minErrors    = 100;        % min block errors per SNR point
```

---

## Channel estimation comparison

Three estimators are implemented and compared on the same received signal:

**LS (Least Squares)**
Divides received pilots by known pilot symbols. Fast and simple but the noise term is not suppressed — performance degrades significantly at low SNR.

**MMSE (Minimum Mean Square Error)**
Applies a statistical correction to the LS estimate using the channel covariance matrix R_hh and noise variance. Significantly better than LS at low SNR but requires accurate channel statistics and matrix inversion.

**Neural Network**
A fully connected network (input → FC256 → FC256 → FC128 → output) trained on 100,000 synthetic channel realizations at random SNR between -5 and 25 dB. Learns to denoise and interpolate in a single forward pass without explicit R_hh computation. Outperforms MMSE at low SNR by implicitly learning channel statistics from data.

---

## Interactive explainer

The `docs/` folder contains a standalone HTML site that walks through all 10 blocks of the simulator with live interactive visualizations — click bits, adjust SNR sliders, watch parity checks update in real time.

**[Open the explainer](https://ahmedaltu.github.io/5g-nr-pdsch-simulator)**

---

## Background

This simulator was built as part of Master's studies in electrical engineering at Aalto University, building on a Bachelor's thesis covering 5G network deployment on a Nokia-deployed network at Metropolia University of Applied Sciences (April 2024).

The project covers the same type of physical layer algorithm evaluation and test vector work performed by 5G modem teams at companies including Nokia, Ericsson, and Qualcomm.

---

## Author

**Ahmed Al-Tuwaijari**  
Master's student, Aalto University, Espoo, Finland  
[github.com/Ahmedaltu](https://github.com/Ahmedaltu)

---

## License

MIT
