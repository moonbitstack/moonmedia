// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
test "a value survives a round trip through its encoding" {
  let value = Amf0::Object([
    ("app", Amf0::String("live")),
    ("tcUrl", Amf0::String("rtmp://127.0.0.1/live")),
    ("fpad", Amf0::Boolean(false)),
    ("audioCodecs", Amf0::Number(3575.0)),
    ("videoCodecs", Amf0::Number(252.0)),
    ("stage", Amf0::Null),
  ])
  let bytes = value.encode()
  let (back, length) = Amf0::decode(bytes[:])
  assert_eq(back, value)
  assert_eq(length, bytes.length())
  // A number is eight bytes of IEEE 754 after its marker, and a boolean is one.
  assert_eq(Amf0::Number(1.0).encode().length(), 9)
  assert_eq(Amf0::Boolean(true).encode().length(), 2)
  // A short string carries a two byte length, a long one four.
  assert_eq(Amf0::String("abc").encode().length(), 6)
  let long = Amf0::String("x".repeat(70_000))
  assert_eq(long.encode().length(), 1 + 4 + 70_000)
  assert_eq(Amf0::decode(long.encode()[:]).0, long)
}

///|
test "a command is a name followed by its arguments" {
  let payload = encode_all([
    Amf0::String("connect"),
    Amf0::Number(1.0),
    Amf0::Object([("app", Amf0::String("live"))]),
  ])
  let values = decode_all(payload[:])
  assert_eq(values.length(), 3)
  assert_eq(values[0].as_string(), Some("connect"))
  assert_eq(values[2].field("app").unwrap().as_string(), Some("live"))
}

///|
test "a message larger than a chunk comes back whole" {
  let writer = ChunkWriter::new()
  let payload = Bytes::makei(1000, i => (i & 0xFF).to_byte())
  let message = Message::new(msg_video, 1, payload, timestamp=1234)
  let bytes = writer.write(message)
  // 1000 bytes at 128 a chunk is eight chunks, each with a header of its own.
  assert_true(bytes.length() > 1000)
  let reader = ChunkReader::new()
  let messages = reader.push(bytes[:])
  assert_eq(messages.length(), 1)
  assert_eq(messages[0].type_, msg_video)
  assert_eq(messages[0].stream_id, 1)
  assert_eq(messages[0].timestamp, 1234)
  assert_eq(messages[0].payload, payload)
}

///|
test "a message that arrives a byte at a time still comes back whole" {
  let writer = ChunkWriter::new()
  let message = Message::new(msg_command, 0, Amf0::String("hi").encode())
  let bytes = writer.write(message)
  let reader = ChunkReader::new()
  let out : Array[Message] = []
  for i = 0; i < bytes.length(); i = i + 1 {
    for message in reader.push(bytes[i:i + 1]) {
      out.push(message)
    }
  }
  assert_eq(out.length(), 1)
  assert_eq(out[0].payload, message.payload)
}

///|
test "a chunk size announced by the peer is used from then on" {
  let writer = ChunkWriter::new()
  let payload = Bytes::makei(400, i => (i & 0xFF).to_byte())
  let announce = set_chunk_size(400)
  let reader = ChunkReader::new()
  // Written at the default size, the announcement itself is one chunk.
  assert_eq(reader.push(writer.write(announce)[:]).length(), 1)
  // The peer's next message is written at the size it announced.
  writer.chunk_size = 400
  let small = writer.write(Message::new(msg_video, 1, payload))
  reader.set_chunk_size(400)
  let messages = reader.push(small[:])
  assert_eq(messages.length(), 1)
  assert_eq(messages[0].payload, payload)
}

///|
test "the handshake echoes what each side sent" {
  let client = client_start(
    0,
    random=Bytes::makei(1528, i => (i & 0xFF).to_byte()),
  )
  let server = Handshake::new()
  let answer = server.answer(client[:], time=0)
  assert_eq(answer.length(), 1 + 1536 + 1536)
  assert_eq(answer.at(0).to_int(), 3)
  // The server's answer ends with the client's block, unchanged.
  assert_eq(answer[1 + 1536:], client[1:])
  let c2 = client_finish(answer[:])
  server.complete_with(c2[:])
  assert_eq(server.is_complete(), true)
}

///|
test "panic: a client that echoes the wrong block is refused" {
  let client = client_start(0)
  let server = Handshake::new(
    random=Bytes::makei(1528, i => (i & 0xFF).to_byte()),
  )
  let _ = server.answer(client[:])
  server.complete_with(Bytes::new(1536))
}

