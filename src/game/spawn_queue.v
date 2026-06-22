`timescale 1ns / 1ps

module spawn_queue #(
	parameter FIFO_DEPTH = 4,
	parameter FIFO_ADDR_W = 2,
	parameter [31:0] POS_SEED = 32'hACE1_1234,
	parameter [31:0] TYPE_SEED = 32'h1D2C_3B4A
) (
	input wire clk,
	input wire resetn,
	input wire enable,

	input wire pop,
	output wire [9:0] spawn_data,
	output wire empty,

	output wire full,
	output wire [FIFO_ADDR_W:0] level
);
localparam TYPE_COIN_1 = 0;
localparam TYPE_COIN_3 = 1;
localparam TYPE_COIN_5 = 2;
localparam TYPE_MINUS5 = 3;

wire [31:0] pos_rnd;
wire [31:0] type_rnd;
wire [3:0] cand_lane = pos_rnd[3:0];
wire [3:0] cand_xoff = pos_rnd[7:4];
wire [6:0] cand_pct  = type_rnd[6:0];
reg [1:0] cand_type;

wire cand_valid = cand_pct < 100;
wire cand_next = enable && !full;
wire fifo_wr_en = cand_next && cand_valid;
wire [9:0] fifo_wr_data = {cand_lane, cand_xoff, cand_type};

always @(*) begin
	     if (cand_pct < 50) cand_type = TYPE_COIN_1;
	else if (cand_pct < 75) cand_type = TYPE_COIN_3;
	else if (cand_pct < 90) cand_type = TYPE_COIN_5;
	else                    cand_type = TYPE_MINUS5;
end

lfsr32 #(
	.SEED(POS_SEED)
) u_pos_lfsr (
	.clk(clk),
	.resetn(resetn),
	.en(cand_next),
	.rnd(pos_rnd)
);

lfsr32 #(
	.SEED(TYPE_SEED)
) u_type_lfsr (
	.clk(clk),
	.resetn(resetn),
	.en(cand_next),
	.rnd(type_rnd)
);

fifo #(
	.WIDTH(10),
	.DEPTH(FIFO_DEPTH)
) u_spawn_fifo (
	.clk(clk),
	.resetn(resetn),
	.wr_en(fifo_wr_en),
	.wr_data(fifo_wr_data),
	.full(full),
	.rd_en(pop),
	.rd_data(spawn_data),
	.empty(empty),
	.level(level)
);
endmodule
