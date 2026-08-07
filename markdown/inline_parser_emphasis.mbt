///| Emphasis (`*`, `_`) and strong (`**`, `__`) inline parsing.

///|

///| Split from inline_parser.mbt to keep that file focused on the inline

///| dispatcher; this file contains the simple single-pass emphasis matcher

///| plus its `parse_until_closing_marker` helper. The full CommonMark

///| delimiter-stack algorithm lives in inline_parser_strict.mbt.

///|
/// Try to parse emphasis or strong
fn InlineParser::try_parse_emphasis(
  self : InlineParser,
  start : Int,
  marker_char : Char,
) -> Inline? {
  // Count opening markers
  let marker_count = self.scanner.count_char(marker_char)
  if marker_count == 0 {
    return None
  }

  // Only handle 1 or 2 markers (emphasis or strong)
  let is_strong = marker_count >= 2
  let consume_count = if is_strong { 2 } else { 1 }
  self.scanner.advance(consume_count)

  // Check if followed by whitespace (not valid opener)
  match self.scanner.peek() {
    Some(' ') | Some('\t') | Some('\n') | None => {
      self.scanner.restore(start)
      return None
    }
    _ => ()
  }

  // Parse content until closing marker
  let children = self.parse_until_closing_marker(marker_char, consume_count)
  if children.is_empty() {
    self.scanner.restore(start)
    return None
  }
  let marker = if marker_char == '*' {
    EmphasisMarker::Asterisk
  } else {
    EmphasisMarker::Underscore
  }
  if is_strong {
    Some(
      Inline::Strong(
        marker~,
        children~,
        span=Span::new(start, self.scanner.pos),
      ),
    )
  } else {
    Some(
      Inline::Emphasis(
        marker~,
        children~,
        span=Span::new(start, self.scanner.pos),
      ),
    )
  }
}

///|
/// Parse content until closing marker
fn InlineParser::parse_until_closing_marker(
  self : InlineParser,
  marker_char : Char,
  marker_count : Int,
) -> Array[Inline] {
  let children : Array[Inline] = []
  let text_buf = StringBuilder::new()
  let text_start = self.scanner.pos
  while !self.scanner.is_eof() {
    // Check for closing marker
    let closing_count = self.scanner.count_char(marker_char)
    if closing_count >= marker_count {
      // Check if preceded by non-whitespace
      let prev_char = self.scanner.peek_at(-1)
      match prev_char {
        Some(' ') | Some('\t') | Some('\n') => () // Not valid closer
        _ => {
          // Valid closer - flush text and consume markers
          if !text_buf.is_empty() {
            children.push(
              Inline::Text(
                content=text_buf.to_string(),
                span=Span::new(text_start, self.scanner.pos),
              ),
            )
          }
          self.scanner.advance(marker_count)
          return children
        }
      }
    }

    // Handle nested inline elements
    match self.scanner.peek() {
      Some('`') => {
        // Flush text before inline
        if !text_buf.is_empty() {
          children.push(
            Inline::Text(
              content=text_buf.to_string(),
              span=Span::new(text_start, self.scanner.pos),
            ),
          )
        }
        let nested_start = self.scanner.pos
        match self.try_parse_code_span(nested_start) {
          Some(code) => {
            children.push(code)
            continue
          }
          None => ()
        }
      }
      Some('[') => {
        if !text_buf.is_empty() {
          children.push(
            Inline::Text(
              content=text_buf.to_string(),
              span=Span::new(text_start, self.scanner.pos),
            ),
          )
        }
        let nested_start = self.scanner.pos
        match self.try_parse_link(nested_start) {
          Some(link) => {
            children.push(link)
            continue
          }
          None => ()
        }
      }
      Some('\n') =>
        // Newline ends emphasis in most cases
        break
      _ => ()
    }

    // Regular character
    match self.scanner.consume() {
      Some(c) => text_buf.write_char(c)
      None => break
    }
  }

  // No closing marker found
  []
}
