// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A transport stream ffmpeg wrote from the same test pattern as the mp4
// samples, cut to two frames:
//
//   ffmpeg -f lavfi -i testsrc2=size=32x32:rate=8 -f lavfi -i sine=frequency=440:sample_rate=8000 \
//     -t 0.25 -c:v libx264 -preset ultrafast -g 2 -pix_fmt yuv420p -b:v 40k \
//     -c:a aac -b:a 8k -ac 1 -f mpegts small.ts

///|
/// The stream the tests read.
let stream : String =
  #|R0AREABC8CUAAcEAAP8B/wAB/IAUSBIBBkZGbXBlZwlTZXJ2aWNlMDF3fEPK////////////
  #|////////////////////////////////////////////////////////////////////////
  #|////////////////////////////////////////////////////////////////////////
  #|//////////////////////////////////9HQAAQAACwDQABwQAAAAHwACqxBLL/////////
  #|////////////////////////////////////////////////////////////////////////
  #|////////////////////////////////////////////////////////////////////////
  #|/////////////////////////////////////////////////////////////////////0dQ
  #|ABAAArAXAAHBAADhAPAAG+EA8AAP4QHwAC9EuZv/////////////////////////////////
  #|////////////////////////////////////////////////////////////////////////
  #|////////////////////////////////////////////////////////////////////////
  #|////////////////////////////////R0EAMAdQAACRjH4AAAAB4AAAgIAFIQAJMmEAAAAB
  #|CfAAAAABZ0LQC9olsBEAAAMAAQAAAwAQDxImoAAAAAFozjyAAAABBgX//1vcRem95tlIt5Ys
  #|2CDZI+7veDI2NCAtIGNvcmUgMTY1IHIzMjIzIDA0ODBjYjAgLSBILjI2NC9NUEVHLTQgQVZD
  #|IGNvZGVjIC0gQ29weWxlZnQgMjAwMy0yMDI1IC0gaHR0cDovL3d3dy52aWRlb2xhbi5HAQAR
  #|b3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTAgcmVmPTEgZGVibG9jaz0wOjA6MCBh
  #|bmFseXNlPTA6MCBtZT1kaWEgc3VibWU9MCBwc3k9MSBwc3lfcmQ9MS4wMDowLjAwIG1peGVk
  #|X3JlZj0wIG1lX3JhbmdlPTE2IGNocm9tYV9tZT0xIHRyZWxsaXM9MCA4eDhkY3Q9MCBjcW09
  #|MCBkZWFkem9uZT0yMSwxMSBmYXN0X0cBABJwc2tpcD0xIGNocm9tYV9xcF9vZmZzZXQ9MCB0
  #|aHJlYWRzPTEgbG9va2FoZWFkX3RocmVhZHM9MSBzbGljZWRfdGhyZWFkcz0wIG5yPTAgZGVj
  #|aW1hdGU9MSBpbnRlcmxhY2VkPTAgYmx1cmF5X2NvbXBhdD0wIGNvbnN0cmFpbmVkX2ludHJh
  #|PTAgYmZyYW1lcz0wIHdlaWdodHA9MCBrZXlpbnQ9MiBrZXlpbnRfbWluPTEgc2NlRwEAE25l
  #|Y3V0PTAgaW50cmFfcmVmcmVzaD0wIHJjPWFiciBtYnRyZWU9MCBiaXRyYXRlPTQwIHJhdGV0
  #|b2w9MS4wIHFjb21wPTAuNjAgcXBtaW49MCBxcG1heD02OSBxcHN0ZXA9NCBpcF9yYXRpbz0x
  #|LjQwIGFxPTAAgAAAAWWIhAXoMYACAACAqAAIAmAACAIAIA1CYUw2At63tgC+AOYAAkygCAEB
  #|BjroLnh4bahAABAdAAEH4yIAAIBHAQAU6AAIPzAAcAAQEgABAUD2QCYcqD0YsxDTB3e3/4cA
  #|AQaQABFgMjgACFeAAJGBnQAAQCwABAICFAPhAiM5Kwt6CJ7M//aAACAEAAQWiDot8KzlaXeh
  #|tV3/4cAAQJQABCSYoAGAQAg2QAuBe3EBnCp6vDgACBKAAISTAEjAAEFkGAfG0NtSsLuDFHtJ
  #|T9QAIAgBJogBcC5uILOFX1eoAYGAwm0C4LVxsVxm9XpAABBrAKAAoDwmRMDeCEcBABWs9++S
  #|AACCmBgASDhu47PQDBWv3wIAARRAABFaAAEX4AAQoQgABAeAAEO0AAQbgABDaAAcAajgkJko
  #|slTVJYJP4WBQ4YBHKApgDViTLpwABkdoHAAAgFgAIHC6NDhO2DmLBpTUTQgABAe1ACaFAaiG
  #|kC5RqP4AC8AYu8gDy7AQwMNOHuAEBRxAwET0pakigJaR5PfAAAgGAACAGLNNDiuViAsRLEGW
  #|ETgBgACCO48AK+KwhHLNMHTYRwEAFvYXwAcAAQOwCgANAEQ9KYCCZQsiSAEwSRBAO4FMAARi
  #|RwABCSAAEeEyAsBAYcAIOBCB1NZtq4AAEBUAAQGgU0AdBITyGbtZNUTwUyEgAAIY4IAAIIAC
  #|RHkEAAEEwAARDzI4AAgEAACCGZIAAEMcAAQfAACpYASAAIAwAAgCD0wLjkzsBAvM/w8J7DQA
  #|BABgAkUJwjCMTDKLAL/q9QAEAKAeeAGRh1eCeAnC76vYAACEeAHAAEBAA4NHAQAXAhK2omgX
  #|T6NBDPQAACBUAAIHoABAAw1HAdxoF2qwLADAFAOPgDIwSngnAJxY9XqADAYBhcExCIbM8D0E
  #|T1egAAECsAAQPQACABkqHAdxoLFVsAABBhAYADQLDBhQL7OHA+jQwHggABAYAAEcIAA4AATP
  #|AgABAGAAEFcQBXQJgYGiQYa50xDZnQMU1uBiSae0AEB7y3f1cDJ24AAEDgAAQBAeBA1OqlBk
  #|As0VIFlz4AAECsACBQfKTEcBABhkTkAFOinBqk7gAYQ8GhJ/biiehAQe1td4AAxwHjPAVaWr
  #|CR7AVsimCFwAAIC4AFCh9k3rzcg1iS4szBwAAIFAAAgEgSCRASa6F4yUZk2l4Czg4AAiqAAC
  #|OUAAIfgAAoCpmWAAINYAAiyMQcAAQawABFkYLAAEGoAARZWCwABBTAAESBgcAAQagABFlYHA
  #|AEFMAARIGIOAAINYAAiyMQcAAQawABFkYHAAEGoAARZWBwABBTAAESBgRwEAGXAAEGoAARZW
  #|BwABBTAAESBgQAAQQwABE4iAACEIAAI4sgAEAAQAgABAVuEEAAQVgJcDgAgACAEAAICtwOQA
  #|BBWAlwgAAQIAABBDAAEFC4QCAAINoBNwOAAIEAAAghgACChcDggACDaATcCzmAACDiAAJzoA
  #|AgMgACXSmCAACEcAAI6bHjgACEcAAI6bHywABBhAAEUpiDgACDCAAIpTA4AAhHAACOmxHAAE
  #|I4AAR02MHAAEGEAARSlHAQA6UQD/////////////////////////////////////////////
  #|/////////////////////////////////////////////////////////////4g4AAgwgACK
  #|UwIAAIAwAAjqRAABASAAEWmQQABCKAAEH64SAAEHIAAQU7gcgACEUAAIP1woAAIOQAAgp3CB
  #|AAEEcAAQUbhAABAAAQRwABBOuBxAAEEcAAQUbgcAAgAAII4AAgnXIEdAABEAALANAAHBAAAA
  #|AfAAKrEEsv//////////////////////////////////////////////////////////////
  #|////////////////////////////////////////////////////////////////////////
  #|////////////////////////////////////////////////////////////////////////
  #|////////////////R1AAEQACsBcAAcEAAOEA8AAb4QDwAA/hAfAAL0S5m///////////////
  #|////////////////////////////////////////////////////////////////////////
  #|////////////////////////////////////////////////////////////////////////
  #|//////////////////////////////////////////////////9HQQA7mRAAAKeFfgD/////
  #|////////////////////////////////////////////////////////////////////////
  #|////////////////////////////////////////////////////////////////////////
  #|/////////////////////////////////////////////wAAAeAAAICABSEACYpFAAAAAQnw
  #|AAAAAUGaIBOiwEdBATABQAAAAcACYoCABSEAB9hh//FsQB7f/N4CAExhdmM2Mi4yOC4xMDEA
  #|AjilUtNG7rP2j7fElXctEiRIkSSDatp2radq2nauM7Vxnatpnp2xTtisO1bTtXGdq4zlWU5V
  #|tOVbTYsTjsTlWUhAhAhAhElGSjKoyqUyVpTXXK6u7cwN2KUCUDAwMDAxs3LLLLLLKbllllll
  #|lNyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyRwEBEcssssssssssssssssss
  #|ssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss
  #|ssssssssssssvP/xbEAbv/wBAJzZOR1EuhlEvBVkvn2+f/4v/P9euONatJ/0/T/8P/P8eeOt
  #|Xd1n/T8/+n/z9dcca1Zr/0/P/p/9/rjjjjUvFl0UgcBl0ck4mmZsMVzTTL2NjZHZs2RLHIfr
  #|wXYIHCUYTrNHAQESnRVUYxqDR0UR0G6B1Cg3QadVFBxGrYiLNhHy3LdsnQuja+xsii2FL8iR
  #|wVlzLOdiPPOc51KVGpSp555551TqnVOqeeedSp51TzqnnnnVOrYeeeeegoLqUInNYUidw/BT
  #|nVDzT8yp5+af5fKrmIn6joUgDv/xbEAQ//wBDp20vhNkfg/Dn8//h/5/jzrrWpH8f/tv8/jz
  #|q+Lu5B8vl8tmzKc77TSyIoYYubjFzD5CIvkPlFFF8p+PHkcBATN1AP//////////////////
  #|////////////////////////////////////////////////////////////////////////
  #|////////////////////////////////////////////////////////////////MXym+Xy+
  #|XHYeKfjxREU6AMsUSqogpQVBepQKSbS6+zOAaz9jIbC5+ZOIafzDh+wafzDh+GkD8uH4aQD8
  #|rfhX8gA4

