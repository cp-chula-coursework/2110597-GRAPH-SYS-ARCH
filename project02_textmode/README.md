# AX7010 Text Mode Display (2nd Project)

An 80x30 hardwired text-mode display over HDMI for the course's "Text mode
display" assignment (06_Text_Mode_Display.pdf): no CPU, no software - a font
ROM, character tile RAM, and a rendering pipeline in pure Verilog, with an
interactive demo on top.

The demo combines two of the assignment's suggested examples:

- **Text editor** - a blinking block cursor moves over the 80x30 grid and
  the character under it is cycled with two buttons, like entering initials
  on an arcade high-score screen. Held buttons auto-repeat (typematic), and
  holding both cycle buttons for 1 second clears the screen.
- **Matrix screensaver** - after ~20 seconds without input, the classic
  digital rain takes over: 80 independent falling streams with bright heads,
  mutating tails, random speeds and restarts. Any button press returns to
  the editor - **with the text exactly as it was left**, because the rain
  animates in its own tile RAM and never touches the editor's.

## Adaptations from the course slides

Two board-driven adaptations, with the taught architecture kept as-is:

- **VGA -> HDMI** (as in [`../project01_pong`](../project01_pong)): the
  slides' reference design outputs VGA; the AX7010 only has HDMI. The
  standard `vga_timing.v` + `hdmi_tx.v`/`tmds_encoder.v`/`oserdes_tmds.v`
  pipeline from the demo/Pong projects is reused unchanged.
- **PS/2 keyboard -> push buttons**: the slides' reference design takes
  input from a Basys3's PS/2 keyboard port. The AX7010 has no keyboard
  connector (and USB-host would need a CPU + software stack, which the
  course forbids), so the input stage becomes the board's 4 push buttons
  with debounce + typematic repeat - everything downstream of the input
  stage matches the slides' text_screen_gen structure.

## Architecture (per the slides' Text Mode v1)

```
                 x,y,syncs                 addr        {bright,ascii}
  vga_timing  ------------->  text_renderer ----> tile RAM (80x30x8, BRAM,
   640x480@60                  |    ^ 2-clk        dual-port, 1-clk read)
                               |    | pipeline       ^ write   ^ write
                               v    |                |         |
                            font_rom (8x16,     text_editor  matrix_rain
                            2048x8 BRAM,           ^              ^
                            1-clk read)         buttons      LFSR + vblank
                                                                sweep
```

