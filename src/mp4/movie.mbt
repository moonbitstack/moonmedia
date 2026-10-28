// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// What a track carries, from the handler `hdlr` names.
pub(all) enum TrackKind {
  Video
  Audio
  Subtitle
  Hint
  Other(String)
} derive(Eq, Debug)

///|
pub extend TrackKind with Eq::{equal, not_equal}

///|
pub extend TrackKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A file and the boxes it was read into.
///
/// The bytes are kept because sample data is described by offsets into them:
/// a sample is a view, not a copy, so a track of a hundred thousand frames
/// costs nothing to list.
pub(all) struct Mp4 {
  data : Bytes
  boxes : Array[Box]
}

///|
/// Read a file.
pub fn Mp4::parse(data : BytesView) -> Mp4 raise Mp4Error {
  let bytes = data.to_owned()
  { data: bytes, boxes: parse(bytes[:]), }
}

///|
/// Write the file back. A file read and written again is the same bytes.
pub fn Mp4::encode(self : Mp4) -> Bytes {
  encode(self.boxes)
}

///|
/// The first box of a type at the top level.
pub fn Mp4::box(self : Mp4, type_ : StringView) -> Box? {
  for box in self.boxes {
    if box.is_type(type_) {
      return Some(box)
    }
  }
  None
}

///|
/// The brand a file declares, `ftyp`.
pub fn Mp4::file_type(self : Mp4) -> FileType? raise Mp4Error {
  match self.box("ftyp") {
    Some(box) => Some(FileType::of(box.raw()))
    None => None
  }
}

///|
/// The movie header, `moov`.
pub fn Mp4::movie(self : Mp4) -> Box? {
  self.box("moov")
}

///|
/// Whether the file describes its media in fragments rather than in a sample
/// table, which is what a stream cut into segments looks like.
pub fn Mp4::is_fragmented(self : Mp4) -> Bool {
  match self.movie() {
    Some(moov) => moov.child("mvex") != None
    None => false
  }
}

///|
/// The brands a file declares in `ftyp`.
pub(all) struct FileType {
  major : String
  minor : Int32
  compatible : Array[String]
} derive(Eq, Debug)

///|
pub extend FileType with Eq::{equal, not_equal}

///|
pub extend FileType with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Read a file type box.
pub fn FileType::of(raw : Bytes) -> FileType raise Mp4Error {
  let data = raw[:]
  if data.length() < 8 {
    raise Malformed(
      at=0,
      want="a major brand and a minor version",
      got=data.length().to_string() + " bytes",
    )
  }
  let compatible : Array[String] = []
  let mut at = 8
  while at + 4 <= data.length() {
    compatible.push(read_type(data, at))
    at = at + 4
  }
  { major: read_type(data, 0), minor: read_u32(data, 4), compatible, }
}

///|
/// Write a file type box.
pub fn FileType::encode(self : FileType) -> Bytes {
  let buf = @buffer.Buffer()
  write_type(buf, self.major)
  write_u32(buf, self.minor)
  for brand in self.compatible {
    write_type(buf, brand)
  }
  buf.contents()
}

///|
/// A track's timescale: how many units make a second.
pub(all) struct MovieHeader {
  timescale : Int64
  duration : Int64
} derive(Eq, Debug)

///|
pub extend MovieHeader with Eq::{equal, not_equal}

///|
pub extend MovieHeader with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Read a `mvhd`.
pub fn movie_header(moov : Box) -> MovieHeader raise Mp4Error {
  let raw = match moov.child("mvhd") {
    Some(box) => box.raw()[:]
    None => raise Malformed(at=0, want="mvhd", got="none")
  }
  let version = read_u8(raw, 0)
  if version == 1 {
    { timescale: read_u32(raw, 20).to_int64(), duration: read_u64(raw, 24), }
  } else {
    {
      timescale: read_u32(raw, 12).to_int64(),
      duration: read_u32(raw, 16).to_int64(),
    }
  }
}

///|
/// One sample: where its bytes are, when it plays, and whether a player may
/// start here.
pub(all) struct Sample {
  /// Offset into the file.
  offset : Int32
  size : Int32
  /// Decode time, in the track's timescale.
  dts : Int64
  duration : Int64
  /// How far presentation time runs ahead of decode time, for reordered video.
  composition_offset : Int64
  sync : Bool
} derive(Eq, Debug)

///|
pub extend Sample with Eq::{equal, not_equal}

///|
pub extend Sample with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// When the sample is shown, in the track's timescale.
pub fn Sample::pts(self : Sample) -> Int64 {
  self.dts + self.composition_offset
}

///|
/// How long the sample is in seconds.
pub fn Sample::seconds(self : Sample, timescale : Int64) -> Double {
  self.duration.to_double() / timescale.to_double()
}

