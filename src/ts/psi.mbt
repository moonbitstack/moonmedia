// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The identifier of the programme association table.
pub let table_pat : Int32 = 0x00

///|
/// The identifier of a programme map table.
pub let table_pmt : Int32 = 0x02

///|
/// A section: what the tables are made of (ISO/IEC 13818-1 §2.4.4).
///
/// The body is kept as bytes because a table's shape is fixed but its contents
/// are not, and a reader that wants the parsed form asks for `Pat::of` or
/// `Pmt::of`.
pub(all) struct Section {
  table_id : Int32
  /// The identifier of the stream the table describes.
  table_id_extension : Int32
  version : Int32
  current : Bool
  number : Int32
  last_number : Int32
  body : Bytes
} derive(Eq, Debug)

///|
pub extend Section with Eq::{equal, not_equal}

///|
pub extend Section with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Read the section that starts at `at`, and say how long it was.
pub fn Section::parse(
  data : BytesView,
  at : Int32,
) -> (Section, Int32) raise TsError {
  if at + 3 > data.length() {
    raise Malformed(at~, want="a section header", got="end of data")
  }
  let table_id = data.at(at).to_int() & 0xFF
  let length = ((data.at(at + 1).to_int() & 0xF) << 8) |
    (data.at(at + 2).to_int() & 0xFF)
  let total = 3 + length
  if at + total > data.length() {
    raise Malformed(
      at~,
      want=total.to_string() + " bytes of section",
      got=(data.length() - at).to_string() + " bytes",
    )
  }
  // Three bytes of header, then four of extension and version control, then
  // four of checksum. A short section has no room for either.
  if length < 9 {
    raise Malformed(
      at~,
      want="a section of at least 9 bytes",
      got=length.to_string(),
    )
  }
  let extension = read_u16(data, at + 3)
  let control = data.at(at + 5).to_int() & 0xFF
  let body = data[at + 8:at + total - 4].to_owned()
  let section = {
    table_id,
    table_id_extension: extension,
    version: (control >> 1) & 0x1F,
    current: (control & 0x1) != 0,
    number: data.at(at + 6).to_int() & 0xFF,
    last_number: data.at(at + 7).to_int() & 0xFF,
    body,
  }
  (section, total)
}

///|
/// Write the section back, checksum included.
pub fn Section::encode(self : Section) -> Bytes {
  let buf = @buffer.Buffer()
  buf.write_byte(self.table_id.to_byte())
  let length = 5 + self.body.length() + 4
  buf.write_byte((0xB0 | ((length >> 8) & 0xF)).to_byte())
  buf.write_byte((length & 0xFF).to_byte())
  buf.write_byte((self.table_id_extension >> 8).to_byte())
  buf.write_byte((self.table_id_extension & 0xFF).to_byte())
  buf.write_byte(
    (0xC0 | (self.version << 1) | (if self.current { 1 } else { 0 })).to_byte(),
  )
  buf.write_byte(self.number.to_byte())
  buf.write_byte(self.last_number.to_byte())
  buf.write_bytes(self.body)
  let without_check = buf.contents()
  let check = crc32(without_check[:])
  buf.write_byte(((check >> 24) & 0xFF).to_byte())
  buf.write_byte(((check >> 16) & 0xFF).to_byte())
  buf.write_byte(((check >> 8) & 0xFF).to_byte())
  buf.write_byte((check & 0xFF).to_byte())
  buf.contents()
}

///|
/// The checksum every section ends with: MPEG-2's CRC-32, which differs from
/// the one Ethernet uses in not inverting the input or the output.
pub fn crc32(data : BytesView) -> Int32 {
  let mut crc = 0xFFFF_FFFF
  for byte in data {
    crc = crc ^ ((byte.to_int() & 0xFF) << 24)
    for i = 0; i < 8; i = i + 1 {
      if (crc & 0x8000_0000) != 0 {
        crc = (crc << 1) ^ 0x04C1_1DB7
      } else {
        crc = crc << 1
      }
    }
  }
  crc
}

///|
/// Whether the section's checksum matches its contents.
pub fn Section::is_intact(self : Section) -> Bool {
  // A section whose checksum is right re-checks to zero when the checksum is
  // included, which is what the format does on purpose.
  let encoded = self.encode()
  crc32(encoded[:]) == 0
}

///|
fn read_u16(data : BytesView, at : Int32) -> Int32 raise TsError {
  if at + 2 > data.length() {
    raise Malformed(at~, want="two bytes", got="end of data")
  }
  ((data.at(at).to_int() & 0xFF) << 8) | (data.at(at + 1).to_int() & 0xFF)
}

///|
/// One entry of a programme association table.
pub(all) struct Program {
  number : Int32
  /// The identifier of the packet that carries this programme's map table, or
  /// the network information table when `number` is zero.
  pid : Int32
} derive(Eq, Debug)

///|
pub extend Program with Eq::{equal, not_equal}

