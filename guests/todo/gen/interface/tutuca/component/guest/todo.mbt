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
impl DynComponent for Todo with fn handle(self, bucket, name, args) {
  guard bucket is INPUT else { return None }
  match name {
    // There is no "setDraft" case: `draft` is a declared field, so the host
    // generates `setDraft` from the schema and writes it through `with_field`
    // below. A handler here would be the same assignment written twice.
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
/// The COW write-through every declared field needs: it is what the host's
/// generated mutators (`setDraft`, `pushInItems`, `removeInItemsAt`, …) write
/// through, and what a host path writes through to reach this instance.
impl DynComponent for Todo with fn with_field(self, name, v) {
  match (name, v) {
    ("draft", @values.Value::Text(s)) =>
      Some({ items: self.items, draft: s } as &DynComponent)
    ("items", @values.Value::List(h)) =>
      Some({ items: items_of(h), draft: self.draft } as &DynComponent)
    _ => None
  }
}

///|
/// The inverse of `items_value`: a host list of {text, done} maps back into
/// items. Both a fresh instance (constructor args, including the ones hot-swap
/// migration hands back) and a `with_field` write arrive in this shape.
fn items_of(h : UInt64) -> Array[TodoItem] {
  let items : Array[TodoItem] = []
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
  items
}

///|
/// The whole state as UTF-8 JSON — the bytes the host stores and hands back.
///
/// This guest persists even though its fields would project fine, and the
/// reason is `draft`: a task half-typed is state a person would be annoyed to
/// lose, and it is exactly the kind of thing a guest knows to keep and a host
/// cannot. The format is this guest's own business; the host never looks in.
impl DynComponent for Todo with fn persist(self) {
  let items : Array[Json] = self.items.map(it => {
    ({ "text": Json::string(it.text), "done": Json::boolean(it.done) } : Json)
  })
  bytes_of(
    ({ "v": Json::number(1), "draft": Json::string(self.draft), "items": Json::array(items) } : Json).stringify(),
  )
}

///|
/// The inverse. None refuses the bytes — a version this guest no longer reads,
/// or text that is not the JSON it wrote — and the host then rebuilds from the
/// declared fields instead, which loses the draft and nothing else.
fn restore_todo(state : FixedArray[Byte]) -> &DynComponent? {
  let text = text_of(state)
  guard text != "" else { return None }
  let parsed = @json.parse(text) catch {
    _ => return None
  }
  guard parsed is Object(m) else { return None }
  guard m.get("v") is Some(Number(1, ..)) else { return None }
  let draft = match m.get("draft") {
    Some(String(s)) => s
    _ => ""
  }
  let items : Array[TodoItem] = []
  if m.get("items") is Some(Array(entries)) {
    for e in entries {
      guard e is Object(im) else { continue }
      let text = match im.get("text") {
        Some(String(s)) => s
        _ => ""
      }
      let done = im.get("done") is Some(True)
      items.push({ text, done })
    }
  }
  Some(({ items, draft } : Todo) as &DynComponent)
}

///|
fn make_todo(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut draft = ""
  let mut items : Array[TodoItem] = []
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      ("draft", @values.Value::Text(s)) => draft = s
      // hot-swap migration hands the declared fields back as args
      ("items", @values.Value::List(h)) => items = items_of(h)
      _ => ()
    }
  }
  ({ items, draft } : Todo) as &DynComponent
}

///|
fn todo_def() -> ComponentDef {
  component_def(
    "Todo",
    doc="A task list: type a task, add it, tick it off, remove it.",
    keywords=["todo", "task", "list", "checklist"],
    category="input",
    message_docs=[
      { name: "add", doc: "Add the drafted task to the list." },
      { name: "addOnEnter", doc: "Add the draft when the key was Enter." },
      { name: "toggleAt", doc: "Tick or untick the task at an index." },
      { name: "removeAt", doc: "Delete the task at an index." },
      { name: "clearDone", doc: "Remove every ticked task." },
      { name: "summary", doc: "How many tasks are done, as a sentence." },
    ],
    views=[
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
    // `items` is a list of {text, done} records; declaring it is what gives
    // the host `setDraft` (which this guest no longer implements), the item
    // mutators, structural equality and the JSON projection.
    types=[
      { kind: TY_TEXT, elem: None, items: [], name: "", members: [] },
      { kind: TY_RECORD, elem: None, items: [], name: "todo-item", members: [] },
      { kind: TY_LIST, elem: Some(1), items: [], name: "", members: [] },
    ],
    fields=[
      field(
        "draft",
        0,
        doc="The task being typed, not yet added.",
        constraint=Some({ ..no_limits(), max_len: Some(200) }),
      ),
      field("items", 2, doc="The tasks, in the order they were added."),
    ],
    // `setDraft` is absent on purpose: the `draft` field implies it, and the
    // host answers it (see `with_field`)
    handlers=["add", "addOnEnter", "toggleAt", "removeAt", "clearDone"],
    methods=["summary"],
    inits=[
      {
        name: "groceries",
        args_json: "{\"items\": [{\"text\": \"milk\", \"done\": false}, {\"text\": \"bread\", \"done\": true}]}",
        doc: "A short shopping list, one item already bought.",
      },
    ],
    // styling is entirely margaui (daisyUI) classes; no scoped fallback CSS
  )
}

///|
fn dyn_module() -> DynModule {
  module_def(
    "todolib",
    [dyn_comp(todo_def(), make_todo, restore=restore_todo)],
    // this bundle serves no requests of its own, and asks the host for nothing
    doc="A sample task list, for exercising list fields and item mutators.",
    version="0.4.0",
  )
}
