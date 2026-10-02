// XIOM -- xiom.json Conformance Tests
// 43 deterministic checks: parse/stringify round-trips, manipulation API,
// JSONPath, schema validation, numeric edge cases and explicit error paths
// (malformed input, truncation, invalid escapes, wrong types, empty
// containers, deep nesting, duplicate keys).
module json_tests
use xiom.io; use xiom.test; use xiom.json;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; } var num = n; var out = "";
  while num > 0 { let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10; }
  return out;
}
fn report(passed: Bool, name: Str) -> Int {
  if passed { io.println("  [PASS] " + name); return 0; }
  io.println("  [FAIL] " + name); return 1;
}

fn roundtrip_eq(input: Str, want: Str) -> Bool {
  let r = json_parse(input);
  match r {
    Ok(v) => { let out = json_stringify(&v); return out == want; }
    Err(_) => return false,
  }
}

fn get_or_null(doc: &JsonValue, key: Str) -> JsonValue {
  let g = json_get(doc, key);
  match g {
    Some(v) => return v,
    None => return JsonValue.Null,
  }
}

fn t1() -> TestResult {
  let r = json_parse("{\"a\":1}");
  match r { Ok(_) => return assert(true, "json: parse object"), Err(_) => return assert(false, "json: parse object failed") }
}
fn t2() -> TestResult {
  let r = json_parse("[1,2,3]");
  match r { Ok(_) => return assert(true, "json: parse array"), Err(_) => return assert(false, "json: parse array failed") }
}
fn t3() -> TestResult {
  let r = json_parse("\"hello\"");
  match r { Ok(_) => return assert(true, "json: parse string"), Err(_) => return assert(false, "json: parse string failed") }
}
fn t4() -> TestResult {
  let r = json_parse("42");
  match r { Ok(_) => return assert(true, "json: parse number"), Err(_) => return assert(false, "json: parse number failed") }
}
fn t5() -> TestResult {
  let r = json_parse("true");
  match r { Ok(_) => return assert(true, "json: parse bool"), Err(_) => return assert(false, "json: parse bool failed") }
}
fn t6() -> TestResult {
  let r = json_parse("null");
  match r { Ok(v) => return assert(json_is_type(&v, JsonType.NullType), "json: null is_type Null"), Err(_) => return assert(false, "json: null parse failed") }
}
fn t7() -> TestResult {
  let r = json_parse("{\"key\":\"val\"}");
  match r { Ok(v) => { let g = json_get(&v, "key"); match g { Some(_) => return assert(true, "json: get existing key"), None => return assert(false, "json: get returned None") } } Err(_) => return assert(false, "json: get parse failed") }
}
fn t8() -> TestResult {
  let r = json_parse("{\"x\":1}");
  match r { Ok(v) => { let g = json_get(&v, "missing"); match g { Some(_) => return assert(false, "json: get missing key returned Some"), None => return assert(true, "json: get missing key => None") } } Err(_) => return assert(false, "json: get parse failed") }
}
fn t9() -> TestResult {
  var obj = json_object();
  json_set(&mut obj, "name", json_string("XIOM"));
  let out = json_stringify(&obj);
  return assert(out.len() > 0, "json: set + stringify round-trip");
}
fn t10() -> TestResult {
  let r = json_validate("{\"valid\":true}");
  match r { Ok(v) => return assert(v, "json: validate valid JSON"), Err(_) => return assert(false, "json: validate parse error") }
}
fn t11() -> TestResult {
  let path = json_path_parse("$.store.book[0].title");
  match path { Ok(_) => return assert(true, "json: path parse OK"), Err(_) => return assert(false, "json: path parse failed") }
}
fn t12() -> TestResult {
  let r = json_parse("{bad");
  match r { Ok(_) => return assert(false, "json: invalid JSON should fail"), Err(_) => return assert(true, "json: invalid JSON rejected") }
}

// ---- error paths: malformed / truncated / invalid escapes ----

