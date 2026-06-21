`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"

module game_core #(
	parameter SVO_MODE             =   "640x480V",
	parameter SVO_FRAMERATE        =   60,
	parameter SVO_BITS_PER_PIXEL   =   24,
	parameter SVO_BITS_PER_RED     =    8,
	parameter SVO_BITS_PER_GREEN   =    8,
	parameter SVO_BITS_PER_BLUE    =    8,
	parameter SVO_BITS_PER_ALPHA   =    0
) (
	input clk,
	input resetn,

	input btn_left,
	input btn_right,
	input btn_start,

	output out_axis_tvalid,
	input out_axis_tready,
	output [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
	output [0:0] out_axis_tuser
);
	wire bg_tvalid;
	wire bg_tready;
	wire [SVO_BITS_PER_PIXEL-1:0] bg_tdata;
	wire [0:0] bg_tuser;

	wire obj_tvalid;
	wire obj_tready;
	wire [SVO_BITS_PER_PIXEL-1:0] obj_tdata;
	wire [0:0] obj_tuser;

	wire frame_tick;
	wire [9:0] player_x;
	wire player_facing_right;
	wire [15:0] obj_active_bus;
	wire [63:0] obj_lane_bus;
	wire [63:0] obj_x_bias_bus;
	wire [159:0] obj_y_bus;
	wire [31:0] obj_type_bus;
	wire [9:0] timer_value;
	wire [13:0] score_value;
	wire [13:0] high_score_value;
	wire [1:0] game_state;

	assign frame_tick = bg_tvalid && bg_tready && bg_tuser[0];

	game_ctrl u_game_ctrl (
		.clk(clk),
		.resetn(resetn),
		.frame_tick(frame_tick),

		.btn_left(btn_left),
		.btn_right(btn_right),
		.btn_start(btn_start),

		.player_x(player_x),
		.player_facing_right(player_facing_right),

		.obj_active_bus(obj_active_bus),
		.obj_lane_bus(obj_lane_bus),
		.obj_x_bias_bus(obj_x_bias_bus),
		.obj_y_bus(obj_y_bus),
		.obj_type_bus(obj_type_bus),

		.timer_value(timer_value),
		.score_value(score_value),
		.high_score_value(high_score_value),
		.game_state(game_state)
	);

	bg_layer #(
		`SVO_PASS_PARAMS,
		.BG_SRC_X_BITS(5),
		.BG_SRC_Y_BITS(5),
		.BG_TILE_INIT_FILE("src/assets/background.mem")
	) u_bg_layer (
		.clk(clk),
		.resetn(resetn),

		.out_axis_tvalid(bg_tvalid),
		.out_axis_tready(bg_tready),
		.out_axis_tdata(bg_tdata),
		.out_axis_tuser(bg_tuser)
	);

	obj_layer #( `SVO_PASS_PARAMS ) u_obj_layer (
		.clk(clk),
		.resetn(resetn),

		.player_x(player_x),
		.player_facing_right(player_facing_right),
		.obj_active_bus(obj_active_bus),
		.obj_lane_bus(obj_lane_bus),
		.obj_x_bias_bus(obj_x_bias_bus),
		.obj_y_bus(obj_y_bus),
		.obj_type_bus(obj_type_bus),

		.in_axis_tvalid(bg_tvalid),
		.in_axis_tready(bg_tready),
		.in_axis_tdata(bg_tdata),
		.in_axis_tuser(bg_tuser),

		.out_axis_tvalid(obj_tvalid),
		.out_axis_tready(obj_tready),
		.out_axis_tdata(obj_tdata),
		.out_axis_tuser(obj_tuser)
	);

	ui_layer #( `SVO_PASS_PARAMS ) u_ui_layer (
		.clk(clk),
		.resetn(resetn),

		.timer_value(timer_value),
		.score_value(score_value),
		.high_score_value(high_score_value),
		.game_state(game_state),
		.btn_left(btn_left),
		.btn_right(btn_right),

		.in_axis_tvalid(obj_tvalid),
		.in_axis_tready(obj_tready),
		.in_axis_tdata(obj_tdata),
		.in_axis_tuser(obj_tuser),

		.out_axis_tvalid(out_axis_tvalid),
		.out_axis_tready(out_axis_tready),
		.out_axis_tdata(out_axis_tdata),
		.out_axis_tuser(out_axis_tuser)
	);
endmodule
