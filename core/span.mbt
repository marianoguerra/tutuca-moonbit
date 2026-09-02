// Where a parsed thing came from.
//
// ONE `Span` for the whole system. It used to be three — `tscript`'s, for a
// slot value and a script block; `statedef`'s, for a spec block; and nothing at
// all in `core`, because the runtime AST carried no positions. The AST is one
// now (`expr_spec.mbt`), it carries its span, and the two lexers above hand it
// theirs — so the three had to become one or the parsers would be converting
// between identical records to cross a package boundary.
//
// It stays a plain pair rather than growing a file name or a line number. A
// span is relative to the string handed to the parser — one attribute's value,
// or one block — and rebasing it onto the containing file is the caller's job:
// `@viewfile.Block` carries the offset that does it, and a span that named its
// own file would be one more thing for that caller to keep consistent.

///|
/// A half-open character range in the source that was parsed.
///
/// Character indices, not bytes: they index `source.to_array()`, the same
/// `Array[Char]` `viewfile` slices with and the WHATWG tokenizer counts in, so
/// a span from a slot value and a span from the file agree for any input,
/// astral characters included.
pub(all) struct Span {
  start : Int
  end_ : Int
} derive(Debug, Eq)

///|
/// The empty span, for a value with no source of its own — a `^macro`
/// variable's expansion, a generated IR module's rebuilt AST, or a value built
/// by hand.
pub let no_span : Span = { start: 0, end_: 0, }
