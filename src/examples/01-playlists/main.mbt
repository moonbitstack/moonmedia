// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Build a master playlist and the media playlist it points at, print both, and
/// read them back to show that what was written is what is understood.
///
///     moon run src/examples/01-playlists
#coverage.skip
fn main raise {
  let media = @m3u8.MediaPlaylist::new(4)
  media.version = Some(7)
  media.playlist_type = Some(@m3u8.PlaylistType::Vod)
  media.independent_segments = true
  media.end_list = true
  let init = @m3u8.InitSection::new("init.mp4")
  for i = 0; i < 3; i = i + 1 {
    let segment = @m3u8.Segment::new("segment" + i.to_string() + ".m4s", 4.0)
    segment.map = Some(init)
    media.segments.push(segment)
  }
  let text = media.encode()
  println("media playlist")
  println(text)

  let master = @m3u8.Master::new()
  master.version = Some(7)
  master.independent_segments = true
  let variant = @m3u8.Variant::new("720p.m3u8", bandwidth=2_400_000)
  variant.resolution = Some(@m3u8.Resolution::new(1280, 720))
  variant.codecs = Some("avc1.64001f,mp4a.40.2")
  variant.frame_rate = Some(30.0)
  master.variants.push(variant)
  let master_text = master.encode()
  println("master playlist")
  println(master_text)

  // What was read has to be what was written: the same number of segments, each
  // with the initialisation section in front of it.
  let back = @m3u8.Playlist::parse(text).media().unwrap()
  println("segments read back: " + back.segments.length().to_string())
  println("first segment: " + back.segments[0].uri)
  println("initialisation: " + back.segments[0].map.unwrap().uri)
  let back_master = @m3u8.Playlist::parse(master_text).master().unwrap()
  println("variants read back: " + back_master.variants.length().to_string())
  println(
    "bandwidth: " + back_master.variants[0].bandwidth.unwrap().to_string(),
  )
}
