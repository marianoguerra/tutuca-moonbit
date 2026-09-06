// Generated from `rt.wap` by `node tgc/rt/embed.mjs`. DO NOT EDIT.
//
// Change `rt.wap`, rerun the script, commit both halves.

///|
pub fn source() -> String {
  let src =
    #|
    #|module rt
    #|
    #|import tgabi
    #|
    #|import was "tgc/abi/sys.mbt":
    #|  fn tgc_next_id() -> i64
    #|
    #|type bytes = [u8]
    #|type vals = [tgabi.tg_val?]
    #|type entries = [tgabi.tg_entry?]
    #|
    #|export "next_id" fn next_id() -> i64:
    #|  tgc_next_id()
    #|
    #|export "get_field" fn get_field(inst :: tgabi.tg_inst, name :: tgabi.tg_bytes) -> tgabi.tg_val?:
    #|  inst.vt.get(inst, name)
    #|
    #|export "call_op" fn call_op(inst :: tgabi.tg_inst, op :: i32, name :: tgabi.tg_bytes,
    #|                            args :: tgabi.tg_vals, v :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  inst.vt.call(inst, op, name, args, v)
    #|
    #|export "cross_get" fn cross_get(vt_from :: tgabi.tg_inst, target :: tgabi.tg_inst,
    #|                                name :: tgabi.tg_bytes) -> tgabi.tg_val?:
    #|  vt_from.vt.get(target, name)
    #|
    #|export "str_eq" fn str_eq(a :: tgabi.tg_bytes, b :: tgabi.tg_bytes) -> i32:
    #|  let n = a.len()
    #|  if n != b.len():
    #|    return 0
    #|  for i in 0 ..< n:
    #|    if a[i] != b[i]:
    #|      return 0
    #|  1
    #|
    #|fn bytes_concat(a :: tgabi.tg_bytes, b :: tgabi.tg_bytes) -> tgabi.tg_bytes:
    #|  let out = bytes[0 ** (a.len() + b.len())]
    #|  out.copy(0, a, 0, a.len())
    #|  out.copy(a.len(), b, 0, b.len())
    #|  out
    #|
    #|const no_bytes_v :: tgabi.tg_bytes = ""
    #|
    #|fn no_bytes() -> tgabi.tg_bytes:
    #|  no_bytes_v
    #|
    #|const the_null :: tgabi.tg_val = tgabi.tg_val{ kind: 0 }
    #|
    #|export "mk_null" fn mk_null() -> tgabi.tg_val:
    #|  the_null
    #|
    #|export "mk_bool" fn mk_bool(b :: i32) -> tgabi.tg_val:
    #|  tgabi.tg_bool{ kind: 1, value: b }
    #|
    #|export "mk_num" fn mk_num(n :: f64) -> tgabi.tg_val:
    #|  tgabi.tg_num{ kind: 2, value: n }
    #|
    #|export "mk_int" fn mk_int(i :: i64) -> tgabi.tg_val:
    #|  tgabi.tg_int{ kind: 3, value: i }
    #|
    #|export "mk_str" fn mk_str(b :: tgabi.tg_bytes) -> tgabi.tg_val:
    #|  tgabi.tg_str{ kind: 4, value: b }
    #|
    #|export "mk_bin" fn mk_bin(b :: tgabi.tg_bytes) -> tgabi.tg_val:
    #|  tgabi.tg_bin{ kind: 5, value: b }
    #|
    #|export "mk_instant" fn mk_instant(secs :: i64, nanos :: i32) -> tgabi.tg_val:
    #|  tgabi.tg_instant{ kind: 6, secs: secs, nanos: nanos }
    #|
    #|export "mk_list" fn mk_list(items :: tgabi.tg_vals) -> tgabi.tg_val:
    #|  tgabi.tg_list{ kind: 7, items: items, count: items.len() }
    #|
    #|export "mk_map" fn mk_map(es :: tgabi.tg_entries) -> tgabi.tg_val:
    #|  tgabi.tg_map{ kind: 8, entries: es, count: es.len() }
    #|
    #|export "mk_comp" fn mk_comp(inst :: tgabi.tg_inst) -> tgabi.tg_val:
    #|  tgabi.tg_comp{ kind: 10, value: inst }
    #|
    #|export "vals_new" fn vals_new(n :: i32) -> tgabi.tg_vals:
    #|  vals[null ** n]
    #|
    #|export "vals_set" fn vals_set(a :: tgabi.tg_vals, i :: i32, v :: tgabi.tg_val?):
    #|  a[i] = v
    #|
    #|export "entries_new" fn entries_new(n :: i32) -> tgabi.tg_entries:
    #|  entries[null ** n]
    #|
    #|export "entries_set" fn entries_set(a :: tgabi.tg_entries, i :: i32,
    #|                                    k :: tgabi.tg_bytes, v :: tgabi.tg_val?):
    #|  a[i] = tgabi.tg_entry{ key: k, value: v }
    #|
    #|const no_args_v :: tgabi.tg_vals = vals[]
    #|
    #|export "no_args" fn no_args() -> tgabi.tg_vals:
    #|  no_args_v
    #|
    #|export "kind_of" fn kind_of(v :: tgabi.tg_val) -> i32:
    #|  v.kind
    #|
    #|export "as_bool" fn as_bool(v :: tgabi.tg_val) -> i32:
    #|  (v as tgabi.tg_bool).value
    #|
    #|export "as_num" fn as_num(v :: tgabi.tg_val) -> f64:
    #|  (v as tgabi.tg_num).value
    #|
    #|export "as_int" fn as_int(v :: tgabi.tg_val) -> i64:
    #|  (v as tgabi.tg_int).value
    #|
    #|export "as_str" fn as_str(v :: tgabi.tg_val) -> tgabi.tg_bytes:
    #|  (v as tgabi.tg_str).value
    #|
    #|export "as_bin" fn as_bin(v :: tgabi.tg_val) -> tgabi.tg_bytes:
    #|  (v as tgabi.tg_bin).value
    #|
    #|export "instant_secs" fn instant_secs(v :: tgabi.tg_val) -> i64:
    #|  (v as tgabi.tg_instant).secs
    #|
    #|export "instant_nanos" fn instant_nanos(v :: tgabi.tg_val) -> i32:
    #|  (v as tgabi.tg_instant).nanos
    #|
    #|export "list_len" fn list_len(v :: tgabi.tg_val) -> i32:
    #|  (v as tgabi.tg_list).count
    #|
    #|export "list_at" fn list_at(v :: tgabi.tg_val, i :: i32) -> tgabi.tg_val?:
    #|  (v as tgabi.tg_list).items[i]
    #|
    #|export "map_len" fn map_len(v :: tgabi.tg_val) -> i32:
    #|  (v as tgabi.tg_map).count
    #|
    #|export "map_key" fn map_key(v :: tgabi.tg_val, i :: i32) -> tgabi.tg_bytes:
    #|  (v as tgabi.tg_map).entries[i]!.key
    #|
    #|export "map_val" fn map_val(v :: tgabi.tg_val, i :: i32) -> tgabi.tg_val?:
    #|  (v as tgabi.tg_map).entries[i]!.value
    #|
    #|export "as_inst" fn as_inst(v :: tgabi.tg_val) -> tgabi.tg_inst:
    #|  (v as tgabi.tg_comp).value
    #|
    #|export "inst_desc" fn inst_desc(i :: tgabi.tg_inst) -> tgabi.tg_val:
    #|  i.desc
    #|
    #|export "inst_id" fn inst_id(i :: tgabi.tg_inst) -> i64:
    #|  i.id
    #|
    #|export "bytes_len" fn bytes_len(b :: tgabi.tg_bytes) -> i32:
    #|  b.len()
    #|
    #|export "bytes_at" fn bytes_at(b :: tgabi.tg_bytes, i :: i32) -> i32:
    #|  b[i]
    #|
    #|export "bytes_new" fn bytes_new(n :: i32) -> tgabi.tg_bytes:
    #|  bytes[0 ** n]
    #|
    #|export "bytes_set" fn bytes_set(b :: tgabi.tg_bytes, i :: i32, x :: i32):
    #|  b[i] = x
    #|
    #|fn size(v :: tgabi.tg_val) -> i32:
    #|  if v.kind == 7:
    #|    return (v as tgabi.tg_list).count
    #|  if v.kind == 8:
    #|    return (v as tgabi.tg_map).count
    #|  if v.kind == 4:
    #|    return (v as tgabi.tg_str).value.len()
    #|  -1
    #|
    #|export "truthy" fn truthy(v :: tgabi.tg_val?) -> i32:
    #|  if v == null:
    #|    return 0
    #|  let x = v!
    #|  if x.kind == 0:
    #|    return 0
    #|  if x.kind == 1:
    #|    return (x as tgabi.tg_bool).value
    #|  if x.kind == 2:
    #|    let n = (x as tgabi.tg_num).value
    #|    if n == 0.0:
    #|      return 0
    #|    if n != n:
    #|      return 0
    #|    return 1
    #|  if x.kind == 3:
    #|    if (x as tgabi.tg_int).value == 0:
    #|      return 0
    #|    return 1
    #|  if x.kind == 4:
    #|    if (x as tgabi.tg_str).value.len() == 0:
    #|      return 0
    #|    return 1
    #|  1
    #|
    #|export "pred_truthy" fn pred_truthy(v :: tgabi.tg_val?) -> i32:
    #|  if v == null:
    #|    return 0
    #|  let n = size(v!)
    #|  if n >= 0:
    #|    if n == 0:
    #|      return 0
    #|    return 1
    #|  truthy(v)
    #|
    #|export "val_eq" fn val_eq(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> i32:
    #|  if a == null:
    #|    if b == null:
    #|      return 1
    #|    return 0
    #|  if b == null:
    #|    return 0
    #|  let x = a!
    #|  let y = b!
    #|  if x.kind != y.kind:
    #|    return 0
    #|  if x.kind == 0:
    #|    return 1
    #|  if x.kind == 1:
    #|    if (x as tgabi.tg_bool).value == (y as tgabi.tg_bool).value:
    #|      return 1
    #|    return 0
    #|  if x.kind == 2:
    #|    if (x as tgabi.tg_num).value == (y as tgabi.tg_num).value:
    #|      return 1
    #|    return 0
    #|  if x.kind == 3:
    #|    if (x as tgabi.tg_int).value == (y as tgabi.tg_int).value:
    #|      return 1
    #|    return 0
    #|  if x.kind == 4:
    #|    return str_eq((x as tgabi.tg_str).value, (y as tgabi.tg_str).value)
    #|  if x.kind == 5:
    #|    return str_eq((x as tgabi.tg_bin).value, (y as tgabi.tg_bin).value)
    #|  if x.kind == 6:
    #|    let p = x as tgabi.tg_instant
    #|    let q = y as tgabi.tg_instant
    #|    if p.secs != q.secs:
    #|      return 0
    #|    if p.nanos != q.nanos:
    #|      return 0
    #|    return 1
    #|  if x.kind == 7:
    #|    let p = x as tgabi.tg_list
    #|    let q = y as tgabi.tg_list
    #|    if p.count != q.count:
    #|      return 0
    #|    for i in 0 ..< p.count:
    #|      if val_eq(p.items[i], q.items[i]) == 0:
    #|        return 0
    #|    return 1
    #|  if x.kind == 8:
    #|    let p = x as tgabi.tg_map
    #|    let q = y as tgabi.tg_map
    #|    if p.count != q.count:
    #|      return 0
    #|    for i in 0 ..< p.count:
    #|      let pe = p.entries[i]!
    #|      let found = map_find(q, pe.key)
    #|      if found < 0:
    #|        return 0
    #|      if val_eq(pe.value, q.entries[found]!.value) == 0:
    #|        return 0
    #|    return 1
    #|  if x.kind == 10:
    #|    if (x as tgabi.tg_comp).value.id == (y as tgabi.tg_comp).value.id:
    #|      return 1
    #|    return 0
    #|  0
    #|
    #|fn map_find(m :: tgabi.tg_map, key :: tgabi.tg_bytes) -> i32:
    #|  for i in 0 ..< m.count:
    #|    if str_eq(m.entries[i]!.key, key) != 0:
    #|      return i
    #|  -1
    #|
    #|fn as_double(v :: tgabi.tg_val?) -> (bool, f64):
    #|  if v == null:
    #|    return (false, 0.0)
    #|  let x = v!
    #|  if x.kind == 2:
    #|    return (true, (x as tgabi.tg_num).value)
    #|  if x.kind == 3:
    #|    return (true, (x as tgabi.tg_int).value as f64_s)
    #|  (false, 0.0)
    #|
    #|fn two_doubles(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> (bool, f64, f64):
    #|  let (ok_a, x :: f64) = as_double(a)
    #|  if !ok_a:
    #|    return (false, 0.0, 0.0)
    #|  let (ok_b, y :: f64) = as_double(b)
    #|  if !ok_b:
    #|    return (false, 0.0, 0.0)
    #|  (true, x, y)
    #|
    #|export "op_add" fn op_add(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let (ok, x :: f64, y :: f64) = two_doubles(a, b)
    #|  if !ok:
    #|    return null
    #|  mk_num(x + y)
    #|
    #|export "op_sub" fn op_sub(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let (ok, x :: f64, y :: f64) = two_doubles(a, b)
    #|  if !ok:
    #|    return null
    #|  mk_num(x - y)
    #|
    #|export "op_mul" fn op_mul(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let (ok, x :: f64, y :: f64) = two_doubles(a, b)
    #|  if !ok:
    #|    return null
    #|  mk_num(x * y)
    #|
    #|export "op_div" fn op_div(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let (ok, x :: f64, y :: f64) = two_doubles(a, b)
    #|  if !ok:
    #|    return null
    #|  mk_num(x / y)
    #|
    #|export "op_mod" fn op_mod(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let (ok, x :: f64, y :: f64) = two_doubles(a, b)
    #|  if !ok:
    #|    return null
    #|  if y == 0.0:
    #|    return mk_num(x / y)
    #|  let q = (x / y) as i64_s
    #|  mk_num(x - q as f64_s * y)
    #|
    #|export "op_neg" fn op_neg(a :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let (ok, x :: f64) = as_double(a)
    #|  if !ok:
    #|    return null
    #|  mk_num(0.0 - x)
    #|
    #|export "op_lt" fn op_lt(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let (ok, x :: f64, y :: f64) = two_doubles(a, b)
    #|  if !ok:
    #|    return null
    #|  if x < y:
    #|    return mk_bool(1)
    #|  mk_bool(0)
    #|
    #|export "op_le" fn op_le(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let (ok, x :: f64, y :: f64) = two_doubles(a, b)
    #|  if !ok:
    #|    return null
    #|  if x <= y:
    #|    return mk_bool(1)
    #|  mk_bool(0)
    #|
    #|export "op_gt" fn op_gt(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let (ok, x :: f64, y :: f64) = two_doubles(a, b)
    #|  if !ok:
    #|    return null
    #|  if x > y:
    #|    return mk_bool(1)
    #|  mk_bool(0)
    #|
    #|export "op_ge" fn op_ge(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let (ok, x :: f64, y :: f64) = two_doubles(a, b)
    #|  if !ok:
    #|    return null
    #|  if x >= y:
    #|    return mk_bool(1)
    #|  mk_bool(0)
    #|
    #|export "op_is" fn op_is(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if a == null:
    #|    return null
    #|  if b == null:
    #|    return null
    #|  mk_bool(val_eq(a, b))
    #|
    #|export "op_is_not" fn op_is_not(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if a == null:
    #|    return null
    #|  if b == null:
    #|    return null
    #|  if val_eq(a, b) != 0:
    #|    return mk_bool(0)
    #|  mk_bool(1)
    #|
    #|export "trunc" fn trunc(v :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let (ok, x :: f64) = as_double(v)
    #|  if !ok:
    #|    return null
    #|  mk_num((x as i64_s) as f64_s)
    #|
    #|fn digits(n :: i64, out :: tgabi.tg_bytes, at :: i32) -> i32:
    #|  if n == 0:
    #|    out[at] = 48
    #|    return at + 1
    #|  let tmp = bytes[0 ** 20]
    #|  var len :: i32 = 0
    #|  var x :: i64 = n
    #|  while x > 0:
    #|    tmp[len] = (x % 10) as i32 + 48
    #|    x = x / 10
    #|    len += 1
    #|  for i in 0 ..< len:
    #|    out[at + i] = tmp[len - 1 - i]
    #|  at + len
    #|
    #|fn num_text(n :: f64) -> tgabi.tg_bytes:
    #|  if n != n:
    #|    return "NaN"
    #|  var neg :: i32 = 0
    #|  var v :: f64 = n
    #|  if v < 0.0:
    #|    neg = 1
    #|    v = 0.0 - v
    #|  if v >= 9223372036854775000.0:
    #|    if neg != 0:
    #|      return "-Infinity"
    #|    return "Infinity"
    #|  var whole :: i64 = v as i64_s
    #|  let frac = v - whole as f64_s
    #|  var scaled :: i64 = (frac * 1000000.0 + 0.5) as i64_s
    #|  if scaled >= 1000000:
    #|    whole += 1
    #|    scaled = 0
    #|  let out_digits = bytes[0 ** 40]
    #|  var at :: i32 = 0
    #|  if neg != 0:
    #|    out_digits[0] = 45
    #|    at = 1
    #|  at = digits(whole, out_digits, at)
    #|  if scaled > 0:
    #|    let f = bytes[0 ** 6]
    #|    var i :: i32 = 5
    #|    var s :: i64 = scaled
    #|    while i >= 0:
    #|      f[i] = (s % 10) as i32 + 48
    #|      s = s / 10
    #|      i -= 1
    #|    var last :: i32 = 5
    #|    while last >= 0:
    #|      if f[last] != 48:
    #|        break
    #|      last -= 1
    #|    out_digits[at] = 46
    #|    at += 1
    #|    var j :: i32 = 0
    #|    while j <= last:
    #|      out_digits[at] = f[j]
    #|      at += 1
    #|      j += 1
    #|  let out = bytes[0 ** at]
    #|  out.copy(0, out_digits, 0, at)
    #|  out
    #|
    #|export "display" fn display(v :: tgabi.tg_val?) -> tgabi.tg_bytes:
    #|  if v == null:
    #|    return no_bytes()
    #|  let x = v!
    #|  if x.kind == 0:
    #|    return no_bytes()
    #|  if x.kind == 1:
    #|    if (x as tgabi.tg_bool).value != 0:
    #|      return "true"
    #|    return "false"
    #|  if x.kind == 2:
    #|    return num_text((x as tgabi.tg_num).value)
    #|  if x.kind == 3:
    #|    return num_text((x as tgabi.tg_int).value as f64_s)
    #|  if x.kind == 4:
    #|    return (x as tgabi.tg_str).value
    #|  no_bytes()
    #|
    #|export "concat" fn concat(a :: tgabi.tg_bytes, b :: tgabi.tg_bytes) -> tgabi.tg_bytes:
    #|  bytes_concat(a, b)
    #|
    #|export "b_empty" fn b_empty(v :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if v == null:
    #|    return null
    #|  let x = v!
    #|  if x.kind == 0:
    #|    return mk_bool(1)
    #|  if size(x) == 0:
    #|    return mk_bool(1)
    #|  mk_bool(0)
    #|
    #|export "b_truthy" fn b_truthy(v :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if v == null:
    #|    return null
    #|  mk_bool(pred_truthy(v))
    #|
    #|export "b_falsy" fn b_falsy(v :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if v == null:
    #|    return null
    #|  if pred_truthy(v) != 0:
    #|    return mk_bool(0)
    #|  mk_bool(1)
    #|
    #|export "b_null" fn b_null(v :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if v == null:
    #|    return null
    #|  if v!.kind == 0:
    #|    return mk_bool(1)
    #|  mk_bool(0)
    #|
    #|export "b_not" fn b_not(v :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if v == null:
    #|    return null
    #|  if truthy(v) != 0:
    #|    return mk_bool(0)
    #|  mk_bool(1)
    #|
    #|export "b_len" fn b_len(v :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if v == null:
    #|    return null
    #|  let n = size(v!)
    #|  if n < 0:
    #|    return null
    #|  mk_num(n as f64_s)
    #|
    #|export "b_has" fn b_has(coll :: tgabi.tg_val?, x :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if coll == null:
    #|    return null
    #|  let c = coll!
    #|  if c.kind == 8:
    #|    if map_find(c as tgabi.tg_map, display(x)) >= 0:
    #|      return mk_bool(1)
    #|    return mk_bool(0)
    #|  if c.kind == 7:
    #|    let l = c as tgabi.tg_list
    #|    for i in 0 ..< l.count:
    #|      if val_eq(l.items[i], x) != 0:
    #|        return mk_bool(1)
    #|    return mk_bool(0)
    #|  null
    #|
    #|export "b_contains" fn b_contains(hay :: tgabi.tg_val?, needle :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if hay == null:
    #|    return null
    #|  if needle == null:
    #|    return null
    #|  if hay!.kind != 4:
    #|    return null
    #|  if needle!.kind != 4:
    #|    return null
    #|  let h = (hay! as tgabi.tg_str).value
    #|  let n = (needle! as tgabi.tg_str).value
    #|  if n.len() == 0:
    #|    return mk_bool(1)
    #|  if n.len() > h.len():
    #|    return mk_bool(0)
    #|  var i :: i32 = 0
    #|  var found :: i32 = 0
    #|  while i <= h.len() - n.len():
    #|    var j :: i32 = 0
    #|    var hit :: i32 = 1
    #|    while j < n.len():
    #|      if h[i + j] != n[j]:
    #|        hit = 0
    #|        break
    #|      j += 1
    #|    if hit != 0:
    #|      found = 1
    #|      break
    #|    i += 1
    #|  mk_bool(found)
    #|
    #|export "b_min" fn b_min(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let (ok, x :: f64, y :: f64) = two_doubles(a, b)
    #|  if !ok:
    #|    return null
    #|  if x < y:
    #|    return mk_num(x)
    #|  mk_num(y)
    #|
    #|export "b_max" fn b_max(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let (ok, x :: f64, y :: f64) = two_doubles(a, b)
    #|  if !ok:
    #|    return null
    #|  if x > y:
    #|    return mk_num(x)
    #|  mk_num(y)
    #|
    #|export "b_clamp" fn b_clamp(v :: tgabi.tg_val?, lo :: tgabi.tg_val?, hi :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let (ok_v, x :: f64) = as_double(v)
    #|  if !ok_v:
    #|    return null
    #|  let (ok_l, l :: f64) = as_double(lo)
    #|  if !ok_l:
    #|    return null
    #|  let (ok_h, h :: f64) = as_double(hi)
    #|  if !ok_h:
    #|    return null
    #|  if h < l:
    #|    return mk_num(l)
    #|  if x < l:
    #|    return mk_num(l)
    #|  if x > h:
    #|    return mk_num(h)
    #|  mk_num(x)
    #|
    #|export "b_str" fn b_str(v :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if v == null:
    #|    return null
    #|  mk_str(display(v))
    #|
    #|export "b_num" fn b_num(v :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if v == null:
    #|    return null
    #|  let x = v!
    #|  if x.kind == 2:
    #|    return x
    #|  if x.kind == 3:
    #|    return mk_num((x as tgabi.tg_int).value as f64_s)
    #|  if x.kind == 4:
    #|    return parse_num((x as tgabi.tg_str).value)
    #|  null
    #|
    #|export "b_int" fn b_int(v :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let n = b_num(v)
    #|  if n == null:
    #|    return null
    #|  let (ok, d :: f64) = as_double(n)
    #|  if !ok:
    #|    return null
    #|  mk_num((d as i64_s) as f64_s)
    #|
    #|fn parse_num(s :: tgabi.tg_bytes) -> tgabi.tg_val?:
    #|  let n = s.len()
    #|  if n == 0:
    #|    return null
    #|  var i :: i32 = 0
    #|  var neg :: i32 = 0
    #|  let c0 = s[0]
    #|  if c0 == 43:
    #|    i = 1
    #|  if c0 == 45:
    #|    neg = 1
    #|    i = 1
    #|  var seen :: i32 = 0
    #|  var acc :: f64 = 0.0
    #|  while i < n:
    #|    let c = s[i]
    #|    if c < 48:
    #|      break
    #|    if c > 57:
    #|      break
    #|    acc = acc * 10.0 + (c - 48) as f64_s
    #|    seen += 1
    #|    i += 1
    #|  if i < n:
    #|    if s[i] == 46:
    #|      i += 1
    #|      var scale :: f64 = 0.1
    #|      while i < n:
    #|        let c = s[i]
    #|        if c < 48:
    #|          break
    #|        if c > 57:
    #|          break
    #|        acc = acc + (c - 48) as f64_s * scale
    #|        scale = scale * 0.1
    #|        seen += 1
    #|        i += 1
    #|  if seen == 0:
    #|    return null
    #|  if i < n:
    #|    let c = s[i]
    #|    if c != 101:
    #|      if c != 69:
    #|        return null
    #|    i += 1
    #|    var eneg :: i32 = 0
    #|    if i < n:
    #|      let sc = s[i]
    #|      if sc == 43:
    #|        i += 1
    #|      if sc == 45:
    #|        eneg = 1
    #|        i += 1
    #|    var e :: i32 = 0
    #|    var edigits :: i32 = 0
    #|    while i < n:
    #|      let c2 = s[i]
    #|      if c2 < 48:
    #|        return null
    #|      if c2 > 57:
    #|        return null
    #|      e = e * 10 + (c2 - 48)
    #|      edigits += 1
    #|      i += 1
    #|    if edigits == 0:
    #|      return null
    #|    var k :: i32 = 0
    #|    while k < e:
    #|      if eneg != 0:
    #|        acc = acc / 10.0
    #|      if eneg == 0:
    #|        acc = acc * 10.0
    #|      k += 1
    #|  if i != n:
    #|    return null
    #|  if neg != 0:
    #|    return mk_num(0.0 - acc)
    #|  mk_num(acc)
    #|
    #|fn case_fold(v :: tgabi.tg_val?, upper :: i32) -> tgabi.tg_val?:
    #|  if v == null:
    #|    return null
    #|  if v!.kind != 4:
    #|    return null
    #|  let s = (v! as tgabi.tg_str).value
    #|  let out = bytes[0 ** s.len()]
    #|  for i in 0 ..< s.len():
    #|    var c :: i32 = s[i]
    #|    if upper != 0:
    #|      if c >= 97:
    #|        if c <= 122:
    #|          c = c - 32
    #|    if upper == 0:
    #|      if c >= 65:
    #|        if c <= 90:
    #|          c = c + 32
    #|    out[i] = c
    #|  mk_str(out)
    #|
    #|export "b_lower" fn b_lower(v :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  case_fold(v, 0)
    #|
    #|export "b_upper" fn b_upper(v :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  case_fold(v, 1)
    #|
    #|fn is_space(c :: i32) -> i32:
    #|  if c == 32:
    #|    return 1
    #|  if c == 9:
    #|    return 1
    #|  if c == 10:
    #|    return 1
    #|  if c == 13:
    #|    return 1
    #|  0
    #|
    #|export "b_trim" fn b_trim(v :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if v == null:
    #|    return null
    #|  if v!.kind != 4:
    #|    return null
    #|  let s = (v! as tgabi.tg_str).value
    #|  var start :: i32 = 0
    #|  var end :: i32 = s.len()
    #|  while start < end:
    #|    if is_space(s[start]) == 0:
    #|      break
    #|    start += 1
    #|  while end > start:
    #|    if is_space(s[end - 1]) == 0:
    #|      break
    #|    end -= 1
    #|  let out = bytes[0 ** (end - start)]
    #|  out.copy(0, s, start, end - start)
    #|  mk_str(out)
    #|
    #|fn list_of(v :: tgabi.tg_val?) -> tgabi.tg_list?:
    #|  if v == null:
    #|    return null
    #|  if v!.kind != 7:
    #|    return null
    #|  v! as tgabi.tg_list
    #|
    #|fn map_of(v :: tgabi.tg_val?) -> tgabi.tg_map?:
    #|  if v == null:
    #|    return null
    #|  if v!.kind != 8:
    #|    return null
    #|  v! as tgabi.tg_map
    #|
    #|fn vals_copy(src :: tgabi.tg_vals, n :: i32, extra :: i32) -> tgabi.tg_vals:
    #|  let out = vals[null ** (n + extra)]
    #|  for i in 0 ..< n:
    #|    out[i] = src[i]
    #|  out
    #|
    #|fn index_of(at :: tgabi.tg_val?) -> (bool, i32):
    #|  let (ok, n :: f64) = as_double(at)
    #|  if !ok:
    #|    return (false, 0)
    #|  (true, n as i32_s)
    #|
    #|export "coll_push" fn coll_push(v :: tgabi.tg_val?, x :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let l = list_of(v)
    #|  if l == null:
    #|    return null
    #|  let src = l!
    #|  let out = vals_copy(src.items, src.count, 1)
    #|  out[src.count] = x
    #|  mk_list(out)
    #|
    #|export "coll_insert_at" fn coll_insert_at(v :: tgabi.tg_val?, at :: tgabi.tg_val?,
    #|                                          x :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if v != null:
    #|    if v!.kind == 8:
    #|      return map_put(v, at, x)
    #|  let l = list_of(v)
    #|  if l == null:
    #|    return null
    #|  let src = l!
    #|  let (ok, i :: i32) = index_of(at)
    #|  if !ok:
    #|    return null
    #|  if i < 0:
    #|    return null
    #|  if i > src.count:
    #|    return null
    #|  let out = vals[null ** (src.count + 1)]
    #|  var k :: i32 = 0
    #|  while k < i:
    #|    out[k] = src.items[k]
    #|    k += 1
    #|  out[i] = x
    #|  while k < src.count:
    #|    out[k + 1] = src.items[k]
    #|    k += 1
    #|  mk_list(out)
    #|
    #|export "coll_set_at" fn coll_set_at(v :: tgabi.tg_val?, at :: tgabi.tg_val?,
    #|                                    x :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if v != null:
    #|    if v!.kind == 8:
    #|      return map_put(v, at, x)
    #|  let l = list_of(v)
    #|  if l == null:
    #|    return null
    #|  let src = l!
    #|  let (ok, i :: i32) = index_of(at)
    #|  if !ok:
    #|    return null
    #|  if i < 0:
    #|    return null
    #|  if i >= src.count:
    #|    return null
    #|  let out = vals_copy(src.items, src.count, 0)
    #|  out[i] = x
    #|  mk_list(out)
    #|
    #|export "coll_delete_at" fn coll_delete_at(v :: tgabi.tg_val?, at :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if v != null:
    #|    if v!.kind == 8:
    #|      return map_del(v, at)
    #|  let l = list_of(v)
    #|  if l == null:
    #|    return null
    #|  let src = l!
    #|  let (ok, i :: i32) = index_of(at)
    #|  if !ok:
    #|    return null
    #|  if i < 0:
    #|    return null
    #|  if i >= src.count:
    #|    return null
    #|  let out = vals[null ** (src.count - 1)]
    #|  var k :: i32 = 0
    #|  while k < i:
    #|    out[k] = src.items[k]
    #|    k += 1
    #|  k = i + 1
    #|  while k < src.count:
    #|    out[k - 1] = src.items[k]
    #|    k += 1
    #|  mk_list(out)
    #|
    #|fn entries_copy(src :: tgabi.tg_entries, n :: i32, extra :: i32) -> tgabi.tg_entries:
    #|  let out = entries[null ** (n + extra)]
    #|  for i in 0 ..< n:
    #|    out[i] = src[i]
    #|  out
    #|
    #|export "map_put" fn map_put(v :: tgabi.tg_val?, key :: tgabi.tg_val?,
    #|                            x :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let m = map_of(v)
    #|  if m == null:
    #|    return null
    #|  let src = m!
    #|  let k = display(key)
    #|  let at = map_find(src, k)
    #|  if at >= 0:
    #|    let out = entries_copy(src.entries, src.count, 0)
    #|    out[at] = tgabi.tg_entry{ key: k, value: x }
    #|    return mk_map(out)
    #|  let out2 = entries_copy(src.entries, src.count, 1)
    #|  out2[src.count] = tgabi.tg_entry{ key: k, value: x }
    #|  mk_map(out2)
    #|
    #|export "map_del" fn map_del(v :: tgabi.tg_val?, key :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let m = map_of(v)
    #|  if m == null:
    #|    return null
    #|  let src = m!
    #|  let at = map_find(src, display(key))
    #|  if at < 0:
    #|    return v
    #|  let out = entries[null ** (src.count - 1)]
    #|  var i :: i32 = 0
    #|  while i < at:
    #|    out[i] = src.entries[i]
    #|    i += 1
    #|  i = at + 1
    #|  while i < src.count:
    #|    out[i - 1] = src.entries[i]
    #|    i += 1
    #|  mk_map(out)
    #|
    #|export "coll_add" fn coll_add(v :: tgabi.tg_val?, x :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  map_put(v, x, mk_bool(1))
    #|
    #|export "coll_remove" fn coll_remove(v :: tgabi.tg_val?, x :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  map_del(v, x)
    #|
    #|export "coll_toggle" fn coll_toggle(v :: tgabi.tg_val?, x :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let m = map_of(v)
    #|  if m == null:
    #|    return null
    #|  if map_find(m!, display(x)) >= 0:
    #|    return map_del(v, x)
    #|  map_put(v, x, mk_bool(1))
    #|
    #|export "item" fn item(coll :: tgabi.tg_val?, key :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if coll == null:
    #|    return null
    #|  let c = coll!
    #|  if c.kind == 7:
    #|    let l = c as tgabi.tg_list
    #|    let (ok, i :: i32) = index_of(key)
    #|    if !ok:
    #|      return null
    #|    if i < 0:
    #|      return null
    #|    if i >= l.count:
    #|      return null
    #|    return l.items[i]
    #|  if c.kind == 8:
    #|    let m = c as tgabi.tg_map
    #|    let at = map_find(m, display(key))
    #|    if at < 0:
    #|      return null
    #|    return m.entries[at]!.value
    #|  null
    #|
    #|export "member" fn member(v :: tgabi.tg_val?, name :: tgabi.tg_bytes) -> tgabi.tg_val?:
    #|  if v != null:
    #|    if v!.kind == 10:
    #|      let inst = (v! as tgabi.tg_comp).value
    #|      return inst.vt.call(inst, 8, name, no_args(), null)
    #|  let m = map_of(v)
    #|  if m == null:
    #|    return null
    #|  let at = map_find(m!, name)
    #|  if at < 0:
    #|    return null
    #|  m!.entries[at]!.value
    #|
    #|export "with_member" fn with_member(v :: tgabi.tg_val?, name :: tgabi.tg_bytes,
    #|                                    x :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if v != null:
    #|    if v!.kind == 10:
    #|      let inst = (v! as tgabi.tg_comp).value
    #|      return inst.vt.call(inst, 9, name, no_args(), x)
    #|  map_put(v, mk_str(name), x)
    #|
    #|export "with_item" fn with_item(coll :: tgabi.tg_val?, key :: tgabi.tg_val?,
    #|                                x :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if coll == null:
    #|    return null
    #|  if coll!.kind == 7:
    #|    return coll_set_at(coll, key, x)
    #|  if coll!.kind == 8:
    #|    return map_put(coll, key, x)
    #|  null
    #|
    #|export "entry_of" fn entry_of(key :: tgabi.tg_bytes, value :: tgabi.tg_val?) -> tgabi.tg_entry:
    #|  tgabi.tg_entry{ key: key, value: value }
    #|
    #|export "arg" fn arg(args :: tgabi.tg_val?, key :: tgabi.tg_bytes,
    #|                    zero :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let m = map_of(args)
    #|  if m == null:
    #|    return zero
    #|  let at = map_find(m!, key)
    #|  if at < 0:
    #|    return zero
    #|  m!.entries[at]!.value
    #|
    #|export "arg_at" fn arg_at(args :: tgabi.tg_vals, i :: i32) -> tgabi.tg_val?:
    #|  if i < 0:
    #|    return mk_null()
    #|  if i >= args.len():
    #|    return mk_null()
    #|  let v = args[i]
    #|  if v == null:
    #|    return mk_null()
    #|  v
    #|
    #|fn pair(a :: tgabi.tg_val?, b :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let items = vals[null ** 2]
    #|  items[0] = a
    #|  items[1] = b
    #|  mk_list(items)
    #|
    #|fn one_entry(key :: tgabi.tg_bytes, value :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  let es = entries[null ** 1]
    #|  es[0] = entry_of(key, value)
    #|  mk_map(es)
    #|
    #|export "mk_step_field" fn mk_step_field(name :: tgabi.tg_bytes) -> tgabi.tg_val?:
    #|  one_entry("field", mk_str(name))
    #|
    #|export "mk_step_key" fn mk_step_key(field :: tgabi.tg_bytes, key :: tgabi.tg_val?) -> tgabi.tg_val?:
    #|  if key == null:
    #|    return null
    #|  let k = key!
    #|  if k.kind == 2:
    #|    let n = (k as tgabi.tg_num).value
    #|    if n >= 0.0:
    #|      let whole = (n as i64_s) as f64_s
    #|      if whole == n:
    #|        return one_entry("at", pair(mk_str(field), mk_num(n)))
    #|  one_entry("item", pair(mk_str(field), mk_str(display(key))))
    #|
  src
}
