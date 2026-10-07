#!/usr/bin/env python3
"""Synthesizes every sound on the board from scratch, so the app ships no borrowed audio.

Standard library only. Writes 44.1 kHz mono WAVs to build/sounds/, then converts each to
AAC .m4a in Shared/Sounds/ with macOS's afconvert. Rerun after changing a recipe:

    python3 scripts/make-sounds.py
"""

import math
import random
import struct
import subprocess
import wave
from pathlib import Path

SR = 44100
ROOT = Path(__file__).resolve().parent.parent
WAV_DIR = ROOT / "build" / "sounds"
OUT_DIR = ROOT / "Shared" / "Sounds"
PEAK = 0.89  # headroom under full scale so AAC doesn't clip
TARGET_RMS = 0.24

random.seed(7)  # same file every run


# ---------- building blocks ----------

def silence(seconds):
    return [0.0] * int(seconds * SR)


def mix(*tracks):
    out = [0.0] * max(len(t) for t in tracks)
    for track in tracks:
        for i, v in enumerate(track):
            out[i] += v
    return out


def place(track, at, length):
    """Pads `track` so it starts `at` seconds into a buffer `length` seconds long."""
    start = int(at * SR)
    out = [0.0] * int(length * SR)
    for i, v in enumerate(track):
        if start + i < len(out):
            out[start + i] += v
    return out


def gain(track, g):
    return [v * g for v in track]


def drive(track, amount):
    norm = math.tanh(amount)
    return [math.tanh(v * amount) / norm for v in track]


def lowpass(track, cutoff):
    """One-pole lowpass. `cutoff` may be a number or a function of time."""
    out, y = [], 0.0
    for i, v in enumerate(track):
        fc = cutoff(i / SR) if callable(cutoff) else cutoff
        a = 1 - math.exp(-2 * math.pi * fc / SR)
        y += a * (v - y)
        out.append(y)
    return out


def highpass(track, cutoff):
    low = lowpass(track, cutoff)
    return [v - l for v, l in zip(track, low)]


def bandpass(track, low, high):
    return lowpass(highpass(track, low), high)


def reverb(track, wet=0.3, tail=1.2):
    """Small Schroeder reverb: four parallel combs into two allpasses."""
    padded = track + silence(tail)
    combs = [(1557, 0.84), (1617, 0.83), (1491, 0.82), (1422, 0.81)]
    acc = [0.0] * len(padded)
    for delay, fb in combs:
        buf = [0.0] * len(padded)
        for i, v in enumerate(padded):
            buf[i] = v + (fb * buf[i - delay] if i >= delay else 0.0)
        for i in range(len(acc)):
            acc[i] += buf[i] / len(combs)
    for delay, g in [(225, 0.5), (556, 0.5)]:
        out = [0.0] * len(acc)
        for i, v in enumerate(acc):
            prev_in = acc[i - delay] if i >= delay else 0.0
            prev_out = out[i - delay] if i >= delay else 0.0
            out[i] = -g * v + prev_in + g * prev_out
        acc = out
    return [d + wet * w for d, w in zip(padded, acc)]


def env_exp(seconds, decay, attack=0.002):
    n = int(seconds * SR)
    return [min(1.0, (i / SR) / attack) * math.exp(-(i / SR) / decay) for i in range(n)]


def env_adsr(seconds, attack=0.01, release=0.05):
    n = int(seconds * SR)
    out = []
    for i in range(n):
        t = i / SR
        out.append(min(1.0, t / attack, (seconds - t) / release))
    return [max(0.0, v) for v in out]


def apply(track, envelope):
    return [v * e for v, e in zip(track, envelope)]


def osc(seconds, freq, shape="sine", phase=0.0):
    """`freq` may be a number or a function of time (for sweeps and vibrato)."""
    out, ph = [], phase
    for i in range(int(seconds * SR)):
        f = freq(i / SR) if callable(freq) else freq
        ph = (ph + f / SR) % 1.0
        if shape == "sine":
            out.append(math.sin(2 * math.pi * ph))
        elif shape == "saw":
            out.append(2 * ph - 1)
        elif shape == "square":
            out.append(1.0 if ph < 0.5 else -1.0)
        elif shape == "triangle":
            out.append(4 * abs(ph - 0.5) - 1)
    return out


