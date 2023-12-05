# Automatically created by the Clocking Wizard IP, commented out to not trigger critical warnings.
# create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clock100mhz];

# Set clocks groups such that we do not time paths between the fabric clock and the i2s-fabric clock.
# There are synchronizers and a handshake protocol in place to handle proper communication.
set_clock_groups -name fabric_and_i2s -asynchronous \
    -group [get_clocks -of_objects [get_pins clocking_wizard_inst/clock10mhz]] \
    -group [get_clocks -of_objects [get_pins clocking_wizard_inst/clock11_2896mhz]]
