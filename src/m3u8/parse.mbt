// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Read a playlist.
///
/// A master playlist and a media playlist are told apart by what the file
/// contains, not by a declaration: the presence of a variant stream or a
/// rendition makes it a master. Anything the release does not model is kept in
/// `unknown` and written back, so a playlist using a tag from a later revision
/// survives a round trip.
pub fn Playlist::parse(text : StringView) -> Playlist raise PlaylistError {
  Playlist::parse_lines(split_lines(text))
}

///|
/// Split on LF, CRLF or a lone CR, and drop the byte order mark a text editor
/// may have put in front.
fn split_lines(text : StringView) -> Array[StringView] {
  let mut body = text
  if body.length() > 0 && body[0] == '\u{FEFF}' {
    body = body[1:]
  }
  let out : Array[StringView] = []
  let n = body.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    let c = body[i]
    if c == '\n' || c == '\r' {
      out.push(body[start:i])
      if c == '\r' && i + 1 < n && body[i + 1] == '\n' {
        i = i + 1
      }
      start = i + 1
    }
    i = i + 1
  }
  if start < n {
    out.push(body[start:])
  }
  out
}

///|
/// One attribute: its name, its value without quotes, and the text it was read
/// from. The third is what an attribute this release does not model is written
/// back as, so that a document with an extension attribute survives a rewrite
/// without this package having to guess how that attribute is quoted.
priv struct Attr {
  name : String
  value : String
  text : String
}

///|
/// The attribute list of a tag, `NAME=value,NAME="value"`.
fn parse_attrs(text : StringView) -> Array[Attr] {
  let out : Array[Attr] = []
  let n = text.length()
  let mut i = 0
  while i < n {
    while i < n && (text[i] == ',' || text[i] == ' ' || text[i] == '\t') {
      i = i + 1
    }
    if i >= n {
      break
    }
    let name_start = i
    while i < n && text[i] != '=' && text[i] != ',' {
      i = i + 1
    }
    let name = text[name_start:i].trim().to_owned()
    if i >= n || text[i] != '=' {
      if name.length() > 0 {
        out.push({ name, value: "", text: name, })
      }
      continue
    }
    i = i + 1
    let value : String = if i < n && text[i] == '"' {
      i = i + 1
      let value_start = i
      while i < n && text[i] != '"' {
        i = i + 1
      }
      let value = text[value_start:i].to_owned()
      if i < n {
        i = i + 1
      }
      value
    } else {
      let value_start = i
      while i < n && text[i] != ',' {
        i = i + 1
      }
      text[value_start:i].trim().to_owned()
    }
    out.push({ name, value, text: text[name_start:i].trim().to_owned(), })
  }
  out
}

///|
/// An attribute list, with the line number to blame when one of them is wrong.
priv struct Attrs {
  pairs : Array[Attr]
  line : Int32
  raw : String
}

///|
fn Attrs::of(text : StringView, line : Int32) -> Attrs {
  { pairs: parse_attrs(text), line, raw: text.trim().to_owned(), }
}

///|
fn Attrs::find(self : Attrs, name : StringView) -> String? {
  for pair in self.pairs {
    if pair.name[:] == name {
      return Some(pair.value)
    }
  }
  None
}

///|
fn Attrs::has(self : Attrs, name : StringView) -> Bool {
  self.find(name) != None
}

///|
fn Attrs::yes(self : Attrs, name : StringView) -> Bool {
  match self.find(name) {
    Some(value) => value == "YES"
    None => false
  }
}

///|
fn Attrs::int(self : Attrs, name : StringView) -> Int32? raise PlaylistError {
  match self.find(name) {
    None => None
    Some(value) =>
      Some(@string.parse_int(value)) catch {
        _ =>
          raise Malformed(
            at=self.line,
            want="a decimal integer in " + name.to_owned(),
            got=value,
          )
      }
  }
}

