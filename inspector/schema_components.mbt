// Per-construct schema components (scalar, object, array, enum, const,
// combinator, conditional, not, boolean, $ref) and the Inspector from-data
// builders that instantiate them. Split from schema.mbt; same package.

///|
/// Primitive type(s): string / number / integer / boolean / null / multi-type.
fn schema_scalar_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=make_schema_view("text-success schema-scalar"),
      ),
    },
    name="SchemaScalar",
    init=schema_node_init(),
    compute=schema_node_compute(_s => ""),
    mutate=composite_mutate(),
    loop_with=composite_loop_with(),
  )
}

///|
fn Inspector::schema_scalar_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let args : Map[String, @tutuca.Value] = {
    "typeLabel": Str(display_type(m, "any")),
    "badges": List(collect_badges(m)),
    "items": List(self.collect_extras(m, "scalar")),
  }
  schema_meta_into(args, m)
  self.make_("SchemaScalar", args~)
}

///|
/// Object schema: property rows (with required markers) plus object-specific
/// branches (additionalProperties / patternProperties / propertyNames).
fn schema_object_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=make_schema_view("text-primary schema-object"),
      ),
    },
    name="SchemaObject",
    init=schema_node_init(),
    compute=schema_node_compute(s => {
      let n = s.items.length()
      if n > 0 {
        "{\{n}}"
      } else {
        ""
      }
    }),
    mutate=composite_mutate(),
    loop_with=composite_loop_with(),
  )
}

///|
fn Inspector::schema_object_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let required : Array[@tutuca.Value] = match m.get("required") {
    Some(List(r)) => r
    _ => []
  }
  let items : Array[@tutuca.Value] = []
  match m.get("properties") {
    Some(Map(props)) =>
      for k, v in props {
        items.push(
          self.make_("SchemaProperty", args={
            "key": Str(k),
            "required": Bool(required.contains(Str(k))),
            "child": self.classify_schema(v),
          }),
        )
      }
    _ => ()
  }
  match m.get("patternProperties") {
    Some(Map(pats)) =>
      for pat, v in pats {
        items.push(
          self.schema_branch(
            "/\{pat}/",
            self.classify_schema(v),
            label_class="text-secondary",
          ),
        )
      }
    _ => ()
  }
  match m.get("additionalProperties") {
    Some(Map(_) as ap) =>
      items.push(
        self.schema_branch(
          "additional properties",
          self.classify_schema(ap),
          label_class="text-secondary",
        ),
      )
    _ => ()
  }
  match m.get("propertyNames") {
    Some(pn) =>
      items.push(
        self.schema_branch(
          "property names",
          self.classify_schema(pn),
          label_class="text-secondary",
        ),
      )
    None => ()
  }
  items.append(self.collect_extras(m, "object"))
  let args : Map[String, @tutuca.Value] = {
    "typeLabel": Str(display_type(m, "object")),
    "badges": List(collect_badges(m)),
    "items": List(items),
  }
  schema_meta_into(args, m)
  self.make_("SchemaObject", args~)
}

///|
/// Array schema: a single `items` schema, or a positional `prefixItems`
/// tuple, plus `contains` and array constraints (as badges).
fn schema_array_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=make_schema_view("text-primary schema-array"),
      ),
    },
    name="SchemaArray",
    init=schema_node_init(),
    compute=schema_node_compute(s => {
      let n = s.items.length()
      if n > 0 {
        "[\{n}]"
      } else {
        ""
      }
    }),
    mutate=composite_mutate(),
    loop_with=composite_loop_with(),
  )
}

