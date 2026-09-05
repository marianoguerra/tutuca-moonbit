// The reader's diagnostics, in one table.
//
// Every one of them names the repair. "not a section" is a verdict the reader
// has to go and act on; "write `logic:` — the section was renamed when it
// stopped living in a `<script>` tag" is the line they needed. The tests
// assert on the MESSAGE for that reason: the code beside it is a constant and
// would stay green while the sentence rotted.

///|
/// The five section names, as a sentence.
fn section_list() -> String {
  let names = []
  for s in Section::all() {
    names.push("`\{s.name()}:`")
  }
  names.join(", ")
}

///|
/// A section name that is nearly one of the five, and the reason it is not.
///
/// The near misses are the ones an author arrives with: the four block types
/// a `.html` card used to carry, and the plurals of the section names.
fn near_miss(name : String) -> String? {
  match name {
    "script" =>
      Some(
        "write `logic:` — the section was renamed when it stopped living in a `<script>` tag",
      )
    "test" =>
      Some("write `tests:` — a section holds every scene, so it is plural")
    "fixture" =>
      Some(
        "write `fixtures:` — a section holds every fixture, so it is plural",
      )
    "views" | "specs" | "logics" =>
      Some(
        "write `\{name[:name.length() - 1]}:` — only `fixtures` and `tests` are plural",
      )
    "state" => Some("write `spec:` — a component's fields are declared there")
    "template" | "templates" | "html" =>
      Some("write `view:` — a `.tutu` file has no templates, it has views")
    _ => None
  }
}

///|
/// A top-level group that is not `<name>:` followed by a block.
fn report_not_a_section(
  src : @report.SourceId,
  span : @report.Span,
  what : String,
) -> @report.Report {
  @report.Report::error("`\{what}` is not a section")
  .with_code("tutu::not_a_section")
  .with_label(
    @report.Label::primary(src, span, message="this is at the top of the file"),
  )
  .with_help(
    "a `.tutu` file holds only \{section_list()} — put this inside one of them",
  )
}

///|
/// A section name nobody declares.
fn report_unknown_section(
  src : @report.SourceId,
  span : @report.Span,
  name : String,
) -> @report.Report {
  let r = @report.Report::error("there is no `\{name}:` section")
    .with_code("tutu::unknown_section")
    .with_label(@report.Label::primary(src, span, message="written here"))
  match near_miss(name) {
    Some(help) => r.with_help(help)
    None => r.with_help("the sections are \{section_list()}, in that order")
  }
}

///|
/// A section header with no block under it.
fn report_section_not_a_block(
  src : @report.SourceId,
  span : @report.Span,
  name : String,
) -> @report.Report {
  @report.Report::error("`\{name}` has no section body")
  .with_code("tutu::section_not_a_block")
  .with_label(@report.Label::primary(src, span, message="nothing is under it"))
  .with_help(
    "write `\{name}:` and indent its declarations under it — a section is a block",
  )
}

///|
/// Two sections with one name.
fn report_duplicate_section(
  src : @report.SourceId,
  span : @report.Span,
  first : @report.Span,
  name : String,
) -> @report.Report {
  @report.Report::error("`\{name}:` is declared twice")
  .with_code("tutu::duplicate_section")
  .with_label(@report.Label::primary(src, span, message="declared again here"))
  .with_label(
    @report.Label::secondary(src, first, message="first declared here"),
  )
  .with_help(
    "move these declarations into the first `\{name}:` — a file has one of each section",
  )
}

///|
/// A section written after one it must precede.
fn report_section_out_of_order(
  src : @report.SourceId,
  span : @report.Span,
  after : @report.Span,
  name : String,
  later : String,
) -> @report.Report {
  @report.Report::error("`\{name}:` comes after `\{later}:`")
  .with_code("tutu::section_out_of_order")
  .with_label(@report.Label::primary(src, span, message="this one is late"))
  .with_label(
    @report.Label::secondary(src, after, message="it belongs above this"),
  )
  .with_help(
    "move `\{name}:` above `\{later}:` — the order is \{section_list()}, so a reader always knows where to look",
  )
}

