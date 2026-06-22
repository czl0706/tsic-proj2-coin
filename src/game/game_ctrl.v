`timescale 1ns / 1ps

module game_ctrl #(
	parameter MAX_OBJ = 16,
	parameter LANE_BITS = 4,
	parameter XOFF_BITS = 4,
	parameter OBJ_TYPE_BITS = 2,
	parameter OBJ_Y_BITS = 10,
	parameter FALL_SPEED = 2,
	parameter SPAWN_PERIOD_FRAMES = 24,
	parameter PLAYER_WIDTH = 64,
	parameter PLAYER_HEIGHT = 64,
	parameter PLAYER_START_X = 288,
	parameter PLAYER_SPEED_START = 8,
	parameter TIMER_START = 90,
	parameter HIGH_SCORE_START = 0
)(
	input clk,
	input resetn,
	input frame_tick,

	input btn_left,
	input btn_right,
	input btn_start,

	output obj_ready,

	output reg [9:0] player_x,
	output reg [5:0] player_speed,
	output reg player_dir,

	output reg [MAX_OBJ              -1:0] obj_valid_bus,
	output reg [MAX_OBJ*LANE_BITS    -1:0] obj_lane_bus,
	output reg [MAX_OBJ*XOFF_BITS    -1:0] obj_xoff_bus,
	output reg [MAX_OBJ*OBJ_Y_BITS   -1:0] obj_ypos_bus,
	output reg [MAX_OBJ*OBJ_TYPE_BITS-1:0] obj_type_bus,

	output reg [9:0] timer,
	output reg [13:0] score,
	output reg [13:0] high_score,
	output game_over
);
localparam S_PLAY = 1;
localparam S_OVER = 2;

localparam TYPE_COIN_1 = 0;
localparam TYPE_COIN_3 = 1;
localparam TYPE_COIN_5 = 2;
localparam TYPE_MINUS5 = 3;

localparam [9:0] SCREEN_W = 640;
localparam [9:0] GAME_X0 = 64;
localparam [9:0] UI_TOP = 416;
localparam [9:0] OBJ_W = 32;
localparam [9:0] OBJ_H = 32;
localparam [9:0] OBJ_GROUND_Y = UI_TOP - OBJ_H;
localparam [9:0] PLAYER_Y = 352;
localparam [9:0] PLAYER_MAX_X = SCREEN_W - PLAYER_WIDTH;

reg [LANE_BITS    -1:0] obj_lane [0:MAX_OBJ-1];
reg [XOFF_BITS    -1:0] obj_xoff [0:MAX_OBJ-1];
reg [OBJ_TYPE_BITS-1:0] obj_type [0:MAX_OBJ-1];
reg [OBJ_Y_BITS   -1:0] obj_ypos [0:MAX_OBJ-1];
reg [4:0] obj_count;
reg [1:0] state;

reg [5:0] sec_cnt;
reg [7:0] spawn_cnt;
reg btn_start_q;

wire btn_start_rise = btn_start && !btn_start_q;
wire can_left = player_x > player_speed;
wire can_right = player_x + player_speed < PLAYER_MAX_X;
wire pause;

wire [9:0] spawn_data;
wire spawn_fifo_empty;
wire obj_has_room = obj_count < MAX_OBJ;
wire remove_valid;
wire spawn_pop = frame_tick && state == S_PLAY && !pause &&
				  spawn_cnt == 0 && !spawn_fifo_empty &&
				  (obj_has_room || remove_valid);

assign pause = 0;
assign obj_ready = obj_has_room;
assign game_over = state == S_OVER;

spawn_queue u_spawn_queue (
	.clk(clk),
	.resetn(resetn),
	.enable(state == S_PLAY && !pause),
	.pop(spawn_pop),
	.spawn_data(spawn_data),
	.empty(spawn_fifo_empty)
);

integer hit_i;
reg hit_valid;
reg [4:0] hit_idx;
reg [9:0] hit_obj_x;

function [9:0] obj_x;
	input [LANE_BITS-1:0] lane;
	input [XOFF_BITS-1:0] xoff;
	begin obj_x = GAME_X0 + ({6'd0, lane} << 5) + {6'd0, xoff}; end
endfunction

always @(*) begin
	hit_valid = 0;
	hit_idx = 0;
	hit_obj_x = 0;

	for (hit_i = 0; hit_i < MAX_OBJ; hit_i = hit_i + 1) begin
		hit_obj_x = obj_x(obj_lane[hit_i], obj_xoff[hit_i]);
		if (!hit_valid && hit_i < obj_count &&
			player_x < hit_obj_x + OBJ_W &&
			player_x + PLAYER_WIDTH > hit_obj_x &&
			PLAYER_Y < obj_ypos[hit_i] + OBJ_H &&
			PLAYER_Y + PLAYER_HEIGHT > obj_ypos[hit_i]) begin
			hit_valid = 1;
			hit_idx = hit_i[4:0];
		end
	end
end

wire ground_valid = (obj_count != 0) && (obj_ypos[0] >= OBJ_GROUND_Y);
assign remove_valid = hit_valid || ground_valid;
wire [4:0] remove_idx = hit_valid ? hit_idx : 0;

reg [13:0] next_score;
wire [13:0] final_score = hit_valid ? next_score : score;

always @(*) begin
	next_score = score;
	if (hit_valid) begin
		case (obj_type[hit_idx])
			TYPE_COIN_1: next_score = score + 1;
			TYPE_COIN_3: next_score = score + 3;
			TYPE_COIN_5: next_score = score + 5;
			TYPE_MINUS5: next_score = score >= 5 ? score - 5 : 0;
			default: next_score = score;
		endcase
	end
end

integer pack_i;

always @(*) begin
	obj_valid_bus = 0;
	obj_lane_bus = 0;
	obj_xoff_bus = 0;
	obj_ypos_bus = 0;
	obj_type_bus = 0;

	for (pack_i = 0; pack_i < MAX_OBJ; pack_i = pack_i + 1) begin
		if (pack_i < obj_count) begin
			obj_valid_bus[pack_i] = 1;
			obj_lane_bus[pack_i*LANE_BITS     +: LANE_BITS]     = obj_lane[pack_i];
			obj_xoff_bus[pack_i*XOFF_BITS     +: XOFF_BITS]     = obj_xoff[pack_i];
			obj_ypos_bus[pack_i*OBJ_Y_BITS    +: OBJ_Y_BITS]    = obj_ypos[pack_i];
			obj_type_bus[pack_i*OBJ_TYPE_BITS +: OBJ_TYPE_BITS] = obj_type[pack_i];
		end
	end
end

integer i;

always @(posedge clk) begin
	if (!resetn) begin
		player_x <= PLAYER_START_X;
		player_speed <= PLAYER_SPEED_START;
		player_dir <= 1;
		obj_count <= 0;
		timer <= TIMER_START;
		score <= 0;
		high_score <= HIGH_SCORE_START;
		state <= S_PLAY;
		sec_cnt <= 0;
		spawn_cnt <= SPAWN_PERIOD_FRAMES;
		btn_start_q <= 0;

		for (i = 0; i < MAX_OBJ; i = i + 1) begin
			obj_lane[i] <= 0;
			obj_xoff[i] <= 0;
			obj_ypos[i] <= 0;
			obj_type[i] <= 0;
		end
	end else begin
		btn_start_q <= btn_start;

		if (btn_start_rise) begin
			player_x <= PLAYER_START_X;
			player_speed <= PLAYER_SPEED_START;
			player_dir <= 1;
			obj_count <= 0;
			timer <= TIMER_START;
			score <= 0;
			state <= S_PLAY;
			sec_cnt <= 0;
			spawn_cnt <= SPAWN_PERIOD_FRAMES;

			for (i = 0; i < MAX_OBJ; i = i + 1) begin
				obj_lane[i] <= 0;
				obj_xoff[i] <= 0;
				obj_ypos[i] <= 0;
				obj_type[i] <= 0;
			end
		end else if (frame_tick) begin
			if (state == S_PLAY && !pause) begin

				// Direction control
				if (btn_left && !btn_right) begin
					if (can_left)
						player_x <= player_x - player_speed;
					else
						player_x <= 0;
					player_dir <= 0;
				end else if (btn_right && !btn_left) begin
					if (can_right)
						player_x <= player_x + player_speed;
					else
						player_x <= PLAYER_MAX_X;
					player_dir <= 1;
				end

				// Score update
				if (hit_valid) begin
					score <= next_score;
				end

				// Object falling and spawning
				if (remove_valid) begin
					for (i = 0; i < MAX_OBJ-1; i = i + 1) begin
						if (i < obj_count - 1) begin
							if (i < remove_idx) begin
								obj_ypos[i] <= obj_ypos[i] + FALL_SPEED;
							end else begin
								obj_lane[i] <= obj_lane[i+1];
								obj_xoff[i] <= obj_xoff[i+1];
								obj_type[i] <= obj_type[i+1];
								obj_ypos[i] <= obj_ypos[i+1] + FALL_SPEED;
							end
						end
					end

					if (spawn_pop) begin
						obj_lane[obj_count - 1] <= spawn_data[9:6];
						obj_xoff[obj_count - 1] <= spawn_data[5:2];
						obj_type[obj_count - 1] <= spawn_data[1:0];
						obj_ypos[obj_count - 1] <= 0;
						obj_count <= obj_count;
					end else begin
						obj_count <= obj_count - 1;
					end
				end else begin
					for (i = 0; i < MAX_OBJ; i = i + 1) begin
						if (i < obj_count)
							obj_ypos[i] <= obj_ypos[i] + FALL_SPEED;
					end

					if (spawn_pop) begin
						obj_lane[obj_count] <= spawn_data[9:6];
						obj_xoff[obj_count] <= spawn_data[5:2];
						obj_type[obj_count] <= spawn_data[1:0];
						obj_ypos[obj_count] <= 0;
						obj_count <= obj_count + 1;
					end
				end

				if (spawn_pop)
					spawn_cnt <= SPAWN_PERIOD_FRAMES - 1;
				else if (spawn_cnt != 0)
					spawn_cnt <= spawn_cnt - 1;

				if (sec_cnt == 59) begin
					sec_cnt <= 0;

					if (timer > 1) begin
						timer <= timer - 1;
					end else begin
						timer <= 0;
						state <= S_OVER;
						if (final_score > high_score)
							high_score <= final_score;
					end
				end else begin
					sec_cnt <= sec_cnt + 1;
				end
			end
		end
	end
end
endmodule
