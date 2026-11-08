<h1 align="center">moonmedia</h1>

<p align="center">
  <sub>HLS · DASH · fragmented MP4 · MPEG-TS · RTMP</sub><br>
  <sub><code>188 bytes · 90 kHz · 33 bits of clock</code></sub>
</p>

<p align="center">
  <a href="https://moonbitstack.github.io/moonmedia/"><b>Homepage</b></a>
  &nbsp;·&nbsp;
  <a href="https://moonbitstack.github.io/moonmedia/guide.html">Guide</a>
  &nbsp;·&nbsp;
  <a href="https://moonbitstack.github.io/moonmedia/api.html">API</a>
  &nbsp;·&nbsp;
  <a href="https://mooncakes.io/docs/moonbitstack/moonmedia">mooncakes</a>
</p>

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

## An MP4 in, an HLS package out

The packager reads a whole MP4 — progressive or already fragmented — and returns
an initialisation section plus one segment per key frame interval. Nothing is
written anywhere: the bytes are handed back for a caller to serve.

The file below is 698 bytes of a 64 × 64 test pattern: eight frames a quarter
of a second apart, the first and the fifth of them key frames. The target is
half a second, but a segment may only begin on a key frame, so the cut lands on
the fifth frame and each segment lasts a second.

```moonbit
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

let file = @mp4.Mp4::parse(movie)
assert_eq(file.boxes.map(fn(box) { box.type_ }), ["ftyp", "moov", "mdat"])

// Every track with its frames, whether the file keeps them in a sample table
// or in the fragments of a stream still being written.
let video = file.tracks()[0]
assert_eq(video.codec, "avc1.42c00a")
assert_eq(video.width, 64)
assert_eq(video.samples.length(), 8)
assert_eq(video.samples[4].sync, true)
assert_eq(video.samples[1].sync, false)

// A file read and written again is the same bytes, down to the boxes this
// package has no name for.
assert_eq(file.encode(), movie)
```

Cutting is one call on that file. Segments start on video key frames and carry
the audio that plays over them, so a player that seeks or switches rendition
lands on something it can decode immediately.

```moonbit
let packager = @moonmedia.Packager::new(file, target_duration=0.5)
assert_eq(packager.segments().length(), 2)
assert_eq(packager.segments()[0].start, 0.0)
assert_eq(packager.segments()[1].start, 1.0)
assert_eq(packager.segments()[0].samples, [4])
assert_eq(packager.duration(), 2.0)

// What a player needs before it can decode anything: the file type and a movie
// header whose sample tables are empty.
let init = @mp4.Mp4::parse(packager.init_segment())
assert_eq(init.boxes.map(fn(box) { box.type_ }), ["ftyp", "moov"])
assert_eq(init.tracks()[0].samples.length(), 0)
```

The media playlist that names the segments is written from the same model, so the
text is exactly what the segments on disk answer to:

```moonbit
let text = packager.media_playlist().encode()
let expected =
  #|#EXTM3U
  #|#EXT-X-VERSION:7
  #|#EXT-X-TARGETDURATION:1
  #|#EXT-X-PLAYLIST-TYPE:VOD
  #|#EXT-X-INDEPENDENT-SEGMENTS
  #|#EXT-X-MAP:URI="init.mp4"
  #|#EXTINF:1,
  #|segment0.m4s
  #|#EXTINF:1,
  #|segment1.m4s
  #|#EXT-X-ENDLIST
  #|
assert_eq(text, expected)
```

A master playlist is the same thing one level up: the codecs a player has to
support, the size it will see, and the bandwidth it costs.

```moonbit
let master = packager.master_playlist(uri="index.m3u8")
assert_eq(master.variants[0].codecs, Some("avc1.42c00a"))
assert_eq(master.variants[0].resolution, Some(@m3u8.Resolution::new(64, 64)))
assert_eq(master.variants[0].bandwidth, Some(1440))
```

The media playlist is a VOD one: it lists every segment and ends with
`#EXT-X-ENDLIST`. For a live stream, keep the sliding window yourself and build
the playlist with `@m3u8.MediaPlaylist` as segments arrive.

## Reading and writing playlists

A playlist is text in and text out. Master and media playlists are told apart by
what the file contains, and what a reader does not understand is kept and written
back rather than dropped.

```moonbit
let source =
  #|#EXTM3U
  #|#EXT-X-VERSION:7
  #|#EXT-X-TARGETDURATION:6
  #|#EXT-X-PLAYLIST-TYPE:VOD
  #|#EXT-X-MAP:URI="init.mp4"
  #|#EXTINF:6,
  #|segment0.m4s
  #|#EXTINF:4.004,
  #|segment1.m4s
  #|#EXT-X-ENDLIST
let playlist = @m3u8.Playlist::parse(source).media().unwrap()
assert_eq(playlist.target_duration, 6)
assert_eq(playlist.segments.length(), 2)
assert_eq(playlist.segments[1].uri, "segment1.m4s")
assert_eq(playlist.segments[1].duration, 4.004)

// The map in force for a segment is resolved for you: a tag applies until it is
// replaced, and the segment carries the result.
assert_eq(playlist.segments[0].map.unwrap().uri, "init.mp4")
```

