`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"

module ui_layer #( `SVO_DEFAULT_PARAMS ) (
	input clk,
	input resetn,

	input [9:0] timer,
	input [13:0] score,
	input [13:0] high_score,
	input [2:0] skill_charge,
	input [7:0] skill_timer,
	input game_over,
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
localparam CHARGE_X = 220;
localparam CHARGE_Y = 474;
localparam CHARGE_W = 36;
localparam CHARGE_H = 6;
localparam CHARGE_GAP = 4;
localparam SKILL_TIME_X = 430;
localparam SKILL_TIME_Y = 452;
localparam SMALL_DIGIT_W = 10;
localparam SMALL_DIGIT_H = 20;
localparam SMALL_DIGIT_GAP = 3;
localparam SMALL_SEG_T = 2;

localparam [23:0] UI_BG_RGB      = 24'h181818;
localparam [23:0] TIMER_RGB      = 24'hE8E8E8;
localparam [23:0] SCORE_RGB      = 24'h20E0FF;
localparam [23:0] HIGH_SCORE_RGB = 24'hE8E8E8;
localparam [23:0] INDICATOR_RGB  = 24'h20FF40;
localparam [23:0] CHARGE_RGB     = 24'hFFEA20;
localparam [23:0] SKILL_TIME_RGB = 24'hFFEA20;

reg [`SVO_XYBITS-1:0] hcursor, vcursor;
reg [4:0] blink_cnt;
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
wire skill_timer_ge_10 = skill_timer >= 10;
wire [3:0] skill_timer_d1 = skill_timer_ge_10 ? 1 : 0;
wire [3:0] skill_timer_d0 = skill_timer_ge_10 ? skill_timer - 10 : skill_timer[3:0];

function [6:0] digit_seg;
	input [3:0] digit;
	begin
		case (digit)
			4'd0: digit_seg = 7'b1111110;
			4'd1: digit_seg = 7'b0110000;
			4'd2: digit_seg = 7'b1101101;
			4'd3: digit_seg = 7'b1111001;
			4'd4: digit_seg = 7'b0110011;
			4'd5: digit_seg = 7'b1011011;
			4'd6: digit_seg = 7'b1011111;
			4'd7: digit_seg = 7'b1110000;
			4'd8: digit_seg = 7'b1111111;
			4'd9: digit_seg = 7'b1111011;
			default: digit_seg = 7'b0000001;
		endcase
	end
endfunction

function [6:0] pixel_seg;
	input [5:0] x;
	input [5:0] y;
	reg x_mid;
	reg x_left;
	reg x_right;
	reg y_top;
	reg y_mid;
	reg y_bottom;
	reg y_upper;
	reg y_lower;
	begin
		x_mid = x >= SEG_T && x < DIGIT_W - SEG_T;
		x_left = x < SEG_T;
		x_right = x >= DIGIT_W - SEG_T;

		y_top = y < SEG_T;
		y_mid = y >= DIGIT_H / 2 - SEG_T / 2 &&
				y < DIGIT_H / 2 + SEG_T / 2;
		y_bottom = y >= DIGIT_H - SEG_T;
		y_upper = y >= SEG_T && y < DIGIT_H / 2;
		y_lower = y >= DIGIT_H / 2 && y < DIGIT_H - SEG_T;

		pixel_seg[6] = x_mid && y_top;
		pixel_seg[5] = x_right && y_upper;
		pixel_seg[4] = x_right && y_lower;
		pixel_seg[3] = x_mid && y_bottom;
		pixel_seg[2] = x_left && y_lower;
		pixel_seg[1] = x_left && y_upper;
		pixel_seg[0] = x_mid && y_mid;
	end
endfunction

function digit_on;
	input [3:0] digit;
	input [5:0] x;
	input [5:0] y;
	begin
		digit_on = |(digit_seg(digit) & pixel_seg(x, y));
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
						number_pixel = digit_on(digit, x - digit_left, y - DIGIT_Y);
				end
			end
		end
end
endfunction

function [6:0] small_pixel_seg;
	input [4:0] x;
	input [4:0] y;
	reg x_mid;
	reg x_left;
	reg x_right;
	reg y_top;
	reg y_mid;
	reg y_bottom;
	reg y_upper;
	reg y_lower;
	begin
		x_mid = x >= SMALL_SEG_T && x < SMALL_DIGIT_W - SMALL_SEG_T;
		x_left = x < SMALL_SEG_T;
		x_right = x >= SMALL_DIGIT_W - SMALL_SEG_T;

		y_top = y < SMALL_SEG_T;
		y_mid = y >= SMALL_DIGIT_H / 2 - SMALL_SEG_T / 2 &&
				y < SMALL_DIGIT_H / 2 + SMALL_SEG_T / 2;
		y_bottom = y >= SMALL_DIGIT_H - SMALL_SEG_T;
		y_upper = y >= SMALL_SEG_T && y < SMALL_DIGIT_H / 2;
		y_lower = y >= SMALL_DIGIT_H / 2 && y < SMALL_DIGIT_H - SMALL_SEG_T;

		small_pixel_seg[6] = x_mid && y_top;
		small_pixel_seg[5] = x_right && y_upper;
		small_pixel_seg[4] = x_right && y_lower;
		small_pixel_seg[3] = x_mid && y_bottom;
		small_pixel_seg[2] = x_left && y_lower;
		small_pixel_seg[1] = x_left && y_upper;
		small_pixel_seg[0] = x_mid && y_mid;
	end
endfunction

function small_digit_on;
	input [3:0] digit;
	input [4:0] x;
	input [4:0] y;
	begin
		small_digit_on = |(digit_seg(digit) & small_pixel_seg(x, y));
	end
endfunction

function small_number_pixel;
	input [`SVO_XYBITS-1:0] x;
	input [`SVO_XYBITS-1:0] y;
	input [`SVO_XYBITS-1:0] number_x;
	input [3:0] d1;
	input [3:0] d0;
	reg [`SVO_XYBITS-1:0] digit_left;
	begin
		small_number_pixel = 0;
		if (y >= SKILL_TIME_Y && y < SKILL_TIME_Y + SMALL_DIGIT_H) begin
			digit_left = number_x;
			if (x >= digit_left && x < digit_left + SMALL_DIGIT_W)
				small_number_pixel = small_digit_on(d1, x - digit_left, y - SKILL_TIME_Y);

			digit_left = number_x + SMALL_DIGIT_W + SMALL_DIGIT_GAP;
			if (x >= digit_left && x < digit_left + SMALL_DIGIT_W)
				small_number_pixel = small_digit_on(d0, x - digit_left, y - SKILL_TIME_Y);
		end
	end
endfunction

wire timer_pixel = number_pixel(pixel_x, pixel_y, TIMER_X, 3, timer_d2, timer_d1, timer_d0, 0);
wire score_pixel = number_pixel(pixel_x, pixel_y, SCORE_X, 4, score_d3, score_d2, score_d1, score_d0);
wire high_score_pixel = number_pixel(pixel_x, pixel_y, HIGH_SCORE_X, 4, high_score_d3, high_score_d2, high_score_d1, high_score_d0);
wire skill_timer_on = skill_timer != 0;
wire skill_timer_pixel = skill_timer_on && small_number_pixel(pixel_x, pixel_y, SKILL_TIME_X, skill_timer_d1, skill_timer_d0);
wire score_on = !game_over || blink_on;
wire in_ui = pixel_y >= UI_TOP;
wire charge_y = pixel_y >= CHARGE_Y && pixel_y < CHARGE_Y + CHARGE_H;
wire charge_pixel =
	charge_y && (
		(skill_charge > 0 && pixel_x >= CHARGE_X && pixel_x < CHARGE_X + CHARGE_W) ||
		(skill_charge > 1 && pixel_x >= CHARGE_X + 1 * (CHARGE_W + CHARGE_GAP) && pixel_x < CHARGE_X + 1 * (CHARGE_W + CHARGE_GAP) + CHARGE_W) ||
		(skill_charge > 2 && pixel_x >= CHARGE_X + 2 * (CHARGE_W + CHARGE_GAP) && pixel_x < CHARGE_X + 2 * (CHARGE_W + CHARGE_GAP) + CHARGE_W) ||
		(skill_charge > 3 && pixel_x >= CHARGE_X + 3 * (CHARGE_W + CHARGE_GAP) && pixel_x < CHARGE_X + 3 * (CHARGE_W + CHARGE_GAP) + CHARGE_W) ||
		(skill_charge > 4 && pixel_x >= CHARGE_X + 4 * (CHARGE_W + CHARGE_GAP) && pixel_x < CHARGE_X + 4 * (CHARGE_W + CHARGE_GAP) + CHARGE_W)
	);
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
						score_on && score_pixel ? SCORE_RGB :
						high_score_pixel ? HIGH_SCORE_RGB :
						skill_timer_pixel ? SKILL_TIME_RGB :
						charge_pixel ? CHARGE_RGB :
						in_ui ? UI_BG_RGB :
						in_axis_tdata;

always @(posedge clk) begin
	if (!resetn) begin
		blink_cnt <= 0;
		blink_on <= 1'b1;
	end else if (fire) begin
		if (in_axis_tuser[0] && game_over) begin
			if (blink_cnt == 5'd29) begin
				blink_cnt <= 5'd0;
				blink_on <= !blink_on;
			end else begin
				blink_cnt <= blink_cnt + 1'b1;
			end
		end else if (!game_over) begin
			blink_cnt <= 5'd0;
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
