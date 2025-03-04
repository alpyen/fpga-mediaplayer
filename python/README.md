# Python Scripts

This readme will guide you through the steps necessary to set up and run the python scripts.


## Navigation
1. [Requirements](#requirements)
2. [Setting up the virtual environment](#setting-up-the-virtual-environment)
3. [Encoding media files into the project format](#encoding-media-files-into-the-project-format)
4. [Playing the encoded media in a software player](#playing-the-encoded-media-in-a-software-player)
5. [Appending the media onto a FPGA bitfile](#appending-the-media-onto-a-fpga-bitfile)


## Requirements

- Python >= 3.8
- Pip Modules (requirements.txt):
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
   - Linux: `source .venv/bin/activate`
   - Windows: `.venv\Scripts\activate.bat`
4. Install the necessary modules by running `pip install -r requirements.txt`

That's it! Make sure to always activate the environment first before running the scripts.

> Note: Linux users may have to install the `python3-tk` package in order to run the player script
> as it uses the tkinter module for the GUI.


## Encoding media files into the project format

`convert.py` takes care of the media encoding and is controlled by supplying command line arguments.
An overview of the possible arguments can be displayed by just calling the script or
with the `--help` flag and looks like this:

<details>
<summary>convert.py help - click to open</summary>

```
usage: convert [-h] -i INPUT [-o OUTPUT] [-r RESOLUTION]

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
                        Target resolution in w:h.
                        (default: 32:24)
```

</details><br>

Encoding a file that is located at `media/demo.mp4` to 8x6 resolution (small LED board) is done like this:<br>
```console
python convert.py -i media/demo.mp4 -o media/demo.bin -r 8:6
```

> Note: If you don't supply an output file path the encoded file will be discarded
> and only the encoding statistics will be printed.

After the encoding process is done you will see information about the achieved compression in the terminal.

<details>
<summary>convert.py output example - click to open</summary>

```
=================== File Information ===================
Input:              media/video.mp4
Size:               19126 K
Output:             media/video.bin
Resolution:         32:24
========================================================

================== FFmpeg Processing ===================
Pre-processing input file...done!

Audio stream detected.
Video stream detected.
========================================================

=================== Audio Processing ===================
Reading audio file...done!
Encoding audio...done!

Uncompressed Size:  37748 K
Reduced Size:       4718 K
Encoded Size:       2467 K (52.29%)
========================================================

=================== Video Processing ===================
Reading video frames...done!
Encoding video...done!

Uncompressed Size:  11835 K
Reduced Size:       1972 K
Encoded Size:       760 K (38.54%)
========================================================

======================= Summary ========================
Writing output file...done!

Uncompressed Size:  49583 K
Reduced Size:       6691 K
Encoded Size:       3227 K (48.24%)
========================================================
```

</details><br>

The script outputs three size metrics for the audio and video encoding process:
- Uncompressed: Size of the **raw data** in its uncompressed form
- Reduced: Size of the **raw data after downscaling** to the target quality
- Encoded: Size of the **encoded reduced data** with the compression ratio in comparison to the reduced size


## Playing the encoded media in a software player

A software player is included with `player.py` to playback encoded media files without having
to build a LED board first. This is also helpful if you want to test the output file before
going through the tedious process of bringing it onto the flash memory of the FPGA.

<details>
<summary style="color: #ffbb33;">player.py help - click to open</summary>

```
usage: player [-h] -i INPUT [-b BLOCKSIZE]

Plays a file that was encoded in the project's media format.

Press [Space] to pause and [m] to mute.

options:
  -h, --help            show this help message and exit
  -i INPUT, --input INPUT
                        Input media file
  -b BLOCKSIZE, --blocksize BLOCKSIZE
                        Scales a pixel by this amount for a bigger preview window.
                        (default: 32)
```

</details><br>

It is pretty self explanatory. You can playback a file at `media/demo.bin` like this:
```console
python player.py -i media/demo.bin
```

> Note: Adjust the blocksize parameter if the window is too big or small with the file's resolution.


## Appending the media onto a FPGA bitfile

...
