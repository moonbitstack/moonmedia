// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Whether a presentation is a file to play or a stream still being written.
pub(all) enum Kind {
  /// A presentation that is complete.
  Static
  /// A presentation that keeps growing, where the manifest is reloaded.
  Dynamic
  Other(String)
} derive(Eq, Debug)

///|
pub extend Kind with Eq::{equal, not_equal}

///|
pub extend Kind with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// The kind as it is written.
pub fn Kind::code(self : Kind) -> String {
  match self {
    Static => "static"
    Dynamic => "dynamic"
    Other(name) => name
  }
}

///|
/// The kind a written value names.
pub fn Kind::of(code : StringView) -> Kind {
  if code == "static" {
    Static
  } else if code == "dynamic" {
    Dynamic
  } else {
    Other(code.to_owned())
  }
}

///|
/// How the segments of a representation are addressed: a template with the
/// numbers filled in, which is what almost every manifest uses.
pub(all) struct Template {
  mut timescale : Int64?
  /// The length of a segment in timescale units, when they are all the same.
  mut duration : Int64?
  mut start_number : Int64?
  mut presentation_time_offset : Int64?
  /// Where the initialisation segment is, with `$RepresentationID$` in it.
  mut initialization : String?
  /// Where the segments are, with `$Number$` or `$Time$` in it.
  mut media : String?
  /// The segments' times and lengths, when they are not all the same.
  mut timeline : Array[Timeline]
} derive(Eq, Debug)

///|
pub extend Template with Eq::{equal, not_equal}

///|
pub extend Template with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A template with nothing set.
pub fn Template::new() -> Template {
  {
    timescale: None,
    duration: None,
    start_number: None,
    presentation_time_offset: None,
    initialization: None,
    media: None,
    timeline: [],
  }
}

///|
/// Where a segment starts and how long it runs, for a stream whose segments do
/// not have one length.
pub(all) struct Timeline {
  /// The start, in timescale units; absent means "where the last one ended".
  mut time : Int64?
  mut duration : Int64
  /// How many times the entry repeats, `-1` for "until the next entry".
  mut repeat : Int32
} derive(Eq, Debug)

///|
pub extend Timeline with Eq::{equal, not_equal}

///|
pub extend Timeline with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A run of segments of `duration` in timescale units.
pub fn Timeline::new(
  duration : Int64,
  repeat? : Int32,
  time? : Int64,
) -> Timeline {
  { time, duration, repeat: repeat.unwrap_or(0), }
}

///|
/// How long the entry lasts, in timescale units: a repeat of negative one means
/// the run lasts until the next entry, which only the next entry can say.
pub fn Timeline::span(self : Timeline) -> Int64 {
  if self.repeat < 0 {
    self.duration
  } else {
    self.duration * (self.repeat.to_int64() + 1L)
  }
}

///|
/// One encoding of the presentation: a single quality a player can choose.
pub(all) struct Representation {
  mut id : String
  mut bandwidth : Int32?
  mut codecs : String?
  mut mime_type : String?
  mut width : Int32?
  mut height : Int32?
  mut frame_rate : Double?
  mut audio_sampling_rate : Int32?
  mut base_url : String?
  mut template : Template?
} derive(Eq, Debug)

///|
pub extend Representation with Eq::{equal, not_equal}

///|
pub extend Representation with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A representation of `id` costing `bandwidth` bits per second.
pub fn Representation::new(id : String, bandwidth? : Int32) -> Representation {
  {
    id,
    bandwidth,
    codecs: None,
    mime_type: None,
    width: None,
    height: None,
    frame_rate: None,
    audio_sampling_rate: None,
    base_url: None,
    template: None,
  }
}

///|
/// A group of representations a player chooses between: the video renditions of
/// one period, or the audio ones.
pub(all) struct AdaptationSet {
  mut id : Int32?
  mut content_type : String?
  mut mime_type : String?
  mut lang : String?
  mut codecs : String?
  mut segment_alignment : Bool?
  mut start_with_sap : Int32?
  mut width : Int32?
  mut height : Int32?
  mut frame_rate : Double?
  mut audio_sampling_rate : Int32?
  mut base_url : String?
  mut template : Template?
  mut representations : Array[Representation]
} derive(Eq, Debug)

///|
pub extend AdaptationSet with Eq::{equal, not_equal}

///|
pub extend AdaptationSet with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A set carrying `content_type`, `mime_type` and a language.
pub fn AdaptationSet::new(
  content_type? : String,
  mime_type? : String,
  lang? : String,
) -> AdaptationSet {
  {
    id: None,
    content_type,
    mime_type,
    lang,
    codecs: None,
    segment_alignment: None,
    start_with_sap: None,
    width: None,
    height: None,
    frame_rate: None,
    audio_sampling_rate: None,
    base_url: None,
    template: None,
    representations: [],
  }
}

