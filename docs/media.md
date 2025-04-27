# Media Documentation

This document contains all the information about the media and codec used in this project - especially the how and why.


## Navigation
1. [Constraints](#constraints)
2. [Goals](#goals)
3. [Codec Specification](#codec-specification)
4. [File Structure](#file-structure)


## Constraints

Most of the constraints emerged from the Digilent Basys3 development board which is the board
I wanted to accomplish this project on. Other constraints are purely for educational purposes only
such as not using pre-existing IP blocks in order to have done most of the workflow myself even though
this is far from the reality of developing on FPGAs.

- Digilent Basys3 (Artix7-35T FPGA)
- Flash Chip has 4MB/32Mbit of space available
  - Configuration uses 17,536,096 bits
  - with Configuration: 16,018,336 bits (~1,905K)
  - without Configuration: 33,554,432 bits (=4MB)
- Real time decodable for playback
- Do not use existing IP for direct codec implementation
- Decoder (Software counterpart) has to be implemented in hardware
  - therefore the encoder can't be too complex -> sacrificing on compression ratio

## Goals

With the idea in mind to playback a certain video (see the demo on the main page), the goals
were also easy to define. It's mostly about the quality of the media file in relation to the available space onboard.

- Implementation musn't be linked to loaded media
  - Design should be able to handle all kinds of media configurations
    - pad the video if it's smaller, do not play if it's bigger
  - Flash size should be solved as a generic and not hard wired
- preferrably load from detachable storage (SD-Card, USB-Stick)
- Video:
  - Length: about 4 minutes
  - Resolution: 32 x 24 pixels
  - Framerate: 24 fps
  - Grayscales: 16 shades (4 bits)
- Audio:
  - Length: about 4 minutes
  - Sample Rate: 44,100 Hz
  - Channels: Mono
  - Depth: 16 amplitudes (4 bits)

According to these audio and video configurations the calculated file size for uncompressed media is:

```
Video: 4 mins * 60 * 32 * 24 pixels * 24 fps * 4 bits => 17,694,720 bits.
Audio: 4 mins * 60 * 44,100 Hz * 1 channel * 4 bits => 42,336,000 bits.
----------------------
Total: 60,030,720 bits

Available (no bitstream):   33,554,432 bits
Available (with bitstream): 16,018,336 bits
```

If no compression is used, around 134 seconds (2:14) can be stored on the flash without the bitstream next to it.
This number drops down to 64 seconds (1:04) if the bitstream is stored next to it.

For the full four minutes, the target file has to be compressed down to 56% of the
uncompressed file's size which will be tough but achievable while not storing the bitstream on the flash.
With the bitstream next to the media file, the target file size has to be 26% which is basically impossible
for a simple and straight forward codec.

> Note: While there is an option in Vivado to compress the bitstream to save space on the flash chip,
> the calculations have been done without it as its size changes depending on the HDL and is not consistent
> over different versions of this project. The compression referred to in this document is about the media compression.


## Codec Specification

Since the bitwidth of the audio and video are very low it allows us to keep the codec very simple.

It works by encoding the differences of the pixels/samples over time so the "current" sample is
directly compared to the "previous" sample and then storing a code word for the difference.
The idea behind this approach is that audio signals consist of waves which have smooth transitions
and do not rapidly jump. Video data behaves somewhat similarly.

Now all that's left is to define a code that will encode these transitions between samples/pixels.
In order to pack the data as tight as possible, we will store these code words sequentially on bit-level.

| Coding Table                         | Bit representation |
|--------------------------------------|--------------------|
| Current Sample = Previous Sample     | 0                  |
| Current Sample = Previous Sample + 1 | 1 0                |
| Current Sample = Previous Sample - 1 | 1 1 0              |
| else (none of the above)             | 1 1 1 x x x x      |

So as an example if the previous sample is a `4` and the current sample is also a `4` we simply write a `0` bit into the encoded file.
For the case where the current sample is `5` we simply write the bits `1 0` into the file indicating that the sample is one higher than the previous saving two bits to the non-encoded counterpart.
For samples that differ too much (e.g. 2 or more) we write `1 1 1` to indicate that the next four bits `x x x x` will define a sample as a whole.

Since there is no previous sample when encoding the first sample we will hardcode this to be 0 for both audio and video.

Analysis of some encoded files show that most differences are 0, +-1 and +-2. So even though the last case seems three bits longer than the non-encoded version, it happens less frequently. This code is similar to what a Huffmann tree would generate but the occurences of the differences are not
analyzed and then encoded based on frequency.

> Note: Making this a true Huffmann code would be quite easy by storing the encoding inside the media file and parsing it on the hardware
> but since this yields close to no compression improvements, it was just skipped.

For simplicity's sake, the whole audio segment and whole video segment will be padded to full bytes.
**This only happens once at the end of the file segments!**


## File Structure

Now all that's left is to define the structure of the encoded media file so it can be properly read on the FPGA.
We start with the header which contains the necessary information about the media file.

In order to make sure, we are actually reading a media file and not some random data, the header is encapsulated
with a signature at the beginning with an ASCII 'A' and at the end with an ASCII 'Z' each 1 byte big.

After the first byte, two bytes follow indicating the width and height of the encoded video.
This information will be used to block playback if the video does not fit onto the LED board with the size
specified in the Control Unit's generics.

Afterwards a 4 byte field contains the number of audio bytes available formatted as an unsigned integer in little-endian.
Analogous to the number of audio bytes, the number of vidoe bytes follow.

> Note: While the HDL only supports at most 24 bits for addressing the flash chip, it is more convenient
> to store the size in 32 bits. Otherwise bit-masking is necessary and bloats the encoding script.

Summarized the header looks lke this:

```
ASCII "A"   (1B)
Width       (1B)
Height      (1B)
#AudioBytes (4B)
#VideoBytes (4B)
ASCII "Z"   (1B)
----------------
Total:  12 Bytes
```

As you can see the header contains little information about the metadata of the encoded file
since it's mostly irrelevant for itself or the modules downstream.
The only reason the resolution is encoded is to ease the use of the player script and perhaps
modify the board driver in the future in such a way, that it will pad the video if the encoded file is smaller than its display.

Immediately after the header the encoded audio and video begin. First all audio bytes are written
and then the video bytes. **The data is not interleaved.** This means that the audio (if present)
starts at file offset `0xC` (12) of the file, and video (if present) starts at offset `0xC + #AudioBytes`.
