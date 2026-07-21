// Port of src/components/tutuca/lint-inspector.js — render lint findings as
// per-component collapsible groups under severity tallies.
//
// Port deviations:
// - The JS `--json` envelope carried only rule ids + info, so the JS file
//   reimplemented the CLI's `lintIdToMessage` prose. The port's findings
//   (cli `LintFinding`) already carry a full human-readable message, so
//   `lintMessage` is not ported. To keep this package free of a cli import,
//   LintReport renders a PLAIN shape: a List of Maps with keys
//   code/level/where/message/suggestion — build one with `finding_value`
//   (levels: "error" / "warn" / "hint"). Findings are grouped by the
//   component part of `where` ("Comp", "Comp/view", "Comp.provide.name").
// - The JS finding `detail` (id/info/context) becomes the finding Map itself,
//   rendered with the data inspector (collapsed).

///|
/// Build one finding entry for `Inspector::lint_report` /
/// `Inspector::lint_report_for`. `level` is "error", "warn" or "hint";
/// `where_` is the linter's location ("Comp", "Comp/view", …).
pub fn finding_value(
  code : String,
  level : String,
  where_ : String,
  message : String,
  suggestion? : String = "",
) -> @tutuca.Value {
  Map({
    "code": Str(code),
    "level": Str(level),
    "where": Str(where_),
    "message": Str(message),
    "suggestion": Str(suggestion),
  })
}

///|
/// The component name a finding belongs to: the part of `where` before the
/// first '/' or '.'.
fn finding_component_name(where_ : String) -> String {
  for i in 0..<where_.length() {
    if where_[i] is ('/' | '.') {
      return where_[0:i].to_owned()
    }
  }
  where_
}

// ---------------------------------------------------------------------------
// Components — colour is reserved for severity (the level badge + the header
// tallies); everything structural stays neutral.
// ---------------------------------------------------------------------------

///|
/// One finding: a soft severity badge, the message, an optional fix
/// suggestion, and the full finding Map via the data inspector (collapsed).
fn lint_finding_comp() -> @component.Component {
  @component.component(
    name="LintFinding",
    fields={
      "code": @component.FieldSpec::of_default(Str("")),
      "level": @component.FieldSpec::of_default(Str("")),
      "message": @component.FieldSpec::of_default(Str("")),
      "suggestion": @component.FieldSpec::of_default(Str("")),
      "detail": @component.FieldSpec::of_default(Null),
    },
    methods={
      "levelBadgeClass": (inst, _args) => {
        let color = match str_field(inst, "level") {
          "error" => "badge-error"
          "warn" => "badge-warning"
          _ => "badge-neutral"
        }
        Str("badge badge-sm badge-soft finding-level \{color}")
      },
      "hasSuggestion": (inst, _args) => {
        Bool(str_field(inst, "suggestion") != "")
      },
      "hasDetail": (inst, _args) => Bool(!(inst.get("detail") is Null)),
    },
    // Decoy so the runtime-built soft badge colours survive the class scan.
    views={
      "_palette": (
        #|<span class="badge-soft badge-error badge-warning badge-neutral"></span>
      ),
    },
    view=(
      #|<div class="flex flex-col gap-1.5 py-1.5 leading-snug lint-finding">
      #|  <div class="flex items-baseline gap-2 flex-wrap">
      #|    <span :class="$levelBadgeClass" @text=".level"></span>
      #|    <span class="text-sm text-base-content/90 finding-message" @text=".message"></span>
      #|  </div>
      #|  <div @show="$hasSuggestion" class="ml-3 flex items-baseline gap-1.5 text-xs text-base-content/60">
      #|    <span>fix</span>
      #|    <span class="font-mono finding-suggestion" @text=".suggestion"></span>
      #|  </div>
      #|  <div @show="$hasDetail" class="ml-3"><x render=".detail"></x></div>
      #|</div>
    ),
  )
}

///|
/// Per-component group of findings, collapsible/paginated; expanded by
/// default when it has error-level findings.
fn lint_component_comp() -> @component.Component {
  let fields = composite_fields()
  fields["componentName"] = @component.FieldSpec::of_default(Str(""))
  fields["errors"] = @component.FieldSpec::of_default(Num(0))
  fields["warns"] = @component.FieldSpec::of_default(Num(0))
  fields["hints"] = @component.FieldSpec::of_default(Num(0))
  let methods = composite_methods(inst => str_field(inst, "componentName"), inst => {
    let parts : Array[String] = []
    let errors = int_field(inst, "errors")
    let warns = int_field(inst, "warns")
    let hints = int_field(inst, "hints")
    if errors > 0 {
      parts.push(count_label(errors, "error"))
    }
    if warns > 0 {
      parts.push(count_label(warns, "warning"))
    }
    if hints > 0 {
      parts.push(count_label(hints, "hint"))
    }
    if parts.length() > 0 {
      parts.join(", ")
    } else {
      "ok"
    }
  })
  @component.component(
    name="LintComponent",
    fields~,
    methods~,
    alter=composite_alter(),
    view=make_composite_view(
      type_class="font-semibold lint-component",
      border_class="border-base-content/15",
    ),
  )
}

