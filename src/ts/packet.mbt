// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The size of every transport stream packet. The format has no other size.
pub let packet_size : Int32 = 188

///|
/// The byte every packet starts with.
pub let sync_byte : Int32 = 0x47

///|
/// The programme association table always arrives on this identifier.
pub let pat_pid : Int32 = 0x0000

///|
/// No packet carries this identifier: it is the null packet, put in to keep the
/// bit rate up when there is nothing to send.
pub let null_pid : Int32 = 0x1FFF

///|
/// Why a stream could not be read.
///
/// `at` is the offset of the packet the reader was in, `want` what the format
/// requires there and `got` what was there.
pub(all) suberror TsError {
  Malformed(at~ : Int32, want~ : String, got~ : String)
}

///|
/// The account of a failure.
pub extend TsError with Show::{to_string, output}

///|
pub impl Show for TsError with fn output(self, logger) {
  let Malformed(at~, want~, got~) = self
  logger.write_string(
    "at " + at.to_string() + ": want " + want + ", got " + got,
  )
}

///|
/// The adaptation field: the extra room a packet uses when its payload is
/// shorter than 184 bytes, and where the programme clock reference travels.
///
/// The field is kept as the bytes it was, because half of it is flags for
/// features that are rare enough to be worth not modelling; the accessors read
/// the parts that matter and a caller that needs more reads `raw`.
pub(all) struct Adaptation {
  /// The field after its length byte, stuffing included.
  raw : Bytes
} derive(Eq, Debug)

///|
pub extend Adaptation with Eq::{equal, not_equal}

///|
pub extend Adaptation with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// An adaptation field with nothing set, long enough to hold `stuffing` bytes.
pub fn Adaptation::new(stuffing? : Int32) -> Adaptation {
  let length = stuffing.unwrap_or(0)
  let buf = @buffer.Buffer()
  if length > 0 {
    buf.write_byte(b'\x00')
    for i = 0; i < length - 1; i = i + 1 {
      buf.write_byte(b'\xFF')
    }
  }
  { raw: buf.contents(), }
}

///|
/// An adaptation field carrying a programme clock reference.
///
/// The clock is 33 bits of 90 kHz plus a 9 bit extension, so that a decoder can
/// line up several streams to a fraction of a frame.
pub fn Adaptation::with_pcr(pcr : Int64, stuffing? : Int32) -> Adaptation {
  let base = pcr >> 9
  let extension = pcr & 0x1FFL
  let stuffing = stuffing.unwrap_or(0)
  let buf = @buffer.Buffer()
  // The discontinuity, random access and priority flags stay clear: this field
  // only carries the clock.
  buf.write_byte(b'\x10')
  // 33 bits of clock, six reserved bits, nine bits of extension.
  buf.write_byte(((base >> 25) & 0xFFL).to_int().to_byte())
  buf.write_byte(((base >> 17) & 0xFFL).to_int().to_byte())
  buf.write_byte(((base >> 9) & 0xFFL).to_int().to_byte())
  buf.write_byte(((base >> 1) & 0xFFL).to_int().to_byte())
  buf.write_byte(
    (((base & 0x1L) << 7) | 0x7EL | ((extension >> 8) & 0x1L))
    .to_int()
    .to_byte(),
  )
  buf.write_byte((extension & 0xFFL).to_int().to_byte())
  for i = 0; i < stuffing; i = i + 1 {
    buf.write_byte(b'\xFF')
  }
  { raw: buf.contents(), }
}

///|
/// The field's length in bytes, the length byte not counted.
pub fn Adaptation::length(self : Adaptation) -> Int32 {
  self.raw.length()
}

///|
/// Whether the stream is discontinuous at this packet.
pub fn Adaptation::discontinuity(self : Adaptation) -> Bool {
  (self.flags() & 0x80) != 0
}

///|
/// Whether a decoder may start here.
pub fn Adaptation::random_access(self : Adaptation) -> Bool {
  (self.flags() & 0x40) != 0
}

