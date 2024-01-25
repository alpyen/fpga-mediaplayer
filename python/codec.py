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


# Disable logging from pyffmpeg because it's useless for our use-case.
import logging
logging.getLogger("pyffmpeg.FFmpeg").setLevel(logging.FATAL)
logging.getLogger("pyffmpeg.misc.Paths").setLevel(logging.FATAL)

parser = argparse.ArgumentParser(
    prog="codec",
    description="Encodes a given media file to the project's media format.\n" +
                "\n" +
                "The file is pre-processed by ffmpeg and as such all\n" +
                "audio and video formats supported by ffmpeg are usable.\n"
                "\n" +
                "Output quality will be fixed:\n" +
                "  Video: 32x24 pixels at 24 fps\n" +
                "  Audio: 1 channel with 4 bit per Sample at 44.100 Hz",
    formatter_class=argparse.RawTextHelpFormatter
)
parser.add_argument("-i", "--input", type=str, required=True, help="Input media file\nIf a WAVE file is passed (.wav) then the video will be left out.")
parser.add_argument("-o", "--output", type=str, required=False, help="Output encoded file")
parser.add_argument("-dv", "--dump-video", action="store_true", help="Dumps a video-only mp4 file with the target quality.")
parser.add_argument("-da", "--dump-audio", action="store_true", help="Dumps an unsigned 8 bit WAVE file with the target quality.")

args = parser.parse_args(args=None if sys.argv[1:] else ["--help"])

if not os.path.exists(args.input):
    print("Input file not found.")
    exit(0)

input_file = str(args.input)
output_file = str(args.output) if args.output is not None else None

print("=================== File Information ===================")

