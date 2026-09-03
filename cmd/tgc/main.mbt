// `tgc` — print the canonical preamble, or compile a module that carries it.

///|
fn main raise {
  let args = @env.args()
  let rest = args[1:]
  guard rest.length() >= 1 else {
    usage()
    return
  }
  match rest[0] {
    "preamble" => {
      let which = if rest.length() >= 2 { rest[1] } else { "--wax" }
      match which {
        "--wax" => println(@abi.preamble_wax())
        "--wat" => println(@abi.preamble_wat())
        other => println("unknown form \{other}; --wax or --wat")
      }
    }
    "build" => build(rest)
    "card" => card(rest)
    // The runtime, from its EMBEDDED source rather than from `rt.wax`. It is
    // the route a page takes, so it is the route worth being able to run.
    "runtime" => {
      let outp = if rest.length() >= 2 { rest[1] } else { "tutuca-rt.wasm" }
      let bytes = @emit.compile_runtime() catch {
        e => {
          println("rejected: \{e.message()}")
          return
        }
      }
      @fs.write_bytes_to_file(outp, bytes)
      println("\{outp}: \{bytes.length()} bytes")
    }
    other => {
      println("unknown command \{other}")
      usage()
    }
  }
}

///|
/// Compile one `.wax` module with the canonical preamble prepended.
///
/// Prepended rather than expected: a module's author writes the module, and the
/// preamble is not theirs to get right. That is the same argument the format
/// makes to a HOST — the types are the format's, not the module's — moved one
/// step earlier, to where a mistake is still cheap.
fn build(rest : ArrayView[String]) -> Unit raise {
  guard rest.length() >= 3 else {
    println("usage: tgc build <in.wax> <out.wasm>")
    return
  }
  let inp = rest[1]
  let outp = rest[2]
  let body = @fs.read_file_to_string(inp) catch {
    _ => {
      println("cannot read \{inp}")
      return
    }
  }
  // The offset is what turns a diagnostic's position back into a line the
  // author can find: everything before it is the preamble, which they did not
  // write and cannot fix.
  let preamble = @abi.preamble_wax()
  let source = preamble + "\n" + body
  let preamble_lines = count_lines(preamble) + 1
  let result = @wax.compile_string(source, fname=inp) catch {
    e => {
      println("this is a tgc bug rather than an input error: \{e}")
      return
    }
  }
  match result {
    Ok(bytes) => {
      @fs.write_bytes_to_file(outp, bytes)
      println("\{outp}: \{bytes.length()} bytes")
    }
    Err(ds) => {
      println("rejected: \{inp}")
      for d in ds {
        let line = d.loc.start.lnum - preamble_lines
        let where_ = if line >= 1 {
          "line \{line}"
        } else {
          "in the preamble (\{d.loc}) — which is a tgc bug, not yours"
        }
        println("  \{where_}: \{@message.to_plain_string(d.message)}")
      }
    }
  }
}

///|
/// Compile a card, the way the playground does.
///
/// It exists so a node test can drive the guest bridge without a browser: a
/// bridge only a page can exercise is a bridge nobody exercises.
fn card(rest : ArrayView[String]) -> Unit raise {
  guard rest.length() >= 3 else {
    println("usage: tgc card <card.html> <out.wasm>")
    return
  }
  let source = @fs.read_file_to_string(rest[1]) catch {
    _ => {
      println("cannot read \{rest[1]}")
      return
    }
  }
  let out = @emit.compile(source, name=stem_of(rest[1])) catch {
    e => {
      println("rejected: \{e.message()}")
      return
    }
  }
  @fs.write_bytes_to_file(rest[2], out.wasm)
  @fs.write_string_to_file(rest[2] + ".wax", out.wax)
  @fs.write_string_to_file(
    rest[2] + ".manifest.json",
    out.manifest.stringify(indent=2),
  )
  println("\{rest[2]}: \{out.wasm.length()} bytes, \{out.component}")
  for r in out.refusals {
    println("  refused \{r.kind} \{r.name}: \{r.reason}")
  }
}

///|
fn stem_of(path : String) -> String {
  let parts = path.split("/")
  let mut last = path
  for p in parts {
    last = p.to_string()
  }
  match last.split(".").to_array() {
    [head, ..] => head.to_string()
    _ => last
  }
}

///|
fn count_lines(s : String) -> Int {
  let mut n = 0
  for c in s {
    if c == '\n' {
      n = n + 1
    }
  }
  n
}

///|
fn usage() -> Unit {
  println("usage:")
  println("  tgc preamble [--wax|--wat]   print the canonical type section")
  println("  tgc build <in.wax> <out.wasm>")
  println("  tgc card <card.html> <out.wasm>")
  println("  tgc runtime [out.wasm]        compile the embedded runtime")
}
