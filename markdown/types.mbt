///| Markdown CST (Concrete Syntax Tree) Types

///| Designed for lossless roundtrip and incremental parsing

// =============================================================================
// Source Position
// =============================================================================

///| Source position in the original markdown text

///|
/// Using #valtype to avoid heap allocation for this frequently-used small struct
#valtype
pub(all) struct Span {
  from : Int32
  to : Int32
} derive(Eq, Debug)

///|
pub extend Span with Eq::{not_equal, equal}

///|
pub extend Span with Debug::{to_repr}

///|
/// Create a span
pub fn Span::new(from : Int32, to : Int32) -> Span {
  { from, to, }
}

///|
/// Empty span (for synthetic nodes)
pub fn Span::empty() -> Span {
  { from: 0, to: 0, }
}

// =============================================================================
// Markers (for lossless serialization)
// =============================================================================

///|
/// Emphasis marker: * or _
pub(all) enum EmphasisMarker {
  Asterisk // *
  Underscore // _
} derive(Eq, Debug)

///|
pub extend EmphasisMarker with Eq::{not_equal, equal}

///|
pub extend EmphasisMarker with Debug::{to_repr}

///|
/// Fence marker for code blocks: ``` or ~~~
pub(all) enum FenceMarker {
  Backtick // ```
  Tilde // ~~~
} derive(Eq, Debug)

///|
pub extend FenceMarker with Eq::{not_equal, equal}

///|
pub extend FenceMarker with Debug::{to_repr}

///|
/// List marker for unordered lists: -, *, +
pub(all) enum BulletMarker {
  Dash // -
  Asterisk // *
  Plus // +
} derive(Eq, Debug)

///|
pub extend BulletMarker with Eq::{not_equal, equal}

///|
pub extend BulletMarker with Debug::{to_repr}

///|
/// Ordered list delimiter: . or )
pub(all) enum OrderedDelimiter {
  Dot // 1.
  Paren // 1)
} derive(Eq, Debug)

///|
pub extend OrderedDelimiter with Eq::{not_equal, equal}

///|
pub extend OrderedDelimiter with Debug::{to_repr}

///|
/// Heading style
pub(all) enum HeadingStyle {
  Atx // # Heading
  Setext // Heading\n======
} derive(Eq, Debug)

// =============================================================================
// Trivia (preserved whitespace/formatting)
// =============================================================================

///|
pub extend HeadingStyle with Eq::{not_equal, equal}

///|
pub extend HeadingStyle with Debug::{to_repr}

///|
/// Trivia represents non-semantic characters that should be preserved
pub(all) struct Trivia {
  content : String
} derive(Eq, Debug)

///|
pub extend Trivia with Eq::{not_equal, equal}

///|
pub extend Trivia with Debug::{to_repr}

///|
pub fn Trivia::new(content : String) -> Trivia {
  { content, }
}

///|
pub fn Trivia::empty() -> Trivia {
  { content: "", }
}

