# Notes

Contains some thoughts over the development time of the project.

**Is it worth separating the SCK and RCK lines for the row selection shift registers?**
- They could be tied together, all that needs to be done is to clock once more because the data is behind one clock cycle, but it would save one line to the FPGA.

