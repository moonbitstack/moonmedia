// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

// A movie in, the files a server would answer with out, written as JSON.
//
// The segment data is base64 because a terminal is not a byte stream a script
// can split: `scripts/check_interop.py` turns this JSON back into an
// initialisation section, one file per segment and the two playlists, then asks
// ffmpeg to play them.

///|
fn main raise {
  // The JSON the script reads back; `@json` keeps the base64 and the playlist
  // text escaped without a writer here having to think about it.

  let movie = @base64.decode(clip, ignore_whitespace=true)
  let file = @mp4.Mp4::parse(movie[:])
  // The clip holds a key frame every half second, and the target is shorter
  // than that: a segment may only begin where a player may begin, so each one
  // lasts half a second and the cut falls on the next key frame rather than on
  // the target.
  let packager = @moonmedia.Packager::new(file, target_duration=0.3)
  let segments : Array[Json] = []
  for i, segment in packager.segments() {
    segments.push(
      Json::object(
        Map([
          ("name", Json::string("segment" + i.to_string() + ".m4s")),
          ("start", Json::number(segment.start)),
          ("duration", Json::number(segment.duration)),
          (
            "samples",
            Json::array(
              segment.samples.map(fn(count) { Json::number(count.to_double()) }),
            ),
          ),
          ("data", Json::string(@base64.encode(segment.data))),
        ]),
      ),
    )
  }
  let out = Json::object(
    Map([
      ("duration", Json::number(packager.duration())),
      (
        "init",
        Json::object(
          Map([
            ("name", Json::string("init.mp4")),
            ("data", Json::string(@base64.encode(packager.init_segment()))),
          ]),
        ),
      ),
      ("segments", Json::array(segments)),
      ("media", Json::string(packager.media_playlist().encode())),
      (
        "master",
        Json::string(packager.master_playlist(uri="index.m3u8").encode()),
      ),
    ]),
  )
  println(out.stringify())
}
