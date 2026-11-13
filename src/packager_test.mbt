// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// Two frames of a test pattern and half a second of a sine wave, as ffmpeg
// wrote them:
//
//   ffmpeg -f lavfi -i testsrc2=size=32x32:rate=4 -f lavfi -i sine=frequency=440:sample_rate=8000 \
//     -t 0.5 -c:v libx264 -preset ultrafast -g 4 -pix_fmt yuv420p -b:v 24k \
//     -c:a aac -b:a 6k -ac 1 -movflags +faststart pack.mp4

///|
/// The movie the packager tests cut up.
let movie : String =
  #|AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAWPbW9vdgAAAGxtdmhkAAAAAAAA
  #|AAAAAAAAAAAD6AAAAfQAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAA
  #|AAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwAAAlh0cmFrAAAAXHRr
  #|aGQAAAADAAAAAAAAAAAAAAABAAAAAAAAAfQAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAA
  #|AAAAAAABAAAAAAAAAAAAAAAAAABAAAAAACAAAAAgAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAA
  #|AAEAAAH0AAAAAAABAAAAAAHQbWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAABAAAAAIABVxAAA
  #|AAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABe21pbmYA
  #|AAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAA
  #|AQAAATtzdGJsAAAAt3N0c2QAAAAAAAAAAQAAAKdhdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAA
  #|AAAAACAAIABIAAAASAAAAAAAAAABFUxhdmM2Mi4yOC4xMDEgbGlieDI2NAAAAAAAAAAAAAAA
  #|GP//AAAALWF2Y0MBQsAK/+EAFmdCwAraJbARAAADAAEAAAMACA8SJqABAARozjyAAAAAEHBh
  #|c3AAAAABAAAAAQAAABRidHJ0AAAAAAAAhVAAAIVQAAAAGHN0dHMAAAAAAAAAAQAAAAIAABAA
  #|AAAAFHN0c3MAAAAAAAAAAQAAAAEAAAAcc3RzYwAAAAAAAAABAAAAAQAAAAEAAAABAAAAHHN0
  #|c3oAAAAAAAAAAAAAAAIAAAe4AAAAnQAAABhzdGNvAAAAAAAAAAIAAAaDAAAPhQAAAmF0cmFr
  #|AAAAXHRraGQAAAADAAAAAAAAAAAAAAACAAAAAAAAAfQAAAAAAAAAAAAAAAEBAAAAAAEAAAAA
  #|AAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAkZWR0cwAAABxlbHN0
  #|AAAAAAAAAAEAAAH0AAAEAAABAAAAAAHZbWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAAAfQAAA
  #|E6BVxAAAAAAALWhkbHIAAAAAAAAAAHNvdW4AAAAAAAAAAAAAAABTb3VuZEhhbmRsZXIAAAAB
  #|hG1pbmYAAAAQc21oZAAAAAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAA
  #|AAABAAABSHN0YmwAAAB+c3RzZAAAAAAAAAABAAAAbm1wNGEAAAAAAAAAAQAAAAAAAAAAAAEA
  #|EAAAAAAfQAAAAAAANmVzZHMAAAAAA4CAgCUAAgAEgICAF0AVAAAAAAApGgAAKRoFgICABRWI
  #|VuUABoCAgAECAAAAFGJ0cnQAAAAAAAApGgAAKRoAAAAgc3R0cwAAAAAAAAACAAAABAAABAAA
  #|AAABAAADoAAAAChzdHNjAAAAAAAAAAIAAAABAAAAAQAAAAEAAAACAAAAAgAAAAEAAAAoc3Rz
  #|egAAAAAAAAAAAAAABQAAAMQAAADVAAAAdQAAAIYAAACmAAAAHHN0Y28AAAAAAAAAAwAABb8A
  #|AA47AAAQIgAAABpzZ3BkAQAAAHJvbGwAAAACAAAAAf//AAAAHHNiZ3AAAAAAcm9sbAAAAAEA
  #|AAAFAAAAAQAAAGJ1ZHRhAAAAWm1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAG1kaXJhcHBsAAAA
  #|AAAAAAAAAAAALWlsc3QAAAAlqXRvbwAAAB1kYXRhAAAAAQAAAABMYXZmNjIuMTIuMTAxAAAA
  #|CGZyZWUAAAuXbWRhdN4CAExhdmM2Mi4yOC4xMDEAAnilIcvBVZv1+n7/F3dpEkkSJERAEhIS
  #|EhISEhISEhISEhISEhISEhITu3bgLxvFSB8spRRRcYoooooouMUUUUUUUUUUUUUUUUURRRRR
  #|RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRR
  #|RRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRRcAAAJfBgX/
  #|/1vcRem95tlIt5Ys2CDZI+7veDI2NCAtIGNvcmUgMTY1IHIzMjIzIDA0ODBjYjAgLSBILjI2
  #|NC9NUEVHLTQgQVZDIGNvZGVjIC0gQ29weWxlZnQgMjAwMy0yMDI1IC0gaHR0cDovL3d3dy52
  #|aWRlb2xhbi5vcmcveDI2NC5odG1sIC0gb3B0aW9uczogY2FiYWM9MCByZWY9MSBkZWJsb2Nr
  #|PTA6MDowIGFuYWx5c2U9MDowIG1lPWRpYSBzdWJtZT0wIHBzeT0xIHBzeV9yZD0xLjAwOjAu
  #|MDAgbWl4ZWRfcmVmPTAgbWVfcmFuZ2U9MTYgY2hyb21hX21lPTEgdHJlbGxpcz0wIDh4OGRj
  #|dD0wIGNxbT0wIGRlYWR6b25lPTIxLDExIGZhc3RfcHNraXA9MSBjaHJvbWFfcXBfb2Zmc2V0
  #|PTAgdGhyZWFkcz0xIGxvb2thaGVhZF90aHJlYWRzPTEgc2xpY2VkX3RocmVhZHM9MCBucj0w
  #|IGRlY2ltYXRlPTEgaW50ZXJsYWNlZD0wIGJsdXJheV9jb21wYXQ9MCBjb25zdHJhaW5lZF9p
  #|bnRyYT0wIGJmcmFtZXM9MCB3ZWlnaHRwPTAga2V5aW50PTQga2V5aW50X21pbj0xIHNjZW5l
  #|Y3V0PTAgaW50cmFfcmVmcmVzaD0wIHJjPWFiciBtYnRyZWU9MCBiaXRyYXRlPTI0IHJhdGV0
  #|b2w9MS4wIHFjb21wPTAuNjAgcXBtaW49MCBxcG1heD02OSBxcHN0ZXA9NCBpcF9yYXRpbz0x
  #|LjQwIGFxPTAAgAAABVFliIQGqDGAAgAAgVgACBBwAAgcAAaAeg8CeBmAZ/ptIwFMABtAAFNs
  #|AQACAEBBkyA6EBANtQgAAgagACGMZEAAEDUAAQxmAA4AAgUAACBoB5MAGQPXA0DF2PLcCqaX
  #|/4cAAQnQABH+MjgACH+AAJkBnQAAQHQABAiBzwA2DpeJ5+3ltdC+Tn/7QAAQEgABASD2QCIe
  #|pzsXsxBTBxd3/4cAAQPwABDiYoAAMAGABg6uC8L5aPRPAgerw4AAgfgACHEwBIGAAISYDgAi
  #|CiGV2beaQH6XkZn6gAAgAYAGji4LwvFo9k8CD6vUAAwBgBgmmG44kAuO4IHq9IAAIT4AOAAI
  #|EQA0Fy9uLYCqT798kAAEH8AYAAQCQCA3Ts5BAkO1++BAACOoAAI/gAAkkAACKGEAAIHQAAix
  #|gACGUAAIygADgAMoKA0HxGVp1NyfhHWA2Bg4MCPeCXgV+YIVL4AYmta4AAEB8AAQDAOBFiv2
  #|pKgNY8O1TXtBAACCF7AAmwkPoRkgaLNx/AAXgAMOlTABYuiOuBhcxPcABAHBQg6Px+ypLB6P
  #|9oIIReAABAgAAEB0NHkxw9nJQAoYMkOeDVwABgACD2YEgKalMIN542w/eJTC+ADgACC+ADgA
  #|CBCAB0D0TQBtGcCSFkAAqBbCqABVAOoAAnWjgACGwAAJWJkBYACACAwADBcFYAujabauAABA
  #|vAAEDwBRYACoCwRzqOXsRXUIglnRAAARIQGAAEIwAePcggAAg8AACMeZHAAEBgAAQczJAAAi
  #|QgACGQAAIE0sAJAAEBgAAQHAW6AIgvGcjHLUUVYIjaR6AABAGAAMAAaHhGdQbBEG0NQDP6vU
  #|AACAAABwAPCQGpeSTUJ4AQg4+r2AAAhpgAHAAEEwACgeHR49CKAKIQQQjqegAAEEgAAQbwAB
  #|AkAASKQVAbwQg41WBYAAgAgAcADgmBqXmg1CcAEIUvV6gABgBgA4ZGZHCeUDcC0DR6vQAACC
  #|SAAIN4AAgSAAJig1AbwQhSqtgAAISYAYAAQGQBAPCOsayiB4CCCERjwQAAgYAACUgAAIFwAA
  #|p0BAACAsAAISYUAd0ARgCAPDAFHutSXyoYgKVNuAMNI0imA0Ls1PDpQh4MXAAAgvAACA8ASA
  #|aG5EneHIEjxchYy/wAAIJoAAgDAQAiJ3WJ3Wgr+rcG+I3AABgw8Inx3nuuNQaHlMykHgAAQC
  #|QUAPBNIBN5KW095AKHRzAQOAABAxAAEAcCAbJi/HsvAdyJ8mls4AAEEgAAQJQDQGDoSXbzaX
  #|nGlTsJwWcHAAEeoAASnAABGSAAFgFMywABCfAAEgRiDgACE+AAJAjBYAAhPAACQKwWAAIP4A
  #|AjTMDgACE8AAJArA4AAg/gACNMxBwABCfAAEgRiDgACE+AAJAjA4AAhPAACQKwOAAIP4AAjT
  #|MDgACE8AAJArA4AAg/gACNMwIAAIN4AAjmRAABDKAAEo+QAAVAAEBgAAQT7hAQABBoCLgcAA
  #|qAAIDAAAgn3A4QABBoCLhAAAgeAACDyAAITlwgAQABCzABdwOAAIHgAAg8gACE5cDgCAAIWY
  #|ALuBZzAABCrAAFSkAAQUwABR1TBAABDSAAEp9jxwABDSAAEp9j5YAAhJgACPExBwABCTAAEe
  #|JgcAAQ0gABKfYjgACGkAAJT7GDgACEmAAI8TEHAAEJMAAR4mBAABAYAAEqiIAAIFAAAkJyAg
  #|ACFkAAIRlwiAAIWAAAhE3A4QABCyAAEIy4HgACFgAAIRNwgAAiAAIKYAAgj3CAADAAAg+gAC
  #|E5cDgAEQABBTAAEEe4HAAMAACD6AAITlyAEAnNk5HUS6GUS8FWS+fb5//i/8/16441q0r/X9
  #|P/w/8/x5461d3XP+v5/9P/n66441qzX/p+f/T/7/XHHHGpeLLopA4DLo5JxNMzYYrmmmXsbG
  #|yOzZsiWOQuqhbRLQUYTrOdFVRjGoNHRRHQboHUKDdBp1UUHEatiIs2EfLct2ydC6Nr7GyKLY
  #|UvyGMFI0U7hjzznOdSlRqUqeeeeedU6p1TqnnnnUqedU86p5551Tq2HnnnnoKC6lCJzWFInc
  #|PwU51Q80/Mqefmn+Xyq5iJ+o6FIA4AES8ori5mVnPPf5/6f/brXHF3dyXK4Wm43xzrAPcg/8
  #|AZ9AP8ZgPfQD/ADoT7gh7++iED4Ad9wH/gwd9yB/gwT7kD/DYHuQGZsD30AfDYHuRMl/Dqfx
  #|w4mUp/HwkvEYomWCIAxgCQYgAiEQAAFQsG2IRCYDgAAAAJlBmiAarwtA4AIAwKZAHgAEwADA
  #|KDbwG4yHsdg21fgCKFhRPW61BZAY5BIFCbJuG2oPwgABEPAAEPMAAQEwDoQAAgNAAEQgABxB
  #|SDBagAAgRoEOHawAB6AZcAfBAACAMxwADAgImYkSm4jGARmYMABwABAgAAECcACgCQIyFqEg
  #|SWIxhGRFYSA+ABlAcEohn0Y1b9Ep7/biGSABFjKLIsFMqu//7H/8l6l3JaSIur3d+vjw5aGZ
  #|N5IDN/gjkYsonRixdaonl9KkYsXOqJ4LnPGNN9HUonlmnQQonBPLrVEkGnQT1HVVExdaosWU
  #|ToJKzqi0rMpDzFzoiYs9+shXrPZv0wCCey+rrOy4ABiatbLeoBEWhesGwgBwCwVCgAQAcAFC
  #|MovmFKrO/2/xxqXctJJEkSIiCdcDyJlUPIKdcDIp2tz0UyqAjKMwnoDkSqIGRHAeQSqOdkU6
  #|zMi5lUPIJVEDIp1mYiZVDwyzrgZFO1Q8iZVCRFOuBkXM1Q8iaejncinXAyKZVDyJp6IGRTr3
  #|PRcyqHkZZ1wMinWZ6KZVDzmWdcDIpxQ8iZVHO5FOuBkXMqh5EyqEsinXAxEyqHkZZ6IGRTr3
  #|PcA=

