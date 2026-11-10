// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// A range of bytes in a file, as a manifest writes it: `1389-15304`, both ends
/// counted.
///
/// The end may be left out, which means "to the end of the file".
#derive(Eq, Debug)
pub(all) struct Range {
  mut start : Int64
  mut end : Int64?
}

///|
pub extend Range with Eq::{equal, not_equal}

///|
pub extend Range with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A range starting at `start`, ending at `end` when there is one.
pub fn Range::new(start : Int64, end? : Int64) -> Range {
  { start, end, }
}

///|
/// How many bytes the range covers, when its end is known.
pub fn Range::length(self : Range) -> Int64? {
  match self.end {
    Some(end) => Some(end - self.start + 1L)
    None => None
  }
}

///|
/// The range a written value names, `start-end` or `start-`.
pub fn Range::of(text : StringView) -> Range? {
  let body = text.trim()
  match body.find("-") {
    None => None
    Some(at) => {
      let start = parse_int64(body[0:at].trim())
      let rest = body[at + 1:].trim()
      if start == None {
        return None
      }
      if rest.length() == 0 {
        return Some({ start: start.unwrap(), end: None, })
      }
      match parse_int64(rest) {
        Some(end) => Some({ start: start.unwrap(), end: Some(end), })
        None => None
      }
    }
  }
}

///|
/// The text a range is written as.
pub fn Range::text(self : Range) -> String {
  match self.end {
    Some(end) => self.start.to_string() + "-" + end.to_string()
    None => self.start.to_string() + "-"
  }
}

///|
fn parse_int64(text : StringView) -> Int64? {
  if text.length() == 0 {
    return None
  }
  let mut value = 0L
  for i = 0; i < text.length(); i = i + 1 {
    let digit = text.code_unit_at(i).to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    value = value * 10L + digit.to_int64()
  }
  Some(value)
}

///|
/// Where the initialisation segment is: a URL, a range inside one, or both.
#derive(Eq, Debug)
pub(all) struct Initialization {
  mut source_url : String?
  mut range : Range?
}

///|
pub extend Initialization with Eq::{equal, not_equal}

///|
pub extend Initialization with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// An initialisation section at `source_url`, with nothing else set.
pub fn Initialization::new(source_url? : String) -> Initialization {
  { source_url, range: None, }
}

///|
/// One segment of a list: the whole file, or a range inside the file the
/// representation's base URL names.
#derive(Eq, Debug)
pub(all) struct SegmentUrl {
  mut media : String?
  mut media_range : Range?
  mut index_range : Range?
}

///|
pub extend SegmentUrl with Eq::{equal, not_equal}

///|
pub extend SegmentUrl with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A segment named `media`, with no range: the whole file.
pub fn SegmentUrl::new(media? : String) -> SegmentUrl {
  { media, media_range: None, index_range: None, }
}

///|
/// Segments written out one by one, each with its own URL or its own range.
///
/// This is how a packager addresses a stream it wrote into a single file: the
/// manifest lists where each piece starts and ends, so a player fetches a range
/// instead of a file.
#derive(Eq, Debug)
pub(all) struct SegmentList {
  mut timescale : Int64?
  mut duration : Int64?
  mut start_number : Int64?
  mut presentation_time_offset : Int64?
  mut initialization : Initialization?
  mut urls : Array[SegmentUrl]
}

///|
pub extend SegmentList with Eq::{equal, not_equal}

///|
pub extend SegmentList with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A list with nothing in it.
pub fn SegmentList::new() -> SegmentList {
  {
    timescale: None,
    duration: None,
    start_number: None,
    presentation_time_offset: None,
    initialization: None,
    urls: [],
  }
}

///|
/// How many segments the list holds.
pub fn SegmentList::length(self : SegmentList) -> Int32 {
  self.urls.length()
}

///|
/// A single file addressed by byte ranges, with an index a player reads first.
///
/// The on-demand profile: one request for the index tells a player where every
/// segment is, so it can fetch the ones it needs without the others.
#derive(Eq, Debug)
pub(all) struct SegmentBase {
  mut timescale : Int64?
  mut presentation_time_offset : Int64?
  mut index_range : Range?
  mut index_range_exact : Bool?
  mut initialization : Initialization?
}

