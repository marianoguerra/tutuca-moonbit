// Typed-state component definitions: the component() builder over a state
// struct S (derive(ToJson, FromJson)), plus the shared Component machinery
// (views, styles, provide/lookup compilation, make).

///|
let comp_id_counter : Ref[Int] = { val: 0 }

///|
fn next_comp_id() -> Int {
  comp_id_counter.val = comp_id_counter.val + 1
  comp_id_counter.val
}

///|
fn[V] map_keys(m : Map[String, V]) -> Array[String] {
  let out : Array[String] = []
  for k, _ in m {
    out.push(k)
  }
  out
}

///|
fn cap_first(s : String) -> String {
  if s.length() == 0 {
    return s
  }
  let head = s[0:1]
  let tail = s[1:]
  head.to_owned().to_upper() + tail.to_owned()
}

///|
priv struct EmptyScope {}

///|
impl @anode.MacroScope for EmptyScope with fn lookup_macro(_self, _name) {
  None
}

///|
/// Shared Component construction: views, styles, provide/lookup — everything
/// except field specs and the make closure.
fn new_component(
  name : String,
  common_style : String,
  global_style : String,
  views : Map[String, @anode.View],
  provide : Map[String, String],
  lookup : Map[String, LookupSpec],
  specs : Map[String, FieldSpec],
  mutate_names? : Array[String] = [],
  compute_names? : Array[String] = [],
  swap_names? : Array[String] = [],
  alter_names? : Array[String] = [],
  generated_names? : Array[String] = [],
  has_update? : Bool = false,
) -> Component {
  // Views arrive already built — either compiled ahead of time by
  // `tutuca gen-views` (View::from_ir) or parsed from source by
  // @anode.View::new; both are @anode.View, and Component::compile finishes
  // whichever needs it. Each carries its own per-view style.
  let vs : Map[String, @anode.View] = Map([])
  for vname, v in views {
    vs[vname] = v
  }
  {
    id: next_comp_id(),
    name,
    views: vs,
    common_style,
    global_style,
    specs,
    mutate_names,
    compute_names,
    swap_names,
    alter_names,
    generated_names,
    has_update,
    make_fn: _args => Null,
    raw_provide: provide,
    raw_lookup: lookup,
    provide: Map([]),
    lookup: Map([]),
    scope: None,
  }
}

///|
/// Define a typed-state component. `init` is a plain struct with
/// derive(ToJson, FromJson): its fields become the component's fields (names,
/// defaults and kinds), compiler-checked inside every handler. Buckets:
/// - update: ALL effectful dispatches in one pattern match over Dispatch
///   (Input/Receive/Bubble/Response), returning the new state (None = no
///   change).
/// - mutate: pure $-callable state changes ($inc in views).
/// - compute: $-callable value reads ($label in value positions).
/// - when / enrich / enrich_scope / loop_with: the render-time directive
///   buckets, each with its own typed signature (@when filter -> Bool;
///   @enrich-with mutates the binds map; the scope form returns binds;
///   @loop-with returns a LoopWith slice/order plan).
/// Auto-mutators are generated per field (setX / updateX / resetX / toggleX /
/// xLen / pushInX / setInXAt / ...); user mutate/compute win over them.
/// `specs` adds Value-level slot fields (child components via
/// FieldSpec::comp) and overrides FSet/FOMap kinds for S fields.
pub fn[S : ToJson + @json.FromJson] component(
  name~ : String,
  views~ : Map[String, @anode.View],
  init~ : S,
  common_style? : String = "",
  global_style? : String = "",
  update? : (S, Dispatch, &@tutuca.Ctx) -> S?,
  mutate? : Map[String, (S, Array[@tutuca.Value]) -> S] = Map([]),
  compute? : Map[String, (S, Array[@tutuca.Value]) -> @tutuca.Value] = Map([]),
  swap? : Map[String, (S, Array[@tutuca.Value], &@tutuca.Ctx) -> @tutuca.Value?] = Map([],
  ),
  when? : Map[String, (S, @tutuca.Value, @tutuca.Value, @tutuca.Value) -> Bool] = Map([],
  ),
  enrich? : Map[
    String,
    (S, Map[String, @tutuca.Value], @tutuca.Value, @tutuca.Value, @tutuca.Value) -> Unit,
  ] = Map([]),
  enrich_scope? : Map[String, (S) -> Map[String, @tutuca.Value]] = Map([]),
  loop_with? : Map[String, (S, @tutuca.Value, LoopCtx) -> LoopWith] = Map([]),
  specs? : Map[String, FieldSpec] = Map([]),
  provide? : Map[String, String] = Map([]),
  lookup? : Map[String, LookupSpec] = Map([]),
) -> Component {
  let init_fields = encode_state(init)
  let s_fields : Array[String] = []
  for k, _ in init_fields {
    s_fields.push(k)
  }
  let all_specs : Map[String, FieldSpec] = Map([])
  for k, v in init_fields {
    all_specs[k] = FieldSpec::of_default(v)
  }
  for k, sp in specs {
    match (all_specs.get(k), sp.kind) {
      // kind override for an S field: the typed default stays authoritative
      (Some(base), FSet | FOMap) =>
        all_specs[k] = { kind: sp.kind, default: base.default }
      _ => all_specs[k] = sp
    }
  }
  let tspec : TypedSpec[S] = {
    comp: None,
    init,
    s_fields,
    update,
    mutate,
    compute,
    swap,
    when,
    enrich,
    enrich_scope,
    loop_with,
    generated: Map([]),
  }
  gen_mutators(all_specs, tspec.generated)
  let comp = new_component(
    name,
    common_style,
    global_style,
    views,
    provide,
    lookup,
    all_specs,
    mutate_names=map_keys(mutate),
    compute_names=map_keys(compute),
    swap_names=map_keys(swap),
    alter_names=map_keys(when) +
      map_keys(enrich) +
      map_keys(enrich_scope) +
      map_keys(loop_with),
    generated_names=map_keys(tspec.generated),
    has_update=update is Some(_),
  )
  tspec.comp = Some(comp)
  comp.make_fn = args => make_typed(comp, tspec, args)
  comp
}

