// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Repro candidate: iterating a JSON object's Map keys through a `match`
// enum binding inside a helper function, feeding each key to a Str
// validator (the shape that misbehaved inside `router_mapping_load` until
// entries.keys/values were copied to locals first -- XVC-C-16 family).
// Expected: exit 0 (both keys valid). Observed on the failing shape:
// the validator inside the loop reads garbage -> exit 1.

module probe_repro_object_key_iter

use xiom.serialize.json;
use xiom.string.slice;
use xiom.io;
use xiom.convert;

fn name_ok(name: Str) -> Bool {
  var b = slice.str_bytes(name);
  if b.len() < 1 || b.len() > 64 { return false; }
  var i: Int = 0;
  while i < b.len() {
    var c = b[i];
    var okc: Bool = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95 || c == 45 || c == 46;
    if !okc { return false; }
    i = i + 1;
  }
  return true;
}

// 0 = ok; -1 = a key failed validation inside the loop; -2/-3 = shape errors.
fn scan_map(doc: JsonValue) -> Int {
  var co = json.json_get(doc, "collections");
  var have: Bool = false;
  match co {
    Some(cv) => {
      if json.json_type(cv) != "object" { return -2; }
      match cv {
        Object(entries) => {
          var i: Int = 0;
          while i < entries.keys.len() {
            var name = entries.keys[i];
            io.println("    i=" + convert.int_to_string(i) + " key=[" + name + "]");
            if !name_ok(name) { return -1; }
            i = i + 1;
          }
        }
        _ => {}
      }
      have = true;
    }
    None => {}
  }
  if !have { return -3; }
  return 0;
}

fn main() -> Int {
  io.println("=== repro: object key iteration through match binding ===");
  var fails: Int = 0;
  var p = json.json_parse("{\"version\":1,\"shards\":[{\"id\":\"s1\",\"url\":\"u\"}],\"collections\":{\"docs\":\"s1\",\"logs\":\"s2\"}}");
  match p {
    Ok(doc) => {
      var rc = scan_map(doc);
      if rc != 0 { io.println("  [FAIL] scan_map rc=" + convert.int_to_string(rc)); fails = fails + 1; }
      else { io.println("  [PASS] scan_map ok"); }
    }
    Err(_) => {
      io.println("  [FAIL] parse");
      fails = fails + 1;
    }
  }
  io.println("repro_object_key_iter: " + convert.int_to_string(fails) + " failed checks");
  return fails;
}
