// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The manifests in `vectors_ffmpeg_test.mbt` and `vectors_gpac_test.mbt` were
// written by ffmpeg and MP4Box, and the facts beside them list the files those
// manifests sit next to. A manifest that names a file nobody wrote is a manifest
// that plays nothing, so the tests expand what it says and look for the result
// in the list.

///|
/// The files a fact block lists, in the order the packager left them.
fn files_of(facts : String) -> Array[String] {
  let out : Array[String] = []
  for line in facts.split("\n") {
    let text = line.trim()
    if text.has_prefix("file ") {
      let rest = text[5:]
      match rest.find(" ") {
        Some(at) => out.push(rest[0:at].to_owned())
        None => out.push(rest.to_owned())
      }
    }
  }
  out
}

///|
/// The size a fact block gives for the one file it lists.
fn size_of(facts : String) -> Int64 {
  let mut size = 0L
  for line in facts.split("\n") {
    let text = line.trim()
    match text.find("bytes ") {
      Some(at) => size = @string.parse_int64(text[at + 6:]) catch { _ => 0L }
      None => ()
    }
  }
  size
}

///|
test "the template ffmpeg wrote names the files it wrote" {
  let manifest = @mpd.Manifest::parse(ffmpeg_manifest)
  assert_eq(manifest.kind, @mpd.Kind::Static)
  assert_eq(manifest.duration, Some(1.0))
  assert_eq(manifest.periods.length(), 1)
  let period = manifest.periods[0]
  // One set for the picture and one for the sound, which is how a packager
  // splits a stream a player chooses pieces of.
  assert_eq(period.adaptations.length(), 2)
  let video = period.adaptations[0]
  assert_eq(video.content_type, Some("video"))
  assert_eq(video.representations.length(), 1)
  let representation = video.representations[0]
  assert_eq(representation.id, "0")
  assert_eq(representation.codecs, Some("avc1.42c00a"))
  assert_eq(representation.width, Some(32))
  assert_eq(representation.bandwidth, Some(8624))
  // `frameRate="8/1"` is a rate written as a fraction.
  assert_eq(video.frame_rate, Some(8.0))
  let template = representation.template.unwrap()
  assert_eq(template.timescale, Some(16384L))
  let files = files_of(ffmpeg_manifest_facts)
  // The names the manifest promises are the names on disk: the initialisation
  // section, then a segment per number, padded to five digits.
  assert_true(
    files.contains(template.initialization_url(representation_id="0")),
  )
  for number = 1L; number <= 2L; number = number + 1L {
    let name = template.segment_url(number~, representation_id="0")
    assert_true(files.contains(name))
  }
  assert_eq(template.count(manifest.duration.unwrap()), 2)
}

///|
test "the timeline ffmpeg wrote says when each segment starts" {
  let manifest = @mpd.Manifest::parse(ffmpeg_manifest)
  let video = manifest.periods[0].adaptations[0]
  let template = video.representations[0].template.unwrap()
  assert_eq(template.timeline.length(), 1)
  let entry = template.timeline[0]
  // One entry that repeats once is two segments of a second each, which is what
  // the two files beside the manifest are.
  assert_eq(entry.time, Some(0L))
  assert_eq(entry.duration, 8192L)
  assert_eq(entry.repeat, 1)
  assert_eq(entry.span(), 16384L)
  let audio = manifest.periods[0].adaptations[1]
  let audio_template = audio.representations[0].template.unwrap()
  // The sound is cut on its own grid, so its timeline has entries of different
  // lengths: a reader that assumed one duration would put the last segment in
  // the wrong place.
  assert_eq(audio_template.timeline.length(), 3)
  assert_eq(audio_template.timescale, Some(8000L))
}

///|
test "the template MP4Box wrote names the files it wrote" {
  let manifest = @mpd.Manifest::parse(gpac_live_manifest)
  assert_eq(manifest.kind, @mpd.Kind::Static)
  assert_eq(manifest.profiles, Some("urn:mpeg:dash:profile:isoff-live:2011"))
  let representation = manifest.periods[0].adaptations[0].representations[0]
  // MP4Box writes the content types as components of the set rather than as an
  // attribute of it.
  assert_eq(manifest.periods[0].adaptations[0].content_type, Some("video"))
  let template = representation.template.unwrap()
  // A template with one duration and no timeline: the segments are counted from
  // how long the presentation is.
  assert_eq(template.duration, Some(8192L))
  assert_eq(template.timescale, Some(16384L))
  assert_eq(template.count(1.0), 2)
  let files = files_of(gpac_live_manifest_facts)
  assert_true(
    files.contains(template.initialization_url(representation_id="1")),
  )
  for number = 1L; number <= 2L; number = number + 1L {
    assert_true(
      files.contains(template.segment_url(number~, representation_id="1")),
    )
  }
}

///|
test "the on-demand manifest MP4Box wrote addresses one file by byte range" {
  let manifest = @mpd.Manifest::parse(gpac_on_demand_manifest)
  let representation = manifest.periods[0].adaptations[0].representations[0]
  assert_eq(representation.base_url, Some("source_dashinit.mp4"))
  let base = representation.segment_base.unwrap()
  assert_eq(base.index_range_exact, Some(true))
  // The index sits near the start of the file and the media follows it: the
  // first segment starts where the index ends.
  let index = base.index_range.unwrap()
  assert_eq(index.start, 1409L)
  assert_eq(index.length(), Some(68L))
  let initialization = base.initialization.unwrap()
  let range = initialization.range.unwrap()
  assert_eq(range.start, 0L)
  assert_eq(range.end, Some(1380L))
  // Every range has to fall inside the file that is there, or a player asks for
  // bytes nobody wrote.
  let size = size_of(gpac_on_demand_manifest_facts)
  assert_eq(size, 4633L)
  assert_true(range.end.unwrap() < size)
  assert_true(index.end.unwrap() < size)
}

///|
test "a manifest read and written again says the same thing" {
  // The model is the manifest: writing one out and reading it back has to give
  // the same periods, the same representations and the same addressing.
  for
    text in [
      @mpd.Manifest::parse(ffmpeg_manifest),
      @mpd.Manifest::parse(gpac_live_manifest),
      @mpd.Manifest::parse(gpac_on_demand_manifest),
    ] {
    let again = @mpd.Manifest::parse(text.encode())
    assert_eq(again, text)
  }
}

///|
test "a placeholder a template does not know is left as it was written" {
  let template = @mpd.Template::new()
  template.media = Some(
    "seg-$RepresentationID$-$Number%04d$-$Time$-$Foo$-$Bar$.m4s",
  )
  assert_eq(
    template.segment_url(number=7L, representation_id="v1", time=2048L),
    "seg-v1-0007-2048-$Foo$-$Bar$.m4s",
  )
  // `$$` is how a literal dollar sign is written.
  let literal = @mpd.Template::new()
  literal.media = Some("cash$$-$Number$.m4s")
  assert_eq(literal.segment_url(number=1L), "cash$-1.m4s")
  // A number wider than its padding keeps every digit.
  let wide = @mpd.Template::new()
  wide.media = Some("$Number%02d$.m4s")
  assert_eq(wide.segment_url(number=1234L), "1234.m4s")
}
