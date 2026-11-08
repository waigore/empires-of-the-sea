"""Offline DSP kit for Empires of the Sea.

Everything here is deterministic (no randomness without a seed) and depends only on
numpy, so the shipped audio in ``assets/audio`` can be rebuilt from source:

    python tools/audio/build_audio.py

Instruments model period forces rather than synth patches: plucked gut strings
(lute/theorbo), quilled harpsichord, bowed viols and violins, wooden flutes, and
hide-headed drums. Nothing here is sampled, so no third-party licences leak into
the build.
"""

from __future__ import annotations

import os
import struct
import subprocess
import wave

import numpy as np

RATE = 44100

_NOTE_BASE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name: str) -> int:
    """'A4' -> 69. Accepts sharps (#) and flats (b)."""
    text = name.strip()
    letter = text[0].upper()
    idx = 1
    acc = 0
    while idx < len(text) and text[idx] in "#b":
        acc += 1 if text[idx] == "#" else -1
        idx += 1
    octave = int(text[idx:])
    return (octave + 1) * 12 + _NOTE_BASE[letter] + acc


def hz(note: int | float | str) -> float:
    if isinstance(note, str):
        note = midi(note)
    return 440.0 * 2.0 ** ((float(note) - 69.0) / 12.0)


def rng(seed: int) -> np.random.Generator:
    return np.random.default_rng(seed)


def time_axis(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * RATE)) / RATE


