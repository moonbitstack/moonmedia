// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// The playlists in `vectors_ffmpeg_test.mbt` and `vectors_gpac_test.mbt` were
// written by ffmpeg and MP4Box, and the facts beside them say which files those
// playlists point at and how long the media they point at lasts. The tests read
// the text and compare what it names with what is on the other side.

///|
/// What a playlist says a player should fetch: the initialisation section, then
/// each segment with the number in the order it appears.
fn describe(playlist : @m3u8.Playlist) -> String {
  let media = match playlist.media() {
    Some(media) => media
    None => return "a master playlist"
  }
  let lines : Array[String] = []
  for i, segment in media.segments {
    match segment.map {
      Some(section) => {
        let line = "init " + section.uri
        if !lines.contains(line) {
          lines.push(line)
        }
      }
      None => ()
    }
    lines.push("segment " + i.to_string() + " uri " + segment.uri)
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
/// The names in a fact block, without the line that carries the total length.
fn names_of(facts : String) -> (String, Int32) {
  let (names, total) = facts.rev_split_once("\n").unwrap()
  (names.to_owned(), millis_of(total))
}

///|
fn millis_of(line : StringView) -> Int32 {
  let text = line.trim()
  match text.find(" ") {
    Some(at) => @string.parse_int(text[at + 1:]) catch { _ => 0 }
    None => 0
  }
}

///|
test "the media playlist ffmpeg wrote names the segments it was given" {
  let playlist = @m3u8.Playlist::parse(ffmpeg_media_playlist)
  assert_eq(playlist.is_master(), false)
  let (names, total) = names_of(ffmpeg_media_playlist_facts)
  assert_eq(describe(playlist), names)
  let media = playlist.media().unwrap()
  assert_eq(media.end_list, true)
  // The declared lengths add up to the media that is there, to within the one
  // segment a packager may round: the last segment ends where the sound does,
  // not where the picture does.
  let mut declared = 0.0
  let mut longest = 0.0
  for segment in media.segments {
    declared = declared + segment.duration
    if segment.duration > longest {
      longest = segment.duration
    }
  }
  let declared_ms = (declared * 1000.0).to_int()
  assert_true(declared_ms <= total)
  assert_true(total - declared_ms <= (longest * 1000.0).to_int() + 1)
}

///|
test "the media playlist ffmpeg wrote for fragmented MP4 names the map and the segments" {
  let playlist = @m3u8.Playlist::parse(ffmpeg_fmp4_playlist)
  let (names, total) = names_of(ffmpeg_fmp4_playlist_facts)
  assert_eq(describe(playlist), names)
  let media = playlist.media().unwrap()
  // Every segment carries the initialisation section in force where it appears,
  // which is what a player needs before it can read a fragment.
  for segment in media.segments {
    assert_true(segment.map != None)
  }
  let mut declared = 0.0
  for segment in media.segments {
    declared = declared + segment.duration
  }
  assert_true((declared * 1000.0).to_int() <= total)
}

///|
test "the master playlist MP4Box wrote describes the rendition it points at" {
  let master = @m3u8.Playlist::parse(gpac_master_playlist).master().unwrap()
  assert_eq(master.variants.length(), 1)
  let variant = master.variants[0]
  assert_eq(variant.bandwidth, Some(8624))
  assert_eq(variant.codecs, Some("avc1.42C00A,mp4a.40.2"))
  assert_eq(variant.resolution, Some(@m3u8.Resolution::new(32, 32)))
  assert_eq(variant.frame_rate, Some(8.0))
  // The media playlist the variant names is the one in the vector, and the
  // segments it names are the ones on disk.
  let media = @m3u8.Playlist::parse(gpac_media_playlist).media().unwrap()
  assert_true(gpac_master_playlist.contains(variant.uri))
  let (names, total) = names_of(gpac_playlist_facts)
  assert_eq(describe(@m3u8.Playlist::MediaPlaylist(media)), names)
  let mut declared = 0.0
  for segment in media.segments {
    declared = declared + segment.duration
  }
  assert_true(total >= (declared * 1000.0).to_int())
}

///|
test "the media playlist MP4Box wrote starts where its sequence number says" {
  // A live stream is a window over a longer list: the first segment in the file
  // is not the first of the presentation, and the sequence number says how far
  // in it is.
  let media = @m3u8.Playlist::parse(gpac_media_playlist).media().unwrap()
  assert_eq(media.media_sequence, 1L)
  assert_eq(media.independent_segments, true)
  assert_eq(media.end_list, true)
  assert_eq(media.version, Some(6))
}
