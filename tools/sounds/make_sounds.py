#!/usr/bin/env python3
"""Synthesises the app's sound effects from scratch (no samples, no
third-party audio), so every file is ours to ship.

    python3 tools/sounds/make_sounds.py

writes 44.1 kHz mono 16-bit WAVs into
`Bible Crossword Challenge/Resources/Sounds/`. Tweak a recipe below and
re-run; the output is deterministic (seeded noise).

The palette is a small handbell family: a soft wooden key tap, a two-note
rising chime for a finished word, and a C-major handbell arpeggio over a
quiet choir-like pad for a finished puzzle.
"""
import os
import wave

import numpy as np

SR = 44_100
OUT = os.path.join(os.path.dirname(__file__), "..", "..",
                   "Bible Crossword Challenge", "Resources", "Sounds")
rng = np.random.default_rng(7)


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def fade(sig, fade_in=0.002, fade_out=0.01):
    """Short ramps at both ends so nothing starts or stops on a click."""
    n_in, n_out = int(SR * fade_in), int(SR * fade_out)
    if n_in:
        sig[:n_in] *= np.linspace(0, 1, n_in)
    if n_out:
        sig[-n_out:] *= np.linspace(1, 0, n_out)
    return sig


def one_pole_lowpass(sig, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    out = np.empty_like(sig)
    y = 0.0
    for i, x in enumerate(sig):
        y = (1 - a) * x + a * y
        out[i] = y
    return out


def tap(freq, seconds=0.06):
    """A soft wooden tick: a fast-decaying body tone, a faint overtone and a
    breath of filtered noise for the contact."""
    t = t_axis(seconds)
    body = np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.007)
    over = 0.25 * np.sin(2 * np.pi * freq * 2.3 * t) * np.exp(-t / 0.003)
    noise = rng.standard_normal(len(t)) * np.exp(-t / 0.0015)
    noise = one_pole_lowpass(noise, 3500) * 0.6
    return fade(body + over + noise, 0.0005, 0.02)


# Handbell-ish partials: (ratio, amplitude, decay seconds). Higher partials
# fade faster, which is most of what makes a struck bell sound warm.
BELL = [(1.0, 1.0, 0.9), (2.0, 0.45, 0.5), (3.0, 0.28, 0.32),
        (4.16, 0.12, 0.2), (5.43, 0.07, 0.14), (6.79, 0.04, 0.1)]


def bell(freq, seconds, decay_scale=1.0):
    t = t_axis(seconds)
    sig = np.zeros_like(t)
    for ratio, amp, decay in BELL:
        sig += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t / (decay * decay_scale))
    strike = rng.standard_normal(len(t)) * np.exp(-t / 0.002)
    sig += one_pole_lowpass(strike, 5000) * 0.08
    return fade(sig, 0.003, 0.05)


def place(track, sig, at):
    start = int(SR * at)
    end = min(len(track), start + len(sig))
    track[start:end] += sig[: end - start]


def pad(freqs, seconds, attack, release_at):
    """A quiet choir-ish swell: detuned sine pairs with a slow vibrato."""
    t = t_axis(seconds)
    sig = np.zeros_like(t)
    vib = 1 + 0.002 * np.sin(2 * np.pi * 5.0 * t)
    for f in freqs:
        for cents in (-4, 4):
            ff = f * 2 ** (cents / 1200)
            sig += np.sin(2 * np.pi * ff * np.cumsum(vib) / SR)
            sig += 0.2 * np.sin(2 * np.pi * 2 * ff * np.cumsum(vib) / SR)
    env = np.clip(t / attack, 0, 1)
    rel = t > release_at
    env[rel] *= np.exp(-(t[rel] - release_at) / 0.35)
    return fade(sig * env, 0.0, 0.05)


def normalise(sig, peak_db):
    return sig / np.max(np.abs(sig)) * 10 ** (peak_db / 20)


def write(name, sig):
    os.makedirs(OUT, exist_ok=True)
    pcm = np.int16(np.clip(sig, -1, 1) * 32767)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


C4, E4, G4 = 261.63, 329.63, 392.00
C5, E5, G5, C6 = 523.25, 659.25, 783.99, 1046.50

# Key taps: the letter a little brighter than delete, as on a real keyboard.
write("key_tap.wav", normalise(tap(1150), -12))
write("key_delete.wav", normalise(tap(800), -13))

# Finished word: G5 then C6, a rising fourth that reads as "done".
word = np.zeros(int(SR * 1.0))
place(word, bell(G5, 0.9, 0.7), 0.0)
place(word, bell(C6, 0.92, 0.8), 0.075)
write("word_complete.wav", normalise(fade(word, 0, 0.08), -3))

# Finished puzzle: C-major handbells up the octave over a soft pad.
solve = np.zeros(int(SR * 2.6))
for i, f in enumerate((C5, E5, G5, C6)):
    place(solve, bell(f, 2.0, 1.4 if f == C6 else 1.0) * (0.85 + 0.05 * i), 0.12 * i)
place(solve, 0.18 * pad((C4, G4, E5), 2.6, 0.45, 1.3), 0.0)
write("puzzle_complete.wav", normalise(fade(solve, 0, 0.15), -2))
print("wrote", sorted(os.listdir(OUT)))
