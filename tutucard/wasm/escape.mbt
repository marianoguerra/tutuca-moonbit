// The escape hatch: a card answering in Wax what the block language could not.
//
// WHY THERE IS ONE. tutuca's ahead-of-time path has had an escape for as long
// as it has refused anything — "a handler the block cannot compile is REFUSED
// by name, with the reason, and comes back as an `update~` argument" — and you
// write that argument in MoonBit. This path refused by name too, with the
// reason, and handed back NOTHING: a refused handler was simply absent, and the
// host fell back to whatever mutator the declared field implied. That is a
// reasonable answer for a handler nobody wrote and a bad one for a handler
// somebody wrote and the generator turned away.
//
// So: `<script type="tutuca/wax">` in the card, and what you write in it is the
// language the module is built out of anyway. The WAX panel the playground
// already shows is the discovery path — read what the generator emitted for the
// handlers that DID compile, and write the missing one in the same idiom.
//
// WHAT MAKES IT SAFE. Two things, and neither is a promise:
//
//   - `allow_wax` is off by default. A card is untrusted content in the
//     `<mb-card>` story, so whether one may carry code at all is the HOST's
//     decision and not the card's.
//   - the screen below takes functions and refuses everything else. A guest's
//     authority is its IMPORT SECTION — that is what `abi.mjs` inspects — so an
//     escape that could add an import could widen what the card may do. It
//     cannot: no `import`, no `memory`, no `data`, no `#[export]`, no
//     `#[start]`, no globals. Whatever the functions do, they do it with the
//     authority the card already had.

///|
/// Prefixes an escape may not define into.
///
/// The stdlib has claimed `wax_ phm_ phmt_ phs_ phst_ pv_ pvt_ utf8_ jv_ jvt_
/// st_`, the card runtime has claimed `tc_` and `tcx_`, and the generator mints
/// `cm_` for a callable and `get_` / `set_` for the accessors below. Wax would
/// reject a duplicate definition on its own, but as a `BadModule` — the error
/// whose message says "this is a cardwasm bug" — and a name collision in a
/// block somebody typed is not one.
let reserved_prefixes : Array[String] = [
  "tc_", "tcx_", "jv_", "jvt_", "phm_", "phmt_", "phs_", "phst_", "pv_", "pvt_",
  "utf8_", "st_", "wax_", "cm_", "get_", "set_", "num_",
]

///|
/// The `card_<role>_<name>` convention, as (kind word, declaration name).
///
/// A NAME rather than an attribute, and that is the whole of the binding: Wax's
/// attributes are its own (`#[export]`, `#[import]`) and inventing a
/// `#[card.on]` would mean teaching the Wax front end about cards. A function
/// called `card_receive_inc` answers the `receive inc` a card declares, and a function
/// called anything else is a helper the escapes may call.
fn escape_role(fn_name : String, comp? : String = "") -> (String, String)? {
  guard fn_name.has_prefix("card_") else { return None }
  let mut rest = fn_name[5:].to_owned()
  // `card_TodoItem_receive_inc` as well as `card_receive_inc`. A file with two
  // components has two escape blocks in one module, and two of them answering
  // `receive inc` need two function names — but the generator cannot rename
  // what an author typed, because the bodies call helpers by name. So the
  // author writes the longer form, and the component segment comes off here
  // before the role scan that has always followed.
  if comp != "" && rest.has_prefix(comp + "_") {
    rest = rest[comp.length() + 1:].to_owned()
  }
  for word in ["receive", "intent", "compute", "pred", "invariant"] {
    if rest.has_prefix(word + "_") {
      let name = rest[word.length() + 1:].to_owned()
      if name != "" {
        return Some((word, name))
      }
    }
  }
  None
}

///|
/// Whether a kind word names a transition — which decides what the function
/// answers and where the dispatch arm goes.
fn escape_is_transition(kind : String) -> Bool {
  kind is ("receive" | "intent")
}

///|
/// One function an escape block defines.
priv struct EscapeFn {
  /// The Wax function's own name.
  fn_name : String
  /// `on` / `compute` / … for one that answers a declaration; "" for a helper.
  kind : String
  name : String
}

///|
/// Parse a card's escape block, and screen what it defines.
///
/// Answers the module fields to splice in and what they answer for. A failure
/// here is `BadEscape` and never `BadModule`: the card's author typed this.
fn parse_escape(
  src : String,
  fname : String,
  comp? : String = "",
) -> (Array[@abi.Field], Array[EscapeFn]) raise GenError {
  let r = @waxfacade.parse_string(src, fname~)
  guard r.module_ is Some(fields) else {
    raise BadEscape(["it did not parse"] + r.errors.map(e => e.message))
  }
  if r.errors.length() > 0 {
    raise BadEscape(r.errors.map(e => e.message))
  }
  let bad : Array[String] = []
  let defined : Array[EscapeFn] = []
  for f in fields {
    match f.desc {
      Func(name~, attributes~, ..) => {
        // An `#[export]` would put a name in the module's EXPORT section, which
        // is the other half of what a host inspects. `#[start]` would run at
        // instantiation, before `tc_boot` has interned a single constant.
        for a in attributes {
          if a.attr_name is ("export" | "start") {
            bad.push(
              "`#[" +
              a.attr_name +
              "]` on `" +
              name.name +
              "`: an escape defines functions the card calls, not exports the host sees",
            )
          }
        }
        for p in reserved_prefixes {
          if name.name.has_prefix(p) {
            bad.push(
              "`" +
              name.name +
              "` starts with `" +
              p +
              "`, which the runtime has claimed — name it something else",
            )
          }
        }
        match escape_role(name.name, comp~) {
          Some(pair) => {
            let (kind, decl) = pair
            defined.push({ fn_name: name.name, kind, name: decl, })
          }
          None => defined.push({ fn_name: name.name, kind: "", name: "", })
        }
      }
      // Everything a guest's AUTHORITY is made of. An escape may not widen it,
      // and saying so here is cheaper than reasoning about a module that did.
      Import(..) | ImportGroup(..) =>
        bad.push(
          "an `import`: a guest's authority is its import section, and an escape does not get to add to it",
        )
      Memory(..) =>
        bad.push("a `memory`: the card already declares the one the ABI uses")
      Data(..) =>
        bad.push(
          "a `data` segment: the constant pool is laid down by the generator, and a second one would overlap it",
        )
      Global(name~, ..) =>
        bad.push(
          "a global `" +
          name.name +
          "`: an escape is functions, and state that outlives a call belongs to the runtime",
        )
      Table(..) | Elem(..) =>
        bad.push("a table: nothing in a card dispatches indirectly")
      _ => ()
    }
  }
  guard bad.is_empty() else { raise BadEscape(bad) }
  (fields, defined)
}

