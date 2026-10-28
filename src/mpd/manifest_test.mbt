// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A manifest of the shape a packager writes for a segmented stream.
let example : String =
  #|<?xml version="1.0" encoding="UTF-8"?>
  #|<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static" profiles="urn:mpeg:dash:profile:isoff-live:2011" minBufferTime="PT2S" mediaPresentationDuration="PT10S">
  #|  <BaseURL>https://example.com/vod/</BaseURL>
  #|  <Period id="1" start="PT0S" duration="PT10S">
  #|    <AdaptationSet id="1" contentType="video" mimeType="video/mp4" segmentAlignment="true" maxWidth="1280" maxHeight="720" frameRate="30">
  #|      <SegmentTemplate timescale="1000" duration="4000" startNumber="1" initialization="init-$RepresentationID$.mp4" media="seg-$RepresentationID$-$Number$.m4s"/>
  #|      <Representation id="v0" bandwidth="1200000" codecs="avc1.64001f" width="1280" height="720" frameRate="30"/>
  #|    </AdaptationSet>
  #|    <AdaptationSet id="2" contentType="audio" mimeType="audio/mp4" lang="en" audioSamplingRate="48000">
  #|      <Representation id="a0" bandwidth="128000" codecs="mp4a.40.2" audioSamplingRate="48000">
  #|        <SegmentTemplate timescale="48000" duration="192000" startNumber="1" initialization="a-init.mp4" media="a-$Number$.m4s"/>
  #|      </Representation>
  #|    </AdaptationSet>
  #|  </Period>
  #|</MPD>
  #|

///|
test "a manifest is read into its parts" {
  let manifest = @mpd.Manifest::parse(example)
  assert_eq(manifest.kind, @mpd.Kind::Static)
  assert_eq(manifest.min_buffer_time, Some(2.0))
  assert_eq(manifest.duration, Some(10.0))
  assert_eq(manifest.base_url, Some("https://example.com/vod/"))
  assert_eq(manifest.periods.length(), 1)
  let period = manifest.periods[0]
  assert_eq(period.id, Some("1"))
  assert_eq(period.start, Some(0.0))
  assert_eq(period.adaptations.length(), 2)
  let video = period.adaptations[0]
  assert_eq(video.content_type, Some("video"))
  assert_eq(video.mime_type, Some("video/mp4"))
  assert_eq(video.segment_alignment, Some(true))
  assert_eq(video.frame_rate, Some(30.0))
  assert_eq(video.representations.length(), 1)
  let representation = video.representations[0]
  assert_eq(representation.id, "v0")
  assert_eq(representation.bandwidth, Some(1200000))
  assert_eq(representation.codecs, Some("avc1.64001f"))
  assert_eq(representation.width, Some(1280))
  // The template belongs to the set, and every representation in it uses it.
  let template = video.template.unwrap()
  assert_eq(template.timescale, Some(1000L))
  assert_eq(template.duration, Some(4000L))
  assert_eq(template.media, Some("seg-$RepresentationID$-$Number$.m4s"))
  // The audio template belongs to the representation instead.
  let audio = period.adaptations[1]
  assert_eq(audio.lang, Some("en"))
  assert_eq(audio.template, None)
  assert_eq(
    audio.representations[0].template.unwrap().media,
    Some("a-$Number$.m4s"),
  )
}