///|
fn bytes_of(text : String) -> Bytes {
  @base64.decode(text, ignore_whitespace=true) catch {
    _ => Bytes::new(0)
  }
}

///|
test "every packet is written back as the bytes it came from" {
  let data = bytes_of(stream)
  assert_eq(data.length() % 188, 0)
  let packets = @ts.parse(data[:])
  assert_eq(packets.length(), data.length() / 188)
  let buf = @buffer.Buffer()
  for packet in packets {
    buf.write_bytes(packet.encode())
  }
  assert_eq(buf.contents(), data)
}

///|
test "the programme table says where the map table is" {
  let data = bytes_of(stream)
  let packets = @ts.parse(data[:])
  let sections = @ts.sections(packets, @ts.pat_pid)
  assert_eq(sections.length() > 0, true)
  let pat = @ts.Pat::of(sections[0])
  assert_eq(pat.programs.length() > 0, true)
  assert_eq(pat.programs[0].number, 1)
  assert_eq(pat.transport_stream, 1)
  // The checksum is the format's own, and a table that fails it is a table with
  // a bit error in it.
  assert_eq(sections[0].is_intact(), true)
  // Writing the table and reading it again gives the same table.
  let again = @ts.sections(pat.section().packets(@ts.pat_pid), @ts.pat_pid)
  assert_eq(@ts.Pat::of(again[0]), pat)
}

