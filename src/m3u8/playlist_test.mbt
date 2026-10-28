// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Parse, write, parse again: the second write must equal the first and the two
/// readings must agree, which is what "the writer says what the reader heard"
/// amounts to.
fn rewrite(text : StringView) -> String raise {
  let once = @m3u8.Playlist::parse(text).encode()
  let twice = @m3u8.Playlist::parse(once[:]).encode()
  assert_eq(twice, once)
  assert_eq(@m3u8.Playlist::parse(once[:]), @m3u8.Playlist::parse(text))
  once
}

///|
test "the simplest media playlist" {
  // RFC 8216 §8.1.
  let text = "#EXTM3U\n#EXT-X-TARGETDURATION:5220\n#EXTINF:5220,\nhttp://media.example.com/entire.ts\n#EXT-X-ENDLIST\n"
  assert_eq(
    rewrite(text),
    "#EXTM3U\n#EXT-X-TARGETDURATION:5220\n#EXTINF:5220,\nhttp://media.example.com/entire.ts\n#EXT-X-ENDLIST\n",
  )
  let playlist = @m3u8.Playlist::parse(text)
  let media = playlist.media().unwrap()
  assert_eq(media.target_duration, 5220)
  assert_eq(media.end_list, true)
  assert_eq(media.segments.length(), 1)
  assert_eq(media.segments[0].duration, 5220.0)
  assert_eq(media.segments[0].title, None)
}

///|
test "a live playlist keeps its sequence numbers" {
  // RFC 8216 §8.2.
  let text = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:8\n#EXT-X-MEDIA-SEQUENCE:2680\n#EXTINF:7.975,\nhttps://priv.example.com/fileSequence2680.ts\n#EXTINF:7.941,\nhttps://priv.example.com/fileSequence2681.ts\n#EXTINF:7.975,\nhttps://priv.example.com/fileSequence2682.ts\n"
  let playlist = @m3u8.Playlist::parse(text)
  let media = playlist.media().unwrap()
  assert_eq(media.version, Some(3))
  assert_eq(media.media_sequence, 2680L)
  assert_eq(media.end_list, false)
  assert_eq(media.segments.length(), 3)
  assert_eq(rewrite(text), text)
}

///|
test "encryption carries from one segment to the next" {
  // RFC 8216 §8.3, cut down to the first two key changes.
  let text = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-MEDIA-SEQUENCE:7794\n#EXT-X-TARGETDURATION:15\n#EXT-X-KEY:METHOD=AES-128,URI=\"https://priv.example.com/key.php?r=52\"\n#EXTINF:2.833,\nhttp://media.example.com/fileSequence52-A.ts\n#EXTINF:2.833,\nhttp://media.example.com/fileSequence52-B.ts\n#EXT-X-KEY:METHOD=AES-128,URI=\"https://priv.example.com/key.php?r=53\"\n#EXTINF:2.833,\nhttp://media.example.com/fileSequence53-A.ts\n#EXT-X-ENDLIST\n"
  let media = @m3u8.Playlist::parse(text).media().unwrap()
  let key52 = @m3u8.Key::new("https://priv.example.com/key.php?r=52")
  assert_eq(media.segments[0].key, Some(key52))
  // The second segment never repeats the tag, and still knows its key.
  assert_eq(media.segments[1].key, Some(key52))
  assert_eq(
    media.segments[2].key,
    Some(@m3u8.Key::new("https://priv.example.com/key.php?r=53")),
  )
  let again = rewrite(text)
  // The tag is written once, where it changed.
  assert_eq(count(again, "#EXT-X-KEY"), 2)
}

