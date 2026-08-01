///| HANDWRITTEN (not wit-bindgen output, unlike the sibling ffi/top files —
/// regeneration must not touch it; see ../../../../../README.md).
///
/// TodoMVC as a `tutuca:component` guest: add, toggle, edit in place, delete,
/// toggle-all, filter, clear-completed, count-left — the canonical list, with
/// nothing left out because it was awkward.
///
/// It exists to answer one question the sibling `todo` guest cannot: what
/// belongs in the DECLARED state and what belongs to the guest alone. The
/// items and the current filter are declared, so the host projects them,
/// compares them, migrates them across a hot swap, and generates `setFilter` —
/// which is why no handler here answers that name. The draft, the row being
/// edited and the text being typed into it are NOT declared: they are what
/// this component is doing rather than what it holds, and the host has no
/// business rendering a form over them. They survive a reload anyway, because
/// `persist` writes them and the host stores the bytes without reading them.
///
/// Everything an author writes is in this file; sdk.mbt does the rest.

///|
priv struct MvcItem {
  text : String
  done : Bool
}

///|
priv struct TodoMvc {
  /// DECLARED. The list itself, in the order it was typed.
  items : Array[MvcItem]
  /// DECLARED: "all" / "active" / "completed". The host generates `setFilter`
  /// from it, so the three filter buttons need no guest code.
  filter : String
  /// The rest is this guest's own: what is half-typed, which row is open for
  /// editing, and what is in that row's box.
  draft : String
  editing : Int
  edit_text : String
}

///|
/// The item list as the view iterates it.
///
/// `editing` rides with each row because `@each` takes a FIELD and not a
/// method — a method result has no addressable path, so nothing could be
/// dispatched against it — and comparing an index inside a view is not
/// something the template language does. It is DERIVED on every read, so it
/// cannot disagree with `editing`, and a write that carries a stale one is
/// ignored by `items_of` below.
fn TodoMvc::items_value(self : TodoMvc) -> @values.Value {
  let l = @values.list_new()
  for i, it in self.items {
    let m = @values.map_new()
    @values.map_set(m, "text", @values.Value::Text(it.text))
    @values.map_set(m, "done", @values.Value::Boolean(it.done))
    @values.map_set(m, "editing", @values.Value::Boolean(i == self.editing))
    @values.list_push(l, @values.Value::Map(m))
  }
  @values.Value::List(l)
}

