`timescale 1ns / 1ps

module debounce #(
	parameter SAMPLE_CYCLES = 25175,
	parameter SAMPLE_BITS = 15,
	parameter HIST_BITS = 8,
	parameter ACTIVE_LOW = 1
) (
	input clk,
	input resetn,
	input sig_in,
	output reg sig_out
);
	reg [SAMPLE_BITS-1:0] sample_cnt;
	reg [HIST_BITS-1:0] hist;

	wire sample_tick = sample_cnt == SAMPLE_CYCLES - 1;
	wire sig_active = ACTIVE_LOW ? ~sig_in : sig_in;
	wire [HIST_BITS-1:0] hist_next = {hist[HIST_BITS-2:0], sig_active};

	always @(posedge clk) begin
		if (!resetn) begin
			sample_cnt <= {SAMPLE_BITS{1'b0}};
		end else if (sample_tick) begin
			sample_cnt <= {SAMPLE_BITS{1'b0}};
		end else begin
			sample_cnt <= sample_cnt + 1'b1;
		end
	end

	always @(posedge clk) begin
		if (!resetn) begin
			sig_out <= 1'b0;
			hist <= {HIST_BITS{1'b0}};
		end else if (sample_tick) begin
			hist <= hist_next;

			if (hist_next == {HIST_BITS{1'b1}})
				sig_out <= 1'b1;
			else if (hist_next == {HIST_BITS{1'b0}})
				sig_out <= 1'b0;
		end
	end
endmodule
