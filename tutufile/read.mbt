// The reader. Shrubbery gives the tree; this decides which parts of it are
// sections, which are declarations, and what to say when they are neither.

///|
/// Read a `.tutu` file.
///
/// `source` is the id the text was registered under in the caller's
/// `Sources`, and every span in every report is an offset into that text — so
/// a caller renders the reports without this package knowing whether it is
/// writing to a terminal, a JSON stream or a browser pane.
///
/// Nothing raises. A file that cannot be parsed at all comes back with no
/// sections and the parse failure in `reports`, which is the same shape as a
/// file that parsed with one bad section.
pub fn read(text : String, source : @report.SourceId) -> TutuFile {
  let reports = []
  let parsed = @shrub.parse(text, recover=true) catch {
    err => {
      reports.push(@shrub.to_report(err.diagnostic(), source))
      return { source, root: None, sections: [], reports, }
    }
  }
  for d in parsed.diagnostics() {
    reports.push(@shrub.to_report(d, source))
  }
  let root = parsed.root()
  let sections = read_sections(root, source, reports)
  { source, root: Some(root), sections, reports, }
}

///|
/// The top level: a `multi` of groups, each of them `<name>:` and a block.
fn read_sections(
  root : @ast.Node,
  source : @report.SourceId,
  reports : Array[@report.Report],
) -> Array[SectionBlock] {
  let groups = match root.it {
    Multi(gs) => gs
    Group(_) => [root]
    _ => []
  }
  if groups.is_empty() {
    reports.push(report_empty_file(source))
    return []
  }
  let out = []
  for group in groups {
    guard group.it is Group(parts) else {
      reports.push(report_not_a_section(source, span_of(group), text_of(group)))
      continue
    }
    guard !parts.is_empty() else { continue }
    let head = parts[0]
    guard head.it is Id(name) else {
      reports.push(report_not_a_section(source, span_of(head), text_of(head)))
      continue
    }
    guard Section::of_name(name) is Some(section) else {
      reports.push(report_unknown_section(source, span_of(head), name))
      continue
    }
    guard last_block(parts) is Some(body) else {
      reports.push(report_section_not_a_block(source, span_of(group), name))
      continue
    }
    guard earlier(out, section) is None else {
      let first = earlier(out, section).unwrap()
      reports.push(
        report_duplicate_section(source, span_of(head), first.span, name),
      )
      continue
    }
    match out_of_order(out, section) {
      Some(later) =>
        reports.push(
          report_section_out_of_order(
            source,
            span_of(head),
            later.span,
            name,
            later.section.name(),
          ),
        )
      None => ()
    }
    out.push({
      section,
      span: span_of(head),
      decls: read_decls(body, section, source, reports),
    })
  }
  out
}

///|
/// One section's declarations.
fn read_decls(
  body : @ast.Node,
  section : Section,
  source : @report.SourceId,
  reports : Array[@report.Report],
) -> Array[Decl] {
  let out = []
  guard body.it is Block(groups) else { return out }
  for group in groups {
    match read_decl(group, section, source, reports) {
      Some(d) => out.push(d)
      None => ()
    }
  }
  out
}

///|
/// One declaration: a keyword one if its head names a kind, and the section's
/// own kind otherwise.
fn read_decl(
  group : @ast.Node,
  section : Section,
  source : @report.SourceId,
  reports : Array[@report.Report],
) -> Decl? {
  guard group.it is Group(parts) else {
    reports.push(report_bad_declaration(source, span_of(group), section))
    return None
  }
  guard !parts.is_empty() else { return None }
  let head = parts[0]
  match head.it {
    Id(word) =>
      match keyword_kind(word) {
        Some(kind) => keyword_decl(group, parts, kind, section, source, reports)
        None => bare_decl(group, parts, section, source, reports)
      }
    Lit(Str(_)) => bare_decl(group, parts, section, source, reports)
    _ => {
      reports.push(report_bad_declaration(source, span_of(head), section))
      None
    }
  }
}

///|
/// A declaration written with no keyword: the section's own kind.
fn bare_decl(
  group : @ast.Node,
  parts : Array[@ast.Node],
  section : Section,
  source : @report.SourceId,
  reports : Array[@report.Report],
) -> Decl? {
  let kind = section.bare_kind()
  let head = parts[0]
  let name = match head.it {
    Id(n) =>
      if kind.wants_string_name() {
        reports.push(
          report_wrong_name_shape(source, span_of(head), section, false),
        )
        return None
      } else if is_upper_start(n) {
        n
      } else {
        reports.push(report_not_a_type_name(source, span_of(head), n, section))
        return None
      }
    Lit(Str(n)) =>
      if kind.wants_string_name() {
        n
      } else {
        reports.push(
          report_wrong_name_shape(source, span_of(head), section, true),
        )
        return None
      }
    _ => {
      reports.push(report_bad_declaration(source, span_of(head), section))
      return None
    }
  }
  // A view may be named `Comp.view`, which reads as three terms rather than
  // one: the section's own kind carries a sub-name where nothing else does.
  let name = name + view_suffix(parts, kind)
  guard last_block(parts) is Some(body) else {
    reports.push(
      report_declaration_has_no_body(source, span_of(group), kind, name),
    )
    return None
  }
  Some({
    kind,
    name,
    options: options_of(parts),
    header: span_of(head),
    span: span_of(group),
    node: group,
    body: Some(body),
  })
}

