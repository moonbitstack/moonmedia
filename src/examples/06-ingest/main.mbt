// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Drive a publish session the way a publisher does: handshake, connect,
/// createStream, publish, then send a key frame and a slice of audio.
///
///     moon run src/examples/06-ingest
///
/// The bytes a publisher would send are built here rather than read from a
/// socket, which is the point: the session takes bytes and gives bytes, and a
/// server is the thing that decides where they come from.
#coverage.skip
fn main raise {
  let session = @rtmp.Session::new()
  println("phase: " + phase_name(session.phase()))

  // The handshake: the client opens, the server answers, the client echoes.
  let opening = @rtmp.client_start(0)
  let answer = session.push(opening[:])
  println("handshake answer: " + answer[0].length().to_string() + " bytes")
  let echo = @rtmp.client_finish(answer[0][:])
  let _ = session.push(echo[:])
  println("phase: " + phase_name(session.phase()))

  // A publisher announces its chunk size before it sends anything large.
  let writer = @rtmp.ChunkWriter::new()
  let _ = session.push(writer.write(@rtmp.set_chunk_size(4096))[:])
  writer.chunk_size = 4096

  let connect = @rtmp.Message::new(
    @rtmp.msg_command,
    0,
    @rtmp.encode_all([
      @rtmp.Amf0::String("connect"),
      @rtmp.Amf0::Number(1.0),
      @rtmp.Amf0::Object([
        ("app", @rtmp.Amf0::String("live")),
        ("tcUrl", @rtmp.Amf0::String("rtmp://127.0.0.1:1935/live")),
      ]),
    ]),
  )
  let replies = session.push(writer.write(connect)[:])
  println("replies to connect: " + replies.length().to_string())
  println("application: " + session.app())

  let create = @rtmp.Message::new(
    @rtmp.msg_command,
    0,
    @rtmp.encode_all([
      @rtmp.Amf0::String("createStream"),
      @rtmp.Amf0::Number(4.0),
      @rtmp.Amf0::Null,
    ]),
  )
  let _ = session.push(writer.write(create)[:])
  let publish = @rtmp.Message::new(
    @rtmp.msg_command,
    1,
    @rtmp.encode_all([
      @rtmp.Amf0::String("publish"),
      @rtmp.Amf0::Number(5.0),
      @rtmp.Amf0::Null,
      @rtmp.Amf0::String("camera"),
      @rtmp.Amf0::String("live"),
    ]),
  )
  let _ = session.push(writer.write(publish)[:])
  println(
    "phase: " +
    phase_name(session.phase()) +
    ", stream: " +
    session.stream_name(),
  )

  // Metadata, then media. The first byte of a video message says what it is:
  // 0x17 is a key frame of an AVC stream.
  let metadata = @rtmp.Message::new(
    @rtmp.msg_data,
    1,
    @rtmp.encode_all([
      @rtmp.Amf0::String("@setDataFrame"),
      @rtmp.Amf0::String("onMetaData"),
      @rtmp.Amf0::Object([
        ("width", @rtmp.Amf0::Number(1280.0)),
        ("height", @rtmp.Amf0::Number(720.0)),
        ("videocodecid", @rtmp.Amf0::Number(7.0)),
      ]),
    ]),
  )
  let _ = session.push(writer.write(metadata)[:])
  let video = @rtmp.Message::new(
    @rtmp.msg_video,
    1,
    Bytes::from_array([b'\x17', b'\x00', b'\x00', b'\x00', b'\x00']),
    timestamp=0,
  )
  let _ = session.push(writer.write(video)[:])
  let audio = @rtmp.Message::new(
    @rtmp.msg_audio,
    1,
    Bytes::from_array([b'\xAF', b'\x01', b'\x00']),
    timestamp=0,
  )
  let _ = session.push(writer.write(audio)[:])

  let media = session.take_media()
  println("messages received: " + media.length().to_string())
  let mut video_count = 0
  let mut audio_count = 0
  for message in media {
    if message.type_ == @rtmp.msg_video {
      video_count = video_count + 1
    } else if message.type_ == @rtmp.msg_audio {
      audio_count = audio_count + 1
    }
  }
  println(
    "video: " + video_count.to_string() + ", audio: " + audio_count.to_string(),
  )
  println("metadata pairs: " + session.metadata().length().to_string())
  for pair in session.metadata() {
    println("  " + pair.0)
  }
  println("bytes received: " + session.bytes_received().to_string())
}

///|
/// The phase, as a word.
fn phase_name(phase : @rtmp.Phase) -> String {
  match phase {
    Opening => "opening"
    Answering => "answering"
    Connected => "connected"
    Publishing => "publishing"
    Closed => "closed"
  }
}