- **`font_rom.v`** - the slides' `ascii_rom`: address = `{char[6:0],
  row[3:0]}` (11 bits), data = one 8-pixel glyph row. Glyphs are the classic
  IBM VGA 8x16 font, extracted from the Linux console font `Lat15-VGA16` by
  `scripts/gen_font_rom.py` (rerun it to regenerate). Registered address +
  full `case` infers one RAMB18.
- **`tile_ram.v`** - the slides' "simple dual port ram: 80col x 30row, 1 clk
  delay": 2400 cells of `{bright, ascii[6:0]}`. Two instances: editor text
  and screensaver.
- **`text_renderer.v`** - the slides' `text_screen_gen`: tile fetch (1 clk)
  -> font fetch (1 clk) -> pick the glyph bit. The slides' Basys3 design
  runs logic at 100 MHz (4x the pixel rate) so it can ignore this latency;
  here everything runs at the 25.175 MHz pixel clock, so the sync/blank
  flags ride the same 2-stage pipeline and leave aligned with the RGB (the
  frame is just shifted 2 pixel clocks - invisible). The cursor inverts its
  cell's pixels, blinking at ~2 Hz, per the slides.
- **`text_editor.v`** - cursor registers + character cycling + clear sweep.
  Cycling needs to read the cell under the cursor, but the RAM's read port
  belongs to the renderer - which only needs it during active video. So the
  editor borrows the read port during blanking intervals to keep a copy of
  the cursor cell (a poor man's third port; refreshed every scanline).
- **`matrix_rain.v`** - per-column stream state (head row, speed, timer)
  updated by a sequential sweep once per frame, triggered at the start of
  vertical blanking (~400 clocks, vblank is ~28000). Randomness from one
  free-running 17-bit maximal LFSR.
- **`button_input.v`** - 2-FF synchronizer, 5 ms counter debounce,
  press-edge detect, and keyboard-style typematic repeat (first repeat after
  0.5 s, then 15 Hz).
- **`text_system.v`** - wires the above together with the editor/screensaver
  mode logic; `top.v` adds the Clocking Wizard and the HDMI/TMDS output
  stage.

## Controls

The board's 4 push buttons (active-low):

| Button | Pin | Function |
|--------|-----|----------|
| key[0] | N15 | Cursor right (wraps to next line, then to top) |
| key[1] | N16 | Cursor down (wraps to top) |
| key[2] | T17 | Next character (space -> A -> B ... -> ~ -> space) |
| key[3] | R17 | Previous character (space -> ~ -> } ... -> ! -> space) |

- Hold any button to auto-repeat.
- Hold **key[2] + key[3]** together for ~1 s to clear the screen.
- Leave the board alone for ~20 s and the Matrix screensaver starts; press
  any button to return to your text (the waking press types nothing).

## Verification

Before targeting hardware, everything below the clocking IP / TMDS output
was simulated with Icarus Verilog:

- `sim/tb_font_rom.v` dumps all 95 printable glyphs as ASCII art
  (`font_dump.txt`) - eyeballed against the real VGA font.
- `sim/tb_text_system.v` simulates the complete core rendering real 640x480
  frames, drives scripted presses through the debouncer, and checks via
  hierarchical references: the power-up clear sweep, character cycling both
  directions, cursor movement/wrap, typematic auto-repeat, hold-to-clear,
  the idle timeout into screensaver mode, that the rain draws (and the
  editor RAM stays untouched), and that a button press wakes the editor with
  the waking press consumed. It also dumps one editor frame and one
  screensaver frame as PPM images for visual inspection.
- The full `top.v` hierarchy elaborates cleanly under `iverilog`; the only
  unknown modules are Xilinx's `OSERDESE2`/`OBUFDS` and the Vivado-generated
  `clk_wiz_video` IP, as expected outside Vivado.

Run them from the project root:

```sh
iverilog -o /tmp/tb_font.vvp hdl/font_rom.v sim/tb_font_rom.v && vvp /tmp/tb_font.vvp
iverilog -o /tmp/tb_sys.vvp hdl/vga_timing.v hdl/font_rom.v hdl/tile_ram.v \
  hdl/text_renderer.v hdl/button_input.v hdl/text_editor.v hdl/matrix_rain.v \
  hdl/text_system.v sim/tb_text_system.v && vvp /tmp/tb_sys.vvp
```

This does not replace testing on real hardware - build the project and
confirm it works on an HDMI display before submitting.

## Building the project

From a terminal, with Vivado on your `PATH`:

```sh
cd project02_textmode
vivado -mode batch -source scripts/create_project.tcl
```

This creates a Vivado project under `project02_textmode/vivado_project/`
(git-ignored) with all sources, constraints, and the clocking IP added. It
does not run synthesis. Open the generated project in the Vivado GUI, then:

1. Run Synthesis
2. Run Implementation
3. Generate Bitstream
4. Open Hardware Manager, connect to the board (JTAG), and program the device

If you'd rather create the Clocking Wizard IP by hand in the GUI instead of
running the script: component name `clk_wiz_video`, input clock 50 MHz on
`clk_in1`, enable `clk_out1` = 25.175 MHz and `clk_out2` = 125.875 MHz.

## Still needed for submission

The assignment asks for: the Verilog code (this project), a video recording
of the hardware running, and a written explanation of the hardware. The
video and writeup aren't part of this repo - happy to help draft the writeup
once the design is confirmed working on the board.