///|
/// A declaration whose header is neither a name nor a keyword.
fn report_bad_declaration(
  src : @report.SourceId,
  span : @report.Span,
  section : Section,
) -> @report.Report {
  let kind = section.bare_kind()
  let named = if kind.wants_string_name() {
    "a name in quotes, like `\"three rows\":`"
  } else {
    "a name, like `Todos:`"
  }
  @report.Report::error("this is not a declaration")
  .with_code("tutu::bad_declaration")
  .with_label(
    @report.Label::primary(src, span, message="inside `\{section.name()}:`"),
  )
  .with_help(
    "a `\{section.name()}:` declaration starts with \{named} — a \{kind.noun()}, which is what this section holds",
  )
}

///|
/// A keyword declaration in a section that does not take it.
fn report_wrong_section_for(
  src : @report.SourceId,
  span : @report.Span,
  kind : DeclKind,
  found : Section,
  wanted : Array[Section],
) -> @report.Report {
  let names = []
  for s in wanted {
    names.push("`\{s.name()}:`")
  }
  @report.Report::error(
    "a \{kind.noun()} cannot be declared in `\{found.name()}:`",
  )
  .with_code("tutu::wrong_section")
  .with_label(
    @report.Label::primary(src, span, message="declared in the wrong section"),
  )
  .with_help("move it to \{names.join(" or ")}")
}

///|
/// A bare lowercase name where a component or view name belongs.
fn report_not_a_type_name(
  src : @report.SourceId,
  span : @report.Span,
  name : String,
  section : Section,
) -> @report.Report {
  let upper = name[:1].to_owned().to_upper() + name[1:].to_owned()
  @report.Report::error("`\{name}` is not a \{section.bare_kind().noun()} name")
  .with_code("tutu::not_a_type_name")
  .with_label(
    @report.Label::primary(src, span, message="this starts lowercase"),
  )
  .with_help(
    "write `\{upper}:` if it is a \{section.bare_kind().noun()}, or name the kind you meant — `struct`, `enum`, `protocol`",
  )
}

///|
/// A string where an identifier belongs, or the reverse.
fn report_wrong_name_shape(
  src : @report.SourceId,
  span : @report.Span,
  section : Section,
  got_string : Bool,
) -> @report.Report {
  let kind = section.bare_kind()
  if got_string {
    @report.Report::error(
      "a \{kind.noun()} is named by an identifier, not a string",
    )
    .with_code("tutu::wrong_name_shape")
    .with_label(@report.Label::primary(src, span, message="this is in quotes"))
    .with_help(
      "drop the quotes — only a fixture and a scene are named in prose, because their names are sentences",
    )
  } else {
    @report.Report::error("a \{kind.noun()} is named by a string")
    .with_code("tutu::wrong_name_shape")
    .with_label(@report.Label::primary(src, span, message="this is bare"))
    .with_help(
      "put the name in quotes, like `\"three rows\":` — a \{kind.noun()} name is prose",
    )
  }
}

///|
/// A declaration with a header and nothing under it.
fn report_declaration_has_no_body(
  src : @report.SourceId,
  span : @report.Span,
  kind : DeclKind,
  name : String,
) -> @report.Report {
  @report.Report::error("`\{name}` declares nothing")
  .with_code("tutu::empty_declaration")
  .with_label(@report.Label::primary(src, span, message="no block follows it"))
  .with_help(
    "end the line with `:` and indent what the \{kind.noun()} holds under it",
  )
}

///|
/// A `struct` with no field list.
fn report_struct_has_no_fields(
  src : @report.SourceId,
  span : @report.Span,
  name : String,
) -> @report.Report {
  @report.Report::error("`\{name}` declares no fields")
  .with_code("tutu::struct_has_no_fields")
  .with_label(
    @report.Label::primary(src, span, message="no field list follows it"),
  )
  .with_help(
    "write the fields in parentheses, like `struct \{name}(what :: String, qty :: Int)`",
  )
}

///|
/// A keyword declaration missing the name after the keyword.
fn report_missing_name(
  src : @report.SourceId,
  span : @report.Span,
  keyword : String,
) -> @report.Report {
  @report.Report::error("`\{keyword}` has no name")
  .with_code("tutu::missing_name")
  .with_label(@report.Label::primary(src, span, message="a name goes here"))
  .with_help("write the name after `\{keyword}`, like `\{keyword} Line`")
}

///|
/// A file with no sections at all.
fn report_empty_file(src : @report.SourceId) -> @report.Report {
  @report.Report::error("this file declares nothing")
  .with_code("tutu::empty_file")
  .with_label(@report.Label::primary(src, @report.Span::at(0)))
  .with_help(
    "a `.tutu` file opens with a section — \{section_list()}, in that order",
  )
}
