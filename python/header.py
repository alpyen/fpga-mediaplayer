from struct import pack, unpack

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
