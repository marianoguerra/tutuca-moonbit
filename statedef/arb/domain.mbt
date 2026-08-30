// A declared DOMAIN, read backwards: as a generator of the values it admits.
//
// This is the half an `invariant` cannot offer, and the reason the `where`
// vocabulary is closed. `Rules::filter` narrows a generator by REJECTION —
// draw, ask, discard — which works for a rule that most states happen to
// satisfy and does not work at all for `0 <= i < len(items)`: a uniform draw
// over `Int` hits a three-element list with probability near 2^-30, so a
// filtered generator gives up rather than narrowing.
//
// Read backwards, the same declaration is a range to draw FROM, and every
// draw is in it. That is the whole feature: the fuzzer stops spending its
// steps on states no interaction could reach.
//
// What is deliberately KEPT from the unconstrained generators is the SKEW.
// `int_value`'s corner bias — 0, 1, the sign flip, the width's edge — is the
// package's thesis, and narrowing a range is not a reason to start drawing
// uniformly over the smaller one. A constrained index still draws its own
// first, last and middle by preference.

///|
/// A value that satisfies `domain`, given the fields already drawn.
///
/// `None` when nothing here can produce one — the target field has not been
/// drawn, or holds something the relation cannot read. The caller falls back
/// to the field's unconstrained generator, which is the honest answer: a
/// domain that could not be inverted has not narrowed anything, and a draw
/// the runtime then refuses is a truthful test of the refusal.
pub fn value_in_domain(
  domain : @tutuca.Domain,
  drawn : Map[String, @tutuca.Value],
) -> @gen.Gen[@tutuca.Value]? {
  match domain {
    @tutuca.DIndexOf(field~, allow_none~) => {
      guard drawn.get(field) is Some(seq) && @tutuca.size_of(seq) is Some(len) else {
        return None
      }
      // An empty list has no valid index at all, so the sentinel is the only
      // value left — and without one there is nothing to draw.
      if len == 0 {
        return if allow_none {
          Some(@gen.one_of_array([(Num(-1.0) : @tutuca.Value), Num(0.0)]))
        } else {
          None
        }
      }
      let ends : Array[@tutuca.Value] = [Num(0.0), Num((len - 1).to_double())]
      let body = @gen.int_range(0, len).fmap(i => {
        (Num(i.to_double()) : @tutuca.Value)
      })
      // The two ends first, for the same reason `int_value` draws the width's
      // edges first: a fold and an off-by-one both live there.
      let in_range = @gen.frequency([(2, @gen.one_of_array(ends)), (3, body)])
      if allow_none {
        Some(
          @gen.frequency([
            (1, @gen.pure((Num(-1.0) : @tutuca.Value))),
            (5, in_range),
          ]),
        )
      } else {
        Some(in_range)
      }
    }
    @tutuca.DKeyOf(field~) => {
      guard drawn.get(field) is Some(Map(m)) else { return None }
      let keys = m.keys().collect()
      if keys.is_empty() {
        return None
      }
      Some(@gen.one_of_array(keys.map(k => (Str(k) : @tutuca.Value))))
    }
    // A member is a key the set HOLDS — value `Bool(true)`. A key present and
    // false is non-membership, which is what `toggleIn` leaves behind.
    @tutuca.DMemberOf(field~) => {
      guard drawn.get(field) is Some(Map(m)) else { return None }
      let members : Array[@tutuca.Value] = []
      for k, held in m {
        if held is Bool(true) {
          members.push(Str(k))
        }
      }
      if members.is_empty() {
        return None
      }
      Some(@gen.one_of_array(members))
    }
    @tutuca.DSubsetOf(field~) => {
      guard drawn.get(field) is Some(Map(m)) else { return None }
      let members : Array[String] = []
      for k, held in m {
        if held is Bool(true) {
          members.push(k)
        }
      }
      // Each member in or out independently, which is the same walk
      // `subset_of` already makes over a closed set's declared members.
      Some(
        @gen.flatten_array(members.map(_ => @gen.one_of_array([true, false]))).fmap(picks => {
            let out : Map[String, @tutuca.Value] = Map([])
            for i, k in members {
              if picks[i] {
                out[k] = Bool(true)
              }
            }
            (Map(out) : @tutuca.Value)
          },
        ),
      )
    }
    @tutuca.DOneOf(members) => {
      if members.is_empty() {
        return None
      }
      Some(@gen.one_of_array(members.map(m => (Str(m) : @tutuca.Value))))
    }
    // The list the value has to come from, drawn from. An empty one bounds
    // nothing a draw can satisfy — the same answer `DKeyOf` gives for an empty
    // map: no generator, and the caller falls back to the field's own.
    @tutuca.DElementOf(field~) => {
      guard drawn.get(field) is Some(List(items)) && !items.is_empty() else {
        return None
      }
      Some(@gen.one_of_array(items))
    }
    // A length, not a value. The caller is what knows how to build a
    // collection of a given size, so these two answer the SIZE and
    // `size_in_domain` is what reads them.
    @tutuca.DNonEmpty | @tutuca.DLen(_) => None
    @tutuca.DCompare(op~, rhs~) => {
      guard operand_of(rhs, drawn) is Some(r) else { return None }
      let (lo, hi) = match op {
        @tutuca.DGe => (r, r + BAND)
        @tutuca.DGt => (r + 1.0, r + BAND)
        @tutuca.DLe => (r - BAND, r)
        @tutuca.DLt => (r - BAND, r - 1.0)
      }
      Some(num_between(lo, hi))
    }
    @tutuca.DBetween(lo~, hi~) => {
      guard operand_of(lo, drawn) is Some(a) && operand_of(hi, drawn) is Some(b) else {
        return None
      }
      if a > b {
        return None
      }
      Some(num_between(a, b))
    }
  }
}