fn t13() -> TestResult {
  let r = json_parse("1 2");
  match r { Ok(_) => return assert(false, "json: parse rejects trailing data"), Err(_) => return assert(true, "json: parse rejects trailing data") }
}
fn t14() -> TestResult {
  let r = json_parse("{\"a\":1");
  match r { Ok(_) => return assert(false, "json: parse rejects truncated object"), Err(_) => return assert(true, "json: parse rejects truncated object") }
}
fn t15() -> TestResult {
  let r = json_parse("\"abc");
  match r { Ok(_) => return assert(false, "json: parse rejects unterminated string"), Err(_) => return assert(true, "json: parse rejects unterminated string") }
}
fn t16() -> TestResult {
  let r = json_parse("\"a\\qb\"");
  match r { Ok(_) => return assert(false, "json: parse rejects invalid escape"), Err(_) => return assert(true, "json: parse rejects invalid escape") }
}
fn t17() -> TestResult {
  let r = json_parse("\"a\tb\"");
  match r { Ok(_) => return assert(false, "json: parse rejects raw control char"), Err(_) => return assert(true, "json: parse rejects raw control char") }
}
fn t18() -> TestResult {
  let r = json_parse("tru");
  match r { Ok(_) => return assert(false, "json: parse rejects bad literal"), Err(_) => return assert(true, "json: parse rejects bad literal") }
}
fn t19() -> TestResult {
  let r = json_parse("-");
  match r { Ok(_) => return assert(false, "json: parse rejects lone minus"), Err(_) => return assert(true, "json: parse rejects lone minus") }
}
fn t20() -> TestResult {
  let r = json_parse("01");
  match r { Ok(_) => return assert(false, "json: parse rejects leading zero"), Err(_) => return assert(true, "json: parse rejects leading zero") }
}
fn t21() -> TestResult {
  let r = json_parse("1e");
  match r { Ok(_) => return assert(false, "json: parse rejects incomplete exponent"), Err(_) => return assert(true, "json: parse rejects incomplete exponent") }
}
fn t36() -> TestResult {
  let r = json_parse("\"\\u12\"");
  match r { Ok(_) => return assert(false, "json: parse rejects truncated unicode escape"), Err(_) => return assert(true, "json: parse rejects truncated unicode escape") }
}
fn t40() -> TestResult {
  let r1 = json_parse("[1,]");
  match r1 { Ok(_) => return assert(false, "json: parse rejects trailing commas"), Err(_) => {} }
  let r2 = json_parse("{\"a\":1,}");
  match r2 { Ok(_) => return assert(false, "json: parse rejects trailing commas"), Err(_) => return assert(true, "json: parse rejects trailing commas") }
}
fn t41() -> TestResult {
  let r = json_parse("{\"a\" 1}");
  match r { Ok(_) => return assert(false, "json: parse rejects missing colon"), Err(_) => return assert(true, "json: parse rejects missing colon") }
}

// ---- numeric edge cases ----

fn t22() -> TestResult {
  if !roundtrip_eq("-1.5e3", "-1500") { return assert(false, "json: numeric canonical forms"); }
  if !roundtrip_eq("0.05", "0.05") { return assert(false, "json: numeric canonical forms"); }
  if !roundtrip_eq("2.50", "2.5") { return assert(false, "json: numeric canonical forms"); }
  if !roundtrip_eq("1E2", "100") { return assert(false, "json: numeric canonical forms"); }
  return assert(true, "json: numeric canonical forms");
}
fn t38() -> TestResult {
  let input = "{\"b\":[1,2,{\"x\":null}],\"a\":true}";
  let r = json_parse(input);
  match r {
    Ok(v) => {
      let s1 = json_stringify(&v);
      let s2 = json_stringify(&v);
      if s1 != s2 { return assert(false, "json: repeated stringify is deterministic"); }
      let cfg = json_pretty_config_sorted();
      let p1 = json_stringify_pretty(&v, &cfg);
      let p2 = json_stringify_pretty(&v, &cfg);
      if p1 != p2 { return assert(false, "json: repeated stringify is deterministic"); }
      let rp = json_parse(p1);
      match rp { Ok(_) => return assert(true, "json: repeated stringify is deterministic"), Err(_) => return assert(false, "json: repeated stringify is deterministic") }
    }
    Err(_) => return assert(false, "json: repeated stringify is deterministic"),
  }
}

