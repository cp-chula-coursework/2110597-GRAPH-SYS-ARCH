## ax7010_pong.xdc
## Pin constraints for the AX7010 (XC7Z010-1CLG400C) Pong project.
## HDMI pins verified against ALINX's official AX7010 course example
## (course_s1_fpga/13_hdmi_out/.../hdmi_out_test.xdc); button pins verified
## against course_s1_fpga/06_key/.../key.xdc.

## 50 MHz onboard oscillator
set_property PACKAGE_PIN U18 [get_ports {sys_clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {sys_clk}]
create_clock -period 20.000 -waveform {0.000 10.000} [get_ports sys_clk]

## Push buttons (active-low: idle=1, pressed=0)
## key[0]=reset  key[1]=up  key[2]=down  key[3]=spare
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
