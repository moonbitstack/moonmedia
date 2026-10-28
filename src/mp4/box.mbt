// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Why a file could not be read.
///
/// `at` is the offset in the file the reader had reached, `want` what the format
/// requires there and `got` what was actually there.
pub(all) suberror Mp4Error {
  Malformed(at~ : Int32, want~ : String, got~ : String)
}

///|
/// The account of a failure.
pub extend Mp4Error with Show::{to_string, output}

///|
pub impl Show for Mp4Error with fn output(self, logger) {
  let Malformed(at~, want~, got~) = self
  logger.write_string(
    "at " + at.to_string() + ": want " + want + ", got " + got,
  )
}

///|
/// What a box holds.
///
/// A box either contains smaller boxes or a run of bytes. The boxes that hold
/// both — a sample description entry is a fixed header followed by child boxes —
/// keep the fixed part in `prefix` and the children after it, so the tree stays
/// generic without losing a byte.
pub(all) enum Content {
  Children(prefix~ : Bytes, boxes~ : Array[Box])
  Bytes(raw~ : Bytes)
} derive(Eq, Debug)

///|
pub extend Content with Eq::{equal, not_equal}

///|
pub extend Content with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// One box: a type, a size and its content.
///
/// `large` remembers that the size was written as a 64-bit field rather than
/// the usual 32-bit one, because writing it back the other way would change the
/// file even though it would still be readable.
pub(all) struct Box {
  type_ : String
  usertype : Bytes?
  large : Bool
  content : Content
} derive(Eq, Debug)

///|
pub extend Box with Eq::{equal, not_equal}

///|
pub extend Box with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A box of `type_` holding smaller boxes.
pub fn Box::children(type_ : StringView, boxes : Array[Box]) -> Box {
  {
    type_: type_.to_owned(),
    usertype: None,
    large: false,
    content: Children(prefix=Bytes::new(0), boxes~),
  }
}

///|
/// A box of `type_` holding bytes.
pub fn Box::bytes(type_ : StringView, raw : Bytes) -> Box {
  {
    type_: type_.to_owned(),
    usertype: None,
    large: false,
    content: Bytes(raw~),
  }
}

///|
/// The child boxes, or an empty array for a box that holds bytes.
pub fn Box::boxes(self : Box) -> Array[Box] {
  match self.content {
    Children(boxes~, ..) => boxes
    Bytes(_) => []
  }
}

///|
/// The bytes this box holds itself, without its children.
pub fn Box::raw(self : Box) -> Bytes {
  match self.content {
    Children(prefix~, ..) => prefix
    Bytes(raw~) => raw
  }
}

///|
/// Whether this box is of the given type.
pub fn Box::is_type(self : Box, type_ : StringView) -> Bool {
  self.type_[:] == type_
}

///|
/// The first child of this box with the given type.
pub fn Box::child(self : Box, type_ : StringView) -> Box? {
  for box in self.boxes() {
    if box.is_type(type_) {
      return Some(box)
    }
  }
  None
}

///|
/// Every child of this box with the given type, in order.
pub fn Box::children_of(self : Box, type_ : StringView) -> Array[Box] {
  let out : Array[Box] = []
  for box in self.boxes() {
    if box.is_type(type_) {
      out.push(box)
    }
  }
  out
}

///|
/// The four character code as a view.
pub fn Box::fourcc(self : Box) -> StringView {
  self.type_[:]
}

///|
/// The boxes that hold smaller boxes and nothing else. Their payload is a run
/// of boxes starting at offset zero.
fn is_container(type_ : StringView) -> Bool {
  let names = [
    "moov", "trak", "mdia", "minf", "stbl", "edts", "dinf", "mvex", "moof", "traf",
    "mfra", "udta", "sinf", "schi", "tref", "meco", "hnti", "hinf", "strk", "stri",
    "ipro", "rinf", "mdis",
  ]
  for name in names {
    if type_ == name {
      return true
    }
  }
  false
}

