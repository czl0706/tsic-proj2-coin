`timescale 1ns / 1ps

module lfsr32 #(
	parameter [31:0] SEED = 32'hACE1_1234
) (
	input wire clk,
	input wire resetn,
	input wire en,
	output reg [31:0] rnd
);
	wire feedback = rnd[31] ^ rnd[21] ^ rnd[1] ^ rnd[0];

	always @(posedge clk) begin
		if (!resetn)
			rnd <= SEED == 32'd0 ? 32'h1 : SEED;
		else if (en)
			rnd <= {rnd[30:0], feedback};
	end
endmodule