// ---- empty containers, duplicate keys, deep nesting, round-trips ----

fn t23() -> TestResult {
  if !roundtrip_eq("{}", "{}") { return assert(false, "json: empty containers round-trip"); }
  if !roundtrip_eq("[]", "[]") { return assert(false, "json: empty containers round-trip"); }
  return assert(true, "json: empty containers round-trip");
}
fn t24() -> TestResult {
  return assert(roundtrip_eq("{\"a\":[],\"b\":{}}", "{\"a\":[],\"b\":{}}"), "json: nested empty containers round-trip");
}
fn t25() -> TestResult {
  if !roundtrip_eq("{\"a\":1,\"a\":2}", "{\"a\":1,\"a\":2}") { return assert(false, "json: duplicate key semantics"); }
  let r = json_parse("{\"a\":1,\"a\":2}");
  match r {
    Ok(v) => {
      let g = json_get(&v, "a");
      match g {
        Some(v1) => { let s = json_stringify(&v1); return assert(s == "1", "json: duplicate key semantics"); }
        None => return assert(false, "json: duplicate key semantics"),
      }
    }
    Err(_) => return assert(false, "json: duplicate key semantics"),
  }
}
fn t26() -> TestResult {
  var s = "0";
  var i: Int = 0;
  while i < 64 {
    s = "[" + s + "]";
    var next_i = i + 1;
    i = next_i;
  }
  let r = json_parse(s);
  match r {
    Ok(v) => {
      let out = json_stringify(&v);
      if out != s { return assert(false, "json: 64-deep array nesting round-trips"); }
      let r2 = json_parse(out);
      match r2 { Ok(_) => return assert(true, "json: 64-deep array nesting round-trips"), Err(_) => return assert(false, "json: 64-deep array nesting round-trips") }
    }
    Err(_) => return assert(false, "json: 64-deep array nesting round-trips"),
  }
}
fn t27() -> TestResult {
  var s = "0";
  var i: Int = 0;
  while i < 32 {
    s = "{\"a\":" + s + "}";
    var next_i = i + 1;
    i = next_i;
  }
  let r = json_parse(s);
  match r {
    Ok(v) => {
      let out = json_stringify(&v);
      return assert(out == s, "json: 32-deep object nesting round-trips");
    }
    Err(_) => return assert(false, "json: 32-deep object nesting round-trips"),
  }
}
fn t28() -> TestResult {
  let input = "{\"name\":\"XIOM\",\"version\":0.1,\"tags\":[\"systems\",\"language\"],\"ok\":true,\"none\":null,\"nested\":{\"nums\":[1,2,3]}}";
  if !roundtrip_eq(input, input) { return assert(false, "json: mixed document round-trip stable"); }
  let r = json_parse(input);
  match r {
    Ok(v) => {
      let once = json_stringify(&v);
      let r2 = json_parse(once);
      match r2 { Ok(v2) => { let twice = json_stringify(&v2); return assert(twice == once, "json: mixed document round-trip stable"); } Err(_) => return assert(false, "json: mixed document round-trip stable") }
    }
    Err(_) => return assert(false, "json: mixed document round-trip stable"),
  }
}
fn t37() -> TestResult {
  if !roundtrip_eq("\"line\\nnext\"", "\"line\\nnext\"") { return assert(false, "json: escaped string round-trip"); }
  if !roundtrip_eq("\"a\\\"b\\\\c\"", "\"a\\\"b\\\\c\"") { return assert(false, "json: escaped string round-trip"); }
  return assert(true, "json: escaped string round-trip");
}
fn t42() -> TestResult {
  return assert(roundtrip_eq(" \t\n{ \"a\" : [ 1 , 2 ] }\n", "{\"a\":[1,2]}"), "json: whitespace tolerated, output canonical");
}

