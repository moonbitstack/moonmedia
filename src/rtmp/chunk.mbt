// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The message that sets how large a chunk may be.
pub let msg_set_chunk_size : Int32 = 1

///|
/// The message that says a stream was abandoned part way through a message.
pub let msg_abort : Int32 = 2

///|
/// The message that acknowledges how much has been received.
pub let msg_acknowledgement : Int32 = 3

///|
/// The message that carries a user control event, such as a ping.
pub let msg_user_control : Int32 = 4

///|
/// The message that says how large the sender's window is.
pub let msg_window_ack_size : Int32 = 5

///|
/// The message that sets how much bandwidth the peer may use.
pub let msg_set_peer_bandwidth : Int32 = 6

///|
/// An audio message.
pub let msg_audio : Int32 = 8

///|
/// A video message.
pub let msg_video : Int32 = 9

///|
/// A message of data, which is how metadata is sent.
pub let msg_data : Int32 = 18

///|
/// A command, which is how a session is set up.
pub let msg_command : Int32 = 20

///|
/// The default chunk size, before either side says otherwise.
pub let default_chunk_size : Int32 = 128

///|
/// A message: what a chunk stream carries once its chunks are put back together.
pub(all) struct Message {
  type_ : Int32
  stream_id : Int32
  /// Milliseconds, and the same for every chunk of the message.
  timestamp : Int32
  payload : Bytes
} derive(Eq, Debug)

///|
pub extend Message with Eq::{equal, not_equal}

///|
pub extend Message with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A message of `type_` on `stream_id`, carrying `payload`.
pub fn Message::new(
  type_ : Int32,
  stream_id : Int32,
  payload : Bytes,
  timestamp? : Int32,
) -> Message {
  { type_, stream_id, timestamp: timestamp.unwrap_or(0), payload, }
}

///|
/// What a reader remembers about one chunk stream between chunks.
///
/// This is bookkeeping, not a thing to be held: a caller reads messages, and
/// never touches the per-stream state that put them together.
#doc(hidden)
pub struct Stream {
  mut timestamp : Int32
  mut length : Int32
  mut type_ : Int32
  mut stream_id : Int32
  mut extended : Bool
  body : @buffer.Buffer
}

///|
fn Stream::new() -> Stream {
  {
    timestamp: 0,
    length: 0,
    type_: 0,
    stream_id: 0,
    extended: false,
    body: @buffer.Buffer(),
  }
}

///|
/// Reads chunks back into messages.
///
/// A chunk stream is stateful: after the first chunk of a message, the ones that
/// follow only carry a few bytes of header, because the type, length and stream
/// are still what they were. The reader keeps that state per chunk stream, which
/// is why it has to see the bytes in order.
pub struct ChunkReader {
  pending : @buffer.Buffer
  streams : Array[Stream]
  mut chunk_size : Int32
}

///|
/// A reader that knows nothing yet.
pub fn ChunkReader::new() -> ChunkReader {
  { pending: @buffer.Buffer(), streams: [], chunk_size: default_chunk_size, }
}

///|
/// Set the chunk size the peer announced, which applies to the chunks after the
/// message that announced it.
pub fn ChunkReader::set_chunk_size(self : ChunkReader, size : Int32) -> Unit {
  if size > 0 {
    self.chunk_size = size
  }
}

///|
fn ChunkReader::stream(self : ChunkReader, id : Int32) -> Stream {
  while self.streams.length() <= id {
    self.streams.push(Stream::new())
  }
  self.streams[id]
}

///|
/// Add bytes and take out the messages they complete.
///
/// A message split across several reads is held until its last chunk arrives;
/// a message larger than the chunk size is split by the sender and put back
/// together here.
///
/// The chunk size is framing rather than content, so it is applied here, as the
/// bytes are read: a message that announces a new size is followed by chunks
/// that already use it, and a reader that waited for its caller to notice would
/// mis-read every one of them.
pub fn ChunkReader::push(
  self : ChunkReader,
  data : BytesView,
) -> Array[Message] {
  self.pending.write_bytes(data)
  let out : Array[Message] = []
  while true {
    let bytes = self.pending.contents()
    match self.read_one(bytes[:]) {
      Some((message, used)) => {
        // Drop what was consumed by rebuilding the buffer from the rest.
        let rest = @buffer.Buffer()
        rest.write_bytes(bytes[used:])
        self.pending.reset()
        self.pending.write_bytes(rest.contents())
        match message {
          Some(message) => {
            if message.type_ == msg_set_chunk_size &&
              message.payload.length() >= 4 {
              let size = ((message.payload.at(0).to_int() & 0xFF) << 24) |
                ((message.payload.at(1).to_int() & 0xFF) << 16) |
                ((message.payload.at(2).to_int() & 0xFF) << 8) |
                (message.payload.at(3).to_int() & 0xFF)
              self.set_chunk_size(size & 0x7FFF_FFFF)
            }
            out.push(message)
          }
          None => ()
        }
      }
      None => break
    }
  }
  out
}

