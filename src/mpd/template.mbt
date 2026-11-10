// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The URL a segment of this template is fetched from.
///
/// A template is a name with the numbers filled in: `$RepresentationID$` for
/// which rendition, `$Number$` for which segment, `$Time$` for a segment
/// addressed by the time it starts, and `$Bandwidth$` for what it costs. A
/// number may carry a width, `$Number%05d$`, which is how a list of segments
/// stays in order when it is listed.
///
/// An identifier this release does not know is written back as it was written,
/// so a caller comparing names can see that the template asked for something
/// else rather than fetching the wrong one.
pub fn Template::segment_url(
  self : Template,
  number? : Int64,
  representation_id? : StringView,
  time? : Int64,
  bandwidth? : Int32,
) -> String {
  let text = match self.media {
    Some(media) => media[:]
    None => return ""
  }
  fill(
    text,
    number.unwrap_or(self.start_number.unwrap_or(1L)),
    representation_id.unwrap_or(""),
    time.unwrap_or(0L),
    bandwidth.unwrap_or(0),
  )
}

///|
/// The URL of the initialisation section this template names.
pub fn Template::initialization_url(
  self : Template,
  representation_id? : StringView,
  bandwidth? : Int32,
) -> String {
  let text = match self.initialization {
    Some(initialization) => initialization[:]
    None => return ""
  }
  fill(text, 0L, representation_id.unwrap_or(""), 0L, bandwidth.unwrap_or(0))
}

///|
/// How many segments this template addresses, when the presentation lasts
/// `seconds`.
///
/// A template with one duration repeats it until the presentation ends; a
/// template with a timeline answers with the entries it lists.
pub fn Template::count(self : Template, seconds : Double) -> Int32 {
  match self.duration {
    Some(duration) =>
      if duration > 0L && self.timescale.unwrap_or(1L) > 0L {
        let total = (seconds * self.timescale.unwrap_or(1L).to_double()).to_int64()
        return ((total + duration - 1L) / duration).to_int()
      }
    None => ()
  }
  let mut total = 0
  for entry in self.timeline {
    if entry.repeat < 0 {
      total = total + 1
    } else {
      total = total + entry.repeat + 1
    }
  }
  total
}

///|
fn fill(
  text : StringView,
  number : Int64,
  representation_id : StringView,
  time : Int64,
  bandwidth : Int32,
) -> String {
  let mut out = ""
  let mut at = 0
  while at < text.length() {
    if text.code_unit_at(at).to_int() != 36 {
      out = out + text[at:at + 1].to_owned()
      at = at + 1
      continue
    }
    // A dollar sign starts a placeholder, unless the next character is another
    // dollar sign, which is how a literal one is written.
    if at + 1 < text.length() && text.code_unit_at(at + 1).to_int() == 36 {
      out = out + "$"
      at = at + 2
      continue
    }
    let close = find(text, at + 1)
    if close < 0 {
      out = out + "$"
      at = at + 1
      continue
    }
    let token = text[at + 1:close]
    match placeholder(token, number, representation_id, time, bandwidth) {
      Some(value) => out = out + value
      None => out = out + "$" + token.to_owned() + "$"
    }
    at = close + 1
  }
  out
}

///|
/// Where the dollar sign that closes a placeholder is, or -1 when there is none.
fn find(text : StringView, from : Int32) -> Int32 {
  let mut at = from
  while at < text.length() {
    if text.code_unit_at(at).to_int() == 36 {
      return at
    }
    at = at + 1
  }
  -1
}

///|
/// What a placeholder stands for, or nothing when it is not one this release
/// knows.
fn placeholder(
  token : StringView,
  number : Int64,
  representation_id : StringView,
  time : Int64,
  bandwidth : Int32,
) -> String? {
  let (name, format) = match token.find("%") {
    Some(at) => (token[0:at], Some(token[at:]))
    None => (token, None)
  }
  if name == "RepresentationID" {
    return Some(representation_id.to_owned())
  }
  let value = if name == "Number" {
    Some(number)
  } else if name == "Time" {
    Some(time)
  } else if name == "Bandwidth" {
    Some(bandwidth.to_int64())
  } else {
    None
  }
  match value {
    Some(value) => Some(padded(value, format))
    None => None
  }
}

///|
/// A number in the width the placeholder asks for: `%05d` is five digits, and a
/// placeholder with no width is written as the number is.
fn padded(value : Int64, format : StringView?) -> String {
  let text = value.to_string()
  let width = match format {
    Some(format) => padding(format)
    None => 0
  }
  let mut out = ""
  let mut i = 0
  while i < width - text.length() {
    out = out + "0"
    i = i + 1
  }
  out + text
}

///|
/// The width in a format like `%05d`, or zero when it names something else.
fn padding(format : StringView) -> Int32 {
  if format.length() < 3 || format.code_unit_at(0).to_int() != 37 {
    return 0
  }
  let last = format.code_unit_at(format.length() - 1).to_int()
  // `d`, `i` and `u` are the integer conversions a manifest asks for.
  if last != 100 && last != 105 && last != 117 {
    return 0
  }
  let mut at = 1
  if at < format.length() && format.code_unit_at(at).to_int() == 48 {
    at = at + 1
  }
  let mut width = 0
  while at < format.length() - 1 {
    let digit = format.code_unit_at(at).to_int() - 48
    if digit < 0 || digit > 9 {
      return 0
    }
    width = width * 10 + digit
    at = at + 1
  }
  width
}
