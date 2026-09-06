// The state, and the four things every component owes a host.
//
// Every field is one slot in a `&tg_vals`, whatever its declared type. That is
// a deliberate simplification and worth stating: a specialising backend would
// unbox an `Int` field into an `f64` field of a generated struct and save a
// `struct.new` per assignment. This one does not, and gets `get_field` and
// `with_field` for two lines each, a successor that shares every slot it did
// not change, and no per-type code path to get subtly wrong. The declared type
// still decides the ZERO and still truncates an `Int` at its assignment sites,
// which is where the semantics actually live.

///|
/// One component's compiled shape: everything the emitters need to name it.
priv struct Comp {
  def : @statedef.StateDef
  /// The card's own name, as a host asks for it.
  name : String
  /// That name as a wap identifier prefix.
  id : String
  /// Declared fields, in declaration order. The index IS the slot.
  fields : Array[@statedef.FieldDef]
  decls : Array[@tscript.Decl]
  /// The declarations the SCRIPT BLOCK wrote, without the rules synthesized
  /// from the spec block.
  ///
  /// `decls` above is what gets compiled and is both; this is what gets
  /// CHECKED. `RULE_IN_BOTH` asks whether an author wrote one rule twice, and
  /// handing it a synthesized copy makes every spec-block rule its own
  /// duplicate.
  authored : Array[@tscript.Decl]
  /// The card's templates, carried through so the manifest can name them. A
  /// component with no view has nothing to mount.
  views : Array[@viewfile.RawView]
  common_style : String
  /// What this component says about ITSELF for a catalog: its category and
  /// its keywords.
  ///
  /// Only a `.tutu` card can set it — the blocks have no syntax for either and
  /// none is being added — so for an `.html` card this is empty and a host's
  /// annotation table is the only channel. That asymmetry is deliberate: it
  /// gives a card a reason to convert.
  meta : @lower.ComponentMeta
  /// Every component the CARD declares, this one included.
  ///
  /// `new Swatch` names a sibling, and whether a name is one is a fact about
  /// the file rather than about the component reading it.
  siblings : Array[String]
  /// The card's named starting states.
  ///
  /// A fixture is not decoration: the DEFAULT one is what a host mounts when it
  /// is told no other name, so a card whose fixtures are dropped mounts at its
  /// declared zero and every string field renders empty. That is what dropping
  /// them looks like on a page, and it is why they are carried.
  inits : Array[@statedef.InitState]
  refusals : Array[@check.Refusal]
}

///|
fn Comp::field_index(self : Comp, name : String) -> Int? {
  for i, f in self.fields {
    if f.name == name {
      return Some(i)
    }
  }
  None
}

///|
/// The zero of a declared type, as a wap expression.
///
/// `Ty::zero` already answers it as a `Value`, so this is only the spelling —
/// which matters because a card and a compiled component must start from the
/// same state, and two zero tables would eventually disagree.
fn zero_node(b : B, ty : @tutuca.Ty) -> @wast.Node {
  value_node(b, ty.zero())
}

///|
/// A constant `Value` as a wap expression.
fn value_node(b : B, v : @tutuca.Value) -> @wast.Node {
  match v {
    Null => b.rt("tg_null", [])
    Bool(x) => b.rt("tg_bool", [b.int_(if x { 1 } else { 0 })])
    Num(n) => b.rt("tg_num", [b.num(n)])
    Str(s) => b.rt("tg_str", [b.str_(s)])
    List(items) => {
      let parts : Array[@wast.Node] = []
      for item in items {
        parts.push(value_node(b, item))
      }
      b.rt("tg_list", [b.vals_of(parts)])
    }
    Map(m) => {
      let parts : Array[@wast.Node] = []
      for k, item in m {
        parts.push(b.rt("tg_entry_of", [b.str_(k), value_node(b, item)]))
      }
      b.rt("tg_map", [b.entries_of(parts)])
    }
    // A function and a component instance are not constants a schema can hold.
    // `Ty::zero` never answers one; a fixture might, and this is where that
    // would be caught rather than emitted as something plausible.
    _ => b.rt("tg_null", [])
  }
}

