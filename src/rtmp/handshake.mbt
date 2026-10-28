// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The version byte every peer sends first. Three is the only version in use.
pub let version : Int32 = 3

///|
/// How many bytes each of the two random blocks is.
pub let random_size : Int32 = 1528

///|
/// The bytes a client sends before anything else: a version, a time, four zero
/// bytes, and a block that is meant to be random.
///
/// The block is not a secret and nothing is derived from it in the simple
/// handshake, which is why a publisher that fills it with zeros is accepted by
/// every server in use. A caller that would rather not can pass its own.
pub fn client_start(time : Int32, random? : Bytes) -> Bytes {
  let buf = @buffer.Buffer()
  buf.write_byte(version.to_byte())
  write_u32(buf, time)
  buf.write_bytes(Bytes::new(4))
  buf.write_bytes(random.unwrap_or(Bytes::new(random_size)))
  buf.contents()
}

///|
/// A handshake as the receiving side sees it.
///
/// The server answers with its own block and an echo of the client's, and the
/// client answers with an echo of the server's. The two echoes are what tells
/// each side that the other can read what it writes.
pub struct Handshake {
  random : Bytes
  mut s1 : Bytes
  mut c1 : Bytes
  mut complete : Bool
}

///|
/// A handshake with a block of `random` bytes, zeros when none are given.
pub fn Handshake::new(random? : Bytes) -> Handshake {
  {
    random: random.unwrap_or(Bytes::new(random_size)),
    s1: Bytes::new(0),
    c1: Bytes::new(0),
    complete: false,
  }
}

///|
/// Answer a client's opening: what to send back, which is a version byte, the
/// server's own block, and the client's block echoed.
pub fn Handshake::answer(
  self : Handshake,
  c0c1 : BytesView,
  time? : Int32,
) -> Bytes raise RtmpError {
  if c0c1.length() < 1 + 1536 {
    raise Malformed(
      at=0,
      want="a version byte and 1536 bytes of client block",
      got=c0c1.length().to_string() + " bytes",
    )
  }
  let version_byte = c0c1.at(0).to_int() & 0xFF
  if version_byte != version {
    raise Malformed(at=0, want="version 3", got=version_byte.to_string())
  }
  let c1 = c0c1[1:1537].to_owned()
  let buf = @buffer.Buffer()
  buf.write_byte(version.to_byte())
  let s1 = @buffer.Buffer()
  write_u32(s1, time.unwrap_or(0))
  s1.write_bytes(Bytes::new(4))
  s1.write_bytes(self.random)
  let s1_bytes = s1.contents()
  buf.write_bytes(s1_bytes)
  // The answer to the client is its own block, unchanged.
  buf.write_bytes(c1)
  self.c1 = c1
  self.s1 = s1_bytes
  buf.contents()
}

///|
/// Check the client's answer, which has to be the server's block echoed.
pub fn Handshake::complete_with(
  self : Handshake,
  c2 : BytesView,
) -> Unit raise RtmpError {
  if c2.length() < 1536 {
    raise Malformed(
      at=0,
      want="1536 bytes echoing the server block",
      got=c2.length().to_string() + " bytes",
    )
  }
  if !c2[0:1536].equal(self.s1[:]) {
    raise Malformed(at=0, want="the server block echoed", got="different bytes")
  }
  self.complete = true
}

///|
/// Whether the handshake has finished.
pub fn Handshake::is_complete(self : Handshake) -> Bool {
  self.complete
}

///|
/// What a client has to answer once the server has answered it.
pub fn client_finish(s0s1s2 : BytesView) -> Bytes raise RtmpError {
  if s0s1s2.length() < 1 + 1536 + 1536 {
    raise Malformed(
      at=0,
      want="a version byte and two blocks",
      got=s0s1s2.length().to_string() + " bytes",
    )
  }
  // The client echoes the server's block, which is the first of the two.
  s0s1s2[1:1537].to_owned()
}
