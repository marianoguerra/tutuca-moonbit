///|
/// Give a module's vtable functions their frozen FUNCTION type.
///
/// A component's `get` and `call` are stored in a `tg_vt`, whose two fields are
/// typed `tg_get` and `tg_call` — and those live inside the format's one
/// recursion group, because they and `tg_inst` and `tg_vt` genuinely refer to
/// each other. Wax will not coerce a function's NAME to a function type
/// declared in a group; it wants the function declared with that type, spelled
/// `fn c_get: tg_get(…)`. wap has no syntax for that and `FnDecl` has no field
/// to carry it, so a vtable is not expressible in wap alone.
///
/// The LOWERED field is expressible: `@wax_ast.ModuleField::Func` carries a
/// `typ` beside its signature, and wap always leaves it `None`. So this is one
/// pass over what wap produced, setting `typ` on exactly the functions that go
/// into a vtable.
///
/// ── Which functions, and how it knows ────────────────────────────────────
///
/// By READING THE MODULE rather than by a naming convention. A function that
/// needs `tg_get` is exactly one stored in a `tg_vt`'s `get` field, and the wap
/// AST says which that is — `tgabi.tg_vt{ get: c_get, call: c_call }` names
/// both. A convention over names would have been shorter and would have been a
/// second rule to keep in step with the emitters; this is the intent the author
/// already wrote.
pub fn retype_vtables(
  module_ : @wast.Module,
  fields : @wax_ast.LocModule,
) -> @wax_ast.LocModule raise PreambleError {
  let named = vtable_functions(module_)
  // The WAP module's name, not the wasm import namespace: it is the prefix wap
  // put on every declaration this module made.
  let wap_module = module_.name
  let out : @wax_ast.LocModule = []
  let found : Map[String, Unit] = Map([])
  for f in fields {
    match f.desc {
      // The two composition imports, bound to the frozen function types. A
      // module that imports them with a same-shaped INLINE signature does not
      // link: the runtime's own `get_field` is interned to `tg_get`, because
      // its signature matches one, and a standalone func type is not the type
      // inside a recursion group however identically it is spelled.
      ImportGroup(module_~, decls~) =>
        out.push({
          desc: ImportGroup(module_~, decls=frozen_imports(wap_module, decls)),
          info: f.info,
        })
      Import(module_~, decl~) =>
        out.push({
          desc: Import(module_~, decl=frozen_import(wap_module, decl)),
          info: f.info,
        })
      Func(name~, sign~, body~, attributes~, ..) =>
        match named.get(name.name) {
          Some(t) => {
            found[name.name] = ()
            out.push({
              desc: Func(
                name~,
                typ=Some(@build.ident(t)),
                sign~,
                body~,
                attributes~,
              ),
              info: f.info,
            })
          }
          None => out.push(f)
        }
      _ => out.push(f)
    }
  }
  // The one thing this pass knows about wap that wap does not promise: that a
  // declaration `name` in module `m` is emitted as `m__name`. That scheme is
  // documented nowhere and pinned by a single incidental assertion in wap's own
  // tests, so a change to it would not fail here — it would annotate nothing
  // and leave Wax to report that a function is not a `tg_get`, three steps from
  // the cause. The miss is therefore the error.
  let missing : Array[String] = []
  for want, _ in named {
    if !found.contains(want) {
      missing.push(want)
    }
  }
  if missing.length() > 0 {
    raise PreambleBug(
      "no lowered function is named " +
      missing.join(", ") +
      " — wap's name mangling has moved, and a vtable's functions can no longer " +
      "be given their frozen type. See `retype_vtables`.",
    )
  }
  out
}

///|
/// Bind every composition import in a group to its frozen function type.
fn frozen_imports(
  module_ : String,
  decls : Array[@basic.Annotated[@wax_ast.ImportDecl, @basic.Location]],
) -> Array[@basic.Annotated[@wax_ast.ImportDecl, @basic.Location]] {
  let out = []
  for d in decls {
    out.push(frozen_import(module_, d))
  }
  out
}