///|
test "a variant list is a master playlist" {
  // RFC 8216 §8.4, with the codecs of the last entry.
  let text = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1280000,AVERAGE-BANDWIDTH=1000000\nhttp://example.com/low.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=2560000,AVERAGE-BANDWIDTH=2000000\nhttp://example.com/mid.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=7680000,AVERAGE-BANDWIDTH=6000000\nhttp://example.com/hi.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=65000,CODECS=\"mp4a.40.5\"\nhttp://example.com/audio-only.m3u8\n"
  let playlist = @m3u8.Playlist::parse(text)
  assert_eq(playlist.is_master(), true)
  let master = playlist.master().unwrap()
  assert_eq(master.variants.length(), 4)
  assert_eq(master.variants[0].bandwidth, Some(1280000))
  assert_eq(master.variants[0].average_bandwidth, Some(1000000))
  assert_eq(master.variants[0].uri, "http://example.com/low.m3u8")
  assert_eq(master.variants[3].codecs, Some("mp4a.40.5"))
  assert_eq(rewrite(text), text)
}

///|
test "an I-frame list rides along" {
  // RFC 8216 §8.5, reduced to the I-frame entry.
  let text = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1280000\nlow/audio-video.m3u8\n#EXT-X-I-FRAME-STREAM-INF:BANDWIDTH=86000,URI=\"low/iframe.m3u8\"\n"
  let master = @m3u8.Playlist::parse(text).master().unwrap()
  assert_eq(master.i_frame_streams.length(), 1)
  assert_eq(master.i_frame_streams[0].uri, "low/iframe.m3u8")
  assert_eq(master.i_frame_streams[0].bandwidth, Some(86000))
  assert_eq(rewrite(text), text)
}

///|
test "alternative audio keeps its flags" {
  // RFC 8216 §8.6, first three renditions.
  let text = "#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"aac\",NAME=\"English\",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE=\"en\",URI=\"main/english-audio.m3u8\"\n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"aac\",NAME=\"Deutsch\",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE=\"de\",URI=\"main/german-audio.m3u8\"\n#EXT-X-STREAM-INF:BANDWIDTH=1280000,AUDIO=\"aac\"\nlow/video-only.m3u8\n"
  let master = @m3u8.Playlist::parse(text).master().unwrap()
  assert_eq(master.renditions.length(), 2)
  assert_eq(master.renditions[0].kind, @m3u8.MediaKind::Audio)
  assert_eq(master.renditions[0].default, true)
  assert_eq(master.renditions[1].default, false)
  assert_eq(master.renditions[1].autoselect, true)
  assert_eq(master.renditions[1].language, Some("de"))
  assert_eq(master.variants[0].audio, Some("aac"))
  assert_eq(rewrite(text), text)
}

///|
test "closed captions may be none rather than quoted" {
  let text = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1280000,CLOSED-CAPTIONS=NONE\nlow.m3u8\n"
  let master = @m3u8.Playlist::parse(text).master().unwrap()
  assert_eq(master.variants[0].closed_captions, Some("NONE"))
  assert_eq(rewrite(text), text)
  // A closed caption group is a quoted string, and stays one.
  let quoted_text = "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1280000,CLOSED-CAPTIONS=\"cc\"\nlow.m3u8\n"
  assert_eq(rewrite(quoted_text), quoted_text)
}

///|
test "a fragmented playlist keeps its map and byte ranges" {
  let text = "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:6\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:6.0,\n#EXT-X-BYTERANGE:1000@0\nmedia.mp4\n#EXTINF:6.0,\n#EXT-X-BYTERANGE:1012\nmedia.mp4\n#EXT-X-ENDLIST\n"
  let media = @m3u8.Playlist::parse(text).media().unwrap()
  assert_eq(media.segments[0].map, Some(@m3u8.InitSection::new("init.mp4")))
  assert_eq(
    media.segments[0].byte_range,
    Some(@m3u8.ByteRange::new(1000L, offset=0L)),
  )
  // No offset means "where the last one ended".
  assert_eq(media.segments[1].byte_range, Some(@m3u8.ByteRange::new(1012L)))
  // The map is written once, before the first segment.
  let again = rewrite(text)
  assert_eq(count(again, "#EXT-X-MAP"), 1)
}

