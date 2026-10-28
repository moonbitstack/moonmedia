// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A byte range inside a resource (RFC 8216 §4.3.2.2).
///
/// `offset` absent means "immediately after the previous range", which is what
/// the tag itself means when the `@` clause is left out. Keeping the two apart
/// matters: a reader that filled in zero would fetch the wrong bytes.
pub(all) struct ByteRange {
  mut length : Int64
  mut offset : Int64?
} derive(Eq, Debug)

///|
pub extend ByteRange with Eq::{equal, not_equal}

///|
pub extend ByteRange with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// One range, `length@offset`.
pub fn ByteRange::new(length : Int64, offset? : Int64) -> ByteRange {
  { length, offset, }
}

///|
/// The encryption method `EXT-X-KEY` names (RFC 8216 §4.3.2.4).
///
/// `Other` carries a method this release does not implement, so a playlist that
/// uses one is read and written back unchanged rather than refused.
pub(all) enum Cipher {
  None
  Aes128
  SampleAes
  Other(String)
} derive(Eq, Debug)

///|
pub extend Cipher with Eq::{equal, not_equal}

///|
pub extend Cipher with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The method as it appears on the wire.
pub fn Cipher::code(self : Cipher) -> String {
  match self {
    None => "NONE"
    Aes128 => "AES-128"
    SampleAes => "SAMPLE-AES"
    Other(name) => name
  }
}

///|
/// The method a wire value names; `Other` for one this release does not know.
pub fn Cipher::of(code : StringView) -> Cipher {
  if code == "NONE" {
    None
  } else if code == "AES-128" {
    Aes128
  } else if code == "SAMPLE-AES" {
    SampleAes
  } else {
    Other(code.to_owned())
  }
}

///|
/// A key a segment is encrypted with (RFC 8216 §4.3.2.4).
///
/// Segments carry the key that was in force when they were written, not the
/// tag that introduced it: a tag applies to every following segment until it
/// is replaced, and a caller hunting for "what encrypts this segment" should
/// not have to replay the file to find out.
pub(all) struct Key {
  mut cipher : Cipher
  mut uri : String?
  mut iv : String?
  mut key_format : String?
  mut key_format_versions : String?
  mut extra : Array[String]
} derive(Eq, Debug)

///|
pub extend Key with Eq::{equal, not_equal}

///|
pub extend Key with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A key, with the URI that serves it.
pub fn Key::new(
  uri : String,
  cipher? : Cipher,
  iv? : String,
  key_format? : String,
  key_format_versions? : String,
) -> Key {
  {
    cipher: cipher.unwrap_or(Aes128),
    uri: Some(uri),
    iv,
    key_format,
    key_format_versions,
    extra: [],
  }
}

///|
/// Whether the key leaves the stream in the clear.
pub fn Key::is_plain(self : Key) -> Bool {
  self.cipher == Cipher::None
}

///|
/// The initialisation section a segment needs before it can be decoded, the
/// `EXT-X-MAP` tag (RFC 8216 §4.3.2.5).
pub(all) struct InitSection {
  mut uri : String
  mut byte_range : ByteRange?
} derive(Eq, Debug)

///|
pub extend InitSection with Eq::{equal, not_equal}

///|
pub extend InitSection with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// An initialisation section served from `uri`.
pub fn InitSection::new(uri : String, byte_range? : ByteRange) -> InitSection {
  { uri, byte_range, }
}

///|
/// A partial segment, the unit low-latency HLS publishes before a segment is
/// complete (RFC 8216bis §4.4.4.9).
pub(all) struct Part {
  mut uri : String
  mut duration : Double
  mut independent : Bool
  mut byte_range : ByteRange?
  mut gap : Bool
} derive(Eq, Debug)

///|
pub extend Part with Eq::{equal, not_equal}

///|
pub extend Part with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A part of the segment at `uri` lasting `duration` seconds.
pub fn Part::new(
  uri : String,
  duration : Double,
  independent? : Bool,
  byte_range? : ByteRange,
  gap? : Bool,
) -> Part {
  {
    uri,
    duration,
    independent: independent.unwrap_or(false),
    byte_range,
    gap: gap.unwrap_or(false),
  }
}

///|
/// One media segment: the URI a player fetches and everything the playlist says
/// about it.
pub(all) struct Segment {
  mut uri : String
  mut duration : Double
  mut title : String?
  mut byte_range : ByteRange?
  mut discontinuity : Bool
  mut program_date_time : String?
  mut gap : Bool
  mut key : Key?
  mut map : InitSection?
  mut parts : Array[Part]
} derive(Eq, Debug)

///|
pub extend Segment with Eq::{equal, not_equal}

