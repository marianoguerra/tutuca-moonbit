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
        // The fixtures checked against THIS component's schema. `file.init`
        // pairs each with the component it was checked against, which is what
        // keeps a two-component card's two sets apart.
        let mine = file.init.filter(p => p.0 == c.g.comp).map(p => p.1)
        let entry = component_json(c.g, c.decls, views, mine)
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
    "manifestVersion": Json::number(3),
    "apiVersion": Json::number(10),
    // Named after the ROOT rather than after the `name~` argument: a terminal
    // passes a file's basename and the browser passes the first template's
    // component, and the root is the one answer both of those agree with.
    "moduleName": Json::string(root.comp.to_lower() + "card"),
    "doc": Json::string(root.def.doc.unwrap_or("")),
    "version": Json::string("0.1.0"),
    "homepage": Json::string(""),
    "authors": Json::array([]),
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
  inits : Array[@statedef.InitState],
) -> Json {
  let fields : Array[Json] = []
  for f in g.fields {
    fields.push(
      Json::object({
        "name": Json::string(f.name),
        "ty": f.ty.to_json(),
        "doc": Json::string(f.doc.unwrap_or("")),
        "required": Json::boolean(false),
      }),
    )
  }
  let properties : Array[Json] = []
  for p in g.def.properties {
    properties.push(
      Json::object({
        "name": Json::string(p.name),
        "ty": p.ty.to_json(),
        "public": Json::boolean(p.public_),
        "writable": Json::boolean(p.writable),
        "doc": Json::string(p.doc.unwrap_or("")),
      }),
    )
  }
  // Built BEFORE the object literal below, because a protocol member's type is
  // interned into `types` and the literal writes that array out.
  let protocol_defs = g.def.protocols.map(protocol_json)
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
    "fields": Json::array(fields),
    "properties": Json::array(properties),
    // The `where` clauses, as the host's own vocabulary rather than as the
    // block's. A card's rules are COMPILED into the module and kept inside it;
    // a domain is not, and this is how it leaves. The host that mounts this
    // card holds the successor of every transition and every generated
    // mutator, and `@tutuca.first_broken_domain` is what it asks about them.
    "domains": @tutuca.domains_to_json(@info.domains_of(g.def)),
    "receives": strings(compiled(DReceive)),
    "intents": strings(compiled(DIntent)),
    "expressMessages": strings(g.def.express_message.map(m => m.name)),
    "expressIntents": strings(g.def.express_intent.map(m => m.name)),
    "implements": strings(g.def.implements),
    "protocols": Json::array(protocol_defs),
    "propertyBindings": bindings_json(g.def.property_bindings),
    "viewBindings": bindings_json(g.def.view_bindings),
    "provideBindings": bindings_json(g.def.provide_bindings),
    "lookupBindings": bindings_json(g.def.lookup_bindings),
    "methods": strings(
      compiled(DCompute) + compiled(DPred) + compiled(DInvariant),
    ),
    // An `invariant` is a `pred` with a role, and every USE a `pred` has it
    // has too: `@when="conserved"` filters a row with one exactly as
    // `@when="canPush"` does, and `dispatch.mbt` already gives it the loop's
    // three parameters. Listing only `DPred` here left the body compiled and
    // the name unroutable — the MoonBit backend folds both, and two backends
    // that disagree about which names a view may filter with are two answers
    // to one question.
    "whens": strings(compiled(DPred) + compiled(DInvariant)),
    // The two the manifest had no key for: a host cannot route to a name it
    // was never told about.
    "enriches": strings(compiled(DEnrich)),
    "enrichScopes": strings(compiled(DEnrichScope)),
    // A card serves no intent yet: the guest ABI's `serve-intent` is a stub
    // for one, so there is nothing a name here could reach. The KEY is the one
    // the host reads (`serves`) rather than a second spelling of it, so the
    // day a card can serve one, saying so is all it takes.
    "serves": Json::array([]),
    // The wiring, projected from the state block's `provide { … }` /
    // `lookup { … }` sections. The expressions go out as SOURCE TEXT: the host
    // parses and judges them exactly as it does a host component's, so a card
    // gets dynamic bindings without the guest ABI learning anything.
    "provide": Json::array(
      g.def.provide.map(pd => {
        Json::object({
          "name": Json::string(pd.name),
          "source": Json::string(pd.source),
        })
      }),
    ),
    "lookup": Json::array(
      g.def.lookup.map(ld => {
        Json::object({
          "name": Json::string(ld.name),
          "default": Json::string(ld.default.unwrap_or("")),
        })
      }),
    ),
    // The card's `<script type="tutuca/init">` fixtures.
    //
    // `InitState` keeps the values, so there is nothing to project.
    //
    // Emitting them is what makes a card's fixtures reachable at all. A scene
    // naming one — `"init": "fresh"` — reads this list to resolve the key.
    "inits": Json::array(
      inits.map(st => {
        Json::object({
          "name": Json::string(st.name),
          // `argsJson`, a STRING, because that is what `parse_inits` reads: the
          // manifest crosses the JS bridge as JSON and a nested object of values
          // would have to be told apart from the rest of it.
          "argsJson": Json::string(
            {
              let m : Map[String, Json] = Map([])
              for k, v in st.args {
                m[k] = v.to_json()
              }
              Json::object(m).stringify()
            },
          ),
          "doc": Json::string(st.doc),
          "view": Json::string(st.view),
          "tags": Json::array(st.tags.map(Json::string)),
          "default": Json::boolean(st.default_),
          // Through untouched, as the wire format's own note says: what a
          // fixture's steps MEAN belongs to whoever runs one.
          "driveJson": Json::string(st.drive.stringify()),
          "intentsJson": Json::string(st.intents.stringify()),
        })
      }),
    ),
    // `split_file` gives a file-level `<style>` to the FIRST component only, so
    // this is already the right value per component rather than a share of one.
    "style": Json::string(views.common_style),
  })
}

