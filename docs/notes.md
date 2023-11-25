# Notes

Contains some thoughts over the development time of the project.

- Is it worth separating the SCK and RCK lines for the row selection shift registers?
  - They could be tied together, all that needs to be done is to clock once more because the data is behind one clock cycle, but it would save one line to the FPGA.
- The small LED board has the IRF4905 P-MOSFET on it, it seems like they are not a good fit, they will be exchanged for the bigger board.
  - They are on there because I ordered them thinking they were a good fit.
  - They work fine but will mess up operating the LEDs at the target voltage/current because the voltage drop changes heavily depending on the current running through it (dependant on how many LEDs are on)
  - Maybe I messed up with the test circuit, I will test again with 32 LEDs for the bigger version when designing that.
- Pullup for logic shifters is 10K which would lead to asymmetrical charge times for the shift registers.
  - See how long it actually takes to charge the lines up with 10K.
- Shift register is CMOS and the inputs have high-impedances so leaving out current limiting resistors.
  - However they are needed for N-MOSFET and P-MOSFET for example (to protect the device that is delivering the current).
  - I think they can be left out if the power supply delivers the current, and not a µC which has output current limitations.
- Pullups for Logic Shifter Drains / Shift Register Inputs are not suitable for the full size board.
  - It seems like it takes a few microseconds to charge up through a 10K, this will be a big problem depending on the video properties. 24fps / 8bpp will need much lower resistor values.
- The small board uses two shift registers for the column selection on purpose even though it could have been implemented with a single one.
  - The only difference to the full size board will be that we are wiring QC to SER from the first to the second register and this only works if the data is present on QC, instead of it only being present in the buffer stage as for example with QH'.
- I think it's worth dividing the memory access, the audio playback, the video playback and the control unit into different modules / entities so they can be interchanged for different implementations such as different memory storages (Flash, SD-Card, USB-Stick) or different codecs.
- The audio and video drivers will be fed through FIFOs and some additional control signals.
- The memory driver does not need a FIFO really.
- Pull all simulations signals to 'U' when they shouldn't be read instead of driving them with '0' for example?
- 'done' was registered in the spi_memory_driver. Is this really necessary? The simulation reacts badly on it, but it should work on hardware?
- Some testbenches could make use of vhdl2008 be pulling out the internal signals as aliases but we're sticking to Vivado's Default for now ('93?)
  - Instead of duplicating the code we simply route the signals outwards, this is ok because none of this will be synthesized so nothing will be wasted.
- I've implemented some ideas for audio codecs which isn't really something that's worth documenting the process of so I'll just implement one and maybe talk about a bit about the other ideas.
- The file header stores the sizes in 4 bytes even though the SPI flash can address at most 3 bytes.
  - This will result in resizing the audio_bytes and video_bytes signal in the control unit to match the 3 bytes address.
- We don't need to save the signature_begin and signature_end in the control unit as they will only be written and read once, it's a waste of flipflops.
- REQUEST_DATA in the control unit only dispatches a request if the read_audio_n_video is set accordingly.
  - This results in one clock cycle loss if for example audio is in order but the audio fifo is full.
  - Then we need to stall for one cycle for the read_audio_n_video signal to change.
  - Technically we could check in the previous state. Does this make sense hardwarewise and timingwise?
- FSM returns to idle when it's done reading audio and video but should only do so when the playback is stopped completely.
