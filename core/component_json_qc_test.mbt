// The round-trip property, universally quantified over (schema, value) pairs.
//
// The example suite next door covers each `TyInfo` case by hand; this covers
// the composition of them, which is where a codec written as two mirrored
// tables actually goes wrong. `Value`'s Eq on an `Obj` is `obj_eq` —
// structural over the schema — so the equality asserted here is definitionally
// the fidelity claim the file header makes.
//
// The generator EXCLUDES `Fn` and schema-less `Obj`, which is not a
// convenience: those are two of the documented gaps, and leaving them out is
// what makes the gaps visible as generator exclusions rather than as prose
// nothing checks. (`core/path_qc_test.mbt` excludes `Fn` for the same reason —
// so `Value` Eq is total.)

///|
/// A type, and a value inhabiting it, generated together — a value drawn
/// independently of its type would be rejected by the codec almost every time
/// and the property would pass vacuously.
fn gen_ty_and_value(depth : Int) -> @gen.Gen[(@core.TyInfo, @core.Value)] {
  if depth <= 0 {
    return gen_scalar_ty()
  }
  @gen.one_of([
    gen_scalar_ty(),
    // a list of one element type
    gen_ty_and_value(depth - 1).bind(tv => {
      @gen.int_range(0, 3).fmap(n => {
        let items : Array[@core.Value] = []
        for _ in 0..<n {
          items.push(tv.1)
        }
        ((TyList(tv.0) : @core.TyInfo), (List(items) : @core.Value))
      })
    }),
    // an ordered map of one value type
    gen_ty_and_value(depth - 1).bind(tv => {
      @gen.one_of_array([["a"], ["a", "b"], []]).fmap(keys => {
        let m : Map[String, @core.Value] = Map([])
        for k in keys {
          m[k] = tv.1
        }
        ((TyOMap(tv.0) : @core.TyInfo), (Map(m) : @core.Value))
      })
    }),
    // a free slot: empty, or holding an instance
    gen_qc_instance(depth - 1).fmap(v => ((TyComp(None) : @core.TyInfo), v)),
    // `any`, which is the position that most needs the tag
    gen_qc_instance(depth - 1).fmap(v => ((TyAny : @core.TyInfo), v)),
  ])
}

///|
fn gen_scalar_ty() -> @gen.Gen[(@core.TyInfo, @core.Value)] {
  @gen.one_of([
    @gen.one_of_array([true, false]).fmap(b => {
      ((TyBool : @core.TyInfo), (Bool(b) : @core.Value))
    }),
    @gen.int_range(-50, 50).fmap(n => {
      ((TyInt : @core.TyInfo), (Num(n.to_double()) : @core.Value))
    }),
    @gen.one_of_array(["", "x", "a/b", "c~d", "hello"]).fmap(s => {
      ((TyText : @core.TyInfo), (Str(s) : @core.Value))
    }),
  ])
}

///|
/// An instance whose schema is generated alongside it: `f0`, `f1`, … each with
/// a generated type and a value of that type. Null half the time, because an
/// empty slot is the case a value-inspecting codec cannot see.
fn gen_qc_instance(depth : Int) -> @gen.Gen[@core.Value] {
  if depth <= 0 {
    return @gen.pure(Null)
  }
  @gen.int_range(0, 3).bind(n => {
    gen_ty_and_value(depth - 1)
    .array_with_size(n)
    .fmap(tvs => {
      if tvs.is_empty() {
        return Null
      }
      let fields : Array[@core.FieldInfo] = []
      let values : Map[String, @core.Value] = Map([])
      for i, tv in tvs {
        let name = "f\{i}"
        fields.push(@core.FieldInfo::new(name, tv.0))
        values[name] = tv.1
      }
      let sc = @core.SchemaInfo::new(
        name="Gen\{tvs.length()}",
        fingerprint="qc",
        fields~,
      )
      Obj(QcNode::{ sc, fields: values })
    })
  })
}

///|
priv struct QcNode {
  sc : @core.SchemaInfo
  fields : Map[String, @core.Value]
}

///|
impl @core.Obj for QcNode with fn obj_schema(self) {
  Some(self.sc)
}

///|
impl @core.Obj for QcNode with fn obj_field(self, name) {
  self.fields.get(name)
}

///|
/// A source that rebuilds a `QcNode` from the schema carried in the document's
/// own shape. It cannot `describe` — the schemas are generated per value and
/// there is no table to look them up in — which is exactly the structural
/// decoding path the trait's default exists for, and the harder one to get
/// right: with no declared types, every tag has to be found by the walk.
fn qc_source() -> @core.FnSource {
  @core.FnSource::new((_m, name, args, _at) => {
    let fields : Array[@core.FieldInfo] = []
    let values : Map[String, @core.Value] = Map([])
    // Field ORDER is the document's, which is the schema's, because the
    // encoder writes in schema order and a Map preserves insertion order.
    for k, v in args {
      fields.push(@core.FieldInfo::new(k, TyAny))
      values[k] = v
    }
    Some(
      Obj(QcNode::{
        sc: @core.SchemaInfo::new(name~, fingerprint="qc", fields~),
        fields: values,
      }),
    )
  })
}

///|
/// Structural equality that ignores the declared TYPES, because the source
/// above cannot recover them — only the names, the order and the values, which
/// is what `obj_eq` compares anyway.
fn same(a : @core.Value, b : @core.Value) -> Bool {
  match (a, b) {
    (Obj(x), Obj(y)) => {
      guard x.obj_schema() is Some(sx) && y.obj_schema() is Some(sy) else {
        return false
      }
      guard sx.name == sy.name && sx.fields.length() == sy.fields.length() else {
        return false
      }
      for i, f in sx.fields {
        guard sy.fields[i].name == f.name else { return false }
        guard same(
          x.obj_field(f.name).unwrap_or(Null),
          y.obj_field(f.name).unwrap_or(Null),
        ) else {
          return false
        }
      }
      true
    }
    (List(xs), List(ys)) => {
      guard xs.length() == ys.length() else { return false }
      for i, x in xs {
        guard same(x, ys[i]) else { return false }
      }
      true
    }
    (Map(xm), Map(ym)) => {
      guard xm.size() == ym.size() else { return false }
      for k, x in xm {
        guard ym.get(k) is Some(y) && same(x, y) else { return false }
      }
      true
    }
    _ => a == b
  }
}

///|
test "property: an instance round-trips through its tagged document" {
  @qc.quick_check(
    @qc.forall(gen_qc_instance(4), v => {
      guard v is Obj(_) else { return true }
      match
        @core.Value::from_component_json(v.to_component_json(), qc_source()) {
        Some(back) => same(back, v)
        None => false
      }
    }),
    max_success=300,
  )
}

///|
test "property: the document is stable — encoding a round trip changes nothing" {
  @qc.quick_check(
    @qc.forall(gen_qc_instance(4), v => {
      guard v is Obj(_) else { return true }
      let doc = v.to_component_json()
      match @core.Value::from_component_json(doc, qc_source()) {
        Some(back) => back.to_component_json().stringify() == doc.stringify()
        None => false
      }
    }),
    max_success=300,
  )
}
