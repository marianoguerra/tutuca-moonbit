// The static half of a bundle.
//
// A card already IS a manifest: the state block names the fields and their
// types, the `<template>`s are the views, the script names the messages and
// the methods, and a `tutuca/init` block is a named example. So this is a
// projection rather than a second thing to author — which is the answer to the
// "manifest authoring" open question in
// `docs/generative-dyncomps-in-the-browser-design.md`, at least for a card.
//
// The shape is `dyncomp/host/manifest.mbt`'s, and the one difference from a
// packed archive's is that views arrive as `html` rather than as a `src` the
// loader hydrates: there is no archive here, only a page that has the card.

///|
/// The `DynManifest` JSON for a compiled card.
///
/// A card is a BUNDLE, and a bundle has always been able to declare several
/// components — `DynManifest.components` was an array before anything could put
/// two things in it. What is bundle-level and what is per component is decided
/// by what the thing IS rather than by convenience: `macros` are the FILE's
/// (one table, `DuplicateMacro` across the whole of it, registered once into
/// the scope the bundle registers into), and everything else describes one
/// component.
fn manifest_json(
  comps : Array[Comp],
  file : @viewfile.ViewFile,
  root : Gen,
) -> Json {
  // The file's macros travel with it, bundle-level. `split_file` has been
  // returning them all along and this dropped them once, which made `<x:badge>`
  // in a compiled card an unknown element that rendered as itself — the same
  // bug the card LOADER had and fixed, one backend later.
  let macro_defs : Array[Json] = file.macros.map(m => {
    let defaults : Map[String, Json] = Map([])
    for k, v in m.defaults {
      defaults[k] = Json::string(v)
    }
    Json::object({
      "name": Json::string(m.name),
      "defaults": Json::object(defaults),
      "html": Json::string(m.source),
    })
  })
  // The ROOT first, then the rest in file order.
  //
  // A host takes the head of this list when it is told no name — that is what
  // `component_names() is [component, ..]` means at every mount site — so
  // "which component is the root" is said HERE, by ordering, rather than by a
  // second key every host would have to learn to read. The wasm's own indices
  // are untouched: they are file order, and nothing outside the module sees
  // them.
  let component_defs : Array[Json] = []
  let rest : Array[Json] = []
  for i, c in comps {
    // `file.components` and `comps` are built in the same pass, in the same
    // order, so the views at `i` are this component's.
    match file.components.get(i) {
      Some(views) => {
        let entry = component_json(c.g, c.decls, views)
        if c.g.comp == root.comp {
          component_defs.push(entry)
        } else {
          rest.push(entry)
        }
      }
      None => ()
    }
  }
  for entry in rest {
    component_defs.push(entry)
  }
  Json::object({
    "manifestVersion": Json::number(1),
    "apiVersion": Json::number(8),
    // Named after the ROOT rather than after the `name~` argument: a terminal
    // passes a file's basename and the browser passes the first template's
    // component, and the root is the one answer both of those agree with.
    "moduleName": Json::string(root.comp.to_lower() + "card"),
    "doc": Json::string(root.def.doc.unwrap_or("")),
    "version": Json::string("0.1.0"),
    "homepage": Json::string(""),
    "authors": Json::array([]),
    // Nothing is asked for, and that is not a placeholder: a compiled card has
    // no clock, no entropy and no timer, because nothing it can express needs
    // one. A capability it did not import could not be used anyway — the host
    // checks the IMPORT SECTION — so asking for one would be a promise rather
    // than a grant.
    "capabilities": Json::array([]),
    "stringEncoding": Json::string("utf8"),
    "macros": Json::array(macro_defs),
    "components": Json::array(component_defs),
  })
}

