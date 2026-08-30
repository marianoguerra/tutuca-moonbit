// Typed-state component definitions: the component() builder over a state
// struct S (derive(ToJson, FromJson)), plus the shared Component machinery
// (views, styles, provide/lookup compilation, make).

///|
let comp_id_counter : Ref[Int] = { val: 0, }

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
/// The mutator-name convention, from the one place that states it. The state
/// editor calls these by name through `Obj::obj_field`, so the two sides have
/// to agree and neither can see the other.
fn mut_name(verb : String, field : String) -> String {
  @tutuca.mutator_name(verb, field)
}

///|
pub fn[E, H] build_bucket(
  all : Array[E],
  name : (E) -> String,
  f : (E) -> H?,
) -> Map[String, H] {
  let out : Map[String, H] = Map([])
  for m in all {
    if f(m) is Some(h) {
      out[name(m)] = h
    }
  }
  out
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
  lookup : Array[LookupSpec],
  specs : Map[String, FieldSpec],
  swap_names? : Array[String] = [],
  alter_names? : Array[String] = [],
  schema~ : SchemaInfo,
  spec? : String = "",
) -> Component {
  // Views arrive already built — either compiled ahead of time by
  // `tutuca gen-views` (View::from_ir) or parsed from source by
  // @anode.View::new; both are @anode.View, and Component::compile finishes
  // whichever needs it. Each carries its own per-view style.
  let vs : Map[String, @anode.View] = Map([])
  for vname, v in views {
    vs[vname] = v
  }
  // A hand-written descriptor is already being passed to a `name~` that says
  // the same thing, so `SchemaInfo::new` lets it go unstated and this fills it
  // in. It matters because the schema, not the Component, is what an instance
  // can reach: `obj_debug` and the JSON projection label themselves from it
  // with no registry in hand.
  let schema = if schema.name == "" { { ..schema, name, } } else { schema }
  {
    id: next_comp_id(),
    name,
    views: vs,
    common_style,
    global_style,
    specs,
    swap_names,
    alter_names,
    schema,
    spec,
    make_fn: _args => Null,
    raw_provide: provide,
    raw_lookup: lookup,
    provide: Map([]),
    provide_type: Map([]),
    lookup: Map([]),
    scope: None,
  }
}