///|
/// A stretch of the presentation that is played on its own: a title, or the
/// part of a live stream between two ad breaks.
pub(all) struct Period {
  mut id : String?
  mut start : Double?
  mut duration : Double?
  mut base_url : String?
  mut template : Template?
  mut adaptations : Array[AdaptationSet]
} derive(Eq, Debug)

///|
pub extend Period with Eq::{equal, not_equal}

///|
pub extend Period with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A period that starts at `start` seconds.
pub fn Period::new(id? : String, start? : Double) -> Period {
  {
    id,
    start,
    duration: None,
    base_url: None,
    template: None,
    adaptations: [],
  }
}

///|
/// A media presentation description: what a DASH client reads before it fetches
/// anything.
pub(all) struct Manifest {
  mut kind : Kind
  mut profiles : String?
  mut min_buffer_time : Double?
  mut duration : Double?
  mut minimum_update_period : Double?
  mut availability_start : String?
  mut publish_time : String?
  mut time_shift_buffer_depth : Double?
  mut suggested_delay : Double?
  mut base_url : String?
  mut periods : Array[Period]
} derive(Eq, Debug)

///|
pub extend Manifest with Eq::{equal, not_equal}

///|
pub extend Manifest with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A manifest for a complete presentation, with nothing set but the kind.
pub fn Manifest::new(kind? : Kind) -> Manifest {
  {
    kind: kind.unwrap_or(Static),
    profiles: None,
    min_buffer_time: None,
    duration: None,
    minimum_update_period: None,
    availability_start: None,
    publish_time: None,
    time_shift_buffer_depth: None,
    suggested_delay: None,
    base_url: None,
    periods: [],
  }
}

///|
/// Read a manifest.
pub fn Manifest::parse(text : StringView) -> Manifest raise MpdError {
  let root = parse_document(text)
  if !root.is_named("MPD") {
    raise Malformed(at=0, want="an MPD element", got=root.name)
  }
  let manifest = Manifest::new(kind=Kind::of(root.text_of("type")[:]))
  manifest.profiles = optional(root, "profiles")
  manifest.min_buffer_time = seconds(root, "minBufferTime")
  manifest.duration = seconds(root, "mediaPresentationDuration")
  manifest.minimum_update_period = seconds(root, "minimumUpdatePeriod")
  manifest.time_shift_buffer_depth = seconds(root, "timeShiftBufferDepth")
  manifest.suggested_delay = seconds(root, "suggestedPresentationDelay")
  manifest.availability_start = optional(root, "availabilityStartTime")
  manifest.publish_time = optional(root, "publishTime")
  manifest.base_url = text_of_child(root, "BaseURL")
  for period in root.children_of("Period") {
    manifest.periods.push(read_period(period))
  }
  manifest
}

///|
/// An attribute, when it is there and not empty.
fn optional(element : Element, name : StringView) -> String? {
  match element.attribute(name) {
    Some(value) if value.length() > 0 => Some(value)
    _ => None
  }
}

///|
/// A duration attribute in seconds.
fn seconds(element : Element, name : StringView) -> Double? raise MpdError {
  match element.attribute(name) {
    None => None
    Some(value) =>
      match parse_duration(value[:]) {
        Some(seconds) => Some(seconds)
        None =>
          raise Malformed(
            at=0,
            want="a duration in " + name.to_owned(),
            got=value,
          )
      }
  }
}

///|
/// The text of the first child of that name.
fn text_of_child(element : Element, name : StringView) -> String? {
  match element.child(name) {
    Some(child) =>
      match child.content().trim() {
        "" => None
        text => Some(text.to_owned())
      }
    None => None
  }
}

///|
fn read_period(element : Element) -> Period raise MpdError {
  let period = Period::new()
  period.id = optional(element, "id")
  period.start = seconds(element, "start")
  period.duration = seconds(element, "duration")
  period.base_url = text_of_child(element, "BaseURL")
  period.template = read_template(element)
  for adaptation in element.children_of("AdaptationSet") {
    period.adaptations.push(read_adaptation(adaptation))
  }
  period
}

///|
fn read_adaptation(element : Element) -> AdaptationSet raise MpdError {
  let set = AdaptationSet::new()
  set.content_type = optional(element, "contentType")
  set.mime_type = optional(element, "mimeType")
  set.lang = optional(element, "lang")
  set.id = integer(element, "id")
  set.codecs = optional(element, "codecs")
  set.segment_alignment = match optional(element, "segmentAlignment") {
    Some(value) => Some(value == "true")
    None => None
  }
  set.start_with_sap = integer(element, "startWithSAP")
  set.width = integer(element, "width")
  set.height = integer(element, "height")
  set.frame_rate = rate(element, "frameRate")
  set.audio_sampling_rate = integer(element, "audioSamplingRate")
  set.base_url = text_of_child(element, "BaseURL")
  set.template = read_template(element)
  for representation in element.children_of("Representation") {
    set.representations.push(read_representation(representation))
  }
  set
}