///|
pub extend SegmentBase with Eq::{equal, not_equal}

///|
pub extend SegmentBase with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A segment base with nothing set.
pub fn SegmentBase::new() -> SegmentBase {
  {
    timescale: None,
    presentation_time_offset: None,
    index_range: None,
    index_range_exact: None,
    initialization: None,
  }
}

///|
fn read_range(element : Element, name : StringView) -> Range? {
  match element.attribute(name) {
    Some(value) => Range::of(value[:])
    None => None
  }
}

///|
fn read_initialization(element : Element) -> Initialization? {
  match element.child("Initialization") {
    None => None
    Some(node) =>
      Some({
        source_url: optional(node, "sourceURL"),
        range: read_range(node, "range"),
      })
  }
}

///|
fn read_segment_base(
  element : Element,
  name : StringView,
) -> SegmentBase? raise MpdError {
  match element.child(name) {
    None => None
    Some(node) =>
      Some({
        timescale: integer(node, "timescale").map(fn(value) { value.to_int64() }),
        presentation_time_offset: integer(node, "presentationTimeOffset").map(fn(
          value,
        ) {
          value.to_int64()
        }),
        index_range: read_range(node, "indexRange"),
        index_range_exact: optional(node, "indexRangeExact").map(fn(value) {
          value == "true"
        }),
        initialization: read_initialization(node),
      })
  }
}

///|
fn read_segment_list(element : Element) -> SegmentList? raise MpdError {
  let node = match element.child("SegmentList") {
    None => return None
    Some(node) => node
  }
  let list = SegmentList::new()
  list.timescale = integer(node, "timescale").map(fn(value) { value.to_int64() })
  list.duration = integer(node, "duration").map(fn(value) { value.to_int64() })
  list.start_number = integer(node, "startNumber").map(fn(value) {
    value.to_int64()
  })
  list.presentation_time_offset = integer(node, "presentationTimeOffset").map(fn(
    value,
  ) {
    value.to_int64()
  })
  list.initialization = read_initialization(node)
  for url in node.children_of("SegmentURL") {
    list.urls.push({
      media: optional(url, "media"),
      media_range: read_range(url, "mediaRange"),
      index_range: read_range(url, "indexRange"),
    })
  }
  Some(list)
}

///|
fn initialization_element(initialization : Initialization) -> Element {
  let out = element("Initialization", [])
  push_attribute(out, "sourceURL", initialization.source_url)
  match initialization.range {
    Some(range) => out.attributes.push(("range", range.text()))
    None => ()
  }
  out
}

///|
fn segment_base_element(base : SegmentBase) -> Element {
  let out = element("SegmentBase", [])
  push_attribute(out, "timescale", base.timescale.map(fn(v) { v.to_string() }))
  push_attribute(
    out,
    "presentationTimeOffset",
    base.presentation_time_offset.map(fn(v) { v.to_string() }),
  )
  push_attribute(out, "indexRange", base.index_range.map(fn(v) { v.text() }))
  push_attribute(
    out,
    "indexRangeExact",
    base.index_range_exact.map(fn(v) { if v { "true" } else { "false" } }),
  )
  match base.initialization {
    Some(initialization) =>
      out.children.push(initialization_element(initialization))
    None => ()
  }
  out
}

///|
fn segment_list_element(list : SegmentList) -> Element {
  let out = element("SegmentList", [])
  push_attribute(out, "timescale", list.timescale.map(fn(v) { v.to_string() }))
  push_attribute(out, "duration", list.duration.map(fn(v) { v.to_string() }))
  push_attribute(
    out,
    "startNumber",
    list.start_number.map(fn(v) { v.to_string() }),
  )
  push_attribute(
    out,
    "presentationTimeOffset",
    list.presentation_time_offset.map(fn(v) { v.to_string() }),
  )
  match list.initialization {
    Some(initialization) =>
      out.children.push(initialization_element(initialization))
    None => ()
  }
  for url in list.urls {
    let node = element("SegmentURL", [])
    push_attribute(node, "media", url.media)
    push_attribute(node, "mediaRange", url.media_range.map(fn(v) { v.text() }))
    push_attribute(node, "indexRange", url.index_range.map(fn(v) { v.text() }))
    out.children.push(node)
  }
  out
}