///|
/// One component's entry in the manifest's `components` array.
fn component_json(
  g : Gen,
  decls : Array[@tscript.Decl],
  views : @viewfile.ViewSet,
) -> Json {
  let types : Array[Json] = []
  let ty_index : Map[String, Int] = Map([])
  let fields : Array[Json] = []
  for f in g.fields {
    let key = f.ty.show_source()
    let at = match ty_index.get(key) {
      Some(i) => i
      None => {
        let i = types.length()
        types.push(ty_entry(f.ty))
        ty_index[key] = i
        i
      }
    }
    fields.push(
      Json::object({
        "name": Json::string(f.name),
        "ty": Json::number(at.to_double()),
        "doc": Json::string(f.doc.unwrap_or("")),
        "required": Json::boolean(false),
      }),
    )
  }
  // Every name this card answers, of one kind — the ones it compiled and the
  // ones its escape block answered. A host routes by this list, so a name
  // answered in Wax has to be in it for the same reason a refused one has to be
  // out: the manifest DESCRIBES the guest.
  let compiled : (@tscript.DeclKind) -> Array[String] = kind => {
    let word = @tscript.kind_word(kind)
    let out : Array[String] = []
    for _key, e in g.escapes {
      if e.kind == word {
        out.push(e.name)
      }
    }
    for d in decls {
      if d.kind == kind && is_compiled(g, d) && !g.escaped(word, d.name) {
        out.push(d.name)
      }
    }
    out
  }
  let docs : Array[Json] = []
  for d in decls {
    if d.doc != "" {
      docs.push(
        Json::object({
          "name": Json::string(d.name),
          "doc": Json::string(d.doc),
        }),
      )
    }
  }
  let view_defs : Array[Json] = views.views.map(v => {
    Json::object({
      "name": Json::string(v.name),
      "html": Json::string(v.source),
    })
  })
  Json::object({
    "name": Json::string(g.comp),
    "doc": Json::string(g.def.doc.unwrap_or("")),
    "keywords": Json::array([]),
    "category": Json::string(""),
    "messageDocs": Json::array(docs),
    "views": Json::array(view_defs),
    "types": Json::array(types),
    "fields": Json::array(fields),
    "receives": strings(compiled(DReceive)),
    "intents": strings(compiled(DIntent)),
    "methods": strings(
      compiled(DCompute) + compiled(DPred) + compiled(DInvariant),
    ),
    "whens": strings(compiled(DPred)),
    // The two the manifest had no key for, which is half of why a card using
    // `@enrich-with` used to lose its bindings in silence: the other half was
    // that nothing compiled them, and a host cannot route to a name it was
    // never told about.
    "enriches": strings(compiled(DEnrich)),
    "enrichScopes": strings(compiled(DEnrichScope)),
    "requests": Json::array([]),
    // `inits` stays empty. A `tutuca/init` block's field values are MoonBit
    // SOURCE — the generator that consumes them writes them into a `make` call
    // — and a manifest wants JSON. Projecting one into the other is a small
    // evaluator, which is a thing to add deliberately rather than in passing.
    "inits": Json::array([]),
    // `split_file` gives a file-level `<style>` to the FIRST component only, so
    // this is already the right value per component rather than a share of one.
    "style": Json::string(views.common_style),
  })
}

///|
/// Whether a declaration made it into the module.
///
/// The manifest DESCRIBES the guest, so a name the generator refused must not
/// appear in it: a host told a component answers `toggle` will route `toggle`
/// to it and get `unhandled` back, having skipped the field mutator that would
/// have worked.
fn is_compiled(g : Gen, d : @tscript.Decl) -> Bool {
  if d.kind is (DCompute | DPred | DInvariant | DEnrich | DEnrichScope) {
    return g.callables.get(d.name) is Some(_)
  }
  for r in g.refusals {
    if r.name == d.name && r.kind == @tscript.kind_word(d.kind) {
      return false
    }
  }
  true
}

///|
fn strings(xs : Array[String]) -> Json {
  Json::array(xs.map(x => Json::string(x)))
}

///|
/// The flat type-table entry a declared type projects to.
fn ty_entry(ty : @statedef.StateTy) -> Json {
  let (kind, name, members) = match ty {
    TBool => ("ty-bool", "", [])
    TInt(..) => ("ty-int", "", [])
    TFloat => ("ty-float", "", [])
    TText => ("ty-text", "", [])
    TList(_) => ("ty-list", "", [])
    TTuple(_) => ("ty-tuple", "", [])
    TOption(_) => ("ty-option", "", [])
    TOMap(_) => ("ty-omap", "", [])
    TSet => ("ty-set", "", [])
    TRecord(n) => ("ty-record", n, [])
    TEnum(n) => ("ty-enum", n, [])
    TVariant(n) => ("ty-variant", n, [])
    TFlags(n) => ("ty-flags", n, [])
    TComp(n) => ("ty-comp", n.unwrap_or(""), [])
    TAny => ("ty-any", "", [])
  }
  Json::object({
    "kind": Json::string(kind),
    "items": Json::array([]),
    "name": Json::string(name),
    "members": strings(members),
  })
}
