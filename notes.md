# Notes

Contains some thoughts over the development time of the project.

- Is it worth separating the SCK and RCK lines for the row selection shift registers?
  - They could be tied together, all that needs to be done is to clock once more because the data is behind one clock cycle, but it would save one line to the FPGA.
- The small LED board has the IRF4905 P-MOSFET on it, it seems like they are not a good fit, they will be exchanged for the bigger board.
  - They are on there because I ordered them thinking they were a good fit.
  - They work fine but will mess up operating the LEDs at the target voltage/current because the voltage drop changes heavily depending on the current running through it (dependant on how many LEDs are on)
  - Maybe I messed up with the test circuit, I will test again with 32 LEDs for the bigger version when designing that.
- Pullup for logic shifters is 10K which would lead to asymmetrical charge times for the shift registers.
  - See how long it actually takes to charge the lines up with 10K.
- Shift register is CMOS and the inputs have high-impedances so leaving out current limiting resistors.
  - However they are needed for N-MOSFET and P-MOSFET for example (to protect the device that is delivering the current).
  - I think they can be left out if the power supply delivers the current, and not a µC which has output current limitations.
- Pullups for Logic Shifter Drains / Shift Register Inputs are not suitable for the full size board.
  - It seems like it takes a few microseconds to charge up through a 10K, this will be a big problem depending on the video properties. 24fps / 8bpp will need much lower resistor values.