///|
fn frozen_import(
  module_ : String,
  d : @basic.Annotated[@wax_ast.ImportDecl, @basic.Location],
) -> @basic.Annotated[@wax_ast.ImportDecl, @basic.Location] {
  match d.desc.kind {
    Func(sign~, exact~, ..) =>
      match frozen_of(module_, d.desc.id.name) {
        Some(t) => {
          let decl : @wax_ast.ImportDecl = {
            id: d.desc.id,
            kind: Func(
              typ=Some(@build.ident(mangled(preamble_module, t))),
              sign~,
              exact~,
            ),
            attributes: d.desc.attributes,
          }
          { desc: decl, info: d.info, }
        }
        None => d
      }
    _ => d
  }
}

///|
/// The frozen function type an imported name carries, if it carries one.
///
/// Matched on the LOCAL name a module gave the import, which is the name the
/// lowered declaration carries. The vocabulary's own `name` is that spelling.
///
/// Anchored on the FULL expected name — `card__get_field` — rather than on the
/// suffix `__get_field`. The suffix form was ambiguous by construction: two wap
/// modules defining the same vocabulary name both end in it, so the match would
/// take whichever field came first. Nothing compiled here declares two today,
/// because a program is the preamble plus one module; a rule that is only
/// correct because of that is a rule waiting for the day it is not.
///
/// The bare name is still accepted, and has to be: a FOREIGN name — a host
/// import, an `import was` — is not mangled at all, so it arrives as written.
fn frozen_of(module_ : String, declared : String) -> String? {
  for f in vocab() {
    if f.frozen is Some(t) &&
      (declared == f.name || declared == mangled(module_, f.name)) {
      return Some(t)
    }
  }
  None
}

///|
/// Every function this module stores in a vtable, and the type it therefore has.
fn vtable_functions(module_ : @wast.Module) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  for d in module_.decls {
    match d {
      Fn(f) =>
        match f.body {
          Some(body) => scan_nodes(module_.name, body, out)
          None => ()
        }
      Impl(methods~, ..) =>
        for m in methods {
          match m.body {
            Some(body) => scan_nodes(module_.name, body, out)
            None => ()
          }
        }
      _ => ()
    }
  }
  out
}

///|
/// Walk for `tgabi.tg_vt{ get: …, call: … }`.
fn scan_nodes(
  module_ : String,
  nodes : Array[@wast.Node],
  out : Map[String, String],
) -> Unit {
  for n in nodes {
    scan_node(module_, n, out)
  }
}

///|
fn scan_node(
  module_ : String,
  n : @wast.Node,
  out : Map[String, String],
) -> Unit {
  match n.it {
    RecordLit(typ~, fields~) => {
      if typ is Some(t) && (t == preamble_module + ".tg_vt" || t == "tg_vt") {
        for f in fields {
          let (fname, value) = f
          let slot = match fname {
            "get" => Some("tg_get")
            "call" => Some("tg_call")
            _ => None
          }
          match (slot, value) {
            (Some(s), Some(v)) =>
              match v.it {
                Var(name) =>
                  out[mangled(module_, name)] = mangled(preamble_module, s)
                _ => ()
              }
            _ => ()
          }
        }
      }
      for f in fields {
        match f.1 {
          Some(v) => scan_node(module_, v, out)
          None => ()
        }
      }
    }
    Block(items) => scan_nodes(module_, items, out)
    Bind(value~, ..) =>
      match value {
        Some(v) => scan_node(module_, v, out)
        None => ()
      }
    Assign(targets~, value~, ..) => {
      scan_nodes(module_, targets, out)
      scan_node(module_, value, out)
    }
    If(arms~, ..) =>
      for arm in arms {
        match arm.0 {
          Some(c) => scan_node(module_, c, out)
          None => ()
        }
        scan_nodes(module_, arm.1, out)
      }
    Call(callee, args) => {
      scan_node(module_, callee, out)
      scan_nodes(module_, args, out)
    }
    Return(v) =>
      match v {
        Some(x) => scan_node(module_, x, out)
        None => ()
      }
    ForRange(body~, ..) | ForIn(body~, ..) | Loop(body~, ..) =>
      scan_nodes(module_, body, out)
    While(cond~, body~, ..) => {
      scan_node(module_, cond, out)
      scan_nodes(module_, body, out)
    }
    _ => ()
  }
}

///|
/// The name wap gives a declaration once lowered.
///
/// wap qualifies every declaration with its module — `card.c_get` becomes
/// `card__c_get`. A FOREIGN name (a host import, an `import was`) is not
/// mangled at all, which is why this is only ever applied to a name the module
/// itself declares.
pub fn mangled(module_ : String, name : String) -> String {
  module_ + "__" + name
}
