# Media

This document contains all the information about the mediatype used in this project.

First we identify natural constraints which emerge from the devices and peripheral used. Second we set boundary constraints to limit the scope of this project to something doable.
Lastly there is the specification of the media format.

- [Media](#media)
  - [Constraints](#constraints)
  - [Goals to achieve](#goals-to-achieve)
  - [Specification](#specification)
  - [Codec](#codec)
  - [File Structure](#file-structure)
    - [Header](#header)
    - [Data](#data)

## Constraints
- Digilent Basys3 (Artix7-35T)
- Flash Chip has 4MB/32Mbit of space available
  - Configuration uses 17,536,096 bits
  - with Configuration: 16,018,336 bits (~1,905K)
  - without Configuration: 33,554,432 bits (=4MB)
- Real time decodable for playback
- Do not use existing IP for direct codec implementation
- Decoder (Software counterpart) has to be implemented in hardware
  - therefore the encoder can't be too complex -> sacrificing on compression ratio

## Goals to achieve
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

Calculated file size for uncompressed media:
- Video:
  - 4 mins * 60 * 32 * 24 pixels * 24 fps * 4 bits
  - 17,694,720 bits
- Audio:
  - 4 mins * 60 * 44,100 Hz * 1 * 4 bits
  - 42,336,000 bits
- Total:
  - 60,030,720 bits


Around 134 seconds (2:14) are available without any compression at all if the configuration is not present on the flash.

For the full four minutes, the target file has to be compressed down to 56% of the original file size which will be tough, but achievable.  With the configuration the target file size has to be 26% which is basically impossible for a simple and straight forward codec.

## Specification

## Codec

Since the bitwidth of the audio and video is so low the codec will be very simple.

The codec works by encoding differences over time so we compare the current sample to encode with the previous sample and write the data according to the table.

| Coding Table                         | Bit representation |
|--------------------------------------|--------------------|
| Current Sample = Previous Sample     | 0                  |
| Current Sample = Previous Sample + 1 | 1 0                |
| Current Sample = Previous Sample - 1 | 1 1 0              |
| else (none of the above)             | 1 1 1 x x x x      |

So as an example if the previous sample is a `4` and the current sample is also a `4` we simply write a `0` bit into the encoded file.
For the case where the current sample is `5` we simply write the bits `1 0` into the file indicating that the sample is one higher than the previous saving two bits to the non-encoded counterpart.
For samples that differ too much (e.g. 2 or more) we write `1 1 1` to indicate that the next four bits `x x x x` will define a sample as a whole.

Analysis of some encoded files show that most differences are 0, +-1 and +-2. So even though the last case seems three bits longer than the non-encoded version, it happens less frequently.

For simplicity's sake audio and video will be padded to full bytes.
This only happens at the end of the file!

With the encoding out of the way, let's define a simple file header for the control unit to read out the metadata of the encoded media file.

## File Structure

### Header

```
"A"         (1B)
Width       (1B)
Height      (1B)
#AudioBytes (4B)
#VideoBytes (4B)
"Z"         (1B)
= 12 Bytes
```

- "A" (1 Byte):
  - This is part of the signature so the control unit can make sure that the contents at the given memory location (to look for the media) is actually a valid encoded file so we don't read garbage. Binary representation in 8-Bit ASCII.
- "Width" (1 Byte):
  - Unsigned byte that determines the width of the encoded video.
- "Height" (1 Byte):
  - Unsigned Byte that determines the height of the encoded video.
- #AudioBytes (4 Bytes):
  - Little Endian encoded unsigned integer that contains the number of audio bytes contained within the media file.
- #VideoBytes (4 Bytes):
  - Little Endian encoded unsigned integer that contains the number of video bytes contained within the media file.
- "Z" (1 Byte):
  - The end of the signature, analog to the "A". Binary representation in 8-Bit ASCII.

As you can see the header contains little information about the metadata of the encoded file since it's mostly irrelevant for itself or the modules downstream.
The only reason the resolution is encoded is to ease the use of the player script and perhaps modify the board driver in the future in such a way, that it will pad the video if the encoded file is smaller than its display.

### Data

Audio and video data follow immediately the header with the complete audio first, then video.
The data is **not** interleaved.