///|
pub extend Segment with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A segment at `uri` lasting `duration` seconds.
pub fn Segment::new(
  uri : String,
  duration : Double,
  title? : String,
) -> Segment {
  {
    uri,
    duration,
    title,
    byte_range: None,
    discontinuity: false,
    program_date_time: None,
    gap: false,
    key: None,
    map: None,
    parts: [],
  }
}

///|
/// A frame size, `1920x1080`.
pub(all) struct Resolution {
  mut width : Int32
  mut height : Int32
} derive(Eq, Debug)

///|
pub extend Resolution with Eq::{equal, not_equal}

///|
pub extend Resolution with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A video size in pixels.
pub fn Resolution::new(width : Int32, height : Int32) -> Resolution {
  { width, height, }
}

///|
/// One rendition of a master playlist, the body of `EXT-X-STREAM-INF`
/// (RFC 8216 §4.3.4.2).
pub(all) struct Variant {
  mut uri : String
  mut bandwidth : Int32?
  mut average_bandwidth : Int32?
  mut codecs : String?
  mut resolution : Resolution?
  mut frame_rate : Double?
  mut hdcp_level : String?
  mut audio : String?
  mut video : String?
  mut subtitles : String?
  mut closed_captions : String?
  mut video_range : String?
  mut pathway_id : String?
  mut stable_variant_id : String?
  mut extra : Array[String]
} derive(Eq, Debug)

///|
pub extend Variant with Eq::{equal, not_equal}

///|
pub extend Variant with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A variant streaming `uri`, using `bandwidth` bits per second.
pub fn Variant::new(
  uri : String,
  bandwidth? : Int32,
  codecs? : String,
) -> Variant {
  {
    uri,
    bandwidth,
    average_bandwidth: None,
    codecs,
    resolution: None,
    frame_rate: None,
    hdcp_level: None,
    audio: None,
    video: None,
    subtitles: None,
    closed_captions: None,
    video_range: None,
    pathway_id: None,
    stable_variant_id: None,
    extra: [],
  }
}

///|
/// What an `EXT-X-MEDIA` rendition carries (RFC 8216 §4.3.4.1).
pub(all) enum MediaKind {
  Audio
  Video
  Subtitles
  ClosedCaptions
  Other(String)
} derive(Eq, Debug)

///|
pub extend MediaKind with Eq::{equal, not_equal}

///|
pub extend MediaKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The kind as it appears on the wire.
pub fn MediaKind::code(self : MediaKind) -> String {
  match self {
    Audio => "AUDIO"
    Video => "VIDEO"
    Subtitles => "SUBTITLES"
    ClosedCaptions => "CLOSED-CAPTIONS"
    Other(name) => name
  }
}

///|
/// The kind a wire value names.
pub fn MediaKind::of(code : StringView) -> MediaKind {
  if code == "AUDIO" {
    Audio
  } else if code == "VIDEO" {
    Video
  } else if code == "SUBTITLES" {
    Subtitles
  } else if code == "CLOSED-CAPTIONS" {
    ClosedCaptions
  } else {
    Other(code.to_owned())
  }
}

///|
/// An alternative rendition a variant can switch to (RFC 8216 §4.3.4.1).
pub(all) struct Rendition {
  mut kind : MediaKind
  mut group_id : String
  mut name : String
  mut uri : String?
  mut language : String?
  mut assoc_language : String?
  mut characteristics : String?
  mut channels : String?
  mut instream_id : String?
  mut stable_rendition_id : String?
  mut pathway_id : String?
  mut default : Bool
  mut autoselect : Bool
  mut forced : Bool
  mut extra : Array[String]
} derive(Eq, Debug)

///|
pub extend Rendition with Eq::{equal, not_equal}

///|
pub extend Rendition with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A rendition called `name` in the group `group_id`.
pub fn Rendition::new(
  kind : MediaKind,
  group_id : String,
  name : String,
  uri? : String,
) -> Rendition {
  {
    kind,
    group_id,
    name,
    uri,
    language: None,
    assoc_language: None,
    characteristics: None,
    channels: None,
    instream_id: None,
    stable_rendition_id: None,
    pathway_id: None,
    default: false,
    autoselect: false,
    forced: false,
    extra: [],
  }
}

///|
/// An I-frame only rendition, `EXT-X-I-FRAME-STREAM-INF` (RFC 8216 §4.3.4.3).
pub(all) struct IFrameStream {
  mut uri : String
  mut bandwidth : Int32?
  mut average_bandwidth : Int32?
  mut codecs : String?
  mut resolution : Resolution?
  mut hdcp_level : String?
  mut video_range : String?
  mut pathway_id : String?
  mut stable_variant_id : String?
  mut extra : Array[String]
} derive(Eq, Debug)

///|
pub extend IFrameStream with Eq::{equal, not_equal}