///|
test "a movie becomes an initialisation section and key frame segments" {
  let file = @mp4.Mp4::parse(@base64.decode(movie, whitespace=true)[:])
  let packager = @moonmedia.Packager::new(file, target_duration=0.3)
  let segments = packager.segments()
  assert_true(segments.length() >= 1)
  // Every segment is a fragment, and a fragment starts with its header.
  for segment in segments {
    assert_eq(segment.data[4:8], Bytes::from_array([b'm', b'o', b'o', b'f']))
    assert_eq(segment.keyframe, true)
    assert_true(segment.samples.length() == 2)
  }
  // The segments tile the stream without a gap.
  assert_eq(segments[0].start, 0.0)
  for i = 1; i < segments.length(); i = i + 1 {
    assert_eq(
      segments[i].start,
      segments[i - 1].start + segments[i - 1].duration,
    )
  }
  // What a player needs first is a file of its own, holding the codec and no
  // frames.
  let init = packager.init_segment()
  let init_file = @mp4.Mp4::parse(init[:])
  assert_eq(init_file.boxes.map(fn(b) { b.type_ }), ["ftyp", "moov"])
}

///|
test "the media playlist names the segments it was given" {
  let file = @mp4.Mp4::parse(@base64.decode(movie, whitespace=true)[:])
  let packager = @moonmedia.Packager::new(file, target_duration=0.3)
  let playlist = packager.media_playlist()
  let text = playlist.encode()
  assert_true(text.has_prefix("#EXTM3U\n"))
  assert_true(text.contains("#EXT-X-MAP:URI=\"init.mp4\"\n"))
  assert_true(text.contains("segment0.m4s\n"))
  // The playlist a player reads and the playlist written from it agree.
  assert_eq(@m3u8.Playlist::parse(text[:]).media().unwrap(), playlist)
  // The target duration is a whole number of seconds at least as long as the
  // longest segment, which is what a player reloads on.
  let mut longest = 0.0
  for segment in packager.segments() {
    if segment.duration > longest {
      longest = segment.duration
    }
  }
  assert_true(playlist.target_duration.to_double() >= longest)
}

