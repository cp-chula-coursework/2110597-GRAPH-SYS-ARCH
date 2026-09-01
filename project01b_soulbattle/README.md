# AX7010 Soul Battle (1st Gen Console Project, variant B)

A second take on the course's "1st Gen game console" assignment
(05_PONG_History_and_Project.pdf), for the same hardware and the same rules
as [`../project01_pong`](../project01_pong): no CPU, no software, no frame
buffer - just hardwired logic driving moving graphics from push-button input,
at 640x480@60 over HDMI.

Instead of Pong, this one is a single-stage RPG **battle encounter** in the
style of Undertale's fight screens: your soul is a heart that you steer in
four directions inside a battle box, dodging the enemy's attacks while your
HP bar drains, and striking back with a timed-hit attack between waves. The
enemy cycles through four attacks, the last of which sends **blasters** -
skulls that appear on the rim of the box, turn to face your soul, give you a
moment's warning, and fire a beam straight down the line they are aiming
along.

```
                    +----------------+
                    |   ROOT SENTINEL|   <- 64x64 sprite ROM, drawn at 2x,
                    |    (128x128)   |      idle bob + shake/flash when hit
                    +----------------+
                       ROOT SENTINEL          <- enemy name / DAMAGE nn
                  [##############------]      <- enemy HP (120)

        +--------------------------------------------+
        |                                            |  <- battle box
        |    |    |         |         |    |    |    |     260x160, 4 px
        |    |    |    <3   |         |    |    |    |     white frame
        |    |    |         |         |    |    |    |
        +--------------------------------------------+
                      PRESS TO STRIKE!                <- phase hint

            HP  [####################]  40 / 40      <- player HP
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
| ball tracked by comparators        | blaster beams: half-plane comparator tests     |
| `SPEEDUP` difficulty ramp           | `spawn_period` - waves get faster every turn   |
| VGA DAC output                      | HDMI/TMDS output stage (see below)             |

Extensions beyond that base: a turn-based state machine, a pseudo-random
bullet generator (LFSR), sprite ROMs with a transparency key, an 8x16 text
HUD, a timed-hit attack minigame, and an aimed-beam attack whose geometry is
solved from the soul's own coordinates.

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
  - **wave 3** - blasters (see below); this wave fires no bullets at all

  Spawns get 2 frames closer together each turn, floored at 8 (`spawn_period`,
  26 frames down to 12 on the pillar wave, down to 8 on the orbs).
- **WIN / LOSE.** Enemy at 0 HP wins the battle; your 40 HP running out ends
  it. Either way the screen holds for 90 frames, then any button returns to
  the attract screen for a rematch.

A full win takes eight perfect strikes (16 x 8 = 128 >= 120 HP) with seven
enemy turns in between, so one battle runs about a minute - still a single
stage, but long enough for the wave cycle to come all the way round to the
blasters on the fourth enemy turn and start over. The enemy's 120 HP is what
sets that length: at 40 HP a good player finished in three strikes and never
saw past wave 1, which is why the player's own HP and the spawn-rate ramp are
scaled to match.

## The blaster wave

```
  frame  0          18             38              58        68
         |   TRACK   |   CHARGE     |     FIRE      |  FADE   |
         | skull     | muzzle       | beam grows    | skull   |
         | fades in, | frozen, a    | out of the    | fades   |
         | re-aims   | 3 px warning | muzzle at 72  | out     |
         | every     | line is      | px/frame and  |         |
         | frame     | drawn        | opens to 19px |         |

                        ,-.
                       (o o)   <- appears on the rim of the box, already
                        \#/       pointing at wherever your soul is
        +----------------#------------------+
        |               ###                 |
        |               ###                 |    the beam is every pixel
        |               #<3                 |    whose distance across the
        |               ###                 |    aim line is under the
        |               ###                 |    half-width and whose
        +---------------###-----------------+    distance along it is
                                                 under the reach
