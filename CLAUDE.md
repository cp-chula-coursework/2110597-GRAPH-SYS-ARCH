# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

Coursework for **2110597 (Graphics System Architecture)**, Chulalongkorn University. The course teaches FPGA graphics-pipeline design through the history of game consoles - each project recreates a console generation's hardwired (no CPU, no software) graphics hardware in Verilog, targeting real hardware.

Layout: each subfolder is a self-contained Vivado project (`hdl/`, `constraints/`, `scripts/create_project.tcl`, own `README.md`). Non-graded exploratory work uses plain folder names (`demo_test_pattern/`); graded assignments follow `projectNN_<name>` (e.g. `project01_pong`, next would be `project02_...`) - always use this convention for new graded projects, never `pong/`, `01_pong/`, etc.

See the root [`README.md`](README.md) for a per-project walkthrough.

## Hardware target

All projects target the **ALINX AX7010** board:

- Zynq-7000 SoC, part `xc7z010clg400-1` (Vivado part string)
- 50 MHz onboard oscillator on pin `U18` (LVCMOS33)
- Video output is **HDMI only** - there is no VGA DAC on this board. TMDS is generated entirely in FPGA fabric (8b/10b encoding + `OSERDESE2` serialization), not offloaded to a PHY chip.
- 4 active-low push buttons for input where a project needs it

## Language: pure Verilog only

Write all RTL in plain Verilog - **no VHDL**, even when a proven reference implementation (e.g. Digilent's `rgb2dvi`) is VHDL-only; port the algorithm to Verilog instead of pulling in VHDL sources. No third-party packaged IP beyond Vivado's own Clocking Wizard (`clk_wiz`).

Where course reference material or slides assume a VGA connector, adapt by keeping the taught game/timing logic as-is and swapping only the final output stage for the HDMI/TMDS pipeline built in `demo_test_pattern/` (`hdmi_tx.v` + `tmds_encoder.v` + `oserdes_tmds.v`) - reuse those three files unchanged in new projects rather than rewriting them.

## Build commands

Each project builds the same way, with Vivado on `PATH`:

```sh
cd <project_folder>
vivado -mode batch -source scripts/create_project.tcl
```

This creates `<project_folder>/vivado_project/` (git-ignored) with sources, constraints, and the Clocking Wizard IP added, but does not run synthesis. Open the generated project in the Vivado GUI, then run Synthesis -> Implementation -> Generate Bitstream, then use Hardware Manager to program the board over JTAG.

## Verification before hardware

There's no formal test suite. Verify new/changed Verilog with Icarus Verilog before considering it hardware-ready:

```sh
iverilog -o /tmp/sim.vvp <files under test> <testbench.v>
vvp /tmp/sim.vvp
```

Notes from past testbenches in this repo:
- Xilinx UNISIM primitives (`OSERDESE2`, `OBUFDS`) and the Vivado-generated `clk_wiz_*` IP don't exist under `iverilog` - "unknown module" errors for just those are expected and harmless; everything else should elaborate cleanly.
- Icarus's `force`/`release` on hierarchical signals with non-constant RHS is unreliable ("procedural continuous assignments are not yet fully supported"). Drive genuine top-level module inputs instead of forcing internal state when writing testbenches.

## Assignment submission shape

Graded projects (`projectNN_*`) typically require: Verilog source (this repo), a video of the design running on real hardware, and a short written explanation of the hardware. The video/writeup aren't part of this repo - flag them as outstanding in the project's own README until the user confirms hardware bring-up and provides/requests writeup help.
