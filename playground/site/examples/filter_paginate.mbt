// Port of docs/examples/filter-paginate.js — THE richest example: three takes
// on the same feature (filter a list, show one page of the matches), trading
// simplicity for how many times the list is scanned per render. All three
// return `keys` (original indices) from @loop-with, so @key keeps each row's
// identity; they differ only in WHO does the scanning:
//
//   1. NaivePeople   — two independent full scans (table + pager).
//   2. SharedPeople  — one count scan + one partial (early-exit) collect scan,
//                      the loop-with reading the enrich's clamped page via `lookup`
//                      and reusing the @when via `filter`.
//   3. CoupledPeople — one scan total: the enrich builds the page keys and
//                      stashes them under `__keys__`; the loop-with just forwards
//                      them. Fast, but the two handlers are welded together.
//
// This exercises the whole @loop-with contract: `keys` (authoritative, skips
// @when), the loopCtx `lookup` (read an @-binding published by a scope enrich)
// and `filter` (reuse the declared @when), and scope @enrich-with feeding it.

///|
/// The one match predicate, shared everywhere. `person` is a Person instance.
fn fp_matches(person : @tutuca.Value, query : String) -> Bool {
  let q = query.trim().to_lower().to_owned()
  if q == "" {
    return true
  }
  "\{person.field("name").str()} \{person.field("email").str()}"
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
/// The state every strategy shares — same fields, same defaults.
struct PeopleState {
  items : Array[@tutuca.Value]
  query : String
  page : Int
  pageSize : Int
} derive(ToJson, FromJson)

///|
fn fp_match_count(s : PeopleState) -> Int {
  let mut n = 0
  for p in s.items {
    if fp_matches(p, s.query) {
      n += 1
    }
  }
  n
}

///|
/// The buckets every strategy shares — the count as a `compute` entry (so
/// views could read it), the search/prev/next Input arms as one shared
/// `update` fn, and the `onlyMatches` @when predicate.
fn fp_base_compute() -> Map[
  String,
  (PeopleState, Array[@tutuca.Value]) -> @tutuca.Value,
] {
  { "matchCount": (s, _args) => Num(fp_match_count(s).to_double()) }
}

///|
fn fp_update() -> (
  PeopleState,
  @component.Dispatch,
  &@tutuca.Ctx,
) -> PeopleState? {
  (s, msg, _ctx) => match msg {
    // reset to page 0 on every query change, so a shrinking result set never
    // strands you on an empty page
    Input("search", [Str(q), ..]) => Some({ ..s, query: q, page: 0 })
    Input("prev", _) => {
      let (_, current) = fp_clamp(s.page, fp_match_count(s), s.pageSize)
      Some({ ..s, page: @cmp.maximum(0, current - 1) })
    }
    Input("next", _) => {
      let (page_count, current) = fp_clamp(
        s.page,
        fp_match_count(s),
        s.pageSize,
      )
      Some({ ..s, page: @cmp.minimum(page_count - 1, current + 1) })
    }
    _ => None
  }
}

///|
fn fp_only_matches() -> Map[
  String,
  (PeopleState, @tutuca.Value, @tutuca.Value, @tutuca.Value) -> Bool,
] {
  {
    "onlyMatches": (s, _key, person, _iter) => fp_matches(person, s.query),
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
fn fp_num_keys(keys : Array[Int]) -> @component.LoopWith {
  @component.LoopWith::new(
    keys=keys.map(k => (Num(k.to_double()) : @tutuca.Value)),
  )
}

///|
struct PersonState {
  name : String
  email : String
  active : Bool
} derive(ToJson, FromJson)

///|
fn person_comp() -> @component.Component {
  @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view=(
      #|<div class="person flex gap-2 items-center grow">
      #|  <input class="input input-sm grow name" :value=".name" @on.input="$setName value" placeholder="name" />
      #|  <input class="input input-sm grow email" :value=".email" @on.input="$setEmail value" placeholder="email" />
      #|  <label class="label cursor-pointer gap-1 chk-label">
      #|    <input type="checkbox" class="checkbox checkbox-sm active" :checked=".active" @on.input="$setActive value" />
      #|    active
      #|  </label>
      #|</div>
    )),
  },
  name="Person",
  init=PersonState::{ name: "", email: "", active: false },
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
/// A scope enrich (`enrich_scope`) shared by all three: count, clamp, publish
/// the pager bindings the controls read. SharedPeople also reads `currentPage`
/// from it; CoupledPeople stashes `__keys__` in it (added in that component's
/// variant).
fn fp_pager_info(s : PeopleState) -> Map[String, @tutuca.Value] {
  let total = fp_match_count(s)
  let (page_count, current) = fp_clamp(s.page, total, s.pageSize)
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
  @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view=people_view("@when=\"onlyMatches\" @loop-with=\"tablePage\"")),
  },
  name="NaivePeople",
  init=PeopleState::{ items: [], query: "", page: 0, pageSize: 5 },
  compute=fp_base_compute(),
  update=fp_update(),
  when=fp_only_matches(),
  enrich_scope={ "pagerInfo": s => fp_pager_info(s) },
  loop_with={
      "tablePage": (s : PeopleState, seq, ctx) => {
        let all : Array[Int] = []
        for i, v in seq.list() {
          if (ctx.filter)(Num(i.to_double()), v, Null) {
            all.push(i)
          }
        }
        let (_, current) = fp_clamp(s.page, all.length(), s.pageSize)
        let start = current * s.pageSize
        fp_num_keys(page_slice(all, start, s.pageSize))
      },
    },
)
}

