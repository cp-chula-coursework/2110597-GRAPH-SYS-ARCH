## ax7010_slidepuzzle.xdc
## Pin constraints for the AX7010 (XC7Z010-1CLG400C) image slide puzzle.
## Clock, buttons and HDMI are the same pins as every other project in this
## repo. The optional J10 buttons are project01b_soulbattle's wiring.

## 50 MHz onboard oscillator
set_property PACKAGE_PIN U18 [get_ports {sys_clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {sys_clk}]
create_clock -period 20.000 -waveform {0.000 10.000} [get_ports sys_clk]

## Push buttons (active-low: idle=1, pressed=0)
## key[0]=up  key[1]=down  key[2]=left  key[3]=right
set_property PACKAGE_PIN N15 [get_ports {key[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key[0]}]

set_property PACKAGE_PIN N16 [get_ports {key[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key[1]}]

set_property PACKAGE_PIN T17 [get_ports {key[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key[2]}]

set_property PACKAGE_PIN R17 [get_ports {key[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key[3]}]

## Optional external buttons on expansion connector J10. Each one shorts its
## pin to ground; the internal pull-ups hold the pins high otherwise, so with
## nothing wired they read "not pressed".
##
##   button    J10 pin   net       package pin
##   --------  --------  --------  -----------
##   up            3     IO1_1N    W19
##   down          4     IO1_1P    W18
##   left          5     IO1_2N    R14
##   right         6     IO1_2P    P14
##   start         7     IO1_3N    Y17
##   common GND    1     -         -
##
## J10's pin 1 is at the bottom (square pad), and pin 2 is 5V - leave it alone.
set_property PACKAGE_PIN W19 [get_ports {ext_key[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ext_key[0]}]
set_property PULLUP true [get_ports {ext_key[0]}]

set_property PACKAGE_PIN W18 [get_ports {ext_key[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ext_key[1]}]
set_property PULLUP true [get_ports {ext_key[1]}]

set_property PACKAGE_PIN R14 [get_ports {ext_key[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ext_key[2]}]
set_property PULLUP true [get_ports {ext_key[2]}]

set_property PACKAGE_PIN P14 [get_ports {ext_key[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ext_key[3]}]
set_property PULLUP true [get_ports {ext_key[3]}]

set_property PACKAGE_PIN Y17 [get_ports {ext_key[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {ext_key[4]}]
set_property PULLUP true [get_ports {ext_key[4]}]

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
