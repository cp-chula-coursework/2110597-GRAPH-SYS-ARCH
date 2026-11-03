# project04_slidepuzzle - Image Slide Puzzle

The fourth graded assignment, on images: a picture cut into a 4x4 grid,
one piece missing, and the other fifteen slid around until it is whole
again. It is still hardwired, with no CPU and no software. A state machine
plays the game, and the picture is drawn live from an image ROM, pixel by
pixel, as the beam scans. There is no framebuffer.

The same game core runs on two targets:

| | AX7010 board | VGA Playground |
|---|---|---|
| top | `hdl/top.v` | `src/tt_um_hextex_slidepuzzle.v` |
| output | HDMI 640x480@60, 24-bit colour | Tiny VGA, 2 bits per channel, Bayer-dithered |
| input | 4 board buttons (+ optional J10 buttons) | Gamepad mode, or the `ui_in` switches |
| shared | `src/puzzle_core.v`, `src/vga_timing.v`, `src/image.mem`, `src/palette.mem` | same |

> **Status:**
> - **Simulation:** verified for the core, the playground top, and the
>   AX7010 top's button path.
> - **Vivado:** builds clean through bitstream.
> - **Playground compile:** never run. Verilator wasn't available locally, so
>   `src/` has only been written to the playground's known limits:
>   - signals of 32 bits or less;
>   - nothing signed;
>   - no array writes inside `for` loops.
>
> Not done yet: loading it live in the VGA Playground (the branch has to be
> pushed first, see below), bring-up on the board, the video and the written
> explanation.

## How it plays

1. The title screen shows the whole picture, with a band of light sweeping
   across it now and then. Press anything to start.
2. The board is shuffled. Each press slides the tile beside the gap **in the
   direction pressed, into the gap**. The tile glides there over 10 frames.
3. When every tile is home, the missing piece returns. The board dims, and
   the finished picture opens from the centre of the screen as a growing
   circle. Then it is back to the title.

You can peek at the finished picture while a game is on, and reshuffle at
any time.

### Controls - AX7010

| Input | Action |
|---|---|
| `key[0]` / `key[1]` / `key[2]` / `key[3]` | up / down / left / right |
| up + down together | reshuffle |
| left + right, held | peek at the finished picture |
| J10 buttons (optional) | the same four directions, plus a real start on pin 7 |

The second button of a chord moves nothing, so a chord costs at most the one
move its first button made. If that move is still sliding when the chord
completes, the reshuffle waits for the tile to land. The J10 wiring is project01b_soulbattle's: five
buttons to ground, on pins W19, W18, R14, P14 and Y17, with internal
pull-ups. With nothing wired, they read as released.

### Controls - VGA Playground

| Gamepad mode (recommended) | Switches (`ui_in`, keys `0`-`7`) | Action |
|---|---|---|
| arrow keys | `0` `1` `2` `3` | up / down / left / right |
| `t` (start) or `a` | `7` | start / reshuffle |
| `s` (select) or `b`, held | - | peek |

The playground's `ui_in` buttons are toggles: a click flips the bit and it
stays flipped. So every flip, in either direction, counts as one press.
`ui_in[6:4]` are never used as switches, because gamepad mode drives them.

## How it works

### Drawing the picture without moving it

The picture never moves in memory. The only thing a move changes is
`board`, sixteen 4-bit entries that say which tile sits in each slot. For
every pixel, stage 0 of the renderer works out:

```
slot    = which slot the beam is in      3 comparators per axis: x >= 160/320/480
tile    = board[slot]                    a 16:1 mux
lx, ly  = position inside the slot       x - col*160, y - row*120 (shift + add)
address = (tile_row*60 + ly/2) * 320 + tile_col*80 + lx/2
```

Every multiply is by a constant, so there are only shifts and adds
(`*320 = <<8 + <<6`, `*160 = <<7 + <<5`, `*120 = <<7 - <<3`) and no
divider. A move rewrites two board entries, and the next frame shows the
picture rearranged.

### Indexed colour

The 320x240 picture is stored as one 8-bit palette index per pixel (600
kbit, in block RAM), with a 256-entry table of 24-bit colours. This is how
indexed-colour consoles stored backgrounds: a byte per pixel, and the real
colour looked up on the way out. `scripts/gen_image.py` picks the 256
colours that suit the picture best.

### Pipeline

```
stage 0   x, y -> slot, tile, address, effect flags   (combinational, registered)
stage 1   image ROM:   address -> palette index      (block RAM)
stage 2   palette ROM: index   -> 24-bit colour
stage 3   bevels, the gap, dimming, shine            -> r, g, b
```

