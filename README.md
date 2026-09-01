# 2110597 - Graphics System Architecture

Coursework for **2110597 (Graphics System Architecture)**, Chulalongkorn
University. The course studies how graphics hardware is built on FPGAs,
using the history of game consoles as the running case study: each project
recreates (and extends) the kind of hardwired, no-CPU graphics pipeline a
given console generation would have used, in real Verilog running on real
hardware.

## Hardware

All projects target the **ALINX AX7010** board:

- Zynq-7000 SoC, `XC7Z010-1CLG400C/I` (Vivado part `xc7z010clg400-1`)
- 50 MHz onboard oscillator (pin `U18`)
- Video output: **HDMI only** - no VGA DAC on this board. HDMI/TMDS is
  generated entirely in FPGA fabric (8b/10b encoding + OSERDESE2
  serialization), not offloaded to a dedicated PHY chip.
- 4 active-low push buttons available for input

All RTL in this repo is written in **plain Verilog** - no VHDL, no
third-party packaged IP beyond Vivado's own Clocking Wizard. Where course
material or reference designs assume a VGA connector, projects here
substitute an HDMI/TMDS output stage built from scratch instead.

## Repository layout

Each subfolder is a self-contained Vivado project (own `hdl/`,
`constraints/`, `scripts/create_project.tcl`, and `README.md`). Non-graded
exploratory work lives in plainly-named folders (e.g. `demo_test_pattern/`);
graded assignments follow a `projectNN_<name>` convention, and a second,
independent take on the same assignment gets a letter suffix
(`projectNNb_<name>`).

### `demo_test_pattern/` - HDMI bring-up demo

Before writing any game logic, this project exists to answer one question:
does the board's HDMI output actually work end-to-end? It drives a
1280x720@60 eight-colour bar test pattern out over HDMI - nothing else.

This is where the reusable HDMI output stage was built and proven first:

- `tmds_encoder.v` - a from-scratch Verilog implementation of the DVI 1.0
  TMDS 8b/10b encoding algorithm (minimal-transition encoding + running
  DC-disparity balancing), verified in simulation against the spec's control
  tokens.
- `oserdes_tmds.v` - a Xilinx `OSERDESE2` MASTER/SLAVE cascade + `OBUFDS`
  that serializes each 10-bit TMDS symbol onto a differential pair.
- `hdmi_tx.v` - wires three colour channels (plus the clock channel) through
  the above to produce a complete HDMI-out driver.
- `color_bar.v` - ALINX's own colour-bar/timing generator, used here only as
  a known-good source of pixels to confirm the output stage works.

Confirmed working on real AX7010 hardware. Every later project in this repo
reuses `hdmi_tx.v` / `tmds_encoder.v` / `oserdes_tmds.v` unchanged as its
video output stage, swapping only whatever generates the RGB pixels.

See [`demo_test_pattern/README.md`](demo_test_pattern/README.md) for build
instructions and full source attribution.

### `project01_pong/` - 1st-generation console: Pong

The first graded assignment, based on the "1st Gen game console" lecture
(Pong-era hardware: no CPU, no software, everything is hardwired logic
driving moving graphics from button input). The brief asks for the taught
base game extended with additional functionality, submitted as Verilog code
plus a video of it running and a short writeup.

The course's reference code targets a VGA connector; since the AX7010 is
HDMI-only, the game logic and 640x480@60 resolution from the slides are kept
as-is, and only the final output stage is swapped to reuse
`demo_test_pattern`'s HDMI/TMDS pipeline instead of a VGA DAC (see that
project's README for the detailed before/after).

Beyond the base slide code, this implementation adds:

- **Score display** - a 5x7 dot-matrix digit per player (`digit_font.v`),
  drawn top-center, incrementing whenever the opposing paddle misses.
- **Ball speedup** - the slides declare a `SPEEDUP` parameter but never
  actually use it; here it's wired up so the ball gains speed every 5
  consecutive paddle hits in a rally, capped to stay within the collision
  logic's safe range, and resets each new point.
- **Center net line** - a dashed vertical line down the middle of the court.

You control the left paddle (button-driven, up/down); the right paddle is a
simple AI that tracks the ball. All gameplay logic (font rendering, scoring,
speedup) was verified in Icarus Verilog simulation before targeting
hardware. See [`project01_pong/README.md`](project01_pong/README.md) for
controls, build steps, and current hardware bring-up / submission status.

### `project01b_soulbattle/` - 1st-generation console: Soul Battle

A second, independent take on the same "1st Gen game console" brief - same
rules (no CPU, no software, no frame buffer), different game. This one is a
single-stage RPG **battle encounter** in the style of Undertale's fight
screens: a heart-shaped soul is steered in four directions inside a battle
box, dodging waves of projectiles while an HP bar drains, and striking back
between waves with a timed-hit attack.

Everything the Pong lecture teaches is still here, just rearranged: the
timing generator is unchanged, projectiles are drawn as comparator-defined
bounding shapes (as Pong draws its ball and paddles), the whole game updates
on the vertical-blanking tick, movement is button-driven and clamped, and
collisions drive the score - here HP, with mercy invincibility. On top of
that it adds:

