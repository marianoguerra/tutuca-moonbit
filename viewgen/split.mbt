// Splitting an input file into views.
//
// The views are recovered as RAW SOURCE TEXT, not by re-serializing a parsed
// tree: view attribute values are tutuca expressions full of quotes and
// `@`/`:`/`$` sigils, and a parse/serialize round-trip through the HTML tree
// would have to reproduce them byte-exactly to be safe. Instead we run the
// WHATWG tokenizer purely to find element boundaries — it already handles
// comments, quoted attribute values and character references — and slice the
// original text between them.
//
// Offsets are indices into `source.to_array()`, the same Array[Char] the
// tokenizer indexes with (@html5.Tokenizer::new -> `input.to_array()`), so
// they line up for any input, astral characters included.

///|
/// The `id=` prefix that marks a `<template>` as a macro declaration.
const MACRO_PREFIX = "macro:"

///|
/// A `<style>` element's span in the source, plus its extracted text.
priv struct StyleRegion {
  start : Int // offset of '<'
  end_ : Int // offset just past '>' of </style>
  text : String
  kind : StyleKind
}

///|
priv enum StyleKind {
  SView // inside a template (or the whole file when there are none)
  SCommon // top-level <style data-common>
  SGlobal // top-level <style data-global>
} derive(Eq)

///|
/// A top-level `<template>`'s CONTENT span (between `>` and `</`).
priv struct TplSpan {
  id : String?
  attrs : Array[@html5.Attribute]
  start : Int
  end_ : Int
}

///|
fn attr_of(attrs : Array[@html5.Attribute], name : String) -> String? {
  for a in attrs {
    if a.name == name {
      return Some(a.value)
    }
  }
  None
}

///|
fn is_space(c : Char) -> Bool {
  c == ' ' || c == '\n' || c == '\t' || c == '\r' || c == '\u{0C}'
}

///|
/// Slice [start, end_) out of `chars`, skipping any style region that starts
/// inside it. Regions are in source order and never overlap.
fn slice_without_styles(
  chars : Array[Char],
  start : Int,
  end_ : Int,
  styles : Array[StyleRegion],
) -> String {
  let sb = StringBuilder::new()
  let mut i = start
  while i < end_ {
    let mut jumped = false
    for s in styles {
      if s.start == i {
        i = s.end_
        jumped = true
        break
      }
    }
    if jumped {
      continue
    }
    sb.write_char(chars[i])
    i = i + 1
  }
  sb.to_string()
}

///|
/// Drop the indentation a view inherits from sitting inside `<template>`:
/// the common leading-space prefix of every non-blank line, plus trailing
/// blank space at either end.
fn dedent(s : String) -> String {
  let lines : Array[String] = s.split("\n").map(l => l.to_owned()).collect()
  let mut common = -1
  for line in lines {
    let chars = line.to_array()
    let mut n = 0
    while n < chars.length() && (chars[n] == ' ' || chars[n] == '\t') {
      n = n + 1
    }
    if n == chars.length() {
      continue // blank line: carries no indentation information
    }
    if common < 0 || n < common {
      common = n
    }
  }
  let out = if common <= 0 {
    lines
  } else {
    lines.map(l => if l.length() >= common { l[common:].to_owned() } else { l })
  }
  // Blank lines at either end, e.g. where a lifted <style> used to be.
  while out.length() > 0 && out[0].trim(chars=" \t") == "" {
    out.remove(0) |> ignore
  }
  while out.length() > 0 && out[out.length() - 1].trim(chars=" \t") == "" {
    out.pop() |> ignore
  }
  out.join("\n")
}

///|
/// The styles that belong to the view spanning [start, end_).
fn styles_within(
  start : Int,
  end_ : Int,
  styles : Array[StyleRegion],
) -> String {
  let parts : Array[String] = []
  for s in styles {
    if s.start >= start && s.start < end_ {
      parts.push(s.text)
    }
  }
  parts.join("\n")
}

///|
/// Read a `<style>` element's text. The bare tokenizer does not enter RAWTEXT
/// on its own (the tree builder normally drives that), so we switch it
/// ourselves, which keeps a `<` inside CSS from being read as a tag.
fn read_style(tok : @html5.Tokenizer) -> (String, Int) {
  tok.switch_to_rawtext()
  let sb = StringBuilder::new()
  let mut end_ = tok.get_position().offset
  let mut done = false
  while !done {
    let before = tok.get_position().offset
    match tok.next_token() {
      Character(c) => sb.write_char(c)
      EndTag(name~) =>
        if name == "style" {
          end_ = tok.get_position().offset
          done = true
        }
      EOF => {
        end_ = before
        done = true
      }
      _ => ()
    }
  }
  (sb.to_string(), end_)
}

