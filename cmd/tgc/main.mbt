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
}
