// A declared type as a generator of values that inhabit it.
//
// The twin of `@info.zero_of`, walking the same `StateTy` tree with the same
// resolution of user types — so a value from here and the zero from there are
// two draws from one description rather than two opinions about it.

///|
/// How deep a generated value nests before the recursion bottoms out.
///
/// A bound rather than a budget. `Array[Array[Array[…]]]` is legal to declare
/// and a uniform walk over it produces values nobody reads the middle of; at
/// the bottom the container's own ZERO is the honest answer, because an empty
/// list is a value of the type and a truncated one is not.
pub const MAX_DEPTH : Int = 3

///|
/// How many elements a generated container holds.
///
/// Small on purpose, and skewed to the ends: a bug in a fold shows up at zero
/// and one, and a bug in a comparison shows up at two. Sizes past that cost
/// time and find nothing the third element did not.
const MAX_ITEMS : Int = 3

///|
/// A value of one declared type.
///
/// The randomized sibling of `@info.zero_of`, and total over `StateTy` for the
/// same reason: every arm answers, so a schema that parses can always be
/// generated for. Two arms answer with the zero rather than a draw and both
/// are deliberate — a component slot holds an instance this package cannot
/// build, and neither can `zero_of`.
pub fn value_of(
  def : @statedef.StateDef,
  ty : @statedef.StateTy,
  depth? : Int = MAX_DEPTH,
) -> @gen.Gen[@tutuca.Value] {
  match ty {
    TBool =>
      @gen.one_of_array([true, false]).fmap(b => (Bool(b) : @tutuca.Value))
    TInt(width~, signed~) => int_value(width, signed)
    TFloat => float_value()
    TText => text_value()
    TList(e) => items_of(def, e, depth).fmap(xs => (List(xs) : @tutuca.Value))
    // A tuple is a fixed-width list, so its length is not drawn — every
    // element is, at the declared type of that position.
    TTuple(ts) =>
      @gen.flatten_array(ts.map(t => value_of(def, t, depth=depth - 1))).fmap(xs => {
        (List(xs) : @tutuca.Value)
      })
    // The one type whose absence is a value. Null often, because a `T?` that
    // is never empty is a `T` nobody noticed.
    TOption(e) =>
      @gen.frequency([
        (1, @gen.pure((Null : @tutuca.Value))),
        (2, value_of(def, e, depth=depth - 1)),
      ])
    TOMap(v) => omap_value(def, v, depth)
    TRecord(n) => record_value(def, n, depth)
    TEnum(n) => enum_value(def, n)
    TVariant(n) => variant_value(def, n, depth)
    TFlags(n) => flags_value(def, n)
    TSet => set_value()
    // A slot holds an instance the host makes, and there is nothing here to
    // make one from. `zero_of` answers Null and so does this — the difference
    // between them is that a caller who wants children fills the slot itself.
    TComp(_) | TCompProtocols(_) => @gen.pure(@info.zero_of(def, ty))
    // `Any` is the position that most needs the tag, so it draws from every
    // scalar shape rather than settling on one. Not from containers: a value
    // no schema describes is one a codec has to read structurally, and the
    // scalars are where that goes wrong.
    TAny => any_value()
  }
}

///|
/// A whole state: every declared field, drawn at its own type.
///
/// The twin of `@info.zero_value`, and the unit a stateful property quantifies
/// over. Nothing here consults the rules — `Rules::filter` is the layer that
/// does, and keeping them apart is what lets a caller ask for states that
/// VIOLATE an invariant, which is the input a contract is tested with.
pub fn state_of(
  def : @statedef.StateDef,
  depth? : Int = MAX_DEPTH,
) -> @gen.Gen[Map[String, @tutuca.Value]] {
  let names = def.fields.map(f => f.name)
  @gen.flatten_array(def.fields.map(f => value_of(def, f.ty, depth~))).fmap(vs => {
    let out : Map[String, @tutuca.Value] = Map([])
    for i, n in names {
      out[n] = vs[i]
    }
    out
  })
}

