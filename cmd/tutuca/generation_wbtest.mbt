///|
async test "discovery stops at nested modules and forgets removed inputs" {
  let dir = @fs.tmpdir(prefix="tutuca-discovery-")
  defer @fs.rmdir(dir, recursive=true)
  @fs.write_file(
    dir + "/a.tutu",
    "view:\n  A:\n    div(): \"a\"",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(dir + "/a_view_gen.mbt", "", create_mode=CreateOrTruncate)
  @fs.mkdir(dir + "/consumer")
  @fs.write_file(
    dir + "/consumer/moon.mod",
    "name = \"test/consumer\"",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    dir + "/consumer/b.tutu",
    "view:\n  B:\n    div(): \"b\"",
    create_mode=CreateOrTruncate,
  )
  @fs.write_file(
    dir + "/consumer/b_view_gen.mbt",
    "",
    create_mode=CreateOrTruncate,
  )
  assert_eq(collect_view_files([dir]), [dir + "/a.tutu"])
  @fs.remove(dir + "/a.tutu")
  assert_eq(collect_view_files([dir]), [])
  assert_eq(collect_view_files([dir + "/a.tutu"]), [])
  assert_true(@fs.exists(dir + "/a_view_gen.mbt"))
}

///|
async test "watch validates the resolved batch before replacing outputs" {
  let dir = @fs.tmpdir(prefix="tutuca-batch-")
  defer @fs.rmdir(dir, recursive=true)
  for name in ["a", "b"] {
    @fs.write_file(
      dir + "/" + name + ".tutu",
      "invalid",
      create_mode=CreateOrTruncate,
    )
  }
  let target = dir + "/out.mbt"
  @fs.write_file(target, "unchanged", create_mode=CreateOrTruncate)
  let paths = [dir + "/a.tutu", dir + "/b.tutu"]
  let plan : @cli.WatchPlan = {
    paths,
    name: None,
    out: Some(target),
    ir: true,
    css: None,
  }
  let messages : Array[String] = []
  assert_false(
    regenerate_batch(paths, plan, report=message => messages.push(message)),
  )
  assert_true(messages[0].contains("2 view files resolved"))
  assert_eq(@fs.read_file(target).text(), "unchanged")
}

///|
async test "watch reports output write failures" {
  let dir = @fs.tmpdir(prefix="tutuca-write-")
  defer @fs.rmdir(dir, recursive=true)
  let path = dir + "/a.tutu"
  @fs.write_file(
    path,
    "view:\n  A:\n    div(): \"a\"",
    create_mode=CreateOrTruncate,
  )
  let target = dir + "/out.mbt"
  @fs.mkdir(target)
  let paths = [path]
  let plan : @cli.WatchPlan = {
    paths,
    name: None,
    out: Some(target),
    ir: true,
    css: None,
  }
  let messages : Array[String] = []
  assert_false(
    regenerate_batch(paths, plan, report=message => messages.push(message)),
  )
  assert_true(messages[0].contains("failed to write"))
}
