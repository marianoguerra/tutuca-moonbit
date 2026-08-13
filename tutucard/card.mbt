// Loading a card.
//
// Five steps, four of which are calls into machinery that already existed:
//
//   viewfile.split_file    the blocks
//   statedef.parse_state   the schema            (already done by split_file)
//   info.schema_info       the runtime description
//   tscript.parse_script   the behaviour
//   anode.View::new        the views, parsed at runtime
//
// and then `Component::for_type` over a `CardObj`. The only genuinely new
// thing in the path is the interpreter, which is the point: a card is not a
// second framework, it is the framework with the compiler taken out.

///|
pub fn CardError::message(self : CardError) -> String {
  match self {
    BadFile(e) => e.message()
    BadScript(line~, message~, ..) => "line \{line}: \{message}"
    NoViews =>
      "a card needs at least one <template>: state and script describe a component, and a view is what makes one visible"
    ManyComponents(names) =>
      "a card is one component, but this file declares " +
      names.map(n => "`\{n}`").join(", ") +
      " — give each its own file, or generate a module with `tutuca gen-views`"
  }
}

///|
pub fn load(source : String, name~ : String) -> Card raise CardError {
  let file = @viewfile.split_file(source, name~) catch { e => raise BadFile(e) }
  guard file.components.length() <= 1 else {
    raise ManyComponents(file.components.map(c => c.component_name(name)))
  }
  guard file.components.get(0) is Some(views) else { raise NoViews }
  let comp_name = views.component_name(name)
  let def = file.state.get(0)
  let issues : Array[CardIssue] = []

  // -- the script ----------------------------------------------------------
  let decls : Array[@tscript.Decl] = match file.script_for(comp_name) {
    Some(block) => {
      let ds = @tscript.parse_script(block.text) catch {
        e =>
          // The block's own coordinates rebased onto the file. This is what
          // the offset on `@viewfile.Block` is for, and it is the first thing
          // in a view file that can point at a column.
          raise BadScript(
            line=block.line + line_of(block.text, e.span().start) - 1,
            message=e.message(),
            span=rebase(e.span(), block.offset),
          )
      }
      match def {
        Some(d) =>
          for f in @check.check(ds, d) {
            issues.push({
              code: f.code,
              message: f.message,
              line: block.line + line_of(block.text, f.span.start) - 1,
              span: rebase(f.span, block.offset),
            })
          }
        // No schema: nothing to check against, and checking against a guess
        // would be the generator inventing a type. A card with no state block
        // is legal and its handlers are unchecked, which is the same trade a
        // view file with no schema already makes.
        None => ()
      }
      ds
    }
    None => []
  }

  // -- the description -----------------------------------------------------
  let schema = match def {
    Some(d) =>
      @info.schema_info(
        d,
        name=comp_name,
        // `inputs` is what this component ANSWERS, which for a card is what
        // the script declares. A generated component takes it from the views'
        // `@on` names instead, because there the block is where the answers
        // live and here it is the script.
        inputs=names_of(decls, DOn),
        methods=names_of(decls, DCompute) +
          names_of(decls, DPred) +
          names_of(decls, DInvariant),
        view_names=views.views.map(v => v.name),
        init_names=file.init.map(pair => pair.1.name),
      )
    // A card with no state block still has views and still needs a name to
    // label an instance with. Fields it has none of, which is the honest
    // description rather than a guess.
    None => {
      let bare = @tutuca.SchemaInfo::new(
        name=comp_name,
        fingerprint="",
        methods=names_of(decls, DCompute) +
          names_of(decls, DPred) +
          names_of(decls, DInvariant),
        view_names=views.views.map(v => v.name),
      )
      // Computed from the shape rather than left blank: the fingerprint is
      // what an instance's render-cache bucket is derived from, and every
      // card sharing one would put them all in the same bucket.
      { ..bare, fingerprint: bare.shape_fingerprint() }
    }
  }

  // -- the deck ------------------------------------------------------------
  let deck : Deck = {
    comp_id: Ref(0),
    schema,
    inputs: by_kind(decls, DOn),
    receives: by_kind(decls, DReceive),
    bubbles: by_kind(decls, DBubble),
    responses: by_kind(decls, DResponse),
    // An `invariant` is callable exactly as a `pred` is — a badge reading
    // `$conserved` asks the rule the same question every transition asks it.
    callables: merge(
      merge(by_kind(decls, DCompute), by_kind(decls, DPred)),
      by_kind(decls, DInvariant),
    ),
    alters: merge(by_kind(decls, DEnrich), by_kind(decls, DEnrichScope)),
    mutators: @component.schema_mutators(schema),
    // A `new` resolves its type name against this card's own declarations, and
    // against nothing else. A card with no state block declares none.
    zero: match def {
      Some(d) => Some(t => @info.zero_of_ref(d, t))
      None => None
    },
  }

  // -- the views -----------------------------------------------------------
  // `View::new` rather than `View::from_ir`: a card's templates arrive as
  // TEXT at runtime, which is the same path a guest bundle's views take.
  let vs : Map[String, @anode.View] = Map([])
  for v in views.views {
    vs[v.name] = @anode.View::new(v.name, raw_view=v.source, style=v.style)
  }
  let component = @component.Component::for_type(
    name=comp_name,
    views=vs,
    schema~,
    common_style=views.common_style,
    global_style=views.global_style,
    // Named arguments overlay the zero, exactly as a generated component's
    // `make` does: a caller states what differs and the type states the rest.
    make=args => {
      let fields = zero_fields(def, schema)
      for k, v in args {
        if fields.contains(k) {
          fields[k] = v
        }
      }
      Obj(CardObj::new(deck, fields))
    },
  )
  // The component's id is assigned when it is built, and an instance has to
  // answer with it — so the deck learns it here rather than guessing. A Ref
  // because the make closure above captures the deck before the id exists.
  deck.comp_id.val = component.id
  // The file's macros, in the shape the parser looks one up in. `split_file`
  // has been returning them all along and the loader dropped them, which made
  // `<x:card>` in a card an unknown element that rendered as itself.
  let macros : Map[String, @anode.Macro] = Map([])
  for m in file.macros {
    macros[m.name] = { defaults: m.defaults, raw_view: m.source }
  }
  { component, issues, def, macros }
}

