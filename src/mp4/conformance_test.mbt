// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The vectors in `vectors_ffmpeg_test.mbt` and `vectors_gpac_test.mbt` were
// written by ffmpeg and MP4Box, and the facts beside them are ffprobe's reading
// of the same bytes. Each test renders what this package makes of the file and
// compares the two readings line for line: a sample count, a decode time or a
// key frame the two disagree about is a difference in the file, not a matter of
// taste.

///|
/// The four letters that name the codec, out of the string a player uses:
/// `avc1.42c00a` is an `avc1` sample entry.
fn fourcc(codec : String) -> String {
  let view = codec[:]
  match view.find(".") {
    Some(at) => view[0:at].to_owned()
    None => codec
  }
}

///|
/// A movie as the reference facts write it: one line per track, then one line
/// per sample with the time it decodes and the time it is shown.
///
/// The times are the presentation's, not the media's: an edit list moves one to
/// the other, and ffprobe reports the first.
fn describe(file : @mp4.Mp4) -> String raise @mp4.Mp4Error {
  let lines : Array[String] = ["bytes " + file.data.length().to_string()]
  for track in file.tracks() {
    let mut ticks = 0L
    for sample in track.samples {
      ticks = ticks + sample.duration
    }
    let kind = match track.kind {
      @mp4.TrackKind::Video => "video"
      @mp4.TrackKind::Audio => "audio"
      @mp4.TrackKind::Subtitle => "subtitle"
      @mp4.TrackKind::Hint => "hint"
      @mp4.TrackKind::Other(name) => name
    }
    lines.push(
      "stream " +
      kind +
      " " +
      fourcc(track.codec) +
      " " +
      track.width.to_string() +
      "x" +
      track.height.to_string() +
      " timescale " +
      track.timescale.to_string() +
      " ticks " +
      ticks.to_string(),
    )
    for i, sample in track.samples {
      let mut line = "  " +
        i.to_string() +
        " dts " +
        (sample.dts - track.edit_time).to_string() +
        " pts " +
        (sample.pts() - track.edit_time).to_string()
      if sample.sync {
        line = line + " key"
      }
      lines.push(line)
    }
  }
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
test "a movie ffmpeg wrote reads the way ffprobe reads it" {
  let bytes = load(ffmpeg_progressive_movie)
  let file = @mp4.Mp4::parse(bytes[:])
  assert_eq(describe(file), ffmpeg_progressive_facts)
  // Reading and writing it again is the same bytes, so nothing was lost on the
  // way through the box tree.
  assert_eq(file.encode(), bytes)
}

///|
test "a fragmented file ffmpeg wrote reads the way ffprobe reads it" {
  let bytes = load(ffmpeg_fragmented_movie)
  let file = @mp4.Mp4::parse(bytes[:])
  assert_eq(file.is_fragmented(), true)
  assert_eq(describe(file), ffmpeg_fragmented_facts)
  assert_eq(file.encode(), bytes)
  // `frag_keyframe` writes one fragment per key frame, and the facts above
  // count those key frames.
  let mut key_frames = 0
  for track in file.tracks() {
    if track.kind == @mp4.TrackKind::Video {
      for sample in track.samples {
        if sample.sync {
          key_frames = key_frames + 1
        }
      }
    }
  }
  assert_eq(file.fragments().length(), key_frames)
}

///|
test "the audio track starts at its priming sample and presents it no later" {
  // An AAC encoder pads the front of the stream with a frame the decoder eats,
  // and the edit list is how a file says so. The media starts a thousand and
  // twenty-four ticks before the presentation does, which is where the two
  // readings of the file above differ.
  let file = @mp4.Mp4::parse(load(ffmpeg_progressive_movie)[:])
  let audio = file.tracks()[1]
  assert_eq(audio.kind, @mp4.TrackKind::Audio)
  assert_eq(audio.edit_time, 1024L)
  assert_eq(audio.samples[0].dts, 0L)
  assert_eq(audio.samples[0].pts() - audio.edit_time, -1024L)
}

///|
test "the initialisation section MP4Box wrote describes tracks and no frames" {
  let init = @mp4.Mp4::parse(load(gpac_cmaf_init)[:])
  let types = init.boxes.map(fn(box) { box.type_ })
  assert_eq(types[0], "ftyp")
  assert_true(types.contains("moov"))
  assert_eq(types.contains("mdat"), false)
  assert_eq(init.is_fragmented(), true)
  for track in init.tracks() {
    assert_eq(track.samples.length(), 0)
  }
}

///|
test "the segments MP4Box wrote read as the stream ffprobe reads them as" {
  // The durations of these segments live in the track extends box of the init
  // section, not in the fragments: a reader that only looks at what a fragment
  // repeats finds a track whose samples all fall on the same instant.
  let bytes = load(gpac_cmaf_init) +
    load(gpac_cmaf_first) +
    load(gpac_cmaf_second)
  assert_eq(describe(@mp4.Mp4::parse(bytes[:])), gpac_cmaf_facts)
}

///|
test "a segment MP4Box wrote is one fragment that starts on a key frame" {
  let segment = @mp4.Mp4::parse(load(gpac_cmaf_first)[:])
  let fragments = segment.fragments()
  assert_eq(fragments.length(), 1)
  let mut started = false
  for run in fragments[0].runs {
    if run.samples.length() > 0 && run.samples[0].sync {
      started = true
    }
  }
  assert_eq(started, true)
}

///|
test "the init section and the segments tile the movie they came from" {
  // A player joins the init section to the segments; the sample times it then
  // reads are the times the source had, with no gap at the joins.
  let bytes = load(gpac_cmaf_init) +
    load(gpac_cmaf_first) +
    load(gpac_cmaf_second)
  let file = @mp4.Mp4::parse(bytes[:])
  let source = @mp4.Mp4::parse(load(ffmpeg_progressive_movie)[:])
  let cut = file.tracks()
  let whole = source.tracks()
  assert_eq(cut.length(), whole.length())
  for i, track in whole {
    assert_eq(cut[i].timescale, track.timescale)
    assert_eq(cut[i].edit_time, track.edit_time)
    assert_eq(cut[i].samples.length(), track.samples.length())
    for j, sample in track.samples {
      assert_eq(cut[i].samples[j].dts, sample.dts)
      assert_eq(cut[i].samples[j].duration, sample.duration)
      assert_eq(cut[i].samples[j].sync, sample.sync)
    }
  }
}
