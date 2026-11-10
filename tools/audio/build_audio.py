"""Build the procedural audio assets in assets/audio from source.

    python tools/audio/build_audio.py            # sfx + ambience
    python tools/audio/build_audio.py --only sfx
    python tools/audio/build_audio.py --only music-synth   # offline music fallback
    python tools/audio/build_audio.py --list

Outputs:
    assets/audio/sfx/*.wav        short mono one-shots for the AudioDirector pool
    assets/audio/ambience/*.ogg   sea bed loop
    assets/audio/music/*.ogg      only with --only music-synth; the shipped beds come
                                  from the ElevenLabs masters via finish_elevenlabs.py

Requires numpy and oggenc (libvorbis). Deterministic: same source -> same bytes
apart from the Vorbis encoder's own bit-exactness.
"""

from __future__ import annotations

import argparse
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import dsp  # noqa: E402
import score  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIO = os.path.join(ROOT, "assets", "audio")


# --- instrument dispatch -----------------------------------------------------


def instrument(name: str, freq: float, dur: float, vel: float, seed: int) -> np.ndarray:
    if name == "lute":
        return dsp.pluck(freq, dur, vel, bright=0.42, damp=3.4, tail=1.1, seed=seed)
    if name == "theorbo":
        return dsp.pluck(freq, dur, vel, bright=0.3, damp=2.2, tail=1.8, seed=seed)
    if name == "harpsichord":
        return dsp.pluck(freq, dur, vel, bright=0.85, damp=2.9, tail=0.45, seed=seed)
    if name == "viol":
        return dsp.bowed(freq, dur, vel, brightness=0.4, attack=0.09, ensemble=3, seed=seed)
    if name == "violin":
        return dsp.bowed(freq, dur, vel, brightness=0.62, attack=0.05,
                         vib_depth=0.0042, ensemble=3, seed=seed)
    if name == "cello":
        return dsp.bowed(freq, dur, vel, brightness=0.34, attack=0.05,
                         release=0.2, ensemble=2, seed=seed)
    if name == "recorder":
        return dsp.flute_tone(freq, dur, vel, breath=0.07, seed=seed)
    if name == "flute":
        return dsp.flute_tone(freq, dur, vel, breath=0.1, seed=seed)
    if name == "fife":
        return dsp.fife(freq, dur, vel, seed=seed)
    if name == "brass":
        return dsp.brass(freq, dur, vel, seed=seed)
    if name == "timpani":
        return dsp.timpani(freq, dur, vel, seed=seed)
    if name == "tabor":
        return dsp.tabor(freq, dur, vel, seed=seed)
    if name == "tambourine":
        return dsp.tambourine(freq, dur, vel, seed=seed)
    if name == "castanet":
        return dsp.castanet(freq, dur, vel, seed=seed)
    if name == "bell":
        return dsp.bell(freq, max(dur, 1.2), vel, seed=seed)
    raise ValueError("unknown instrument %r" % name)


# --- rendering ---------------------------------------------------------------


def render(piece: score.Piece) -> np.ndarray:
    beat_sec = 60.0 / piece.bpm
    loop_sec = piece.bars * piece.beats_per_bar * beat_sec
    loop_n = int(round(loop_sec * dsp.RATE))
    tail_n = int(3.0 * dsp.RATE)
    total = loop_n + (tail_n if piece.loop else 0)

    dry = np.zeros((total, 2), dtype=np.float64)
    send = np.zeros((total, 2), dtype=np.float64)
    rng = dsp.rng(hash(piece.name) & 0xFFFF)

    for ev in piece.events:
        # humanise: period ensembles are never machine-tight
        jitter = rng.uniform(-0.006, 0.006)
        cents = rng.uniform(-5.0, 5.0)
        vel = float(np.clip(ev.vel + rng.uniform(-0.045, 0.045), 0.05, 1.0))
        freq = dsp.hz(ev.note) * 2.0 ** (cents / 1200.0)
        sig = instrument(ev.instr, freq, max(ev.dur, 0.05), vel, int(rng.integers(1, 1 << 20)))
        start = int((ev.start + jitter) * dsp.RATE)
        if start < 0:
            sig = sig[-start:]
            start = 0
        if start >= total:
            continue
        end = min(total, start + sig.size)
        if end <= start:
            continue
        sig = sig[: end - start]
        angle = (ev.pan + 1.0) * math.pi / 4.0
        gains = np.array([math.cos(angle), math.sin(angle)])
        dry[start:end] += np.outer(sig, gains) * (1.0 - 0.35 * ev.rev)
        send[start:end] += np.outer(sig, gains) * ev.rev

    wet = np.stack([dsp.reverb(send[:, 0], piece.rt60, 1.0, seed=21),
                    dsp.reverb(send[:, 1], piece.rt60, 1.0, seed=22)], axis=1)
    mix = dry + wet * 0.9

    if piece.loop:
        mix[:tail_n] += mix[loop_n: loop_n + tail_n]
        mix = mix[:loop_n]
    return mix


