# Notes

Contains some thoughts over the development time of the project.

- Is it worth separating the SCK and RCK lines for the row selection shift registers?
  - They could be tied together, all that needs to be done is to clock once more because the data is behind one clock cycle, but it would save one line to the FPGA.
- The small LED board has the IRF4905 P-MOSFET on it, it seems like they are not a good fit, they will be exchanged for the bigger board.
  - They are on there because I ordered them thinking they were a good fit.
  - They work fine but will mess up operating the LEDs at the target voltage/current because the voltage drop changes heavily depending on the current running through it (dependant on how many LEDs are on)