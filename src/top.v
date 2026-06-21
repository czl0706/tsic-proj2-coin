module top (
    input clk,
    input resetn,
    input btn_left,
    input btn_right,
    input btn_start,

    output       tmds_clk_n,
    output       tmds_clk_p,
    output [2:0] tmds_d_n,
    output [2:0] tmds_d_p
);

wire clk_p;
wire clk_p5;
wire pll_lock;
wire sys_resetn;

wire btn_left_sync;
wire btn_right_sync;
wire btn_start_sync;

wire btn_left_level;
wire btn_right_level;
wire btn_start_level;

wire game_tvalid;
wire game_tready;
wire [23:0] game_tdata;
wire [0:0] game_tuser;

Gowin_CLKDIV u_div_5 (
    .clkout(clk_p),
    .hclkin(clk_p5),
    .resetn(pll_lock)
);

Gowin_PLLVR Gowin_PLLVR_inst(
    .clkout(clk_p5),
    .lock(pll_lock),
    .clkin(clk)
);

Reset_Sync u_Reset_Sync (
  .resetn(sys_resetn),
  .ext_reset(resetn & pll_lock),
  .clk(clk_p)
);

ff_sync #(
    .RESET_VALUE(1'b1)
) u_btn_left_sync (
    .clk(clk_p),
    .resetn(sys_resetn),
    .async_in(btn_left),
    .sync_out(btn_left_sync)
);

ff_sync #(
    .RESET_VALUE(1'b1)
) u_btn_right_sync (
    .clk(clk_p),
    .resetn(sys_resetn),
    .async_in(btn_right),
    .sync_out(btn_right_sync)
);

ff_sync #(
    .RESET_VALUE(1'b1)
) u_btn_start_sync (
    .clk(clk_p),
    .resetn(sys_resetn),
    .async_in(btn_start),
    .sync_out(btn_start_sync)
);

debounce #(
    .ACTIVE_LOW(1)
) u_btn_left_debounce (
    .clk(clk_p),
    .resetn(sys_resetn),
    .sig_in(btn_left_sync),
    .sig_out(btn_left_level)
);

debounce #(
    .ACTIVE_LOW(1)
) u_btn_right_debounce (
    .clk(clk_p),
    .resetn(sys_resetn),
    .sig_in(btn_right_sync),
    .sig_out(btn_right_level)
);

debounce #(
    .ACTIVE_LOW(1)
) u_btn_start_debounce (
    .clk(clk_p),
    .resetn(sys_resetn),
    .sig_in(btn_start_sync),
    .sig_out(btn_start_level)
);

game_core #(
    .SVO_MODE("640x480V")
) u_game_core (
    .clk(clk_p),
    .resetn(sys_resetn),

    .btn_left(btn_left_level),
    .btn_right(btn_right_level),
    .btn_start(btn_start_level),

    .out_axis_tvalid(game_tvalid),
    .out_axis_tready(game_tready),
    .out_axis_tdata(game_tdata),
    .out_axis_tuser(game_tuser)
);

svo_hdmi #(
    .SVO_MODE("640x480V")
) svo_hdmi_inst (
	.resetn(sys_resetn),

	// video clocks
	.clk_pixel(clk_p),
	.clk_5x_pixel(clk_p5),
	.locked(pll_lock),

    // input video stream
	.in_axis_tvalid(game_tvalid),
	.in_axis_tready(game_tready),
	.in_axis_tdata(game_tdata),
	.in_axis_tuser(game_tuser),

	// output signals
	.tmds_clk_n(tmds_clk_n),
	.tmds_clk_p(tmds_clk_p),
	.tmds_d_n(tmds_d_n),
	.tmds_d_p(tmds_d_p)
);

endmodule

module Reset_Sync (
    input clk,
    input ext_reset,
    output resetn
);

reg [3:0] reset_cnt = 0;

always @(posedge clk or negedge ext_reset) begin
    if (~ext_reset)
        reset_cnt <= 4'b0;
    else
        reset_cnt <= reset_cnt + !resetn;
end

assign resetn = &reset_cnt;

endmodule
