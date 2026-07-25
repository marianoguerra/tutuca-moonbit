// Runtime values as path nodes (the JS role of Immutable.js Map/List in
// path.js Step.lookup/setValue). Containers answer traversal; with_* is
// copy-on-write over the ONE container on the spine, so untouched siblings
// are shared. Scalars answer as_key/as_value only. Obj arms delegate to the
// component-instance trait (the hybrid seam): plain data carries no handlers,
// instances answer handler() through Obj::obj_handler.

///|
pub impl PathNode for Value with fn field(self, name) {
  match self {
    Map(m) =>
      match m.get(name) {
        Some(v) => Some(v as &PathNode)
        None => None
      }
    Obj(o) =>
      match o.obj_field(name) {
        Some(v) => Some(v as &PathNode)
        None => None
      }
    _ => None
  }
}

///|
pub impl PathNode for Value with fn item(self, key) {
  match (self, key) {
    (List(a), KInt(i)) =>
      if i >= 0 && i < a.length() {
        Some(a[i] as &PathNode)
      } else {
        None
      }
    (Map(m), KStr(s)) =>
      match m.get(s) {
        Some(v) => Some(v as &PathNode)
        None => None
      }
    (Obj(o), key) =>
      match o.obj_item(key) {
        Some(v) => Some(v as &PathNode)
        None => None
      }
    _ => None
  }
}

///|
pub impl PathNode for Value with fn with_field(self, name, v) {
  match (self, v.as_value()) {
    (Map(m), Some(value)) => {
      // Writing back the very object already stored leaves the container
      // structurally identical, so hand back THIS one: the spine rebuild
      // above collapses level by level and the root keeps its identity,
      // which is what the render cache and the transactor's change check
      // both read as "nothing happened".
      if m.get(name) is Some(old) && physical_equal(old, value) {
        return Some(self as &PathNode)
      }
      let out = m.copy()
      out[name] = value
      Some(Value::Map(out) as &PathNode)
    }
    (Obj(o), Some(value)) =>
      match o.obj_with_field(name, value) {
        Some(nv) => Some(nv as &PathNode)
        None => None
      }
    _ => None
  }
}

///|
pub impl PathNode for Value with fn with_item(self, key, v) {
  match (self, key, v.as_value()) {
    (List(a), KInt(i), Some(value)) =>
      if i >= 0 && i < a.length() {
        // see with_field: an identical write keeps the container's identity
        if physical_equal(a[i], value) {
          return Some(self as &PathNode)
        }
        let out = a.copy()
        out[i] = value
        Some(Value::List(out) as &PathNode)
      } else {
        None
      }
    (Map(m), KStr(s), Some(value)) => {
      if m.get(s) is Some(old) && physical_equal(old, value) {
        return Some(self as &PathNode)
      }
      let out = m.copy()
      out[s] = value
      Some(Value::Map(out) as &PathNode)
    }
    (Obj(o), key, Some(value)) =>
      match o.obj_with_item(key, value) {
        Some(nv) => Some(nv as &PathNode)
        None => None
      }
    _ => None
  }
}

///|
pub impl PathNode for Value with fn as_key(self) {
  match self {
    Str(s) => Some(KStr(s))
    Num(n) => {
      let i = n.to_int()
      if i.to_double() == n {
        Some(KInt(i))
      } else {
        None
      }
    }
    _ => None
  }
}

///|
pub impl PathNode for Value with fn as_value(self) {
  Some(self)
}

///|
pub impl PathNode for Value with fn handler(self, bucket, name) {
  match self {
    Obj(o) => o.obj_handler(bucket, name)
    _ => None
  }
}