///|
/// The commands a publisher sends, in the order ffmpeg sends them.
fn connect_command(app : StringView) -> Message {
  Message::new(
    msg_command,
    0,
    encode_all([
      Amf0::String("connect"),
      Amf0::Number(1.0),
      Amf0::Object([
        ("app", Amf0::String(app.to_owned())),
        ("type", Amf0::String("nonprivate")),
        ("flashVer", Amf0::String("FMLE/3.0 (compatible; Lavf60.16)")),
        ("tcUrl", Amf0::String("rtmp://127.0.0.1:1935/" + app.to_owned())),
      ]),
    ]),
  )
}

///|
/// The name of a command in a message, when it is one.
fn command_of(message : Message) -> String? {
  let values = decode_all(message.payload[:]) catch { _ => return None }
  match values {
    [Amf0::String(name), ..] => Some(name)
    _ => None
  }
}

///|
test "a publisher drives the session from handshake to stream" {
  let session = Session::new()
  let client = client_start(0)
  let first = session.push(client[:])
  assert_eq(first.length(), 1)
  assert_eq(session.phase(), Answering)
  let c2 = client_finish(first[0][:])
  assert_eq(session.push(c2[:]).length(), 0)
  assert_eq(session.phase(), Connected)
  // A publisher sets its chunk size, then connects.
  let writer = ChunkWriter::new()
  let replies = session.push(writer.write(set_chunk_size(4096))[:])
  assert_eq(replies.length(), 0)
  // From here the publisher writes at the size it just announced.
  writer.chunk_size = 4096
  let replies = session.push(writer.write(connect_command("live"))[:])
  // Window, bandwidth, chunk size and the result.
  assert_eq(replies.length(), 4)
  assert_eq(session.app(), "live")
  // The server announced a chunk size of its own, so a client reads at that
  // size from then on.
  let result = ChunkReader::new()
  result.set_chunk_size(4096)
  let messages = result.push(replies[3][:])
  assert_eq(messages.length(), 1)
  assert_eq(command_of(messages[0]), Some("_result"))
  // createStream, then publish.
  let create = Message::new(
    msg_command,
    0,
    encode_all([Amf0::String("createStream"), Amf0::Number(4.0), Amf0::Null]),
  )
  let replies = session.push(writer.write(create)[:])
  assert_eq(replies.length(), 1)
  let publish = rtmp_command_publish()
  let replies = session.push(writer.write(publish)[:])
  assert_eq(replies.length(), 1)
  assert_eq(session.phase(), Publishing)
  assert_eq(session.stream_name(), "test")
  // Then media, which the caller takes.
  let video = Message::new(
    msg_video,
    1,
    Bytes::from_array([b'\x17', b'\x00']),
    timestamp=0,
  )
  let audio = Message::new(
    msg_audio,
    1,
    Bytes::from_array([b'\xAF', b'\x00']),
    timestamp=0,
  )
  let _ = session.push(writer.write(video)[:])
  let _ = session.push(writer.write(audio)[:])
  let media = session.take_media()
  assert_eq(media.length(), 2)
  assert_eq(media[0].type_, msg_video)
  assert_eq(session.take_media().length(), 0)
  assert_true(session.bytes_received() > 3000)
}

///|
fn rtmp_command_publish() -> Message {
  Message::new(
    msg_command,
    1,
    encode_all([
      Amf0::String("publish"),
      Amf0::Number(5.0),
      Amf0::Null,
      Amf0::String("test"),
      Amf0::String("live"),
    ]),
  )
}

///|
test "metadata arrives as the pairs the publisher sent" {
  let session = Session::new()
  let client = client_start(0)
  let answer = session.push(client[:])[0]
  let _ = session.push(client_finish(answer[:])[:])
  let writer = ChunkWriter::new()
  let payload = encode_all([
    Amf0::String("@setDataFrame"),
    Amf0::String("onMetaData"),
    Amf0::Object([
      ("width", Amf0::Number(64.0)),
      ("height", Amf0::Number(64.0)),
      ("encoder", Amf0::String("Lavf60.16.100")),
    ]),
  ])
  let _ = session.push(writer.write(Message::new(msg_data, 1, payload))[:])
  let metadata = session.metadata()
  assert_eq(metadata.length(), 3)
  assert_eq(metadata[0].0, "width")
  assert_eq(metadata[2].1.as_string(), Some("Lavf60.16.100"))
}

///|
test "panic: a packet that does not begin an AMF0 value is refused" {
  let bytes = Bytes::from_array([b'\xFF', b'\x00'])
  Amf0::decode(bytes[:]) |> ignore
}
