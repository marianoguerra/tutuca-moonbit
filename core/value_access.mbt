// Coercing accessors: total reads with defaults, for handler args, loop items
// and typed-state decodes. The permissive counterpart of pattern matching —
// use a match when the shape distinction matters.

///|
pub fn Value::int(self : Value, default? : Int = 0) -> Int {
  match self {
    Num(n) => n.to_int()
    _ => default
  }
}

///|
pub fn Value::num(self : Value, default? : Double = 0) -> Double {
  match self {
    Num(n) => n
    _ => default
  }
}

///|
pub fn Value::str(self : Value, default? : String = "") -> String {
  match self {
    Str(s) => s
    _ => default
  }
}

///|
pub fn Value::bool(self : Value, default? : Bool = false) -> Bool {
  match self {
    Bool(b) => b
    _ => default
  }
}

///|
/// The list payload; [] for non-lists (shared empty NOT returned — fresh).
pub fn Value::list(self : Value) -> Array[Value] {
  match self {
    List(a) => a
    _ => []
  }
}

///|
/// The map payload; empty for non-maps.
pub fn Value::entries(self : Value) -> Map[String, Value] {
  match self {
    Map(m) => m
    _ => Map([])
  }
}

///|
/// Field access that works on Map values and Obj instances alike; Null for
/// anything else (including missing fields).
pub fn Value::field(self : Value, name : String) -> Value {
  match self {
    Map(m) => m.get(name).unwrap_or(Null)
    Obj(o) => o.obj_field(name).unwrap_or(Null)
    _ => Null
  }
}
