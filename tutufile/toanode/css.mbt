// A `style()` body written as notation rather than as raw text.
//
// `marianoguerra/shrubbery-html` takes a RAW-TEXT HOOK for exactly this: its
// own note says letting a `style()` body hold shrubbery CSS is "the obvious
// next thought", and that the hook is a parameter rather than a dependency so
// that a consumer who already has both halves gets the composition and everyone
// else pays nothing. Tutuca is that consumer.
//
// WHICH SPELLING IS IN USE IS DECIDED BY THE BODY'S OWN SHAPE, with no flag and
// no second element name: `@{…}` is an at-notation literal block and its text is
// CSS verbatim; an ordinary block is notation. Neither can be read as the other.

///|
/// A scoped style block's CSS, lowered from notation.
///
/// A view's style is injected INSIDE `[data-cid="N"]{ … }`, so what is written
/// here is a rule BODY and not a stylesheet. That is why the groups are wrapped
/// in a synthetic rule before they are lowered and unwrapped after: bare
/// declarations are then legal -- which is what `styles.md` documents, they
/// style the component's root element -- and so are nested rules, and the two
/// may be mixed in one block the way the corpus mixes them.
///
/// Lowering the groups at top level instead would refuse every declaration with
/// `shrubcss::declaration_at_top_level`, which is the right answer to the
/// question it is asked and the wrong question to ask.
fn scoped_css(
  groups : Array[@ast.Node],
  span : @report.Span,
) -> String raise ExError {
  guard groups.length() > 0 else { return "" }
  // The groups' own span, reused rather than invented: `basic.Pos` carries a
  // tab-aware column and cannot be built from an offset.
  let at = groups[0].span
  let block = @ast.Node::new(Block(groups), at)
  let head = @ast.Node::new(Id("scope"), at)
  let rule = @ast.Node::new(Group([head, block]), at)
  let root = @ast.Node::new(Multi([rule]), at)
  let out = @csslower.lower(root) catch { _ => raise css_refused(span) }
  if out.has_errors() {
    raise css_diagnostic(out, span)
  }
  let body = StringBuilder()
  for item in out.sheet().items {
    guard item is Rule(Style(r)) else { continue }
    for b in r.body {
      write_item(b, body)
    }
  }
  body.to_string()
}

///|
/// A global style block's CSS: a stylesheet in its own right.
///
/// `style(~global)` is emitted verbatim with no wrapper, so top level is where
/// it belongs -- and it is where `@font-face`, `@keyframes`, `@import` and
/// `:root` are legal. `styles.md` says those must go here and that a browser
/// silently drops them anywhere else; lowering the two scopes in their own
/// contexts is what turns that from a rule an author remembers into one the
/// reader enforces.
fn global_css(
  groups : Array[@ast.Node],
  span : @report.Span,
) -> String raise ExError {
  guard groups.length() > 0 else { return "" }
  let root = @ast.Node::new(Multi(groups), groups[0].span)
  let out = @csslower.lower(root) catch { _ => raise css_refused(span) }
  if out.has_errors() {
    raise css_diagnostic(out, span)
  }
  @csswrite.stylesheet(out.sheet(), style=Minified)
}

///|
/// One item of a rule body.
fn write_item(item : @cssast.BlockItem, out : StringBuilder) -> Unit {
  match item {
    Decl(d) => {
      out.write_string(@csswrite.declaration(d, style=Minified))
      out.write_string(";")
    }
    Rule(r) => out.write_string(@csswrite.rule(r, style=Minified))
    _ => ()
  }
}

///|
/// The notation was read but does not mean CSS.
///
/// The diagnostic is carried across as text rather than as a kind, because the
/// two error sets are different questions -- `shrubcss::` is about CSS that
/// could not be read and `tutu::` about a view that could not be -- and a
/// consumer should be able to tell them apart without parsing the string.
fn css_diagnostic(out : @csslower.Lowered, span : @report.Span) -> ExError {
  let first = out.diagnostics()[0]
  ExError(
    message="this style block is not CSS: " + first.kind.code(),
    help="write the block as `@{ … }` for CSS the notation cannot spell",
    span~,
  )
}

///|
fn css_refused(span : @report.Span) -> ExError {
  ExError(
    message="this style block could not be read as CSS",
    help="write the block as `@{ … }` for CSS the notation cannot spell",
    span~,
  )
}