def finish(mix: np.ndarray, target_rms_db: float, ceiling: float = 0.85) -> np.ndarray:
    """Loudness for playback under SFX; no gain-adding limiter, so no pumping."""
    return dsp.normalize(mix, target_rms_db, peak_ceiling=ceiling)


# --- sound effects -----------------------------------------------------------


def _hp(x: np.ndarray, smooth: int = 10) -> np.ndarray:
    return x - np.convolve(x, np.ones(smooth) / smooth, mode="same")


def _lp(x: np.ndarray, smooth: int = 10) -> np.ndarray:
    return np.convolve(x, np.ones(smooth) / smooth, mode="same")


def sfx_ui_click(seed: int = 11) -> np.ndarray:
    t = dsp.time_axis(0.09)
    body = np.sin(2 * np.pi * 1180 * t) * np.exp(-t * 90.0)
    body += 0.5 * np.sin(2 * np.pi * 1730 * t) * np.exp(-t * 120.0)
    tick = _hp(dsp.rng(seed).standard_normal(t.size)) * np.exp(-t * 300.0) * 0.55
    return dsp.fade_edges((body * 0.55 + tick) * 0.7, 0.001, 0.02)


def sfx_panel_open(seed: int = 12) -> np.ndarray:
    t = dsp.time_axis(0.34)
    n = _lp(dsp.rng(seed).standard_normal(t.size), 26)
    swell = np.sin(np.pi * np.clip(t / 0.3, 0, 1)) ** 2
    tone = np.sin(2 * np.pi * (300 + 240 * t / 0.34) * t) * 0.1
    return dsp.fade_edges((n * swell * 2.2 + tone * swell) * 0.5, 0.01, 0.05)


def sfx_panel_close(seed: int = 13) -> np.ndarray:
    t = dsp.time_axis(0.26)
    n = _lp(dsp.rng(seed).standard_normal(t.size), 20)
    swell = np.exp(-t * 9.0)
    tone = np.sin(2 * np.pi * (520 - 260 * t / 0.26) * t) * 0.12
    return dsp.fade_edges((n * swell * 2.4 + tone * swell) * 0.45, 0.004, 0.04)


def sfx_province_select(seed: int = 14) -> np.ndarray:
    t = dsp.time_axis(0.5)
    body = np.sin(2 * np.pi * 660 * t) * np.exp(-t * 12.0)
    body += 0.4 * np.sin(2 * np.pi * 990 * t) * np.exp(-t * 20.0)
    body += 0.2 * np.sin(2 * np.pi * 1320 * t) * np.exp(-t * 26.0)
    strike = _hp(dsp.rng(seed).standard_normal(t.size)) * np.exp(-t * 220.0) * 0.2
    return dsp.fade_edges((body + strike) * 0.6, 0.001, 0.06)


def sfx_fleet_select(seed: int = 15) -> np.ndarray:
    return dsp.bell(880.0, 1.1, 0.55, seed=seed) * 0.8


def sfx_fleet_move(seed: int = 16) -> np.ndarray:
    t = dsp.time_axis(0.85)
    n = _lp(dsp.rng(seed).standard_normal(t.size), 12)
    swell = np.sin(np.pi * np.clip(t / 0.8, 0, 1)) ** 1.6
    creak = np.sin(2 * np.pi * (150 + 60 * np.sin(2 * np.pi * 3.2 * t)) * t) * 0.16
    creak *= np.exp(-np.maximum(t - 0.45, 0) * 9.0)
    return dsp.fade_edges((n * swell * 1.8 + creak) * 0.55, 0.02, 0.08)


def sfx_order_denied(seed: int = 17) -> np.ndarray:
    t = dsp.time_axis(0.22)
    body = np.sin(2 * np.pi * (128 - 40 * t) * t) * np.exp(-t * 22.0)
    knock = _lp(dsp.rng(seed).standard_normal(t.size), 6) * np.exp(-t * 60.0) * 0.35
    return dsp.fade_edges((body + knock) * 0.7, 0.002, 0.05)