// ---- validate / wrong types / is_type ----

fn t29() -> TestResult {
  let bad = json_validate("[1,");
  match bad {
    Ok(_) => return assert(false, "json: validate rejects malformed input"),
    Err(_) => {},
  }
  let good = json_validate("{\"a\":[true,null]}");
  match good {
    Ok(v) => return assert(v, "json: validate rejects malformed input"),
    Err(_) => return assert(false, "json: validate rejects malformed input"),
  }
}
fn t30() -> TestResult {
  var arr = json_array();
  json_array_push(&mut arr, json_number(1.0));
  let g = json_get(&arr, "a");
  match g { Some(_) => return assert(false, "json: wrong-type accessors are safe"), None => {} }
  let set_ok = json_set(&mut arr, "a", json_bool(true));
  json_object_put(&mut arr, "a", json_bool(true));
  let has = json_has_key(&arr, "a");
  let rem = json_remove(&mut arr, "a");
  let arr_out = json_stringify(&arr);
  var obj = json_object();
  json_object_put(&mut obj, "k", json_number(1.0));
  json_array_push(&mut obj, json_null());
  let obj_out = json_stringify(&obj);
  return assert(!set_ok && !has && !rem && arr_out == "[1]" && obj_out == "{\"k\":1}", "json: wrong-type accessors are safe");
}
fn t43() -> TestResult {
  let r = json_parse("{\"n\":null,\"b\":true,\"num\":1,\"s\":\"x\",\"arr\":[],\"obj\":{}}");
  match r {
    Ok(v) => {
      let vn = get_or_null(&v, "n");
      let vb = get_or_null(&v, "b");
      let vnum = get_or_null(&v, "num");
      let vs = get_or_null(&v, "s");
      let va = get_or_null(&v, "arr");
      let vo = get_or_null(&v, "obj");
      let ok = json_is_type(&vn, JsonType.NullType) && json_is_type(&vb, JsonType.BoolType) && json_is_type(&vnum, JsonType.NumberType) && json_is_type(&vs, JsonType.StringType) && json_is_type(&va, JsonType.ArrayType) && json_is_type(&vo, JsonType.ObjectType) && !json_is_type(&vn, JsonType.BoolType);
      return assert(ok, "json: is_type matrix over all six types");
    }
    Err(_) => return assert(false, "json: is_type matrix over all six types"),
  }
}

// ---- JSONPath ----