///|
/// Read one chunk, when the bytes for it are all there. The message is returned
/// only when the chunk completes one.
fn ChunkReader::read_one(
  self : ChunkReader,
  data : BytesView,
) -> (Message?, Int32)? {
  if data.length() < 1 {
    return None
  }
  let b0 = data.at(0).to_int() & 0xFF
  let format = (b0 >> 6) & 0x3
  let id = b0 & 0x3F
  let mut cursor = 1
  let chunk_id = if id == 0 {
    if data.length() < 2 {
      return None
    }
    let value = (data.at(1).to_int() & 0xFF) + 64
    cursor = 2
    value
  } else if id == 1 {
    if data.length() < 3 {
      return None
    }
    let value = (data.at(1).to_int() & 0xFF) +
      (data.at(2).to_int() & 0xFF) * 256 +
      64
    cursor = 3
    value
  } else {
    id
  }
  let stream = self.stream(chunk_id)
  // The message header, sized by the format: a full one, then three narrower
  // ones that lean on what the last message said.
  let mut timestamp_field = 0
  if format <= 2 {
    if cursor + 3 > data.length() {
      return None
    }
    timestamp_field = ((data.at(cursor).to_int() & 0xFF) << 16) |
      ((data.at(cursor + 1).to_int() & 0xFF) << 8) |
      (data.at(cursor + 2).to_int() & 0xFF)
    cursor = cursor + 3
  }
  if format <= 1 {
    if cursor + 4 > data.length() {
      return None
    }
    let length = ((data.at(cursor).to_int() & 0xFF) << 16) |
      ((data.at(cursor + 1).to_int() & 0xFF) << 8) |
      (data.at(cursor + 2).to_int() & 0xFF)
    let type_ = data.at(cursor + 3).to_int() & 0xFF
    cursor = cursor + 4
    if format == 0 {
      if cursor + 4 > data.length() {
        return None
      }
      // The stream identifier is little endian, alone among the fields here.
      let stream_id = (data.at(cursor).to_int() & 0xFF) |
        ((data.at(cursor + 1).to_int() & 0xFF) << 8) |
        ((data.at(cursor + 2).to_int() & 0xFF) << 16) |
        ((data.at(cursor + 3).to_int() & 0xFF) << 24)
      cursor = cursor + 4
      stream.stream_id = stream_id
      stream.timestamp = timestamp_field
    } else {
      stream.timestamp = stream.timestamp + timestamp_field
    }
    stream.length = length
    stream.type_ = type_
  } else if format == 2 {
    stream.timestamp = stream.timestamp + timestamp_field
  }
  // A timestamp too large for three bytes is written in four after them, and is
  // repeated on every chunk of the message.
  let mut extended = stream.extended
  if format <= 2 {
    if timestamp_field == 0xFF_FFFF {
      extended = true
    } else {
      extended = false
    }
    stream.extended = extended
  }
  if extended {
    if cursor + 4 > data.length() {
      return None
    }
    let value = ((data.at(cursor).to_int() & 0xFF) << 24) |
      ((data.at(cursor + 1).to_int() & 0xFF) << 16) |
      ((data.at(cursor + 2).to_int() & 0xFF) << 8) |
      (data.at(cursor + 3).to_int() & 0xFF)
    cursor = cursor + 4
    if format == 0 {
      stream.timestamp = value
    } else if format <= 2 {
      stream.timestamp = stream.timestamp - timestamp_field + value
    }
  }
  let remaining = stream.length - stream.body.length()
  let take = if remaining < self.chunk_size {
    remaining
  } else {
    self.chunk_size
  }
  if data.length() < cursor + take {
    return None
  }
  stream.body.write_bytes(data[cursor:cursor + take])
  cursor = cursor + take
  if stream.body.length() < stream.length {
    return Some((None, cursor))
  }
  let message = {
    type_: stream.type_,
    stream_id: stream.stream_id,
    timestamp: stream.timestamp,
    payload: stream.body.contents(),
  }
  stream.body.reset()
  Some((Some(message), cursor))
}

///|
/// Writes messages as chunks.
pub(all) struct ChunkWriter {
  mut chunk_size : Int32
}

///|
/// A writer that splits at the default chunk size.
pub fn ChunkWriter::new() -> ChunkWriter {
  { chunk_size: default_chunk_size, }
}

