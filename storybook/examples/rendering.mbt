///|
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
/// `@push-view=".view"` pushes a view name onto the render stack: every
/// component rendered underneath (not just direct children) looks for that view
/// first and falls back to "main". Toggling one field flips every Entry between
/// read-only and editable at once.
fn push_view_comp() -> @component.Component {
  push_view_component(
    initial={ items: [], query: "", view: "main", },
    compute=m => {
      match m {
        GetToggleLabel =>
          Some((s, _args, _stack) => {
            if s.view == "main" {
              Str("Set Edit Mode")
            } else {
              Str("Set Read Only")
            }
          })
      }
    },
    when=w => {
      match w {
        // the item is an Entry INSTANCE, so the filter calls its own method
        FilterItem =>
          Some((s, _k, item, _iter, _stack) => {
            contains_text_filter(s.query, item)
          })
      }
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
/// `<x render=".by_index[.current_index]">` resolves the inner expression as a key
/// into the outer collection — by index for a List, by string key for a Map.
/// `@text="@value.title"` is the one-level bind-member access.
fn seq_item_access_comp() -> @component.Component {
  seq_item_access_component(
    initial={
      by_key: Map([]),
      by_index: [],
      current_key: Null,
      current_index: 0,
    },
    compute=m => {
      match m {
        GetMaxIndex =>
          Some((s, _args, _stack) => {
            Num(@cmp.maximum(0, s.by_index.length() - 1).to_double())
          })
      }
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
          "by_index": List(by_index),
          "by_key": Map(by_key),
          "current_key": Str("key-0"),
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
///
/// `prev` and `next` are in the view file's `<script type="tutuca/script">`
/// block — `clamp`, `min` and `max` are in that language because moving a page
/// index is the commonest handler there is. `page_count` stays here for the
/// labels, which are `compute`s.
fn pagination_comp() -> @component.Component {
  pagination_component(
    initial={ items: [], page: 0, page_size: 5, },
    compute=m => {
      match m {
        // No `PageCount`: nothing called `$pageCount`, in a view or out of one.
        // The string-keyed bucket had no way to say so.
        PageLabel =>
          Some((s, _args, _stack) => {
            Str("Page \{s.page + 1} of \{page_count(s)}")
          })
        IsFirstPage => Some((s, _args, _stack) => Bool(s.page <= 0))
        IsLastPage =>
          Some((s, _args, _stack) => Bool(s.page >= page_count(s) - 1))
      }
    },
    loop_with=l => {
      match l {
        // once per render: turn the current page into a slice range
        Paginate =>
          Some((s, seq, _ctx) => {
            let total = match seq {
              List(a) => a.length()
              _ => 0
            }
            let start = s.page * s.page_size
            @component.LoopWith::new(
              iter_data=Map({ "total": Num(total.to_double()) }),
              start~,
              end=start + s.page_size,
            )
          })
      }
    },
  )
}

///|
fn page_count(s : PaginationState) -> Int {
  let size = s.items.length()
  let per = @cmp.maximum(1, s.page_size)
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