///|
/// The inverse: a host list of {text, done} maps back into items. Both a fresh
/// instance (constructor args, including what a hot swap or a field-restore
/// hands back) and a `with_field` write arrive in this shape.
fn items_of(h : UInt64) -> Array[MvcItem] {
  let items : Array[MvcItem] = []
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
/// A successor with the same everything except what is named. MoonBit has no
/// record update across a `&DynComponent`, so this is the one place the five
/// fields are listed and every handler below reads as the change it makes.
fn TodoMvc::changed(
  self : TodoMvc,
  items? : Array[MvcItem]? = None,
  filter? : String? = None,
  draft? : String? = None,
  editing? : Int? = None,
  edit_text? : String? = None,
) -> &DynComponent {
  (
    {
      items: items.unwrap_or(self.items),
      filter: filter.unwrap_or(self.filter),
      draft: draft.unwrap_or(self.draft),
      editing: editing.unwrap_or(self.editing),
      edit_text: edit_text.unwrap_or(self.edit_text),
    } : TodoMvc)
  as &DynComponent
}

///|
/// The loop `@key` a per-row handler carries, as an index.
fn key_index(args : Array[@values.Value]) -> Int? {
  match args {
    [@values.Value::Number(n), ..] => Some(n.to_int())
    _ => None
  }
}

///|
fn text_arg(args : Array[@values.Value]) -> String? {
  match args {
    [@values.Value::Text(s), ..] => Some(s)
    _ => None
  }
}

///|
impl DynComponent for TodoMvc with fn get_field(self, name) {
  match name {
    "items" => Some(self.items_value())
    "filter" => Some(@values.Value::Text(self.filter))
    _ => None
  }
}

///|
/// The declared fields, written through. `filter` is here rather than in
/// `handle` because the host's generated `setFilter` is what the three filter
/// buttons call — a handler of the same name would be that assignment written
/// twice, and would win over the mutator besides.
impl DynComponent for TodoMvc with fn with_field(self, name, v) {
  match (name, v) {
    ("items", @values.Value::List(h)) =>
      Some(self.changed(items=Some(items_of(h))))
    ("filter", @values.Value::Text(f)) =>
      if f == "all" || f == "active" || f == "completed" {
        Some(self.changed(filter=Some(f)))
      } else {
        // A filter nobody defined would hide every row and look like data
        // loss, so it is refused: the host reads None as "unchanged".
        None
      }
    _ => None
  }
}

///|
impl DynComponent for TodoMvc with fn handle(self, bucket, name, args) {
  guard bucket is INPUT else { return None }
  match name {
    "typeDraft" =>
      match text_arg(args) {
        Some(s) => Some(self.changed(draft=Some(s)))
        None => None
      }
    // The Enter key on the new-todo box (`@on.keydown+send="addOnEnter isSend"`)
    // and the Add button reach the same place.
    "addOnEnter" =>
      match args {
        [@values.Value::Boolean(true), ..] => self.add_draft()
        _ => None
      }
    "add" => self.add_draft()
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
    // The classic chevron: everything on, unless everything already is.
    "toggleAll" => {
      let all_done = self.items.length() > 0 &&
        self.items.filter(it => !it.done).length() == 0
      let items = self.items.map(it => {
        ({ text: it.text, done: !all_done } : MvcItem)
      })
      Some(self.changed(items=Some(items)))
    }
    "clearCompleted" =>
      Some(self.changed(items=Some(self.items.filter(it => !it.done))))
    // Editing in place: open the row, type into it, and either commit or
    // abandon. Committing an empty row DELETES it, which is what TodoMVC
    // specifies and what a person emptying a box means.
    "startEdit" =>
      match key_index(args) {
        Some(i) =>
          if i >= 0 && i < self.items.length() {
            Some(
              self.changed(editing=Some(i), edit_text=Some(self.items[i].text)),
            )
          } else {
            None
          }
        None => None
      }
    "typeEdit" =>
      match text_arg(args) {
        Some(s) => Some(self.changed(edit_text=Some(s)))
        None => None
      }
    "commitEdit" => self.commit_edit()
    "cancelEdit" =>
      if self.editing < 0 {
        None
      } else {
        Some(self.changed(editing=Some(-1), edit_text=Some("")))
      }
    _ => None
  }
}

///|
fn TodoMvc::add_draft(self : TodoMvc) -> &DynComponent? {
  let text = self.draft.trim(chars=" ").to_owned()
  guard text != "" else { return None }
  let items = self.items.copy()
  items.push({ text, done: false })
  Some(self.changed(items=Some(items), draft=Some("")))
}

///|
fn TodoMvc::toggle_at(self : TodoMvc, i : Int) -> &DynComponent? {
  guard i >= 0 && i < self.items.length() else { return None }
  let items = self.items.copy()
  let it = items[i]
  items[i] = { text: it.text, done: !it.done }
  Some(self.changed(items=Some(items)))
}

///|
fn TodoMvc::remove_at(self : TodoMvc, i : Int) -> &DynComponent? {
  guard i >= 0 && i < self.items.length() else { return None }
  let items = self.items.copy()
  items.remove(i) |> ignore
  // A row that disappears takes the edit box with it, and a row that shifts up
  // takes the cursor's index with it.
  let editing = if self.editing == i {
    -1
  } else if self.editing > i {
    self.editing - 1
  } else {
    self.editing
  }
  Some(self.changed(items=Some(items), editing=Some(editing)))
}

///|
fn TodoMvc::commit_edit(self : TodoMvc) -> &DynComponent? {
  guard self.editing >= 0 && self.editing < self.items.length() else {
    return None
  }
  let text = self.edit_text.trim(chars=" ").to_owned()
  if text == "" {
    return self.remove_at(self.editing)
  }
  let items = self.items.copy()
  items[self.editing] = { text, done: items[self.editing].done }
  Some(self.changed(items=Some(items), editing=Some(-1), edit_text=Some("")))
}

///|
/// The render-time reads, plus the `@when` filter.
///
/// `matchesFilter` is what makes the three filters cost no state: the view
/// iterates every item and this answers, per item, whether the filter lets it
/// through — so an item's `@key` stays its index in the WHOLE list and the
/// per-row handlers keep working while a filter is on.
impl DynComponent for TodoMvc with fn call_method(self, name, args) {
  match name {
    "draft" => @values.Value::Text(self.draft)
    "editText" => @values.Value::Text(self.edit_text)
    "countLeft" => {
      let left = self.items.filter(it => !it.done).length()
      @values.Value::Text(
        if left == 1 {
          "1 item left"
        } else {
          "\{left} items left"
        },
      )
    }
    // What "clear done" is for; a view hides the button with `empty? $done`.
    "done" => {
      let l = @values.list_new()
      for it in self.items {
        if it.done {
          @values.list_push(l, @values.Value::Text(it.text))
        }
      }
      @values.Value::List(l)
    }
    "matchesFilter" =>
      match args {
        // (key, item, iter-data) — the item is the map `items_value` built
        [_, @values.Value::Map(mh), ..] => {
          let done = match @values.map_get(mh, "done") {
            Some(@values.Value::Boolean(b)) => b
            _ => false
          }
          @values.Value::Boolean(
            match self.filter {
              "active" => !done
              "completed" => done
              _ => true
            },
          )
        }
        _ => @values.Value::Boolean(true)
      }
    _ => @values.Value::Nil
  }
}

// --- persistence -------------------------------------------------------------

///|
/// Everything, as UTF-8 JSON: the declared half AND the half only this guest
/// knows about. That second half is the reason this component persists at all
/// — the host could rebuild the items and the filter on its own, but not the
/// sentence you were halfway through typing.
impl DynComponent for TodoMvc with fn persist(self) {
  let items : Array[Json] = self.items.map(it => {
    ({ "text": Json::string(it.text), "done": Json::boolean(it.done) } : Json)
  })
  bytes_of(
    (
      {
        "v": Json::number(1),
        "items": Json::array(items),
        "filter": Json::string(self.filter),
        "draft": Json::string(self.draft),
        "editing": Json::number(self.editing.to_double()),
        "editText": Json::string(self.edit_text),
      } : Json).stringify(),
  )
}

///|
/// The inverse. None refuses the bytes — a version this guest no longer reads,
/// or text that is not the JSON it wrote — and the host then rebuilds from the
/// declared fields, which keeps the list and loses the typing.
fn restore_todomvc(state : FixedArray[Byte]) -> &DynComponent? {
  let text = text_of(state)
  guard text != "" else { return None }
  let parsed = @json.parse(text) catch { _ => return None }
  guard parsed is Object(m) else { return None }
  guard m.get("v") is Some(Number(1, ..)) else { return None }
  let str_at = (key : String) => {
    match m.get(key) {
      Some(String(s)) => s
      _ => ""
    }
  }
  let items : Array[MvcItem] = []
  if m.get("items") is Some(Array(entries)) {
    for e in entries {
      guard e is Object(im) else { continue }
      let text = match im.get("text") {
        Some(String(s)) => s
        _ => ""
      }
      items.push({ text, done: im.get("done") is Some(True) })
    }
  }
  let editing = match m.get("editing") {
    Some(Number(n, ..)) => n.to_int()
    _ => -1
  }
  let filter = match str_at("filter") {
    "active" => "active"
    "completed" => "completed"
    _ => "all"
  }
  Some(
    (
      {
        items,
        filter,
        draft: str_at("draft"),
        editing: if editing >= 0 && editing < items.length() {
          editing
        } else {
          -1
        },
        edit_text: str_at("editText"),
      } : TodoMvc)
    as &DynComponent,
  )
}

///|
fn make_todomvc(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut items : Array[MvcItem] = []
  let mut filter = "all"
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      // hot-swap migration and a field-restore both hand the declared fields
      // back as constructor args
      ("items", @values.Value::List(h)) => items = items_of(h)
      ("filter", @values.Value::Text(f)) =>
        if f == "active" || f == "completed" {
          filter = f
        }
      _ => ()
    }
  }
  ({ items, filter, draft: "", editing: -1, edit_text: "" } : TodoMvc)
  as &DynComponent
}

