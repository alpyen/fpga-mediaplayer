# HDL Code Documentation

This document contains the detailed architecture for the VHDL code of the modules, how they work and how they interact with another.

> Note: Some details, especially technical details, can be found within the code and won't be discussed here.
> So make sure you check the source files aswell!


## Navigation

1. [Top Level Overview](#top-level-overview)
2. [Top Level Entity (TLE)](#top-level-entity-tle)
3. [Memory Driver](#memory-driver)
4. [Audio Driver](#audio-driver)
5. [Video Driver](#video-driver)
6. [i2s Master](#i2s-master)
7. [Board Driver](#board-driver)


## Top Level Overview

To better illustrate how the modules interconnect, here's the top level view of the system again.
It is not exactly identical to the actual code as some modules are contained within others but the general
dataflow is shown pretty well.

<img src="top-level-view.svg" />


## Top Level Entity (TLE)

Source File: [hdl/fpga_mediaplayer.vhdl](../hdl/fpga_mediaplayer.vhdl)

The TLE instantiates all top level components such as the several drivers,
the control unit, clocking and FIFOs to buffer data in between them.
What's not shown in the overview is the synchronization and debouncing of the two pushbuttons for resetting and playing.

Generics allow to parameterize the TLE to support different sizes of LED boards by passing the `WIDTH` and `HEIGHT`.
To cut the time during simulation the `SIMULATION` parameter is used  to disable the synchronization and debouncing of the pushbuttons
to start the playback.

Other than that, the TLE is quite unspectacular as there is no functionality implemented directly in it other than instantiating
the modules and presenting the interface to the outside world for the SPI flash memory, LED Board and i2s2 PMOD.


## Memory Driver

Source File: [hdl/memory/spi_memory_driver.vhdl](../hdl/memory/spi_memory_driver.vhdl)

The memory driver has an interface to connect to the control unit that requests certain addresses from the memory to be read.

```vhdl
-- Memory Driver Interface (in the entity definition)
address: in std_ulogic_vector(23 downto 0);
data: out std_ulogic_vector(7 downto 0);

start: in std_ulogic;
done: out std_ulogic;
```

As you can see this interface completely hides from what resource the memory driver actually reads from. This is intentional
so that it could be expanded to different storage media such as USB, DDR or SD. Because of this the control unit does not need
to care where the data comes from as long as the memory driver, in this case the spi_memory_driver, implements this interface.

A basic memory transaction works by asserting the address lines and start signal for at least one clock cycle.
The memory driver latches this data and dispatches a basic READ command to the SPI flash onboard. When the data starts returning
from the flash, the memory driver will shift it onto the data lines. Upon asserting the done signal, the data lines are valid.

The done signal will be held until the next transaction starts.


## Audio Driver



## Video Driver



## i2s Master



## Board Driver