///|
/// The chunks one message becomes: a full header, then a continuation header for
/// each chunk after the first.
pub fn ChunkWriter::write(
  self : ChunkWriter,
  message : Message,
  chunk_id? : Int32,
) -> Bytes {
  let chunk_id = chunk_id.unwrap_or(
    if message.type_ == msg_command && message.stream_id == 0 {
      3
    } else if message.type_ == msg_audio {
      4
    } else if message.type_ == msg_video {
      6
    } else if message.type_ == msg_data {
      5
    } else {
      4
    },
  )
  let buf = @buffer.Buffer()
  let extended = message.timestamp >= 0xFF_FFFF
  write_basic_header(buf, 0, chunk_id)
  if extended {
    write_u24(buf, 0xFF_FFFF)
  } else {
    write_u24(buf, message.timestamp)
  }
  write_u24(buf, message.payload.length())
  buf.write_byte(message.type_.to_byte())
  // Little endian, unlike everything around it.
  buf.write_byte((message.stream_id & 0xFF).to_byte())
  buf.write_byte(((message.stream_id >> 8) & 0xFF).to_byte())
  buf.write_byte(((message.stream_id >> 16) & 0xFF).to_byte())
  buf.write_byte(((message.stream_id >> 24) & 0xFF).to_byte())
  if extended {
    write_u32(buf, message.timestamp)
  }
  let payload = message.payload[:]
  let mut at = 0
  let mut first = true
  while at < payload.length() {
    if !first {
      write_basic_header(buf, 3, chunk_id)
      if extended {
        write_u32(buf, message.timestamp)
      }
    }
    let take = if payload.length() - at < self.chunk_size {
      payload.length() - at
    } else {
      self.chunk_size
    }
    buf.write_bytes(payload[at:at + take])
    at = at + take
    first = false
  }
  if payload.length() == 0 {
    // A message with no payload is still a message, and still needs its header.
    ()
  }
  buf.contents()
}

///|
/// A chunk's basic header: the format and the chunk stream identifier, in one
/// byte when the identifier fits.
fn write_basic_header(
  buf : @buffer.Buffer,
  format : Int32,
  chunk_id : Int32,
) -> Unit {
  if chunk_id < 64 {
    buf.write_byte(((format << 6) | chunk_id).to_byte())
  } else if chunk_id < 320 {
    buf.write_byte(((format << 6) | 0).to_byte())
    buf.write_byte((chunk_id - 64).to_byte())
  } else {
    buf.write_byte(((format << 6) | 1).to_byte())
    let value = chunk_id - 64
    buf.write_byte((value & 0xFF).to_byte())
    buf.write_byte(((value >> 8) & 0xFF).to_byte())
  }
}

///|
fn write_u24(buf : @buffer.Buffer, value : Int32) -> Unit {
  buf.write_byte(((value >> 16) & 0xFF).to_byte())
  buf.write_byte(((value >> 8) & 0xFF).to_byte())
  buf.write_byte((value & 0xFF).to_byte())
}

///|
fn write_u32(buf : @buffer.Buffer, value : Int32) -> Unit {
  buf.write_byte(((value >> 24) & 0xFF).to_byte())
  buf.write_byte(((value >> 16) & 0xFF).to_byte())
  buf.write_byte(((value >> 8) & 0xFF).to_byte())
  buf.write_byte((value & 0xFF).to_byte())
}

///|
/// A protocol control message: a payload of four bytes in most cases, on stream
/// zero, which is where control messages live.
pub fn control(type_ : Int32, payload : Bytes) -> Message {
  Message::new(type_, 0, payload)
}

///|
/// The message that sets the chunk size, which applies to the chunks that follow
/// it and not to itself.
pub fn set_chunk_size(size : Int32) -> Message {
  let buf = @buffer.Buffer()
  write_u32(buf, size)
  control(msg_set_chunk_size, buf.contents())
}

///|
/// The message that says how many bytes may be in flight.
pub fn window_ack_size(size : Int32) -> Message {
  let buf = @buffer.Buffer()
  write_u32(buf, size)
  control(msg_window_ack_size, buf.contents())
}

///|
/// The message that tells the peer how much bandwidth it may use, and how it
/// should react when it goes over.
pub fn set_peer_bandwidth(size : Int32, limit : Int32) -> Message {
  let buf = @buffer.Buffer()
  write_u32(buf, size)
  buf.write_byte(limit.to_byte())
  control(msg_set_peer_bandwidth, buf.contents())
}

///|
/// The message that acknowledges a peer's bytes, which a publisher sends when it
/// has received the window it announced.
pub fn acknowledgement(sequence : Int32) -> Message {
  let buf = @buffer.Buffer()
  write_u32(buf, sequence)
  control(msg_acknowledgement, buf.contents())
}

///|
/// The user control event that answers a ping with a pong.
pub fn pong(timestamp : Int32) -> Message {
  let buf = @buffer.Buffer()
  let event = 0x0007
  buf.write_byte(((event >> 8) & 0xFF).to_byte())
  buf.write_byte((event & 0xFF).to_byte())
  write_u32(buf, timestamp)
  control(msg_user_control, buf.contents())
}
