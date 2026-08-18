## ax7010_test_pattern.xdc
## Pin constraints for the AX7010 (XC7Z010-1CLG400C) HDMI-out test pattern demo.
## Pin assignments verified against ALINX's official AX7010 course example
## (course_s1_fpga/13_hdmi_out/auto_create_project/src/constraints/hdmi_out_test.xdc).

## 50 MHz onboard oscillator
set_property PACKAGE_PIN U18 [get_ports {sys_clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {sys_clk}]
create_clock -period 20.000 -waveform {0.000 10.000} [get_ports sys_clk]

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