///|
test "the map table names the streams and the clock" {
  let data = bytes_of(stream)
  let packets = @ts.parse(data[:])
  let pat = @ts.Pat::of(@ts.sections(packets, @ts.pat_pid)[0])
  let pmt_pid = pat.programs[0].pid
  let sections = @ts.sections(packets, pmt_pid)
  assert_eq(sections[0].is_intact(), true)
  let pmt = @ts.Pmt::of(sections[0])
  assert_eq(pmt.program, 1)
  assert_eq(pmt.streams.length(), 2)
  // H.264 and AAC, as ffmpeg wrote them.
  let types = pmt.streams.map(fn(s) { s.stream_type })
  assert_eq(types, [0x1B, 0x0F])
  // The clock rides on the video stream.
  assert_eq(pmt.pcr_pid, pmt.streams[0].pid)
  let again = @ts.sections(pmt.section().packets(pmt_pid), pmt_pid)
  assert_eq(@ts.Pmt::of(again[0]), pmt)
}

///|
test "the clock reference reads as the time it names" {
  let data = bytes_of(stream)
  let packets = @ts.parse(data[:])
  let mut seen = 0
  let mut previous = -1L
  for packet in packets {
    match packet.adaptation {
      Some(adaptation) =>
        match adaptation.pcr() {
          Some(pcr) => {
            assert_true(pcr > previous)
            previous = pcr
            seen = seen + 1
            // The clock counts 27 MHz, so a clip of a few seconds is a count of
            // a few tens of millions.
            assert_true(pcr / 27_000_000L < 60L)
          }
          None => ()
        }
      None => ()
    }
  }
  assert_eq(seen > 0, true)
  // A clock written into a field reads back as the same clock.
  let field = @ts.Adaptation::with_pcr(12345678L * 300L)
  assert_eq(field.pcr(), Some(12345678L * 300L))
  assert_eq(field.length(), 7)
}