Building one is the same model, written the other way:

```moonbit
let media = @m3u8.MediaPlaylist::new(6)
media.version = Some(7)
media.playlist_type = Some(@m3u8.PlaylistType::Vod)
media.end_list = true
let section = @m3u8.InitSection::new("init.mp4")
for i = 0; i < 2; i = i + 1 {
  let segment = @m3u8.Segment::new("segment" + i.to_string() + ".m4s", 6.0)
  segment.map = Some(section)
  media.segments.push(segment)
}
assert_eq(media.encode().contains("#EXT-X-ENDLIST"), true)
assert_eq(media.segments.length(), 2)
```

Low-latency HLS is the same model with more tags: `EXT-X-PART` lists attached to
the segment they build, `EXT-X-PART-INF`, `EXT-X-SERVER-CONTROL`,
`EXT-X-PRELOAD-HINT`, `EXT-X-RENDITION-REPORT` and `EXT-X-SKIP` all read and
write. The parts of a segment that has not been announced yet are the playlist's
`next_parts`, because they belong to no segment yet.

## Transport streams

A transport stream is 188-byte packets; the tables that say what is in it and the
frames inside it are found by walking them.

```moonbit
let pat = @ts.Pat::new(
  transport_stream=1,
  programs=[@ts.Program::new(1, 0x1000)],
)
let packet = pat.section().packets(@ts.pat_pid)[0]
let stream = packet.encode()
assert_eq(stream.length(), 188)

// The table puts itself back together from the packets that carry it.
let packets = @ts.parse(stream[:])
let table = @ts.sections(packets, @ts.pat_pid)[0]
let read = @ts.Pat::of(table)
assert_eq(read.programs[0].number, 1)
assert_eq(read.programs[0].pid, 0x1000)
assert_eq(table.is_intact(), true)

// A programme map says which stream is which, and which one carries the clock.
let pmt = @ts.Pmt::new(
  program=1,
  pcr_pid=0x1001,
  streams=[@ts.Stream::new(0x1B, 0x1001)],
)
let program = @ts.Pmt::of(@ts.sections(pmt.section().packets(0x1000), 0x1000)[0])
assert_eq(program.pcr_pid, 0x1001)
assert_eq(program.streams[0].stream_type, 0x1B)

// One frame of an elementary stream, with its presentation time in 90 kHz ticks.
let frame = @ts.Pes::new(
  0xE0,
  Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x01', b'\x09']),
  pts=90000L,
)
assert_eq(frame.pts().unwrap(), 90000L)
```

Every packet read and written again is the same 188 bytes, adaptive field
stuffing included.

## Taking a publish

The RTMP package is the receiving side of a publish. A session takes whatever
arrived and gives back what to send; the socket belongs to the caller.

```moonbit
let session = @rtmp.Session::new()
let answer = session.push(@rtmp.client_start(0)[:])
assert_eq(answer.length(), 1)
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
let replies = session.push(writer.write(connect)[:])
assert_eq(replies.length(), 4)
assert_eq(session.app(), "live")

let publish = @rtmp.Message::new(
  @rtmp.msg_command,
  1,
  @rtmp.encode_all([
    @rtmp.Amf0::String("publish"),
    @rtmp.Amf0::Number(2.0),
    @rtmp.Amf0::Null,
    @rtmp.Amf0::String("camera"),
    @rtmp.Amf0::String("live"),
  ]),
)
let _ = session.push(writer.write(publish)[:])
assert_eq(session.stream_name(), "camera")

let video = @rtmp.Message::new(
  @rtmp.msg_video,
  1,
  Bytes::from_array([b'\x17', b'\x00', b'\x00']),
)
let _ = session.push(writer.write(video)[:])
assert_eq(session.take_media().length(), 1)
```

The handshake, the chunk stream and the commands a publisher sends — `connect`,
`createStream`, `publish`, the metadata — are handled; the media messages are
handed to the caller as they arrive.

## DASH manifests

A manifest is a model, not a document: the reader takes the XML apart and the
writer puts it back, and both know about periods, adaptation sets,
representations, segment templates and timelines.

```moonbit
let manifest = @mpd.Manifest::new(kind=@mpd.Kind::Static)
manifest.min_buffer_time = Some(2.0)
manifest.duration = Some(8.0)
let period = @mpd.Period::new(id="1", start=0.0)
let video = @mpd.AdaptationSet::new(
  content_type="video",
  mime_type="video/mp4",
)
let template = @mpd.Template::new()
template.timescale = Some(1000L)
template.duration = Some(4000L)
template.media = Some("segment-$Number$.m4s")
video.template = Some(template)
video.representations.push(@mpd.Representation::new("v0", bandwidth=800_000))
period.adaptations.push(video)
manifest.periods.push(period)

let xml = manifest.encode()
assert_eq(xml.contains("media=\"segment-$Number$.m4s\""), true)
assert_eq(@mpd.Manifest::parse(xml).periods.length(), 1)
assert_eq(@mpd.parse_duration("PT1H2M3.5S"), Some(3723.5))
assert_eq(@mpd.format_duration(3723.5), "PT1H2M3.5S")
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
