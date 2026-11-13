// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// One `ContentProtection` entry: the scheme that names a key system, the value
/// that scheme gives the rendition, and the protection header the key system is
/// handed.
///
/// A manifest does not encrypt anything itself; it says which key system opens a
/// rendition and gives that system the box it needs. The box travels base64 in
/// the manifest and is kept here as the bytes it decodes to, so a caller hands it
/// on without decoding anything a second time.
#derive(Eq, Debug)
pub(all) struct ContentProtection {
  /// The scheme that names what protects the rendition, often a UUID.
  mut scheme_id_uri : String
  /// The value the scheme gives this entry, when it gives one.
  mut value : String?
  /// The `pssh` box, decoded.
  mut pssh : Bytes?
}

///|
pub extend ContentProtection with Eq::{equal, not_equal}

///|
pub extend ContentProtection with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// An entry for `scheme_id_uri`, optionally carrying a value and a header.
pub fn ContentProtection::new(
  scheme_id_uri : String,
  value? : String,
  pssh? : Bytes,
) -> ContentProtection {
  { scheme_id_uri, value, pssh, }
}

///|
/// Every `ContentProtection` an element carries.
fn read_protection(
  element : Element,
) -> Array[ContentProtection] raise MpdError {
  let out : Array[ContentProtection] = []
  for entry in element.children_of("ContentProtection") {
    out.push(read_content_protection(entry))
  }
  out
}

///|
fn read_content_protection(
  element : Element,
) -> ContentProtection raise MpdError {
  let pssh = match text_of_child(element, "pssh") {
    None => None
    Some(text) => {
      let outcome = Ok(@base64.decode(text[:], whitespace=true)) catch {
        failure => Err(failure)
      }
      match outcome {
        Ok(bytes) => Some(bytes)
        Err(_) =>
          raise Malformed(at=0, want="a base64 protection header", got=text)
      }
    }
  }
  ContentProtection::new(
    element.text_of("schemeIdUri"),
    value?=optional(element, "value"),
    pssh?,
  )
}

///|
fn content_protection_element(protection : ContentProtection) -> Element {
  let out = element("ContentProtection", [
    ("schemeIdUri", protection.scheme_id_uri),
  ])
  push_attribute(out, "value", protection.value)
  match protection.pssh {
    Some(bytes) => {
      // The prefix is declared on the element that uses it: a rewritten manifest
      // is read without the prolog the original carried.
      out.attributes.push(("xmlns:cenc", "urn:mpeg:cenc:2013"))
      out.children.push(text_element("cenc:pssh", @base64.encode(bytes[:])))
    }
    None => ()
  }
  out
}
