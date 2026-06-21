`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"

module obj_layer #(
	`SVO_DEFAULT_PARAMS,
	parameter MAX_OBJ = 16,
	parameter LANE_BITS = 4,
	parameter X_BIAS_BITS = 4,
	parameter OBJ_TYPE_BITS = 2,
	parameter OBJ_Y_BITS = 10
) (
	input clk,
	input resetn,

	// object state from game controller
	input [9:0] player_x,
	input player_facing_right,

	input [MAX_OBJ-1:0] obj_active_bus,
	input [MAX_OBJ*LANE_BITS-1:0] obj_lane_bus,
	input [MAX_OBJ*X_BIAS_BITS-1:0] obj_x_bias_bus,
	input [MAX_OBJ*OBJ_Y_BITS-1:0] obj_y_bus,
	input [MAX_OBJ*OBJ_TYPE_BITS-1:0] obj_type_bus,

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

	localparam [9:0] GAME_X0 = 10'd64;
	localparam [9:0] OBJ_W = 10'd32;
	localparam [9:0] OBJ_H = 10'd32;

	localparam PLAYER_W = 64;
	localparam PLAYER_H = 64;
	localparam PLAYER_SRC_BITS = 5;
	localparam PLAYER_SRC_ADDR_WIDTH = 10;
	localparam PLAYER_Y = 352;

	localparam OBJ_ADDR_WIDTH = 8;
	localparam [15:0] TRANSPARENT_RGB565 = 16'h0000;

	reg [`SVO_XYBITS-1:0] hcursor;
	reg [`SVO_XYBITS-1:0] vcursor;

	reg hit_object_d;
	reg [OBJ_TYPE_BITS-1:0] object_type_d;
	reg hit_player_d;
	reg player_facing_right_d;
	reg [SVO_BITS_PER_PIXEL-1:0] bg_rgb_d;
	reg [0:0] tuser_d;
	reg tvalid_d;

	wire fire = in_axis_tvalid && in_axis_tready;
	wire [`SVO_XYBITS-1:0] pixel_x = in_axis_tuser[0] ? 0 : hcursor;
	wire [`SVO_XYBITS-1:0] pixel_y = in_axis_tuser[0] ? 0 : vcursor;

	integer obj_i;
	reg object_hit_now;
	reg [OBJ_TYPE_BITS-1:0] object_type_now;
	reg [4:0] object_local_x_now;
	reg [4:0] object_local_y_now;
	reg [9:0] scan_obj_x;
	reg [9:0] scan_obj_y;
	reg [LANE_BITS-1:0] scan_lane;
	reg [X_BIAS_BITS-1:0] scan_x_bias;
	reg [9:0] scan_local_x;
	reg [9:0] scan_local_y;

	always @(*) begin
		object_hit_now = 1'b0;
		object_type_now = {OBJ_TYPE_BITS{1'b0}};
		object_local_x_now = 5'd0;
		object_local_y_now = 5'd0;
		scan_obj_x = 10'd0;
		scan_obj_y = 10'd0;
		scan_lane = {LANE_BITS{1'b0}};
		scan_x_bias = {X_BIAS_BITS{1'b0}};
		scan_local_x = 10'd0;
		scan_local_y = 10'd0;

		for (obj_i = 0; obj_i < MAX_OBJ; obj_i = obj_i + 1) begin
			scan_lane = obj_lane_bus[obj_i*LANE_BITS +: LANE_BITS];
			scan_x_bias = obj_x_bias_bus[obj_i*X_BIAS_BITS +: X_BIAS_BITS];
			scan_obj_x = GAME_X0 + ({6'd0, scan_lane} << 5) + {6'd0, scan_x_bias};
			scan_obj_y = obj_y_bus[obj_i*OBJ_Y_BITS +: OBJ_Y_BITS];

			if (!object_hit_now && obj_active_bus[obj_i] &&
			    pixel_x >= scan_obj_x && pixel_x < scan_obj_x + OBJ_W &&
			    pixel_y >= scan_obj_y && pixel_y < scan_obj_y + OBJ_H) begin
				scan_local_x = pixel_x - scan_obj_x;
				scan_local_y = pixel_y - scan_obj_y;
				object_hit_now = 1'b1;
				object_type_now = obj_type_bus[obj_i*OBJ_TYPE_BITS +: OBJ_TYPE_BITS];
				object_local_x_now = scan_local_x[4:0];
				object_local_y_now = scan_local_y[4:0];
			end
		end
	end

	wire [3:0] object_src_x = object_local_x_now[4:1];
	wire [3:0] object_src_y = object_local_y_now[4:1];
	wire [OBJ_ADDR_WIDTH-1:0] object_addr = {object_src_y, object_src_x};
	wire [15:0] obj_plus1_rgb565;
	wire [15:0] obj_plus3_rgb565;
	wire [15:0] obj_plus5_rgb565;
	wire [15:0] obj_minus5_rgb565;
	wire [15:0] object_rgb565 =
		object_type_d == 2'd0 ? obj_plus1_rgb565 :
		object_type_d == 2'd1 ? obj_plus3_rgb565 :
		object_type_d == 2'd2 ? obj_plus5_rgb565 :
		                       obj_minus5_rgb565;

	wire hit_player = pixel_x >= player_x && pixel_x < player_x + PLAYER_W &&
	                  pixel_y >= PLAYER_Y && pixel_y < PLAYER_Y + PLAYER_H;
	wire [9:0] player_rel_x = pixel_x - player_x;
	wire [9:0] player_rel_y = pixel_y - PLAYER_Y;
	wire [5:0] player_dst_x = player_rel_x[5:0];
	wire [5:0] player_dst_y = player_rel_y[5:0];
	wire [PLAYER_SRC_BITS-1:0] player_src_x = player_dst_x[5:1];
	wire [PLAYER_SRC_BITS-1:0] player_src_y = player_dst_y[5:1];
	wire [PLAYER_SRC_ADDR_WIDTH-1:0] player_addr = {player_src_y, player_src_x};

	wire [15:0] player_left_rgb565;
	wire [15:0] player_right_rgb565;
	wire [15:0] player_rgb565 = player_facing_right_d ? player_right_rgb565 : player_left_rgb565;

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
		.ADDR_WIDTH(OBJ_ADDR_WIDTH),
		.DEPTH(256),
		.INIT_FILE("src/assets/objects/obj_plus1_16.mem")
	) u_obj_plus1_rom (
		.clk(clk),
		.addr(object_addr),
		.data(obj_plus1_rgb565)
	);

	rom #(
		.DATA_WIDTH(16),
		.ADDR_WIDTH(OBJ_ADDR_WIDTH),
		.DEPTH(256),
		.INIT_FILE("src/assets/objects/obj_plus3_16.mem")
	) u_obj_plus3_rom (
		.clk(clk),
		.addr(object_addr),
		.data(obj_plus3_rgb565)
	);

	rom #(
		.DATA_WIDTH(16),
		.ADDR_WIDTH(OBJ_ADDR_WIDTH),
		.DEPTH(256),
		.INIT_FILE("src/assets/objects/obj_plus5_16.mem")
	) u_obj_plus5_rom (
		.clk(clk),
		.addr(object_addr),
		.data(obj_plus5_rgb565)
	);

	rom #(
		.DATA_WIDTH(16),
		.ADDR_WIDTH(OBJ_ADDR_WIDTH),
		.DEPTH(256),
		.INIT_FILE("src/assets/objects/obj_minus5_16.mem")
	) u_obj_minus5_rom (
		.clk(clk),
		.addr(object_addr),
		.data(obj_minus5_rgb565)
	);

	rom #(
		.DATA_WIDTH(16),
		.ADDR_WIDTH(PLAYER_SRC_ADDR_WIDTH),
		.DEPTH(1024),
		.INIT_FILE("src/assets/player/player_left1_32.mem")
	) u_player_left_rom (
		.clk(clk),
		.addr(player_addr),
		.data(player_left_rgb565)
	);

	rom #(
		.DATA_WIDTH(16),
		.ADDR_WIDTH(PLAYER_SRC_ADDR_WIDTH),
		.DEPTH(1024),
		.INIT_FILE("src/assets/player/player_right1_32.mem")
	) u_player_right_rom (
		.clk(clk),
		.addr(player_addr),
		.data(player_right_rgb565)
	);

	wire [SVO_BITS_PER_PIXEL-1:0] object_or_bg_rgb =
		hit_object_d && object_rgb565 != TRANSPARENT_RGB565 ?
		rgb565_to_bgr888(object_rgb565) : bg_rgb_d;

	assign in_axis_tready = out_axis_tready;
	assign out_axis_tvalid = tvalid_d;
	assign out_axis_tdata =
		hit_player_d && player_rgb565 != TRANSPARENT_RGB565 ?
		rgb565_to_bgr888(player_rgb565) : object_or_bg_rgb;
	assign out_axis_tuser = tuser_d;

	always @(posedge clk) begin
		if (!resetn) begin
			hcursor <= 0;
			vcursor <= 0;
			hit_object_d <= 0;
			object_type_d <= 0;
			hit_player_d <= 0;
			player_facing_right_d <= 0;
			bg_rgb_d <= 0;
			tuser_d <= 0;
			tvalid_d <= 0;
		end else if (out_axis_tready) begin
			tvalid_d <= in_axis_tvalid;
			if (fire) begin
				hit_object_d <= object_hit_now;
				object_type_d <= object_type_now;
				hit_player_d <= hit_player;
				player_facing_right_d <= player_facing_right;
				bg_rgb_d <= in_axis_tdata;
				tuser_d <= in_axis_tuser;

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
	end
endmodule
