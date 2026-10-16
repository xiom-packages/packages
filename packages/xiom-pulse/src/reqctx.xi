// XIOM PULSE -- per-request context (request id) for logs and error bodies.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The server sets the current request id before dispatch; the error
// envelope reads it so every error carries the same id as the access log.
module xiom.pulse.reqctx

var current_rid: Str = "";

/// set_rid sets the current request id ("" clears it).
/// Complexity: O(1).
pub fn set_rid(rid: Str) {
  current_rid = rid;
}

/// get_rid returns the current request id ("" when unset).
/// Complexity: O(1).
pub fn get_rid() -> Str {
  return current_rid;
}
