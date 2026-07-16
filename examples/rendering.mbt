// Ports of:
//   docs/examples/push-view.js       — @push-view + <x render-each> + @when
//   docs/examples/seq-item-access.js — .seq[.key] item access as a render target
//   docs/examples/pagination.js      — @loop-with returning a start/end slice
//   docs/examples/todo.js            — a list of child components
//
// Note on building child instances: a Component value carries its own id and is
// bound to the scope it is registered in, so each module builds ONE `entry_comp()`
// and uses that same value both in `components=[...]` and to make its instances.

///|
/// Entries built from the shared sample list — the seed data three of these
/// examples share.
fn entries_of(entry : @component.Component) -> Array[@tutuca.Value] {
  items().map(v => {
    match v {
      Str(s) =>
        entry
        .make({ "title": Str(s), "description": Str("Length: \{s.length()}") })
        .to_value()
      _ => Null
    }
  })
}

///|
/// `@push-view=".view"` pushes a view name onto the render stack: every
/// component rendered underneath (not just direct children) looks for that view
/// first and falls back to "main". Toggling one field flips every Entry between
/// read-only and editable at once.
fn push_view_comp() -> @component.Component {
  @component.component(
    name="PushView",
    view=(
      #|<section class="flex flex-col gap-3">
      #|  <div class="flex justify-between">
      #|    <input type="search" class="input" :value=".query"
      #|      @on.input="$setQuery value" @on.keydown+cancel="$resetQuery"
      #|      placeholder="Filter entries" />
      #|    <button class="btn bnt-sm btn-primary toggle" @text="$getToggleLabel" @on.click="$toggleView"></button>
      #|  </div>
      #|  <div class="flex flex-col gap-3 max-h-[40vh] overflow-y-auto pr-3 rows" @push-view=".view">
      #|    <x render-each=".items" @when="filterItem"></x>
      #|  </div>
      #|</section>
    ),
    fields={
      "items": @component.FieldSpec::of_default(List([])),
      "query": @component.FieldSpec::of_default(Str("")),
      "view": @component.FieldSpec::of_default(Str("main")),
    },
    methods={
      "toggleView": (inst, _args) => {
        match inst.get("view") {
          Str("main") => inst.set("view", Str("edit")).to_value()
          _ => inst.set("view", Str("main")).to_value()
        }
      },
      "getToggleLabel": (inst, _args) => {
        match inst.get("view") {
          Str("main") => Str("Set Edit Mode")
          _ => Str("Set Read Only")
        }
      },
    },
    alter={
      // the item is an Entry INSTANCE, so the filter calls its own method
      "filterItem": (inst, args) => filter_by_contains_text(inst, args),
    },
  )
}

///|
pub fn push_view_module() -> @component.ModuleDef {
  let entry = entry_comp()
  @component.ModuleDef::new(
    name="push-view",
    components=[push_view_comp(), entry],
    examples=[
      {
        component: "PushView",
        title: "Read Only",
        args: { "items": List(entries_of(entry)) },
        view: None,
      },
      {
        component: "PushView",
        title: "Edit Mode",
        args: { "items": List(entries_of(entry)), "view": Str("edit") },
        view: None,
      },
    ],
  )
}

///|
/// `<x render=".byIndex[.currentIndex]">` resolves the inner expression as a key
/// into the outer collection — by index for a List, by string key for a Map.
/// `@text="@value.title"` is the one-level bind-member access.
fn seq_item_access_comp() -> @component.Component {
  @component.component(
    name="SeqItemAccess",
    view=(
      #|<section class="flex flex-col gap-3">
      #|  <input type="range" min="0" :max="$getMaxIndex" :value=".currentIndex"
      #|    @on.input="$setCurrentIndex valueAsInt" />
      #|  <x render=".byIndex[.currentIndex]"></x>
      #|  <select class="select" :value=".currentKey" @on.input="$setCurrentKey value">
      #|    <option @each=".byKey" :value="@key" @text="@value.title"></option>
      #|  </select>
      #|  <x render=".byKey[.currentKey]"></x>
      #|</section>
    ),
    fields={
      "byKey": @component.FieldSpec::of_default(Map({})),
      "byIndex": @component.FieldSpec::of_default(List([])),
      "currentKey": @component.FieldSpec::of_default(Null),
      "currentIndex": @component.FieldSpec::of_default(Num(0)),
    },
    methods={
      "getMaxIndex": (inst, _args) => {
        match inst.get("byIndex") {
          List(a) => Num(@cmp.maximum(0, a.length() - 1).to_double())
          _ => Num(0)
        }
      },
    },
  )
}

