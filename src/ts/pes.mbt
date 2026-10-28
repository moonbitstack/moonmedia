// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The identifier of a video stream, `0xE0` to `0xEF`.
pub let video_stream_base : Int32 = 0xE0

///|
/// The identifier of an audio stream, `0xC0` to `0xDF`.
pub let audio_stream_base : Int32 = 0xC0

///|
/// A packetised elementary stream packet: the frame, or the piece of a frame,
/// that a stream carries (ISO/IEC 13818-1 §2.4.3.7).
///
/// The optional header is kept as bytes. It carries the timestamps a player
/// needs and a dozen flags about how the frame may be decoded, which it does
/// not; keeping the bytes means a packet read and written again is the same
/// packet, and a caller that wants a timestamp reads it with `pts`.
pub(all) struct Pes {
  stream_id : Int32
  /// The length the packet declares, header included. Zero means "until the
  /// next packet begins", which is what a video frame larger than a packet uses.
  packet_length : Int32
  /// The bits of the first flags byte: scrambling, priority, alignment.
  flags : Int32
  /// The bits of the second flags byte: which timestamps are present.
  timestamp_flags : Int32
  /// The optional fields, verbatim: timestamps and the rarer flags.
  header : Bytes
  data : Bytes
} derive(Eq, Debug)

///|
pub extend Pes with Eq::{equal, not_equal}

///|
pub extend Pes with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Whether a stream identifier of this value carries an optional header. A
/// padding stream and the private tables do not.
fn has_optional_header(stream_id : Int32) -> Bool {
  stream_id != 0xBE &&
  stream_id != 0xBF &&
  stream_id != 0xF0 &&
  stream_id != 0xF1 &&
  stream_id != 0xF2 &&
  stream_id != 0xF8 &&
  stream_id != 0xFF
}

///|
/// Read the packet that starts at `at`.
pub fn Pes::parse(data : BytesView, at? : Int32) -> Pes raise TsError {
  let at = at.unwrap_or(0)
  if at + 6 > data.length() {
    raise Malformed(at~, want="a packet header", got="end of data")
  }
  if data.at(at).to_int() != 0 ||
    data.at(at + 1).to_int() != 0 ||
    data.at(at + 2).to_int() != 1 {
    raise Malformed(at~, want="a start code of 00 00 01", got="something else")
  }
  let stream_id = data.at(at + 3).to_int() & 0xFF
  let packet_length = ((data.at(at + 4).to_int() & 0xFF) << 8) |
    (data.at(at + 5).to_int() & 0xFF)
  let mut cursor = at + 6
  if !has_optional_header(stream_id) {
    let end = if packet_length == 0 {
      data.length()
    } else {
      at + 6 + packet_length
    }
    return {
      stream_id,
      packet_length,
      flags: 0,
      timestamp_flags: 0,
      header: Bytes::new(0),
      data: data[cursor:min(end, data.length())].to_owned(),
    }
  }
  if cursor + 3 > data.length() {
    raise Malformed(
      at~,
      want="a flags byte and a header length",
      got="end of data",
    )
  }
  let flags = data.at(cursor).to_int() & 0xFF
  let timestamp_flags = data.at(cursor + 1).to_int() & 0xFF
  let header_length = data.at(cursor + 2).to_int() & 0xFF
  cursor = cursor + 3
  if cursor + header_length > data.length() {
    raise Malformed(
      at~,
      want=header_length.to_string() + " bytes of optional header",
      got=(data.length() - cursor).to_string() + " bytes",
    )
  }
  let header = data[cursor:cursor + header_length].to_owned()
  cursor = cursor + header_length
  let end = if packet_length == 0 {
    data.length()
  } else {
    at + 6 + packet_length
  }
  {
    stream_id,
    packet_length,
    flags,
    timestamp_flags,
    header,
    data: data[cursor:min(end, data.length())].to_owned(),
  }
}

///|
/// The smaller of two numbers.
fn min(a : Int32, b : Int32) -> Int32 {
  if a < b {
    a
  } else {
    b
  }
}

///|
/// Write the packet back.
pub fn Pes::encode(self : Pes) -> Bytes {
  let buf = @buffer.Buffer()
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x00')
  buf.write_byte(b'\x01')
  buf.write_byte(self.stream_id.to_byte())
  let length = if self.packet_length == 0 {
    0
  } else {
    3 + self.header.length() + self.data.length()
  }
  buf.write_byte(((length >> 8) & 0xFF).to_byte())
  buf.write_byte((length & 0xFF).to_byte())
  if has_optional_header(self.stream_id) {
    buf.write_byte(self.flags.to_byte())
    buf.write_byte(self.timestamp_flags.to_byte())
    buf.write_byte(self.header.length().to_byte())
    buf.write_bytes(self.header)
  }
  buf.write_bytes(self.data)
  buf.contents()
}