///|
/// Define a typed-state component. `init` is a plain struct with
/// PLAIN struct — no derives — whose fields become the component's fields,
/// compiler-checked inside every handler. `encode`/`decode` convert it to and
/// from the fields map the render and path layers read, and `schema` states
/// what it declares; all three are required, and `gen-views` writes them.
/// Buckets:
/// - update: ALL effectful dispatches in one pattern match over Dispatch
///   (Receive/Intent), returning the new state (None = no
///   change).
/// - compute: $-callable value reads ($label in value positions).
/// - when / enrich / enrich_scope / loop_with: the render-time directive
///   buckets, each with its own typed signature (@when filter -> Bool;
///   @enrich-with mutates the binds map; the scope form returns binds;
///   @loop-with returns a LoopWith slice/order plan).
/// Auto-mutators are generated per field (setX / updateX / resetX / toggleX /
/// xLen / pushInX / setInXAt / ...); a user `compute` entry wins over them.
/// `slots` names a component slot the schema could not name; `slot_args` gives a
/// slot's child its construction arguments.
pub fn[S : @tutuca.Fields] component(
  name~ : String,
  views~ : Map[String, @anode.View],
  init~ : S,
  common_style? : String = "",
  global_style? : String = "",
  update? : (S, Dispatch, &@tutuca.Ctx) -> Update[S],
  get_property? : Map[String, (S) -> @tutuca.Value] = Map([]),
  set_property? : Map[String, (S, @tutuca.Value) -> Update[S]] = Map([]),
  compute? : Map[
    String,
    (S, Array[@tutuca.Value], &@tutuca.Stack) -> @tutuca.Value,
  ] = Map([]),
  swap? : Map[String, (S, Array[@tutuca.Value], &@tutuca.Ctx) -> @tutuca.Value?] = Map([],
  ),
  when? : Map[
    String,
    (S, @tutuca.Value, @tutuca.Value, @tutuca.Value, &@tutuca.Stack) -> Bool,
  ] = Map([]),
  enrich? : Map[
    String,
    (
      S,
      Map[String, @tutuca.Value],
      @tutuca.Value,
      @tutuca.Value,
      @tutuca.Value,
      &@tutuca.Stack,
    ) -> Unit,
  ] = Map([]),
  enrich_scope? : Map[String, (S, &@tutuca.Stack) -> Map[String, @tutuca.Value]] = Map([],
  ),
  loop_with? : Map[String, (S, @tutuca.Value, LoopCtx) -> LoopWith] = Map([]),
  slots? : Map[String, String] = Map([]),
  slot_args? : Map[String, Map[String, @tutuca.Value]] = Map([]),
  provide? : Map[String, String] = Map([]),
  lookup? : Array[LookupSpec] = [],
  spec? : String = "",
) -> Component {
  // The three facts only the author knows — the declared schema and the
  // conversion to and from the fields map — arrive as ONE trait implemented on
  // the state type rather than as three parameters threaded through every call
  // site. `gen-views` writes the impl; a hand-written state writes three short
  // methods, which is the same code in a place that cannot drift from the type
  // it describes.
  let schema = S::schema()
  let encode = (s : S) => s.encode()
  let decode = (f : Map[String, @tutuca.Value]) => S::decode(f)
  let init_fields = encode(init)
  // Every spec comes from the SCHEMA now. The kind is `fi.kind()` and the
  // default `fi.ty.zero()`, both projections of the declared type, so there is
  // nothing here a caller could state differently from what the block says.
  //
  // A child's construction ARGUMENTS are a value the author picks, which no
  // type can express — that is all `slot_args~` carries.
  // A slot the SCHEMA cannot name, in either of the two ways it can fail to.
  // Folded INTO the schema rather than kept beside it, so the descriptor still
  // names every field an instance has — which is what the inspector and
  // structural equality read.
  //
  //  1. It does not declare the field at all — several components share one state
  //     type and hold different children. A view file gives each component its
  //     own interface and so never needs this; a component built by hand does,
  //     and there is nowhere else for it to say so.
  //  2. It declares the field as the bare `component` marker: "a component slot"
  //     without saying which, because the name is not spellable there. The
  //     commonest reason is a component whose name kebab-case cannot round-trip
  //     (`DnDExample` -> `d-n-d-example` -> `DNDExample`).
  //
  // A slot the schema NAMES is not overridable: the caller would be contradicting
  // a declared type, and every reader of the descriptor would then disagree with
  // the block. Nothing is silently dropped either way — an entry that matches
  // neither case is a field this component does not have, which `all_specs`
  // below leaves untouched.
  let schema = if slots.is_empty() {
    schema
  } else {
    let fields : Array[@tutuca.FieldInfo] = []
    for fi in schema.fields {
      // case 2: the declared slot has no name, and this entry supplies it
      fields.push(
        match (fi.ty, slots.get(fi.name)) {
          (TyComp(None), Some(comp)) => { ..fi, ty: TyComp(Some(comp)), }
          _ => fi
        },
      )
    }
    for name, comp in slots {
      // case 1: a field the schema does not declare
      if schema.field(name) is None {
        fields.push(@tutuca.FieldInfo::new(name, TyComp(Some(comp))))
      }
    }
    { ..schema, fields, }
  }
  // Which fields the STATE TYPE carries — the question `set` asks to decide
  // whether a write has to be decoded back into the struct or only recorded in
  // the fields map.
  //
  // From the SCHEMA, because it is a question about the type and not about one
  // value of it. Reading it off `encode(init)` was wrong for every field an
  // encoder may omit: a generated `encode` leaves an `option` out when it is
  // None, so `kid : Component[Child]?` seeded `None` produced no `kid` key, no
  // `kid` in this list, and every later write to `.kid` updated the fields map
  // while the struct kept the value it was born with. The child's own view
  // re-rendered (it renders from the map) and everything reading `s.kid` — a
  // `compute`, a `loop_with`, an `update` arm — saw the first child forever.
  //
  // The union with the encoded keys keeps what was there before: a
  // hand-written state whose encoder emits a field its schema does not declare.
  let s_fields : Array[String] = []
  for fi in schema.fields {
    s_fields.push(fi.name)
  }
  for k, _ in init_fields {
    if !s_fields.contains(k) {
      s_fields.push(k)
    }
  }
  // Every declared field, from the schema. The kind is `fi.kind()` and the
  // default the encoded seed where there is one, `fi.ty.zero()` otherwise, so
  // nothing here can say something different from what the block declared.
  let all_specs = field_specs(schema, slot_args~, seed=init_fields)
  // ...and anything the encoder produced that the schema does not name. It
  // exists, but nothing declared what it is.
  for k, v in init_fields {
    if !all_specs.contains(k) {
      all_specs[k] = {
        kind: FAny,
        default: v,
        protocol_ids: [],
        protocols: [],
      }
    }
  }
  let tspec : TypedSpec[S] = {
    comp: None,
    init,
    s_fields,
    update,
    get_property,
    set_property,
    compute,
    swap,
    when,
    enrich,
    enrich_scope,
    loop_with,
    generated: Map([]),
    encode,
    decode,
  }
  gen_mutators(all_specs, tspec.generated)
  // Protocol-qualified bindings use canonical ids as runtime keys. Raw names
  // keep their existing namespace; the two cannot collide.
  for b in schema.provide_bindings {
    let key = b.protocol_id + "::" + b.member_name
    if !provide.contains(key) {
      provide[key] = b.source
    }
  }
  for b in schema.lookup_bindings {
    let key = b.protocol_id + "::" + b.member_name
    if !lookup.iter().any(x => x.name == key) {
      lookup.push(lookup_or(key, b.source))
    }
  }
  let comp = new_component(
    name,
    common_style,
    global_style,
    views,
    provide,
    lookup,
    all_specs,
    swap_names=map_keys(swap),
    alter_names=map_keys(when) +
      map_keys(enrich) +
      map_keys(enrich_scope) +
      map_keys(loop_with),
    schema~,
    spec~,
  )
  tspec.comp = Some(comp)
  comp.make_fn = args => make_typed(comp, tspec, args)
  comp
}