///|
test "the master playlist names the codecs a player has to support" {
  let file = @mp4.Mp4::parse(@base64.decode(movie, whitespace=true)[:])
  let packager = @moonmedia.Packager::new(file)
  let master = packager.master_playlist()
  assert_eq(master.variants.length(), 1)
  assert_eq(master.variants[0].codecs, Some("avc1.42c00a,mp4a.40.2"))
  assert_eq(master.variants[0].resolution, Some(@m3u8.Resolution::new(32, 32)))
  assert_true(master.variants[0].bandwidth.unwrap() > 0)
  assert_eq(master.i_frame_streams.length(), 0)
  let text = master.encode()
  assert_true(text.contains("#EXT-X-STREAM-INF:"))
}

///|
test "panic: a file with no movie header cannot be cut" {
  let file = @mp4.Mp4::parse(
    Bytes::from_array([
      b'\x00', b'\x00', b'\x00', b'\x08', b'f', b't', b'y', b'p',
    ]),
  )
  @moonmedia.Packager::new(file) |> ignore
}

///|
test "a packaged stream reads back as a fragmented file and cuts the same way" {
  let file = @mp4.Mp4::parse(@base64.decode(movie, whitespace=true)[:])
  let first = @moonmedia.Packager::new(file, target_duration=0.3)
  // What a player does: the initialisation section, then the segments in order.
  let buf = @buffer.Buffer()
  buf.write_bytes(first.init_segment())
  for segment in first.segments() {
    buf.write_bytes(segment.data)
  }
  let joined = buf.contents()
  let repackaged = @mp4.Mp4::parse(joined[:])
  assert_eq(repackaged.is_fragmented(), true)
  let samples = file.tracks().map(fn(track) { track.samples.length() })
  assert_eq(
    repackaged.tracks().map(fn(track) { track.samples.length() }),
    samples,
  )
  // Cutting it again gives the segments it was cut into, byte for byte.
  let second = @moonmedia.Packager::new(repackaged, target_duration=0.3)
  assert_eq(second.segments().length(), first.segments().length())
  for i, segment in second.segments() {
    assert_eq(segment.data, first.segments()[i].data)
    assert_eq(segment.start, first.segments()[i].start)
    assert_eq(segment.duration, first.segments()[i].duration)
  }
}

