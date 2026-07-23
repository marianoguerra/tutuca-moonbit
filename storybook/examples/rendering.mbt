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
        entry.make({
          "title": Str(s),
          "description": Str("Length: \{s.length()}"),
        })
      _ => Null
    }
  })
}

///|
priv struct PushViewState {
  items : Array[@tutuca.Value]
  query : String
  view : String
} derive(ToJson, FromJson)

///|
/// `@push-view=".view"` pushes a view name onto the render stack: every
/// component rendered underneath (not just direct children) looks for that view
/// first and falls back to "main". Toggling one field flips every Entry between
/// read-only and editable at once.
fn push_view_comp() -> @component.Component {
  @component.component(
    views=push_view_views(),
    name="PushView",
    init=PushViewState::{ items: [], query: "", view: "main" },
    mutate={
      "toggleView": (s : PushViewState, _args) => {
        ..s,
        view: if s.view == "main" {
          "edit"
        } else {
          "main"
        },
      },
    },
    compute={
      "getToggleLabel": (s : PushViewState, _args) => {
        if s.view == "main" {
          Str("Set Edit Mode")
        } else {
          Str("Set Read Only")
        }
      },
    },
    when={
      // the item is an Entry INSTANCE, so the filter calls its own method
      "filterItem": (s : PushViewState, _k, item, _iter) => {
        contains_text_filter(s.query, item)
      },
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
priv struct SeqItemAccessState {
  byKey : Map[String, @tutuca.Value]
  byIndex : Array[@tutuca.Value]
  currentKey : @tutuca.Value
  currentIndex : Int
} derive(ToJson, FromJson)

///|
/// `<x render=".byIndex[.currentIndex]">` resolves the inner expression as a key
/// into the outer collection — by index for a List, by string key for a Map.
/// `@text="@value.title"` is the one-level bind-member access.
fn seq_item_access_comp() -> @component.Component {
  @component.component(
    views=seq_item_access_views(),
    name="SeqItemAccess",
    init=SeqItemAccessState::{
      byKey: Map([]),
      byIndex: [],
      currentKey: Null,
      currentIndex: 0,
    },
    compute={
      "getMaxIndex": (s : SeqItemAccessState, _args) => {
        Num(@cmp.maximum(0, s.byIndex.length() - 1).to_double())
      },
    },
  )
}

///|
pub fn seq_item_access_module() -> @component.ModuleDef {
  let entry = entry_comp()
  let by_index = entries_of(entry)
  let by_key : Map[String, @tutuca.Value] = Map([])
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
priv struct PaginationState {
  items : Array[@tutuca.Value]
  page : Int
  pageSize : Int
} derive(ToJson, FromJson)

///|
/// `@loop-with="paginate"` runs once per render and returns a `start`/`end`
/// slice range: `@each` never walks the off-page items. Slicing keeps each
/// item's ORIGINAL key, so the badge on page 2 reads 5, 6, 7… not 0, 1, 2.
fn pagination_comp() -> @component.Component {
  @component.component(
    views=pagination_views(),
    name="Pagination",
    init=PaginationState::{ items: [], page: 0, pageSize: 5 },
    compute={
      "pageCount": (s : PaginationState, _args) => {
        Num(page_count(s).to_double())
      },
      "pageLabel": (s : PaginationState, _args) => {
        Str("Page \{s.page + 1} of \{page_count(s)}")
      },
      "isFirstPage": (s : PaginationState, _args) => Bool(s.page <= 0),
      "isLastPage": (s : PaginationState, _args) => {
        Bool(s.page >= page_count(s) - 1)
      },
    },
    update=(s : PaginationState, msg, _ctx) => {
      match PaginationMsg::from_dispatch(msg) {
        Some(Prev) => Some({ ..s, page: @cmp.maximum(0, s.page - 1) })
        Some(Next) =>
          Some({ ..s, page: @cmp.minimum(page_count(s) - 1, s.page + 1) })
        Some(Unknown(_, _)) | None => None
      }
    },
    loop_with={
      // once per render: turn the current page into a slice range
      "paginate": (s : PaginationState, seq, _ctx) => {
        let total = match seq {
          List(a) => a.length()
          _ => 0
        }
        let start = s.page * s.pageSize
        @component.LoopWith::new(
          iter_data=Map({ "total": Num(total.to_double()) }),
          start~,
          end=start + s.pageSize,
        )
      },
    },
  )
}

///|
fn page_count(s : PaginationState) -> Int {
  let size = s.items.length()
  let per = @cmp.maximum(1, s.pageSize)
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