///|
/// The two array types a generated module names locally.
///
/// Not new wasm types: each is a singleton recursion group with the same
/// content as the preamble's, so the engine canonicalizes them together. They
/// exist because wap takes an array literal's element type from a bare name and
/// not from a qualified one, which is the same reason `tgc/rt` declares its
/// own.
fn own_array_types(b : B) -> Array[@wast.Decl] {
  [
    b.array_alias(vals_type, Nullable(Named(@abi.preamble_module + ".tg_val"))),
    b.array_alias(
      entries_type,
      Nullable(Named(@abi.preamble_module + ".tg_entry")),
    ),
  ]
}

///|
/// The state type, the field table, and the two vtable slots' data half.
fn emit_state(b : B, c : Comp) -> Array[@wast.Decl] {
  let out : Array[@wast.Decl] = []
  // Every declared field is one slot. The index is the field.
  out.push(b.record("\{c.id}_state", [("fields", abi_type("tg_vals"))]))

  // The name -> slot table. An if-chain rather than a hash: a card has a
  // handful of fields, and a chain the reader can follow beats a table nobody
  // can check by eye.
  let slot_body : Array[@wast.Node] = []
  for i, f in c.fields {
    slot_body.push(
      b.if_(
        b.made(
          Bin(Ne, b.rt("str_eq", [b.var_("name"), b.str_(f.name)]), b.int_(0)),
        ),
        [b.ret(Some(b.int_(i)))],
      ),
    )
  }
  slot_body.push(b.int_(-1))
  out.push(
    b.fn_(
      "\{c.id}_slot",
      [b.param("name", abi_type("tg_bytes"))],
      [I32],
      slot_body,
    ),
  )

  // Absence, not null-the-value: there is no such field.
  out.push(
    b.fn_(
      "\{c.id}_get",
      [
        b.param("self", abi_type("tg_inst")),
        b.param("name", abi_type("tg_bytes")),
      ],
      [opt_val()],
      [
        b.bind(
          "st",
          b.made(
            Cast(
              b.force(b.made(Field(b.var_("self"), "state"))),
              Named("\{c.id}_state"),
            ),
          ),
        ),
        b.bind("i", b.call("\{c.id}_slot", [b.var_("name")])),
        b.if_(b.made(Bin(Lt, b.var_("i"), b.int_(0))), [b.ret(Some(b.null_()))]),
        b.made(Index(b.made(Field(b.var_("st"), "fields")), b.var_("i"))),
      ],
    ),
  )

  // Copy on write. The successor shares every slot it did not change.
  out.push(
    b.fn_(
      "\{c.id}_copy",
      [b.param("st", Named("\{c.id}_state"))],
      [abi_type("tg_vals")],
      [
        b.bind(
          "out",
          b.made(
            ArrayRepeat(
              typ=Some(vals_type),
              value=b.null_(),
              count=b.int_(c.fields.length()),
            ),
          ),
        ),
        b.made(
          ForRange(
            label=None,
            var_="i",
            from=b.int_(0),
            to=b.int_(c.fields.length()),
            inclusive=false,
            by=None,
            body=[
              b.set(
                b.made(Index(b.var_("out"), b.var_("i"))),
                b.made(
                  Index(b.made(Field(b.var_("st"), "fields")), b.var_("i")),
                ),
              ),
            ],
          ),
        ),
        b.var_("out"),
      ],
    ),
  )
  out
}

