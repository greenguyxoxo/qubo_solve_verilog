// -----------------------------------------------------------------------
// qubo_annealer_top.v  (30x30 version, parametrized schedule length)
//
// Same architecture as before. N_TEMPS and SWEEPS_PER_TEMP are now module
// parameters (defaulting to the original 40/10) rather than fixed
// localparams, so a longer search can be run by instantiating this same
// module with an overridden SWEEPS_PER_TEMP -- no file duplication needed.
// T_START/ALPHA_FIXED are unaffected by this, since they depend only on
// the worst-case dE range (a function of N and the Q value range), not
// on how many sweeps happen at each temperature.
//
// Requires -g2012 for the array port.
// -----------------------------------------------------------------------
module qubo_annealer_top #(
    parameter integer N_TEMPS         = 40,
    parameter integer SWEEPS_PER_TEMP = 10   // default matches the original schedule; override to extend the search
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,

    input  wire signed [5:0] q_in [0:29][0:29],  // full symmetric matrix, -32..31 each

    output reg         done,
    output reg  [29:0] x_out
);

    localparam N = 30;
    localparam NUM_OTHERS = N - 1;

    // ---------------- fixed hardware constants (see gen_constants_30x30.py) ----------------
    // T_START/ALPHA_FIXED depend only on the worst-case dE range (a function of N and the
    // Q value range), NOT on the sweep schedule -- so these stay correct unchanged even
    // when SWEEPS_PER_TEMP is overridden to run a longer search.
    localparam [19:0] T_START     = 20'd271180;
    localparam [7:0]  ALPHA_FIXED = 8'd197;
    localparam [19:0] T_MIN       = 20'd8;

    // ---------------- FSM ----------------
    localparam S_IDLE = 3'd0, S_RUN = 3'd1, S_COOL = 3'd2, S_DONE = 3'd3;
    reg [2:0] state;

    // ---------------- registers ----------------
    reg signed [5:0] q [0:29][0:29];
    reg [29:0] spin_reg;
    reg [19:0] t_reg;
    reg [4:0]  attempt_cnt;             // supports SWEEPS_PER_TEMP up to 31 (was 4 bits / max 15 -- too narrow to double past 15)
    reg [5:0]  temp_cnt;
    reg [4:0]  rr_idx;   // 0..29 now needs 5 bits (was 4 bits for 0..14)

    integer li, lj;

    // ---------------- LFSR seeds, one per unit ----------------
    function [7:0] seed_for;
        input integer idx;
        begin
            case (idx)
                0: seed_for = 8'h82;  1: seed_for = 8'h83;  2: seed_for = 8'h04;
                3: seed_for = 8'h0B;  4: seed_for = 8'h12;  5: seed_for = 8'h15;
                6: seed_for = 8'h97;  7: seed_for = 8'h9A;  8: seed_for = 8'h1E;
                9: seed_for = 8'hB0; 10: seed_for = 8'hB1; 11: seed_for = 8'hB4;
                12: seed_for = 8'h38; 13: seed_for = 8'h39; 14: seed_for = 8'hBA;
                15: seed_for = 8'h3B; 16: seed_for = 8'h40; 17: seed_for = 8'hC1;
                18: seed_for = 8'hC8; 19: seed_for = 8'hD5; 20: seed_for = 8'h57;
                21: seed_for = 8'h5B; 22: seed_for = 8'hDF; 23: seed_for = 8'h66;
                24: seed_for = 8'h6B; 25: seed_for = 8'hF2; 26: seed_for = 8'hF6;
                27: seed_for = 8'hF8; 28: seed_for = 8'hFA; 29: seed_for = 8'h7E;
                default: seed_for = 8'hFF;
            endcase
        end
    endfunction

    // ---------------- h'_i = 2*Qii + sum of the 29 off-diagonal row entries ----------------
    wire signed [11:0] h_partial [0:29][0:29];
    wire signed [11:0] h [0:29];

    genvar gi, gj;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : h_gen
            assign h_partial[gi][0] = 2 * q[gi][gi];
            for (gj = 0; gj < N; gj = gj + 1) begin : h_accum
                if (gj != gi) begin : valid
                    localparam integer STEP = (gj < gi) ? gj : gj - 1;
                    assign h_partial[gi][STEP+1] = h_partial[gi][STEP] + q[gi][gj];
                end
            end
            assign h[gi] = h_partial[gi][NUM_OTHERS];
        end
    endgenerate

    // ---------------- 30 parallel spin update units ----------------
    wire [29:0] accept_vec;

    generate
        for (gi = 0; gi < N; gi = gi + 1) begin : units
            wire signed [5:0] my_j [0:NUM_OTHERS-1];
            wire               my_s [0:NUM_OTHERS-1];
            wire signed [15:0] my_dE;

            for (gj = 0; gj < N; gj = gj + 1) begin : other_wiring
                if (gj != gi) begin : valid
                    localparam integer DEST = (gj < gi) ? gj : gj - 1;
                    assign my_j[DEST] = q[gi][gj];
                    assign my_s[DEST] = spin_reg[gj];
                end
            end

            spin_update_unit #(
                .LFSR_SEED(seed_for(gi)),
                .NUM_OTHERS(NUM_OTHERS)
            ) u_spin (
                .clk(clk), .rst_n(rst_n),
                .h_i(h[gi]),
                .j(my_j),
                .s_i(spin_reg[gi]),
                .s(my_s),
                .t_reg(t_reg),
                .dE(my_dE),
                .accept(accept_vec[gi])
            );
        end
    endgenerate

    // ---------------- temperature cooling ----------------
    wire [27:0] t_mult    = t_reg * ALPHA_FIXED;
    wire [19:0] t_shifted = t_mult[27:8];
    wire [19:0] t_next    = (t_shifted < T_MIN) ? T_MIN : t_shifted;

    // ---------------- main FSM ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            done        <= 1'b0;
            spin_reg    <= 30'b0;
            t_reg       <= T_START;
            attempt_cnt <= 5'd0;
            temp_cnt    <= 6'd0;
            rr_idx      <= 5'd0;
            x_out       <= 30'b0;
        end else begin
            case (state)

                S_IDLE: begin
                    done <= 1'b0;
                    if (start) begin
                        for (li = 0; li < N; li = li + 1)
                            for (lj = 0; lj < N; lj = lj + 1)
                                q[li][lj] <= q_in[li][lj];
                        spin_reg    <= 30'h3FFFFFFF; // start from x = all-ones
                        t_reg       <= T_START;
                        attempt_cnt <= 5'd0;
                        temp_cnt    <= 6'd0;
                        rr_idx      <= 5'd0;
                        state       <= S_RUN;
                    end
                end

                S_RUN: begin
                    if (accept_vec[rr_idx])
                        spin_reg[rr_idx] <= ~spin_reg[rr_idx];

                    rr_idx <= (rr_idx == N-1) ? 5'd0 : rr_idx + 5'd1;

                    if (attempt_cnt == SWEEPS_PER_TEMP - 1) begin
                        attempt_cnt <= 5'd0;
                        state       <= S_COOL;
                    end else begin
                        attempt_cnt <= attempt_cnt + 5'd1;
                    end
                end

                S_COOL: begin
                    t_reg <= t_next;
                    if (temp_cnt == N_TEMPS - 1) begin
                        state <= S_DONE;
                    end else begin
                        temp_cnt <= temp_cnt + 6'd1;
                        state    <= S_RUN;
                    end
                end

                S_DONE: begin
                    x_out <= spin_reg;
                    done  <= 1'b1;
                    if (start)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
