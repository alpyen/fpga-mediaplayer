import argparse
import sys
import os

import wave

import struct

parser = argparse.ArgumentParser(
    prog="audiocodec",
    description="Encodes a given WAVE file to the project's media format.\n" +
                "\n" +
                "Note that the input file must have 44.1 kHz sample rate\n" +
                "and will be converted down to 4 bits and mono channel.\n" +
                "\n" +
                "Video is not implemented yet and will be left empty.",
    formatter_class=argparse.RawTextHelpFormatter
)
parser.add_argument("-i", "--input", type=str, required=True, help="Input WAVE file")
parser.add_argument("-o", "--output", type=str, required=False, help="Output encoded file")
parser.add_argument("-da", "--dump-audio", action="store_true", help="Dumps a 8 bit WAVE file with the encoded file's quality settings.")

args = parser.parse_args(args=None if sys.argv[1:] else ["--help"])

try:
    inputfile = wave.open(args.input, "r")
except Exception as error:
    print("The WAVE file could not be read correctly.")
    print("Error raised:\n" + str(error))
    exit(0)

if inputfile.getframerate() != 44100:
    print("The sample rate of the WAVE file is " + str(inputfile.getframerate()) + " Hz although it should be 44100 Hz.")
    inputfile.close()
    exit(0)

if inputfile.getnframes() == 0:
    print("The audio file is empty.")
    inputfile.close()
    exit(0)

print("Reading input file...", end="")

depth = inputfile.getsampwidth()
channels = inputfile.getnchannels()
length = inputfile.getnframes()
frames = inputfile.readframes(length)
original_size = length * channels * depth
reduced_size = original_size / channels / depth * (4 / 8)

inputfile.close()

print("done!")
print()

# Print Input file statistics
# Reduced Size is the size that the file after quality loss but before compression.
print("Input: ".ljust(20) + args.input)
print("Bitdepth: ".ljust(20) + str(depth * 8))
print("Channels: ".ljust(20) + str(channels))
print("Size: ".ljust(20) + str(int(original_size / 1024)) + " K")
print("Reduced Size: ".ljust(20) + str(int(reduced_size / 1024)) + " K")
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

if args.dump_audio:
    print("Dumping reduced audio file...", end="")

    if os.path.exists(args.input + "_dump.wav"):
        os.remove(args.input + "_dump.wav")

    dumpfile = wave.open(args.input + "_dump.wav", "w")
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

encoded_samples = []

for i in range(0, length):
    if int(i % (length / 10)) == 0:
        print(str(int(i / length * 100)) + "%...", end="", flush=True)

    current_sample = mono_samples[i]

    if current_sample - previous_sample == 0:
        encoded_samples.extend([0])

    elif current_sample - previous_sample == 1:
        encoded_samples.extend([1, 0])

    elif current_sample - previous_sample == -1:
        encoded_samples.extend([1, 1, 0])

    else:
        encoded_samples.extend([1, 1, 1])
        for j in range(0, 4):
            encoded_samples.append(mono_samples[i] >> (4 - 1 - j) & 0b1)

    previous_sample = current_sample

# Pad to full bytes
while len(encoded_samples) % 8 != 0:
    encoded_samples.append(0)

print("done!")

print()
print("Encoded Size: ".ljust(20) + str(int(len(encoded_samples) / 8 / 1024)) + " K")

print("Encoded To Reduced:".ljust(20) + str(int(round(len(encoded_samples) / 8 / reduced_size * 100, 2))) + " %")

if args.output is not None:
    print()
    print("Writing output file...", end="")

    if os.path.exists(args.output):
        os.remove(args.output)

    outputfile = open(args.output, "wb+")

    # Write File Header
    outputfile.write("A".encode("ascii"))
    outputfile.write(struct.pack("<I", int(len(encoded_samples) / 8)))
    outputfile.write(struct.pack("<I", 0))
    outputfile.write("Z".encode("ascii"))

    for i in range(0, len(encoded_samples), 8):
        if int(i % (len(encoded_samples) / 10)) == 0:
            print(str(int(i / len(encoded_samples) * 100)) + "%...", end="", flush=True)

        byte = 0

        for j in range(0, 8):
            byte |= encoded_samples[i + j] << j

        outputfile.write(struct.pack("B", byte))

    outputfile.close()

    print("done!")
