# Memory

Notes on the memory driver interfacing with the onboard Macronix MX25L3233F ([Datasheet](https://www.macronix.com/Lists/Datasheet/Attachments/8933/MX25L3233F,%203V,%2032Mb,%20v1.7.pdf)).

> The Digilent Basys3 was manufactured with two different flash chips the other one being the Spansion S25FL032P. I happen to have the one with the Macronix on it. They are similar but not identical. The standard feature set is identical though, so the code can be used for both.

The onboard flash chip has different READ commands, to figure out which one we should use we have to determine
the minimum bandwidth from the media file.

The [Bandwidth minimum](memory.md#goals-to-achieve) is 161,928 bits/s which is 20,241 B/s.
Now we need to calculate the minimum clock frequency for the FPGA to achieve this bandwidth.

The standard READ command `(p.29, 10-7. Read Data Bytes (READ))` needs 8 cycles for the command, 24 cycles for the address and 8 cycles to return the data without pipelining which is 40 cycles in total.

Interfacing the flash chip with 50 MHz is rather dangerous, as stray capacitance (such as hands closeby) can actually disturb the connection and read faulty data, so we use a much safer clock of 10 MHz.
This is a clock that will safely work on-chip and on-board without any interference.

Assuming that we non-stop read data from the flash chip this means that we need to calculate: 10 MHz / 40 cycles/read = 250,000 reads/second.
Since one read will return a byte this will yield an average read-rate of 250 kB/s which is way more than we need.

Macronix offers a verilog simulation model for this chip, but for our use-case it is definitely overkill.
The model only needs to only support the basic READ command and initialize the storage with a given file, it can error out with unsupported commands.