hsync, vsync and display-enable ride the same four registers, so the
colour and the sync come out together.

### Shuffling so it can always be solved

Placing the fifteen tiles at random would give an unsolvable board half of
the time (the classic 14-15 puzzle). The shuffle instead starts from the
solved board and makes 200 random but legal moves of the gap, one per clock,
all inside one vertical blanking interval. It never undoes the move it just
made. Every step is a real move, so walking back is always possible. The
random source is a 16-bit LFSR that steps on every clock, so how long the
player waits before pressing start decides the board.

### The sliding tile is a sprite

When a move is accepted, the tile becomes a 160x120 sprite at exactly the
position it was drawn. That is why a move can start mid-frame without a
seam. The sprite steps 16 px (horizontal) or 12 px (vertical) once per
frame during vblank. Both slots it is travelling between draw as the gap
underneath it. Only when the sprite arrives are the two board entries
written. Presses during a slide are ignored.

### Win: the iris

The board is solved when `board[i] == i` for all sixteen slots. The radius
grows 6 px a frame. For each pixel, `dx^2 + dy^2 < r^2` decides whether it
shows the finished picture or the dimmed board. `|dx|` and `|dy|` are
formed with compare-and-subtract, so nothing is signed. `r^2` sits in a
register, because it depends only on `r` and not on the pixel.

### The other effects

These are all per-pixel tests in stage 0, applied in stage 3:

- Every tile has a raised bevel: the top and left 2 px lighter, the bottom
  and right 2 px darker.
- The gap is a dark well with a 5 px shadow along its top and left.
- The title shine is a band where `|x + y - pos| < 26`.

### Two ends for two targets

- `hdl/top.v` puts the core between the Clocking Wizard, debounced buttons
  and the repo's HDMI/TMDS pipeline. `hdmi_tx.v`, `tmds_encoder.v` and
  `oserdes_tmds.v` are copied unchanged from `demo_test_pattern/`.
- `src/tt_um_hextex_slidepuzzle.v` puts the same core between the
  playground's pins and the Tiny VGA output.
  - `gamepad_pmod_rx.v` is a fresh receiver for the gamepad's 3-wire
    shift-register protocol.
  - 24-bit colour becomes 2 bits per channel with a 4x4 Bayer threshold built
    from bits, `{x0^y0, y0, x1^y1, y1}`, with no table:
    `level = (3c + threshold) >> 8`.

Nothing in `src/` is wider than 32 bits or signed, because the playground's
simulator does not handle either.

## Layout, and why it differs from the other projects

```
project04_slidepuzzle/
  info.yaml          playground / Tiny Tapeout manifest
  src/               everything the playground needs, shared with the board
    puzzle_core.v      the game and the renderer
    vga_timing.v       640x480@60 timing (project03's, unchanged)
    tt_um_hextex_slidepuzzle.v   playground top
    gamepad_pmod_rx.v  gamepad receiver (playground only)
    image.mem          picture, 8-bit indices    (generated)
    palette.mem        256 x RRGGBB              (generated)
  hdl/               AX7010 only: top, HDMI, button debounce
  constraints/       AX7010 pins
  scripts/           create_project.tcl, gen_image.py, make_playground_branch.sh
  sim/               testbenches and frame checkers
```

The VGA Playground's loader has fixed paths:

- it reads `info.yaml` from the root of a branch;
- it fetches every source file, and every `$readmemh` file, from `src/`;
- it finds the `$readmemh` files by reading the literal file name in the
  call.

That is why the shared files live in `src/` rather than `hdl/`, and why
`puzzle_core.v` says `$readmemh("image.mem")` with a bare name. Vivado finds
the same bare name because `create_project.tcl` adds both `.mem` files to
the project. Icarus finds it because the testbenches run from `src/`.

## Using your own picture

```sh
python3 scripts/gen_image.py my_picture.jpg --preview /tmp/preview.png
```

The script centre-crops the picture to 4:3, scales it to 320x240, reduces
it to 256 colours, and rewrites `src/image.mem` and `src/palette.mem`. With
no argument it writes the built-in test scene (a lake at dusk, original
procedural art). The puzzle is easiest when each part of the picture looks
different: a large plain sky makes for tiles that cannot be told apart. Then
rerun the simulations; nothing in them depends on which picture it is.

## Building

### AX7010

```sh
cd project04_slidepuzzle
vivado -mode batch -source scripts/create_project.tcl
```

Then open `vivado_project/ax7010_slidepuzzle.xpr`. Run Synthesis ->
Implementation -> Generate Bitstream, and program the board from Hardware
Manager.

Implemented on the xc7z010 (Vivado, after place and route):

