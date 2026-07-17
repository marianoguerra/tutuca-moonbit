// Filter a list as you type, then show one page of the matches — three
// strategies that trade simplicity for how many times the list is scanned per
// render (naive two scans, shared one-and-a-partial, coupled one scan).

///|
/// Field off a Value::Obj; Null for non-objects and missing fields.
fn obj_get(v : @tutuca.Value, field : String) -> @tutuca.Value {
  match v {
    Obj(o) => o.obj_field(field).unwrap_or(Null)
    _ => Null
  }
}

///|
fn obj_str(v : @tutuca.Value, field : String) -> String {
  as_str(obj_get(v, field))
}

///|
fn as_str(v : @tutuca.Value) -> String {
  match v {
    Str(s) => s
    _ => ""
  }
}

///|
fn as_int(v : @tutuca.Value) -> Int {
  match v {
    Num(n) => n.to_int()
    _ => 0
  }
}

///|
/// Component-state variant: `inst.get(name)` coerced to Int.
fn int_field(inst : @component.Instance, name : String) -> Int {
  as_int(inst.get(name))
}

///|
/// The one match predicate, shared everywhere. `person` is a Person instance.
fn fp_matches(person : @tutuca.Value, query : String) -> Bool {
  let q = query.trim().to_lower().to_owned()
  if q == "" {
    return true
  }
  "\{obj_str(person, "name")} \{obj_str(person, "email")}"
  .to_lower()
  .contains(q)
}

///|
/// Clamp a possibly-stale page against the match count.
fn fp_clamp(page : Int, total : Int, page_size : Int) -> (Int, Int) {
  let page_count = @cmp.maximum(1, (total + page_size - 1) / page_size) // ceil
  let current = @cmp.minimum(@cmp.maximum(0, page), page_count - 1)
  (page_count, current)
}

///|
fn fp_pager_label(current : Int, page_count : Int, total : Int) -> String {
  let suffix = if total == 1 { "" } else { "es" }
  "Page \{current + 1} of \{page_count} · \{total} match\{suffix}"
}

///|
fn fp_items(inst : @component.Instance) -> Array[@tutuca.Value] {
  match inst.get("items") {
    List(a) => a
    _ => []
  }
}

///|
fn fp_query(inst : @component.Instance) -> String {
  match inst.get("query") {
    Str(s) => s
    _ => ""
  }
}

///|
fn fp_match_count(inst : @component.Instance) -> Int {
  let q = fp_query(inst)
  let mut n = 0
  for p in fp_items(inst) {
    if fp_matches(p, q) {
      n += 1
    }
  }
  n
}

///|
/// The `alter` entries every strategy shares — the count method (as a `methods`
/// entry so it can be reused inside handlers), the search/prev/next inputs, and
/// the `onlyMatches` @when predicate. Merged into each component's tables.
fn fp_base_methods() -> Map[String, @component.MethodFn] {
  { "matchCount": (inst, _args) => Num(fp_match_count(inst).to_double()) }
}

///|
fn fp_base_input() -> Map[String, @component.InstanceHandler] {
  {
    // reset to page 0 on every query change, so a shrinking result set never
    // strands you on an empty page
    "search": (inst, args, _ctx) => {
      match args {
        [Str(q), ..] => Some(inst.set("query", Str(q)).set("page", Num(0)))
        _ => None
      }
    },
    "prev": (inst, _args, _ctx) => {
      let (_, current) = fp_clamp(
        int_field(inst, "page"),
        fp_match_count(inst),
        int_field(inst, "pageSize"),
      )
      Some(inst.set("page", Num(@cmp.maximum(0, current - 1).to_double())))
    },
    "next": (inst, _args, _ctx) => {
      let (page_count, current) = fp_clamp(
        int_field(inst, "page"),
        fp_match_count(inst),
        int_field(inst, "pageSize"),
      )
      Some(
        inst.set(
          "page",
          Num(@cmp.minimum(page_count - 1, current + 1).to_double()),
        ),
      )
    },
  }
}