def sfx_turn_bell(seed: int = 18) -> np.ndarray:
    first = dsp.bell(622.0, 2.6, 0.6, seed=seed)
    second = dsp.bell(830.0, 2.6, 0.42, seed=seed + 1)
    out = np.zeros(int(3.0 * dsp.RATE))
    out[: first.size] += first
    shift = int(0.62 * dsp.RATE)
    out[shift: shift + second.size] += second[: out.size - shift]
    return dsp.fade_edges(out * 0.75, 0.001, 0.2)


def sfx_coin(seed: int = 19) -> np.ndarray:
    a = dsp.pluck(2360.0, 0.14, 0.42, bright=0.95, damp=13.0, tail=0.3, seed=seed)
    b = dsp.pluck(3140.0, 0.12, 0.34, bright=0.95, damp=16.0, tail=0.3, seed=seed + 1)
    out = np.zeros(int(0.6 * dsp.RATE))
    out[: a.size] += a
    shift = int(0.055 * dsp.RATE)
    out[shift: shift + b.size] += b[: out.size - shift]
    return dsp.fade_edges(out * 0.6, 0.001, 0.05)


def sfx_coast_charted(seed: int = 20) -> np.ndarray:
    a = dsp.pluck(880.0, 0.5, 0.5, bright=0.5, damp=6.0, seed=seed)
    b = dsp.pluck(1174.7, 0.9, 0.45, bright=0.5, damp=4.2, seed=seed + 1)
    out = np.zeros(int(1.4 * dsp.RATE))
    out[: a.size] += a
    shift = int(0.16 * dsp.RATE)
    out[shift: shift + b.size] += b[: out.size - shift]
    return dsp.fade_edges(out * 0.55, 0.001, 0.1)


def sfx_broadside(seed: int = 21) -> np.ndarray:
    """A rolling broadside: three guns, then a long low rumble."""
    total = int(3.2 * dsp.RATE)
    out = np.zeros(total)
    rng = dsp.rng(seed)
    for shot, delay in enumerate((0.0, 0.13, 0.31)):
        t = dsp.time_axis(2.6)
        drop = 92.0 * np.exp(-t * 5.5) + 34.0
        phase = 2 * np.pi * np.cumsum(drop) / dsp.RATE
        boom = np.sin(phase) * np.exp(-t * 2.9)
        boom += 0.4 * np.sin(phase * 1.7) * np.exp(-t * 4.6)
        crack = _hp(rng.standard_normal(t.size), 4) * np.exp(-t * 42.0) * 0.55
        rumble = _lp(rng.standard_normal(t.size), 90) * np.exp(-t * 1.5) * 1.9
        gun = (boom * 0.9 + crack + rumble) * (0.85 - 0.12 * shot)
        start = int(delay * dsp.RATE)
        end = min(total, start + gun.size)
        out[start:end] += gun[: end - start]
    return dsp.fade_edges(out * 0.9, 0.002, 0.3)


def sfx_hull_hit(seed: int = 22) -> np.ndarray:
    t = dsp.time_axis(0.7)
    thump = np.sin(2 * np.pi * (70 - 26 * t) * t) * np.exp(-t * 14.0)
    splinter = _hp(dsp.rng(seed).standard_normal(t.size), 5) * np.exp(-t * 26.0) * 0.5
    body = _lp(dsp.rng(seed + 1).standard_normal(t.size), 16) * np.exp(-t * 8.0) * 0.6
    return dsp.fade_edges((thump + splinter + body) * 0.7, 0.001, 0.1)


def sfx_civilian_select(seed: int = 24) -> np.ndarray:
    """Surveying rod set down: a wooden tap with a small brass clink."""
    t = dsp.time_axis(0.42)
    knock = np.sin(2 * np.pi * 320 * t) * np.exp(-t * 34.0)
    knock += 0.5 * np.sin(2 * np.pi * 480 * t) * np.exp(-t * 48.0)
    clink = np.sin(2 * np.pi * 1480 * t) * np.exp(-t * 26.0) * 0.18
    tick = _hp(dsp.rng(seed).standard_normal(t.size)) * np.exp(-t * 140.0) * 0.25
    return dsp.fade_edges((knock + clink + tick) * 0.6, 0.001, 0.06)