///|
pub fn seq_item_access_module() -> @component.ModuleDef {
  let entry = entry_comp()
  let by_index = entries_of(entry)
  let by_key : Map[String, @tutuca.Value] = {}
  for i, v in by_index {
    by_key["key-\{i}"] = v
  }
  @component.ModuleDef::new(
    name="seq-item-access",
    components=[seq_item_access_comp(), entry],
    examples=[
      {
        component: "SeqItemAccess",
        title: "Default",
        args: {
          "byIndex": List(by_index),
          "byKey": Map(by_key),
          "currentKey": Str("key-0"),
        },
        view: None,
      },
    ],
  )
}

///|
/// `@loop-with="paginate"` runs once per render and returns a `start`/`end`
/// slice range: `@each` never walks the off-page items. Slicing keeps each
/// item's ORIGINAL key, so the badge on page 2 reads 5, 6, 7… not 0, 1, 2.
fn pagination_comp() -> @component.Component {
  @component.component(
    name="Pagination",
    view=(
      #|<section class="flex flex-col gap-3">
      #|  <div class="join">
      #|    <button class="btn join-item prev" @on.click="prev" :disabled="$isFirstPage">&lsaquo; Prev</button>
      #|    <button class="btn join-item btn-disabled label" @text="$pageLabel"></button>
      #|    <button class="btn join-item next" @on.click="next" :disabled="$isLastPage">Next &rsaquo;</button>
      #|  </div>
      #|  <ul class="flex flex-col gap-1">
      #|    <li @each=".items" @loop-with="paginate" class="flex gap-2 items-center">
      #|      <span class="badge badge-neutral" @text="@key"></span>
      #|      <x text="@value"></x>
      #|    </li>
      #|  </ul>
      #|</section>
    ),
    fields={
      "items": @component.FieldSpec::of_default(List([])),
      "page": @component.FieldSpec::of_default(Num(0)),
      "pageSize": @component.FieldSpec::of_default(Num(5)),
    },
    methods={
      "pageCount": (inst, _args) => Num(page_count(inst).to_double()),
      "pageLabel": (inst, _args) => {
        let p = int_field(inst, "page")
        Str("Page \{p + 1} of \{page_count(inst)}")
      },
      "isFirstPage": (inst, _args) => Bool(int_field(inst, "page") <= 0),
      "isLastPage": (inst, _args) => {
        Bool(int_field(inst, "page") >= page_count(inst) - 1)
      },
    },
    input={
      "prev": (inst, _args, _ctx) => {
        let p = @cmp.maximum(0, int_field(inst, "page") - 1)
        Some(inst.set("page", Num(p.to_double())))
      },
      "next": (inst, _args, _ctx) => {
        let p = @cmp.minimum(page_count(inst) - 1, int_field(inst, "page") + 1)
        Some(inst.set("page", Num(p.to_double())))
      },
    },
    alter={
      // once per render: turn the current page into a slice range
      "paginate": (inst, args) => {
        let total = match args {
          [List(seq), ..] => seq.length()
          _ => 0
        }
        let start = int_field(inst, "page") * int_field(inst, "pageSize")
        Map({
          "iterData": Map({ "total": Num(total.to_double()) }),
          "start": Num(start.to_double()),
          "end": Num((start + int_field(inst, "pageSize")).to_double()),
        })
      },
    },
  )
}

///|
fn page_count(inst : @component.Instance) -> Int {
  let size = match inst.get("items") {
    List(a) => a.length()
    _ => 0
  }
  let per = @cmp.maximum(1, int_field(inst, "pageSize"))
  @cmp.maximum(1, (size + per - 1) / per) // ceil
}

///|
pub fn pagination_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="pagination", components=[pagination_comp()], examples=[
    {
      component: "Pagination",
      title: "First Page",
      args: { "items": List(items()) },
      view: None,
    },
    {
      component: "Pagination",
      title: "Second Page",
      args: { "items": List(items()), "page": Num(1) },
      view: None,
    },
  ])
}