```

Two blasters can be on screen at once, a new one every ~54 frames (~30 by the
last turn), each one living 74 frames from fade-in to fade-out. Standing in a
firing beam costs 3 HP where a bullet costs 2, through the same 60-frame mercy
window.

**How it aims.** The heading is picked at random from eight compass points,
and then the muzzle is *solved for*: given a soul centre and a heading, there
is exactly one point on the rim of the box that a ray of that heading reaches
the soul from. For the four axis headings that is just the soul's own x or y
carried out to the edge; for the four diagonals it is the soul's centre walked
back along the 45-degree line until it meets the nearer edge, `t = min(dx, dy)`
- subtractions and one comparison, no multiplier and no divider. The muzzle
keeps re-solving every frame while the blaster is fading in, so the skull
visibly slides along the rim after you, and freezes the moment the warning
line appears. Whichever side of the box is further from the soul is preferred,
and a side closer than 40 px is swapped for the opposite one, so there is
always room to dodge.

## Hardware structure

Everything runs at the 25.175 MHz pixel clock. `battle_logic` updates the
whole game once per frame during vertical blanking (36,000 pixel clocks are
available; it uses one), so the renderers never see state change mid-frame.

```
                              x,y
  vga_timing --> +---------+---------+---------+---------+---------+
                 |         |         |         |         |         |
                 v         v         v         v         v         v
          soul_renderer  blaster_  bullet_   hud_      monster_
           (soul_rom)    renderer  renderer  renderer  renderer
                        (blaster_ (comparator (font_rom)(monster_rom
                          rom,2x)   shapes)              , 2x)
                 |         |         |         |         |
                 +---------+---------+---------+---------+
                                    |
        compositor: soul > blasters > bullets > HUD > enemy > black
                    (every layer has the same 2-clock latency)
                                    |
                          vid_r/g/b + syncs ---> hdmi_tx

  battle_logic ----- soul_x/soul_y, state, wave ----> blaster_logic
       ^                                                   |
       +--------- blast_hit, blast_busy -------------------+
