// Personal site: a filterable list of entries with category/role facets,
// sorting, and a solo/unsolo (alt-click) interaction; fixture data loads via a
// request handler dispatched on `init` after mount.

// --- shared field helpers (inlined from examples/fields.mbt) ---

fn obj_get(v : @tutuca.Value, field : String) -> @tutuca.Value {
  v.field(field)
}

fn obj_str(v : @tutuca.Value, field : String) -> String {
  v.field(field).str()
}

fn obj_int(v : @tutuca.Value, field : String) -> Int {
  v.field(field).int()
}

fn obj_bool(v : @tutuca.Value, field : String) -> Bool {
  v.field(field).bool()
}

// --- personal_site (adapted from examples/personal_site.mbt) ---

///|
/// A Map-backed set: membership is key-presence.
fn ps_set_of(members : Array[String]) -> Map[String, Bool] {
  let m : Map[String, Bool] = Map([])
  for s in members {
    m[s] = true
  }
  m
}

///|
/// Toggle a member in a Map-backed set.
fn ps_set_toggle(set : Map[String, Bool], entry : String) -> Map[String, Bool] {
  let out : Map[String, Bool] = Map([])
  for k, v in set {
    out[k] = v
  }
  if out.contains(entry) {
    out.remove(entry)
  } else {
    out[entry] = true
  }
  out
}

///|
/// Sort entries: featured first (optional), then by year (asc/desc).
fn ps_sort(
  entries : Array[@tutuca.Value],
  by_end : Bool,
  asc : Bool,
  feat : Bool,
) -> Array[@tutuca.Value] {
  let out = entries.copy()
  let year = (e : @tutuca.Value) => {
    let start = obj_int(e, "startYear")
    if by_end {
      let end = obj_int(e, "endYear")
      if end != 0 {
        end
      } else {
        start
      }
    } else {
      start
    }
  }
  out.sort_by((a, b) => {
    if feat {
      let fa = obj_bool(a, "featured")
      let fb = obj_bool(b, "featured")
      if fa && !fb {
        return -1
      }
      if !fa && fb {
        return 1
      }
    }
    let ay = year(a)
    let by = year(b)
    if asc {
      ay - by
    } else {
      by - ay
    }
  })
  out
}

///|
fn ps_resort(s : PsRootState) -> PsRootState {
  {
    ..s,
    allEntries: ps_sort(s.allEntries, s.sortByEnd, s.sortAsc, s.featuredFirst),
  }
}

///|
/// The JS CATEGORY_COLORS table — per-category ring/text classes for an
/// UNSELECTED facet button or badge.
fn ps_category_colors() -> Map[String, String] {
  {
    "Programming Languages": "ring-1 ring-violet-500 text-violet-700 dark:text-violet-300",
    "Distributed Systems": "ring-1 ring-indigo-500 text-indigo-700 dark:text-indigo-300",
    "End User Programming": "ring-1 ring-orange-500 text-orange-700 dark:text-orange-300",
    "Erlang / Elixir": "ring-1 ring-purple-500 text-purple-700 dark:text-purple-300",
    "WebAssembly": "ring-1 ring-fuchsia-500 text-fuchsia-700 dark:text-fuchsia-300",
    "Web": "ring-1 ring-cyan-500 text-cyan-700 dark:text-cyan-300",
    "Future of Coding": "ring-1 ring-rose-500 text-rose-700 dark:text-rose-300",
    "Startup": "ring-1 ring-amber-500 text-amber-700 dark:text-amber-300",
    "AI": "ring-1 ring-emerald-500 text-emerald-700 dark:text-emerald-300",
    "Python": "ring-1 ring-sky-500 text-sky-700 dark:text-sky-300",
    "Education": "ring-1 ring-teal-500 text-teal-700 dark:text-teal-300",
    "Rust": "ring-1 ring-red-500 text-red-700 dark:text-red-300",
  }
}

