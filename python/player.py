import argparse
import os
import sys
import tkinter
import time
import pyaudio
import struct

from codec import MediaFile, audio_decoder, video_decoder
from multiprocessing import Process, Queue

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
    mediafile = MediaFile(binary)
    # MediaFile copies the audio and video ranges,
    # so there's no need to keep an additional copy of the file around.
    del binary
except Exception as e:
    print("Input file could not be parsed.")
    print("Error raised: " + str(e))
    exit(0)

# This is done for readability purposes, otherwise the code looks bloated.
WIDTH = mediafile.WIDTH
HEIGHT = mediafile.HEIGHT
AUDIO_LENGTH = mediafile.AUDIO_LENGTH
VIDEO_LENGTH = mediafile.VIDEO_LENGTH
BLOCK_SIZE = args.blocksize

COLORS = ["#" + c * 6 for c in "0123456789abcdef"]

# Pre-Decode audio and video
audio_queue = audio_decoder(mediafile.AUDIO)
video_queue = video_decoder(WIDTH * HEIGHT, mediafile.VIDEO)


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


def audio_callback(in_data, frame_count, time_info, status):
    # Check if we still have enough frames available.
    insertable_frames = min(len(audio_queue), frame_count)

    # The selected playback format is Int8 so the Int4 data needs to be expanded.
    packed_samples = struct.pack(
        f"{insertable_frames}b",
        *[audio_queue.popleft() << 4 for _ in range(insertable_frames)]
    )

    return (packed_samples, pyaudio.paContinue)

audio_manager = pyaudio.PyAudio()
audio_stream = audio_manager.open(
    rate=44100,
    channels=1,
    format=pyaudio.paInt8,
    output=True,
    start=False,
    stream_callback=audio_callback
)

def video_callback():
    global playback_started_time
    global framecounter
    global pixels

    now_time = time.time()

    for i in range(len(pixels)):
        canvas.itemconfigure(pixels[i], fill=COLORS[video_queue.popleft()])

    framecounter += 1
    fps = round(framecounter / (now_time - playback_started_time), 1)
    tk.title(f"fpga-mediaplayer - {args.input} - {fps} fps")

    # Instead of sleeping 1ms and checking if we need to display the frame
    # we will just sleep the time until the frame is supposed to be played.
    # This works remarkably well if the decoding process only takes a millisecond or two
    # otherwise it will not play on time.
    play_time = now_time - playback_started_time
    next_frame_time = (framecounter + 1) * 1/24

    delay = max(int(round((next_frame_time - play_time) * 1000)), 1)
    tk.after(delay, video_callback)

playback_started_time = time.time()

tk.after(1, video_callback)
audio_stream.start_stream()

tk.mainloop()