```

| File | Role |
|------|------|
| `top.v` | clocking IP + core + HDMI transmitter |
| `battle_core.v` | timing, layers, compositor, enemy bob/shake |
| `battle_logic.v` | the turn machine, bullet register file, collisions, LFSR |
| `blaster_logic.v` | the blaster wave: heading choice, muzzle solve, phase timers |
| `blaster_renderer.v` | beam half-plane tests + the skull, 8 headings from 2 ROM frames |
| `soul_renderer.v` | 16x16 heart sprite from `soul_rom` |
| `monster_renderer.v` | 64x64 enemy sprite drawn at 2x from `monster_rom` |
| `bullet_renderer.v` | 8 parallel bullet shape tests + priority mux, clipped to the box |
| `hud_renderer.v` | box frame, both HP bars, attack cursor, 4 lines of text |
| `soul_rom.v`, `monster_rom.v`, `blaster_rom.v` | generated art (`scripts/gen_assets.py`) |
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
- **Eight headings, so a beam is still just a comparator.** With the aim
  quantized to the compass points, "inside the beam" is `|across| <= width`
  and `0 <= down <= reach`, where `across` and `down` are `dx`, `dy`, `dx+dy`
  or `dx-dy` picked by the heading - four adders and four comparators per
  blaster, and no rotation, normalization or multiplier anywhere. On a
  diagonal `dx-dy` measures `sqrt(2)` times the true distance across the beam,
  so the width is scaled by ~1.375 with two shifts rather than dividing.
  `reach` grows 72 px per frame, which is what makes the beam travel out of
  the muzzle instead of appearing all at once.
- **Eight sprite orientations out of two ROM frames.** `blaster_rom` stores
  the skull facing down and facing down-right; the other six headings are
  reached by mirroring the row address, mirroring the column address, or
  swapping the two - the symmetries of the square, free in hardware. The skull
  is symmetric about its own axis, so the mirroring never shows.
- **One sprite ROM port for both blasters**, picked by cell priority, the same
  sharing trick the four text bands use on the font ROM. Two overlapping
  skulls therefore occlude at cell granularity, which is exactly the artifact
  real fixed-sprite hardware has.
- **The blasters composite above the HUD** on purpose: a skull that comes in
  over the top edge passes in front of the enemy's name and HP bar for the
  second it is on screen.

## Art

`scripts/gen_assets.py` draws all the sprites in Python (original art - no
ripped game assets) and emits them as Verilog `initial` blocks, so the ROMs
behave identically in Vivado and in Icarus Verilog with no `.mem` path
issues. 12'hFFF (pure white) is the transparency key, per the course slides.

The blaster skull is drawn in the beam's own frame of reference (how far
behind the muzzle a pixel is, and how far to the side), so one shape function
rasterizes both ROM frames and the diagonal one really is the same skull, not
a rotation of a bitmap.

```sh
python3 scripts/gen_assets.py                  # regenerate the ROMs
python3 scripts/gen_assets.py --preview /tmp/art   # + PNG previews
```

## Verification

Before targeting hardware:

- `sim/tb_battle_logic.v` drives the game logic with synthetic frame pulses
  (20 clocks apart instead of a real 420,000-clock frame), which makes it
  practical to play the battle out twice through the real button interface:
  once winning with bullseye strikes while a small avoidance policy dodges
  the bullets for the seven enemy turns that takes, once losing with weak
  strikes and no dodging at all. The winning run is also the check that a
  120 HP enemy is still beatable. It checks
  the win and loss paths, restart-from-title, that a bullseye scores 16 and
  an edge press scores 3, that all four wall clamps and diagonal movement
  work, that a hit costs exactly 2 HP and cannot repeat inside the 60-frame
  mercy window, and that no live bullet ever leaves the spawn window. It
  also plays the turn order round to the blaster wave and checks that the
  wave fires no bullets at all, that a soul standing still is hit by a beam
  for 3 HP, and that the turn is not handed back while a blaster is still on
  screen.
- `sim/tb_blaster.v` drives `blaster_logic` directly, which is what makes the
  aiming geometry checkable exactly rather than by eye: with the soul held
  still, the ray from every live muzzle passes precisely through the soul's
  centre, for all eight headings; every muzzle lands on the rim of the box;
  no muzzle is ever closer than the 40 px minimum lead; the phases run
  TRACK -> CHARGE -> FIRE -> FADE with no beam while tracking and a 3 px line
  while charging; a soul that stands still is hit and one that steps aside
  after the lock is not; and all eight headings really do come up.
- `sim/tb_soulbattle.v` runs the whole core at real 640x480@60 timing,
  checks the video timing the HDMI encoder depends on (exactly 640x480
  active pixels and 525 lines per frame), and dumps one frame of each screen
  (title / aim / hit / dodge) as PPM images for visual inspection.
- `sim/tb_blaster_draw.v` dumps the blaster layer on its own with all eight
  headings placed at once - the beams should all meet on the soul marker and
  each skull should point down its own beam. The blaster wave is four enemy
  turns into a battle, which is thousands of frames at real timing, so this
  is how that picture gets checked without running the whole core that long.
- The full `top.v` hierarchy elaborates cleanly under `iverilog` (the only
  errors are for Xilinx's `OSERDESE2`/`OBUFDS` primitives and the
  Vivado-generated `clk_wiz_video` IP, neither of which exist outside
  Vivado/its simulator - expected and harmless).

```sh
iverilog -o /tmp/tb_logic.vvp hdl/battle_logic.v hdl/blaster_logic.v \
  sim/tb_battle_logic.v
vvp /tmp/tb_logic.vvp

iverilog -o /tmp/tb_blaster.vvp hdl/blaster_logic.v sim/tb_blaster.v
vvp /tmp/tb_blaster.vvp

iverilog -o /tmp/tb_bd.vvp hdl/vga_timing.v hdl/blaster_rom.v \
  hdl/blaster_renderer.v sim/tb_blaster_draw.v
vvp /tmp/tb_bd.vvp     # writes soulbattle_blaster.ppm

iverilog -o /tmp/tb_sb.vvp hdl/vga_timing.v hdl/pad_input.v hdl/soul_rom.v \
  hdl/monster_rom.v hdl/blaster_rom.v hdl/font_rom.v hdl/soul_renderer.v \
  hdl/monster_renderer.v hdl/bullet_renderer.v hdl/blaster_renderer.v \
  hdl/hud_renderer.v hdl/battle_logic.v hdl/blaster_logic.v hdl/battle_core.v \
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
