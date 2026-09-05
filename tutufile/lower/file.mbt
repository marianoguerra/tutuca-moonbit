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
  let impls : Map[String, Map[String, PropImpl]] = {}
  match file.section(Logic) {
    Some(section) =>
      for decl in section.decls {
        let body = StringBuilder()
        match (try? print_logic(decl, body)) {
          Ok(found) => {
            impls[decl.name] = found
            logic_text.write_string(
              "<script type=\"tutuca/script\" for=\"\{decl.name}\">\n",
            )
            logic_text.write_string(body.to_string())
            logic_text.write_string("</script>\n\n")
          }
          Err(e) => reports.push(ex_report(e, source))
        }
      }
    None => ()
  }
  match file.section(Spec) {
    Some(section) => {
      out.write_string("<script type=\"tutuca/spec\">\n")
      for decl in section.decls {
        let body = StringBuilder()
        let ok = match decl.kind {
          Component =>
            try? print_state(decl, impls.get(decl.name).unwrap_or({}), body)
          Struct => try? print_struct(decl, body)
          Enum => try? print_enum(decl, body)
          _ => Ok(())
        }
        match ok {
          Ok(_) => {
            out.write_string(body.to_string())
            if decl.kind is Component {
              let ch = StringBuilder()
              match (try? print_channels(decl, ch)) {
                Ok(_) => out.write_string(ch.to_string())
                Err(e) => reports.push(ex_report(e, source))
              }
            }
          }
          Err(e) => reports.push(ex_report(e, source))
        }
      }
      out.write_string("</script>\n\n")
    }
    None => ()
  }
  out.write_string(logic_text.to_string())
  match file.section(Fixtures) {
    Some(section) =>
      match (try? print_fixtures(section.decls)) {
        Ok(json) => {
          out.write_string("<script type=\"tutuca/fixtures\">\n")
          out.write_string(json)
          out.write_string("\n</script>\n\n")
        }
        Err(e) => reports.push(ex_report(e, source))
      }
    None => ()
  }
  match file.section(Tests) {
    Some(section) =>
      match (try? print_scenes(section.decls)) {
        Ok(json) => {
          out.write_string("<script type=\"tutuca/test\">\n")
          out.write_string(json)
          out.write_string("\n</script>\n\n")
        }
        Err(e) => reports.push(ex_report(e, source))
      }
    None => ()
  }
  match file.section(View) {
    Some(section) =>
      for decl in section.decls {
        let body = StringBuilder()
        match decl.kind {
          View =>
            match (try? print_view(decl, body)) {
              Ok(_) => out.write_string(body.to_string())
              Err(e) => reports.push(ex_report(e, source))
            }
          Style =>
            match (try? print_file_style(decl, body)) {
              Ok(_) => out.write_string(body.to_string())
              Err(e) => reports.push(ex_report(e, source))
            }
          Macro =>
            match (try? print_macro(decl, body)) {
              Ok(_) => out.write_string(body.to_string())
              Err(e) => reports.push(ex_report(e, source))
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
        match (try? read_args([g])) {
          Ok(args) =>
            for a in args {
              match a {
                AKw(name, value) =>
                  defaults.push(
                    "data-\{attr_name(name)}=\"\{attr_escape(print_ex(value))}\"",
                  )
                _ => ()
              }
            }
          Err(_) => ()
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
pub fn ex_report(e : ExError, source : @report.SourceId) -> @report.Report {
  let ExError(message~, help~, span~) = e
  @report.Report::error(message)
  .with_code("tutu::lower")
  .with_label(@report.Label::primary(source, span))
  .with_help(help)
}
