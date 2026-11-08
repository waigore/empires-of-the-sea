# Audio

Music, cues and ambience for the map screen (`REQ-P1-06`). Everything ships as
generated assets: no sampled or third-party material, so the mix is reproducible
from source and licence-clean.

## Rebuild

```bash
python tools/audio/build_audio.py            # music + sfx + ambience
python tools/audio/build_audio.py --only sfx
python tools/audio/build_audio.py --list
```

Needs `numpy` and `oggenc` (libvorbis). The generator is deterministic per seed;
`tools/audio/dsp.py` holds the instrument/effect kit, `tools/audio/score.py` the
hand-written material.

## Score (period-fitting, `REQ-P1-02`)

| Bed | Era | Character |
|-----|-----|-----------|
| `music_age_of_discovery` | 1500–1549 | Dorian consort air: viols, lute, recorder |
| `music_spanish_main` | 1550–1699 | Baroque allegro in D: two violins, continuo, harpsichord |
| `music_gilded_minuet` | 1700+ | Galant minuet in C: strings, flute, harpsichord |
| `music_broadsides` | combat | D-minor toccata: tremolo strings, timpani, natural trumpet |
| `stinger_victory` / `stinger_defeat` | one-shot | Fanfare / knell |
| `ambience_sea` | always | Swell, rigging creak, distant gull |

Loops are rendered with the reverb tail folded back into the head, so the seam is
sample-continuous. Bed choice comes from `MusicPlaylist.bed_for_year` via
`TurnTime` — the campaign opens on the consort and moves to Baroque at 1550,
then galant at 1700.

Mix targets: music ≈ −17.5 dBFS RMS, cues ≈ −13 dBFS, music default 0.50 under
effects at 0.85 so feedback always reads over the score.

## Runtime

| Piece | Role |
|-------|------|
| `scripts/audio/audio_events.gd` | Event → file, trim, pitch-jitter table |
| `scripts/audio/audio_mix.gd` | Volumes, mute, `user://audio.cfg` persistence |
| `scripts/audio/music_playlist.gd` | Track catalogue + era rule |
| `scripts/audio/audio_director.gd` | Scene node: crossfade pair, 6-voice SFX pool, ambience |
| `scripts/audio/map_soundtrack.gd` | Listens to map-screen signals, picks beds/cues |
| `scripts/ui/audio_controls.gd` | Bell seal + mix desk (touch-first) |

No autoload: the director is a node in `map_screen.tscn`, so `arch-lint` stays
clean and screens can be instantiated in tests.

## Cue map

| Moment | Cue |
|--------|-----|
| Any UI press | `ui_click` |
| Province selected / panel | `province_select` + `panel_open` |
| Selection cleared / panel closed | `panel_close` |
| Fleet selected / moved | `fleet_select` / `fleet_move` |
| Civilian selected / moved | `civilian_select` / `civilian_move` |
| Coast charted | `coast_charted` |
| End turn | `turn_bell` + `coin` |
| Broadside, hull hit, fleet lost | `broadside`, `hull_hit`, `fleet_sunk` |
| Order refused | `order_denied` |
| Battle won / lost | victory fanfare / defeat knell |

Battle switches to the battle bed for 14 s, then the era bed returns.

## Controls

Bell seal, top-left under the cartouche, opens the mix desk (music, effects,
mute). Keyboard: `M` mutes. Settings persist and are restored on boot.

## Tests

`tests/test_audio_*.gd`, `tests/test_music_playlist.gd`,
`tests/test_map_soundtrack.gd`. They assert cue files exist, eras map correctly,
mute silences both buses, and screen moments fire the expected cues.
