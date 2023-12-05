# Todos

Stuff that needs to be done, may be incomplete and not in order.

## Project

## HDL
- Implement the Audio Driver
  - I2S Master to output samples to I2S2 PMOD-Board
    - i2s_lrck is a fabric clock.
      - Constrain? Test? Does this even work?
  - Add CDC-XDC
  - Add reset to debouncer
  - Use Generic for Memory Address width
  - Add Base Address to the TLE so the data is not assumed to be at address zero
  - Remove the SPI clk driving from the spi_memory_driver
    - TLE is supposed to drive it
- Implement the Video Driver
- Use 7-Segment Display to display the current runtime / total runtime

## Vivado
- Change the board store in the project-tcl to be OS-independent
- Add custom command to write project tcl
  - add two scripts for loading and storing that just need to be sourced?

## Software
- Codec development
  - Expand the existing script to include video

# How to open with Vivado

The vivado project has to be regenerated from the project tcl file.
Simply run Vivado and use the tcl console to `cd` into the vivado subfolder of this repository and run `source ./fpga-mediaplayer.tcl`.

If you want to update the tcl file make sure to pass the correct project folder.
Vivado creates a subfolder with the name of the project by default which creates unnecessary nesting so you need to run the tcl command manually.

To write the project tcl make sure you're in the vivado subfolder and run this command: `write_project_tcl -target_proj_dir . fpga-mediaplayer.tcl -force`

Vivado stores absolute paths in the tcl comments, make sure to delete those if you don't want them public.
They can be found at the very top in the big comment.

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
- Write packages and make them accessible
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
