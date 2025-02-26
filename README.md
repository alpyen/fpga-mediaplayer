
# To-do List

Stuff that needs to be done, may be incomplete and not in order.

- HDL
  - Implement some sort of luminosity ramp or brightness control
  - Pixels that should be very dim (brightness = 1) can shine very bright.
- Software
  - Implement play/pause into the player
  - Implement audio playback into the player
- Documentation
  - Write README on how to encode and load up the media file into the board's flash and play it back.
  - Update scripts README for merger.py
  - Write README for kicad/
  - Write README for vivado/
    - Move the Vivado project stuff into the corresponding README
  - Clean up main README and docs/ READMEs and restructure
    - One README for subfolders like kicad/ python/
    - Link the sub-READMEs in this project README
  - System Diagram (Top-Level-View)
- Vivado
  - What happens if you try to recreate the project on a Vivado installation that is missing the board files?

<br>
Below is the draft of the repository's readme once the To-do List above is completely worked out.

___
<br>

# fpga-mediaplayer - learning FPGA development

Hi there, and welcome to my FPGA project to deep dive into FPGA development and everything around it.

Watch a demo of this project on YouTube!

## Navigation
1. [Introduction](#introduction)
2. [Project Goal](#project-goal)
3. [Vivado Build](#vivado-build)
   1. [Opening the project](#opening-the-project)
   2. [Saving the project](#saving-the-project)

## Introduction

This is a beginner project on hardware development with FPGAs and VHDL to create a system that can
play audio and video through an FPGA.

A FPGA development board -- here a Digilent Basys3 -- fetches audio and video data stored on the on-board
flash memory chip, decodes them and drives a Digilent i2s2-PMOD for audio output and a custom designed
LED matrix as the video display.

Originally the idea was to drive one of these standard Arduino LED shields (14x9 pixels) but that plan
was scrapped due to the very low resolution.

The key focus of this project was to accomplish this vision with certain -- partially arbitrary -- constraints
and to get the whole thing done while touching on many aspects of FPGA and electronics development.

It is by no means perfect, but it is done while hitting all the project goal's I set for myself.

## Project Goal

The main goal of this project was to get my hands dirty with all parts of FPGA development.
While the main focus is on the actual hardware description, a good amount of time was also spent
on developing the software and electronics side of things to get the full picture.

Besides getting this project actually done,
there were a lot of topics I wanted to cover (which includes, but is not limited to):
- Develop a full FPGA project with everything necessary
- Keep it flexible that it could run on different devices without too much additional effort
- Write HDL and verify with testbenches
- Write packages and make them accessible
- Make use of existing IP
- Prototyping
- Schematics, Layouting and Manufacturing a PCB
- Interface with other onboard components such as the flash memory
- Interface with prebuilt offboard components such as the Digilent I2S2 PMOD
- Interface with external offboard components such as the LED board
- Work within the limits of the given board such as the Digilent Basys3 (Artix7-35T)
  - 4MB Flash (only ~2MB with configuration)
  - Available IO
  - Clock Speed to maintain realtime
- Software development
  - Codec for audio and video
- Miscellaneous
  - Organization of project structure and repository for Git
  - Documentation of the whole project

Please note that these constraints emerged from the components and devices I have at disposal.
This project could be done with greater resolution and sound output but the goal is to bring it up
and learn everything along the way, that's the reason behind this approach.

## Vivado Build

This project was developed using Xilinx Vivado using the non-project mode.

### Opening the project
The vivado project has to be regenerated from the project tcl file.
Simply run Vivado and use the tcl console to `cd` into the vivado subfolder of this repository and run `source ./fpga-mediaplayer.tcl`.

### Saving the project
If you want to update the tcl file make sure to pass the correct project folder.
Vivado creates a subfolder with the name of the project by default which creates unnecessary nesting so you need to run the tcl command manually.

To write the project tcl make sure you're in the vivado subfolder and run this command:<br>`write_project_tcl -target_proj_dir . fpga-mediaplayer.tcl -force`

> Note: Vivado stores absolute paths in the tcl comments, make sure to delete those if you don't want them public.
They can be found at the very top in the big comment.