def fade_edges(x: np.ndarray, fade_in: float = 0.004, fade_out: float = 0.02) -> np.ndarray:
    n = x.size
    a = max(2, int(fade_in * RATE))
    b = max(2, int(fade_out * RATE))
    a = min(a, n // 2)
    b = min(b, n // 2)
    if a > 0:
        x[:a] *= np.linspace(0.0, 1.0, a)
    if b > 0:
        x[-b:] *= np.linspace(1.0, 0.0, b)
    return x


# --- instruments -------------------------------------------------------------


def pluck(freq: float, dur: float, vel: float = 0.8, bright: float = 0.55,
          damp: float = 4.0, tail: float = 0.9, seed: int = 1) -> np.ndarray:
    """Quilled/plucked string: bright attack, harmonic staircase, no sustain."""
    length = min(dur + tail, max(dur, 0.08) + tail)
    t = time_axis(length)
    out = np.zeros_like(t)
    env0 = 1.0 - np.exp(-t * 900.0)
    for h in range(1, 13):
        f = freq * h * (1.0 + 0.00035 * h * h)
        if f > 15000.0:
            break
        amp = (1.0 / h ** 0.85) * np.exp(-h / (2.0 + 9.0 * bright))
        decay = damp * (1.0 + 0.55 * h)
        out += amp * np.sin(2.0 * np.pi * f * t) * np.exp(-t * decay)
    out *= env0 * vel
    # plectrum / quill tick
    tick = rng(seed).standard_normal(t.size) * np.exp(-t * 260.0) * 0.10 * bright
    out += tick
    gate = np.ones_like(t)
    gate[t > dur] = np.exp(-(t[t > dur] - dur) * 26.0)
    out *= gate
    return fade_edges(out, 0.001, 0.03)


def bowed(freq: float, dur: float, vel: float = 0.8, attack: float = 0.07,
          release: float = 0.14, vib_hz: float = 5.1, vib_depth: float = 0.0035,
          brightness: float = 0.55, seed: int = 1, ensemble: int = 3) -> np.ndarray:
    """Bowed string section: band-limited sawtooth stack with vibrato and bow noise."""
    t = time_axis(dur + release)
    out = np.zeros_like(t)
    nyquist_guard = 12000.0
    for voice in range(ensemble):
        drift = (voice - (ensemble - 1) * 0.5) * 0.0016
        phase_offset = voice * 0.7
        vib = 1.0 + vib_depth * np.sin(2.0 * np.pi * vib_hz * t + phase_offset)
        vib *= 1.0 + 0.0012 * np.sin(2.0 * np.pi * (vib_hz * 0.31) * t + voice)
        acc = np.zeros_like(t)
        for h in range(1, 26):
            f = freq * h * (1.0 + drift)
            if f > nyquist_guard:
                break
            amp = (1.0 / h ** 1.25) * np.exp(-h / (3.0 + 14.0 * brightness))
            acc += amp * np.sin(2.0 * np.pi * f * t * vib + phase_offset * h)
        out += acc / ensemble
    env = np.ones_like(t)
    a = max(2, int(attack * RATE))
    r = max(2, int(release * RATE))
    a = min(a, t.size)
    env[:a] = np.linspace(0.0, 1.0, a) ** 1.4
    if t.size > r:
        env[-r:] *= np.linspace(1.0, 0.0, r) ** 1.2
    out *= env * vel
    # bow scrape
    noise = rng(seed).standard_normal(t.size)
    noise = np.convolve(noise, np.ones(6) / 6.0, mode="same")
    out += noise * 0.012 * env * vel
    return fade_edges(out, 0.004, 0.03)


def flute_tone(freq: float, dur: float, vel: float = 0.8, breath: float = 0.06,
               seed: int = 1) -> np.ndarray:
    """Wooden flute / recorder: soft fundamental, faint octave, airy breath."""
    release = 0.12
    t = time_axis(dur + release)
    vib = 1.0 + 0.0022 * np.sin(2.0 * np.pi * 5.3 * t)
    base = np.sin(2.0 * np.pi * freq * t * vib)
    base += 0.13 * np.sin(2.0 * np.pi * freq * 2.0 * t * vib)
    base += 0.05 * np.sin(2.0 * np.pi * freq * 3.0 * t * vib)
    base += 0.02 * np.sin(2.0 * np.pi * freq * 4.0 * t * vib)
    env = np.ones_like(t)
    a = int(0.035 * RATE)
    env[:a] = np.linspace(0.0, 1.0, a) ** 1.3
    r = int(release * RATE)
    env[-r:] *= np.linspace(1.0, 0.0, r) ** 1.1
    # gentle swell so long notes breathe
    env *= 0.94 + 0.06 * np.sin(2.0 * np.pi * 0.7 * t)
    n = rng(seed).standard_normal(t.size)
    n = n - np.convolve(n, np.ones(12) / 12.0, mode="same")  # crude high-pass
    return fade_edges((base * env + n * breath * env) * vel, 0.004, 0.03)


def brass(freq: float, dur: float, vel: float = 0.8, seed: int = 1) -> np.ndarray:
    """Soft natural trumpet: widened harmonic stack that blooms after the attack."""
    release = 0.18
    t = time_axis(dur + release)
    bloom = np.clip(t / 0.09, 0.0, 1.0)
    out = np.zeros_like(t)
    for h in range(1, 12):
        f = freq * h
        if f > 11000.0:
            break
        amp = (1.0 / h ** 0.75) * np.exp(-h / 9.0)
        out += amp * np.sin(2.0 * np.pi * f * t) * bloom ** (0.6 + 0.15 * h)
    env = np.ones_like(t)
    env[-int(release * RATE):] *= np.linspace(1.0, 0.0, int(release * RATE)) ** 1.2
    noise = rng(seed).standard_normal(t.size)
    noise = np.convolve(noise, np.ones(9) / 9.0, mode="same")
    return fade_edges((out * env + noise * 0.02 * env) * vel, 0.006, 0.03)


def timpani(freq: float, dur: float, vel: float = 0.9, seed: int = 3) -> np.ndarray:
    """Kettledrum: pitch-dropping membrane plus a low noise thump."""
    t = time_axis(max(dur, 1.6))
    drop = freq * (1.0 + 0.45 * np.exp(-t * 26.0))
    phase = 2.0 * np.pi * np.cumsum(drop) / RATE
    body = np.sin(phase) * np.exp(-t * 2.6)
    body += 0.28 * np.sin(phase * 1.62) * np.exp(-t * 4.2)
    body += 0.12 * np.sin(phase * 2.31) * np.exp(-t * 6.0)
    noise = rng(seed).standard_normal(t.size)
    noise = np.convolve(noise, np.ones(24) / 24.0, mode="same")
    body += noise * np.exp(-t * 16.0) * 0.5
    return fade_edges(body * vel, 0.002, 0.06)


def bell(freq: float, dur: float = 2.4, vel: float = 0.7, seed: int = 5) -> np.ndarray:
    t = time_axis(max(dur, 1.2))
    partials = [(1.0, 1.0, 1.1), (2.0, 0.5, 1.9), (2.76, 0.4, 2.6),
                (5.40, 0.22, 4.1), (8.93, 0.12, 6.4), (13.3, 0.06, 8.0)]
    out = np.zeros_like(t)
    for ratio, amp, decay in partials:
        out += amp * np.sin(2.0 * np.pi * freq * ratio * t) * np.exp(-t * decay)
    strike = rng(seed).standard_normal(t.size) * np.exp(-t * 90.0) * 0.25
    return fade_edges((out + strike) * vel, 0.001, 0.05)


def noise_burst(dur: float, cutoff: float, decay: float, vel: float = 1.0, seed: int = 7,
                smooth: int = 8) -> np.ndarray:
    t = time_axis(dur)
    n = rng(seed).standard_normal(t.size)
    n = np.convolve(n, np.ones(max(1, smooth)) / max(1, smooth), mode="same")
    n *= np.exp(-t * decay)
    return fade_edges(n * vel, 0.0005, 0.02)


# --- effects -----------------------------------------------------------------


def reverb(x: np.ndarray, rt60: float = 1.7, mix: float = 0.3, seed: int = 11,
           damp_hz: int = 5200, predelay: float = 0.02) -> np.ndarray:
    """Convolution reverb against a synthesised decaying-noise impulse response."""
    n_ir = int(rt60 * RATE)
    ir = make_ir(n_ir, rt60, seed, damp_hz, predelay)
    size = x.size + ir.size - 1
    n_fft = 1 << (size - 1).bit_length()
    wet = np.fft.irfft(np.fft.rfft(x, n_fft) * np.fft.rfft(ir, n_fft), n_fft)[: x.size]
    wet /= max(np.max(np.abs(wet)), 1e-9)
    wet *= np.max(np.abs(x)) if np.max(np.abs(x)) > 1e-9 else 1.0
    return (1.0 - mix) * x + mix * wet


def make_ir(n: int, rt60: float, seed: int, damp_hz: int, predelay: float) -> np.ndarray:
    t = np.arange(n) / RATE
    envelope = np.exp(-t * (6.9078 / rt60))
    noise = rng(seed).standard_normal(n) * envelope
    # one-pole-ish low-pass, then a touch of high shelf loss by repeated smoothing
    kernel = max(1, int(RATE / max(damp_hz, 400)))
    noise = np.convolve(noise, np.ones(kernel) / kernel, mode="same")
    pre = int(predelay * RATE)
    if pre > 0:
        noise = np.concatenate([np.zeros(pre), noise[: n - pre]])
    noise[:64] *= np.linspace(0.0, 1.0, 64)
    return noise / max(np.max(np.abs(noise)), 1e-9)


def stereo(left: np.ndarray, right: np.ndarray) -> np.ndarray:
    return np.stack([left, right], axis=1)


def pad_to(x: np.ndarray, n: int) -> np.ndarray:
    if x.size >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - x.size)])


