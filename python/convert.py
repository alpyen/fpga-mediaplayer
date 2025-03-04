import argparse
import sys
import os
import shutil
import tempfile

import pyffmpeg
import wave
import struct

import PIL.Image
import time

from collections import deque

# Disable logging from pyffmpeg because it's useless for our use-case.
import logging
logging.getLogger("pyffmpeg.FFmpeg").setLevel(logging.FATAL)
logging.getLogger("pyffmpeg.misc.Paths").setLevel(logging.FATAL)

from codec import MediaFile, audio_encoder, video_encoder

parser = argparse.ArgumentParser(
    prog="convert",
    description="Encodes a given media file to the project's media format.\n" +
                "\n" +
                "The file is pre-processed by ffmpeg and as such all\n" +
                "audio and video formats supported by ffmpeg are usable.\n"
                "\n" +
                "Output quality will be fixed:\n" +
                "  Video: 32:24 (default) at 24 fps\n" +
                "  Audio: 1 channel with 4 bit per Sample at 44.100 Hz",
    formatter_class=argparse.RawTextHelpFormatter
)
parser.add_argument("-i", "--input", type=str, required=True, help="Input media file\nIf a WAVE file is passed (.wav) then the video will be left out.")
parser.add_argument("-o", "--output", type=str, required=False, help="Output encoded file")
parser.add_argument("-r", "--resolution", type=str, required=False, default="32:24", help="Target resolution in w:h.\n(default: 32:24)")

args = parser.parse_args(args=None if sys.argv[1:] else ["--help"])

if not os.path.exists(args.input):
    print("Input file not found.")
    exit(0)

resolution = args.resolution.split(":")
if len(resolution) != 2 or any([not x.isnumeric() or int(x) <= 0 for x in resolution]):
    print("Resolution format is incorrect. Example: -r 32:24.")

# Remove any preceeding zeroes.
resolution = [str(int(x)) for x in resolution]

input_file = str(args.input)
output_file = str(args.output) if args.output is not None else None

print("=================== File Information ===================")

print("Input: ".ljust(20) + str(args.input))
print("Size: ".ljust(20) + str(int(os.stat(args.input).st_size / 1024)) + " K")
print("Output: ".ljust(20) + str(args.output))
print("Resolution: ".ljust(20) + resolution[0] + ":" + resolution[1])

print("========================================================")


print()
print("================== FFmpeg Processing ===================")

print("Pre-processing input file...", end="", flush=True)

temp_dir = tempfile.mkdtemp(None, "fpga_mediaplayer_tmp_")

ff = pyffmpeg.FFmpeg()

try:
    audio_command = (
        "-i \"" + input_file + "\" " +
        "-ar 44100 -c:a pcm_s16le " +
        "\"" + os.path.join(temp_dir, "audio.wav") + "\""
    )

    video_command = (
        "-i \"" + input_file + "\" " +
        "-vf \"scale=" + args.resolution + ",format=gray,fps=24\" " +
        "\"" + os.path.join(temp_dir, "%05d.png") + "\""
    )

    ff.options(audio_command)
    ff.options(video_command)
except Exception as error:
    print("error!")
    print()

    print("The media file could not be processed by ffmpeg.")
    print("Error raised:\n" + str(error))

    try:
        ff.quit()
    finally:
        shutil.rmtree(temp_dir)
        exit(0)

ff.quit()

print("done!")
print()

# Contains the frames and the audio file output from ffmpeg.
# 00001.png, 00002.png, ..., audio.wav
# If a video was dumped with --dump-video, that landed next to the original file.
files = sorted(os.listdir(temp_dir))

video_available = False
audio_available = False

encoded_audio_bytes = bytes(0)
encoded_video_bytes = bytes(0)

if "audio.wav" in files:
    print("Audio stream detected.")
    files.remove("audio.wav")
    audio_available = True
else:
    print("No audio stream detected")

if len(files) > 0:
    print("Video stream detected.")
    video_available = True
else:
    print("No video stream detected.")

print("========================================================")


# Tracks passed time to update status.
ts = time.time()