///|
test "discontinuity and program date time travel with their segment" {
  let text = "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-DISCONTINUITY-SEQUENCE:3\n#EXTINF:4,\na.ts\n#EXT-X-DISCONTINUITY\n#EXT-X-PROGRAM-DATE-TIME:2026-01-02T03:04:05.678Z\n#EXTINF:4,\nb.ts\n"
  let media = @m3u8.Playlist::parse(text).media().unwrap()
  assert_eq(media.discontinuity_sequence, 3L)
  assert_eq(media.segments[0].discontinuity, false)
  assert_eq(media.segments[1].discontinuity, true)
  assert_eq(
    media.segments[1].program_date_time,
    Some("2026-01-02T03:04:05.678Z"),
  )
  assert_eq(rewrite(text), text)
}

///|
test "a key may be turned off again" {
  let text = "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-KEY:METHOD=AES-128,URI=\"k\"\n#EXTINF:4,\na.ts\n#EXT-X-KEY:METHOD=NONE\n#EXTINF:4,\nb.ts\n"
  let media = @m3u8.Playlist::parse(text).media().unwrap()
  assert_eq(media.segments[0].key.unwrap().is_plain(), false)
  assert_eq(media.segments[1].key.unwrap().is_plain(), true)
  let again = rewrite(text)
  // METHOD=NONE has to be written: without it the second segment would still
  // be read as encrypted.
  assert_eq(count(again, "METHOD=NONE"), 1)
}

///|
test "a playlist type and allow cache survive" {
  let text = "#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-TARGETDURATION:10\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-ALLOW-CACHE:NO\n#EXTINF:10,\na.ts\n#EXT-X-ENDLIST\n"
  let media = @m3u8.Playlist::parse(text).media().unwrap()
  assert_eq(media.playlist_type, Some(@m3u8.PlaylistType::Vod))
  assert_eq(media.allow_cache, Some(false))
  assert_eq(rewrite(text), text)
}

///|
test "start offset names a position" {
  let media_text = "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXT-X-START:TIME-OFFSET=-12.5\n#EXTINF:10,\na.ts\n"
  let media = @m3u8.Playlist::parse(media_text).media().unwrap()
  assert_eq(media.start, Some(@m3u8.Start::new(-12.5)))
  assert_eq(rewrite(media_text), media_text)
  let precise = "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXT-X-START:TIME-OFFSET=5,PRECISE=YES\n#EXTINF:10,\na.ts\n"
  assert_eq(
    @m3u8.Playlist::parse(precise).media().unwrap().start,
    Some(@m3u8.Start::new(5.0, precise=true)),
  )
}

///|
test "session data and a session key belong to the master playlist" {
  let text = "#EXTM3U\n#EXT-X-SESSION-DATA:DATA-ID=\"com.example.title\",VALUE=\"A film\",LANGUAGE=\"en\"\n#EXT-X-SESSION-KEY:METHOD=AES-128,URI=\"https://example.com/key\"\n#EXT-X-STREAM-INF:BANDWIDTH=1280000\nlow.m3u8\n"
  let master = @m3u8.Playlist::parse(text).master().unwrap()
  assert_eq(master.session_data.length(), 1)
  assert_eq(master.session_data[0].value, Some("A film"))
  assert_eq(master.session_keys.length(), 1)
  assert_eq(rewrite(text), text)
}

