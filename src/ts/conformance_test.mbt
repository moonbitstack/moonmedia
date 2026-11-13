// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The vectors in `vectors_ffmpeg_test.mbt` and `vectors_gpac_test.mbt` are
// transport streams two other implementations wrote, with ffprobe's reading of
// them beside each one. The tests walk the stream the way a player does —
// programme table, programme map, then the packets of each stream — and compare
// what they find with the probe's.

///|
/// A transport stream as the reference facts write it: the packets, the
/// programme that lists them, and for each stream the elementary bytes it
/// carries and the instant it starts.
fn describe(stream : Bytes) -> String raise @ts.TsError {
  let packets = @ts.parse(stream[:])
  let lines : Array[String] = [
    "bytes " + stream.length().to_string(),
    "packets " + packets.length().to_string(),
  ]
  for table in @ts.sections(packets, @ts.pat_pid) {
    for program in @ts.Pat::of(table).programs {
      lines.push(
        "program " +
        program.number.to_string() +
        " pmt " +
        program.pid.to_string(),
      )
      for map in @ts.sections(packets, program.pid) {
        for entry in @ts.Pmt::of(map).streams {
          let frames = @ts.pes_packets(packets, entry.pid)
          let mut bytes = 0
          for frame in frames {
            bytes = bytes + frame.data.length()
          }
          let first = if frames.length() > 0 {
            frames[0].pts().unwrap_or(0L)
          } else {
            0L
          }
          lines.push(
            "stream " +
            entry.pid.to_string() +
            " type " +
            entry.stream_type.to_string() +
            " payload " +
            bytes.to_string() +
            " first_pts " +
            first.to_string(),
          )
        }
      }
    }
  }
  join(lines)
}

///|
fn join(lines : Array[String]) -> String {
  let mut text = ""
  for i, line in lines {
    if i > 0 {
      text = text + "\n"
    }
    text = text + line
  }
  text
}

///|
fn load(text : String) -> Bytes raise {
  @base64.decode(text, whitespace=true)
}

///|
test "a stream ffmpeg wrote reads the way ffprobe reads it" {
  assert_eq(describe(load(ffmpeg_stream)), ffmpeg_stream_facts)
}

///|
test "a stream GPAC wrote reads the way ffprobe reads it" {
  assert_eq(describe(load(gpac_stream)), gpac_stream_facts)
}

///|
test "every packet of a stream read and written again is the same bytes" {
  // A stream passing through a server is not rebuilt: the packets a caller does
  // not touch come out as they went in, stuffing and counters included.
  for text in [ffmpeg_stream, gpac_stream] {
    let bytes = load(text)
    let packets = @ts.parse(bytes[:])
    for i, packet in packets {
      let at = i * @ts.packet_size
      assert_eq(packet.encode(), bytes[at:at + @ts.packet_size].to_owned())
    }
  }
}

///|
test "the clock a stream carries runs forward, packet by packet" {
  // A decode time that went backwards would be a stream a player cannot order.
  for text in [ffmpeg_stream, gpac_stream] {
    let packets = @ts.parse(load(text)[:])
    for table in @ts.sections(packets, @ts.pat_pid) {
      for program in @ts.Pat::of(table).programs {
        for map in @ts.sections(packets, program.pid) {
          for entry in @ts.Pmt::of(map).streams {
            let mut previous = -1L
            for frame in @ts.pes_packets(packets, entry.pid) {
              let at = frame.pts().unwrap_or(0L)
              assert_true(at > previous)
              previous = at
            }
          }
        }
      }
    }
  }
}

///|
test "the tables a stream carries are intact" {
  // A section says how long it is and what its checksum is; a table that fails
  // either is a table the stream lost part of.
  for text in [ffmpeg_stream, gpac_stream] {
    let packets = @ts.parse(load(text)[:])
    for table in @ts.sections(packets, @ts.pat_pid) {
      assert_eq(table.is_intact(), true)
      for program in @ts.Pat::of(table).programs {
        for map in @ts.sections(packets, program.pid) {
          assert_eq(map.is_intact(), true)
        }
      }
    }
  }
}

///|
test "a video stream carries one picture per packetised packet" {
  // Both muxers write one access unit per packetised stream packet for video,
  // which is what lets a caller hand a decoder one picture at a time.
  let packets = @ts.parse(load(ffmpeg_stream)[:])
  for table in @ts.sections(packets, @ts.pat_pid) {
    for program in @ts.Pat::of(table).programs {
      for map in @ts.sections(packets, program.pid) {
        for entry in @ts.Pmt::of(map).streams {
          // 0x1B is H.264, which both muxers write here.
          if entry.stream_type == 0x1B {
            assert_eq(@ts.pes_packets(packets, entry.pid).length(), 8)
          }
        }
      }
    }
  }
}
