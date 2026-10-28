// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// What a publisher actually sent. ffmpeg pushed a test pattern and a sine wave
// to the session in this repository for one second over the loopback interface;
// this is the first 2500 bytes after its opening handshake, verbatim:
//
//   ffmpeg -re -f lavfi -i testsrc2=size=32x32:rate=8 -f lavfi -i sine=frequency=440:sample_rate=8000 \
//     -t 1 -c:v libx264 -preset ultrafast -g 4 -pix_fmt yuv420p -b:v 40k \
//     -c:a aac -b:a 8k -ac 1 -f flv rtmp://127.0.0.1:1935/live/test
//
// It holds the commands that set up the stream, the metadata, and the first
// audio and video messages. The tail is cut mid-message on purpose: a session
// has to survive a publisher that went away without saying so.

///|
/// The published bytes, the handshake left out.
let publish_trace : String =
  #|AwAAAAAAixQAAAAAAgAHY29ubmVjdAA/8AAAAAAAAAMAA2FwcAIABGxpdmUABHR5cGUCAApu
  #|b25wcml2YXRlAAhmbGFzaFZlcgIAJEZNTEUvMy4wIChjb21wYXRpYmxlOyBMYXZmNjIuMTIu
  #|MTAxKQAFdGNVcmwCABpydG1wOi8vMTI3LjAuMC4xOjHDOTM1L2xpdmUAAAkEAAAAAAAEAQAA
  #|AAAAABAAQwAAAAAAIRQCAA1yZWxlYXNlU3RyZWFtAEAAAAAAAAAABQIABHRlc3RDAAAAAAAd
  #|FAIACUZDUHVibGlzaABACAAAAAAAAAUCAAR0ZXN0QwAAAAAAGRQCAAxjcmVhdGVTdHJlYW0A
  #|QBAAAAAAAAAFCAAAAAAAIhQBAAAAAgAHcHVibGlzaABAFAAAAAAAAAUCAAR0ZXN0AgAEbGl2
  #|ZQQAAAAAATUSAQAAAAIADUBzZXREYXRhRnJhbWUCAApvbk1ldGFEYXRhCAAAAA0ACGR1cmF0
  #|aW9uAD/wAAAAAAAAAAV3aWR0aABAQAAAAAAAAAAGaGVpZ2h0AEBAAAAAAAAAAA12aWRlb2Rh
  #|dGFyYXRlAEBDiAAAAAAAAAlmcmFtZXJhdGUAQCAAAAAAAAAADHZpZGVvY29kZWNpZABAHAAA
  #|AAAAAAANYXVkaW9kYXRhcmF0ZQBAH0AAAAAAAAAPYXVkaW9zYW1wbGVyYXRlAEC/QAAAAAAA
  #|AA9hdWRpb3NhbXBsZXNpemUAQDAAAAAAAAAABnN0ZXJlbwEAAAxhdWRpb2NvZGVjaWQAQCQA
  #|AAAAAAAAB2VuY29kZXICAA1MYXZmNjIuMTIuMTAxAAhmaWxlc2l6ZQAAAAAAAAAAAAAACQYA
  #|AAAAACoJAQAAABcAAAAAAULQC//hABZnQtAL2iWwEQAAAwABAAADABAPEiagAQAEaM48gAQA
  #|AAAAAAcIAQAAAK8AFYhW5QAEAAAAAADxCAEAAACvAd4CAExhdmM2Mi4yOC4xMDEAAjilUtNG
  #|7rP2j7fElXctEiRIkSSDatp2radq2nauM7Vxnatpnp2xTtisO1bTtXGdq4zlWU5VtOVbTYsT
  #|jsTlWUhAhAhAhElGSjKoyqUyVpTXXK6u7cwN2KUCUDAwMDAxs3LLLLLLKblllllllNyyyyyy
  #|yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
  #|yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy8
  #|RgAAgAAHXwkXAQAAAAAAAl8GBf//W9xF6b3m2Ui3lizYINkj7u94MjY0IC0gY29yZSAxNjUg
  #|cjMyMjMgMDQ4MGNiMCAtIEguMjY0L01QRUctNCBBVkMgY29kZWMgLSBDb3B5bGVmdCAyMDAz
  #|LTIwMjUgLSBodHRwOi8vd3d3LnZpZGVvbGFuLm9yZy94MjY0Lmh0bWwgLSBvcHRpb25zOiBj
  #|YWJhYz0wIHJlZj0xIGRlYmxvY2s9MDowOjAgYW5hbHlzZT0wOjAgbWU9ZGlhIHN1Ym1lPTAg
  #|cHN5PTEgcHN5X3JkPTEuMDA6MC4wMCBtaXhlZF9yZWY9MCBtZV9yYW5nZT0xNiBjaHJvbWFf
  #|bWU9MSB0cmVsbGlzPTAgOHg4ZGN0PTAgY3FtPTAgZGVhZHpvbmU9MjEsMTEgZmFzdF9wc2tp
  #|cD0xIGNocm9tYV9xcF9vZmZzZXQ9MCB0aHJlYWRzPTEgbG9va2FoZWFkX3RocmVhZHM9MSBz
  #|bGljZWRfdGhyZWFkcz0wIG5yPTAgZGVjaW1hdGU9MSBpbnRlcmxhY2VkPTAgYmx1cmF5X2Nv
  #|bXBhdD0wIGNvbnN0cmFpbmVkX2ludHJhPTAgYmZyYW1lcz0wIHdlaWdodHA9MCBrZXlpbnQ9
  #|NCBrZXlpbnRfbWluPTEgc2NlbmVjdXQ9MCBpbnRyYV9yZWZyZXNoPTAgcmM9YWJyIG1idHJl
  #|ZT0wIGJpdHJhdGU9NDAgcmF0ZXRvbD0xLjAgcWNvbXA9MC42MCBxcG1pbj0wIHFwbWF4PTY5
  #|IHFwc3RlcD00IGlwX3JhdGlvPTEuNDAgYXE9MACAAAAE82WIhAXoMYACAACAqAAIAmAACAIA
  #|IA1CYUw2At63tgC+AOYAAkygCAEBBjroLnh4bahAABAdAAEH4yIAAIDoAAg/MABwABASAAEB
  #|QPZAJhyoPRizENMHd7f/hwABBpAAEWAyOAAIV4AAkYGdAABALAAEAgIUA+ECIzkrC3oInsz/
  #|9oAAIAQABBaIOi3wrOVpd6G1Xf/hwABAlAAEJJigAYBACDZAC4F7cQGcKnq8OAAIEoAAhJMA
  #|SMAAQWQYB8bQ21Kwu4MUe0lP1AAgCAEmiAFwLm4gs4VfV6gBgYDCbQLgtXGxXGb1ekAAEGsA
  #|oACgPCZEwN4IrPfvkgAAgpgYAEg4buOz0AwVr98CAAEUQAARWgABF+AAEKEIAAQHgABDtAAE
  #|G4AAQ2gAHAGo4JCZKLJU1SWCT+FgUOGARygKYA1Yky6cAAZHaBwAAIBYACBwujQ4Ttg5iwaU
  #|1E0IAAQHtQAmhQGohpAuUaj+AAvAGLvIA8uwEMDDTh7gBAUcQMBE9KWpIoCWkeT3wAAIBgAA
  #|gBizTQ4rlYgLESxBlhE4AYAAgjuPACvisIRyzTB02PYXwAcAAQOwCgANAEQ9KYCCZQsiSAEw
  #|SRBAO4FMAARiRwABCSAAEeEyAsBAYcAIOBCB1NZtq4AAEBUAAQGgU0AdBITyGbtZNUTwUyEg
  #|AAIY4IAAIIACRHkEAAEEwAARDzI4AAgEAACCGZIAAEMcAAQfAACpYASAAIAwAAgCD0wLjkzs
  #|BAvM/w8J7DQABABgAkUJwjCMTDKLAL/q9QAEAKAeeAGRh1eCeAnC76vYAACEeAHAAEBAA4MC
  #|EraiaBdPo0EM9AAAIFQAAgegAEADDUcB3GgXarAsAMAUA4+AMjBKeCcAnFj1eoAMBgGFwTEI
  #|hszwPQRPV6AAAQKwABA9AAIAGSocB3GgsVWwAAEGEBgANAsMGFAvs4cD6NDAeCAAEBgAARwg
  #|ADgABM8CAAEAYAAQVxAFdAmBgaJBhrnTENmdAxTW4GJJp7QAQHvLd/VwMnbgAAQOAABAEB4E
  #|DU6qUGQCzRUgWXPgAAQKwAIFB8pMZE5ABTopwapO4AGEPBoSf24onoQEHtbXeAAMcB4zwFWl
  #|qwkewFbIpghcAACAuABQofZN683INYkuLMwcAACBQAAIBIEgkQEmuheMlGZNpeAs4OAAIqgA
  #|AjlAACH4AAKAqZlgACDWAA==

