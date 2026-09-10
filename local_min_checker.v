// -----------------------------------------------------------------------
// local_min_checker.v
//
// Practical verification for problem sizes where exhaustive brute force
// is no longer feasible (2^30 states is ~1.07 billion -- checking all of
// them, even at 1/cycle, would take far too long to simulate). Instead,
// checks LOCAL optimality: given SA's final answer, evaluate the energy
// of all 30 single-bit-flip neighbors and confirm none of them improve
// on it. This is the standard practical sanity check used on real
// problems too large to solve exactly -- it can't prove global
// optimality, but it can catch SA stopping somewhere genuinely bad
// (a state where an obvious one-flip improvement was sitting right
// there and unused).
//
// Only 31 energy evaluations total (the original + 30 flips), so this
// finishes in ~32 cycles regardless of N -- nothing like the 2^N cost
// of exhaustive search.
// -----------------------------------------------------------------------
module local_min_checker (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    input  wire signed [5:0] q_in [0:29][0:29],
    input  wire        [29:0] x_check,   // the SA result to verify

    output reg          done,
    output reg          is_local_min,
    output reg   [4:0]  best_flip_idx,   // which single flip helps most (valid only if !is_local_min)
    output reg   signed [15:0] best_flip_dE,  // energy change of that flip (negative = improvement)
    output reg   signed [15:0] base_E          // energy of x_check itself -- for comparing runs against each other
);

    localparam N = 30;
    localparam S_IDLE = 2'd0, S_SEARCH = 2'd1, S_DONE = 2'd2;
    reg [1:0] state;

    reg [4:0] cand_idx;              // 0 = baseline (x_check itself), 1..30 = flip bit (cand_idx-1)
    reg signed [15:0] base_E_reg;
    reg signed [15:0] best_dE_reg;
    reg [4:0] best_idx_reg;

    wire [29:0] x_cand = (cand_idx == 5'd0) ? x_check : (x_check ^ (30'b1 << (cand_idx - 5'd1)));

    wire signed [15:0] qx [0:29][0:29];
    genvar gi, gj;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : sx_row
            for (gj = 0; gj < N; gj = gj + 1) begin : sx_col
                assign qx[gi][gj] = q_in[gi][gj];
            end
        end
    endgenerate

    wire signed [15:0] diag_partial [0:N];
    assign diag_partial[0] = 16'sd0;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : diag_gen
            assign diag_partial[gi+1] = diag_partial[gi] + (x_cand[gi] ? qx[gi][gi] : 16'sd0);
        end
    endgenerate

    // C(30,2) = 435 off-diagonal pairs
    wire signed [15:0] off_partial [0:435];
    assign off_partial[0] = 16'sd0;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : off_row
            for (gj = gi+1; gj < N; gj = gj + 1) begin : off_col
                localparam integer STEP = 29*gi - (gi*(gi-1))/2 + (gj-gi-1);
                assign off_partial[STEP+1] = off_partial[STEP]
                    + ((x_cand[gi] && x_cand[gj]) ? qx[gi][gj] : 16'sd0);
            end
        end
    endgenerate

    wire signed [15:0] e_cand = diag_partial[N] + off_partial[435];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done  <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        cand_idx    <= 5'd0;
                        best_dE_reg <= 16'sd0;
                        best_idx_reg<= 5'd0;
                        state       <= S_SEARCH;
                    end
                end

                S_SEARCH: begin
                    if (cand_idx == 5'd0) begin
                        base_E_reg <= e_cand;   // record baseline energy
                    end else begin
                        // record the first flip unconditionally (nothing to compare against yet),
                        // then only keep it if it's the best (most negative / most improving) so far
                        if (cand_idx == 5'd1 || (e_cand - base_E_reg) < best_dE_reg) begin
                            best_dE_reg  <= e_cand - base_E_reg;
                            best_idx_reg <= cand_idx - 5'd1;
                        end
                    end

                    if (cand_idx == 5'd30) begin
                        state <= S_DONE;
                    end else begin
                        cand_idx <= cand_idx + 5'd1;
                    end
                end

                S_DONE: begin
                    done          <= 1'b1;
                    is_local_min  <= (best_dE_reg >= 0);
                    best_flip_idx <= best_idx_reg;
                    best_flip_dE  <= best_dE_reg;
                    base_E        <= base_E_reg;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