///|
/// A packet carrying `data` on `stream_id`, timed by `pts` and, when frames are
/// reordered, `dts`.
///
/// A timestamp is in units of 1/90000 second and is written as 33 bits, which
/// wraps after about 26 hours: a stream that runs longer counts in circles,
/// which is why players compare timestamps rather than sort by them.
pub fn Pes::new(
  stream_id : Int32,
  data : Bytes,
  pts? : Int64,
  dts? : Int64,
) -> Pes {
  let header = @buffer.Buffer()
  let mut flags = 0
  match dts {
    Some(dts) =>
      match pts {
        Some(pts) => {
          write_timestamp(header, pts, 0x3)
          write_timestamp(header, dts, 0x1)
          flags = 0xC0
        }
        None => {
          write_timestamp(header, dts, 0x1)
          flags = 0x80
        }
      }
    None =>
      match pts {
        Some(pts) => {
          write_timestamp(header, pts, 0x2)
          flags = 0x80
        }
        None => ()
      }
  }
  {
    stream_id,
    packet_length: 3 + header.length() + data.length(),
    flags: 0x80,
    timestamp_flags: flags,
    header: header.contents(),
    data,
  }
}

///|
/// The presentation time of the packet, in units of 1/90000 second.
pub fn Pes::pts(self : Pes) -> Int64? {
  let present = (self.timestamp_flags & 0x80) != 0
  if !present || self.header.length() < 5 {
    return None
  }
  Some(read_timestamp(self.header[:], 0))
}

///|
/// The decode time of the packet, when it differs from the presentation time.
pub fn Pes::dts(self : Pes) -> Int64? {
  let both = (self.timestamp_flags & 0xC0) == 0xC0
  if !both || self.header.length() < 10 {
    return None
  }
  Some(read_timestamp(self.header[:], 5))
}

///|
/// Write a 33 bit timestamp in the five bytes the format gives it, with the
/// marker bits that make a reader able to tell a timestamp from data.
fn write_timestamp(buf : @buffer.Buffer, value : Int64, prefix : Int32) -> Unit {
  buf.write_byte(
    ((prefix << 4) | ((value >> 29) & 0xE).to_int() | 0x1).to_byte(),
  )
  buf.write_byte(((value >> 22) & 0xFFL).to_int().to_byte())
  buf.write_byte((((value >> 14) & 0xFE).to_int() | 0x1).to_byte())
  buf.write_byte(((value >> 7) & 0xFFL).to_int().to_byte())
  buf.write_byte((((value << 1) & 0xFE).to_int() | 0x1).to_byte())
}

///|
/// Read the 33 bit timestamp at `at`.
fn read_timestamp(data : BytesView, at : Int32) -> Int64 {
  let b0 = (data.at(at).to_int() >> 1) & 0x7
  let b1 = data.at(at + 1).to_int() & 0xFF
  let b2 = (data.at(at + 2).to_int() >> 1) & 0x7F
  let b3 = data.at(at + 3).to_int() & 0xFF
  let b4 = (data.at(at + 4).to_int() >> 1) & 0x7F
  (b0.to_int64() << 30) |
  (b1.to_int64() << 22) |
  (b2.to_int64() << 15) |
  (b3.to_int64() << 7) |
  b4.to_int64()
}

///|
/// The elementary stream packets a PID carries, reassembled from its transport
/// packets.
///
/// A packet begins at a transport packet whose payload starts a unit, and ends
/// where its own length says or, when the length is zero, where the next one
/// begins.
pub fn pes_packets(
  packets : Array[Packet],
  pid : Int32,
) -> Array[Pes] raise TsError {
  let out : Array[Pes] = []
  let joined = @buffer.Buffer()
  let mut open = false
  for packet in packets {
    if packet.pid != pid || packet.payload.length() == 0 {
      continue
    }
    if packet.starts_unit {
      if open {
        out.push(Pes::parse(joined.contents()[:]))
        joined.reset()
      }
      open = true
    }
    if open {
      joined.write_bytes(packet.payload)
    }
  }
  if open && joined.length() > 0 {
    out.push(Pes::parse(joined.contents()[:]))
  }
  out
}