///|
test "low latency: parts, preload hint and rendition report" {
  // The shape of Apple's low-latency examples: the parts of a segment come
  // before the segment itself, and the parts of the segment still being
  // produced come after the last one, with a hint for what does not exist yet.
  let text = "#EXTM3U\n#EXT-X-VERSION:6\n#EXT-X-TARGETDURATION:4\n#EXT-X-SERVER-CONTROL:CAN-BLOCK-RELOAD=YES,PART-HOLD-BACK=1.0,CAN-SKIP-UNTIL=12.0\n#EXT-X-PART-INF:PART-TARGET=0.33334\n#EXT-X-MEDIA-SEQUENCE:266\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXT-X-PART:DURATION=0.33334,URI=\"filePart267.0.mp4\",INDEPENDENT=YES\n#EXT-X-PART:DURATION=0.33334,URI=\"filePart267.1.mp4\"\n#EXTINF:4.00008,\nfileSequence267.mp4\n#EXT-X-PART:DURATION=0.33334,URI=\"filePart268.0.mp4\",INDEPENDENT=YES\n#EXT-X-PRELOAD-HINT:TYPE=PART,URI=\"filePart268.1.mp4\"\n#EXT-X-RENDITION-REPORT:URI=\"../1M/waitForMSN.php\",LAST-MSN=267,LAST-PART=0\n"
  let media = @m3u8.Playlist::parse(text).media().unwrap()
  assert_eq(media.server_control.unwrap().can_block_reload, true)
  assert_eq(media.server_control.unwrap().part_hold_back, Some(1.0))
  assert_eq(media.part_inf, Some(0.33334))
  assert_eq(media.segments.length(), 1)
  assert_eq(media.segments[0].parts.length(), 2)
  assert_eq(media.segments[0].parts[0].independent, true)
  assert_eq(media.segments[0].parts[1].independent, false)
  // The parts of the segment that has no URI yet are the playlist's, not a
  // segment's.
  assert_eq(media.next_parts.length(), 1)
  assert_eq(media.next_parts[0].uri, "filePart268.0.mp4")
  assert_eq(media.preload_hint.unwrap().kind, "PART")
  assert_eq(media.rendition_reports[0].last_msn, Some(267L))
  assert_eq(media.rendition_reports[0].last_part, Some(0))
  // Tags come out in the order the specification lists them, which is not the
  // order this file happened to use.
  let canonical = "#EXTM3U\n#EXT-X-VERSION:6\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:266\n#EXT-X-SERVER-CONTROL:CAN-SKIP-UNTIL=12,PART-HOLD-BACK=1,CAN-BLOCK-RELOAD=YES\n#EXT-X-PART-INF:PART-TARGET=0.33334\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXT-X-PART:DURATION=0.33334,URI=\"filePart267.0.mp4\",INDEPENDENT=YES\n#EXT-X-PART:DURATION=0.33334,URI=\"filePart267.1.mp4\"\n#EXTINF:4.00008,\nfileSequence267.mp4\n#EXT-X-PART:DURATION=0.33334,URI=\"filePart268.0.mp4\",INDEPENDENT=YES\n#EXT-X-PRELOAD-HINT:TYPE=PART,URI=\"filePart268.1.mp4\"\n#EXT-X-RENDITION-REPORT:URI=\"../1M/waitForMSN.php\",LAST-MSN=267,LAST-PART=0\n"
  assert_eq(rewrite(text), canonical)
}

///|
test "skipped segments are counted, not listed" {
  let text = "#EXTM3U\n#EXT-X-VERSION:9\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:100\n#EXT-X-SKIP:SKIPPED-SEGMENTS=3\n#EXTINF:4,\nfileSequence103.mp4\n"
  let media = @m3u8.Playlist::parse(text).media().unwrap()
  assert_eq(media.skip, Some(3))
  assert_eq(media.segments.length(), 1)
  assert_eq(rewrite(text), text)
}

///|
test "a date range keeps its client attributes" {
  let text = "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-DATERANGE:ID=\"splice-1\",START-DATE=\"2026-01-02T03:04:05Z\",DURATION=30,SCTE35-OUT=0xFC002F,X-COM-EXAMPLE-SPLICE=1\n#EXTINF:4,\na.ts\n"
  let media = @m3u8.Playlist::parse(text).media().unwrap()
  assert_eq(media.date_ranges.length(), 1)
  let range = media.date_ranges[0]
  assert_eq(range.id, "splice-1")
  assert_eq(range.duration, Some(30.0))
  assert_eq(range.scte35_out, Some("0xFC002F"))
  assert_eq(range.extra.length(), 1)
  assert_eq(rewrite(text), text)
}

