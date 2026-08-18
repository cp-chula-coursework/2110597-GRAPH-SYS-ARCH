# create_project.tcl
#
# Builds the AX7010 HDMI test-pattern demo as a Vivado project.
#
# Usage:
#   From a shell:            vivado -mode batch -source scripts/create_project.tcl
#   From the Vivado Tcl console (cwd = demo_test_pattern/):
#                             source scripts/create_project.tcl
#
# This only creates the project and adds sources/constraints/IP - it does not
# run synthesis. Open the project in the Vivado GUI afterwards and run
# Synthesis -> Implementation -> Generate Bitstream, then use Hardware
# Manager to program the board.

set script_dir [file normalize [file dirname [info script]]]
set repo_dir   [file normalize [file join $script_dir ..]]
set proj_name  "ax7010_test_pattern"
set proj_dir   [file join $repo_dir "vivado_project"]

create_project -force $proj_name $proj_dir -part xc7z010clg400-1

# ---------------------------------------------------------------------------
# Design sources (pure Verilog)
# ---------------------------------------------------------------------------
add_files -fileset sources_1 [glob $repo_dir/hdl/*.v]

set_property top top [current_fileset]

# ---------------------------------------------------------------------------
# Constraints
# ---------------------------------------------------------------------------
add_files -fileset constrs_1 [glob $repo_dir/constraints/*.xdc]

# ---------------------------------------------------------------------------
# Pixel-clock generator: 50 MHz sys_clk -> 74.25 MHz pixel clock +
# 371.25 MHz (5x) serial clock for TMDS serialization.
#
# These MMCM settings reproduce ALINX's own verified clk_wiz configuration
# for 1280x720 HDMI-out on this exact board/part (see hdmi_out.tcl in
# ALINX's AX7010 course examples), so they're known to lock and to keep the
# two output clocks in an exact 5:1 ratio.
# ---------------------------------------------------------------------------
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_wiz_video
set_property -dict [list \
  CONFIG.PRIM_IN_FREQ {50} \
  CONFIG.NUM_OUT_CLKS {2} \
  CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {74.25} \
  CONFIG.CLKOUT2_USED {true} \
  CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {371.25} \
  CONFIG.CLKIN1_JITTER_PS {200.0} \
  CONFIG.CLKOUT1_JITTER {462.435} \
  CONFIG.CLKOUT1_PHASE_ERROR {610.813} \
  CONFIG.CLKOUT2_JITTER {372.733} \
  CONFIG.CLKOUT2_PHASE_ERROR {610.813} \
  CONFIG.MMCM_CLKFBOUT_MULT_F {59.375} \
  CONFIG.MMCM_CLKIN1_PERIOD {20.000} \
  CONFIG.MMCM_CLKIN2_PERIOD {10.0} \
  CONFIG.MMCM_CLKOUT0_DIVIDE_F {10.000} \
  CONFIG.MMCM_CLKOUT1_DIVIDE {2} \
  CONFIG.MMCM_DIVCLK_DIVIDE {4} \
] [get_ips clk_wiz_video]
generate_target {instantiation_template} \
  [get_files $proj_dir/$proj_name.srcs/sources_1/ip/clk_wiz_video/clk_wiz_video.xci]

update_compile_order -fileset sources_1

puts "Project '$proj_name' created at $proj_dir"
puts "Open it in Vivado, then run Synthesis -> Implementation -> Generate Bitstream."