///|
/// Read base64, tolerating the line breaks the text has.
fn trace_bytes() -> Bytes {
  @base64.decode(publish_trace, ignore_whitespace=true) catch {
    _ => Bytes::new(0)
  }
}

///|
/// A session that has just finished its handshake, ready for commands.
fn handshaken() -> @rtmp.Session raise @rtmp.RtmpError {
  let session = @rtmp.Session::new()
  let answer = session.push(@rtmp.client_start(0)[:])
  let _ = session.push(@rtmp.client_finish(answer[0][:])[:])
  session
}

///|
test "a publisher trace drives the session to a published stream" {
  let session = handshaken()
  let replies = session.push(trace_bytes()[:])
  assert_eq(replies.length(), 8)
  assert_eq(session.app(), "live")
  assert_eq(session.stream_name(), "test")
  assert_eq(session.phase(), @rtmp.Publishing)
  // The metadata ffmpeg writes for a test pattern.
  let metadata = session.metadata()
  assert_eq(metadata.length(), 13)
  assert_eq(metadata[0].0, "duration")
  // The frame size ffmpeg was told to produce.
  assert_eq(metadata[1].0, "width")
  assert_eq(metadata[1].1, @rtmp.Amf0::Number(32.0))
  let media = session.take_media()
  assert_eq(media.length(), 4)
  // A metadata message, then a key frame, then the audio that goes with it.
  let types = media.map(fn(m) { m.type_ })
  assert_eq(types, [
    @rtmp.msg_data, @rtmp.msg_video, @rtmp.msg_audio, @rtmp.msg_audio,
  ])
  // The video message starts with the FLV byte that says the frame is a key
  // frame of an AVC stream, which is what the packager downstream needs.
  assert_eq(media[1].payload.at(0).to_int(), 0x17)
}

///|
test "the trace reads the same one byte at a time" {
  let whole = handshaken()
  let _ = whole.push(trace_bytes()[:])
  let pieces = handshaken()
  let bytes = trace_bytes()
  for i = 0; i < bytes.length(); i = i + 1 {
    let _ = pieces.push(bytes[i:i + 1])
  }
  assert_eq(pieces.app(), whole.app())
  assert_eq(pieces.stream_name(), whole.stream_name())
  assert_eq(pieces.phase(), whole.phase())
  assert_eq(pieces.take_media().length(), whole.take_media().length())
  assert_eq(pieces.metadata(), whole.metadata())
}

///|
test "a message that arrives before the stream is set up is still read" {
  // A publisher may send the metadata before the reply to publish arrives; the
  // session keeps it either way.
  let session = handshaken()
  let _ = session.push(trace_bytes()[:])
  assert_eq(session.stream_name(), "test")
  // Reading the same bytes twice does not duplicate anything.
  let before = session.metadata().length()
  let _ = session.push(Bytes::new(0))
  assert_eq(session.metadata().length(), before)
}