///|
fn todomvc_def() -> ComponentDef {
  component_def(
    "TodoMvc",
    doc="The canonical todo list: add, tick, edit in place, delete, filter, and clear what is done.",
    keywords=["todo", "todomvc", "task", "list", "checklist", "filter"],
    category="input",
    message_docs=[
      { name: "add", doc: "Add the drafted task." },
      { name: "addOnEnter", doc: "Add the draft when the key was Enter." },
      {
        name: "typeDraft",
        doc: "Hold what is being typed into the new-task box.",
      },
      { name: "toggleAt", doc: "Tick or untick the task at an index." },
      { name: "removeAt", doc: "Delete the task at an index." },
      { name: "toggleAll", doc: "Tick everything, or untick it if it all is." },
      { name: "clearCompleted", doc: "Remove every ticked task." },
      { name: "startEdit", doc: "Open the task at an index for editing." },
      { name: "typeEdit", doc: "Hold what is being typed into the open row." },
      { name: "commitEdit", doc: "Keep the edit; an emptied row is deleted." },
      { name: "cancelEdit", doc: "Abandon the edit and keep what was there." },
      { name: "countLeft", doc: "How many tasks are not done, as a sentence." },
      {
        name: "matchesFilter",
        doc: "Whether the current filter lets a row through.",
      },
    ],
    views=[
      {
        name: "main",
        html: (
          #|<div class="card bg-base-100 border border-base-300 shadow-sm w-96 todomvc">
          #|  <div class="card-body gap-3 p-4">
          #|    <h2 class="card-title text-base">todos</h2>
          #|    <div class="join w-full">
          #|      <button class="btn btn-sm join-item toggle-all" title="toggle all" @on.click="toggleAll">v</button>
          #|      <input class="input input-bordered input-sm join-item grow new-todo" placeholder="What needs to be done?" :value="$draft" @on.input="typeDraft value" @on.keydown+send="addOnEnter isSend" />
          #|      <button class="btn btn-sm btn-primary join-item add" @on.click="add">Add</button>
          #|    </div>
          #|    <ul class="flex flex-col gap-1" @hide="empty? .items">
          #|      <li class="flex gap-2 items-center todo-row" @each=".items" @when="matchesFilter">
          #|        <input type="checkbox" class="checkbox checkbox-sm toggle" :checked="@value.done" @on.input="toggleAt @key" />
          #|        <span class="grow text-sm todo-text" @hide="@value.editing" @text="@value.text" @on.dblclick="startEdit @key"></span>
          #|        <input class="input input-bordered input-xs grow edit" @show="@value.editing" :value="$editText" @on.input="typeEdit value" @on.keydown+send="commitEdit" @on.keydown+cancel="cancelEdit" @on.blur="commitEdit" />
          #|        <button class="btn btn-ghost btn-xs btn-circle destroy" @on.click="removeAt @key">x</button>
          #|      </li>
          #|    </ul>
          #|    <p class="text-sm opacity-60 italic nothing" @show="empty? .items">Nothing to do.</p>
          #|    <div class="flex items-center gap-1 text-xs" @hide="empty? .items">
          #|      <span class="opacity-70 grow count-left" @text="$countLeft"></span>
          #|      <button class="btn btn-xs filter-all" @on.click="setFilter 'all'">all</button>
          #|      <button class="btn btn-xs filter-active" @on.click="setFilter 'active'">active</button>
          #|      <button class="btn btn-xs filter-done" @on.click="setFilter 'completed'">done</button>
          #|      <button class="btn btn-xs btn-ghost clear-done" @hide="empty? $done" @on.click="clearCompleted">clear</button>
          #|    </div>
          #|  </div>
          #|</div>
        ),
      },
    ],
    // `items` is a list of {text, done} records and `filter` is one of three
    // words. Declaring them is what gives the host `setFilter` (which this
    // guest does not implement), the item mutators, structural equality, the
    // JSON projection and hot-swap migration.
    types=[
      { kind: TY_TEXT, elem: None, items: [], name: "", members: [] },
      { kind: TY_RECORD, elem: None, items: [], name: "todo-item", members: [] },
      { kind: TY_LIST, elem: Some(1), items: [], name: "", members: [] },
    ],
    fields=[
      field("items", 2, doc="The tasks, in the order they were typed."),
      field(
        "filter",
        0,
        doc="Which tasks are shown: all, active, or completed.",
        constraint=Some({
          ..no_limits(),
          enum_json: "[\"all\", \"active\", \"completed\"]",
          default_json: "\"all\"",
        }),
      ),
    ],
    // `setFilter` is absent on purpose: the `filter` field implies it, and the
    // host answers it through `with_field`.
    handlers=[
      "add", "addOnEnter", "typeDraft", "toggleAt", "removeAt", "toggleAll", "clearCompleted",
      "startEdit", "typeEdit", "commitEdit", "cancelEdit",
    ],
    methods=["draft", "editText", "countLeft", "done"],
    whens=["matchesFilter"],
    inits=[
      {
        name: "example",
        args_json: "{\"items\": [{\"text\": \"taste MoonBit\", \"done\": true}, {\"text\": \"build a component\", \"done\": false}]}",
        doc: "The TodoMVC sample list, one item already done.",
      },
    ],
    // styling is entirely margaui (daisyUI) classes; no scoped fallback CSS
  )
}

///|
fn dyn_module() -> DynModule {
  module_def(
    "todomvclib",
    [dyn_comp(todomvc_def(), make_todomvc, restore=restore_todomvc)],
    // this bundle serves no requests of its own, and asks the host for nothing
    doc="TodoMVC, as a dynamic component: the whole canonical list in one bundle.",
    version="0.4.0",
  )
}