///|
/// Build an instance Value: coerce args against field specs, fill defaults
/// (FComp children made through the registration scope), decode the state.
fn[S : ToJson + @json.FromJson] make_typed(
  comp : Component,
  tspec : TypedSpec[S],
  args : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let fields : Map[String, @tutuca.Value] = Map([])
  for name, fspec in comp.specs {
    let v = match args.get(name) {
      Some(given) => fspec.coerce_or_default(given)
      None =>
        match fspec.kind {
          // component-typed default: made through the registration scope
          FComp(comp=cname, args=cargs) =>
            match comp.scope {
              Some(s) =>
                match s.lookup_component(cname) {
                  Some(child) => child.make(cargs)
                  None => Null
                }
              None => Null
            }
          _ => fspec.default
        }
    }
    fields[name] = v
  }
  let state : S = match decode_state(fields, tspec.s_fields) {
    Some(s) => s
    None => tspec.init
  }
  Obj(TypedInstance::{ spec: tspec, state, fields })
}

///|
/// Define a component whose instances are a user typed struct implementing
/// @tutuca.Obj directly (the fully-manual path): views/styles/provide/lookup
/// only — fields and handlers live on the struct itself. The struct's
/// component_id() must return this component's id. make() yields Null.
pub fn Component::for_type(
  name~ : String,
  views~ : Map[String, @anode.View],
  common_style? : String = "",
  global_style? : String = "",
  provide? : Map[String, String] = Map([]),
  lookup? : Map[String, LookupSpec] = Map([]),
) -> Component {
  new_component(
    name,
    common_style,
    global_style,
    views,
    provide,
    lookup,
    Map([]),
  )
}

///|
pub fn Component::get_view(self : Component, name : String?) -> @anode.View? {
  self.views.get(name.unwrap_or("main"))
}

///|
/// Build an instance Value for this component (Null for for_type components —
/// their instances are user structs).
pub fn Component::make(
  self : Component,
  args : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  (self.make_fn)(args)
}

///|
fn split_source(s : String) -> (String, String)? {
  for i in 0..<s.length() {
    if s[i] is '.' {
      let a = s[0:i]
      let b = s[i + 1:]
      if a.length() > 0 && b.length() > 0 {
        return Some((a.to_owned(), b.to_owned()))
      }
      return None
    }
  }
  None
}

