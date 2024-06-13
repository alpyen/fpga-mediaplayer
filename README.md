# Todos

Stuff that needs to be done, may be incomplete and not in order.

## Project

## HDL
- Implement the Video Driver and Board Driver
  - Figure out the logic for the frame available/processed, this has to be reset in the fsm, not the decode fsm
  - Frame Buffer needs to be cleared/ignored when decoding initial frame
  - Video Fifo can contain bits after the last frame has been decoded due to the full byte padding
    - They need to be flushed out before marking playback as done.
      - We need to make sure video_play is low and we encounter an empty video fifo during decoding.
  - Calculate how long the frame decode takes after starting playback
    - if the duration is short enough, we don't need to pre-decode the first frame when the video fifo is filling up (which would in turn cause problems detecting the end of the file)
  - Check how much cumulative skew the fsms generate (if any)
- Write notes about clock calculation
- Media notes say sampling rate is 22,050 Hz, wasn't this changed to 44,100 Hz?
- Frame Buffer
  - Check if it's better to restrict the ports as much as possible or two make them less restrictive
- Control Unit
  - Use Generic for Memory Address width that is set in the TLE and passed to the CU and AD
  - Add Base Address to the TLE so the data is not assumed to be at address zero
- Vendor agnostic
  - move all vendor specific stuff into entities

## Vivado
- Change the board store in the project-tcl to be OS-independent
- Add custom command to write project tcl
  - add two scripts for loading and storing that just need to be sourced?

## Software
- Codec development
  - Add documentation on how to set up codec env with libraries and how to encode files
  - Wrap around 4 bit during encoding to save even more space
  - Check if the bitcrushing to 4 bits is correct and compresses uniforly
  - Adjust codec and player to playback various sized files
    - command-line option to set target resolution
    - this is so we can use the small and led board by just setting the generics

- Add output file display in summary of codec
- Add ffmpeg parameter to enforce grayscale to save space or force specific format?

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
