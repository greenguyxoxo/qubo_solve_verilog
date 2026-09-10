module lfsr #(
    parameter [7:0] SEED = 8'hA5
) (
    input  wire       clk,
    input  wire       rst_n,
    output reg  [7:0] rnd
);

    wire feedback = rnd[7] ^ rnd[5] ^ rnd[4] ^ rnd[3];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rnd <= SEED;
        else
            rnd <= {rnd[6:0], feedback};
    end

endmodule
// -----------------------------------------------------------------------
// lfsr.v
// 8-bit maximal-length Fibonacci LFSR (polynomial x^8+x^6+x^5+x^4+1).
// Free-running: advances by one tap every clock cycle. Each instance
// must be given a distinct non-zero SEED so the three parallel spin
// update units don't draw correlated random numbers.
// -----------------------------------------------------------------------