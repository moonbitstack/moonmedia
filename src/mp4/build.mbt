// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A sample as it is written into a fragment: its bytes and what the fragment
/// has to say about it.
pub(all) struct SampleData {
  data : Bytes
  duration : Int64
  composition_offset : Int64
  sync : Bool
} derive(Eq, Debug)

///|
pub extend SampleData with Eq::{equal, not_equal}

///|
pub extend SampleData with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// One track's contribution to a fragment.
pub(all) struct FragmentTrack {
  track_id : Int32
  base_decode_time : Int64
  samples : Array[SampleData]
} derive(Eq, Debug)

///|
pub extend FragmentTrack with Eq::{equal, not_equal}

///|
pub extend FragmentTrack with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A movie fragment ready to be written: `moof` and the `mdat` it points at.
pub(all) struct MovieFragment {
  sequence : Int32
  tracks : Array[FragmentTrack]
} derive(Eq, Debug)

///|
pub extend MovieFragment with Eq::{equal, not_equal}

///|
pub extend MovieFragment with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A fragment of `tracks` carrying fragment number `sequence`.
pub fn MovieFragment::new(
  sequence : Int32,
  tracks : Array[FragmentTrack],
) -> MovieFragment {
  { sequence, tracks, }
}

///|
/// The fragment as bytes: the `moof` and then the `mdat`, which is the order a
/// player needs them in when both arrive in one request.
pub fn MovieFragment::encode(self : MovieFragment) -> Bytes {
  let moof = self.moof(0)
  let data_offset = moof.byte_length() + 8
  let moof = self.moof(data_offset)
  let buf = @buffer.Buffer()
  buf.write_bytes(moof.encode())
  buf.write_bytes(mdat(self.sample_bytes()).encode())
  buf.contents()
}

///|
/// The sample bytes of every track, in track order, which is the order the
/// data offsets describe.
pub fn MovieFragment::sample_bytes(self : MovieFragment) -> Bytes {
  let buf = @buffer.Buffer()
  for track in self.tracks {
    for sample in track.samples {
      buf.write_bytes(sample.data)
    }
  }
  buf.contents()
}

///|
/// How long the fragment plays, in the timescale of its longest track.
pub fn MovieFragment::duration(
  self : MovieFragment,
  timescale : Int64,
) -> Double {
  let mut longest = 0L
  for track in self.tracks {
    let mut total = 0L
    for sample in track.samples {
      total = total + sample.duration
    }
    if total > longest {
      longest = total
    }
  }
  longest.to_double() / timescale.to_double()
}

///|
/// Build the `moof`, with the data offset `data_offset` from the start of the
/// fragment.
fn MovieFragment::moof(self : MovieFragment, data_offset : Int32) -> Box {
  let boxes : Array[Box] = [mfhd(self.sequence)]
  // Each track's data follows the one before it in the media data box, so the
  // offset a run names is the start of that track's samples, not of the box.
  let mut at = data_offset
  for track in self.tracks {
    let traf : Array[Box] = [tfhd(track.track_id), tfdt(track.base_decode_time)]
    traf.push(trun(track.samples, at))
    let mut length = 0
    for sample in track.samples {
      length = length + sample.data.length()
    }
    at = at + length
    boxes.push(Box::children("traf", traf))
  }
  Box::children("moof", boxes)
}

///|
/// A fragment header: the fragment's number.
pub fn mfhd(sequence : Int32) -> Box {
  let buf = @buffer.Buffer()
  buf.write_byte(b'\x00')
  write_u24(buf, 0)
  write_u32(buf, sequence)
  Box::bytes("mfhd", buf.contents())
}

///|
/// A track fragment header that says where this track's data is: in this
/// fragment, which is what `default-base-is-moof` means.
pub fn tfhd(track_id : Int32) -> Box {
  let buf = @buffer.Buffer()
  buf.write_byte(b'\x00')
  write_u24(buf, 0x020000)
  write_u32(buf, track_id)
  Box::bytes("tfhd", buf.contents())
}

///|
/// The decode time the fragment starts at, so a player can place it without
/// having seen the ones before it.
pub fn tfdt(base_decode_time : Int64) -> Box {
  let buf = @buffer.Buffer()
  buf.write_byte(b'\x01')
  write_u24(buf, 0)
  write_u64(buf, base_decode_time)
  Box::bytes("tfdt", buf.contents())
}

///|
/// A track run: every sample, with its duration, size, flags and composition
/// offset written out rather than defaulted, so the fragment needs nothing
/// from the header to be read.
pub fn trun(samples : Array[SampleData], data_offset : Int32) -> Box {
  let buf = @buffer.Buffer()
  buf.write_byte(b'\x00')
  // data-offset, sample-duration, sample-size, sample-flags,
  // sample-composition-time-offset.
  write_u24(buf, 0x000F01)
  write_u32(buf, samples.length())
  write_u32(buf, data_offset)
  for sample in samples {
    write_u32(buf, sample.duration.to_int())
    write_u32(buf, sample.data.length())
    write_u32(buf, sample_flags(sample.sync))
    write_u32(buf, sample.composition_offset.to_int())
  }
  Box::bytes("trun", buf.contents())
}

