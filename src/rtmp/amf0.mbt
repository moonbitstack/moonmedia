// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Why a stream could not be read.
pub(all) suberror RtmpError {
  Malformed(at~ : Int32, want~ : String, got~ : String)
}

///|
/// The account of a failure.
pub extend RtmpError with Show::{to_string, output}

///|
pub impl Show for RtmpError with fn output(self, logger) {
  let Malformed(at~, want~, got~) = self
  logger.write_string(
    "at " + at.to_string() + ": want " + want + ", got " + got,
  )
}

///|
/// The value types AMF0 defines, which is what a command is written in.
///
/// A command is a name followed by arguments, and the arguments are objects:
/// `connect` carries an object of application and version, `publish` a stream
/// name. The variants here are the ones a publish session meets; the rest of the
/// encoding — references, records, XML — is not used by any publisher and is
/// refused rather than guessed at.
pub(all) enum Amf0 {
  Number(Double)
  Boolean(Bool)
  String(String)
  Null
  Undefined
  /// An anonymous object: ordered key and value pairs.
  Object(Array[(String, Amf0)])
  /// An object that announced its size first, which JavaScript sends for event
  /// data.
  EcmaArray(Array[(String, Amf0)])
  StrictArray(Array[Amf0])
  Date(Double, Int32)
} derive(Eq, Debug)

///|
pub extend Amf0 with Eq::{equal, not_equal}

///|
pub extend Amf0 with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A number.
pub fn Amf0::number(value : Double) -> Amf0 {
  Number(value)
}

///|
/// A string.
pub fn Amf0::text(value : String) -> Amf0 {
  String(value)
}

///|
/// The value under `key`, when this is an object.
pub fn Amf0::field(self : Amf0, key : StringView) -> Amf0? {
  match self {
    Object(pairs) | EcmaArray(pairs) => {
      for pair in pairs {
        if pair.0[:] == key {
          return Some(pair.1)
        }
      }
      None
    }
    _ => None
  }
}

///|
/// The value as a string, when it is one.
pub fn Amf0::as_string(self : Amf0) -> String? {
  match self {
    String(value) => Some(value)
    _ => None
  }
}

///|
/// The value as a number, when it is one.
pub fn Amf0::as_number(self : Amf0) -> Double? {
  match self {
    Number(value) => Some(value)
    _ => None
  }
}

///|
/// The value as a boolean, when it is one.
pub fn Amf0::as_boolean(self : Amf0) -> Bool? {
  match self {
    Boolean(value) => Some(value)
    _ => None
  }
}

///|
/// The pairs of an object, empty for anything else.
pub fn Amf0::pairs(self : Amf0) -> Array[(String, Amf0)] {
  match self {
    Object(pairs) | EcmaArray(pairs) => pairs
    _ => []
  }
}

///|
/// Read a value, and say how many bytes it took.
pub fn Amf0::decode(
  data : BytesView,
  at? : Int32,
) -> (Amf0, Int32) raise RtmpError {
  decode_at(data, at.unwrap_or(0))
}

///|
fn decode_at(data : BytesView, at : Int32) -> (Amf0, Int32) raise RtmpError {
  if at >= data.length() {
    raise Malformed(at~, want="a value", got="end of data")
  }
  let marker = data.at(at).to_int() & 0xFF
  match marker {
    0x00 => {
      if at + 9 > data.length() {
        raise Malformed(at~, want="a number", got="end of data")
      }
      (Number(read_double(data, at + 1)), 9)
    }
    0x01 => {
      if at + 2 > data.length() {
        raise Malformed(at~, want="a boolean", got="end of data")
      }
      (Boolean((data.at(at + 1).to_int() & 0xFF) != 0), 2)
    }
    0x02 => {
      let (text, length) = read_text(data, at + 1, 2)
      (String(text), 1 + length)
    }
    0x03 => {
      let (pairs, length) = read_pairs(data, at + 1)
      (Object(pairs), 1 + length)
    }
    0x05 => (Null, 1)
    0x06 => (Undefined, 1)
    0x08 => {
      let (pairs, length) = read_pairs(data, at + 5)
      (EcmaArray(pairs), 5 + length)
    }
    0x0A => {
      let count = read_u32_be(data, at + 1)
      let values : Array[Amf0] = []
      let mut cursor = at + 5
      for i = 0; i < count; i = i + 1 {
        let (value, length) = decode_at(data, cursor)
        values.push(value)
        cursor = cursor + length
      }
      (StrictArray(values), cursor - at)
    }
    0x0B => {
      if at + 11 > data.length() {
        raise Malformed(at~, want="a date", got="end of data")
      }
      (Date(read_double(data, at + 1), read_i16_be(data, at + 9)), 11)
    }
    0x0C | 0x0F => {
      let (text, length) = read_text(data, at + 1, 4)
      (String(text), 1 + length)
    }
    _ =>
      raise Malformed(
        at~,
        want="an AMF0 marker",
        got=marker.to_string() + " at " + (at + 1).to_string(),
      )
  }
}

