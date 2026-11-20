"""Finish the ElevenLabs music masters into the shipped Ogg Vorbis beds.

    python tools/audio/finish_elevenlabs.py

The masters live in ``tools/audio/masters`` (ignored by Godot) and are listed in
``tools/audio/elevenlabs_music.json`` with the exact generation prompt and song id.
This script trims encoder silence, folds the tail into the head for a seamless
loop, normalises to the mix target and encodes the ``assets/audio/music`` files.

Needs ``ffmpeg`` (decode) and ``oggenc`` (encode). Deterministic per master.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import tempfile
import wave

import numpy as np

RATE = 44100
SILENCE_DB = -60.0
PEAK_CEILING = 0.9
## Vorbis quality per bed. A three-minute bed at q6 costs ~4.5 MB; the long theme
## beds encode at q4 (~112 kbps, about 2.8 MB) and stay pleasant under play.
DEFAULT_QUALITY = 6
## Headroom of the soft knee: 1.6 keeps the top 3 dB gentle rather than a wall.
SOFT_KNEE = 1.6
## Level a bed may lose to the ceiling before the knee takes over.
SOFT_KNEE_MIN_LOSS_DB = 1.0

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def decode(path: str) -> np.ndarray:
    raw = subprocess.check_output(
        ["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2", "-ar", str(RATE), "-"]
    )
    return np.frombuffer(raw, dtype="<f4").reshape(-1, 2).astype(np.float64)


def trim(x: np.ndarray, preroll: float = 0.05, tail: float = 0.08) -> np.ndarray:
    """Drop leading/trailing near-silence, keeping a short musical margin."""
    loud = np.nonzero(np.max(np.abs(x), axis=1) > 10.0 ** (SILENCE_DB / 20.0))[0]
    if loud.size == 0:
        return x
    start = max(0, int(loud[0] - preroll * RATE))
    end = min(x.shape[0], int(loud[-1] + tail * RATE))
    return x[start:end]


def loop_crossfade(x: np.ndarray, seconds: float) -> np.ndarray:
    """Fold the tail into the head so the end flows into the start without a gap."""
    fade = min(int(seconds * RATE), x.shape[0] // 3)
    if fade <= 0:
        return x
    m = x.shape[0] - fade
    w = np.linspace(0.0, 1.0, fade, dtype=np.float64)[:, None]
    head = x[:fade] * np.sqrt(w) + x[m:m + fade] * np.sqrt(1.0 - w)
    return np.concatenate([head, x[fade:m]])


def normalize(x: np.ndarray, target_db: float) -> np.ndarray:
    """Land on the mix RMS, then shape the crest instead of dropping the level.

    A bed with dense peaks (a march's timpani) used to hit the ceiling and be
    scaled down with it — five dB of applause-quiet next to the rest. Peaks over
    the ceiling now pass a soft-knee tanh, and the result is put back on the mix
    target, so every bed reads the same loudness.
    """
    out = _scale_to(x, target_db)
    peak = float(np.max(np.abs(out)))
    if peak > PEAK_CEILING:
        # A peak a few tenths over the ceiling is a hair to shave; shaving keeps
        # the take untouched. Only a real crest problem (more than a dB of level
        # at stake) earns the soft knee.
        loss_db = 20.0 * np.log10(peak / PEAK_CEILING)
        if loss_db <= SOFT_KNEE_MIN_LOSS_DB:
            out *= PEAK_CEILING / peak
            return out
        out = np.tanh(out / peak * SOFT_KNEE) * (PEAK_CEILING / np.tanh(SOFT_KNEE))
        out = _scale_to(out, target_db)
        out = np.clip(out, -PEAK_CEILING, PEAK_CEILING)
    return out


def _scale_to(x: np.ndarray, target_db: float) -> np.ndarray:
    rms = float(np.sqrt(np.mean(np.square(x))))
    return x * (10.0 ** ((target_db - 20.0 * np.log10(max(rms, 1e-9))) / 20.0))


def write_ogg(path: str, x: np.ndarray, quality: int = 6) -> None:
    pcm = (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2")
    handle = tempfile.NamedTemporaryFile(suffix=".wav", delete=False)
    temp = handle.name
    handle.close()
    try:
        with wave.open(temp, "wb") as out:
            out.setnchannels(2)
            out.setsampwidth(2)
            out.setframerate(RATE)
            out.writeframes(pcm.tobytes())
        proc = subprocess.run(["oggenc", "-Q", "-q", str(quality), "-o", path, temp],
                              capture_output=True)
        if proc.returncode != 0:
            raise RuntimeError(proc.stderr.decode() or "oggenc failed")
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default=os.path.join(ROOT, "tools", "audio",
                                                          "elevenlabs_music.json"))
    parser.add_argument("--out", default=os.path.join(ROOT, "assets", "audio", "music"))
    args = parser.parse_args()

    manifest_path = os.path.abspath(args.manifest)
    base = os.path.dirname(manifest_path)
    manifest = json.load(open(manifest_path))
    os.makedirs(args.out, exist_ok=True)
    failures = 0
    for track in manifest["tracks"]:
        master = os.path.join(base, track["master"])
        if not os.path.exists(master):
            print("  %-28s missing master %s" % (track["id"], master))
            failures += 1
            continue
        audio = trim(decode(master))
        if track.get("loop", True):
            audio = loop_crossfade(audio, float(track.get("crossfade_seconds", 1.5)))
        audio = normalize(audio, float(track.get("target_rms_db", -17.5)))
        path = os.path.join(args.out, track["file"])
        write_ogg(path, audio, int(track.get("quality", DEFAULT_QUALITY)))
        print("  %-28s %6.1fs  %6.1f KB  peak %.2f" % (
            track["id"], audio.shape[0] / RATE, os.path.getsize(path) / 1024.0,
            float(np.max(np.abs(audio)))))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
