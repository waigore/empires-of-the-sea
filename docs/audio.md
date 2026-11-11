# Audio

Music, cues and ambience for the whole app (`REQ-P1-06`); no sampled
recordings.

## Music

Four beds and two stingers are ElevenLabs Music tracks (`music_v2_5`,
`force_instrumental`); prompts and song ids sit in
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

`score.py`/`dsp.py` are an offline fallback; `music-synth` overwrites the beds.

## Score (period-fitting, `REQ-P1-02`)

| Bed | Era | Character |
|-----|-----|-----------|
| `music_age_of_discovery` | 1500–1549 | G-major branle: recorders, lute, viols, tabor |
| `music_spanish_main` | 1550–1699 | D-major gigue: violins, harpsichord, castanets, natural trumpet |
| `music_gilded_minuet` | 1700+ | G-major galant minuet: flute, strings, harpsichord |
| `music_broadsides` | combat | D-major buccaneer hornpipe: fife, fiddles, tabor, timpani |
| `stinger_victory` / `stinger_defeat` | one-shot | Fanfare / knell |
| `ambience_sea` | always | Swell, rigging creak, distant gull |

Bright major-mode dances: percussion leads, reverb 1.4–1.5 s.

Loops crossfade at the seam (1.5 s equal-power). Beds follow the calendar:
branle, gigue at 1550, minuet at 1700; the title screen borrows the branle, so a
campaign opens on a bed already playing.

Mix: music ≈ −17.5 dBFS RMS, cues ≈ −13 dBFS, music 0.50 under effects 0.85.

## Runtime

| Piece | Role |
|-------|------|
| `scripts/audio/audio_events.gd` | Event → file, trim, pitch-jitter table |
| `scripts/audio/audio_mix.gd` | Volumes, mute, `user://audio.cfg` persistence |
| `scripts/audio/music_playlist.gd` | Track catalogue + era rule |
| `scripts/audio/audio_director.gd` | Crossfade pair, 6-voice SFX pool, ambience |
| `scripts/audio/shell_soundtrack.gd` | Launch bed, global mute key |
| `scripts/audio/map_soundtrack.gd` | Listens to map-screen signals, picks beds/cues |
| `scripts/ui/audio_controls.gd` | Bell seal + mix desk |

No autoload: `main.tscn` owns the one director and hands it to each map screen,
so the bed plays from launch, `arch-lint` stays clean and tests inject their own.

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
| Raid: crown pays / crown takes prize | `raid_alarm` / `cargo_seized` |
| Order refused | `order_denied` |
| Battle won / lost | victory fanfare / defeat knell |

Battle switches beds for 14 s, then the era bed returns; raids cue off
`raid_resolved`.

## Controls

The bell seal opens the mix desk (music, effects, mute); the title page carries
one too. `M` mutes anywhere; settings persist.

## Tests

`tests/test_audio_*.gd`, `tests/test_map_soundtrack.gd`,
`tests/test_shell_soundtrack.gd`: cue files exist, eras map correctly, mute
silences both buses, and the launch bed carries into play.
