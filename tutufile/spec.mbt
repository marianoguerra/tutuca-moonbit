// Spec for the `.tutu` reader: the public data types. The implementation
// lives in read.mbt and the messages in errors.mbt.
//
//   source text --read--> TutuFile   (five sections, their declarations)
//
// One stage, and it is the only one that knows what a `.tutu` FILE looks
// like. It does not know what a component, a view, a fixture or a scene is
// written in — each section's body is handed on as the shrubbery tree it
// parsed to. That asymmetry is the same one `viewfile` makes for the script
// block and it is deliberate: the section languages have their own readers,
// and a file splitter that also parsed them would be the only thing in the
// pipeline that had to change when any of them did.

///|
/// One of the five sections of a `.tutu` file, in the order they are written.
///
/// The order is fixed rather than conventional. A section is a place to look,
/// and a place that moves is not one — so `tests` after `fixtures` is a rule
/// the reader enforces rather than a habit the formatter encourages.
pub(all) enum Section {
  Spec
  Logic
  View
  Fixtures
  Tests
} derive(Eq, Compare, Hash, @debug.Debug)

///|
/// What a declaration inside a section is.
///
/// `Component`, `View`, `Fixture` and `Scene` are the four kinds written with
/// no keyword at all: each is the primary kind of the section it appears in,
/// so the section says what it is and writing the word again would say it
/// twice. Everything else names itself.
pub(all) enum DeclKind {
  Component
  View
  Fixture
  Scene
  Struct
  Enum
  Protocol
  Macro
  Style
} derive(Eq, @debug.Debug)

///|
/// One declaration recovered from a section.
///
/// `body` is the shrubbery block under the header, unread — a `Component`'s
/// fields and rules, a `View`'s markup, a `Scene`'s steps. A `Struct` has
/// none: its fields are the parenthesised list in its header, which is why
/// the two are separate fields rather than one "the rest of it".
pub(all) struct Decl {
  kind : DeclKind
  name : String
  options : Array[String]
  header : @report.Span
  span : @report.Span
  node : @ast.Node
  body : @ast.Node?
}

///|
/// One section, with the declarations it holds in source order.
pub(all) struct SectionBlock {
  section : Section
  span : @report.Span
  decls : Array[Decl]
}

///|
/// A `.tutu` file as read: the sections that parsed, and everything wrong
/// with the ones that did not.
///
/// Both halves always come back. A file with a bad `logic` section still
/// reports its `view` declarations, because an author fixing one section
/// should not lose the diagnostics for the next — and a tool that only wanted
/// the shape of the file gets it from a file that does not yet compile.
pub(all) struct TutuFile {
  source : @report.SourceId
  root : @ast.Node?
  sections : Array[SectionBlock]
  reports : Array[@report.Report]
}

///|
/// The section's name, which is also how it is written.
pub fn Section::name(self : Section) -> String {
  match self {
    Spec => "spec"
    Logic => "logic"
    View => "view"
    Fixtures => "fixtures"
    Tests => "tests"
  }
}

///|
/// The five, in the order a file writes them.
pub fn Section::all() -> Array[Section] {
  [Spec, Logic, View, Fixtures, Tests]
}

///|
/// The section a name spells, or nothing.
pub fn Section::of_name(name : String) -> Section? {
  for s in Section::all() {
    if s.name() == name {
      return Some(s)
    }
  }
  None
}

///|
/// The kind a section's bare declarations are: `Todos:` in `spec` is a
/// component, the same line in `view` is a view.
pub fn Section::bare_kind(self : Section) -> DeclKind {
  match self {
    Spec | Logic => Component
    View => View
    Fixtures => Fixture
    Tests => Scene
  }
}

///|
/// How a declaration of this kind is named: by an identifier, or by a string.
///
/// A fixture and a scene are named in prose — "a fixture is where a scene
/// starts" is a name — so they carry a string where the others carry an
/// identifier, and neither can be mistaken for the other.
pub fn DeclKind::wants_string_name(self : DeclKind) -> Bool {
  self is (Fixture | Scene)
}

///|
/// The word a declaration of this kind is written with, or the empty string
/// for the four that take the section's word.
pub fn DeclKind::keyword(self : DeclKind) -> String {
  match self {
    Struct => "struct"
    Enum => "enum"
    Protocol => "protocol"
    Macro => "macro"
    Style => "style"
    Component | View | Fixture | Scene => ""
  }
}

///|
/// What a declaration of this kind is called in a message.
pub fn DeclKind::noun(self : DeclKind) -> String {
  match self {
    Component => "component"
    View => "view"
    Fixture => "fixture"
    Scene => "scene"
    Struct => "struct"
    Enum => "enum"
    Protocol => "protocol"
    Macro => "macro"
    Style => "style block"
  }
}

///|
/// Whether the file read with nothing to report.
pub fn TutuFile::ok(self : TutuFile) -> Bool {
  for r in self.reports {
    if r.severity is Error {
      return false
    }
  }
  true
}

///|
/// One section by name, if the file has it.
pub fn TutuFile::section(self : TutuFile, want : Section) -> SectionBlock? {
  for s in self.sections {
    if s.section == want {
      return Some(s)
    }
  }
  None
}

///|
/// One declaration, by section and name.
pub fn TutuFile::decl(
  self : TutuFile,
  section : Section,
  name : String,
) -> Decl? {
  guard self.section(section) is Some(block) else { return None }
  for d in block.decls {
    if d.name == name {
      return Some(d)
    }
  }
  None
}

///|
/// The names declared in a section, in source order. The outline a reader
/// wants, and what the CLI prints.
pub fn SectionBlock::names(self : SectionBlock) -> Array[String] {
  let out = []
  for d in self.decls {
    out.push(d.name)
  }
  out
}
