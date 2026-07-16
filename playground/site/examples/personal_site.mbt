// Personal site: a filterable list of entries with category/role facets,
// sorting, and a solo/unsolo (alt-click) interaction; fixture data loads via a
// request handler dispatched on `init` after mount.

// --- shared field helpers (inlined from examples/fields.mbt) ---

/// Field off a Value::Obj; Null for non-objects and missing fields.
fn obj_get(v : @tutuca.Value, field : String) -> @tutuca.Value {
  match v {
    Obj(o) => o.obj_field(field).unwrap_or(Null)
    _ => Null
  }
}

fn obj_str(v : @tutuca.Value, field : String) -> String {
  as_str(obj_get(v, field))
}

fn obj_int(v : @tutuca.Value, field : String) -> Int {
  as_int(obj_get(v, field))
}

fn obj_bool(v : @tutuca.Value, field : String) -> Bool {
  as_bool(obj_get(v, field))
}

fn as_str(v : @tutuca.Value) -> String {
  match v {
    Str(s) => s
    _ => ""
  }
}

fn as_int(v : @tutuca.Value) -> Int {
  match v {
    Num(n) => n.to_int()
    _ => 0
  }
}

fn as_bool(v : @tutuca.Value) -> Bool {
  v is Bool(true)
}

fn as_list(v : @tutuca.Value) -> Array[@tutuca.Value] {
  match v {
    List(a) => a
    _ => []
  }
}

// --- personal_site (copied verbatim from examples/personal_site.mbt) ---

/// A Map-backed set: membership is key-presence.
fn ps_set_of(members : Array[String]) -> Map[String, @tutuca.Value] {
  let m : Map[String, @tutuca.Value] = {}
  for s in members {
    m[s] = Bool(true)
  }
  m
}

///|
fn ps_set_field(
  inst : @component.Instance,
  field : String,
) -> Map[String, @tutuca.Value] {
  match inst.get(field) {
    Map(m) => m
    _ => {}
  }
}

///|
fn ps_list_strings(inst : @component.Instance, field : String) -> Array[String] {
  as_list(inst.get(field)).filter_map(v => {
    match v {
      Str(s) => Some(s)
      _ => None
    }
  })
}