///|
/// `tgc.make`, `tgc.describe` and the instance constructor.
fn emit_shell(
  b : B,
  comps : Array[Comp],
  manifest : @tutuca.Value,
) -> Array[@wast.Decl] {
  let out : Array[@wast.Decl] = []
  for c in comps {
    // The vtable. Its two slots are typed by the format's frozen function
    // types, which live inside the one recursion group — see `retype_named`
    // for why those two functions get their type after wap has lowered them
    // rather than in the source above.
    out.push(
      b.fn_(
        "\{c.id}_inst",
        [
          b.param("desc", abi_type("tg_val")),
          b.param("fields", abi_type("tg_vals")),
        ],
        [abi_type("tg_inst")],
        [
          b.bind(
            "vt",
            b.made(
              RecordLit(typ=Some(@abi.preamble_module + ".tg_vt"), fields=[
                ("get", Some(b.var_("\{c.id}_get"))),
                ("call", Some(b.var_("\{c.id}_call"))),
              ]),
            ),
          ),
          b.bind(
            "st",
            b.made(
              RecordLit(typ=Some("\{c.id}_state"), fields=[
                ("fields", Some(b.var_("fields"))),
              ]),
            ),
          ),
          b.made(
            RecordLit(typ=Some(@abi.preamble_module + ".tg_inst"), fields=[
              ("vt", Some(b.var_("vt"))),
              ("desc", Some(b.var_("desc"))),
              ("state", Some(b.var_("st"))),
              // The RUNTIME's counter, not this module's. Two modules with
              // private counters hand out the same first id, and `val_eq`
              // compares component values by id alone.
              ("id", Some(b.rt("next_id", []))),
            ]),
          ),
        ],
      ),
    )
  }

  // Construction from a host's argument map. A missing or oddly-shaped `args`
  // is the declared zero rather than a refusal: a host that hands a component
  // nothing has asked for its initial state, and that is a thing a component
  // knows.
  for c in comps {
    let items : Array[@wast.Node] = []
    for f in c.fields {
      items.push(
        b.rt("tg_arg", [b.var_("args"), b.str_(f.name), zero_node(b, f.ty)]),
      )
    }
    out.push(
      b.fn_(
        "\{c.id}_make_fields",
        [b.param("args", opt_val())],
        [abi_type("tg_vals")],
        [b.vals_of(items)],
      ),
    )
  }

  // A descriptor PER COMPONENT, and it is that component's slice of the ONE
  // manifest rather than a second description of it.
  //
  // `desc` is how an instance says what it is, and a host reads `component` off
  // it to decide which view to draw. A card declaring several components whose
  // children all carried the module's descriptor drew the root's view for every
  // child, which looked like the page repeating itself.
  let by_name = component_descriptors(manifest)
  for c in comps {
    out.push(
      b.fn_("\{c.id}_desc", [], [abi_type("tg_val")], [
        value_node(b, by_name.get(c.name).unwrap_or(Null)),
      ]),
    )
  }

  let make_body : Array[@wast.Node] = []
  for c in comps {
    make_body.push(
      b.if_(
        b.made(
          Bin(Ne, b.rt("str_eq", [b.var_("name"), b.str_(c.name)]), b.int_(0)),
        ),
        [
          b.ret(
            Some(
              b.call("\{c.id}_inst", [
                b.call("\{c.id}_desc", []),
                b.call("\{c.id}_make_fields", [b.var_("args")]),
              ]),
            ),
          ),
        ],
      ),
    )
  }
  make_body.push(b.null_())
  out.push(
    b.fn_(
      "tgc_make",
      [b.param("name", abi_type("tg_bytes")), b.param("args", opt_val())],
      [Nullable(Named(@abi.preamble_module + ".tg_inst"))],
      make_body,
      export_name=@abi.export_make,
    ),
  )

  // The WHOLE manifest, in the module. A module that says what it is needs no
  // packer and no file beside it — which is what lets a toolchain that has
  // never heard of this repository produce one, and what stops a card arriving
  // with half of itself.
  //
  // It names the root component first, because every mount site takes the head
  // of `components`.
  out.push(
    b.fn_(
      "tgc_describe",
      [],
      [abi_type("tg_val")],
      [value_node(b, manifest)],
      export_name=@abi.export_describe,
    ),
  )

  // This card serves no module-scoped intent. A `serve` block would answer
  // here, on the `lex` leg.
  out.push(
    b.fn_(
      "tgc_serve",
      [
        b.param("name", abi_type("tg_bytes")),
        b.param("args", abi_type("tg_vals")),
      ],
      [opt_val()],
      [b.null_()],
      export_name=@abi.export_serve,
    ),
  )
  out.push(
    b.fn_(
      "tgc_abi",
      [],
      [I32],
      [b.int_(@abi.ABI_VERSION)],
      export_name=@abi.export_abi,
    ),
  )
  out
}

///|
/// The manifest's components, by name — so an instance's descriptor is a slice
/// of the module's rather than a second copy of the same facts.
fn component_descriptors(
  manifest : @tutuca.Value,
) -> Map[String, @tutuca.Value] {
  let out : Map[String, @tutuca.Value] = Map([])
  guard manifest is Map(m) && m.get("components") is Some(List(items)) else {
    return out
  }
  for item in items {
    if item is Map(c) && c.get("name") is Some(Str(name)) {
      out[name] = item
    }
  }
  out
}
