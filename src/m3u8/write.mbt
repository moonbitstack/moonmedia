// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Write a playlist back out.
///
/// Tags are written in the order the specification lists them rather than the
/// order they were read, except inside a segment, where the order the file had
/// is the order players expect to see: the key and the map apply to the segment
/// that follows, so they come first, and `#EXTINF` immediately precedes its URI.
pub fn Playlist::encode(self : Playlist) -> String {
  match self {
    MasterPlaylist(master) => master.encode()
    MediaPlaylist(media) => media.encode()
  }
}

///|
fn line(buf : @buffer.Buffer, text : StringView) -> Unit {
  buf.write_string_utf8(text)
  buf.write_byte(b'\n')
}

///|
/// The bytes written so far, as text. `Buffer::to_string` is the display form of
/// the buffer rather than its contents, so the contents are decoded instead;
/// they are UTF-8 by construction, every write having come from a `StringView`.
fn text_of(buf : @buffer.Buffer) -> String {
  @utf8.decode_lossy(buf.contents())
}

///|
/// `NAME=value`.
fn attr(name : StringView, value : StringView) -> String {
  name.to_owned() + "=" + value.to_owned()
}

///|
/// `NAME="value"`.
fn quoted(name : StringView, value : StringView) -> String {
  name.to_owned() + "=\"" + value.to_owned() + "\""
}

///|
/// An attribute list as one comma-separated string.
fn join_attrs(attrs : Array[String]) -> String {
  let buf = @buffer.Buffer()
  for i = 0; i < attrs.length(); i = i + 1 {
    if i > 0 {
      buf.write_byte(b',')
    }
    buf.write_string_utf8(attrs[i])
  }
  text_of(buf)
}

///|
/// Write a tag line, `#EXT-X-VERSION:6` or `#EXT-X-ENDLIST`.
fn tag(buf : @buffer.Buffer, name : StringView, attrs : Array[String]) -> Unit {
  if attrs.length() == 0 {
    line(buf, name)
  } else {
    line(buf, name + ":" + join_attrs(attrs))
  }
}

///|
/// Whether a value of this attribute is written in quotes. The specification
/// fixes the form per attribute name, so a reader that kept the quotes would
/// not be able to tell a quoted enumerated string from a bare one.
fn needs_quotes(name : StringView) -> Bool {
  let names = [
    "URI", "LANGUAGE", "ASSOC-LANGUAGE", "NAME", "GROUP-ID", "STABLE-VARIANT-ID",
    "STABLE-RENDITION-ID", "AUDIO", "VIDEO", "SUBTITLES", "CLOSED-CAPTIONS", "CODECS",
    "PATHWAY-ID", "VALUE", "QUERYPARAM", "CLASS", "ID", "START-DATE", "END-DATE",
    "CHARACTERISTICS", "CHANNELS", "KEYFORMAT", "KEYFORMATVERSIONS",
  ]
  for candidate in names {
    if name == candidate {
      return true
    }
  }
  // A client attribute is defined by whoever invented it, and every one in the
  // wild is quoted.
  name.has_prefix("X-")
}

///|
/// `NAME=value`, quoted when the attribute's grammar says so.
fn text_attr(name : StringView, value : StringView) -> String {
  if name == "CLOSED-CAPTIONS" && value == "NONE" {
    return attr(name, value)
  }
  if needs_quotes(name) {
    quoted(name, value)
  } else {
    attr(name, value)
  }
}

///|
/// `NAME=123`.
fn int_attr(name : StringView, value : Int32) -> String {
  attr(name, value.to_string())
}

///|
/// `NAME=123`.
fn int64_attr(name : StringView, value : Int64) -> String {
  attr(name, value.to_string())
}

///|
/// `NAME=1.5`.
fn double_attr(name : StringView, value : Double) -> String {
  attr(name, compact(value))
}

///|
/// A duration as the shortest text that reads back as the same number. `9.009`
/// stays `9.009`; a whole number loses the `.0` the specification never had.
fn compact(value : Double) -> String {
  if value == value.floor() && value.abs() < 1.0e15 {
    value.to_int64().to_string()
  } else {
    value.to_string()
  }
}

