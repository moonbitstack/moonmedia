---
name: moonmedia
description: "HLS, DASH, MPEG-TS, fragmented MP4 and RTMP for MoonBit, all of it bytes in and bytes out: read and write playlists, walk a container, cut a movie into segments, take a publisher's stream. Use it when a task involves an m3u8, an MPD, an MP4 or a transport stream, or an RTMP ingest, and the caller owns the socket and the files."
---

# moonmedia

`moon add moonbitstack/moonmedia`, then import the package you need: `moonbitstack/moonmedia/m3u8`
for playlists, `moonbitstack/moonmedia/mp4` for ISO base media, `moonbitstack/moonmedia/ts` for
transport streams, `moonbitstack/moonmedia/mpd` for DASH manifests, `moonbitstack/moonmedia/rtmp`
for ingest, and `moonbitstack/moonmedia` itself for the packager that ties them together.

Nothing here opens a socket, reads a file or decodes a frame. A format takes the bytes your program
already has and gives back a model; writing it gives bytes back. That is what makes the same code
usable behind a range request, in a command-line tool and in a test.

## Read a playlist, and write one back

`Playlist::parse` decides by itself whether the text is a master or a media playlist. A tag applies
to the segments after it until it is replaced, and every segment carries the key and the
initialisation section that were in force where it appears.

```mbt check
test {
  let source =
    #|#EXTM3U
    #|#EXT-X-VERSION:7
    #|#EXT-X-TARGETDURATION:6
    #|#EXT-X-MAP:URI="init.mp4"
    #|#EXTINF:6,
    #|segment0.m4s
    #|#EXTINF:4.004,
    #|segment1.m4s
    #|#EXT-X-ENDLIST
  let media = @m3u8.Playlist::parse(source).media().unwrap()
  assert_eq(media.target_duration, 6)
  assert_eq(media.segments.length(), 2)
  assert_eq(media.segments[1].duration, 4.004)
  assert_eq(media.segments[1].map.unwrap().uri, "init.mp4")
}
```

Building one is the same model, filled in and encoded. `MediaPlaylist::new` takes the target
duration and nothing else, because it is the only tag RFC 8216 requires to be present:

```mbt check
test {
  let media = @m3u8.MediaPlaylist::new(6)
  media.version = Some(7)
  media.playlist_type = Some(@m3u8.PlaylistType::Vod)
  media.end_list = true
  let init = @m3u8.InitSection::new("init.mp4")
  let segment = @m3u8.Segment::new("segment0.m4s", 6.0)
  segment.map = Some(init)
  media.segments.push(segment)
  assert_eq(media.encode().contains("#EXT-X-MAP:URI=\"init.mp4\""), true)
}
```

A rewrite is the same model, not the same text: tags come out in the order the specification lists
them, durations in their shortest form, and a tag this release does not know survives in `unknown`
rather than being dropped.

## Cut a movie into an HLS package

`Packager` takes a parsed movie — progressive or already fragmented — and returns the initialisation
section plus one segment per key frame interval, each with the audio that plays over it. The file
below is 698 bytes of a 64 × 64 test pattern, eight frames 400 ms apart, the first and the fifth of
them key frames; a real caller passes whatever bytes it has.

```mbt check
test {
  let packed =
    #|AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAJqbW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAD6AAA
    #|B9AAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAA
    #|AAAAAAAAAAAAAAAAAAAAAgAAAfZ0cmFrAAAAXHRraGQAAAAHAAAAAAAAAAAAAAABAAAAAAAAB9AAAAAAAAAAAAAA
    #|AAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAEAAAABAAAAAAAGSbWRpYQAAACBtZGhk
    #|AAAAAAAAAAAAAAAAAAAyAAAAB9BVxAAAAAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRs
    #|ZXIAAAABPW1pbmYAAAAUdm1oZAAAAAEAAAAAAAAAAAAAASFzdGJsAAAAhXN0c2QAAAAAAAAAAQAAAHVhdmMxAAAA
    #|AAAAAAEAAAAAAAAAAAAAAAAAAAAAAEAAQABIAAAASAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
    #|AAAAAAAAGP//AAAAH2F2Y0MBQsAK/+EACWdCwArZAPA8AQAEaM48gAAAABhzdHRzAAAAAAAAAAEAAAAIAAAMgAAA
    #|ABxzdHNjAAAAAAAAAAEAAAABAAAACAAAAAEAAAA0c3RzegAAAAAAAAAAAAAACAAAAAUAAAAFAAAABQAAAAUAAAAF
    #|AAAABQAAAAUAAAAFAAAAGHN0c3MAAAAAAAAAAgAAAAEAAAAFAAAAFHN0Y28AAAAAAAAAAQAAApIAAAAwbWRhdAAA
    #|AAFlAAAAAUEAAAABQQAAAAFBAAAAAWUAAAABQQAAAAFBAAAAAUE=
  let movie = @base64.decode(packed, ignore_whitespace=true)
  let file = @mp4.Mp4::parse(movie[:])
  assert_eq(file.boxes.map(fn(box) { box.type_ }), ["ftyp", "moov", "mdat"])
  let video = file.tracks()[0]
  assert_eq(video.codec, "avc1.42c00a")
  assert_eq(video.samples.length(), 8)

  let packager = @moonmedia.Packager::new(file, target_duration=0.5)
  assert_eq(packager.segments().length(), 2)
  assert_eq(packager.media_playlist().segments[1].duration, 1.0)
  assert_eq(packager.master_playlist(uri="index.m3u8").variants[0].bandwidth, Some(1440))
}
```

