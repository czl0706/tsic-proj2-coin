`timescale 1ns / 1ps

module ff_sync #(
	parameter RESET_VALUE = 1'b0
) (
	input clk,
	input resetn,
	input async_in,
	output reg sync_out
);
	reg meta;

	always @(posedge clk) begin
		if (!resetn) begin
			meta <= RESET_VALUE;
			sync_out <= RESET_VALUE;
		end else begin
			meta <= async_in;
			sync_out <= meta;
		end
	end
endmodule