///|
pub impl Show for Span with fn output(self : Span, logger : &Logger) -> Unit {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend Span with Show::{to_string, output}

///|
pub impl Show for EmphasisMarker with fn output(
  self : EmphasisMarker,
  logger : &Logger,
) -> Unit {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend EmphasisMarker with Show::{to_string, output}

///|
pub impl Show for FenceMarker with fn output(
  self : FenceMarker,
  logger : &Logger,
) -> Unit {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend FenceMarker with Show::{to_string, output}

///|
pub impl Show for BulletMarker with fn output(
  self : BulletMarker,
  logger : &Logger,
) -> Unit {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend BulletMarker with Show::{to_string, output}

///|
pub impl Show for OrderedDelimiter with fn output(
  self : OrderedDelimiter,
  logger : &Logger,
) -> Unit {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend OrderedDelimiter with Show::{to_string, output}

///|
pub impl Show for HeadingStyle with fn output(
  self : HeadingStyle,
  logger : &Logger,
) -> Unit {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend HeadingStyle with Show::{to_string, output}

///|
pub impl Show for Trivia with fn output(self : Trivia, logger : &Logger) -> Unit {
  logger.write_string(@debug.to_string(self))
}

// =============================================================================
// Block-level CST Nodes
// =============================================================================

///|
pub extend Trivia with Show::{to_string, output}

///|
/// Document root
pub(all) struct Document {
  frontmatter : Frontmatter?
  children : Array[Block]
  span : Span
}

///|
/// Frontmatter (YAML)
pub(all) struct Frontmatter {
  raw : String // Original YAML content (between ---)
  entries : Array[(String, String)] // Parsed key-value pairs
  span : Span
}

///|
/// Block-level nodes
pub(all) enum Block {
  /// Thematic break (---, ***, ___)
  ThematicBreak(
    marker~ : Char, // '-', '*', or '_'
    count~ : Int32, // Number of marker chars (>= 3)
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// ATX or Setext heading
  Heading(
    level~ : Int32, // 1-6
    style~ : HeadingStyle,
    children~ : Array[Inline],
    closing_hashes~ : Int32, // For ATX: number of closing # (0 if none)
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Paragraph
  Paragraph(
    children~ : Array[Inline],
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Fenced code block
  FencedCode(
    fence_marker~ : FenceMarker,
    fence_length~ : Int32, // Number of fence chars (>= 3)
    info~ : String, // Language info (e.g., "json:file.json")
    code~ : String, // Code content
    indent~ : Int32, // Leading spaces on fence (0-3)
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Indented code block
  IndentedCode(
    code~ : String,
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Blockquote
  Blockquote(
    children~ : Array[Block],
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Unordered list
  BulletList(
    marker~ : BulletMarker,
    tight~ : Bool, // Tight (no blank lines) or loose
    items~ : Array[ListItem],
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Ordered list
  OrderedList(
    start~ : Int32, // Starting number
    delimiter~ : OrderedDelimiter,
    tight~ : Bool,
    items~ : Array[ListItem],
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Raw HTML block
  HtmlBlock(
    html~ : String,
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Table (GFM)
  Table(
    header~ : Array[TableCell],
    alignments~ : Array[TableAlign],
    rows~ : Array[Array[TableCell]],
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
  /// Blank lines (preserved)
  BlankLines(count~ : Int32, span~ : Span)
  /// Footnote definition [^label]: content (GFM)
  FootnoteDefinition(
    label~ : String,
    children~ : Array[Block],
    span~ : Span,
    leading_trivia~ : Trivia,
    trailing_trivia~ : Trivia
  )
}

///|
/// List item
pub(all) struct ListItem {
  children : Array[Block]
  checked : Bool? // For task lists: Some(true), Some(false), or None
  marker_offset : Int32 // Spaces before marker
  content_offset : Int32 // Spaces after marker before content
  span : Span
}

///|
/// Table cell
pub(all) struct TableCell {
  children : Array[Inline]
  span : Span
}

///|
/// Table alignment
pub(all) enum TableAlign {
  Left
  Center
  Right
  None
} derive(Eq, Debug)

// =============================================================================
// Inline-level CST Nodes
// =============================================================================

///|
pub extend TableAlign with Eq::{not_equal, equal}

///|
pub extend TableAlign with Debug::{to_repr}

///|
/// Inline-level nodes
pub(all) enum Inline {
  /// Plain text
  Text(content~ : String, span~ : Span)
  /// Soft line break (single newline in source)
  SoftBreak(span~ : Span)
  /// Hard line break (two spaces + newline or backslash + newline)
  HardBreak(style~ : HardBreakStyle, span~ : Span)
  /// Emphasis (*text* or _text_)
  Emphasis(marker~ : EmphasisMarker, children~ : Array[Inline], span~ : Span)
  /// Strong emphasis (**text** or __text__)
  Strong(marker~ : EmphasisMarker, children~ : Array[Inline], span~ : Span)
  /// Strikethrough (~~text~~) - GFM
  Strikethrough(children~ : Array[Inline], span~ : Span)
  /// Inline code (`code`)
  Code(
    content~ : String,
    backtick_count~ : Int32, // Number of backticks used
    span~ : Span
  )
  /// Wiki link [[target]] or [[target|label]] (opt-in extension)
  WikiLink(target~ : String, label~ : String, fragment~ : String, span~ : Span)
  /// Link [text](url "title")
  Link(children~ : Array[Inline], url~ : String, title~ : String, span~ : Span)
  /// Reference link [text][ref]
  RefLink(children~ : Array[Inline], label~ : String, span~ : Span)
  /// Autolink <url>
  Autolink(url~ : String, is_email~ : Bool, span~ : Span)
  /// Image ![alt](url "title")
  Image(alt~ : String, url~ : String, title~ : String, span~ : Span)
  /// Reference image ![alt][ref]
  RefImage(alt~ : String, label~ : String, span~ : Span)
  /// Raw inline HTML
  HtmlInline(html~ : String, span~ : Span)
  /// Footnote reference [^label] (GFM)
  FootnoteReference(label~ : String, span~ : Span)
}

///|
/// Hard break style
pub(all) enum HardBreakStyle {
  TwoSpaces // "  \n"
  Backslash // "\\\n"
} derive(Eq, Debug)

///|
pub extend HardBreakStyle with Eq::{not_equal, equal}

///|
pub extend HardBreakStyle with Debug::{to_repr}

///|
pub impl Show for TableAlign with fn output(self : TableAlign, logger : &Logger) -> Unit {
  logger.write_string(@debug.to_string(self))
}

///|
pub extend TableAlign with Show::{to_string, output}

///|
pub impl Show for HardBreakStyle with fn output(
  self : HardBreakStyle,
  logger : &Logger,
) -> Unit {
  logger.write_string(@debug.to_string(self))
}

// =============================================================================
// Reference Definitions
// =============================================================================

///|
pub extend HardBreakStyle with Show::{to_string, output}

///|
/// Link reference definition [label]: url "title"
pub(all) struct LinkDefinition {
  label : String
  url : String
  title : String
  span : Span
}