///|
/// The programme clock reference, in units of 1/27000000 second, when the packet
/// carries one.
///
/// The format stores 33 bits of a 90 kHz clock and nine bits of extension, which
/// together count a 27 MHz clock: dividing by 27_000_000 gives seconds, and
/// dividing by 300 gives the 90 kHz count that timestamps use.
pub fn Adaptation::pcr(self : Adaptation) -> Int64? {
  if (self.flags() & 0x10) == 0 || self.raw.length() < 7 {
    return None
  }
  let at = self.raw
  let base = ((at.at(1).to_int() & 0xFF).to_int64() << 25) |
    ((at.at(2).to_int() & 0xFF).to_int64() << 17) |
    ((at.at(3).to_int() & 0xFF).to_int64() << 9) |
    ((at.at(4).to_int() & 0xFF).to_int64() << 1) |
    ((at.at(5).to_int() >> 7) & 0x1).to_int64()
  let extension = (((at.at(5).to_int() & 0x1) << 8) | (at.at(6).to_int() & 0xFF)).to_int64()
  let value = (base << 9) | extension
  Some(value)
}

///|
/// The flags byte, or zero when the field is empty.
fn Adaptation::flags(self : Adaptation) -> Int32 {
  if self.raw.length() == 0 {
    0
  } else {
    self.raw.at(0).to_int() & 0xFF
  }
}

///|
/// How many bytes of the field are stuffing.
pub fn Adaptation::stuffing(self : Adaptation) -> Int32 {
  if self.raw.length() == 0 {
    0
  } else {
    self.raw.length() - 1
  }
}

///|
/// One transport stream packet: a fixed 188 bytes, of which four or more are
/// header, and the rest either adaptation field or payload.
pub(all) struct Packet {
  /// The packet had an error crossing the network.
  error : Bool
  /// A new unit of the stream starts in this packet's payload.
  starts_unit : Bool
  priority : Bool
  pid : Int32
  scrambling : Int32
  counter : Int32
  adaptation : Adaptation?
  /// The payload as it sits in the packet, which for a partial packet is a
  /// piece of a unit and not the unit itself.
  payload : Bytes
} derive(Eq, Debug)

///|
pub extend Packet with Eq::{equal, not_equal}

///|
pub extend Packet with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A packet of `pid` carrying `payload`, with no adaptation field.
pub fn Packet::new(
  pid : Int32,
  payload : Bytes,
  counter? : Int32,
  starts_unit? : Bool,
) -> Packet {
  {
    error: false,
    starts_unit: starts_unit.unwrap_or(false),
    priority: false,
    pid,
    scrambling: 0,
    counter: counter.unwrap_or(0),
    adaptation: None,
    payload,
  }
}

///|
/// Whether this packet carries the programme association table.
pub fn Packet::is_pat(self : Packet) -> Bool {
  self.pid == pat_pid
}

///|
/// Whether this packet carries nothing.
pub fn Packet::is_null(self : Packet) -> Bool {
  self.pid == null_pid
}

///|
/// Read the packet at the start of `data`.
pub fn Packet::parse(data : BytesView) -> Packet raise TsError {
  Packet::parse_at(data, 0, 0)
}

///|
/// Read the packet at `at`, with `origin` the offset of `data` in the stream so
/// that an error names a place the caller can find.
pub fn Packet::parse_at(
  data : BytesView,
  at : Int32,
  origin : Int32,
) -> Packet raise TsError {
  if at + packet_size > data.length() {
    raise Malformed(
      at=origin + at,
      want="a 188 byte packet",
      got=(data.length() - at).to_string() + " bytes",
    )
  }
  if (data.at(at).to_int() & 0xFF) != sync_byte {
    raise Malformed(
      at=origin + at,
      want="a packet starting with 0x47",
      got=hex_byte(data.at(at)),
    )
  }
  let b1 = data.at(at + 1).to_int() & 0xFF
  let b2 = data.at(at + 2).to_int() & 0xFF
  let b3 = data.at(at + 3).to_int() & 0xFF
  let error = (b1 & 0x80) != 0
  let starts_unit = (b1 & 0x40) != 0
  let priority = (b1 & 0x20) != 0
  let pid = ((b1 & 0x1F) << 8) | b2
  let scrambling = (b3 >> 6) & 0x3
  let control = (b3 >> 4) & 0x3
  let counter = b3 & 0x0F
  if control == 0 {
    // Reserved in the standard, and a stream that uses it is not a stream this
    // reader can carry on with.
    raise Malformed(
      at=origin + at,
      want="a payload or an adaptation field",
      got="neither",
    )
  }
  let mut cursor = at + 4
  let mut adaptation : Adaptation? = None
  if (control & 0x2) != 0 {
    let length = data.at(cursor).to_int() & 0xFF
    if cursor + 1 + length > at + packet_size {
      raise Malformed(
        at=origin + at,
        want="an adaptation field inside the packet",
        got=length.to_string() + " bytes",
      )
    }
    adaptation = Some({ raw: data[cursor + 1:cursor + 1 + length].to_owned(), })
    cursor = cursor + 1 + length
  }
  let payload = if (control & 0x1) != 0 && cursor <= at + packet_size {
    data[cursor:at + packet_size].to_owned()
  } else {
    Bytes::new(0)
  }
  {
    error,
    starts_unit,
    priority,
    pid,
    scrambling,
    counter,
    adaptation,
    payload,
  }
}

