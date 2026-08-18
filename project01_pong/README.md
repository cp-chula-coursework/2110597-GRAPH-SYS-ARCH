# AX7010 Pong (1st Gen Console Project)

Single-player Pong vs. a simple AI paddle, for the course's "1st Gen game
console" assignment (05_PONG_History_and_Project.pdf): no CPU, no software -
just hardwired logic driving moving graphics from push-button input.

## Adaptation from the course slides: VGA -> HDMI

The slides target a board with a VGA connector. The AX7010 only has HDMI out
(no VGA DAC on this board/kit - confirmed against ALINX's own AX7010 course
examples, which only ever demo HDMI). The game logic and screen resolution
(640x480) are otherwise a direct port of the slides' code - only the final
output stage differs:

- Slides: `vga` timing generator embedded in the `pong` module, RGB driven
  straight onto a VGA DAC.
- Here: `vga_timing.v` is a standalone 640x480@60 timing generator (same
  role as the slides' `vga` module) whose x/y/HS/VS/blank feed `pong.v`;
  `top.v` then routes the resulting RGB through the same HDMI/TMDS pipeline
  built for [`../demo_test_pattern`](../demo_test_pattern) instead of a VGA
  connector.

## Controls

The board's 4 push buttons (active-low):

| Button | Pin | Function |
|--------|-----|----------|
| key[0] | N15 | Reset (new game, scores to 0) |
| key[1] | N16 | Move paddle up |
| key[2] | T17 | Move paddle down |
| key[3] | R17 | Unused (spare) |

You control the left paddle; the right paddle is a simple AI that tracks the
ball's vertical position.

## Extensions beyond the base slide code

The assignment asks to extend the base Pong with more functionality. This
project adds:

- **Score display** (`digit_font.v` + rendering in `pong.v`): a 5x7
  dot-matrix digit per player, drawn top-center, incrementing when the
  opposing paddle misses. Saturates at 9 (first to 9 effectively wins);
  `btn_reset` clears both scores.
- **Ball speedup** (`pong.v`): the slides declare a `SPEEDUP` parameter
  ("speed up ball after this many shots") but never wire it up. This
  implements it - every `SPEEDUP` (5) consecutive paddle hits in a rally,
  `ball_spx`/`ball_spy` each increase by 1, capped at `BALL_ISPX+4` /
  `BALL_ISPY+4` to stay well clear of the collision-detection math's safe
  range. Speed resets to the initial value at the start of each new point.
- **Center net line** (`pong.v`, the `net` signal): a dashed vertical line
  down the middle of the court, standard Pong background dressing.

Game logic, parameter names, and structure otherwise match the slides'
`pong` module (`part I` object/state/player-control code, `part II` ball
motion/collision and AI paddle code) as closely as the VGA->HDMI restructure
allows.

## Verification

Before targeting hardware:
- `digit_font.v` was simulated and its output dumped as ASCII art to confirm
  all 10 glyphs are legible digits.
- `pong.v` was simulated with `iverilog`/`vvp` driving realistic gameplay
  (a bang-bang paddle tracker toggled on/off through real `btn_up`/`btn_dn`
  inputs, not forced internal signals) for thousands of simulated frames,
  confirming: the speedup mechanic engages and respects its cap, scores
  increment on misses and saturate at 9, and `btn_reset` clears them.
- The full `top.v` hierarchy elaborates cleanly under `iverilog` (the only
  errors are for Xilinx's `OSERDESE2`/`OBUFDS` primitives and the
  Vivado-generated `clk_wiz_video` IP, neither of which exist outside
  Vivado/its simulator - expected and harmless).

This does not replace testing on real hardware - build the project and
confirm the game plays correctly on an HDMI display before submitting.

## Building the project

From a terminal, with Vivado on your `PATH`:

```sh
cd project01_pong
vivado -mode batch -source scripts/create_project.tcl
```

This creates a Vivado project under `project01_pong/vivado_project/` (git-ignored)
with all sources, constraints, and the clocking IP added. It does not run
synthesis. Open the generated project in the Vivado GUI, then:

1. Run Synthesis
2. Run Implementation
3. Generate Bitstream
4. Open Hardware Manager, connect to the board (JTAG), and program the device

If you'd rather create the Clocking Wizard IP by hand in the GUI instead of
running the script: component name `clk_wiz_video`, input clock 50 MHz on
`clk_in1`, enable `clk_out1` = 25.175 MHz and `clk_out2` = 125.875 MHz.

## Still needed for submission

The assignment asks for: the Verilog code (this project), a video recording
of the hardware running, and a 2-3 page document explaining how the hardware
works. The video and writeup aren't part of this repo - happy to help draft
the writeup once the design is confirmed working on the board.