///|
pub fn Component::compile(self : Component) -> Unit raise {
  let scope_obj : &@anode.MacroScope = match self.scope {
    Some(s) => s as &@anode.MacroScope
    None => EmptyScope::{  }
  }
  for _, view in self.views {
    view.compile(
      @anode.ParseContext::new(),
      scope_obj,
      cid=LNum(self.id.to_double()),
    )
  }
  for pname, src in self.raw_provide {
    match @tutuca.parse_provide(src, @tutuca.ParseCtx::new()) {
      Some(val) =>
        self.provide[pname] = {
          name: pname,
          val,
          key: { comp: self.id, name: pname },
        }
      None => () // bad shape dropped silently (linter territory)
    }
  }
  for lname, spec in self.raw_lookup {
    match split_source(spec.source) {
      Some((comp_name, provide_name)) => {
        let default_val : @tutuca.Val? = match spec.default {
          Some(d) => @tutuca.parse_field(d, @tutuca.ParseCtx::new())
          None => None
        }
        self.lookup[lname] = {
          name: lname,
          comp_name,
          provide_name,
          default_val,
          producer_key: Pending,
        }
      }
      None => ()
    }
  }
}

///|
pub fn Component::compile_style(self : Component) -> String {
  let sb = StringBuilder()
  if self.common_style != "" {
    sb <+ "[data-cid=\"\{self.id}\"]{\{self.common_style}}\n"
  }
  if self.global_style != "" {
    sb <+ "\{self.global_style}\n"
  }
  for vname, view in self.views {
    if view.style != "" {
      sb <+ "[data-cid=\"\{self.id}\"][data-vid=\"\{vname}\"]{\{view.style}}\n"
    }
  }
  sb.to_string()
}

///|
/// Generated per-field mutators (oo.js ClassBuilder), JS camelCase names so
/// views port verbatim: set/update/reset/toggle/len/pushIn/setInAt/updateInAt/
/// deleteInAt/removeInAt for list/map/omap, and addIn/deleteIn/removeIn/hasIn/
/// toggleIn for sets. getInAt is the only deferred accessor.
fn[S : ToJson + @json.FromJson] gen_mutators(
  fields : Map[String, FieldSpec],
  into : Map[String, (TypedInstance[S], Array[@tutuca.Value]) -> @tutuca.Value],
) -> Unit {
  for name, spec in fields {
    let u = cap_first(name)
    into["set" + u] = (inst, args) => {
      inst.set(name, args.get(0).unwrap_or(Null)).to_value()
    }
    into["reset" + u] = (inst, _args) => inst.set(name, spec.default).to_value()
    // the update fn is a plain lambda: it receives ONLY the current value
    into["update" + u] = (inst, args) => {
      match args {
        [Fn(f), ..] => inst.set(name, f([inst.get(name)])).to_value()
        _ => inst.to_value()
      }
    }
    into[name + "Len"] = (inst, _args) => {
      match @tutuca.size_of(inst.get(name)) {
        Some(n) => Num(n.to_double())
        None => Null
      }
    }
    match spec.kind {
      FBool =>
        into["toggle" + u] = (inst, _args) => {
          match inst.get(name) {
            Bool(b) => inst.set(name, Bool(!b)).to_value()
            _ => inst.to_value()
          }
        }
      // Set fields (JS FieldSet.extendProtoForType): membership mutators over
      // the Map-backed set (key = member display string, value Bool(true)).
      FSet => {
        into["addIn" + u] = (inst, args) => {
          match (inst.get(name), args) {
            (Map(m), [v, ..]) => {
              let out = m.copy()
              out[v.to_display_string()] = Bool(true)
              inst.set(name, Map(out)).to_value()
            }
            _ => inst.to_value()
          }
        }
        // JS deleteIn<X> and removeIn<X> alias the same delete (oo.js
        // extendDeleteInAt, called with the bare uname for sets).
        let delete_member = (
          inst : TypedInstance[S],
          args : Array[@tutuca.Value],
        ) => {
          match (inst.get(name), args) {
            (Map(m), [v, ..]) => {
              let out = m.copy()
              out.remove(v.to_display_string()) |> ignore
              inst.set(name, Map(out)).to_value()
            }
            _ => inst.to_value()
          }
        }
        into["deleteIn" + u] = delete_member
        into["removeIn" + u] = delete_member
        into["hasIn" + u] = (inst, args) => {
          match (inst.get(name), args) {
            (Map(m), [v, ..]) => Bool(m.contains(v.to_display_string()))
            _ => Bool(false)
          }
        }
        into["toggleIn" + u] = (inst, args) => {
          match (inst.get(name), args) {
            (Map(m), [v, ..]) => {
              let key = v.to_display_string()
              let out = m.copy()
              if out.contains(key) {
                out.remove(key) |> ignore
              } else {
                out[key] = Bool(true)
              }
              inst.set(name, Map(out)).to_value()
            }
            _ => inst.to_value()
          }
        }
      }
      FList | FMap | FOMap => {
        into["pushIn" + u] = (inst, args) => {
          match (inst.get(name), args) {
            (List(a), [v, ..]) => {
              let out = a.copy()
              out.push(v)
              inst.set(name, List(out)).to_value()
            }
            _ => inst.to_value()
          }
        }
        // JS FieldList.insertIn<X>At(i, v): insert v BEFORE index i (oo.js:221).
        // List-only in JS; harmless on the (currently absent) map case.
        into["insertIn" + u + "At"] = (inst, args) => {
          match (inst.get(name), args) {
            (List(a), [Num(i), v, ..]) => {
              let out = a.copy()
              let at = i.to_int()
              if at >= 0 && at <= out.length() {
                out.insert(at, v)
              } else {
                out.push(v)
              }
              inst.set(name, List(out)).to_value()
            }
            _ => inst.to_value()
          }
        }
        into["setIn" + u + "At"] = (inst, args) => seq_set(inst, name, args)
        into["updateIn" + u + "At"] = (inst, args) => {
          seq_update(inst, name, args)
        }
        // JS names these deleteIn<X>At / removeIn<X>At for KEYED fields:
        // extendProtoForKeyed passes `${uname}At` into extendDeleteInAt
        // (src/oo.js:201). The bare deleteIn<X> / removeIn<X> spelling is the
        // SET-field variant, generated in the FSet arm above. Views like
        // `$removeInItemsAt @key` (docs/examples/todo.js, json.js) depend on it.
        into["deleteIn" + u + "At"] = (inst, args) => {
          seq_delete(inst, name, args)
        }
        into["removeIn" + u + "At"] = (inst, args) => {
          seq_delete(inst, name, args)
        }
      }
      _ => ()
    }
  }
}