///|
fn read_representation(element : Element) -> Representation raise MpdError {
  let representation = Representation::new(element.text_of("id"))
  representation.bandwidth = integer(element, "bandwidth")
  representation.codecs = optional(element, "codecs")
  representation.mime_type = optional(element, "mimeType")
  representation.width = integer(element, "width")
  representation.height = integer(element, "height")
  representation.frame_rate = rate(element, "frameRate")
  representation.audio_sampling_rate = integer(element, "audioSamplingRate")
  representation.base_url = text_of_child(element, "BaseURL")
  representation.template = read_template(element)
  representation
}

///|
/// An integer attribute.
fn integer(element : Element, name : StringView) -> Int32? raise MpdError {
  match element.attribute(name) {
    None => None
    Some(value) =>
      Some(@string.parse_int(value)) catch {
        _ =>
          raise Malformed(
            at=0,
            want="an integer in " + name.to_owned(),
            got=value,
          )
      }
  }
}

///|
/// A frame rate, which may be written as a fraction, `30000/1001`.
fn rate(element : Element, name : StringView) -> Double? {
  match element.attribute(name) {
    None => None
    Some(value) =>
      match value[:].find("/") {
        Some(at) =>
          try {
            let numerator = @string.parse_double(value[:at])
            let denominator = @string.parse_double(value[at + 1:])
            if denominator == 0.0 {
              None
            } else {
              Some(numerator / denominator)
            }
          } catch {
            _ => None
          }
        None => Some(@string.parse_double(value)) catch { _ => None }
      }
  }
}

///|
fn read_template(element : Element) -> Template? raise MpdError {
  let node = match element.child("SegmentTemplate") {
    Some(node) => node
    None => return None
  }
  let template = Template::new()
  template.timescale = integer(node, "timescale").map(fn(value) {
    value.to_int64()
  })
  template.duration = integer(node, "duration").map(fn(value) {
    value.to_int64()
  })
  template.start_number = integer(node, "startNumber").map(fn(value) {
    value.to_int64()
  })
  template.presentation_time_offset = integer(node, "presentationTimeOffset").map(fn(
      value,
    ) {
      value.to_int64()
    },
  )
  template.initialization = optional(node, "initialization")
  template.media = optional(node, "media")
  match node.child("SegmentTimeline") {
    Some(timeline) =>
      for entry in timeline.children_of("S") {
        template.timeline.push({
          time: integer(entry, "t").map(fn(value) { value.to_int64() }),
          duration: integer(entry, "d").unwrap_or(0).to_int64(),
          repeat: integer(entry, "r").unwrap_or(0),
        })
      }
    None => ()
  }
  Some(template)
}

///|
/// The profile to claim when none was given: fragmented MP4 segments addressed
/// by a template, which is what this package writes.
fn profiles_for(manifest : Manifest) -> String {
  let mut fragments = false
  for period in manifest.periods {
    if period.template != None {
      fragments = true
    }
    for set in period.adaptations {
      if set.template != None {
        fragments = true
      }
      for representation in set.representations {
        if representation.template != None {
          fragments = true
        }
      }
    }
  }
  if fragments {
    "urn:mpeg:dash:profile:isoff-live:2011"
  } else {
    "urn:mpeg:dash:profile:isoff-on-demand:2011"
  }
}

///|
/// Write the manifest.
pub fn Manifest::encode(self : Manifest) -> String {
  let root = element("MPD", [
    ("xmlns", "urn:mpeg:dash:schema:mpd:2011"),
    ("type", self.kind.code()),
    ("profiles", self.profiles.unwrap_or(profiles_for(self))),
    ("minBufferTime", format_duration(self.min_buffer_time.unwrap_or(2.0))),
  ])
  match self.duration {
    Some(value) =>
      root.attributes.push(
        ("mediaPresentationDuration", format_duration(value)),
      )
    None => ()
  }
  match self.minimum_update_period {
    Some(value) =>
      root.attributes.push(("minimumUpdatePeriod", format_duration(value)))
    None => ()
  }
  match self.availability_start {
    Some(value) => root.attributes.push(("availabilityStartTime", value))
    None => ()
  }
  match self.publish_time {
    Some(value) => root.attributes.push(("publishTime", value))
    None => ()
  }
  match self.time_shift_buffer_depth {
    Some(value) =>
      root.attributes.push(("timeShiftBufferDepth", format_duration(value)))
    None => ()
  }
  match self.suggested_delay {
    Some(value) =>
      root.attributes.push(
        ("suggestedPresentationDelay", format_duration(value)),
      )
    None => ()
  }
  match self.base_url {
    Some(value) => root.children.push(text_element("BaseURL", value))
    None => ()
  }
  for period in self.periods {
    root.children.push(period.encode())
  }
  render(root)
}

