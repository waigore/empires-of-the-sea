"""Score definitions for Empires of the Sea — hand-written period material.

Four beds (Renaissance air, Baroque allegro, galant minuet, battle toccata),
two stingers and a sea ambience. Melodies are written by hand; accompaniment
(chord voicing, continuo figuration, divisions on repeats) is derived from the
chord progression so the parts stay in key and move by the smallest step.

Form for each bed is A (8 bars) – B (8 bars) – A' (8 bars, ornamented repeat).
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

import dsp

QUALITIES = {
    "maj": [0, 4, 7],
    "min": [0, 3, 7],
    "dim": [0, 3, 6],
    "dom7": [0, 4, 7, 10],
    "sus4": [0, 5, 7],
}

PITCH_CLASS = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6,
               "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11,
               "Bb": 10, "Eb": 3, "Ab": 8, "Db": 1, "Gb": 6}


@dataclass
class Event:
    start: float          # seconds
    dur: float            # seconds
    note: int             # midi
    instr: str
    vel: float = 0.75
    pan: float = 0.0
    rev: float = 0.28


@dataclass
class Piece:
    name: str
    bpm: float
    beats_per_bar: int = 4
    bars: int = 24
    events: list[Event] = field(default_factory=list)
    wet: float = 0.34
    rt60: float = 2.0
    loop: bool = True
    target_rms_db: float = -17.5

    def beat(self, bar: int, beat: float) -> float:
        return (bar * self.beats_per_bar + beat) * 60.0 / self.bpm

    def add(self, bar: float, beat: float, dur: float, note, instr: str,
            vel: float = 0.75, pan: float = 0.0, rev: float = 0.28) -> None:
        start = self.beat(int(bar), (bar - int(bar)) * self.beats_per_bar + beat)
        self.events.append(Event(start, dur * 60.0 / self.bpm, dsp.midi(note),
                                 instr, vel, pan, rev))


# --- harmony helpers ---------------------------------------------------------


def pitch_class(name: str) -> int:
    return PITCH_CLASS[name[:2] if name[1:2] in ("b", "#") else name[:1]]


def voicing(root: str, quality: str, lo: int = 55, hi: int = 74,
            prev: list[int] | None = None, size: int | None = None) -> list[int]:
    """Nearest-position chord voicing inside [lo, hi], minimal motion from prev."""
    import itertools

    ivs = QUALITIES[quality]
    classes = sorted({(pitch_class(root) + i) % 12 for i in ivs})
    pool = [m for m in range(lo, hi + 1) if m % 12 in classes]
    count = size or len(classes)
    if len(pool) < count:
        return pool
    best: list[int] = []
    best_cost = 1e9
    for combo in itertools.combinations(pool, count):
        if len({m % 12 for m in combo}) < min(count, len(classes)):
            continue
        cost = 0.0
        if prev:
            cost = sum(min(abs(m - p) for p in prev) for m in combo)
            cost += 1.5 * abs(sum(combo) / len(combo) - sum(prev) / len(prev))
        cost += 0.35 * abs(sum(combo) / len(combo) - (lo + hi) * 0.5)
        if cost < best_cost:
            best_cost, best = cost, list(combo)
    return best or pool[:count]


def bass_note(root: str, lo: int = 36, hi: int = 50, prev: int | None = None) -> int:
    pc = pitch_class(root)
    pool = [m for m in range(lo, hi + 1) if m % 12 == pc]
    if not pool:
        return 40
    if prev is None:
        return pool[len(pool) // 2]
    return min(pool, key=lambda m: abs(m - prev))


# --- shared accompaniment patterns ------------------------------------------


def add_consort(piece: Piece, bar0: int, chords: list[tuple[str, str]],
                variation: bool, prev_state: dict) -> None:
    """Renaissance consort: sustained inner viols, lute chords, theorbo bass."""
    lo, hi = (52, 67)
    for i, (root, quality) in enumerate(chords):
        bar = bar0 + i
        inner = voicing(root, quality, lo, hi, prev_state.get("inner"))
        prev_state["inner"] = inner
        for k, note in enumerate(inner):
            pan = -0.18 + 0.36 * (k / max(1, len(inner) - 1))
            piece.add(bar, 0.0, 2.0, _name(note), "viol", 0.42, pan, 0.34)
            piece.add(bar, 2.0, 2.0, _name(note), "viol", 0.36, pan, 0.34)
        low = bass_note(root, 36, 48, prev_state.get("bass"))
        prev_state["bass"] = low
        piece.add(bar, 0.0, 4.0, _name(low), "theorbo", 0.62, 0.0, 0.2)
        if variation:
            # lute divisions: broken chord in eighths
            shape = [0, 2, 1, 2, 3, 2, 1, 2]
            tones = [inner[0] + 12, inner[1] + 12, inner[2] + 12]
            for step in range(8):
                note = tones[shape[step] % len(tones)]
                piece.add(bar, step * 0.5, 0.45, _name(note), "lute", 0.3, 0.16, 0.4)
        else:
            for beat in (0.0, 2.0):
                for note in inner:
                    piece.add(bar, beat, 1.7, _name(note + 12), "lute", 0.22, 0.16, 0.42)


def add_continuo(piece: Piece, bar0: int, chords: list[tuple[str, str]],
                 variation: bool, prev_state: dict) -> None:
    """Baroque continuo: harpsichord blocks, cello bass, inner violin.";
    """
    for i, (root, quality) in enumerate(chords):
        bar = bar0 + i
        upper = voicing(root, quality, 59, 76, prev_state.get("upper"))
        prev_state["upper"] = upper
        for k, note in enumerate(upper):
            pan = -0.2 + 0.4 * (k / max(1, len(upper) - 1))
            piece.add(bar, 0.0, 1.9, _name(note), "harpsichord", 0.3, pan - 0.1, 0.3)
            piece.add(bar, 2.0, 1.8, _name(note), "harpsichord", 0.24, pan - 0.1, 0.3)
        low = bass_note(root, 38, 52, prev_state.get("bass"))
        prev_state["bass"] = low
        if variation:
            for step in range(4):  # walking eighths
                note = low if step % 2 == 0 else (low + 12 if step % 4 == 1 else low + 7)
                piece.add(bar, step * 0.5 * 2, 0.9, _name(note), "cello", 0.5, -0.05, 0.22)
            for step in range(4):
                for note in upper[:2]:
                    piece.add(bar, step * 1.0, 0.5, _name(note + 12), "harpsichord", 0.16, 0.24, 0.35)
        else:
            piece.add(bar, 0.0, 2.0, _name(low), "cello", 0.55, -0.05, 0.22)
            piece.add(bar, 2.0, 2.0, _name(low + 7 if quality == "maj" else low), "cello", 0.45, -0.05, 0.22)
        # sustained inner string keeps the texture warm under the solo line
        piece.add(bar, 0.0, 4.0, _name(upper[0] if not variation else upper[1]), "viol", 0.22, -0.3, 0.4)


def add_galant(piece: Piece, bar0: int, chords: list[tuple[str, str]],
               variation: bool, prev_state: dict, beats_per_bar: int = 3) -> None:
    """Classical minuet: strings pad, broken-chord harpsichord, light bass."""
    for i, (root, quality) in enumerate(chords):
        bar = bar0 + i
        upper = voicing(root, quality, 55, 72, prev_state.get("upper"))
        prev_state["upper"] = upper
        piece.add(bar, 0.0, float(beats_per_bar), _name(upper[0]), "viol", 0.3, -0.32, 0.36)
        piece.add(bar, 0.0, float(beats_per_bar), _name(upper[1]), "viol", 0.26, -0.1, 0.36)
        low = bass_note(root, 40, 52, prev_state.get("bass"))
        prev_state["bass"] = low
        piece.add(bar, 0.0, 1.6, _name(low), "cello", 0.5, -0.06, 0.2)
        if beats_per_bar >= 3:
            piece.add(bar, 2.0, 1.0, _name(low + 7), "cello", 0.34, -0.06, 0.2)
        pattern = ([0, 1, 2, 1, 0, 1] if variation else [0, 2, 1]) * 4
        step_len = beats_per_bar / (6 if variation else 3)
        for step in range(6 if variation else 3):
            note = upper[pattern[step] % len(upper)] + 12
            piece.add(bar, step * step_len, step_len * 0.92, _name(note),
                      "harpsichord", 0.19, 0.26, 0.34)


def _name(note: int) -> str:
    names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    return "%s%d" % (names[note % 12], note // 12 - 1)


def add_melody(piece: Piece, bar0: int, notes: list[tuple], instr: str,
               vel: float = 0.82, pan: float = 0.18, transpose: int = 0) -> None:
    for bar, beat, dur, note in notes:
        piece.add(bar0 + bar, beat, dur, _name(dsp.midi(note) + transpose), instr, vel, pan, 0.3)


# --- pieces ------------------------------------------------------------------

# I. 1500 — Renaissance air in G dorian, consort of viols and lute.
AIR_CHORDS_A = [("G", "min"), ("F", "maj"), ("C", "maj"), ("D", "min"),
                ("G", "min"), ("F", "maj"), ("C", "maj"), ("D", "min")]
AIR_CHORDS_B = [("Bb", "maj"), ("F", "maj"), ("C", "maj"), ("G", "min"),
                ("Bb", "maj"), ("F", "maj"), ("D", "min"), ("G", "min")]

AIR_MELODY_A = [
    (0, 0.0, 1.0, "D5"), (0, 1.0, 0.5, "E5"), (0, 1.5, 0.5, "F5"), (0, 2.0, 2.0, "G5"),
    (1, 0.0, 1.0, "F5"), (1, 1.0, 1.0, "E5"), (1, 2.0, 2.0, "D5"),
    (2, 0.0, 1.5, "E5"), (2, 1.5, 0.5, "D5"), (2, 2.0, 1.0, "C5"), (2, 3.0, 1.0, "E5"),
    (3, 0.0, 2.0, "D5"), (3, 2.0, 1.0, "C5"), (3, 3.0, 1.0, "A4"),
    (4, 0.0, 1.0, "D5"), (4, 1.0, 0.5, "E5"), (4, 1.5, 0.5, "F5"), (4, 2.0, 2.0, "G5"),
    (5, 0.0, 1.0, "A5"), (5, 1.0, 1.0, "G5"), (5, 2.0, 2.0, "F5"),
    (6, 0.0, 1.5, "G5"), (6, 1.5, 0.5, "F5"), (6, 2.0, 1.0, "E5"), (6, 3.0, 1.0, "D5"),
    (7, 0.0, 2.0, "A4"), (7, 2.0, 2.0, "D5"),
]

AIR_MELODY_B = [
    (0, 0.0, 1.0, "F5"), (0, 1.0, 0.5, "G5"), (0, 1.5, 0.5, "A5"), (0, 2.0, 2.0, "Bb5"),
    (1, 0.0, 1.0, "A5"), (1, 1.0, 1.0, "G5"), (1, 2.0, 2.0, "F5"),
    (2, 0.0, 1.5, "G5"), (2, 1.5, 0.5, "E5"), (2, 2.0, 1.0, "C5"), (2, 3.0, 1.0, "E5"),
    (3, 0.0, 2.0, "D5"), (3, 2.0, 1.0, "Bb4"), (3, 3.0, 1.0, "G4"),
    (4, 0.0, 1.0, "D5"), (4, 1.0, 0.5, "F5"), (4, 1.5, 0.5, "G5"), (4, 2.0, 2.0, "Bb5"),
    (5, 0.0, 1.0, "A5"), (5, 1.0, 1.0, "F5"), (5, 2.0, 2.0, "C5"),
    (6, 0.0, 1.5, "D5"), (6, 1.5, 0.5, "E5"), (6, 2.0, 1.0, "F5"), (6, 3.0, 1.0, "A5"),
    (7, 0.0, 4.0, "G5"),
]


def age_of_discovery() -> Piece:
    piece = Piece("music_age_of_discovery", bpm=76, bars=24, wet=0.36, rt60=2.4)
    state: dict = {}
    add_consort(piece, 0, AIR_CHORDS_A, False, state)
    add_consort(piece, 8, AIR_CHORDS_B, False, state)
    add_consort(piece, 16, AIR_CHORDS_A, True, state)
    add_melody(piece, 0, AIR_MELODY_A, "recorder", 0.8, 0.16)
    add_melody(piece, 8, AIR_MELODY_B, "recorder", 0.8, 0.16)
    add_melody(piece, 16, AIR_MELODY_A, "recorder", 0.86, 0.16)
    # a second recorder a fourth below thickens the repeat like a consort pair
    add_melody(piece, 16, AIR_MELODY_A, "recorder", 0.34, -0.32, transpose=-5)
    return piece


# II. 1600s — Baroque allegro in D major: two violins, continuo, harpsichord.
MAIN_CHORDS_A = [("D", "maj"), ("B", "min"), ("G", "maj"), ("A", "maj"),
                 ("D", "maj"), ("F#", "min"), ("G", "maj"), ("A", "maj")]
MAIN_CHORDS_B = [("B", "min"), ("F#", "min"), ("G", "maj"), ("D", "maj"),
                 ("E", "min"), ("A", "maj"), ("D", "maj"), ("A", "maj")]

MAIN_MELODY_A = [
    (0, 0.0, 0.5, "A5"), (0, 0.5, 0.5, "A5"), (0, 1.0, 0.5, "F#5"), (0, 1.5, 0.5, "D5"),
    (0, 2.0, 1.0, "E5"), (0, 3.0, 1.0, "F#5"),
    (1, 0.0, 1.0, "F#5"), (1, 1.0, 1.0, "D5"), (1, 2.0, 2.0, "B4"),
    (2, 0.0, 0.5, "G5"), (2, 0.5, 0.5, "F#5"), (2, 1.0, 0.5, "G5"), (2, 1.5, 0.5, "A5"),
    (2, 2.0, 2.0, "B5"),
    (3, 0.0, 1.0, "A5"), (3, 1.0, 1.0, "E5"), (3, 2.0, 1.0, "C#5"), (3, 3.0, 1.0, "E5"),
    (4, 0.0, 0.5, "D5"), (4, 0.5, 0.5, "E5"), (4, 1.0, 0.5, "F#5"), (4, 1.5, 0.5, "G5"),
    (4, 2.0, 2.0, "A5"),
    (5, 0.0, 1.0, "F#5"), (5, 1.0, 1.0, "A5"), (5, 2.0, 2.0, "C#6"),
    (6, 0.0, 1.0, "B5"), (6, 1.0, 0.5, "A5"), (6, 1.5, 0.5, "G5"), (6, 2.0, 1.0, "F#5"),
    (6, 3.0, 1.0, "E5"),
    (7, 0.0, 2.0, "E5"), (7, 2.0, 2.0, "A4"),
]

MAIN_MELODY_B = [
    (0, 0.0, 0.5, "B4"), (0, 0.5, 0.5, "D5"), (0, 1.0, 0.5, "F#5"), (0, 1.5, 0.5, "B5"),
    (0, 2.0, 1.0, "A5"), (0, 3.0, 1.0, "F#5"),
    (1, 0.0, 1.0, "F#5"), (1, 1.0, 0.5, "E5"), (1, 1.5, 0.5, "D5"), (1, 2.0, 2.0, "C#5"),
    (2, 0.0, 0.5, "G5"), (2, 0.5, 0.5, "A5"), (2, 1.0, 1.0, "B5"), (2, 2.0, 2.0, "D6"),
    (3, 0.0, 1.5, "A5"), (3, 1.5, 0.5, "F#5"), (3, 2.0, 2.0, "D5"),
    (4, 0.0, 0.5, "E5"), (4, 0.5, 0.5, "F#5"), (4, 1.0, 1.0, "G5"), (4, 2.0, 2.0, "B5"),
    (5, 0.0, 1.0, "A5"), (5, 1.0, 1.0, "G5"), (5, 2.0, 1.0, "E5"), (5, 3.0, 1.0, "C#5"),
    (6, 0.0, 1.0, "D5"), (6, 1.0, 1.0, "F#5"), (6, 2.0, 1.0, "A5"), (6, 3.0, 1.0, "D6"),
    (7, 0.0, 2.0, "A5"), (7, 2.0, 2.0, "E5"),
]


def spanish_main() -> Piece:
    piece = Piece("music_spanish_main", bpm=100, bars=24, wet=0.3, rt60=1.9)
    state: dict = {}
    add_continuo(piece, 0, MAIN_CHORDS_A, False, state)
    add_continuo(piece, 8, MAIN_CHORDS_B, False, state)
    add_continuo(piece, 16, MAIN_CHORDS_A, True, state)
    add_melody(piece, 0, MAIN_MELODY_A, "violin", 0.82, 0.2)
    add_melody(piece, 8, MAIN_MELODY_B, "violin", 0.82, 0.2)
    add_melody(piece, 16, MAIN_MELODY_A, "violin", 0.86, 0.2)
    add_melody(piece, 16, MAIN_MELODY_A, "violin", 0.3, -0.28, transpose=-3)
    return piece


# III. 1700 — galant minuet in C major for the later game.
MINUET_CHORDS_A = [("C", "maj"), ("G", "maj"), ("A", "min"), ("F", "maj"),
                   ("C", "maj"), ("G", "maj"), ("F", "maj"), ("G", "maj")]
MINUET_CHORDS_B = [("A", "min"), ("E", "min"), ("F", "maj"), ("C", "maj"),
                   ("D", "min"), ("G", "maj"), ("C", "maj"), ("G", "maj")]

MINUET_MELODY_A = [
    (0, 0.0, 1.0, "E5"), (0, 1.0, 1.0, "G5"), (0, 2.0, 1.0, "E5"),
    (1, 0.0, 1.5, "D5"), (1, 1.5, 0.5, "B4"), (1, 2.0, 1.0, "G4"),
    (2, 0.0, 1.0, "C5"), (2, 1.0, 1.0, "E5"), (2, 2.0, 1.0, "A5"),
    (3, 0.0, 2.0, "G5"), (3, 2.0, 1.0, "F5"),
    (4, 0.0, 1.0, "E5"), (4, 1.0, 1.0, "G5"), (4, 2.0, 1.0, "C6"),
    (5, 0.0, 1.5, "B5"), (5, 1.5, 0.5, "A5"), (5, 2.0, 1.0, "G5"),
    (6, 0.0, 1.0, "F5"), (6, 1.0, 1.0, "E5"), (6, 2.0, 1.0, "D5"),
    (7, 0.0, 3.0, "C5"),
]

MINUET_MELODY_B = [
    (0, 0.0, 1.0, "A5"), (0, 1.0, 1.0, "C6"), (0, 2.0, 1.0, "A5"),
    (1, 0.0, 1.0, "G5"), (1, 1.0, 1.0, "E5"), (1, 2.0, 1.0, "B4"),
    (2, 0.0, 2.0, "A5"), (2, 2.0, 1.0, "F5"),
    (3, 0.0, 2.0, "E5"), (3, 2.0, 1.0, "G5"),
    (4, 0.0, 1.0, "F5"), (4, 1.0, 1.0, "A5"), (4, 2.0, 1.0, "D6"),
    (5, 0.0, 1.0, "C6"), (5, 1.0, 1.0, "B5"), (5, 2.0, 1.0, "G5"),
    (6, 0.0, 1.0, "A5"), (6, 1.0, 1.0, "G5"), (6, 2.0, 1.0, "E5"),
    (7, 0.0, 3.0, "C5"),
]


def gilded_minuet() -> Piece:
    piece = Piece("music_gilded_minuet", bpm=132, beats_per_bar=3, bars=24,
                  wet=0.3, rt60=1.7)
    state: dict = {}
    add_galant(piece, 0, MINUET_CHORDS_A, False, state)
    add_galant(piece, 8, MINUET_CHORDS_B, False, state)
    add_galant(piece, 16, MINUET_CHORDS_A, True, state)
    add_melody(piece, 0, MINUET_MELODY_A, "flute", 0.8, 0.22)
    add_melody(piece, 8, MINUET_MELODY_B, "flute", 0.8, 0.22)
    add_melody(piece, 16, MINUET_MELODY_A, "flute", 0.85, 0.22)
    add_melody(piece, 16, MINUET_MELODY_A, "viol", 0.28, -0.3, transpose=-12)
    return piece


# IV. Battle — D minor toccata: string tremolo, timpani, driving bass.
BATTLE_CHORDS = [("D", "min"), ("D", "min"), ("C", "maj"), ("D", "min"),
                 ("G", "min"), ("D", "min"), ("A", "maj"), ("D", "min")]

BATTLE_MELODY = [
    (0, 0.0, 1.0, "A4"), (0, 1.0, 1.0, "D5"), (0, 2.0, 1.0, "F5"), (0, 3.0, 0.5, "E5"),
    (0, 3.5, 0.5, "D5"),
    (1, 0.0, 2.0, "D5"), (1, 2.0, 1.0, "A4"), (1, 3.0, 1.0, "F4"),
    (2, 0.0, 1.0, "C5"), (2, 1.0, 1.0, "Bb4"), (2, 2.0, 2.0, "A4"),
    (3, 0.0, 1.0, "D5"), (3, 1.0, 1.0, "F5"), (3, 2.0, 1.0, "A5"), (3, 3.0, 1.0, "G5"),
    (4, 0.0, 2.0, "G5"), (4, 2.0, 2.0, "Bb5"),
    (5, 0.0, 1.0, "A5"), (5, 1.0, 1.0, "F5"), (5, 2.0, 2.0, "D5"),
    (6, 0.0, 2.0, "C#5"), (6, 2.0, 1.0, "E5"), (6, 3.0, 1.0, "G5"),
    (7, 0.0, 4.0, "D5"),
]


def broadsides() -> Piece:
    piece = Piece("music_broadsides", bpm=148, bars=16, wet=0.26, rt60=1.5,
                  target_rms_db=-17.0)
    state: dict = {}
    for bar0 in (0, 8):
        variation = bar0 == 8
        for i, (root, quality) in enumerate(BATTLE_CHORDS):
            bar = bar0 + i
            inner = voicing(root, quality, 48, 64, state.get("inner"))
            state["inner"] = inner
            # tremolo in sixteenths
            steps = 16 if variation else 12
            for step in range(steps):
                note = inner[step % len(inner)] + 12
                piece.add(bar, step * 4.0 / steps, 4.0 / steps * 0.8, _name(note),
                          "viol", 0.3 if step % 2 else 0.38, 0.24, 0.25)
            low = bass_note(root, 36, 45, state.get("bass"))
            state["bass"] = low
            for step in range(8):
                note = low if step % 4 != 3 else low + 7
                piece.add(bar, step * 0.5, 0.42, _name(note), "cello", 0.55, -0.1, 0.18)
            if bar % 2 == 0:
                piece.add(bar, 0.0, 1.0, _name(low - 12), "timpani", 0.8, -0.1, 0.3)
            piece.add(bar, 2.0, 0.8, _name(low - 12), "timpani", 0.55, 0.12, 0.3)
        add_melody(piece, bar0, BATTLE_MELODY, "brass", 0.62, -0.12)
    return piece


# --- stingers ----------------------------------------------------------------


def victory_fanfare() -> Piece:
    piece = Piece("stinger_victory", bpm=132, bars=4, wet=0.24, rt60=1.6, loop=False)
    bars = [("D", "maj"), ("A", "maj"), ("D", "maj"), ("D", "maj")]
    for i, (root, quality) in enumerate(bars):
        chord = voicing(root, quality, 50, 70)
        for note in chord:
            piece.add(i, 0.0, 3.6, _name(note), "brass", 0.34, 0.0, 0.25)
        low = bass_note(root, 38, 50)
        piece.add(i, 0.0, 4.0, _name(low), "cello", 0.5, -0.05, 0.2)
        piece.add(i, 0.0, 0.9, _name(low - 12), "timpani", 0.75, 0.0, 0.3)
    add_melody(piece, 0, [
        (0, 0.0, 0.5, "D5"), (0, 0.5, 0.5, "F#5"), (0, 1.0, 0.5, "A5"), (0, 1.5, 1.5, "D6"),
        (1, 0.0, 1.0, "A5"), (1, 1.0, 1.0, "B5"), (1, 2.0, 2.0, "A5"),
        (2, 0.0, 0.5, "F#5"), (2, 0.5, 0.5, "A5"), (2, 1.0, 1.0, "D6"), (2, 2.0, 2.0, "A5"),
        (3, 0.0, 3.5, "D6"),
    ], "brass", 0.78, 0.1)
    return piece


def defeat_knell() -> Piece:
    piece = Piece("stinger_defeat", bpm=76, bars=4, wet=0.42, rt60=2.6, loop=False)
    bars = [("D", "min"), ("Bb", "maj"), ("G", "min"), ("D", "min")]
    for i, (root, quality) in enumerate(bars):
        chord = voicing(root, quality, 50, 68)
        for note in chord:
            piece.add(i, 0.0, 4.0, _name(note), "viol", 0.34, -0.15, 0.45)
        piece.add(i, 0.0, 4.0, _name(bass_note(root, 36, 48)), "cello", 0.5, -0.05, 0.4)
    add_melody(piece, 0, [
        (0, 0.0, 2.0, "D5"), (0, 2.0, 2.0, "C#5"),
        (1, 0.0, 1.0, "D5"), (1, 1.0, 1.0, "Bb4"), (1, 2.0, 2.0, "A4"),
        (2, 0.0, 2.0, "G4"), (2, 2.0, 2.0, "F4"),
        (3, 0.0, 1.0, "E4"), (3, 1.0, 3.0, "D4"),
    ], "viol", 0.6, 0.1)
    piece.add(3, 0.0, 2.0, "D3", "bell", 0.35, 0.0, 0.55)
    return piece



