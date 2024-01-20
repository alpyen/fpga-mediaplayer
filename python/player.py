import argparse
import os
import sys
import tkinter
import time
import struct

def positive(value: int):
    int_value = int(value)
    if int_value <= 0:
        raise argparse.ArgumentTypeError(str(int_value) + " is not a positive integer.")
    return int_value

parser = argparse.ArgumentParser(
    prog="player",
    description="Plays a file that was encoded in the project's media format.\n",
    formatter_class=argparse.RawTextHelpFormatter
)
parser.add_argument("-i", "--input", type=str, required=True, help="Input media file")
parser.add_argument("-b", "--blocksize", action="store", default=32, type=int, required=False, help="Scales a pixel by this amount for a bigger preview window.\n(default: 32)")

args = parser.parse_args(args=None if sys.argv[1:] else ["--help"])

if not os.path.exists(args.input):
    print("Input file does not exist.")
    exit(0)

if int(args.blocksize) <= 0:
    print("Blocksize has to be a positive integer.")
    exit(0)

WIDTH = 32
HEIGHT = 24
BLOCK_SIZE = args.blocksize

file = open(args.input, "rb")
binary = file.read()
file.close()

try:
    header = struct.unpack("<B2IB", binary[0:10])
    if not (header[0] == ord("A") and header[3] == ord("Z")):
        print("File does not contain header.")
        exit(0)
except Exception as e:
    print("Input file could not be parsed.")
    print("Error raised: " + str(e))
    exit(0)

audio = binary[10:10+header[1]]
video = []

# Flatten to bit array to easier decode
for i in range(10+header[1], 10+header[1]+header[2]):
    for j in range(8):
        video.append((binary[i] >> j) & 0b1)

videoindex = 0
last_frame = [0] * WIDTH * HEIGHT

tk = tkinter.Tk()
tk.title("fpga-mediaplayer")

tk.minsize(WIDTH * BLOCK_SIZE, HEIGHT * BLOCK_SIZE)
tk.maxsize(WIDTH * BLOCK_SIZE, HEIGHT * BLOCK_SIZE)

tk.geometry(
    "{}x{}+{}+{}".format(
        WIDTH * BLOCK_SIZE,
        HEIGHT * BLOCK_SIZE,
        int((tk.winfo_screenwidth() - WIDTH * BLOCK_SIZE) / 2),
        int((tk.winfo_screenheight() - HEIGHT * BLOCK_SIZE) / 2)
    )
)

canvas = tkinter.Canvas(tk, width=WIDTH * BLOCK_SIZE, height=HEIGHT * BLOCK_SIZE)

last_frame_time = time.time()
pixels = []

for y in range(0, HEIGHT):
    for x in range(0, WIDTH):
        pixels.append(
            canvas.create_rectangle(
                x * BLOCK_SIZE,
                y * BLOCK_SIZE,
                x * BLOCK_SIZE + BLOCK_SIZE,
                y * BLOCK_SIZE + BLOCK_SIZE,
                fill="#000000",
                width=0
            )
        )

canvas.pack()

def get_color(sample: int):
    alphabet = list("0123456789abcdef")
    return "#" + alphabet[sample] * 6

def draw_frame():
    global last_frame_time
    global pixels
    global videoindex
    global last_frame

    if time.time() - last_frame_time >= 1/24:
        tk.title("fpga-mediaplayer - " + args.input + " - " + str(round(1 / (time.time() - last_frame_time), 1)) + " fps")
        index = 0

        state = 0
        while index < WIDTH * HEIGHT:
            # We have to check the exit manually since it is padded to full bytes
            # and not to full frames.
            if videoindex == len(video):
                exit(0)

            match state:
                case 0:
                    if video[videoindex] == 0:
                        current_pixel = last_frame[index]

                        canvas.itemconfigure(pixels[index], fill=get_color(current_pixel))
                        last_frame[index] = current_pixel
                        index += 1
                        state = 0

                    elif video[videoindex] == 1:
                        state = 1

                    videoindex += 1

                case 1:
                    if video[videoindex] == 0:
                        current_pixel = last_frame[index] + 1

                        canvas.itemconfigure(pixels[index], fill=get_color(current_pixel))
                        last_frame[index] = current_pixel
                        index += 1
                        state = 0

                    elif video[videoindex] == 1:
                        state = 2

                    videoindex += 1

                case 2:
                    if video[videoindex] == 0:
                        current_pixel = last_frame[index] - 1

                        canvas.itemconfigure(pixels[index], fill=get_color(current_pixel))
                        last_frame[index] = current_pixel
                        index += 1
                        state = 0
                        videoindex += 1

                    elif video[videoindex] == 1:
                        current_pixel = 0 \
                            | (video[videoindex + 1] << 3) \
                            | (video[videoindex + 2] << 2) \
                            | (video[videoindex + 3] << 1) \
                            | (video[videoindex + 4] << 0)

                        canvas.itemconfigure(pixels[index], fill=get_color(current_pixel))
                        last_frame[index] = current_pixel
                        index += 1
                        state = 0
                        videoindex += 5

        last_frame_time = time.time()

    tk.after(1, draw_frame)

tk.after(1, draw_frame)
tk.mainloop()