///|
pub fn split_file(source : String) -> ViewFile raise GenError {
  let chars = source.to_array()
  let tok = @html5.Tokenizer::new(source)
  let styles : Array[StyleRegion] = []
  let templates : Array[TplSpan] = []
  let mut depth = 0
  let mut open_start = 0
  let mut open_id : String? = None
  let mut open_attrs : Array[@html5.Attribute] = []
  let mut open_at = ""
  let mut stray : Char? = None
  let mut at_eof = false
  while !at_eof {
    let before = tok.get_position().offset
    let token = tok.next_token()
    let after = tok.get_position().offset
    match token {
      EOF => at_eof = true
      StartTag(name~, attrs~, self_closing~) =>
        match name {
          "template" =>
            if !self_closing {
              if depth == 0 {
                open_start = after
                open_id = attr_of(attrs, "id")
                open_attrs = attrs
                open_at = match open_id {
                  Some(id) => " id=\"\{id}\""
                  None => ""
                }
              }
              depth = depth + 1
            }
          "style" => {
            let (text, end_) = read_style(tok)
            // Inside a template: that view's style. At file level:
            // data-global picks the global style, otherwise the common one.
            let kind = if depth > 0 {
              SView
            } else if attr_of(attrs, "data-global") is Some(_) {
              SGlobal
            } else {
              SCommon
            }
            styles.push({ start: before, end_, text, kind })
          }
          _ => ()
        }
      EndTag(name~) =>
        if name == "template" && depth > 0 {
          depth = depth - 1
          if depth == 0 {
            templates.push({
              id: open_id,
              attrs: open_attrs,
              start: open_start,
              end_: before,
            })
          }
        }
      Character(c) =>
        if depth == 0 && !is_space(c) && stray is None {
          stray = Some(c)
        }
      _ => ()
    }
  }
  if depth > 0 {
    raise UnclosedTemplate(open_at)
  }
  let common_style = collect_style(styles, SCommon)
  let global_style = collect_style(styles, SGlobal)
  // No templates at all: the file IS one unnamed component's main view.
  if templates.is_empty() {
    let src = slice_without_styles(chars, 0, chars.length(), styles)
    return {
      components: [
        {
          name: "",
          views: [
            {
              name: "main",
              source: dedent(src.trim(chars="\n").to_owned()),
              style: "",
            },
          ],
          common_style,
          global_style,
        },
      ],
      macros: [],
    }
  }
  if stray is Some(c) {
    raise StrayText(
      "unexpected '\{c}' outside a <template>; with templates present, every view must live inside one",
    )
  }
  let macros : Array[MacroDef] = []
  let macro_names : Map[String, Bool] = Map([])
  // Component name -> its views, in first-seen order.
  let order : Array[String] = []
  let by_comp : Map[String, Array[RawView]] = Map([])
  let mut saw_named = false
  let mut saw_unnamed = false
  for t in templates {
    let body = dedent(
      slice_without_styles(chars, t.start, t.end_, styles)
      .trim(chars="\n")
      .to_owned(),
    )
    let style = styles_within(t.start, t.end_, styles)
    let id = t.id.unwrap_or("")
    // `macro:name` — a macro shared by every component in the file.
    if id.has_prefix(MACRO_PREFIX) {
      let name = id[MACRO_PREFIX.length():].to_owned()
      if name == "" {
        raise BadMacroName(id)
      }
      if macro_names.contains(name) {
        raise DuplicateMacro(name)
      }
      macro_names[name] = true
      let defaults : Map[String, String] = Map([])
      for a in t.attrs {
        if a.name.has_prefix("data-") {
          defaults[a.name[5:].to_owned()] = a.value
        }
      }
      macros.push({ name, defaults, source: body })
      continue
    }
    // `Comp:view` / `Comp` name a component; a bare id or none belongs to the
    // file's single unnamed component.
    let (comp, vname) = match split_qualified(id) {
      Some(pair) => {
        saw_named = true
        pair
      }
      None => {
        saw_unnamed = true
        ("", if id == "" { "main" } else { id })
      }
    }
    if saw_named && saw_unnamed {
      raise MixedViewIds
    }
    if !by_comp.contains(comp) {
      order.push(comp)
      by_comp[comp] = []
    }
    guard by_comp.get(comp) is Some(views)
    for v in views {
      if v.name == vname {
        raise DuplicateView(if comp == "" { vname } else { comp + ":" + vname })
      }
    }
    views.push({ name: vname, source: body, style })
  }
  let components : Array[ViewSet] = []
  for i, comp in order {
    guard by_comp.get(comp) is Some(views)
    // `main` first: it is the view component() adopts by default, and the
    // emitter names it specially.
    let mut main : RawView? = None
    let rest : Array[RawView] = []
    for v in views {
      if v.name == "main" {
        main = Some(v)
      } else {
        rest.push(v)
      }
    }
    guard main is Some(m) else {
      raise NoMainViewFor(if comp == "" { "this file" } else { comp })
    }
    // File-level styles belong to the first component: emitting them per
    // component would duplicate the same CSS under every data-cid.
    components.push({
      name: comp,
      views: [m, ..rest],
      common_style: if i == 0 {
        common_style
      } else {
        ""
      },
      global_style: if i == 0 {
        global_style
      } else {
        ""
      },
    })
  }
  { components, macros }
}

///|
/// `Counter:row` -> ("Counter", "row"); `Counter` -> ("Counter", "main").
/// None when the id names no component — a bare view name, or empty.
///
/// A component name is Uppercase-initial, which is what distinguishes
/// `Counter` (a component) from `row` (a view of the unnamed one).
fn split_qualified(id : String) -> (String, String)? {
  if id == "" {
    return None
  }
  let chars = id.to_array()
  if !(chars[0] >= 'A' && chars[0] <= 'Z') {
    return None
  }
  for i, c in chars {
    if c == ':' {
      let comp = id[:i].to_owned()
      let view = id[i + 1:].to_owned()
      return Some((comp, if view == "" { "main" } else { view }))
    }
  }
  Some((id, "main"))
}

///|
/// The component name for a ViewSet: its own, or the caller's fallback for a
/// file that declares a single unnamed component.
pub fn ViewSet::component_name(self : ViewSet, fallback : String) -> String {
  if self.name == "" {
    fallback
  } else {
    self.name
  }
}

///|
fn collect_style(styles : Array[StyleRegion], kind : StyleKind) -> String {
  let parts : Array[String] = []
  for s in styles {
    if s.kind == kind {
      parts.push(s.text)
    }
  }
  parts.join("\n")
}