///|
fn Period::encode(self : Period) -> Element {
  let out = element("Period", [])
  match self.id {
    Some(value) => out.attributes.push(("id", value))
    None => ()
  }
  match self.start {
    Some(value) => out.attributes.push(("start", format_duration(value)))
    None => ()
  }
  match self.duration {
    Some(value) => out.attributes.push(("duration", format_duration(value)))
    None => ()
  }
  match self.base_url {
    Some(value) => out.children.push(text_element("BaseURL", value))
    None => ()
  }
  match self.template {
    Some(value) => out.children.push(template_element(value))
    None => ()
  }
  for adaptation in self.adaptations {
    out.children.push(adaptation.encode())
  }
  out
}

///|
fn AdaptationSet::encode(self : AdaptationSet) -> Element {
  let out = element("AdaptationSet", [])
  push_attribute(out, "id", self.id.map(fn(value) { value.to_string() }))
  push_attribute(out, "contentType", self.content_type)
  push_attribute(out, "mimeType", self.mime_type)
  push_attribute(out, "lang", self.lang)
  push_attribute(out, "codecs", self.codecs)
  push_attribute(
    out,
    "segmentAlignment",
    self.segment_alignment.map(fn(value) {
      if value {
        "true"
      } else {
        "false"
      }
    }),
  )
  push_attribute(
    out,
    "startWithSAP",
    self.start_with_sap.map(fn(value) { value.to_string() }),
  )
  push_attribute(out, "width", self.width.map(fn(value) { value.to_string() }))
  push_attribute(
    out,
    "height",
    self.height.map(fn(value) { value.to_string() }),
  )
  push_attribute(out, "frameRate", self.frame_rate.map(number_text))
  push_attribute(
    out,
    "audioSamplingRate",
    self.audio_sampling_rate.map(fn(value) { value.to_string() }),
  )
  match self.base_url {
    Some(value) => out.children.push(text_element("BaseURL", value))
    None => ()
  }
  match self.template {
    Some(value) => out.children.push(template_element(value))
    None => ()
  }
  for representation in self.representations {
    out.children.push(representation.encode())
  }
  out
}

///|
fn Representation::encode(self : Representation) -> Element {
  let out = element("Representation", [("id", self.id)])
  push_attribute(
    out,
    "bandwidth",
    self.bandwidth.map(fn(value) { value.to_string() }),
  )
  push_attribute(out, "mimeType", self.mime_type)
  push_attribute(out, "codecs", self.codecs)
  push_attribute(out, "width", self.width.map(fn(value) { value.to_string() }))
  push_attribute(
    out,
    "height",
    self.height.map(fn(value) { value.to_string() }),
  )
  push_attribute(out, "frameRate", self.frame_rate.map(number_text))
  push_attribute(
    out,
    "audioSamplingRate",
    self.audio_sampling_rate.map(fn(value) { value.to_string() }),
  )
  match self.base_url {
    Some(value) => out.children.push(text_element("BaseURL", value))
    None => ()
  }
  match self.template {
    Some(value) => out.children.push(template_element(value))
    None => ()
  }
  out
}

///|
/// A number written without a trailing zero, for an attribute that carries a
/// rate.
fn number_text(value : Double) -> String {
  shortest(value)
}

///|
fn push_attribute(
  element : Element,
  name : StringView,
  value : String?,
) -> Unit {
  match value {
    Some(text) => element.attributes.push((name.to_owned(), text))
    None => ()
  }
}

///|
fn template_element(template : Template) -> Element {
  let out = element("SegmentTemplate", [])
  push_attribute(
    out,
    "timescale",
    template.timescale.map(fn(v) { v.to_string() }),
  )
  push_attribute(
    out,
    "duration",
    template.duration.map(fn(v) { v.to_string() }),
  )
  push_attribute(
    out,
    "startNumber",
    template.start_number.map(fn(v) { v.to_string() }),
  )
  push_attribute(
    out,
    "presentationTimeOffset",
    template.presentation_time_offset.map(fn(v) { v.to_string() }),
  )
  push_attribute(out, "initialization", template.initialization)
  push_attribute(out, "media", template.media)
  if template.timeline.length() > 0 {
    let timeline = element("SegmentTimeline", [])
    for entry in template.timeline {
      let node = element("S", [])
      push_attribute(node, "t", entry.time.map(fn(v) { v.to_string() }))
      node.attributes.push(("d", entry.duration.to_string()))
      if entry.repeat != 0 {
        node.attributes.push(("r", entry.repeat.to_string()))
      }
      timeline.children.push(node)
    }
    out.children.push(timeline)
  }
  out
}