///|
pub extend IFrameStream with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// I-frame streams served from `uri`.
pub fn IFrameStream::new(uri : String, bandwidth? : Int32) -> IFrameStream {
  {
    uri,
    bandwidth,
    average_bandwidth: None,
    codecs: None,
    resolution: None,
    hdcp_level: None,
    video_range: None,
    pathway_id: None,
    stable_variant_id: None,
    extra: [],
  }
}

///|
/// A piece of session metadata, `EXT-X-SESSION-DATA` (RFC 8216 §4.3.4.4).
pub(all) struct SessionData {
  mut data_id : String
  mut value : String?
  mut uri : String?
  mut language : String?
  mut extra : Array[String]
} derive(Eq, Debug)

///|
pub extend SessionData with Eq::{equal, not_equal}

///|
pub extend SessionData with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The metadata named `data_id`, carried inline as `value` or by `uri`.
pub fn SessionData::new(
  data_id : String,
  value? : String,
  uri? : String,
  language? : String,
) -> SessionData {
  { data_id, value, uri, language, extra: [], }
}

///|
/// Where playback should start, `EXT-X-START` (RFC 8216 §4.3.5.2).
pub(all) struct Start {
  mut time_offset : Double
  mut precise : Bool
} derive(Eq, Debug)

///|
pub extend Start with Eq::{equal, not_equal}

///|
pub extend Start with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Start `time_offset` seconds from the beginning.
pub fn Start::new(time_offset : Double, precise? : Bool) -> Start {
  { time_offset, precise: precise.unwrap_or(false), }
}

///|
/// The reload advice a low-latency server gives, `EXT-X-SERVER-CONTROL`
/// (RFC 8216bis §4.4.3.8).
pub(all) struct ServerControl {
  mut can_skip_until : Double?
  mut can_skip_date_ranges : Bool
  mut hold_back : Double?
  mut part_hold_back : Double?
  mut can_block_reload : Bool
  mut extra : Array[String]
} derive(Eq, Debug)

///|
pub extend ServerControl with Eq::{equal, not_equal}

///|
pub extend ServerControl with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The reload advice with nothing set.
pub fn ServerControl::new() -> ServerControl {
  {
    can_skip_until: None,
    can_skip_date_ranges: false,
    hold_back: None,
    part_hold_back: None,
    can_block_reload: false,
    extra: [],
  }
}

///|
/// What to fetch next before it is listed, `EXT-X-PRELOAD-HINT`
/// (RFC 8216bis §4.4.4.10).
pub(all) struct PreloadHint {
  mut kind : String
  mut uri : String
  mut byte_range : ByteRange?
  mut start : Int64?
  mut extra : Array[String]
} derive(Eq, Debug)

///|
pub extend PreloadHint with Eq::{equal, not_equal}

///|
pub extend PreloadHint with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A hint that `uri` will hold the next `kind` (`PART` or `MAP`).
pub fn PreloadHint::new(
  kind : String,
  uri : String,
  byte_range? : ByteRange,
  start? : Int64,
) -> PreloadHint {
  { kind, uri, byte_range, start, extra: [], }
}

///|
/// How far along a sibling rendition is, `EXT-X-RENDITION-REPORT`
/// (RFC 8216bis §4.4.4.11).
pub(all) struct RenditionReport {
  mut uri : String
  mut last_msn : Int64?
  mut last_part : Int32?
  mut extra : Array[String]
} derive(Eq, Debug)

///|
pub extend RenditionReport with Eq::{equal, not_equal}

///|
pub extend RenditionReport with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A report on the rendition at `uri`.
pub fn RenditionReport::new(
  uri : String,
  last_msn? : Int64,
  last_part? : Int32,
) -> RenditionReport {
  { uri, last_msn, last_part, extra: [], }
}

///|
/// A wall-clock interval the stream marks, `EXT-X-DATERANGE`
/// (RFC 8216 §4.3.2.7).
pub(all) struct DateRange {
  mut id : String
  mut class_ : String?
  mut start_date : String?
  mut end_date : String?
  mut duration : Double?
  mut planned_duration : Double?
  mut scte35_cmd : String?
  mut scte35_out : String?
  mut scte35_in : String?
  mut end_on_next : Bool
  mut extra : Array[String]
} derive(Eq, Debug)

///|
pub extend DateRange with Eq::{equal, not_equal}

///|
pub extend DateRange with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The interval named `id`.
pub fn DateRange::new(id : String, start_date? : String) -> DateRange {
  {
    id,
    class_: None,
    start_date,
    end_date: None,
    duration: None,
    planned_duration: None,
    scte35_cmd: None,
    scte35_out: None,
    scte35_in: None,
    end_on_next: false,
    extra: [],
  }
}

///|
/// What kind of playlist a media playlist is (RFC 8216 §4.3.3.5).
pub(all) enum PlaylistType {
  Event
  Vod
  Other(String)
} derive(Eq, Debug)

