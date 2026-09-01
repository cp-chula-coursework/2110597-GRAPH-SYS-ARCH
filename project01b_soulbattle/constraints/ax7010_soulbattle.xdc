## ax7010_soulbattle.xdc
## Pin constraints for the AX7010 (XC7Z010-1CLG400C) Soul Battle project.
## HDMI pins verified against ALINX's official AX7010 course example
## (course_s1_fpga/13_hdmi_out/.../hdmi_out_test.xdc); button pins verified
## against course_s1_fpga/06_key/.../key.xdc.

## 50 MHz onboard oscillator
set_property PACKAGE_PIN U18 [get_ports {sys_clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {sys_clk}]
create_clock -period 20.000 -waveform {0.000 10.000} [get_ports sys_clk]

## Push buttons (active-low: idle=1, pressed=0)
## key[0]=up  key[1]=down  key[2]=left  key[3]=right (all four are needed
## for four-way movement; a press of any of them also serves as "confirm"
## on the attract, win and game-over screens)
set_property PACKAGE_PIN N15 [get_ports {key[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key[0]}]

set_property PACKAGE_PIN N16 [get_ports {key[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key[1]}]

set_property PACKAGE_PIN T17 [get_ports {key[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key[2]}]

set_property PACKAGE_PIN R17 [get_ports {key[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key[3]}]

## HDMI output enable
set_property PACKAGE_PIN V16 [get_ports {hdmi_oen}]
set_property IOSTANDARD LVCMOS33 [get_ports {hdmi_oen}]

## HDMI TMDS clock (negative leg auto-paired by Vivado from the device's
## differential pin pair, only the positive leg needs a PACKAGE_PIN)
set_property PACKAGE_PIN N18 [get_ports {TMDS_clk_p}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_clk_p}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_clk_n}]

## HDMI TMDS data channels 0-2
set_property PACKAGE_PIN V20 [get_ports {TMDS_data_p[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[0]}]

set_property PACKAGE_PIN T20 [get_ports {TMDS_data_p[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[1]}]

set_property PACKAGE_PIN N20 [get_ports {TMDS_data_p[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[2]}]

## PlayStation (PSX/PS2) controller, on expansion connector IO2.
## Pin names are the AX7010 net names; the package pins are what Vivado wants.
##
##   controller wire      colour   direction   net       package pin
##   -------------------  -------  ----------  --------  -----------
##   CLOCK                blue     FPGA -> pad  IO2_1P    F16
##   COMMAND              orange   FPGA -> pad  IO2_1N    F17
##   ATTENTION            yellow   FPGA -> pad  IO2_2P    F19
##   DATA                 brown    pad -> FPGA  IO2_2N    F20   (open drain)
##   3.3V                 red      -            3V3 pin on the same header
##   GND                  black    -            GND pin on the same header
##
## ACKNOWLEDGE (green) and the 7V rumble supply (purple) are left
## unconnected: the byte gap ps2_pad uses is longer than the controller's
## worst-case acknowledge, and nothing here drives the rumble motors.
##
## DATA is open drain and needs a pull-up to 3.3V. The internal one below is
## enough for a short lead; add an external 1k for a full-length cable.
set_property PACKAGE_PIN F16 [get_ports {ps2_clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {ps2_clk}]
set_property SLEW SLOW [get_ports {ps2_clk}]

set_property PACKAGE_PIN F17 [get_ports {ps2_cmd}]
set_property IOSTANDARD LVCMOS33 [get_ports {ps2_cmd}]
set_property SLEW SLOW [get_ports {ps2_cmd}]

set_property PACKAGE_PIN F19 [get_ports {ps2_att}]
set_property IOSTANDARD LVCMOS33 [get_ports {ps2_att}]
set_property SLEW SLOW [get_ports {ps2_att}]

set_property PACKAGE_PIN F20 [get_ports {ps2_dat}]
set_property IOSTANDARD LVCMOS33 [get_ports {ps2_dat}]
set_property PULLUP true [get_ports {ps2_dat}]