///|
fn count_label(n : Int, word : String) -> String {
  if n == 1 {
    "\{n} \{word}"
  } else {
    "\{n} \{word}s"
  }
}

///|
/// Top-level lint report: a neutral title + soft severity tallies over the
/// per-component groups (clean components are omitted).
fn lint_report_comp() -> @component.Component {
  @component.component(
    name="LintReport",
    fields={
      "title": @component.FieldSpec::of_default(Str("")),
      "path": @component.FieldSpec::of_default(Str("")),
      "errors": @component.FieldSpec::of_default(Num(0)),
      "warnings": @component.FieldSpec::of_default(Num(0)),
      "hints": @component.FieldSpec::of_default(Num(0)),
      "clean": @component.FieldSpec::of_default(Bool(true)),
      "components": @component.FieldSpec::of_default(List([])),
    },
    methods={
      "errText": (inst, _args) => {
        Str(count_label(int_field(inst, "errors"), "error"))
      },
      "warnText": (inst, _args) => {
        Str(count_label(int_field(inst, "warnings"), "warning"))
      },
      "hintText": (inst, _args) => {
        Str(count_label(int_field(inst, "hints"), "hint"))
      },
      "hasErrors": (inst, _args) => Bool(int_field(inst, "errors") > 0),
      "hasWarnings": (inst, _args) => Bool(int_field(inst, "warnings") > 0),
      "hasHints": (inst, _args) => Bool(int_field(inst, "hints") > 0),
    },
    // Decoy so the runtime-absent soft tally colours are emitted.
    views={
      "_palette": (
        #|<span class="badge-soft badge-error badge-warning badge-neutral badge-success"></span>
      ),
    },
    view=(
      #|<div class="font-mono text-sm leading-snug flex flex-col gap-3 lint-report">
      #|  <div class="flex items-center gap-2 flex-wrap">
      #|    <span class="font-semibold lint-title" @text=".title"></span>
      #|    <span class="text-base-content/40 text-xs" @text=".path"></span>
      #|    <span @show="$hasErrors" class="badge badge-sm badge-soft badge-error lint-errors" @text="$errText"></span>
      #|    <span @show="$hasWarnings" class="badge badge-sm badge-soft badge-warning lint-warnings" @text="$warnText"></span>
      #|    <span @show="$hasHints" class="badge badge-sm badge-soft badge-neutral lint-hints" @text="$hintText"></span>
      #|    <span @show=".clean" class="badge badge-sm badge-soft badge-success lint-clean">✓ clean</span>
      #|  </div>
      #|  <x render-each=".components"></x>
      #|</div>
    ),
  )
}

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

///|
fn finding_str(f : @tutuca.Value, key : String) -> String {
  match f {
    Map(m) =>
      match m.get(key) {
        Some(Str(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
fn Inspector::build_finding(
  self : Inspector,
  f : @tutuca.Value,
) -> @tutuca.Value {
  self.make_("LintFinding", args={
    "code": Str(finding_str(f, "code")),
    "level": Str(finding_str(f, "level")),
    "message": Str(finding_str(f, "message")),
    "suggestion": Str(finding_str(f, "suggestion")),
    "detail": self.inspect_value(f),
  })
}

///|
/// JS LintReport.Class.fromData over the plain finding shape: group the
/// findings by component (the prefix of `where`), tally severities, expand
/// groups that contain errors.
pub fn Inspector::lint_report(
  self : Inspector,
  findings : Array[@tutuca.Value],
  title? : String = "Lint",
  path? : String = "",
) -> @tutuca.Value {
  // group by component name, preserving first-seen order
  let order : Array[String] = []
  let groups : Map[String, Array[@tutuca.Value]] = Map([])
  for f in findings {
    let comp_name = finding_component_name(finding_str(f, "where"))
    match groups.get(comp_name) {
      Some(g) => g.push(f)
      None => {
        order.push(comp_name)
        groups[comp_name] = [f]
      }
    }
  }
  let mut errors = 0
  let mut warnings = 0
  let mut hints = 0
  let built : Array[@tutuca.Value] = []
  for comp_name in order {
    let group = groups.get(comp_name).unwrap_or([])
    let mut e = 0
    let mut w = 0
    let mut h = 0
    for f in group {
      match finding_str(f, "level") {
        "error" => e += 1
        "warn" => w += 1
        "hint" => h += 1
        _ => ()
      }
    }
    errors += e
    warnings += w
    hints += h
    built.push(
      self.make_("LintComponent", args={
        "componentName": Str(comp_name),
        "errors": Num(e.to_double()),
        "warns": Num(w.to_double()),
        "hints": Num(h.to_double()),
        "items": List(group.map(f => self.build_finding(f))),
        "isExpanded": Bool(e > 0),
      }),
    )
  }
  self.make_("LintReport", args={
    "title": Str(title),
    "path": Str(path),
    "errors": Num(errors.to_double()),
    "warnings": Num(warnings.to_double()),
    "hints": Num(hints.to_double()),
    "clean": Bool(built.length() == 0),
    "components": List(built),
  })
}