///|
/// How many bytes a box holds before its child boxes start: a version and flags
/// field, an entry count, the fixed fields of a sample entry.
fn header_length(type_ : StringView) -> Int32? {
  // Sample entries: a fixed part, then the boxes describing the codec.
  let sample_entries = [
    ("avc1", 78),
    ("avc3", 78),
    ("hvc1", 78),
    ("hev1", 78),
    ("vp08", 78),
    ("vp09", 78),
    ("av01", 78),
    ("encv", 78),
    ("mp4v", 78),
    ("s263", 78),
    ("mp4a", 28),
    ("enca", 28),
    ("Opus", 28),
    ("fLaC", 28),
    ("ac-3", 28),
    ("ec-3", 28),
    ("alac", 28),
    ("samr", 28),
    ("ac-4", 28),
    ("wvtt", 8),
    ("stpp", 8),
    ("tx3g", 8),
    ("text", 8),
  ]
  for pair in sample_entries {
    if type_ == pair.0 {
      return Some(pair.1)
    }
  }
  let with_count = ["stsd", "dref"]
  for name in with_count {
    if type_ == name {
      return Some(8)
    }
  }
  None
}

///|
/// Whether a box with this type can hold child boxes at all.
fn has_children(type_ : StringView) -> Bool {
  is_container(type_) || header_length(type_) != None
}

///|
/// Read the boxes at the start of `data`.
///
/// Reading stops at the first byte that is not a box; a file whose last box was
/// cut short is refused rather than half-read.
pub fn parse(data : BytesView) -> Array[Box] raise Mp4Error {
  parse_boxes(data, 0, data.length())
}

///|
/// Read the boxes between `start` and `end` of `data`.
fn parse_boxes(
  data : BytesView,
  start : Int32,
  end : Int32,
) -> Array[Box] raise Mp4Error {
  let out : Array[Box] = []
  let mut at = start
  while at + 8 <= end {
    let (box, next) = parse_box(data, at, end)
    out.push(box)
    if next <= at {
      raise Malformed(
        at~,
        want="a box longer than its header",
        got=next.to_string(),
      )
    }
    at = next
  }
  if at != end {
    raise Malformed(
      at~,
      want="a box header",
      got=(end - at).to_string() + " trailing bytes",
    )
  }
  out
}

///|
/// Read one box starting at `at`, and say where the next one starts.
fn parse_box(
  data : BytesView,
  at : Int32,
  end : Int32,
) -> (Box, Int32) raise Mp4Error {
  let size32 = read_u32(data, at)
  let type_ = read_type(data, at + 4)
  let mut header = 8
  let mut size = size32
  let mut large = false
  if size32 == 1 {
    if at + 16 > end {
      raise Malformed(at~, want="a 64-bit size", got="end of file")
    }
    size = read_u64(data, at + 8).to_int()
    header = 16
    large = true
  } else if size32 == 0 {
    // A size of zero means the box runs to the end of the file.
    size = end - at
  }
  if size < header || at + size > end {
    raise Malformed(
      at~,
      want="a box of at most " + (end - at).to_string() + " bytes",
      got=size.to_string() + " bytes of type " + type_,
    )
  }
  let mut usertype : Bytes? = None
  if type_ == "uuid" {
    if at + header + 16 > end {
      raise Malformed(at~, want="a 16-byte user type", got="end of box")
    }
    usertype = Some(data[at + header:at + header + 16].to_owned())
    header = header + 16
  }
  let body_start = at + header
  let body_end = at + size
  let content = if has_children(type_[:]) {
    let prefix_length = match header_length(type_[:]) {
      Some(length) => length
      None => 0
    }
    if body_start + prefix_length > body_end {
      raise Malformed(
        at~,
        want=prefix_length.to_string() +
          " bytes before the children of " +
          type_,
        got=(body_end - body_start).to_string() + " bytes",
      )
    }
    let prefix = data[body_start:body_start + prefix_length].to_owned()
    let boxes = parse_boxes(data, body_start + prefix_length, body_end)
    Children(prefix~, boxes~)
  } else {
    Bytes(raw=data[body_start:body_end].to_owned())
  }
  ({ type_, usertype, large, content, }, at + size)
}

///|
/// Write boxes back out.
pub fn encode(boxes : Array[Box]) -> Bytes {
  let buf = @buffer.Buffer()
  for box in boxes {
    write_box(buf, box)
  }
  buf.contents()
}

///|
/// Write one box.
pub fn Box::encode(self : Box) -> Bytes {
  let buf = @buffer.Buffer()
  write_box(buf, self)
  buf.contents()
}