print("Input: ".ljust(20) + str(args.input))
print("Size: ".ljust(20) + str(int(os.stat(args.input).st_size / 1024)) + " K")
print("Output: ".ljust(20) + str(args.output))
print("Dump Audio? ".ljust(20) + (("Yes (" + input_file[:input_file.rfind(".")] + "_dump.wav)") if args.dump_audio else "No"))
print("Dump Video? ".ljust(20) + (("Yes (" + input_file[:input_file.rfind(".")] + "_dump.mp4)") if args.dump_video else "No"))

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
        "-vf \"scale=32:24,format=gray,fps=24\" " +
        "\"" + os.path.join(temp_dir, "%05d.png") + "\""
    )

    if args.dump_video:
        video_command += (
            " " +
            "-vf \"scale=32:24,format=gray,fps=24\" " +
            "-an \"" + input_file[:input_file.rfind(".")] + "_dump.mp4" + "\""
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

encoded_audio_samples = []
encoded_video_samples = []

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
    print()

    mono_samples = []

    if length > 0:
        print("Reducing to mono and 4 bits...", end="")

        for i in range(0, length):
            if time.time() - ts > 0.1:
                print("\rReducing to mono and 4 bits..." + str(int(i / length * 100)) + "%", end="", flush=True)
                ts = time.time()

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

        print("\rReducing to mono and 4 bits...done!")

    if args.dump_audio:
        print("Dumping reduced audio file...", end="", flush=True)

        audio_dump_file = input_file[:input_file.rfind(".")] + "_dump.wav"

        if os.path.exists(audio_dump_file):
            os.remove(audio_dump_file)

        dumpfile = wave.open(audio_dump_file, "w")
        dumpfile.setnchannels(1)
        dumpfile.setsampwidth(1)
        dumpfile.setframerate(44100)

        # 8 bit WAVE needs to be unsigned so we add 128.
        # Also mono contains 4 bit data, so we resize it to 8 bits first.
        wavedata = bytes([sample * (2 ** 4) + 128 for sample in mono_samples])

        dumpfile.writeframes(wavedata)
        dumpfile.close()

        print("done!")

    print("Encoding reduced file...", end="")

    # We assume in HDL the previous sample to be 0 so we can immediately start encoding.
    previous_sample = 0

    for i in range(0, length):
        if time.time() - ts > 0.1:
            print("\rEncoding reduced file..." + str(int(i / length * 100)) + "%", end="", flush=True)
            ts = time.time()

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
                encoded_audio_samples.append(current_sample >> (4 - 1 - j) & 0b1)

        previous_sample = current_sample

    # Pad to full bytes
    while len(encoded_audio_samples) % 8 != 0:
        encoded_audio_samples.append(0)

    print("\rEncoding reduced file...done!")

    print()

    uncompressed_audio_size = 0
    reduced_audio_size = 0
    encoded_audio_size = 0

    if length > 0:
        # Print Input file statistics
        # Reduced Size is the size of the file after quality loss but before compression.
        uncompressed_audio_size = length * channels * depth
        reduced_audio_size = uncompressed_audio_size / channels / depth * (4 / 8)
        encoded_audio_size = len(encoded_audio_samples) / 8
        print("Uncompressed Size: ".ljust(20) + str(int(uncompressed_audio_size / 1024)) + " K")
        print("Reduced Size: ".ljust(20) + str(int(reduced_audio_size / 1024)) + " K")
        print("Encoded Size: ".ljust(20) + str(int(encoded_audio_size / 1024)) + " K (" + str(round(encoded_audio_size / reduced_audio_size * 100, 2)) + "%)")
    else:
        print("Uncompressed Size: ".ljust(20) + "0 K")
        print("Reduced Size: ".ljust(20) + "0 K")
        print("Encoded Size: ".ljust(20) + "0 K (100.0%)")

    print("========================================================")


if video_available:
    print()
    print("=================== Video Processing ===================")

    print("Reading video frames...", end="")

    videoframes = []

    for i in range(0, len(files)):
        if time.time() - ts > 0.1:
            print("\rReading video frames..." + str(int(i / len(files) * 100)) + "%", end="", flush=True)
            ts = time.time()

        frame = PIL.Image.open(os.path.join(temp_dir, files[i]))
        videoframes.append(list(frame.getdata(0)))
        frame.close()

    print("\rReading video frames...done!")
    print()

    print("Reducing to 4 bits...", end="")

    for i in range(0, len(videoframes)):
        print("\rReducing to 4 bits..." + str(int(i / len(videoframes) * 100)) + "%", end="", flush=True)
        ts = time.time()

        for j in range(0, len(videoframes[0])):
            pixel = videoframes[i][j]
            pixel = int(round(pixel / (2 ** (8 - 4))))

            # Same issue with the audio samples.
            if pixel == 16:
                pixel = 15

            videoframes[i][j] = pixel

    print("\rReducing to 4 bits...done!")

    if len(videoframes) > 0:
        print("Encoding reduced file...", end="")

        # Remember that we encode the pixel differences over time so the
        # inner loop loops over all frames where the outer one loops over the pixels.
        # This way we loop through all values of one pixel location, then the next, etc...
        for j in range(0, len(videoframes[0])):
            if time.time() - ts > 0.1:
                print("\rEncoding reduced file..." + str(int(j / (len(videoframes[0]) + len(videoframes)) * 100)) + "%", end="", flush=True)
                ts = time.time()

            previous_sample = 0

            for i in range(0, len(videoframes)):
                current_sample = videoframes[i][j]

                if current_sample - previous_sample == 0:
                    videoframes[i][j] = [0]

                elif current_sample - previous_sample == 1:
                    videoframes[i][j] = [1, 0]

                elif current_sample - previous_sample == -1:
                    videoframes[i][j] = [1, 1, 0]

                else:
                    videoframes[i][j] = [1, 1, 1]
                    for k in range(0, 4):
                        videoframes[i][j].append(current_sample >> (4 - 1 - k) & 0b1)

                previous_sample = current_sample

        # But we need to write then in the normal order into the file otherwise
        # we would have to run in a very weird bitwise way through the memory.
        for i in range(0, len(videoframes)):
            if time.time() - ts > 0.1:
                print("\rEncoding reduced file..." + str(int((i + len(videoframes[0])) / (len(videoframes[0]) + len(videoframes)) * 100)) + "%", end="", flush=True)
                ts = time.time()

            for j in range(0, len(videoframes[0])):
                encoded_video_samples.extend(videoframes[i][j])

        while len(encoded_video_samples) % 8 != 0:
            encoded_video_samples.append(0)

        print("\rEncoding reduced file...done!")

        print()

    uncompressed_video_size = 0
    reduced_video_size = 0
    encoded_video_size = 0

    if len(videoframes) > 0:
        # Uncompressed Size: #frames * resolution * 3 bytes per pixel
        uncompressed_video_size = len(videoframes) * len(videoframes[0]) * 3
        reduced_video_size = len(videoframes) * len(videoframes[0]) * (4 / 8)
        encoded_video_size = len(encoded_video_samples) / 8
        print("Uncompressed Size: ".ljust(20) + str(int(uncompressed_video_size / 1024)) + " K")
        print("Reduced Size: ".ljust(20) + str(int(reduced_video_size / 1024)) + " K")
        print("Encoded Size: ".ljust(20) + str(int(encoded_video_size / 1024)) + " K (" + str(round(encoded_video_size / reduced_video_size * 100, 2)) + "%)")
    else:
        print("Uncompressed Size: ".ljust(20) + "0 K")
        print("Reduced Size: ".ljust(20) + "0 K")
        print("Encoded Size: ".ljust(20) + "0 K (100.0%)")

    print("========================================================")

print()
print("======================= Summary ========================")

if output_file is not None:
    print("Writing output file...", end="")

    if os.path.exists(output_file):
        os.remove(output_file)

    file = open(output_file, "wb+")

    # Write File Header
    file.write("A".encode("ascii"))
    file.write(struct.pack("<I", int(len(encoded_audio_samples) / 8)))
    file.write(struct.pack("<I", int(len(encoded_video_samples) / 8)))
    file.write("Z".encode("ascii"))

    for i in range(0, len(encoded_audio_samples), 8):
        if time.time() - ts > 0.1:
            print("\rWriting output file..." + str(int(i / (len(encoded_audio_samples) + len(encoded_video_samples)) * 100)) + "%", end="", flush=True)
            ts = time.time()

        byte = 0

        for j in range(0, 8):
            byte |= encoded_audio_samples[i + j] << j

        file.write(struct.pack("B", byte))

    for i in range(0, len(encoded_video_samples), 8):
        if time.time() - ts > 0.1:
            print("\rWriting output file..." + str(int((i + len(encoded_audio_samples)) / (len(encoded_audio_samples) + len(encoded_video_samples)) * 100)) + "%", end="", flush=True)
            ts = time.time()

        byte = 0

        for j in range(0, 8):
            byte |= encoded_video_samples[i + j] << j

        file.write(struct.pack("B", byte))

    file.close()

    print("\rWriting output file...done!")

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

if reduced_size > 0:
    print("Uncompressed Size: ".ljust(20) + str(int(uncompressed_size / 1024)) + " K")
    print("Reduced Size: ".ljust(20) + str(int(reduced_size / 1024)) + " K")
    print("Encoded Size: ".ljust(20) + str(int(encoded_size / 1024)) + " K (" + str(round(encoded_size / reduced_size * 100, 2)) + "%)")
else:
    print("Uncompressed Size: ".ljust(20) + "0 K")
    print("Reduced Size: ".ljust(20) + "0 K")
    print("Encoded Size: ".ljust(20) + "0 K (100.0%)")

print("========================================================")

shutil.rmtree(temp_dir)
exit(0)
