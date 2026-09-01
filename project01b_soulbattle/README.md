# AX7010 Soul Battle (1st Gen Console Project, variant B)

A second take on the course's "1st Gen game console" assignment
(05_PONG_History_and_Project.pdf), for the same hardware and the same rules
as [`../project01_pong`](../project01_pong): no CPU, no software, no frame
buffer - just hardwired logic driving moving graphics from push-button input,
at 640x480@60 over HDMI.

Instead of Pong, this one is a single-stage RPG **battle encounter** in the
style of Undertale's fight screens: your soul is a heart that you steer in
four directions inside a battle box, dodging the enemy's attacks while your
HP bar drains, and striking back with a timed-hit attack between waves.

```
                    +----------------+
                    |   ROOT SENTINEL|   <- 64x64 sprite ROM, drawn at 2x,
                    |    (128x128)   |      idle bob + shake/flash when hit
                    +----------------+
                       ROOT SENTINEL          <- enemy name / DAMAGE nn
                  [##############------]      <- enemy HP (40)

        +--------------------------------------------+
        |                                            |  <- battle box
        |    |    |         |         |    |    |    |     260x160, 4 px
        |    |    |    <3   |         |    |    |    |     white frame
        |    |    |         |         |    |    |    |
        +--------------------------------------------+
                      PRESS TO STRIKE!                <- phase hint

            HP  [####################]  20 / 20      <- player HP
```

## Why this is still the Pong assignment

The assignment is about hardwired graphics hardware, not about Pong itself,
so everything the slides teach is still here - just rearranged:

| Slides' Pong                       | This project                                  |
|------------------------------------|-----------------------------------------------|
| `vga` timing generator             | `vga_timing.v` (unchanged from project01)      |
| object bounding-box rendering      | `bullet_renderer.v` - pure comparator shapes   |
| ball/paddle motion on `posedge VS`  | `battle_logic.v` - everything on `frame_start` |
| paddle from buttons, clamped        | four-way soul movement, clamped to the box     |
| collision -> score                  | collision -> HP loss + mercy invincibility     |
| `SPEEDUP` difficulty ramp           | `spawn_period` - waves get faster every turn   |
| VGA DAC output                      | HDMI/TMDS output stage (see below)             |

Extensions beyond that base: a turn-based state machine, a pseudo-random
bullet generator (LFSR), sprite ROMs with a transparency key, an 8x16 text
HUD, and a timed-hit attack minigame.

## Adaptation from the course slides: VGA -> HDMI

Same as the other projects in this repo. The AX7010 has no VGA DAC, so the
final stage is the pure-Verilog HDMI/TMDS pipeline built in
[`../demo_test_pattern`](../demo_test_pattern) - `hdmi_tx.v` +
`tmds_encoder.v` + `oserdes_tmds.v`, reused byte-for-byte, with
`vga_timing.v` in front of it exactly as in project01.

## Controls

The board's 4 push buttons (active-low). Four-way movement needs all four,
so there is no spare reset key - the battle restarts through the attract
screen instead.

| Button | Pin | Function                                          |
|--------|-----|---------------------------------------------------|
| key[0] | N15 | Move up    / confirm (start, strike, continue)    |
| key[1] | N16 | Move down  / confirm                              |
| key[2] | T17 | Move left  / confirm                              |
| key[3] | R17 | Move right / confirm                              |

## How the battle plays

```
  TITLE --press--> AIM --press--> HIT --> DODGE --+--> AIM ...
                    ^                             |
                    |            enemy HP = 0 --> WIN  --press--> TITLE
                    |           player HP = 0 --> LOSE --press--> TITLE
```

- **AIM (your turn).** A cursor sweeps across the battle box at 7 px/frame.
  Press any button to stop it: the closer to the yellow centre line, the more
  damage (16 / 12 / 8 / 5 / 3), scored from the distance to the middle. The
  grey marks show the scoring tiers. The soul waits at the left of the box
  during this phase so it isn't sitting on the centre line.
- **HIT.** The damage read-out replaces the enemy's name for 75 frames while
  the sprite shakes and flashes white, and the green enemy HP bar drops.
- **DODGE (enemy turn).** Bullets spawn from the edges of the box for 330
  frames; you steer the soul at 3 px/frame in any of eight directions
  (diagonals work - the axes move independently). Touching a bullet costs
  2 HP and gives 60 frames of mercy invincibility, during which the heart
  blinks. The wave pattern cycles every turn:
  - **wave 0** - pillars falling from the top at random x
  - **wave 1** - pillars swiping in from the left or right at random y
  - **wave 2** - orbs dropping diagonally and bouncing off the side walls

  Spawns get faster each turn (`spawn_period`, 26 frames down to 8).
- **WIN / LOSE.** Enemy at 0 HP wins the battle; your 20 HP running out ends
  it. Either way the screen holds for 90 frames, then any button returns to
  the attract screen for a rematch.

A full win takes three perfect strikes (16 x 3 = 48 >= 40 HP) with two enemy
turns in between, so one battle runs about 20 seconds - a single stage, as
intended.

## Hardware structure

Everything runs at the 25.175 MHz pixel clock. `battle_logic` updates the
whole game once per frame during vertical blanking (36,000 pixel clocks are
available; it uses one), so the renderers never see state change mid-frame.

