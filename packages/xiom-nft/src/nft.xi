// XIOM -- xiom.nft: deterministic NFT registry model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM, deterministic MODEL of a non-fungible token registry. It
// performs no cryptography, no hashing and no networking. Collection names,
// creators, owners, spenders, operators and event actors are opaque
// caller-supplied strings that are only validated structurally (non-empty,
// bounded byte length, no control bytes) and stored.
//
//   * Collections: unique name, creator, royalty basis points (0..10000),
//     recorded live supply and all-time minted count.
//   * Tokens: positive globally-unique token id, collection, last owner,
//     minted tick, live/burned status and burn tick.
//   * Ownership: exactly one owner per token at any time. Transfers are
//     authorized by the current owner, by an unexpired per-token approval
//     granted by the current owner, or by an unexpired operator granted by
//     the current owner. A transfer to the current owner is rejected.
//   * Approvals: append-only rows; the latest row for a (token, spender)
//     pair is authoritative. A row is valid iff its token is live, its
//     grantor is still the current owner and expiry_tick >= tick.
//   * Operators: append-only rows; the latest row for an (owner, operator)
//     pair is authoritative. A row is valid iff expiry_tick >= tick.
//     operator_revoke appends an already-expired row.
//   * Royalties: creator amount = floor(sale_price * bps / 10000)
//     computed overflow-free; seller amount = sale_price - creator amount.
//   * Events: canonical append-only log with strict sequence numbers 1..N
//     (mint, transfer, approve, burn); every token mutation (mint, transfer,
//     burn) and every per-token approval appends exactly one event.
//     Operator grants and revocations are recorded as operator rows (with
//     expiry ticks) and do not append events.
//   * Invariants: nft_registry_valid checks parallel-vector consistency,
//     globally unique token ids, live/burned supply accounting, collection
//     counters, reference validity and strictly increasing event sequences.
//
// Language notes (compiler v0.62.2): free functions only; no self methods,
// no lambdas, no Vec of struct or Str element types (the registry uses
// parallel Vec[Int] fields and one shared Str text store with Vec[Int]
// offset/length rows); Vec[Str].push is not used anywhere; Result
// construction is confined to the leaf helpers below; Str values are
// compared with str_compare, never with `==`; every Vec element read is
// bound to a typed local first; a Vec element is never assigned in place
// (vectors are rebuilt instead); every loop has a guaranteed progress step;
// Int division calls use the q/r form.

module xiom.nft

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (leaf helpers; see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Maximum collection-name length, in bytes.
pub const NFT_MAX_NAME_LEN: Int = 64;

/// Maximum owner / creator / spender / operator / burner length, in bytes.
pub const NFT_MAX_IDENTITY_LEN: Int = 128;

/// Royalty basis points denominator and maximum.
pub const NFT_MAX_BPS: Int = 10000;

/// Largest platform Int (2^63 - 1); royalty arithmetic never exceeds it.
pub const NFT_INT64_MAX: Int = 9223372036854775807;

/// Token status: live (transferable, burnable).
pub const NFT_TOKEN_LIVE: Int = 0;

/// Token status: burned (final; the id is never reused).
pub const NFT_TOKEN_BURNED: Int = 1;

/// Event kind: mint.
pub const NFT_EVENT_MINT: Int = 1;

/// Event kind: transfer.
pub const NFT_EVENT_TRANSFER: Int = 2;

/// Event kind: approve (also emitted for operator grants and revocations).
pub const NFT_EVENT_APPROVE: Int = 3;

/// Event kind: burn.
pub const NFT_EVENT_BURN: Int = 4;

// --------------------------------------------------
//  Shared text store
// --------------------------------------------------

/// Append `v` to the registry text store and return its row id. Row ids are
/// stable and never reused.
fn _text_add(reg: &mut NftRegistry, v: Str) -> Int {
  let off = reg.text.len();
  reg.text = reg.text + v;
  reg.text_start.push(off);
  reg.text_len.push(string.str_len(v));
  return reg.text_start.len() - 1;
}

/// Text stored at row id; "" when out of range.
fn _text_get(reg: &NftRegistry, id: Int) -> Str {
  if id < 0 || id >= reg.text_len.len() {
    return "";
  }
  let st: Int = reg.text_start[id];
  let ln: Int = reg.text_len[id];
  return string.str_slice(reg.text, st, st + ln);
}

// --------------------------------------------------
//  Structural validation helpers
// --------------------------------------------------

// Validate a non-empty text whose bytes must not be control characters
// (0x00..0x1F and 0x7F). Returns the text or Err("nft: ...").
fn _validate_text(s: Str, kind: Str, maxlen: Int) -> Result[Str, Str] {
  let n = string.str_len(s);
  if n == 0 {
    return _err_str("nft: empty " + kind);
  }
  if n > maxlen {
    return _err_str("nft: " + kind + " too long (max " + convert.int_to_string(maxlen) + " bytes)");
  }
  var i = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b < 32 || b == 127 {
      return _err_str("nft: " + kind + " contains control character at offset " + convert.int_to_string(i));
    }
    i = i + 1;
  }
  return _ok_str(s);
}

// Validate an owner-like identity (owner, creator, sender, recipient,
// burner); same rules as _validate_text with the "owner" kind.
fn _validate_owner(s: Str) -> Result[Str, Str] {
  return _validate_text(s, "owner", NFT_MAX_IDENTITY_LEN);
}