def sfx_civilian_move(seed: int = 25) -> np.ndarray:
    """Two bootfalls on dry earth with a faint tool jingle."""
    total = int(0.62 * dsp.RATE)
    out = np.zeros(total)
    rng = dsp.rng(seed)
    for step, delay in enumerate((0.0, 0.17)):
        t = dsp.time_axis(0.22)
        thud = np.sin(2 * np.pi * (86 - 24 * t) * t) * np.exp(-t * 26.0)
        grit = _lp(rng.standard_normal(t.size), 7) * np.exp(-t * 40.0) * 0.55
        foot = (thud + grit) * (0.9 - 0.15 * step)
        start = int(delay * dsp.RATE)
        out[start: start + foot.size] += foot
    jingle = dsp.pluck(1760.0, 0.1, 0.16, bright=0.9, damp=18.0, tail=0.18, seed=seed + 1)
    out[int(0.21 * dsp.RATE): int(0.21 * dsp.RATE) + jingle.size] += jingle[: total - int(0.21 * dsp.RATE)]
    return dsp.fade_edges(out * 0.7, 0.002, 0.08)


def sfx_fleet_sunk(seed: int = 23) -> np.ndarray:
    t = dsp.time_axis(2.4)
    groan = np.sin(2 * np.pi * (110 - 55 * np.clip(t / 2.0, 0, 1)) * t) * np.exp(-t * 1.6)
    splash = _lp(dsp.rng(seed).standard_normal(t.size), 30) * np.exp(-t * 2.4) * 1.6
    out = groan * 0.4 + splash
    return dsp.fade_edges(out * 0.7, 0.02, 0.3)


def sfx_cargo_seized(seed: int = 26) -> np.ndarray:
    """Prize hauled into the hold: a crate set down, then coin counted out."""
    total = int(0.85 * dsp.RATE)
    out = np.zeros(total)
    t = dsp.time_axis(0.4)
    thud = np.sin(2 * np.pi * (104 - 34 * np.clip(t / 0.22, 0, 1)) * t) * np.exp(-t * 18.0)
    scrape = _lp(dsp.rng(seed).standard_normal(t.size), 14) * np.exp(-t * 9.0) * 0.7
    out[: t.size] += (thud * 0.8 + scrape) * 0.9
    for index, delay in enumerate((0.11, 0.19, 0.28)):
        coin = dsp.pluck(
            2080.0 + 260.0 * index, 0.1, 0.3, bright=0.95, damp=17.0, tail=0.22, seed=seed + 1 + index
        )
        start = int(delay * dsp.RATE)
        end = min(total, start + coin.size)
        out[start:end] += coin[: end - start]
    return dsp.fade_edges(out * 0.75, 0.002, 0.08)


def sfx_raid_alarm(seed: int = 27) -> np.ndarray:
    """A warning gun across the water: one distant, dull thump and its echo."""
    total = int(1.9 * dsp.RATE)
    out = np.zeros(total)
    rng = dsp.rng(seed)
    for shot, delay, gain in ((0, 0.0, 1.0), (1, 0.62, 0.45)):
        t = dsp.time_axis(1.3)
        drop = 74.0 * np.exp(-t * 4.2) + 28.0
        phase = 2 * np.pi * np.cumsum(drop) / dsp.RATE
        boom = np.sin(phase) * np.exp(-t * 3.4)
        rumble = _lp(rng.standard_normal(t.size), 120) * np.exp(-t * 2.2) * 1.5
        shot_body = (boom * 0.8 + rumble) * gain
        # Distance: roll the highs off so it reads from the far side of the bay.
        shot_body = _lp(shot_body, 4)
        start = int(delay * dsp.RATE)
        end = min(total, start + shot_body.size)
        out[start:end] += shot_body[: end - start]
    return dsp.fade_edges(out * 0.9, 0.004, 0.25)


SFX = {
    "ui_click": sfx_ui_click,
    "panel_open": sfx_panel_open,
    "panel_close": sfx_panel_close,
    "province_select": sfx_province_select,
    "fleet_select": sfx_fleet_select,
    "fleet_move": sfx_fleet_move,
    "order_denied": sfx_order_denied,
    "turn_bell": sfx_turn_bell,
    "coin": sfx_coin,
    "coast_charted": sfx_coast_charted,
    "broadside": sfx_broadside,
    "hull_hit": sfx_hull_hit,
    "fleet_sunk": sfx_fleet_sunk,
    "civilian_select": sfx_civilian_select,
    "civilian_move": sfx_civilian_move,
    "cargo_seized": sfx_cargo_seized,
    "raid_alarm": sfx_raid_alarm,
}


# --- ambience ----------------------------------------------------------------