///|
fn fp_only_matches() -> Map[String, @component.MethodFn] {
  {
    // @when: args [key, value, iterData]
    "onlyMatches": (inst, args) => {
      match args {
        [_key, person, ..] => Bool(fp_matches(person, fp_query(inst)))
        _ => Bool(true)
      }
    },
  }
}

///|
fn fp_base_fields() -> Map[String, @component.FieldSpec] {
  {
    "items": @component.FieldSpec::of_default(List([])),
    "query": @component.FieldSpec::of_default(Str("")),
    "page": @component.FieldSpec::of_default(Num(0)),
    "pageSize": @component.FieldSpec::of_default(Num(5)),
  }
}

///|
/// The row markup, identical in every strategy (the whole point — only the
/// directives on the <li> and the scope @enrich-with differ).
const ROW =
  #|<span class="badge badge-neutral" @text="@key"></span>
  #|      <x render-it></x>
  #|      <button class="btn btn-sm btn-error btn-outline rm" @on.click="$removeInItemsAt @key">x</button>

///|
/// The loopCtx `filter` — reuse the declared @when for an item. Element 0 is the
/// this-slot; a 4th (iterData) element is required or the ctx returns true.
fn fp_ctx_filter(
  ctx : Map[String, @tutuca.Value],
  i : Int,
  v : @tutuca.Value,
) -> Bool {
  match ctx.get("filter") {
    Some(Fn(f)) => f([Null, Num(i.to_double()), v, Null]) is Bool(true)
    _ => true
  }
}

///|
/// The loopCtx `lookup` — read an @-binding a scope enrich published.
fn fp_ctx_lookup(
  ctx : Map[String, @tutuca.Value],
  name : String,
) -> @tutuca.Value {
  match ctx.get("lookup") {
    Some(Fn(f)) => f([Null, Str(name)])
    _ => Null
  }
}

///|
fn fp_num_keys(keys : Array[Int]) -> @tutuca.Value {
  Map({ "keys": List(keys.map(k => @tutuca.Value::Num(k.to_double()))) })
}

///|
fn person_comp() -> @component.Component {
  @component.component(
    name="Person",
    view=(
      #|<div class="person flex gap-2 items-center grow">
      #|  <input class="input input-sm grow name" :value=".name" @on.input="$setName value" placeholder="name" />
      #|  <input class="input input-sm grow email" :value=".email" @on.input="$setEmail value" placeholder="email" />
      #|  <label class="label cursor-pointer gap-1 chk-label">
      #|    <input type="checkbox" class="checkbox checkbox-sm active" :checked=".active" @on.input="$setActive value" />
      #|    active
      #|  </label>
      #|</div>
    ),
    fields={
      "name": @component.FieldSpec::of_default(Str("")),
      "email": @component.FieldSpec::of_default(Str("")),
      "active": @component.FieldSpec::of_default(Bool(false)),
    },
  )
}

///|
/// The pager markup + <ul>, parametrized by the <li> directives so the three
/// strategies share everything but their scanning handler.
fn people_view(li_attrs : String) -> String {
  "<section class=\"flex flex-col gap-3\" @enrich-with=\"pagerInfo\">" +
  "<input type=\"search\" class=\"input q\" :value=\".query\" @on.input=\"search value\" placeholder=\"Filter by name or email\" />" +
  "<ul class=\"flex flex-col gap-2\">" +
  "<li @each=\".items\" \{li_attrs} class=\"flex gap-2 items-center row\">\{ROW}</li>" +
  "</ul>" +
  "<div class=\"join\">" +
  "<button class=\"btn join-item prev\" @on.click=\"prev\" :disabled=\"@isFirst\">Prev</button>" +
  "<button class=\"btn join-item btn-disabled pglabel\" @text=\"@pageLabel\"></button>" +
  "<button class=\"btn join-item next\" @on.click=\"next\" :disabled=\"@isLast\">Next</button>" +
  "</div>" +
  "</section>"
}

