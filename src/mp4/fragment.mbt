// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The samples one track contributes to a fragment.
pub(all) struct Run {
  track_id : Int32
  base_decode_time : Int64
  samples : Array[Sample]
} derive(Eq, Debug)

///|
pub extend Run with Eq::{equal, not_equal}

///|
pub extend Run with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// One movie fragment: the `moof` that describes it and the media data that
/// follows, up to the next fragment.
pub(all) struct Fragment {
  sequence : Int32
  /// Offset of the `moof` in the file.
  start : Int32
  /// Offset just past the fragment's last byte.
  end : Int32
  runs : Array[Run]
} derive(Eq, Debug)

///|
pub extend Fragment with Eq::{equal, not_equal}

///|
pub extend Fragment with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The fragments of a fragmented file, in order.
///
/// A fragment runs from its `moof` to the next one, so a segment cut on a
/// fragment boundary is a run of whole boxes.
pub fn Mp4::fragments(self : Mp4) -> Array[Fragment] raise Mp4Error {
  let out : Array[Fragment] = []
  // Offsets are not carried by the tree, so they are recovered by walking the
  // top-level boxes in file order. A fragment runs to the next `moof`, which
  // means it takes the media data box after it: a fragment cut anywhere else
  // would need two requests to play.
  let starts = top_level_offsets(self.boxes)
  let moofs : Array[Int32] = []
  for i = 0; i < self.boxes.length(); i = i + 1 {
    if self.boxes[i].is_type("moof") {
      moofs.push(i)
    }
  }
  for k = 0; k < moofs.length(); k = k + 1 {
    let i = moofs[k]
    let box = self.boxes[i]
    let start = starts[i]
    let end = if k + 1 < moofs.length() {
      starts[moofs[k + 1]]
    } else {
      self.data.length()
    }
    let sequence = match box.child("mfhd") {
      Some(mfhd) => read_u32(mfhd.raw()[:], 4)
      None => 0
    }
    let runs : Array[Run] = []
    for traf in box.children_of("traf") {
      runs.push(traf_runs(traf, start, end))
    }
    out.push({ sequence, start, end, runs, })
  }
  out
}

///|
/// Where each top-level box starts in the file.
fn top_level_offsets(boxes : Array[Box]) -> Array[Int32] {
  let out : Array[Int32] = []
  let mut at = 0
  for box in boxes {
    out.push(at)
    at = at + box.byte_length()
  }
  out
}

///|
/// How many bytes this box occupies, header included.
pub fn Box::byte_length(self : Box) -> Int32 {
  let payload = self.raw().length()
  let children = match self.content {
    Children(boxes~, ..) => {
      let mut total = 0
      for child in boxes {
        total = total + child.byte_length()
      }
      total
    }
    Bytes(_) => 0
  }
  let usertype = match self.usertype {
    Some(types) => types.length()
    None => 0
  }
  let size = payload + children + 8 + usertype
  if self.large || (size + 8).to_int64() > 0xFFFF_FFFFL {
    size + 8
  } else {
    size
  }
}