///|
/// An integer, skewed to the corners of its declared width.
///
/// Uniform over the range would be the wrong distribution, and the reason is
/// the one the blog post this suite was written against gives: the bugs live
/// at 0, at 1, at the sign flip and at the width's edge, and a uniform draw
/// over 2^32 reaches those with probability near zero. `width` and `signed`
/// come from the declaration, so an `Int8` field is generated at `Int8`'s
/// edges rather than at `Int`'s — the decode is range-checked, and this is
/// what tests it.
fn int_value(width : Int, signed : Bool) -> @gen.Gen[@tutuca.Value] {
  let (lo, hi) = int_bounds(width, signed)
  let (blo, bhi) = body_bounds(lo, hi)
  @gen.frequency([
    // The small neighbourhood, where a fold or an off-by-one shows.
    (5, @gen.int_range(if signed { -4 } else { 0 }, 5)),
    // The edges themselves, which nothing else reaches.
    (2, @gen.one_of_array([lo, hi, lo + 1, hi - 1])),
    // And the body of the range, so the middle is not a blind spot.
    (3, @gen.int_range(blo, bhi)),
  ]).fmap(n => (Num(n.to_double()) : @tutuca.Value))
}

///|
/// What a declared width admits.
///
/// `Int` is not clamped to its own 32-bit edge for a reason worth stating:
/// state travels as JSON, where a number is a Double, so the honest bound for
/// the unsized case is the one the WIRE keeps. The narrow widths ARE clamped,
/// because those are the ones the generated decoder range-checks — and a
/// generator that never produced 128 for an `Int8` would never test that.
fn int_bounds(width : Int, signed : Bool) -> (Int, Int) {
  match (width, signed) {
    (8, true) => (-128, 127)
    (8, false) => (0, 255)
    (16, true) => (-32768, 32767)
    (16, false) => (0, 65535)
    (_, false) => (0, @int.MAX_VALUE)
    _ => (@int.MIN_VALUE, @int.MAX_VALUE)
  }
}

///|
/// A span for the uniform draw that `hi - lo` can be computed over.
///
/// `@gen.int_range` picks with `next_int().abs() % (hi - lo)`, and the full
/// signed span overflows that subtraction — so the widest int field would wrap
/// or divide by a negative rather than produce a number. Narrowing the UNIFORM
/// draw is the right fix rather than a workaround: the edges are already drawn
/// separately, and with far better odds than a uniform pick over 2^32 would
/// ever give them, so this arm's only job is to cover the middle.
fn body_bounds(lo : Int, hi : Int) -> (Int, Int) {
  let span = 1000000
  let blo = if lo < -span { -span } else { lo }
  let bhi = if hi > span { span } else { hi }
  if blo >= bhi {
    (lo, hi)
  } else {
    (blo, bhi)
  }
}

///|
/// A double, including the two a naive generator never produces.
///
/// Negative zero and the fractions that do not round-trip through a decimal
/// printer are the whole reason a float field is worth generating at all.
fn float_value() -> @gen.Gen[@tutuca.Value] {
  @gen.frequency([
    (4, @gen.one_of_array([0.0, -0.0, 1.0, -1.0, 0.5, -0.5])),
    (3, @gen.int_range(-1000, 1000).fmap(n => n.to_double())),
    (3, @gen.int_range(-1000, 1000).fmap(n => n.to_double() / 7.0)),
  ]).fmap(d => (Num(d) : @tutuca.Value))
}

///|
/// A string from a pool chosen for what breaks downstream, not for variety.
///
/// The empty string, one that needs escaping in HTML, one that needs escaping
/// in JSON, one with a path separator and one with a `~` — the last two
/// because `core/path_*` reads those as structure, and a field holding one is
/// how a path layer learns the difference between a name and a route.
fn text_value() -> @gen.Gen[@tutuca.Value] {
  @gen.one_of_array([
    "", "x", "hello", "a b", "a/b", "c~d", "<script>", "\"quoted\"", "líne\nbreak",
    "0",
  ]).fmap(s => (Str(s) : @tutuca.Value))
}

///|
/// Anything at all, as the scalars a structural decoder has to tell apart.
fn any_value() -> @gen.Gen[@tutuca.Value] {
  @gen.one_of([
    @gen.pure((Null : @tutuca.Value)),
    @gen.one_of_array([true, false]).fmap(b => (Bool(b) : @tutuca.Value)),
    @gen.int_range(-50, 50).fmap(n => (Num(n.to_double()) : @tutuca.Value)),
    text_value(),
  ])
}

///|
/// The elements of a container, at the element type.
fn items_of(
  def : @statedef.StateDef,
  e : @statedef.StateTy,
  depth : Int,
) -> @gen.Gen[Array[@tutuca.Value]] {
  if depth <= 0 {
    return @gen.pure([])
  }
  @gen.int_range(0, MAX_ITEMS).bind(n => {
    value_of(def, e, depth=depth - 1).array_with_size(n)
  })
}

