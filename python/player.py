import argparse
import os
import sys
import tkinter
import time
import pyaudio
import struct

from header import MediaHeader

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

file = open(args.input, "rb")
binary = file.read()
file.close()

try:
    header = MediaHeader(binary)
except Exception as e:
    print("Input file could not be parsed.")
    print("Error raised: " + str(e))
    exit(0)

# This is done for readability purposes, otherwise the code looks bloated.
WIDTH = header.WIDTH
HEIGHT = header.HEIGHT
AUDIO_LENGTH = header.AUDIO_LENGTH
VIDEO_LENGTH = header.VIDEO_LENGTH
BLOCK_SIZE = args.blocksize

audio = []
audioindex = 0

# Flatten to bit array to decode easier
for i in range(12, 12+AUDIO_LENGTH):
    for j in range(8):
        audio.append((binary[i] >> j) & 0b1)

last_sample = 0

samples = []

state = 0

while audioindex < len(audio):
    match state:
        case 0:
            if audio[audioindex] == 0:
                current_sample = last_sample
                samples.append(current_sample)
                last_sample = current_sample

                state = 0
            else:
                state = 1

            audioindex += 1

        case 1:
            if audio[audioindex] == 0:
                current_sample = last_sample + 1
                if current_sample == 8:
                    current_sample = -8

                samples.append(current_sample)
                last_sample = current_sample

                state = 0
            else:
                state = 2

            audioindex += 1

        case 2:
            if audio[audioindex] == 0:
                current_sample = last_sample - 1
                if current_sample == -9:
                    current_sample = 7

                samples.append(current_sample)
                last_sample = current_sample

                audioindex += 1
            else:
                # The new sample is Int4 so we need to respect the two's complement
                # otherwise it will be parsed as a UInt4
                current_sample = 0 \
                    - 2 ** 3 * audio[audioindex + 1] \
                    + 2 ** 2 * audio[audioindex + 2] \
                    + 2 ** 1 * audio[audioindex + 3] \
                    + 2 ** 0 * audio[audioindex + 4]

                samples.append(current_sample)
                last_sample = current_sample

                audioindex += 5

            state = 0

# The selected playback format is Int8 so the 4-bit data needs to be expanded.
samples = [v * 2 ** 4 for v in samples]

audioindex = 0

def audio_callback(in_data, frame_count, time_info, status):
    global audioindex
    samples_to_insert = min(len(audio) - audioindex, frame_count)

    packed_samples = struct.pack(f"{samples_to_insert}b", *samples[audioindex:audioindex + samples_to_insert])
    audioindex += samples_to_insert

    return (packed_samples, pyaudio.paContinue)

audio_manager = pyaudio.PyAudio()
audio_stream = audio_manager.open(
    rate=44000,
    channels=1,
    format=pyaudio.paInt8,
    output=True,
    start=False,
    stream_callback=audio_callback
)

video = []
videoindex = 0
last_frame = [0] * WIDTH * HEIGHT

# Flatten to bit array to decode easier
for i in range(12+AUDIO_LENGTH, 12+AUDIO_LENGTH+VIDEO_LENGTH):
    for j in range(8):
        video.append((binary[i] >> j) & 0b1)

tk = tkinter.Tk()
tk.title("fpga-mediaplayer")
tk.bind("<Escape>", lambda event: tk.destroy())

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

framecounter = 0
playback_started_time = time.time() - 1 / 24
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

def get_color(sample: int) -> str:
    alphabet = list("0123456789abcdef")
    return "#" + alphabet[sample] * 6

def draw_frame():
    global playback_started_time
    global framecounter
    global pixels
    global videoindex
    global last_frame

    now_time = time.time()

    if now_time - playback_started_time >= (framecounter + 1) * 1/24:
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
                        current_pixel = (last_frame[index] + 1) % 16
                        # The %16 implements the hardware wraparound (15 to 0 and vice versa)

                        canvas.itemconfigure(pixels[index], fill=get_color(current_pixel))
                        last_frame[index] = current_pixel
                        index += 1
                        state = 0

                    elif video[videoindex] == 1:
                        state = 2

                    videoindex += 1

                case 2:
                    if video[videoindex] == 0:
                        current_pixel = (last_frame[index] - 1) % 16

                        canvas.itemconfigure(pixels[index], fill=get_color(current_pixel))
                        videoindex += 1

                    elif video[videoindex] == 1:
                        current_pixel = 0 \
                            | (video[videoindex + 1] << 3) \
                            | (video[videoindex + 2] << 2) \
                            | (video[videoindex + 3] << 1) \
                            | (video[videoindex + 4] << 0)

                        canvas.itemconfigure(pixels[index], fill=get_color(current_pixel))
                        videoindex += 5

                    last_frame[index] = current_pixel
                    index += 1
                    state = 0

        framecounter += 1
        fps = round(framecounter / (now_time - playback_started_time), 1)
        tk.title(f"fpga-mediaplayer - {args.input} - {fps} fps")

    tk.after(1, draw_frame)

tk.after(1, draw_frame)
audio_stream.start_stream()

tk.mainloop()
