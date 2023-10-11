# Media

This document contains all the information about the mediatype used in this project.

First we identify natural constraints which emerge from the devices and peripheral used. Second we set boundary constraints to limit the scope of this project to something doable.
Lastly there is the specification of the media format.

- [Media](#media)
  - [Constraints](#constraints)
  - [Goals to achieve](#goals-to-achieve)
  - [Specification](#specification)

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
  - Design should be able to handle all kinds of media configurationswith greater memory capacity can be used easily
- preferrably load from detachable storage (SD-Card, USB-Stick)
- Video:
  - Length: about 4 minutes
  - Resolution: 32 x 24 pixels
  - Framerate: 24 fps
  - Grayscales: 16 shades (4 bits)
- Audio:
  - Length: about 4 minutes
  - Sample Rate: 22,050 Hz
  - Channels: Mono
  - Depth: 16 amplitudes (4 bits)

Calculated file size for uncompressed media:
- Video:
  - 4 mins * 60 * 32 * 24 pixels * 24 fps * 4 bits
  - 17,694,720 bits
- Audio:
  - 4 mins * 60 * 22,050 Hz * 1 * 4 bits
  - 21,168,000 bits
- Total:
  - 38,862,720 bits

Around 207 seconds (3:27) are available without any compression at all if the configuration is not present on the flash. For the full four minutes, the compression ratio has to be around 14% which is easily achievable.

With the configuration, the compression ratio has to be 46% to fit the entire four minutes alongside the configuration on the flash.

## Specification

Todo: Invent a codec, lol.
