`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"

module ui_layer #( `SVO_DEFAULT_PARAMS ) (
	input clk,
	input resetn,

	input [9:0] timer,
	input [13:0] score,
	input [13:0] high_score,
	input [1:0] state,
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

localparam [23:0] UI_BG_RGB      = 24'h181818;
localparam [23:0] TIMER_RGB      = 24'hE8E8E8;
localparam [23:0] SCORE_RGB      = 24'h20E0FF;
localparam [23:0] HIGH_SCORE_RGB = 24'hE8E8E8;
localparam [23:0] INDICATOR_RGB  = 24'h20FF40;
localparam S_OVER = 2'd2;

reg [`SVO_XYBITS-1:0] hcursor, vcursor;
reg [4:0] blink_frame_count;
reg blink_on;

wire fire = in_axis_tvalid && in_axis_tready;
wire [`SVO_XYBITS-1:0] pixel_x = in_axis_tuser[0] ? 0 : hcursor;
wire [`SVO_XYBITS-1:0] pixel_y = in_axis_tuser[0] ? 0 : vcursor;

wire [3:0] timer_d2 = timer / 10'd100;
wire [3:0] timer_d1 = (timer / 10'd10) % 10'd10;
wire [3:0] timer_d0 = timer % 10'd10;

wire [3:0] score_d3 = score / 14'd1000;
wire [3:0] score_d2 = (score / 14'd100) % 14'd10;
wire [3:0] score_d1 = (score / 14'd10) % 14'd10;
wire [3:0] score_d0 = score % 14'd10;

wire [3:0] high_score_d3 = high_score / 14'd1000;
wire [3:0] high_score_d2 = (high_score / 14'd100) % 14'd10;
wire [3:0] high_score_d1 = (high_score / 14'd10) % 14'd10;
wire [3:0] high_score_d0 = high_score % 14'd10;

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
	reg a, b, c, d, e, f, g;
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

function number_pixel;
	input [`SVO_XYBITS-1:0] x;
	input [`SVO_XYBITS-1:0] y;
	input [`SVO_XYBITS-1:0] number_x;
	input [2:0] num_digits;
	input [3:0] d0;
	input [3:0] d1;
	input [3:0] d2;
	input [3:0] d3;
	integer i;
	reg [3:0] digit;
	reg [`SVO_XYBITS-1:0] digit_left;
	begin
		number_pixel = 0;
		if (y >= DIGIT_Y && y < DIGIT_Y + DIGIT_H) begin
			for (i = 0; i < 4; i = i + 1) begin
				if (i < num_digits) begin
					digit_left = number_x + i * (DIGIT_W + DIGIT_GAP);
					case (i)
						0: digit = d0;
						1: digit = d1;
						2: digit = d2;
						default: digit = d3;
					endcase

					if (x >= digit_left && x < digit_left + DIGIT_W)
						number_pixel = digit_pixel(digit, x - digit_left, y - DIGIT_Y);
				end
			end
		end
	end
endfunction

wire timer_pixel = number_pixel(pixel_x, pixel_y, TIMER_X, 3, timer_d2, timer_d1, timer_d0, 0);
wire score_pixel = number_pixel(pixel_x, pixel_y, SCORE_X, 4, score_d3, score_d2, score_d1, score_d0);
wire high_pixel = number_pixel(pixel_x, pixel_y, HIGH_SCORE_X, 4, high_score_d3, high_score_d2, high_score_d1, high_score_d0);
wire show_score = state != S_OVER || blink_on;
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
						show_score && score_pixel ? SCORE_RGB :
						high_pixel ? HIGH_SCORE_RGB :
						ui_region ? UI_BG_RGB :
						in_axis_tdata;

always @(posedge clk) begin
	if (!resetn) begin
		blink_frame_count <= 0;
		blink_on <= 1'b1;
	end else if (fire) begin
		if (in_axis_tuser[0] && state == S_OVER) begin
			if (blink_frame_count == 5'd29) begin
				blink_frame_count <= 5'd0;
				blink_on <= !blink_on;
			end else begin
				blink_frame_count <= blink_frame_count + 1'b1;
			end
		end else if (state != S_OVER) begin
			blink_frame_count <= 5'd0;
			blink_on <= 1'b1;
		end
	end
end

always @(posedge clk) begin
	if (!resetn) begin
		hcursor <= 0;
		vcursor <= 0;
	end else if (fire) begin
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