///|
/// An ordered map at the declared value type. The keys are a small fixed pool
/// so that two generated maps of the same size collide on keys often — which
/// is the case a merge or a diff gets wrong.
fn omap_value(
  def : @statedef.StateDef,
  v : @statedef.StateTy,
  depth : Int,
) -> @gen.Gen[@tutuca.Value] {
  items_of(def, v, depth).fmap(vs => {
    let m : Map[String, @tutuca.Value] = Map([])
    for i, x in vs {
      m["k\{i}"] = x
    }
    Map(m)
  })
}

///|
/// A record's fields, each at its own declared type. A record this schema does
/// not declare generates its zero, exactly as `zero_of` does — the two agree
/// about a name neither can resolve.
fn record_value(
  def : @statedef.StateDef,
  n : String,
  depth : Int,
) -> @gen.Gen[@tutuca.Value] {
  guard def.user_ty(n) is Some({ kind: URecord(fs), .. }) else {
    return @gen.pure(@info.zero_of(def, TRecord(n)))
  }
  if depth <= 0 {
    return @gen.pure(@info.zero_of(def, TRecord(n)))
  }
  let names = fs.map(f => f.name)
  @gen.flatten_array(fs.map(f => value_of(def, f.ty, depth=depth - 1))).fmap(vs => {
    let m : Map[String, @tutuca.Value] = Map([])
    for i, name in names {
      m[name] = vs[i]
    }
    Map(m)
  })
}

///|
/// One of the enum's cases, by its wire spelling. An enum with no cases cannot
/// be declared, so the fallback is only reachable for a name this schema does
/// not have.
fn enum_value(def : @statedef.StateDef, n : String) -> @gen.Gen[@tutuca.Value] {
  guard def.user_ty(n) is Some({ kind: UEnum(cs), .. }) && !cs.is_empty() else {
    return @gen.pure(@info.zero_of(def, TEnum(n)))
  }
  @gen.one_of_array(cs.map(c => (Str(c.1) : @tutuca.Value)))
}

///|
/// A variant as the wire carries it: the bare case name when it carries
/// nothing, else the name followed by its payload.
///
/// Both shapes, because they are both legal and a reader that handles one is
/// the bug — the same reason `TyInfo::kind` answers `FAny` for a variant.
fn variant_value(
  def : @statedef.StateDef,
  n : String,
  depth : Int,
) -> @gen.Gen[@tutuca.Value] {
  guard def.user_ty(n) is Some({ kind: UVariant(cs), .. }) && !cs.is_empty() else {
    return @gen.pure(@info.zero_of(def, TVariant(n)))
  }
  @gen.one_of_array(cs).bind(c => {
    if c.payload.is_empty() || depth <= 0 {
      @gen.pure((Str(c.variant) : @tutuca.Value))
    } else {
      @gen.flatten_array(c.payload.map(p => value_of(def, p, depth=depth - 1))).fmap(ps => {
          let parts : Array[@tutuca.Value] = [Str(c.variant)]
          for p in ps {
            parts.push(p)
          }
          (List(parts) : @tutuca.Value)
        },
      )
    }
  })
}

///|
/// A closed set: a subset of the enum's cases, as the `Map[String, Bool]` both
/// set kinds travel as. Membership is `Bool(true)` and a non-member is ABSENT
/// rather than `Bool(false)`, which is the shape the generated mutators write.
fn flags_value(def : @statedef.StateDef, n : String) -> @gen.Gen[@tutuca.Value] {
  let members : Array[String] = match def.user_ty(n) {
    Some({ kind: UEnum(ms), .. }) => ms.map(m => m.1)
    _ => []
  }
  subset_of(members)
}

///|
/// An open set: a subset of a small pool, so two generated sets overlap often.
fn set_value() -> @gen.Gen[@tutuca.Value] {
  subset_of(["a", "b", "c"])
}

///|
/// Each member in or out independently — every subset reachable, including the
/// empty one and the full one, which a "pick n of them" draw reaches rarely.
fn subset_of(members : Array[String]) -> @gen.Gen[@tutuca.Value] {
  if members.is_empty() {
    return @gen.pure((Map(Map([])) : @tutuca.Value))
  }
  @gen.flatten_array(members.map(_ => @gen.one_of_array([true, false]))).fmap(picks => {
    let m : Map[String, @tutuca.Value] = Map([])
    for i, name in members {
      if picks[i] {
        m[name] = Bool(true)
      }
    }
    Map(m)
  })
}
