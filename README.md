# Todos (in order)

Stuff that needs to be done, may be incomplete.

## Kicad
- Unify all MOSFET gate resistors to 1k
- Recalculate LED resistors according to the P-MOS
  - check if worst- and best-case (one LED on vs. all LEDs on) makes an impact
  - check if makes an impact with the final size of 32 LEDs in a row
- Finish up schematic
- Solder small version and clock in example data with push-buttons

## HDL
- Write a functional model that represents the small LED board
- Calculate timings / timing limits (shift register clocks, strobing frequency, ...)