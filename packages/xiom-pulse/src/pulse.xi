module xiom.pulse

// XIOM PULSE -- project root module.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

/// pulse_version returns the PULSE project version string.
/// Complexity: O(1). Pure.
pub fn pulse_version() -> Str
  ensures: result.len() > 0
{
  "0.2.1"
}