///|
/// How far past an open bound a draw ranges.
///
/// A `>= 0` has no upper end, and a generator has to pick one. Small, because
/// the bugs a bound is protecting against live at the bound: `0`, `1`, and
/// just past it. Drawing `2^31` for a `count >= 0` would be technically in
/// the domain and would find nothing the third value did not.
const BAND : Double = 32.0

///|
/// A whole number in `[lo, hi]`, skewed to the ends.
///
/// The corner bias `int_value` argues for, kept across the narrowing: the ends
/// of a range are where an off-by-one shows, and a uniform draw over a
/// thirty-wide band reaches them one time in fifteen.
fn num_between(lo : Double, hi : Double) -> @gen.Gen[@tutuca.Value] {
  let a = lo.to_int()
  let b = hi.to_int()
  if a >= b {
    return @gen.pure((Num(a.to_double()) : @tutuca.Value))
  }
  @gen.frequency([
    (2, @gen.one_of_array([a, b])),
    (1, @gen.one_of_array([a + 1, b - 1])),
    (3, @gen.int_range(a, b + 1)),
  ]).fmap(n => (Num(n.to_double()) : @tutuca.Value))
}

///|
/// A comparison operand as a number, given the fields already drawn.
fn operand_of(
  o : @tutuca.DomainOperand,
  drawn : Map[String, @tutuca.Value],
) -> Double? {
  match o {
    @tutuca.DLit(n) => Some(n)
    @tutuca.DField(f) =>
      match drawn.get(f) {
        Some(Num(n)) => Some(n)
        _ => None
      }
  }
}