///|
/// The `.view` half of a `Comp.view` name, or the empty string.
///
/// Only a view has one. A component is one component whatever its views are
/// called, and a fixture and a scene are named in prose, so neither has a
/// place to put a second name.
fn view_suffix(parts : Array[@ast.Node], kind : DeclKind) -> String {
  guard kind is View else { return "" }
  guard parts.length() > 2 else { return "" }
  guard parts[1].it is Op(".") else { return "" }
  guard parts[2].it is Id(sub) else { return "" }
  "." + sub
}

///|
/// A declaration written with its own keyword: `struct`, `enum`, `protocol`,
/// `macro`, or the `@style{…}` block a view section may hold.
fn keyword_decl(
  group : @ast.Node,
  parts : Array[@ast.Node],
  kind : DeclKind,
  section : Section,
  source : @report.SourceId,
  reports : Array[@report.Report],
) -> Decl? {
  let head = parts[0]
  let wanted = sections_for(kind)
  guard wanted.contains(section) else {
    reports.push(
      report_wrong_section_for(source, span_of(group), kind, section, wanted),
    )
    return None
  }
  if kind is Style {
    return Some({
      kind,
      name: "",
      options: options_of(parts),
      header: span_of(head),
      span: span_of(group),
      node: group,
      body: None,
    })
  }
  guard parts.length() > 1 && parts[1].it is Id(name) else {
    reports.push(report_missing_name(source, span_of(head), kind.keyword()))
    return None
  }
  let body = last_block(parts)
  if kind is Struct {
    guard parts.length() > 2 && parts[2].it is Parens(_) else {
      reports.push(report_struct_has_no_fields(source, span_of(group), name))
      return None
    }
  } else if body is None {
    reports.push(
      report_declaration_has_no_body(source, span_of(group), kind, name),
    )
    return None
  }
  Some({
    kind,
    name,
    options: options_of(parts),
    header: span_of(head).merge(span_of(parts[1])),
    span: span_of(group),
    node: group,
    body,
  })
}

///|
/// The kind a leading word names, if it names one.
fn keyword_kind(word : String) -> DeclKind? {
  match word {
    "struct" => Some(Struct)
    "enum" => Some(Enum)
    "protocol" => Some(Protocol)
    "macro" => Some(Macro)
    "style" => Some(Style)
    _ => None
  }
}

///|
/// Where a keyword declaration is allowed to appear.
fn sections_for(kind : DeclKind) -> Array[Section] {
  match kind {
    Struct | Enum | Protocol => [Spec]
    Macro | Style => [View]
    Component | View | Fixture | Scene => []
  }
}

///|
/// The `~name` options written on a declaration's header.
fn options_of(parts : Array[@ast.Node]) -> Array[String] {
  let out = []
  for p in parts {
    if p.it is Kw(name) {
      out.push(name)
    }
  }
  out
}

///|
/// The block a group ends with, if it ends with one.
fn last_block(parts : Array[@ast.Node]) -> @ast.Node? {
  let last = parts[parts.length() - 1]
  if last.it is Block(_) {
    Some(last)
  } else {
    None
  }
}

///|
/// The section already read under this name, if any.
fn earlier(read : Array[SectionBlock], want : Section) -> SectionBlock? {
  for s in read {
    if s.section == want {
      return Some(s)
    }
  }
  None
}

///|
/// The first section already read that this one belongs above.
fn out_of_order(read : Array[SectionBlock], want : Section) -> SectionBlock? {
  let order = Section::all()
  let rank = fn(s : Section) -> Int {
    let mut i = 0
    for o in order {
      if o == s {
        return i
      }
      i = i + 1
    }
    i
  }
  for s in read {
    if rank(s.section) > rank(want) {
      return Some(s)
    }
  }
  None
}

///|
/// A shrubbery span as an offset span into the file.
fn span_of(node : @ast.Node) -> @report.Span {
  @report.Span::of_range(node.span.start.idx, node.span.end.idx)
}

///|
/// What a node reads as, for a message that has to quote it.
fn text_of(node : @ast.Node) -> String {
  match node.it {
    Id(s) | Op(s) | Kw(s) => s
    Lit(Str(s)) => s
    _ => node.it.tag()
  }
}

///|
/// Whether a name is written the way a component, view, record or enum is.
fn is_upper_start(name : String) -> Bool {
  guard name.length() > 0 else { return false }
  let c = name.get_char(0)
  c is Some(ch) && ch >= 'A' && ch <= 'Z'
}
