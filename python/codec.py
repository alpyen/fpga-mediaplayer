from struct import pack, unpack
from typing import List

from multiprocessing import Queue
from collections import deque

# See the notes about the media encoding for the header structure description
class MediaHeader:
    A: bytes
    WIDTH: int
    HEIGHT: int
    AUDIO_LENGTH: int
    VIDEO_LENGTH: int
    Z: bytes

    def __init__(self, header: bytes):
        unpacked = unpack("<cBBIIc", header[0:12])

        self.A, self.WIDTH, self.HEIGHT, self.AUDIO_LENGTH, self.VIDEO_LENGTH, self.Z = unpacked

        if not (self.A == b"A" and self.Z == b"Z"):
            raise Exception("File does not contain header.")

    @staticmethod
    def as_bytes(width: int, height: int, audio_length: int, video_length: int) -> bytes:
        header = [b"A", width, height, audio_length, video_length, b"Z"]
        return pack("<cBBIIc", *header)


# audio_data consists of Int16 44.1kHz WAVE frames
def audio_encoder(channels: int, length: int, audio_data: bytes, output_queue: deque):
    # We assume in HDL the previous sample to be 0 for the first sample.
    previous_sample = 0

    # Stores the encoded audio data in bits (one bit per index)
    encoded_bits = deque()

    for i in range(length):
        current_sample = 0

        # Reduce to target quality and mono audio

        # Sum up the samples across all available channels
        for j in range(channels):
            # Samples are Int16 coded by our ffmpeg call.
            current_sample += int.from_bytes(
                audio_data[i*(2+channels):i*(2+channels)+2],
                byteorder="little",
                signed=True
            )

        # Calculate the average of the channels
        current_sample = int(round(current_sample / channels))

        # Reduce bitwidth to target quality of 4 bits
        current_sample = int(round(current_sample / (2 ** (2 * 8 - 4))))

        # Since we are rounding and not flooring mono can contain +8 as a sample
        # which is out of the signed 4 bit range -> clip that to +7.
        if current_sample == 8:
            current_sample = 7


        # Encode the reduced sample and put it into the output queue

        # Since the hardware register will wrap around from +7 to -8 we should implement it aswell.
        if current_sample - previous_sample == 0:
            encoded_bits.extend([0])

        elif current_sample - previous_sample == 1 or (current_sample == -8 and previous_sample == 7):
            encoded_bits.extend([1, 0])

        elif current_sample - previous_sample == -1 or (current_sample == 7 and previous_sample == -8):
            encoded_bits.extend([1, 1, 0])

        else:
            encoded_bits.extend([1, 1, 1])
            for j in range(4):
                encoded_bits.append(current_sample >> (4 - 1 - j) & 0b1)

        previous_sample = current_sample

    # Pad to full bytes
    while len(encoded_bits) % 8 != 0:
        encoded_bits.append(0)

    # Write output bytes
    for i in range(0, len(encoded_bits), 8):
        byte = 0

        for j in range(8):
            byte |= encoded_bits.popleft() << j

        output_queue.append(byte)


def audio_decoder(encoded_audio_data: bytes, output_queue: Queue):
    pass


# video_data is list of deque (1d-frames in grayscale 0-255)
def video_encoder(video_data: List[deque], output_queue: deque):
    framelength = len(video_data[0])

    encoded_video_frames = []
    for i in range(len(video_data)):
        encoded_video_frames.append([0] * framelength)

    # Remember that we encode the pixel differences over time so the
    # inner loop loops over all frames where the outer one loops over the pixels.
    # This way we loop through all values of one pixel location, then the next, etc...
    for j in range(framelength):
        previous_pixel = 0

        for i in range(len(video_data)):
            current_pixel = video_data[i].popleft()
            current_pixel = int(round(current_pixel / (2 ** (8 - 4))))

            if current_pixel == 16:
                current_pixel = 15

            if current_pixel - previous_pixel == 0:
                encoded_video_frames[i][j] = [0]

            elif current_pixel - previous_pixel == 1 or (current_pixel == 0 and previous_pixel == 15):
                encoded_video_frames[i][j] = [1, 0]

            elif current_pixel - previous_pixel == -1 or (current_pixel == 15 and previous_pixel == 0):
                encoded_video_frames[i][j] = [1, 1, 0]

            else:
                encoded_video_frames[i][j] = [1, 1, 1]
                for k in range(4):
                    encoded_video_frames[i][j].append(current_pixel >> (4 - 1 - k) & 0b1)

            previous_pixel = current_pixel

    encoded_bits = deque()

    # But we need to write then in the normal order into the file otherwise
    # we would have to run in a very weird bitwise way through the memory.
    for i in range(len(video_data)):
        for j in range(framelength):
            encoded_bits.extend(encoded_video_frames[i][j])

    # Pad to full bytes
    while len(encoded_bits) % 8 != 0:
        encoded_bits.append(0)

    # Write output bytes
    for i in range(0, len(encoded_bits), 8):
        byte = 0

        for j in range(8):
            byte |= encoded_bits.popleft() << j

        output_queue.append(byte)


def video_decoder(width: int, height: int, encoded_video_data: bytes, output_queue: Queue):
    pass