///|
/// A track and the samples it holds, read from the sample table or from the
/// fragments.
pub(all) struct Track {
  id : Int32
  kind : TrackKind
  timescale : Int64
  duration : Int64
  language : String
  /// The codec as a player names it: `avc1.64001f`, `mp4a.40.2`, `hvc1`.
  codec : String
  width : Int32
  height : Int32
  sample_rate : Int32
  channels : Int32
  samples : Array[Sample]
} derive(Eq, Debug)

///|
pub extend Track with Eq::{equal, not_equal}

///|
pub extend Track with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The samples of every track, in the order the tracks appear.
pub fn Mp4::tracks(self : Mp4) -> Array[Track] raise Mp4Error {
  let out : Array[Track] = []
  let moov = match self.movie() {
    Some(moov) => moov
    None => return out
  }
  let mvhd = movie_header(moov)
  // A file says where its samples are in one of two places: the sample table of
  // each track, or the fragments that carry them. Both are read here, so a
  // caller does not have to know which kind of file it opened.
  let fragmented = self.is_fragmented()
  let from_fragments = if fragmented { self.fragment_samples() } else { [] }
  for trak in moov.children_of("trak") {
    let track = track_header(trak, mvhd)
    let samples = if fragmented {
      let mut found : Array[Sample] = []
      for pair in from_fragments {
        if pair.0 == track.id {
          found = pair.1
        }
      }
      found
    } else {
      sample_table(trak) catch {
        _ => []
      }
    }
    out.push({ ..track, samples, })
  }
  out
}

///|
/// The samples of every track, taken from the fragments in the order they are
/// presented.
fn Mp4::fragment_samples(self : Mp4) -> Array[(Int32, Array[Sample])] {
  let ids : Array[Int32] = []
  let runs : Array[Array[Sample]] = []
  let fragments = self.fragments() catch { _ => [] }
  for fragment in fragments {
    for run in fragment.runs {
      let mut at = -1
      for i, id in ids {
        if id == run.track_id {
          at = i
        }
      }
      if at < 0 {
        ids.push(run.track_id)
        runs.push(run.samples)
      } else {
        for sample in run.samples {
          runs[at].push(sample)
        }
      }
    }
  }
  let out : Array[(Int32, Array[Sample])] = []
  for i, id in ids {
    out.push((id, runs[i]))
  }
  out
}

///|
/// The track's identity and codec, without its samples.
fn track_header(trak : Box, mvhd : MovieHeader) -> Track raise Mp4Error {
  let tkhd = match trak.child("tkhd") {
    Some(box) => box.raw()[:]
    None => raise Malformed(at=0, want="tkhd", got="none")
  }
  let tkhd_version = read_u8(tkhd, 0)
  let (id, tkhd_duration, width, height) = if tkhd_version == 1 {
    (
      read_u32(tkhd, 20),
      read_u64(tkhd, 28),
      read_u32(tkhd, 88) >> 16,
      read_u32(tkhd, 92) >> 16,
    )
  } else {
    (
      read_u32(tkhd, 12),
      read_u32(tkhd, 20).to_int64(),
      read_u32(tkhd, 76) >> 16,
      read_u32(tkhd, 80) >> 16,
    )
  }
  let mdia = match trak.child("mdia") {
    Some(box) => box
    None => raise Malformed(at=0, want="mdia", got="none")
  }
  let mdhd = match mdia.child("mdhd") {
    Some(box) => box.raw()[:]
    None => raise Malformed(at=0, want="mdhd", got="none")
  }
  let mdhd_version = read_u8(mdhd, 0)
  let (timescale, duration, language) = if mdhd_version == 1 {
    (
      read_u32(mdhd, 20).to_int64(),
      read_u64(mdhd, 24),
      language_of(read_u16(mdhd, 32)),
    )
  } else {
    (
      read_u32(mdhd, 12).to_int64(),
      read_u32(mdhd, 16).to_int64(),
      language_of(read_u16(mdhd, 20)),
    )
  }
  let handler = match mdia.child("hdlr") {
    Some(box) => box.raw()[:]
    None => raise Malformed(at=0, want="hdlr", got="none")
  }
  // The handler type sits after a version and flags field and a pre-defined
  // field, and names what the track is for.
  let handler_type = if handler.length() >= 12 {
    read_type(handler, 8)
  } else {
    ""
  }
  let kind = if handler_type == "vide" {
    Video
  } else if handler_type == "soun" {
    Audio
  } else if handler_type == "text" ||
    handler_type == "subt" ||
    handler_type == "sbtl" {
    Subtitle
  } else if handler_type == "hint" {
    Hint
  } else {
    Other(handler_type)
  }
  let (codec, entry_width, entry_height, sample_rate, channels) = match
    mdia.child("minf") {
    Some(minf) =>
      match minf.child("stbl") {
        Some(stbl) =>
          match stbl.child("stsd") {
            Some(stsd) => sample_description(stsd, kind)
            None => ("", 0, 0, 0, 0)
          }
        None => ("", 0, 0, 0, 0)
      }
    None => ("", 0, 0, 0, 0)
  }
  {
    id,
    kind,
    timescale: if timescale == 0L {
      mvhd.timescale
    } else {
      timescale
    },
    duration: if duration == 0L {
      tkhd_duration
    } else {
      duration
    },
    language,
    codec,
    width: if entry_width > 0 {
      entry_width
    } else {
      width
    },
    height: if entry_height > 0 {
      entry_height
    } else {
      height
    },
    sample_rate,
    channels,
    samples: [],
  }
}