///|
fn Attrs::int64(self : Attrs, name : StringView) -> Int64? raise PlaylistError {
  match self.find(name) {
    None => None
    Some(value) =>
      Some(@string.parse_int64(value)) catch {
        _ =>
          raise Malformed(
            at=self.line,
            want="a decimal integer in " + name.to_owned(),
            got=value,
          )
      }
  }
}

///|
fn Attrs::double(
  self : Attrs,
  name : StringView,
) -> Double? raise PlaylistError {
  match self.find(name) {
    None => None
    Some(value) =>
      Some(@string.parse_double(value)) catch {
        _ =>
          raise Malformed(
            at=self.line,
            want="a decimal number in " + name.to_owned(),
            got=value,
          )
      }
  }
}

///|
fn Attrs::resolution(
  self : Attrs,
  name : StringView,
) -> Resolution? raise PlaylistError {
  match self.find(name) {
    None => None
    Some(value) =>
      match split_once(value[:], 'x') {
        None =>
          raise Malformed(
            at=self.line,
            want="WIDTHxHEIGHT in " + name.to_owned(),
            got=value,
          )
        Some((width, height)) =>
          Some(
            Resolution::new(@string.parse_int(width), @string.parse_int(height)),
          ) catch {
            _ =>
              raise Malformed(
                at=self.line,
                want="WIDTHxHEIGHT in " + name.to_owned(),
                got=value,
              )
          }
      }
  }
}

///|
/// The part of `text` before the first `sep`, and the part after it.
fn split_once(text : StringView, sep : Int32) -> (StringView, StringView)? {
  for i = 0; i < text.length(); i = i + 1 {
    if text[i].to_int() == sep {
      return Some((text[:i], text[i + 1:]))
    }
  }
  None
}

///|
/// What follows a tag name, for the tags whose body is not an attribute list.
fn tag_body(line : StringView, tag : StringView) -> StringView {
  line[tag.length():]
}

///|
/// The value of a tag that carries one bare value, `#EXT-X-VERSION:3`.
fn tag_value(line : StringView, tag : StringView) -> StringView? {
  if line.length() > tag.length() && line.has_prefix(tag) {
    Some(line[tag.length():].trim())
  } else {
    None
  }
}

///|
/// A number in a tag that carries one bare value.
fn bare_int(
  line : StringView,
  tag : StringView,
  at : Int32,
) -> Int32 raise PlaylistError {
  match tag_value(line, tag) {
    None => raise Malformed(at~, want=tag.to_owned(), got=line.to_owned())
    Some(value) =>
      @string.parse_int(value) catch {
        _ =>
          raise Malformed(
            at~,
            want="a decimal integer after " + tag.to_owned(),
            got=value.to_owned(),
          )
      }
  }
}

///|
/// The bytes a `ByteRange` was written from, `n@o`.
fn parse_byte_range(
  text : StringView,
  line : Int32,
) -> ByteRange raise PlaylistError {
  match split_once(text.trim(), 0x40) {
    None =>
      ByteRange::new(@string.parse_int64(text.trim())) catch {
        _ =>
          raise Malformed(at=line, want="LENGTH[@OFFSET]", got=text.to_owned())
      }
    Some((length, offset)) =>
      ByteRange::new(
        @string.parse_int64(length),
        offset=@string.parse_int64(offset),
      ) catch {
        _ =>
          raise Malformed(at=line, want="LENGTH[@OFFSET]", got=text.to_owned())
      }
  }
}