///|
/// The JS CATEGORY_COLORS_SELECTED table — solid background for a SELECTED
/// facet button (and for entry category badges, which always use it).
fn ps_category_colors_selected() -> Map[String, String] {
  {
    "Programming Languages": "bg-violet-700 text-white",
    "Distributed Systems": "bg-indigo-700 text-white",
    "End User Programming": "bg-orange-700 text-white",
    "Erlang / Elixir": "bg-purple-700 text-white",
    "WebAssembly": "bg-fuchsia-700 text-white",
    "Web": "bg-cyan-700 text-white",
    "Future of Coding": "bg-rose-700 text-white",
    "Startup": "bg-amber-700 text-white",
    "AI": "bg-emerald-700 text-white",
    "Python": "bg-sky-700 text-white",
    "Education": "bg-teal-700 text-white",
    "Rust": "bg-red-700 text-white",
  }
}

///|
/// JS `getCategoryColor(cat, isSelected)`.
fn ps_category_color(cat : String, selected : Bool) -> String {
  if selected {
    match ps_category_colors_selected().get(cat) {
      Some(c) => c
      None => "bg-primary text-primary-content"
    }
  } else {
    match ps_category_colors().get(cat) {
      Some(c) => c
      None => "bg-base-300 text-base-content"
    }
  }
}

///|
/// All per-category color classes joined into one literal, interpolated into
/// the `_margauiClasses` decoy view below — same trick as personal-site.js's
/// CATEGORY_DECOY_CLASSES, so the color tables stay the single source of truth.
fn ps_category_decoy_classes() -> String {
  let parts : Array[String] = []
  for _, v in ps_category_colors() {
    parts.push(v)
  }
  for _, v in ps_category_colors_selected() {
    parts.push(v)
  }
  parts.join(" ")
}

///|
struct AltUrlState {
  label : String
  url : String
} derive(ToJson, FromJson)

///|
fn alt_url_comp() -> @component.Component {
  @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view=(
      #|<a class="badge badge-ghost badge-sm cursor-pointer gap-1 no-underline hover:bg-base-200 alt-url" :href=".url" target="_blank">🔗 <span @text=".label"></span></a>
    )),
  },
  name="AltUrl",
  init=AltUrlState::{ label: "", url: "#" },
)
}

///|
struct PsEntryState {
  title : String
  description : String
  lang : String
  startYear : @tutuca.Value
  endYear : @tutuca.Value
  role : @tutuca.Value
  featured : Bool
  url : String
  altUrls : Array[@tutuca.Value]
  categories : Array[@tutuca.Value]
} derive(ToJson, FromJson)

///|
fn ps_entry_comp() -> @component.Component {
  @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view=(
      #|<div class="card bg-base-200 shadow-sm p-2 sm:p-3 flex flex-col gap-2 ps-entry">
      #|  <div class="flex gap-1 sm:gap-2 flex-wrap items-center">
      #|    <span class="star" @show=".featured">⭐</span>
      #|    <span class="flag" @show="$isSpanish" @text="$langFlag"></span>
      #|    <span class="badge badge-ghost badge-sm border-0 font-bold years" @show="truthy? .startYear" @text="$yearDisplay"></span>
      #|    <span class="badge badge-neutral badge-sm border-0 font-bold role" @show=".role" @text=".role"></span>
      #|  </div>
      #|  <a :href=".url" target="_blank" class="link link-hover"><h2 class="font-bold title" @text=".title"></h2></a>
      #|  <p class="text-sm opacity-70 desc" @text=".description"></p>
      #|  <div class="flex gap-1 sm:gap-2 flex-wrap cats">
      #|    <span @each=".categories" @enrich-with="enrichCategoryBadge" :class="@badgeClass" @text="@value"></span>
      #|  </div>
      #|  <div class="alts" @hide="empty? .altUrls">
      #|    <ul><li @each=".altUrls"><x render-it></x></li></ul>
      #|  </div>
      #|</div>
    )),
  },
  name="PSEntry",
  enrich={
      // JS `enrichCategoryBadge`: entry category badges always use the
      // SELECTED color variant. The `cat` token is the MB test hook.
      "enrichCategoryBadge": (_s : PsEntryState, binds, _key, value, _iter) => match
        value {
        Str(cat) =>
          binds["badgeClass"] = Str(
            "badge badge-sm \{ps_category_color(cat, true)} cat",
          )
        _ => ()
      },
    },
  init=PsEntryState::{
      title: "?",
      description: "",
      lang: "en",
      startYear: Null,
      endYear: Null,
      role: Null,
      featured: false,
      url: "#",
      altUrls: [],
      categories: [],
    },
  compute={
      "langFlag": (s : PsEntryState, _args) => if s.lang == "es" {
        Str("🇪🇸")
      } else {
        Str("🇬🇧")
      },
      "isSpanish": (s : PsEntryState, _args) => Bool(s.lang == "es"),
      "yearDisplay": (s : PsEntryState, _args) => match s.startYear {
        Num(start) =>
          match s.endYear {
            Num(e) => Str("\{start.to_int()}-\{e.to_int()}")
            _ => Str("\{start.to_int()}")
          }
        _ => Str("")
      },
    },
)
}