///|
/// 2. SHARED — the scope enrich does the one count scan and publishes the
/// clamped page; the loop-with reads it (`lookup`) and reuses the @when
/// (`filter`) to collect just this page's keys, early-exiting once it is full.
fn shared_people_comp() -> @component.Component {
  @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view=people_view("@when=\"onlyMatches\" @loop-with=\"page\"")),
  },
  name="SharedPeople",
  init=PeopleState::{ items: [], query: "", page: 0, pageSize: 5 },
  compute=fp_base_compute(),
  update=fp_update(),
  when=fp_only_matches(),
  enrich_scope={ "pagerInfo": s => fp_pager_info(s) },
  loop_with={
      "page": (s : PeopleState, seq, ctx) => {
        let current = match (ctx.lookup)("currentPage") {
          Num(n) => n.to_int()
          _ => 0
        }
        let start = current * s.pageSize
        let end = start + s.pageSize
        let keys : Array[Int] = []
        let mut m = 0
        for i, v in seq.list() {
          if m >= end {
            break
          }
          if (ctx.filter)(Num(i.to_double()), v, Null) {
            if m >= start {
              keys.push(i)
            }
            m += 1
          }
        }
        fp_num_keys(keys)
      },
    },
)
}

///|
/// 3. COUPLED — one scan total. The enrich builds the page keys into `__keys__`
/// (and the pager labels); the loop-with does nothing but hand them back.
fn coupled_people_comp() -> @component.Component {
  @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view=people_view("@loop-with=\"forwardKeys\"")),
  },
  name="CoupledPeople",
  init=PeopleState::{ items: [], query: "", page: 0, pageSize: 5 },
  compute=fp_base_compute(),
  update=fp_update(),
  enrich_scope={
      "pagerInfo": (s : PeopleState) => {
        let all : Array[Int] = []
        for i, p in s.items {
          if fp_matches(p, s.query) {
            all.push(i)
          }
        }
        let (page_count, current) = fp_clamp(s.page, all.length(), s.pageSize)
        let start = current * s.pageSize
        let page_keys = page_slice(all, start, s.pageSize)
        {
          // consumed ONLY by the loop-with below
          "__keys__": List(
            page_keys.map(k => (Num(k.to_double()) : @tutuca.Value)),
          ),
          "isFirst": Bool(current <= 0),
          "isLast": Bool(current >= page_count - 1),
          "pageLabel": Str(fp_pager_label(current, page_count, all.length())),
        }
      },
    },
  loop_with={
      "forwardKeys": (_s : PeopleState, _seq, ctx) => match
        (ctx.lookup)("__keys__") {
        List(keys) => @component.LoopWith::new(keys~)
        _ => @component.LoopWith::new(keys=[])
      },
    },
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
struct StrategiesState {} derive(ToJson, FromJson)

///|
fn strategies_comp() -> @component.Component {
  @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view=(
      #|<div class="flex flex-col gap-6">
      #|  <div class="flex flex-col gap-1"><h3 class="font-bold">1. Naive — two independent scans</h3><x render=".naive"></x></div>
      #|  <div class="flex flex-col gap-1"><h3 class="font-bold">2. Shared — one count + one partial collect</h3><x render=".shared"></x></div>
      #|  <div class="flex flex-col gap-1"><h3 class="font-bold">3. Coupled — one scan; loop-with forwards the enrich's keys</h3><x render=".coupled"></x></div>
      #|</div>
    )),
  },
  name="Strategies",
  init=StrategiesState::{  },
  specs={
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
  people.map(p => person.make({ "name": Str(p.0), "email": Str(p.1) }))
}

///|
pub fn filter_paginate_module() -> @component.ModuleDef {
  let person = person_comp()
  let naive = naive_people_comp()
  let shared = shared_people_comp()
  let coupled = coupled_people_comp()
  let mk = (c : @component.Component) => c.make({
    "items": List(fp_people(person)),
  })
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

///|
fn build() -> @component.ModuleDef {
  filter_paginate_module()
}