///|
/// `NAME=YES` or `NAME=NO`.
fn flag_attr(name : StringView, value : Bool) -> String {
  attr(name, if value { "YES" } else { "NO" })
}

///|
/// A byte range, `n@o`.
fn byte_range_text(range : ByteRange) -> String {
  match range.offset {
    Some(offset) => range.length.to_string() + "@" + offset.to_string()
    None => range.length.to_string()
  }
}

///|
/// The attributes of a key.
fn key_attrs(key : Key) -> Array[String] {
  let out : Array[String] = []
  out.push(attr("METHOD", key.cipher.code()))
  if key.cipher != Cipher::None {
    match key.uri {
      Some(uri) => out.push(quoted("URI", uri))
      None => ()
    }
    match key.iv {
      Some(iv) => out.push(attr("IV", iv))
      None => ()
    }
    match key.key_format {
      Some(format) => out.push(quoted("KEYFORMAT", format))
      None => ()
    }
    match key.key_format_versions {
      Some(versions) => out.push(quoted("KEYFORMATVERSIONS", versions))
      None => ()
    }
  }
  for fragment in key.extra {
    out.push(fragment)
  }
  out
}

///|
/// The attributes of an initialisation section.
fn map_attrs(map : InitSection) -> Array[String] {
  let out : Array[String] = [quoted("URI", map.uri)]
  match map.byte_range {
    Some(range) => out.push(quoted("BYTERANGE", byte_range_text(range)))
    None => ()
  }
  out
}

///|
/// The attributes of a partial segment.
fn part_attrs(part : Part) -> Array[String] {
  let out : Array[String] = [
    double_attr("DURATION", part.duration),
    quoted("URI", part.uri),
  ]
  if part.independent {
    out.push(attr("INDEPENDENT", "YES"))
  }
  match part.byte_range {
    Some(range) => out.push(quoted("BYTERANGE", byte_range_text(range)))
    None => ()
  }
  if part.gap {
    out.push(attr("GAP", "YES"))
  }
  out
}

///|
/// The attributes of a variant stream.
fn variant_attrs(variant : Variant) -> Array[String] {
  let out : Array[String] = []
  match variant.bandwidth {
    Some(value) => out.push(int_attr("BANDWIDTH", value))
    None => ()
  }
  match variant.average_bandwidth {
    Some(value) => out.push(int_attr("AVERAGE-BANDWIDTH", value))
    None => ()
  }
  match variant.codecs {
    Some(value) => out.push(quoted("CODECS", value))
    None => ()
  }
  match variant.resolution {
    Some(value) => out.push(attr("RESOLUTION", resolution_text(value)))
    None => ()
  }
  match variant.frame_rate {
    Some(value) => out.push(double_attr("FRAME-RATE", value))
    None => ()
  }
  match variant.video_range {
    Some(value) => out.push(attr("VIDEO-RANGE", value))
    None => ()
  }
  match variant.hdcp_level {
    Some(value) => out.push(attr("HDCP-LEVEL", value))
    None => ()
  }
  match variant.audio {
    Some(value) => out.push(quoted("AUDIO", value))
    None => ()
  }
  match variant.video {
    Some(value) => out.push(quoted("VIDEO", value))
    None => ()
  }
  match variant.subtitles {
    Some(value) => out.push(quoted("SUBTITLES", value))
    None => ()
  }
  match variant.closed_captions {
    Some(value) => out.push(text_attr("CLOSED-CAPTIONS", value))
    None => ()
  }
  match variant.pathway_id {
    Some(value) => out.push(quoted("PATHWAY-ID", value))
    None => ()
  }
  match variant.stable_variant_id {
    Some(value) => out.push(quoted("STABLE-VARIANT-ID", value))
    None => ()
  }
  for fragment in variant.extra {
    out.push(fragment)
  }
  out
}

///|
/// `1920x1080`.
fn resolution_text(resolution : Resolution) -> String {
  resolution.width.to_string() + "x" + resolution.height.to_string()
}

