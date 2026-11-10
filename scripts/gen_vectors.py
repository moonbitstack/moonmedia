#!/usr/bin/env python3
# Copyright 2026 Leo Cheng
# SPDX-License-Identifier: Apache-2.0
"""Regenerate the reference vectors under `src/`, from ffmpeg and MP4Box.

The tests replay media that somebody else produced: ffmpeg's muxers and GPAC's
packager. This script is how those bytes were made, so a reader can see the
exact commands instead of trusting a comment. It is run by hand, never by CI:
the vectors are committed, and CI only replays them.

    python3 scripts/gen_vectors.py

Both tools have to be present. ffmpeg and ffprobe come from PATH, or from
`--ffmpeg-dir`. MP4Box and gpac come from PATH, or from `--gpac-dir`, or from a
WSL distribution named with `--wsl`.

Besides the bytes, each vector carries what the tools say about them: ffprobe's
reading of a file, written as one line per fact. The tests render the same lines
out of this library's model and compare the two, so a mismatch shows both
readings side by side.
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

FFMPEG_VERSION = "8.1.1"
GPAC_VERSION = "2.4"

# One second of a test pattern and a sine wave: long enough to hold two key
# frame intervals, short enough that the bytes fit in a test file.
SOURCE_ARGS = [
    "-f", "lavfi", "-i", "testsrc2=size=32x32:rate=8",
    "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=8000",
    "-t", "1",
    "-c:v", "libx264", "-preset", "veryslow", "-profile:v", "baseline",
    "-g", "4", "-keyint_min", "4", "-sc_threshold", "0",
    "-pix_fmt", "yuv420p", "-crf", "40",
    "-c:a", "aac", "-b:a", "6k", "-ac", "1",
    # No encoder name and no build date: the bytes depend on the picture only.
    "-fflags", "+bitexact", "-flags", "+bitexact",
]

# The stream types ISO/IEC 13818-1 gives the codecs ffprobe names, so a
# programme map and a probe can be compared as numbers.
STREAM_TYPE = {"h264": 0x1B, "aac": 0x0F, "mp2": 0x03, "mp3": 0x04}


class Tools:
    """The external programs, and how to run them on this machine."""

    def __init__(self, ffmpeg_dir: str | None, gpac_dir: str | None, wsl: str | None):
        self.ffmpeg = self._which("ffmpeg", ffmpeg_dir)
        self.ffprobe = self._which("ffprobe", ffmpeg_dir)
        self.mp4box = self._gpac("MP4Box", gpac_dir, wsl)
        self.gpac = self._gpac("gpac", gpac_dir, wsl)

    @staticmethod
    def _which(name: str, directory: str | None) -> list[str]:
        if directory:
            suffix = ".exe" if sys.platform == "win32" else ""
            candidate = Path(directory) / (name + suffix)
            if candidate.exists():
                return [str(candidate)]
        found = shutil.which(name)
        if not found:
            raise SystemExit(f"{name} is not on PATH; pass --ffmpeg-dir")
        return [found]

    @staticmethod
    def _gpac(name: str, directory: str | None, wsl: str | None) -> list[str]:
        if wsl:
            program = f"{directory}/{name}" if directory else name
            return ["wsl", "-d", wsl, "-e", program]
        if directory:
            return [str(Path(directory) / name)]
        found = shutil.which(name)
        if found:
            return [found]
        raise SystemExit(
            f"{name} is not on PATH; pass --gpac-dir, or --wsl with a distribution "
            "that has GPAC built in it"
        )


def wsl_path(path: Path) -> str:
    text = str(path.resolve()).replace("\\", "/")
    if len(text) > 1 and text[1] == ":":
        return "/mnt/" + text[0].lower() + text[2:]
    return text


def run(argv: list[str], cwd: Path, merge: bool = False) -> str:
    """Run a program in `cwd`, where paths in `argv` are relative to it.

    `merge` folds the diagnostics into the answer: the packagers say what they
    are on standard error, and a successful probe of one has nothing else to
    say.
    """
    command = list(argv)
    if command[0] == "wsl":
        # A distribution sees the work directory through /mnt, and every
        # argument is a relative name, so only the directory has to move.
        where = wsl_path(cwd)
        inner = " ".join(command[4:])
        command = command[:4] + ["bash", "-lc", f"cd '{where}' && {inner}"]
    done = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    if done.returncode != 0:
        sys.stderr.write(done.stdout + done.stderr)
        raise SystemExit(f"failed: {' '.join(argv)}")
    if merge:
        return done.stdout + done.stderr
    return done.stdout


def probe(tools: Tools, cwd: Path, name: str) -> dict:
    text = run(
        tools.ffprobe
        + [
            "-v", "error",
            "-show_streams",
            "-show_programs",
            "-show_packets",
            "-show_format",
            "-of", "json",
            name,
        ],
        cwd,
    )
    return json.loads(text)


def packets_of(data: dict, index: int) -> list[dict]:
    out = []
    for packet in data.get("packets", []):
        if packet.get("stream_index") != index:
            continue
        out.append(
            {
                "dts": packet.get("dts", 0),
                "pts": packet.get("pts", 0),
                "duration": packet.get("duration", 0),
                "key": "K" in packet.get("flags", ""),
            }
        )
    return out


def timescale_of(stream: dict) -> int:
    return int(stream["time_base"].split("/")[1])


def number(value) -> int:
    """A field ffprobe writes as an int or as a hexadecimal string."""
    if isinstance(value, int):
        return value
    return int(value, 16) if value.startswith("0x") else int(value)


def mp4_facts(tools: Tools, cwd: Path, name: str) -> str:
    """A movie as ffprobe reads it: its tracks and every frame in them."""
    data = probe(tools, cwd, name)
    lines = [f"bytes {(cwd / name).stat().st_size}"]
    for stream in data.get("streams", []):
        kind = stream.get("codec_type", "other")
        if kind not in ("video", "audio"):
            continue
        packets = packets_of(data, stream["index"])
        ticks = sum(number(packet.get("duration", 0)) for packet in packets)
        lines.append(
            "stream %s %s %dx%d timescale %d ticks %d"
            % (
                kind,
                stream.get("codec_tag_string", ""),
                int(stream.get("width", 0)),
                int(stream.get("height", 0)),
                timescale_of(stream),
                ticks,
            )
        )
        for index, packet in enumerate(packets):
            lines.append(
                "  %d dts %d pts %d%s"
                % (index, packet["dts"], packet["pts"], " key" if packet["key"] else "")
            )
    return "\n".join(lines)


def ts_facts(tools: Tools, cwd: Path, name: str) -> str:
    """A transport stream as ffprobe reads it: its programme and its frames."""
    data = probe(tools, cwd, name)
    size = (cwd / name).stat().st_size
    lines = [f"bytes {size}", f"packets {size // 188}"]
    for program in data.get("programs", []):
        lines.append(f"program {program['program_id']} pmt {number(program['pmt_pid'])}")
        for stream in program.get("streams", []):
            codec = stream.get("codec_name", "")
            packets = packets_of(data, stream["index"])
            # The bytes of the elementary stream and the instant it starts: a
            # packetised stream carries packets of it, and how many access units
            # fit in one is the codec's business, so the frame boundaries ffprobe
            # reports are not something a demuxer of packets can be asked for.
            payload = sum(int(packet.get("size", 0)) for packet in data.get("packets", [])
                          if packet.get("stream_index") == stream["index"])
            lines.append(
                "stream %d type %d payload %d first_pts %d"
                % (
                    number(stream["id"]),
                    STREAM_TYPE.get(codec, 0),
                    payload,
                    packets[0]["pts"] if packets else 0,
                )
            )
    return "\n".join(lines)


def playlist_facts(tools: Tools, cwd: Path, names: list[str], init: str | None) -> str:
    """What a playlist names, and how long the media it names lasts.

    The names come from the packager's directory; the length comes from reading
    the pieces the way a player does, with the initialisation section in front
    of the fragments.
    """
    lines = []
    if init:
        lines.append(f"init {Path(init).name}")
    for index, name in enumerate(names):
        lines.append(f"segment {index} uri {Path(name).name}")
    joined = cwd / "joined.mp4"
    body = b""
    if init:
        body += (cwd / init).read_bytes()
    for name in names:
        body += (cwd / name).read_bytes()
    joined.write_bytes(body)
    data = probe(tools, cwd, joined.name)
    lines.append(f"total_ms {round(float(data['format'].get('duration', 0.0)) * 1000)}")
    return "\n".join(lines)


def file_facts(cwd: Path, directory: str) -> str:
    """A directory of segments by name, as the packager left it."""
    names = sorted(path.name for path in (cwd / directory).iterdir() if path.is_file())
    return "\n".join("file " + name for name in names)


def b64(text: bytes) -> list[str]:
    encoded = base64.b64encode(text).decode("ascii")
    return [encoded[i : i + 76] for i in range(0, len(encoded), 76)]


def moonbit_string(name: str, payload: bytes, comment: str) -> list[str]:
    lines = ["///|", f"/// {comment}", f"let {name} : String ="]
    for chunk in b64(payload):
        lines.append(f"  #|{chunk}")
    lines.append("")
    return lines


def moonbit_text(name: str, payload: str, comment: str) -> list[str]:
    lines = ["///|", f"/// {comment}", f"let {name} : String ="]
    for line in payload.splitlines():
        lines.append("  #|" + line)
    lines.append("")
    return lines


HEADER = """// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Generated by `scripts/gen_vectors.py`; do not edit by hand. What the tests
// replay is what another implementation wrote, so the facts beside each
// payload are the tool's answer, not this library's.
"""


def write(
    out: Path,
    package: str,
    filename: str,
    tool: str,
    commands: list[str],
    body: list[str],
) -> None:
    path = out / "src" / package / filename
    lines = [HEADER, "//", f"// {tool}", "//"]
    for command in commands:
        lines.append("//   " + command)
    lines.append("")
    lines.extend(body)
    while lines and lines[-1] == "":
        lines.pop()
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {path.relative_to(out)}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ffmpeg-dir", help="directory holding ffmpeg and ffprobe")
    parser.add_argument("--gpac-dir", help="directory holding MP4Box and gpac")
    parser.add_argument("--wsl", help="run MP4Box and gpac in this WSL distribution")
    parser.add_argument("--out", default=".", help="root of the repository")
    options = parser.parse_args()

    out = Path(options.out).resolve()
    tools = Tools(options.ffmpeg_dir, options.gpac_dir, options.wsl)
    ffmpeg_version = run(tools.ffmpeg + ["-version"], out).splitlines()[0].split()[2]
    mp4box_version = run(tools.mp4box + ["-version"], out, merge=True).splitlines()[0]
    print(f"ffmpeg {ffmpeg_version}")
    print(mp4box_version)
    if not ffmpeg_version.startswith(FFMPEG_VERSION):
        print(f"  warning: the vectors were made with ffmpeg {FFMPEG_VERSION}")
    if GPAC_VERSION not in mp4box_version:
        print(f"  warning: the vectors were made with GPAC {GPAC_VERSION}")

    work = Path(tempfile.mkdtemp(prefix="moonmedia-vectors-"))
    try:
        build(out, work, tools, ffmpeg_version, mp4box_version)
    finally:
        shutil.rmtree(work, ignore_errors=True)


def build(out: Path, work: Path, tools: Tools, ffmpeg_version: str, mp4box_version: str) -> None:
    ffmpeg = tools.ffmpeg
    source = "source.mp4"
    for directory in ("hls", "cmaf", "dash", "gpac_live", "gpac_on_demand", "gpac_hls"):
        (work / directory).mkdir()

    # ffmpeg -----------------------------------------------------------------
    ffmpeg_commands = [
        "ffmpeg -f lavfi -i testsrc2=size=32x32:rate=8 -f lavfi -i sine=frequency=440:sample_rate=8000"
        " -t 1 -c:v libx264 -preset veryslow -profile:v baseline -g 4 -keyint_min 4 -sc_threshold 0"
        " -pix_fmt yuv420p -crf 40 -c:a aac -b:a 6k -ac 1 -fflags +bitexact -flags +bitexact"
        " -movflags +faststart source.mp4",
    ]
    run(ffmpeg + ["-hide_banner", "-loglevel", "error", "-y"] + SOURCE_ARGS
        + ["-movflags", "+faststart", source], work)

    run(ffmpeg + ["-hide_banner", "-loglevel", "error", "-y", "-i", source, "-c", "copy",
                  "-fflags", "+bitexact", "-flags", "+bitexact",
                  "-movflags", "frag_keyframe+empty_moov+default_base_moof",
                  "fragmented.mp4"], work)
    ffmpeg_commands.append(
        "ffmpeg -i source.mp4 -c copy -movflags frag_keyframe+empty_moov+default_base_moof fragmented.mp4"
    )

    run(ffmpeg + ["-hide_banner", "-loglevel", "error", "-y", "-i", source, "-c", "copy",
                  "-fflags", "+bitexact", "-flags", "+bitexact",
                  "-f", "mpegts", "stream.ts"], work)
    ffmpeg_commands.append("ffmpeg -i source.mp4 -c copy -f mpegts stream.ts")

    run(ffmpeg + ["-hide_banner", "-loglevel", "error", "-y", "-i", source, "-c", "copy",
                  "-f", "hls", "-hls_time", "0.5", "-hls_list_size", "0",
                  "-hls_segment_type", "mpegts",
                  "-hls_segment_filename", "hls/segment%d.ts", "hls/media.m3u8"], work)
    ffmpeg_commands.append(
        "ffmpeg -i source.mp4 -c copy -f hls -hls_time 0.5 -hls_list_size 0"
        " -hls_segment_type mpegts -hls_segment_filename hls/segment%d.ts hls/media.m3u8"
    )

    run(ffmpeg + ["-hide_banner", "-loglevel", "error", "-y", "-i", source, "-c", "copy",
                  "-f", "hls", "-hls_time", "0.5", "-hls_list_size", "0",
                  "-hls_segment_type", "fmp4",
                  "-hls_fmp4_init_filename", "init.mp4",
                  "-hls_segment_filename", "cmaf/segment%d.m4s", "cmaf/media.m3u8"], work)
    ffmpeg_commands.append(
        "ffmpeg -i source.mp4 -c copy -f hls -hls_time 0.5 -hls_list_size 0"
        " -hls_segment_type fmp4 -hls_fmp4_init_filename init.mp4"
        " -hls_segment_filename cmaf/segment%d.m4s cmaf/media.m3u8"
    )

    run(ffmpeg + ["-hide_banner", "-loglevel", "error", "-y", "-i", source, "-c", "copy",
                  "-f", "dash", "-seg_duration", "0.5", "-use_template", "1",
                  "-use_timeline", "1", "dash/manifest.mpd"], work)
    ffmpeg_commands.append(
        "ffmpeg -i source.mp4 -c copy -f dash -seg_duration 0.5 -use_template 1"
        " -use_timeline 1 dash/manifest.mpd"
    )

    # GPAC -------------------------------------------------------------------
    gpac_commands = [
        "MP4Box -dash 500 -frag 250 -rap -profile live -out gpac_live/manifest.mpd source.mp4",
        "MP4Box -dash 500 -frag 250 -rap -profile onDemand -out gpac_on_demand/manifest.mpd source.mp4",
        "MP4Box -dash 500 -profile live -out gpac_hls/master.m3u8 source.mp4",
        "gpac -i source.mp4 -o stream_gpac.ts",
    ]
    run(tools.mp4box + ["-dash", "500", "-frag", "250", "-rap", "-profile", "live",
                        "-out", "gpac_live/manifest.mpd", source], work)
    run(tools.mp4box + ["-dash", "500", "-frag", "250", "-rap", "-profile", "onDemand",
                        "-out", "gpac_on_demand/manifest.mpd", source], work)
    run(tools.mp4box + ["-dash", "500", "-profile", "live",
                        "-out", "gpac_hls/master.m3u8", source], work)
    run(tools.gpac + ["-i", source, "-o", "stream_gpac.ts"], work)

    # The examples -----------------------------------------------------------
    # The interchange check runs a program that has to start from a movie
    # nobody has on disk, so the clip the vectors are made from comes with it.
    clip = work / source
    example = out / "src" / "examples" / "07-emit-package" / "clip.mbt"
    example.write_text(
        "\n".join(
            [
                HEADER.rstrip(),
                "//",
                "// The clip the package is cut from: one second of a test pattern and a",
                "// sine wave, as ffmpeg wrote it. `scripts/check_interop.py` reads what the",
                "// example makes of it and hands it to ffmpeg.",
                "",
            ]
            + moonbit_string("clip", clip.read_bytes(), "The movie, base64 encoded.")
        ).rstrip()
        + "\n",
        encoding="utf-8",
    )
    print(f"wrote {example.relative_to(out)}")

    # mp4 --------------------------------------------------------------------
    body = moonbit_string("ffmpeg_progressive_movie", (work / source).read_bytes(),
                          "A movie ffmpeg muxed with its sample table up front.")
    body += moonbit_text("ffmpeg_progressive_facts", mp4_facts(tools, work, source),
                         "What ffprobe reads out of it: the tracks and every frame.")
    body += moonbit_string("ffmpeg_fragmented_movie", (work / "fragmented.mp4").read_bytes(),
                           "The same movie fragmented: an empty movie header and one fragment per key frame.")
    body += moonbit_text("ffmpeg_fragmented_facts", mp4_facts(tools, work, "fragmented.mp4"),
                         "What ffprobe reads out of the fragmented file.")
    write(out, "mp4", "vectors_ffmpeg_test.mbt", f"ffmpeg {ffmpeg_version}", ffmpeg_commands, body)

    init_name = next((work / "gpac_hls").glob("*init.mp4")).name
    segments = sorted(path.name for path in (work / "gpac_hls").glob("*.m4s"))
    init_bytes = (work / "gpac_hls" / init_name).read_bytes()
    first = (work / "gpac_hls" / segments[0]).read_bytes()
    second = (work / "gpac_hls" / segments[1]).read_bytes()
    body = moonbit_string("gpac_cmaf_init", init_bytes,
                          "The initialisation section MP4Box wrote for an HLS rendition.")
    body += moonbit_string("gpac_cmaf_first", first, "The first segment MP4Box wrote.")
    body += moonbit_string("gpac_cmaf_second", second, "The second segment MP4Box wrote.")
    (work / "gpac_cmaf.mp4").write_bytes(init_bytes + first + second)
    body += moonbit_text("gpac_cmaf_facts", mp4_facts(tools, work, "gpac_cmaf.mp4"),
                         "The init section and both segments, as ffprobe reads the stream they make.")
    write(out, "mp4", "vectors_gpac_test.mbt", mp4box_version, gpac_commands, body)

    # ts ---------------------------------------------------------------------
    body = moonbit_string("ffmpeg_stream", (work / "stream.ts").read_bytes(),
                          "A transport stream ffmpeg wrote from the same movie.")
    body += moonbit_text("ffmpeg_stream_facts", ts_facts(tools, work, "stream.ts"),
                         "What ffprobe reads out of it: the programme, its streams and their frames.")
    write(out, "ts", "vectors_ffmpeg_test.mbt", f"ffmpeg {ffmpeg_version}", ffmpeg_commands, body)

    body = moonbit_string("gpac_stream", (work / "stream_gpac.ts").read_bytes(),
                          "A transport stream GPAC wrote from the same movie.")
    body += moonbit_text("gpac_stream_facts", ts_facts(tools, work, "stream_gpac.ts"),
                         "What ffprobe reads out of the GPAC stream.")
    write(out, "ts", "vectors_gpac_test.mbt", mp4box_version, gpac_commands, body)

    # m3u8 -------------------------------------------------------------------
    body = moonbit_text("ffmpeg_media_playlist",
                        (work / "hls" / "media.m3u8").read_text(encoding="utf-8"),
                        "The media playlist ffmpeg wrote, naming its transport stream segments.")
    body += moonbit_text(
        "ffmpeg_media_playlist_facts",
        playlist_facts(tools, work, ["hls/segment0.ts", "hls/segment1.ts"], init=None),
        "The segments it names, and how long they play.",
    )
    body += moonbit_text("ffmpeg_fmp4_playlist",
                         (work / "cmaf" / "media.m3u8").read_text(encoding="utf-8"),
                         "The media playlist ffmpeg wrote for fragmented MP4 segments.")
    body += moonbit_text(
        "ffmpeg_fmp4_playlist_facts",
        playlist_facts(tools, work, ["cmaf/segment0.m4s", "cmaf/segment1.m4s"],
                       init="cmaf/init.mp4"),
        "The initialisation section and the segments it names, and how long they play.",
    )
    write(out, "m3u8", "vectors_ffmpeg_test.mbt", f"ffmpeg {ffmpeg_version}", ffmpeg_commands, body)

    master_name = "master.m3u8"
    master_text = (work / "gpac_hls" / master_name).read_text(encoding="utf-8")
    media_name = next(
        line.strip()
        for line in master_text.splitlines()
        if line.strip() and not line.startswith("#")
    )
    body = moonbit_text("gpac_master_playlist", master_text,
                        "The master playlist MP4Box wrote.")
    body += moonbit_text("gpac_media_playlist",
                         (work / "gpac_hls" / media_name).read_text(encoding="utf-8"),
                         "The media playlist it points at.")
    body += moonbit_text(
        "gpac_playlist_facts",
        playlist_facts(
            tools, work,
            [f"gpac_hls/{name}" for name in segments],
            init=f"gpac_hls/{init_name}",
        ),
        "The initialisation section and the segments the media playlist names, and how long they play.",
    )
    write(out, "m3u8", "vectors_gpac_test.mbt", mp4box_version, gpac_commands, body)

    # mpd --------------------------------------------------------------------
    body = moonbit_text("ffmpeg_manifest",
                        (work / "dash" / "manifest.mpd").read_text(encoding="utf-8"),
                        "The MPD ffmpeg wrote: a template with a segment timeline.")
    body += moonbit_text("ffmpeg_manifest_facts", file_facts(work, "dash"),
                         "The files it wrote beside the manifest, which its template has to name.")
    write(out, "mpd", "vectors_ffmpeg_test.mbt", f"ffmpeg {ffmpeg_version}", ffmpeg_commands, body)

    body = moonbit_text("gpac_live_manifest",
                        (work / "gpac_live" / "manifest.mpd").read_text(encoding="utf-8"),
                        "The MPD MP4Box wrote for the live profile: a template with a duration.")
    body += moonbit_text("gpac_live_manifest_facts", file_facts(work, "gpac_live"),
                         "The files it wrote beside the manifest, which its template has to name.")
    body += moonbit_text("gpac_on_demand_manifest",
                         (work / "gpac_on_demand" / "manifest.mpd").read_text(encoding="utf-8"),
                         "The MPD MP4Box wrote for the on-demand profile: one file addressed by byte range.")
    on_demand = sorted((work / "gpac_on_demand").glob("*.mp4"))[0]
    body += moonbit_text(
        "gpac_on_demand_manifest_facts",
        f"file {on_demand.name} bytes {on_demand.stat().st_size}",
        "The one file it addresses.",
    )
    write(out, "mpd", "vectors_gpac_test.mbt", mp4box_version, gpac_commands, body)


if __name__ == "__main__":
    main()