///|
/// The JS `Entry.Class.fromData` static, as a plain function.
fn entry_from_data(
  entry : @component.Component,
  alt_url : @component.Component,
  title : String,
  description : String,
  start_year : Int,
  end_year : Int,
  role : String,
  featured : Bool,
  categories : Array[String],
  alt_urls : Array[(String, String)],
) -> @tutuca.Value {
  let cats = categories.copy()
  cats.sort_by((a, b) => a.lexical_compare(b))
  entry.make({
    "title": Str(title),
    "description": Str(description),
    "startYear": Num(start_year.to_double()),
    "endYear": Num(end_year.to_double()),
    "role": if role == "" {
      Null
    } else {
      Str(role)
    },
    "featured": Bool(featured),
    "categories": List(cats.map(c => Str(c))),
    "altUrls": List(
      alt_urls.map(a => alt_url.make({ "label": Str(a.0), "url": Str(a.1) })),
    ),
  })
}

///|
struct PsRootState {
  allEntries : Array[@tutuca.Value]
  allCategories : Array[String]
  allRoles : Array[String]
  selectedCategories : Map[String, Bool]
  selectedRoles : Map[String, Bool]
  featuredFirst : Bool
  sortByEnd : Bool
  sortAsc : Bool
} derive(ToJson, FromJson)