///|
pub extend Program with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A programme of `number` whose map table is on `pid`.
pub fn Program::new(number : Int32, pid : Int32) -> Program {
  { number, pid, }
}

///|
/// The programme association table: which programme is on which identifier.
pub(all) struct Pat {
  transport_stream : Int32
  version : Int32
  programs : Array[Program]
} derive(Eq, Debug)

///|
pub extend Pat with Eq::{equal, not_equal}

///|
pub extend Pat with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Read a programme association table.
pub fn Pat::of(section : Section) -> Pat raise TsError {
  if section.table_id != table_pat {
    raise Malformed(
      at=0,
      want="a table with identifier 0",
      got=section.table_id.to_string(),
    )
  }
  let programs : Array[Program] = []
  let body = section.body[:]
  let mut at = 0
  while at + 4 <= body.length() {
    programs.push({
      number: read_u16(body, at),
      pid: read_u16(body, at + 2) & 0x1FFF,
    })
    at = at + 4
  }
  {
    transport_stream: section.table_id_extension,
    version: section.version,
    programs,
  }
}

///|
/// A table of `programs` for the stream `transport_stream`.
pub fn Pat::new(
  transport_stream? : Int32,
  version? : Int32,
  programs? : Array[Program],
) -> Pat {
  {
    transport_stream: transport_stream.unwrap_or(1),
    version: version.unwrap_or(0),
    programs: programs.unwrap_or([]),
  }
}

///|
/// The section a programme association table is written as.
pub fn Pat::section(self : Pat) -> Section {
  let body = @buffer.Buffer()
  for program in self.programs {
    body.write_byte(((program.number >> 8) & 0xFF).to_byte())
    body.write_byte((program.number & 0xFF).to_byte())
    body.write_byte((0xE0 | ((program.pid >> 8) & 0x1F)).to_byte())
    body.write_byte((program.pid & 0xFF).to_byte())
  }
  Section::new(
    table_id=table_pat,
    extension=self.transport_stream,
    version=self.version,
    body=body.contents(),
  )
}

///|
/// Write a programme association table.
pub fn Pat::encode(self : Pat) -> Bytes {
  self.section().encode()
}

///|
/// A section built from its parts, with one section in the set.
pub fn Section::new(
  table_id? : Int32,
  extension? : Int32,
  version? : Int32,
  number? : Int32,
  last_number? : Int32,
  body? : Bytes,
) -> Section {
  {
    table_id: table_id.unwrap_or(0),
    table_id_extension: extension.unwrap_or(0),
    version: version.unwrap_or(0),
    current: true,
    number: number.unwrap_or(0),
    last_number: last_number.unwrap_or(0),
    body: body.unwrap_or(Bytes::new(0)),
  }
}

///|
/// One elementary stream a programme carries.
pub(all) struct Stream {
  /// What the stream is: 0x1B is H.264, 0x0F is AAC in ADTS, 0x24 is HEVC.
  stream_type : Int32
  pid : Int32
  /// The descriptors as they came, tag, length and payload together.
  descriptors : Bytes
} derive(Eq, Debug)

///|
pub extend Stream with Eq::{equal, not_equal}

///|
pub extend Stream with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A stream of `stream_type` on `pid`, with the descriptors that describe it.
pub fn Stream::new(
  stream_type : Int32,
  pid : Int32,
  descriptors? : Bytes,
) -> Stream {
  { stream_type, pid, descriptors: descriptors.unwrap_or(Bytes::new(0)), }
}

///|
/// The programme map table: what a programme is made of, and which packet
/// carries its clock.
pub(all) struct Pmt {
  program : Int32
  pcr_pid : Int32
  version : Int32
  descriptors : Bytes
  streams : Array[Stream]
} derive(Eq, Debug)

///|
pub extend Pmt with Eq::{equal, not_equal}

///|
pub extend Pmt with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Read a programme map table.
pub fn Pmt::of(section : Section) -> Pmt raise TsError {
  if section.table_id != table_pmt {
    raise Malformed(
      at=0,
      want="a table with identifier 2",
      got=section.table_id.to_string(),
    )
  }
  let body = section.body[:]
  if body.length() < 4 {
    raise Malformed(
      at=0,
      want="a programme map table body",
      got=body.length().to_string() + " bytes",
    )
  }
  let pcr_pid = read_u16(body, 0) & 0x1FFF
  let info_length = read_u16(body, 2) & 0x0FFF
  if 4 + info_length > body.length() {
    raise Malformed(
      at=0,
      want="programme descriptors inside the table",
      got=info_length.to_string() + " bytes",
    )
  }
  let descriptors = body[4:4 + info_length].to_owned()
  let streams : Array[Stream] = []
  let mut at = 4 + info_length
  while at + 5 <= body.length() {
    let stream_type = body.at(at).to_int() & 0xFF
    let pid = read_u16(body, at + 1) & 0x1FFF
    let length = read_u16(body, at + 3) & 0x0FFF
    if at + 5 + length > body.length() {
      raise Malformed(
        at~,
        want="a stream's descriptors inside the table",
        got=length.to_string() + " bytes",
      )
    }
    streams.push({
      stream_type,
      pid,
      descriptors: body[at + 5:at + 5 + length].to_owned(),
    })
    at = at + 5 + length
  }
  {
    program: section.table_id_extension,
    pcr_pid,
    version: section.version,
    descriptors,
    streams,
  }
}