///|
/// What the parser has read so far. Both kinds are gathered as the file is
/// read; which one it was is decided once there is nothing left to read.
priv struct Builder {
  mut version : Int32?
  mut independent_segments : Bool
  mut start : Start?
  defines : Array[Define]
  session_data : Array[SessionData]
  session_keys : Array[Key]
  renditions : Array[Rendition]
  variants : Array[Variant]
  i_frame_streams : Array[IFrameStream]
  mut target_duration : Int32?
  mut media_sequence : Int64
  mut discontinuity_sequence : Int64
  mut playlist_type : PlaylistType?
  mut i_frames_only : Bool
  mut allow_cache : Bool?
  mut end_list : Bool
  mut server_control : ServerControl?
  mut part_inf : Double?
  mut skip : Int32?
  date_ranges : Array[DateRange]
  segments : Array[Segment]
  mut preload_hint : PreloadHint?
  rendition_reports : Array[RenditionReport]
  unknown : Array[String]
  // State that a tag sets and the next segment consumes.
  mut key : Key?
  mut map : InitSection?
  mut discontinuity : Bool
  mut program_date_time : String?
  mut gap : Bool
  mut byte_range : ByteRange?
  mut parts : Array[Part]
  mut duration : Double?
  mut title : String?
  mut pending_variant : Variant?
}

///|
fn Builder::new() -> Builder {
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
    target_duration: None,
    media_sequence: 0L,
    discontinuity_sequence: 0L,
    playlist_type: None,
    i_frames_only: false,
    allow_cache: None,
    end_list: false,
    server_control: None,
    part_inf: None,
    skip: None,
    date_ranges: [],
    segments: [],
    preload_hint: None,
    rendition_reports: [],
    unknown: [],
    key: None,
    map: None,
    discontinuity: false,
    program_date_time: None,
    gap: false,
    byte_range: None,
    parts: [],
    duration: None,
    title: None,
    pending_variant: None,
  }
}

///|
/// Whether the file has said anything only a master playlist may say.
fn Builder::looks_master(self : Builder) -> Bool {
  self.variants.length() > 0 ||
  self.i_frame_streams.length() > 0 ||
  self.renditions.length() > 0 ||
  self.session_data.length() > 0 ||
  self.session_keys.length() > 0
}

///|
fn Playlist::parse_lines(
  lines : Array[StringView],
) -> Playlist raise PlaylistError {
  if lines.length() == 0 || lines[0].trim() != "#EXTM3U" {
    let got = if lines.length() == 0 { "" } else { lines[0].trim().to_owned() }
    raise Malformed(at=1, want="#EXTM3U", got~)
  }
  let b = Builder::new()
  for i in 1..<lines.length() {
    let line = lines[i].trim()
    let at = i + 1
    if line.length() == 0 {
      continue
    } else if line[0] != '#' {
      b.take_uri(line, at)
    } else if line == "#EXT-X-INDEPENDENT-SEGMENTS" {
      b.independent_segments = true
    } else if line == "#EXT-X-ENDLIST" {
      b.end_list = true
    } else if line == "#EXT-X-I-FRAMES-ONLY" {
      b.i_frames_only = true
    } else if line == "#EXT-X-DISCONTINUITY" {
      b.discontinuity = true
    } else if line == "#EXT-X-GAP" {
      b.gap = true
    } else if line.has_prefix("#EXTINF:") {
      b.take_extinf(line, at)
    } else if line.has_prefix("#EXT-X-") || line.has_prefix("#EXTM3U") {
      b.take_ext_tag(line, at)
    }
    // Any other `#` line is a comment, which the specification leaves the
    // parser free to ignore.
  }
  b.finish()
}

///|
fn Builder::take_uri(
  self : Builder,
  line : StringView,
  at : Int32,
) -> Unit raise PlaylistError {
  let uri = line.to_owned()
  match self.pending_variant {
    Some(variant) => {
      self.variants.push({ ..variant, uri, })
      self.pending_variant = None
    }
    None =>
      match self.duration {
        None =>
          raise Malformed(at~, want="#EXTINF before a segment URI", got=uri)
        Some(duration) => {
          self.segments.push({
            uri,
            duration,
            title: self.title,
            byte_range: self.byte_range,
            discontinuity: self.discontinuity,
            program_date_time: self.program_date_time,
            gap: self.gap,
            key: self.key,
            map: self.map,
            parts: self.parts,
          })
          self.duration = None
          self.title = None
          self.byte_range = None
          self.discontinuity = false
          self.program_date_time = None
          self.gap = false
          self.parts = []
        }
      }
  }
}