fn t31() -> TestResult {
  let r = json_parse("{\"store\":{\"book\":[{\"title\":\"X\"},{\"title\":\"Y\"}]}}");
  match r {
    Ok(v) => {
      let p = json_path_parse("$.store.book[1].title");
      match p {
        Ok(path) => {
          let g = json_get_path(&v, &path);
          match g {
            Some(t) => { let s = json_stringify(&t); return assert(s == "\"Y\"", "json: get_path nested hit"); }
            None => return assert(false, "json: get_path nested hit"),
          }
        }
        Err(_) => return assert(false, "json: get_path nested hit"),
      }
    }
    Err(_) => return assert(false, "json: get_path nested hit"),
  }
}
fn t32() -> TestResult {
  let r = json_parse("{\"store\":{\"book\":[{\"title\":\"X\"}]}}");
  match r {
    Ok(v) => {
      let p1 = json_path_parse("$.store.book[9]");
      match p1 {
        Ok(path) => { let g = json_get_path(&v, &path); match g { Some(_) => return assert(false, "json: get_path misses + constructed path"), None => {} } }
        Err(_) => return assert(false, "json: get_path misses + constructed path"),
      }
      let p2 = json_path_parse("$.store.missing");
      match p2 {
        Ok(path) => { let g = json_get_path(&v, &path); match g { Some(_) => return assert(false, "json: get_path misses + constructed path"), None => {} } }
        Err(_) => return assert(false, "json: get_path misses + constructed path"),
      }
      let p3 = json_path_parse("$.store.book.title");
      match p3 {
        Ok(path) => { let g = json_get_path(&v, &path); match g { Some(_) => return assert(false, "json: get_path misses + constructed path"), None => {} } }
        Err(_) => return assert(false, "json: get_path misses + constructed path"),
      }
      var p4 = json_path_new();
      json_path_push_key(&mut p4, "store");
      json_path_push_key(&mut p4, "book");
      json_path_push_index(&mut p4, 0);
      json_path_push_key(&mut p4, "title");
      let g4 = json_get_path(&v, &p4);
      match g4 {
        Some(t) => { let s = json_stringify(&t); return assert(s == "\"X\"", "json: get_path misses + constructed path"); }
        None => return assert(false, "json: get_path misses + constructed path"),
      }
    }
    Err(_) => return assert(false, "json: get_path misses + constructed path"),
  }
}
fn t33() -> TestResult {
  var root = json_object();
  let p = json_path_parse("$.a.b");
  match p {
    Ok(path) => {
      let ok = json_set_path(&mut root, &path, json_number(1.0));
      let out = json_stringify(&root);
      return assert(ok && out == "{\"a\":{\"b\":1}}", "json: set_path creates intermediate objects");
    }
    Err(_) => return assert(false, "json: set_path creates intermediate objects"),
  }
}
fn t35() -> TestResult {
  let p1 = json_path_parse("$[0");
  match p1 { Ok(_) => return assert(false, "json: path parse rejects malformed path"), Err(_) => {} }
  let p2 = json_path_parse("x");
  match p2 { Ok(_) => return assert(false, "json: path parse rejects malformed path"), Err(_) => return assert(true, "json: path parse rejects malformed path") }
}

// ---- merge / object_put ----

fn t34() -> TestResult {
  let rb = json_parse("{\"a\":1,\"b\":{\"x\":1,\"y\":2}}");
  match rb {
    Ok(vb) => {
      var base = vb;
      let ro = json_parse("{\"b\":{\"y\":3,\"z\":4},\"c\":5}");
      match ro {
        Ok(ov) => {
          let ok = json_merge(&mut base, &ov);
          let out = json_stringify(&base);
          let exp = "{\"a\":1,\"b\":{\"x\":1,\"y\":3,\"z\":4},\"c\":5}";
          if !ok || out != exp { return assert(false, "json: merge deep semantics"); }
          var scalar = json_number(1.0);
          let ok2 = json_merge(&mut scalar, &ov);
          return assert(!ok2, "json: merge deep semantics");
        }
        Err(_) => return assert(false, "json: merge deep semantics"),
      }
    }
    Err(_) => return assert(false, "json: merge deep semantics"),
  }
}
fn t39() -> TestResult {
  var obj = json_object();
  json_object_put(&mut obj, "a", json_number(1.0));
  json_object_put(&mut obj, "a", json_number(2.0));
  let out = json_stringify(&obj);
  return assert(out == "{\"a\":2}", "json: object_put replaces existing key");
}

