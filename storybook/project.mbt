// Stories, projected from a module rather than written beside it.
//
// A `ModuleDef` already declares its own examples — the same values
// `@harness.mount_example` mounts in a test — and each one names a component
// and the args to make it with. That is a story, minus the editorial part. So
// the gallery derives its story set from the module, and a consumer's whole
// integration is `stories_of_modules([...])`; sections, human descriptions and
// per-story `init` are `.map` overrides on top.
//
// Deriving is also the SAFE door. An `ExampleDef`'s args are built inside the
// module that registers the components they name, and an arg holding a child
// component instance only renders if it was made from the very Component the
// story's module registers. A hand-written Story list can get that wrong; a
// projected one cannot.

///|
/// A story with defaults for everything the gallery can infer. `Story` is
/// `pub(all)`, so this is convenience rather than the only door — but it keeps
/// a caller from having to spell ten fields to say three.
pub fn Story::new(
  id~ : String,
  title~ : String,
  module_~ : @component.ModuleDef,
  root~ : String,
  section? : String = "",
  description? : String = "",
  args? : Map[String, @tutuca.Value] = Map([]),
  view? : String = "",
  renderable? : Bool = true,
  init? : Bool = false,
) -> Story {
  {
    id,
    title,
    section,
    description,
    module_,
    root,
    args,
    view,
    renderable,
    init,
  }
}

///|
/// Lowercase, every run of non-alphanumerics collapsed to one `-`, trimmed.
/// Story ids are DOM ids, click-handler literals and URL query values, so they
/// are slugs whether or not the titles they came from were.
pub fn slug(s : String) -> String {
  let out = StringBuilder()
  let mut pending = false
  let mut any = false
  for c in s {
    if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
      if pending && any {
        out.write_char('-')
      }
      pending = false
      any = true
      out.write_char(c)
    } else if c >= 'A' && c <= 'Z' {
      if pending && any {
        out.write_char('-')
      }
      pending = false
      any = true
      out.write_char((c.to_int() + 32).unsafe_to_char())
    } else {
      pending = true
    }
  }
  out.to_string()
}

///|
/// The id `stories_of_module` gives an example: the module, the component and
/// the example title, slugged. A module with one untitled example per component
/// gets `"<module>-<component>"`.
pub fn story_id(module_name : String, ex : @component.ExampleDef) -> String {
  slug("\{module_name} \{ex.component} \{ex.title}")
}

///|
/// The title `stories_of_module` gives an example: the component's name alone
/// when the example is untitled, else `"Component · Title"`. One rule
/// everywhere, so a reader can tell where a sidebar label came from.
pub fn story_title(ex : @component.ExampleDef) -> String {
  if ex.title == "" {
    ex.component
  } else {
    "\{ex.component} · \{ex.title}"
  }
}

///|
/// One story for one declared example. `root` is the example's component,
/// `args` are its args and `view` its view — the three things a gallery cannot
/// infer and an ExampleDef already knows.
///
/// `init` and `renderable` have no ExampleDef field and so take the safe
/// defaults (don't dispatch, do render); override them with a record update:
/// `stories_of_module(m).map(s => if s.id == "…" { { ..s, init: true } } else { s })`.
pub fn Story::of_example(
  module_ : @component.ModuleDef,
  ex : @component.ExampleDef,
  section? : String = "",
  id? : String = "",
  title? : String = "",
  description? : String = "",
  renderable? : Bool = true,
  init? : Bool = false,
) -> Story {
  {
    id: if id == "" {
      story_id(module_.name, ex)
    } else {
      id
    },
    title: if title == "" {
      story_title(ex)
    } else {
      title
    },
    section,
    description,
    module_,
    root: ex.component,
    args: ex.args,
    view: ex.view.unwrap_or(""),
    renderable,
    init,
  }
}

///|
/// Every example a module declares, in declaration order, with ids made unique
/// within the module. A module that declares no examples projects to no
/// stories — the gallery has nothing to show a component it cannot make.
pub fn stories_of_module(
  m : @component.ModuleDef,
  section? : String = "",
) -> Array[Story] {
  unique_ids(m.examples.map(ex => Story::of_example(m, ex, section~)))
}

///|
/// Several modules at once, with ids made unique across the whole set.
/// `section_of` names each module's sidebar group; without it every story
/// lands in one unnamed group, which `sections_of` still renders.
pub fn stories_of_modules(
  ms : Array[@component.ModuleDef],
  section_of? : (@component.ModuleDef) -> String,
) -> Array[Story] {
  let section_fn = match section_of {
    Some(f) => f
    None => (_m : @component.ModuleDef) => ""
  }
  let out : Array[Story] = []
  for m in ms {
    let section = section_fn(m)
    for ex in m.examples {
      out.push(Story::of_example(m, ex, section~))
    }
  }
  unique_ids(out)
}

///|
/// Suffix duplicate ids (`-2`, `-3`, …), keeping the first occurrence as it is.
/// Two examples of one component with the same title would otherwise collide
/// into one DOM id, one nav entry and one URL — a story you cannot reach.
pub fn unique_ids(stories : Array[Story]) -> Array[Story] {
  let seen : Map[String, Int] = Map([])
  stories.map(s => {
    match seen.get(s.id) {
      None => {
        seen[s.id] = 1
        s
      }
      Some(n) => {
        let next = n + 1
        seen[s.id] = next
        { ..s, id: "\{s.id}-\{next}", }
      }
    }
  })
}
