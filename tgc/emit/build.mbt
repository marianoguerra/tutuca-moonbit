// The IR, and the two naming rules.
//
// `tgc/1` had no IR: `emit_expr` answered a Wax expression as a STRING and
// wrote statements into a shared buffer as a side effect, so the generated
// module's shape lived in a `StringBuilder` and its indentation was
// hand-maintained with `depth = depth ± 1` at eleven call sites. This is the
// same emitters over `marianoguerra/wap/ast` values instead.
//
// Four things follow from the change, and they are the reason for it rather
// than a bonus:
//
//   - An expression is a VALUE, so it can be built, held and placed. The
//     short-circuit forms needed a temporary and a hand-written branch; they
//     need a `Block` now.
//   - Escaping is gone. A string literal is `StrLit(s)` and the encoder deals
//     with the bytes, so `wax_str` and the class of bug it lived in are gone.
//   - Every node carries a SPAN, and the span is the card's. `tgc/1` prepended
//     the preamble as text and then subtracted its line count from every
//     diagnostic; a diagnostic now points where the author typed.
//   - What a card imported is what the emitters ASKED for, recorded as they
//     built. `tgc/1` scanned the generated text for each of eighty names and
//     called it "sound because it wrote it".

///|
/// The emitter's notebook: where spans point, and what got called.
priv struct B {
  /// The card's source, registered once so a span means something.
  src : @report.SourceId
  /// Every vocabulary name an emitter reached for. The import block is built
  /// from this, so a module's imports are exactly its authority — no scan, no
  /// over-approximation, and nothing imported that nothing calls.
  used : @set.Set[String]
}

///|
fn B::new(src : @report.SourceId) -> B {
  { src, used: Set([]), }
}

///|
/// A card span, as a report span.
///
/// The `SourceId` is what makes one mean anything: a span is an offset into a
/// registered source, and `tgc/1` had none to point at — it prepended the
/// preamble as text and subtracted its line count from every diagnostic
/// afterwards.
fn B::at(self : B, s : @tutuca.Span) -> @report.Span {
  ignore(self.src)
  @report.Span::of_range(s.start, s.end_)
}

///|
/// A node with no source of its own — a shell the emitter wrote, rather than
/// anything an author typed.
fn B::made(self : B, e : @wast.Expr) -> @wast.Node {
  { it: e, span: self.at(@tutuca.no_span), }
}

///|
/// A call to the runtime vocabulary, recorded.
///
/// This is the only door to `tut`, which is what keeps the import block honest:
/// an emitter cannot reach a runtime function without this noticing.
fn B::rt(self : B, name : String, args : Array[@wast.Node]) -> @wast.Node {
  self.used.add(name)
  self.made(Call(self.made(Var(name)), args))
}

///|
/// A call to something the card itself declares.
fn B::call(self : B, name : String, args : Array[@wast.Node]) -> @wast.Node {
  self.made(Call(self.made(Var(name)), args))
}

///|
fn B::var_(self : B, name : String) -> @wast.Node {
  self.made(Var(name))
}

///|
/// A text literal.
///
/// No escaping: wap carries the string and the encoder writes the bytes. A wap
/// string literal is an anonymous `[u8]`, which canonicalizes to the same wasm
/// type as `tgabi.tg_bytes` — singleton recursion groups with identical content
/// are one type — so a card's text needs no interning table and no constant
/// pool.
fn B::str_(self : B, s : String) -> @wast.Node {
  self.made(StrLit(s))
}

///|
/// A double, spelled so wap reads it back as the same double.
///
/// The trailing `.0` is not decoration: wap types `1` as an integer and `1.0`
/// as a float, and an `f64` argument spelled `1` is a type error rather than a
/// coercion. Neither NaN nor an infinity has a literal, so both are built.
fn B::num(self : B, n : Double) -> @wast.Node {
  if n.is_nan() {
    // A card cannot write one; a `Ty::zero` cannot be one. Belt and braces.
    return self.made(Bin(Div, self.made(Float("0.0")), self.made(Float("0.0"))))
  }
  if n.is_inf() {
    let one = if n > 0.0 { "1.0" } else { "-1.0" }
    return self.made(Bin(Div, self.made(Float(one)), self.made(Float("0.0"))))
  }
  let s = n.to_string()
  self.made(
    Float(
      if s.contains(".") || s.contains("e") || s.contains("E") {
        s
      } else {
        s + ".0"
      },
    ),
  )
}

///|
fn B::int_(self : B, n : Int) -> @wast.Node {
  self.made(Int(n.to_string()))
}

///|
fn B::null_(self : B) -> @wast.Node {
  self.made(Null)
}

///|
/// `let name = value`, and `var name = value` when something assigns to it.
fn B::bind(
  self : B,
  name : String,
  value : @wast.Node,
  typ? : @wast.Type,
  mutable? : Bool = false,
) -> @wast.Node {
  self.made(
    Bind(
      binders=[{ name, typ, span: self.at(@tutuca.no_span), }],
      value=Some(value),
      mutable~,
    ),
  )
}

