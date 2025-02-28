# Python Scripts - Codec and Player

This readme will guide you through the steps of how to get the scripts up and running to encode and playback files.

### Requirements
- Python >= 3.8
- Pip Modules:
  - pillow >= 10.2.0
  - PyAudio >= 0.2.14
  - pyffmpeg >= 2.4.2.18.1


## Setting up the virtual environment

Using pip and venv is recommended for setting up an environment where these scripts can run.
You could install the packages globally, but that will clutter your system.

Follow these steps to create the environment:

1. Open a terminal and switch into the `python`-folder
2. Create a virtual environment with `python -m venv .venv`
3. Activate the virtual environment in your current shell/terminal
   1. Linux: `source .venv/bin/activate`
   2. Windows: `.venv\Scripts\activate.bat`
4. Install the necessary modules by running `pip install -r requirements.txt`

That's it! Make sure to always activate the environment first before running the scripts.

## How to use the codec.py

This script will, as the name suggest, take care of the data encoding, like the player it has a command line interface that can be displayed with calling just the script or with the `--help` argument. Here's what it looks like:

```
usage: codec [-h] -i INPUT [-o OUTPUT] [-r RESOLUTION] [-dv] [-da]

Encodes a given media file to the project's media format.

The file is pre-processed by ffmpeg and as such all
audio and video formats supported by ffmpeg are usable.

Output quality will be fixed:
  Video: 32:24 (default) at 24 fps
  Audio: 1 channel with 4 bit per Sample at 44.100 Hz

options:
  -h, --help            show this help message and exit
  -i INPUT, --input INPUT
                        Input media file
                        If a WAVE file is passed (.wav) then the video will be left out.
  -o OUTPUT, --output OUTPUT
                        Output encoded file
  -r RESOLUTION, --resolution RESOLUTION
                        Target resolution in w:h. Default: 32:24.
  -dv, --dump-video     Dumps a video-only mp4 file with the target quality.
  -da, --dump-audio     Dumps an unsigned 8 bit WAVE file with the target quality.
```

Here are some example use cases:
- Encode a file located at `media/demo.mp4` to 8:6 resolution: `python codec.py -i media/demo.mp4 -o media/demo.enc -r 8:6`
- Display encoding statistics without writing an output file: `python codec.py -i media/demo.mp4 -r 8:6`
- Dump audio and video to quickly playback on PC: `python codec.py -i media/demo.mp4 -r 8:6 -da -dv`

In general these parameters can be combined arbritrarily.

Here's what the output of `python codec.py -i media/video.mp4 -o media/video.env` looks like:
```
=================== File Information ===================
Input:              media/video.mp4
Size:               19126 K
Output:             media/video.enc
Resolution:         32:24
Dump Audio?         No
Dump Video?         No
========================================================

================== FFmpeg Processing ===================
Pre-processing input file...done!

Audio stream detected.
Video stream detected.
========================================================

=================== Audio Processing ===================
Reading audio file...done!

Reducing to mono and 4 bits...done!
Encoding reduced file...done!

Uncompressed Size:  37748 K
Reduced Size:       4718 K
Encoded Size:       2467 K (52.29%)
========================================================

=================== Video Processing ===================
Reading video frames...done!

Reducing to 4 bits...done!
Encoding reduced file...done!

Uncompressed Size:  11835 K
Reduced Size:       1972 K
Encoded Size:       770 K (39.08%)
========================================================

======================= Summary ========================
Writing output file...done!

Uncompressed Size:  49583 K
Reduced Size:       6691 K
Encoded Size:       3238 K (48.4%)
========================================================
```

The meaning of these values are explained here:
- File Information
  - Size: The original file size of the source media file
- Audio Processing
  - Uncompressed Size: The size of the audio when it's fully uncompressed
  - Reduced Size: The size of the audio size with the project's target quality settings (1 channel, 4 bits, 44.1 kHz)
  - Encoded Size: The final size of the reduced audio when it's encoded
- Video Processing
  - Uncompressed Size: The size of the video when it's fully uncompressed
  - Reduced Size: The size of the video size with the project's target quality settings (4 bits, 24 fps, target resolution)
  - Encoded Size: The final size of the reduced video when it's encoded
- Summary
  - Just contains the sum of the audio and video segments and most importantly the final encoded file size

While there is a player script supplied to playback the encoded media file (without audio), the codec can still dump a mp4 file to be played in any regular video player. Please keep in mind though, that the player might be interpolating the video when you scale it up, making it look very different from the real board, that's why there is the player.py aswell.

As there is no difference in audio playback, dumping the audio will result in a regular wave file but with the target quality even if the file says 8 bit, the used values are all on 4 bit intervals.

## How to use the player.py

To accurately playback the video portion of the encoded file, this script will create a window with block tiles that are meant to simulate the LEDs on the board. It has a command line interface and it looks like this:
```
usage: player [-h] -i INPUT [-b BLOCKSIZE]

Plays a file that was encoded in the project's media format.

options:
  -h, --help            show this help message and exit
  -i INPUT, --input INPUT
                        Input media file
  -b BLOCKSIZE, --blocksize BLOCKSIZE
                        Scales a pixel by this amount for a bigger preview window.
                        (default: 32)
```

It is pretty self explanatory, and if you want to playback a file simple run a command like: `python player.py -i media/demo.enc`

The blocksize parameter is used to scale up the window by this factor. Meaning, if you have a target file of 8:6 resolution, the window will be too small to be usable, so the player will scale it up by a default of 32 so the window grows to a size of 256:192. Vary this parameter if it is still too small.
