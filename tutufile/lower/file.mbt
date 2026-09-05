// The whole file: five sections in, the four blocks and the templates out.

///|
/// A lowered `.tutu` file, and everything that could not be lowered.
pub(all) struct Lowered {
  text : String
  reports : Array[@report.Report]
}

///|
/// Lower a `.tutu` source into the `.html` the front end reads.
///
/// Nothing raises: a section that cannot be lowered contributes its report
/// and nothing else, so a file with one bad handler still produces the blocks
/// around it and an author fixing one is not hiding the next.
pub fn lower(text : String, source : @report.SourceId) -> Lowered {
  let file = @tutufile.read(text, source)
  let reports = []
  for r in file.reports {
    reports.push(r)
  }
  let out = StringBuilder()
  // the logic section is read first: the spec block spells a property with
  // what implements it, and only the logic section knows that
  let logic_text = StringBuilder()
  let impls : Map[String, Map[String, PropImpl]] = Map([])
  match file.section(Logic) {
    Some(section) =>
      for decl in section.decls {
        let body = StringBuilder()
        try {
          let found = print_logic(decl, body)
          impls[decl.name] = found
          logic_text.write_string(
            "<script type=\"tutuca/script\" for=\"\{decl.name}\">\n",
          )
          logic_text.write_string(body.to_string())
          logic_text.write_string("</script>\n\n")
        } catch {
          e => reports.push(ex_report(e, source, fallback=decl.span))
        }
      }
    None => ()
  }
  match file.section(Spec) {
    Some(section) => {
      out.write_string("<script type=\"tutuca/spec\">\n")
      for decl in section.decls {
        let body = StringBuilder()
        try {
          match decl.kind {
            Component =>
              print_state(decl, impls.get(decl.name).unwrap_or(Map([])), body)
            Struct => print_struct(decl, body)
            Enum => print_enum(decl, body)
            Protocol => print_protocol(decl, body)
            _ => ()
          }
          out.write_string(body.to_string())
          if decl.kind is Component {
            let ch = StringBuilder()
            print_channels(decl, ch)
            out.write_string(ch.to_string())
          }
        } catch {
          e => reports.push(ex_report(e, source, fallback=decl.span))
        }
      }
      out.write_string("</script>\n\n")
    }
    None => ()
  }
  out.write_string(logic_text.to_string())
  match file.section(Fixtures) {
    Some(section) =>
      try {
        let json = print_fixtures(section.decls)
        out.write_string("<script type=\"tutuca/fixtures\">\n")
        out.write_string(json)
        out.write_string("\n</script>\n\n")
      } catch {
        e => reports.push(ex_report(e, source, fallback=section.span))
      }
    None => ()
  }
  match file.section(Tests) {
    Some(section) =>
      try {
        let json = print_scenes(section.decls)
        out.write_string("<script type=\"tutuca/test\">\n")
        out.write_string(json)
        out.write_string("\n</script>\n\n")
      } catch {
        e => reports.push(ex_report(e, source, fallback=section.span))
      }
    None => ()
  }
  match file.section(View) {
    Some(section) =>
      for decl in section.decls {
        let body = StringBuilder()
        match decl.kind {
          View =>
            try {
              print_view(decl, body)
              out.write_string(body.to_string())
            } catch {
              e => reports.push(ex_report(e, source, fallback=decl.span))
            }
          Style =>
            try {
              print_file_style(decl, body)
              out.write_string(body.to_string())
            } catch {
              e => reports.push(ex_report(e, source, fallback=decl.span))
            }
          Macro =>
            try {
              print_macro(decl, body)
              out.write_string(body.to_string())
            } catch {
              e => reports.push(ex_report(e, source, fallback=decl.span))
            }
          _ => ()
        }
      }
    None => ()
  }
  { text: out.to_string(), reports, }
}

///|
/// A file-level `@style{…}`, which is the component's common style.
fn print_file_style(
  decl : @tutufile.Decl,
  out : StringBuilder,
) -> Unit raise ExError {
  guard decl.node.it is Group(parts) else { return }
  print_element("style", parts, out, "", {})
  out.write_string("\n")
}

///|
/// `macro badge(~label: "New"): …` → the `macro:` template it was.
fn print_macro(
  decl : @tutufile.Decl,
  out : StringBuilder,
) -> Unit raise ExError {
  let m = read_member(decl.node)
  let attrs = []
  for p in m.params {
    attrs.push("data-\{attr_name(p.name)}=\"\"")
  }
  // a macro's defaults are written as its parameters' initialisers
  guard decl.node.it is Group(parts) else { return }
  let defaults = []
  for t in parts {
    if t.it is Parens(gs) {
      for g in gs {
        try {
          for a in read_args([g]) {
            match a {
              AKw(name, value) =>
                defaults.push(
                  "data-\{attr_name(name)}=\"\{attr_escape(print_ex(value))}\"",
                )
              _ => ()
            }
          }
        } catch {
          _ => ()
        }
      }
      break
    }
  }
  let head = if defaults.is_empty() { attrs } else { defaults }
  let joined = if head.is_empty() { "" } else { " " + head.join(" ") }
  out.write_string("<template id=\"macro:\{decl.name}\"\{joined}>\n")
  for g in body_groups(decl) {
    print_content(g, out, "  ", {})
  }
  out.write_string("</template>\n\n")
}

///|
/// An expression failure as a report, with the repair it names.
pub fn ex_report(
  e : ExError,
  source : @report.SourceId,
  fallback? : @report.Span = @report.Span::at(0),
) -> @report.Report {
  let ExError(message~, help~, span~) = e
  // A printer works over an expression, which carries no span — so a failure
  // raised inside one points nowhere, and the enclosing declaration is the
  // narrowest place that does. Better the right line than the first one.
  let at = if span.start == 0 && span.len == 0 { fallback } else { span }
  @report.Report::error(message)
  .with_code("tutu::lower")
  .with_label(@report.Label::primary(source, at))
  .with_help(help)
}
