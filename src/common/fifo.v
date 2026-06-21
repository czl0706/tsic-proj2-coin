`timescale 1ns / 1ps

module fifo #(
	parameter WIDTH = 10,
	parameter DEPTH = 4,
	parameter ADDR_W = 2
) (
	input wire clk,
	input wire resetn,

	input wire wr_en,
	input wire [WIDTH-1:0] wr_data,
	output wire full,

	input wire rd_en,
	output wire [WIDTH-1:0] rd_data,
	output wire empty,

	output wire [ADDR_W:0] level
);
	reg [WIDTH-1:0] mem [0:DEPTH-1];
	reg [ADDR_W-1:0] wr_ptr;
	reg [ADDR_W-1:0] rd_ptr;
	reg [ADDR_W:0] count;
	localparam [ADDR_W:0] DEPTH_VALUE = DEPTH;

	assign full = count == DEPTH_VALUE;
	assign empty = count == 0;
	assign level = count;
	assign rd_data = mem[rd_ptr];

	always @(posedge clk) begin
		if (!resetn) begin
			wr_ptr <= {ADDR_W{1'b0}};
			rd_ptr <= {ADDR_W{1'b0}};
			count <= {(ADDR_W+1){1'b0}};
		end else begin
			if (wr_en && !full) begin
				mem[wr_ptr] <= wr_data;
				wr_ptr <= wr_ptr + 1'b1;
			end

			if (rd_en && !empty)
				rd_ptr <= rd_ptr + 1'b1;

			case ({wr_en && !full, rd_en && !empty})
				2'b10: count <= count + 1'b1;
				2'b01: count <= count - 1'b1;
				default: count <= count;
			endcase
		end
	end
endmodule