///|
fn Builder::take_extinf(
  self : Builder,
  line : StringView,
  at : Int32,
) -> Unit raise PlaylistError {
  let body = tag_body(line, "#EXTINF:").trim()
  let parsed : (StringView, String?) = match split_once(body, 0x2C) {
    None => (body, None)
    // An empty title is the same as none: the comma after the duration is
    // required either way.
    Some((duration, title)) =>
      (
        duration,
        if title.trim().length() == 0 {
          None
        } else {
          Some(title.to_owned())
        },
      )
  }
  let (duration_text, title) = parsed
  let duration = @string.parse_double(duration_text.trim()) catch {
    _ =>
      raise Malformed(
        at~,
        want="a duration in #EXTINF",
        got=duration_text.to_owned(),
      )
  }
  self.duration = Some(duration)
  self.title = title
}

///|
fn Builder::take_ext_tag(
  self : Builder,
  line : StringView,
  at : Int32,
) -> Unit raise PlaylistError {
  if line.has_prefix("#EXT-X-VERSION:") {
    self.version = Some(bare_int(line, "#EXT-X-VERSION:", at))
  } else if line.has_prefix("#EXT-X-TARGETDURATION:") {
    self.target_duration = Some(bare_int(line, "#EXT-X-TARGETDURATION:", at))
  } else if line.has_prefix("#EXT-X-MEDIA-SEQUENCE:") {
    self.media_sequence = bare_int(line, "#EXT-X-MEDIA-SEQUENCE:", at).to_int64()
  } else if line.has_prefix("#EXT-X-DISCONTINUITY-SEQUENCE:") {
    self.discontinuity_sequence = bare_int(
      line, "#EXT-X-DISCONTINUITY-SEQUENCE:", at,
    ).to_int64()
  } else if line.has_prefix("#EXT-X-PLAYLIST-TYPE:") {
    let value = tag_value(line, "#EXT-X-PLAYLIST-TYPE:").unwrap()
    self.playlist_type = Some(
      if value == "EVENT" {
        PlaylistType::Event
      } else if value == "VOD" {
        PlaylistType::Vod
      } else {
        PlaylistType::Other(value.to_owned())
      },
    )
  } else if line.has_prefix("#EXT-X-ALLOW-CACHE:") {
    let value = tag_value(line, "#EXT-X-ALLOW-CACHE:").unwrap()
    self.allow_cache = Some(value == "YES")
  } else if line.has_prefix("#EXT-X-PROGRAM-DATE-TIME:") {
    self.program_date_time = Some(
      tag_body(line, "#EXT-X-PROGRAM-DATE-TIME:").to_owned(),
    )
  } else if line.has_prefix("#EXT-X-BYTERANGE:") {
    self.byte_range = Some(
      parse_byte_range(tag_body(line, "#EXT-X-BYTERANGE:"), at),
    )
  } else if line.has_prefix("#EXT-X-START:") {
    self.start = Some(
      take_start(Attrs::of(tag_body(line, "#EXT-X-START:"), at)),
    )
  } else if line.has_prefix("#EXT-X-KEY:") {
    self.key = Some(take_key(Attrs::of(tag_body(line, "#EXT-X-KEY:"), at)))
  } else if line.has_prefix("#EXT-X-MAP:") {
    self.map = Some(take_map(Attrs::of(tag_body(line, "#EXT-X-MAP:"), at)))
  } else if line.has_prefix("#EXT-X-PART:") {
    self.parts.push(take_part(Attrs::of(tag_body(line, "#EXT-X-PART:"), at)))
  } else if line.has_prefix("#EXT-X-PART-INF:") {
    let attrs = Attrs::of(tag_body(line, "#EXT-X-PART-INF:"), at)
    self.part_inf = attrs.double("PART-TARGET")
  } else if line.has_prefix("#EXT-X-SERVER-CONTROL:") {
    self.server_control = Some(
      take_server_control(
        Attrs::of(tag_body(line, "#EXT-X-SERVER-CONTROL:"), at),
      ),
    )
  } else if line.has_prefix("#EXT-X-SKIP:") {
    self.skip = Attrs::of(tag_body(line, "#EXT-X-SKIP:"), at).int(
      "SKIPPED-SEGMENTS",
    )
  } else if line.has_prefix("#EXT-X-PRELOAD-HINT:") {
    self.preload_hint = Some(
      take_preload_hint(Attrs::of(tag_body(line, "#EXT-X-PRELOAD-HINT:"), at)),
    )
  } else if line.has_prefix("#EXT-X-RENDITION-REPORT:") {
    self.rendition_reports.push(
      take_rendition_report(
        Attrs::of(tag_body(line, "#EXT-X-RENDITION-REPORT:"), at),
      ),
    )
  } else if line.has_prefix("#EXT-X-DATERANGE:") {
    self.date_ranges.push(
      take_date_range(Attrs::of(tag_body(line, "#EXT-X-DATERANGE:"), at)),
    )
  } else if line.has_prefix("#EXT-X-DEFINE:") {
    self.defines.push(
      take_define(Attrs::of(tag_body(line, "#EXT-X-DEFINE:"), at)),
    )
  } else if line.has_prefix("#EXT-X-SESSION-DATA:") {
    self.session_data.push(
      take_session_data(Attrs::of(tag_body(line, "#EXT-X-SESSION-DATA:"), at)),
    )
  } else if line.has_prefix("#EXT-X-SESSION-KEY:") {
    self.session_keys.push(
      take_key(Attrs::of(tag_body(line, "#EXT-X-SESSION-KEY:"), at)),
    )
  } else if line.has_prefix("#EXT-X-MEDIA:") {
    self.renditions.push(
      take_rendition(Attrs::of(tag_body(line, "#EXT-X-MEDIA:"), at)),
    )
  } else if line.has_prefix("#EXT-X-STREAM-INF:") {
    self.pending_variant = Some(
      take_variant(Attrs::of(tag_body(line, "#EXT-X-STREAM-INF:"), at)),
    )
  } else if line.has_prefix("#EXT-X-I-FRAME-STREAM-INF:") {
    self.i_frame_streams.push(
      take_i_frame_stream(
        Attrs::of(tag_body(line, "#EXT-X-I-FRAME-STREAM-INF:"), at),
      ),
    )
  } else {
    self.unknown.push(line.to_owned())
  }
}

