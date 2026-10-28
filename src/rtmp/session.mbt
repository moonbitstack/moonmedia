// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Where a session is.
pub(all) enum Phase {
  /// Waiting for the client's opening.
  Opening
  /// Waiting for the client to echo the server's block.
  Answering
  /// Handshaken, and waiting for the commands that set up a stream.
  Connected
  /// A stream is being pushed.
  Publishing
  /// The stream ended.
  Closed
} derive(Eq, Debug)

///|
pub extend Phase with Eq::{equal, not_equal}

///|
pub extend Phase with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The receiving half of a publish: it answers the handshake, answers the
/// commands that set up a stream, and hands the caller the audio, video and
/// metadata that arrives.
///
/// A session has no socket. Bytes go in and bytes come out, which is what lets
/// it be tested without one and left to a server to drive.
pub struct Session {
  handshake : Handshake
  reader : ChunkReader
  writer : ChunkWriter
  pending : @buffer.Buffer
  mut phase : Phase
  mut application : String
  mut name : String
  mut stream_id : Int32
  mut media : Array[Message]
  mut metadata : Array[(String, Amf0)]
  mut bytes_in : Int32
}

///|
/// The chunk size this side announces, which is what it will use for everything
/// it sends afterwards.
let our_chunk_size : Int32 = 4096

///|
/// The window this side offers.
let our_window : Int32 = 2_500_000

///|
/// A session that has not heard anything yet.
pub fn Session::new() -> Session {
  {
    handshake: Handshake::new(),
    reader: ChunkReader::new(),
    writer: ChunkWriter::new(),
    pending: @buffer.Buffer(),
    phase: Opening,
    application: "",
    name: "",
    stream_id: 0,
    media: [],
    metadata: [],
    bytes_in: 0,
  }
}

///|
/// Where the session is.
pub fn Session::phase(self : Session) -> Phase {
  self.phase
}

///|
/// The application name the client asked for, from `connect`.
pub fn Session::app(self : Session) -> String {
  self.application
}

///|
/// The stream name the client is publishing to, from `publish`.
pub fn Session::stream_name(self : Session) -> String {
  self.name
}

///|
/// The metadata the publisher sent, in the order it sent it.
pub fn Session::metadata(self : Session) -> Array[(String, Amf0)] {
  self.metadata
}

///|
/// How many bytes have been received.
pub fn Session::bytes_received(self : Session) -> Int32 {
  self.bytes_in
}

///|
/// Feed the session what arrived, and send back what it has to say.
///
/// The answer is a list of writes rather than one buffer because a handshake
/// happens at a different moment from a reply: a caller that wants them together
/// concatenates them, and a caller on a socket sends them one by one.
pub fn Session::push(
  self : Session,
  data : BytesView,
) -> Array[Bytes] raise RtmpError {
  self.bytes_in = self.bytes_in + data.length()
  self.pending.write_bytes(data)
  let out : Array[Bytes] = []
  match self.phase {
    Opening => {
      let bytes = self.pending.contents()
      if bytes.length() >= 1537 {
        let answer = self.handshake.answer(bytes[:1537])
        out.push(answer)
        self.replace_pending(bytes[1537:])
        self.phase = Answering
      }
    }
    _ => ()
  }
  match self.phase {
    Answering => {
      let bytes = self.pending.contents()
      if bytes.length() >= 1536 {
        self.handshake.complete_with(bytes[:1536])
        self.replace_pending(bytes[1536:])
        self.phase = Connected
      }
    }
    _ => ()
  }
  if self.phase == Connected || self.phase == Publishing {
    let bytes = self.pending.contents()
    if bytes.length() > 0 {
      self.pending.reset()
      let messages = self.reader.push(bytes[:])
      for message in messages {
        let replies = self.handle(message)
        for reply in replies {
          out.push(reply)
        }
      }
    }
  }
  out
}

///|
/// Keep what has not been read yet.
fn Session::replace_pending(self : Session, rest : BytesView) -> Unit {
  self.pending.reset()
  self.pending.write_bytes(rest)
}

///|
/// Take the media messages received so far, which leaves the session with none.
pub fn Session::take_media(self : Session) -> Array[Message] {
  let out = self.media
  self.media = []
  out
}

