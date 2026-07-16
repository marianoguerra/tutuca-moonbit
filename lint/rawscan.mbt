// Case-preserving raw scan of a start-tag's source span. The WHATWG
// tokenizer lowercases tag/attr names and drops duplicate attributes, so
// case rules (HTML_TAG_NAME_HAS_UPPERCASE, HTML_SVG_ATTR_WILL_LOWERCASE, …)
// re-read the raw span the token came from. The span was already validated
// by the real tokenizer; this scanner only needs the happy shapes.

///|
fn scan_is_space(c : Char) -> Bool {
  c is (' ' | '\t' | '\n' | '\r' | '\u{c}')
}

///|
/// Returns (raw_tag_name, name_start_offset, attrs) for the start tag whose
/// source occupies chars[span_start:span_end].
fn scan_start_tag(
  chars : Array[Char],
  span_start : Int,
  span_end : Int,
) -> (String, Int, Array[RawAttr]) {
  let mut i = span_start
  while i < span_end && chars[i] != '<' {
    i = i + 1
  }
  i = i + 1
  let name_start = i
  let name_buf = StringBuilder::new()
  while i < span_end && !scan_is_space(chars[i]) && !(chars[i] is ('/' | '>')) {
    name_buf.write_char(chars[i])
    i = i + 1
  }
  let attrs : Array[RawAttr] = []
  while i < span_end {
    // Skip whitespace and stray slashes before an attribute name.
    while i < span_end && (scan_is_space(chars[i]) || chars[i] == '/') {
      i = i + 1
    }
    if i >= span_end || chars[i] == '>' {
      break
    }
    let attr_start = i
    let attr_buf = StringBuilder::new()
    while i < span_end &&
          !scan_is_space(chars[i]) &&
          !(chars[i] is ('=' | '/' | '>')) {
      attr_buf.write_char(chars[i])
      i = i + 1
    }
    let raw_name = attr_buf.to_string()
    // Optional value.
    while i < span_end && scan_is_space(chars[i]) {
      i = i + 1
    }
    let mut value = ""
    let mut has_value = false
    if i < span_end && chars[i] == '=' {
      has_value = true
      i = i + 1
      while i < span_end && scan_is_space(chars[i]) {
        i = i + 1
      }
      if i < span_end && chars[i] is ('"' | '\'') {
        let quote = chars[i]
        i = i + 1
        let val_buf = StringBuilder::new()
        while i < span_end && chars[i] != quote {
          val_buf.write_char(chars[i])
          i = i + 1
        }
        i = i + 1 // closing quote
        value = val_buf.to_string()
      } else {
        let val_buf = StringBuilder::new()
        while i < span_end && !scan_is_space(chars[i]) && chars[i] != '>' {
          val_buf.write_char(chars[i])
          i = i + 1
        }
        value = val_buf.to_string()
      }
    }
    if raw_name != "" {
      attrs.push({
        name: raw_name.to_lower(),
        raw_name,
        name_start: attr_start,
        value,
        has_value,
      })
    }
  }
  (name_buf.to_string(), name_start, attrs)
}
