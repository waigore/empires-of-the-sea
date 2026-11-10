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
    rms = float(np.sqrt(np.mean(np.square(x))))
    out = x * (10.0 ** ((target_db - 20.0 * np.log10(max(rms, 1e-9))) / 20.0))
    peak = float(np.max(np.abs(out)))
    if peak > PEAK_CEILING:
        out *= PEAK_CEILING / peak
    return out


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
        write_ogg(path, audio)
        print("  %-28s %6.1fs  %6.1f KB  peak %.2f" % (
            track["id"], audio.shape[0] / RATE, os.path.getsize(path) / 1024.0,
            float(np.max(np.abs(audio)))))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
