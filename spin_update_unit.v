// -----------------------------------------------------------------------
// spin_update_unit.v  (parametrized via NUM_OTHERS; currently used at N=30)
//
// Same role as the 5x5/15x15 versions -- one instance per spin, computes
// local field, delta-E, and the Metropolis accept decision. Structurally
// unchanged from the 15x15 version (the generate-loop local-field sum
// already scales via the NUM_OTHERS parameter) -- only register widths
// grew, since more neighbors means larger worst-case magnitudes even
// though the Q value range itself (still -32..31) hasn't changed.
// Requires -g2012 for the array ports.
// -----------------------------------------------------------------------
module spin_update_unit #(
    parameter [7:0] LFSR_SEED = 8'hA5,
    parameter integer NUM_OTHERS = 14
) (
    input  wire               clk,
    input  wire               rst_n,

    input  wire signed [11:0] h_i,                    // scaled linear field (h'), wider than 5x5's 9 bits
    input  wire signed [5:0]  j [0:NUM_OTHERS-1],      // couplings to the 14 other spins (array port)
    input  wire                s_i,                    // this spin: 1 = +1, 0 = -1
    input  wire                s [0:NUM_OTHERS-1],      // the 14 other spins (array port)
    input  wire        [19:0] t_reg,                   // current temperature, Q_.4 fixed point

    output wire signed [15:0] dE,                      // scaled energy change if this spin flips
    output wire                accept
);

    genvar k;

    // Sign-extend each coupling to 7 bits BEFORE negating (same reasoning
    // as the 5x5 version: -(-32) doesn't fit back into 6 bits, so widen
    // first), then apply the multiply-by-sign trick.
    wire signed [6:0] j_ext [0:NUM_OTHERS-1];
    wire signed [6:0] term  [0:NUM_OTHERS-1];
    generate
        for (k = 0; k < NUM_OTHERS; k = k + 1) begin : mul_by_sign
            assign j_ext[k] = j[k];
            assign term[k]  = s[k] ? j_ext[k] : -j_ext[k];
        end
    endgenerate

    // local_field = h_i + sum of all 14 terms, built as a running
    // combinational sum via generate (equivalent to writing out 14
    // "+ term[k]"s by hand, just not error-prone to type).
    wire signed [13:0] partial [0:NUM_OTHERS];
    assign partial[0] = h_i;
    generate
        for (k = 0; k < NUM_OTHERS; k = k + 1) begin : accum
            assign partial[k+1] = partial[k] + term[k];
        end
    endgenerate
    wire signed [13:0] local_field = partial[NUM_OTHERS];

    // dE = -2 * s_i * local_field -- unchanged trick, just wider.
    assign dE = s_i ? -(local_field <<< 1) : (local_field <<< 1);

    // ------------------------------------------------------------
    // Independent random source for this unit -- lfsr.v itself is
    // completely unchanged from the 3x3/5x5 versions.
    // ------------------------------------------------------------
    wire [7:0] rnd;
    lfsr #(.SEED(LFSR_SEED)) u_lfsr (
        .clk   (clk),
        .rst_n (rst_n),
        .rnd   (rnd)
    );

    // ------------------------------------------------------------
    // ratio_idx = (dE * 128) / T_reg, saturated to [0,63].
    // Unchanged logic from the 5x5 version -- only the width of the
    // intermediate wires grew to accommodate the larger dE/T_reg range.
    // ------------------------------------------------------------
    wire [15:0] dE_mag    = dE[15] ? -dE : dE;
    wire [31:0] ratio_raw = (dE_mag <<< 7) / t_reg;
    wire [5:0]  ratio_idx = (ratio_raw > 32'd63) ? 6'd63 : ratio_raw[5:0];

    reg [7:0] rom_val;
    always @(*) begin
        case (ratio_idx)
`include "rom_cases.vh"
            default: rom_val = 8'd0;
        endcase
    end

    assign accept = (dE <= 0) || (rnd < rom_val);

endmodule