///|
/// The samples one `traf` describes.
fn traf_runs(
  traf : Box,
  moof_start : Int32,
  fragment_end : Int32,
) -> Run raise Mp4Error {
  let tfhd = match traf.child("tfhd") {
    Some(box) => box.raw()[:]
    None => raise Malformed(at=moof_start, want="tfhd", got="none")
  }
  let flags = read_u24(tfhd, 1)
  let track_id = read_u32(tfhd, 4)
  let mut cursor = 8
  let base_data_offset = if (flags & 0x000001) != 0 {
    let value = read_u64(tfhd, cursor)
    cursor = cursor + 8
    Some(value.to_int())
  } else {
    None
  }
  if (flags & 0x000002) != 0 {
    cursor = cursor + 4
  }
  let default_duration = if (flags & 0x000008) != 0 {
    let value = read_u32(tfhd, cursor).to_int64()
    cursor = cursor + 4
    Some(value)
  } else {
    None
  }
  let default_size = if (flags & 0x000010) != 0 {
    let value = read_u32(tfhd, cursor)
    cursor = cursor + 4
    Some(value)
  } else {
    None
  }
  let default_flags = if (flags & 0x000020) != 0 {
    let value = read_u32(tfhd, cursor)
    cursor = cursor + 4
    Some(value)
  } else {
    None
  }
  // Without an explicit base, sample data sits in the movie fragment that
  // describes it; the older rule points at the start of the file instead.
  let base = match base_data_offset {
    Some(offset) => offset
    None => moof_start
  }
  let base_decode_time = match traf.child("tfdt") {
    Some(tfdt) => {
      let raw = tfdt.raw()[:]
      if read_u8(raw, 0) == 1 {
        read_u64(raw, 4)
      } else {
        read_u32(raw, 4).to_int64()
      }
    }
    None => 0L
  }
  let samples : Array[Sample] = []
  let mut decode_time = base_decode_time
  for trun in traf.children_of("trun") {
    let raw = trun.raw()[:]
    let flags = read_u24(raw, 1)
    let count = read_u32(raw, 4)
    let mut cursor = 8
    let data_offset = if (flags & 0x000001) != 0 {
      let value = read_u32(raw, cursor)
      cursor = cursor + 4
      Some(value)
    } else {
      None
    }
    let first_flags = if (flags & 0x000004) != 0 {
      let value = read_u32(raw, cursor)
      cursor = cursor + 4
      Some(value)
    } else {
      None
    }
    let mut offset = match data_offset {
      Some(value) => base + value
      None => base
    }
    if offset < 0 || offset > fragment_end {
      // A run that points outside its fragment cannot be read, and pretending
      // otherwise would hand a caller bytes from the wrong stream.
      raise Malformed(
        at=moof_start,
        want="sample data inside the fragment",
        got=offset.to_string(),
      )
    }
    for i = 0; i < count; i = i + 1 {
      let duration = if (flags & 0x000100) != 0 {
        let value = read_u32(raw, cursor).to_int64()
        cursor = cursor + 4
        value
      } else {
        default_duration.unwrap_or(0L)
      }
      let size = if (flags & 0x000200) != 0 {
        let value = read_u32(raw, cursor)
        cursor = cursor + 4
        value
      } else {
        default_size.unwrap_or(0)
      }
      let sample_flags = if (flags & 0x000400) != 0 {
        let value = read_u32(raw, cursor)
        cursor = cursor + 4
        value
      } else if i == 0 {
        match first_flags {
          Some(value) => value
          None => default_flags.unwrap_or(0)
        }
      } else {
        default_flags.unwrap_or(0)
      }
      let composition = if (flags & 0x000800) != 0 {
        let value = read_u32_unsigned(raw, cursor)
        cursor = cursor + 4
        value
      } else {
        0L
      }
      samples.push({
        offset,
        size,
        dts: decode_time,
        duration,
        composition_offset: composition,
        // The non-sync bit is the sixteenth from the bottom of the flags.
        sync: (sample_flags & 0x0001_0000) == 0,
      })
      offset = offset + size
      decode_time = decode_time + duration
    }
  }
  { track_id, base_decode_time, samples, }
}

///|
/// A segment index, `sidx` (ISO/IEC 14496-12 §8.16.3).
///
/// It says where the pieces of a fragmented stream are, in a form a player can
/// read without downloading them, which is how a DASH client knows what to
/// fetch next.
pub(all) struct SegmentIndex {
  reference_id : Int32
  timescale : Int64
  earliest_presentation_time : Int64
  first_offset : Int64
  references : Array[IndexReference]
} derive(Eq, Debug)

///|
pub extend SegmentIndex with Eq::{equal, not_equal}

///|
pub extend SegmentIndex with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// One piece of a segment index: how big the next piece is and how long it
/// plays, or a pointer to another index.
pub(all) struct IndexReference {
  reference_type : Bool
  subsegment_duration : Int64
  starts_with_sap : Bool
  sap_type : Int32
  sap_delta_time : Int64
} derive(Eq, Debug)

///|
pub extend IndexReference with Eq::{equal, not_equal}

///|
pub extend IndexReference with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Read a `sidx` box.
pub fn segment_index(box : Box) -> SegmentIndex raise Mp4Error {
  let raw = box.raw()[:]
  let version = read_u8(raw, 0)
  let reference_id = read_u32(raw, 4)
  let mut at = 8
  let (timescale, earliest, first_offset) = if version == 0 {
    let timescale = read_u32(raw, 8).to_int64()
    let earliest = read_u32(raw, 12).to_int64()
    at = 20
    (timescale, earliest, read_u32(raw, 16).to_int64())
  } else {
    let timescale = read_u32(raw, 8).to_int64()
    let earliest = read_u64(raw, 12)
    at = 28
    (timescale, earliest, read_u64(raw, 20))
  }
  let count = read_u16(raw, at)
  at = at + 2
  let references : Array[IndexReference] = []
  for i = 0; i < count; i = i + 1 {
    let word = read_u32(raw, at + i * 12)
    let duration = read_u32(raw, at + i * 12 + 4).to_int64()
    let sap = read_u32(raw, at + i * 12 + 8)
    references.push({
      reference_type: (word & 0x8000_0000) != 0,
      subsegment_duration: duration,
      starts_with_sap: (sap & 0x8000_0000) != 0,
      sap_type: (sap >> 28) & 0x7,
      sap_delta_time: (sap & 0x0FFF_FFFF).to_int64(),
    })
  }
  {
    reference_id,
    timescale,
    earliest_presentation_time: earliest,
    first_offset,
    references,
  }
}
