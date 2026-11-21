"""Ask ElevenLabs Music for any bed the manifest lists but has no master for.

    python tools/audio/generate_elevenlabs.py            # fill every gap
    python tools/audio/generate_elevenlabs.py --only court,research

Reads ``tools/audio/elevenlabs_music.json``, posts each track's prompt to
``/v1/music/detailed`` at the best MP3 container the Music API offers
(192 kbps), writes ``tools/audio/masters/<id>.mp3`` and records the returned
song id beside the prompt. Run ``finish_elevenlabs.py`` afterwards to trim,
loop-crossfade, normalise and encode the shipped Ogg beds.

Needs ``ELEVENLABS_API_KEY``. Billed by length: it prints each request's
seconds so the total is visible before and after.
"""

from __future__ import annotations

import argparse
import json
import os
import ssl
import threading
import time
import urllib.error
import urllib.request

API = "https://api.elevenlabs.io"
OUTPUT_FORMAT = "mp3_44100_192"
MODEL = "music_v2_5"
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MANIFEST = os.path.join(ROOT, "tools", "audio", "elevenlabs_music.json")


class Failure(RuntimeError):
    pass


def split_multipart(body: bytes, content_type: str) -> tuple[dict, bytes]:
    """(metadata, audio) from ``/v1/music/detailed``'s multipart/mixed reply."""
    boundary = ""
    for part in content_type.split(";"):
        if part.strip().lower().startswith("boundary="):
            boundary = part.split("=", 1)[1].strip().strip('"')
    if not boundary:
        raise Failure("no multipart boundary in %r" % content_type)
    metadata: dict = {}
    audio = b""
    for part in body.split(b"--" + boundary.encode("latin-1")):
        if part.startswith(b"--") or b"\r\n\r\n" not in part:
            continue
        head, _, content = part.lstrip(b"\r\n").partition(b"\r\n\r\n")
        if content.endswith(b"\r\n"):
            content = content[:-2]
        kind = ""
        for line in head.decode("latin-1").split("\r\n"):
            name, _, value = line.partition(":")
            if name.strip().lower() == "content-type":
                kind = value.strip().lower()
        if kind.startswith("application/json"):
            metadata = json.loads(content)
        elif kind.startswith("audio/"):
            audio = content
    if not audio:
        raise Failure("reply held no audio part")
    return metadata, audio


def _context() -> ssl.SSLContext:
    """Verifying TLS context. A framework Python on macOS often has no CA bundle
    of its own, so borrow certifi's when it is installed."""
    try:
        import certifi
    except ImportError:
        return ssl.create_default_context()
    return ssl.create_default_context(cafile=certifi.where())


def generate(track: dict, api_key: str) -> dict:
    body = {
        "prompt": track["prompt"],
        "model_id": track.get("model", MODEL),
        "music_length_ms": int(round(float(track["seconds"]) * 1000)),
        "force_instrumental": True,
    }
    request = urllib.request.Request(
        "%s/v1/music/detailed?output_format=%s" % (API, OUTPUT_FORMAT),
        data=json.dumps(body).encode("utf-8"),
        headers={"xi-api-key": api_key, "content-type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=600, context=_context()) as response:
            body_bytes = response.read()
            content_type = response.headers.get("content-type", "")
            song_id = response.headers.get("song-id", "")
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:400]
        raise Failure("HTTP %d: %s" % (error.code, detail)) from None
    metadata, audio = split_multipart(body_bytes, content_type)
    return {"metadata": metadata, "audio": audio, "song_id": song_id}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", default=MANIFEST)
    parser.add_argument("--only", default="", help="comma-separated track ids")
    parser.add_argument("--force", action="store_true", help="regenerate existing masters")
    parser.add_argument("--workers", type=int, default=2)
    args = parser.parse_args()

    api_key = os.environ.get("ELEVENLABS_API_KEY", "")
    if not api_key:
        print("ELEVENLABS_API_KEY is not set")
        return 2
    path = os.path.abspath(args.manifest)
    manifest = json.load(open(path))
    wanted = {part.strip() for part in args.only.split(",") if part.strip()}
    base = os.path.dirname(path)

    todo = []
    for track in manifest["tracks"]:
        if wanted and track["id"] not in wanted and track.get("theme") not in wanted:
            continue
        master = os.path.join(base, track.get("master", ""))
        if os.path.exists(master) and not args.force:
            print("  %-24s master exists" % track["id"])
            continue
        if not track.get("prompt"):
            print("  %-24s no prompt, skipped" % track["id"])
            continue
        todo.append(track)

    if not todo:
        print("nothing to generate")
        return 0
    print("generating %d bed(s), %.0f s of music" % (len(todo), sum(float(t["seconds"]) for t in todo)))

    lock = threading.Lock()
    failures: list[str] = []

    def work(track: dict) -> None:
        started = time.time()
        result = None
        for attempt in range(4):
            try:
                result = generate(track, api_key)
                break
            except Failure as error:
                # The plan allows two concurrent songs; a third waits its turn.
                if "HTTP 429" in str(error) and attempt < 3:
                    time.sleep(20.0 * (attempt + 1))
                    continue
                with lock:
                    failures.append(track["id"])
                print("  %-24s FAILED %s" % (track["id"], error))
                return
            except OSError as error:
                with lock:
                    failures.append(track["id"])
                print("  %-24s FAILED %s" % (track["id"], error))
                return
        if result is None:
            return
        master = os.path.join(base, track["master"])
        os.makedirs(os.path.dirname(master), exist_ok=True)
        with open(master, "wb") as handle:
            handle.write(result["audio"])
        song = result["metadata"].get("song_metadata") or {}
        with lock:
            if result["song_id"]:
                track["song_id"] = result["song_id"]
            if song.get("title"):
                track["title"] = song["title"]
            json.dump(manifest, open(path, "w"), indent=2, ensure_ascii=False)
            open(path, "a").write("\n")
            print("  %-24s %.1f KB in %.0fs  song %s" % (
                track["id"], len(result["audio"]) / 1024.0, time.time() - started,
                track["song_id"]))

    threads: list[threading.Thread] = []
    for track in todo:
        thread = threading.Thread(target=work, args=(track,), daemon=True)
        thread.start()
        threads.append(thread)
        while sum(1 for t in threads if t.is_alive()) >= max(1, args.workers):
            time.sleep(0.5)
    for thread in threads:
        thread.join()
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
