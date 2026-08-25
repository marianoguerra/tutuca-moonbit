// The Wax standard library, parsed once and prepended to every card.
//
// Wax has no import system: the stdlib IS its source, concatenated ahead of
// whatever uses it and compiled as one module. So this package holds the text
// (`stdlib_src_gen.mbt`, generated from `vendor/wax/`), parses it, and hands
// `emit_module` an `@ast.LocModule` to put in front of its own fields.
//
// This is the one place the Wax FRONT END is reached. Every other call into
// `marianoguerra/wax` from this package is AST-first through
// `marianoguerra/wax/compile`, which does not link the lexer, the token table
// or the generated LR parser. Importing the facade here puts all three in the
// bundle: the page went from 369 KB gzipped to 460 KB, +66 KB of it the front
// end and the rest the embedded sources. That is the price of using the
// stdlib as it is distributed, and the alternative -- a build step that prints
// MoonBit which rebuilds the same AST through `@build` -- costs a generated
// file of comparable size, a drift check, and a second thing to be wrong. Buy
// the parser.
//
// `binding_slots` is rebuilt per function (`emit/wasm/module.mbt:699`), so the
// stdlib's spans -- real byte offsets into 93 KB -- cannot collide with the
// small counter `dsl.mbt` mints for generated identifiers.

///|
/// The parsed stdlib, or the diagnostics that stopped it.
///
/// Parsing 93 KB is not free and the answer never changes, so it is done once
/// and held. The playground compiles on nearly every keystroke; without this
/// the front end would run the LR parser over the whole stdlib each time.
let stdlib_cache : Ref[Array[@abi.Field]?] = Ref(None)

///|
/// The card runtime, parsed once per combination of halves. Keyed by the
/// concatenation recipe rather than by one name, because a module now gets a
/// lowering half AND a set of optional pieces, and neither is a property of the
/// source they are cut from.
let runtime_cache : Map[String, Array[@abi.Field]] = Map([])

///|
/// The stdlib's module fields, ready to prepend.
///
/// A failure here is not a card's fault and not a user's: these sources are
/// fixed, and `stdlib_test.mbt` / `runtime_test.mbt` compile them on their own.
/// If this raises, the vendoring is broken.
pub fn stdlib_fields() -> Array[@abi.Field] raise BadSource {
  match stdlib_cache.val {
    Some(fs) => fs
    None => {
      let fs = parse_fixed(stdlib_src, "<wax-stdlib>")
      stdlib_cache.val = Some(fs)
      fs
    }
  }
}

///|
/// The card runtime's module fields: `runtime/runtime.wax`, then whichever
/// lowering half this card needs.
///
/// `uses_values` is what decides. A card that can hold or build a collection
/// gets `lower_values.wax` and with it an import of the `values` arena; one
/// that cannot gets `lower_scalar.wax` and imports nothing. The import section
/// is what a host inspects to know what a guest can do, so this flag is a
/// statement about the card rather than a build option.
///
/// The other three flags are the other kind. `parse_num.wax` is a decimal
/// parser only a card saying `num` or `int` can reach; `send_at.wax` reifies
/// and lowers a `&.place`; `contract_log.wax` builds the line a declined rule
/// says. Wax emits every function it is handed, so nothing else takes them out,
/// and these are purely about not making every card carry what two cards in ten
/// use.
///
/// `uses_contract_log` DOES reach the import section, unlike the other two — a
/// card that reports a refusal imports `control.log` to report it with. That is
/// a true statement about the card and the reason it is worth making: `log` is
/// the one thing on that interface no capability gates.
pub fn runtime_wax_fields(
  uses_values : Bool,
  uses_num? : Bool = false,
  uses_send_at? : Bool = false,
  uses_contract_log? : Bool = false,
  uses_children? : Bool = false,
  uses_escape? : Bool = false,
) -> Array[@abi.Field] raise BadSource {
  let which = if uses_values { "lower_values.wax" } else { "lower_scalar.wax" }
  let extra : Array[String] = []
  if uses_num {
    extra.push("parse_num.wax")
  }
  if uses_send_at {
    extra.push("send_at.wax")
  }
  if uses_contract_log {
    extra.push("contract_log.wax")
  }
  if uses_children {
    extra.push("make_child.wax")
  }
  if uses_escape {
    extra.push("escape_help.wax")
  }
  let key = which + "+" + extra.join("+")
  match runtime_cache.get(key) {
    Some(fs) => fs
    None => {
      let sb = StringBuilder()
      sb.write_string(runtime_src)
      sb.write_string(lower_src(which))
      for name in extra {
        sb.write_string(optional_src(name))
      }
      let fs = parse_fixed(sb.to_string(), "<card-runtime>")
      runtime_cache[key] = fs
      fs
    }
  }
}

///|
/// Parse one of the fixed sources. Anything wrong with it is a compiler bug.
fn parse_fixed(
  src : String,
  what : String,
) -> Array[@abi.Field] raise BadSource {
  let r = @waxfacade.parse_string(src, fname=what)
  guard r.module_ is Some(fs) else {
    raise BadSource([what + " did not parse"] + r.errors.map(e => e.message))
  }
  fs
}

///|
/// These sources did not parse, which is never a card's fault.
///
/// Its own error rather than the compiler's, because the dependency runs the
/// other way: this package knows nothing about cards, and importing the
/// generator's error would make it a package the generator could not be built
/// without.
pub suberror BadSource {
  BadSource(Array[String])
}

///|
pub fn BadSource::reasons(self : BadSource) -> Array[String] {
  let BadSource(ds) = self
  ds
}
