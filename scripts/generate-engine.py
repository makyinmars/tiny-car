"""Recreate the small, seamless engine bed. Run from any working directory."""
import math
import struct
import wave
from pathlib import Path

RATE = 22050
output = Path(__file__).resolve().parents[1] / "resources/sound/engine.wav"
frames = bytearray()
for i in range(RATE * 2):
    t = i / RATE
    value = sum(
        math.sin(2 * math.pi * 55 * k * t + k * 0.3) / k**1.25
        for k in range(1, 8)
    ) * 0.26
    value *= 0.84 + 0.16 * math.sin(2 * math.pi * 27.5 * t)
    frames.extend(struct.pack("<h", round(value * 26000)))
with wave.open(str(output), "wb") as audio:
    audio.setnchannels(1)
    audio.setsampwidth(2)
    audio.setframerate(RATE)
    audio.writeframes(frames)
