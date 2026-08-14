// `cardwasm <card.html> [outdir]` — compile a card and write what came out.
//
// The playground's job in a terminal: it exists so the generator can be
// checked against `dyncomp/host/wasm/abi.mjs` by a node test, which is the
// only place the canonical ABI is actually agreed rather than merely believed.

///|
fn main raise {
  let args = @env.args()
  // `--allow-wax` compiles the card's `<script type="tutuca/wax">` block — the
  // escape hatch — rather than refusing it. Off by default here for the same
  // reason it is off in the library: whether a card may carry hand-written code
  // is the host's decision, and a CLI is a host.
  let allow_wax = args.iter().any(a => a == "--allow-wax")
  let positional = args[1:].iter().filter(a => a != "--allow-wax").collect()
  guard positional.length() >= 1 else {
    println("usage: cardwasm [--allow-wax] <card.html> [outdir]")
    return
  }
  let path = positional[0]
  let outdir = if positional.length() >= 2 { positional[1] } else { "." }
  let source = @fs.read_file_to_string(path) catch {
    _ => {
      println("cannot read " + path)
      return
    }
  }
  let stem = basename(path)
  let out = @gen.compile(source, name=stem, allow_wax~) catch {
    // Not "refused": a refusal is per-declaration and leaves a module behind,
    // and this is the card being turned away whole.
    e => {
      println("rejected: " + e.message())
      return
    }
  }
  @fs.write_bytes_to_file(outdir + "/" + stem + ".wasm", out.wasm)
  @fs.write_string_to_file(outdir + "/" + stem + ".wat", out.wat)
  @fs.write_string_to_file(outdir + "/" + stem + ".wax", out.wax)
  @fs.write_string_to_file(
    outdir + "/" + stem + ".manifest.json",
    out.manifest.stringify(indent=2),
  )
  @fs.write_string_to_file(
    outdir + "/" + stem + ".descriptor.json",
    out.descriptor.stringify(indent=2),
  )
  println(
    out.component +
    ": " +
    out.wasm.length().to_string() +
    " bytes, fields [" +
    out.fields.join(", ") +
    "]",
  )
  for r in out.refusals {
    // A field refusal has no line: the state block is parsed into a schema
    // rather than into a tree with coordinates.
    let at = if r.line == 0 { "" } else { " (line " + r.line.to_string() + ")" }
    println("  refused " + r.kind + " " + r.name + at + ": " + r.reason)
  }
  for e in out.escapes {
    let was = if e.replaced != "" {
      " (which the script block declares, and this backend refused)"
    } else if e.declared {
      " (which the script block declares too)"
    } else {
      " (which the script block does not declare)"
    }
    println("  escaped " + e.kind + " " + e.name + " -> " + e.fn_name + was)
  }
}

///|
/// The file name without its directory or its extensions.
fn basename(path : String) -> String {
  let parts = path.split("/").collect()
  let last = if parts.length() == 0 {
    path
  } else {
    parts[parts.length() - 1].to_owned()
  }
  match last.split(".").collect().get(0) {
    Some(v) => v.to_owned()
    None => last
  }
}
