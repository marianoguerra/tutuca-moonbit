fn build() -> @component.ModuleDef {
  task_list_module()
}

///|
pub fn task_list_module() -> @component.ModuleDef {
  let item = task_item_component()
  let list = task_list_component(
    initial=TaskListState::fresh(),
    update=(s, dispatch, _ctx) => {
      match dispatch {
        Receive("add", _) => {
          let text = s.draft.trim().to_owned()
          if text == "" {
            return Unchanged
          }
          let next_id = s.next_id + 1
          let id = "task-\{next_id}"
          let items = s.items.copy()
          items[id] = item.make({ "id": Str(id), "text": Str(text) })
          Next({ ..s, next_id, items, draft: "", })
        }
        _ => Unhandled
      }
    },
    when=_ => {
      Some((s, key, _value, _iter, _stack) => {
        let done = s.completed.get(key.str()).unwrap_or(false)
        s.filter == "all" ||
        (s.filter == "completed" && done) ||
        (s.filter == "active" && !done)
      })
    },
  )
  @component.ModuleDef::new(name="task-list", components=[list, item], examples=[
    { component: "TaskList", title: "Task list", args: Map([]), view: None, },
  ])
}