def sea_ambience(seconds: float = 24.0, seed: int = 41) -> np.ndarray:
    """Stereo swell bed: filtered noise waves, rigging creak, one distant gull."""
    n = int(seconds * dsp.RATE)
    t = np.arange(n) / dsp.RATE
    rng = dsp.rng(seed)
    left = np.zeros(n)
    right = np.zeros(n)
    for channel, buf in enumerate((left, right)):
        raw = rng.standard_normal(n)
        swell = 0.55 + 0.45 * np.sin(2 * np.pi * t / seconds * 3.0 + channel * 0.8)
        swell *= 0.7 + 0.3 * np.sin(2 * np.pi * t / seconds * 5.0 + 1.1 + channel)
        deep = _lp(raw, 220) * swell
        foam = _lp(_hp(raw, 40), 5) * (0.35 + 0.65 * np.abs(np.sin(2 * np.pi * t / seconds * 3.0)))
        buf[:] = deep * 1.7 + foam * 0.22
    # rigging creak, twice per loop, wrapped so the loop stays seamless
    for offset in (3.4, 14.2):
        start = int(offset * dsp.RATE)
        dur = int(1.1 * dsp.RATE)
        tc = np.arange(dur) / dsp.RATE
        creak = np.sin(2 * np.pi * (128 + 26 * np.sin(2 * np.pi * 2.4 * tc)) * tc)
        creak *= np.sin(np.pi * np.clip(tc / 1.1, 0, 1)) ** 2 * 0.05
        for buf, gain in ((left, 1.0), (right, 0.65)):
            end = start + dur
            if end <= n:
                buf[start:end] += creak * gain
            else:
                buf[start:] += creak[: n - start] * gain
    # a gull, far off, panned right
    gull_start = int(9.1 * dsp.RATE)
    gull = np.zeros(int(1.6 * dsp.RATE))
    for k, (offset, length, base) in enumerate(((0.0, 0.26, 1450.0), (0.34, 0.3, 1280.0))):
        tt = np.arange(int(length * dsp.RATE)) / dsp.RATE
        chirp = np.sin(2 * np.pi * (base - 300 * tt / length) * tt)
        chirp *= np.sin(np.pi * np.clip(tt / length, 0, 1)) ** 1.5 * 0.06
        s = int(offset * dsp.RATE)
        gull[s: s + chirp.size] += chirp
    end = min(n, gull_start + gull.size)
    right[gull_start:end] += gull[: end - gull_start]
    left[gull_start:end] += gull[: end - gull_start] * 0.35
    stereo = np.stack([left, right], axis=1)
    return dsp.normalize(stereo, -26.0, peak_ceiling=0.8)


# --- main --------------------------------------------------------------------


PIECES = [
    score.age_of_discovery,
    score.spanish_main,
    score.gilded_minuet,
    score.broadsides,
    score.victory_fanfare,
    score.defeat_knell,
]


def build_music(out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for factory in PIECES:
        piece = factory()
        audio = finish(render(piece), piece.target_rms_db)
        path = os.path.join(out_dir, piece.name + ".ogg")
        dsp.write_ogg(path, audio, quality=5)
        print("  %-28s %6.1fs  %s" % (piece.name, audio.shape[0] / dsp.RATE,
                                      _size(path)))


def build_sfx(out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    for name, factory in SFX.items():
        audio = dsp.normalize(factory(), -13.0, peak_ceiling=0.92)
        path = os.path.join(out_dir, name + ".wav")
        dsp.write_wav(path, audio, peak_ceiling=0.92)
        print("  %-28s %6.2fs  %s" % (name, audio.size / dsp.RATE, _size(path)))


def build_ambience(out_dir: str) -> None:
    os.makedirs(out_dir, exist_ok=True)
    audio = sea_ambience()
    path = os.path.join(out_dir, "ambience_sea.ogg")
    dsp.write_ogg(path, audio, quality=4)
    print("  %-28s %6.1fs  %s" % ("ambience_sea", audio.shape[0] / dsp.RATE, _size(path)))


def _size(path: str) -> str:
    kb = os.path.getsize(path) / 1024.0
    return "%6.1f KB" % kb


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--only", choices=("sfx", "ambience", "music-synth"),
                        help="build one group (music-synth overwrites the shipped beds)")
    parser.add_argument("--list", action="store_true", help="list asset names")
    args = parser.parse_args()

    if args.list:
        for factory in PIECES:
            print(factory().name + "  (music-synth fallback)")
        for name in SFX:
            print(name)
        print("ambience_sea")
        return 0

    groups = [args.only] if args.only else ["sfx", "ambience"]
    for group in groups:
        print("%s:" % group)
        if group == "music-synth":
            build_music(os.path.join(AUDIO, "music"))
        elif group == "sfx":
            build_sfx(os.path.join(AUDIO, "sfx"))
        else:
            build_ambience(os.path.join(AUDIO, "ambience"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