///|
/// A table of `streams` for programme `program`, timed by `pcr_pid`.
pub fn Pmt::new(
  program? : Int32,
  pcr_pid? : Int32,
  version? : Int32,
  descriptors? : Bytes,
  streams? : Array[Stream],
) -> Pmt {
  {
    program: program.unwrap_or(1),
    pcr_pid: pcr_pid.unwrap_or(0x100),
    version: version.unwrap_or(0),
    descriptors: descriptors.unwrap_or(Bytes::new(0)),
    streams: streams.unwrap_or([]),
  }
}

///|
/// The section a programme map table is written as.
pub fn Pmt::section(self : Pmt) -> Section {
  let body = @buffer.Buffer()
  body.write_byte((0xE0 | ((self.pcr_pid >> 8) & 0x1F)).to_byte())
  body.write_byte((self.pcr_pid & 0xFF).to_byte())
  body.write_byte((0xF0 | ((self.descriptors.length() >> 8) & 0xF)).to_byte())
  body.write_byte((self.descriptors.length() & 0xFF).to_byte())
  body.write_bytes(self.descriptors)
  for stream in self.streams {
    body.write_byte(stream.stream_type.to_byte())
    body.write_byte((0xE0 | ((stream.pid >> 8) & 0x1F)).to_byte())
    body.write_byte((stream.pid & 0xFF).to_byte())
    body.write_byte(
      (0xF0 | ((stream.descriptors.length() >> 8) & 0xF)).to_byte(),
    )
    body.write_byte((stream.descriptors.length() & 0xFF).to_byte())
    body.write_bytes(stream.descriptors)
  }
  Section::new(
    table_id=table_pmt,
    extension=self.program,
    version=self.version,
    body=body.contents(),
  )
}

///|
/// Write a programme map table.
pub fn Pmt::encode(self : Pmt) -> Bytes {
  self.section().encode()
}

///|
/// The packets that carry this section on `pid`.
///
/// A section longer than a packet is split, which a programme map table with
/// many streams does; the rest of the last packet is filled with the null byte,
/// as the format asks.
pub fn Section::packets(
  self : Section,
  pid : Int32,
  counter? : Int32,
) -> Array[Packet] {
  let bytes = self.encode()
  let out : Array[Packet] = []
  let mut at = 0
  let mut count = counter.unwrap_or(0)
  while at < bytes.length() {
    let buf = @buffer.Buffer()
    let mut room = 184
    if out.length() == 0 {
      // The first packet says how much of a previous section is still to come,
      // which is nothing here.
      buf.write_byte(b'\x00')
      room = 183
    }
    let take = if bytes.length() - at < room {
      bytes.length() - at
    } else {
      room
    }
    buf.write_bytes(bytes[at:at + take])
    at = at + take
    let padding = @buffer.Buffer()
    padding.write_bytes(buf.contents())
    for i = padding.length(); i < 184; i = i + 1 {
      padding.write_byte(b'\xFF')
    }
    out.push(
      Packet::new(
        pid,
        padding.contents(),
        counter=count,
        starts_unit=out.length() == 0,
      ),
    )
    count = (count + 1) & 0xF
  }
  out
}

///|
/// The identifier a packet's payload starts with when the packet begins a new
/// unit: the byte says how many bytes of the previous section are still to come,
/// and the section starts after them.
fn payload_after_pointer(packet : Packet) -> BytesView {
  let payload = packet.payload[:]
  if payload.length() == 0 {
    return payload
  }
  let pointer = payload.at(0).to_int() & 0xFF
  if 1 + pointer > payload.length() {
    payload[payload.length():]
  } else {
    payload[1 + pointer:]
  }
}

///|
/// The sections a PID carries, with the pointer fields taken out.
pub fn sections(
  packets : Array[Packet],
  pid : Int32,
) -> Array[Section] raise TsError {
  let out : Array[Section] = []
  let joined = @buffer.Buffer()
  for packet in packets {
    if packet.pid != pid || packet.payload.length() == 0 {
      continue
    }
    if packet.starts_unit {
      joined.write_bytes(payload_after_pointer(packet))
    } else {
      joined.write_bytes(packet.payload)
    }
  }
  let data = joined.contents()
  let mut at = 0
  while at + 3 <= data.length() {
    // Padding after the last section of a packet is 0xFF, which is not a table.
    if (data.at(at).to_int() & 0xFF) == 0xFF {
      break
    }
    let (section, length) = Section::parse(data[:], at)
    out.push(section)
    at = at + length
  }
  out
}