///|
fn Builder::finish(self : Builder) -> Playlist raise PlaylistError {
  if self.pending_variant != None {
    raise Malformed(
      at=self.unknown.length(),
      want="a URI after #EXT-X-STREAM-INF",
      got="end of playlist",
    )
  }
  if self.looks_master() {
    return MasterPlaylist({
      version: self.version,
      independent_segments: self.independent_segments,
      start: self.start,
      defines: self.defines,
      session_data: self.session_data,
      session_keys: self.session_keys,
      renditions: self.renditions,
      variants: self.variants,
      i_frame_streams: self.i_frame_streams,
      unknown: self.unknown,
    })
  }
  let target_duration = match self.target_duration {
    Some(value) => value
    None =>
      raise Malformed(at=1, want="#EXT-X-TARGETDURATION", got="end of playlist")
  }
  MediaPlaylist({
    version: self.version,
    target_duration,
    media_sequence: self.media_sequence,
    discontinuity_sequence: self.discontinuity_sequence,
    playlist_type: self.playlist_type,
    i_frames_only: self.i_frames_only,
    independent_segments: self.independent_segments,
    allow_cache: self.allow_cache,
    end_list: self.end_list,
    start: self.start,
    server_control: self.server_control,
    part_inf: self.part_inf,
    skip: self.skip,
    defines: self.defines,
    date_ranges: self.date_ranges,
    segments: self.segments,
    next_parts: self.parts,
    preload_hint: self.preload_hint,
    rendition_reports: self.rendition_reports,
    unknown: self.unknown,
  })
}

