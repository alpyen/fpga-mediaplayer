# Todos (in order)

Stuff that needs to be done, may be incomplete.

## HDL
- Write a functional model that represents the small LED board
- Calculate timings / timing limits (shift register clocks, strobing frequency, ...)

# Project Goal

This is a personal project to deep dive into FPGA development and get in touch with every part of it
and to learn also a little bit about electrical engineering.

The vision is to have Basys3 board drive a selfmade LED matrix playing back a grayscale video and 
outputting sound simultaneously.

Some of the decisions along the way are deliberately made in a non-optimal way such as writing
hdl descriptions for components that already exist to have it done myself and to constrain things.

Topics I want to cover (includes, but is not limited to):
- Develop a full FPGA project with everything necessary
- Write HDL and verify with testbenches
- Make use of existing IP
- Prototyping
- Schematics, Layouting and Manufacturing a PCB
- Interface with other onboard components such as memory
- Interface with prebuilt offboard components such as the Digilent I2S2 PMOD
- Interface with external offboard components such as the LED board
- Work within the limits of the given board such as the Digilent Basys3 (Artix7-35T)
  - 4MB Flash (2MB with configuration)
  - Available IO
  - Clock Speed to maintain realtime
- Software development
  - Codec for audio and video
- Miscellaneous
  - Organization of project structure and repository for Git
  - Documentation of the whole project

Please note that these constraints emerged from the components and devices I have at disposal.
This project could be done with greater resolution and sound output but the goal is to bring it up
and learn everything along the way, that's the reason behind the fullstack approach.