///|
/// The attributes of an alternative rendition.
fn rendition_attrs(rendition : Rendition) -> Array[String] {
  let out : Array[String] = [
    attr("TYPE", rendition.kind.code()),
    quoted("GROUP-ID", rendition.group_id),
    quoted("NAME", rendition.name),
  ]
  out.push(flag_attr("DEFAULT", rendition.default))
  out.push(flag_attr("AUTOSELECT", rendition.autoselect))
  match rendition.language {
    Some(value) => out.push(quoted("LANGUAGE", value))
    None => ()
  }
  match rendition.assoc_language {
    Some(value) => out.push(quoted("ASSOC-LANGUAGE", value))
    None => ()
  }
  if rendition.forced {
    out.push(attr("FORCED", "YES"))
  }
  match rendition.instream_id {
    Some(value) => out.push(quoted("INSTREAM-ID", value))
    None => ()
  }
  match rendition.characteristics {
    Some(value) => out.push(quoted("CHARACTERISTICS", value))
    None => ()
  }
  match rendition.channels {
    Some(value) => out.push(quoted("CHANNELS", value))
    None => ()
  }
  match rendition.stable_rendition_id {
    Some(value) => out.push(quoted("STABLE-RENDITION-ID", value))
    None => ()
  }
  match rendition.pathway_id {
    Some(value) => out.push(quoted("PATHWAY-ID", value))
    None => ()
  }
  match rendition.uri {
    Some(value) => out.push(quoted("URI", value))
    None => ()
  }
  for fragment in rendition.extra {
    out.push(fragment)
  }
  out
}

///|
/// The attributes of an I-frame stream.
fn i_frame_attrs(stream : IFrameStream) -> Array[String] {
  let out : Array[String] = []
  match stream.bandwidth {
    Some(value) => out.push(int_attr("BANDWIDTH", value))
    None => ()
  }
  match stream.average_bandwidth {
    Some(value) => out.push(int_attr("AVERAGE-BANDWIDTH", value))
    None => ()
  }
  match stream.codecs {
    Some(value) => out.push(quoted("CODECS", value))
    None => ()
  }
  match stream.resolution {
    Some(value) => out.push(attr("RESOLUTION", resolution_text(value)))
    None => ()
  }
  match stream.video_range {
    Some(value) => out.push(attr("VIDEO-RANGE", value))
    None => ()
  }
  match stream.hdcp_level {
    Some(value) => out.push(attr("HDCP-LEVEL", value))
    None => ()
  }
  match stream.pathway_id {
    Some(value) => out.push(quoted("PATHWAY-ID", value))
    None => ()
  }
  match stream.stable_variant_id {
    Some(value) => out.push(quoted("STABLE-VARIANT-ID", value))
    None => ()
  }
  out.push(quoted("URI", stream.uri))
  for fragment in stream.extra {
    out.push(fragment)
  }
  out
}

///|
/// The attributes of a session data tag.
fn session_data_attrs(data : SessionData) -> Array[String] {
  let out : Array[String] = [quoted("DATA-ID", data.data_id)]
  match data.value {
    Some(value) => out.push(quoted("VALUE", value))
    None => ()
  }
  match data.uri {
    Some(value) => out.push(quoted("URI", value))
    None => ()
  }
  match data.language {
    Some(value) => out.push(quoted("LANGUAGE", value))
    None => ()
  }
  for fragment in data.extra {
    out.push(fragment)
  }
  out
}

///|
/// The attributes of a start tag.
fn start_attrs(start : Start) -> Array[String] {
  let out : Array[String] = [double_attr("TIME-OFFSET", start.time_offset)]
  if start.precise {
    out.push(attr("PRECISE", "YES"))
  }
  out
}

///|
/// The attributes of a server control tag.
fn server_control_attrs(control : ServerControl) -> Array[String] {
  let out : Array[String] = []
  match control.can_skip_until {
    Some(value) => out.push(double_attr("CAN-SKIP-UNTIL", value))
    None => ()
  }
  if control.can_skip_date_ranges {
    out.push(attr("CAN-SKIP-DATERANGES", "YES"))
  }
  match control.hold_back {
    Some(value) => out.push(double_attr("HOLD-BACK", value))
    None => ()
  }
  match control.part_hold_back {
    Some(value) => out.push(double_attr("PART-HOLD-BACK", value))
    None => ()
  }
  if control.can_block_reload {
    out.push(attr("CAN-BLOCK-RELOAD", "YES"))
  }
  for fragment in control.extra {
    out.push(fragment)
  }
  out
}

