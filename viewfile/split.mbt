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
/// The `type=` that marks a `<script>` as the file's state schema.
///
/// A `<script>` and not a `<template>`: script content is RAW TEXT to an HTML
/// parser, template content is markup — and the schema is full of `<` and
/// `>`, so `list<s32>` inside a template would be read as an `<s32>` element.
const STATE_TYPE = "tutuca/state"

///|
/// The `type=` that marks a `<script>` as the file's named initial states.
///
/// Separate from the schema because a default is a value, not a type: WIT
/// has no defaults, and smuggling them into it through a comment convention
/// would make the schema mean two things. Keeping them apart is also what
/// lets several fixtures share one state type.
const INIT_TYPE = "tutuca/init"

///|
/// The `type=` that marks a `<script>` as the file's handlers.
///
/// A `<script>` for the same reason the schema is one — the language has `<`,
/// `>` and `and`, none of which would survive being read as markup — and it
/// buys the thing the WIT block cannot have: the block is sliced out of the
/// original source with its offset intact, so every declaration in it carries
/// a real span from the first commit.
const SCRIPT_TYPE = "tutuca/script"

///|
/// The `type=` that marks a `<script>` as hand-written Wax — the ESCAPE HATCH.
///
/// The ahead-of-time path has had one for as long as it has refused anything:
/// a handler `gen-views` cannot compile comes back by name as an `update~`
/// argument, and you write it in MoonBit. The compiled path refused by name
/// too and handed back nothing at all, which is the difference this block
/// closes — a card whose handler the generator turns away can answer it in the
/// language the module is built out of.
///
/// Lifted here and read by NOBODY but `tutucard/wasm`. It is inert everywhere
/// else: the interpreter has no Wax to run and `gen-views` has no wasm to put
/// it in, so a file carrying one is a file with a block those two ignore.
///
/// A `<script>` for the third time and for the same reason: Wax is full of
/// `<`, `>` and `&`, none of which would survive being read as markup.
const WAX_TYPE = "tutuca/wax"

///|
/// The `type=` that marks a `<script>` as the file's scenes.
///
/// JSON, the way the init block is, and for the same two reasons: a block a
/// machine has to write is a block with a grammar a machine already has, and a
/// block validated where the file is SPLIT puts a mistake on the line of the
/// `.html` the author has open rather than on a line of the block.
///
/// What it says is the card's tests. Whether anything runs them is a property
/// of the consumer rather than of the file: `tutucard` drives a scene on the
/// in-memory DOM and `gen-views` ignores the block entirely — exactly as it
/// ignores `tutuca/wax` — which is what makes this additive rather than a
/// fifth thing every backend has to answer for.
const TEST_TYPE = "tutuca/test"

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
  // A `tutuca/state`, `tutuca/init` or `tutuca/script` block. Not a style at
  // all — it rides
  // in this list because the list IS the set of spans lifted out of view
  // source, and a file with no templates is otherwise its own main view,
  // schema included.
  SLifted
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
///
/// Copies the runs BETWEEN the regions rather than walking char by char and
/// re-scanning every region at each one: that cost `chars × regions` per view,
/// so the whole file cost `chars × regions`, quadratic in a view file's size
/// (both factors grow with it). One `from_array` per run, at most one run more
/// than there are regions in the span.
fn slice_without_styles(
  chars : Array[Char],
  start : Int,
  end_ : Int,
  styles : Array[StyleRegion],
) -> String {
  let sb = StringBuilder()
  let mut i = start
  for s in styles {
    // Before the span (or inside a region already skipped — regions never
    // overlap, so `i` is only ever past one that has been jumped).
    if s.start < i {
      continue
    }
    // In source order, so nothing after this one starts inside the span.
    if s.start >= end_ {
      break
    }
    sb.write_string(String::from_array(chars[i:s.start]))
    i = s.end_
  }
  // A region may end past the span; then there is no trailing run.
  if i < end_ {
    sb.write_string(String::from_array(chars[i:end_]))
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
    if s.kind != SLifted && s.start >= start && s.start < end_ {
      parts.push(s.text)
    }
  }
  parts.join("\n")
}

