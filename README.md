# moonmedia

Containers and playlists for segmented streaming: the bytes a player fetches, the
document that says which pieces exist, and the protocol a publisher pushes them
with. Every format is read and written from bytes, so a stream can be inspected,
cut and repackaged without a socket or a file anywhere in the library.

- **`mp4`** — ISO base media files and fragments, read and written back byte for
  byte, with the sample tables walked into frames.
- **`m3u8`** — HLS playlists: master and media, every tag of RFC 8216, and the
  low-latency tags of RFC 8216bis.
- **`ts`** — MPEG-2 transport streams: packets, the programme tables, the
  elementary streams inside them and the clock that times them.
- **`rtmp`** — the publish side: handshake, chunk stream, commands, and the state
  machine a publisher drives.
- **`mpd`** — DASH manifests, read into a model and written back as XML.
- **`moonmedia`** — the packager that ties them together: an MP4 in, key-frame
  segments and the playlists that name them out.

Each package has one job and no dependencies outside the standard library, so a
program that only needs HLS playlists does not carry a container parser with it.

| Package | Reads and writes | Specification |
|:--|:--|:--|
| `moonbitstack/moonmedia/mp4` | ISO BMFF: `ftyp`, `moov`, `moof`, `mdat`, `sidx`, fragments | ISO/IEC 14496-12 |
| `moonbitstack/moonmedia/m3u8` | HLS master and media playlists, low-latency additions | [RFC 8216](https://www.rfc-editor.org/rfc/rfc8216) |
| `moonbitstack/moonmedia/ts` | MPEG-TS packets, PAT, PMT, PES, PCR | ISO/IEC 13818-1 |
| `moonbitstack/moonmedia/rtmp` | RTMP handshake, chunks, AMF0, publish session | Adobe RTMP 1.0 |
| `moonbitstack/moonmedia/mpd` | DASH MPD: periods, adaptation sets, templates, timelines | ISO/IEC 23009-1 |
| `moonbitstack/moonmedia` | MP4 to HLS: segments, media playlist, master playlist | — |

## Install

```bash
moon add moonbitstack/moonmedia
```

## Cutting a movie into an HLS package

The packager reads a whole MP4 — progressive or already fragmented — and returns
an initialisation section plus one segment per key frame interval. Nothing is
written anywhere: the bytes are handed back for a caller to serve.

<!-- nocheck -->
```mbt
///|
test {
  // `movie` is a file's bytes, from wherever the caller got them.
  let file = @mp4.Mp4::parse(movie)
  let packager = @moonmedia.Packager::new(file, target_duration=6.0)
  // What a player needs before it can decode anything.
  let init = packager.init_segment()
  // Each segment is a movie fragment: a `moof` and the `mdat` it points at.
  for segment in packager.segments() {
    println(segment.data.length().to_string() + " bytes, " +
      segment.duration.to_string() + " s")
  }
  // The playlist that names them, ready to be served as text.
  println(packager.media_playlist().encode())
}
```

Segments start on video key frames, and each carries the audio that plays over
it, so a player that seeks or switches rendition lands on something it can
decode immediately. The media playlist is a VOD one: it lists every segment and
ends with `#EXT-X-ENDLIST`. For a live stream, keep the sliding window yourself
and rebuild the playlist with `@m3u8.MediaPlaylist` as segments arrive.

## Reading and writing playlists

A playlist is text in and text out. Master and media playlists are told apart by
what the file contains, and what a reader does not understand is kept and
written back rather than dropped.

```mbt
///|
test {
  let text =
    #|#EXTM3U
    #|#EXT-X-VERSION:7
    #|#EXT-X-TARGETDURATION:6
    #|#EXT-X-MAP:URI="init.mp4"
    #|#EXTINF:6,
    #|segment0.m4s
    #|#EXT-X-ENDLIST
  match @m3u8.Playlist::parse(text) {
    MediaPlaylist(media) => {
      println(media.segments.length().to_string() + " segments")
      // The key and the map in force for a segment are resolved for you: a tag
      // applies until it is replaced, and the segment carries the result.
      for segment in media.segments {
        println(segment.uri + " " + segment.duration.to_string())
      }
    }
    MasterPlaylist(master) =>
      for variant in master.variants {
        println(variant.uri + " at " + variant.bandwidth.unwrap().to_string())
      }
  }
}
```

Building one is the same model, written the other way:

```mbt
///|
test {
  let media = @m3u8.MediaPlaylist::new(6)
  media.version = Some(7)
  media.playlist_type = Some(@m3u8.PlaylistType::Vod)
  media.end_list = true
  let init = @m3u8.InitSection::new("init.mp4")
  for i = 0; i < 4; i = i + 1 {
    let segment = @m3u8.Segment::new("segment" + i.to_string() + ".m4s", 6.0)
    segment.map = Some(init)
    media.segments.push(segment)
  }
  let text = media.encode()
  println(text)
}
```

Low-latency HLS is the same model with more tags: `EXT-X-PART` lists attached to
the segment they build, `EXT-X-PART-INF`, `EXT-X-SERVER-CONTROL`,
`EXT-X-PRELOAD-HINT`, `EXT-X-RENDITION-REPORT` and `EXT-X-SKIP` all read and
write. The parts of a segment that has not been announced yet are the playlist's
`next_parts`, because they belong to no segment yet.

## Reading a movie

A file is a tree of boxes. Reading keeps the tree, and writing it back gives the
same bytes — including the boxes this package has no name for, and including
whether a box used the 32-bit or the 64-bit size form.

<!-- nocheck -->
```mbt
///|
test {
  let file = @mp4.Mp4::parse(bytes)
  for box in file.boxes {
    println(box.type_ + " " + box.byte_length().to_string())
  }
  // The samples of every track, from the sample table of a plain file or from
  // the fragments of a fragmented one.
  for track in file.tracks() {
    println(track.codec + " " + track.width.to_string() + "x" +
      track.height.to_string() + ", " + track.samples.length().to_string() +
      " frames")
    for sample in track.samples {
      // Where the frame is, how long it plays, and whether a player may start
      // on it.
      println(sample.offset.to_string() + " " + sample.duration.to_string() +
        " " + sample.sync.to_string())
    }
  }
}
```

`file.encode() == bytes` holds for any file this package can read.

## Transport streams

A transport stream is 188-byte packets; the tables that say what is in it and the
frames inside it are found by walking them.

<!-- nocheck -->
```mbt
///|
test {
  let packets = @ts.parse(bytes)
  let pat = @ts.Pat::of(@ts.sections(packets, @ts.pat_pid)[0])
  let pmt = @ts.Pmt::of(@ts.sections(packets, pat.programs[0].pid)[0])
  println(
    "programme " + pmt.program.to_string() +
    ", clock on pid " + pmt.pcr_pid.to_string(),
  )
  for stream in pmt.streams {
    println("type " + stream.stream_type.to_string() + " on " + stream.pid.to_string())
  }
  // The frames of one elementary stream, with their timestamps.
  for frame in @ts.pes_packets(packets, pmt.streams[0].pid) {
    println(frame.data.length().to_string() + " bytes at " +
      frame.pts().unwrap().to_string())
  }
}
```

Every packet read and written again is the same 188 bytes, adaptive field
stuffing included.

## Taking a publish

The RTMP package is the receiving side of a publish. A session takes whatever
arrived and gives back what to send; the socket belongs to the caller.

<!-- nocheck -->
```mbt
///|
test {
  let session = @rtmp.Session::new()
  // Whatever came off the socket, in the order it came.
  for reply in session.push(bytes) {
    println(reply.length().to_string() + " bytes to send back")
  }
  match session.phase() {
    Publishing => {
      println(session.app() + "/" + session.stream_name())
      for message in session.take_media() {
        println(message.type_.to_string() + " " + message.timestamp.to_string())
      }
    }
    _ => println("still setting up")
  }
}
```

The handshake, the chunk stream and the commands a publisher sends — `connect`,
`createStream`, `publish`, the metadata — are handled; the media messages are
handed to the caller as they arrive.

## DASH manifests

A manifest is a model, not a document: the reader takes the XML apart and the
writer puts it back, and both know about periods, adaptation sets,
representations, segment templates and timelines.

<!-- nocheck -->
```mbt
///|
test {
  let manifest = @mpd.Manifest::parse(text)
  println(@mpd.format_duration(manifest.duration.unwrap()))
  for period in manifest.periods {
    for set in period.adaptations {
      for representation in set.representations {
        println(representation.id + " " +
          representation.bandwidth.unwrap().to_string() + " bit/s")
      }
    }
  }
  // Writing it back gives a manifest a player reads the same way.
  println(manifest.encode())
}
```

## How the packages behave

**Bytes in, bytes out.** Nothing here opens a socket, reads a file or keeps
global state. A caller decides where the bytes come from and where they go, which
is what makes the library usable in a server, a command-line tool and a test
alike.

**What is read is what is written.** `mp4`, `ts` and the RTMP chunk stream
reproduce their input byte for byte: a box nobody named keeps its payload and its
size form, an adaptation field keeps its stuffing, a chunk keeps its header
format. Playlists are written in the order the specification lists their tags, so
they round-trip as the same model rather than the same text.

**Unknown is kept, not guessed.** A playlist tag or attribute from a later
revision survives a rewrite. A transport stream that loses its sync is refused
rather than resynchronised, because a stream whose packets have been dropped is a
stream with a problem the caller needs to know about.

**Durations and times are numbers.** Times inside a container are integer ticks
in the track's timescale and are kept that way; a `Double` is used only where the
format itself allows a fraction, and a duration written to a manifest or a
playlist is the shortest text that reads back as the same number.

## The API, package by package

### `moonbitstack/moonmedia/mp4`

| | |
|:--|:--|
| `parse(data)` | read the boxes at the start of `data` |
| `encode(boxes)`, `box.encode()` | write boxes back |
| `Mp4::parse(data)` | a whole file, with the bytes kept for slicing |
| `Mp4::encode()`, `Mp4::boxes`, `Mp4::box(type)` | the file and its tree |
| `Mp4::file_type()`, `Mp4::movie()`, `Mp4::is_fragmented()` | what the file says it is |
| `Mp4::tracks()` | tracks with their samples, from the sample table or the fragments |
| `Mp4::fragments()` | the fragments, each with the media data that belongs to it |
| `Mp4::init_section()` | the boxes a player needs before any fragment |
| `Box::child(type)`, `Box::children_of(type)`, `Box::boxes()`, `Box::raw()` | walking the tree |
| `MovieFragment::new(sequence, tracks)`, `MovieFragment::encode()` | writing a fragment |
| `Box::children(type, boxes)`, `Box::bytes(type, raw)`, `Box::byte_length()` | building a tree |
| `segment_index(box)` | a `sidx` read into references |
| `Sample`, `Track`, `Fragment`, `Run`, `SegmentIndex`, `FileType`, `MovieHeader` | the data shapes |

### `moonbitstack/moonmedia/m3u8`

| | |
|:--|:--|
| `Playlist::parse(text)`, `Playlist::encode()` | text in, text out |
| `Playlist::master()`, `Playlist::media()`, `Playlist::is_master()` | which kind it is |
| `Master`, `MediaPlaylist` | the two models, built field by field |
| `Segment`, `Part`, `Key`, `InitSection`, `ByteRange` | what a segment says |
| `Variant`, `Rendition`, `IFrameStream`, `SessionData` | what a master playlist says |
| `ServerControl`, `PreloadHint`, `RenditionReport`, `DateRange`, `Define` | the rest of the tags |
| `Cipher`, `MediaKind`, `PlaylistType` | the enumerated attributes, with `of` and `code` |

### `moonbitstack/moonmedia/ts`

| | |
|:--|:--|
| `parse(data)`, `Packet::parse(packet)`, `Packet::encode()` | packets |
| `Packet::is_pat()`, `Packet::is_null()`, `Packet::pid`, `Packet::counter` | what a packet is |
| `Adaptation::pcr()`, `Adaptation::with_pcr(pcr)`, `Adaptation::discontinuity()` | the clock and the flags |
| `sections(packets, pid)`, `Section::parse`, `Section::encode`, `Section::packets` | the tables |
| `Pat::of(section)`, `Pat::encode()`, `Pmt::of(section)`, `Pmt::encode()` | programme tables |
| `Pes::parse`, `Pes::encode`, `Pes::new`, `Pes::pts()`, `Pes::dts()` | elementary stream packets |
| `pes_packets(packets, pid)` | one track's frames, reassembled |
| `crc32(data)`, `Section::is_intact()` | the checksum the tables carry |
| `continues(from, to)`, `next_counter(previous, packet)` | continuity |

### `moonbitstack/moonmedia/rtmp`

| | |
|:--|:--|
| `Session::new()`, `Session::push(bytes)` | a publish session, fed by its caller |
| `Session::phase()`, `Session::app()`, `Session::stream_name()` | where it is |
| `Session::take_media()`, `Session::metadata()` | what the publisher sent |
| `Handshake::new()`, `Handshake::answer(c0c1)`, `Handshake::complete_with(c2)` | the handshake |
| `client_start(time)`, `client_finish(s0s1s2)` | the other side of it |
| `ChunkReader::push(bytes)`, `ChunkWriter::write(message)` | chunks and messages |
| `Message`, `msg_command`, `msg_audio`, `msg_video`, `msg_data` | messages |
| `Amf0`, `encode_all(values)`, `decode_all(data)` | the command encoding |
| `set_chunk_size`, `window_ack_size`, `set_peer_bandwidth`, `pong` | protocol control |

### `moonbitstack/moonmedia/mpd`

| | |
|:--|:--|
| `Manifest::parse(text)`, `Manifest::encode()` | a manifest in and out |
| `Manifest`, `Period`, `AdaptationSet`, `Representation` | the model |
| `Template`, `Timeline` | how segments are addressed |
| `parse_duration(text)`, `format_duration(seconds)` | ISO 8601 durations |
| `Kind` | static or dynamic |

### `moonbitstack/moonmedia`

| | |
|:--|:--|
| `Packager::new(file, target_duration?)` | cut a movie into segments |
| `Packager::init_segment()`, `Packager::segments()`, `Packager::duration()` | what came out |
| `Packager::media_playlist()`, `Packager::master_playlist()` | the playlists |
| `Packager::video_track()`, `Packager::audio_track()`, `Packager::tracks` | what went in |
| `Segment` | one segment: bytes, duration, start, sample counts |

## Examples

Each of these runs with no arguments and no files:

```bash
moon run src/examples/01-playlists   # build a master and a media playlist, read both back
moon run src/examples/02-boxes       # a fragment written, read, and walked
moon run src/examples/03-package     # an MP4 cut into segments, with the playlists
moon run src/examples/04-transport   # tables and a frame, as transport stream packets
moon run src/examples/05-manifest    # a DASH manifest, printed as XML
moon run src/examples/06-ingest      # a publish session driven from handshake to media
```

## Licence

Apache-2.0. See [LICENSE](LICENSE).