///|
fn write_box(buf : @buffer.Buffer, box : Box) -> Unit {
  let payload = match box.content {
    Children(prefix~, boxes~) => {
      let inner = @buffer.Buffer()
      inner.write_bytes(prefix)
      for child in boxes {
        write_box(inner, child)
      }
      inner.contents()
    }
    Bytes(raw~) => raw
  }
  let extra = match box.usertype {
    Some(_) => 16
    None => 0
  }
  let size = payload.length() + 8 + extra
  // A 32-bit size field holds anything below four gigabytes; the comparison
  // is done in 64 bits because `Int` is 32 wide and would wrap.
  if box.large || size.to_int64() > 0xFFFF_FFFFL {
    buf.write_byte(b'\x00')
    buf.write_byte(b'\x00')
    buf.write_byte(b'\x00')
    buf.write_byte(b'\x01')
    write_type(buf, box.type_)
    write_u64(buf, (size + 8).to_int64())
  } else {
    write_u32(buf, size)
    write_type(buf, box.type_)
  }
  match box.usertype {
    Some(usertype) => buf.write_bytes(usertype)
    None => ()
  }
  buf.write_bytes(payload)
}

///|
fn write_type(buf : @buffer.Buffer, type_ : StringView) -> Unit {
  let bytes = @utf8.encode(type_)
  buf.write_bytes(bytes)
  for i = bytes.length(); i < 4; i = i + 1 {
    buf.write_byte(b' ')
  }
}

///|
fn write_u32(buf : @buffer.Buffer, value : Int32) -> Unit {
  buf.write_byte(((value >> 24) & 0xFF).to_byte())
  buf.write_byte(((value >> 16) & 0xFF).to_byte())
  buf.write_byte(((value >> 8) & 0xFF).to_byte())
  buf.write_byte((value & 0xFF).to_byte())
}

///|
fn write_u24(buf : @buffer.Buffer, value : Int32) -> Unit {
  buf.write_byte(((value >> 16) & 0xFF).to_byte())
  buf.write_byte(((value >> 8) & 0xFF).to_byte())
  buf.write_byte((value & 0xFF).to_byte())
}

///|
fn write_u64(buf : @buffer.Buffer, value : Int64) -> Unit {
  for shift in [56, 48, 40, 32, 24, 16, 8, 0] {
    buf.write_byte(((value >> shift) & 0xFFL).to_int().to_byte())
  }
}

///|
/// Four bytes as a type.
fn read_type(data : BytesView, at : Int32) -> String raise Mp4Error {
  if at < 0 || at + 4 > data.length() {
    raise Malformed(at~, want="a four character code", got="end of file")
  }
  @utf8.decode_lossy(data[at:at + 4])
}

///|
fn read_u8(data : BytesView, at : Int32) -> Int32 raise Mp4Error {
  if at < 0 || at >= data.length() {
    raise Malformed(at~, want="a byte", got="end of file")
  }
  data.at(at).to_int() & 0xFF
}

///|
fn read_u16(data : BytesView, at : Int32) -> Int32 raise Mp4Error {
  (read_u8(data, at) << 8) | read_u8(data, at + 1)
}

///|
fn read_u24(data : BytesView, at : Int32) -> Int32 raise Mp4Error {
  (read_u8(data, at) << 16) |
  (read_u8(data, at + 1) << 8) |
  read_u8(data, at + 2)
}

///|
fn read_u32(data : BytesView, at : Int32) -> Int32 raise Mp4Error {
  (read_u8(data, at) << 24) |
  (read_u8(data, at + 1) << 16) |
  (read_u8(data, at + 2) << 8) |
  read_u8(data, at + 3)
}

///|
/// A 32-bit field that the format treats as signed, read through 64 bits so the
/// sign is the format's rather than the machine's.
fn read_u32_unsigned(data : BytesView, at : Int32) -> Int64 raise Mp4Error {
  let value = read_u32(data, at).to_int64() & 0xFFFF_FFFFL
  if value >= 0x8000_0000L {
    value - 0x1_0000_0000L
  } else {
    value
  }
}

///|
fn read_u64(data : BytesView, at : Int32) -> Int64 raise Mp4Error {
  let high = read_u32(data, at).to_int64()
  let low = read_u32(data, at + 4).to_int64()
  (high << 32) | low
}
