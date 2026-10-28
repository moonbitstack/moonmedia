// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Two hex digits.
fn hex(value : Int32) -> String {
  let digits = "0123456789abcdef"
  "0x" +
  digits[value >> 4:(value >> 4) + 1].to_owned() +
  digits[value & 0xF:(value & 0xF) + 1].to_owned()
}

///|
/// Build the tables and a frame of a transport stream, write them as packets,
/// then read the packets back.
///
///     moon run src/examples/04-transport
#coverage.skip
fn main raise {
  let pat = @ts.Pat::new(transport_stream=1, programs=[
    @ts.Program::new(1, 0x1000),
  ])
  let pmt = @ts.Pmt::new(program=1, pcr_pid=0x100, streams=[
    @ts.Stream::new(0x1B, 0x100),
    @ts.Stream::new(0x0F, 0x101),
  ])
  // A frame of five bytes, timed a quarter of a second in.
  let frame = Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x01', b'\x09'])
  let pes = @ts.Pes::new(0xE0, frame, pts=22500L)

  let assembled : Array[@ts.Packet] = []
  for i, packet in pat.section().packets(@ts.pat_pid) {
    assembled.push({ ..packet, counter: i & 0xF, })
  }
  for i, packet in pmt.section().packets(0x1000) {
    assembled.push({ ..packet, counter: i & 0xF, })
  }
  assembled.push(
    @ts.Packet::new(0x100, pes.encode(), starts_unit=true, counter=0),
  )
  let buf = @buffer.Buffer()
  for packet in assembled {
    buf.write_bytes(packet.encode())
  }
  let stream = buf.contents()
  println(
    "packets: " +
    assembled.length().to_string() +
    ", " +
    stream.length().to_string() +
    " bytes",
  )

  let packets = @ts.parse(stream[:])
  let tables = @ts.sections(packets, @ts.pat_pid)
  let read_pat = @ts.Pat::of(tables[0])
  println(
    "programme " +
    read_pat.programs[0].number.to_string() +
    " on pid " +
    read_pat.programs[0].pid.to_string(),
  )
  let map = @ts.Pmt::of(@ts.sections(packets, 0x1000)[0])
  println("programme clock on pid " + map.pcr_pid.to_string())
  for stream_ in map.streams {
    println(
      "  stream type " +
      hex(stream_.stream_type) +
      " on pid " +
      stream_.pid.to_string(),
    )
  }
  let frames = @ts.pes_packets(packets, 0x100)
  println("frames: " + frames.length().to_string())
  println(
    "presentation time: " +
    frames[0].pts().unwrap().to_string() +
    " (1/90000 s)",
  )
  println("payload: " + frames[0].data.length().to_string() + " bytes")
  println("checksum holds: " + tables[0].is_intact().to_string())
  // Every packet is 188 bytes, and a packet written and read again is the same
  // packet.
  println("packet size: " + packets[0].encode().length().to_string())
  println(
    "round trip: " +
    (packets[0].encode() == stream[0:188].to_owned()).to_string(),
  )
}
