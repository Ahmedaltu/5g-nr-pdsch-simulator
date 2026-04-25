function [decodedBits, blockError] = ldpc_decode(llrs, bgn, maxIter)
% =========================================================================
% LDPC_DECODE  5G NR LDPC channel decoding with CRC check
%
% INPUTS:
%   llrs     - soft LLR values from demodulator (real column vector)
%              positive = likely 0, negative = likely 1
%   bgn      - base graph number: 1 or 2 (must match encoder)
%   maxIter  - maximum belief propagation iterations
%              more iterations = better performance but slower
%              typical: 50 for simulation, 5-10 for real hardware
%
% OUTPUTS:
%   decodedBits - decoded information bits (binary column vector)
%                 length = original K bits before encoding
%   blockError  - 1 if CRC check failed (block error), 0 if passed
%                 this is what gets counted for BLER measurement
%
% HOW IT WORKS:
%   Belief propagation on the sparse Tanner graph:
%   1. Initialise variable nodes with input LLRs
%   2. Variable nodes send messages to connected check nodes
%   3. Check nodes enforce parity constraints, send back updated beliefs
%   4. Repeat for maxIter iterations (or until parity checks all pass)
%   5. Make hard decisions on final LLRs
%   6. Check CRC to verify if the decoded block is correct
%
% WHY SOFT INPUT MATTERS:
%   The decoder uses the MAGNITUDE of the LLR, not just its sign.
%   A bit with LLR = 0.1 (nearly uncertain) is treated very differently
%   from a bit with LLR = 5.0 (very confident).
%   During belief propagation, confident bits help correct uncertain ones.
%   This is why soft-input LDPC decoding outperforms hard-decision by ~2-3 dB.
%
% EARLY TERMINATION:
%   nrLDPCDecode automatically stops early if all parity checks pass
%   before reaching maxIter. This saves computation at high SNR where
%   the codeword is correct after just a few iterations.
% =========================================================================

    % --- Step 1: LDPC decoding via belief propagation ---
    % nrLDPCDecode runs the sum-product algorithm on the 5G NR LDPC graph
    % It takes soft LLRs and returns hard bit decisions
    %
    % Input LLR convention for nrLDPCDecode:
    %   positive LLR --> likely 0
    %   negative LLR --> likely 1
    % (this matches the output convention of qamdemod with 'llr')
    decodedCRC = nrLDPCDecode(llrs(:), bgn, maxIter);
    % decodedCRC contains decoded bits INCLUDING the CRC bits
    % Length = K + 24 (24 CRC bits appended by nrCRCEncode at TX)

    % --- Step 2: CRC check to detect remaining errors ---
    % nrCRCDecode removes the 24 CRC bits and checks if they match
    % the decoded data bits.
    %
    % If the CRC passes: the block was decoded correctly (with very high
    % probability — CRC-24A has a false positive rate of ~1 in 16 million)
    %
    % If the CRC fails: the block contains uncorrected errors.
    % This is counted as a BLOCK ERROR in the BLER measurement.
    %
    % '24A' refers to CRC-24A polynomial used for transport blocks in 5G NR
    % (defined in 3GPP TS 38.212 Section 5.1)
    [decodedBits, crcError] = nrCRCDecode(decodedCRC, '24A');
    % decodedBits: information bits only (CRC removed)
    % crcError:    0 = CRC passed (block OK), 1 = CRC failed (block error)

    % blockError is 1 if this transport block was received incorrectly
    % It is added to the block error counter in the BLER measurement loop
    blockError = double(crcError);

end
