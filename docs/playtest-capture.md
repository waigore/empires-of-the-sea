# Playtest capture mode

Desktop-only tooling for playtesters and agents (issue #1393). Toggle it on,
take screenshots or video, type a comment on each capture, then file issues from
the report it writes. A separate, complementary tool: the
[agent debug bridge](agent-debug.md) reads live state; capture mode saves what
the screen showed. Use both in tandem when a live dump helps.

## Turn it on

Mount the map screen. Press **F9** or use the **Capture** plaque at the top
right. While the mode is off, the shot and record keys do nothing. Mobile is out
of scope for v1: the mode never mounts there.

| Key | Action |
|-----|--------|
| **F9** | Toggle capture mode (always works) |
| **F10** | Screenshot (mode on) |
| **F11** | Start / stop video (mode on) |

The overlay carries the same three controls, so a mouse-only run never needs the
keyboard.

## Captures

Every finished screenshot or recording opens a comment sheet. Type what you saw
and press **Save comment**, or **Skip**. A skipped capture still lands in the
report with an empty comment.

Video is captured as a 10 fps JPEG frame sequence. When `ffmpeg` is on `PATH` it
is encoded to `video.mp4` in the background, so the UI keeps drawing. Without
`ffmpeg` the frames stay as the artifact and the report says so.

## Where it lands

Everything lives in the game cache:

```text
user://playtest_captures/
  session-2026-11-23-051317-seed1500/
    report.md
    report.json
    shot-0001.png
    video-0001/
      frame-0001.jpg ...
      video.mp4
```

Each capture carries the session parameters at the moment it was taken: map
seed, turn and year, crown, region, build and commit, platform, timestamp. The
report header carries the same bag for the session.

`report.md` is for people. `report.json` is for agents:

```json
{
  "meta": {"seed": 1500, "turn": 12, "crown": "Spain", "...": "..."},
  "entries": [
    {"kind": "screenshot", "file": "shot-0001.png",
     "comment": "Fleet stuck on the reef.", "meta": {"...": "..."}}
  ]
}
```

The folder is safe to delete. Copy it out before a cache clean if you want the
evidence.

## Filing issues

A person can read the Markdown and file a report by hand. An agent can read the
JSON and turn one entry into a GitHub issue: `todo` plus `bug` for a defect or
`enhancement` for a wish. `PlaytestReport.issue_draft(entry, meta, label)`
builds the title, body and labels; review it before filing.

The companion project skill
[`playtest-capture`](../.agents/skills/playtest-capture/SKILL.md) walks an agent
through the whole loop: toggle, capture, comment, locate the report, file.

## Tests

`tests/test_playtest_capture.gd` covers the metadata bag, the report shapes,
issue drafts, the overlay's mode/comment chrome and the controller's toggle and
comment state. Viewport grabs and `ffmpeg` are exercised by hand on desktop.
