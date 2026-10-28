// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// An ISO 8601 duration in seconds: `PT2S`, `PT1M30.5S`, `PT1H`.
///
/// A manifest writes the length of a presentation this way rather than as a
/// count of seconds, and the reader has to take it back apart. Years and months
/// have no fixed length, so a duration that uses them is refused rather than
/// given a length it might not have.
pub fn parse_duration(text : StringView) -> Double? {
  let mut body = text
  let negative = body.has_prefix("-")
  if negative {
    body = body[1:]
  }
  if !body.has_prefix("P") {
    return None
  }
  body = body[1:]
  let mut total = 0.0
  let mut number = ""
  let mut in_time = false
  for i = 0; i < body.length(); i = i + 1 {
    let ch = body[i]
    if ch == 'T' {
      in_time = true
      continue
    }
    if (ch.to_int() >= 0x30 && ch.to_int() <= 0x39) || ch == '.' || ch == '-' {
      number = number + body[i:i + 1].to_owned()
      continue
    }
    let value = @string.parse_double(number) catch { _ => return None }
    number = ""
    if ch == 'W' && !in_time {
      total = total + value * 604_800.0
    } else if ch == 'D' && !in_time {
      total = total + value * 86_400.0
    } else if ch == 'H' && in_time {
      total = total + value * 3600.0
    } else if ch == 'M' && in_time {
      total = total + value * 60.0
    } else if ch == 'S' && in_time {
      total = total + value
    } else {
      // A year or a month, which has no fixed length.
      return None
    }
  }
  if number.length() > 0 {
    return None
  }
  if negative {
    Some(-total)
  } else {
    Some(total)
  }
}

///|
/// A duration in seconds written the way a manifest writes it.
///
/// Fractions are kept to three places, which is finer than any frame rate and
/// short enough to read.
pub fn format_duration(seconds : Double) -> String {
  let negative = seconds < 0.0
  let total = if negative { -seconds } else { seconds }
  let hours = (total / 3600.0).floor()
  let minutes = ((total - hours * 3600.0) / 60.0).floor()
  let rest = total - hours * 3600.0 - minutes * 60.0
  let buf = @buffer.Buffer()
  if negative {
    buf.write_string_utf8("-")
  }
  buf.write_string_utf8("PT")
  if hours >= 1.0 {
    buf.write_string_utf8(hours.to_int().to_string() + "H")
  }
  if minutes >= 1.0 {
    buf.write_string_utf8(minutes.to_int().to_string() + "M")
  }
  if rest != 0.0 || (hours == 0.0 && minutes == 0.0) {
    buf.write_string_utf8(shortest(rest) + "S")
  }
  @utf8.decode_lossy(buf.contents())
}

///|
/// A number written with at most three decimals and no trailing zeros.
fn shortest(value : Double) -> String {
  let rounded = (value * 1000.0).round() / 1000.0
  if rounded == rounded.floor() {
    rounded.to_int().to_string()
  } else {
    rounded.to_string()
  }
}