///|
pub fn Card::initial(
  self : Card,
  fixture? : String = "",
) -> Map[String, @tutuca.Value] {
  let _ = fixture
  zero_fields(self.def, self.component.schema)
}

// ---------------------------------------------------------------------------
// Helpers

///|
/// The zero state: the schema's if there is one, and the description's
/// otherwise.
fn zero_fields(
  def : @statedef.StateDef?,
  schema : @tutuca.SchemaInfo,
) -> Map[String, @tutuca.Value] {
  match def {
    Some(d) => @info.zero_value(d)
    None => {
      let out : Map[String, @tutuca.Value] = Map([])
      for f in schema.fields {
        out[f.name] = f.ty.zero()
      }
      out
    }
  }
}

///|
/// Rebase a span from a block's coordinates onto the file's.
fn rebase(s : @tscript.Span, offset : Int) -> @tscript.Span {
  { start: s.start + offset, end_: s.end_ + offset }
}

///|
/// The 1-based line of a character offset in `text`.
fn line_of(text : String, offset : Int) -> Int {
  let chars = text.to_array()
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
fn by_kind(
  decls : Array[@tscript.Decl],
  kind : @tscript.DeclKind,
) -> Map[String, @tscript.Decl] {
  let out : Map[String, @tscript.Decl] = Map([])
  for d in decls {
    if d.kind == kind {
      out[d.name] = d
    }
  }
  out
}

///|
fn names_of(
  decls : Array[@tscript.Decl],
  kind : @tscript.DeclKind,
) -> Array[String] {
  let out : Array[String] = []
  for d in decls {
    if d.kind == kind {
      out.push(d.name)
    }
  }
  out
}

///|
fn merge(
  a : Map[String, @tscript.Decl],
  b : Map[String, @tscript.Decl],
) -> Map[String, @tscript.Decl] {
  let out : Map[String, @tscript.Decl] = Map([])
  for k, v in a {
    out[k] = v
  }
  for k, v in b {
    out[k] = v
  }
  out
}