///|
/// The attributes no field of the model reads, kept in the order and the form
/// they came in.
fn leftovers(attrs : Attrs, known : Array[StringView]) -> Array[String] {
  let out : Array[String] = []
  for pair in attrs.pairs {
    let mut seen = false
    for name in known {
      if pair.name[:] == name {
        seen = true
      }
    }
    if !seen {
      out.push(pair.text)
    }
  }
  out
}

///|
fn take_start(attrs : Attrs) -> Start raise PlaylistError {
  let time_offset = match attrs.double("TIME-OFFSET") {
    Some(value) => value
    None =>
      raise Malformed(
        at=attrs.line,
        want="TIME-OFFSET in #EXT-X-START",
        got=attrs.raw,
      )
  }
  { time_offset, precise: attrs.yes("PRECISE"), }
}

///|
fn take_key(attrs : Attrs) -> Key raise PlaylistError {
  let cipher = match attrs.find("METHOD") {
    Some(value) => Cipher::of(value[:])
    None =>
      raise Malformed(at=attrs.line, want="METHOD in #EXT-X-KEY", got=attrs.raw)
  }
  {
    cipher,
    uri: attrs.find("URI"),
    iv: attrs.find("IV"),
    key_format: attrs.find("KEYFORMAT"),
    key_format_versions: attrs.find("KEYFORMATVERSIONS"),
    extra: leftovers(attrs, [
      "METHOD", "URI", "IV", "KEYFORMAT", "KEYFORMATVERSIONS",
    ]),
  }
}

///|
fn take_map(attrs : Attrs) -> InitSection raise PlaylistError {
  let uri = match attrs.find("URI") {
    Some(value) => value
    None =>
      raise Malformed(at=attrs.line, want="URI in #EXT-X-MAP", got=attrs.raw)
  }
  let byte_range = match attrs.find("BYTERANGE") {
    Some(value) => Some(parse_byte_range(value[:], attrs.line))
    None => None
  }
  { uri, byte_range, }
}

///|
fn take_part(attrs : Attrs) -> Part raise PlaylistError {
  let uri = match attrs.find("URI") {
    Some(value) => value
    None =>
      raise Malformed(at=attrs.line, want="URI in #EXT-X-PART", got=attrs.raw)
  }
  let duration = match attrs.double("DURATION") {
    Some(value) => value
    None =>
      raise Malformed(
        at=attrs.line,
        want="DURATION in #EXT-X-PART",
        got=attrs.raw,
      )
  }
  let byte_range = match attrs.find("BYTERANGE") {
    Some(value) => Some(parse_byte_range(value[:], attrs.line))
    None => None
  }
  {
    uri,
    duration,
    independent: attrs.yes("INDEPENDENT"),
    byte_range,
    gap: attrs.yes("GAP"),
  }
}

///|
fn take_server_control(attrs : Attrs) -> ServerControl raise PlaylistError {
  {
    can_skip_until: attrs.double("CAN-SKIP-UNTIL"),
    can_skip_date_ranges: attrs.yes("CAN-SKIP-DATERANGES"),
    hold_back: attrs.double("HOLD-BACK"),
    part_hold_back: attrs.double("PART-HOLD-BACK"),
    can_block_reload: attrs.yes("CAN-BLOCK-RELOAD"),
    extra: leftovers(attrs, [
      "CAN-SKIP-UNTIL", "CAN-SKIP-DATERANGES", "HOLD-BACK", "PART-HOLD-BACK", "CAN-BLOCK-RELOAD",
    ]),
  }
}

///|
fn take_preload_hint(attrs : Attrs) -> PreloadHint raise PlaylistError {
  let kind = match attrs.find("TYPE") {
    Some(value) => value
    None =>
      raise Malformed(
        at=attrs.line,
        want="TYPE in #EXT-X-PRELOAD-HINT",
        got=attrs.raw,
      )
  }
  let uri = match attrs.find("URI") {
    Some(value) => value
    None =>
      raise Malformed(
        at=attrs.line,
        want="URI in #EXT-X-PRELOAD-HINT",
        got=attrs.raw,
      )
  }
  let byte_range = match attrs.find("BYTERANGE") {
    Some(value) => Some(parse_byte_range(value[:], attrs.line))
    None => None
  }
  {
    kind,
    uri,
    byte_range,
    start: attrs.int64("BYTERANGE-START"),
    extra: leftovers(attrs, ["TYPE", "URI", "BYTERANGE", "BYTERANGE-START"]),
  }
}