///|
fn root_comp() -> @component.Component {
  @component.component(
  compiled_views={
    "main": @anode.View::new("main", raw_view=(
      #|<section class="ps-root flex flex-col gap-4">
      #|  <div class="card bg-base-200 p-4 controls">
      #|    <p class="text-sm mb-4">💡 Click tags to toggle. Solo / unsolo toggle with <kbd class="text-mono">alt/option + click</kbd>.</p>
      #|    <div class="grid grid-cols-1 sm:grid-cols-[auto_1fr] gap-y-1 sm:gap-x-3 sm:gap-y-3 items-start">
      #|      <span class="font-semibold text-sm pt-1">Categories</span>
      #|      <div class="cat-facets flex flex-wrap gap-2">
      #|        <button @each=".allCategories" @enrich-with="enrichCategoryBindings"
      #|          :class="@btnClass" @on.click="onCategoryToggle @key isAlt" @text="@value"></button>
      #|      </div>
      #|      <span class="font-semibold text-sm pt-1">Roles</span>
      #|      <div class="role-facets flex flex-wrap gap-2">
      #|        <button @each=".allRoles" @enrich-with="enrichRoleBindings"
      #|          :class="@btnClass" @on.click="onRoleToggle @key isAlt" @text="@value"></button>
      #|      </div>
      #|      <span class="font-semibold text-sm pt-1">Sort By</span>
      #|      <div class="flex flex-wrap items-center gap-2">
      #|        <label class="swap btn btn-xs btn-outline btn-primary">
      #|          <input type="checkbox" class="sort-end" :checked=".sortByEnd" @on.change="onToggleSortByEnd" />
      #|          <span class="swap-on">End Year</span>
      #|          <span class="swap-off">Start Year</span>
      #|        </label>
      #|        <label class="swap btn btn-xs btn-outline btn-primary">
      #|          <input type="checkbox" class="sort-asc" :checked=".sortAsc" @on.change="onToggleSortAsc" />
      #|          <span class="swap-on">↑ Oldest first</span>
      #|          <span class="swap-off">↓ Newest first</span>
      #|        </label>
      #|        <label class="flex items-center gap-2 cursor-pointer">
      #|          <input type="checkbox" class="toggle toggle-sm feat-first" :checked=".featuredFirst" @on.change="onToggleFeaturedFirst" />
      #|          <span class="text-sm">Featured first</span>
      #|        </label>
      #|      </div>
      #|    </div>
      #|    <div class="flex flex-wrap items-center gap-4 mt-4">
      #|      <button class="btn btn-outline btn-sm clear-filters" @on.click="$clearFilters" @show="$hasActiveFilters">Clear Filters</button>
      #|    </div>
      #|  </div>
      #|  <div class="entries flex flex-col gap-3">
      #|    <div class="entry-row" @each=".allEntries" @when="filterEntry"><x render-it></x></div>
      #|  </div>
      #|</section>
    )),
    "_margauiClasses": @anode.View::new("_margauiClasses", raw_view="<p class=\"btn btn-xs btn-neutral btn-ghost border-0 badge badge-sm font-bold opacity-40 ring-1 ring-neutral-content/30 \{ps_category_decoy_classes()}\"></p>"),
  },
  name="Root",
  init=PsRootState::{
      allEntries: [],
      allCategories: [],
      allRoles: [],
      selectedCategories: Map([]),
      selectedRoles: Map([]),
      featuredFirst: true,
      sortByEnd: false,
      sortAsc: false,
    },
  mutate={
      "clearFilters": (s : PsRootState, _args) => {
        ..s,
        selectedCategories: ps_set_of(s.allCategories),
        selectedRoles: ps_set_of(s.allRoles),
      },
    },
  compute={
      "hasActiveFilters": (s : PsRootState, _args) => Bool(
        s.selectedCategories.length() != s.allCategories.length() ||
        s.selectedRoles.length() != s.allRoles.length(),
      ),
    },
  when={ "filterEntry": (s : PsRootState, _key, e, _iter) => ps_filter_entry(
      s, e,
    ) },
  enrich={
      // JS composes `btn btn-xs border-0 ${getCategoryColor(cat, isSelected)}`;
      // the trailing `cat-btn on|off` tokens are the MB test hooks.
      "enrichCategoryBindings": (s : PsRootState, binds, _key, value, _iter) => match
        value {
        Str(cat) => {
          let selected = s.selectedCategories.contains(cat)
          binds["isSelected"] = Bool(selected)
          let state = if selected { "on" } else { "off" }
          binds["btnClass"] = Str(
            "btn btn-xs border-0 \{ps_category_color(cat, selected)} cat-btn \{state}",
          )
        }
        _ => ()
      },
      // JS: selected -> `btn btn-xs btn-neutral font-bold ring-1
      // ring-neutral-content/30`, else `btn btn-xs btn-ghost font-bold
      // opacity-40`; the trailing `role-btn on|off` tokens are the MB hooks.
      "enrichRoleBindings": (s : PsRootState, binds, _key, value, _iter) => match
        value {
        Str(role) => {
          let selected = s.selectedRoles.contains(role)
          binds["btnClass"] = Str(
            if selected {
              "btn btn-xs btn-neutral font-bold ring-1 ring-neutral-content/30 role-btn on"
            } else {
              "btn btn-xs btn-ghost font-bold opacity-40 role-btn off"
            },
          )
        }
        _ => ()
      },
    },
  update=(s : PsRootState, msg, ctx) => match msg {
      Input("onCategoryToggle", args) =>
        Some({
          ..s,
          selectedCategories: ps_facet_toggle(
            s.allCategories,
            s.selectedCategories,
            args,
          ),
        })
      Input("onRoleToggle", args) =>
        Some({
          ..s,
          selectedRoles: ps_facet_toggle(s.allRoles, s.selectedRoles, args),
        })
      Input("onToggleSortByEnd", _) =>
        Some(ps_resort({ ..s, sortByEnd: !s.sortByEnd }))
      Input("onToggleSortAsc", _) =>
        Some(ps_resort({ ..s, sortAsc: !s.sortAsc }))
      Input("onToggleFeaturedFirst", _) =>
        Some(ps_resort({ ..s, featuredFirst: !s.featuredFirst }))
      Response("loadData", args) => {
        let entries = match args {
          [List(a), ..] => a
          _ => []
        }
        // collect + sort the distinct categories and roles
        let cat_set : Map[String, Unit] = Map([])
        let role_set : Map[String, Unit] = Map([])
        for e in entries {
          match e {
            Obj(o) => {
              match o.obj_field("categories") {
                Some(List(cs)) =>
                  for c in cs {
                    if c is Str(cstr) {
                      cat_set[cstr] = ()
                    }
                  }
                _ => ()
              }
              match o.obj_field("role") {
                Some(Str(r)) => role_set[r] = ()
                _ => ()
              }
            }
            _ => ()
          }
        }
        let cats = cat_set.keys().collect()
        cats.sort_by((a, b) => a.lexical_compare(b))
        let roles = role_set.keys().collect()
        roles.sort_by((a, b) => a.lexical_compare(b))
        Some({
          ..s,
          allEntries: ps_sort(entries, s.sortByEnd, s.sortAsc, s.featuredFirst),
          allCategories: cats,
          selectedCategories: ps_set_of(cats),
          allRoles: roles,
          selectedRoles: ps_set_of(roles),
        })
      }
      Receive("init", _) => {
        ctx.request("loadData", [], @tutuca.RequestOpts::new())
        Some(s)
      }
      _ => None
    },
)
}

