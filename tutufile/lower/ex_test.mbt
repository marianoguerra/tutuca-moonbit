// The expression reader and printer, as one round trip: shrubbery in, the
// notation the slot parser reads out.

///|
/// Read one expression from source and print it as tutuca.
fn ex(src : String) -> String {
  let parsed = @shrub.parse(src + "\n") catch { _ => return "<not shrubbery>" }
  guard parsed.root().it is Multi(gs) && gs.length() == 1 else {
    return "<not one group>"
  }
  print_ex(read_group(gs[0])) catch {
    ExError(message~, ..) => "<error: " + message + ">"
  }
}

///|
test "names carry their binder into the sigil the old notation used" {
  inspect(ex("it.count"), content=".count")
  inspect(ex("it.state.count"), content="state.count")
  inspect(ex("dyn.theme"), content="*theme")
  inspect(ex("item.title"), content="@item.title")
  inspect(ex("e.value"), content="e.value")
  inspect(ex("label"), content="label")
}

///|
test "the operators map family by family" {
  inspect(ex("it.a == \"x\""), content="(.a is 'x')")
  inspect(ex("it.a != \"x\""), content="(.a is not 'x')")
  inspect(ex("it.a && it.b"), content="(.a and .b)")
  inspect(ex("it.a || it.b"), content="(.a or .b)")
  inspect(ex("!it.open"), content="(not .open)")
  inspect(ex("(it.n > 0) && it.open"), content="((.n > 0) and .open)")
  inspect(ex("it.qty * it.price"), content="(.qty * .price)")
  inspect(ex("it.a implies it.b"), content="(.a implies .b)")
}

///|
test "a builtin is a method here and a prefix word there" {
  inspect(ex("it.items.is_empty()"), content="(empty? .items)")
  inspect(ex("!it.draft.is_empty()"), content="(not (empty? .draft))")
  inspect(ex("it.items.length()"), content="(len .items)")
  inspect(
    ex("it.title.lower().contains(q)"),
    content="(contains (lower .title) q)",
  )
  inspect(ex("it.picked.has(item)"), content="(has .picked item)")
  inspect(ex("math.max(0, it.qty - 1)"), content="(max 0 (.qty - 1))")
  inspect(ex("item.to_string()"), content="(str item)")
  inspect(ex("it.x == none"), content="(null? .x)")
}

///|
test "a compute is called, and prints as the sigil that calls one" {
  inspect(ex("label()"), content="$label")
  inspect(ex("format(item)"), content="$format item")
}

///|
test "a string template is one string with holes in both notations" {
  inspect(ex("@str{count: @(it.n)}"), content="$'count: {.n}'")
  inspect(
    ex("@str{@(it.qty) x @(it.item) = @(it.qty * it.price)}"),
    content="$'{.qty} x {.item} = {(.qty * .price)}'",
  )
}

///|
test "an if keeps both arms" {
  inspect(
    ex("if it.done | @str{@(it.text) (done)} | it.text"),
    content="if .done { $'{.text} (done)' } else { .text }",
  )
}

///|
test "a sequence access keeps its key" {
  inspect(ex("it.sheets[it.sel_id]"), content=".sheets[.sel_id]")
}

///|
test "a nested read is refused, and the message names the two repairs" {
  inspect(
    ex("it.user.name"),
    content="<error: a member read needs a binding or the event to read it from>",
  )
}

///|
test "a method nobody has is refused by name" {
  inspect(
    ex("it.items.sorted()"),
    content="<error: `sorted` is not a method of a value>",
  )
}