The cut falls on the first key frame at or after the target, never in the middle of a GOP, so a
segment can be longer or shorter than the target and a player seeking into one still lands on
something it can decode. Writing the segments out and answering requests for them is the caller's
job; `Packager::media_playlist(prefix=, init_name=)` decides what names the playlist uses.

## Read a transport stream

A transport stream is 188-byte packets. `parse` takes them as they are — adaptive field stuffing,
continuity counters and all — and `sections` and `pes_packets` put the payloads back into tables and
frames.

```mbt check
test {
  let pat = @ts.Pat::new(transport_stream=1, programs=[@ts.Program::new(1, 0x1000)])
  let packet = pat.section().packets(@ts.pat_pid)[0]
  let bytes = packet.encode()
  assert_eq(bytes.length(), 188)

  let packets = @ts.parse(bytes[:])
  let table = @ts.sections(packets, @ts.pat_pid)[0]
  assert_eq(table.is_intact(), true)
  assert_eq(@ts.Pat::of(table).programs[0].pid, 0x1000)

  let frame = @ts.Pes::new(
    0xE0,
    Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x01', b'\x09']),
    pts=90000L,
  )
  assert_eq(frame.pts().unwrap(), 90000L)
}
```

`Section::is_intact` recomputes the CRC-32: a table with a bit error is still parsed, so the caller
can see what it claimed, but it can also tell that the table is damaged before acting on it.

## Take a publish

`Session` is the receiving half of RTMP as a state machine: handshake, chunk size, commands, media.
Feed it whatever the connection read, send back what it returns.

```mbt check
test {
  let session = @rtmp.Session::new()
  let answer = session.push(@rtmp.client_start(0)[:])
  let _ = session.push(@rtmp.client_finish(answer[0][:])[:])

  let writer = @rtmp.ChunkWriter::new()
  let _ = session.push(writer.write(@rtmp.set_chunk_size(4096))[:])
  writer.chunk_size = 4096
  let connect = @rtmp.Message::new(
    @rtmp.msg_command,
    0,
    @rtmp.encode_all([
      @rtmp.Amf0::String("connect"),
      @rtmp.Amf0::Number(1.0),
      @rtmp.Amf0::Object([("app", @rtmp.Amf0::String("live"))]),
    ]),
  )
  assert_eq(session.push(writer.write(connect)[:]).length(), 4)
  assert_eq(session.app(), "live")

  let video = @rtmp.Message::new(
    @rtmp.msg_video,
    1,
    Bytes::from_array([b'\x17', b'\x00', b'\x00']),
  )
  let _ = session.push(writer.write(video)[:])
  assert_eq(session.take_media().length(), 1)
}
```

## Rules that catch people out

- **A session is fed, not driven.** `Session::push` returns the bytes owed to the peer right now and
  queues the media in `take_media`; a half message is kept and waits for the rest, so one byte or
  sixty kilobytes at a time both work.
- **Times stay in the format's units.** A container keeps integer ticks in the track's timescale and
  a playlist or a manifest writes seconds as the shortest text that reads back the same. Convert at
  the edge, not in the middle.
- **Unknown is kept.** Later-revision playlist tags, boxes with no name here, and chunk headers this
  release does not use all survive a read-and-write. Do not expect the bytes to match the input where
  the format allows more than one spelling — compare models, or assert on the fields.
- **A damaged stream is refused.** `@ts.parse` raises `TsError` when a packet loses its sync byte
  instead of resynchronising; a playlist raises `PlaylistError` with the line number, the value found
  and the value the grammar wanted.
- **The packager has no live window.** It cuts a file that has an end. A rolling playlist for a live
  stream is a `MediaPlaylist` the caller maintains: drop the segment that fell out, push the one that
  finished, and let `next_parts` and `preload_hint` carry the low-latency ones.