///|
fn take_rendition_report(attrs : Attrs) -> RenditionReport raise PlaylistError {
  let uri = match attrs.find("URI") {
    Some(value) => value
    None =>
      raise Malformed(
        at=attrs.line,
        want="URI in #EXT-X-RENDITION-REPORT",
        got=attrs.raw,
      )
  }
  {
    uri,
    last_msn: attrs.int64("LAST-MSN"),
    last_part: attrs.int("LAST-PART"),
    extra: leftovers(attrs, ["URI", "LAST-MSN", "LAST-PART"]),
  }
}

///|
fn take_date_range(attrs : Attrs) -> DateRange raise PlaylistError {
  let id = match attrs.find("ID") {
    Some(value) => value
    None =>
      raise Malformed(
        at=attrs.line,
        want="ID in #EXT-X-DATERANGE",
        got=attrs.raw,
      )
  }
  {
    id,
    class_: attrs.find("CLASS"),
    start_date: attrs.find("START-DATE"),
    end_date: attrs.find("END-DATE"),
    duration: attrs.double("DURATION"),
    planned_duration: attrs.double("PLANNED-DURATION"),
    scte35_cmd: attrs.find("SCTE35-CMD"),
    scte35_out: attrs.find("SCTE35-OUT"),
    scte35_in: attrs.find("SCTE35-IN"),
    end_on_next: attrs.yes("END-ON-NEXT"),
    extra: leftovers(attrs, [
      "ID", "CLASS", "START-DATE", "END-DATE", "DURATION", "PLANNED-DURATION", "SCTE35-CMD",
      "SCTE35-OUT", "SCTE35-IN", "END-ON-NEXT",
    ]),
  }
}

///|
fn take_define(attrs : Attrs) -> Define raise PlaylistError {
  if !attrs.has("NAME") && !attrs.has("IMPORT") && !attrs.has("QUERYPARAM") {
    raise Malformed(
      at=attrs.line,
      want="NAME, IMPORT or QUERYPARAM in #EXT-X-DEFINE",
      got=attrs.raw,
    )
  }
  {
    name: attrs.find("NAME"),
    value: attrs.find("VALUE"),
    import_: attrs.find("IMPORT"),
    queryparam: attrs.find("QUERYPARAM"),
  }
}

///|
fn take_session_data(attrs : Attrs) -> SessionData raise PlaylistError {
  let data_id = match attrs.find("DATA-ID") {
    Some(value) => value
    None =>
      raise Malformed(
        at=attrs.line,
        want="DATA-ID in #EXT-X-SESSION-DATA",
        got=attrs.raw,
      )
  }
  if !attrs.has("VALUE") && !attrs.has("URI") {
    raise Malformed(
      at=attrs.line,
      want="VALUE or URI in #EXT-X-SESSION-DATA",
      got=attrs.raw,
    )
  }
  {
    data_id,
    value: attrs.find("VALUE"),
    uri: attrs.find("URI"),
    language: attrs.find("LANGUAGE"),
    extra: leftovers(attrs, ["DATA-ID", "VALUE", "URI", "LANGUAGE"]),
  }
}

