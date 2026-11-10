"""Score definitions for Empires of the Sea — hand-written period material.

Four beds, two stingers and a sea ambience, all in the bright major-mode dance
idioms of the colonial era: a Renaissance branle for the first voyages, a
Baroque gigue for the Spanish Main, a galant minuet for the later court, and a
buccaneer hornpipe for battle. Melodies are written by hand; accompaniment
(chord voicing, continuo figuration, divisions on repeats) is derived from the
chord progression so the parts stay in key and move by the smallest step.

Form for each bed is A (8 bars) – B (8 bars) – A' (8 bars, ornamented repeat).
Percussion (tabor, tambourine, castanets, timpani) carries the dance pulse so the
beds read as lively rather than haunted.
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


def _name(note: int) -> str:
    names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    return "%s%d" % (names[note % 12], note // 12 - 1)


# --- shared accompaniment patterns ------------------------------------------


def add_branle(piece: Piece, bar0: int, chords: list[tuple[str, str]],
               variation: bool, state: dict) -> None:
    """Renaissance branle: plucked offbeats, viol consort, tabor and tambourine."""
    for i, (root, quality) in enumerate(chords):
        bar = bar0 + i
        inner = voicing(root, quality, 55, 72, state.get("inner"))
        state["inner"] = inner
        low = bass_note(root, 36, 48, state.get("bass"))
        state["bass"] = low
        for k, note in enumerate(inner):
            pan = -0.24 + 0.48 * (k / max(1, len(inner) - 1))
            piece.add(bar, 0.0, 1.7, _name(note), "viol", 0.24, pan, 0.22)
            piece.add(bar, 2.0, 1.5, _name(note), "viol", 0.2, pan, 0.22)
        fifth = 7 if quality == "maj" else 3
        piece.add(bar, 0.0, 1.8, _name(low), "theorbo", 0.6, -0.06, 0.14)
        piece.add(bar, 2.0, 1.5, _name(low + fifth), "theorbo", 0.48, -0.06, 0.14)
        for beat in (0.5, 1.5, 2.5, 3.5):
            for note in inner[:3]:
                piece.add(bar, beat, 0.4, _name(note + 12), "lute",
                          0.15 if not variation else 0.2, 0.22, 0.26)
        if variation:
            for step in range(8):
                note = inner[[0, 1, 2, 1, 0, 2, 1, 2][step]] + 12
                piece.add(bar, step * 0.5, 0.34, _name(note), "lute", 0.19, 0.24, 0.3)
        # branle pulse: tabor on the strong beats, jingles lifting the offbeats
        piece.add(bar, 0.0, 0.45, "C2", "tabor", 0.55, -0.08, 0.14)
        piece.add(bar, 2.0, 0.4, "C2", "tabor", 0.4, -0.08, 0.14)
        for beat in (0.5, 1.5, 2.5, 3.5):
            piece.add(bar, beat, 0.2, "C5", "tambourine", 0.18, 0.26, 0.16)


def add_gigue(piece: Piece, bar0: int, chords: list[tuple[str, str]],
              variation: bool, state: dict) -> None:
    """Baroque gigue: running harpsichord divisions, walking cello, castanets."""
    for i, (root, quality) in enumerate(chords):
        bar = bar0 + i
        upper = voicing(root, quality, 57, 76, state.get("upper"))
        state["upper"] = upper
        low = bass_note(root, 38, 52, state.get("bass"))
        state["bass"] = low
        tones = [low, low + 7 if quality != "dim" else low + 6, low + 12,
                 upper[0], upper[1], upper[2]]
        pattern = [0, 2, 4, 1, 3, 5, 2, 1] if variation else [0, 2, 1, 3, 4, 2, 1, 0]
        for step in range(8):
            note = tones[pattern[step] % len(tones)]
            piece.add(bar, step * 0.5, 0.42, _name(note), "harpsichord",
                      0.28 if step % 2 == 0 else 0.19, 0.2, 0.14)
        for beat in range(4):
            note = low if beat % 2 == 0 else low + (7 if quality == "maj" else 5)
            piece.add(bar, float(beat), 0.66, _name(note), "cello", 0.5, -0.08, 0.12)
        for k, note in enumerate(upper):
            piece.add(bar, 0.0, 1.8, _name(note), "viol", 0.15,
                      -0.3 + 0.3 * k, 0.2)
        # Spanish colonial colour: heel-and-toe castanets
        for beat in (1.0, 3.0):
            piece.add(bar, beat, 0.2, "C5", "castanet", 0.38, 0.3, 0.1)
        for beat in (0.5, 1.5, 2.5, 3.5):
            piece.add(bar, beat, 0.16, "C5", "castanet", 0.2, -0.28, 0.1)


def add_minuet(piece: Piece, bar0: int, chords: list[tuple[str, str]],
               variation: bool, prev_state: dict, beats_per_bar: int = 3) -> None:
    """Galant minuet: light strings on the after-beats, broken-chord harpsichord."""
    for i, (root, quality) in enumerate(chords):
        bar = bar0 + i
        upper = voicing(root, quality, 55, 74, prev_state.get("upper"))
        prev_state["upper"] = upper
        low = bass_note(root, 40, 52, prev_state.get("bass"))
        prev_state["bass"] = low
        for k, note in enumerate(upper):
            piece.add(bar, 1.0, 0.8, _name(note), "viol", 0.2,
                      -0.26 + 0.34 * k, 0.2)
            piece.add(bar, 2.0, 0.8, _name(note), "viol", 0.17,
                      -0.26 + 0.34 * k, 0.2)
        piece.add(bar, 0.0, 1.6, _name(low), "cello", 0.52, -0.05, 0.16)
        piece.add(bar, 1.0, 0.9, _name(low + 7), "cello", 0.3, -0.05, 0.16)
        steps = 6 if variation else 3
        pattern = [0, 1, 2, 1, 2, 1] if variation else [0, 2, 1]
        for step in range(steps):
            note = upper[pattern[step] % len(upper)] + 12
            piece.add(bar, step * beats_per_bar / steps,
                      beats_per_bar / steps * 0.85, _name(note), "harpsichord",
                      0.17 if not variation else 0.21, 0.28, 0.22)


def add_hornpipe(piece: Piece, bar0: int, chords: list[tuple[str, str]],
                 variation: bool, state: dict) -> None:
    """Buccaneer hornpipe: driving cello eighths, fiddles, tabor, timpani."""
    for i, (root, quality) in enumerate(chords):
        bar = bar0 + i
        inner = voicing(root, quality, 50, 66, state.get("inner"))
        state["inner"] = inner
        low = bass_note(root, 36, 48, state.get("bass"))
        state["bass"] = low
        fifth = 7 if quality == "maj" else 3
        for step in range(8):
            note = low if step % 4 != 2 else low + fifth
            if step % 4 == 3:
                note = low + 12
            piece.add(bar, step * 0.5, 0.4, _name(note), "cello",
                      0.5 if step % 2 == 0 else 0.4, -0.1, 0.12)
        for k, note in enumerate(inner):
            piece.add(bar, 1.0, 0.5, _name(note), "viol", 0.2,
                      -0.22 + 0.44 * k / max(1, len(inner) - 1), 0.2)
            piece.add(bar, 3.0, 0.5, _name(note), "viol", 0.18,
                      -0.22 + 0.44 * k / max(1, len(inner) - 1), 0.2)
        for beat in (0.0, 2.0):
            piece.add(bar, beat, 0.5, _name(low - 12), "timpani", 0.42, -0.12, 0.18)
        for step in range(8):
            piece.add(bar, step * 0.5, 0.24, "C2" if step % 2 == 0 else "C4",
                      "tabor", 0.38 if step % 2 == 0 else 0.16, 0.06, 0.1)
        for beat in (0.5, 1.5, 2.5, 3.5):
            piece.add(bar, beat, 0.18, "C5", "tambourine", 0.22, 0.28, 0.12)
        if variation:
            for step in range(8):
                note = inner[step % len(inner)] + 12
                piece.add(bar, step * 0.5, 0.28, _name(note), "harpsichord",
                          0.18, -0.24, 0.2)


def add_melody(piece: Piece, bar0: int, notes: list[tuple], instr: str,
               vel: float = 0.82, pan: float = 0.18, transpose: int = 0) -> None:
    for bar, beat, dur, note in notes:
        piece.add(bar0 + bar, beat, dur, _name(dsp.midi(note) + transpose), instr, vel, pan, 0.26)


# --- pieces ------------------------------------------------------------------

# I. 1500 — "The Caravel's Branle" in G major: recorders, lute, viols, tabor.
AIR_CHORDS_A = [("G", "maj"), ("C", "maj"), ("G", "maj"), ("D", "maj"),
                ("G", "maj"), ("C", "maj"), ("D", "maj"), ("G", "maj")]
AIR_CHORDS_B = [("E", "min"), ("C", "maj"), ("G", "maj"), ("D", "maj"),
                ("E", "min"), ("C", "maj"), ("D", "maj"), ("G", "maj")]

AIR_MELODY_A = [
    (0, 0.0, 0.5, "D5"), (0, 0.5, 0.5, "G5"), (0, 1.0, 0.5, "A5"), (0, 1.5, 0.5, "B5"),
    (0, 2.0, 1.0, "A5"), (0, 3.0, 1.0, "G5"),
    (1, 0.0, 1.0, "E5"), (1, 1.0, 1.0, "G5"), (1, 2.0, 2.0, "C6"),
    (2, 0.0, 0.5, "B5"), (2, 0.5, 0.5, "A5"), (2, 1.0, 1.0, "G5"), (2, 2.0, 2.0, "D5"),
    (3, 0.0, 1.0, "F#5"), (3, 1.0, 1.0, "A5"), (3, 2.0, 1.0, "D6"), (3, 3.0, 1.0, "A5"),
    (4, 0.0, 0.5, "G5"), (4, 0.5, 0.5, "A5"), (4, 1.0, 1.0, "B5"), (4, 2.0, 2.0, "D6"),
    (5, 0.0, 1.0, "E5"), (5, 1.0, 1.0, "G5"), (5, 2.0, 2.0, "C6"),
    (6, 0.0, 1.0, "A5"), (6, 1.0, 1.0, "F#5"), (6, 2.0, 1.0, "D5"), (6, 3.0, 1.0, "F#5"),
    (7, 0.0, 3.0, "G5"),
]

AIR_MELODY_B = [
    (0, 0.0, 0.5, "B5"), (0, 0.5, 0.5, "A5"), (0, 1.0, 1.0, "G5"), (0, 2.0, 2.0, "E5"),
    (1, 0.0, 1.0, "E5"), (1, 1.0, 1.0, "G5"), (1, 2.0, 2.0, "C6"),
    (2, 0.0, 0.5, "B5"), (2, 0.5, 0.5, "A5"), (2, 1.0, 1.0, "G5"), (2, 2.0, 2.0, "D5"),
    (3, 0.0, 1.0, "A5"), (3, 1.0, 1.0, "F#5"), (3, 2.0, 2.0, "D5"),
    (4, 0.0, 0.5, "E5"), (4, 0.5, 0.5, "F#5"), (4, 1.0, 1.0, "G5"), (4, 2.0, 2.0, "B5"),
    (5, 0.0, 1.0, "A5"), (5, 1.0, 1.0, "G5"), (5, 2.0, 1.0, "E5"), (5, 3.0, 1.0, "G5"),
    (6, 0.0, 0.5, "F#5"), (6, 0.5, 0.5, "E5"), (6, 1.0, 1.0, "D5"), (6, 2.0, 2.0, "A4"),
    (7, 0.0, 3.0, "G5"),
]


def age_of_discovery() -> Piece:
    piece = Piece("music_age_of_discovery", bpm=126, bars=24, wet=0.2, rt60=1.5)
    state: dict = {}
    add_branle(piece, 0, AIR_CHORDS_A, False, state)
    add_branle(piece, 8, AIR_CHORDS_B, False, state)
    add_branle(piece, 16, AIR_CHORDS_A, True, state)
    add_melody(piece, 0, AIR_MELODY_A, "recorder", 0.82, 0.16)
    add_melody(piece, 8, AIR_MELODY_B, "recorder", 0.82, 0.16)
    add_melody(piece, 16, AIR_MELODY_A, "recorder", 0.88, 0.16)
    # a second recorder a fourth below thickens the repeat like a consort pair
    add_melody(piece, 16, AIR_MELODY_A, "recorder", 0.34, -0.32, transpose=-5)
    return piece


# II. 1600s — "The Treasure Fleet" gigue in D: violins, continuo, castanets.
MAIN_CHORDS_A = [("D", "maj"), ("G", "maj"), ("A", "maj"), ("D", "maj"),
                 ("B", "min"), ("G", "maj"), ("A", "maj"), ("D", "maj")]
MAIN_CHORDS_B = [("G", "maj"), ("A", "maj"), ("D", "maj"), ("B", "min"),
                 ("E", "min"), ("A", "maj"), ("D", "maj"), ("A", "dom7")]

MAIN_MELODY_A = [
    (0, 0.0, 0.5, "A4"), (0, 0.5, 0.5, "D5"), (0, 1.0, 0.5, "F#5"), (0, 1.5, 0.5, "A5"),
    (0, 2.0, 0.5, "F#5"), (0, 2.5, 0.5, "D5"), (0, 3.0, 0.5, "E5"), (0, 3.5, 0.5, "F#5"),
    (1, 0.0, 0.5, "G5"), (1, 0.5, 0.5, "B5"), (1, 1.0, 0.5, "A5"), (1, 1.5, 0.5, "G5"),
    (1, 2.0, 0.5, "F#5"), (1, 2.5, 0.5, "E5"), (1, 3.0, 0.5, "D5"), (1, 3.5, 0.5, "G5"),
    (2, 0.0, 1.0, "A5"), (2, 1.0, 0.5, "E5"), (2, 1.5, 0.5, "C#5"),
    (2, 2.0, 1.0, "E5"), (2, 3.0, 1.0, "A5"),
    (3, 0.0, 0.5, "D6"), (3, 0.5, 0.5, "A5"), (3, 1.0, 0.5, "F#5"), (3, 1.5, 0.5, "D5"),
    (3, 2.0, 2.0, "D5"),
    (4, 0.0, 0.5, "B5"), (4, 0.5, 0.5, "A5"), (4, 1.0, 0.5, "F#5"), (4, 1.5, 0.5, "D5"),
    (4, 2.0, 0.5, "F#5"), (4, 2.5, 0.5, "A5"), (4, 3.0, 0.5, "B5"), (4, 3.5, 0.5, "D6"),
    (5, 0.0, 1.0, "B5"), (5, 1.0, 0.5, "A5"), (5, 1.5, 0.5, "G5"),
    (5, 2.0, 1.0, "D5"), (5, 3.0, 1.0, "G5"),
    (6, 0.0, 1.0, "A5"), (6, 1.0, 1.0, "C#6"), (6, 2.0, 1.0, "A5"), (6, 3.0, 1.0, "E5"),
    (7, 0.0, 0.5, "F#5"), (7, 0.5, 0.5, "E5"), (7, 1.0, 0.5, "D5"), (7, 1.5, 0.5, "A4"),
    (7, 2.0, 2.0, "D5"),
]

MAIN_MELODY_B = [
    (0, 0.0, 0.5, "G5"), (0, 0.5, 0.5, "B5"), (0, 1.0, 0.5, "D6"), (0, 1.5, 0.5, "B5"),
    (0, 2.0, 2.0, "G5"),
    (1, 0.0, 0.5, "A5"), (1, 0.5, 0.5, "C#6"), (1, 1.0, 0.5, "E6"), (1, 1.5, 0.5, "C#6"),
    (1, 2.0, 2.0, "A5"),
    (2, 0.0, 0.5, "D6"), (2, 0.5, 0.5, "A5"), (2, 1.0, 0.5, "F#5"), (2, 1.5, 0.5, "D5"),
    (2, 2.0, 2.0, "F#5"),
    (3, 0.0, 0.5, "B5"), (3, 0.5, 0.5, "F#5"), (3, 1.0, 0.5, "D5"), (3, 1.5, 0.5, "F#5"),
    (3, 2.0, 2.0, "B5"),
    (4, 0.0, 0.5, "G5"), (4, 0.5, 0.5, "E5"), (4, 1.0, 0.5, "G5"), (4, 1.5, 0.5, "B5"),
    (4, 2.0, 2.0, "E5"),
    (5, 0.0, 0.5, "A5"), (5, 0.5, 0.5, "E5"), (5, 1.0, 0.5, "C#5"), (5, 1.5, 0.5, "E5"),
    (5, 2.0, 1.0, "A5"), (5, 3.0, 1.0, "C#6"),
    (6, 0.0, 0.5, "D6"), (6, 0.5, 0.5, "A5"), (6, 1.0, 0.5, "F#5"), (6, 1.5, 0.5, "A5"),
    (6, 2.0, 2.0, "D6"),
    (7, 0.0, 1.0, "B5"), (7, 1.0, 1.0, "G5"), (7, 2.0, 2.0, "A5"),
]


def spanish_main() -> Piece:
    piece = Piece("music_spanish_main", bpm=132, bars=24, wet=0.18, rt60=1.4)
    state: dict = {}
    add_gigue(piece, 0, MAIN_CHORDS_A, False, state)
    add_gigue(piece, 8, MAIN_CHORDS_B, False, state)
    add_gigue(piece, 16, MAIN_CHORDS_A, True, state)
    add_melody(piece, 0, MAIN_MELODY_A, "violin", 0.84, 0.2)
    add_melody(piece, 8, MAIN_MELODY_B, "violin", 0.84, 0.2)
    add_melody(piece, 16, MAIN_MELODY_A, "violin", 0.88, 0.2)
    # natural trumpets salute the B section like a treasure-fleet arrival
    add_melody(piece, 8, [
        (0, 0.0, 1.0, "D5"), (0, 1.0, 1.0, "F#5"), (0, 2.0, 2.0, "A5"),
        (1, 0.0, 2.0, "A5"), (1, 2.0, 2.0, "C#6"),
    ], "brass", 0.26, -0.2)
    return piece


# III. 1700 — "Gilded Minuet" in G: flute, strings, harpsichord.
MINUET_CHORDS_A = [("G", "maj"), ("D", "maj"), ("E", "min"), ("C", "maj"),
                   ("G", "maj"), ("D", "dom7"), ("C", "maj"), ("D", "maj")]
MINUET_CHORDS_B = [("E", "min"), ("B", "min"), ("C", "maj"), ("G", "maj"),
                   ("A", "min"), ("D", "sus4"), ("D", "maj"), ("G", "maj")]

MINUET_MELODY_A = [
    (0, 0.0, 1.0, "G5"), (0, 1.0, 1.0, "B5"), (0, 2.0, 1.0, "G5"),
    (1, 0.0, 1.5, "A5"), (1, 1.5, 0.5, "F#5"), (1, 2.0, 1.0, "D5"),
    (2, 0.0, 1.0, "E5"), (2, 1.0, 1.0, "G5"), (2, 2.0, 1.0, "B5"),
    (3, 0.0, 2.0, "C6"), (3, 2.0, 1.0, "G5"),
    (4, 0.0, 1.0, "G5"), (4, 1.0, 1.0, "B5"), (4, 2.0, 1.0, "D6"),
    (5, 0.0, 1.0, "C6"), (5, 1.0, 1.0, "B5"), (5, 2.0, 1.0, "A5"),
    (6, 0.0, 1.5, "G5"), (6, 1.5, 0.5, "A5"), (6, 2.0, 1.0, "G5"),
    (7, 0.0, 3.0, "D5"),
]

MINUET_MELODY_B = [
    (0, 0.0, 1.0, "B5"), (0, 1.0, 1.0, "D6"), (0, 2.0, 1.0, "B5"),
    (1, 0.0, 1.5, "A5"), (1, 1.5, 0.5, "G5"), (1, 2.0, 1.0, "F#5"),
    (2, 0.0, 1.0, "G5"), (2, 1.0, 1.0, "B5"), (2, 2.0, 1.0, "E6"),
    (3, 0.0, 2.0, "D6"), (3, 2.0, 1.0, "B5"),
    (4, 0.0, 1.0, "C6"), (4, 1.0, 1.0, "B5"), (4, 2.0, 1.0, "A5"),
    (5, 0.0, 1.5, "G5"), (5, 1.5, 0.5, "A5"), (5, 2.0, 1.0, "B5"),
    (6, 0.0, 1.0, "A5"), (6, 1.0, 1.0, "F#5"), (6, 2.0, 1.0, "D5"),
    (7, 0.0, 3.0, "G5"),
]


def gilded_minuet() -> Piece:
    piece = Piece("music_gilded_minuet", bpm=144, beats_per_bar=3, bars=24,
                  wet=0.2, rt60=1.4)
    state: dict = {}
    add_minuet(piece, 0, MINUET_CHORDS_A, False, state)
    add_minuet(piece, 8, MINUET_CHORDS_B, False, state)
    add_minuet(piece, 16, MINUET_CHORDS_A, True, state)
    add_melody(piece, 0, MINUET_MELODY_A, "flute", 0.84, 0.22)
    add_melody(piece, 8, MINUET_MELODY_B, "flute", 0.84, 0.22)
    add_melody(piece, 16, MINUET_MELODY_A, "flute", 0.88, 0.22)
    add_melody(piece, 16, MINUET_MELODY_A, "viol", 0.24, -0.3, transpose=-12)
    return piece


# IV. Battle — "Hornpipe for a Broadside" in D: fife, fiddles, drum, timpani.
BATTLE_CHORDS_A = [("D", "maj"), ("G", "maj"), ("A", "maj"), ("D", "maj"),
                   ("B", "min"), ("G", "maj"), ("A", "maj"), ("D", "maj")]
BATTLE_CHORDS_B = [("B", "min"), ("G", "maj"), ("D", "maj"), ("A", "maj"),
                   ("B", "min"), ("G", "maj"), ("A", "maj"), ("D", "maj")]

BATTLE_MELODY_A = [
    (0, 0.0, 0.5, "D5"), (0, 0.5, 0.5, "F#5"), (0, 1.0, 0.5, "A5"), (0, 1.5, 0.5, "D6"),
    (0, 2.0, 0.5, "A5"), (0, 2.5, 0.5, "F#5"), (0, 3.0, 0.5, "E5"), (0, 3.5, 0.5, "D5"),
    (1, 0.0, 0.5, "G5"), (1, 0.5, 0.5, "B5"), (1, 1.0, 0.5, "D6"), (1, 1.5, 0.5, "B5"),
    (1, 2.0, 0.5, "A5"), (1, 2.5, 0.5, "G5"), (1, 3.0, 0.5, "F#5"), (1, 3.5, 0.5, "E5"),
    (2, 0.0, 0.5, "E5"), (2, 0.5, 0.5, "A5"), (2, 1.0, 0.5, "C#6"), (2, 1.5, 0.5, "E6"),
    (2, 2.0, 1.0, "C#6"), (2, 3.0, 1.0, "A5"),
    (3, 0.0, 1.0, "D6"), (3, 1.0, 0.5, "A5"), (3, 1.5, 0.5, "F#5"), (3, 2.0, 2.0, "D5"),
    (4, 0.0, 0.5, "B5"), (4, 0.5, 0.5, "D6"), (4, 1.0, 0.5, "F#6"), (4, 1.5, 0.5, "D6"),
    (4, 2.0, 1.0, "B5"), (4, 3.0, 1.0, "F#5"),
    (5, 0.0, 0.5, "G5"), (5, 0.5, 0.5, "B5"), (5, 1.0, 0.5, "D6"), (5, 1.5, 0.5, "B5"),
    (5, 2.0, 1.0, "G5"), (5, 3.0, 1.0, "E5"),
    (6, 0.0, 0.5, "A5"), (6, 0.5, 0.5, "C#6"), (6, 1.0, 0.5, "E6"), (6, 1.5, 0.5, "C#6"),
    (6, 2.0, 1.0, "A5"), (6, 3.0, 1.0, "E5"),
    (7, 0.0, 0.5, "D6"), (7, 0.5, 0.5, "C#6"), (7, 1.0, 0.5, "B5"), (7, 1.5, 0.5, "A5"),
    (7, 2.0, 2.0, "D5"),
]

BATTLE_MELODY_B = [
    (0, 0.0, 0.5, "B5"), (0, 0.5, 0.5, "F#5"), (0, 1.0, 0.5, "D5"), (0, 1.5, 0.5, "F#5"),
    (0, 2.0, 1.0, "B5"), (0, 3.0, 1.0, "D6"),
    (1, 0.0, 0.5, "B5"), (1, 0.5, 0.5, "G5"), (1, 1.0, 0.5, "D5"), (1, 1.5, 0.5, "G5"),
    (1, 2.0, 1.0, "B5"), (1, 3.0, 1.0, "D6"),
    (2, 0.0, 0.5, "A5"), (2, 0.5, 0.5, "F#5"), (2, 1.0, 0.5, "D5"), (2, 1.5, 0.5, "F#5"),
    (2, 2.0, 2.0, "A5"),
    (3, 0.0, 0.5, "C#6"), (3, 0.5, 0.5, "A5"), (3, 1.0, 0.5, "E5"), (3, 1.5, 0.5, "A5"),
    (3, 2.0, 2.0, "C#6"),
    (4, 0.0, 0.5, "D6"), (4, 0.5, 0.5, "B5"), (4, 1.0, 0.5, "F#5"), (4, 1.5, 0.5, "B5"),
    (4, 2.0, 1.0, "D6"), (4, 3.0, 1.0, "F#6"),
    (5, 0.0, 0.5, "E6"), (5, 0.5, 0.5, "D6"), (5, 1.0, 0.5, "B5"), (5, 1.5, 0.5, "G5"),
    (5, 2.0, 2.0, "E6"),
    (6, 0.0, 0.5, "C#6"), (6, 0.5, 0.5, "A5"), (6, 1.0, 0.5, "E5"), (6, 1.5, 0.5, "A5"),
    (6, 2.0, 1.0, "C#6"), (6, 3.0, 1.0, "E6"),
    (7, 0.0, 3.0, "D6"),
]


def broadsides() -> Piece:
    piece = Piece("music_broadsides", bpm=152, bars=16, wet=0.18, rt60=1.4,
                  target_rms_db=-17.0)
    state: dict = {}
    add_hornpipe(piece, 0, BATTLE_CHORDS_A, False, state)
    add_hornpipe(piece, 8, BATTLE_CHORDS_B, True, state)
    add_melody(piece, 0, BATTLE_MELODY_A, "fife", 0.7, 0.16)
    add_melody(piece, 8, BATTLE_MELODY_B, "fife", 0.7, 0.16)
    add_melody(piece, 0, BATTLE_MELODY_A, "violin", 0.26, -0.24, transpose=-12)
    add_melody(piece, 8, BATTLE_MELODY_B, "violin", 0.26, -0.24, transpose=-12)
    for bar in (0, 4, 8, 12):
        piece.add(bar, 0.0, 1.2, "D3", "timpani", 0.5, -0.1, 0.22)
    return piece


# --- stingers ----------------------------------------------------------------


def victory_fanfare() -> Piece:
    piece = Piece("stinger_victory", bpm=138, bars=4, wet=0.2, rt60=1.5, loop=False)
    bars = [("D", "maj"), ("A", "maj"), ("D", "maj"), ("D", "maj")]
    for i, (root, quality) in enumerate(bars):
        chord = voicing(root, quality, 50, 70)
        for note in chord:
            piece.add(i, 0.0, 3.6, _name(note), "brass", 0.34, 0.0, 0.22)
        low = bass_note(root, 38, 50)
        piece.add(i, 0.0, 4.0, _name(low), "cello", 0.5, -0.05, 0.16)
        piece.add(i, 0.0, 0.9, _name(low - 12), "timpani", 0.75, 0.0, 0.25)
    add_melody(piece, 0, [
        (0, 0.0, 0.5, "D5"), (0, 0.5, 0.5, "F#5"), (0, 1.0, 0.5, "A5"), (0, 1.5, 1.5, "D6"),
        (1, 0.0, 1.0, "A5"), (1, 1.0, 1.0, "B5"), (1, 2.0, 2.0, "A5"),
        (2, 0.0, 0.5, "F#5"), (2, 0.5, 0.5, "A5"), (2, 1.0, 1.0, "D6"), (2, 2.0, 2.0, "A5"),
        (3, 0.0, 3.5, "D6"),
    ], "brass", 0.78, 0.1)
    return piece


def defeat_knell() -> Piece:
    piece = Piece("stinger_defeat", bpm=84, bars=4, wet=0.32, rt60=2.2, loop=False)
    bars = [("D", "min"), ("Bb", "maj"), ("G", "min"), ("D", "min")]
    for i, (root, quality) in enumerate(bars):
        chord = voicing(root, quality, 50, 68)
        for note in chord:
            piece.add(i, 0.0, 4.0, _name(note), "viol", 0.34, -0.15, 0.38)
        piece.add(i, 0.0, 4.0, _name(bass_note(root, 36, 48)), "cello", 0.5, -0.05, 0.34)
    add_melody(piece, 0, [
        (0, 0.0, 2.0, "D5"), (0, 2.0, 2.0, "C#5"),
        (1, 0.0, 1.0, "D5"), (1, 1.0, 1.0, "Bb4"), (1, 2.0, 2.0, "A4"),
        (2, 0.0, 2.0, "G4"), (2, 2.0, 2.0, "F4"),
        (3, 0.0, 1.0, "E4"), (3, 1.0, 3.0, "D4"),
    ], "viol", 0.6, 0.1)
    piece.add(3, 0.0, 2.0, "D3", "bell", 0.35, 0.0, 0.5)
    return piece