def noise(seconds):
    return [random.uniform(-1, 1) for _ in range(int(seconds * SR))]


def finish(track, fade=0.01):
    n = int(fade * SR)
    for i in range(min(n, len(track))):
        track[-1 - i] *= i / n
    # Level by loudness (RMS) so one pad isn't twice as loud as the next, never past PEAK.
    peak = max(abs(v) for v in track) or 1.0
    rms = math.sqrt(sum(v * v for v in track) / len(track)) or 1.0
    scale = min(PEAK / peak, TARGET_RMS / rms)
    return [v * scale for v in track]


# ---------- the board ----------

def boom():
    sweep = lambda t: 45 + 95 * math.exp(-t * 7)
    body = apply(osc(1.6, sweep), env_exp(1.6, 0.45, attack=0.004))
    click = apply(lowpass(noise(0.03), 2500), env_exp(0.03, 0.006))
    hit = mix(drive(body, 2.4), gain(click, 0.6))
    return reverb(hit, wet=0.55, tail=1.0)


def airhorn():
    def blast(seconds, bend):
        f = lambda t, base: base * (1 - bend * max(0.0, t - (seconds - 0.25)))
        voices = [osc(seconds, lambda t, b=b: f(t, b), "saw") for b in (466, 469, 587, 590)]
        tone = drive(lowpass(mix(*voices), 3200), 1.8)
        return apply(tone, env_adsr(seconds, attack=0.015, release=0.06))
    total = 1.45
    return reverb(
        mix(
            place(blast(0.16, 0), 0.0, total),
            place(blast(0.16, 0), 0.22, total),
            place(blast(0.95, 0.35), 0.48, total),
        ),
        wet=0.25,
        tail=0.5,
    )


def snare(seconds=0.22, tone=190):
    rattle = apply(bandpass(noise(seconds), 900, 7000), env_exp(seconds, 0.06))
    body = apply(osc(seconds, lambda t: tone * (1 + 0.6 * math.exp(-t * 60))), env_exp(seconds, 0.04))
    return mix(gain(rattle, 0.8), gain(body, 0.7))


def tom(freq=120):
    return apply(osc(0.45, lambda t: freq * (1 + 0.8 * math.exp(-t * 25))), env_exp(0.45, 0.13))


def cymbal(seconds=1.4):
    return apply(highpass(noise(seconds), 5000), env_exp(seconds, 0.38, attack=0.001))


def rimshot():
    total = 2.0
    return reverb(
        mix(
            place(snare(), 0.0, total),
            place(tom(), 0.17, total),
            place(mix(gain(snare(), 0.9), gain(cymbal(), 0.7)), 0.42, total),
        ),
        wet=0.2,
        tail=0.4,
    )


def sad_trombone():
    notes = [(233.1, 0.42), (220.0, 0.42), (207.7, 0.42), (196.0, 1.5)]
    out = []
    for i, (freq, seconds) in enumerate(notes):
        last = i == len(notes) - 1
        wobble = (lambda t, f=freq: f * (1 + 0.012 * math.sin(2 * math.pi * 6 * t) * min(1, t / 0.4))) if last else freq
        tone = osc(seconds, wobble, "saw")
        # the "wah": the filter opens as each note speaks
        wah = lowpass(tone, lambda t: 300 + 1700 * min(1.0, t / 0.12) * (0.55 if last else 1.0))
        out += apply(wah, env_adsr(seconds, attack=0.03, release=0.09 if not last else 0.4))
    return reverb(out, wet=0.2, tail=0.4)