///|
/// The three letters of an ISO 639-2/T language, packed five bits at a time.
fn language_of(packed : Int32) -> String {
  let letters = @buffer.Buffer()
  for shift in [10, 5, 0] {
    let code = ((packed >> shift) & 0x1F) + 0x60
    letters.write_byte(code.to_byte())
  }
  @utf8.decode_lossy(letters.contents())
}

///|
/// The codec and the sizes a sample description carries.
fn sample_description(
  stsd : Box,
  kind : TrackKind,
) -> (String, Int32, Int32, Int32, Int32) raise Mp4Error {
  // The entries follow the version, flags and count, as boxes of their own.
  let entries = stsd.boxes()
  if entries.length() == 0 {
    return ("", 0, 0, 0, 0)
  }
  let entry = entries[0]
  let format = entry.type_
  let body = entry.raw()[:]
  // A sample entry starts with the same six fields whatever it describes, then
  // branches: a video entry has its size where an audio entry has its channel
  // count and sample rate, so the fields are read by what the track is.
  let mut width = 0
  let mut height = 0
  let mut sample_rate = 0
  let mut channels = 0
  if kind == Audio {
    if body.length() >= 28 {
      channels = read_u16(body, 16)
      sample_rate = read_u32(body, 24) >> 16
    }
  } else if body.length() >= 78 {
    width = read_u16(body, 24)
    height = read_u16(body, 26)
  }
  let codec = if format == "avc1" || format == "avc3" {
    match entry.child("avcC") {
      Some(avcc) => {
        let config = avcc.raw()[:]
        if config.length() >= 4 {
          format +
          "." +
          byte_hex(config.at(1)) +
          byte_hex(config.at(2)) +
          byte_hex(config.at(3))
        } else {
          format
        }
      }
      None => format
    }
  } else if format == "mp4a" {
    "mp4a.40.2"
  } else {
    format
  }
  (codec, width, height, sample_rate, channels)
}

///|
/// Two hex digits of a byte, lower case.
fn byte_hex(value : Byte) -> String {
  let digits = "0123456789abcdef"
  let byte = value.to_int() & 0xFF
  digits[byte >> 4:(byte >> 4) + 1].to_owned() +
  digits[byte & 0xF:(byte & 0xF) + 1].to_owned()
}

///|
/// The samples a sample table describes, in decode order.
///
/// The table is four lists that only mean anything together: how many samples
/// each chunk holds, how big each sample is, where each chunk starts, and how
/// long each sample lasts. Walking them in step is the only way to turn a
/// description into offsets.
fn sample_table(trak : Box) -> Array[Sample] raise Mp4Error {
  let minf = match trak.child("mdia") {
    Some(mdia) => mdia.child("minf")
    None => None
  }
  let stbl = match minf {
    Some(minf) =>
      match minf.child("stbl") {
        Some(stbl) => stbl
        None => return []
      }
    None => return []
  }
  let sizes = sample_sizes(stbl)
  if sizes.length() == 0 {
    return []
  }
  let offsets = chunk_offsets(stbl)
  let runs = sample_to_chunk(stbl)
  let durations = sample_durations(stbl)
  let composition = composition_offsets(stbl, sizes.length())
  let syncs = sync_samples(stbl)
  let samples : Array[Sample] = []
  let mut index = 0
  let mut dts = 0L
  for i = 0; i < runs.length(); i = i + 1 {
    let (first_chunk, per_chunk, _) = runs[i]
    let last_chunk = if i + 1 < runs.length() {
      runs[i + 1].0 - 1
    } else {
      offsets.length()
    }
    for chunk = first_chunk; chunk <= last_chunk; chunk = chunk + 1 {
      if chunk - 1 >= offsets.length() {
        break
      }
      let mut offset = offsets[chunk - 1]
      for i = 0; i < per_chunk; i = i + 1 {
        if index >= sizes.length() {
          break
        }
        let size = sizes[index]
        let duration = if index < durations.length() {
          durations[index]
        } else {
          0L
        }
        let is_sync = match syncs {
          Some(list) => list.contains(index + 1)
          None => true
        }
        samples.push({
          offset,
          size,
          dts,
          duration,
          composition_offset: if index < composition.length() {
            composition[index]
          } else {
            0L
          },
          sync: is_sync,
        })
        offset = offset + size
        dts = dts + duration
        index = index + 1
      }
    }
  }
  samples
}

