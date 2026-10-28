// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A separator between the parts of a report. It is a control character no
/// playlist can contain, so a split on it cannot hit content.
let separator : String = "\u{1E}"

///|
/// What the documentation page asks for: a playlist as text, and a report back.
///
/// The report is three parts: a summary of what was read, the playlist as this
/// package would write it, and one line per segment or variant. The page draws
/// its own tables from the last part, which keeps the layout out of the library.
pub fn report(text : String) -> String {
  let playlist = @m3u8.Playlist::parse(text) catch {
    err => return "error" + separator + err.to_string() + separator
  }
  match playlist {
    MediaPlaylist(media) => {
      let mut total = 0.0
      let mut parts = 0
      for segment in media.segments {
        total = total + segment.duration
        parts = parts + segment.parts.length()
      }
      let kind = match media.playlist_type {
        Some(Vod) => "vod"
        Some(Event) => "event"
        Some(Other(_)) => "other"
        None => "live"
      }
      let summary = "media|segments=" +
        media.segments.length().to_string() +
        "|target=" +
        media.target_duration.to_string() +
        "|duration=" +
        total.to_string() +
        "|type=" +
        kind +
        "|parts=" +
        parts.to_string() +
        "|endlist=" +
        (if media.end_list { "1" } else { "0" })
      let rows = @buffer.Buffer()
      for i, segment in media.segments {
        let row = (i + 1).to_string() +
          "\t" +
          segment.duration.to_string() +
          "\t" +
          segment.parts.length().to_string() +
          "\t" +
          segment.uri +
          "\n"
        rows.write_string_utf8(row)
      }
      summary +
      separator +
      playlist.encode() +
      separator +
      @utf8.decode_lossy(rows.contents())
    }
    MasterPlaylist(master) => {
      let summary = "master|variants=" +
        master.variants.length().to_string() +
        "|iframes=" +
        master.i_frame_streams.length().to_string()
      let rows = @buffer.Buffer()
      for i, variant in master.variants {
        let bandwidth = match variant.bandwidth {
          Some(value) => value.to_string()
          None => ""
        }
        let resolution = match variant.resolution {
          Some(value) =>
            value.width.to_string() + "x" + value.height.to_string()
          None => ""
        }
        let row = (i + 1).to_string() +
          "\t" +
          bandwidth +
          "\t" +
          resolution +
          "\t" +
          variant.uri +
          "\n"
        rows.write_string_utf8(row)
      }
      summary +
      separator +
      playlist.encode() +
      separator +
      @utf8.decode_lossy(rows.contents())
    }
  }
}

///|
fn main {
  publish(report)
}
