// Writing Wax without writing Wax.
//
// `marianoguerra/wax/ast` is the tree a code generator builds and
// `marianoguerra/wax/ast/build` has the constructors for a module's FIELDS —
// but not for the instructions inside one, which is where a generator spends
// all of its time. These are those: one short name per construct, so the
// emitters below read as the Wax they stand for rather than as a tree walk.
//
// Nothing here is card-specific. It is the layer `cardwasm/reference/counter.wax`
// is written in, written out in MoonBit.

///|
fn ins(d : @ast.InstrDesc[@basic.Location]) -> @abi.I {
  @ast.no_loc_instr(d)
}

///|
fn body(xs : Array[@abi.I]) -> @basic.Annotated[Array[@abi.I], @basic.Location] {
  { desc: xs, info: @basic.dummy_loc }
}

///|
/// The source of distinct spans. See `id`.
///
/// Process-global rather than per-compile, which is stricter than needed:
/// `binding_slots` is rebuilt per function (`emit/wasm/module.mbt:699`), so
/// uniqueness only has to hold within one function. Nothing is gained by
/// resetting it and a counter that only ever goes up cannot develop a reuse
/// bug, so it stays.
let spans : @build.Spans = @build.Spans::new(fname="<cardwasm>")

///|
/// A name, at a location no other name shares.
///
/// The uniqueness is LOAD-BEARING, and it is the one thing about Wax's AST a
/// generator has to know. A `let` binding's slot is recorded against the
/// binding's source offset — `binding_slots[name.loc.start.cnum]` in
/// `emit/wasm/module.mbt` — precisely so that a shadowing `let` is not in
/// scope for its own initializer. A whole function's identifiers built at one
/// location collapse its locals onto one slot.
///
/// Wax now REFUSES that outright — `AmbiguousBinding`, raised by `claim_slot`
/// — so the failure mode is a `LowerError` naming the identifier rather than a
/// module that is quietly wrong. This used to say the opposite, and the older
/// wording is why: before that check landed, getting this wrong produced
/// something that ran and misbehaved.
///
/// `@build.Spans` is upstream's answer to exactly this, and is what this now
/// delegates to. Each span it mints is one column on a line of its own, so the
/// line a diagnostic prints — `File "<cardwasm>", line 412` — is a usable node
/// id. That matters for `BadModule`, whose whole job is to be read by whoever
/// is debugging this generator.
fn id(name : String) -> @ast.Ident {
  spans.ident(name)
}

///|
/// The i32 type, which is nearly every type in a canonical-ABI core module.
let i32_ : @abi.VT = I32

///|
let i64_ : @abi.VT = I64

///|
/// What a number reads as outside the value model. Only the escape prelude's
/// `num_<field>` answers one — everything the generator itself builds stays a
/// `&jv_value`, because tutuca has exactly one number and unwrapping it early
/// is how two of them stop being equal.
let f64_ : @abi.VT = F64

///|
/// A non-nullable reference to a type the stdlib declares.
///
/// The reason `@build` has no builder for this: it is the one place a generator
/// has to name something it did not define, and Wax resolves that name against
/// whatever was concatenated ahead of it. `jv_value` and `jv_record_value` come
/// from `vendor/wax/immutable_value.wax` and `pv_vector` from
/// `persistent_vector.wax`, so getting one of these wrong is a diagnostic
/// against the stdlib rather than against this file.
fn ref_(name : String) -> @abi.VT {
  Ref({ nullable: false, typ: Type(id(name)) })
}

///|
/// A nullable one — `&?T`. What "no arguments" is.
fn refopt_(name : String) -> @abi.VT {
  Ref({ nullable: true, typ: Type(id(name)) })
}

///|
/// `null` — the empty argument list, which allocates nothing.
fn nullref() -> @abi.I {
  ins(Null)
}

///|
/// What every expression this generator compiles leaves on the stack.
///
/// It was `i32_` — a pointer to a 16-byte cell — for as long as the value
/// runtime was linear memory. That it is now a typed reference is what makes a
/// whole class of generator bug into a Wax diagnostic: an expression that used
/// to be an integer indistinguishable from a length or an offset now has a type
/// the checker knows.
let jv_ : @abi.VT = ref_("jv_value")

///|
/// The state an expression reads `.field` from.
let rec_ : @abi.VT = ref_("jv_record_value")

///|
/// A declaration's arguments. Nullable because a call with none allocates
/// nothing.
let args_ : @abi.VT = refopt_("pv_vector")

// ---------------------------------------------------------------------------
// values

///|
fn i32c(n : Int) -> @abi.I {
  ins(Int(n.to_string()))
}

///|
/// A name: a local, a parameter, a global, or a function being referred to.
fn get(name : String) -> @abi.I {
  ins(Get(id(name)))
}

///|
/// `name = value`.
fn set(name : String, value : @abi.I) -> @abi.I {
  ins(Set(id(name), None, value))
}

///|
/// `let name = value;`
fn let_(name : String, value : @abi.I) -> @abi.I {
  ins(Let([(Some(id(name)), None)], Some(value)))
}

///|
/// A direct call: `name(args)`.
fn call(name : String, args : Array[@abi.I]) -> @abi.I {
  ins(Call(get(name), args))
}

///|
/// A method call on a receiver: `recv.meth(args)`. Memory accesses and the
/// float intrinsics are both spelled this way.
fn mcall(recv : @abi.I, meth : String, args : Array[@abi.I]) -> @abi.I {
  ins(Call(ins(StructGet(recv, id(meth))), args))
}

///|
/// `MEM.meth(args)` — the one memory this module declares.
fn mem(meth : String, args : Array[@abi.I]) -> @abi.I {
  mcall(get(@abi.memory_name), meth, args)
}