///|
pub extend PlaylistType with Eq::{equal, not_equal}

///|
pub extend PlaylistType with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A variable the playlist defines, `EXT-X-DEFINE` (RFC 8216bis §4.4.2.3).
pub(all) struct Define {
  mut name : String?
  mut value : String?
  mut import_ : String?
  mut queryparam : String?
} derive(Eq, Debug)

///|
pub extend Define with Eq::{equal, not_equal}

///|
pub extend Define with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A variable set to `value`.
pub fn Define::new(name : String, value : String) -> Define {
  { name: Some(name), value: Some(value), import_: None, queryparam: None, }
}

///|
/// A master playlist: which renditions exist and how to reach them
/// (RFC 8216 §4.3.4).
pub(all) struct Master {
  mut version : Int32?
  mut independent_segments : Bool
  mut start : Start?
  mut defines : Array[Define]
  mut session_data : Array[SessionData]
  mut session_keys : Array[Key]
  mut renditions : Array[Rendition]
  mut variants : Array[Variant]
  mut i_frame_streams : Array[IFrameStream]
  mut unknown : Array[String]
} derive(Eq, Debug)

///|
pub extend Master with Eq::{equal, not_equal}

///|
pub extend Master with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// An empty master playlist.
pub fn Master::new() -> Master {
  {
    version: None,
    independent_segments: false,
    start: None,
    defines: [],
    session_data: [],
    session_keys: [],
    renditions: [],
    variants: [],
    i_frame_streams: [],
    unknown: [],
  }
}

///|
/// A media playlist: the segments of one rendition (RFC 8216 §4.3.3).
pub(all) struct MediaPlaylist {
  mut version : Int32?
  mut target_duration : Int32
  mut media_sequence : Int64
  mut discontinuity_sequence : Int64
  mut playlist_type : PlaylistType?
  mut i_frames_only : Bool
  mut independent_segments : Bool
  mut allow_cache : Bool?
  mut end_list : Bool
  mut start : Start?
  mut server_control : ServerControl?
  mut part_inf : Double?
  mut skip : Int32?
  mut defines : Array[Define]
  mut date_ranges : Array[DateRange]
  mut segments : Array[Segment]
  mut next_parts : Array[Part]
  mut preload_hint : PreloadHint?
  mut rendition_reports : Array[RenditionReport]
  mut unknown : Array[String]
} derive(Eq, Debug)

///|
pub extend MediaPlaylist with Eq::{equal, not_equal}

///|
pub extend MediaPlaylist with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// An empty media playlist whose segments are at most `target_duration`
/// seconds long, which the specification requires to be present.
pub fn MediaPlaylist::new(target_duration : Int32) -> MediaPlaylist {
  {
    version: None,
    target_duration,
    media_sequence: 0L,
    discontinuity_sequence: 0L,
    playlist_type: None,
    i_frames_only: false,
    independent_segments: false,
    allow_cache: None,
    end_list: false,
    start: None,
    server_control: None,
    part_inf: None,
    skip: None,
    defines: [],
    date_ranges: [],
    segments: [],
    next_parts: [],
    preload_hint: None,
    rendition_reports: [],
    unknown: [],
  }
}

///|
/// A playlist, of one kind or the other.
pub(all) enum Playlist {
  MasterPlaylist(Master)
  MediaPlaylist(MediaPlaylist)
} derive(Eq, Debug)

///|
pub extend Playlist with Eq::{equal, not_equal}

///|
pub extend Playlist with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Whether this is a master playlist.
pub fn Playlist::is_master(self : Playlist) -> Bool {
  match self {
    MasterPlaylist(_) => true
    MediaPlaylist(_) => false
  }
}

///|
/// The master playlist, when this is one.
pub fn Playlist::master(self : Playlist) -> Master? {
  match self {
    MasterPlaylist(master) => Some(master)
    MediaPlaylist(_) => None
  }
}

///|
/// The media playlist, when this is one.
pub fn Playlist::media(self : Playlist) -> MediaPlaylist? {
  match self {
    MasterPlaylist(_) => None
    MediaPlaylist(media) => Some(media)
  }
}

///|
/// Why a playlist could not be read.
///
/// `at` is the line the parser stopped on, counting from one; `got` is what was
/// there and `want` what the grammar allows.
pub(all) suberror PlaylistError {
  Malformed(at~ : Int32, want~ : String, got~ : String)
}

///|
/// The one-line account of a failure.
pub extend PlaylistError with Show::{to_string, output}

///|
pub impl Show for PlaylistError with fn output(self, logger) {
  let Malformed(at~, want~, got~) = self
  logger.write_string(
    "line " + at.to_string() + ": want " + want + ", got " + got,
  )
}
