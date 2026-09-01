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

The four board LEDs (M14, M15, K16, J16) show the player's HP a quarter at a
time, so the board itself shows how the battle is going. On the attract
screen, where HP is always full, they echo the four external buttons instead.

### External buttons (optional)

Five plain push buttons on expansion connector J10, each shorting its pin to
ground - no supply, no resistors, nothing that can be driven into a pin that
would not survive it.

| Button | J10 pin | Package pin |
|--------|---------|-------------|
| up | 3 | W19 |
| down | 4 | W18 |
| left | 5 | R14 |
| right | 6 | P14 |
| confirm | 7 | Y17 |
| common ground | 1 | - |

J10 numbers the opposite way round from J11: its pin 1 is at the **bottom**,
marked by the square pad, and pin 2 is 5V - leave that one alone.

### PlayStation controller through a serial adapter (optional)

The way a controller actually reached this design in the end. The adapter is
a board with its own microcontroller: it talks the PlayStation protocol to
the pad and sends the result on as plain serial, so the FPGA needs one input
pin and a UART receiver rather than four pins and bit-level timing.

| Adapter pin | Goes to | J10 pin | Package pin |
|-------------|---------|---------|-------------|
| TXD | `uart_rx_pin`, through ~1k | 8 | Y16 |
| GND | header GND | 1 | - |
| VCC | header **3.3V** | 39 or 40 | - |
| RXD | leave unconnected | - | - |

Power it from 3.3V rather than the 5V on pin 2: at 3.3V its TXD swings 3.3V
and can be wired straight in.

This particular adapter turned out to send one byte per button rather than
the 8-byte packet its documentation describes, at 9600 baud:

| Byte | Button | | Byte | Button |
|------|--------|-|------|--------|
| `41` | up | | `49` | triangle |
| `42` | down | | `4a` | cross |
| `43` | left | | `4b` | square |
| `44` | right | | `4c` | circle |

All four face buttons confirm, as do the neighbouring codes the shoulder
buttons and START land on. Nothing says when a button is released, so
`serial_pad.v` gives each button a timer that an arriving byte reloads and
the frame tick counts down; a button reads as held while its timer runs.

Because none of that could be known in advance, a read-out sits on screen
above the enemy's name in every state:

```
B0 00 43 --LR- 41414143
│  │  │  │     └─ the last four bytes, raw
│  │  │  └─────── what the game is being told: up down left right confirm
│  │  └────────── the last byte that arrived
│  └───────────── frames that arrived without a stop bit
└──────────────── selected baud rate: B0 9600 ... B4 115200
```

Holding left and right together for three quarters of a second steps the baud
rate, and doing so restarts the error count - a wrong rate shows as errors
climbing, a dead wire as nothing happening at all, which is the difference
that matters when nothing works yet.

### PlayStation controller (optional)

A PSX/PS2 controller can be wired to the expansion header and used instead of
- or alongside - the buttons. `ps2_pad.v` polls it once per frame and simply
ORs the result in with the board buttons, so neither input has to be present
and both work at the same time.

> **Status: written and simulated, superseded on hardware by the serial
> adapter below.** The module
> passes its testbench against a model of a real controller, and the game runs
> with or without a controller plugged in, but bring-up on this board did not
> get as far as a controller answering. What was established: all three
> outputs (COMMAND, CLOCK, ATTENTION) reach the header and are identifiable by
> earthing them one at a time, the pin numbering below is correct, and the
> adapter's own regulator needs 5V rather than 3.3V. What was never solved:
> the DATA pin never registered being earthed, on any of three pins tried and
> whether declared as an input or as a tri-stated inout, even though the same
> pin drove out correctly. The four board buttons play the game in full, so
> this is an extra rather than a dependency.

| Controller            | Game                                             |
|-----------------------|--------------------------------------------------|
| D-pad                 | Move the soul in four directions                 |
| Left stick            | The same, with a 25% deadzone (analog mode only) |
| X / O / triangle / square | Confirm - start, strike, continue            |
| START                 | Confirm                                          |

Unlike the board buttons, the controller has a confirm button that is *not*
one of the directions, which is what `pad_ok` in `battle_logic.v` is for.

Wiring, in the order the pins sit in the connector:

| Wire   | Signal      | Direction   | Connect to        | Package pin |
|--------|-------------|-------------|-------------------|-------------|
| brown  | DATA        | pad -> FPGA | `IO2_2N`          | F20         |
| orange | COMMAND     | FPGA -> pad | `IO2_1N`          | F17         |
| purple | 7V rumble   | -           | leave unconnected | -           |
| black  | GND         | -           | header GND        | -           |
| red    | 3.3V        | -           | header 3V3        | -           |
| yellow | ATTENTION   | FPGA -> pad | `IO2_2P`          | F19         |
| blue   | CLOCK       | FPGA -> pad | `IO2_1P`          | F16         |
| green  | ACKNOWLEDGE | -           | leave unconnected | -           |

If you are using one of the small breakout boards that turns the controller
socket into a 6-pin SPI header, those six pins are exactly the four signals
above plus power - it has already dropped the two wires this design leaves
unconnected:

| Board pin        | Connect to | Package pin |
|------------------|------------|-------------|
| `DAT` / `DI`     | `ps2_dat`  | F20         |
| `CMD` / `DO`     | `ps2_cmd`  | F17         |
| `CS` / `ATT`     | `ps2_att`  | F19         |
| `CLK` / `SCK`    | `ps2_clk`  | F16         |
| `VCC`            | header 3V3 | -           |
| `GND`            | header GND | -           |

**Power those boards from 3.3V, not 5V.** They are usually passive breakouts
with no level shifting, so a 5V supply puts 5V back on DATA, and the Zynq's
IO is not 5V tolerant. The controller itself is a 3.3V device and is happy
on 3.3V.

`DI`/`DO` labelling on these boards is ambiguous - some name the lines from
the controller's point of view and some from the host's. Go by direction
rather than by name: the line the FPGA drives is `ps2_cmd`, the line the
controller drives is `ps2_dat`. If a board does not respond, swapping those
two is the first thing to try.

Notes:

- The package pins are what the XDC constrains; which physical pin of the
  expansion header carries `IO2_1P` and friends is in the ALINX schematic -
  check it before wiring, and edit
  [`constraints/ax7010_soulbattle.xdc`](constraints/ax7010_soulbattle.xdc)
  if you would rather use other pins. Any four free 3.3V IO will do.
- **DATA is open drain** and needs a pull-up to 3.3V. The XDC turns on the
  FPGA's internal one, which is enough for a short lead; add an external 1k
  for a full-length controller cable.
- **ACKNOWLEDGE is not used.** It exists so the host knows the controller has
  kept up; `ps2_pad` instead leaves a 16 us gap between bytes, which is
  longer than the controller's worst case, so the wire can stay unconnected.
- **Do not connect the 7V rumble line.** Nothing here drives the motors, and
  the expansion header has no 7V rail anyway.

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
  - **wave 4** - blasters again, sweeping a circle around the soul three
    times as fast
  - **wave 5** - one crimson blaster at a time, slow and heavily telegraphed,
    whose beam ends the battle outright

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

**The ring.** Wave 4 is the same module with one thing changed: instead of
drawing each heading at random it walks the compass one point at a time, so
the attack sweeps a full circle about the soul. Every phase is shortened -
one blaster every 18 frames instead of 54, alive for 46 instead of 74 - so
three or four are on screen at once, trailing round. The warning is cut least
of all, to 16 frames: it is the one thing between the player and an attack
that cannot be dodged. Where the sweep starts and which way it turns are
drawn once per turn, so it stays readable without being memorisable.

Because the muzzle is still solved the same way, every beam in the circle
still passes exactly through the soul - the sweep is not decoration around a
fixed target, it is eight aimed shots in a row from eight different sides.

**The crimson one.** Wave 5 goes the other way entirely. Its beam does not
take HP, it ends the battle, so everything about it is built to be seen
coming: one blaster on screen at a time, a second and a half of warning line
before it fires, and a long wait between them. An instant kill is only fair
while it is never a surprise. It ignores the mercy window too - there is no
such thing as a graze.