def crickets():
    total = 2.6

    def cricket(freq, start, gap, level):
        track = silence(total)
        t0 = start
        while t0 < total - 0.2:
            for pulse in range(3):
                chirp = apply(osc(0.035, freq), env_adsr(0.035, attack=0.005, release=0.012))
                at = int((t0 + pulse * 0.05) * SR)
                for i, v in enumerate(chirp):
                    if at + i < len(track):
                        track[at + i] += v * level
            t0 += gap
        return track

    night = gain(lowpass(noise(total), 400), 0.03)
    return reverb(mix(cricket(4600, 0.05, 0.52, 1.0), cricket(4250, 0.3, 0.61, 0.55), night), wet=0.3, tail=0.4)


def bell(freq, seconds=1.4):
    partials = [(1.0, 1.0, 0.9), (2.0, 0.5, 0.5), (2.76, 0.35, 0.35), (5.4, 0.15, 0.12)]
    return mix(*[apply(osc(seconds, freq * r), env_exp(seconds, d)) for r, _, d in partials],
               *[gain(apply(osc(seconds, freq * r), env_exp(seconds, d)), a - 1) for r, a, d in partials])


def ding():
    total = 1.8
    return reverb(mix(place(bell(1046.5), 0.0, total), place(bell(1318.5), 0.13, total)), wet=0.25, tail=0.4)


def buzzer():
    def buzz(seconds):
        tone = mix(osc(seconds, 98, "square"), osc(seconds, 104, "saw"))
        return apply(lowpass(drive(tone, 2.0), 2400), env_adsr(seconds, attack=0.005, release=0.04))
    total = 1.0
    return mix(place(buzz(0.28), 0.0, total), place(buzz(0.62), 0.36, total))


def record_scratch():
    # a "record" of a bright chord, read back with the hand pushing and pulling the needle
    source = lowpass(mix(osc(2.0, 220, "saw"), osc(2.0, 277, "saw"), osc(2.0, 330, "saw"), gain(noise(2.0), 0.3)), 5000)
    out, pos = [], 0.4 * SR
    seconds = 0.75
    for i in range(int(seconds * SR)):
        t = i / SR
        speed = 3.2 * math.sin(2 * math.pi * 3.6 * t) * math.exp(-t * 1.3)
        pos = min(max(pos + speed, 0), len(source) - 2)
        j = int(pos)
        frac = pos - j
        out.append((source[j] * (1 - frac) + source[j + 1] * frac) * min(1.0, abs(speed)))
    return bandpass(out, 250, 6000) + silence(0.15)


def brass(freq, seconds, swell=False):
    tone = mix(osc(seconds, freq, "saw"), gain(osc(seconds, freq / 2, "saw"), 0.6), gain(osc(seconds, freq * 1.003, "saw"), 0.5))
    opened = lowpass(tone, lambda t: 500 + 2200 * min(1.0, t / (0.25 if swell else 0.05)))
    return apply(drive(opened, 1.6), env_adsr(seconds, attack=0.02, release=0.6 if swell else 0.05))


def dun_dun_dun():
    total = 3.0
    timpani = apply(osc(1.6, lambda t: 82 * (1 + 0.2 * math.exp(-t * 20))), env_exp(1.6, 0.6))
    return reverb(
        mix(
            place(brass(196.0, 0.26), 0.0, total),
            place(brass(196.0, 0.26), 0.38, total),
            place(brass(155.6, 2.0, swell=True), 0.9, total),
            place(gain(timpani, 0.8), 0.9, total),
        ),
        wet=0.4,
        tail=0.6,
    )


def bonk():
    knock = apply(osc(0.5, lambda t: 420 * (1 + 0.5 * math.exp(-t * 40)) * (1 - 0.35 * min(1, t / 0.2))), env_exp(0.5, 0.09))
    ring = apply(osc(0.5, 1170), env_exp(0.5, 0.05))
    click = apply(bandpass(noise(0.02), 1500, 6000), env_exp(0.02, 0.004))
    return mix(drive(knock, 1.5), gain(ring, 0.25), gain(click, 0.5)) + silence(0.1)


