// Ports of the "Collections" tutorial examples:
//
//   docs/examples/render-with-scope.js       — @enrich-with WITHOUT @each (scope form)
//   docs/examples/list-filter-enrich.js      — @each + @when + @enrich-with
//   docs/examples/list-filter-enrich-with.js — + @loop-with (shared per-loop data)
//
// The `alter` call conventions the renderer uses (render/render.mbt,
// render/loop.mbt), with the instance as `this` in every case:
//
//   @when        args [key, value, iterData]                -> truthy keeps the item
//   @enrich-with args [binds, key, value, iterData]         -> MUTATE binds; return ignored
//   @loop-with   args [seq, loopCtx]                        -> { iterData?, start?, end?, keys? }
//   @enrich-with args [] (scope form, no @each)             -> RETURN a map of binds

///|
/// `@enrich-with` on an element with no `@each` is the *scope* form: the alter
/// returns a map whose keys become `@`-bindings for the subtree. Derived values
/// without putting them in component state.
fn render_with_scope_comp() -> @component.Component {
  @component.component(
    name="RenderWithScope",
    view=(
      #|<section class="flex flex-col gap-3">
      #|  <input class="input" :value=".text" @on.input="$setText value" />
      #|  <div @enrich-with="enrichScope">
      #|    <p>Text: <span class="v-text" @text=".text"></span></p>
      #|    <p>Len: <span class="v-len" @text="@len"></span></p>
      #|    <p>Upper: <span class="v-upper" @text="@upper"></span></p>
      #|  </div>
      #|</section>
    ),
    fields={ "text": @component.FieldSpec::of_default(Str("Hello")) },
    alter={
      "enrichScope": (inst, _args) => {
        match inst.get("text") {
          Str(s) =>
            Map({
              "len": Num(s.length().to_double()),
              "upper": Str(s.to_upper()),
            })
          _ => Map(Map([]))
        }
      },
    },
  )
}

///|
pub fn render_with_scope_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="render-with-scope",
    components=[render_with_scope_comp()],
    examples=[
      {
        component: "RenderWithScope",
        title: "Default",
        args: Map([]),
        view: None,
      },
      {
        component: "RenderWithScope",
        title: "Custom Text",
        args: { "text": Str("Tutuca") },
        view: None,
      },
    ],
  )
}

///|
/// `@enrich-with` inside a loop MUTATES the binds map it is handed — the return
/// value is ignored. Setting `binds["count"]` makes `@count` readable in the row.
fn list_filter_enrich_comp() -> @component.Component {
  @component.component(
    name="ListFilterEnrich",
    view=(
      #|<section class="flex flex-col gap-3">
      #|  <input type="search" class="input" :value=".query"
      #|    @on.input="$setQuery value" @on.keydown+cancel="$resetQuery"
      #|    placeholder="Filter entries" />
      #|  <ul>
      #|    <li @each=".items" @when="filterItem" @enrich-with="enrichItem">
      #|      <span @text="@key"></span>: <x text="@value"></x> (<x text="@count"></x> characters)
      #|    </li>
      #|  </ul>
      #|</section>
    ),
    fields={
      "items": @component.FieldSpec::of_default(List([])),
      "query": @component.FieldSpec::of_default(Str("")),
    },
    alter={
      "filterItem": (inst, args) => {
        match (inst.get("query"), args) {
          (Str(q), [_key, Str(item), ..]) =>
            Bool(item.to_lower().contains(q.to_lower()))
          _ => Bool(true)
        }
      },
      "enrichItem": (_inst, args) => {
        match args {
          [Map(binds), _key, Str(item), ..] =>
            binds["count"] = Num(item.length().to_double())
          _ => ()
        } // the return value is ignored; the mutation is the point
        Null
      },
    },
  )
}

///|
pub fn list_filter_enrich_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="list-filter-enrich",
    components=[list_filter_enrich_comp()],
    examples=[
      {
        component: "ListFilterEnrich",
        title: "Default",
        args: { "items": List(items()) },
        view: None,
      },
    ],
  )
}

///|
/// `@loop-with="getIterData"` runs ONCE before the loop and its `iterData` is
/// handed to every @when / @enrich-with call. `queryLower` is lowercased once
/// instead of per item, and `totalChars` is summed over the WHOLE sequence,
/// before any filtering.
fn list_filter_enrich_with_comp() -> @component.Component {
  @component.component(
    name="ListFilterEnrichWith",
    view=(
      #|<section class="flex flex-col gap-3">
      #|  <input type="search" class="input" :value=".query"
      #|    @on.input="$setQuery value" @on.keydown+cancel="$resetQuery"
      #|    placeholder="Filter entries" />
      #|  <ul>
      #|    <li @each=".items" @when="filterItem" @enrich-with="enrichItem" @loop-with="getIterData">
      #|      <span @text="@key"></span>: <x text="@value"></x> (<x text="@count"></x> / <x text="@total"></x>)
      #|    </li>
      #|  </ul>
      #|</section>
    ),
    fields={
      "items": @component.FieldSpec::of_default(List([])),
      "query": @component.FieldSpec::of_default(Str("")),
    },
    alter={
      "getIterData": (inst, args) => {
        let mut total = 0
        match args {
          [List(seq), ..] =>
            for item in seq {
              match item {
                Str(s) => total += s.length()
                _ => ()
              }
            }
          _ => ()
        }
        let query_lower = match inst.get("query") {
          Str(q) => q.to_lower()
          _ => ""
        }
        Map({
          "iterData": Map({
            "totalChars": Num(total.to_double()),
            "queryLower": Str(query_lower),
          }),
        })
      },
      "filterItem": (_inst, args) => {
        match args {
          [_key, Str(item), Map(iter_data), ..] =>
            match iter_data.get("queryLower") {
              Some(Str(q)) => Bool(item.to_lower().contains(q))
              _ => Bool(true)
            }
          _ => Bool(true)
        }
      },
      "enrichItem": (_inst, args) => {
        match args {
          [Map(binds), _key, Str(item), Map(iter_data), ..] => {
            binds["count"] = Num(item.length().to_double())
            binds["total"] = iter_data.get("totalChars").unwrap_or(Null)
          }
          _ => ()
        }
        Null
      },
    },
  )
}

///|
pub fn list_filter_enrich_with_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="list-filter-enrich-with",
    components=[list_filter_enrich_with_comp()],
    examples=[
      {
        component: "ListFilterEnrichWith",
        title: "Default",
        args: { "items": List(items()) },
        view: None,
      },
    ],
  )
}
