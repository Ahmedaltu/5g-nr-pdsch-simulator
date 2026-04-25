function codeword = ldpc_encode(bits, bgn, rate)
% =========================================================================
% LDPC_ENCODE  5G NR LDPC channel encoding
%
% INPUTS:
%   bits  - column vector of information bits (after CRC attachment)
%   bgn   - base graph number: 1 or 2
%             BG1 = for large transport blocks and high code rates (>= 1/3)
%             BG2 = for small transport blocks and low code rates (<= 2/3)
%   rate  - code rate (e.g. 0.5 for rate 1/2)
%             rate = k/n where k=info bits, n=codeword length
%
% OUTPUT:
%   codeword - encoded bit vector (length > input, includes parity bits)
%
% HOW IT WORKS:
%   LDPC encoding uses a sparse parity check matrix H.
%   The encoder finds a codeword c such that H * c = 0 (mod 2).
%   This codeword contains your original data bits plus parity bits.
%   The parity bits are the "redundancy" that lets the receiver
%   detect and correct errors introduced by the channel.
%
% WHY LDPC:
%   5G NR chose LDPC over turbo codes (used in LTE) because LDPC
%   decoding parallelises efficiently in hardware. Qualcomm implements
%   thousands of check node processors running simultaneously, enabling
%   multi-Gbps throughput that turbo codes cannot achieve.
%
% MATLAB TOOLBOX:
%   nrLDPCEncode is from the MATLAB 5G Toolbox (Communications Toolbox
%   required). It implements the 3GPP TS 38.212 LDPC specification.
% =========================================================================

    % Validate base graph number
    % BG1 handles large blocks (up to 8448 bits) at rates 1/3 to 8/9
    % BG2 handles small blocks (up to 3840 bits) at rates 1/5 to 2/3
    assert(bgn == 1 || bgn == 2, 'Base graph must be 1 or 2');

    % Validate code rate range
    assert(rate > 0 && rate < 1, 'Code rate must be between 0 and 1');

    % Perform LDPC encoding using MATLAB 5G Toolbox
    % nrLDPCEncode automatically selects the correct lifting size
    % based on the input block length and base graph
    codeword = nrLDPCEncode(bits, bgn, rate);

    % The output codeword length = input length / rate
    % Example: 1024 input bits, rate 0.5 -> 2048 output bits
    %          1024 data bits + 1024 parity bits = 2048 total
end
