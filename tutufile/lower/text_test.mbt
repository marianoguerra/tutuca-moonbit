///|
/// Text around an escape and around a hole.
///
/// A body containing an escape comes back as SEVERAL pieces — `@p{a@"@"b}` is
/// three strings — and a printer that trims each one loses the spaces between
/// them. Found next door in a converter with the same shape; measured here
/// rather than assumed to be different.
test "the spaces between text pieces survive" {
  let src =
    #|spec:
    #|  T:
    #|    field n :: Int
    #|view:
    #|  T:
    #|    @p{a@"@"b}
    #|    @span{a @(it.n) b}
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  let parts = out.text.split("<template").collect()
  inspect(
    parts[parts.length() - 1].to_owned(),
    content=(
      #| id="T"><p>a@b</p><span>a <x text=".n"></x> b</span></template>
      #|
      #|
    ),
  )
}

///|
/// The two spaces again, as characters in a quoted string.
///
/// The block literal above asserts them too, but a trailing space at the end
/// of a `#|` line is exactly the kind of thing a formatter eats — and if it
/// ever does, that assertion weakens in silence and still passes. These two
/// cannot be normalised away by anything, which is the half that matters:
/// the bug being guarded against invents or eats precisely these characters.
test "the spaces around a hole are characters, pinned where nothing trims" {
  let src =
    #|spec:
    #|  T:
    #|    field n :: Int
    #|view:
    #|  T:
    #|    @span{a @(it.n) b}
    #|
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  // a space before the hole and a space after it, both as characters
  assert_true(out.text.contains(">a <x text=\".n\">"))
  assert_true(out.text.contains("</x> b</span>"))
  // and the run that must NOT gain a space
  let joined = lower_text(
    (
      #|spec:
      #|  T:
      #|    field n :: Int
      #|view:
      #|  T:
      #|    @p{a@"@"b}
      #|
    ),
  )
  assert_true(
    joined.text.contains(">a@b<") || joined.text.contains("\n    a@b\n"),
  )
  assert_false(joined.text.contains("a @ b"))
}