def fart():
    seconds = 1.1
    out, ph = [], 0.0
    jitter = lowpass(noise(seconds), 9)
    for i in range(int(seconds * SR)):
        t = i / SR
        f = 78 + 30 * math.sin(2 * math.pi * 2.3 * t) + 900 * jitter[i] - 25 * t
        ph = (ph + max(f, 30) / SR) % 1.0
        out.append(1.0 if ph < 0.2 else -0.25)  # thin pulses buzz like lips do
    shaped = apply(lowpass(out, 900), env_adsr(seconds, attack=0.02, release=0.25))
    flutter = [1 + 0.35 * math.sin(2 * math.pi * 17 * (i / SR)) for i in range(len(shaped))]
    return apply(shaped, flutter) + silence(0.1)


def whoosh():
    seconds = 0.9
    center = lambda t: 300 + 4500 * math.sin(math.pi * t / seconds) ** 2
    air = lowpass(highpass(noise(seconds), lambda t: center(t) * 0.5), center)
    swell = [math.sin(math.pi * (i / SR) / seconds) ** 2 for i in range(len(air))]
    return reverb(apply(air, swell), wet=0.2, tail=0.3)


def applause():
    total = 3.0
    crowd = silence(total)
    for _ in range(420):
        at = random.betavariate(1.6, 2.2) * (total - 0.3)
        clap = apply(bandpass(noise(0.03), 700 + random.random() * 900, 3500), env_exp(0.03, 0.007))
        level = random.uniform(0.3, 1.0)
        start = int(at * SR)
        for i, v in enumerate(clap):
            crowd[start + i] += v * level
    return reverb(crowd, wet=0.35, tail=0.4)


def drumroll():
    total = 3.0
    track = silence(total)
    t, n = 0.0, 0
    while t < 1.9:
        hit = gain(snare(0.12, 210), 0.25 + 0.75 * (t / 1.9) ** 1.5)
        start = int(t * SR)
        for i, v in enumerate(hit):
            track[start + i] += v
        t += 0.045 if n % 2 else 0.05
        n += 1
    crash = mix(gain(cymbal(1.0), 1.3), gain(tom(90), 1.2))
    return reverb(mix(track, place(crash, 1.95, total)), wet=0.25, tail=0.4)


def boing():
    seconds = 1.0
    f = lambda t: 220 * (1 + 0.9 * min(1, t / 0.06)) * (1 + 0.25 * math.sin(2 * math.pi * 13 * t) * math.exp(-t * 3.5))
    return apply(mix(osc(seconds, f), gain(osc(seconds, lambda t: 2 * f(t), "triangle"), 0.25)), env_exp(seconds, 0.35, attack=0.005))


def coin():
    first = apply(osc(0.08, 987.8, "square"), env_adsr(0.08, attack=0.002, release=0.005))
    second = apply(osc(0.5, 1318.5, "square"), env_exp(0.5, 0.16))
    return lowpass(first + second, 7000) + silence(0.1)


BOARD = {
    "boom": boom,
    "airhorn": airhorn,
    "rimshot": rimshot,
    "sad-trombone": sad_trombone,
    "crickets": crickets,
    "ding": ding,
    "buzzer": buzzer,
    "record-scratch": record_scratch,
    "dun-dun-dun": dun_dun_dun,
    "bonk": bonk,
    "fart": fart,
    "whoosh": whoosh,
    "applause": applause,
    "drumroll": drumroll,
    "boing": boing,
    "coin": coin,
}


def write_wav(path, track):
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767)) for v in track))


def main():
    WAV_DIR.mkdir(parents=True, exist_ok=True)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, recipe in BOARD.items():
        wav = WAV_DIR / f"{name}.wav"
        m4a = OUT_DIR / f"{name}.m4a"
        track = finish(recipe())
        write_wav(wav, track)
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "128000", str(wav), str(m4a)], check=True)
        print(f"{name:16} {len(track) / SR:4.2f}s  ->  {m4a.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
