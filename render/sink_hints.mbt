// Which render-time rules an element could possibly concern, decided once.
//
// The bridge the two halves of this could not build themselves: the names are
// in `anode`, the tables that classify them are in `vdom/filter`, and neither
// package may import the other (`sinks/moon.pkg` has the reasons). `render`
// already imports both, so it is the one place the question can be asked.
//
// ## Why it is a memo and not a parse result
//
// Because the answer needs `vdom/filter`. Parsing would be the tidier place —
// it happens once per view rather than once per element — but the tables are
// behind a CSS tokenizer and an HTML parser, and every consumer of a view tree
// would link them to compute a fact only a renderer uses.
//
// Memoizing on first build costs one `Option` test per element per render and
// gets the same steady state: `DomData` is shared by every render of that
// element, so the walk over its attributes happens once for the life of the
// tree, whatever renders it.
//
// ## Why memoizing is sound
//
// The bits are a fact about attribute NAMES, and an element's names are fixed
// once it is parsed. Two things could break that and neither does:
//
// - **`Attrs` is mutable after construction.** Only through `set_data_attr`,
//   whose callers write `data-vid`, `data-cid` and `data-nid` — none of which
//   is a URL name, an `on*` name, a CSS property or a directive, and all of
//   which are written at compile time, before any render. `sink_hints_test.mbt`
//   pins the three names against the three predicates.
// - **A filter could add an attribute the next rule then skips.** The three
//   replacing filters only REMOVE the payload name from the element and build
//   CHILDREN, which they sanitize themselves because nothing runs after them
//   there. Nothing in `vdom/filter` writes a new attribute onto the element it
//   was handed.
//
// The failure direction is also the safe one: a hint that is missing (`None`,
// never computed) or too generous (`all()`) costs speed, and only a hint that
// is too NARROW could cost safety. The fold below starts from `empty()` and
// only ever sets bits, over every name the element has.

///|
/// The hints for this element, computing them on first sight.
///
/// Called from the one place `render` builds an element, so "first sight" is
/// the first render that builds it and every later one reads the memo.
fn sink_hints(d : @anode.DomData) -> @sinks.SinkHints {
  match d.sink_hints {
    Some(hints) => hints
    None => {
      let hints = classify_attrs(d.attrs)
      d.sink_hints = Some(hints)
      hints
    }
  }
}

///|
/// Every attribute name this element has, folded into the four bits.
///
/// The name predicates are `vdom/filter`'s own — the same functions the rules
/// call — rather than copies, so a name added to `url_attrs` or a property
/// added to the generated CSS table cannot be classified one way here and
/// decided another way there.
fn classify_attrs(attrs : @anode.Attrs) -> @sinks.SinkHints {
  let mut url = false
  let mut handler = false
  let mut css = false
  let mut markup = false
  fn visit(n : String) {
    url = url || @filter.is_url_attr(n)
    handler = handler || @filter.is_event_handler_attr(n)
    css = css || @filter.is_css_attr(n)
  }

  match attrs {
    ConstAttrs(m) =>
      for attr_name, _ in m {
        visit(attr_name)
      }
    DynAttrs(items) =>
      for item in items {
        match item {
          Plain(name~, ..) | ConstA(name~, ..) => visit(name)
          // Both branches set the SAME attribute, so one name settles it.
          If(if_attr) => visit(if_attr.name)
          // The four directives, which arrive under fixed names rather than
          // author-chosen ones (`eval_attrs` writes them) — so this is the same
          // name question, asked of the variant instead of the string.
          RawHtml(_) | RawMarkdown(_) | SafeHtml(_) | SafeSvg(_) =>
            markup = true
        }
      }
  }
  { url, handler, css, markup }
}