///|
/// Toggle a member in a Map-backed set.
fn ps_set_toggle(
  set : Map[String, @tutuca.Value],
  entry : String,
) -> Map[String, @tutuca.Value] {
  let out : Map[String, @tutuca.Value] = {}
  for k, v in set {
    out[k] = v
  }
  if out.contains(entry) {
    out.remove(entry)
  } else {
    out[entry] = Bool(true)
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
fn ps_resort(inst : @component.Instance) -> @component.Instance {
  let entries = match inst.get("allEntries") {
    List(a) => a
    _ => []
  }
  inst.set(
    "allEntries",
    List(
      ps_sort(
        entries,
        inst.get("sortByEnd") is Bool(true),
        inst.get("sortAsc") is Bool(true),
        inst.get("featuredFirst") is Bool(true),
      ),
    ),
  )
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
fn alt_url_comp() -> @component.Component {
  @component.component(
    name="AltUrl",
    view=(
      #|<a class="badge badge-ghost badge-sm cursor-pointer gap-1 no-underline hover:bg-base-200 alt-url" :href=".url" target="_blank">🔗 <span @text=".label"></span></a>
    ),
    fields={
      "label": @component.FieldSpec::of_default(Str("")),
      "url": @component.FieldSpec::of_default(Str("#")),
    },
  )
}

///|
fn ps_entry_comp() -> @component.Component {
  @component.component(
    name="PSEntry",
    view=(
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
    ),
    alter={
      // JS `enrichCategoryBadge`: entry category badges always use the
      // SELECTED color variant. The `cat` token is the MB test hook.
      "enrichCategoryBadge": (_inst, args) => {
        match args {
          [Map(binds), _key, Str(cat), ..] =>
            binds["badgeClass"] = Str(
              "badge badge-sm \{ps_category_color(cat, true)} cat",
            )
          _ => ()
        }
        Null
      },
    },
    fields={
      "title": @component.FieldSpec::of_default(Str("?")),
      "description": @component.FieldSpec::of_default(Str("")),
      "lang": @component.FieldSpec::of_default(Str("en")),
      "startYear": @component.FieldSpec::of_default(Null),
      "endYear": @component.FieldSpec::of_default(Null),
      "role": @component.FieldSpec::of_default(Null),
      "featured": @component.FieldSpec::of_default(Bool(false)),
      "url": @component.FieldSpec::of_default(Str("#")),
      "altUrls": @component.FieldSpec::of_default(List([])),
      "categories": @component.FieldSpec::of_default(List([])),
    },
    methods={
      "langFlag": (inst, _args) => {
        if inst.get("lang") is Str("es") {
          Str("🇪🇸")
        } else {
          Str("🇬🇧")
        }
      },
      "isSpanish": (inst, _args) => Bool(inst.get("lang") is Str("es")),
      "yearDisplay": (inst, _args) => {
        match inst.get("startYear") {
          Num(s) =>
            match inst.get("endYear") {
              Num(e) => Str("\{s.to_int()}-\{e.to_int()}")
              _ => Str("\{s.to_int()}")
            }
          _ => Str("")
        }
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
  entry
  .make({
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
    "categories": List(cats.map(c => @tutuca.Value::Str(c))),
    "altUrls": List(
      alt_urls.map(a => {
        alt_url.make({ "label": Str(a.0), "url": Str(a.1) }).to_value()
      }),
    ),
  })
  .to_value()
}

///|
fn root_comp() -> @component.Component {
  @component.component(
    name="Root",
    view=(
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
    ),
    // Decoy view mirroring personal-site.js's `_margauiClasses`: every class
    // assembled at runtime in enrichCategoryBindings / enrichRoleBindings /
    // enrichCategoryBadge lives here as a literal so the margaui scanner picks
    // it up. Never rendered; the per-category colors are interpolated from the
    // color tables above (single source of truth).
    views={
      "_margauiClasses": "<p class=\"btn btn-xs btn-neutral btn-ghost border-0 badge badge-sm font-bold opacity-40 ring-1 ring-neutral-content/30 \{ps_category_decoy_classes()}\"></p>",
    },
    fields={
      "allEntries": @component.FieldSpec::of_default(List([])),
      "allCategories": @component.FieldSpec::of_default(List([])),
      "allRoles": @component.FieldSpec::of_default(List([])),
      "selectedCategories": @component.FieldSpec::of_default(Map({})),
      "selectedRoles": @component.FieldSpec::of_default(Map({})),
      "featuredFirst": @component.FieldSpec::of_default(Bool(true)),
      "sortByEnd": @component.FieldSpec::of_default(Bool(false)),
      "sortAsc": @component.FieldSpec::of_default(Bool(false)),
    },
    methods={
      "clearFilters": (inst, _args) => {
        inst
        .set(
          "selectedCategories",
          Map(ps_set_of(ps_list_strings(inst, "allCategories"))),
        )
        .set("selectedRoles", Map(ps_set_of(ps_list_strings(inst, "allRoles"))))
        .to_value()
      },
      "hasActiveFilters": (inst, _args) => {
        let cats_all = ps_list_strings(inst, "allCategories").length()
        let roles_all = ps_list_strings(inst, "allRoles").length()
        Bool(
          ps_set_field(inst, "selectedCategories").length() != cats_all ||
          ps_set_field(inst, "selectedRoles").length() != roles_all,
        )
      },
    },
    input={
      "onCategoryToggle": (inst, args, _ctx) => {
        Some(ps_facet_toggle(inst, args, "allCategories", "selectedCategories"))
      },
      "onRoleToggle": (inst, args, _ctx) => {
        Some(ps_facet_toggle(inst, args, "allRoles", "selectedRoles"))
      },
      "onToggleSortByEnd": (inst, _args, _ctx) => {
        Some(ps_resort(flip(inst, "sortByEnd")))
      },
      "onToggleSortAsc": (inst, _args, _ctx) => {
        Some(ps_resort(flip(inst, "sortAsc")))
      },
      "onToggleFeaturedFirst": (inst, _args, _ctx) => {
        Some(ps_resort(flip(inst, "featuredFirst")))
      },
    },
    alter={
      "filterEntry": (inst, args) => {
        let entry = match args {
          [_key, e, ..] => e
          _ => return Bool(true)
        }
        let roles = ps_set_field(inst, "selectedRoles")
        if roles.length() > 0 {
          let r = obj_str(entry, "role")
          if !roles.contains(r) {
            return Bool(false)
          }
        }
        let cats = ps_set_field(inst, "selectedCategories")
        let entry_cats = match entry {
          Obj(o) =>
            match o.obj_field("categories") {
              Some(List(a)) => a
              _ => []
            }
          _ => []
        }
        if cats.length() > 0 && entry_cats.length() > 0 {
          let mut hit = false
          for c in entry_cats {
            if c is Str(cs) && cats.contains(cs) {
              hit = true
              break
            }
          }
          if !hit {
            return Bool(false)
          }
        }
        Bool(true)
      },
      // JS composes `btn btn-xs border-0 ${getCategoryColor(cat, isSelected)}`;
      // the trailing `cat-btn on|off` tokens are the MB test hooks.
      "enrichCategoryBindings": (inst, args) => {
        match args {
          [Map(binds), _key, Str(cat), ..] => {
            let selected = ps_set_field(inst, "selectedCategories").contains(
              cat,
            )
            binds["isSelected"] = Bool(selected)
            let state = if selected { "on" } else { "off" }
            binds["btnClass"] = Str(
              "btn btn-xs border-0 \{ps_category_color(cat, selected)} cat-btn \{state}",
            )
          }
          _ => ()
        }
        Null
      },
      // JS: selected -> `btn btn-xs btn-neutral font-bold ring-1
      // ring-neutral-content/30`, else `btn btn-xs btn-ghost font-bold
      // opacity-40`; the trailing `role-btn on|off` tokens are the MB hooks.
      "enrichRoleBindings": (inst, args) => {
        match args {
          [Map(binds), _key, Str(role), ..] => {
            let selected = ps_set_field(inst, "selectedRoles").contains(role)
            binds["btnClass"] = Str(
              if selected {
                "btn btn-xs btn-neutral font-bold ring-1 ring-neutral-content/30 role-btn on"
              } else {
                "btn btn-xs btn-ghost font-bold opacity-40 role-btn off"
              },
            )
          }
          _ => ()
        }
        Null
      },
    },
    response={
      "loadData": (inst, args, _ctx) => {
        let entries = match args {
          [List(a), ..] => a
          _ => []
        }
        // collect + sort the distinct categories and roles
        let cat_set : Map[String, Unit] = {}
        let role_set : Map[String, Unit] = {}
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
        Some(
          inst
          .set(
            "allEntries",
            List(
              ps_sort(
                entries,
                inst.get("sortByEnd") is Bool(true),
                inst.get("sortAsc") is Bool(true),
                inst.get("featuredFirst") is Bool(true),
              ),
            ),
          )
          .set("allCategories", List(cats.map(c => @tutuca.Value::Str(c))))
          .set("selectedCategories", Map(ps_set_of(cats)))
          .set("allRoles", List(roles.map(r => @tutuca.Value::Str(r))))
          .set("selectedRoles", Map(ps_set_of(roles))),
        )
      },
    },
    receive={
      "init": (inst, _args, ctx) => {
        ctx.request("loadData", [], @tutuca.RequestOpts::new())
        Some(inst)
      },
    },
  )
}

///|
fn flip(inst : @component.Instance, field : String) -> @component.Instance {
  inst.set(field, Bool(!(inst.get(field) is Bool(true))))
}

///|
/// Shared category/role toggle: plain click toggles the member; alt-click solos
/// it (or, if already selected, inverse-solos — everything except it).
fn ps_facet_toggle(
  inst : @component.Instance,
  args : Array[@tutuca.Value],
  all_field : String,
  sel_field : String,
) -> @component.Instance {
  let all = ps_list_strings(inst, all_field)
  let key = match args {
    [Num(k), ..] => k.to_int()
    _ => -1
  }
  let is_alt = match args {
    [_, Bool(a), ..] => a
    _ => false
  }
  guard key >= 0 && key < all.length() else { return inst }
  let entry = all[key]
  let set = ps_set_field(inst, sel_field)
  let next = if is_alt {
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
  inst.set(sel_field, Map(next))
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
    "loadData": @component.RequestFn((_args, respond) => {
      respond(Ok(ps_fixture(entry, alt_url)))
    }),
  }
  @component.ModuleDef::new(
    name="personal-site",
    components=[root, entry, alt_url],
    requests~,
    examples=[
      { component: "Root", title: "Default (Loading)", args: {}, view: None },
      {
        component: "AltUrl",
        title: "Alt URL",
        args: { "label": Str("GitHub"), "url": Str("#") },
        view: None,
      },
    ],
  )
}

fn build() -> @component.ModuleDef {
  personal_site_module()
}

fn main {
  @host.mount(build(), "app")
}
