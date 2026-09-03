// Generated from `rt.wax` by `node tgc/rt/embed.mjs`. DO NOT EDIT.
//
// Change `rt.wax`, rerun the script, commit both halves.

///|
pub fn source() -> String {
  let src =
    #|
    #|
    #|#[export = "get_field"]
    #|fn rt_get_field(inst: &tg_inst, name: &tg_bytes) -> &?tg_val {
    #|    inst.vt.get(inst, name)
    #|}
    #|
    #|#[export = "call_op"]
    #|fn rt_call_op(inst: &tg_inst, op: i32, name: &tg_bytes,
    #|              args: &tg_vals, v: &?tg_val) -> &?tg_val {
    #|    inst.vt.call(inst, op, name, args, v)
    #|}
    #|
    #|#[export = "cross_get"]
    #|fn rt_cross_get(vt_from: &tg_inst, target: &tg_inst, name: &tg_bytes) -> &?tg_val {
    #|    vt_from.vt.get(target, name)
    #|}
    #|
    #|#[export = "str_eq"]
    #|fn tg_str_eq(a: &tg_bytes, b: &tg_bytes) -> i32 {
    #|    let n = a.length();
    #|    if n != b.length() { return 0; }
    #|    let i: i32 = 0;
    #|    while i <s n {
    #|        if (a[i] as i32_u) != (b[i] as i32_u) { return 0; }
    #|        i += 1;
    #|    }
    #|    1
    #|}
    #|
    #|fn tg_bytes_concat(a: &tg_bytes, b: &tg_bytes) -> &tg_bytes {
    #|    let out = [tg_bytes| 0; a.length() + b.length()];
    #|    out.copy(0, a, 0, a.length());
    #|    out.copy(a.length(), b, 0, b.length());
    #|    out
    #|}
    #|
    #|let tg_empty_bytes: &?tg_bytes = null;
    #|
    #|fn tg_no_bytes() -> &tg_bytes {
    #|    if tg_empty_bytes == null { tg_empty_bytes = [tg_bytes| 0; 0]; }
    #|    tg_empty_bytes!
    #|}
    #|
    #|let tg_the_null: &?tg_val = null;
    #|
    #|#[export = "mk_null"]
    #|fn tg_null() -> &tg_val {
    #|    if tg_the_null == null { tg_the_null = {tg_val| kind: 0 }; }
    #|    tg_the_null!
    #|}
    #|
    #|#[export = "mk_bool"]
    #|fn tg_bool(b: i32) -> &tg_val {
    #|    let out: &tg_bool = { kind: 1, value: b };
    #|    out
    #|}
    #|
    #|#[export = "mk_num"]
    #|fn tg_num(n: f64) -> &tg_val {
    #|    let out: &tg_num = { kind: 2, value: n };
    #|    out
    #|}
    #|
    #|#[export = "mk_int"]
    #|fn tg_int(i: i64) -> &tg_val {
    #|    let out: &tg_int = { kind: 3, value: i };
    #|    out
    #|}
    #|
    #|#[export = "mk_str"]
    #|fn tg_str(b: &tg_bytes) -> &tg_val {
    #|    let out: &tg_str = { kind: 4, value: b };
    #|    out
    #|}
    #|
    #|#[export = "mk_bin"]
    #|fn tg_bin(b: &tg_bytes) -> &tg_val {
    #|    let out: &tg_bin = { kind: 5, value: b };
    #|    out
    #|}
    #|
    #|#[export = "mk_instant"]
    #|fn tg_instant(secs: i64, nanos: i32) -> &tg_val {
    #|    let out: &tg_instant = { kind: 6, secs, nanos };
    #|    out
    #|}
    #|
    #|#[export = "mk_list"]
    #|fn tg_list(items: &tg_vals) -> &tg_val {
    #|    let out: &tg_list = { kind: 7, items, count: items.length() };
    #|    out
    #|}
    #|
    #|#[export = "mk_map"]
    #|fn tg_map(entries: &tg_entries) -> &tg_val {
    #|    let out: &tg_map = { kind: 8, entries, count: entries.length() };
    #|    out
    #|}
    #|
    #|#[export = "mk_comp"]
    #|fn tg_comp(inst: &tg_inst) -> &tg_val {
    #|    let out: &tg_comp = { kind: 10, value: inst };
    #|    out
    #|}
    #|
    #|#[export = "vals_new"]
    #|fn tg_vals_new(n: i32) -> &tg_vals { [tg_vals| null; n] }
    #|
    #|#[export = "vals_set"]
    #|fn tg_vals_set(a: &tg_vals, i: i32, v: &?tg_val) { a[i] = v; }
    #|
    #|#[export = "entries_new"]
    #|fn tg_entries_new(n: i32) -> &tg_entries { [tg_entries| null; n] }
    #|
    #|#[export = "entries_set"]
    #|fn tg_entries_set(a: &tg_entries, i: i32, k: &tg_bytes, v: &?tg_val) {
    #|    let e: &tg_entry = { key: k, value: v };
    #|    a[i] = e;
    #|}
    #|
    #|let tg_no_args_v: &?tg_vals = null;
    #|
    #|#[export = "no_args"]
    #|fn tg_no_args() -> &tg_vals {
    #|    if tg_no_args_v == null { tg_no_args_v = [tg_vals| null; 0]; }
    #|    tg_no_args_v!
    #|}
    #|
    #|#[export = "kind_of"]
    #|fn tg_kind(v: &tg_val) -> i32 { v.kind }
    #|
    #|#[export = "as_bool"]
    #|fn tg_as_bool(v: &tg_val) -> i32 { (v as &tg_bool).value }
    #|
    #|#[export = "as_num"]
    #|fn tg_as_num(v: &tg_val) -> f64 { (v as &tg_num).value }
    #|
    #|#[export = "as_int"]
    #|fn tg_as_int(v: &tg_val) -> i64 { (v as &tg_int).value }
    #|
    #|#[export = "as_str"]
    #|fn tg_as_str(v: &tg_val) -> &tg_bytes { (v as &tg_str).value }
    #|
    #|#[export = "as_bin"]
    #|fn tg_as_bin(v: &tg_val) -> &tg_bytes { (v as &tg_bin).value }
    #|
    #|#[export = "instant_secs"]
    #|fn tg_instant_secs(v: &tg_val) -> i64 { (v as &tg_instant).secs }
    #|
    #|#[export = "instant_nanos"]
    #|fn tg_instant_nanos(v: &tg_val) -> i32 { (v as &tg_instant).nanos }
    #|
    #|#[export = "list_len"]
    #|fn tg_list_len(v: &tg_val) -> i32 { (v as &tg_list).count }
    #|
    #|#[export = "list_at"]
    #|fn tg_list_at(v: &tg_val, i: i32) -> &?tg_val {
    #|    let l = v as &tg_list;
    #|    if i <s 0 { return null; }
    #|    if i >=s l.count { return null; }
    #|    l.items[i]
    #|}
    #|
    #|#[export = "map_len"]
    #|fn tg_map_len(v: &tg_val) -> i32 { (v as &tg_map).count }
    #|
    #|#[export = "map_key"]
    #|fn tg_map_key(v: &tg_val, i: i32) -> &tg_bytes {
    #|    (v as &tg_map).entries[i]!.key
    #|}
    #|
    #|#[export = "map_val"]
    #|fn tg_map_val(v: &tg_val, i: i32) -> &?tg_val {
    #|    (v as &tg_map).entries[i]!.value
    #|}
    #|
    #|#[export = "as_inst"]
    #|fn tg_as_inst(v: &tg_val) -> &tg_inst { (v as &tg_comp).value }
    #|
    #|#[export = "inst_desc"]
    #|fn tg_inst_desc(i: &tg_inst) -> &tg_val { i.desc }
    #|
    #|#[export = "inst_id"]
    #|fn tg_inst_id(i: &tg_inst) -> i64 { i.id }
    #|
    #|#[export = "bytes_len"]
    #|fn tg_bytes_len(b: &tg_bytes) -> i32 { b.length() }
    #|
    #|#[export = "bytes_at"]
    #|fn tg_bytes_at(b: &tg_bytes, i: i32) -> i32 { b[i] as i32_u }
    #|
    #|#[export = "bytes_new"]
    #|fn tg_bytes_new(n: i32) -> &tg_bytes { [tg_bytes| 0; n] }
    #|
    #|#[export = "bytes_set"]
    #|fn tg_bytes_set(b: &tg_bytes, i: i32, x: i32) { b[i] = x; }
    #|
    #|fn tg_size(v: &tg_val) -> i32 {
    #|    if v.kind == 7 { return (v as &tg_list).count; }
    #|    if v.kind == 8 { return (v as &tg_map).count; }
    #|    if v.kind == 4 { return (v as &tg_str).value.length(); }
    #|    -1
    #|}
    #|
    #|#[export = "truthy"]
    #|fn tg_truthy(v: &?tg_val) -> i32 {
    #|    if v == null { return 0; }
    #|    let x = v!;
    #|    if x.kind == 0 { return 0; }
    #|    if x.kind == 1 { return (x as &tg_bool).value; }
    #|    if x.kind == 2 {
    #|        let n = (x as &tg_num).value;
    #|        if n == 0.0 { return 0; }
    #|        if n != n { return 0; }
    #|        return 1;
    #|    }
    #|    if x.kind == 3 { if (x as &tg_int).value == 0 { return 0; } return 1; }
    #|    if x.kind == 4 { if (x as &tg_str).value.length() == 0 { return 0; } return 1; }
    #|    1
    #|}
    #|
    #|#[export = "pred_truthy"]
    #|fn tg_pred_truthy(v: &?tg_val) -> i32 {
    #|    if v == null { return 0; }
    #|    let x = v!;
    #|    let n = tg_size(x);
    #|    if n >=s 0 { if n == 0 { return 0; } return 1; }
    #|    tg_truthy(v)
    #|}
    #|
    #|#[export = "val_eq"]
    #|fn tg_val_eq(a: &?tg_val, b: &?tg_val) -> i32 {
    #|    if a == null { if b == null { return 1; } return 0; }
    #|    if b == null { return 0; }
    #|    let x = a!;
    #|    let y = b!;
    #|    if x.kind != y.kind { return 0; }
    #|    if x.kind == 0 { return 1; }
    #|    if x.kind == 1 { if (x as &tg_bool).value == (y as &tg_bool).value { return 1; } return 0; }
    #|    if x.kind == 2 { if (x as &tg_num).value == (y as &tg_num).value { return 1; } return 0; }
    #|    if x.kind == 3 { if (x as &tg_int).value == (y as &tg_int).value { return 1; } return 0; }
    #|    if x.kind == 4 { return tg_str_eq((x as &tg_str).value, (y as &tg_str).value); }
    #|    if x.kind == 5 { return tg_str_eq((x as &tg_bin).value, (y as &tg_bin).value); }
    #|    if x.kind == 6 {
    #|        let p = x as &tg_instant;
    #|        let q = y as &tg_instant;
    #|        if p.secs != q.secs { return 0; }
    #|        if p.nanos != q.nanos { return 0; }
    #|        return 1;
    #|    }
    #|    if x.kind == 7 {
    #|        let p = x as &tg_list;
    #|        let q = y as &tg_list;
    #|        if p.count != q.count { return 0; }
    #|        let i: i32 = 0;
    #|        while i <s p.count {
    #|            if tg_val_eq(p.items[i], q.items[i]) == 0 { return 0; }
    #|            i += 1;
    #|        }
    #|        return 1;
    #|    }
    #|    if x.kind == 8 {
    #|        let p = x as &tg_map;
    #|        let q = y as &tg_map;
    #|        if p.count != q.count { return 0; }
    #|        let i: i32 = 0;
    #|        while i <s p.count {
    #|            let pe = p.entries[i]!;
    #|            let found = tg_map_find(q, pe.key);
    #|            if found <s 0 { return 0; }
    #|            if tg_val_eq(pe.value, q.entries[found]!.value) == 0 { return 0; }
    #|            i += 1;
    #|        }
    #|        return 1;
    #|    }
    #|    if x.kind == 10 {
    #|        if (x as &tg_comp).value.id == (y as &tg_comp).value.id { return 1; }
    #|        return 0;
    #|    }
    #|    0
    #|}
    #|
    #|fn tg_map_find(m: &tg_map, key: &tg_bytes) -> i32 {
    #|    let i: i32 = 0;
    #|    while i <s m.count {
    #|        if tg_str_eq(m.entries[i]!.key, key) != 0 { return i; }
    #|        i += 1;
    #|    }
    #|    -1
    #|}
    #|
    #|let tg_num_ok: i32 = 0;
    #|
    #|fn tg_as_double(v: &?tg_val) -> f64 {
    #|    tg_num_ok = 0;
    #|    if v == null { return 0.0; }
    #|    let x = v!;
    #|    if x.kind == 2 { tg_num_ok = 1; return (x as &tg_num).value; }
    #|    if x.kind == 3 { tg_num_ok = 1; return (x as &tg_int).value as f64_s; }
    #|    0.0
    #|}
    #|
    #|fn tg_two_doubles(a: &?tg_val, b: &?tg_val) -> i32 {
    #|    let x = tg_as_double(a);
    #|    if tg_num_ok == 0 { return 0; }
    #|    let y = tg_as_double(b);
    #|    if tg_num_ok == 0 { return 0; }
    #|    1
    #|}
    #|
    #|#[export = "op_add"]
    #|fn tg_op_add(a: &?tg_val, b: &?tg_val) -> &?tg_val {
    #|    let x = tg_as_double(a);
    #|    if tg_num_ok == 0 { return null; }
    #|    let y = tg_as_double(b);
    #|    if tg_num_ok == 0 { return null; }
    #|    tg_num(x + y)
    #|}
    #|
    #|#[export = "op_sub"]
    #|fn tg_op_sub(a: &?tg_val, b: &?tg_val) -> &?tg_val {
    #|    let x = tg_as_double(a);
    #|    if tg_num_ok == 0 { return null; }
    #|    let y = tg_as_double(b);
    #|    if tg_num_ok == 0 { return null; }
    #|    tg_num(x - y)
    #|}
    #|
    #|#[export = "op_mul"]
    #|fn tg_op_mul(a: &?tg_val, b: &?tg_val) -> &?tg_val {
    #|    let x = tg_as_double(a);
    #|    if tg_num_ok == 0 { return null; }
    #|    let y = tg_as_double(b);
    #|    if tg_num_ok == 0 { return null; }
    #|    tg_num(x * y)
    #|}
    #|
    #|#[export = "op_div"]
    #|fn tg_op_div(a: &?tg_val, b: &?tg_val) -> &?tg_val {
    #|    let x = tg_as_double(a);
    #|    if tg_num_ok == 0 { return null; }
    #|    let y = tg_as_double(b);
    #|    if tg_num_ok == 0 { return null; }
    #|    tg_num(x / y)
    #|}
    #|
    #|#[export = "op_mod"]
    #|fn tg_op_mod(a: &?tg_val, b: &?tg_val) -> &?tg_val {
    #|    let x = tg_as_double(a);
    #|    if tg_num_ok == 0 { return null; }
    #|    let y = tg_as_double(b);
    #|    if tg_num_ok == 0 { return null; }
    #|    if y == 0.0 { return tg_num(x / y); }
    #|    let q = (x / y) as i64_s;
    #|    tg_num(x - (q as f64_s) * y)
    #|}
    #|
    #|#[export = "op_neg"]
    #|fn tg_op_neg(a: &?tg_val) -> &?tg_val {
    #|    let x = tg_as_double(a);
    #|    if tg_num_ok == 0 { return null; }
    #|    tg_num(0.0 - x)
    #|}
    #|
    #|#[export = "op_lt"]
    #|fn tg_op_lt(a: &?tg_val, b: &?tg_val) -> &?tg_val {
    #|    if tg_two_doubles(a, b) == 0 { return null; }
    #|    let x = tg_as_double(a);
    #|    let y = tg_as_double(b);
    #|    if x < y { return tg_bool(1); }
    #|    tg_bool(0)
    #|}
    #|
    #|#[export = "op_le"]
    #|fn tg_op_le(a: &?tg_val, b: &?tg_val) -> &?tg_val {
    #|    if tg_two_doubles(a, b) == 0 { return null; }
    #|    let x = tg_as_double(a);
    #|    let y = tg_as_double(b);
    #|    if x <= y { return tg_bool(1); }
    #|    tg_bool(0)
    #|}
    #|
    #|#[export = "op_gt"]
    #|fn tg_op_gt(a: &?tg_val, b: &?tg_val) -> &?tg_val {
    #|    if tg_two_doubles(a, b) == 0 { return null; }
    #|    let x = tg_as_double(a);
    #|    let y = tg_as_double(b);
    #|    if x > y { return tg_bool(1); }
    #|    tg_bool(0)
    #|}
    #|
    #|#[export = "op_ge"]
    #|fn tg_op_ge(a: &?tg_val, b: &?tg_val) -> &?tg_val {
    #|    if tg_two_doubles(a, b) == 0 { return null; }
    #|    let x = tg_as_double(a);
    #|    let y = tg_as_double(b);
    #|    if x >= y { return tg_bool(1); }
    #|    tg_bool(0)
    #|}
    #|
    #|#[export = "op_is"]
    #|fn tg_op_is(a: &?tg_val, b: &?tg_val) -> &?tg_val {
    #|    if a == null { return null; }
    #|    if b == null { return null; }
    #|    tg_bool(tg_val_eq(a, b))
    #|}
    #|
    #|#[export = "op_is_not"]
    #|fn tg_op_is_not(a: &?tg_val, b: &?tg_val) -> &?tg_val {
    #|    if a == null { return null; }
    #|    if b == null { return null; }
    #|    if tg_val_eq(a, b) != 0 { return tg_bool(0); }
    #|    tg_bool(1)
    #|}
    #|
    #|#[export = "trunc"]
    #|fn tg_trunc(v: &?tg_val) -> &?tg_val {
    #|    let x = tg_as_double(v);
    #|    if tg_num_ok == 0 { return null; }
    #|    tg_num((x as i64_s) as f64_s)
    #|}
    #|
    #|fn tg_digits(n: i64, out: &tg_bytes, at: i32) -> i32 {
    #|    if n == (0 as i64) { out[at] = 48; return at + 1; }
    #|    let tmp = [tg_bytes| 0; 20];
    #|    let len: i32 = 0;
    #|    let x: i64 = n;
    #|    while x >s (0 as i64) {
    #|        tmp[len] = ((x %s (10 as i64)) as i32) + 48;
    #|        x = x /s (10 as i64);
    #|        len += 1;
    #|    }
    #|    let i: i32 = 0;
    #|    while i <s len {
    #|        out[at + i] = tmp[len - 1 - i] as i32_u;
    #|        i += 1;
    #|    }
    #|    at + len
    #|}
    #|
    #|fn tg_num_text(n: f64) -> &tg_bytes {
    #|    if n != n { return "NaN"; }
    #|    let neg: i32 = 0;
    #|    let v: f64 = n;
    #|    if v < 0.0 { neg = 1; v = 0.0 - v; }
    #|    if v >= 9223372036854775000.0 {
    #|        if neg != 0 { return "-Infinity"; }
    #|        return "Infinity";
    #|    }
    #|    let whole = v as i64_s;
    #|    let frac = v - (whole as f64_s);
    #|    let scaled = ((frac * 1000000.0) + 0.5) as i64_s;
    #|    if scaled >=s (1000000 as i64) { whole = whole + (1 as i64); scaled = (0 as i64); }
    #|    let digits = [tg_bytes| 0; 40];
    #|    let at: i32 = 0;
    #|    if neg != 0 { digits[0] = 45; at = 1; }
    #|    at = tg_digits(whole, digits, at);
    #|    if scaled >s (0 as i64) {
    #|        let f = [tg_bytes| 0; 6];
    #|        let i: i32 = 5;
    #|        let s: i64 = scaled;
    #|        while i >=s 0 {
    #|            f[i] = ((s %s (10 as i64)) as i32) + 48;
    #|            s = s /s (10 as i64);
    #|            i -= 1;
    #|        }
    #|        let last: i32 = 5;
    #|        'trim: do {
    #|            while last >=s 0 {
    #|                if (f[last] as i32_u) != 48 { br 'trim; }
    #|                last -= 1;
    #|            }
    #|        }
    #|        digits[at] = 46;
    #|        at += 1;
    #|        let j: i32 = 0;
    #|        while j <=s last {
    #|            digits[at] = f[j] as i32_u;
    #|            at += 1;
    #|            j += 1;
    #|        }
    #|    }
    #|    let out = [tg_bytes| 0; at];
    #|    out.copy(0, digits, 0, at);
    #|    out
    #|}
    #|
    #|#[export = "display"]
    #|fn tg_display(v: &?tg_val) -> &tg_bytes {
    #|    if v == null { return tg_no_bytes(); }
    #|    let x = v!;
    #|    if x.kind == 0 { return tg_no_bytes(); }
    #|    if x.kind == 1 {
    #|        if (x as &tg_bool).value != 0 { return "true"; }
    #|        return "false";
    #|    }
    #|    if x.kind == 2 { return tg_num_text((x as &tg_num).value); }
    #|    if x.kind == 3 { return tg_num_text((x as &tg_int).value as f64_s); }
    #|    if x.kind == 4 { return (x as &tg_str).value; }
    #|    tg_no_bytes()
    #|}
    #|
    #|#[export = "concat"]
    #|fn tg_concat(a: &tg_bytes, b: &tg_bytes) -> &tg_bytes { tg_bytes_concat(a, b) }
    #|
    #|#[export = "b_empty"]
    #|fn tg_b_empty(v: &?tg_val) -> &?tg_val {
    #|    if v == null { return null; }
    #|    let x = v!;
    #|    if x.kind == 0 { return tg_bool(1); }
    #|    if tg_size(x) == 0 { return tg_bool(1); }
    #|    tg_bool(0)
    #|}
    #|
    #|#[export = "b_truthy"]
    #|fn tg_b_truthy(v: &?tg_val) -> &?tg_val {
    #|    if v == null { return null; }
    #|    tg_bool(tg_pred_truthy(v))
    #|}
    #|
    #|#[export = "b_falsy"]
    #|fn tg_b_falsy(v: &?tg_val) -> &?tg_val {
    #|    if v == null { return null; }
    #|    if tg_pred_truthy(v) != 0 { return tg_bool(0); }
    #|    tg_bool(1)
    #|}
    #|
    #|#[export = "b_null"]
    #|fn tg_b_null(v: &?tg_val) -> &?tg_val {
    #|    if v == null { return null; }
    #|    if v!.kind == 0 { return tg_bool(1); }
    #|    tg_bool(0)
    #|}
    #|
    #|#[export = "b_not"]
    #|fn tg_b_not(v: &?tg_val) -> &?tg_val {
    #|    if v == null { return null; }
    #|    if tg_truthy(v) != 0 { return tg_bool(0); }
    #|    tg_bool(1)
    #|}
    #|
    #|#[export = "b_len"]
    #|fn tg_b_len(v: &?tg_val) -> &?tg_val {
    #|    if v == null { return null; }
    #|    let n = tg_size(v!);
    #|    if n <s 0 { return null; }
    #|    tg_num(n as f64_s)
    #|}
    #|
    #|#[export = "b_has"]
    #|fn tg_b_has(coll: &?tg_val, x: &?tg_val) -> &?tg_val {
    #|    if coll == null { return null; }
    #|    let c = coll!;
    #|    if c.kind == 8 {
    #|        if tg_map_find(c as &tg_map, tg_display(x)) >=s 0 { return tg_bool(1); }
    #|        return tg_bool(0);
    #|    }
    #|    if c.kind == 7 {
    #|        let l = c as &tg_list;
    #|        let i: i32 = 0;
    #|        while i <s l.count {
    #|            if tg_val_eq(l.items[i], x) != 0 { return tg_bool(1); }
    #|            i += 1;
    #|        }
    #|        return tg_bool(0);
    #|    }
    #|    null
    #|}
    #|
    #|#[export = "b_contains"]
    #|fn tg_b_contains(hay: &?tg_val, needle: &?tg_val) -> &?tg_val {
    #|    if hay == null { return null; }
    #|    if needle == null { return null; }
    #|    if hay!.kind != 4 { return null; }
    #|    if needle!.kind != 4 { return null; }
    #|    let h = (hay! as &tg_str).value;
    #|    let n = (needle! as &tg_str).value;
    #|    if n.length() == 0 { return tg_bool(1); }
    #|    if n.length() >s h.length() { return tg_bool(0); }
    #|    let i: i32 = 0;
    #|    let found: i32 = 0;
    #|    'scan: do {
    #|        while i <=s h.length() - n.length() {
    #|            let j: i32 = 0;
    #|            let hit: i32 = 1;
    #|            'probe: do {
    #|                while j <s n.length() {
    #|                    if (h[i + j] as i32_u) != (n[j] as i32_u) { hit = 0; br 'probe; }
    #|                    j += 1;
    #|                }
    #|            }
    #|            if hit != 0 { found = 1; br 'scan; }
    #|            i += 1;
    #|        }
    #|    }
    #|    tg_bool(found)
    #|}
    #|
    #|#[export = "b_min"]
    #|fn tg_b_min(a: &?tg_val, b: &?tg_val) -> &?tg_val {
    #|    if tg_two_doubles(a, b) == 0 { return null; }
    #|    let x = tg_as_double(a);
    #|    let y = tg_as_double(b);
    #|    if x < y { return tg_num(x); }
    #|    tg_num(y)
    #|}
    #|
    #|#[export = "b_max"]
    #|fn tg_b_max(a: &?tg_val, b: &?tg_val) -> &?tg_val {
    #|    if tg_two_doubles(a, b) == 0 { return null; }
    #|    let x = tg_as_double(a);
    #|    let y = tg_as_double(b);
    #|    if x > y { return tg_num(x); }
    #|    tg_num(y)
    #|}
    #|
    #|#[export = "b_clamp"]
    #|fn tg_b_clamp(v: &?tg_val, lo: &?tg_val, hi: &?tg_val) -> &?tg_val {
    #|    let x = tg_as_double(v);
    #|    if tg_num_ok == 0 { return null; }
    #|    let l = tg_as_double(lo);
    #|    if tg_num_ok == 0 { return null; }
    #|    let h = tg_as_double(hi);
    #|    if tg_num_ok == 0 { return null; }
    #|    if h < l { return tg_num(l); }
    #|    if x < l { return tg_num(l); }
    #|    if x > h { return tg_num(h); }
    #|    tg_num(x)
    #|}
    #|
    #|#[export = "b_str"]
    #|fn tg_b_str(v: &?tg_val) -> &?tg_val {
    #|    if v == null { return null; }
    #|    tg_str(tg_display(v))
    #|}
    #|
    #|#[export = "b_num"]
    #|fn tg_b_num(v: &?tg_val) -> &?tg_val {
    #|    if v == null { return null; }
    #|    let x = v!;
    #|    if x.kind == 2 { return x; }
    #|    if x.kind == 3 { return tg_num((x as &tg_int).value as f64_s); }
    #|    if x.kind == 4 { return tg_parse_num((x as &tg_str).value); }
    #|    null
    #|}
    #|
    #|#[export = "b_int"]
    #|fn tg_b_int(v: &?tg_val) -> &?tg_val {
    #|    let n = tg_b_num(v);
    #|    if n == null { return null; }
    #|    tg_num((tg_as_double(n) as i64_s) as f64_s)
    #|}
    #|
    #|fn tg_parse_num(s: &tg_bytes) -> &?tg_val {
    #|    let n = s.length();
    #|    if n == 0 { return null; }
    #|    let i: i32 = 0;
    #|    let neg: i32 = 0;
    #|    let c0 = s[0] as i32_u;
    #|    if c0 == 43 { i = 1; }
    #|    if c0 == 45 { neg = 1; i = 1; }
    #|    let seen: i32 = 0;
    #|    let acc: f64 = 0.0;
    #|    'whole: do {
    #|        while i <s n {
    #|            let c = s[i] as i32_u;
    #|            if c <u 48 { br 'whole; }
    #|            if c >u 57 { br 'whole; }
    #|            acc = acc * 10.0 + ((c - 48) as f64_s);
    #|            seen += 1;
    #|            i += 1;
    #|        }
    #|    }
    #|    if i <s n {
    #|        if (s[i] as i32_u) == 46 {
    #|            i += 1;
    #|            let scale: f64 = 0.1;
    #|            'frac: do {
    #|                while i <s n {
    #|                    let c = s[i] as i32_u;
    #|                    if c <u 48 { br 'frac; }
    #|                    if c >u 57 { br 'frac; }
    #|                    acc = acc + ((c - 48) as f64_s) * scale;
    #|                    scale = scale * 0.1;
    #|                    seen += 1;
    #|                    i += 1;
    #|                }
    #|            }
    #|        }
    #|    }
    #|    if seen == 0 { return null; }
    #|    if i <s n {
    #|        let c = s[i] as i32_u;
    #|        if c == 101 { i += 1; } else { if c == 69 { i += 1; } else { return null; } }
    #|        let eneg: i32 = 0;
    #|        if i <s n {
    #|            let sc = s[i] as i32_u;
    #|            if sc == 43 { i += 1; }
    #|            if sc == 45 { eneg = 1; i += 1; }
    #|        }
    #|        let e: i32 = 0;
    #|        let edigits: i32 = 0;
    #|        while i <s n {
    #|            let c2 = s[i] as i32_u;
    #|            if c2 <u 48 { return null; }
    #|            if c2 >u 57 { return null; }
    #|            e = e * 10 + (c2 - 48);
    #|            edigits += 1;
    #|            i += 1;
    #|        }
    #|        if edigits == 0 { return null; }
    #|        let k: i32 = 0;
    #|        while k <s e {
    #|            if eneg != 0 { acc = acc / 10.0; } else { acc = acc * 10.0; }
    #|            k += 1;
    #|        }
    #|    }
    #|    if i != n { return null; }
    #|    if neg != 0 { return tg_num(0.0 - acc); }
    #|    tg_num(acc)
    #|}
    #|
    #|fn tg_case(v: &?tg_val, upper: i32) -> &?tg_val {
    #|    if v == null { return null; }
    #|    if v!.kind != 4 { return null; }
    #|    let s = (v! as &tg_str).value;
    #|    let out = [tg_bytes| 0; s.length()];
    #|    let i: i32 = 0;
    #|    while i <s s.length() {
    #|        let c = s[i] as i32_u;
    #|        if upper != 0 {
    #|            if c >=u 97 { if c <=u 122 { c = c - 32; } }
    #|        } else {
    #|            if c >=u 65 { if c <=u 90 { c = c + 32; } }
    #|        }
    #|        out[i] = c;
    #|        i += 1;
    #|    }
    #|    tg_str(out)
    #|}
    #|
    #|#[export = "b_lower"]
    #|fn tg_b_lower(v: &?tg_val) -> &?tg_val { tg_case(v, 0) }
    #|
    #|#[export = "b_upper"]
    #|fn tg_b_upper(v: &?tg_val) -> &?tg_val { tg_case(v, 1) }
    #|
    #|fn tg_is_space(c: i32) -> i32 {
    #|    if c == 32 { return 1; }
    #|    if c == 9 { return 1; }
    #|    if c == 10 { return 1; }
    #|    if c == 13 { return 1; }
    #|    0
    #|}
    #|
    #|#[export = "b_trim"]
    #|fn tg_b_trim(v: &?tg_val) -> &?tg_val {
    #|    if v == null { return null; }
    #|    if v!.kind != 4 { return null; }
    #|    let s = (v! as &tg_str).value;
    #|    let start: i32 = 0;
    #|    let end: i32 = s.length();
    #|    'lead: do {
    #|        while start <s end {
    #|            if tg_is_space(s[start] as i32_u) == 0 { br 'lead; }
    #|            start += 1;
    #|        }
    #|    }
    #|    'tail: do {
    #|        while end >s start {
    #|            if tg_is_space(s[end - 1] as i32_u) == 0 { br 'tail; }
    #|            end -= 1;
    #|        }
    #|    }
    #|    let out = [tg_bytes| 0; end - start];
    #|    out.copy(0, s, start, end - start);
    #|    tg_str(out)
    #|}
    #|
    #|fn tg_list_of(v: &?tg_val) -> &?tg_list {
    #|    if v == null { return null; }
    #|    if v!.kind != 7 { return null; }
    #|    v! as &tg_list
    #|}
    #|
    #|fn tg_map_of(v: &?tg_val) -> &?tg_map {
    #|    if v == null { return null; }
    #|    if v!.kind != 8 { return null; }
    #|    v! as &tg_map
    #|}
    #|
    #|fn tg_vals_copy(src: &tg_vals, n: i32, extra: i32) -> &tg_vals {
    #|    let out = [tg_vals| null; n + extra];
    #|    let i: i32 = 0;
    #|    while i <s n {
    #|        out[i] = src[i];
    #|        i += 1;
    #|    }
    #|    out
    #|}
    #|
    #|#[export = "coll_push"]
    #|fn tg_coll_push(v: &?tg_val, x: &?tg_val) -> &?tg_val {
    #|    let l = tg_list_of(v);
    #|    if l == null { return null; }
    #|    let src = l!;
    #|    let out = tg_vals_copy(src.items, src.count, 1);
    #|    out[src.count] = x;
    #|    tg_list(out)
    #|}
    #|
    #|#[export = "coll_insert_at"]
    #|fn tg_coll_insert_at(v: &?tg_val, at: &?tg_val, x: &?tg_val) -> &?tg_val {
    #|    if v != null {
    #|        if v!.kind == 8 { return tg_map_put(v, at, x); }
    #|    }
    #|    let l = tg_list_of(v);
    #|    if l == null { return null; }
    #|    let src = l!;
    #|    let n = tg_as_double(at);
    #|    if tg_num_ok == 0 { return null; }
    #|    let i = n as i32_s;
    #|    if i <s 0 { return null; }
    #|    if i >s src.count { return null; }
    #|    let out = [tg_vals| null; src.count + 1];
    #|    let k: i32 = 0;
    #|    while k <s i {
    #|        out[k] = src.items[k];
    #|        k += 1;
    #|    }
    #|    out[i] = x;
    #|    while k <s src.count {
    #|        out[k + 1] = src.items[k];
    #|        k += 1;
    #|    }
    #|    tg_list(out)
    #|}
    #|
    #|#[export = "coll_set_at"]
    #|fn tg_coll_set_at(v: &?tg_val, at: &?tg_val, x: &?tg_val) -> &?tg_val {
    #|    if v != null {
    #|        if v!.kind == 8 { return tg_map_put(v, at, x); }
    #|    }
    #|    let l = tg_list_of(v);
    #|    if l == null { return null; }
    #|    let src = l!;
    #|    let n = tg_as_double(at);
    #|    if tg_num_ok == 0 { return null; }
    #|    let i = n as i32_s;
    #|    if i <s 0 { return null; }
    #|    if i >=s src.count { return null; }
    #|    let out = tg_vals_copy(src.items, src.count, 0);
    #|    out[i] = x;
    #|    tg_list(out)
    #|}
    #|
    #|#[export = "coll_delete_at"]
    #|fn tg_coll_delete_at(v: &?tg_val, at: &?tg_val) -> &?tg_val {
    #|    if v != null {
    #|        if v!.kind == 8 { return tg_map_del(v, at); }
    #|    }
    #|    let l = tg_list_of(v);
    #|    if l == null { return null; }
    #|    let src = l!;
    #|    let n = tg_as_double(at);
    #|    if tg_num_ok == 0 { return null; }
    #|    let i = n as i32_s;
    #|    if i <s 0 { return null; }
    #|    if i >=s src.count { return null; }
    #|    let out = [tg_vals| null; src.count - 1];
    #|    let k: i32 = 0;
    #|    while k <s i {
    #|        out[k] = src.items[k];
    #|        k += 1;
    #|    }
    #|    k = i + 1;
    #|    while k <s src.count {
    #|        out[k - 1] = src.items[k];
    #|        k += 1;
    #|    }
    #|    tg_list(out)
    #|}
    #|
    #|fn tg_entries_copy(src: &tg_entries, n: i32, extra: i32) -> &tg_entries {
    #|    let out = [tg_entries| null; n + extra];
    #|    let i: i32 = 0;
    #|    while i <s n {
    #|        out[i] = src[i];
    #|        i += 1;
    #|    }
    #|    out
    #|}
    #|
    #|#[export = "map_put"]
    #|fn tg_map_put(v: &?tg_val, key: &?tg_val, x: &?tg_val) -> &?tg_val {
    #|    let m = tg_map_of(v);
    #|    if m == null { return null; }
    #|    let src = m!;
    #|    let k = tg_display(key);
    #|    let at = tg_map_find(src, k);
    #|    if at >=s 0 {
    #|        let out = tg_entries_copy(src.entries, src.count, 0);
    #|        let e: &tg_entry = { key: k, value: x };
    #|        out[at] = e;
    #|        return tg_map(out);
    #|    }
    #|    let out2 = tg_entries_copy(src.entries, src.count, 1);
    #|    let e2: &tg_entry = { key: k, value: x };
    #|    out2[src.count] = e2;
    #|    tg_map(out2)
    #|}
    #|
    #|#[export = "map_del"]
    #|fn tg_map_del(v: &?tg_val, key: &?tg_val) -> &?tg_val {
    #|    let m = tg_map_of(v);
    #|    if m == null { return null; }
    #|    let src = m!;
    #|    let at = tg_map_find(src, tg_display(key));
    #|    if at <s 0 { return v; }
    #|    let out = [tg_entries| null; src.count - 1];
    #|    let i: i32 = 0;
    #|    while i <s at {
    #|        out[i] = src.entries[i];
    #|        i += 1;
    #|    }
    #|    i = at + 1;
    #|    while i <s src.count {
    #|        out[i - 1] = src.entries[i];
    #|        i += 1;
    #|    }
    #|    tg_map(out)
    #|}
    #|
    #|#[export = "coll_add"]
    #|fn tg_coll_add(v: &?tg_val, x: &?tg_val) -> &?tg_val {
    #|    tg_map_put(v, x, tg_bool(1))
    #|}
    #|
    #|#[export = "coll_remove"]
    #|fn tg_coll_remove(v: &?tg_val, x: &?tg_val) -> &?tg_val { tg_map_del(v, x) }
    #|
    #|#[export = "coll_toggle"]
    #|fn tg_coll_toggle(v: &?tg_val, x: &?tg_val) -> &?tg_val {
    #|    let m = tg_map_of(v);
    #|    if m == null { return null; }
    #|    if tg_map_find(m!, tg_display(x)) >=s 0 { return tg_map_del(v, x); }
    #|    tg_map_put(v, x, tg_bool(1))
    #|}
    #|
    #|#[export = "item"]
    #|fn tg_item(coll: &?tg_val, key: &?tg_val) -> &?tg_val {
    #|    if coll == null { return null; }
    #|    let c = coll!;
    #|    if c.kind == 7 {
    #|        let l = c as &tg_list;
    #|        let n = tg_as_double(key);
    #|        if tg_num_ok == 0 { return null; }
    #|        let i = n as i32_s;
    #|        if i <s 0 { return null; }
    #|        if i >=s l.count { return null; }
    #|        return l.items[i];
    #|    }
    #|    if c.kind == 8 {
    #|        let m = c as &tg_map;
    #|        let at = tg_map_find(m, tg_display(key));
    #|        if at <s 0 { return null; }
    #|        return m.entries[at]!.value;
    #|    }
    #|    null
    #|}
    #|
    #|#[export = "member"]
    #|fn tg_member(v: &?tg_val, name: &tg_bytes) -> &?tg_val {
    #|    let m = tg_map_of(v);
    #|    if m == null { return null; }
    #|    let at = tg_map_find(m!, name);
    #|    if at <s 0 { return null; }
    #|    m!.entries[at]!.value
    #|}
    #|
    #|#[export = "with_member"]
    #|fn tg_with_member(v: &?tg_val, name: &tg_bytes, x: &?tg_val) -> &?tg_val {
    #|    tg_map_put(v, tg_str(name), x)
    #|}
    #|
    #|#[export = "with_item"]
    #|fn tg_with_item(coll: &?tg_val, key: &?tg_val, x: &?tg_val) -> &?tg_val {
    #|    if coll == null { return null; }
    #|    if coll!.kind == 7 { return tg_coll_set_at(coll, key, x); }
    #|    if coll!.kind == 8 { return tg_map_put(coll, key, x); }
    #|    null
    #|}
    #|
    #|#[export = "entry_of"]
    #|fn tg_entry_of(key: &tg_bytes, value: &?tg_val) -> &tg_entry {
    #|    let e: &tg_entry = { key, value };
    #|    e
    #|}
    #|
    #|#[export = "arg"]
    #|fn tg_arg(args: &?tg_val, key: &tg_bytes, zero: &?tg_val) -> &?tg_val {
    #|    let m = tg_map_of(args);
    #|    if m == null { return zero; }
    #|    let at = tg_map_find(m!, key);
    #|    if at <s 0 { return zero; }
    #|    m!.entries[at]!.value
    #|}
    #|
    #|#[export = "arg_at"]
    #|fn tg_arg_at(args: &tg_vals, i: i32) -> &?tg_val {
    #|    if i <s 0 { return tg_null(); }
    #|    if i >=s args.length() { return tg_null(); }
    #|    let v = args[i];
    #|    if v == null { return tg_null(); }
    #|    v
    #|}
    #|
    #|fn tg_pair(a: &?tg_val, b: &?tg_val) -> &?tg_val {
    #|    let items = [tg_vals| null; 2];
    #|    items[0] = a;
    #|    items[1] = b;
    #|    tg_list(items)
    #|}
    #|
    #|fn tg_one_entry(key: &tg_bytes, value: &?tg_val) -> &?tg_val {
    #|    let es = [tg_entries| null; 1];
    #|    es[0] = tg_entry_of(key, value);
    #|    tg_map(es)
    #|}
    #|
    #|#[export = "mk_step_field"]
    #|fn tg_step_field(name: &tg_bytes) -> &?tg_val {
    #|    tg_one_entry("field", tg_str(name))
    #|}
    #|
    #|#[export = "mk_step_key"]
    #|fn tg_step_key(field: &tg_bytes, key: &?tg_val) -> &?tg_val {
    #|    if key == null { return null; }
    #|    let k = key!;
    #|    if k.kind == 2 {
    #|        let n = (k as &tg_num).value;
    #|        if n >= 0.0 {
    #|            let whole = (n as i64_s) as f64_s;
    #|            if whole == n {
    #|                return tg_one_entry("at", tg_pair(tg_str(field), tg_num(n)));
    #|            }
    #|        }
    #|    }
    #|    tg_one_entry("item", tg_pair(tg_str(field), tg_str(tg_display(key))))
    #|}
    #|
  src
}