///|
/// One protocol's entry, with `intern` the owning component's type table.
///
/// The properties are OBJECTS, spelled exactly as a component's are, and that
/// is not decoration: `DynProtocolDef` carries a `DynPropertyDef` per member
/// and the host resolves its `ty` through the same table to build a
/// `PropertyInfo`. A list of bare names would drop the type the declaration
/// wrote down, and the host that reads one has no way to ask for it back.
///
/// The other member lists ARE names, because that is all they have: a message
/// or a view is named by a protocol and described by whoever implements it.
fn protocol_json(p : @statedef.ProtocolDef) -> Json {
  Json::object({
    "id": Json::string(p.id),
    "handleMessages": strings(p.handle_message.map(m => m.name)),
    "handleIntents": strings(p.handle_intent.map(m => m.name)),
    "expressMessages": strings(p.express_message.map(m => m.name)),
    "expressIntents": strings(p.express_intent.map(m => m.name)),
    "properties": Json::array(
      p.properties.map(x => {
        Json::object({
          "name": Json::string(x.name),
          "ty": x.ty.to_json(),
          // A protocol member is public by definition: it is what the protocol
          // promises, and a private one would promise nothing.
          "public": Json::boolean(true),
          "writable": Json::boolean(x.writable),
          "doc": Json::string(x.doc.unwrap_or("")),
        })
      }),
    ),
    "views": strings(p.views),
    "provides": strings(p.provides.map(x => x.name)),
    "lookups": strings(p.lookups.map(x => x.name)),
  })
}

///|
fn bindings_json(xs : Array[@statedef.ProtocolBinding]) -> Json {
  Json::array(
    xs.map(b => {
      Json::object({
        "protocolId": Json::string(b.protocol_id),
        "member": Json::string(b.member_name),
        "source": Json::string(b.source),
      })
    }),
  )
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