///|
fn Inspector::schema_array_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let items : Array[@tutuca.Value] = []
  let prefix_items : Array[@tutuca.Value]? = match m.get("prefixItems") {
    Some(List(p)) => Some(p)
    _ => None
  }
  let is_tuple = prefix_items is Some(_)
  // Inline a bare primitive item type into the label ("array of string")
  // instead of an expandable `items` row.
  let inline_type : String? = if !is_tuple && !(m.get("items") is Some(List(_))) {
    simple_scalar_type(m.get("items"))
  } else {
    None
  }
  match prefix_items {
    Some(ps) =>
      for i, s in ps {
        items.push(self.schema_branch("item \{i}", self.classify_schema(s)))
      }
    None => ()
  }
  match m.get("items") {
    // draft-07 tuple form
    Some(List(ss)) =>
      for i, s in ss {
        items.push(self.schema_branch("item \{i}", self.classify_schema(s)))
      }
    Some(s) =>
      if inline_type is None {
        items.push(self.schema_branch("items", self.classify_schema(s)))
      }
    None => ()
  }
  match m.get("contains") {
    Some(c) =>
      items.push(self.schema_branch("contains", self.classify_schema(c)))
    None => ()
  }
  items.append(self.collect_extras(m, "array"))
  let type_label = if is_tuple {
    "tuple"
  } else {
    match inline_type {
      Some(t) => "array of \{t}"
      None => display_type(m, "array")
    }
  }
  let args : Map[String, @tutuca.Value] = {
    "typeLabel": Str(type_label),
    "badges": List(collect_badges(m)),
    "items": List(items),
  }
  schema_meta_into(args, m)
  self.make_("SchemaArray", args~)
}

///|
/// Enumerated allowed values — each rendered with the value inspector.
fn schema_enum_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=make_schema_view("text-info schema-enum", body=LIST_BODY),
      ),
    },
    name="SchemaEnum",
    init=schema_node_init(),
    compute=schema_node_compute(s => {
      let n = s.items.length()
      if n > 0 {
        "(\{n})"
      } else {
        ""
      }
    }),
    mutate=composite_mutate(),
    loop_with=composite_loop_with(),
  )
}

///|
fn Inspector::schema_enum_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let members : Array[@tutuca.Value] = match m.get("enum") {
    Some(List(e)) => e
    _ => []
  }
  let items = members.map(v => self.inspect_value(v))
  items.append(self.collect_extras(m, "enum"))
  let args : Map[String, @tutuca.Value] = {
    "typeLabel": Str("enum"),
    "badges": List(collect_badges(m)),
    "items": List(items),
  }
  schema_meta_into(args, m)
  self.make_("SchemaEnum", args~)
}

///|
/// A single constant value — terminal, rendered inline.
fn schema_const_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<span class="font-mono text-sm leading-tight inline-flex items-center gap-2 schema-const">
          #|  <span class="text-info font-semibold">const</span>
          #|  <span class="text-base-content/30">=</span>
          #|  <x render=".value"></x>
          #|</span>
        ),
      ),
    },
    name="SchemaConst",
    init=ChildValueState::{ value: Null },
  )
}

///|
/// Combinator: allOf / anyOf / oneOf, subschemas listed without keys.
fn schema_combinator_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=make_schema_view(
          "text-accent schema-combinator",
          body=LIST_BODY,
        ),
      ),
    },
    name="SchemaCombinator",
    init=schema_node_init(),
    compute=schema_node_compute(s => {
      let n = s.items.length()
      if n > 0 {
        "(\{n})"
      } else {
        ""
      }
    }),
    mutate=composite_mutate(),
    loop_with=composite_loop_with(),
  )
}

///|
fn Inspector::schema_combinator_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let items : Array[@tutuca.Value] = []
  let mut kind = ""
  for k in ["allOf", "anyOf", "oneOf"] {
    if m.get(k) is Some(List(subs)) {
      if kind == "" {
        kind = k
      }
      for s in subs {
        items.push(self.classify_schema(s))
      }
    }
  }
  items.append(self.collect_extras(m, "combinator"))
  let args : Map[String, @tutuca.Value] = {
    "typeLabel": Str(combinator_phrasing(kind)),
    "badges": List(collect_badges(m)),
    "items": List(items),
  }
  schema_meta_into(args, m)
  self.make_("SchemaCombinator", args~)
}