///|
test "the packaged stream lasts as long as the segments it was cut into" {
  let file = @mp4.Mp4::parse(@base64.decode(movie, whitespace=true)[:])
  let packager = @moonmedia.Packager::new(file, target_duration=0.3)
  let mut total = 0.0
  for segment in packager.segments() {
    total = total + segment.duration
  }
  assert_true(total > 0.0)
  assert_eq(packager.duration(), total)
}

///|
test "the media playlist can be served from a prefix" {
  let file = @mp4.Mp4::parse(@base64.decode(movie, whitespace=true)[:])
  let packager = @moonmedia.Packager::new(file, target_duration=0.3)
  let playlist = packager.media_playlist(
    prefix="media/",
    init_name="header.mp4",
  )
  assert_eq(playlist.segments[0].uri, "media/segment0.m4s")
  assert_eq(playlist.segments[0].map.unwrap().uri, "media/header.mp4")
  // Every segment names the same initialisation section, and a player reading
  // the playlist back gets the names that were written.
  for segment in playlist.segments {
    assert_eq(segment.map.unwrap().uri, "media/header.mp4")
  }
  assert_eq(@m3u8.Playlist::parse(playlist.encode()).media().unwrap(), playlist)
}

///|
test "the master playlist keeps the bandwidth and the name it is given" {
  let file = @mp4.Mp4::parse(@base64.decode(movie, whitespace=true)[:])
  let packager = @moonmedia.Packager::new(file)
  let master = packager.master_playlist(uri="index.m3u8", bandwidth=800_000)
  assert_eq(master.variants.length(), 1)
  assert_eq(master.variants[0].uri, "index.m3u8")
  assert_eq(master.variants[0].bandwidth, Some(800_000))
  assert_true(master.encode().contains("#EXT-X-STREAM-INF:BANDWIDTH=800000"))
}

