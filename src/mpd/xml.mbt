// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// Why a manifest could not be read.
///
/// `at` is the byte offset the reader had reached, `want` what the grammar
/// requires there and `got` what was there.
pub(all) suberror MpdError {
  Malformed(at~ : Int32, want~ : String, got~ : String)
}

///|
/// The account of a failure.
pub extend MpdError with Show::{to_string, output}

///|
pub impl Show for MpdError with fn output(self, logger) {
  let Malformed(at~, want~, got~) = self
  logger.write_string(
    "at " + at.to_string() + ": want " + want + ", got " + got,
  )
}

///|
/// An element of the document: a name, its attributes in the order they were
/// written, and what it contains.
priv struct Element {
  name : String
  attributes : Array[(String, String)]
  children : Array[Element]
  text : String
}

///|
/// An element with attributes and no children yet.
fn element(name : StringView, attributes : Array[(String, String)]) -> Element {
  { name: name.to_owned(), attributes, children: [], text: "", }
}

///|
/// An element whose content is text.
fn text_element(name : StringView, text : StringView) -> Element {
  {
    name: name.to_owned(),
    attributes: [],
    children: [],
    text: text.to_owned(),
  }
}

///|
/// Write the document, two spaces to the level, with the declaration first.
fn render(root : Element) -> String {
  let buf = @buffer.Buffer()
  buf.write_string_utf8("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
  write_element(buf, root, 0)
  @utf8.decode_lossy(buf.contents())
}

///|
fn write_element(
  buf : @buffer.Buffer,
  element : Element,
  depth : Int32,
) -> Unit {
  for i = 0; i < depth * 2; i = i + 1 {
    buf.write_byte(b' ')
  }
  buf.write_string_utf8("<" + element.name)
  for pair in element.attributes {
    buf.write_string_utf8(" " + pair.0 + "=\"" + escape(pair.1[:]) + "\"")
  }
  if element.children.length() == 0 && element.text.length() == 0 {
    buf.write_string_utf8("/>\n")
    return
  }
  buf.write_string_utf8(">")
  if element.children.length() == 0 {
    // Text stays on the line of its element: a URL broken across lines is a
    // URL some reader will get wrong.
    buf.write_string_utf8(escape(element.text[:]))
    buf.write_string_utf8("</" + element.name + ">\n")
    return
  }
  buf.write_byte(b'\n')
  for child in element.children {
    write_element(buf, child, depth + 1)
  }
  for i = 0; i < depth * 2; i = i + 1 {
    buf.write_byte(b' ')
  }
  buf.write_string_utf8("</" + element.name + ">\n")
}

///|
/// Whether this element is named `name`, with or without a namespace prefix.
fn Element::is_named(self : Element, name : StringView) -> Bool {
  self.name[:] == name || self.name.has_suffix(":" + name.to_owned())
}

///|
/// An attribute by name.
fn Element::attribute(self : Element, name : StringView) -> String? {
  for pair in self.attributes {
    if pair.0[:] == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// An attribute by name, or the empty string.
fn Element::text_of(self : Element, name : StringView) -> String {
  match self.attribute(name) {
    Some(value) => value
    None => ""
  }
}

///|
/// The first child with this name.
fn Element::child(self : Element, name : StringView) -> Element? {
  for child in self.children {
    if child.is_named(name) {
      return Some(child)
    }
  }
  None
}

///|
/// Every child with this name.
fn Element::children_of(self : Element, name : StringView) -> Array[Element] {
  let out : Array[Element] = []
  for child in self.children {
    if child.is_named(name) {
      out.push(child)
    }
  }
  out
}

///|
/// What an element holds, when it holds text rather than elements: a `BaseURL`
/// or the value of a `SegmentTemplate` media pattern.
fn Element::content(self : Element) -> String {
  self.text
}

///|
/// A document: its root element.
fn parse_document(text : StringView) -> Element raise MpdError {
  let mut cursor = 0
  let n = text.length()
  // The prolog, comments and whitespace before the root.
  while cursor < n {
    if text[cursor] == '<' {
      if starts_with(text, cursor, "<?") {
        cursor = skip_past(text, cursor, "?>")
      } else if starts_with(text, cursor, "<!--") {
        cursor = skip_past(text, cursor, "-->")
      } else if starts_with(text, cursor, "<!") {
        cursor = skip_past(text, cursor, ">")
      } else {
        break
      }
    } else {
      cursor = cursor + 1
    }
  }
  if cursor >= n {
    raise Malformed(at=cursor, want="a root element", got="end of document")
  }
  let (root, _) = parse_element(text, cursor)
  root
}

///|
/// Whether `text` has `pattern` at `at`.
fn starts_with(text : StringView, at : Int32, pattern : StringView) -> Bool {
  if at + pattern.length() > text.length() {
    return false
  }
  text[at:at + pattern.length()] == pattern
}

///|
/// Where `pattern` ends, the first time it appears at or after `at`.
fn skip_past(
  text : StringView,
  at : Int32,
  pattern : StringView,
) -> Int32 raise MpdError {
  let mut cursor = at
  while cursor + pattern.length() <= text.length() {
    if starts_with(text, cursor, pattern) {
      return cursor + pattern.length()
    }
    cursor = cursor + 1
  }
  raise Malformed(
    at~,
    want="a closing " + pattern.to_owned(),
    got="end of document",
  )
}

///|
/// Read the element that starts at `at`, and say where it ended.
fn parse_element(
  text : StringView,
  at : Int32,
) -> (Element, Int32) raise MpdError {
  if at >= text.length() || text[at] != '<' {
    raise Malformed(at~, want="an element", got="something else")
  }
  let mut cursor = at + 1
  let name_start = cursor
  while cursor < text.length() &&
        !is_space(text[cursor].to_int()) &&
        text[cursor] != '>' &&
        text[cursor] != '/' {
    cursor = cursor + 1
  }
  let name = text[name_start:cursor].to_owned()
  if name.length() == 0 {
    raise Malformed(at~, want="an element name", got="nothing")
  }
  let attributes : Array[(String, String)] = []
  while true {
    while cursor < text.length() && is_space(text[cursor].to_int()) {
      cursor = cursor + 1
    }
    if cursor >= text.length() {
      raise Malformed(at=cursor, want=">", got="end of document")
    }
    if text[cursor] == '/' {
      // A self-closing element holds nothing.
      if cursor + 1 >= text.length() || text[cursor + 1] != '>' {
        raise Malformed(at=cursor, want="/>", got="something else")
      }
      return ({ name, attributes, children: [], text: "", }, cursor + 2)
    }
    if text[cursor] == '>' {
      cursor = cursor + 1
      break
    }
    let attribute_start = cursor
    while cursor < text.length() &&
          text[cursor] != '=' &&
          !is_space(text[cursor].to_int()) {
      cursor = cursor + 1
    }
    let attribute_name = text[attribute_start:cursor].to_owned()
    while cursor < text.length() && is_space(text[cursor].to_int()) {
      cursor = cursor + 1
    }
    if cursor >= text.length() || text[cursor] != '=' {
      raise Malformed(at=cursor, want="=", got="something else")
    }
    cursor = cursor + 1
    while cursor < text.length() && is_space(text[cursor].to_int()) {
      cursor = cursor + 1
    }
    if cursor >= text.length() || (text[cursor] != '"' && text[cursor] != '\'') {
      raise Malformed(at=cursor, want="a quoted value", got="something else")
    }
    let quote = text[cursor]
    cursor = cursor + 1
    let value_start = cursor
    while cursor < text.length() && text[cursor] != quote {
      cursor = cursor + 1
    }
    if cursor >= text.length() {
      raise Malformed(
        at=value_start,
        want="a closing quote",
        got="end of document",
      )
    }
    let value = unescape(text[value_start:cursor])
    cursor = cursor + 1
    attributes.push((attribute_name, value))
  }
  // Content: text, child elements, and comments, up to the closing tag.
  let children : Array[Element] = []
  let body = @buffer.Buffer()
  while true {
    if cursor >= text.length() {
      raise Malformed(at=cursor, want="</" + name + ">", got="end of document")
    }
    if text[cursor] == '<' {
      if starts_with(text, cursor, "</") {
        let (closing, next) = parse_closing(text, cursor)
        if closing != name {
          raise Malformed(
            at=cursor,
            want="</" + name + ">",
            got="</" + closing + ">",
          )
        }
        return (
          { name, attributes, children, text: decode_text(body.contents()), },
          next,
        )
      } else if starts_with(text, cursor, "<!--") {
        cursor = skip_past(text, cursor, "-->")
      } else if starts_with(text, cursor, "<![CDATA[") {
        let start = cursor + 9
        let next = skip_past(text, cursor, "]]>")
        body.write_bytes(@utf8.encode(text[start:next - 3]))
        cursor = next
      } else {
        let (child, next) = parse_element(text, cursor)
        children.push(child)
        cursor = next
      }
    } else {
      let start = cursor
      while cursor < text.length() && text[cursor] != '<' {
        cursor = cursor + 1
      }
      body.write_bytes(@utf8.encode(text[start:cursor]))
    }
  }
  raise Malformed(at=cursor, want="an element end", got="nothing")
}

///|
/// Split a closing tag into its name and where it ended.
fn parse_closing(
  text : StringView,
  at : Int32,
) -> (String, Int32) raise MpdError {
  let mut cursor = at + 2
  let start = cursor
  while cursor < text.length() &&
        !is_space(text[cursor].to_int()) &&
        text[cursor] != '>' {
    cursor = cursor + 1
  }
  let name = text[start:cursor].to_owned()
  while cursor < text.length() && text[cursor] != '>' {
    cursor = cursor + 1
  }
  if cursor >= text.length() {
    raise Malformed(at~, want=">", got="end of document")
  }
  (name, cursor + 1)
}

///|
fn is_space(ch : Int32) -> Bool {
  ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D
}

///|
/// The text of an element, with the five entities the specification defines and
/// the numeric ones a document may carry turned back into characters.
fn unescape(text : StringView) -> String {
  if !text.contains_char('&') {
    return text.to_owned()
  }
  decode_text(@utf8.encode(text))
}

///|
/// Decode a run of entity references, and trim it when it is only whitespace.
fn decode_text(bytes : Bytes) -> String {
  let text = @utf8.decode_lossy(bytes)
  let view = text[:]
  if !view.contains_char('&') {
    return text
  }
  let out = @buffer.Buffer()
  let n = view.length()
  let mut at = 0
  while at < n {
    if view[at] == '&' {
      match view[at:].find(";") {
        Some(offset) => {
          let entity = view[at + 1:at + offset]
          let replacement : String? = if entity == "amp" {
            Some("&")
          } else if entity == "lt" {
            Some("<")
          } else if entity == "gt" {
            Some(">")
          } else if entity == "quot" {
            Some("\"")
          } else if entity == "apos" {
            Some("'")
          } else if entity.has_prefix("#x") || entity.has_prefix("#X") {
            numeric_entity(entity[2:], 16)
          } else if entity.has_prefix("#") {
            numeric_entity(entity[1:], 10)
          } else {
            None
          }
          match replacement {
            Some(value) => {
              out.write_string_utf8(value)
              at = at + offset + 1
            }
            None => {
              out.write_byte(b'&')
              at = at + 1
            }
          }
        }
        None => {
          out.write_byte(b'&')
          at = at + 1
        }
      }
    } else {
      out.write_string_utf8(view[at:at + 1])
      at = at + 1
    }
  }
  @utf8.decode_lossy(out.contents())
}

///|
/// The character a numeric reference names, when it names one a document may
/// carry.
fn numeric_entity(digits : StringView, base : Int32) -> String? {
  let value = @string.parse_int(digits, base~) catch { _ => return None }
  match value.to_char() {
    Some(ch) => Some(ch.to_string())
    None => None
  }
}

///|
/// Write `text` with the characters that would end an element or an attribute
/// replaced by their entities.
fn escape(text : StringView) -> String {
  let out = @buffer.Buffer()
  for ch in text {
    if ch == '&' {
      out.write_string_utf8("&amp;")
    } else if ch == '<' {
      out.write_string_utf8("&lt;")
    } else if ch == '>' {
      out.write_string_utf8("&gt;")
    } else if ch == '"' {
      out.write_string_utf8("&quot;")
    } else {
      out.write_char_utf8(ch)
    }
  }
  @utf8.decode_lossy(out.contents())
}