///|
/// Conditional applicator: if / then / else as three labeled regions.
fn schema_conditional_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<span class="font-mono text-sm leading-tight inline-block schema-conditional">
          #|  <span class="inline-flex items-center gap-2 flex-wrap">
          #|    <span class="text-accent font-semibold">conditional</span>
          #|    <span @show=".deprecated" class="badge badge-xs badge-warning">deprecated</span>
          #|  </span>
          #|  <span @show="truthy? .title" class="block text-base-content/80 italic" @text=".title"></span>
          #|  <span @show="truthy? .description" class="block text-base-content/50" @text=".description"></span>
          #|  <div class="ml-1 grid gap-x-2 gap-y-0.5 items-baseline border-l border-base-content/10 pl-2 mt-0.5" style="grid-template-columns: auto 1fr">
          #|    <div @show="truthy? .ifNode" class="contents">
          #|      <span class="font-mono text-sm flex items-center gap-1 leading-tight">
          #|        <span class="text-info">if</span>
          #|        <span class="text-base-content/30">:</span>
          #|      </span>
          #|      <x render=".ifNode"></x>
          #|    </div>
          #|    <div @show="truthy? .thenNode" class="contents">
          #|      <span class="font-mono text-sm flex items-center gap-1 leading-tight">
          #|        <span class="text-success">then</span>
          #|        <span class="text-base-content/30">:</span>
          #|      </span>
          #|      <x render=".thenNode"></x>
          #|    </div>
          #|    <div @show="truthy? .elseNode" class="contents">
          #|      <span class="font-mono text-sm flex items-center gap-1 leading-tight">
          #|        <span class="text-warning">else</span>
          #|        <span class="text-base-content/30">:</span>
          #|      </span>
          #|      <x render=".elseNode"></x>
          #|    </div>
          #|  </div>
          #|</span>
        ),
      ),
    },
    name="SchemaConditional",
    init=SchemaConditionalState::{
      ifNode: Null,
      thenNode: Null,
      elseNode: Null,
      title: "",
      description: "",
      deprecated: false,
    },
  )
}

///|
fn Inspector::schema_conditional_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let node = (k : String) => {
    match m.get(k) {
      Some(s) => self.classify_schema(s)
      None => Null
    }
  }
  let args : Map[String, @tutuca.Value] = {
    "ifNode": node("if"),
    "thenNode": node("then"),
    "elseNode": node("else"),
  }
  schema_meta_into(args, m)
  self.make_("SchemaConditional", args~)
}

///|
/// Negation: the value must NOT match the wrapped schema.
fn schema_not_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<span class="font-mono text-sm leading-tight inline-flex items-center gap-2 schema-not">
          #|  <span class="text-error font-semibold">not</span>
          #|  <span class="text-base-content/30">:</span>
          #|  <x render=".child"></x>
          #|</span>
        ),
      ),
    },
    name="SchemaNot",
    init=ChildOnlyState::{ child: Null },
  )
}

///|
/// Boolean schemas: `true` accepts any value, `false` accepts none.
fn schema_boolean_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<span :class="$cssClass" @text="$text"></span>
        ),
      ),
      "_margauiClasses": @anode.View::new(
        "_margauiClasses",
        raw_view=(
          #|<p class="text-success text-error"></p>
        ),
      ),
    },
    name="SchemaBoolean",
    init=SchemaBooleanState::{ value: true },
    compute={
      "text": (s : SchemaBooleanState, _args) => {
        Str(
          if s.value {
            "any value (true)"
          } else {
            "no value allowed (false)"
          },
        )
      },
      "cssClass": (s : SchemaBooleanState, _args) => {
        let color = if s.value { "text-success" } else { "text-error" }
        Str("font-mono text-sm leading-tight italic schema-boolean \{color}")
      },
    },
  )
}

///|
/// A `$ref`. Rendered as a label only — never resolved/followed, so recursive
/// schemas (`{ "$ref": "#" }`) cannot loop.
fn schema_ref_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<span class="font-mono text-sm leading-tight text-secondary schema-ref">→ <span @text=".target"></span></span>
        ),
      ),
    },
    name="SchemaRef",
    init=SchemaRefState::{ target: "" },
  )
}

///|
priv struct ChildValueState {
  value : @tutuca.Value
} derive(ToJson, FromJson)

///|
priv struct ChildOnlyState {
  child : @tutuca.Value
} derive(ToJson, FromJson)

///|
priv struct SchemaConditionalState {
  ifNode : @tutuca.Value
  thenNode : @tutuca.Value
  elseNode : @tutuca.Value
  title : String
  description : String
  deprecated : Bool
} derive(ToJson, FromJson)

///|
priv struct SchemaBooleanState {
  value : Bool
} derive(ToJson, FromJson)

///|
priv struct SchemaRefState {
  target : String
} derive(ToJson, FromJson)
