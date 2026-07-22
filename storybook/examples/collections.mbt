// Ports of the "Collections" tutorial examples:
//
//   docs/examples/render-with-scope.js       — @enrich-with WITHOUT @each (scope form)
//   docs/examples/list-filter-enrich.js      — @each + @when + @enrich-with
//   docs/examples/list-filter-enrich-with.js — + @loop-with (shared per-loop data)
//
// Each render-time directive now has its own TYPED bucket, so the handler
// signatures say what the renderer hands them (state first, always):
//
//   when         (s, key, value, iterData) -> Bool           true keeps the item
//   enrich       (s, binds, key, value, iterData) -> Unit    MUTATE binds; return ignored
//   loop_with    (s, seq, loopCtx) -> LoopWith               iter_data? / start? / end? / keys?
//   enrich_scope (s) -> Map[String, Value]                   RETURN the binds (no @each)

///|
priv struct RenderWithScopeState {
  text : String
} derive(ToJson, FromJson)

///|
/// `@enrich-with` on an element with no `@each` is the *scope* form: the
/// `enrich_scope` handler returns a map whose keys become `@`-bindings for the
/// subtree. Derived values without putting them in component state.
fn render_with_scope_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section class="flex flex-col gap-3">
          #|  <input class="input" :value=".text" @on.input="$setText value" />
          #|  <div @enrich-with="enrichScope">
          #|    <p>Text: <span class="v-text" @text=".text"></span></p>
          #|    <p>Len: <span class="v-len" @text="@len"></span></p>
          #|    <p>Upper: <span class="v-upper" @text="@upper"></span></p>
          #|  </div>
          #|</section>
        ),
      ),
    },
    name="RenderWithScope",
    init=RenderWithScopeState::{ text: "Hello" },
    enrich_scope={
      "enrichScope": (s : RenderWithScopeState) => {
        "len": Num(s.text.length().to_double()),
        "upper": Str(s.text.to_upper()),
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
priv struct ListFilterEnrichState {
  items : Array[@tutuca.Value]
  query : String
} derive(ToJson, FromJson)

///|
/// `enrich` inside a loop MUTATES the binds map it is handed — the return
/// value is Unit. Setting `binds["count"]` makes `@count` readable in the row.
fn list_filter_enrich_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
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
      ),
    },
    name="ListFilterEnrich",
    init=ListFilterEnrichState::{ items: [], query: "" },
    when={
      "filterItem": (s : ListFilterEnrichState, _key, value, _iter) => {
        match value {
          Str(item) => item.to_lower().contains(s.query.to_lower())
          _ => true
        }
      },
    },
    enrich={
      "enrichItem": (_s : ListFilterEnrichState, binds, _key, value, _iter) => {
        match value {
          Str(item) => binds["count"] = Num(item.length().to_double())
          _ => ()
        }
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
/// `@loop-with="getIterData"` runs ONCE before the loop and its `iter_data` is
/// handed to every when / enrich call. `queryLower` is lowercased once
/// instead of per item, and `totalChars` is summed over the WHOLE sequence,
/// before any filtering.
fn list_filter_enrich_with_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
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
      ),
    },
    name="ListFilterEnrichWith",
    init=ListFilterEnrichState::{ items: [], query: "" },
    loop_with={
      "getIterData": (s : ListFilterEnrichState, seq, _ctx) => {
        let mut total = 0
        for item in seq.list() {
          match item {
            Str(v) => total += v.length()
            _ => ()
          }
        }
        @component.LoopWith::new(
          iter_data=Map({
            "totalChars": Num(total.to_double()),
            "queryLower": Str(s.query.to_lower()),
          }),
        )
      },
    },
    when={
      "filterItem": (_s : ListFilterEnrichState, _key, value, iter) => {
        match (value, iter) {
          (Str(item), Map(iter_data)) =>
            match iter_data.get("queryLower") {
              Some(Str(q)) => item.to_lower().contains(q)
              _ => true
            }
          _ => true
        }
      },
    },
    enrich={
      "enrichItem": (_s : ListFilterEnrichState, binds, _key, value, iter) => {
        match (value, iter) {
          (Str(item), Map(iter_data)) => {
            binds["count"] = Num(item.length().to_double())
            binds["total"] = iter_data.get("totalChars").unwrap_or(Null)
          }
          _ => ()
        }
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