///|
/// Read `count` bytes of length prefix followed by that many bytes of text.
fn read_text(
  data : BytesView,
  at : Int32,
  count : Int32,
) -> (String, Int32) raise RtmpError {
  if at + count > data.length() {
    raise Malformed(at~, want="a string length", got="end of data")
  }
  let length = if count == 2 {
    read_u16_be(data, at)
  } else {
    read_u32_be(data, at)
  }
  if at + count + length > data.length() {
    raise Malformed(
      at~,
      want=length.to_string() + " bytes of text",
      got=(data.length() - at - count).to_string() + " bytes",
    )
  }
  (@utf8.decode_lossy(data[at + count:at + count + length]), count + length)
}

///|
/// Read key and value pairs up to the three byte terminator, which the empty key
/// followed by the object-end marker is.
fn read_pairs(
  data : BytesView,
  at : Int32,
) -> (Array[(String, Amf0)], Int32) raise RtmpError {
  let pairs : Array[(String, Amf0)] = []
  let mut cursor = at
  while true {
    if cursor + 3 > data.length() {
      raise Malformed(at=cursor, want="a property name", got="end of data")
    }
    let length = read_u16_be(data, cursor)
    cursor = cursor + 2
    if length == 0 {
      if cursor < data.length() && (data.at(cursor).to_int() & 0xFF) == 0x09 {
        cursor = cursor + 1
        break
      }
      raise Malformed(
        at=cursor,
        want="an object end marker",
        got="something else",
      )
    }
    if cursor + length > data.length() {
      raise Malformed(at=cursor, want="a property name", got="end of data")
    }
    let key = @utf8.decode_lossy(data[cursor:cursor + length])
    cursor = cursor + length
    let (value, bytes) = decode_at(data, cursor)
    pairs.push((key, value))
    cursor = cursor + bytes
  }
  (pairs, cursor - at)
}

///|
/// Write the value.
pub fn Amf0::encode(self : Amf0) -> Bytes {
  let buf = @buffer.Buffer()
  write_value(buf, self)
  buf.contents()
}

///|
fn write_value(buf : @buffer.Buffer, value : Amf0) -> Unit {
  match value {
    Number(number) => {
      buf.write_byte(b'\x00')
      write_double(buf, number)
    }
    Boolean(flag) => {
      buf.write_byte(b'\x01')
      buf.write_byte(if flag { b'\x01' } else { b'\x00' })
    }
    String(text) =>
      if text.length() > 0xFFFF {
        buf.write_byte(b'\x0C')
        write_u32_be(buf, byte_length(text))
        buf.write_string_utf8(text)
      } else {
        buf.write_byte(b'\x02')
        write_u16_be(buf, byte_length(text))
        buf.write_string_utf8(text)
      }
    Null => buf.write_byte(b'\x05')
    Undefined => buf.write_byte(b'\x06')
    Object(pairs) => {
      buf.write_byte(b'\x03')
      write_properties(buf, pairs)
    }
    EcmaArray(pairs) => {
      buf.write_byte(b'\x08')
      write_u32_be(buf, pairs.length())
      write_properties(buf, pairs)
    }
    StrictArray(values) => {
      buf.write_byte(b'\x0A')
      write_u32_be(buf, values.length())
      for value in values {
        write_value(buf, value)
      }
    }
    Date(milliseconds, zone) => {
      buf.write_byte(b'\x0B')
      write_double(buf, milliseconds)
      write_i16_be(buf, zone)
    }
  }
}

