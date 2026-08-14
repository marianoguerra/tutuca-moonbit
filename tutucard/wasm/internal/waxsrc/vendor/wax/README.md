# Vendored Wax standard library

Copied verbatim from `marianoguerra/wax`, the `data` profile:

```sh
tools/vendor-stdlib.sh cardwasm/vendor/wax data
```

| | |
|---|---|
| upstream | https://github.com/marianoguerra/wax-mb |
| commit | `380aeb6c77ddf82d7c2021ca642f3a14db58f307` (`v0.2.0-2-g380aeb6`) |
| profile | `data` — all seven files |

**Do not edit these files.** Change them upstream and re-vendor; the embedded
copy the generator reads is produced from this directory by
`cmd/dev -- vendor-wax-stdlib`, and the drift check compares the two.

## Why the whole profile

Wax has no source import system, so there is no way to take a part of this.
`immutable_value.wax` calls `jv_record_equal` / `jv_record_hash`, which are
defined in `record.wax`; `record.wax` builds `jv_record_value`, whose type is
declared in `immutable_value.wax`'s `rec` block. The two are one unit, and that
unit reaches the vector, the HAMT, the set and utf8. The compiler never constructs an unordered `jv_map` or `jv_set`: tutuca's own
maps are insertion ordered, so it uses `jv_ordered_map` and `jv_ordered_set`
throughout. The unordered pair is not separable from the value hierarchy that
names them.

## Concatenation order

Fixed, and load-bearing: Wax resolves in one pass over one module, so a file
must follow everything it names. From the upstream `stdlib/README.md`:

1. `hashing.wax`
2. `persistent_hash_map.wax`
3. `persistent_hash_set.wax`
4. `persistent_vector.wax`
5. `utf8.wax`
6. `immutable_value.wax`
7. `record.wax`

Then the card runtime, then the generated card.

## Reserved prefixes

Every name in a Wax module is global — there is no privacy and no namespacing.
These prefixes belong to the stdlib and nothing cardwasm emits may use them:

`wax_` `phm_` `phmt_` `phs_` `phst_` `pv_` `pvt_` `utf8_` `jv_` `jvt_` `st_`

cardwasm's own runtime uses `tc_`, and every name taken from a card is prefixed
too, so a card declaring `compute jv_hash` cannot collide with the stdlib.