The red skull is the same ROM read through a filter rather than a second set
of art: take whichever channel is brightest as the strength of the pixel and
put it in red. Bone comes out red, the glowing eyes come out brighter red,
the dark outline stays dark - the shape and shading survive, only the hue
changes, for the cost of two comparators.

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
| `ps2_pad.v` | PlayStation controller host: SPI mode 3, LSB first, one poll per frame (see the status note under Controls) |
| `uart_rx.v` | 8N1 serial receiver, baud selectable on the board |
| `serial_pad.v` | serial adapter bytes -> held button levels |
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
- **A circling attack for free.** The ring wave needed no sine table, no
  multiplier and nothing new in the renderer: with the heading already
  quantized to eight compass points, sweeping a circle is a counter that steps
  by one. What made the first blaster wave cheap is what made the second one
  nearly free.
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
- **The controller is polled in vertical blanking**, on the same `frame_start`
  tick the game logic runs on. A whole transaction is about 12,600 pixel
  clocks against the 420,000 in a frame, so it is finished long before the
  next frame wants it, and the game never has to wait on a serial bus. The
  controller's own reply decides how long the transaction is: the low nibble
  of its ID byte is the number of 16-bit words it is about to send, so a
  digital pad takes 5 bytes and an analog one 9, with nothing hardwired.

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
  once winning with bullseye strikes while a small avoidance policy plays
  the seven enemy turns that takes, once losing with weak strikes and no
  dodging at all. That policy steps out of the way of beams as well as
  bullets - the distance across a beam is the same expression the hardware
  draws it with, so the bench can move to make it bigger - and keeps walking
  when the box is empty, because a blaster locks on to whatever is standing
  still. The winning run is what shows the battle is still finishable now
  that one of the waves kills outright: it comes through with 33 HP of 40. It checks
  the win and loss paths, restart-from-title, that a bullseye scores 16 and
  an edge press scores 3, that all four wall clamps and diagonal movement
  work, that a hit costs exactly 2 HP and cannot repeat inside the 60-frame
  mercy window, and that no live bullet ever leaves the spawn window. It
  also plays the turn order round to the blaster wave and checks that the
  wave fires no bullets at all, that a soul standing still is hit by a beam
  for 3 HP, and that the turn is not handed back while a blaster is still on
  screen.
- `sim/tb_uart_rx.v` shifts bytes in the way a transmitter does and checks
  they come back out: single bytes, a whole 8-byte packet back to back, a
  transmitter a few percent off the receiver's rate, a frame with no stop bit
  being dropped and counted rather than passed on, and a glitch on an idle
  line not being taken for a start bit.
- `sim/tb_ps2_pad.v` puts a model of a real controller on the other end of
  the wire - it shifts its answer out on each falling clock edge and latches
  the host's command on each rising one, exactly as the hardware does. It
  checks the command bytes (01, 42, then filler, LSB first), that the ID's
  low nibble really does set the transaction length (5 bytes digital, 9
  analog), the d-pad and face buttons, the left stick with its deadzone, that
  an unplugged socket reports nothing at all so the board buttons stay in
  charge, and that plugging back in recovers.
- `sim/tb_blaster.v` drives `blaster_logic` directly, which is what makes the
  aiming geometry checkable exactly rather than by eye: with the soul held
  still, the ray from every live muzzle passes precisely through the soul's
  centre, for all eight headings; every muzzle lands on the rim of the box;
  no muzzle is ever closer than the 40 px minimum lead; the phases run
  TRACK -> CHARGE -> FIRE -> FADE with no beam while tracking and a 3 px line
  while charging; a soul that stands still is hit and one that steps aside
  after the lock is not; and all eight headings really do come up. In ring
  mode it also checks that the heading walks one compass point at a time,
  always the same way round, all the way through the circle, and that
  blasters come far closer together than in the ordinary wave. In crimson
  mode it checks that only one is ever on screen, that the warning runs over
  a second, and that hits are reported as fatal rather than as damage.
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

iverilog -o /tmp/tb_ps2.vvp hdl/ps2_pad.v sim/tb_ps2_pad.v
vvp /tmp/tb_ps2.vvp

iverilog -o /tmp/tb_blaster.vvp hdl/blaster_logic.v sim/tb_blaster.v
vvp /tmp/tb_blaster.vvp

iverilog -o /tmp/tb_bd.vvp hdl/vga_timing.v hdl/blaster_rom.v \
  hdl/blaster_renderer.v sim/tb_blaster_draw.v
vvp /tmp/tb_bd.vvp     # writes soulbattle_blaster.ppm

iverilog -o /tmp/tb_sb.vvp hdl/vga_timing.v hdl/pad_input.v hdl/soul_rom.v \
  hdl/monster_rom.v hdl/blaster_rom.v hdl/font_rom.v hdl/soul_renderer.v \
  hdl/monster_renderer.v hdl/bullet_renderer.v hdl/blaster_renderer.v \
  hdl/hud_renderer.v hdl/battle_logic.v hdl/blaster_logic.v hdl/ps2_pad.v \
  hdl/battle_core.v sim/tb_soulbattle.v
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