fn main() -> Int {
  io.println("=== XIOM JSON Conformance ===");
  var failed: Int = 0; var total: Int = 0;
  // Explicit per-test calls: `Vec[fn() -> TestResult]` element dispatch is
  // miscompiled on the pinned toolchain (element call lowers to Unit); the
  // green sibling suites use this same explicit pattern.
  total = total + 1; let r1 = t1(); failed = failed + report(r1.passed, r1.name);
  total = total + 1; let r2 = t2(); failed = failed + report(r2.passed, r2.name);
  total = total + 1; let r3 = t3(); failed = failed + report(r3.passed, r3.name);
  total = total + 1; let r4 = t4(); failed = failed + report(r4.passed, r4.name);
  total = total + 1; let r5 = t5(); failed = failed + report(r5.passed, r5.name);
  total = total + 1; let r6 = t6(); failed = failed + report(r6.passed, r6.name);
  total = total + 1; let r7 = t7(); failed = failed + report(r7.passed, r7.name);
  total = total + 1; let r8 = t8(); failed = failed + report(r8.passed, r8.name);
  total = total + 1; let r9 = t9(); failed = failed + report(r9.passed, r9.name);
  total = total + 1; let r10 = t10(); failed = failed + report(r10.passed, r10.name);
  total = total + 1; let r11 = t11(); failed = failed + report(r11.passed, r11.name);
  total = total + 1; let r12 = t12(); failed = failed + report(r12.passed, r12.name);
  total = total + 1; let r13 = t13(); failed = failed + report(r13.passed, r13.name);
  total = total + 1; let r14 = t14(); failed = failed + report(r14.passed, r14.name);
  total = total + 1; let r15 = t15(); failed = failed + report(r15.passed, r15.name);
  total = total + 1; let r16 = t16(); failed = failed + report(r16.passed, r16.name);
  total = total + 1; let r17 = t17(); failed = failed + report(r17.passed, r17.name);
  total = total + 1; let r18 = t18(); failed = failed + report(r18.passed, r18.name);
  total = total + 1; let r19 = t19(); failed = failed + report(r19.passed, r19.name);
  total = total + 1; let r20 = t20(); failed = failed + report(r20.passed, r20.name);
  total = total + 1; let r21 = t21(); failed = failed + report(r21.passed, r21.name);
  total = total + 1; let r22 = t22(); failed = failed + report(r22.passed, r22.name);
  total = total + 1; let r23 = t23(); failed = failed + report(r23.passed, r23.name);
  total = total + 1; let r24 = t24(); failed = failed + report(r24.passed, r24.name);
  total = total + 1; let r25 = t25(); failed = failed + report(r25.passed, r25.name);
  total = total + 1; let r26 = t26(); failed = failed + report(r26.passed, r26.name);
  total = total + 1; let r27 = t27(); failed = failed + report(r27.passed, r27.name);
  total = total + 1; let r28 = t28(); failed = failed + report(r28.passed, r28.name);
  total = total + 1; let r29 = t29(); failed = failed + report(r29.passed, r29.name);
  total = total + 1; let r30 = t30(); failed = failed + report(r30.passed, r30.name);
  total = total + 1; let r31 = t31(); failed = failed + report(r31.passed, r31.name);
  total = total + 1; let r32 = t32(); failed = failed + report(r32.passed, r32.name);
  total = total + 1; let r33 = t33(); failed = failed + report(r33.passed, r33.name);
  total = total + 1; let r34 = t34(); failed = failed + report(r34.passed, r34.name);
  total = total + 1; let r35 = t35(); failed = failed + report(r35.passed, r35.name);
  total = total + 1; let r36 = t36(); failed = failed + report(r36.passed, r36.name);
  total = total + 1; let r37 = t37(); failed = failed + report(r37.passed, r37.name);
  total = total + 1; let r38 = t38(); failed = failed + report(r38.passed, r38.name);
  total = total + 1; let r39 = t39(); failed = failed + report(r39.passed, r39.name);
  total = total + 1; let r40 = t40(); failed = failed + report(r40.passed, r40.name);
  total = total + 1; let r41 = t41(); failed = failed + report(r41.passed, r41.name);
  total = total + 1; let r42 = t42(); failed = failed + report(r42.passed, r42.name);
  total = total + 1; let r43 = t43(); failed = failed + report(r43.passed, r43.name);
  let passed = total - failed;
  io.println(""); io.println("XIOM JSON: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