///|
/// Build an instance Value: coerce args against field specs, fill defaults
/// (FComp children made through the registration scope), decode the state.
fn[S] make_typed(
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
  let state : S = match (tspec.decode)(fields) {
    Some(s) => s
    None => tspec.init
  }
  // through to_value() so the instance's memoized box is the one every
  // later reader sees
  TypedInstance::make(tspec, state, fields).to_value()
}

///|
/// Define a component whose instances are a user typed struct implementing
/// @tutuca.Obj directly (the fully-manual path): views/styles/provide/lookup
/// only — fields and handlers live on the struct itself. The struct's
/// component_id() must return this component's id. make() yields Null.
///
/// `schema` is REQUIRED, exactly as it is for a typed-state component. Being
/// hand-written is not being under-described: a caller here knows what its
/// instances answer to — a dyncomp guest's manifest lists its handlers, the
/// storybook shell computes its own field set — and the descriptor is where
/// that goes. Without it the inspector had nothing to show for these
/// components and the runtime had nothing to be told.
///
/// A `fields: []` schema is a fine answer when the instances really are
/// opaque, which is the dyncomp contract: only views and handlers cross the
/// boundary, and saying so beats leaving the whole descriptor blank.
pub fn Component::for_type(
  name~ : String,
  views~ : Map[String, @anode.View],
  schema~ : SchemaInfo,
  common_style? : String = "",
  global_style? : String = "",
  provide? : Map[String, String] = Map([]),
  lookup? : Array[LookupSpec] = [],
  make? : (Map[String, @tutuca.Value]) -> @tutuca.Value,
  spec? : String = "",
) -> Component {
  let comp = new_component(
    name,
    common_style,
    global_style,
    views,
    provide,
    lookup,
    Map([]),
    schema~,
    spec~,
  )
  // Without this a `for_type` component cannot be INSTANTIATED, only adopted:
  // `make_fn` defaults to answering Null, and the field is package-private, so
  // a holder of foreign instances had nowhere to say how one is built. The
  // dyncomp host worked around it with a `Bundle::make_instance` of its own,
  // which meant an app root could never simply be a guest. A card needs the
  // ordinary path, so the parameter is the ordinary answer.
  match make {
    Some(f) => comp.make_fn = f
    None => ()
  }
  comp
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
pub fn Component::compile(self : Component) -> Unit raise {
  let scope_obj : &@anode.MacroScope = match self.scope {
    Some(s) => s as &@anode.MacroScope
    None => EmptyScope::{ }
  }
  for _, view in self.views {
    view.compile(
      @anode.ParseContext::new(),
      scope_obj,
      cid=LNum(self.id.to_double()),
    )
  }
  // `view_handlers` is the names the VIEWS raise, and a view that has just
  // been compiled is where they can be read off. The generator states them
  // ahead of time and this leaves those alone; a component whose views arrive
  // at RUNTIME (a wasm guest's manifest) has no generator to state them, and
  // recovering them here is what keeps its descriptor as complete as a
  // compiled one's.
  if self.schema.view_handlers.is_empty() {
    let names = self.view_handler_names()
    if !names.is_empty() {
      self.schema = { ..self.schema, view_handlers: names, }
    }
  }
  // The name rule splits the two keyspaces: an uppercase key publishes a TYPE,
  // and `"self"` is the only legal value for one — which is what keeps a
  // published type a component by construction, so the `dyn` leg never has to
  // trust an arbitrary expression. Anything else is a value, and must be
  // ADDRESSABLE (`.field` / `.seq[.key]`) because a provide doubles as the
  // teleport target for `<x render="*name">`.
  //
  // Both bad shapes are dropped here rather than raised: what is wrong with a
  // declaration is a finding, with a name and a place to point at, and
  // `ComponentStack::check_names` is where they are said.
  for pname, src in self.raw_provide {
    if @tutuca.is_type_name(pname) {
      if src == "self" {
        self.provide_type[pname] = self.id
      }
      continue
    }
    match @tscript.parse_provide(src, @tscript.ParseCtx::new()) {
      Some(val) => self.provide[pname] = { name: pname, val, }
      None => ()
    }
  }
  for spec in self.raw_lookup {
    let default_val : @tutuca.Val? = match spec.default {
      Some(d) => @tscript.parse_field(d, @tscript.ParseCtx::new())
      None => None
    }
    self.lookup[spec.name] = { name: spec.name, default_val, }
  }
}

///|
/// Every `@on` handler name this component's COMPILED views raise, in
/// first-seen order. Empty before `compile()`: the names live in the parsed
/// tree, not in the source string.
pub fn Component::view_handler_names(self : Component) -> Array[String] {
  let seen : Map[String, Unit] = Map([])
  let out : Array[String] = []
  for _, view in self.views {
    match view.ctx {
      Some(px) =>
        for ne in px.events {
          for h in ne.handlers {
            match h.handler.handler {
              HandlerName(name~, ns~) =>
                if ns is Receive && !seen.contains(name) {
                  seen[name] = ()
                  out.push(name)
                }
              _ => ()
            }
          }
        }
      None => ()
    }
  }
  out
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
/// Every declared field's runtime handling, from the schema alone: the kind is
/// `fi.kind()` and the default its type's zero, both projections of the
/// declared type, so nothing here can say something different from what the
/// block declared. `seed` lets a component start a field at the value its
/// `init` gives it rather than at the type's zero; `slot_args` carries the one
/// thing no type states — which arguments a child slot is built with.
fn field_specs(
  schema : SchemaInfo,
  slot_args? : Map[String, Map[String, @tutuca.Value]] = Map([]),
  seed? : Map[String, @tutuca.Value] = Map([]),
) -> Map[String, FieldSpec] {
  let out : Map[String, FieldSpec] = Map([])
  for fi in schema.fields {
    out[fi.name] = match fi.ty {
      TyCompProtocols(ids) =>
        FieldSpec::comp(
          "",
          args=slot_args.get(fi.name).unwrap_or(Map([])),
          protocol_ids=ids,
          protocols=schema.protocols,
        )
      _ =>
        match fi.ty.slot() {
          Some(comp) =>
            FieldSpec::comp(
              comp,
              args=slot_args.get(fi.name).unwrap_or(Map([])),
            )
          None =>
            {
              kind: fi.kind(),
              default: seed.get(fi.name).unwrap_or(fi.ty.zero()),
              protocol_ids: [],
              protocols: [],
            }
        }
    }
  }
  out
}

///|
/// The mutators a declared schema implies, for a holder that is not a
/// `TypedInstance` — the dynamic-component host, whose guest instances answer
/// `obj_field` / `obj_with_field` and get the same `setX` / `toggleX` /
/// `pushInX` set from the same generator.
pub fn schema_mutators(
  schema : SchemaInfo,
) -> Map[String, (FieldBox, Array[@tutuca.Value]) -> @tutuca.Value] {
  let out : Map[String, (FieldBox, Array[@tutuca.Value]) -> @tutuca.Value] = Map([],
  )
  gen_mutators(field_specs(schema), out)
  out
}

///|
/// The generated names a component can be SENT, as messages.
///
/// `schema_mutators` is every generated callable, and that is one table with
/// two kinds of thing in it: names that build a successor, and names that
/// merely read. `<field>Len` and `hasIn<Field>` answer a scalar — they are
/// `$`-callables a view writes as `$tabLen`, and dispatching one as a message
/// does nothing at all. The runtime already knows this and says so: the
/// receive path takes a generated entry's result only when it is `Obj(_)`
/// (see `TypedInstance`'s dispatch), so a reader falls through to `Unhandled`.
///
/// This is that same distinction, up front, for a caller deciding what to
/// send rather than discovering afterwards that it could not have worked.
/// `statedef/arb` is the caller: a generator drawing from the full table
/// spends a share of every script on names nothing can answer, and reports
/// them as refusals that look like findings.
pub fn schema_writers(
  schema : SchemaInfo,
) -> Map[String, (FieldBox, Array[@tutuca.Value]) -> @tutuca.Value] {
  let out : Map[String, (FieldBox, Array[@tutuca.Value]) -> @tutuca.Value] = Map([],
  )
  let readers : Array[String] = []
  gen_mutators(field_specs(schema), out, readers~)
  for name in readers {
    out.remove(name) |> ignore
  }
  out
}

///|
/// Generated per-field mutators, camelCase names so
/// views port verbatim: set/reset/len/pushIn/setInAt/deleteInAt/removeInAt for
/// list/map/omap, toggle for bools, and addIn/deleteIn/removeIn/hasIn/toggleIn
/// for sets. getInAt is the only deferred accessor.
///
/// NOTE(dropped): the `update<X>` and `updateIn<X>At` mutators took a FUNCTION value
/// and applied it to the current one. A view can write values and never a
/// lambda, so no template could ever call either, and outside this package's
/// own tests the tree had no call site. Worse, the gap between "set a field"
/// and "transform a field with a function nobody can supply" is exactly why
/// `inc`/`dec` were hand-written in every counter in the corpus. The
/// in-between is an expression language (`.count += 1`), not a lambda.
fn gen_mutators(
  fields : Map[String, FieldSpec],
  into : Map[String, (FieldBox, Array[@tutuca.Value]) -> @tutuca.Value],
  /// The names installed here that only READ. Collected at the two sites that
  /// install one rather than recomputed by a second walk of the same fields:
  /// a second walk is a second opinion about which names those are, and the
  /// whole point of the list is that it cannot disagree with the table.
  readers? : Array[String] = [],
) -> Unit {
  for name, spec in fields {
    into[mut_name("set", name)] = (inst, args) => {
      (inst.set)(name, args.get(0).unwrap_or(Null))
    }
    into[mut_name("reset", name)] = (inst, _args) => {
      (inst.set)(name, spec.default)
    }
    // READS. `size_of` and `contains` answer a scalar and touch nothing, so
    // unlike everything else here these are `$`-callables for a view and not
    // messages — see `schema_writers`.
    readers.push(name + "Len")
    into[name + "Len"] = (inst, _args) => {
      match @tutuca.size_of((inst.get)(name)) {
        Some(n) => Num(n.to_double())
        None => Null
      }
    }
    match spec.kind {
      FBool =>
        into[mut_name("toggle", name)] = (inst, _args) => {
          match (inst.get)(name) {
            Bool(b) => (inst.set)(name, Bool(!b))
            _ => (inst.value)()
          }
        }
      // Set fields: membership mutators over
      // the Map-backed set (key = member display string, value Bool(true)).
      FSet => {
        into[mut_name("addIn", name)] = (inst, args) => {
          match args {
            [v, ..] =>
              put_seq_item(inst, name, KStr(v.to_display_string()), Bool(true))
            _ => (inst.value)()
          }
        }
        // deleteIn<X> and removeIn<X> alias the same delete for sets.
        let delete_member = (inst : FieldBox, args : Array[@tutuca.Value]) => {
          seq_delete(inst, name, args)
        }
        into[mut_name("deleteIn", name)] = delete_member
        into[mut_name("removeIn", name)] = delete_member
        readers.push(mut_name("hasIn", name))
        into[mut_name("hasIn", name)] = (inst, args) => {
          match ((inst.get)(name), args) {
            (Map(m), [v, ..]) => Bool(m.contains(v.to_display_string()))
            _ => Bool(false)
          }
        }
        into[mut_name("toggleIn", name)] = (inst, args) => {
          match ((inst.get)(name), args) {
            (Map(m), [v, ..]) => {
              let key = v.to_display_string()
              if m.contains(key) {
                seq_delete(inst, name, [Str(key)])
              } else {
                put_seq_item(inst, name, KStr(key), Bool(true))
              }
            }
            _ => (inst.value)()
          }
        }
      }
      FList | FMap | FOMap => {
        into[mut_name("pushIn", name)] = (inst, args) => {
          match ((inst.get)(name), args) {
            (List(a), [v, ..]) => {
              let out = a.copy()
              out.push(v)
              (inst.set)(name, List(out))
            }
            _ => (inst.value)()
          }
        }
        // insertIn<X>At(i, v): insert v BEFORE index i.
        // List-only upstream; harmless on the (currently absent) map case.
        into[mut_name("insertIn", name) + "At"] = (inst, args) => {
          match ((inst.get)(name), args) {
            (List(a), [Num(i), v, ..]) => {
              let out = a.copy()
              let at = i.to_int()
              if at >= 0 && at <= out.length() {
                out.insert(at, v)
              } else {
                out.push(v)
              }
              (inst.set)(name, List(out))
            }
            _ => (inst.value)()
          }
        }
        into[mut_name("setIn", name) + "At"] = (inst, args) => {
          seq_set(inst, name, args)
        }
        // The At suffix distinguishes the KEYED-field deleteIn<X>At /
        // removeIn<X>At spellings; the bare deleteIn<X> / removeIn<X> spelling
        // is the SET-field variant, generated in the FSet arm above. Views
        // like `$removeInItemsAt @key` depend on it.
        into[mut_name("deleteIn", name) + "At"] = (inst, args) => {
          seq_delete(inst, name, args)
        }
        into[mut_name("removeIn", name) + "At"] = (inst, args) => {
          seq_delete(inst, name, args)
        }
      }
      _ => ()
    }
  }
}

///|
fn mutator_key(v : @tutuca.Value) -> @tutuca.PathKey? {
  match v {
    Num(i) => Some(KInt(i.to_int()))
    Str(k) => Some(KStr(k))
    _ => None
  }
}

///|
/// Replace one sequence item through core's identity-preserving COW
/// operation. Invalid keys keep the original instance.
fn put_seq_item(
  inst : FieldBox,
  field : String,
  key : @tutuca.PathKey,
  value : @tutuca.Value,
) -> @tutuca.Value {
  match (inst.get)(field).with_item_opt(key, value) {
    Some(seq) => (inst.set)(field, seq)
    None => (inst.value)()
  }
}

///|
fn seq_set(
  inst : FieldBox,
  field : String,
  args : Array[@tutuca.Value],
) -> @tutuca.Value {
  match args {
    [key_arg, value, ..] =>
      match mutator_key(key_arg) {
        Some(key) => put_seq_item(inst, field, key, value)
        None => (inst.value)()
      }
    _ => (inst.value)()
  }
}

///|
fn seq_delete(
  inst : FieldBox,
  field : String,
  args : Array[@tutuca.Value],
) -> @tutuca.Value {
  guard args is [key_arg, ..] else { return (inst.value)() }
  guard mutator_key(key_arg) is Some(key) else { return (inst.value)() }
  match ((inst.get)(field), key) {
    (List(a), KInt(idx)) =>
      if idx >= 0 && idx < a.length() {
        let out = a.copy()
        let _ = out.remove(idx)
        (inst.set)(field, List(out))
      } else {
        (inst.value)()
      }
    (Map(m), KStr(k)) =>
      if m.contains(k) {
        let out = m.copy()
        out.remove(k)
        (inst.set)(field, Map(out))
      } else {
        (inst.value)()
      }
    _ => (inst.value)()
  }
}

///|
pub fn LoopWith::new(
  iter_data? : @tutuca.Value,
  start? : Int,
  end? : Int,
  keys? : Array[@tutuca.Value],
) -> LoopWith {
  { iter_data, start, end, keys, }
}
