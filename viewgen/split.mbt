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
pub fn split_views(source : String) -> ViewSet raise GenError {
  let chars = source.to_array()
  let tok = @html5.Tokenizer::new(source)
  let styles : Array[StyleRegion] = []
  let templates : Array[TplSpan] = []
  let mut depth = 0
  let mut open_start = 0
  let mut open_id : String? = None
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
            templates.push({ id: open_id, start: open_start, end_: before })
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
  if templates.is_empty() {
    // No templates: the whole file is the main view.
    let src = slice_without_styles(chars, 0, chars.length(), styles)
    return {
      views: [
        {
          name: "main",
          source: dedent(src.trim(chars="\n").to_owned()),
          style: "",
        },
      ],
      common_style,
      global_style,
    }
  }
  if stray is Some(c) {
    raise StrayText(
      "unexpected '\{c}' outside a <template>; with templates present, every view must live inside one",
    )
  }
  let by_name : Map[String, RawView] = Map([])
  let others : Array[RawView] = []
  let mut main : RawView? = None
  for t in templates {
    let name = t.id.unwrap_or("main")
    if by_name.contains(name) {
      raise DuplicateView(name)
    }
    let view : RawView = {
      name,
      source: dedent(
        slice_without_styles(chars, t.start, t.end_, styles)
        .trim(chars="\n")
        .to_owned(),
      ),
      style: styles_within(t.start, t.end_, styles),
    }
    by_name[name] = view
    if name == "main" {
      main = Some(view)
    } else {
      others.push(view)
    }
  }
  guard main is Some(m) else { raise NoMainView }
  { views: [m, ..others], common_style, global_style }
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