///|
/// Act on one message, returning the bytes to send back.
fn Session::handle(
  self : Session,
  message : Message,
) -> Array[Bytes] raise RtmpError {
  let out : Array[Bytes] = []
  let type_ = message.type_
  if type_ == msg_set_chunk_size {
    if message.payload.length() >= 4 {
      let size = read_u32_be(message.payload[:], 0) & 0x7FFF_FFFF
      self.reader.set_chunk_size(size)
    }
  } else if type_ == msg_user_control {
    // A ping is answered with a pong carrying the same timestamp, which is how
    // a peer learns the connection is still there.
    if message.payload.length() >= 6 {
      let event = read_u16_be(message.payload[:], 0)
      if event == 0x0006 {
        let stamp = read_u32_be(message.payload[:], 2)
        out.push(self.send(pong(stamp)))
      }
    }
  } else if type_ == msg_command {
    for reply in self.command(message) {
      out.push(reply)
    }
  } else if type_ == msg_audio || type_ == msg_video {
    self.media.push(message)
  } else if type_ == msg_data {
    self.data(message)
    self.media.push(message)
  }
  out
}

///|
/// Read a metadata message: `@setDataFrame` wrapping `onMetaData`, or
/// `onMetaData` alone, which older publishers send.
fn Session::data(self : Session, message : Message) -> Unit raise RtmpError {
  let values = decode_all(message.payload[:])
  let mut at = 0
  match values {
    [Amf0::String(first), ..] if first == "@setDataFrame" => at = 1
    _ => ()
  }
  if at >= values.length() {
    return
  }
  match values[at] {
    Amf0::String(name) if name == "onMetaData" =>
      if at + 1 < values.length() {
        self.metadata = values[at + 1].pairs()
      }
    _ => ()
  }
}

///|
/// Answer a command.
fn Session::command(
  self : Session,
  message : Message,
) -> Array[Bytes] raise RtmpError {
  let out : Array[Bytes] = []
  let values = decode_all(message.payload[:])
  if values.length() == 0 {
    return out
  }
  let name = match values[0] {
    Amf0::String(name) => name
    _ => return out
  }
  let transaction = if values.length() > 1 {
    match values[1] {
      Amf0::Number(value) => value
      _ => 0.0
    }
  } else {
    0.0
  }
  match name {
    "connect" => {
      if values.length() > 2 {
        match values[2].field("app") {
          Some(Amf0::String(app)) => self.application = app
          _ => ()
        }
      }
      // The order matters to a publisher: it has to know the window and the
      // chunk size before it sends anything large.
      out.push(self.send(window_ack_size(our_window)))
      out.push(self.send(set_peer_bandwidth(our_window, 2)))
      out.push(self.send(set_chunk_size(our_chunk_size)))
      self.writer.chunk_size = our_chunk_size
      out.push(
        self.send(
          Message::new(
            msg_command,
            0,
            encode_all([
              Amf0::String("_result"),
              Amf0::Number(transaction),
              Amf0::Object([
                ("fmsVer", Amf0::String("FMS/3,0,1,123")),
                ("capabilities", Amf0::Number(31.0)),
              ]),
              Amf0::Object([
                ("level", Amf0::String("status")),
                ("code", Amf0::String("NetConnection.Connect.Success")),
                ("description", Amf0::String("Connection succeeded.")),
                ("objectEncoding", Amf0::Number(0.0)),
              ]),
            ]),
          ),
        ),
      )
    }
    "releaseStream" | "FCPublish" | "FCUnpublish" | "deleteStream" =>
      // These are courtesy calls: a publisher sends them so that a server can
      // free a name, and none of them changes what the stream is.
      out.push(
        self.send(
          Message::new(
            msg_command,
            0,
            encode_all([
              Amf0::String("_result"),
              Amf0::Number(transaction),
              Amf0::Null,
            ]),
          ),
        ),
      )
    "createStream" => {
      self.stream_id = 1
      out.push(
        self.send(
          Message::new(
            msg_command,
            0,
            encode_all([
              Amf0::String("_result"),
              Amf0::Number(transaction),
              Amf0::Null,
              Amf0::Number(self.stream_id.to_double()),
            ]),
          ),
        ),
      )
    }
    "publish" => {
      if values.length() > 3 {
        match values[3] {
          Amf0::String(name) => self.name = name
          _ => ()
        }
      }
      self.phase = Publishing
      out.push(
        self.send(
          Message::new(
            msg_command,
            self.stream_id,
            encode_all([
              Amf0::String("onStatus"),
              Amf0::Number(0.0),
              Amf0::Null,
              Amf0::Object([
                ("level", Amf0::String("status")),
                ("code", Amf0::String("NetStream.Publish.Start")),
                (
                  "description",
                  Amf0::String("Stream " + self.name + " is now published."),
                ),
              ]),
            ]),
          ),
        ),
      )
    }
    "closeStream" => self.phase = Closed
    _ => ()
  }
  out
}

///|
/// Write one message as chunks.
fn Session::send(self : Session, message : Message) -> Bytes {
  self.writer.write(message)
}
