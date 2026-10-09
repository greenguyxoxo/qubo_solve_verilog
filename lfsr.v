module lfsr #( // linear fibonacci shift register module 
    parameter [7:0] SEED = 8'hA5 // starting seed 
) (
    input  wire       clk, // clock line 
    input  wire       rst_n, //reset line 
    output reg  [7:0] rnd 
);

    wire feedback = rnd[7] ^ rnd[5] ^ rnd[4] ^ rnd[3]; // implements x^8+x^6+x^5+x^4+1 

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rnd <= SEED;
        else
            rnd <= {rnd[6:0], feedback};
    end

endmodule //three modules run in parallel