///|
/// The `filterEntry` @when: keep an entry when its role and at least one of
/// its categories are selected.
fn ps_filter_entry(s : PsRootState, entry : @tutuca.Value) -> Bool {
  if s.selectedRoles.length() > 0 {
    let r = obj_str(entry, "role")
    if !s.selectedRoles.contains(r) {
      return false
    }
  }
  let entry_cats = match entry {
    Obj(o) =>
      match o.obj_field("categories") {
        Some(List(a)) => a
        _ => []
      }
    _ => []
  }
  if s.selectedCategories.length() > 0 && entry_cats.length() > 0 {
    let mut hit = false
    for c in entry_cats {
      if c is Str(cs) && s.selectedCategories.contains(cs) {
        hit = true
        break
      }
    }
    if !hit {
      return false
    }
  }
  true
}

///|
/// Shared category/role toggle: plain click toggles the member; alt-click solos
/// it (or, if already selected, inverse-solos — everything except it).
fn ps_facet_toggle(
  all : Array[String],
  set : Map[String, Bool],
  args : Array[@tutuca.Value],
) -> Map[String, Bool] {
  let key = match args {
    [Num(k), ..] => k.to_int()
    _ => -1
  }
  let is_alt = match args {
    [_, Bool(a), ..] => a
    _ => false
  }
  guard key >= 0 && key < all.length() else { return set }
  let entry = all[key]
  if is_alt {
    if set.contains(entry) {
      // inverse solo: all except this
      let rest = all.filter(m => m != entry)
      ps_set_of(rest)
    } else {
      // solo: only this
      ps_set_of([entry])
    }
  } else {
    ps_set_toggle(set, entry)
  }
}

///|
/// The fixture data (in place of the JS remote fetch).
fn ps_fixture(
  entry : @component.Component,
  alt_url : @component.Component,
) -> @tutuca.Value {
  List([
    entry_from_data(
      entry,
      alt_url,
      "Tutuca",
      "A SPA framework",
      2024,
      2026,
      "Author",
      true,
      ["Programming Languages", "Web"],
      [("repo", "#")],
    ),
    entry_from_data(
      entry,
      alt_url,
      "MoonBit port",
      "This very port",
      2026,
      2026,
      "Author",
      false,
      ["Programming Languages"],
      [],
    ),
    entry_from_data(
      entry,
      alt_url,
      "Distributed thing",
      "A system",
      2018,
      2020,
      "Maintainer",
      false,
      ["Distributed Systems"],
      [],
    ),
    entry_from_data(
      entry,
      alt_url,
      "Talk on WASM",
      "A conference talk",
      2021,
      2021,
      "Speaker",
      true,
      ["WebAssembly", "Web"],
      [],
    ),
  ])
}

///|
pub fn personal_site_module() -> @component.ModuleDef {
  let alt_url = alt_url_comp()
  let entry = ps_entry_comp()
  let root = root_comp()
  let requests : Map[String, @component.RequestFn] = {
    "loadData": RequestFn((_args, respond) => {
      respond(Ok(ps_fixture(entry, alt_url)))
    }),
  }
  @component.ModuleDef::new(
    name="personal-site",
    components=[root, entry, alt_url],
    requests~,
    examples=[
      {
        component: "Root",
        title: "Default (Loading)",
        args: Map([]),
        view: None,
      },
      {
        component: "AltUrl",
        title: "Alt URL",
        args: { "label": Str("GitHub"), "url": Str("#") },
        view: None,
      },
    ],
  )
}

///|
fn build() -> @component.ModuleDef {
  personal_site_module()
}