```
                              x,y
  vga_timing ---> +------------+------------+-------------+
                  |            |            |             |
                  v            v            v             v
           soul_renderer  bullet_renderer  hud_renderer  monster_renderer
            (soul_rom)     (comparator      (font_rom)    (monster_rom, 2x)
             2 clks          shapes)         2 clks         2 clks
                  |          2 clks             |             |
                  +------------+------------+---+-------------+
                                    |
                     compositor: soul > bullets > HUD > enemy > black
                                    |
                          vid_r/g/b + syncs ---> hdmi_tx
```

| File | Role |
|------|------|
| `top.v` | clocking IP + core + HDMI transmitter |
| `battle_core.v` | timing, layers, compositor, enemy bob/shake |
| `battle_logic.v` | the turn machine, bullet register file, collisions, LFSR |
| `soul_renderer.v` | 16x16 heart sprite from `soul_rom` |
| `monster_renderer.v` | 64x64 enemy sprite drawn at 2x from `monster_rom` |
| `bullet_renderer.v` | 8 parallel bullet shape tests + priority mux, clipped to the box |
| `hud_renderer.v` | box frame, both HP bars, attack cursor, 4 lines of text |
| `soul_rom.v`, `monster_rom.v` | generated art (`scripts/gen_assets.py`) |
| `font_rom.v` | 8x16 ASCII font, reused verbatim from project02_textmode |
| `pad_input.v` | 4-button synchronizer + debouncer, as in project03 |
| `vga_timing.v`, `hdmi_tx.v`, `tmds_encoder.v`, `oserdes_tmds.v` | unchanged from project01 |

Notes on the design decisions a hardwired console forces:

- **Bullets are a register file, not a display list.** Eight fixed slots of
  {x, y, vx, vy, type, active}; the per-frame update is an unrolled loop and
  the renderer tests all eight in parallel, then priority-muxes the pixel.
- **Shapes are comparators, not ROM.** The pillars and orbs are drawn from
  their in-bullet offset (dx, dy) with pure comparisons - the same technique
  the slides' Pong uses for the ball and paddles - so there is no bullet
  sprite ROM to feed and no per-bullet ROM port contention.
- **One font ROM port for four text lines.** The four text bands sit on
  disjoint scanlines and start on multiples of 16 in y and 8 in x, so the
  glyph row is `y[3:0]` and the glyph column `x[2:0]`, and a single ROM read
  serves whichever band the beam is in.
- **All layers have the same 2-clock latency**, so the compositor is a plain
  priority mux and the sync signals just ride a matching 2-stage delay.

## Art

`scripts/gen_assets.py` draws all the sprites in Python (original art - no
ripped game assets) and emits them as Verilog `initial` blocks, so the ROMs
behave identically in Vivado and in Icarus Verilog with no `.mem` path
issues. 12'hFFF (pure white) is the transparency key, per the course slides.

```sh
python3 scripts/gen_assets.py                  # regenerate the ROMs
python3 scripts/gen_assets.py --preview /tmp/art   # + PNG previews
```

## Verification

Before targeting hardware:

- `sim/tb_battle_logic.v` drives the game logic with synthetic frame pulses
  (20 clocks apart instead of a real 420,000-clock frame), which makes it
  practical to play the battle out twice through the real button interface:
  once winning with bullseye strikes, once losing with weak ones. It checks
  the win and loss paths, restart-from-title, that a bullseye scores 16 and
  an edge press scores 3, that all four wall clamps and diagonal movement
  work, that a hit costs exactly 2 HP and cannot repeat inside the 60-frame
  mercy window, and that no live bullet ever leaves the spawn window.
- `sim/tb_soulbattle.v` runs the whole core at real 640x480@60 timing,
  checks the video timing the HDMI encoder depends on (exactly 640x480
  active pixels and 525 lines per frame), and dumps one frame of each screen
  (title / aim / hit / dodge) as PPM images for visual inspection.
- The full `top.v` hierarchy elaborates cleanly under `iverilog` (the only
  errors are for Xilinx's `OSERDESE2`/`OBUFDS` primitives and the
  Vivado-generated `clk_wiz_video` IP, neither of which exist outside
  Vivado/its simulator - expected and harmless).

```sh
iverilog -o /tmp/tb_logic.vvp hdl/battle_logic.v sim/tb_battle_logic.v
vvp /tmp/tb_logic.vvp

iverilog -o /tmp/tb_sb.vvp hdl/vga_timing.v hdl/pad_input.v hdl/soul_rom.v \
  hdl/monster_rom.v hdl/font_rom.v hdl/soul_renderer.v hdl/monster_renderer.v \
  hdl/bullet_renderer.v hdl/hud_renderer.v hdl/battle_logic.v hdl/battle_core.v \
  sim/tb_soulbattle.v
vvp /tmp/tb_sb.vvp     # slow: real frames, writes soulbattle_*.ppm
```

This does not replace testing on real hardware - build the project and
confirm the battle plays correctly on an HDMI display before submitting.

## Building the project

From a terminal, with Vivado on your `PATH`:

```sh
cd project01b_soulbattle
vivado -mode batch -source scripts/create_project.tcl
```

This creates a Vivado project under `project01b_soulbattle/vivado_project/`
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
of the hardware running, and a 2-3 page document explaining how the hardware
works. The video and writeup aren't part of this repo - happy to help draft
the writeup once the design is confirmed working on the board.