///|
test "the continuity counter moves once per packet that carries data" {
  let data = bytes_of(stream)
  let packets = @ts.parse(data[:])
  let by_pid : Array[(Int32, Int32)] = []
  for packet in packets {
    let mut at = -1
    for i, pair in by_pid {
      if pair.0 == packet.pid {
        at = i
      }
    }
    if at >= 0 {
      let previous = by_pid[at].1
      assert_eq((previous + 1) & 0xF, packet.counter)
      by_pid[at] = (packet.pid, packet.counter)
    } else {
      by_pid.push((packet.pid, packet.counter))
    }
  }
}

///|
test "the elementary streams come back as packets with timestamps" {
  let data = bytes_of(stream)
  let packets = @ts.parse(data[:])
  let pat = @ts.Pat::of(@ts.sections(packets, @ts.pat_pid)[0])
  let pmt = @ts.Pmt::of(@ts.sections(packets, pat.programs[0].pid)[0])
  let video = @ts.pes_packets(packets, pmt.streams[0].pid)
  assert_eq(video.length(), 2)
  assert_eq(video[0].stream_id, 0xE0)
  // The first frame is a key frame, and its bytes begin with the H.264 access
  // unit delimiter, which is what a decoder looks for at the start of a frame.
  assert_eq(video[0].data.at(0).to_int(), 0x00)
  assert_eq(video[0].data.at(1).to_int(), 0x00)
  assert_eq(video[0].data.at(2).to_int(), 0x00)
  assert_eq(video[0].data.at(3).to_int(), 0x01)
  assert_eq(video[0].data.at(4).to_int() & 0x1F, 0x09)
  // Every frame is timed, and the times run forward.
  let mut previous = -1L
  for packet in video {
    match packet.pts() {
      Some(pts) => {
        assert_true(pts > previous)
        previous = pts
      }
      None => fail("a video packet with no presentation time")
    }
  }
  let audio = @ts.pes_packets(packets, pmt.streams[1].pid)
  assert_true(audio.length() > 0)
  assert_eq(audio[0].stream_id, 0xC0)
}

///|
test "a packet written here reads back as the packet that went in" {
  let pes = @ts.Pes::new(
    0xE0,
    Bytes::from_array([b'\x00', b'\x00', b'\x00', b'\x01', b'\x09']),
    pts=90000L,
    dts=89000L,
  )
  assert_eq(pes.pts(), Some(90000L))
  assert_eq(pes.dts(), Some(89000L))
  let again = @ts.Pes::parse(pes.encode()[:])
  assert_eq(again, pes)
  // Three bytes of start code, one of stream identifier, two of length, two of
  // flags, one of header length, ten of timestamps, and the data itself.
  assert_eq(pes.encode().length(), 3 + 1 + 2 + 2 + 1 + 10 + 5)
  // A packet with no timestamp says so rather than guessing.
  let plain = @ts.Pes::new(0xE0, Bytes::new(4))
  assert_eq(plain.pts(), None)
  assert_eq(@ts.Pes::parse(plain.encode()[:]).data.length(), 4)
}

///|
test "panic: a packet that does not start with the sync byte is refused" {
  let data = Bytes::new(188)
  @ts.parse(data[:]) |> ignore
}

///|
test "panic: a stream that is not a whole number of packets is refused" {
  let data = Bytes::new(200)
  @ts.parse(data[:]) |> ignore
}

///|
test "panic: a packet with neither payload nor adaptation field is refused" {
  let data = Bytes::from_array([
    b'\x47', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
  ])
  @ts.Packet::parse(data[:]) |> ignore
}

///|
test "panic: a section that claims more bytes than it has is refused" {
  let data = Bytes::from_array([
    b'\x00', b'\xF0', b'\xFF', b'\x00', b'\x01', b'\xC1', b'\x00', b'\x00',
  ])
  @ts.Section::parse(data[:], 0) |> ignore
}