///|
/// Write the pairs of an object and the terminator that ends it.
fn write_properties(
  buf : @buffer.Buffer,
  pairs : Array[(String, Amf0)],
) -> Unit {
  for pair in pairs {
    write_u16_be(buf, byte_length(pair.0[:]))
    buf.write_string_utf8(pair.0)
    write_value(buf, pair.1)
  }
  write_u16_be(buf, 0)
  buf.write_byte(b'\x09')
}

///|
/// Write values one after another, which is how a command's arguments are laid
/// out.
pub fn encode_all(values : Array[Amf0]) -> Bytes {
  let buf = @buffer.Buffer()
  for value in values {
    write_value(buf, value)
  }
  buf.contents()
}

///|
/// Read values until the data runs out.
pub fn decode_all(data : BytesView) -> Array[Amf0] raise RtmpError {
  let out : Array[Amf0] = []
  let mut at = 0
  while at < data.length() {
    let (value, length) = decode_at(data, at)
    out.push(value)
    at = at + length
  }
  out
}

///|
fn read_u16_be(data : BytesView, at : Int32) -> Int32 raise RtmpError {
  if at + 2 > data.length() {
    raise Malformed(at~, want="two bytes", got="end of data")
  }
  ((data.at(at).to_int() & 0xFF) << 8) | (data.at(at + 1).to_int() & 0xFF)
}

///|
fn read_i16_be(data : BytesView, at : Int32) -> Int32 raise RtmpError {
  let value = read_u16_be(data, at)
  if value >= 0x8000 {
    value - 0x1_0000
  } else {
    value
  }
}

///|
fn read_u32_be(data : BytesView, at : Int32) -> Int32 raise RtmpError {
  if at + 4 > data.length() {
    raise Malformed(at~, want="four bytes", got="end of data")
  }
  ((data.at(at).to_int() & 0xFF) << 24) |
  ((data.at(at + 1).to_int() & 0xFF) << 16) |
  ((data.at(at + 2).to_int() & 0xFF) << 8) |
  (data.at(at + 3).to_int() & 0xFF)
}

///|
fn read_double(data : BytesView, at : Int32) -> Double raise RtmpError {
  if at + 8 > data.length() {
    raise Malformed(at~, want="eight bytes", got="end of data")
  }
  let high = read_u32_be(data, at)
  let low = read_u32_be(data, at + 4)
  let bits = (high.to_int64() << 32) | (low.to_int64() & 0xFFFF_FFFFL)
  bits.reinterpret_as_double()
}

///|
/// The number of bytes a string takes when it is written out, which is what an
/// AMF length counts.
fn byte_length(text : StringView) -> Int32 {
  @utf8.encode(text).length()
}

///|
fn write_u16_be(buf : @buffer.Buffer, value : Int32) -> Unit {
  buf.write_byte(((value >> 8) & 0xFF).to_byte())
  buf.write_byte((value & 0xFF).to_byte())
}

///|
fn write_i16_be(buf : @buffer.Buffer, value : Int32) -> Unit {
  write_u16_be(buf, value & 0xFFFF)
}

///|
fn write_u32_be(buf : @buffer.Buffer, value : Int32) -> Unit {
  buf.write_byte(((value >> 24) & 0xFF).to_byte())
  buf.write_byte(((value >> 16) & 0xFF).to_byte())
  buf.write_byte(((value >> 8) & 0xFF).to_byte())
  buf.write_byte((value & 0xFF).to_byte())
}

///|
fn write_double(buf : @buffer.Buffer, value : Double) -> Unit {
  let bits = value.reinterpret_as_int64()
  write_u32_be(buf, ((bits >> 32) & 0xFFFF_FFFFL).to_int())
  write_u32_be(buf, (bits & 0xFFFF_FFFFL).to_int())
}
