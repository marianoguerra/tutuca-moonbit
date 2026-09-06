// An `@on.<event>` handler, printed as the `~on_<event>:` option it becomes.

///|
/// One registered handler, as one element option.
fn print_handler(h : @anode.NodeEvent) -> String raise NoSpelling {
  let body = match h.handler.action {
    Some(action) => print_action(action)
    None => print_call(h.handler)
  }
  let opts = StringBuilder()
  // An event name reaches an option through the same rule an attribute does:
  // an underscore is a hyphen. `@on.emoji-click` is `~on_emoji_click:`.
  opts.write_string("~on_\{option_event(h.name)}: \{body}")
  // The modifiers the old notation spelled in the name (`@on.keydown.enter+prevent`)
  // are options here. A key name is `~key:`; everything else is a bare flag.
  for m in h.modifiers {
    if is_key_name(m) {
      opts.write_string(" ~key: \{quote(capitalize(m))}")
    } else {
      opts.write_string(" ~\{@names.snake_of(m)}")
    }
  }
  opts.to_string()
}

///|
/// An event name as an option name: a hyphen is an underscore, and the rest is
/// the name the DOM knows it by.
fn option_event(name : String) -> String {
  let out = StringBuilder()
  for c in @names.snake_of(name) {
    if c == '-' {
      out.write_char('_')
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// A write to one of this component's own properties.
fn print_action(action : @tscript.PropertyAction) -> String raise NoSpelling {
  match action {
    PropertyReset(name) => "it.\{@names.snake_of(name)} := default"
    PropertyCall(name~, operation~, args~) => {
      let parts = []
      for a in args {
        parts.push(print_expr(a))
      }
      "it.\{@names.snake_of(name)}.\{checked_mutator(operation)}(\{parts.join(", ")})"
    }
    // `+=` and `-=` reach the tree as a `PropertySet` of the field plus the
    // operand, which is what `parse_property_action` built them into. Reading
    // that shape back gives the author's own spelling instead of the expansion.
    PropertySet(name~, value~) => {
      let field = @names.snake_of(name)
      match value {
        EApp(name=op, args~, ..) if op is ("+" | "-") &&
          args.length() == 2 &&
          args[0].as_field() is Some(f) &&
          @names.snake_of(f) == field =>
          "it.\{field} \{op}= \{print_expr(args[1])}"
        _ => "it.\{field} := \{print_expr(value)}"
      }
    }
  }
}

///|
/// A handler that is dispatched: a name, with the arguments it is called with.
fn print_call(h : @tscript.HandlerParse) -> String raise NoSpelling {
  let name = match h.handler {
    EName(name~, ..) | EMethod(name~, ..) => @names.rename_member(name)
    _ =>
      raise NoSpelling(
        what="an `@on` handler that is not a name",
        help="an event names the thing to run — write `~on_click: inc`",
      )
  }
  if h.args.is_empty() {
    return name
  }
  let parts = []
  for a in h.args {
    parts.push(print_expr(a))
  }
  "\{name}(\{parts.join(", ")})"
}

///|
/// Whether a modifier names a KEY rather than a behaviour.
///
/// The old notation put both in one dotted list (`@on.keydown.enter+prevent`),
/// so telling them apart is a closed list of the behaviours — everything else
/// in that position was a key.
fn is_key_name(m : String) -> Bool {
  // `send` and `cancel` name a KEY without naming it — Enter and Escape — and
  // `ctrl`/`cmd`/`meta`/`alt`/`shift` name a chord rather than a key. All of
  // them are behaviours the runtime already knows (`app/app.mbt`), so writing
  // one as `~key: "Cancel"` asks for a key nothing presses.
  ![
    "prevent", "stop", "once", "capture", "passive", "self", "trusted", "send", "cancel",
    "ctrl", "cmd", "meta", "alt", "shift",
  ].contains(m)
}

///|
/// A key modifier is lowercased in the old notation and named in the DOM's own
/// spelling here: `enter` was `KeyboardEvent.key === "Enter"`.
fn capitalize(s : String) -> String {
  guard s.length() > 0 else { return s }
  let cs : Array[Char] = s.iter().collect()
  let out = StringBuilder()
  if cs[0] is ('a'..='z') {
    out.write_char(Int::unsafe_to_char(cs[0].to_int() - 32))
  } else {
    out.write_char(cs[0])
  }
  for i in 1..<cs.length() {
    out.write_char(cs[i])
  }
  out.to_string()
}