- **Turn-based state machine** - title -> aim -> strike -> dodge -> win/lose,
  with the enemy's wave pattern cycling and its spawn rate ramping up each
  turn (the same role Pong's unused `SPEEDUP` parameter plays).
- **Bullet register file** - eight fixed object slots of {x, y, vx, vy,
  type, active}, updated in an unrolled per-frame loop and rendered by eight
  parallel shape tests behind a priority mux, clipped to the battle box.
  Spawn positions come from a free-running LFSR.
- **Timed-hit attack** - a cursor sweeps the box; how close to the centre
  line you stop it decides the damage (16 down to 3).
- **Sprite ROMs + text HUD** - a 16x16 soul (whole and shattered) and a
  64x64 enemy drawn at 2x, both original art generated by a Python script;
  two HP bars and four lines of text through project02's 8x16 ASCII font
  ROM, all four text lines served by a single font ROM port.

Verified with two Icarus Verilog testbenches: one plays the battle out twice
through the real button interface (once to a win, once to a death) checking
the rules and invariants, the other runs the whole core at real 640x480@60
timing and dumps rendered frames of each screen. See
[`project01b_soulbattle/README.md`](project01b_soulbattle/README.md) for
controls, architecture, and build steps.

### `project02_textmode/` - Text mode display

The second graded assignment, based on the "Text Mode" lecture (how
terminals and early micros drew text: a font ROM holding the character
glyphs, a tile RAM saying which character sits in each grid cell, and a
pixel pipeline looking up both per pixel). The brief asks for an interactive
text-mode demo with keyboard input.

This implementation is an 80x30 character display (8x16 glyphs, classic IBM
VGA font, 640x480@60 over the same HDMI pipeline) running two of the
brief's suggested demos in one design:

- **Text editor** - arcade-style: a blinking block cursor moves over the
  grid and two buttons cycle the character under it, with typematic
  auto-repeat and a hold-to-clear combo.
- **Matrix screensaver** - after ~20 s idle, digital rain (80 independent
  LFSR-driven streams with bright heads) takes over; any press returns to
  the editor with the text intact, since the rain animates in its own
  separate tile RAM.

Board adaptations: VGA -> HDMI as usual, and - since the AX7010 has no
keyboard connector - the reference design's PS/2 input stage becomes the 4
push buttons. The full core (everything except the clocking IP and TMDS
serializers) is covered by an Icarus Verilog testbench that renders real
frames to image files and scripts button presses through the debouncer. See
[`project02_textmode/README.md`](project02_textmode/README.md) for
controls, architecture, and build steps.

### `project03_platformer/` - Background tile: 2D platformer

The third graded assignment, based on the "2D Platformer on FPGA" lecture
(how NES/SNES-era consoles drew scrolling worlds: a map ROM saying which
tile fills each cell, a tile ROM holding the tile pixels, a sprite ROM +
window-test renderer for the player, and a hardwired state machine for the
game logic - still no CPU, no software). The brief covers the lecture's
sections up through scrolling and the single-sprite renderer, plus "use
state machine to do simple game logic"; the multi-sprite/line-buffer PPU is
the *next* assignment.

This implementation is a playable mini platformer (640x480@60 over the same
HDMI pipeline):

- **Scrolling tile world** - 80x30 map (2 screens wide, x-axis scrolling
  per the slides), 32-tile 16x16 tileset; tile index bit 4 doubles as the
  collision "solid" attribute.
- **Player sprite** - 32x32, 4 frames (idle / 2-frame walk / jump), mirrored
  when facing left, white-as-transparent, per the slides' sprite renderer.
  Original art, generated (with the whole tileset and level) by a Python
  script into plain Verilog ROMs.
- **Game state machine** - gravity with variable-height jumps, walk/run,
  map collision through a second map-ROM instance (the slides' `coll_rom`),
  pits that respawn the player, and a camera that follows - one FSM run
  during each vertical blanking interval.

Board adaptations: VGA -> HDMI as usual, buttons as the controller, and the
whole pipeline at the pixel clock (the slides' 2-clock BRAM latency is
absorbed by delaying the sync flags to match). The full core is covered by
an Icarus Verilog testbench in which an auto-runner *plays the level* -
walking, jumping crates/pit/pipe, dying, respawning - while per-frame
camera/animation invariants are checked and real rendered frames are dumped
to image files. See
[`project03_platformer/README.md`](project03_platformer/README.md) for
controls, architecture, and build steps.

## Building any project

Each project is built the same way, with Vivado on your `PATH`:

```sh
cd <project_folder>
vivado -mode batch -source scripts/create_project.tcl
```

This creates a Vivado project under `<project_folder>/vivado_project/`
(git-ignored) with sources, constraints, and the Clocking Wizard IP already
added, but does not run synthesis. From there, open it in the Vivado GUI and
run Synthesis -> Implementation -> Generate Bitstream, then use Hardware
Manager to program the board over JTAG.