///|
/// How many elements a collection under these domains may hold.
///
/// `None` when the domains say nothing about a length, which is the common
/// case and means "draw the usual number".
pub fn size_in_domain(
  domains : Array[@tutuca.Domain],
  drawn : Map[String, @tutuca.Value],
) -> @gen.Gen[Int]? {
  let mut least = 0
  let mut most = MAX_ITEMS
  let mut said = false
  for d in domains {
    match d {
      @tutuca.DNonEmpty => {
        least = @cmp.maximum(least, 1)
        said = true
      }
      @tutuca.DLen(inner) =>
        // A bound on the length is read the same way a bound on a value is,
        // and then clamped into the sizes this package is willing to build:
        // `len <= 10000` is a legal thing to declare and not a list anybody
        // wants generated.
        match inner {
          @tutuca.DCompare(op~, rhs~) =>
            match operand_of(rhs, drawn) {
              Some(r) => {
                said = true
                match op {
                  @tutuca.DGe => least = @cmp.maximum(least, r.to_int())
                  @tutuca.DGt => least = @cmp.maximum(least, r.to_int() + 1)
                  @tutuca.DLe => most = @cmp.minimum(most, r.to_int())
                  @tutuca.DLt => most = @cmp.minimum(most, r.to_int() - 1)
                }
              }
              None => ()
            }
          @tutuca.DBetween(lo~, hi~) =>
            match (operand_of(lo, drawn), operand_of(hi, drawn)) {
              (Some(x), Some(y)) => {
                said = true
                least = @cmp.maximum(least, x.to_int())
                most = @cmp.minimum(most, y.to_int())
              }
              _ => ()
            }
          _ => ()
        }
      _ => ()
    }
  }
  if !said {
    return None
  }
  // A declaration that admits no size at all — `len >= 5` beside `len <= 2`.
  // The low bound wins: a caller asking for a length wants one, and a
  // contradiction is the author's to notice through the refusal it causes.
  if most < least {
    most = least
  }
  Some(@gen.int_range(least, most + 1))
}

///|
/// What a field's domains say about OTHER fields, implicitly.
///
/// `where cursor is index of .photos` is a statement about `cursor`, and it is
/// also — unavoidably — a statement about `photos`: if an index into it always
/// exists, then it is never empty. Nobody writes that second clause, and a
/// generator that ignored it would draw `photos: []` and then have no legal
/// cursor to pair with it, which is a state the declaration says cannot
/// happen.
///
/// GENERATION ONLY, and the asymmetry is deliberate. The runtime does not
/// enforce this: a component that empties its list is refused on the next
/// write to `cursor`, by the clause that was actually written, and inventing a
/// second refusal on the author's behalf would report a field they said
/// nothing about. What the generator needs is different — it has to CHOOSE a
/// list length, and choosing one that admits no cursor is choosing to generate
/// an impossible state.
///
/// `or none` is exactly the escape: a selection field that admits the empty
/// answer implies nothing about the list, because the empty list is one of the
/// cases it was written for.
pub fn implied_domains(
  all : Array[@tutuca.FieldDomain],
  field : String,
) -> Array[@tutuca.Domain] {
  let out : Array[@tutuca.Domain] = []
  for d in all {
    let implies_nonempty = match d.domain {
      @tutuca.DIndexOf(field=target, allow_none~) =>
        target == field && !allow_none
      @tutuca.DKeyOf(field=target) | @tutuca.DMemberOf(field=target) =>
        target == field
      _ => false
    }
    if implies_nonempty && !out.contains(@tutuca.DNonEmpty) {
      out.push(@tutuca.DNonEmpty)
    }
  }
  out
}

///|
/// Which fields a domain reads, so a caller can draw them first.
pub fn domain_deps(domain : @tutuca.Domain) -> Array[String] {
  match domain {
    @tutuca.DIndexOf(field~, ..)
    | @tutuca.DKeyOf(field~)
    | @tutuca.DMemberOf(field~)
    | @tutuca.DElementOf(field~)
    | @tutuca.DSubsetOf(field~) => [field]
    @tutuca.DCompare(rhs~, ..) => operand_dep(rhs)
    @tutuca.DBetween(lo~, hi~) => operand_dep(lo) + operand_dep(hi)
    @tutuca.DLen(inner) => domain_deps(inner)
    @tutuca.DOneOf(_) | @tutuca.DNonEmpty => []
  }
}

///|
fn operand_dep(o : @tutuca.DomainOperand) -> Array[String] {
  match o {
    @tutuca.DField(f) => [f]
    @tutuca.DLit(_) => []
  }
}