if audio_available:
    print()
    print("=================== Audio Processing ===================")

    print("Reading audio file...", end="", flush=True)

    audiofile = wave.open(os.path.join(temp_dir, "audio.wav"), "r")

    depth = audiofile.getsampwidth()
    channels = audiofile.getnchannels()
    length = audiofile.getnframes()
    frames = audiofile.readframes(length)

    audiofile.close()

    print("done!")


    print("Encoding audio...", end="", flush=True)

    encoded_audio_bytes = audio_encoder(channels, length, frames)

    print("done!")
    print()


    uncompressed_audio_size = 0
    reduced_audio_size = 0
    encoded_audio_size = 0

    # Print Input file statistics
    # Reduced Size is the size of the file after quality loss but before compression.
    uncompressed_audio_size = length * channels * depth
    reduced_audio_size = uncompressed_audio_size / channels / depth * (4 / 8)
    encoded_audio_size = len(encoded_audio_bytes)
    print("Uncompressed Size: ".ljust(20) + str(int(uncompressed_audio_size / 1024)) + " K")
    print("Reduced Size: ".ljust(20) + str(int(reduced_audio_size / 1024)) + " K")
    print("Encoded Size: ".ljust(20) + str(int(encoded_audio_size / 1024)) + " K (" + str(round(encoded_audio_size / reduced_audio_size * 100, 2)) + "%)")

    print("========================================================")


if video_available:
    print()
    print("=================== Video Processing ===================")

    print("Reading video frames...", end="", flush=True)

    videoframes = []

    for i in range(0, len(files)):
        frame = PIL.Image.open(os.path.join(temp_dir, files[i]))
        videoframes.append(deque(frame.getdata(0)))
        frame.close()

    print("done!")


    print("Encoding video...", end="", flush=True)

    encoded_video_bytes = video_encoder(videoframes)

    print("done!")
    print()


    uncompressed_video_size = 0
    reduced_video_size = 0
    encoded_video_size = 0

    # Uncompressed Size: #frames * resolution * 3 bytes per pixel
    framelength = int(resolution[0]) * int(resolution[1])

    uncompressed_video_size = len(videoframes) * framelength * 3
    reduced_video_size = len(videoframes) * framelength * (4 / 8)
    encoded_video_size = len(encoded_video_bytes)
    print("Uncompressed Size: ".ljust(20) + str(int(uncompressed_video_size / 1024)) + " K")
    print("Reduced Size: ".ljust(20) + str(int(reduced_video_size / 1024)) + " K")
    print("Encoded Size: ".ljust(20) + str(int(encoded_video_size / 1024)) + " K (" + str(round(encoded_video_size / reduced_video_size * 100, 2)) + "%)")

    print("========================================================")


print()
print("======================= Summary ========================")

if output_file is not None:
    print("Writing output file...", end="", flush=True)

    if os.path.exists(output_file):
        os.remove(output_file)

    file = open(output_file, "wb+")

    # Generate media header and write file contents
    header = MediaFile.as_bytes(
        int(resolution[0]) if video_available else 0,
        int(resolution[1]) if video_available else 0,
        len(encoded_audio_bytes),
        len(encoded_video_bytes)
    )

    file.write(header)
    file.write(encoded_audio_bytes)
    file.write(encoded_video_bytes)

    file.close()

    print("done!")
    print()

uncompressed_size = 0
reduced_size = 0
encoded_size = 0

if audio_available:
    uncompressed_size += uncompressed_audio_size
    reduced_size += reduced_audio_size
    encoded_size += encoded_audio_size

if video_available:
    uncompressed_size += uncompressed_video_size
    reduced_size += reduced_video_size
    encoded_size += encoded_video_size

if audio_available or video_available:
    print("Uncompressed Size: ".ljust(20) + str(int(uncompressed_size / 1024)) + " K")
    print("Reduced Size: ".ljust(20) + str(int(reduced_size / 1024)) + " K")
    print("Encoded Size: ".ljust(20) + str(int(encoded_size / 1024)) + " K (" + str(round(encoded_size / reduced_size * 100, 2)) + "%)")

print("========================================================")

shutil.rmtree(temp_dir)
exit(0)
