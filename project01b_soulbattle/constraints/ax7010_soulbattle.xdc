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
##   5V                   red      -            header pin 2 (the adapter has
##                                              its own 3.3V regulator)
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
set_property PULLUP true [get_ports {ps2_clk}]   ## holds it high while the port test lets go

set_property PACKAGE_PIN F17 [get_ports {ps2_cmd}]
set_property IOSTANDARD LVCMOS33 [get_ports {ps2_cmd}]
set_property SLEW SLOW [get_ports {ps2_cmd}]
set_property PULLUP true [get_ports {ps2_cmd}]   ## holds it high while the port test lets go

set_property PACKAGE_PIN F19 [get_ports {ps2_att}]
set_property IOSTANDARD LVCMOS33 [get_ports {ps2_att}]
set_property SLEW SLOW [get_ports {ps2_att}]
set_property PULLUP true [get_ports {ps2_att}]   ## holds it high while the port test lets go

## Bring-up note: whichever pin was given to ps2_dat did not register being
## earthed, on three different pins (F20, G20, F19), while that same F19 did
## register while it carried ps2_att. The one difference was the port
## direction, so ps2_dat is now declared inout and let go rather than being a
## plain input - see battle_core.v. The pin map below is the tidy one, with all
## four signals in the top three rows of the header.
##
## Keep a series resistor of about 1k on DATA. The adapter pulls the line to
## 5V through its own pull-up and this input is not 5V tolerant; without the
## resistor the pin's clamp diode carries the whole current.
set_property PACKAGE_PIN F20 [get_ports {ps2_dat}]
set_property IOSTANDARD LVCMOS33 [get_ports {ps2_dat}]
set_property PULLUP true [get_ports {ps2_dat}]

## Board LEDs, used as PlayStation-controller diagnostics (see battle_core.v).
## Active low: VCCIO_35 -> 330R -> LED -> FPGA pin, so a 0 lights the LED.
set_property PACKAGE_PIN M14 [get_ports {led[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]

set_property PACKAGE_PIN M15 [get_ports {led[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]

set_property PACKAGE_PIN K16 [get_ports {led[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]

set_property PACKAGE_PIN J16 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]

## External push buttons on expansion connector J10 (the IO1 header, on the
## opposite edge of the board from J11). Each button just shorts its pin to
## ground; the pins hold themselves high, so there is no supply involved and
## nothing that can be driven into them that they would not survive.
##
##   button    J10 pin   net       package pin
##   --------  --------  --------  -----------
##   up            3     IO1_1N    W19
##   down          4     IO1_1P    W18
##   left          5     IO1_2N    R14
##   right         6     IO1_2P    P14
##   confirm       7     IO1_3N    Y17
##   common GND    1     -         -
##
## Careful: J10 numbers the opposite way round from J11 - its pin 1 is at the
## BOTTOM of the header, marked by the square pad. Pin 2 is 5V; leave it alone.
##
## Leaving these pins unwired is fine: they read as "not pressed" and the
## board's own four buttons carry on as before.
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

## PS2-to-serial adapter (the board with its own microcontroller on it, which
## talks the PlayStation protocol to the pad and sends the result on as an
## 8-byte packet). Only its TXD is needed - nothing is ever sent back to it.
##
##   adapter pin   goes to             J10 pin   package pin
##   -----------   -----------------   -------   -----------
##   TXD           uart_rx_pin         8         Y16
##   GND           header GND          1         -
##   VCC           header 3V3          39 or 40  -
##   RXD           leave unconnected   -         -
##
## Power it from 3.3V, not the 5V on pin 2: at 3.3V its TXD swings 3.3V and
## can be wired straight in. A 1k resistor in series with TXD costs nothing
## and means a module that turns out to drive 5V cannot hurt the input.
set_property PACKAGE_PIN Y16 [get_ports {uart_rx_pin}]
set_property IOSTANDARD LVCMOS33 [get_ports {uart_rx_pin}]
set_property PULLUP true [get_ports {uart_rx_pin}]