///|
fn take_rendition(attrs : Attrs) -> Rendition raise PlaylistError {
  let kind = match attrs.find("TYPE") {
    Some(value) => MediaKind::of(value[:])
    None =>
      raise Malformed(at=attrs.line, want="TYPE in #EXT-X-MEDIA", got=attrs.raw)
  }
  let group_id = match attrs.find("GROUP-ID") {
    Some(value) => value
    None =>
      raise Malformed(
        at=attrs.line,
        want="GROUP-ID in #EXT-X-MEDIA",
        got=attrs.raw,
      )
  }
  let name = match attrs.find("NAME") {
    Some(value) => value
    None =>
      raise Malformed(at=attrs.line, want="NAME in #EXT-X-MEDIA", got=attrs.raw)
  }
  {
    kind,
    group_id,
    name,
    uri: attrs.find("URI"),
    language: attrs.find("LANGUAGE"),
    assoc_language: attrs.find("ASSOC-LANGUAGE"),
    characteristics: attrs.find("CHARACTERISTICS"),
    channels: attrs.find("CHANNELS"),
    instream_id: attrs.find("INSTREAM-ID"),
    stable_rendition_id: attrs.find("STABLE-RENDITION-ID"),
    pathway_id: attrs.find("PATHWAY-ID"),
    default: attrs.yes("DEFAULT"),
    autoselect: attrs.yes("AUTOSELECT"),
    forced: attrs.yes("FORCED"),
    extra: leftovers(attrs, [
      "TYPE", "GROUP-ID", "NAME", "URI", "LANGUAGE", "ASSOC-LANGUAGE", "CHARACTERISTICS",
      "CHANNELS", "INSTREAM-ID", "STABLE-RENDITION-ID", "PATHWAY-ID", "DEFAULT",
      "AUTOSELECT", "FORCED",
    ]),
  }
}

///|
fn take_variant(attrs : Attrs) -> Variant raise PlaylistError {
  {
    uri: "",
    bandwidth: attrs.int("BANDWIDTH"),
    average_bandwidth: attrs.int("AVERAGE-BANDWIDTH"),
    codecs: attrs.find("CODECS"),
    resolution: attrs.resolution("RESOLUTION"),
    frame_rate: attrs.double("FRAME-RATE"),
    hdcp_level: attrs.find("HDCP-LEVEL"),
    audio: attrs.find("AUDIO"),
    video: attrs.find("VIDEO"),
    subtitles: attrs.find("SUBTITLES"),
    closed_captions: attrs.find("CLOSED-CAPTIONS"),
    video_range: attrs.find("VIDEO-RANGE"),
    pathway_id: attrs.find("PATHWAY-ID"),
    stable_variant_id: attrs.find("STABLE-VARIANT-ID"),
    extra: leftovers(attrs, [
      "BANDWIDTH", "AVERAGE-BANDWIDTH", "CODECS", "RESOLUTION", "FRAME-RATE", "HDCP-LEVEL",
      "AUDIO", "VIDEO", "SUBTITLES", "CLOSED-CAPTIONS", "VIDEO-RANGE", "PATHWAY-ID",
      "STABLE-VARIANT-ID",
    ]),
  }
}

///|
fn take_i_frame_stream(attrs : Attrs) -> IFrameStream raise PlaylistError {
  let uri = match attrs.find("URI") {
    Some(value) => value
    None =>
      raise Malformed(
        at=attrs.line,
        want="URI in #EXT-X-I-FRAME-STREAM-INF",
        got=attrs.raw,
      )
  }
  {
    uri,
    bandwidth: attrs.int("BANDWIDTH"),
    average_bandwidth: attrs.int("AVERAGE-BANDWIDTH"),
    codecs: attrs.find("CODECS"),
    resolution: attrs.resolution("RESOLUTION"),
    hdcp_level: attrs.find("HDCP-LEVEL"),
    video_range: attrs.find("VIDEO-RANGE"),
    pathway_id: attrs.find("PATHWAY-ID"),
    stable_variant_id: attrs.find("STABLE-VARIANT-ID"),
    extra: leftovers(attrs, [
      "URI", "BANDWIDTH", "AVERAGE-BANDWIDTH", "CODECS", "RESOLUTION", "HDCP-LEVEL",
      "VIDEO-RANGE", "PATHWAY-ID", "STABLE-VARIANT-ID",
    ]),
  }
}
