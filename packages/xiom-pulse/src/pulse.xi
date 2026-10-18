module xiom.pulse

// XIOM PULSE -- project root module.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0

/// PULSE_PACKAGE_VERSION is the single source of truth for the package
/// release version. Keep it in sync with the `version:` field in package.xi;
/// the conformance suite pins the accessor to it.
const PULSE_PACKAGE_VERSION: Str = "0.2.2";

/// pulse_version returns the PULSE package version string (0.2.2). The
/// response Server header is deliberately NOT derived from this value: it
/// carries the neutral, consumer-configurable token from
/// `xiom.pulse.http.server_token()` (default "xiom-pulse").
/// Complexity: O(1). Pure.
pub fn pulse_version() -> Str
  ensures: result.len() > 0
{
  PULSE_PACKAGE_VERSION
}
