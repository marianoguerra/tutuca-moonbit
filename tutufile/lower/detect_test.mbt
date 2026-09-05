///|
test "a source is told apart by what it opens with, not by what it mentions" {
  assert_true(is_tutu_source("spec:\n  Counter:\n    field n :: Int\n"))
  assert_true(
    is_tutu_source("\n// a comment first\nview:\n  C:\n    @div{x}\n"),
  )
  // the case that made the body test wrong: a card that TEACHES markup
  assert_true(
    is_tutu_source(
      (
        #|spec:
        #|  /// Renders a `<script>` tag for the reader, which is not one.
        #|  C:
        #|    field body :: String
        #|
      ),
    ),
  )
  assert_false(
    is_tutu_source("<script type=\"tutuca/spec\">\n  state C { n: Int }\n"),
  )
  assert_false(is_tutu_source("<template id=\"C\"><p></p></template>\n"))
  // an indented first line cannot be a section: a file does not open inside
  assert_false(is_tutu_source("  spec:\n    C:\n"))
  assert_false(is_tutu_source(""))
}
