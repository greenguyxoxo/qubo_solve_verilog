// -----------------------------------------------------------------------
// brute_force_solver.v  (15x15 version)
//
// Same role as the 5x5 version: reference/verification hardware only,
// exhaustively checks all 2^15=32768 states, one per cycle. At this
// scale, E(x) has 120 terms (15 diagonal + 105 off-diagonal) instead of
// 15, so they're summed via generate-built running totals rather than
// written out by hand.
// -----------------------------------------------------------------------
module brute_force_solver (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    input  wire signed [5:0] q_in [0:14][0:14],  // same symmetric-matrix convention as qubo_annealer_top

    output reg         done,
    output reg  [14:0] best_x,
    output reg  signed [19:0] best_E
);

    localparam N = 15;

    localparam S_IDLE = 2'd0, S_SEARCH = 2'd1, S_DONE = 2'd2;
    reg [1:0] state;

    reg [14:0] x_test;               // candidate state, 0..32767
    reg signed [19:0] best_E_reg;

    // Sign-extend every Q entry once, up front (same pattern as the 5x5 version).
    wire signed [19:0] qx [0:14][0:14];
    genvar gi, gj;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : sx_row
            for (gj = 0; gj < N; gj = gj + 1) begin : sx_col
                assign qx[gi][gj] = q_in[gi][gj];
            end
        end
    endgenerate

    // ---- diagonal terms: sum of Qii*xi for i=0..14 ----
    wire signed [19:0] diag_partial [0:N];
    assign diag_partial[0] = 20'sd0;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : diag_gen
            assign diag_partial[gi+1] = diag_partial[gi] + (x_test[gi] ? qx[gi][gi] : 20'sd0);
        end
    endgenerate

    // ---- off-diagonal terms: sum of Qij*xi*xj for all i<j (105 pairs) ----
    // Flattened into a single running sum via a closed-form triangular
    // index: STEP counts how many (i,j) pairs with i<j come before this one.
    wire signed [19:0] off_partial [0:105];
    assign off_partial[0] = 20'sd0;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : off_row
            for (gj = gi+1; gj < N; gj = gj + 1) begin : off_col
                localparam integer STEP = 14*gi - (gi*(gi-1))/2 + (gj-gi-1);
                assign off_partial[STEP+1] = off_partial[STEP]
                    + ((x_test[gi] && x_test[gj]) ? qx[gi][gj] : 20'sd0);
            end
        end
    endgenerate

    wire signed [19:0] e_test = diag_partial[N] + off_partial[105];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            done  <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        x_test     <= 15'd0;
                        best_x     <= 15'd0;
                        best_E_reg <= 20'sd0;
                        state      <= S_SEARCH;
                    end
                end

                S_SEARCH: begin
                    if (x_test == 15'd0 || e_test < best_E_reg) begin
                        best_E_reg <= e_test;
                        best_x     <= x_test;
                    end

                    if (x_test == 15'd32767) begin
                        state <= S_DONE;
                    end else begin
                        x_test <= x_test + 15'd1;
                    end
                end

                S_DONE: begin
                    done   <= 1'b1;
                    best_E <= best_E_reg;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