# --- loudness ----------------------------------------------------------------


def rms_db(x: np.ndarray) -> float:
    r = float(np.sqrt(np.mean(np.square(x))))
    return 20.0 * np.log10(max(r, 1e-9))


def normalize(x: np.ndarray, target_rms_db: float = -18.0, peak_ceiling: float = 0.9) -> np.ndarray:
    current = rms_db(x)
    gain = 10.0 ** ((target_rms_db - current) / 20.0)
    out = x * gain
    peak = float(np.max(np.abs(out)))
    if peak > peak_ceiling:
        out *= peak_ceiling / peak
    return out


def soft_limit(x: np.ndarray, ceiling: float = 0.95) -> np.ndarray:
    return np.tanh(x * 1.08) / np.tanh(1.08) * ceiling


# --- io ----------------------------------------------------------------------


def write_wav(path: str, x: np.ndarray, peak_ceiling: float = 0.95) -> None:
    data = np.clip(x, -1.0, 1.0)
    pcm = (data * peak_ceiling * 32767.0).astype("<i2")
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(pcm.tobytes())


def write_ogg(path: str, stereo_audio: np.ndarray, quality: int = 5) -> None:
    """Encode (N, 2) float data to Ogg Vorbis with oggenc (libvorbis)."""
    import tempfile

    data = np.clip(stereo_audio, -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")
    handle = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    temp_path = handle.name
    handle.close()
    try:
        with wave.open(temp_path, "wb") as out:
            out.setnchannels(2)
            out.setsampwidth(2)
            out.setframerate(RATE)
            out.writeframes(pcm.tobytes())
        proc = subprocess.run(
            ["oggenc", "-Q", "-q", str(quality), "-o", path, temp_path],
            capture_output=True,
        )
        if proc.returncode != 0:
            raise RuntimeError(proc.stderr.decode() or "oggenc failed")
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)


def wav_bytes(x: np.ndarray) -> bytes:
    return struct.pack("<" + "h" * x.size, *x.astype("<i2").tolist())