// Rebuild `v` with element `idx` replaced by `val`. Returns the new vector;
// the caller assigns it back to the field. Elements are never assigned in
// place (see the module header).
fn _vec_set(v: &Vec[Int], idx: Int, val: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < v.len() {
    if i == idx {
      out.push(val);
    } else {
      let old: Int = v[i];
      out.push(old);
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Registry
// --------------------------------------------------

/// A deterministic NFT registry. All vectors are append-only parallel rows;
/// every vector of a section has exactly the section's count elements for
/// any registry produced by the mutating functions (nft_registry_valid
/// checks this).
pub type NftRegistry = {
  // shared string store
  text: Str;
  text_start: Vec[Int];
  text_len: Vec[Int];
  // collections
  coll_count: Int;
  coll_name_text: Vec[Int];
  coll_creator_text: Vec[Int];
  coll_royalty_bps: Vec[Int];
  coll_live: Vec[Int];
  // tokens (rows are append-only; status changes on burn)
  token_count: Int;
  token_id: Vec[Int];
  token_collection: Vec[Int];
  token_owner_text: Vec[Int];
  token_minted_tick: Vec[Int];
  token_burn_tick: Vec[Int];
  token_status: Vec[Int];
  // approvals (latest row per token/spender wins)
  appr_count: Int;
  appr_token: Vec[Int];
  appr_owner_text: Vec[Int];
  appr_spender_text: Vec[Int];
  appr_expiry: Vec[Int];
  // operators (latest row per owner/operator wins)
  oper_count: Int;
  oper_owner_text: Vec[Int];
  oper_operator_text: Vec[Int];
  oper_expiry: Vec[Int];
  // canonical event log (sequence 1..event_count)
  event_count: Int;
  event_seq: Vec[Int];
  event_kind: Vec[Int];
  event_token_id: Vec[Int];
  event_collection: Vec[Int];
  event_actor_text: Vec[Int];
  event_to_text: Vec[Int];
  event_tick: Vec[Int];
}

/// An empty registry: no collections, tokens, approvals, operators or
/// events.
pub fn nft_registry_new() -> NftRegistry {
  return NftRegistry{
    text: "";
    text_start: Vec[Int].new();
    text_len: Vec[Int].new();
    coll_count: 0;
    coll_name_text: Vec[Int].new();
    coll_creator_text: Vec[Int].new();
    coll_royalty_bps: Vec[Int].new();
    coll_live: Vec[Int].new();
    token_count: 0;
    token_id: Vec[Int].new();
    token_collection: Vec[Int].new();
    token_owner_text: Vec[Int].new();
    token_minted_tick: Vec[Int].new();
    token_burn_tick: Vec[Int].new();
    token_status: Vec[Int].new();
    appr_count: 0;
    appr_token: Vec[Int].new();
    appr_owner_text: Vec[Int].new();
    appr_spender_text: Vec[Int].new();
    appr_expiry: Vec[Int].new();
    oper_count: 0;
    oper_owner_text: Vec[Int].new();
    oper_operator_text: Vec[Int].new();
    oper_expiry: Vec[Int].new();
    event_count: 0;
    event_seq: Vec[Int].new();
    event_kind: Vec[Int].new();
    event_token_id: Vec[Int].new();
    event_collection: Vec[Int].new();
    event_actor_text: Vec[Int].new();
    event_to_text: Vec[Int].new();
    event_tick: Vec[Int].new();
  };
}

// --------------------------------------------------
//  Internal row helpers
// --------------------------------------------------

// Row index of the token with id `token_id`; -1 when absent. Burned tokens
// keep their row (ids are never reused), so this finds them too.
fn _token_row(reg: &NftRegistry, token_id: Int) -> Int {
  var i = 0;
  while i < reg.token_count {
    if i < reg.token_id.len() {
      let v: Int = reg.token_id[i];
      if v == token_id {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// True when `row` is a live token row.
fn _token_live_row(reg: &NftRegistry, row: Int) -> Bool {
  if row < 0 || row >= reg.token_count || row >= reg.token_status.len() {
    return false;
  }
  let st: Int = reg.token_status[row];
  if st == NFT_TOKEN_LIVE {
    return true;
  }
  return false;
}

// Last owner text of token row `row`; "" when out of range.
fn _token_owner_row(reg: &NftRegistry, row: Int) -> Str {
  if row < 0 || row >= reg.token_count || row >= reg.token_owner_text.len() {
    return "";
  }
  let id: Int = reg.token_owner_text[row];
  return _text_get(reg, id);
}

// Collection index of token row `row`; -1 when out of range.
fn _token_collection_row(reg: &NftRegistry, row: Int) -> Int {
  if row < 0 || row >= reg.token_count || row >= reg.token_collection.len() {
    return -1;
  }
  let c: Int = reg.token_collection[row];
  return c;
}

// Rebuild token_owner_text with row `row` set to `text_id`.
fn _token_owner_set(reg: &mut NftRegistry, row: Int, text_id: Int) {
  var rebuilt = Vec[Int].new();
  var i = 0;
  while i < reg.token_owner_text.len() {
    if i == row {
      rebuilt.push(text_id);
    } else {
      let old: Int = reg.token_owner_text[i];
      rebuilt.push(old);
    }
    i = i + 1;
  }
  reg.token_owner_text = rebuilt;
}

// Rebuild token_status with row `row` set to `status`.
fn _token_status_set(reg: &mut NftRegistry, row: Int, status: Int) {
  var rebuilt = Vec[Int].new();
  var i = 0;
  while i < reg.token_status.len() {
    if i == row {
      rebuilt.push(status);
    } else {
      let old: Int = reg.token_status[i];
      rebuilt.push(old);
    }
    i = i + 1;
  }
  reg.token_status = rebuilt;
}

// Rebuild token_burn_tick with row `row` set to `tick`.
fn _token_burn_set(reg: &mut NftRegistry, row: Int, tick: Int) {
  var rebuilt = Vec[Int].new();
  var i = 0;
  while i < reg.token_burn_tick.len() {
    if i == row {
      rebuilt.push(tick);
    } else {
      let old: Int = reg.token_burn_tick[i];
      rebuilt.push(old);
    }
    i = i + 1;
  }
  reg.token_burn_tick = rebuilt;
}

// Append one canonical event and return its sequence number.
fn _event_push(reg: &mut NftRegistry, kind: Int, token_id: Int, collection: Int, actor_text: Int, to_text: Int, tick: Int) -> Int {
  let seq = reg.event_count + 1;
  reg.event_seq.push(seq);
  reg.event_kind.push(kind);
  reg.event_token_id.push(token_id);
  reg.event_collection.push(collection);
  reg.event_actor_text.push(actor_text);
  reg.event_to_text.push(to_text);
  reg.event_tick.push(tick);
  reg.event_count = reg.event_count + 1;
  return seq;
}

// Number of live tokens (scan).
fn _live_count(reg: &NftRegistry) -> Int {
  var n = 0;
  var i = 0;
  while i < reg.token_count {
    if i < reg.token_status.len() {
      let st: Int = reg.token_status[i];
      if st == NFT_TOKEN_LIVE {
        n = n + 1;
      }
    }
    i = i + 1;
  }
  return n;
}

// Number of burned tokens (scan).
fn _burned_count(reg: &NftRegistry) -> Int {
  var n = 0;
  var i = 0;
  while i < reg.token_count {
    if i < reg.token_status.len() {
      let st: Int = reg.token_status[i];
      if st == NFT_TOKEN_BURNED {
        n = n + 1;
      }
    }
    i = i + 1;
  }
  return n;
}

// Actual number of live tokens recorded in collection `collection`.
fn _coll_actual_live(reg: &NftRegistry, collection: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < reg.token_count {
    if i < reg.token_collection.len() && i < reg.token_status.len() {
      let c: Int = reg.token_collection[i];
      let st: Int = reg.token_status[i];
      if c == collection && st == NFT_TOKEN_LIVE {
        n = n + 1;
      }
    }
    i = i + 1;
  }
  return n;
}

// All-time minted count of collection `collection` (live + burned rows).
fn _coll_minted_count(reg: &NftRegistry, collection: Int) -> Int {
  var n = 0;
  var i = 0;
  while i < reg.token_count {
    if i < reg.token_collection.len() {
      let c: Int = reg.token_collection[i];
      if c == collection {
        n = n + 1;
      }
    }
    i = i + 1;
  }
  return n;
}

// --------------------------------------------------
//  Collections
// --------------------------------------------------

/// Number of collections.
pub fn nft_collection_count(reg: &NftRegistry) -> Int {
  return reg.coll_count;
}

/// Index of the collection named `name`; -1 when absent.
pub fn nft_collection_find(reg: &NftRegistry, name: Str) -> Int {
  var i = 0;
  while i < reg.coll_count {
    if i < reg.coll_name_text.len() {
      let id: Int = reg.coll_name_text[i];
      let stored = _text_get(reg, id);
      if str_compare(stored, name) == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Register a collection and return its index. Names are unique and must be
/// non-empty, control-free and at most 64 bytes; creators are non-empty,
/// control-free and at most 128 bytes; royalty_bps is 0..10000.
/// Errors, in this order: collection-name validation errors ("nft: empty
/// collection name", "nft: collection name too long (max 64 bytes)", "nft:
/// collection name contains control character at offset N"), creator
/// validation errors ("nft: empty creator", "nft: creator too long (max 128
/// bytes)", "nft: creator contains control character at offset N"), "nft:
/// royalty basis points out of range (0..10000)", "nft: duplicate
/// collection name".
pub fn nft_collection_add(reg: &mut NftRegistry, name: Str, creator: Str, royalty_bps: Int) -> Result[Int, Str] {
  let nv = _validate_text(name, "collection name", NFT_MAX_NAME_LEN);
  if !nv.is_ok {
    return _err_int(nv.error);
  }
  let cv = _validate_text(creator, "creator", NFT_MAX_IDENTITY_LEN);
  if !cv.is_ok {
    return _err_int(cv.error);
  }
  if royalty_bps < 0 || royalty_bps > NFT_MAX_BPS {
    return _err_int("nft: royalty basis points out of range (0..10000)");
  }
  if nft_collection_find(reg, name) >= 0 {
    return _err_int("nft: duplicate collection name");
  }
  let nid = _text_add(reg, name);
  let cid = _text_add(reg, creator);
  reg.coll_name_text.push(nid);
  reg.coll_creator_text.push(cid);
  reg.coll_royalty_bps.push(royalty_bps);
  reg.coll_live.push(0);
  reg.coll_count = reg.coll_count + 1;
  return _ok_int(reg.coll_count - 1);
}

/// Name of collection `i`; "" when out of range.
pub fn nft_collection_name(reg: &NftRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.coll_count || i >= reg.coll_name_text.len() {
    return "";
  }
  let id: Int = reg.coll_name_text[i];
  return _text_get(reg, id);
}

/// Creator of collection `i`; "" when out of range.
pub fn nft_collection_creator(reg: &NftRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.coll_count || i >= reg.coll_creator_text.len() {
    return "";
  }
  let id: Int = reg.coll_creator_text[i];
  return _text_get(reg, id);
}

/// Royalty basis points of collection `i` (0..10000); -1 when out of range.
pub fn nft_collection_royalty_bps(reg: &NftRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.coll_count || i >= reg.coll_royalty_bps.len() {
    return -1;
  }
  let v: Int = reg.coll_royalty_bps[i];
  return v;
}

/// Recorded live supply of collection `i`; -1 when out of range.
pub fn nft_collection_live_count(reg: &NftRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.coll_count || i >= reg.coll_live.len() {
    return -1;
  }
  let v: Int = reg.coll_live[i];
  return v;
}

/// All-time minted count of collection `i` (live + burned); -1 when out of
/// range.
pub fn nft_collection_minted_count(reg: &NftRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.coll_count {
    return -1;
  }
  return _coll_minted_count(reg, i);
}

// --------------------------------------------------
//  Tokens
// --------------------------------------------------

/// Number of token rows (all-time mints; burned tokens keep their row).
pub fn nft_token_count(reg: &NftRegistry) -> Int {
  return reg.token_count;
}

/// Number of live tokens.
pub fn nft_live_supply(reg: &NftRegistry) -> Int {
  return _live_count(reg);
}

/// Number of burned tokens.
pub fn nft_burned_supply(reg: &NftRegistry) -> Int {
  return _burned_count(reg);
}

/// Row index of `token_id`; -1 when unknown.
pub fn nft_token_row(reg: &NftRegistry, token_id: Int) -> Int {
  return _token_row(reg, token_id);
}

/// True when a token row with this id exists (live or burned).
pub fn nft_token_exists(reg: &NftRegistry, token_id: Int) -> Bool {
  if _token_row(reg, token_id) >= 0 {
    return true;
  }
  return false;
}

/// True when a token row with this id exists and is live.
pub fn nft_token_is_live(reg: &NftRegistry, token_id: Int) -> Bool {
  let row = _token_row(reg, token_id);
  if row < 0 {
    return false;
  }
  return _token_live_row(reg, row);
}

/// Mint token `token_id` into `collection` for `owner` at `tick` and return
/// the new token row index. Token ids must be positive and globally unique
/// forever (burning does not free an id).
/// Errors, in this order: "nft: unknown collection"; "nft: token id must be
/// positive"; owner validation errors ("nft: empty owner", "nft: owner too
/// long (max 128 bytes)", "nft: owner contains control character at offset
/// N"); "nft: negative tick"; "nft: duplicate token id".
pub fn nft_mint(reg: &mut NftRegistry, collection: Int, token_id: Int, owner: Str, tick: Int) -> Result[Int, Str] {
  if collection < 0 || collection >= reg.coll_count {
    return _err_int("nft: unknown collection");
  }
  if token_id <= 0 {
    return _err_int("nft: token id must be positive");
  }
  let ov = _validate_owner(owner);
  if !ov.is_ok {
    return _err_int(ov.error);
  }
  if tick < 0 {
    return _err_int("nft: negative tick");
  }
  if _token_row(reg, token_id) >= 0 {
    return _err_int("nft: duplicate token id");
  }
  let oid = _text_add(reg, owner);
  let row = reg.token_count;
  reg.token_id.push(token_id);
  reg.token_collection.push(collection);
  reg.token_owner_text.push(oid);
  reg.token_minted_tick.push(tick);
  reg.token_burn_tick.push(-1);
  reg.token_status.push(NFT_TOKEN_LIVE);
  reg.token_count = reg.token_count + 1;
  let live_now: Int = reg.coll_live[collection];
  let live_src: Vec[Int] = reg.coll_live;
  reg.coll_live = _vec_set(&live_src, collection, live_now + 1);
  _event_push(reg, NFT_EVENT_MINT, token_id, collection, oid, oid, tick);
  return _ok_int(row);
}

/// Last owner of `token_id` (burned tokens keep their final owner); ""
/// when unknown.
pub fn nft_token_owner(reg: &NftRegistry, token_id: Int) -> Str {
  let row = _token_row(reg, token_id);
  if row < 0 {
    return "";
  }
  return _token_owner_row(reg, row);
}

/// Collection index of `token_id`; -1 when unknown.
pub fn nft_token_collection(reg: &NftRegistry, token_id: Int) -> Int {
  let row = _token_row(reg, token_id);
  if row < 0 {
    return -1;
  }
  return _token_collection_row(reg, row);
}

/// Mint tick of `token_id`; -1 when unknown.
pub fn nft_token_minted_tick(reg: &NftRegistry, token_id: Int) -> Int {
  let row = _token_row(reg, token_id);
  if row < 0 || row >= reg.token_minted_tick.len() {
    return -1;
  }
  let v: Int = reg.token_minted_tick[row];
  return v;
}

/// Burn tick of `token_id`; -1 when unknown or still live.
pub fn nft_token_burn_tick(reg: &NftRegistry, token_id: Int) -> Int {
  let row = _token_row(reg, token_id);
  if row < 0 || row >= reg.token_burn_tick.len() {
    return -1;
  }
  let v: Int = reg.token_burn_tick[row];
  return v;
}

// True when `actor` may act on live token row `row` at `tick`: the actor is
// the current owner, holds a valid approval, or is a valid operator.
fn _authorized_row(reg: &NftRegistry, row: Int, actor: Str, tick: Int) -> Bool {
  if !_token_live_row(reg, row) {
    return false;
  }
  let owner = _token_owner_row(reg, row);
  if str_compare(owner, actor) == 0 {
    return true;
  }
  let tid: Int = reg.token_id[row];
  if nft_approval_valid_for(reg, tid, actor, tick) {
    return true;
  }
  if nft_is_operator(reg, owner, actor, tick) {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Transfers and burns
// --------------------------------------------------

/// Transfer live token `token_id` from `from` to `to` at `tick` and return
/// the sequence number of the appended TRANSFER event. `from` must be
/// authorized (current owner, valid approval or valid operator). The
/// approval is implicitly invalidated when the owner changes because a
/// valid approval requires its grantor to still be the current owner.
/// Errors, in this order: "nft: unknown token"; "nft: token is burned";
/// "nft: negative tick"; sender validation errors ("nft: empty sender",
/// "nft: sender too long (max 128 bytes)", "nft: sender contains control
/// character at offset N"); recipient validation errors ("nft: empty
/// recipient", "nft: recipient too long (max 128 bytes)", "nft: recipient
/// contains control character at offset N"); "nft: sender not authorized";
/// "nft: transfer to current owner".
pub fn nft_transfer(reg: &mut NftRegistry, token_id: Int, from: Str, to: Str, tick: Int) -> Result[Int, Str] {
  let row = _token_row(reg, token_id);
  if row < 0 {
    return _err_int("nft: unknown token");
  }
  if !_token_live_row(reg, row) {
    return _err_int("nft: token is burned");
  }
  if tick < 0 {
    return _err_int("nft: negative tick");
  }
  let fv = _validate_text(from, "sender", NFT_MAX_IDENTITY_LEN);
  if !fv.is_ok {
    return _err_int(fv.error);
  }
  let tv = _validate_text(to, "recipient", NFT_MAX_IDENTITY_LEN);
  if !tv.is_ok {
    return _err_int(tv.error);
  }
  if !_authorized_row(reg, row, from, tick) {
    return _err_int("nft: sender not authorized");
  }
  let owner = _token_owner_row(reg, row);
  if str_compare(owner, to) == 0 {
    return _err_int("nft: transfer to current owner");
  }
  let from_id = _text_add(reg, from);
  let to_id = _text_add(reg, to);
  _token_owner_set(reg, row, to_id);
  let coll = _token_collection_row(reg, row);
  let seq = _event_push(reg, NFT_EVENT_TRANSFER, token_id, coll, from_id, to_id, tick);
  return _ok_int(seq);
}

/// Burn live token `token_id` at `tick` and return the sequence number of
/// the appended BURN event. `burner` must be authorized (current owner,
/// valid approval or valid operator). The token row, its id, its last owner
/// and its burn tick are retained; the id is never reused.
/// Errors, in this order: "nft: unknown token"; "nft: token is burned";
/// "nft: negative tick"; burner validation errors ("nft: empty burner",
/// "nft: burner too long (max 128 bytes)", "nft: burner contains control
/// character at offset N"); "nft: burner not authorized".
pub fn nft_burn(reg: &mut NftRegistry, token_id: Int, burner: Str, tick: Int) -> Result[Int, Str] {
  let row = _token_row(reg, token_id);
  if row < 0 {
    return _err_int("nft: unknown token");
  }
  if !_token_live_row(reg, row) {
    return _err_int("nft: token is burned");
  }
  if tick < 0 {
    return _err_int("nft: negative tick");
  }
  let bv = _validate_text(burner, "burner", NFT_MAX_IDENTITY_LEN);
  if !bv.is_ok {
    return _err_int(bv.error);
  }
  if !_authorized_row(reg, row, burner, tick) {
    return _err_int("nft: burner not authorized");
  }
  let coll = _token_collection_row(reg, row);
  let owner_id: Int = reg.token_owner_text[row];
  let burner_id = _text_add(reg, burner);
  _token_status_set(reg, row, NFT_TOKEN_BURNED);
  _token_burn_set(reg, row, tick);
  let live_now: Int = reg.coll_live[coll];
  let live_src: Vec[Int] = reg.coll_live;
  reg.coll_live = _vec_set(&live_src, coll, live_now - 1);
  let seq = _event_push(reg, NFT_EVENT_BURN, token_id, coll, burner_id, owner_id, tick);
  return _ok_int(seq);
}

// --------------------------------------------------
//  Approvals
// --------------------------------------------------

// Latest approval row for (token row, spender text). Compare the spender by
// string, not by text-row id: a re-approval of the same spender appends a
// fresh text row.
fn _approval_last_match(reg: &NftRegistry, token_row: Int, spender: Str) -> Int {
  var found = -1;
  var i = 0;
  while i < reg.appr_count {
    if i < reg.appr_token.len() && i < reg.appr_spender_text.len() {
      let t: Int = reg.appr_token[i];
      if t == token_row {
        let st: Int = reg.appr_spender_text[i];
        let sp = _text_get(reg, st);
        if str_compare(sp, spender) == 0 {
          found = i;
        }
      }
    }
    i = i + 1;
  }
  return found;
}

/// Approve `spender` for live token `token_id` on behalf of `owner` at
/// `tick`, valid until `expiry_tick` (inclusive), and return the new
/// approval row index. `owner` must be the current token owner. Only the
/// latest row per (token, spender) pair is authoritative.
/// Errors, in this order: "nft: unknown token"; "nft: token is burned";
/// "nft: negative tick"; spender validation errors ("nft: empty spender",
/// "nft: spender too long (max 128 bytes)", "nft: spender contains control
/// character at offset N"); "nft: not token owner"; "nft: negative expiry".
pub fn nft_approve(reg: &mut NftRegistry, token_id: Int, owner: Str, spender: Str, tick: Int, expiry_tick: Int) -> Result[Int, Str] {
  let row = _token_row(reg, token_id);
  if row < 0 {
    return _err_int("nft: unknown token");
  }
  if !_token_live_row(reg, row) {
    return _err_int("nft: token is burned");
  }
  if tick < 0 {
    return _err_int("nft: negative tick");
  }
  let sv = _validate_text(spender, "spender", NFT_MAX_IDENTITY_LEN);
  if !sv.is_ok {
    return _err_int(sv.error);
  }
  let cur_owner = _token_owner_row(reg, row);
  if str_compare(cur_owner, owner) != 0 {
    return _err_int("nft: not token owner");
  }
  if expiry_tick < 0 {
    return _err_int("nft: negative expiry");
  }
  let owner_id: Int = reg.token_owner_text[row];
  let spender_id = _text_add(reg, spender);
  let coll = _token_collection_row(reg, row);
  let idx = reg.appr_count;
  reg.appr_token.push(row);
  reg.appr_owner_text.push(owner_id);
  reg.appr_spender_text.push(spender_id);
  reg.appr_expiry.push(expiry_tick);
  reg.appr_count = reg.appr_count + 1;
  _event_push(reg, NFT_EVENT_APPROVE, token_id, coll, owner_id, spender_id, tick);
  return _ok_int(idx);
}

/// Number of approval rows (all tokens and spenders).
pub fn nft_approval_count(reg: &NftRegistry) -> Int {
  return reg.appr_count;
}

/// Token id of approval row `i`; -1 when out of range.
pub fn nft_approval_token_id(reg: &NftRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.appr_count || i >= reg.appr_token.len() {
    return -1;
  }
  let row: Int = reg.appr_token[i];
  if row < 0 || row >= reg.token_id.len() {
    return -1;
  }
  let tid: Int = reg.token_id[row];
  return tid;
}

/// Grantor of approval row `i`; "" when out of range.
pub fn nft_approval_owner(reg: &NftRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.appr_count || i >= reg.appr_owner_text.len() {
    return "";
  }
  let id: Int = reg.appr_owner_text[i];
  return _text_get(reg, id);
}

/// Spender of approval row `i`; "" when out of range.
pub fn nft_approval_spender(reg: &NftRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.appr_count || i >= reg.appr_spender_text.len() {
    return "";
  }
  let id: Int = reg.appr_spender_text[i];
  return _text_get(reg, id);
}

/// Expiry tick of approval row `i`; -1 when out of range.
pub fn nft_approval_expiry(reg: &NftRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.appr_count || i >= reg.appr_expiry.len() {
    return -1;
  }
  let v: Int = reg.appr_expiry[i];
  return v;
}

/// True when approval row `i` is authoritative (latest for its token and
/// spender) and currently valid at `tick`: its token is live, its grantor is
/// still the current owner and expiry_tick >= tick.
pub fn nft_approval_is_valid(reg: &NftRegistry, i: Int, tick: Int) -> Bool {
  if i < 0 || i >= reg.appr_count {
    return false;
  }
  if i >= reg.appr_token.len() || i >= reg.appr_owner_text.len() || i >= reg.appr_spender_text.len() || i >= reg.appr_expiry.len() {
    return false;
  }
  let row: Int = reg.appr_token[i];
  let spender = nft_approval_spender(reg, i);
  if _approval_last_match(reg, row, spender) != i {
    return false;
  }
  if !_token_live_row(reg, row) {
    return false;
  }
  let ex: Int = reg.appr_expiry[i];
  if ex < tick {
    return false;
  }
  let owner = _token_owner_row(reg, row);
  let grantor_id: Int = reg.appr_owner_text[i];
  let grantor = _text_get(reg, grantor_id);
  if str_compare(grantor, owner) == 0 {
    return true;
  }
  return false;
}

/// True when `spender` is approved for live token `token_id` at `tick` by
/// its current owner.
pub fn nft_approval_valid_for(reg: &NftRegistry, token_id: Int, spender: Str, tick: Int) -> Bool {
  let row = _token_row(reg, token_id);
  if row < 0 {
    return false;
  }
  if !_token_live_row(reg, row) {
    return false;
  }
  let idx = _approval_last_match(reg, row, spender);
  if idx < 0 {
    return false;
  }
  return nft_approval_is_valid(reg, idx, tick);
}

/// Number of approval rows recorded for `token_id` (all spenders); -1 when
/// the token is unknown.
pub fn nft_token_approval_count(reg: &NftRegistry, token_id: Int) -> Int {
  let row = _token_row(reg, token_id);
  if row < 0 {
    return -1;
  }
  var n = 0;
  var i = 0;
  while i < reg.appr_count {
    if i < reg.appr_token.len() {
      let tr: Int = reg.appr_token[i];
      if tr == row {
        n = n + 1;
      }
    }
    i = i + 1;
  }
  return n;
}

// --------------------------------------------------
//  Operators
// --------------------------------------------------

// Latest matching row by owner/operator strings.
fn _operator_last_match(reg: &NftRegistry, owner: Str, operator: Str) -> Int {
  var found = -1;
  var i = 0;
  while i < reg.oper_count {
    if i < reg.oper_owner_text.len() && i < reg.oper_operator_text.len() {
      let ot: Int = reg.oper_owner_text[i];
      let pt: Int = reg.oper_operator_text[i];
      let o = _text_get(reg, ot);
      let p = _text_get(reg, pt);
      if str_compare(o, owner) == 0 && str_compare(p, operator) == 0 {
        found = i;
      }
    }
    i = i + 1;
  }
  return found;
}

/// Grant `operator` authority over every token owned by `owner` until
/// `expiry_tick` (inclusive) and return the new operator row index. Only
/// the latest row per (owner, operator) pair is authoritative.
/// Errors, in this order: "nft: negative tick"; owner validation errors
/// ("nft: empty owner", ...); operator validation errors ("nft: empty
/// operator", ...); "nft: negative expiry".
pub fn nft_set_operator(reg: &mut NftRegistry, owner: Str, operator: Str, expiry_tick: Int) -> Result[Int, Str] {
  if expiry_tick < 0 {
    return _err_int("nft: negative expiry");
  }
  let ov = _validate_owner(owner);
  if !ov.is_ok {
    return _err_int(ov.error);
  }
  let pv = _validate_text(operator, "operator", NFT_MAX_IDENTITY_LEN);
  if !pv.is_ok {
    return _err_int(pv.error);
  }
  let owner_id = _text_add(reg, owner);
  let operator_id = _text_add(reg, operator);
  let idx = reg.oper_count;
  reg.oper_owner_text.push(owner_id);
  reg.oper_operator_text.push(operator_id);
  reg.oper_expiry.push(expiry_tick);
  reg.oper_count = reg.oper_count + 1;
  return _ok_int(idx);
}

/// Number of operator rows.
pub fn nft_operator_count(reg: &NftRegistry) -> Int {
  return reg.oper_count;
}

/// Owner of operator row `i`; "" when out of range.
pub fn nft_operator_owner(reg: &NftRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.oper_count || i >= reg.oper_owner_text.len() {
    return "";
  }
  let id: Int = reg.oper_owner_text[i];
  return _text_get(reg, id);
}

/// Operator of operator row `i`; "" when out of range.
pub fn nft_operator_operator(reg: &NftRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.oper_count || i >= reg.oper_operator_text.len() {
    return "";
  }
  let id: Int = reg.oper_operator_text[i];
  return _text_get(reg, id);
}

/// Expiry tick of operator row `i`; -1 when out of range.
pub fn nft_operator_expiry(reg: &NftRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.oper_count || i >= reg.oper_expiry.len() {
    return -1;
  }
  let v: Int = reg.oper_expiry[i];
  return v;
}

/// True when operator row `i` is authoritative (latest for its owner and
/// operator) and currently valid at `tick`.
pub fn nft_operator_is_valid(reg: &NftRegistry, i: Int, tick: Int) -> Bool {
  if i < 0 || i >= reg.oper_count {
    return false;
  }
  if i >= reg.oper_owner_text.len() || i >= reg.oper_operator_text.len() || i >= reg.oper_expiry.len() {
    return false;
  }
  let owner = nft_operator_owner(reg, i);
  let operator = nft_operator_operator(reg, i);
  if _operator_last_match(reg, owner, operator) != i {
    return false;
  }
  let ex: Int = reg.oper_expiry[i];
  if ex >= tick {
    return true;
  }
  return false;
}

/// True when `operator` is a valid operator for `owner` at `tick` (the
/// latest (owner, operator) row has expiry_tick >= tick).
pub fn nft_is_operator(reg: &NftRegistry, owner: Str, operator: Str, tick: Int) -> Bool {
  let idx = _operator_last_match(reg, owner, operator);
  if idx < 0 {
    return false;
  }
  let ex: Int = reg.oper_expiry[idx];
  if ex >= tick {
    return true;
  }
  return false;
}

/// Revoke a currently valid operator (latest (owner, operator) row has
/// expiry_tick >= tick) by appending an already-expired row, and return the
/// new row index.
/// Errors, in this order: "nft: negative tick"; owner validation errors;
/// operator validation errors; "nft: unknown operator"; "nft: operator
/// already revoked".
pub fn nft_operator_revoke(reg: &mut NftRegistry, owner: Str, operator: Str, tick: Int) -> Result[Int, Str] {
  if tick < 0 {
    return _err_int("nft: negative tick");
  }
  let ov = _validate_owner(owner);
  if !ov.is_ok {
    return _err_int(ov.error);
  }
  let pv = _validate_text(operator, "operator", NFT_MAX_IDENTITY_LEN);
  if !pv.is_ok {
    return _err_int(pv.error);
  }
  let idx = _operator_last_match(reg, owner, operator);
  if idx < 0 {
    return _err_int("nft: unknown operator");
  }
  let ex: Int = reg.oper_expiry[idx];
  if ex < tick {
    return _err_int("nft: operator already revoked");
  }
  let owner_id = _text_add(reg, owner);
  let operator_id = _text_add(reg, operator);
  let new_idx = reg.oper_count;
  reg.oper_owner_text.push(owner_id);
  reg.oper_operator_text.push(operator_id);
  reg.oper_expiry.push(tick - 1);
  reg.oper_count = reg.oper_count + 1;
  return _ok_int(new_idx);
}

// --------------------------------------------------
//  Events
// --------------------------------------------------

/// Number of canonical events.
pub fn nft_event_count(reg: &NftRegistry) -> Int {
  return reg.event_count;
}

/// Sequence number of event `i` (1-based); 0 when out of range.
pub fn nft_event_seq(reg: &NftRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.event_count || i >= reg.event_seq.len() {
    return 0;
  }
  let v: Int = reg.event_seq[i];
  return v;
}

/// Kind of event `i` (NFT_EVENT_MINT / NFT_EVENT_TRANSFER /
/// NFT_EVENT_APPROVE / NFT_EVENT_BURN); -1 when out of range.
pub fn nft_event_kind(reg: &NftRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.event_count || i >= reg.event_kind.len() {
    return -1;
  }
  let v: Int = reg.event_kind[i];
  return v;
}

/// "mint" / "transfer" / "approve" / "burn"; "unknown" for any other kind.
pub fn nft_event_kind_name(kind: Int) -> Str {
  if kind == NFT_EVENT_MINT {
    return "mint";
  }
  if kind == NFT_EVENT_TRANSFER {
    return "transfer";
  }
  if kind == NFT_EVENT_APPROVE {
    return "approve";
  }
  if kind == NFT_EVENT_BURN {
    return "burn";
  }
  return "unknown";
}

/// Token id of event `i`; -1 when out of range.
pub fn nft_event_token_id(reg: &NftRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.event_count || i >= reg.event_token_id.len() {
    return -1;
  }
  let v: Int = reg.event_token_id[i];
  return v;
}

/// Collection index of event `i`; -1 when out of range.
pub fn nft_event_collection(reg: &NftRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.event_count || i >= reg.event_collection.len() {
    return -1;
  }
  let v: Int = reg.event_collection[i];
  return v;
}

/// Actor text of event `i` (minter, sender, grantor or burner); "" when out
/// of range.
pub fn nft_event_actor(reg: &NftRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.event_count || i >= reg.event_actor_text.len() {
    return "";
  }
  let id: Int = reg.event_actor_text[i];
  return _text_get(reg, id);
}

/// Counterparty text of event `i` (mint: owner; transfer: recipient;
/// approve: spender/operator; burn: final owner); "" when out of range.
pub fn nft_event_to(reg: &NftRegistry, i: Int) -> Str {
  if i < 0 || i >= reg.event_count || i >= reg.event_to_text.len() {
    return "";
  }
  let id: Int = reg.event_to_text[i];
  return _text_get(reg, id);
}

/// Tick of event `i`; -1 when out of range.
pub fn nft_event_tick(reg: &NftRegistry, i: Int) -> Int {
  if i < 0 || i >= reg.event_count || i >= reg.event_tick.len() {
    return -1;
  }
  let v: Int = reg.event_tick[i];
  return v;
}

// --------------------------------------------------
//  Royalties
// --------------------------------------------------

/// Creator royalty for a `sale_price` in collection `collection`:
/// floor(sale_price * bps / 10000), computed overflow-free with the q/r
/// decomposition (q = price / 10000, r = price % 10000). Returns 0 when the
/// collection is unknown or sale_price <= 0.
pub fn nft_royalty_creator_amount(reg: &NftRegistry, collection: Int, sale_price: Int) -> Int {
  if collection < 0 || collection >= reg.coll_count || collection >= reg.coll_royalty_bps.len() {
    return 0;
  }
  if sale_price <= 0 {
    return 0;
  }
  let bps: Int = reg.coll_royalty_bps[collection];
  let q = sale_price / NFT_MAX_BPS;
  let r = sale_price % NFT_MAX_BPS;
  return q * bps + (r * bps) / NFT_MAX_BPS;
}

/// Seller proceeds for a `sale_price` in collection `collection`:
/// sale_price - creator amount. Returns 0 when the collection is unknown or
/// sale_price <= 0.
pub fn nft_royalty_seller_amount(reg: &NftRegistry, collection: Int, sale_price: Int) -> Int {
  if collection < 0 || collection >= reg.coll_count || collection >= reg.coll_royalty_bps.len() {
    return 0;
  }
  if sale_price <= 0 {
    return 0;
  }
  return sale_price - nft_royalty_creator_amount(reg, collection, sale_price);
}

/// Canonical royalty split text: "creator\t<amount>\tseller\t<amount>"; ""
/// when the collection is unknown or sale_price <= 0.
pub fn nft_royalty_split_text(reg: &NftRegistry, collection: Int, sale_price: Int) -> Str {
  if collection < 0 || collection >= reg.coll_count || collection >= reg.coll_royalty_bps.len() {
    return "";
  }
  if sale_price <= 0 {
    return "";
  }
  let c = nft_royalty_creator_amount(reg, collection, sale_price);
  let s = nft_royalty_seller_amount(reg, collection, sale_price);
  return "creator\t" + convert.int_to_string(c) + "\tseller\t" + convert.int_to_string(s);
}

// --------------------------------------------------
//  Enumeration
// --------------------------------------------------

/// Number of live tokens owned by `owner`.
pub fn nft_owner_token_count(reg: &NftRegistry, owner: Str) -> Int {
  var n = 0;
  var i = 0;
  while i < reg.token_count {
    if _token_live_row(reg, i) {
      let text_id: Int = reg.token_owner_text[i];
      let stored = _text_get(reg, text_id);
      if str_compare(stored, owner) == 0 {
        n = n + 1;
      }
    }
    i = i + 1;
  }
  return n;
}

/// Token id of the k-th live token owned by `owner` (0-based, token-row
/// order); -1 when out of range.
pub fn nft_owner_token_at(reg: &NftRegistry, owner: Str, k: Int) -> Int {
  if k < 0 {
    return -1;
  }
  var seen = 0;
  var i = 0;
  while i < reg.token_count {
    if _token_live_row(reg, i) {
      let text_id: Int = reg.token_owner_text[i];
      let stored = _text_get(reg, text_id);
      if str_compare(stored, owner) == 0 {
        if seen == k {
          let tid: Int = reg.token_id[i];
          return tid;
        }
        seen = seen + 1;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Token id of the k-th live token in `collection` (0-based, token-row
/// order); -1 when out of range.
pub fn nft_collection_token_at(reg: &NftRegistry, collection: Int, k: Int) -> Int {
  if collection < 0 || collection >= reg.coll_count {
    return -1;
  }
  if k < 0 {
    return -1;
  }
  var seen = 0;
  var i = 0;
  while i < reg.token_count {
    if _token_live_row(reg, i) {
      let c: Int = reg.token_collection[i];
      if c == collection {
        if seen == k {
          let tid: Int = reg.token_id[i];
          return tid;
        }
        seen = seen + 1;
      }
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Invariants
// --------------------------------------------------

// True when every parallel vector has exactly the length its section count
// promises.
fn _parallel_ok(reg: &NftRegistry) -> Bool {
  if reg.text_start.len() != reg.text_len.len() {
    return false;
  }
  if reg.coll_name_text.len() != reg.coll_count {
    return false;
  }
  if reg.coll_creator_text.len() != reg.coll_count {
    return false;
  }
  if reg.coll_royalty_bps.len() != reg.coll_count {
    return false;
  }
  if reg.coll_live.len() != reg.coll_count {
    return false;
  }
  if reg.token_id.len() != reg.token_count {
    return false;
  }
  if reg.token_collection.len() != reg.token_count {
    return false;
  }
  if reg.token_owner_text.len() != reg.token_count {
    return false;
  }
  if reg.token_minted_tick.len() != reg.token_count {
    return false;
  }
  if reg.token_burn_tick.len() != reg.token_count {
    return false;
  }
  if reg.token_status.len() != reg.token_count {
    return false;
  }
  if reg.appr_token.len() != reg.appr_count {
    return false;
  }
  if reg.appr_owner_text.len() != reg.appr_count {
    return false;
  }
  if reg.appr_spender_text.len() != reg.appr_count {
    return false;
  }
  if reg.appr_expiry.len() != reg.appr_count {
    return false;
  }
  if reg.oper_owner_text.len() != reg.oper_count {
    return false;
  }
  if reg.oper_operator_text.len() != reg.oper_count {
    return false;
  }
  if reg.oper_expiry.len() != reg.oper_count {
    return false;
  }
  if reg.event_seq.len() != reg.event_count {
    return false;
  }
  if reg.event_kind.len() != reg.event_count {
    return false;
  }
  if reg.event_token_id.len() != reg.event_count {
    return false;
  }
  if reg.event_collection.len() != reg.event_count {
    return false;
  }
  if reg.event_actor_text.len() != reg.event_count {
    return false;
  }
  if reg.event_to_text.len() != reg.event_count {
    return false;
  }
  if reg.event_tick.len() != reg.event_count {
    return false;
  }
  return true;
}

/// True when every token id is positive and globally unique (ids are never
/// reused after burn): the unique-ownership key invariant.
pub fn nft_token_ids_unique(reg: &NftRegistry) -> Bool {
  if !_parallel_ok(reg) {
    return false;
  }
  var i = 0;
  while i < reg.token_count {
    let a: Int = reg.token_id[i];
    if a <= 0 {
      return false;
    }
    var j = i + 1;
    while j < reg.token_count {
      let b: Int = reg.token_id[j];
      if a == b {
        return false;
      }
      j = j + 1;
    }
    i = i + 1;
  }
  return true;
}

/// True when supply accounting balances: live + burned = token rows, every
/// per-collection recorded live count equals the actual count, and the
/// per-collection counts sum to the global live supply.
pub fn nft_supply_balanced(reg: &NftRegistry) -> Bool {
  if !_parallel_ok(reg) {
    return false;
  }
  var live = 0;
  var i = 0;
  while i < reg.token_count {
    let st: Int = reg.token_status[i];
    if st == NFT_TOKEN_LIVE {
      live = live + 1;
    } elif st != NFT_TOKEN_BURNED {
      return false;
    }
    i = i + 1;
  }
  if live != _live_count(reg) {
    return false;
  }
  var coll_live_sum = 0;
  var c = 0;
  while c < reg.coll_count {
    let recorded: Int = reg.coll_live[c];
    let actual = _coll_actual_live(reg, c);
    if recorded != actual {
      return false;
    }
    coll_live_sum = coll_live_sum + recorded;
    c = c + 1;
  }
  if coll_live_sum != live {
    return false;
  }
  return true;
}

/// Full registry invariant: parallel-vector consistency, unique positive
/// token ids, supply accounting, reference validity (collections, text
/// rows, token rows), status/burn-tick coherence and the canonical event
/// log (sequence 1..N, valid kinds, real token/collection/text references).
pub fn nft_registry_valid(reg: &NftRegistry) -> Bool {
  if !_parallel_ok(reg) {
    return false;
  }
  if !nft_token_ids_unique(reg) {
    return false;
  }
  if !nft_supply_balanced(reg) {
    return false;
  }
  var i = 0;
  while i < reg.token_count {
    let coll: Int = reg.token_collection[i];
    if coll < 0 || coll >= reg.coll_count {
      return false;
    }
    let ot: Int = reg.token_owner_text[i];
    if ot < 0 || ot >= reg.text_start.len() {
      return false;
    }
    let st: Int = reg.token_status[i];
    let bt: Int = reg.token_burn_tick[i];
    if st == NFT_TOKEN_LIVE {
      if bt != -1 {
        return false;
      }
    } elif st == NFT_TOKEN_BURNED {
      if bt < 0 {
        return false;
      }
    } else {
      return false;
    }
    i = i + 1;
  }
  var c = 0;
  while c < reg.coll_count {
    let nt: Int = reg.coll_name_text[c];
    if nt < 0 || nt >= reg.text_start.len() {
      return false;
    }
    let ct: Int = reg.coll_creator_text[c];
    if ct < 0 || ct >= reg.text_start.len() {
      return false;
    }
    let bps: Int = reg.coll_royalty_bps[c];
    if bps < 0 || bps > NFT_MAX_BPS {
      return false;
    }
    c = c + 1;
  }
  var a = 0;
  while a < reg.appr_count {
    let tr: Int = reg.appr_token[a];
    if tr < 0 || tr >= reg.token_count {
      return false;
    }
    let g: Int = reg.appr_owner_text[a];
    if g < 0 || g >= reg.text_start.len() {
      return false;
    }
    let s: Int = reg.appr_spender_text[a];
    if s < 0 || s >= reg.text_start.len() {
      return false;
    }
    let ex: Int = reg.appr_expiry[a];
    if ex < -1 {
      return false;
    }
    a = a + 1;
  }
  var o = 0;
  while o < reg.oper_count {
    let x: Int = reg.oper_owner_text[o];
    if x < 0 || x >= reg.text_start.len() {
      return false;
    }
    let y: Int = reg.oper_operator_text[o];
    if y < 0 || y >= reg.text_start.len() {
      return false;
    }
    let ex2: Int = reg.oper_expiry[o];
    if ex2 < -1 {
      return false;
    }
    o = o + 1;
  }
  var e = 0;
  while e < reg.event_count {
    let sq: Int = reg.event_seq[e];
    if sq != e + 1 {
      return false;
    }
    let kd: Int = reg.event_kind[e];
    if kd < NFT_EVENT_MINT || kd > NFT_EVENT_BURN {
      return false;
    }
    let etid: Int = reg.event_token_id[e];
    if _token_row(reg, etid) < 0 {
      return false;
    }
    let ec: Int = reg.event_collection[e];
    if ec < 0 || ec >= reg.coll_count {
      return false;
    }
    let ea: Int = reg.event_actor_text[e];
    if ea < 0 || ea >= reg.text_start.len() {
      return false;
    }
    let eto: Int = reg.event_to_text[e];
    if eto < 0 || eto >= reg.text_start.len() {
      return false;
    }
    e = e + 1;
  }
  return true;
}

// --------------------------------------------------
//  Canonical export
// --------------------------------------------------

// "live" / "burned" for a token status; "unknown" otherwise.
fn _token_status_name(status: Int) -> Str {
  if status == NFT_TOKEN_LIVE {
    return "live";
  }
  if status == NFT_TOKEN_BURNED {
    return "burned";
  }
  return "unknown";
}

/// Canonical tab-separated listing of the whole registry:
///   nft-registry\t1\n
///   collections\t<n>\n
///   collection\t<i>\t<name>\t<creator>\t<bps>\t<live>\t<minted>\n
///   tokens\t<n>\n
///   token\t<id>\t<collection>\t<owner>\t<live|burned>\t<minted_tick>\t<burn_tick>\n
///   approvals\t<a>\n
///   approval\t<token_id>\t<owner>\t<spender>\t<expiry>\n
///   operators\t<o>\n
///   operator\t<owner>\t<operator>\t<expiry>\n
///   events\t<e>\n
///   event\t<seq>\t<mint|transfer|approve|burn>\t<token_id>\t<collection>\t<actor>\t<to>\t<tick>\n
/// One line per record, trailing newline after every line. The owner field
/// of a burned token is its final owner.
pub fn nft_registry_export(reg: &NftRegistry) -> Str {
  var out = "nft-registry\t1\n";
  out = out + "collections\t" + convert.int_to_string(reg.coll_count) + "\n";
  var c = 0;
  while c < reg.coll_count {
    if c < reg.coll_name_text.len() && c < reg.coll_creator_text.len() && c < reg.coll_royalty_bps.len() && c < reg.coll_live.len() {
      let nt: Int = reg.coll_name_text[c];
      let ct: Int = reg.coll_creator_text[c];
      let bps: Int = reg.coll_royalty_bps[c];
      let lv: Int = reg.coll_live[c];
      let minted = _coll_minted_count(reg, c);
      out = out + "collection\t" + convert.int_to_string(c) + "\t" + _text_get(reg, nt) + "\t" + _text_get(reg, ct) + "\t" + convert.int_to_string(bps) + "\t" + convert.int_to_string(lv) + "\t" + convert.int_to_string(minted) + "\n";
    }
    c = c + 1;
  }
  out = out + "tokens\t" + convert.int_to_string(reg.token_count) + "\n";
  var i = 0;
  while i < reg.token_count {
    if i < reg.token_id.len() && i < reg.token_collection.len() && i < reg.token_owner_text.len() && i < reg.token_minted_tick.len() && i < reg.token_burn_tick.len() && i < reg.token_status.len() {
      let tid: Int = reg.token_id[i];
      let coll: Int = reg.token_collection[i];
      let ot: Int = reg.token_owner_text[i];
      let mt: Int = reg.token_minted_tick[i];
      let bt: Int = reg.token_burn_tick[i];
      let st: Int = reg.token_status[i];
      out = out + "token\t" + convert.int_to_string(tid) + "\t" + convert.int_to_string(coll) + "\t" + _text_get(reg, ot) + "\t" + _token_status_name(st) + "\t" + convert.int_to_string(mt) + "\t" + convert.int_to_string(bt) + "\n";
    }
    i = i + 1;
  }
  out = out + "approvals\t" + convert.int_to_string(reg.appr_count) + "\n";
  var a = 0;
  while a < reg.appr_count {
    if a < reg.appr_token.len() && a < reg.appr_owner_text.len() && a < reg.appr_spender_text.len() && a < reg.appr_expiry.len() {
      let tr: Int = reg.appr_token[a];
      let gt: Int = reg.appr_owner_text[a];
      let sp: Int = reg.appr_spender_text[a];
      let ex: Int = reg.appr_expiry[a];
      var tid_out = -1;
      if tr >= 0 && tr < reg.token_id.len() {
        let tid2: Int = reg.token_id[tr];
        tid_out = tid2;
      }
      out = out + "approval\t" + convert.int_to_string(tid_out) + "\t" + _text_get(reg, gt) + "\t" + _text_get(reg, sp) + "\t" + convert.int_to_string(ex) + "\n";
    }
    a = a + 1;
  }
  out = out + "operators\t" + convert.int_to_string(reg.oper_count) + "\n";
  var o = 0;
  while o < reg.oper_count {
    if o < reg.oper_owner_text.len() && o < reg.oper_operator_text.len() && o < reg.oper_expiry.len() {
      let ot2: Int = reg.oper_owner_text[o];
      let pt: Int = reg.oper_operator_text[o];
      let ex2: Int = reg.oper_expiry[o];
      out = out + "operator\t" + _text_get(reg, ot2) + "\t" + _text_get(reg, pt) + "\t" + convert.int_to_string(ex2) + "\n";
    }
    o = o + 1;
  }
  out = out + "events\t" + convert.int_to_string(reg.event_count) + "\n";
  var e = 0;
  while e < reg.event_count {
    if e < reg.event_seq.len() && e < reg.event_kind.len() && e < reg.event_token_id.len() && e < reg.event_collection.len() && e < reg.event_actor_text.len() && e < reg.event_to_text.len() && e < reg.event_tick.len() {
      let sq: Int = reg.event_seq[e];
      let kd: Int = reg.event_kind[e];
      let etid: Int = reg.event_token_id[e];
      let ec: Int = reg.event_collection[e];
      let ea: Int = reg.event_actor_text[e];
      let eto: Int = reg.event_to_text[e];
      let et: Int = reg.event_tick[e];
      out = out + "event\t" + convert.int_to_string(sq) + "\t" + nft_event_kind_name(kd) + "\t" + convert.int_to_string(etid) + "\t" + convert.int_to_string(ec) + "\t" + _text_get(reg, ea) + "\t" + _text_get(reg, eto) + "\t" + convert.int_to_string(et) + "\n";
    }
    e = e + 1;
  }
  return out;
}
