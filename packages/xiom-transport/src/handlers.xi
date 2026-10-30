// XIOM -- xiom.transport.handlers: ordered packet-handler chain
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A deterministic, value-semantic chain of payload handlers that layers can
// compose over datagrams or session payloads. The chain is plain data (no
// globals, no callbacks, no wall clock): handlers are small records with a
// kind discriminator, and the apply functions dispatch on that kind.
//
// Layering contract:
//   * outbound handlers run in registration order (index 0 first), so a
//     handler registered later wraps the bytes produced by the earlier ones;
//   * inbound handlers run in reverse registration order (last registered
//     first), so the same handlers registered in the same order undo the
//     outbound stack in the natural order;
//   * an empty chain, a chain disabled with handlers_set_enabled(false), or
//     a disabled entry is a byte-exact pass-through -- the default path is
//     unchanged.
//
// Kinds shipped here are deliberately sample transforms, not cryptography:
// HANDLER_KIND_NOOP (identity), HANDLER_KIND_PREFIX (prepend/verify a fixed
// tag, useful for framing or a resend/reservation header) and
// HANDLER_KIND_XOR (reversible byte mask, useful as a test double for a
// compression or encryption stage). A real compression/encryption adapter
// can be added as a new kind without changing the chain or its ordering
// rules; the chain itself never assumes a wire format.
//
// Language notes (XIOM v0.64.5): free functions only; Ok/Err construction
// confined to leaf helpers; every Vec element read binds a typed local; no
// Vec[fn] dispatch (the recorded miscompile class), so handlers are data and
// dispatch is an explicit kind switch.

module xiom.transport.handlers

// Handler kinds.
pub const HANDLER_KIND_NOOP: Int = 0;
pub const HANDLER_KIND_PREFIX: Int = 1;
pub const HANDLER_KIND_XOR: Int = 2;

// Stages (handlers_apply, handlers_set_handler_enabled).
pub const HANDLER_STAGE_OUTBOUND: Int = 1;
pub const HANDLER_STAGE_INBOUND: Int = 2;

// HandlerOutcome.code values (0 means the run succeeded).
pub const HANDLER_ERR_KIND: Int = 1;
pub const HANDLER_ERR_DECODE: Int = 2;
pub const HANDLER_ERR_STAGE: Int = 3;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// One handler record. `tag` is used by HANDLER_KIND_PREFIX and `key` by
/// HANDLER_KIND_XOR; the other field is ignored. `enabled` is per-entry so a
/// layer can be switched off without rebuilding the chain.
pub type PacketHandler = {
  id: Int;
  kind: Int;
  enabled: Bool;
  tag: Vec[UInt8];
  key: Vec[UInt8];
}

/// The chain: a global enable flag plus two ordered handler lists.
pub type HandlerChain = {
  enabled: Bool;
  outbound: Vec[PacketHandler];
  inbound: Vec[PacketHandler];
}

/// The result of one apply call: `ok` false with `failed_id` and `code`
/// identifies the handler that refused the bytes. On failure `bytes` is the
/// input unchanged (no handler after the failing one ran).
pub type HandlerOutcome = {
  ok: Bool;
  bytes: Vec[UInt8];
  failed_id: Int;
  code: Int;
}

// ---------------------------------------------------------------------------
// Leaf helpers
// ---------------------------------------------------------------------------

fn _houtcome(ok: Bool, bytes: Vec[UInt8], failed_id: Int, code: Int) -> HandlerOutcome {
  return HandlerOutcome { ok: ok; bytes: bytes; failed_id: failed_id; code: code; };
}

