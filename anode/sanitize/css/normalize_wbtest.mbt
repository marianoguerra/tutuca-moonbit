// The normalization phase from inside the package, where `preprocess` lives.
//
// Whitebox because the phase is not API: a host chooses a `CssPolicy`, and what
// happens to the bytes before the tokenizer sees them is this package's own
// business. It is still worth pinning, because it is the half that closes the
// two places `mizchi/css/token` diverges from css-syntax-3.

///|
/// The surviving declaration list, or `"-"`.
fn kept_wb(src : String) -> String {
  match CssPolicy::payload().declarations(src).css {
    Some(text) => text
    None => "-"
  }
}

///|
/// css-syntax-3 §3.3 preprocessing runs before the tokenizer sees anything.
///
/// A NUL matters more than it looks: `mizchi/css/token` uses U+0000 as the
/// value `peek_char` returns past the end of input, so an embedded one is
/// indistinguishable from end-of-file to every caller inside the tokenizer,
/// while a browser replaces it with U+FFFD and keeps reading. After
/// `preprocess` there is no NUL left to be ambiguous about.
test "NUL, form feed and CRLF are normalized before tokenizing" {
  inspect(preprocess("a\u{0}b").length(), content="3")
  inspect(preprocess("a\u{0}b") == "a\u{FFFD}b", content="true")
  inspect(preprocess("a\r\nb") == "a\nb", content="true")
  inspect(preprocess("a\rb") == "a\nb", content="true")
  inspect(preprocess("a\u{C}b") == "a\nb", content="true")
  // A NUL does not truncate the list. It lands in a name, which stops being
  // ASCII and so stops being a property — but only THAT declaration is lost,
  // and everything after it is still read. A tokenizer that took the NUL for
  // end-of-input would have kept the first declaration and silently dropped
  // both of the others.
  inspect(
    kept_wb("color:red;te\u{0}xt-align:left;font-size:12px"),
    content="color:red;font-size:12px",
  )
}
