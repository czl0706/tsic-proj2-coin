`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"

module bg_layer #(
	`SVO_DEFAULT_PARAMS,
	parameter BG_SRC_X_BITS = 5,
	parameter BG_SRC_Y_BITS = 5,
	parameter BG_TILE_INIT_FILE = "src/assets/background.mem"
) (
	input clk,
	input resetn,

	// output stream
	//   tuser[0] ... start of frame
	output reg out_axis_tvalid,
	input out_axis_tready,
	output reg [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output reg [0:0] out_axis_tuser
);
	`SVO_DECLS

	localparam BG_SRC_ADDR_WIDTH = BG_SRC_X_BITS + BG_SRC_Y_BITS;
	localparam BG_SRC_DEPTH = 1 << BG_SRC_ADDR_WIDTH;
	localparam BG_DST_X_BITS = BG_SRC_X_BITS + 1;
	localparam BG_DST_Y_BITS = BG_SRC_Y_BITS + 1;

	reg [`SVO_XYBITS-1:0] hcursor;
	reg [`SVO_XYBITS-1:0] vcursor;
	reg pipe_valid;
	reg pipe_tuser;

	wire [BG_DST_X_BITS-1:0] dst_x = hcursor[BG_DST_X_BITS-1:0];
	wire [BG_DST_Y_BITS-1:0] dst_y = vcursor[BG_DST_Y_BITS-1:0];
	wire [BG_SRC_X_BITS-1:0] src_x = dst_x[BG_DST_X_BITS-1:1];
	wire [BG_SRC_Y_BITS-1:0] src_y = dst_y[BG_DST_Y_BITS-1:1];
	wire [BG_SRC_ADDR_WIDTH-1:0] bg_addr = {src_y, src_x};
	wire [15:0] bg_rgb565;

	function [23:0] rgb565_to_bgr888;
		input [15:0] rgb565;
		reg [7:0] r;
		reg [7:0] g;
		reg [7:0] b;
		begin
			r = {rgb565[15:11], rgb565[15:13]};
			g = {rgb565[10:5], rgb565[10:9]};
			b = {rgb565[4:0], rgb565[4:2]};
			rgb565_to_bgr888 = {b, g, r};
		end
	endfunction

	rom #(
		.DATA_WIDTH(16),
		.ADDR_WIDTH(BG_SRC_ADDR_WIDTH),
		.DEPTH(BG_SRC_DEPTH),
		.INIT_FILE(BG_TILE_INIT_FILE)
	) u_bg_rom (
		.clk(clk),
		.addr(bg_addr),
		.data(bg_rgb565)
	);

	always @(posedge clk) begin
		if (!resetn) begin
			hcursor <= 0;
			vcursor <= 0;
			pipe_valid <= 0;
			pipe_tuser <= 0;
			out_axis_tvalid <= 0;
			out_axis_tdata <= 0;
			out_axis_tuser <= 0;
		end else if (!out_axis_tvalid || out_axis_tready) begin
			out_axis_tvalid <= pipe_valid;
			out_axis_tdata <= rgb565_to_bgr888(bg_rgb565);
			out_axis_tuser[0] <= pipe_tuser;
			pipe_valid <= 1;
			pipe_tuser <= hcursor == 0 && vcursor == 0;

			if (hcursor == SVO_HOR_PIXELS - 1) begin
				hcursor <= 0;
				if (vcursor == SVO_VER_PIXELS - 1)
					vcursor <= 0;
				else
					vcursor <= vcursor + 1;
			end else begin
				hcursor <= hcursor + 1;
			end
		end
	end
endmodule
