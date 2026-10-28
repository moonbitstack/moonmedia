// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A segment of a packaged stream: the bytes a player fetches, and how long
/// they play.
pub(all) struct Segment {
  /// The fragment as bytes, a `moof` followed by its `mdat`.
  data : Bytes
  duration : Double
  /// Where the segment starts, in seconds from the beginning of the stream.
  start : Double
  /// Whether a player may start here. Every segment the packager cuts starts on
  /// a key frame, and is kept as a field because a caller assembling its own
  /// segments may want to know.
  keyframe : Bool
  /// How many samples each track contributes, in track order.
  samples : Array[Int32]
} derive(Eq, Debug)

///|
pub extend Segment with Eq::{equal, not_equal}

///|
pub extend Segment with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A stream cut into segments a player can fetch one at a time.
///
/// The packager is HLS packaging without the files: it turns a movie into an
/// initialisation section and a list of segments, and writes the playlists that
/// name them. Writing them out and answering HTTP requests is the caller's job,
/// and deliberately so — nothing here touches a socket.
pub(all) struct Packager {
  init : Bytes
  segments : Array[Segment]
  tracks : Array[Track]
  target_duration : Double
}

///|
/// A track as the packager needs it: what it is, its timescale, and where its
/// samples are.
pub(all) struct Track {
  id : Int32
  kind : TrackKind
  codec : String
  timescale : Int64
  width : Int32
  height : Int32
  samples : Array[Sample]
}

///|
/// What a track carries.
pub(all) enum TrackKind {
  Video
  Audio
  Subtitle
  Other(String)
} derive(Eq, Debug)

///|
pub extend TrackKind with Eq::{equal, not_equal}

///|
pub extend TrackKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// One sample, already cut out of the file it came from.
pub(all) struct Sample {
  data : Bytes
  dts : Int64
  duration : Int64
  composition_offset : Int64
  sync : Bool
} derive(Eq, Debug)

///|
pub extend Sample with Eq::{equal, not_equal}

///|
pub extend Sample with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Cut `file` into segments of about `target_duration` seconds, each starting on
/// a key frame.
///
/// A segment starts on a video key frame and takes the audio that plays over it,
/// so a player that switches rendition or seeks lands on something it can decode
/// without waiting for the next key frame. Cuts fall on the first key frame at or
/// after the target, which is what keeps segments independent: cutting at the
/// exact duration would leave a key frame in the middle of the previous segment.
pub fn Packager::new(
  file : @mp4.Mp4,
  target_duration? : Double,
) -> Packager raise @mp4.Mp4Error {
  let target = target_duration.unwrap_or(6.0)
  let source = file.tracks()
  let cuts = cut_points(source, target)
  let tracks : Array[Track] = []
  for track in source {
    let samples : Array[Sample] = []
    for sample in track.samples {
      samples.push({
        data: file.data[sample.offset:sample.offset + sample.size].to_owned(),
        dts: sample.dts,
        duration: sample.duration,
        composition_offset: sample.composition_offset,
        sync: sample.sync,
      })
    }
    tracks.push({
      id: track.id,
      kind: match track.kind {
        @mp4.TrackKind::Video => Video
        @mp4.TrackKind::Audio => Audio
        @mp4.TrackKind::Subtitle => Subtitle
        @mp4.TrackKind::Hint => Other("hint")
        @mp4.TrackKind::Other(name) => Other(name)
      },
      codec: track.codec,
      timescale: track.timescale,
      width: track.width,
      height: track.height,
      samples,
    })
  }
  let per_track : Array[Array[Array[Sample]]] = []
  for track in tracks {
    per_track.push(split(track, cuts))
  }
  let segments : Array[Segment] = []
  for i, cut in cuts {
    let runs : Array[@mp4.FragmentTrack] = []
    let counts : Array[Int32] = []
    for t = 0; t < tracks.length(); t = t + 1 {
      let track = tracks[t]
      if i >= per_track[t].length() {
        continue
      }
      let picked = per_track[t][i]
      if picked.length() == 0 {
        continue
      }
      let samples : Array[@mp4.SampleData] = []
      for sample in picked {
        samples.push({
          data: sample.data,
          duration: sample.duration,
          composition_offset: sample.composition_offset,
          sync: sample.sync,
        })
      }
      runs.push({
        track_id: track.id,
        base_decode_time: picked[0].dts,
        samples,
      })
      counts.push(samples.length())
    }
    if runs.length() == 0 {
      continue
    }
    let fragment = @mp4.MovieFragment::new(i + 1, runs)
    segments.push({
      data: fragment.encode(),
      duration: cut.duration(),
      start: cut.start.to_double() / 1.0e6,
      keyframe: true,
      samples: counts,
    })
  }
  { init: file.init_section(), segments, tracks, target_duration: target, }
}

///|
/// The bytes a player needs before it can decode any segment.
pub fn Packager::init_segment(self : Packager) -> Bytes {
  self.init
}

///|
/// The segments, in presentation order.
pub fn Packager::segments(self : Packager) -> Array[Segment] {
  self.segments
}

///|
/// How long the packaged stream plays, in seconds.
pub fn Packager::duration(self : Packager) -> Double {
  match self.segments.length() {
    0 => 0.0
    n => self.segments[n - 1].start + self.segments[n - 1].duration
  }
}

