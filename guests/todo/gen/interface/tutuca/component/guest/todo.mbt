///| HANDWRITTEN (not wit-bindgen output, unlike the sibling ffi/top files —
/// regeneration must not touch it; see ../../../../../README.md).
///
/// The todo guest module: a single `tutuca:component` with opaque native
/// state (a list of items + a draft string), styled with margaui utility
/// classes. Mirrors guests/counter — one struct implementing `DynComponent`
/// plus a `dyn_module()` factory — but exercises per-item events: the host
/// renders `<li @each=".items">` and forwards the loop `@key` (and the input
/// `value`/`isSend`) as handler args, so a single opaque instance handles
/// toggle/remove/add without nested children.
///
/// Everything an author writes is in this file; sdk.mbt does the rest.

///|
priv struct TodoItem {
  text : String
  done : Bool
}

///|
priv struct Todo {
  items : Array[TodoItem]
  draft : String
}

///|
/// A list Value of {text, done} maps for the host to iterate with @each.
fn Todo::items_value(self : Todo) -> @values.Value {
  let l = @values.list_new()
  for it in self.items {
    let m = @values.map_new()
    @values.map_set(m, "text", @values.Value::Text(it.text))
    @values.map_set(m, "done", @values.Value::Boolean(it.done))
    @values.list_push(l, @values.Value::Map(m))
  }
  @values.Value::List(l)
}

///|
/// Parse a loop @key arg (a list index) into an Int; tolerate Number or Text.
fn key_index(args : Array[@values.Value]) -> Int? {
  // an @each over a list field passes the loop index as a Number
  match args {
    [@values.Value::Number(n), ..] => Some(n.to_int())
    _ => None
  }
}

///|
impl DynComponent for Todo with fn get_field(self, name) {
  match name {
    "draft" => Some(@values.Value::Text(self.draft))
    "items" => Some(self.items_value())
    _ => None
  }
}

///|
impl DynComponent for Todo with fn handle(self, bucket, name, _event, args) {
  guard bucket is INPUT else { return None }
  match name {
    // draft input: `@on.input="setDraft value"` -> args = [text]
    "setDraft" =>
      match args {
        [@values.Value::Text(s), ..] =>
          Some({ items: self.items, draft: s } as &DynComponent)
        _ => None
      }
    // Add button, or Enter in the input via `addOnEnter isSend`
    "add" => self.add_draft()
    "addOnEnter" =>
      match args {
        [@values.Value::Boolean(true), ..] => self.add_draft()
        _ => None
      }
    // `@on.input="toggleAt @key"` / `@on.click="removeAt @key"` carry the
    // loop index (see key_index)
    "toggleAt" =>
      match key_index(args) {
        Some(i) => self.toggle_at(i)
        None => None
      }
    "removeAt" =>
      match key_index(args) {
        Some(i) => self.remove_at(i)
        None => None
      }
    "clearDone" => {
      let kept = self.items.filter(it => !it.done)
      Some({ items: kept, draft: self.draft } as &DynComponent)
    }
    _ => None
  }
}

///|
fn Todo::add_draft(self : Todo) -> &DynComponent? {
  let text = self.draft.trim(chars=" ").to_owned()
  guard text != "" else { return None }
  let items = self.items.copy()
  items.push({ text, done: false })
  Some({ items, draft: "" } as &DynComponent)
}

///|
fn Todo::toggle_at(self : Todo, i : Int) -> &DynComponent? {
  guard i >= 0 && i < self.items.length() else { return None }
  let items = self.items.copy()
  let it = items[i]
  items[i] = { text: it.text, done: !it.done }
  Some({ items, draft: self.draft } as &DynComponent)
}

///|
fn Todo::remove_at(self : Todo, i : Int) -> &DynComponent? {
  guard i >= 0 && i < self.items.length() else { return None }
  let items = self.items.copy()
  items.remove(i) |> ignore
  Some({ items, draft: self.draft } as &DynComponent)
}

///|
/// `$summary` — a render-time view method (count of done / total).
impl DynComponent for Todo with fn call_method(self, name, _args) {
  match name {
    "summary" => {
      let total = self.items.length()
      let done = self.items.filter(it => it.done).length()
      @values.Value::Text("Todo — \{done}/\{total} done")
    }
    _ => @values.Value::Nil
  }
}

///|
/// JSON projection used for inspection and hot-swap migration; make_todo
/// reads it back.
impl DynComponent for Todo with fn to_json(self) {
  let root = @values.map_new()
  @values.map_set(root, "draft", @values.Value::Text(self.draft))
  @values.map_set(root, "items", self.items_value())
  @values.to_json(@values.Value::Map(root))
}

///|
fn make_todo(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut draft = ""
  let items : Array[TodoItem] = []
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      ("draft", @values.Value::Text(s)) => draft = s
      // hot-swap migration hands the to-json projection back as args
      ("items", @values.Value::List(h)) =>
        for i in 0U..<@values.list_len(h) {
          match @values.list_get(h, i) {
            @values.Value::Map(mh) => {
              let text = match @values.map_get(mh, "text") {
                Some(@values.Value::Text(t)) => t
                _ => ""
              }
              let done = match @values.map_get(mh, "done") {
                Some(@values.Value::Boolean(b)) => b
                _ => false
              }
              items.push({ text, done })
            }
            _ => ()
          }
        }
      _ => ()
    }
  }
  ({ items, draft } : Todo) as &DynComponent
}

///|
fn todo_def() -> ComponentDef {
  {
    name: "Todo",
    views: [
      {
        name: "main",
        html: (
          #|<div class="card bg-base-100 border border-base-300 shadow-sm w-80 todo">
          #|  <div class="card-body gap-3">
          #|    <h2 class="card-title text-base" @text="$summary"></h2>
          #|    <div class="join w-full">
          #|      <input class="input input-bordered input-sm join-item grow" placeholder="Add a task…" :value=".draft" @on.input="setDraft value" @on.keydown="addOnEnter isSend" />
          #|      <button class="btn btn-sm btn-primary join-item" @on.click="add">Add</button>
          #|    </div>
          #|    <ul class="flex flex-col gap-1" @hide="empty? .items">
          #|      <li class="flex gap-2 items-center" @each=".items">
          #|        <input type="checkbox" class="checkbox checkbox-sm" :checked="@value.done" @on.input="toggleAt @key" />
          #|        <span class="grow text-sm" @text="@value.text"></span>
          #|        <button class="btn btn-ghost btn-xs btn-circle" @on.click="removeAt @key">✕</button>
          #|      </li>
          #|    </ul>
          #|    <p class="text-sm opacity-60 italic" @show="empty? .items">No tasks yet — add one above.</p>
          #|  </div>
          #|</div>
        ),
      },
    ],
    input_handlers: [
      "setDraft", "add", "addOnEnter", "toggleAt", "removeAt", "clearDone",
    ],
    receive_handlers: [],
    response_handlers: [],
    method_names: ["summary"],
    // styling is entirely margaui (daisyUI) classes; no scoped fallback CSS
    style: "",
  }
}

///|
fn dyn_module() -> DynModule {
  { name: "todolib", components: [{ def: todo_def(), make: make_todo }] }
}
