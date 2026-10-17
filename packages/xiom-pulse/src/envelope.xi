// XIOM PULSE -- uniform JSON error envelope.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Error responses are `{"error":{"code":"<code>","message":"<text>"}}`.
module xiom.pulse.envelope

use xiom.serialize.json;
use xiom.pulse.reqctx;

/// error_body builds the uniform error envelope
/// `{"error":{"code":"...","message":"...","rid":"..."}}`; `rid` is included
/// when the server has set a request id. Complexity: O(1). Pure.
pub fn error_body(code: Str, message: Str) -> Str {
  var inner = json.json_set(json.json_object_new(), "code", json.json_string(code));
  inner = json.json_set(inner, "message", json.json_string(message));
  let rid = reqctx.get_rid();
  if rid.len() > 0 {
    inner = json.json_set(inner, "rid", json.json_string(rid));
  }
  let outer = json.json_set(json.json_object_new(), "error", inner);
  return json.json_stringify(outer);
}

/// ok_bool returns `{"ok":true|false}`.
/// Complexity: O(1). Pure.
pub fn ok_bool(v: Bool) -> Str {
  return json.json_stringify(json.json_set(json.json_object_new(), "ok", json.json_bool(v)));
}

/// single_field returns `{"<key>":"<value>"}` (string value).
/// Complexity: O(1). Pure.
pub fn single_field(key: Str, value: Str) -> Str {
  return json.json_stringify(json.json_set(json.json_object_new(), key, json.json_string(value)));
}