///|
test "a variable can be defined three ways" {
  let text = "#EXTM3U\n#EXT-X-DEFINE:NAME=\"host\",VALUE=\"example.com\"\n#EXT-X-DEFINE:IMPORT=\"token\"\n#EXT-X-DEFINE:QUERYPARAM=\"session\"\n#EXT-X-STREAM-INF:BANDWIDTH=1\nhttps://{$host}/low.m3u8\n"
  let master = @m3u8.Playlist::parse(text).master().unwrap()
  assert_eq(master.defines.length(), 3)
  assert_eq(master.defines[0], @m3u8.Define::new("host", "example.com"))
  assert_eq(master.defines[1].import_, Some("token"))
  assert_eq(master.defines[2].queryparam, Some("session"))
  assert_eq(rewrite(text), text)
}

///|
test "a tag this release does not model is written back" {
  let text = "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-FUTURE-THING:EVERYTHING=1\n#EXTINF:4,\na.ts\n"
  let media = @m3u8.Playlist::parse(text).media().unwrap()
  assert_eq(media.unknown, ["#EXT-X-FUTURE-THING:EVERYTHING=1"])
  // A tag whose position the model does not track is written after the
  // segments rather than dropped.
  assert_eq(
    rewrite(text),
    "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\na.ts\n#EXT-X-FUTURE-THING:EVERYTHING=1\n",
  )
}

///|
test "an attribute this release does not model is written back" {
  let text = "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-KEY:METHOD=SAMPLE-AES,URI=\"skd://key\",KEYFORMAT=\"com.apple.streamingkeydelivery\",KEYID=0x1234\n#EXTINF:4,\na.ts\n"
  let media = @m3u8.Playlist::parse(text).media().unwrap()
  let key = media.segments[0].key.unwrap()
  assert_eq(key.cipher, @m3u8.Cipher::SampleAes)
  assert_eq(key.extra, ["KEYID=0x1234"])
  assert_eq(rewrite(text), text)
}

///|
test "carriage returns and a byte order mark are ignored" {
  let lf = "#EXTM3U\r\n#EXT-X-TARGETDURATION:4\r\n#EXTINF:4.0,\r\na.ts\r\n"
  let media = @m3u8.Playlist::parse(lf).media().unwrap()
  assert_eq(media.segments[0].uri, "a.ts")
  let with_bom = "\u{FEFF}#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\na.ts\n"
  assert_eq(
    @m3u8.Playlist::parse(with_bom).media().unwrap().segments[0].uri,
    "a.ts",
  )
}

///|
test "a trailing line without a newline is read" {
  let media = @m3u8.Playlist::parse(
      "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\na.ts",
    )
    .media()
    .unwrap()
  assert_eq(media.segments.length(), 1)
}

///|
test "panic: a file that is not a playlist is refused" {
  @m3u8.Playlist::parse("#EXTINF:4,\na.ts\n") |> ignore
}

///|
test "panic: a playlist without a target duration is refused" {
  // A media playlist has to say how long its longest segment is.
  @m3u8.Playlist::parse("#EXTM3U\n#EXTINF:4,\na.ts\n") |> ignore
}

///|
test "panic: a URI with no duration before it is refused" {
  @m3u8.Playlist::parse("#EXTM3U\n#EXT-X-TARGETDURATION:4\na.ts\n") |> ignore
}

///|
test "panic: a duration that is not a number is refused" {
  @m3u8.Playlist::parse(
    "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:soon,\na.ts\n",
  )
  |> ignore
}

///|
test "panic: a key without a method is refused" {
  @m3u8.Playlist::parse(
    "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-KEY:URI=\"k\"\n#EXTINF:4,\na.ts\n",
  )
  |> ignore
}

///|
test "panic: a stream without its URI is refused" {
  @m3u8.Playlist::parse("#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1280000\n")
  |> ignore
}

///|
/// How many times `needle` occurs in `haystack`.
fn count(haystack : StringView, needle : StringView) -> Int32 {
  let mut seen = 0
  let mut at = 0
  while at < haystack.length() {
    match haystack[at:].find(needle) {
      Some(offset) => {
        seen = seen + 1
        at = at + offset + needle.length()
      }
      None => break
    }
  }
  seen
}
