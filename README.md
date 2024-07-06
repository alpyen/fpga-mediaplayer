# Todos

Stuff that needs to be done, may be incomplete and not in order.

## Project

## HDL
- Video Driver
  - Adjust HDL and pin constraints to match new board interface
  - Fifo can contain bits after the last frame has been decoded due to the full byte padding
    - They need to be flushed out before marking playback as done.
      - We need to make sure video_play is low and we encounter an empty video fifo during decoding.
  - Test FSM and generated clock skew over four minutes
- Control Unit
  - Add Generic for the Base Address of the media file
    - This will be useful if we store a media file next to the bitstream or when we want to playback two files
  - Restructure to use less FFs
  - Add check for resolution and don't playback when it's incorrect

## Hardware
  - Determine LED resistors
  - TPIC6A595 Open Drain Power Shift Register for low-side switching
  - 74HCT367 Hex-Buffer for level shifting and buffering
  - 74HCT595 instead of 74HC595 to get rid of the level shifters
  - Need to use one wire to disconnect shift register outputs to not overload on unknown power up state
  - No input resistors for shift registers as PMOD JB already has 200 Ohms
  - Pick new high-side MOSFET with low capacitance

## Vivado
- Change the board store in the project-tcl to be OS-independent
- Add custom command to write project tcl
  - add two scripts for loading and storing that just need to be sourced?
- Make sure assertions trigger on synthesis and implementation aswell

## Software
- Codec development
  - Wrap around 4 bit during encoding to save even more space
  - Check if the bitcrushing to 4 bits is correct and compresses uniforly
  - Add resolution to media file

## Documentation
- Write README on how to encode and load up the media file into the board's flash and play it back.

## Compatibility
- Check repo for Ubuntu Linux

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
