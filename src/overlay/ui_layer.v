`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"

module ui_layer #( `SVO_DEFAULT_PARAMS ) (
	input clk,
	input resetn,

	input [9:0] timer_value,
	input [13:0] score_value,
	input [13:0] high_score_value,
	input [1:0] game_state,
	input btn_left,
	input btn_right,

	// input stream from previous layer
	input in_axis_tvalid,
	output in_axis_tready,
	input [SVO_BITS_PER_PIXEL-1:0] in_axis_tdata,
	input [0:0] in_axis_tuser,

	// output stream to next layer
	output out_axis_tvalid,
	input out_axis_tready,
	output [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output [0:0] out_axis_tuser
);
	`SVO_DECLS

	localparam UI_TOP = 416;
	localparam DIGIT_Y = 424;
	localparam DIGIT_W = 24;
	localparam DIGIT_H = 48;
	localparam DIGIT_GAP = 6;
	localparam SEG_T = 5;

	localparam TIMER_X = 32;
	localparam SCORE_X = 263;
	localparam HIGH_SCORE_X = 494;

	localparam [23:0] UI_BG_RGB = 24'h181818;
	localparam [23:0] TIMER_RGB = 24'hE8E8E8;
	localparam [23:0] SCORE_RGB = 24'h20E0FF;
	localparam [23:0] HIGH_SCORE_RGB = 24'hE8E8E8;
	localparam [23:0] INDICATOR_RGB = 24'h20FF40;
	localparam GAME_GAMEOVER = 2'd2;

	reg [`SVO_XYBITS-1:0] hcursor;
	reg [`SVO_XYBITS-1:0] vcursor;
	reg [4:0] blink_frame_count;
	reg blink_on;

	wire fire = in_axis_tvalid && in_axis_tready;
	wire [`SVO_XYBITS-1:0] pixel_x = in_axis_tuser[0] ? 0 : hcursor;
	wire [`SVO_XYBITS-1:0] pixel_y = in_axis_tuser[0] ? 0 : vcursor;

	wire [9:0] timer_clamped = timer_value > 10'd999 ? 10'd999 : timer_value;
	wire [13:0] score_clamped = score_value > 14'd9999 ? 14'd9999 : score_value;
	wire [13:0] high_score_clamped = high_score_value > 14'd9999 ? 14'd9999 : high_score_value;

	wire [3:0] timer_d2 = timer_clamped / 10'd100;
	wire [3:0] timer_d1 = (timer_clamped / 10'd10) % 10'd10;
	wire [3:0] timer_d0 = timer_clamped % 10'd10;

	wire [3:0] score_d3 = score_clamped / 14'd1000;
	wire [3:0] score_d2 = (score_clamped / 14'd100) % 14'd10;
	wire [3:0] score_d1 = (score_clamped / 14'd10) % 14'd10;
	wire [3:0] score_d0 = score_clamped % 14'd10;

	wire [3:0] high_score_d3 = high_score_clamped / 14'd1000;
	wire [3:0] high_score_d2 = (high_score_clamped / 14'd100) % 14'd10;
	wire [3:0] high_score_d1 = (high_score_clamped / 14'd10) % 14'd10;
	wire [3:0] high_score_d0 = high_score_clamped % 14'd10;

	function [6:0] digit_segments;
		input [3:0] digit;
		begin
			case (digit)
				4'd0: digit_segments = 7'b1111110;
				4'd1: digit_segments = 7'b0110000;
				4'd2: digit_segments = 7'b1101101;
				4'd3: digit_segments = 7'b1111001;
				4'd4: digit_segments = 7'b0110011;
				4'd5: digit_segments = 7'b1011011;
				4'd6: digit_segments = 7'b1011111;
				4'd7: digit_segments = 7'b1110000;
				4'd8: digit_segments = 7'b1111111;
				4'd9: digit_segments = 7'b1111011;
				default: digit_segments = 7'b0000001;
			endcase
		end
	endfunction

	function digit_pixel;
		input [3:0] digit;
		input [5:0] x;
		input [5:0] y;
		reg [6:0] seg;
		reg a;
		reg b;
		reg c;
		reg d;
		reg e;
		reg f;
		reg g;
		begin
			seg = digit_segments(digit);

			a = y < SEG_T && x >= SEG_T && x < DIGIT_W - SEG_T;
			b = x >= DIGIT_W - SEG_T && y >= SEG_T && y < DIGIT_H / 2;
			c = x >= DIGIT_W - SEG_T && y >= DIGIT_H / 2 && y < DIGIT_H - SEG_T;
			d = y >= DIGIT_H - SEG_T && x >= SEG_T && x < DIGIT_W - SEG_T;
			e = x < SEG_T && y >= DIGIT_H / 2 && y < DIGIT_H - SEG_T;
			f = x < SEG_T && y >= SEG_T && y < DIGIT_H / 2;
			g = y >= DIGIT_H / 2 - SEG_T / 2 && y < DIGIT_H / 2 + SEG_T / 2 &&
			    x >= SEG_T && x < DIGIT_W - SEG_T;

			digit_pixel = (seg[6] && a) || (seg[5] && b) || (seg[4] && c) ||
			              (seg[3] && d) || (seg[2] && e) || (seg[1] && f) ||
			              (seg[0] && g);
		end
	endfunction

	function group3_pixel;
		input [`SVO_XYBITS-1:0] x;
		input [`SVO_XYBITS-1:0] y;
		input [`SVO_XYBITS-1:0] x0;
		input [3:0] d2;
		input [3:0] d1;
		input [3:0] d0;
		begin
			group3_pixel = 0;
			if (y >= DIGIT_Y && y < DIGIT_Y + DIGIT_H) begin
				if (x >= x0 && x < x0 + DIGIT_W)
					group3_pixel = digit_pixel(d2, x - x0, y - DIGIT_Y);
				else if (x >= x0 + DIGIT_W + DIGIT_GAP && x < x0 + 2*DIGIT_W + DIGIT_GAP)
					group3_pixel = digit_pixel(d1, x - (x0 + DIGIT_W + DIGIT_GAP), y - DIGIT_Y);
				else if (x >= x0 + 2*DIGIT_W + 2*DIGIT_GAP && x < x0 + 3*DIGIT_W + 2*DIGIT_GAP)
					group3_pixel = digit_pixel(d0, x - (x0 + 2*DIGIT_W + 2*DIGIT_GAP), y - DIGIT_Y);
			end
		end
	endfunction

	function group4_pixel;
		input [`SVO_XYBITS-1:0] x;
		input [`SVO_XYBITS-1:0] y;
		input [`SVO_XYBITS-1:0] x0;
		input [3:0] d3;
		input [3:0] d2;
		input [3:0] d1;
		input [3:0] d0;
		begin
			group4_pixel = 0;
			if (y >= DIGIT_Y && y < DIGIT_Y + DIGIT_H) begin
				if (x >= x0 && x < x0 + DIGIT_W)
					group4_pixel = digit_pixel(d3, x - x0, y - DIGIT_Y);
				else if (x >= x0 + DIGIT_W + DIGIT_GAP && x < x0 + 2*DIGIT_W + DIGIT_GAP)
					group4_pixel = digit_pixel(d2, x - (x0 + DIGIT_W + DIGIT_GAP), y - DIGIT_Y);
				else if (x >= x0 + 2*DIGIT_W + 2*DIGIT_GAP && x < x0 + 3*DIGIT_W + 2*DIGIT_GAP)
					group4_pixel = digit_pixel(d1, x - (x0 + 2*DIGIT_W + 2*DIGIT_GAP), y - DIGIT_Y);
				else if (x >= x0 + 3*DIGIT_W + 3*DIGIT_GAP && x < x0 + 4*DIGIT_W + 3*DIGIT_GAP)
					group4_pixel = digit_pixel(d0, x - (x0 + 3*DIGIT_W + 3*DIGIT_GAP), y - DIGIT_Y);
			end
		end
	endfunction

	wire timer_pixel = group3_pixel(pixel_x, pixel_y, TIMER_X, timer_d2, timer_d1, timer_d0);
	wire score_pixel = group4_pixel(pixel_x, pixel_y, SCORE_X, score_d3, score_d2, score_d1, score_d0);
	wire high_score_pixel = group4_pixel(pixel_x, pixel_y, HIGH_SCORE_X, high_score_d3, high_score_d2, high_score_d1, high_score_d0);
	wire score_visible = game_state != GAME_GAMEOVER || blink_on;
	wire ui_region = pixel_y >= UI_TOP;
	wire left_indicator = btn_left && pixel_y >= UI_TOP + 8 && pixel_y < UI_TOP + 56 &&
	                      pixel_x >= 4 && pixel_x < 20;
	wire right_indicator = btn_right && pixel_y >= UI_TOP + 8 && pixel_y < UI_TOP + 56 &&
	                       pixel_x >= SVO_HOR_PIXELS - 20 && pixel_x < SVO_HOR_PIXELS - 4;

	assign in_axis_tready = out_axis_tready;
	assign out_axis_tvalid = in_axis_tvalid;
	assign out_axis_tuser = in_axis_tuser;
	assign out_axis_tdata = left_indicator ? INDICATOR_RGB :
	                        right_indicator ? INDICATOR_RGB :
	                        timer_pixel ? TIMER_RGB :
	                        score_visible && score_pixel ? SCORE_RGB :
	                        high_score_pixel ? HIGH_SCORE_RGB :
	                        ui_region ? UI_BG_RGB :
	                        in_axis_tdata;

	always @(posedge clk) begin
		if (!resetn) begin
			hcursor <= 0;
			vcursor <= 0;
			blink_frame_count <= 0;
			blink_on <= 1'b1;
		end else if (fire) begin
			if (in_axis_tuser[0] && game_state == GAME_GAMEOVER) begin
				if (blink_frame_count == 5'd29) begin
					blink_frame_count <= 5'd0;
					blink_on <= !blink_on;
				end else begin
					blink_frame_count <= blink_frame_count + 1'b1;
				end
			end else if (game_state != GAME_GAMEOVER) begin
				blink_frame_count <= 5'd0;
				blink_on <= 1'b1;
			end

			if (in_axis_tuser[0]) begin
				hcursor <= 1;
				vcursor <= 0;
			end else if (hcursor == SVO_HOR_PIXELS - 1) begin
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
