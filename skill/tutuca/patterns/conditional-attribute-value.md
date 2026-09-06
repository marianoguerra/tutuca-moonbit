# Conditional attribute value

**Problem:** set an attribute (class, title, …) to one value or another
depending on a condition.

```tutu
spec:
  Toggle:
    field is_active :: Bool
    field tab :: String

    message toggle_is_active

view:
  Toggle:
    @button(
      ~class: if it.is_active | "btn btn-success" | "btn btn-ghost",
      ~on_click: toggle_is_active,
    ){@" toggle "}

    // the condition is any expression, and each attribute carries its own
    @button(
      ~class: if it.tab == "x" | "on" | "off",
      ~title: if it.is_active | "On" | "Off",
    ){two}
```

An attribute's value is an `if` expression: the condition, then the two
values. The condition is the ordinary expression language — a field read, a
call, a comparison — and each attribute carries its own, so two conditional
attributes on one element are two independent `if`s rather than a first and a
second that have to be told apart.
