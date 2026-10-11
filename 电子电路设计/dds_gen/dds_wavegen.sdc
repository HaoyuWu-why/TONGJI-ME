# Final 50 MHz board clock constraint, refreshed with the September release.
create_clock -name clk50 -period 20.000 [get_ports {CLK}]
