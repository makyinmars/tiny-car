"""Reproduce Tiny Car's original open-wheel loop and friendly warning sounds."""
import math
from pathlib import Path
import struct
import wave

RATE = 22050
ROOT = Path(__file__).resolve().parents[1] / "resources/sound"


def save(name, seconds, sample):
    frames = bytearray()
    for index in range(round(RATE * seconds)):
        value = max(-1, min(1, sample(index / RATE)))
        frames.extend(struct.pack("<h", round(value * 25000)))
    with wave.open(str(ROOT / name), "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(RATE)
        audio.writeframes(frames)


def engine(t):
    # Integer frequencies make the two-second loop seamless. Higher harmonics
    # distinguish the race car from the player's low, 55 Hz engine bed.
    return sum(
        math.sin(2 * math.pi * 185 * harmonic * t + harmonic * 0.2)
        / harmonic**1.1
        for harmonic in range(1, 9)
    ) * (0.24 + 0.025 * math.sin(2 * math.pi * 37 * t))


def chime(t, base):
    note = int(t / 0.14)
    local = t % 0.14
    envelope = min(1, local / 0.008) * max(0, 1 - local / 0.14) ** 2
    return math.sin(2 * math.pi * base * (1 if note == 0 else 1.5) * local) * envelope * 0.38


save("open-wheel.wav", 2, engine)
save("pedestrian-alert.wav", 0.28, lambda t: chime(t, 660))
save("fast-alert.wav", 0.28, lambda t: chime(t, 990))
save(
    "whoops.wav",
    0.38,
    lambda t: math.sin(2 * math.pi * (420 * t - 320 * t * t)
                       + 0.8 * math.sin(2 * math.pi * 18 * t))
    * math.sin(math.pi * t / 0.38) ** 2 * 0.4,
)
