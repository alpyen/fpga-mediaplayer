# Vivado Documentation

This document guides you through the steps in Vivado to get this project running.

## Navigation

1. [Managing the project](#managing-the-project)
   1. [Opening](#opening)
   2. [Saving](#saving)
2. [Simulation differences](#simulation-differences)
3. [Synthesizing bitfile](#synthesizing-bitfile)
4. [Flashing the FPGA](#flashing-the-fpga)

## Managing the project

> Note: This project was developed with Vivado 2023.2 and uses basic Xilinx IP cores
> which should be also be compatible with previous/future versions of Vivado.

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

For the simulation, only the small version of the LED board (8x6) is simulated
and the flash chip has not only been capped to 8 kilobytes (instead of 4 Megabytes) but also only implements the basic READ command.
That also means that the media files ingested into the simulation are also
rather tiny.

Apart from the board and flash memory the buttons are synchronized and debounced
on the real hardware. This has also been disabled for the simulation.

These differences are toggled through the parameter `SIMULATION` in the
top level entity's generic map which is false by default but enabled
by the testbench file `sim/fpga_mediaplayer_tb.vhdl`.

With these modifications the simulation time is cut down to a fraction of the
time actually needed for the full hardware.


## Synthesizing bitfile

The project is set up to synthesize and implement on a Digilent Basys3 where
the LED board connects to the JA-PMOD header on the top left and the
Digilent i2s2 PMOD to the the JB-PMOD header on the top right.

In case you want use a different board, make sure you edit the project settings
and adjust your constraints accordingly.
If everything is set, you can directly generate the bitstream.


## Flashing the FPGA

Loading the synthesized bitfile onto the FPGA is done the usual way so we'll only
discuss the steps to write the bitstream and media on the onboard flash memory
and boot it from there. See [Python Scripts Documentation](python.md)
on how to generate the media files or combine them with the bitstream.

> Note: The project supports only loading the media file through an SPI connection
> which means only boards that have an onboard flash memory with SPIs are
> supported. Loading the media through USB or other means is theoretically
> possible but outside the scope of this project.

Plug in your board and connect to it via the Vivado hardware manager.

First we need to set up the memory configuration. As stated in the
[Memory Documentation](memory.md) the Basys3 comes with different
memory chips - I happend to have the MX25L3233F.
Right click the xc7a35t chip and select "Add Configuration Memory Device...".
Search for the chip you have, you may not find the exact one but as long
as the name pops up on the alias column it's fine.

Vivado will prompt you to program the memory device, you can select "no".
Programming this through the hardware manager is done by right clicking the
memory chip entry that popped up below the chip in the hardware window.
Select the option "Program Configuration Memory Device...".

In the following window select an encoded media file or a bitstream concatenated
with a mediafile and click on "OK". The programming will take a few seconds
depending on how big the file size is.

> Note: Flashing will fail if the file to write is larger than the memory capacity.

Programming the flash will load a different bitstream onto the FPGA so
reprogram the FPGA with the bitstream afterwards if you don't have the bitstream
burned onto the flash chip.

If you've opted to write the bitstream also on the flash make sure you
power off the board, move the "JP1" boot mode jumper to QSPI from USB
and power it back up.

Once everything is set up correctly, you should be able to play back the media
file by pressing the right push button on the board and resetting the board by
pressing the left push button.
