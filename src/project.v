/*
 * Copyright (c) 2024 Renaldas Zioma (original checker demo)
 * Modified: floating checker boxes replaced with "OzelHD" text
 * Same animation offsets, same color system, same layer compositing.
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none

module tt_um_vga_example(
  input  wire [7:0] ui_in,
  output wire [7:0] uo_out,
  input  wire [7:0] uio_in,
  output wire [7:0] uio_out,
  output wire [7:0] uio_oe,
  input  wire       ena,
  input  wire       clk,
  input  wire       rst_n
);

  // ── Font ROM ─────────────────────────────────────────────────────────────
  // "OzelHD" in an 8x8 pixel font, 2px spacing, total 58px wide.
  // Padded to 64px wide so column index = rx[shift+5:shift] (free bit-select).
  // Bit [63 - col] = pixel at column col.
  localparam [63:0] FONT_ROW0 = 64'h3C00000000C33F00;
  localparam [63:0] FONT_ROW1 = 64'h6600000000C33180;
  localparam [63:0] FONT_ROW2 = 64'hC33F83C300C330C0;
  localparam [63:0] FONT_ROW3 = 64'hC303066300FF30C0;
  localparam [63:0] FONT_ROW4 = 64'hC30C0FE300C330C0;
  localparam [63:0] FONT_ROW5 = 64'hC3180C0300C330C0;
  localparam [63:0] FONT_ROW6 = 64'h663F87C3F8C33180;
  localparam [63:0] FONT_ROW7 = 64'h3C00000000003F00;

  function automatic font_pixel;
    input [5:0] col;
    input [2:0] row;
    reg [63:0] rd;
    begin
      case (row)
        3'd0: rd = FONT_ROW0;
        3'd1: rd = FONT_ROW1;
        3'd2: rd = FONT_ROW2;
        3'd3: rd = FONT_ROW3;
        3'd4: rd = FONT_ROW4;
        3'd5: rd = FONT_ROW5;
        3'd6: rd = FONT_ROW6;
        3'd7: rd = FONT_ROW7;
        default: rd = 64'd0;
      endcase
      font_pixel = rd[63 - col];
    end
  endfunction

  // ── VGA ──────────────────────────────────────────────────────────────────
  wire hsync, vsync;
  wire [1:0] R, G, B;
  wire video_active;
  wire [9:0] pix_x, pix_y;

  assign uo_out  = {hsync, B[0], G[0], R[0], vsync, B[1], G[1], R[1]};
  assign uio_out = 0;
  assign uio_oe  = 0;
  wire _unused_ok = &{ena, ui_in, uio_in};

  hvsync_generator hvsync_gen(
    .clk(clk), .reset(~rst_n),
    .hsync(hsync), .vsync(vsync),
    .display_on(video_active),
    .hpos(pix_x), .vpos(pix_y)
  );

  // ── Frame counter (identical to original) ────────────────────────────────
  reg [9:0] counter;
  always @(posedge vsync, negedge rst_n) begin
    if (~rst_n) counter <= 0;
    else        counter <= counter + 1;
  end

  // ── Scroll offsets (identical to original) ────────────────────────────────
  wire [9:0] layer_a_ox = counter * 10'd16;
  wire [9:0] layer_a_oy = counter * 10'd2;

  wire [9:0] layer_b_ox = counter * 10'd7;
  wire [9:0] layer_b_oy = counter + (counter >> 1);

  wire [9:0] layer_c_ox = counter * 10'd4;
  wire [9:0] layer_c_oy = counter >> 1;

  wire [9:0] layer_d_ox = counter * 10'd2;
  wire [9:0] layer_d_oy = counter >> 2;

  wire [9:0] layer_e_ox = counter >> 1;
  wire [9:0] layer_e_oy = counter / 10'd6;

  // ── Text layers ───────────────────────────────────────────────────────────
  // Scales reduced vs prior version so multiple copies tile across the screen:
  //   Layer A: scale=8  → tile every 512px (~1-2 copies visible)
  //   Layer B: scale=4  → tile every 256px (~2-3 copies visible)
  //   Layer C: scale=2  → tile every 128px (~5 copies visible)
  //   Layer D: scale=2  → tile every 128px (~5 copies visible)
  //   Layer E: scale=1  → tile every  64px (~10 copies visible)
  //
  // Column tiling is free: col = rx[shift+5:shift] naturally wraps at 64.
  // Row valid check: row bits [2:0] from ty after shift, guard ty < 8*scale.

  // ── Layer A (scale=8, shift=3, centre Y=120) ─────────────────────────────
  wire [9:0] la_rx = pix_x + layer_a_ox;
  wire [9:0] la_ry = pix_y + layer_a_oy;
  wire [9:0] la_ty = la_ry - 10'd56;        // centre(120) - half-height(64) = 56
  wire [5:0] la_col = la_rx[8:3];
  wire [5:0] la_row6 = la_ty[8:3];
  wire       layer_a = (la_ty < 10'd64) & (la_row6 < 6'd8)
                       & font_pixel(la_col, la_row6[2:0])
                       & (pix_y[1] ^ pix_x[0]);

  // ── Layer B (scale=4, shift=2, centre Y=200) ─────────────────────────────
  wire [9:0] lb_rx = pix_x + layer_b_ox;
  wire [9:0] lb_ry = pix_y + layer_b_oy;
  wire [9:0] lb_ty = lb_ry - 10'd184;       // 200 - 16 = 184
  wire [5:0] lb_col = lb_rx[7:2];
  wire [5:0] lb_row6 = lb_ty[7:2];
  wire       layer_b = (lb_ty < 10'd32) & (lb_row6 < 6'd8)
                       & font_pixel(lb_col, lb_row6[2:0])
                       & (~pix_y[0] ^ pix_x[1]);

  // ── Layer C (scale=2, shift=1, centre Y=248) ─────────────────────────────
  wire [9:0] lc_rx = pix_x + layer_c_ox;
  wire [9:0] lc_ry = pix_y + layer_c_oy;
  wire [9:0] lc_ty = lc_ry - 10'd240;       // 248 - 8 = 240
  wire [5:0] lc_col = lc_rx[6:1];
  wire [5:0] lc_row6 = lc_ty[6:1];
  wire       layer_c = (lc_ty < 10'd16) & (lc_row6 < 6'd8)
                       & font_pixel(lc_col, lc_row6[2:0]);

  // ── Layer D (scale=2, shift=1, centre Y=268) ─────────────────────────────
  wire [9:0] ld_rx = pix_x + layer_d_ox;
  wire [9:0] ld_ry = pix_y + layer_d_oy;
  wire [9:0] ld_ty = ld_ry - 10'd260;       // 268 - 8 = 260
  wire [5:0] ld_col = ld_rx[6:1];
  wire [5:0] ld_row6 = ld_ty[6:1];
  wire       layer_d = (ld_ty < 10'd16) & (ld_row6 < 6'd8)
                       & font_pixel(ld_col, ld_row6[2:0]);

  // ── Layer E (scale=1, shift=0, centre Y=284) ─────────────────────────────
  wire [9:0] le_rx = pix_x + layer_e_ox;
  wire [9:0] le_ry = pix_y + layer_e_oy;
  wire [9:0] le_ty = le_ry - 10'd280;       // 284 - 4 = 280
  wire [5:0] le_col = le_rx[5:0];
  wire [5:0] le_row6 = le_ty[5:0];
  wire       layer_e = (le_ty < 10'd8) & (le_row6 < 6'd8)
                       & font_pixel(le_col, le_row6[2:0])
                       & (pix_y[1] ^ pix_x[0]);

  // ── Colors (identical to original) ───────────────────────────────────────
  wire [5:0] color_a  = ~ui_in[5:0];
  wire [5:0] color_b  = color_a ^ 6'b00_10_10;
  wire [5:0] color_c  = color_b & 6'b10_10_10;
  wire [5:0] color_de = color_c >> 1;

  // ── Composite (identical priority to original) ────────────────────────────
  assign {R, G, B} =
    video_active ?
      (layer_a ? color_a  :
      (layer_b ? color_b  :
      (layer_c ? color_c  :
      (layer_d ? color_de :
      (layer_e ? color_de : 6'b00_00_00))))) : 6'b00_00_00;

endmodule