///|
/// The per-field accessors an escape block is given.
///
/// This is the difference between an escape being writable and being a research
/// project. The generator reaches a field through
/// `tc_get(s, tc_const_str(<pool index>))`, and the pool index is a number only
/// the generator knows — so without these, a hand-writer's first problem is
/// that they cannot name a field at all.
///
/// Emitted ONLY when the card has an escape block, so a card without one pays
/// nothing for them. Three lines each, over `tc_get` / `tc_set`, which already
/// do the work:
///
///   fn get_count(s: &jv_record_value) -> &jv_value
///   fn set_count(s: &jv_record_value, v: &jv_value) -> &jv_record_value
///   fn num_count(s: &jv_record_value) -> f64          // Int and Double only
///
/// `set_` answers the SUCCESSOR rather than mutating, because that is what a
/// `jv_record` is: `tc_set` validates against the schema and shares every part
/// it did not change.
fn escape_prelude(g : Gen) -> Array[@abi.Field] {
  let fs : Array[@abi.Field] = []
  for f in g.fields {
    let key = text_const_str(g.pool, f.name)
    fs.push(
      func(g.sym("get_", f.name), params=[("s", rec_)], results=[jv_], body=[
        call("tc_get", [get("s"), key]),
      ]),
    )
    fs.push(
      func(
        g.sym("set_", f.name),
        params=[("s", rec_), ("v", jv_)],
        results=[rec_],
        body=[call("tc_set", [get("s"), key, g.coerce(f.name, get("v"))])],
      ),
    )
    // Arithmetic is the common case and `tc_num_of(get_x(s))` is the common
    // line, so a number field gets the shorter one too.
    if f.ty is (TInt(..) | TFloat) {
      fs.push(
        func(g.sym("num_", f.name), params=[("s", rec_)], results=[f64_], body=[
          call("tc_num_of", [call("tc_get", [get("s"), key])]),
        ]),
      )
    }
  }
  fs
}

///|
/// A `cm_<name>` for every callable an escape answers.
///
/// A three-line forwarder rather than teaching four call sites about escapes:
/// a render operation, a `requires`, an `ensures` and a body that calls one bare all
/// reach a callable as `cm_<name>`, and giving an escaped one the same name
/// means none of them has to know the difference.
///
/// Emitted AFTER the escape functions, because Wax resolves in one pass. That
/// is also the one thing an escaped callable cannot do: a COMPILED callable is
/// emitted before all of this, so it cannot call an escaped one. It reads as a
/// refusal rather than as a mystery — the fixpoint in `callable_fields` refuses
/// a callable whose dependency was refused — and the answer is to escape both.
fn escape_wrappers(g : Gen) -> Array[@abi.Field] {
  let fs : Array[@abi.Field] = []
  for _key, e in g.escapes {
    if escape_is_transition(e.kind) {
      continue
    }
    fs.push(
      func(
        callable_fn(g, e.name),
        params=[("s", rec_), ("args", args_)],
        results=[jv_],
        body=[call(e.fn_name, [get("s"), get("args")])],
      ),
    )
  }
  fs
}

///|
/// What the card's escape block answered for, for `Compiled`.
///
/// `replaced` is the reason the block language turned the name away, when it
/// declared the name and was refused — which is the case this whole mechanism
/// exists for, and worth seeing beside the escape rather than only in the
/// refusal list.
fn escape_list(g : Gen, decls : Array[@tscript.Decl]) -> Array[Escape] {
  let out : Array[Escape] = []
  for _key, e in g.escapes {
    let mut why = ""
    for r in g.refusals {
      // Scoped to THIS component: a file with two of them can refuse the same
      // name in each, and the reason one was turned away is not the reason the
      // other was.
      if r.comp == g.comp && r.name == e.name && r.kind == e.kind {
        why = r.reason
      }
    }
    let declared = decls
      .iter()
      .any(d => d.name == e.name && @tscript.kind_word(d.kind) == e.kind)
    out.push({
      comp: g.comp,
      kind: e.kind,
      name: e.name,
      fn_name: e.fn_name,
      declared,
      replaced: why,
    })
  }
  out.sort_by((a, b) => {
    if a.name < b.name {
      -1
    } else if a.name > b.name {
      1
    } else {
      0
    }
  })
  out
}

///|
/// Whether a declaration this card wrote is answered by the escape block
/// instead. Used to keep a refused name out of the refusal list twice over.
fn Gen::escaped(self : Gen, kind : String, name : String) -> Bool {
  self.escapes.get(kind + " " + name) is Some(_)
}