///|
/// A scope @enrich-with shared by all three: count, clamp, publish the pager
/// bindings the controls read. SharedPeople also reads `currentPage` from it;
/// CoupledPeople stashes `__keys__` in it (added in that component's variant).
fn fp_pager_info(inst : @component.Instance) -> Map[String, @tutuca.Value] {
  let total = fp_match_count(inst)
  let (page_count, current) = fp_clamp(
    int_field(inst, "page"),
    total,
    int_field(inst, "pageSize"),
  )
  {
    "currentPage": Num(current.to_double()),
    "isFirst": Bool(current <= 0),
    "isLast": Bool(current >= page_count - 1),
    "pageLabel": Str(fp_pager_label(current, page_count, total)),
  }
}

///|
/// 1. NAIVE — the table scans the whole list to build+slice its page; the pager
/// scans again for the count. Two independent walks, nothing shared.
fn naive_people_comp() -> @component.Component {
  let alter = fp_only_matches()
  alter["pagerInfo"] = (inst, _args) => Map(fp_pager_info(inst))
  alter["tablePage"] = (inst, args) => {
    let seq = match args {
      [List(s), ..] => s
      _ => []
    }
    let ctx = match args {
      [_, Map(c), ..] => c
      _ => {}
    }
    let all : Array[Int] = []
    for i, v in seq {
      if fp_ctx_filter(ctx, i, v) {
        all.push(i)
      }
    }
    let (_, current) = fp_clamp(
      int_field(inst, "page"),
      all.length(),
      int_field(inst, "pageSize"),
    )
    let start = current * int_field(inst, "pageSize")
    fp_num_keys(page_slice(all, start, int_field(inst, "pageSize")))
  }
  @component.component(
    name="NaivePeople",
    view=people_view("@when=\"onlyMatches\" @loop-with=\"tablePage\""),
    fields=fp_base_fields(),
    methods=fp_base_methods(),
    input=fp_base_input(),
    alter~,
  )
}

///|
/// 2. SHARED — the scope enrich does the one count scan and publishes the
/// clamped page; the loop-with reads it (`lookup`) and reuses the @when
/// (`filter`) to collect just this page's keys, early-exiting once it is full.
fn shared_people_comp() -> @component.Component {
  let alter = fp_only_matches()
  alter["pagerInfo"] = (inst, _args) => Map(fp_pager_info(inst))
  alter["page"] = (inst, args) => {
    let seq = match args {
      [List(s), ..] => s
      _ => []
    }
    let ctx = match args {
      [_, Map(c), ..] => c
      _ => {}
    }
    let current = match fp_ctx_lookup(ctx, "currentPage") {
      Num(n) => n.to_int()
      _ => 0
    }
    let page_size = int_field(inst, "pageSize")
    let start = current * page_size
    let end = start + page_size
    let keys : Array[Int] = []
    let mut m = 0
    for i, v in seq {
      if m >= end {
        break
      }
      if fp_ctx_filter(ctx, i, v) {
        if m >= start {
          keys.push(i)
        }
        m += 1
      }
    }
    fp_num_keys(keys)
  }
  @component.component(
    name="SharedPeople",
    view=people_view("@when=\"onlyMatches\" @loop-with=\"page\""),
    fields=fp_base_fields(),
    methods=fp_base_methods(),
    input=fp_base_input(),
    alter~,
  )
}

///|
/// 3. COUPLED — one scan total. The enrich builds the page keys into `__keys__`
/// (and the pager labels); the loop-with does nothing but hand them back.
fn coupled_people_comp() -> @component.Component {
  let alter : Map[String, @component.MethodFn] = Map([])
  alter["pagerInfo"] = (inst, _args) => {
    let q = fp_query(inst)
    let all : Array[Int] = []
    for i, p in fp_items(inst) {
      if fp_matches(p, q) {
        all.push(i)
      }
    }
    let (page_count, current) = fp_clamp(
      int_field(inst, "page"),
      all.length(),
      int_field(inst, "pageSize"),
    )
    let start = current * int_field(inst, "pageSize")
    let page_keys = page_slice(all, start, int_field(inst, "pageSize"))
    Map({
      // consumed ONLY by the loop-with below
      "__keys__": List(page_keys.map(k => @tutuca.Value::Num(k.to_double()))),
      "isFirst": Bool(current <= 0),
      "isLast": Bool(current >= page_count - 1),
      "pageLabel": Str(fp_pager_label(current, page_count, all.length())),
    })
  }
  alter["forwardKeys"] = (_inst, args) => {
    let ctx = match args {
      [_, Map(c), ..] => c
      _ => {}
    }
    Map({ "keys": fp_ctx_lookup(ctx, "__keys__") })
  }
  @component.component(
    name="CoupledPeople",
    // no @when here: the loop-with's keys are authoritative
    view=people_view("@loop-with=\"forwardKeys\""),
    fields=fp_base_fields(),
    methods=fp_base_methods(),
    input=fp_base_input(),
    alter~,
  )
}