///|
/// Eight frames of a 64 x 64 test pattern, 250 ms apart, with a key frame only
/// at the first and the fifth: a group of pictures longer than the target
/// duration, so a cut has to wait for the second key frame.
let gop_movie : String =
  #|AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAJqbW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAA
  #|AAAD6AAAB9AAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAA
  #|AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAfZ0cmFrAAAAXHRraGQAAAAHAAAAAAAAAAAAAAAB
  #|AAAAAAAAB9AAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAA
  #|AEAAAABAAAAAAAGSbWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAAAyAAAAB9BVxAAAAAAALWhkbHIAAAAA
  #|AAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABPW1pbmYAAAAUdm1oZAAAAAEAAAAAAAAA
  #|AAAAASFzdGJsAAAAhXN0c2QAAAAAAAAAAQAAAHVhdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAEAA
  #|QABIAAAASAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAGP//AAAAH2F2Y0MB
  #|QsAK/+EACWdCwArZAPA8AQAEaM48gAAAABhzdHRzAAAAAAAAAAEAAAAIAAAMgAAAABxzdHNjAAAAAAAA
  #|AAEAAAABAAAACAAAAAEAAAA0c3RzegAAAAAAAAAAAAAACAAAAAUAAAAFAAAABQAAAAUAAAAFAAAABQAA
  #|AAUAAAAFAAAAGHN0c3MAAAAAAAAAAgAAAAEAAAAFAAAAFHN0Y28AAAAAAAAAAQAAApIAAAAwbWRhdAAA
  #|AAFlAAAAAUEAAAABQQAAAAFBAAAAAWUAAAABQQAAAAFBAAAAAUE=

