`timescale 1ns / 1ps

module game_ctrl #(
	parameter MAX_OBJ = 16,
	parameter LANE_BITS = 4,
	parameter X_BIAS_BITS = 4,
	parameter OBJ_TYPE_BITS = 2,
	parameter OBJ_Y_BITS = 10,
	parameter FALL_SPEED = 2,
	parameter SPAWN_PERIOD_FRAMES = 24,
	parameter PLAYER_WIDTH = 64,
	parameter PLAYER_HEIGHT = 64,
	parameter PLAYER_START_X = 288,
	parameter PLAYER_SPEED_START = 8,
	parameter TIMER_START = 30,
	parameter HIGH_SCORE_START = 0
)(
	input clk,
	input resetn,
	input frame_tick,

	input btn_left,
	input btn_right,
	input btn_start,

	output spawn_valid,

	output reg [9:0] player_x,
	output reg [5:0] player_speed,
	output reg player_facing_right,

	output reg [MAX_OBJ-1:0] obj_active_bus,
	output reg [MAX_OBJ*LANE_BITS-1:0] obj_lane_bus,
	output reg [MAX_OBJ*X_BIAS_BITS-1:0] obj_x_bias_bus,
	output reg [MAX_OBJ*OBJ_Y_BITS-1:0] obj_y_bus,
	output reg [MAX_OBJ*OBJ_TYPE_BITS-1:0] obj_type_bus,

	output reg [9:0] timer_value,
	output reg [13:0] score_value,
	output reg [13:0] high_score_value,
	output reg [1:0] game_state
);
	localparam GAME_IDLE = 2'd0;
	localparam GAME_PLAYING = 2'd1;
	localparam GAME_GAMEOVER = 2'd2;

	localparam TYPE_COIN_1 = 2'd0;
	localparam TYPE_COIN_3 = 2'd1;
	localparam TYPE_COIN_5 = 2'd2;
	localparam TYPE_MINUS5 = 2'd3;

	localparam [9:0] SCREEN_W = 10'd640;
	localparam [9:0] GAME_X0 = 10'd64;
	localparam [9:0] UI_TOP = 10'd416;
	localparam [9:0] OBJ_W = 10'd32;
	localparam [9:0] OBJ_H = 10'd32;
	localparam [9:0] OBJ_GROUND_Y = UI_TOP - OBJ_H;
	localparam [9:0] PLAYER_Y = 10'd352;
	localparam [9:0] PLAYER_WIDTH_VALUE = PLAYER_WIDTH;
	localparam [9:0] PLAYER_HEIGHT_VALUE = PLAYER_HEIGHT;
	localparam [9:0] PLAYER_START_X_INIT = PLAYER_START_X;
	localparam [9:0] PLAYER_MAX_X = SCREEN_W - PLAYER_WIDTH_VALUE;
	localparam [5:0] PLAYER_SPEED_INIT = PLAYER_SPEED_START;
	localparam [OBJ_Y_BITS-1:0] FALL_SPEED_VALUE = FALL_SPEED;
	localparam [7:0] SPAWN_PERIOD_INIT = SPAWN_PERIOD_FRAMES;

	reg [LANE_BITS-1:0] obj_lane [0:MAX_OBJ-1];
	reg [X_BIAS_BITS-1:0] obj_x_bias [0:MAX_OBJ-1];
	reg [OBJ_TYPE_BITS-1:0] obj_type [0:MAX_OBJ-1];
	reg [OBJ_Y_BITS-1:0] obj_y [0:MAX_OBJ-1];
	reg [4:0] obj_count;

	reg [5:0] frame_count;
	reg [7:0] spawn_timer;
	reg btn_start_q;

	wire btn_start_rise = btn_start && !btn_start_q;
	wire player_can_move_left = player_x > player_speed;
	wire player_can_move_right = player_x + player_speed < PLAYER_MAX_X;

	wire [9:0] spawn_packet;
	wire spawn_fifo_empty;
	wire spawn_fifo_full;
	wire [2:0] spawn_fifo_level;
	wire obj_queue_ready = obj_count < MAX_OBJ;
	wire remove_valid;
	wire spawn_fire = frame_tick && game_state == GAME_PLAYING &&
	                  spawn_timer == 8'd0 && !spawn_fifo_empty &&
	                  (obj_queue_ready || remove_valid);

	assign spawn_valid = obj_queue_ready;

	spawn_queue u_spawn_queue (
		.clk(clk),
		.resetn(resetn),
		.enable(game_state == GAME_PLAYING),
		.pop(spawn_fire),
		.packet(spawn_packet),
		.empty(spawn_fifo_empty),
		.full(spawn_fifo_full),
		.level(spawn_fifo_level)
	);

	integer hit_i;
	reg hit_valid;
	reg [4:0] hit_idx;
	reg [9:0] hit_obj_x;

	always @(*) begin
		hit_valid = 1'b0;
		hit_idx = 5'd0;
		hit_obj_x = 10'd0;

		for (hit_i = 0; hit_i < MAX_OBJ; hit_i = hit_i + 1) begin
			hit_obj_x = GAME_X0 + ({6'd0, obj_lane[hit_i]} << 5) + {6'd0, obj_x_bias[hit_i]};
			if (!hit_valid && hit_i < obj_count &&
			    player_x < hit_obj_x + OBJ_W &&
			    player_x + PLAYER_WIDTH_VALUE > hit_obj_x &&
			    PLAYER_Y < obj_y[hit_i] + OBJ_H &&
			    PLAYER_Y + PLAYER_HEIGHT_VALUE > obj_y[hit_i]) begin
				hit_valid = 1'b1;
				hit_idx = hit_i[4:0];
			end
		end
	end

	wire ground_valid = obj_count != 0 && obj_y[0] >= OBJ_GROUND_Y;
	assign remove_valid = hit_valid || ground_valid;
	wire [4:0] remove_idx = hit_valid ? hit_idx : 5'd0;

	reg [13:0] score_after_hit;
	wire [13:0] score_for_gameover = hit_valid ? score_after_hit : score_value;

	always @(*) begin
		score_after_hit = score_value;
		if (hit_valid) begin
			case (obj_type[hit_idx])
				TYPE_COIN_1: score_after_hit = score_value + 14'd1;
				TYPE_COIN_3: score_after_hit = score_value + 14'd3;
				TYPE_COIN_5: score_after_hit = score_value + 14'd5;
				TYPE_MINUS5: score_after_hit = score_value >= 14'd5 ? score_value - 14'd5 : 14'd0;
				default: score_after_hit = score_value;
			endcase
		end
	end

	integer pack_i;

	always @(*) begin
		obj_active_bus = {MAX_OBJ{1'b0}};
		obj_lane_bus = {(MAX_OBJ*LANE_BITS){1'b0}};
		obj_x_bias_bus = {(MAX_OBJ*X_BIAS_BITS){1'b0}};
		obj_y_bus = {(MAX_OBJ*OBJ_Y_BITS){1'b0}};
		obj_type_bus = {(MAX_OBJ*OBJ_TYPE_BITS){1'b0}};

		for (pack_i = 0; pack_i < MAX_OBJ; pack_i = pack_i + 1) begin
			if (pack_i < obj_count) begin
				obj_active_bus[pack_i] = 1'b1;
				obj_lane_bus[pack_i*LANE_BITS +: LANE_BITS] = obj_lane[pack_i];
				obj_x_bias_bus[pack_i*X_BIAS_BITS +: X_BIAS_BITS] = obj_x_bias[pack_i];
				obj_y_bus[pack_i*OBJ_Y_BITS +: OBJ_Y_BITS] = obj_y[pack_i];
				obj_type_bus[pack_i*OBJ_TYPE_BITS +: OBJ_TYPE_BITS] = obj_type[pack_i];
			end
		end
	end

	integer i;

	always @(posedge clk) begin
		if (!resetn) begin
			player_x <= PLAYER_START_X_INIT;
			player_speed <= PLAYER_SPEED_INIT;
			player_facing_right <= 1'b1;
			obj_count <= 5'd0;
			timer_value <= TIMER_START;
			score_value <= 14'd0;
			high_score_value <= HIGH_SCORE_START;
			game_state <= GAME_PLAYING;
			frame_count <= 6'd0;
			spawn_timer <= SPAWN_PERIOD_INIT;
			btn_start_q <= 1'b0;

			for (i = 0; i < MAX_OBJ; i = i + 1) begin
				obj_lane[i] <= {LANE_BITS{1'b0}};
				obj_x_bias[i] <= {X_BIAS_BITS{1'b0}};
				obj_y[i] <= {OBJ_Y_BITS{1'b0}};
				obj_type[i] <= {OBJ_TYPE_BITS{1'b0}};
			end
		end else begin
			btn_start_q <= btn_start;

			if (btn_start_rise) begin
				player_x <= PLAYER_START_X_INIT;
				player_speed <= PLAYER_SPEED_INIT;
				player_facing_right <= 1'b1;
				obj_count <= 5'd0;
				timer_value <= TIMER_START;
				score_value <= 14'd0;
				game_state <= GAME_PLAYING;
				frame_count <= 6'd0;
				spawn_timer <= SPAWN_PERIOD_INIT;

				for (i = 0; i < MAX_OBJ; i = i + 1) begin
					obj_lane[i] <= {LANE_BITS{1'b0}};
					obj_x_bias[i] <= {X_BIAS_BITS{1'b0}};
					obj_y[i] <= {OBJ_Y_BITS{1'b0}};
					obj_type[i] <= {OBJ_TYPE_BITS{1'b0}};
				end
			end else if (frame_tick) begin
				if (game_state == GAME_PLAYING) begin
					if (btn_left && !btn_right) begin
						if (player_can_move_left)
							player_x <= player_x - player_speed;
						else
							player_x <= 10'd0;
						player_facing_right <= 1'b0;
					end else if (btn_right && !btn_left) begin
						if (player_can_move_right)
							player_x <= player_x + player_speed;
						else
							player_x <= PLAYER_MAX_X;
						player_facing_right <= 1'b1;
					end

					if (hit_valid) begin
						score_value <= score_after_hit;
					end

					if (remove_valid) begin
						for (i = 0; i < MAX_OBJ-1; i = i + 1) begin
							if (i < obj_count - 1) begin
								if (i < remove_idx) begin
									obj_lane[i] <= obj_lane[i];
									obj_x_bias[i] <= obj_x_bias[i];
									obj_type[i] <= obj_type[i];
									obj_y[i] <= obj_y[i] + FALL_SPEED_VALUE;
								end else begin
									obj_lane[i] <= obj_lane[i+1];
									obj_x_bias[i] <= obj_x_bias[i+1];
									obj_type[i] <= obj_type[i+1];
									obj_y[i] <= obj_y[i+1] + FALL_SPEED_VALUE;
								end
							end
						end

						if (spawn_fire) begin
							obj_lane[obj_count - 1] <= spawn_packet[9:6];
							obj_x_bias[obj_count - 1] <= spawn_packet[5:2];
							obj_type[obj_count - 1] <= spawn_packet[1:0];
							obj_y[obj_count - 1] <= {OBJ_Y_BITS{1'b0}};
							obj_count <= obj_count;
						end else begin
							obj_count <= obj_count - 1'b1;
						end
					end else begin
						for (i = 0; i < MAX_OBJ; i = i + 1) begin
							if (i < obj_count)
								obj_y[i] <= obj_y[i] + FALL_SPEED_VALUE;
						end

						if (spawn_fire) begin
							obj_lane[obj_count] <= spawn_packet[9:6];
							obj_x_bias[obj_count] <= spawn_packet[5:2];
							obj_type[obj_count] <= spawn_packet[1:0];
							obj_y[obj_count] <= {OBJ_Y_BITS{1'b0}};
							obj_count <= obj_count + 1'b1;
						end
					end

					if (spawn_fire)
						spawn_timer <= SPAWN_PERIOD_INIT - 1'b1;
					else if (spawn_timer != 8'd0)
						spawn_timer <= spawn_timer - 1'b1;

					if (frame_count == 6'd59) begin
						frame_count <= 6'd0;

						if (timer_value > 10'd1) begin
							timer_value <= timer_value - 10'd1;
						end else begin
							timer_value <= 10'd0;
							game_state <= GAME_GAMEOVER;
							if (score_for_gameover > high_score_value)
								high_score_value <= score_for_gameover;
						end
					end else begin
						frame_count <= frame_count + 6'd1;
					end
				end
			end
		end
	end
endmodule
