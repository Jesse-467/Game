"""Original synthesized fantasy motif and event cues (22.05kHz mono PCM)."""
import math
import pathlib
import struct
import wave

RATE = 22050

def tone(frequency, time):
    return math.sin(math.tau * frequency * time) + 0.25 * math.sin(math.tau * frequency * 2 * time)

def write(name, samples):
    destination = pathlib.Path("assets/audio")
    destination.mkdir(parents=True, exist_ok=True)
    with wave.open(str(destination / (name + ".wav")), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, value)) * 30000)) for value in samples))

def cue(name, duration, frequencies):
    samples = []
    for index in range(round(duration * RATE)):
        time = index / RATE
        envelope = min(1, time / 0.008) * math.exp(-time * 7 / duration)
        value = sum(tone(frequency, time) for frequency in frequencies) / len(frequencies)
        samples.append(value * envelope * 0.22)
    write(name, samples)

cue("attack", 0.10, [440, 660])
cue("hurt", 0.20, [115, 173])
cue("dash", 0.13, [880, 1320])
cue("skill", 0.50, [261.63, 329.63, 392])
cue("upgrade", 0.70, [523.25, 659.25, 783.99])
cue("boss", 0.85, [130.81, 155.56, 196])
cue("death", 1.10, [130.81, 174.61, 207.65])

# Restrained 16-bar minor-key arpeggio with an exact 32-second seamless loop.
duration = 32.0
chords = [[48, 55, 60, 63], [44, 51, 56, 60], [46, 53, 58, 62], [43, 50, 55, 59]]
samples = [0.0] * round(duration * RATE)
for eighth in range(128):
    chord = chords[(eighth // 8) % len(chords)]
    midi = chord[[0, 1, 2, 3, 2, 1, 3, 1][eighth % 8]] + 12
    frequency = 440 * 2 ** ((midi - 69) / 12)
    start = round(eighth * 0.25 * RATE)
    for offset in range(round(0.60 * RATE)):
        time = offset / RATE
        value = tone(frequency, time) * min(1, time / 0.015) * math.exp(-time * 8) * 0.04
        samples[(start + offset) % len(samples)] += value
for index in range(len(samples)):
    time = index / RATE
    root = chords[int(time / 2) % 4][0] - 12
    frequency = 440 * 2 ** ((root - 69) / 12)
    phase = (time % 2) / 2
    samples[index] += tone(frequency, time) * math.sin(math.pi * phase) ** 2 * 0.045
write("expedition", samples)
print("Composed original expedition loop and seven combat cues")
