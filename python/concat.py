import argparse
import sys
import os

parser = argparse.ArgumentParser(
    prog="concat",
    description="Concatenates two binary files together with an offset.\n",
    formatter_class=argparse.RawTextHelpFormatter
)
parser.add_argument("-i", "--input", type=str, required=True, help="Input fpga bitfile (or already concatenated binfile)")
parser.add_argument("-m", "--mediafile", type=str, required=True, help="Mediafile to append after the bitfile or at a specific index.")
parser.add_argument("-p", "--position", type=str, required=False, help="Place the mediafile at this byte position (decimal or hex).\nExisting data will not be overwritten.\n(default: append after input file)")
parser.add_argument("-o", "--output", type=str, required=True, help="Output binfile that contains both files.")

args = parser.parse_args(args=None if sys.argv[1:] else ["--help"])

if not os.path.exists(args.input):
    print("Input file not found.")
    exit(0)

if not os.path.exists(args.mediafile):
    print("Media file not found.")
    exit(0)

input_size = os.path.getsize(args.input)
position = input_size

if args.position is not None:
    try:
        if args.position[0:2] == "0x":
            position = int(args.position, 16)
        else:
            position = int(args.position)
    except:
        print("Byte position is not a valid hex number.")
        exit(0)

    if position <= 0:
        print("Byte position cannot be zero or negative.")
        exit(0)


if position < input_size:
    print("Byte position needs to be after the input file.")
    exit(0)

with open(args.output, "wb") as output_file:
    # Copy bitfile contents
    with open(args.input, "rb") as input_file:
        output_file.write(input_file.read())

    # Insert padding if necessary
    output_file.write(bytes(position - input_size))

    # Insert mediafile
    with open(args.mediafile, "rb") as media_file:
        output_file.write(media_file.read())
