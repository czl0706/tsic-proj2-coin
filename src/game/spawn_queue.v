`timescale 1ns / 1ps

module spawn_queue #(
	parameter FIFO_DEPTH = 4,
	parameter FIFO_ADDR_W = 2,
	parameter [31:0] LFSR_SEED = 32'hACE1_1234
) (
	input wire clk,
	input wire resetn,
	input wire enable,

	input wire pop,
	output wire [9:0] packet,
	output wire empty,

	output wire full,
	output wire [FIFO_ADDR_W:0] level
);
	localparam TYPE_COIN_1 = 2'd0;
	localparam TYPE_COIN_3 = 2'd1;
	localparam TYPE_COIN_5 = 2'd2;
	localparam TYPE_MINUS5 = 2'd3;

	wire [31:0] rnd;
	wire [3:0] candidate_lane = rnd[3:0];
	wire [3:0] candidate_x_bias = rnd[7:4];
	wire [6:0] candidate_pct = rnd[14:8];
	reg [1:0] candidate_type;

	wire pct_valid = candidate_pct < 7'd100;
	wire lfsr_en = enable && !full;
	wire fifo_wr_en = enable && !full && pct_valid;
	wire [9:0] fifo_wr_data = {candidate_lane, candidate_x_bias, candidate_type};

	always @(*) begin
		if (candidate_pct < 7'd50)
			candidate_type = TYPE_COIN_1;
		else if (candidate_pct < 7'd75)
			candidate_type = TYPE_COIN_3;
		else if (candidate_pct < 7'd90)
			candidate_type = TYPE_COIN_5;
		else
			candidate_type = TYPE_MINUS5;
	end

	lfsr32 #(
		.SEED(LFSR_SEED)
	) u_lfsr32 (
		.clk(clk),
		.resetn(resetn),
		.en(lfsr_en),
		.rnd(rnd)
	);

	fifo #(
		.WIDTH(10),
		.DEPTH(FIFO_DEPTH),
		.ADDR_W(FIFO_ADDR_W)
	) u_spawn_fifo (
		.clk(clk),
		.resetn(resetn),
		.wr_en(fifo_wr_en),
		.wr_data(fifo_wr_data),
		.full(full),
		.rd_en(pop),
		.rd_data(packet),
		.empty(empty),
		.level(level)
	);
endmodule