///|
fn[S : ToJson + @json.FromJson] seq_set(
  inst : TypedInstance[S],
  field : String,
  args : Array[@tutuca.Value],
) -> @tutuca.Value {
  match (inst.get(field), args) {
    (List(a), [Num(i), v, ..]) => {
      let idx = i.to_int()
      if idx >= 0 && idx < a.length() {
        let out = a.copy()
        out[idx] = v
        inst.set(field, List(out)).to_value()
      } else {
        inst.to_value()
      }
    }
    (Map(m), [Str(k), v, ..]) => {
      let out = m.copy()
      out[k] = v
      inst.set(field, Map(out)).to_value()
    }
    _ => inst.to_value()
  }
}

///|
fn[S : ToJson + @json.FromJson] seq_update(
  inst : TypedInstance[S],
  field : String,
  args : Array[@tutuca.Value],
) -> @tutuca.Value {
  match (inst.get(field), args) {
    (List(a), [Num(i), Fn(f), ..]) => {
      let idx = i.to_int()
      if idx >= 0 && idx < a.length() {
        seq_set(inst, field, [Num(i), f([a[idx]])])
      } else {
        inst.to_value()
      }
    }
    (Map(m), [Str(k), Fn(f), ..]) =>
      match m.get(k) {
        Some(cur) => seq_set(inst, field, [Str(k), f([cur])])
        None => inst.to_value()
      }
    _ => inst.to_value()
  }
}

///|
fn[S : ToJson + @json.FromJson] seq_delete(
  inst : TypedInstance[S],
  field : String,
  args : Array[@tutuca.Value],
) -> @tutuca.Value {
  match (inst.get(field), args) {
    (List(a), [Num(i), ..]) => {
      let idx = i.to_int()
      if idx >= 0 && idx < a.length() {
        let out = a.copy()
        let _ = out.remove(idx)
        inst.set(field, List(out)).to_value()
      } else {
        inst.to_value()
      }
    }
    (Map(m), [Str(k), ..]) => {
      let out = m.copy()
      out.remove(k)
      inst.set(field, Map(out)).to_value()
    }
    _ => inst.to_value()
  }
}

///|
pub fn LoopWith::new(
  iter_data? : @tutuca.Value,
  start? : Int,
  end? : Int,
  keys? : Array[@tutuca.Value],
) -> LoopWith {
  { iter_data, start, end, keys }
}