///|
/// keys[start .. start+n], clamped.
fn page_slice(keys : Array[Int], start : Int, n : Int) -> Array[Int] {
  let out : Array[Int] = []
  let end = @cmp.minimum(start + n, keys.length())
  for i in start..<end {
    if i >= 0 {
      out.push(keys[i])
    }
  }
  out
}

///|
fn strategies_comp() -> @component.Component {
  @component.component(
    name="Strategies",
    view=(
      #|<div class="flex flex-col gap-6">
      #|  <div class="flex flex-col gap-1"><h3 class="font-bold">1. Naive — two independent scans</h3><x render=".naive"></x></div>
      #|  <div class="flex flex-col gap-1"><h3 class="font-bold">2. Shared — one count + one partial collect</h3><x render=".shared"></x></div>
      #|  <div class="flex flex-col gap-1"><h3 class="font-bold">3. Coupled — one scan; loop-with forwards the enrich's keys</h3><x render=".coupled"></x></div>
      #|</div>
    ),
    fields={
      "naive": @component.FieldSpec::comp("NaivePeople"),
      "shared": @component.FieldSpec::comp("SharedPeople"),
      "coupled": @component.FieldSpec::comp("CoupledPeople"),
    },
  )
}

///|
fn fp_people(person : @component.Component) -> Array[@tutuca.Value] {
  let people = [
    ("Ada Lovelace", "ada@analytical.engine"),
    ("Alan Turing", "alan@bletchley.uk"),
    ("Grace Hopper", "grace@navy.mil"),
    ("Edsger Dijkstra", "edsger@shortest.path"),
    ("Barbara Liskov", "barbara@substitution.org"),
    ("Donald Knuth", "don@tex.org"),
    ("Margaret Hamilton", "margaret@apollo.nasa"),
    ("John von Neumann", "john@architecture.edu"),
    ("Katherine Johnson", "katherine@orbit.nasa"),
    ("Tim Berners-Lee", "tim@web.org"),
    ("Linus Torvalds", "linus@kernel.org"),
    ("Radia Perlman", "radia@spanning.tree"),
    ("Ken Thompson", "ken@bell.labs"),
    ("Dennis Ritchie", "dennis@bell.labs"),
  ]
  people.map(p => {
    person.make({ "name": Str(p.0), "email": Str(p.1) }).to_value()
  })
}

///|
pub fn filter_paginate_module() -> @component.ModuleDef {
  let person = person_comp()
  let naive = naive_people_comp()
  let shared = shared_people_comp()
  let coupled = coupled_people_comp()
  let mk = (c : @component.Component) => {
    c.make({ "items": List(fp_people(person)) }).to_value()
  }
  @component.ModuleDef::new(
    name="filter-paginate",
    components=[strategies_comp(), naive, shared, coupled, person],
    examples=[
      {
        component: "Strategies",
        title: "Default",
        args: {
          "naive": mk(naive),
          "shared": mk(shared),
          "coupled": mk(coupled),
        },
        view: None,
      },
      {
        component: "SharedPeople",
        title: "Shared alone",
        args: { "items": List(fp_people(person)) },
        view: None,
      },
    ],
  )
}

fn build() -> @component.ModuleDef {
  filter_paginate_module()
}

fn main {
  @host.mount(build(), "app")
}