///|
fn B::set(self : B, target : @wast.Node, value : @wast.Node) -> @wast.Node {
  self.made(Assign(targets=[target], op=Set, value~))
}

///|
/// `if cond: then` and `if cond: then | else`, as an expression.
///
/// `typ` matters and is not optional in practice: an `if` in a value position
/// is a wasm block with a result, and wap needs to be told what that result is
/// when neither arm is a literal it can read one from.
fn B::if_(
  self : B,
  cond : @wast.Node,
  then_ : Array[@wast.Node],
  else_? : Array[@wast.Node],
  typ? : @wast.Type,
) -> @wast.Node {
  let arms : Array[(@wast.Node?, Array[@wast.Node])] = [(Some(cond), then_)]
  match else_ {
    Some(e) => arms.push((None, e))
    None => ()
  }
  self.made(If(arms~, typ~))
}

///|
fn B::ret(self : B, value : @wast.Node?) -> @wast.Node {
  self.made(Return(value))
}

///|
/// `a == null` and `a != null`, the two questions the two-nulls rule turns on.
fn B::is_null(self : B, v : @wast.Node) -> @wast.Node {
  self.made(Bin(Eq, v, self.made(Null)))
}

///|
/// `v!` — the value behind a nullable, which traps if there is none.
fn B::force(self : B, v : @wast.Node) -> @wast.Node {
  self.made(NonNull(v))
}

///|
/// A `tg_vals` literal.
///
/// It names the LOCAL array type rather than `tgabi.tg_vals`, because wap takes
/// an array literal's element type from a bare name and not from a qualified
/// one. The two canonicalize to the same wasm type — singleton recursion groups
/// with identical content are one type — which is the property `tgc/2` is built
/// on, used here for the second time.
fn B::vals_of(self : B, items : Array[@wast.Node]) -> @wast.Node {
  self.made(ArrayLit(typ=Some(vals_type), items~))
}

///|
/// A `tg_entries` literal, on the same terms.
fn B::entries_of(self : B, items : Array[@wast.Node]) -> @wast.Node {
  self.made(ArrayLit(typ=Some(entries_type), items~))
}

///|
/// The names a generated module gives its own copies of the two array types.
let vals_type : String = "vals"

///|
let entries_type : String = "entries"

///|
/// The two types every generated signature is written in.
fn opt_val() -> @wast.Type {
  Nullable(Named(@abi.preamble_module + ".tg_val"))
}

///|
fn abi_type(name : String) -> @wast.Type {
  Named(@abi.preamble_module + "." + name)
}

///|
/// A card's name, as a wap identifier.
///
/// wap HAS module namespaces, but a card's components all live in one module —
/// they share a state vocabulary and call each other's helpers — so the
/// component prefix does the same job it did under Wax. A card declaring one
/// component gets `C_receive_inc`; a card declaring several gets one per
/// component and they cannot collide, which is the whole of what the prefix is
/// for.
///
/// Non-identifier characters become `_`, and a name that would start with a
/// digit gets a leading `_`. Two card names that mangle the same are a
/// collision the caller has to catch — `compile_decls` does, because a silent
/// one would be a handler answering another handler's messages.
fn mangle(s : String) -> String {
  let out = StringBuilder()
  let mut first = true
  for c in s {
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      c == '_' ||
      (!first && c >= '0' && c <= '9')
    if ok {
      out.write_char(c)
    } else {
      out.write_char('_')
    }
    first = false
  }
  let text = out.to_string()
  if text.length() == 0 {
    "_"
  } else {
    text
  }
}

///|
fn B::param(self : B, name : String, typ : @wast.Type) -> @wast.Param {
  { name, typ, span: self.at(@tutuca.no_span), }
}

///|
/// A function declaration.
///
/// `export_name` is the wasm export, and it is the ABI: `tgc.make` is spelled
/// that way in the module's export section however the function is called
/// inside it.
fn B::fn_(
  self : B,
  name : String,
  params : Array[@wast.Param],
  results : Array[@wast.Type],
  body : Array[@wast.Node],
  export_name? : String,
) -> @wast.Decl {
  Fn({
    name,
    receiver: None,
    params,
    results,
    body: Some(body),
    export_name,
    import_name: None,
    is_start: false,
    is_pub: false,
    span: self.at(@tutuca.no_span),
  })
}

///|
/// A record type declaration.
fn B::record(
  self : B,
  name : String,
  fields : Array[(String, @wast.Type)],
) -> @wast.Decl {
  let fs : Array[@wast.Field] = []
  for f in fields {
    let (fname, typ) = f
    fs.push({ name: fname, mut_: false, typ, span: self.at(@tutuca.no_span), })
  }
  TypeD(
    name~,
    def=Record(parent=None, fields=fs),
    is_pub=false,
    span=self.at(@tutuca.no_span),
  )
}

///|
/// An array type alias, for the two the generated module needs locally.
fn B::array_alias(self : B, name : String, of : @wast.Type) -> @wast.Decl {
  TypeD(
    name~,
    def=Alias(ArrayOf(of)),
    is_pub=false,
    span=self.at(@tutuca.no_span),
  )
}
