# Vivado Documentation

This document guides you through the steps in Vivado to get this project running.

## Navigation

1. [Managing the project](#managing-the-project)
   1. [Opening](#opening)
   2. [Saving](#saving)
2. [Simulation differences](#simulation-differences)
3. [Synthesizing bitfile](#synthesizing-bitfile)
4. [Flashing onto the FPGA](#flashing-onto-the-fpga)


## Managing the project

Vivado generates a lot of intermediate files when synthesizing a project which
dramatically increases the repository's size and bloats it unncessarily.

In order to keep the files to track to a minimum, Vivado offers to
regenerate a project from a tcl script.
Not only does this help with version control but it also gets rid off the
absolute paths which are contained in some files making it easier to run
on different machines.


### Opening

When cloning the repo there is no project file available to load directly,
instead the project has to be regenerated from a tcl script first.

Simply run Vivado and use the tcl console to `cd` into the vivado subfolder of this repository and run: `source ./fpga-mediaplayer.tcl`

Vivado will regenerate the project which can be loaded through the main menu
or through the generated xpr project file the next time.

> Note: The tcl script contains the hdl files, constraints, ip configuration,
> and all other relevant paths to create the project. Regenerate the project
> everytime you visit a new commit of this repository.


### Saving

Changes to the project may require saving a new tcl script so that
it can be rebuilt correctly. Adding new source or constraint files
for example whereas modifications to already existing files do not.
Files outside of Vivado's scope like the KiCAD PCBs or media files are irrelevant.

Updating the tcl file is pretty straight forward but one parameter
should be used to avoid unnecessary nesting of the files which is
caused by Vivado placing the project in a subfolder with the project's name.

To write the project tcl make sure you're in the vivado subfolder and run this command:<br>`write_project_tcl -target_proj_dir . fpga-mediaplayer.tcl -force`

> Note: Vivado stores absolute paths in the tcl comments,
> make sure to delete those if you don't want them public.
> They can be found at the very top in the big comment.


## Simulation differences

Even though I mainly verified the circuit with behavioral simulation, it can
take up a lot of time to simulate the peripheral components such as the
flash chip or the LED board.

For the simulation only the small version of the LED board (8x6) is simulated
and the flash chip has not only been capped to 8 kilobytes (instead of 4 Megabytes) but also only implements the basic READ command.
That also means that the media files ingested into the simulation are also
rather tiny.

Apart from the board and flash memory the buttons are synchronized and debounced
on the real hardware. This has also been disabled for the simulation.

These differences are toggled through the parameter `SIMULATION` in the
top level entity's generic map which is false by default but enabled
by the testbench `hdl/fpga_mediaplayer_tb.vhdl`.

With these modifications the simulation time is cut down to a fraction of the
time actually needed for the full hardware.


## Synthesizing bitfile

The project is set up to synthesize and implement on a Digilent Basys3 where
the LED board connects to the JA-PMOD header on the top left and the
Digilent i2s2 PMOD to the the JB-PMOD header on the top right.

In case you want use a different board, make sure you edit the project settings
and adjust your constraints accordingly.
If everything is set, you can directly generate the bitstream.


## Flashing onto the FPGA