| Resource | Used | of |
|---|---|---|
| Slice LUTs | 929 | 17600 |
| Registers | 535 | 35200 |
| Block RAM tiles | 24.5 | 60 |
| DSP48 | 2 | 80 |

- **Block RAM:** the picture takes 24 RAMB36 and the palette one RAMB18.
- **DSPs:** the iris's `dx^2` and `dy^2` use the two DSPs.
- **Timing:** met at 25.175 MHz with 17.8 ns of slack.
- **Warnings:** Vivado reports reading both `.mem` files. The only warning
  is the usual `sys_clk` redefinition by the Clocking Wizard.

### VGA Playground

The playground loads from a public GitHub branch whose root holds
`info.yaml`. This repo keeps the project in a subfolder, so a script builds
that branch from the committed HEAD:

```sh
project04_slidepuzzle/scripts/make_playground_branch.sh          # build project04-playground locally
project04_slidepuzzle/scripts/make_playground_branch.sh --push   # and push it
```

Then open
<https://vga-playground.com/?repo=https://github.com/cp-chula-coursework/2110597-GRAPH-SYS-ARCH&ref=project04-playground>.
Turn on Gamepad mode and use the arrow keys.

## Verification

Both testbenches run from `src/` so that the `.mem` files are found:

```sh
cd project04_slidepuzzle/src
iverilog -o /tmp/tb_puzzle.vvp ../sim/tb_puzzle.v puzzle_core.v vga_timing.v
vvp /tmp/tb_puzzle.vvp && python3 ../sim/check_frames.py

iverilog -o /tmp/tb_tt.vvp ../sim/tb_tt.v tt_um_hextex_slidepuzzle.v \
         puzzle_core.v vga_timing.v gamepad_pmod_rx.v
vvp /tmp/tb_tt.vvp && python3 ../sim/check_tt.py

# shuffle soak: six full 200-move shuffles, each checked for solvability
iverilog -P tb_puzzle.SHUF=200 -P tb_puzzle.REPLAY=0 -o /tmp/tb_soak.vvp \
         ../sim/tb_puzzle.v puzzle_core.v vga_timing.v
vvp /tmp/tb_soak.vvp

# the AX7010 top's buttons (Clocking Wizard and hdmi_tx stubbed in the bench)
iverilog -o /tmp/tb_top.vvp ../sim/tb_top.v ../hdl/top.v ../hdl/pad_input.v \
         puzzle_core.v vga_timing.v
vvp /tmp/tb_top.vvp
```

**`tb_puzzle.v`** plays a whole game at real 640x480 timing.

- It watches the shuffle move by move. Then it undoes the shuffle by
  pressing the same directions in reverse order, which must solve the board
  and trigger the win.
- Along the way it checks that:
  - every board is a permutation with solvable parity;
  - a move off the edge of the board changes nothing;
  - a press during a slide is ignored;
  - peek blocks moves.
- It dumps seven frames: title, shuffled, peek, mid-slide, mid-iris, final,
  and soak in the soak run.
- `check_frames.py` rebuilds every pixel of every frame from `image.mem`,
  `palette.mem` and the logged board state alone, then compares exactly.

**`tb_tt.v`** drives the playground top the way the playground does.

- The gamepad model is a line-for-line copy of the playground's
  `updateGamepadPmod()`.
- It checks that:
  - start, the arrows and select each act exactly once per press;
  - each switch flip is one press;
  - a switch already on through reset is not a press;
  - `ui_in[7]` reshuffles;
  - the sync pulses on `uo_out[7]` / `uo_out[3]` are 96 clocks / 2 lines.
- `check_tt.py` decodes the title frame from `uo_out` with the playground's
  own bit mapping and compares it exactly against the dithered picture.

**`tb_top.v`** runs the AX7010 top's button path at the real 5 ms debounce.
The Clocking Wizard and `hdmi_tx` are stubbed, because they exist only
inside Vivado, and the picture behind them is already checked by
`tb_puzzle.v`. Presses are counted where they reach the core. It checks:

- power-on reset;
- a 2 ms blip is filtered out;
- any key on the title starts a game;
- up then down gives one up, no down and a reshuffle, even when the up
  started a slide;
- left then right peeks while held, with one left and no right;
- the J10 direction and start buttons work;
- every push is exactly one press.

## Outstanding for submission

- [ ] Load it live in the VGA Playground (push `project04-playground`)
- [ ] Hardware bring-up on the AX7010
- [ ] Video of it running on real hardware
- [ ] Short written explanation of the hardware
- [ ] Swap the test scene for the final picture (`scripts/gen_image.py`)