///|
/// The flags of one sample: whether it may be started on, and whether it needs
/// the ones before it.
fn sample_flags(sync : Bool) -> Int32 {
  // depends-on: 2 for a sample nothing is needed for, 1 for one that needs
  // another; is-non-sync: the sixteenth bit from the bottom.
  if sync {
    0x0200_0000
  } else {
    0x0101_0000
  }
}

///|
/// A media data box holding `data`.
pub fn mdat(data : Bytes) -> Box {
  Box::bytes("mdat", data)
}

///|
/// A file type box.
pub fn ftyp(major : StringView, compatible : Array[String]) -> Box {
  let buf = @buffer.Buffer()
  write_type(buf, major)
  write_u32(buf, 0)
  for brand in compatible {
    write_type(buf, brand)
  }
  Box::bytes("ftyp", buf.contents())
}

///|
/// The boxes a player needs before the first fragment: a file type, and a movie
/// header whose sample tables are empty and whose `mvex` describes what is to
/// come.
///
/// The durations in the header are set to zero, because a live stream does not
/// know how long it is; a fragment says when it starts, and that is what a
/// player uses.
pub fn Mp4::init_section(self : Mp4) -> Bytes raise Mp4Error {
  let moov = match self.movie() {
    Some(moov) => moov
    None => raise Malformed(at=0, want="moov", got="none")
  }
  let out : Array[Box] = []
  match self.box("ftyp") {
    Some(box) => out.push(box)
    None => out.push(ftyp("iso6", ["iso6", "mp41"]))
  }
  let tracks = track_ids(moov)
  let boxes : Array[Box] = []
  for box in moov.boxes() {
    if box.is_type("trak") {
      boxes.push(strip_sample_table(box))
    } else if box.is_type("mvex") {
      // Replaced below with one that matches the tracks that are left.
    } else if box.is_type("mvhd") {
      boxes.push(with_duration(box, 0L))
    } else {
      boxes.push(box)
    }
  }
  let trex : Array[Box] = []
  for id in tracks {
    trex.push(track_extends(id))
  }
  boxes.push(Box::children("mvex", trex))
  out.push(Box::children("moov", boxes))
  encode(out)
}

///|
/// The identifiers of the tracks a movie header describes.
fn track_ids(moov : Box) -> Array[Int32] raise Mp4Error {
  let out : Array[Int32] = []
  for trak in moov.children_of("trak") {
    match trak.child("tkhd") {
      Some(tkhd) => {
        let raw = tkhd.raw()[:]
        if read_u8(raw, 0) == 1 {
          out.push(read_u32(raw, 20))
        } else {
          out.push(read_u32(raw, 12))
        }
      }
      None => ()
    }
  }
  out
}

///|
/// A `trak` with the sample table reduced to the sample description, so the
/// initialisation section describes the codec without claiming to hold frames.
fn strip_sample_table(trak : Box) -> Box {
  let boxes : Array[Box] = []
  for box in trak.boxes() {
    if box.is_type("mdia") {
      let media : Array[Box] = []
      for part in box.boxes() {
        if part.is_type("mdhd") {
          media.push(with_duration(part, 0L))
        } else if part.is_type("minf") {
          let inner : Array[Box] = []
          for piece in part.boxes() {
            if piece.is_type("stbl") {
              let kept : Array[Box] = []
              for entry in piece.boxes() {
                if entry.is_type("stsd") {
                  kept.push(entry)
                }
              }
              inner.push(Box::children("stbl", kept))
            } else {
              inner.push(piece)
            }
          }
          media.push(Box::children("minf", inner))
        } else {
          media.push(part)
        }
      }
      boxes.push(Box::children("mdia", media))
    } else if box.is_type("tkhd") {
      boxes.push(with_duration(box, 0L))
    } else if box.is_type("edts") {
      // An edit list would place the samples of a file that is no longer
      // there, so it is dropped.
    } else {
      boxes.push(box)
    }
  }
  Box::children("trak", boxes)
}

///|
/// A track extends box: what every fragment of this track will say about its
/// samples unless it says otherwise.
fn track_extends(track_id : Int32) -> Box {
  let buf = @buffer.Buffer()
  buf.write_byte(b'\x00')
  write_u24(buf, 0)
  write_u32(buf, track_id)
  write_u32(buf, 1)
  write_u32(buf, 0)
  write_u32(buf, 0)
  write_u32(buf, 0)
  Box::bytes("trex", buf.contents())
}

///|
/// The same box with its duration field set to `duration`.
///
/// The boxes that carry a duration — `mvhd`, `tkhd`, `mdhd` — put it after a
/// version and flags field and a creation and modification time, so its offset
/// depends only on the version, and a four byte field holds it in both.
fn with_duration(box : Box, duration : Int64) -> Box {
  let raw = box.raw()
  if raw.length() < 1 {
    return box
  }
  let at = if raw.at(0).to_int() == 1 { 24 } else { 16 }
  let width = if raw.at(0).to_int() == 1 { 8 } else { 4 }
  if at + width > raw.length() {
    return box
  }
  let buf = @buffer.Buffer()
  buf.write_bytes(raw[0:at])
  if width == 8 {
    write_u64(buf, duration)
  } else {
    write_u32(buf, duration.to_int())
  }
  buf.write_bytes(raw[at + width:])
  { ..box, content: Bytes(raw=buf.contents()), }
}
