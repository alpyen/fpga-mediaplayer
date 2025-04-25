# To-do List

Stuff that needs to be done, may be incomplete and not in order.

- Documentation
  - Write docs/README.md
  - Add Documentation section to project README.md
  - Write documentation for KiCad PCBs
  - Write documentation for HDL

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
3. [Top Level Overview](#top-level-overview)


## Introduction

This is a beginner project on hardware development with FPGAs and VHDL to create a system that can
play audio and video through an FPGA.

A FPGA development board -- here a <a href="https://digilent.com/reference/programmable-logic/basys-3/start">Digilent Basys3</a>
-- fetches audio and video data stored on the on-board flash memory chip,
decodes them and drives a <a href="https://digilent.com/reference/pmod/pmodi2s2/start">Digilent i2s2-PMOD</a>
for audio output and a custom designedLED matrix as the video display.

Originally the idea was to drive one of these standard Arduino LED shields (14x9 pixels) but that plan
was scrapped due to the very low resolution.

The key focus of this project was to accomplish this vision with certain -- partially arbitrary -- constraints
and to get the whole thing done while touching on many aspects of FPGA and electronics development.
It is by no means perfect, but it is done while hitting all the project's goals I set for myself.


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


## Top Level Overview

Here's a top level view of the system. It is build in a modular fashion encapsulating functionality
such that everything remains as local as possible so each module is easy to understand.
Dataflow is indicated by the directional arrows.

The Control Unit requests data from the memory driver which (here) accesses the onboard SPI flash.
It then alternately fills the Audio and Video FIFO which are read by the respective modules
on the other side. Those decode the data and fill up a FIFO for Audio and BRAMs for Video.
After the data is available the i2s Master and Board Driver will read the data at the correct time and
play them back by driving a Digilent i2s2 PMOD and a self designed LED multiplex display.

<img src="docs/top-level-view.svg" />
