import argparse
import os
import sys
import tkinter
import time
import pyaudio
import struct

from codec import MediaFile, audio_decoder, video_decoder
from collections import deque

from PIL import ImageTk, ImageDraw


parser = argparse.ArgumentParser(
    prog="player",
    description="Plays a file that was encoded in the project's media format.\n" +
                "\n" +
                "Press [Space] to pause and [m] to mute.",
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
BLOCK_SIZE = args.blocksize
COLORS = ["#" + c * 6 for c in "0123456789abcdef"]


muted = False
def toggle_mute(event):
    global muted
    muted = not muted

playing = True
last_pause_time = 0
total_pause = 0

def toggle_playstate(event):
    global playing, last_pause_time, total_pause

    playing = not playing
    now_time = time.time()

    if playing:
        total_pause += now_time - last_pause_time
        audio_stream.start_stream()
    else:
        audio_stream.stop_stream()
        last_pause_time = now_time


tk = tkinter.Tk()
tk.title("fpga-mediaplayer")
tk.bind("<Escape>", lambda event: tk.destroy())
tk.bind("<space>", toggle_playstate)
tk.bind("m", toggle_mute)

tk.minsize(WIDTH * BLOCK_SIZE, HEIGHT * BLOCK_SIZE)
tk.maxsize(WIDTH * BLOCK_SIZE, HEIGHT * BLOCK_SIZE)

tk.geometry(
    "{}x{}+{}+{}".format(
        WIDTH * BLOCK_SIZE,
        HEIGHT * BLOCK_SIZE,
        (tk.winfo_screenwidth() - WIDTH * BLOCK_SIZE) // 2,
        (tk.winfo_screenheight() - HEIGHT * BLOCK_SIZE) // 2
    )
)

canvas = tkinter.Canvas(tk, width=WIDTH * BLOCK_SIZE, height=HEIGHT * BLOCK_SIZE)
canvas.pack()

frame_image = ImageTk.Image.new("L", (WIDTH * BLOCK_SIZE, HEIGHT * BLOCK_SIZE))
frame_draw = ImageDraw.Draw(frame_image)
frame_photo = ImageTk.PhotoImage(frame_image)

canvas_image = canvas.create_image(0, 0, anchor="nw", image=frame_photo)


print("Decoding audio...", end="", flush=True)
audio_queue = audio_decoder(mediafile.AUDIO)
print("done!")
print("Decoding video...", end="", flush=True)
video_queue = video_decoder(WIDTH * HEIGHT, mediafile.VIDEO)
print("done!")


samples_skipped = 0
samples_played = 0

def audio_callback(in_data, frame_count, time_info, status):
    global samples_played, samples_skipped

    # Check if we still have enough frames available.
    insertable_frames = min(len(audio_queue), frame_count)

    # PyAudio will start skewing if we keep start and stopping the audio stream
    # or if it can't keep up with the framerate.
    # It results in slower playback due to the overhead so we need to remove
    # the samples that should not be in there anymore.
    total_elapsed_time = time.time() - playback_started_time - total_pause
    expected_elapsed_samples = int(total_elapsed_time * 44100)
    samples_behind = expected_elapsed_samples - samples_played

    # Pyaudio calls this callback shortly before the data is necesssary
    # so the expected_elapsed_samples does not really match.
    # Otherwise we would also have it elastic like the video_callback
    # to insert more samples when we are below the skipping threshold.

    # Start skipping samples if we are behind.
    if samples_behind > 0:
        for i in range(samples_behind):
            audio_queue.popleft()

        samples_skipped += samples_behind
        samples_played += samples_behind

    # The selected playback format is Int8 so the Int4 data needs to be expanded.
    packed_samples = struct.pack(
        f"{insertable_frames}b",
        *[audio_queue.popleft() << 4 for _ in range(insertable_frames)]
    )

    samples_played += insertable_frames

    if muted:
        packed_samples = bytes(insertable_frames)

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


frames_played = 0
frames_skipped = 0

def video_callback():
    global frames_played, frames_skipped
    global frametimes, last_framedecode_time
    global frame_photo

    if not playing:
        tk.after(2, video_callback)
        return

    if len(video_queue) == 0:
        # It does the job.
        exit(0)

    now_time = time.time()

    # Frameskip implementation analoguous to the one in audio_callback.
    total_elapsed_time = now_time - playback_started_time - total_pause
    expected_elapsed_frames = int(total_elapsed_time * 24)
    frames_behind = expected_elapsed_frames - frames_played

    # Start skipping frames if we are more than one frame behind.
    # If not, the rescheduling of the video_callback will be done
    # automatically with a lower delay so we can catch back up.
    if frames_behind > 1:
        for i in range(frames_behind * WIDTH * HEIGHT):
            video_queue.popleft()

        frames_played += frames_behind
        frames_skipped += frames_behind

        play_time = now_time - playback_started_time - total_pause
        next_frame_time = frames_played * 1/24

        delay = max(int(round((next_frame_time - play_time) * 1000)), 1)
        tk.after(delay, video_callback)
        return


    for y in range(HEIGHT):
        for x in range(WIDTH):
            frame_draw.rectangle(
                (
                    x * BLOCK_SIZE,
                    y * BLOCK_SIZE,
                    (x+1) * BLOCK_SIZE,
                    (y+1) * BLOCK_SIZE
                ),
                fill=video_queue.popleft() << 4
            )

    frame_photo = ImageTk.PhotoImage(frame_image)
    canvas.itemconfigure(canvas_image, image=frame_photo)

    frametimes.append(now_time - last_framedecode_time)
    last_framedecode_time = now_time
    frames_played += 1

    # Instead of sleeping 1ms and checking if we need to display the frame
    # we will just sleep the time until the frame is supposed to be played.
    # This works remarkably well if the decoding process only takes a millisecond or two
    # otherwise it will not play on time.
    play_time = now_time - playback_started_time - total_pause
    next_frame_time = frames_played * 1/24

    delay = max(int(round((next_frame_time - play_time) * 1000)), 1)
    tk.after(delay, video_callback)


TOTAL_FRAMES = len(video_queue) // WIDTH // HEIGHT

def update_title():
    fps = round(len(frametimes) / sum(frametimes), 1)

    tk.title(
        f"fpga-mediaplayer" \
        + f" - {args.input}" \
        + f" - {fps} fps" \
        + f" - Frame: {frames_played} / {TOTAL_FRAMES}" \
        + f" - Skipped {frames_skipped} frames and {samples_skipped} samples" \
        + (" [Paused]" if not playing else "") \
        + (" [Muted]" if muted else "")
    )

    tk.after(5, update_title)

playback_started_time = time.time()

frametimes = deque([.1], 24)
last_framedecode_time = time.time()


audio_stream.start_stream()
tk.after(1, video_callback)
tk.after(1, update_title)

tk.mainloop()