///|
test "a manifest written from what was read says the same thing" {
  let manifest = @mpd.Manifest::parse(example)
  let text = manifest.encode()
  let again = @mpd.Manifest::parse(text)
  assert_eq(again, manifest)
  // Writing it twice gives the same text, which is what makes the writer a
  // fixed point rather than something that drifts.
  assert_eq(again.encode(), text)
  // The declaration comes first and every element is closed.
  assert_true(text.has_prefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"))
  assert_true(text.contains("<MPD "))
  assert_true(text.contains("<SegmentTemplate "))
}

///|
test "a segment timeline carries runs of segments" {
  let text =
    #|<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="dynamic" minimumUpdatePeriod="PT2S" availabilityStartTime="2026-01-02T03:04:05Z" timeShiftBufferDepth="PT1M">
    #|  <Period id="live" start="PT0S">
    #|    <AdaptationSet contentType="video" mimeType="video/mp4">
    #|      <SegmentTemplate timescale="90000" initialization="init.mp4" media="seg-$Time$.m4s" startNumber="0">
    #|        <SegmentTimeline>
    #|          <S t="0" d="360000" r="2"/>
    #|          <S d="180000" r="-1"/>
    #|        </SegmentTimeline>
    #|      </SegmentTemplate>
    #|      <Representation id="v" bandwidth="800000"/>
    #|    </AdaptationSet>
    #|  </Period>
    #|</MPD>
  let manifest = @mpd.Manifest::parse(text)
  assert_eq(manifest.kind, @mpd.Kind::Dynamic)
  assert_eq(manifest.minimum_update_period, Some(2.0))
  assert_eq(manifest.time_shift_buffer_depth, Some(60.0))
  assert_eq(manifest.availability_start, Some("2026-01-02T03:04:05Z"))
  let template = manifest.periods[0].adaptations[0].template.unwrap()
  assert_eq(template.timeline.length(), 2)
  assert_eq(template.timeline[0].time, Some(0L))
  assert_eq(template.timeline[0].duration, 360000L)
  assert_eq(template.timeline[0].repeat, 2)
  // Three segments of four seconds, then an open run.
  assert_eq(template.timeline[0].span(), 1_080_000L)
  assert_eq(template.timeline[1].repeat, -1)
  // A manifest that leaves out an attribute the specification requires gets
  // one when it is written, so what has to hold is that writing is stable.
  let text = manifest.encode()
  assert_eq(@mpd.Manifest::parse(text).encode(), text)
}

///|
test "the reader takes the shapes a real manifest uses" {
  // A comment, a single quoted attribute, both kinds of element ending, an
  // entity, and text with whitespace around it.
  let text =
    #|<?xml version="1.0"?>
    #|<!-- written by hand -->
    #|<MPD type='static' profiles="x" minBufferTime="PT1.5S">
    #|  <BaseURL>
    #|    https://example.com/a?b=1&amp;c=2
    #|  </BaseURL>
    #|  <Period id="p"><AdaptationSet contentType="video"><!-- nothing here --></AdaptationSet></Period>
    #|</MPD>
  let manifest = @mpd.Manifest::parse(text)
  assert_eq(manifest.min_buffer_time, Some(1.5))
  assert_eq(manifest.base_url, Some("https://example.com/a?b=1&c=2"))
  assert_eq(manifest.periods[0].adaptations.length(), 1)
  // Writing it back escapes the ampersand again, so reading it gives the same
  // value.
  let again = @mpd.Manifest::parse(manifest.encode())
  assert_eq(again.base_url, manifest.base_url)
}

///|
test "a duration reads and writes the way the specification spells it" {
  assert_eq(@mpd.parse_duration("PT2S"), Some(2.0))
  assert_eq(@mpd.parse_duration("PT1M30.5S"), Some(90.5))
  assert_eq(@mpd.parse_duration("PT1H2M3S"), Some(3723.0))
  assert_eq(@mpd.parse_duration("PT0.5S"), Some(0.5))
  assert_eq(@mpd.parse_duration("P1D"), Some(86_400.0))
  assert_eq(@mpd.parse_duration("-PT5S"), Some(-5.0))
  // Years and months have no fixed length, so a duration that uses them is
  // refused rather than guessed at.
  assert_eq(@mpd.parse_duration("P1Y"), None)
  assert_eq(@mpd.parse_duration("P1M"), None)
  assert_eq(@mpd.parse_duration("2S"), None)
  assert_eq(@mpd.format_duration(2.0), "PT2S")
  assert_eq(@mpd.format_duration(90.5), "PT1M30.5S")
  assert_eq(@mpd.format_duration(3723.0), "PT1H2M3S")
  assert_eq(@mpd.format_duration(0.0), "PT0S")
  // A writer and a reader that disagree by a millisecond would put segments in
  // the wrong place, so the text round-trips to the same number.
  for seconds in [0.001, 1.5, 59.999, 3600.0, 86_399.5] {
    assert_eq(@mpd.parse_duration(@mpd.format_duration(seconds)), Some(seconds))
  }
}

///|
test "a period carries its own base address" {
  let text =
    #|<MPD type="static" minBufferTime="PT2S"><Period id="1" duration="PT5S"><BaseURL>period-1/</BaseURL><AdaptationSet contentType="text" lang="en"/></Period></MPD>
  let manifest = @mpd.Manifest::parse(text)
  assert_eq(manifest.periods[0].base_url, Some("period-1/"))
  assert_eq(manifest.periods[0].duration, Some(5.0))
  assert_eq(manifest.periods[0].adaptations[0].content_type, Some("text"))
  let text = manifest.encode()
  assert_eq(@mpd.Manifest::parse(text).encode(), text)
}

///|
test "panic: a document without a root element is refused" {
  @mpd.Manifest::parse("<?xml version=\"1.0\"?>") |> ignore
}

///|
test "panic: a document whose tags do not match is refused" {
  @mpd.Manifest::parse("<MPD><Period></AdaptationSet></MPD>") |> ignore
}

///|
test "panic: an unclosed element is refused" {
  @mpd.Manifest::parse("<MPD><Period>") |> ignore
}

///|
test "panic: a duration that is not one is refused" {
  @mpd.Manifest::parse("<MPD minBufferTime=\"soon\"/>") |> ignore
}