///|
/// The attributes of a preload hint.
fn preload_hint_attrs(hint : PreloadHint) -> Array[String] {
  let out : Array[String] = [attr("TYPE", hint.kind), quoted("URI", hint.uri)]
  match hint.byte_range {
    Some(range) => out.push(quoted("BYTERANGE", byte_range_text(range)))
    None => ()
  }
  match hint.start {
    Some(value) => out.push(int64_attr("BYTERANGE-START", value))
    None => ()
  }
  for fragment in hint.extra {
    out.push(fragment)
  }
  out
}

///|
/// The attributes of a rendition report.
fn rendition_report_attrs(report : RenditionReport) -> Array[String] {
  let out : Array[String] = [quoted("URI", report.uri)]
  match report.last_msn {
    Some(value) => out.push(int64_attr("LAST-MSN", value))
    None => ()
  }
  match report.last_part {
    Some(value) => out.push(int_attr("LAST-PART", value))
    None => ()
  }
  for fragment in report.extra {
    out.push(fragment)
  }
  out
}

///|
/// The attributes of a date range.
fn date_range_attrs(range : DateRange) -> Array[String] {
  let out : Array[String] = [quoted("ID", range.id)]
  match range.class_ {
    Some(value) => out.push(quoted("CLASS", value))
    None => ()
  }
  match range.start_date {
    Some(value) => out.push(quoted("START-DATE", value))
    None => ()
  }
  match range.end_date {
    Some(value) => out.push(quoted("END-DATE", value))
    None => ()
  }
  match range.duration {
    Some(value) => out.push(double_attr("DURATION", value))
    None => ()
  }
  match range.planned_duration {
    Some(value) => out.push(double_attr("PLANNED-DURATION", value))
    None => ()
  }
  if range.end_on_next {
    out.push(attr("END-ON-NEXT", "YES"))
  }
  match range.scte35_cmd {
    Some(value) => out.push(text_attr("SCTE35-CMD", value))
    None => ()
  }
  match range.scte35_out {
    Some(value) => out.push(text_attr("SCTE35-OUT", value))
    None => ()
  }
  match range.scte35_in {
    Some(value) => out.push(text_attr("SCTE35-IN", value))
    None => ()
  }
  for fragment in range.extra {
    out.push(fragment)
  }
  out
}

///|
/// The attributes of a variable definition.
fn define_attrs(variable : Define) -> Array[String] {
  let out : Array[String] = []
  match variable.name {
    Some(value) => out.push(quoted("NAME", value))
    None => ()
  }
  match variable.value {
    Some(value) => out.push(quoted("VALUE", value))
    None => ()
  }
  match variable.import_ {
    Some(value) => out.push(quoted("IMPORT", value))
    None => ()
  }
  match variable.queryparam {
    Some(value) => out.push(quoted("QUERYPARAM", value))
    None => ()
  }
  out
}

///|
pub fn Master::encode(self : Master) -> String {
  let buf = @buffer.Buffer()
  line(buf, "#EXTM3U")
  match self.version {
    Some(value) => tag(buf, "#EXT-X-VERSION", [value.to_string()])
    None => ()
  }
  if self.independent_segments {
    line(buf, "#EXT-X-INDEPENDENT-SEGMENTS")
  }
  match self.start {
    Some(value) => tag(buf, "#EXT-X-START", start_attrs(value))
    None => ()
  }
  for variable in self.defines {
    tag(buf, "#EXT-X-DEFINE", define_attrs(variable))
  }
  for data in self.session_data {
    tag(buf, "#EXT-X-SESSION-DATA", session_data_attrs(data))
  }
  for key in self.session_keys {
    tag(buf, "#EXT-X-SESSION-KEY", key_attrs(key))
  }
  for rendition in self.renditions {
    tag(buf, "#EXT-X-MEDIA", rendition_attrs(rendition))
  }
  for variant in self.variants {
    tag(buf, "#EXT-X-STREAM-INF", variant_attrs(variant))
    line(buf, variant.uri)
  }
  for stream in self.i_frame_streams {
    tag(buf, "#EXT-X-I-FRAME-STREAM-INF", i_frame_attrs(stream))
  }
  for unknown in self.unknown {
    line(buf, unknown)
  }
  text_of(buf)
}

