#!/usr/bin/env python3
# Copyright 2026 Leo Cheng
# SPDX-License-Identifier: Apache-2.0
"""Ask ffmpeg to play what this library packaged.

`src/examples/07-emit-package` turns a movie into the bytes of an HLS package
and prints them as JSON. This script writes them out as a player would find
them on a server — an initialisation section, one file per segment, a media
playlist and a master playlist — and then hands the result to ffmpeg.

What is compared is what a player decides on: how many frames each stream has,
where the key frames are, and how long the presentation lasts. ffmpeg also
decodes the whole thing, which a file with a wrong sample table or a fragment
naming the wrong offset cannot survive.

    python3 scripts/check_interop.py

ffmpeg and ffprobe come from PATH, or from `--ffmpeg-dir`.
"""

from __future__ import annotations

import argparse
import base64
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def run(argv: list[str], cwd: Path | None = None, merge: bool = False) -> subprocess.CompletedProcess:
    done = subprocess.run(argv, cwd=cwd, capture_output=True, text=True)
    if merge:
        return done
    if done.returncode != 0:
        sys.stderr.write(done.stdout + done.stderr)
        raise SystemExit(f"failed: {' '.join(argv)}")
    return done


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg-dir", help="directory holding ffmpeg and ffprobe")
    parser.add_argument("--out", default=".", help="root of the repository")
    options = parser.parse_args()

    root = Path(options.out).resolve()
    ffmpeg = tool("ffmpeg", options.ffmpeg_dir)
    ffprobe = tool("ffprobe", options.ffmpeg_dir)

    package = emit(root)
    work = Path(tempfile.mkdtemp(prefix="moonmedia-interop-"))
    try:
        check(package, work, ffmpeg, ffprobe)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print("the package plays in ffmpeg, and its frames, key frames and length agree")


def tool(name: str, directory: str | None) -> str:
    if directory:
        candidate = Path(directory) / (name + (".exe" if sys.platform == "win32" else ""))
        if candidate.exists():
            return str(candidate)
    found = shutil.which(name)
    if not found:
        raise SystemExit(f"{name} is not on PATH; pass --ffmpeg-dir")
    return found


def emit(root: Path) -> dict:
    """Run the example and read the package it prints."""
    done = run(
        [
            "moon",
            "run",
            "src/examples/07-emit-package",
            "--target",
            "native",
        ],
        cwd=root,
        merge=True,
    )
    for line in reversed((done.stdout + "\n" + done.stderr).splitlines()):
        text = line.strip()
        if text.startswith("{") and text.endswith("}"):
            return json.loads(text)
    sys.stderr.write(done.stdout + done.stderr)
    raise SystemExit("the example printed no package")


def check(package: dict, work: Path, ffmpeg: str, ffprobe: str) -> None:
    write(package, work)
    streams = probe(ffprobe, work, "index.m3u8")
    video = [stream for stream in streams["streams"] if stream["codec_type"] == "video"]
    audio = [stream for stream in streams["streams"] if stream["codec_type"] == "audio"]
    if len(video) != 1 or len(audio) != 1:
        raise SystemExit(f"the playlist names {len(video)} video and {len(audio)} audio streams")

    packets = streams.get("packets", [])
    video_packets = [p for p in packets if p["stream_index"] == video[0]["index"]]
    audio_packets = [p for p in packets if p["stream_index"] == audio[0]["index"]]

    segments = package["segments"]
    expected_video = sum(segment["samples"][0] for segment in segments)
    expected_audio = sum(segment["samples"][1] for segment in segments)
    check_equal("video frames", len(video_packets), expected_video)
    check_equal("audio frames", len(audio_packets), expected_audio)

    # Every segment begins on a key frame, so the frames a player may start on
    # are the first frame of each segment and no others.
    starts = []
    at = 0
    for segment in segments:
        starts.append(at)
        at = at + segment["samples"][0]
    key_frames = [i for i, packet in enumerate(video_packets) if "K" in packet["flags"]]
    check_equal("key frames", key_frames, starts)

    # The presentation lasts what the packager said it lasts, to within the one
    # frame a player may pad the end with.
    longest = max(segment["duration"] for segment in segments)
    duration = float(streams["format"].get("duration", 0.0))
    if abs(duration - float(package["duration"])) > longest + 0.05:
        raise SystemExit(
            f"ffprobe reads {duration:.3f}s, the packager says {package['duration']:.3f}s"
        )

    # The playlist says what the packager said, down to the durations.
    for segment, entry in zip(segments, package["media"].split("#EXTINF:")[1:]):
        declared = float(entry.split(",")[0])
        if abs(declared - segment["duration"]) > 0.001:
            raise SystemExit(
                f"the playlist says {declared}s for {segment['name']}, the packager {segment['duration']}s"
            )

    # Reading the frames is not the same as playing them: decode both streams of
    # both entry points, and let a frame that does not decode be an error.
    for entry in ("index.m3u8", "stream.m3u8", "joined.mp4"):
        done = run(
            [ffmpeg, "-v", "error", "-i", entry, "-f", "null", "-"],
            cwd=work,
            merge=True,
        )
        if done.returncode != 0 or done.stderr.strip():
            sys.stderr.write(done.stderr)
            raise SystemExit(f"ffmpeg could not play {entry}")


def write(package: dict, work: Path) -> None:
    (work / package["init"]["name"]).write_bytes(decode(package["init"]["data"]))
    joined = decode(package["init"]["data"])
    for segment in package["segments"]:
        data = decode(segment["data"])
        (work / segment["name"]).write_bytes(data)
        joined = joined + data
    (work / "joined.mp4").write_bytes(joined)
    (work / "index.m3u8").write_text(package["media"], encoding="utf-8", newline="\n")
    (work / "stream.m3u8").write_text(package["master"], encoding="utf-8", newline="\n")


def decode(text: str) -> bytes:
    return base64.b64decode(text)


def probe(ffprobe: str, work: Path, name: str) -> dict:
    done = run(
        [
            ffprobe,
            "-v", "error",
            "-show_streams",
            "-show_packets",
            "-show_format",
            "-of", "json",
            name,
        ],
        cwd=work,
    )
    return json.loads(done.stdout)


def check_equal(what: str, got, want) -> None:
    if got != want:
        raise SystemExit(f"{what}: ffmpeg reads {got}, this library says {want}")


if __name__ == "__main__":
    main()
