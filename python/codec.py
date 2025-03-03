from struct import pack, unpack
from typing import List

from collections import deque

# See the notes about the media encoding for the header structure description
class MediaFile:
    A: bytes
    WIDTH: int
    HEIGHT: int
    AUDIO_LENGTH: int
    VIDEO_LENGTH: int
    Z: bytes
    AUDIO: bytes
    VIDEO: bytes

    def __init__(self, file: bytes):
        unpacked = unpack("<cBBIIc", file[0:12])

        self.A, self.WIDTH, self.HEIGHT, self.AUDIO_LENGTH, self.VIDEO_LENGTH, self.Z = unpacked

        if not (self.A == b"A" and self.Z == b"Z"):
            raise Exception("File does not contain header.")

        self.AUDIO = file[12:12+self.AUDIO_LENGTH]
        self.VIDEO = file[12+self.AUDIO_LENGTH:12+self.AUDIO_LENGTH+self.VIDEO_LENGTH]

    @staticmethod
    def as_bytes(width: int, height: int, audio_length: int, video_length: int) -> bytes:
        header = [b"A", width, height, audio_length, video_length, b"Z"]
        return pack("<cBBIIc", *header)


# audio_data consists of Int16 44.1kHz WAVE frames
def audio_encoder(channels: int, length: int, audio_data: bytes) -> bytes:
    # We assume in HDL the previous sample to be 0 for the first sample.
    previous_sample = 0

    # Stores the encoded audio data in bits (one bit per index)
    encoded_bits = deque()

    for i in range(length):
        # Sum up the samples across all available channels
        current_sample = 0

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
    encoded_audio = deque()

    for i in range(0, len(encoded_bits), 8):
        byte = 0

        for j in range(8):
            byte |= encoded_bits.popleft() << j

        encoded_audio.append(byte)

    return bytes(encoded_audio)


def audio_decoder(encoded_audio_data: bytes) -> deque:
    previous_sample = 0

    encoded_bits = deque()
    for i in range(len(encoded_audio_data)):
        byte = encoded_audio_data[i]
        for j in range(8):
            encoded_bits.append((byte >> j) & 0b1)

    decoded_audio = deque()
    state = 0

    while len(encoded_bits) > 0:
        match state:
            case 0:
                if encoded_bits.popleft() == 0:
                    decoded_audio.append(previous_sample)
                else:
                    state = 1

            case 1:
                if encoded_bits.popleft() == 0:
                    current_sample = previous_sample + 1
                    if current_sample == 8:
                        current_sample = -8

                    decoded_audio.append(current_sample)

                    previous_sample = current_sample
                    state = 0
                else:
                    state = 2

            case 2:
                if encoded_bits.popleft() == 0:
                    current_sample = previous_sample - 1
                    if current_sample == -9:
                        current_sample = 7
                else:
                    # The new sample is Int4 so we need to respect the two's complement
                    # otherwise it will be parsed as a UInt4
                    current_sample = 0 \
                        - 2 ** 3 * encoded_bits.popleft() \
                        + 2 ** 2 * encoded_bits.popleft() \
                        + 2 ** 1 * encoded_bits.popleft() \
                        + 2 ** 0 * encoded_bits.popleft()

                decoded_audio.append(current_sample)

                previous_sample = current_sample
                state = 0

    return decoded_audio

# video_data is list of deque (1d-frames in grayscale 0-255)
def video_encoder(video_data: List[deque]) -> bytes:
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

    # But we need to write then in the normal order into the file otherwise
    # we would have to run in a very weird bitwise way through the memory.
    encoded_bits = deque()

    for i in range(len(video_data)):
        for j in range(framelength):
            encoded_bits.extend(encoded_video_frames[i][j])

    # Pad to full bytes
    while len(encoded_bits) % 8 != 0:
        encoded_bits.append(0)

    # Write output bytes
    encoded_video = deque()
    for i in range(0, len(encoded_bits), 8):
        byte = 0

        for j in range(8):
            byte |= encoded_bits.popleft() << j

        encoded_video.append(byte)

    return bytes(encoded_video)


def video_decoder(framelength: int, encoded_video_data: bytes) -> deque:
    previous_frame = [0] * framelength
    pixel_counter = 0

    encoded_bits = deque()
    for i in range(len(encoded_video_data)):
        byte = encoded_video_data[i]
        for j in range(8):
            encoded_bits.append((byte >> j) & 0b1)

    decoded_video = deque()
    state = 0

    while len(encoded_bits) > 0:
        match state:
            case 0:
                if encoded_bits.popleft() == 0:
                    decoded_video.append(previous_frame[pixel_counter])
                    pixel_counter += 1

                    state = 0
                else:
                    state = 1

            case 1:
                if encoded_bits.popleft() == 0:
                    current_pixel = previous_frame[pixel_counter] + 1
                    if current_pixel == 16:
                        current_pixel = 0

                    decoded_video.append(current_pixel)
                    previous_frame[pixel_counter] = current_pixel
                    pixel_counter += 1

                    state = 0
                else:
                    state = 2

            case 2:
                if encoded_bits.popleft() == 0:
                    current_pixel = previous_frame[pixel_counter] - 1
                    if current_pixel == -1:
                        current_pixel = 15
                else:
                    current_pixel = 0 \
                        | (encoded_bits.popleft() << 3) \
                        | (encoded_bits.popleft() << 2) \
                        | (encoded_bits.popleft() << 1) \
                        | (encoded_bits.popleft() << 0)

                decoded_video.append(current_pixel)
                previous_frame[pixel_counter] = current_pixel
                pixel_counter += 1

                state = 0

        if pixel_counter == framelength:
            pixel_counter = 0

            # Since we pad the data to full bytes there can be bits remaining.
            # This can be atmost 7 bits and we need to check for this
            # when we finished processing a frame (pixel_counter wraps to 0).
            if len(encoded_bits) < 8:
                break

    return decoded_video