///|
/// The size of every sample, `stsz` or `stz2`.
fn sample_sizes(stbl : Box) -> Array[Int32] raise Mp4Error {
  let out : Array[Int32] = []
  match stbl.child("stsz") {
    Some(box) => {
      let raw = box.raw()[:]
      let fixed = read_u32(raw, 4)
      let count = read_u32(raw, 8)
      for i = 0; i < count; i = i + 1 {
        out.push(if fixed != 0 { fixed } else { read_u32(raw, 12 + i * 4) })
      }
    }
    None => ()
  }
  out
}

///|
/// Where each chunk starts, `stco` or `co64`.
fn chunk_offsets(stbl : Box) -> Array[Int32] raise Mp4Error {
  let out : Array[Int32] = []
  match stbl.child("stco") {
    Some(box) => {
      let raw = box.raw()[:]
      let count = read_u32(raw, 4)
      for i = 0; i < count; i = i + 1 {
        out.push(read_u32(raw, 8 + i * 4))
      }
    }
    None =>
      match stbl.child("co64") {
        Some(box) => {
          let raw = box.raw()[:]
          let count = read_u32(raw, 4)
          for i = 0; i < count; i = i + 1 {
            out.push(read_u64(raw, 8 + i * 8).to_int())
          }
        }
        None => ()
      }
  }
  out
}

///|
/// How many samples each chunk holds, as runs of (first chunk, per chunk,
/// description index).
fn sample_to_chunk(stbl : Box) -> Array[(Int32, Int32, Int32)] raise Mp4Error {
  let out : Array[(Int32, Int32, Int32)] = []
  match stbl.child("stsc") {
    Some(box) => {
      let raw = box.raw()[:]
      let count = read_u32(raw, 4)
      for i = 0; i < count; i = i + 1 {
        let at = 8 + i * 12
        out.push(
          (read_u32(raw, at), read_u32(raw, at + 4), read_u32(raw, at + 8)),
        )
      }
    }
    None => ()
  }
  out
}

///|
/// How long each sample lasts, expanded from runs, `stts`.
fn sample_durations(stbl : Box) -> Array[Int64] raise Mp4Error {
  let out : Array[Int64] = []
  match stbl.child("stts") {
    Some(box) => {
      let raw = box.raw()[:]
      let count = read_u32(raw, 4)
      for i = 0; i < count; i = i + 1 {
        let at = 8 + i * 8
        let repeat = read_u32(raw, at)
        let delta = read_u32(raw, at + 4).to_int64()
        for i = 0; i < repeat; i = i + 1 {
          out.push(delta)
        }
      }
    }
    None => ()
  }
  out
}

///|
/// The presentation offset of each sample, `ctts`. An absent table means every
/// sample is shown as soon as it is decoded.
fn composition_offsets(
  stbl : Box,
  count : Int32,
) -> Array[Int64] raise Mp4Error {
  let out : Array[Int64] = []
  match stbl.child("ctts") {
    Some(box) => {
      let raw = box.raw()[:]
      let entries = read_u32(raw, 4)
      for i = 0; i < entries; i = i + 1 {
        let at = 8 + i * 8
        let repeat = read_u32(raw, at)
        // Signed: a negative offset means the sample is shown before it is
        // decoded, which is what a stream with B-frames and an offset edit
        // list looks like.
        let offset = read_u32_unsigned(raw, at + 4)
        for i = 0; i < repeat; i = i + 1 {
          out.push(offset)
        }
      }
    }
    None =>
      for i = 0; i < count; i = i + 1 {
        out.push(0L)
      }
  }
  out
}

///|
/// Which samples a player may start on, `stss`. An absent table means all of
/// them, which is what an audio track looks like.
fn sync_samples(stbl : Box) -> Array[Int32]? raise Mp4Error {
  match stbl.child("stss") {
    Some(box) => {
      let raw = box.raw()[:]
      let count = read_u32(raw, 4)
      let out : Array[Int32] = []
      for i = 0; i < count; i = i + 1 {
        out.push(read_u32(raw, 8 + i * 4))
      }
      Some(out)
    }
    None => None
  }
}
