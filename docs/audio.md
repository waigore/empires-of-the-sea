# Audio

Music, cues and ambience for the map screen (`REQ-P1-06`); no sampled
recordings.

## Music

Four beds and two stingers are instrumental tracks from ElevenLabs Music
(`music_v2_5`, `force_instrumental`), with prompts and song ids in
`tools/audio/elevenlabs_music.json`. Masters live in Godot-ignored
`tools/audio/masters/`; `finish_elevenlabs.py` trims silence, folds the tail into
the head for a seamless loop, normalises to −17.5 dBFS and writes
`assets/audio/music/*.ogg`.

```bash
python tools/audio/finish_elevenlabs.py     # masters -> shipped Ogg beds
python tools/audio/build_audio.py           # sfx + ambience
python tools/audio/build_audio.py --only sfx
python tools/audio/build_audio.py --only music-synth   # offline fallback only
```

`score.py` and `dsp.py` are a deterministic offline fallback in the same idiom;
`music-synth` overwrites the shipped beds.

## Score (period-fitting, `REQ-P1-02`)

| Bed | Era | Character |
|-----|-----|-----------|
| `music_age_of_discovery` | 1500–1549 | G-major branle: recorders, lute, viols, tabor |
| `music_spanish_main` | 1550–1699 | D-major gigue: violins, harpsichord, castanets, natural trumpet |
| `music_gilded_minuet` | 1700+ | G-major galant minuet: flute, strings, harpsichord |
| `music_broadsides` | combat | D-major buccaneer hornpipe: fife, fiddles, tabor, timpani |
| `stinger_victory` / `stinger_defeat` | one-shot | Fanfare / knell |
| `ambience_sea` | always | Swell, rigging creak, distant gull |

All beds are bright major-mode dances; percussion carries the pulse and reverb is
short (1.4–1.5 s), so the score reads lively, not haunted.

Loops crossfade at the seam (1.5 s equal-power), so beds repeat without clicks.
`MusicPlaylist.bed_for_year` (via `TurnTime`) opens on the branle, moves to the
gigue at 1550, then the minuet at 1700.

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
| Siege battle / battery silenced | `siege_cannon`, then `wall_breach` |
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