///|
pub fn MediaPlaylist::encode(self : MediaPlaylist) -> String {
  let buf = @buffer.Buffer()
  line(buf, "#EXTM3U")
  match self.version {
    Some(value) => tag(buf, "#EXT-X-VERSION", [value.to_string()])
    None => ()
  }
  tag(buf, "#EXT-X-TARGETDURATION", [self.target_duration.to_string()])
  if self.media_sequence != 0L {
    tag(buf, "#EXT-X-MEDIA-SEQUENCE", [self.media_sequence.to_string()])
  }
  if self.discontinuity_sequence != 0L {
    tag(buf, "#EXT-X-DISCONTINUITY-SEQUENCE", [
      self.discontinuity_sequence.to_string(),
    ])
  }
  match self.playlist_type {
    Some(value) =>
      tag(buf, "#EXT-X-PLAYLIST-TYPE", [
        match value {
          Event => "EVENT"
          Vod => "VOD"
          Other(name) => name
        },
      ])
    None => ()
  }
  if self.i_frames_only {
    line(buf, "#EXT-X-I-FRAMES-ONLY")
  }
  match self.allow_cache {
    Some(value) =>
      tag(buf, "#EXT-X-ALLOW-CACHE", [if value { "YES" } else { "NO" }])
    None => ()
  }
  if self.independent_segments {
    line(buf, "#EXT-X-INDEPENDENT-SEGMENTS")
  }
  match self.start {
    Some(value) => tag(buf, "#EXT-X-START", start_attrs(value))
    None => ()
  }
  match self.server_control {
    Some(value) =>
      tag(buf, "#EXT-X-SERVER-CONTROL", server_control_attrs(value))
    None => ()
  }
  match self.part_inf {
    Some(value) =>
      tag(buf, "#EXT-X-PART-INF", [double_attr("PART-TARGET", value)])
    None => ()
  }
  match self.skip {
    Some(value) =>
      tag(buf, "#EXT-X-SKIP", [int_attr("SKIPPED-SEGMENTS", value)])
    None => ()
  }
  for variable in self.defines {
    tag(buf, "#EXT-X-DEFINE", define_attrs(variable))
  }
  for interval in self.date_ranges {
    tag(buf, "#EXT-X-DATERANGE", date_range_attrs(interval))
  }
  let mut key : Key? = None
  let mut map : InitSection? = None
  for segment in self.segments {
    if segment.key != key {
      match segment.key {
        Some(value) => tag(buf, "#EXT-X-KEY", key_attrs(value))
        None => ()
      }
      key = segment.key
    }
    if segment.map != map {
      match segment.map {
        Some(value) => tag(buf, "#EXT-X-MAP", map_attrs(value))
        None => ()
      }
      map = segment.map
    }
    if segment.discontinuity {
      line(buf, "#EXT-X-DISCONTINUITY")
    }
    match segment.program_date_time {
      Some(value) => tag(buf, "#EXT-X-PROGRAM-DATE-TIME", [value])
      None => ()
    }
    if segment.gap {
      line(buf, "#EXT-X-GAP")
    }
    match segment.byte_range {
      Some(range) => tag(buf, "#EXT-X-BYTERANGE", [byte_range_text(range)])
      None => ()
    }
    for part in segment.parts {
      tag(buf, "#EXT-X-PART", part_attrs(part))
    }
    let title = match segment.title {
      Some(value) => value
      None => ""
    }
    tag(buf, "#EXTINF", [compact(segment.duration) + "," + title])
    line(buf, segment.uri)
  }
  for part in self.next_parts {
    tag(buf, "#EXT-X-PART", part_attrs(part))
  }
  match self.preload_hint {
    Some(value) => tag(buf, "#EXT-X-PRELOAD-HINT", preload_hint_attrs(value))
    None => ()
  }
  for report in self.rendition_reports {
    tag(buf, "#EXT-X-RENDITION-REPORT", rendition_report_attrs(report))
  }
  if self.end_list {
    line(buf, "#EXT-X-ENDLIST")
  }
  for unknown in self.unknown {
    line(buf, unknown)
  }
  text_of(buf)
}
