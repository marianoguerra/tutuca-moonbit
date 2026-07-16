// extract_globals: every flag spelling from extractGlobals (tools/tutuca.js).

///|
fn ok_opts(argv : Array[String]) -> (@cli.GlobalOpts, Array[String]) {
  match @cli.extract_globals(argv) {
    Ok(pair) => pair
    Err(_) => abort("expected Ok for \{@debug.to_string(argv)}")
  }
}

///|
test "format flag spellings" {
  @debug.assert_eq(ok_opts(["-f", "json"]).0.format, Some("json"))
  @debug.assert_eq(ok_opts(["--format", "md"]).0.format, Some("md"))
  @debug.assert_eq(ok_opts(["--format=html"]).0.format, Some("html"))
  @debug.assert_eq(ok_opts(["--json"]).0.format, Some("json"))
  @debug.assert_eq(ok_opts([]).0.format, None)
}

///|
test "output, pretty, module, help flags" {
  let (opts, rest) = ok_opts([
    "render", "./m.js", "-o", "out.html", "--pretty", "--module=./other.js", "-h",
  ])
  @debug.assert_eq(opts.output, Some("out.html"))
  assert_true(opts.pretty)
  @debug.assert_eq(opts.module_path, Some("./other.js"))
  assert_true(opts.help)
  @debug.assert_eq(rest, ["render", "./m.js"])
  @debug.assert_eq(ok_opts(["--output=x"]).0.output, Some("x"))
  @debug.assert_eq(ok_opts(["--module", "m.js"]).0.module_path, Some("m.js"))
  assert_true(ok_opts(["--help"]).0.help)
}

///|
test "globals can appear anywhere; positionals keep order" {
  let (opts, rest) = ok_opts(["get", "--json", "./m.js", "Button"])
  @debug.assert_eq(opts.format, Some("json"))
  @debug.assert_eq(rest, ["get", "./m.js", "Button"])
}

///|
test "unknown format is a coded error with a suggestion" {
  match @cli.extract_globals(["-f", "jsn"]) {
    Ok(_) => abort("expected Err")
    Err((opts, shape)) => {
      @debug.assert_eq(opts.format, Some("jsn"))
      assert_eq(shape.code, "ERR_FORMAT_UNKNOWN")
      assert_eq(shape.message, "Unknown format 'jsn'")
      assert_true(shape.suggestion is Some(ReplaceName(from="jsn", to="json")))
      @debug.assert_eq(shape.hint, Some("Valid formats: cli, md, json, html"))
      assert_eq(shape.exit_code, 1)
    }
  }
}

///|
test "--json after a bad -f wins, like the JS end-of-loop validation" {
  @debug.assert_eq(ok_opts(["-f", "xml", "--json"]).0.format, Some("json"))
}
