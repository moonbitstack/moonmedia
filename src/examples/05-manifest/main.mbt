// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Build a manifest for a packaged stream and print it.
///
///     moon run src/examples/05-manifest
#coverage.skip
fn main raise {
  let manifest = @mpd.Manifest::new(kind=@mpd.Kind::Static)
  manifest.min_buffer_time = Some(2.0)
  manifest.duration = Some(8.0)
  manifest.base_url = Some("https://example.com/vod/")

  let period = @mpd.Period::new(id="1", start=0.0)
  period.duration = Some(8.0)

  let video = @mpd.AdaptationSet::new(
    content_type="video",
    mime_type="video/mp4",
  )
  video.id = Some(1)
  video.segment_alignment = Some(true)
  video.frame_rate = Some(30.0)
  let template = @mpd.Template::new()
  template.timescale = Some(1000L)
  template.duration = Some(4000L)
  template.start_number = Some(1L)
  template.initialization = Some("init-$RepresentationID$.mp4")
  template.media = Some("seg-$RepresentationID$-$Number$.m4s")
  video.template = Some(template)
  let rendition = @mpd.Representation::new("v0", bandwidth=1_200_000)
  rendition.codecs = Some("avc1.64001f")
  rendition.width = Some(1280)
  rendition.height = Some(720)
  video.representations.push(rendition)
  period.adaptations.push(video)

  let audio = @mpd.AdaptationSet::new(
    content_type="audio",
    mime_type="audio/mp4",
    lang="en",
  )
  audio.id = Some(2)
  let sound = @mpd.Representation::new("a0", bandwidth=128_000)
  sound.codecs = Some("mp4a.40.2")
  sound.audio_sampling_rate = Some(48_000)
  let audio_template = @mpd.Template::new()
  audio_template.timescale = Some(48_000L)
  audio_template.duration = Some(192_000L)
  audio_template.initialization = Some("a-init.mp4")
  audio_template.media = Some("a-$Number$.m4s")
  sound.template = Some(audio_template)
  audio.representations.push(sound)
  period.adaptations.push(audio)

  manifest.periods.push(period)
  let text = manifest.encode()
  println(text)

  // What a player reads is what was written.
  let back = @mpd.Manifest::parse(text)
  println("periods: " + back.periods.length().to_string())
  println("duration: " + @mpd.format_duration(back.duration.unwrap()))
  for set in back.periods[0].adaptations {
    println(
      set.content_type.unwrap() +
      ": " +
      set.representations[0].id +
      " at " +
      set.representations[0].bandwidth.unwrap().to_string() +
      " bit/s",
    )
  }
}