///|
/// Read a raw-text element's content up to its end tag. The bare tokenizer
/// does not enter RAWTEXT on its own (the tree builder normally drives that),
/// so we switch it ourselves — which is what keeps a `<` inside CSS, or
/// inside a `list<s32>`, from being read as a tag.
fn read_raw(tok : @html5.Tokenizer, tag : String) -> (String, Int) {
  tok.switch_to_rawtext()
  let sb = StringBuilder()
  let mut end_ = tok.get_position().offset
  let mut done = false
  while !done {
    let before = tok.get_position().offset
    match tok.next_token() {
      Character(c) => sb.write_char(c)
      EndTag(name~) =>
        if name == tag {
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
/// True when nothing but whitespace and HTML comments is left.
///
/// A comment above the schema must not turn a schema-only file back into a
/// view: the note explaining why a file has no templates is exactly the kind
/// of thing someone writes there.
fn is_blank(src : String) -> Bool {
  let chars = src.to_array()
  let mut i = 0
  while i < chars.length() {
    if is_space(chars[i]) {
      i = i + 1
    } else if i + 3 < chars.length() &&
      chars[i] == '<' &&
      chars[i + 1] == '!' &&
      chars[i + 2] == '-' &&
      chars[i + 3] == '-' {
      let mut j = i + 4
      while j + 2 < chars.length() &&
            !(chars[j] == '-' && chars[j + 1] == '-' && chars[j + 2] == '>') {
        j = j + 1
      }
      i = if j + 2 < chars.length() { j + 3 } else { chars.length() }
    } else {
      return false
    }
  }
  true
}

///|
/// The 1-based line `offset` falls on, for a diagnostic that points at the
/// file the author edits rather than at the block we sliced out of it.
fn line_at(chars : Array[Char], offset : Int) -> Int {
  let mut line = 1
  let n = if offset < chars.length() { offset } else { chars.length() }
  for i in 0..<n {
    if chars[i] == '\n' {
      line = line + 1
    }
  }
  line
}

///|
pub fn split_file(
  source : String,
  name? : String = "",
) -> ViewFile raise FileError {
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
  let mut state_src : (String, Int)? = None
  let mut init_src : (String, Int)? = None
  let mut test_src : (String, Int)? = None
  let script_srcs : Array[(String, String, Int)] = []
  let wax_srcs : Array[(String, String, Int)] = []
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
          // The state schema. Consumed here rather than left to the
          // Character arm below, so its `<` and `>` never reach the
          // tokenizer as markup and its text never counts as stray.
          "script" if attr_of(attrs, "type") is Some(STATE_TYPE) => {
            let content_at = after
            let (text, end_) = read_raw(tok, "script")
            if state_src is Some(_) {
              raise DuplicateStateBlock
            }
            state_src = Some((text, content_at))
            styles.push({ start: before, end_, text: "", kind: SLifted })
          }
          "script" if attr_of(attrs, "type") is Some(INIT_TYPE) => {
            let content_at = after
            let (text, end_) = read_raw(tok, "script")
            init_src = Some((text, content_at))
            styles.push({ start: before, end_, text: "", kind: SLifted })
          }
          // The handlers. Lifted out unparsed: checking them needs the schema
          // and the argument types the views imply, and neither is in hand
          // here.
          "script" if attr_of(attrs, "type") is Some(SCRIPT_TYPE) => {
            let content_at = after
            let (text, end_) = read_raw(tok, "script")
            // `for=` names the component, the way a template id does. Absent
            // is the file's single component, and two blocks claiming the same
            // name is the same failure as two templates claiming one view.
            let for_comp = match attr_of(attrs, "for") {
              Some(c) => c
              None => ""
            }
            if script_srcs.iter().any(t => t.0 == for_comp) {
              raise DuplicateScriptBlock(for_comp)
            }
            script_srcs.push((for_comp, text, content_at))
            styles.push({ start: before, end_, text: "", kind: SLifted })
          }
          // The escape hatch. Lifted exactly as the handlers are, and for the
          // same reason: what it says can only be judged by a backend that has
          // the module in front of it, and only one backend has one.
          "script" if attr_of(attrs, "type") is Some(WAX_TYPE) => {
            let content_at = after
            let (text, end_) = read_raw(tok, "script")
            let for_comp = match attr_of(attrs, "for") {
              Some(c) => c
              None => ""
            }
            if wax_srcs.iter().any(t => t.0 == for_comp) {
              raise DuplicateWaxBlock(for_comp)
            }
            wax_srcs.push((for_comp, text, content_at))
            styles.push({ start: before, end_, text: "", kind: SLifted })
          }
          // The scenes. Parsed here, the way the init block is, because a
          // scene block IS self-contained: JSON in, `Scene`s out, and the only
          // thing this adds is the line map that puts a mistake on the file
          // the author has open. It carries no `for=`: a scene NAMES the
          // component it mounts, because a card with two of them has scenes
          // that drive one and scenes that drive the other, and splitting the
          // block per component would say the second could not exist.
          "script" if attr_of(attrs, "type") is Some(TEST_TYPE) => {
            let content_at = after
            let (text, end_) = read_raw(tok, "script")
            if test_src is Some(_) {
              raise DuplicateTestBlock
            }
            test_src = Some((text, content_at))
            styles.push({ start: before, end_, text: "", kind: SLifted })
          }
          "style" => {
            let (text, end_) = read_raw(tok, "style")
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
  let state = parse_state_block(chars, state_src, name)
  let init = parse_init_block(chars, init_src, state)
  let tests = parse_test_block(chars, test_src)
  let scripts = script_blocks(chars, script_srcs)
  // The same shape, and deliberately the same function: an escape block is a
  // script block that happens to be in another language.
  let wax = script_blocks(chars, wax_srcs)
  // No templates at all: the file IS one unnamed component's main view —
  // unless nothing is left once the schema is lifted out, which is a
  // SCHEMA-ONLY file. Those exist so a component whose views are built at
  // runtime (a macro user, a dynamically assembled view) can still declare
  // its state.
  if templates.is_empty() {
    let src = slice_without_styles(chars, 0, chars.length(), styles)
    if is_blank(src) {
      return {
        components: [],
        macros: [],
        state,
        init,
        scripts,
        wax,
        tests,
        root: "",
      }
    }
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
      state,
      init,
      scripts,
      wax,
      tests,
      root: "",
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
  let mut root_marked : String? = None
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
    // `data-root` names the component a host mounts when it is told no other
    // name. Absent from every card ever written, and absent from most that will
    // be: a file's FIRST component is the root, which is the only answer a card
    // with one has and the obvious one for a card whose list comes first. The
    // marker exists for the file where it does not — a `TodoItem` declared
    // above the `TodoList` that renders it, because that is the order the
    // author found readable.
    for a in t.attrs {
      if a.name == "data-root" {
        if root_marked is Some(other) {
          raise TwoRoots(other, comp)
        }
        root_marked = Some(comp)
      }
    }
    // One lookup, not a `contains` followed by a `get` that had to be guarded
    // against the None the `contains` already ruled out. `order` is appended to
    // in the same breath as the map, which is the pairing the loop below reads.
    let views = match by_comp.get(comp) {
      Some(vs) => vs
      None => {
        let vs : Array[RawView] = []
        order.push(comp)
        by_comp[comp] = vs
        vs
      }
    }
    for v in views {
      if v.name == vname {
        raise DuplicateView(if comp == "" { vname } else { comp + ":" + vname })
      }
    }
    views.push({ name: vname, source: body, style })
  }
  let components : Array[ViewSet] = []
  for i, comp in order {
    // `order` exists only to give the map a stable iteration order, and a name
    // lands in it in the same statement that creates its bucket above — so a
    // miss here would mean the two had drifted apart, which is a bug rather
    // than a case to handle.
    guard! by_comp.get(comp) is Some(views)
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
  {
    components,
    macros,
    state,
    init,
    scripts,
    wax,
    tests,
    root: root_marked.unwrap_or(""),
  }
}

///|
/// Parse the state block, mapping a schema error onto the line of the HTML
/// file the author edits.
///
/// The block's own offsets are exact (statedef prepends nothing), so the
/// file line is the block's start line plus the newlines before the error.
fn parse_state_block(
  chars : Array[Char],
  src : (String, Int)?,
  name : String,
) -> Array[@statedef.StateDef] raise FileError {
  guard src is Some((text, at)) else { return [] }
  // The fallback names a bare `state { … }`, and the name prefixes every
  // generated type — so it has to arrive here rather than at emit time.
  @statedef.parse_state(text, name~) catch {
    e => {
      // Every failure carries its own span now, so the file line is the
      // block's start line plus the newlines before it. What this replaced was
      // a whole-word scanner: mizchi/wit carried no positions, so a semantic
      // error named an IDENTIFIER and this function went looking for it —
      // landing on the right line and never the right column.
      let within = line_at(text.to_array(), e.span().start) - 1
      raise BadStateBlock(line=line_at(chars, at) + within, message=e.message())
    }
  }
}

///|
/// Parse the init block against the schema, mapping an error onto the line
/// of the HTML file.
fn parse_init_block(
  chars : Array[Char],
  src : (String, Int)?,
  state : Array[@statedef.StateDef],
) -> Array[(String, @statedef.InitState)] raise FileError {
  guard src is Some((text, at)) else { return [] }
  guard !state.is_empty() else {
    raise BadInitBlock(
      line=line_at(chars, at),
      message="an init block needs a <script type=\"tutuca/state\"> schema to check against",
    )
  }
  // One schema per component, so a fixture belongs to whichever component
  // its fields fit. With a single component — the common case — that is the
  // only one there is.
  let out : Array[(String, @statedef.InitState)] = []
  for def in state {
    let states = @statedef.parse_init(text, def) catch {
      e => raise BadInitBlock(line=line_at(chars, at), message=e.message())
    }
    for st in states {
      out.push((def.component, st))
    }
  }
  out
}

///|
/// Parse the test block, mapping an error onto the line of the HTML file.
///
/// Unlike the init block this needs no schema: a scene names selectors and
/// message names, and neither is checkable against a state record. What it
/// DOES check is the shape — the verbs, the readers, the selectors and the
/// places — which is the half a machine writing one gets wrong.
fn parse_test_block(
  chars : Array[Char],
  src : (String, Int)?,
) -> Array[@scenedef.Scene] raise FileError {
  guard src is Some((text, at)) else { return [] }
  @scenedef.parse_scenes(text) catch {
    e => raise BadTestBlock(line=line_at(chars, at), message=e.message())
  }
}

///|
/// The script blocks as raw text plus where each started.
///
/// No parse and no failure: a block that does not parse is a failure of the
/// LANGUAGE, reported by whoever type-checks it against a schema, and saying
/// so here would mean carrying a checker into a package whose whole job is
/// finding element boundaries.
fn script_blocks(
  chars : Array[Char],
  srcs : Array[(String, String, Int)],
) -> Array[ScriptBlock] {
  srcs.map(t => {
    comp: t.0,
    block: { text: t.1, offset: t.2, line: line_at(chars, t.2) },
  })
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

///|
/// The script block for one component, or None when the file writes none.
///
/// A bare block answers for the file's single component: a file with one
/// component has nothing to disambiguate, so making it write the name would be
/// ceremony for a fact the file already states once.
pub fn ViewFile::script_for(self : ViewFile, comp : String) -> Block? {
  for s in self.scripts {
    if s.comp == comp {
      return Some(s.block)
    }
  }
  if self.scripts.length() == 1 && self.scripts[0].comp == "" {
    return Some(self.scripts[0].block)
  }
  None
}

///|
/// The hand-written Wax for one component, or None when the file writes none.
///
/// The same rule `script_for` follows, down to the bare-block case: an escape
/// block is a script block in another language, so it is looked up the same way
/// or the two would disagree about which component an unqualified block is
/// about.
pub fn ViewFile::wax_for(self : ViewFile, comp : String) -> Block? {
  for s in self.wax {
    if s.comp == comp {
      return Some(s.block)
    }
  }
  if self.wax.length() == 1 && self.wax[0].comp == "" {
    return Some(self.wax[0].block)
  }
  None
}
