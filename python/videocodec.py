import argparse
import sys
import os
import shutil
import tempfile

import pyffmpeg
import wave

import struct

import PIL.Image

# Disable logging from pyffmpeg because it's useless.
import logging
logging.getLogger("pyffmpeg.FFmpeg").setLevel(logging.FATAL)
logging.getLogger("pyffmpeg.misc.Paths").setLevel(logging.FATAL)

parser = argparse.ArgumentParser(
    prog="videocodec",
    description="Encodes a given media file to the project's media format.\n" +
                "\n" +
                "The file is processed by ffmpeg and as such all video formats\n" +
                "supported by ffmpeg are usable.\n" +
                "\n" +
                "Output quality will be 32x24@24fps / 1x4b@44.1kHz.",
    formatter_class=argparse.RawTextHelpFormatter
)
parser.add_argument("-i", "--input", type=str, required=True, help="Input video file")
parser.add_argument("-o", "--output", type=str, required=False, help="Output encoded file")

args = parser.parse_args(args=None if sys.argv[1:] else ["--help"])

if not os.path.exists(args.input):
    print("Input file not found.")
    exit(0)

temp_dir = tempfile.mkdtemp(None, "fpga_mediaplayer_tmp_")

ff = pyffmpeg.FFmpeg()

print("=================== FFmpeg Processing ====================")

print("Input: ".ljust(20) + str(args.input))
print("Size: ".ljust(20) + str(int(os.stat(args.input).st_size / 1024)) + " K")
print()

print("Converting input file to target quality settings...", end="")

# Extract frames from the video file
try:
    ff.options(
        "-i \"" + args.input + "\" " +
        "-vf \"scale=32:24,hue=s=0,fps=24\" " +
        "\"" + os.path.join(temp_dir, "%05d.png") + "\" " +
        "-ar 44100 " +
        "\"" + os.path.join(temp_dir, "audio.wav") + "\""
    )
except Exception as error:
    print("error!")
    print()

    print("The media file could not be processed by ffmpeg.")
    print("Error raised:\n" + str(error))

    try:
        ff.quit()
    except Exception:
        pass

    shutil.rmtree(temp_dir)
    exit(0)

ff.quit()

print("done!")
print("==========================================================")
print()

videoframes = sorted(os.listdir(temp_dir))

if len(videoframes) == 0:
    print("The media file does not contain a video stream.")
    shutil.rmtree(temp_dir)
    exit(0)

if "audio.wav" not in videoframes:
    print("The media file does not contain an audio stream.")
    shutil.rmtree(temp_dir)
    exit(0)

videoframes.remove("audio.wav")

if len(videoframes) == 0:
    print("The media file could not be processed by ffmpeg.")
    print("There were no extracted frames located.")
    shutil.rmtree(temp_dir)
    exit(0)

try:
    audiofile = wave.open(os.path.join(temp_dir, "audio.wav"), "r")
except Exception as error:
    print("The WAVE file could not be read correctly.")
    print("Error raised:\n" + str(error))
    shutil.rmtree(temp_dir)
    exit(0)

if audiofile.getnframes() == 0:
    print("The audio file is empty.")
    audiofile.close()
    shutil.rmtree(temp_dir)
    exit(0)

print("==================== Audio Processing ====================")
print("Reading audio file...", end="")

depth = audiofile.getsampwidth()
channels = audiofile.getnchannels()
length = audiofile.getnframes()
frames = audiofile.readframes(length)
original_size = length * channels * depth
reduced_size = original_size / channels / depth * (4 / 8)

audiofile.close()

print("done!")
print()

print("Reducing to mono and 4 bits...", end="")

mono_samples = []
for i in range(0, length):
    if int(i % (length / 10)) == 0:
        print(str(int(i / length * 100)) + "%...", end="", flush=True)

    mono_samples.append(0)

    for j in range(0, channels):
        # WAVE officially only supports unsigned for 8 bits bitdepth. It's signed above that.
        mono_samples[-1] += int.from_bytes(frames[i*(depth+channels) + 0:i*(depth+channels) + depth], byteorder="little", signed=depth>1)

    # Calculate the average of the channels
    mono_samples[-1] = int(round(mono_samples[-1] / channels))

    # Convert it to signed incase the input file was unsigned
    if depth == 1:
        mono_samples[-1] -= 128

    # Bitcrush down to 4 bits
    mono_samples[-1] = int(round(mono_samples[-1] / (2 ** (depth * 8 - 4))))

    # Since we are rounding and not flooring mono can contain +8 as a sample
    # which is out of the signed 4 bit range -> clip that to +7.
    if mono_samples[-1] == 8:
        mono_samples[-1] = 7

print("done!")

print("Encoding reduced file...", end="")

# We assume in HDL the previous sample to be 0 so we can immediately start encoding.
previous_sample = 0

encoded_audio_samples = []

for i in range(0, length):
    if int(i % (length / 10)) == 0:
        print(str(int(i / length * 100)) + "%...", end="", flush=True)

    current_sample = mono_samples[i]

    if current_sample - previous_sample == 0:
        encoded_audio_samples.extend([0])

    elif current_sample - previous_sample == 1:
        encoded_audio_samples.extend([1, 0])

    elif current_sample - previous_sample == -1:
        encoded_audio_samples.extend([1, 1, 0])

    else:
        encoded_audio_samples.extend([1, 1, 1])
        for j in range(0, 4):
            encoded_audio_samples.append(mono_samples[i] >> (4 - 1 - j) & 0b1)

    previous_sample = current_sample

# Pad to full bytes
while len(encoded_audio_samples) % 8 != 0:
    encoded_audio_samples.append(0)

print("done!")

print()

# Print Input file statistics
# Reduced Size is the size of the file after quality loss but before compression.
print("Uncompressed Size: ".ljust(20) + str(int(original_size / 1024)) + " K")
print("Reduced Size: ".ljust(20) + str(int(reduced_size / 1024)) + " K")
print("Encoded Size: ".ljust(20) + str(int(len(encoded_audio_samples) / 8 / 1024)) + " K (" + str(int(round(len(encoded_audio_samples) / 8 / reduced_size * 100, 2))) + "%)")

# if args.output is not None:
#     print()
#     print("Writing output file...", end="")

#     if os.path.exists(args.output):
#         os.remove(args.output)

#     outputfile = open(args.output, "wb+")

#     # Write File Header
#     outputfile.write("A".encode("ascii"))
#     outputfile.write(struct.pack("<I", int(len(encoded_samples) / 8)))
#     outputfile.write(struct.pack("<I", 0))
#     outputfile.write("Z".encode("ascii"))

#     for i in range(0, len(encoded_samples), 8):
#         if int(i % (len(encoded_samples) / 10)) == 0:
#             print(str(int(i / len(encoded_samples) * 100)) + "%...", end="", flush=True)

#         byte = 0

#         for j in range(0, 8):
#             byte |= encoded_samples[i + j] << j

#         outputfile.write(struct.pack("B", byte))

#     outputfile.close()

#     print("done!")

print("==========================================================")
print()
print("==================== Video Processing ====================")


print("==========================================================")