///|
/// The media playlist for these segments.
///
/// `prefix` is what a player puts in front of a segment name; leaving it out
/// serves the segments from the same directory as the playlist.
pub fn Packager::media_playlist(
  self : Packager,
  prefix? : StringView,
  init_name? : StringView,
) -> @m3u8.MediaPlaylist {
  let prefix = prefix.unwrap_or("")
  let playlist = @m3u8.MediaPlaylist::new(declared_target_duration(self))
  playlist.version = Some(7)
  playlist.playlist_type = Some(@m3u8.PlaylistType::Vod)
  playlist.end_list = true
  playlist.independent_segments = true
  let init = @m3u8.InitSection::new(
    prefix.to_owned() + init_name.unwrap_or("init.mp4").to_owned(),
  )
  for i, segment in self.segments {
    let entry = @m3u8.Segment::new(
      prefix.to_owned() + "segment" + i.to_string() + ".m4s",
      segment.duration,
    )
    entry.map = Some(init)
    playlist.segments.push(entry)
  }
  playlist
}

///|
/// A master playlist offering the packaged stream as one variant.
///
/// `bandwidth` is what the variant costs per second. When it is left out the
/// packager measures what it produced, which is close enough for a player
/// choosing between renditions and pointless as a description of the source.
///
/// There is no `EXT-X-I-FRAME-STREAM-INF`: a list of key frames only is a
/// different playlist, with different segments, and pointing this one at that
/// tag would describe it as something it is not.
pub fn Packager::master_playlist(
  self : Packager,
  uri? : StringView,
  bandwidth? : Int32,
) -> @m3u8.Master {
  let master = @m3u8.Master::new()
  master.version = Some(7)
  master.independent_segments = true
  let mut bytes = 0
  for segment in self.segments {
    bytes = bytes + segment.data.length()
  }
  let measured = if self.duration() > 0.0 {
    (bytes.to_double() * 8.0 / self.duration()).to_int()
  } else {
    0
  }
  let name = uri.unwrap_or("stream.m3u8").to_owned()
  let variant = @m3u8.Variant::new(
    name,
    bandwidth=bandwidth.unwrap_or(measured),
  )
  let video = self.video_track()
  let audio = self.audio_track()
  match video {
    Some(track) => {
      variant.codecs = Some(
        match audio {
          Some(audio) if track.codec.length() > 0 =>
            track.codec + "," + audio.codec
          Some(audio) => audio.codec
          None => track.codec
        },
      )
      if track.width > 0 && track.height > 0 {
        variant.resolution = Some(
          @m3u8.Resolution::new(track.width, track.height),
        )
      }
    }
    None =>
      match audio {
        Some(audio) => variant.codecs = Some(audio.codec)
        None => ()
      }
  }
  master.variants.push(variant)
  master
}

///|
/// The first video track, when there is one.
pub fn Packager::video_track(self : Packager) -> Track? {
  for track in self.tracks {
    if track.kind == Video {
      return Some(track)
    }
  }
  None
}

///|
/// The first audio track, when there is one.
pub fn Packager::audio_track(self : Packager) -> Track? {
  for track in self.tracks {
    if track.kind == Audio {
      return Some(track)
    }
  }
  None
}

///|
/// The duration a playlist must declare: the longest segment, rounded up,
/// because a player uses it as a reload period and a value below the truth
/// makes it reload too often.
fn declared_target_duration(packager : Packager) -> Int32 {
  let mut longest = 0.0
  for segment in packager.segments {
    if segment.duration > longest {
      longest = segment.duration
    }
  }
  if longest <= 0.0 {
    return 1
  }
  let rounded = longest.ceil()
  if rounded > 3600.0 {
    3600
  } else {
    rounded.to_int()
  }
}

///|
/// A place the stream is cut: from `start` to `end`, in microseconds so that
/// comparisons do not drift the way a float sum does.
priv struct Cut {
  start : Int64
  end : Int64
}

///|
/// How long this cut lasts, in seconds.
fn Cut::duration(self : Cut) -> Double {
  (self.end - self.start).to_double() / 1.0e6
}

///|
/// When a sample plays, in microseconds.
fn micros(dts : Int64, timescale : Int64) -> Int64 {
  if timescale <= 0L {
    0L
  } else {
    dts * 1_000_000L / timescale
  }
}

///|
/// Where to cut: on video key frames at least `target` seconds apart, or on
/// audio when there is no video to cut on.
fn cut_points(tracks : Array[@mp4.Track], target : Double) -> Array[Cut] {
  let mut primary : @mp4.Track? = None
  for track in tracks {
    if track.kind == @mp4.TrackKind::Video {
      primary = Some(track)
      break
    }
  }
  if primary == None {
    for track in tracks {
      if track.kind == @mp4.TrackKind::Audio {
        primary = Some(track)
        break
      }
    }
  }
  let track = match primary {
    Some(track) => track
    None => return []
  }
  let cuts : Array[Cut] = []
  if track.samples.length() == 0 {
    return cuts
  }
  let target_micros = (target * 1.0e6).to_int64()
  let mut start = micros(track.samples[0].dts, track.timescale)
  let mut last = start
  for sample in track.samples {
    let at = micros(sample.dts, track.timescale)
    // Only a key frame may begin a segment; audio samples are all key frames,
    // so an audio-only stream cuts on the moment it passes the target.
    if sample.sync && at > start && at - start >= target_micros {
      cuts.push({ start, end: at, })
      start = at
    }
    let duration = micros(sample.duration, track.timescale)
    last = at + duration
  }
  cuts.push({ start, end: last, })
  cuts
}

///|
/// The samples of `track` that belong to each cut.
fn split(track : Track, cuts : Array[Cut]) -> Array[Array[Sample]] {
  let out : Array[Array[Sample]] = []
  let mut cursor = 0
  for cut in cuts {
    let picked : Array[Sample] = []
    while cursor < track.samples.length() {
      let sample = track.samples[cursor]
      let at = micros(sample.dts, track.timescale)
      if at >= cut.end {
        break
      }
      if at >= cut.start {
        picked.push(sample)
      }
      cursor = cursor + 1
    }
    out.push(picked)
  }
  out
}
