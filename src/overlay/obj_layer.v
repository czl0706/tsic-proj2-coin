`timescale 1ns / 1ps
`include "hdmi/svo_defines.vh"

module obj_layer #(
	`SVO_DEFAULT_PARAMS,
	parameter MAX_OBJ       = 16,
	parameter LANE_BITS     = 4,
	parameter XOFF_BITS     = 4,
	parameter OBJ_TYPE_BITS = 3,
	parameter OBJ_Y_BITS    = 10
) (
	input clk,
	input resetn,

	// object state from game controller
	input [9:0] player_x,
	input       player_dir,

	input [MAX_OBJ              -1:0] obj_valid_bus,
	input [MAX_OBJ*LANE_BITS    -1:0] obj_lane_bus,
	input [MAX_OBJ*XOFF_BITS    -1:0] obj_xoff_bus,
	input [MAX_OBJ*OBJ_Y_BITS   -1:0] obj_ypos_bus,
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

localparam [9:0] GAME_X0 = 64;
localparam [9:0] OBJ_W = 32;
localparam [9:0] OBJ_H = 32;

localparam PLAYER_W = 64;
localparam PLAYER_H = 64;
localparam PLAYER_SRC_BITS = 5;
localparam PLAYER_SRC_ADDR_WIDTH = 10;
localparam PLAYER_Y = 352;

localparam OBJ_ADDR_WIDTH = 8;
localparam [15:0] TRANSPARENT_VAL = 16'h0000;

reg [`SVO_XYBITS-1:0] hcursor;
reg [`SVO_XYBITS-1:0] vcursor;

reg obj_hit_d;
reg [OBJ_TYPE_BITS-1:0] obj_type_d;
reg hit_player_d;
reg player_dir_d;
reg [SVO_BITS_PER_PIXEL-1:0] bg_rgb_d;
reg [0:0] tuser_d;
reg tvalid_d;

wire fire = in_axis_tvalid && in_axis_tready;
wire [`SVO_XYBITS-1:0] pixel_x = in_axis_tuser[0] ? 0 : hcursor;
wire [`SVO_XYBITS-1:0] pixel_y = in_axis_tuser[0] ? 0 : vcursor;

integer obj_i;
reg obj_hit;
reg [OBJ_TYPE_BITS-1:0] obj_type_now;
reg [4:0] obj_local_x;
reg [4:0] obj_local_y;
reg [9:0] scan_obj_x;
reg [9:0] scan_obj_ypos;
reg [9:0] scan_local_x;
reg [9:0] scan_local_y;

function [9:0] obj_x;
	input [LANE_BITS-1:0] lane;
	input [XOFF_BITS-1:0] xoff;
	begin obj_x = GAME_X0 + ({6'd0, lane} << 5) + {6'd0, xoff}; end
endfunction

always @(*) begin
	obj_hit = 0;
	obj_type_now = 0;
	obj_local_x = 0;
	obj_local_y = 0;
	scan_obj_x = 0;
	scan_obj_ypos = 0;
	scan_local_x = 0;
	scan_local_y = 0;

	for (obj_i = 0; obj_i < MAX_OBJ; obj_i = obj_i + 1) begin
		scan_obj_x = obj_x(
			obj_lane_bus[obj_i*LANE_BITS +: LANE_BITS],
			obj_xoff_bus[obj_i*XOFF_BITS +: XOFF_BITS]
		);
		scan_obj_ypos = obj_ypos_bus[obj_i*OBJ_Y_BITS +: OBJ_Y_BITS];

		// AABB hit test
		if (!obj_hit && obj_valid_bus[obj_i] &&
			pixel_x >= scan_obj_x && pixel_x < scan_obj_x + OBJ_W &&
			pixel_y >= scan_obj_ypos && pixel_y < scan_obj_ypos + OBJ_H) begin
			scan_local_x = pixel_x - scan_obj_x;
			scan_local_y = pixel_y - scan_obj_ypos;
			obj_hit = 1;
			obj_type_now = obj_type_bus[obj_i*OBJ_TYPE_BITS +: OBJ_TYPE_BITS];
			obj_local_x = scan_local_x[4:0];
			obj_local_y = scan_local_y[4:0];
		end
	end
end

// 16x16 -> 32x32 scaling by replicating pixels
wire [3:0] obj_src_x = obj_local_x[4:1];
wire [3:0] obj_src_y = obj_local_y[4:1];
wire [OBJ_ADDR_WIDTH-1:0] obj_addr = {obj_src_y, obj_src_x};

// Sprite selection
wire [15:0] obj_plus1_rgb565;
wire [15:0] obj_plus3_rgb565;
wire [15:0] obj_plus5_rgb565;
wire [15:0] obj_minus3_rgb565;
wire [15:0] obj_minus5_rgb565;
wire [15:0] obj_time_rgb565;
wire [15:0] obj_charge_rgb565;
wire [15:0] obj_rgb565 =
	obj_type_d == 0 ? obj_plus1_rgb565 :
	obj_type_d == 1 ? obj_plus3_rgb565 :
	obj_type_d == 2 ? obj_plus5_rgb565 :
	obj_type_d == 3 ? obj_minus3_rgb565 :
	obj_type_d == 4 ? obj_minus5_rgb565 :
	obj_type_d == 5 ? obj_time_rgb565 :
						 obj_charge_rgb565;

wire hit_player = pixel_x >= player_x && pixel_x < player_x + PLAYER_W &&
				  pixel_y >= PLAYER_Y && pixel_y < PLAYER_Y + PLAYER_H;

// 32x32 -> 64x64 scaling by replicating pixels
wire [9:0] player_rel_x = pixel_x - player_x;
wire [9:0] player_rel_y = pixel_y - PLAYER_Y;
wire [PLAYER_SRC_BITS-1:0] player_src_x = player_rel_x[5:1];
wire [PLAYER_SRC_BITS-1:0] player_src_y = player_rel_y[5:1];
wire [PLAYER_SRC_ADDR_WIDTH-1:0] player_addr = {player_src_y, player_src_x};

// Player facing direction selection
wire [15:0] player_left_rgb565;
wire [15:0] player_right_rgb565;
wire [15:0] player_rgb565 = player_dir_d ? player_right_rgb565 : player_left_rgb565;

function [23:0] rgb565_to_bgr888;
	input [15:0] rgb565;
	reg [7:0] r;
	reg [7:0] g;
	reg [7:0] b;
	begin
		r = {rgb565[15:11], rgb565[15:13]};
		g = {rgb565[10: 5], rgb565[10: 9]};
		b = {rgb565[ 4: 0], rgb565[ 4: 2]};
		rgb565_to_bgr888 = {b, g, r};
	end
endfunction

// If there is an object then just show it, otherwise show the background pixel
wire [SVO_BITS_PER_PIXEL-1:0] pxl_after_obj =
	obj_hit_d && obj_rgb565 != TRANSPARENT_VAL ?
	rgb565_to_bgr888(obj_rgb565) : bg_rgb_d;

// If the player sprite is hit then show it, otherwise show whatever comes from obj layer
wire [SVO_BITS_PER_PIXEL-1:0] pxl_after_player =
	hit_player_d && player_rgb565 != TRANSPARENT_VAL ?
	rgb565_to_bgr888(player_rgb565) : pxl_after_obj;

assign in_axis_tready  = out_axis_tready;
assign out_axis_tvalid = tvalid_d;
assign out_axis_tdata  = pxl_after_player;
assign out_axis_tuser  = tuser_d;

always @(posedge clk) begin
	if (!resetn) begin
		obj_hit_d <= 0;
		obj_type_d <= 0;
		hit_player_d <= 0;
		player_dir_d <= 0;
		bg_rgb_d <= 0;
		tuser_d <= 0;
		tvalid_d <= 0;
	end else if (out_axis_tready) begin
		tvalid_d <= in_axis_tvalid;
		if (fire) begin
			obj_hit_d <= obj_hit;
			obj_type_d <= obj_type_now;
			hit_player_d <= hit_player;
			player_dir_d <= player_dir;
			bg_rgb_d <= in_axis_tdata;
			tuser_d <= in_axis_tuser;
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

rom #(
	.DATA_WIDTH(16),
	.ADDR_WIDTH(OBJ_ADDR_WIDTH),
	.DEPTH(256),
	.INIT_FILE("src/assets/obj_plus1_16.mem")
) u_obj_plus1_rom (
	.clk(clk),
	.addr(obj_addr),
	.data(obj_plus1_rgb565)
);

rom #(
	.DATA_WIDTH(16),
	.ADDR_WIDTH(OBJ_ADDR_WIDTH),
	.DEPTH(256),
	.INIT_FILE("src/assets/obj_plus3_16.mem")
) u_obj_plus3_rom (
	.clk(clk),
	.addr(obj_addr),
	.data(obj_plus3_rgb565)
);

rom #(
	.DATA_WIDTH(16),
	.ADDR_WIDTH(OBJ_ADDR_WIDTH),
	.DEPTH(256),
	.INIT_FILE("src/assets/obj_plus5_16.mem")
) u_obj_plus5_rom (
	.clk(clk),
	.addr(obj_addr),
	.data(obj_plus5_rgb565)
);

rom #(
	.DATA_WIDTH(16),
	.ADDR_WIDTH(OBJ_ADDR_WIDTH),
	.DEPTH(256),
	.INIT_FILE("src/assets/obj_minus3_16.mem")
) u_obj_minus3_rom (
	.clk(clk),
	.addr(obj_addr),
	.data(obj_minus3_rgb565)
);

rom #(
	.DATA_WIDTH(16),
	.ADDR_WIDTH(OBJ_ADDR_WIDTH),
	.DEPTH(256),
	.INIT_FILE("src/assets/obj_minus5_16.mem")
) u_obj_minus5_rom (
	.clk(clk),
	.addr(obj_addr),
	.data(obj_minus5_rgb565)
);

rom #(
	.DATA_WIDTH(16),
	.ADDR_WIDTH(OBJ_ADDR_WIDTH),
	.DEPTH(256),
	.INIT_FILE("src/assets/obj_time_16.mem")
) u_obj_time_rom (
	.clk(clk),
	.addr(obj_addr),
	.data(obj_time_rgb565)
);

rom #(
	.DATA_WIDTH(16),
	.ADDR_WIDTH(OBJ_ADDR_WIDTH),
	.DEPTH(256),
	.INIT_FILE("src/assets/obj_charge_16.mem")
) u_obj_charge_rom (
	.clk(clk),
	.addr(obj_addr),
	.data(obj_charge_rgb565)
);

rom #(
	.DATA_WIDTH(16),
	.ADDR_WIDTH(PLAYER_SRC_ADDR_WIDTH),
	.DEPTH(1024),
	.INIT_FILE("src/assets/player_left1_32.mem")
) u_player_left_rom (
	.clk(clk),
	.addr(player_addr),
	.data(player_left_rgb565)
);

rom #(
	.DATA_WIDTH(16),
	.ADDR_WIDTH(PLAYER_SRC_ADDR_WIDTH),
	.DEPTH(1024),
	.INIT_FILE("src/assets/player_right1_32.mem")
) u_player_right_rom (
	.clk(clk),
	.addr(player_addr),
	.data(player_right_rgb565)
);

endmodule
