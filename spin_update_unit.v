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

    wire signed [6:0] j_ext [0:NUM_OTHERS-1];
    wire signed [6:0] term  [0:NUM_OTHERS-1];
    generate
        for (k = 0; k < NUM_OTHERS; k = k + 1) begin : mul_by_sign
            assign j_ext[k] = j[k];
            assign term[k]  = s[k] ? j_ext[k] : -j_ext[k];
        end
    endgenerate

    wire signed [13:0] partial [0:NUM_OTHERS];
    assign partial[0] = h_i;
    generate
        for (k = 0; k < NUM_OTHERS; k = k + 1) begin : accum
            assign partial[k+1] = partial[k] + term[k];
        end
    endgenerate
    wire signed [13:0] local_field = partial[NUM_OTHERS];


    assign dE = s_i ? -(local_field <<< 1) : (local_field <<< 1);


    wire [7:0] rnd;
    lfsr #(.SEED(LFSR_SEED)) u_lfsr (
        .clk   (clk),
        .rst_n (rst_n),
        .rnd   (rnd)
    );


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