fn _copy_bytes(src: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    let b: UInt8 = src[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

fn _same_prefix(data: &Vec[UInt8], tag: &Vec[UInt8]) -> Bool {
  if tag.len() > data.len() { return false; }
  var i = 0;
  while i < tag.len() {
    let a: UInt8 = data[i];
    let b: UInt8 = tag[i];
    if a != b { return false; }
    i = i + 1;
  }
  return true;
}

fn _with_prefix(tag: &Vec[UInt8], data: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < tag.len() {
    let b: UInt8 = tag[i];
    out.push(b);
    i = i + 1;
  }
  i = 0;
  while i < data.len() {
    let b: UInt8 = data[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

fn _without_prefix(tag: &Vec[UInt8], data: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = tag.len();
  while i < data.len() {
    let b: UInt8 = data[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

fn _xor_bytes(key: &Vec[UInt8], data: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  if key.len() == 0 {
    return _copy_bytes(data);
  }
  var i = 0;
  while i < data.len() {
    let b: UInt8 = data[i];
    let k: UInt8 = key[i % key.len()];
    let v = (b as Int) & 255;
    let kv = (k as Int) & 255;
    out.push(((v ^ kv) & 255) as UInt8);
    i = i + 1;
  }
  return out;
}

// Apply one handler to bytes. `outbound` selects the direction for kinds
// whose inverse is direction-dependent (PREFIX).
fn _apply_one(h: &PacketHandler, outbound: Bool, bytes: &Vec[UInt8]) -> HandlerOutcome {
  if !h.enabled {
    return _houtcome(true, _copy_bytes(bytes), -1, 0);
  }
  if h.kind == HANDLER_KIND_NOOP {
    return _houtcome(true, _copy_bytes(bytes), -1, 0);
  }
  if h.kind == HANDLER_KIND_PREFIX {
    if outbound {
      return _houtcome(true, _with_prefix(&h.tag, bytes), -1, 0);
    }
    if !_same_prefix(bytes, &h.tag) {
      return _houtcome(false, _copy_bytes(bytes), h.id, HANDLER_ERR_DECODE);
    }
    return _houtcome(true, _without_prefix(&h.tag, bytes), -1, 0);
  }
  if h.kind == HANDLER_KIND_XOR {
    return _houtcome(true, _xor_bytes(&h.key, bytes), -1, 0);
  }
  return _houtcome(false, _copy_bytes(bytes), h.id, HANDLER_ERR_KIND);
}

// Run one list. Inbound lists unwind in reverse registration order.
fn _run(list: &Vec[PacketHandler], reverse: Bool, bytes: &Vec[UInt8]) -> HandlerOutcome {
  var current = _copy_bytes(bytes);
  var i = 0;
  while i < list.len() {
    var idx = i;
    if reverse { idx = list.len() - 1 - i; }
    let h: PacketHandler = list[idx];
    let step = _apply_one(&h, !reverse, &current);
    if !step.ok {
      return step;
    }
    current = step.bytes;
    i = i + 1;
  }
  return _houtcome(true, current, -1, 0);
}

fn _list_empty(list: &Vec[PacketHandler]) -> Bool {
  if list.len() == 0 { return true; }
  return false;
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

/// A new, enabled chain with no handlers (the no-op default).
pub fn handlers_new() -> HandlerChain {
  var outbound: Vec[PacketHandler] = Vec[PacketHandler].new();
  var inbound: Vec[PacketHandler] = Vec[PacketHandler].new();
  return HandlerChain { enabled: true; outbound: outbound; inbound: inbound; };
}

/// Identity handler: passes bytes through unchanged.
pub fn handlers_noop(id: Int) -> PacketHandler {
  var empty_tag: Vec[UInt8] = Vec[UInt8].new();
  var empty_key: Vec[UInt8] = Vec[UInt8].new();
  return PacketHandler { id: id; kind: HANDLER_KIND_NOOP; enabled: true; tag: empty_tag; key: empty_key; };
}

/// Prefix handler: outbound prepends `tag`; inbound verifies and strips it.
pub fn handlers_prefix(id: Int, tag: Vec[UInt8]) -> PacketHandler {
  var empty_key: Vec[UInt8] = Vec[UInt8].new();
  return PacketHandler { id: id; kind: HANDLER_KIND_PREFIX; enabled: true; tag: tag; key: empty_key; };
}

/// XOR-mask handler: reversible byte transform with a repeating key. This is
/// a sample/test-double for a real compression or encryption layer, not a
/// security primitive.
pub fn handlers_xor(id: Int, key: Vec[UInt8]) -> PacketHandler {
  var empty_tag: Vec[UInt8] = Vec[UInt8].new();
  return PacketHandler { id: id; kind: HANDLER_KIND_XOR; enabled: true; tag: empty_tag; key: key; };
}

// ---------------------------------------------------------------------------
// Registration, ordering and enable/clear
// ---------------------------------------------------------------------------

pub fn handlers_is_enabled(c: &HandlerChain) -> Bool {
  return c.enabled;
}

pub fn handlers_set_enabled(c: &mut HandlerChain, enabled: Bool) {
  c.enabled = enabled;
}

pub fn handlers_outbound_len(c: &HandlerChain) -> Int {
  return c.outbound.len();
}

pub fn handlers_inbound_len(c: &HandlerChain) -> Int {
  return c.inbound.len();
}

/// Append an outbound handler; returns its index in the list.
pub fn handlers_register_outbound(c: &mut HandlerChain, h: PacketHandler) -> Int {
  let idx = c.outbound.len();
  c.outbound.push(h);
  return idx;
}

/// Append an inbound handler; returns its index in the list. Inbound apply
/// runs this list in reverse, so the same registration order as the outbound
/// list unwinds the layers correctly.
pub fn handlers_register_inbound(c: &mut HandlerChain, h: PacketHandler) -> Int {
  let idx = c.inbound.len();
  c.inbound.push(h);
  return idx;
}

/// Insert an outbound handler at an explicit index (clamped to [0, len]).
pub fn handlers_insert_outbound(c: &mut HandlerChain, index: Int, h: PacketHandler) -> Bool {
  var idx = index;
  if idx < 0 { idx = 0; }
  if idx > c.outbound.len() { idx = c.outbound.len(); }
  c.outbound.insert(idx, h);
  return true;
}

/// Insert an inbound handler at an explicit index (clamped to [0, len]).
pub fn handlers_insert_inbound(c: &mut HandlerChain, index: Int, h: PacketHandler) -> Bool {
  var idx = index;
  if idx < 0 { idx = 0; }
  if idx > c.inbound.len() { idx = c.inbound.len(); }
  c.inbound.insert(idx, h);
  return true;
}

/// Enable or disable one entry by stage and index; false when out of range.
pub fn handlers_set_handler_enabled(c: &mut HandlerChain, stage: Int, index: Int, enabled: Bool) -> Bool {
  if stage == HANDLER_STAGE_OUTBOUND {
    if index < 0 || index >= c.outbound.len() { return false; }
    var h: PacketHandler = c.outbound[index];
    h.enabled = enabled;
    c.outbound[index] = h;
    return true;
  }
  if stage == HANDLER_STAGE_INBOUND {
    if index < 0 || index >= c.inbound.len() { return false; }
    var h: PacketHandler = c.inbound[index];
    h.enabled = enabled;
    c.inbound[index] = h;
    return true;
  }
  return false;
}

pub fn handlers_clear_outbound(c: &mut HandlerChain) {
  var empty: Vec[PacketHandler] = Vec[PacketHandler].new();
  c.outbound = empty;
}

pub fn handlers_clear_inbound(c: &mut HandlerChain) {
  var empty: Vec[PacketHandler] = Vec[PacketHandler].new();
  c.inbound = empty;
}

/// Clear both lists and re-enable the chain (a clean no-op default).
pub fn handlers_clear(c: &mut HandlerChain) {
  handlers_clear_outbound(c);
  handlers_clear_inbound(c);
  c.enabled = true;
}

// ---------------------------------------------------------------------------
// Apply
// ---------------------------------------------------------------------------

/// Run the outbound stack in registration order. A chain that is disabled,
/// or has no outbound handlers, returns the input byte-exact.
pub fn handlers_apply_outbound(c: &HandlerChain, bytes: &Vec[UInt8]) -> HandlerOutcome {
  if !c.enabled {
    return _houtcome(true, _copy_bytes(bytes), -1, 0);
  }
  if _list_empty(&c.outbound) {
    return _houtcome(true, _copy_bytes(bytes), -1, 0);
  }
  return _run(&c.outbound, false, bytes);
}

/// Run the inbound stack in reverse registration order. A chain that is
/// disabled, or has no inbound handlers, returns the input byte-exact.
pub fn handlers_apply_inbound(c: &HandlerChain, bytes: &Vec[UInt8]) -> HandlerOutcome {
  if !c.enabled {
    return _houtcome(true, _copy_bytes(bytes), -1, 0);
  }
  if _list_empty(&c.inbound) {
    return _houtcome(true, _copy_bytes(bytes), -1, 0);
  }
  return _run(&c.inbound, true, bytes);
}

/// Stage-selected apply (HANDLER_STAGE_OUTBOUND / HANDLER_STAGE_INBOUND). An
/// unknown stage is a typed refusal with the input unchanged.
pub fn handlers_apply(c: &HandlerChain, stage: Int, bytes: &Vec[UInt8]) -> HandlerOutcome {
  if stage == HANDLER_STAGE_OUTBOUND {
    return handlers_apply_outbound(c, bytes);
  }
  if stage == HANDLER_STAGE_INBOUND {
    return handlers_apply_inbound(c, bytes);
  }
  return _houtcome(false, _copy_bytes(bytes), -1, HANDLER_ERR_STAGE);
}