///|
test "a cut never falls inside a group of pictures" {
  let file = @mp4.Mp4::parse(@base64.decode(gop_movie, whitespace=true)[:])
  let packager = @moonmedia.Packager::new(file, target_duration=0.3)
  // The nearest key frame is one second away, so each segment lasts a second
  // even though the target is 0.3.
  assert_eq(packager.segments().length(), 2)
  for segment in packager.segments() {
    assert_eq(segment.duration, 1.0)
    let fragment = @mp4.Mp4::parse(segment.data).fragments()[0]
    assert_eq(fragment.runs[0].samples[0].sync, true)
  }
}

///|
test "the media playlist is a complete one of independent segments" {
  let file = @mp4.Mp4::parse(@base64.decode(movie, whitespace=true)[:])
  let packager = @moonmedia.Packager::new(file, target_duration=0.3)
  let text = packager.media_playlist().encode()
  // A file that has an end is a VOD playlist, and every segment begins on a key
  // frame, which is what lets a player switch rendition between them.
  assert_true(text.contains("#EXT-X-PLAYLIST-TYPE:VOD\n"))
  assert_true(text.contains("#EXT-X-INDEPENDENT-SEGMENTS\n"))
  assert_true(text.has_suffix("#EXT-X-ENDLIST\n"))
  assert_true(packager.master_playlist().independent_segments)
}

///|
test "the initialisation section describes the codec and claims no frames" {
  let file = @mp4.Mp4::parse(@base64.decode(movie, whitespace=true)[:])
  let packager = @moonmedia.Packager::new(file, target_duration=0.3)
  let init = @mp4.Mp4::parse(packager.init_segment())
  let moov = init.movie().unwrap()
  // A stream still being written does not know how long it is: each fragment
  // says when it starts, and the header says nothing.
  assert_eq(@mp4.movie_header(moov).duration, 0L)
  assert_true(moov.child("mvex") != None)
  // The sample description stays, because a player needs the codec; every table
  // that describes frames is gone.
  let trak = moov.children_of("trak")[0]
  let stbl = trak
    .child("mdia")
    .unwrap()
    .child("minf")
    .unwrap()
    .child("stbl")
    .unwrap()
  assert_eq(stbl.boxes().map(fn(box) { box.type_ }), ["stsd"])
  for track in init.tracks() {
    assert_eq(track.samples.length(), 0)
  }
}
