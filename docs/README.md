# Documentation Overview

**Welcome to the Documentation Overview!**<br>

The documentation is organized into several markdown README files and source files.
Most of it is contained within the README files, the more technical details -
if no separate file exists - is found within the code itself.


## Navigation

1. [Documentation Links](#documentation-links)
2. [Repository Organization](#repository-organization)


## Documentation Links

Below you'll find a list linking to each part of the documentation along
with a short description:

- [Media Specification](media.md)
  - Constraints and goals that the media has and wants to achieve.
  - Codec to encode uncompressed media and decode compressed media.
  - File structure to hold the encoded media file with metadata.
- [Memory Considerations](memory.md)
  - Notes about the memory interface in regards to bandwidth and clock frequency.
- [General Notes](notes.md)
  - Scratchpad used during the development of the project to note down thoughts.
- [HDL Code](hdl.md)
  - Notes about the inner workings of the modules.
  - Notes about the high level interactions between the moduels.
- [KiCAD PCBs](kicad.md)
  - General overview and considerations of the PCBs
  - Notes about the different LED Board iterations
- [Python Scripts](python.md)
  - Generate a virtual environment to execute python scripts in.
  - Encode media files into the project format.
  - Playback encoded media files with a software player.
  - Append media and FPGA bitfile for playback without USB reflashing.
- [Vivado](vivado.md)
  - Manage the project with the project tcl script.
  - Differences between the simulation and actual hardware implementation.
  - Synthesize the project into a bitfile.
  - Flash the FPGA directly or the onboard memory chip.


## Repository Organization

Here's a short description on what each subfolder in the project repository contains:

- [`boards/`](../boards) - Vivado board definitions (Basys3 only). The project's board repo path links here.
- [`constraints/`](../constraints) - Vivado pin and timing constraints for synthesis and implementation (Basys3 only).
- [`docs/`](../docs) - Documentation README files about each of the folders in the repository root.
- [`hdl/`](../hdl) - VHDL source code used for synthesis and implementation organized
  into different subfolders based on the functionality.
- [`ip/`](../ip) - Vivado IP configuration organized into subfolders for clocking and audio/video FIFOs.
- [`kicad/`](../kicad) - KiCAD schematics, PCBs and symbol library organized into subfolders for
  the small and fullsize LED board.
- [`python/`](../python) - Python scripts for encoding media files, playing back the encoded files in software and media files for testing and simulation.
- [`sim/`](../sim) - VHDL source code only for simulation. Contains testbench and functional
  implementations of third party components.
- [`vivado/`](../vivado) - Vivado project folder to generate the output files in. Contains the tcl
  file necessary to regenerate this project when cloned.
