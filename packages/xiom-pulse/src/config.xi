// XIOM PULSE -- runtime configuration from environment.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Carved from the frozen PULSE core at 56eb9f8 (see PROVENANCE.md). Slimmed
// to exactly the loop knobs the carved server core reads: PULSE_PORT /
// PULSE_BIND for the listener, and PULSE_READ_TIMEOUT /
// PULSE_WRITE_TIMEOUT / PULSE_IDLE_TIMEOUT / PULSE_KEEPALIVE for the
// connection loop. Every product knob (uploads, site, jwt, store, game,
// cors, csrf, audit, log, openapi, rate limit, session ttl) and the
// PULSE_CONFIG file loader are dropped; the parse helpers and the getters
// below are verbatim from the frozen module.
module xiom.pulse.config

use xiom.env;

/// cfg_parse_port parses a decimal port, falling back to 8080.
/// Complexity: O(n). Pure.
fn cfg_parse_port(s: Str) -> Int {
  if s.len() == 0 { return 8080; }
  var v: Int = 0;
  var i: Int = 0;
  while i < s.len() {
    let b = s.byte_at(i);
    if b < 48u8 || b > 57u8 { return 8080; }
    v = v * 10 + ((b as Int) - 48);
    i = i + 1;
  }
  if v <= 0 || v > 65535 { return 8080; }
  return v;
}

/// cfg_parse_uint parses a non-negative decimal, or returns fallback.
/// Complexity: O(n). Pure.
fn cfg_parse_uint(s: Str, fallback: Int) -> Int {
  if s.len() == 0 { return fallback; }
  var v: Int = 0;
  var i: Int = 0;
  while i < s.len() {
    let b = s.byte_at(i);
    if b < 48u8 || b > 57u8 { return fallback; }
    v = v * 10 + ((b as Int) - 48);
    i = i + 1;
  }
  return v;
}

/// cfg_read_timeout returns the full-request read deadline in ms
/// (PULSE_READ_TIMEOUT, default 30000; 0 = no deadline, dev only).
/// Complexity: O(1). Pure.
pub fn cfg_read_timeout() -> Int {
  return cfg_parse_uint(env.var_or("PULSE_READ_TIMEOUT", "30000"), 30000);
}

/// cfg_write_timeout returns the response write deadline in ms
/// (PULSE_WRITE_TIMEOUT, default 30000; 0 = no deadline, dev only).
/// Complexity: O(1). Pure.
pub fn cfg_write_timeout() -> Int {
  return cfg_parse_uint(env.var_or("PULSE_WRITE_TIMEOUT", "30000"), 30000);
}

/// cfg_idle_timeout returns the keep-alive idle deadline in ms
/// (PULSE_IDLE_TIMEOUT, default 5000; honored from keep-alive Phase B).
/// Complexity: O(1). Pure.
pub fn cfg_idle_timeout() -> Int {
  return cfg_parse_uint(env.var_or("PULSE_IDLE_TIMEOUT", "5000"), 5000);
}

/// cfg_keepalive is false when PULSE_KEEPALIVE=0 (connection reuse is on
/// by default once Phase B landed; 0 restores close-per-request).
/// Complexity: O(1). Pure.
pub fn cfg_keepalive() -> Bool {
  return env.var_or("PULSE_KEEPALIVE", "1") != "0";
}

/// cfg_port returns the listen port (PULSE_PORT, default 8080).
/// Complexity: O(1). Pure.
pub fn cfg_port() -> Int {
  return cfg_parse_port(env.var_or("PULSE_PORT", "8080"));
}

/// cfg_bind returns the listen address (PULSE_BIND, default "127.0.0.1").
/// Keep the loopback default for host deployments behind a proxy (ops
/// requirement: the public surface stays 443-only); containers and the
/// benchmark harness may set 0.0.0.0 because the container network is the
/// isolation boundary there.
/// Complexity: O(1). Pure.
pub fn cfg_bind() -> Str {
  return env.var_or("PULSE_BIND", "127.0.0.1");
}
