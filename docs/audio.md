# Audio

Music, cues and ambience for the whole app (`REQ-P1-06`); no sampled recordings.

## Music

Thirteen beds and two stingers are ElevenLabs Music tracks (`music_v2_5`,
`force_instrumental`); prompts and song ids sit in
`tools/audio/elevenlabs_music.json`. Masters live in Godot-ignored
`tools/audio/masters/`; `generate_elevenlabs.py` fills a missing master from its
prompt, `finish_elevenlabs.py` trims, loop-folds, normalises to −17.5 dBFS and
writes `assets/audio/music/*.ogg`.

```bash
python tools/audio/generate_elevenlabs.py --only court   # prompt -> master (billed)
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
| `music_spanish_main` | 1550–1699 | D-major gigue: violins, harpsichord, castanets, trumpet |
| `music_gilded_minuet` | 1700+ | G-major galant minuet: flute, strings, harpsichord |
| `music_broadsides` | combat | D-major hornpipe: fife, fiddles, tabor, timpani |
| `stinger_victory` / `stinger_defeat` | one-shot | Fanfare / knell |
| `ambience_sea` | always | Swell, rigging creak, distant gull |

Nine 200 s theme beds ride the same rotate — `court`, `exploration`, `battle`,
`extraction`, `industry`, `trade`, `diplomacy`, `research`, `conquest` — each a
major-mode period ensemble, reverb 1.4–1.5 s.

Loops crossfade at the seam (1.5 s equal-power), and beds follow the calendar:
branle, gigue at 1550, minuet at 1700. The title screen borrows the branle, so a
campaign opens mid-bed. From there the score rotates
(`MusicPlaylist.ROTATION`): each bed plays once, unlooped, and the next takes
over when it ends; stingers stay event-only. The launch, a new era and the end
of a battle re-anchor it; a turn close leaves it alone.

Mix: music ≈ −17.5 dBFS RMS, cues ≈ −13 dBFS, music 0.50, effects 0.85.

## Runtime

| Piece | Role |
|-------|------|
| `scripts/audio/audio_events.gd` | Event → file, trim, jitter |
| `scripts/audio/audio_mix.gd` | Volumes, mute, `user://audio.cfg` |
| `scripts/audio/music_playlist.gd` | Catalogue, era rule, rotate order |
| `scripts/audio/audio_director.gd` | Crossfade pair, rotate hand-off, SFX, ambience |
| `scripts/audio/shell_soundtrack.gd` | Launch bed, global mute key |
| `scripts/audio/map_soundtrack.gd` | Map moments → beds and cues |
| `scripts/ui/sound_desk.gd` | Mix desk: music, effects, mute |

No autoload: `main.tscn` owns the director and retires the map scene's own.

## Cue map

| Moment | Cue |
|--------|-----|
| Province selected / panel | `province_select` + `panel_open` |
| Selection cleared / panel closed | `panel_close` |
| Fleet selected / moved | `fleet_select` / `fleet_move` |
| Coast charted | `coast_charted` |
| End turn | `turn_bell` + `coin` |
| Broadside, hull hit, fleet lost | `broadside`, `hull_hit`, `fleet_sunk` |
| Siege battle / battery silenced | `siege_cannon`, then `wall_breach` |
| Raid: crown pays / crown takes prize | `raid_alarm` / `cargo_seized` |
| Battle won / lost | victory fanfare / defeat knell |

Battle switches beds for 14 s, then the era bed returns; raids cue off
`raid_resolved`.

## Controls

Mix desk: pause menu, or the title page's bell seal. `M` mutes anywhere;
settings persist.

## Tests

`tests/test_17_audio_rules.gd` covers the catalogue, the era rule, mute, the
launch carry-over and the rotate hand-off.