///|
/// Read every packet of `data`.
///
/// A stream that loses its sync is refused: the reader could search for the next
/// 0x47, but a transport stream that lost its alignment is a stream whose
/// packets have already been dropped, and guessing hides that.
pub fn parse(data : BytesView) -> Array[Packet] raise TsError {
  let out : Array[Packet] = []
  let mut at = 0
  while at + packet_size <= data.length() {
    out.push(Packet::parse_at(data, at, 0))
    at = at + packet_size
  }
  if at != data.length() {
    raise Malformed(
      at~,
      want="a whole number of packets",
      got=(data.length() - at).to_string() + " trailing bytes",
    )
  }
  out
}

///|
/// Write the packet back as 188 bytes.
pub fn Packet::encode(self : Packet) -> Bytes {
  let buf = @buffer.Buffer()
  let payload_length = self.payload.length()
  let adaptation_length = match self.adaptation {
    Some(adaptation) => adaptation.raw.length() + 1
    None => 0
  }
  let control = if adaptation_length > 0 && payload_length > 0 {
    0x3
  } else if adaptation_length > 0 {
    0x2
  } else {
    0x1
  }
  buf.write_byte(sync_byte.to_byte())
  let mut b1 = self.pid >> 8
  if self.error {
    b1 = b1 | 0x80
  }
  if self.starts_unit {
    b1 = b1 | 0x40
  }
  if self.priority {
    b1 = b1 | 0x20
  }
  buf.write_byte(b1.to_byte())
  buf.write_byte((self.pid & 0xFF).to_byte())
  buf.write_byte(
    (((self.scrambling & 0x3) << 6) | (control << 4) | (self.counter & 0xF)).to_byte(),
  )
  match self.adaptation {
    Some(adaptation) => {
      buf.write_byte(adaptation.raw.length().to_byte())
      buf.write_bytes(adaptation.raw)
    }
    None => ()
  }
  buf.write_bytes(self.payload)
  let written = buf.contents()
  if written.length() >= packet_size {
    return written[0:packet_size].to_owned()
  }
  // A packet with room to spare is filled with the null byte, which is what the
  // format means by stuffing at the end of a packet.
  let padded = @buffer.Buffer()
  padded.write_bytes(written)
  for i = written.length(); i < packet_size; i = i + 1 {
    padded.write_byte(b'\xFF')
  }
  padded.contents()
}

///|
/// Two hex digits.
fn hex_byte(value : Byte) -> String {
  let digits = "0123456789abcdef"
  let byte = value.to_int() & 0xFF
  "0x" +
  digits[byte >> 4:(byte >> 4) + 1].to_owned() +
  digits[byte & 0xF:(byte & 0xF) + 1].to_owned()
}

///|
/// The continuity counter of the next packet of a stream identifier, which is
/// how a demultiplexer notices that a packet was lost.
///
/// A counter only advances on packets that carry a payload, and repeats when a
/// packet is repeated, so the rule is a function of the packet rather than of
/// the count.
pub fn next_counter(previous : Int32, packet : Packet) -> Int32 {
  if packet.adaptation != None && packet.payload.length() == 0 {
    previous
  } else {
    (previous + 1) & 0xF
  }
}

///|
/// Whether `packet` follows `previous` without a gap.
pub fn continues(from : Packet, to : Packet) -> Bool {
  if from.pid != to.pid {
    return false
  }
  let expected = next_counter(from.counter, from)
  expected == to.counter
}