// ---------------------------------------------------------------------------
// operators

///|
fn binop(op : @ast.BinOp, a : @abi.I, b : @abi.I) -> @abi.I {
  ins(BinOpI({ desc: op, info: @basic.dummy_loc }, a, b))
}

///|
fn add(a : @abi.I, b : @abi.I) -> @abi.I {
  binop(Add, a, b)
}

///|
fn sub(a : @abi.I, b : @abi.I) -> @abi.I {
  binop(Sub, a, b)
}

///|
fn mul(a : @abi.I, b : @abi.I) -> @abi.I {
  binop(Mul, a, b)
}

///|
/// Unsigned division: `/u`. Wax refuses a bare `/` on integers, which is the
/// right call — the two are different instructions.
fn divu(a : @abi.I, b : @abi.I) -> @abi.I {
  binop(Div(Some(Unsigned)), a, b)
}

///|
fn andi(a : @abi.I, b : @abi.I) -> @abi.I {
  binop(And, a, b)
}

///|
fn eq(a : @abi.I, b : @abi.I) -> @abi.I {
  binop(Eq, a, b)
}

///|
fn ne(a : @abi.I, b : @abi.I) -> @abi.I {
  binop(Ne, a, b)
}

///|
/// Signed comparisons, for the i32 counters and indices generated code uses.
fn lts(a : @abi.I, b : @abi.I) -> @abi.I {
  binop(Lt(Some(Signed)), a, b)
}

///|
fn les(a : @abi.I, b : @abi.I) -> @abi.I {
  binop(Le(Some(Signed)), a, b)
}

///|
fn gts(a : @abi.I, b : @abi.I) -> @abi.I {
  binop(Gt(Some(Signed)), a, b)
}

///|
fn ges(a : @abi.I, b : @abi.I) -> @abi.I {
  binop(Ge(Some(Signed)), a, b)
}

// ---------------------------------------------------------------------------
// casts

// ---------------------------------------------------------------------------
// control flow

///|
fn if_(cond : @abi.I, then_ : Array[@abi.I], else_ : Array[@abi.I]) -> @abi.I {
  ins(
    If(
      label=None,
      typ={ params: [], results: [] },
      cond~,
      if_block=body(then_),
      else_block=if else_.is_empty() { None } else { Some(body(else_)) },
    ),
  )
}

///|
/// An `if` in a VALUE position: both arms leave one value of type `ty`.
fn if_val(
  ty : @abi.VT,
  cond : @abi.I,
  then_ : Array[@abi.I],
  else_ : Array[@abi.I],
) -> @abi.I {
  ins(
    If(
      label=None,
      typ={ params: [], results: [ty] },
      cond~,
      if_block=body(then_),
      else_block=Some(body(else_)),
    ),
  )
}

///|
/// `let name: ty;` — declared, at its type's zero, assigned later.
///
/// For a nullable reference that zero is `null`, which is what makes "the
/// target a `new` has not made yet" a state the type can hold rather than a
/// flag beside it.
fn let_zero(name : String, ty : @abi.VT) -> @abi.I {
  ins(Let([(Some(id(name)), Some(ty))], None))
}

///|
/// `while cond { block }`, with an optional step run at the end of each turn.
fn while_(cond : @abi.I, step : @abi.I?, block : Array[@abi.I]) -> @abi.I {
  ins(While(label=None, cond~, step~, block=body(block)))
}

///|
/// `name op= value`, e.g. `i += 1`.
fn setop(name : String, op : @ast.BinOp, value : @abi.I) -> @abi.I {
  ins(Set(id(name), Some({ desc: op, info: @basic.dummy_loc }), value))
}

///|
fn ret(value : @abi.I?) -> @abi.I {
  ins(Return(value))
}

// ---------------------------------------------------------------------------
// module fields

///|
/// A function, optionally exported under a wasm name of its own, and
/// optionally the module's `start`.
///
/// `start` is how the schema and the string constants get built exactly once,
/// before the host can call anything: a wasm start function runs at
/// instantiation. The alternative was a flag checked at the top of every
/// export, which is the same work plus a branch and a way to forget one.
fn func(
  name : String,
  params? : Array[(String, @abi.VT)] = [],
  results? : Array[@abi.VT] = [],
  export_as? : String,
  start? : Bool = false,
  body~ : Array[@abi.I],
) -> @abi.Field {
  let attributes : Array[@ast.Attribute] = match export_as {
    Some(n) => [@build.exported(name=n)]
    None => []
  }
  if start {
    attributes.push({
      attr_name: "start",
      attr_value: None,
      attr_guard: None,
      attr_span: @basic.dummy_loc,
    })
  }
  @build.func(
    name,
    params=params.map(p => (Some(p.0), p.1)),
    results~,
    body~,
    attributes~,
  )
}

///|
/// A mutable global with an i32 initializer.
fn global_i32(name : String, value : Int) -> @abi.Field {
  @build.global(name, typ=Some(i32_), mut_=true, def=i32c(value))
}

///|
/// The module's one linear memory, exported as `memory` because the canonical
/// ABI reads and writes it from the host side.
fn memory_field(pages : Int) -> @abi.Field {
  @build.field(
    Memory(
      name=id(@abi.memory_name),
      address_type=I32,
      limits=Some((pages.to_uint64(), None)),
      page_size_log2=None,
      shared=false,
      data=[],
      attributes=[@build.exported(name="memory")],
    ),
  )
}

///|
/// One active data segment: the constant pool, laid down at `offset`.
fn data_field(name : String, offset : Int, bytes : Bytes) -> @abi.Field {
  @build.field(
    Data(
      name=Some(id(name)),
      mode=Active(id(@abi.memory_name), i32c(offset)),
      init=[Str(bytes)],
      attributes=[],
    ),
  )
}
