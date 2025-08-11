# HDL Code Documentation

This document contains the detailed architecture for the VHDL code of the modules, how they work and how they interact with another on a high level.

> Note: Some details, especially technical ones, can be found within the code and won't be discussed here.
> The code is written in a pretty straight forward fashion and is commented on the more complicated parts.

## Navigation

1. [Top Level Overview](#top-level-overview)
2. [Top Level Entity (TLE)](#top-level-entity-tle)
3. [Memory Driver](#memory-driver)
4. [Control Unit](#control-unit)
5. [Audio Driver](#audio-driver)
   1. [Control FSM](#control-fsm)
   2. [Decode FSM](#decode-fsm)
   3. [Transfer FSM](#transfer-fsm)
6. [i2s Master](#i2s-master)
7. [Video Driver](#video-driver)
8. [Board Driver](#board-driver)


## Top Level Overview

To better illustrate how the modules interconnect, here's the top level view of the system again.
It is not exactly identical to the actual code as some modules are contained within others but the general
dataflow is shown pretty well.

<picture>
    <source media="(prefers-color-scheme: dark)" srcset="images/top-level-view-dark.png">
    <img src="images/top-level-view-light.png">
</picture>


## Top Level Entity (TLE)

Source File: [hdl/fpga_mediaplayer.vhdl](../hdl/fpga_mediaplayer.vhdl)

The TLE instantiates all top level components such as the several drivers,
the Control Unit, clocking and FIFOs to buffer data in between them.
What's not shown in the overview is the synchronization and debouncing of the two pushbuttons for resetting and playing.

Generics allow to parameterize the TLE to support different sizes of LED boards by passing the `WIDTH` and `HEIGHT`.
To cut the time during simulation the `SIMULATION` parameter is used  to disable the synchronization and debouncing of the pushbuttons
to start the playback.

Other than that, the TLE is quite unspectacular as there is no functionality implemented directly in it other than instantiating
the modules and presenting the interface to the outside world for the SPI flash memory, LED Board and i2s2 PMOD.


## Memory Driver

Source File: [hdl/memory/spi_memory_driver.vhdl](../hdl/memory/spi_memory_driver.vhdl)

The memory driver has an interface to connect to the Control Unit that requests certain addresses from the memory to be read.

```vhdl
-- Memory Driver Interface
address: in std_ulogic_vector(23 downto 0);
data: out std_ulogic_vector(7 downto 0);

start: in std_ulogic;
done: out std_ulogic;
```

As you can see this interface completely hides from what resource the memory driver actually reads from. This is intentional
so that it could be expanded to different storage media such as USB, DDR or SD. Because of this the Control Unit does not need
to care where the data comes from as long as the memory driver, in this case the spi_memory_driver, implements this interface.

A basic memory transaction works by asserting the address lines and start signal for at least one clock cycle when
the memory driver signals it can handle a new request by having the done signal on high.
The memory driver latches this data and dispatches a basic READ command to the SPI flash onboard.
When the data starts returning from the flash, the memory driver will shift it onto the data lines.
Upon asserting the done signal, then the data lines are valid.

The done signal will be held until the next transaction starts.

For simplicity's sake, the SPI flash is clocked with the same speed as the main clock used for most of the design
with 10 MHz, this is because the connection is unstable with higher clock frequencies on the Basys3. This is explained
in the [memory considerations](memory.md).


## Control Unit

Source File: [hdl/control/control_unit.vhdl](../hdl/control/control_unit.vhdl)

The Control Unit is the core of the design and handles the loading of the media file from the memory driver,
feeding the FIFOs for the audio and video drivers with data and reading the state of the push buttons for reset
and play.

It like most modules is implemented through a FSM, here's a rough description:

First it reads as many bytes
as a media header is wide from the given media base address. After that's done
it will check if the header contains the valid begin and end signatures
to make sure it doesn't play random data. It will also check if the resolution
of the media file is larger than what is given through the generics.

After the checks have passed, the Control Unit will start to preload data
into the FIFOs until either the media file is completely read or the FIFOs
filled up completely. This is done this way because the Control Unit will
alternately fill the buffers and not check which one is missing more data.
There are two main reasons for this, one- it dramatically simplifies the
control logic, two- the code, FIFO IP and hardware constraints are designed in
such a way, that even though we will feed them alternately, it is impossible to
run the buffers dry.

Once the preloading is done, the Control Unit will tell the audio and video
driver to start the playback. During playback it will keep the FIFOs
as full as possible and return to an idle state when the FIFOs are empty
and both drivers have asserted their done signal.

Since the decoding is handled in the each driver respectively, the control
unit will feed the FIFOs with full bytes. The Audio FIFO is 16 words
deep, each 8 bit, the Video FIFO is 1024 words deep, each also 8 bit.
Some testing showed that this is sufficient enough for this project.


## Audio Driver

Source File: [hdl/audio/audio_driver.vhdl](../hdl/audio/audio_driver.vhdl)

The audio driver implements two interfaces where one of them connects
to the Control Unit with a FIFO and the other implements the sound
output which is realized through the i2s protocol.

```vhdl
-- Audio Driver Interface
audio_driver_play: in std_ulogic;
audio_driver_done: out std_ulogic;

-- Audio Fifo
audio_fifo_read_enable: out std_ulogic;
audio_fifo_data_out: in std_ulogic_vector(0 downto 0);
audio_fifo_empty: in std_ulogic;

-- I2S Interface
i2s_mclk: in std_ulogic;
i2s_lrck: out std_ulogic;
i2s_sclk: out std_ulogic;
i2s_sdin: out std_ulogic
```

> Note: The i2s interface is due to the i2s Master instantiated within the
> Audio Driver. Since this project relies on the i2s2 PMOD, it is the protocol
> we implement for sound output.

Compared to the Control Unit, the Audio Driver is much more sophisticated.
It implements three FSMs (Control, Decode and Transfer) and will be explained
one by one.

### Control FSM

Being the simplest of the three, the control fsm only has three states -
`IDLE`, `DECODE` and `WAIT_UNTIL_SAMPLE_PLAYED`.
Once the playback starts, it jumps back and forth the decode and wait state
depending whether the decoding or playback of a sample has finished.

There is no pipelining of decoding and buffering the decoded samples
for the i2s Master to play because the decoding speed is fast enough
even at 10 MHz system clock.

### Decode FSM

This is where the magic happens. When started by the control fsm, the decode
fsm will read from the Audio FIFO and start the decode process.

Because of the straight forward nature of the codec and the bit-by-bit
fetching from the FIFO we can simply express the decoding logic through
FSM states.

> Note: I highly recommend checking the actual VHDL code to see
> how easy it is to implement the decoder this way.

When done with the decoding of a single sample, the fsm will assert
a done signal so the control fsm can instruct the transfer fsm to
send a sample to the i2s Master.

### Transfer FSM

As the i2s2 PMOD needs a specific clock frequency on the i2s mclk line
(11.2896 MHz in our configuration) we need a way to safely cross
the clock domains from the FPGA board clock of 10 MHz to the i2s Master's
clock domain.

The i2s Master, which is the component responsible to drive the i2s lines
to the i2s2 PMOD, is implemented in such a way that it runs its logic
on the required 11.2896 MHz.

> Note: Theoretically we could clock the system clock higher
> and use a phase accumulator like in the Video Driver to run it
> but this way we will learn about proper Clock-Domain-Crossing (CDC)
> which is an essential topic in FPGA-based development.

To bridge this gap safely, we need a solid protocol that will take these
clock differences into account. This is what the transfer fsm is built for.
A detailed description of this protocol along with the timing considerations
can be found in the source code of the i2s Master (at the very bottom) and will be explained here briefly:

The Audio Driver module accepts two generics `CLOCK_SPEED` and
`I2S_MCLK_SPEED` which represent the clock speed of the board and i2s Master
in Hz respectively. From these valus it calculates the minimum
amount clock cycles of each modules own clock cycles to (de)assert a signal
connected to the other clock domain such that the signal will be read correctly.

Because of the different clock speeds and phases the signal transitions
do not always line up on the other sides' flip-flops with valid setup and hold requirements. Holding them long enough solves this problem.
Now all that's left is to actually send the data to the i2s Master and receive
an acknowledgement that the sample was read.

All signals passing clock boundaries are synchronized with two flip flops each.

> Note: The actual CDC-protocol implemented is inherently self clocked
> so that the holding of the transfer signals is probably not necessary.
> This was simply an oversight when implementing both modules.


## i2s Master

Source File: [hdl/audio/i2s_master.vhdl](../hdl/audio/i2s_master.vhdl)

As the driver of the i2s2 PMOD, the i2s Master is the final module on the FPGA
in regards to handling audio. It implements the other side of the transfer fsm
connected to the Audio Driver and the logic to drive the PMOD.

As the i2s protocol itself is a complicated topic on its own, we won't be
diving into any detail here. I suggest reading through the easily digestable
datasheet of the <a href="https://statics.cirrus.com/pubs/proDatasheet/CS5343-44_F5.pdf">Cirrus CS5343</a> (the ADC/DAC chip on the i2s2 PMOD) while looking at the code
which is commented in all the relevant parts.

The only noteworthy topic here is the clocking on the falling edge which is
due to the i2s protocol. The sound chip wants the data to be latched
on the falling edge so it can be read on the next rising edge.
Since we are not fixed to clocking our own user logic on the rising edge -
due to the safe clock domain crossing technique used - we also use
the falling edge to save some FPGA slices.


## Video Driver

Source File: [hdl/video/video_driver.vhdl](../hdl/video/video_driver.vhdl)

The structure of the Video Driver closely mirrors that of the Audio Driver
so only the key differences will be discussed here. In this case it relays
the interface of the module that drives the LED display.

```vhdl
-- Video Driver Interface
video_driver_play: in std_ulogic;
video_driver_done: out std_ulogic;

-- Video Fifo
video_fifo_read_enable: out std_ulogic;
video_fifo_data_out: in std_ulogic_vector(0 downto 0);
video_fifo_empty: in std_ulogic;

-- Board interface to LED Board
board_row_data: out std_ulogic;
board_shift_row_data: out std_ulogic;
board_apply_row_and_strobe: out std_ulogic;
board_row_strobe: out std_ulogic;
board_shift_row_strobe: out std_ulogic;
board_output_enable_n: out std_ulogic
```

While the decoded audio was played and then discarded, the Video Driver
has to store all pixels of the same frame because it needs to read them
multiple times due to the strobing of the display which is explained
in the section about the [Board Driver](#board-driver).

Not only do we need to store a full frame, but we also need space
for a second frame to prepare the next one without overwriting the
current frame while it needs to be displayed. For this purpose
the Video Driver instantiates a so called "ping-pong buffer" which is
just a fancy name for two buffers which alternately get read and written.

These frame buffers have two ports. The Video Driver side can read/write,
while the Board Driver side can only read. In order for Vivado to correctly
infer actual memory blocks (BRAM in this case) certain coding guidelines
have to be followed which you can read about in the code of the frame buffer.


## Board Driver

With the frames decoded, the board driver's job is to correctly toggle the lines
to the LED display so the frame will be displayed correctly. It needs
two interfaces for this, one to read from the frame buffers and the second one
to drive the display.

```vhdl
-- Board interface to ping-pong framebuffers
frame_buffer_request: out std_ulogic;
frame_buffer_address: out std_ulogic_vector(integer(ceil(log2(real(WIDTH * HEIGHT)))) - 1 downto 0);
frame_buffer_data: in std_ulogic_vector(SAMPLE_DEPTH - 1 downto 0);

frame_available: in std_ulogic;
frame_processed: out std_ulogic;

-- Board interface to LED Board
board_row_data: out std_ulogic;
board_shift_row_data: out std_ulogic;
board_apply_row_and_strobe: out std_ulogic;
board_row_strobe: out std_ulogic;
board_shift_row_strobe: out std_ulogic;
board_output_enable_n: out std_ulogic
```

Requesting the data from the frame buffer is pretty straight forward.
The choice on which buffer to select to read from is handled by the Video Driver.
Basically whenever the Board Driver signals that it processed the current frame,
the Video Driver will simply switch the frame buffers.

More interesting is the interface to the LED board which consists of a total
of six signals to smoothly drive a huge LED display! The technique used
is called multiplexing and leverages the biological effect called
"Persistance of Vision". While our eyes can make out great details in still
images, it slacks at fast paced or short pulsed lights/objects.
This phenomenon makes lights, especially LEDs, appear to be glowing
continuosly even when the light itself is only turned on and off for
a brief monent in time repeatedly.

We can leverage this effect by selecting each row of the display
individually and lighting up the pixels that are supposed to be lit.
By rapidly strobing through the rows the board will seem to display
and image where in reality we only perceive it that way.

> Note: Try turning down the board frequency to this strobing
> much slower. Beware though that the LEDs will stay on for longer
> and the display driver board is designed to run these LEDs
> close to the peak current draw for short pulses so it may
> damage the display if you run it for too long.

> Note: You can also "select" the columns one by one instead of the rows.
> This project implements multiplexing on a row-basis.

The Board Driver handles all this logic through a FSM that is clocked with
the exact clock frequency needed to run the board with the given width and
height. Unlike the main FPGA board clock and the i2s clock, this clock
is not generated through the Clocking Wizard IP.

It is handled by a phase accumulator which is a component that generates
a slower clock based on an input clock. The generated clock can be
only be as fast as half the original clock speed so this approach
is only useful for generating slower clocks.

> Note: In a real system one should avoid generating clocks on the FPGA fabric
> and running them to the outside world without proper constraints
> as there can be major skew between it and the data lines.

Actually driving the board is quite simple. The driver board has shift registers
along the rows and columns. The row shift registers will be used
to select a row to light up, and the column shift registers will be used
to light up or turn off the LEDs of the columns.

The FSM basically feeds a row into the column shift registers with
`board_row_data` and `board_shift_row_data` and advances the current
row selection (also known as strobe) with `board_row_strobe` and
`board_shift_row_strobe`. All of this happens without any changes on the
display because the shift registers have a buffer stage before the actual output.
Once the data is fed into the shift registers, we apply the new data in the
buffer by asserting `board_apply_row_and_strobe`.

However, if we did that only once for each frame we would have only one
brightness level. This process is repeated for 2^(Bit Depth) cycles
while comparing the current iteration to the given pixel value.
If the pixel value is low, it corresponds to a dim pixel so it will only
turn on for a few cycles and then remain off for the following ones.
For higher pixel values, the pixel will stay on for longer and be brighter.
This way we can implement a grayscale by tuning the on time of the LEDs.
Pulse-Width-Modulation is the name of this technique on a single LED level.

But we are not done yet, if we run the display in this configuration then
pixels that are supposed to be dim might actually flicker due to the low
frequency of the board. The solution for this is very simple:
Just repeat the whole process again and again. By just strobing
the whole frame-brightness-sequence four times the flickering is eliminated.

Theoretically you can push this even higher or increase the bit depth to
allow for more grayscale shades but don't forget that these signals
will need to travel from the FPGA to an external board so you need to consider
the physical implications of the wire and PCB traces. At some point
it is impossible for the FPGA to drive these IO pins with such a high speed.

In this project the fastest line to the board driver is clocked with around
1.5 MHz, increasing the strobe frequency causes the driver to not work
correctly anymore as the FPGA lines do not toggle fast enough.

> Note: A better designed driver board could have allowed for faster speeds
> but as this is not the main goal of the project and it already hits the target
> I did not bother improving the PCB layout and components any further.

One final note to mention is that LEDs typically do not have a linear
luminosity curve, which means that a pixel with a value of 6 is not twice
as bright as one with the value of 3. The luminosity typically rises in
a logarithmic fashion where the LED gains most of it brightess at low on times
and yields less brightness increases at higher on times.

The board driver does not take this into an account with a luminosity ramp that
maps the pixel values to the actual on-time necessary. This is not correctly
doable as it would require higher board speeds to not sacrifice on the depth
of the grayscale. Sadly this results in a blurry mess when converting videos
with flat colors and only works particularly well with black and white and high
contrast videos.
