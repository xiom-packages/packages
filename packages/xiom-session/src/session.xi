// XIOM -- xiom.session: in-memory session store with explicit clocks
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A small, pure-XIOM session store: opaque 128-bit session ids rendered as
// 32 lowercase hex characters, Str key -> Str value entries per session,
// absolute expiry in caller-supplied integer milliseconds, and exact
// Set-Cookie header rendering. The module never reads the system clock, so
// behavior is deterministic given the caller's clock.
//
// Expiry semantics: a session is valid while `now_ms < expires_ms`; at
// `now_ms == expires_ms` it is expired. Expired sessions are never returned
// by session_get / session_value and never accept session_set or
// session_touch; they stay stored until session_prune or session_remove
// discards them, so session_count counts stored sessions, expired ones
// included.
//
// Id generation: session_create and session_rotate draw 16 bytes from
// xiom.crypto.secure_random_bytes and render them as 32 lowercase hex
// characters. When a drawn id is already stored the draw is retried, up to
// 8 draws; after that the result is Err("session: id generation failed").
//
// What is covered:
//   * session_store_new / session_store_ttl_ms / session_count accessors;
//   * session_id_valid (exactly 32 lowercase hex characters);
//   * create/get/set/value/touch/remove/rotate/prune with absolute expiry;
//   * session_cookie_header / session_cookie_clear exact header text.
//
// Deliberate boundaries: no system clock, no persistence, no concurrency, no
// cookie parsing, no value typing, no expiry extension on set, no eviction of
// live sessions. Entries are structs (SessionEntry), never tuples.
//
// v0.64.0 notes that shaped this module:
//   * free functions only; stores travel by reference (`&mut` to mutate, `&`
//     to read) and state lives in the public fields;
//   * every raw byte read via xiom.string.byte_at is widened with
//     `(x as Int) & 0xFF` before comparison (_byte);
//   * no `==` on Str anywhere: every string comparison goes through
//     xiom.string.compare.str_compare;
//   * Vec[Struct] `.clone()` crashes the current codegen (access violation),
//     so entries are copied element by element (_entries_copy) and updated
//     sessions are written back whole (`s.sessions[at] = Session{ ... }`)
//     instead of cloned.

module xiom.session

use xiom.crypto;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Types
// --------------------------------------------------

/// One session entry: a caller-defined key and its value, both opaque Str.
pub type SessionEntry = {
  key: Str;
  value: Str;
}

/// One stored session. `id` is 32 lowercase hex characters; `entries` holds
/// the key/value pairs in insertion order; `created_ms` is the caller clock
/// at creation (reset by session_rotate); `expires_ms` is the absolute expiry
/// instant. A session is valid while now_ms < expires_ms.
pub type Session = {
  id: Str;
  entries: Vec[SessionEntry];
  created_ms: Int;
  expires_ms: Int;
}

/// An in-memory session store. `sessions` holds stored sessions in insertion
/// order (expired but unswept ones included); `ttl_ms` is the default
/// lifetime applied by session_create / session_touch / session_rotate and is
/// always >= 1.
pub type SessionStore = {
  sessions: Vec[Session];
  ttl_ms: Int;
}

// --------------------------------------------------
//  Constants
// --------------------------------------------------

const _HEX_LOWER: Str = "0123456789abcdef";
const _DIGITS: Str = "0123456789";
const _ID_LEN: Int = 32;
const _ERR_ID_GEN: Str = "session: id generation failed";
const _ERR_ROTATE: Str = "session: not found or expired";

// --------------------------------------------------
//  Byte and string helpers
// --------------------------------------------------

// One byte of `s` at `i`, zero-extended to Int (0..255). Every byte read in
// this module goes through here.
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// One lowercase hex character for the nibble `n` (0..15), as a fresh Str.
fn _hex_digit(n: Int) -> Str {
  return string.str_slice(_HEX_LOWER, n, n + 1);
}

// Lowercase hex of a byte vector: two characters per byte, in order.
fn _hex_encode(bytes: &Vec[UInt8]) -> Str {
  var out = "";
  var i = 0;
  while i < bytes.len() {
    let b: Int = (bytes[i] as Int) & 0xFF;
    out = string.str_concat(out, _hex_digit(b / 16));
    out = string.str_concat(out, _hex_digit(b % 16));
    i = i + 1;
  }
  return out;
}

// Decimal text of a non-negative Int (n <= 0 renders "0"). Used only for the
// cookie Max-Age attribute; no other formatting exists in this module.
fn _dec_str(n: Int) -> Str {
  var v = n;
  if v <= 0 {
    return "0";
  }
  var out = "";
  while v > 0 {
    let d = v % 10;
    out = string.str_concat(string.str_slice(_DIGITS, d, d + 1), out);
    v = v / 10;
  }
  return out;
}

// --------------------------------------------------
//  Store helpers
// --------------------------------------------------

// Index of the session stored under `id`, or -1 when absent. Linear scan in
// insertion order; ids compare byte-wise through str_compare.
fn _store_find(s: &SessionStore, id: Str) -> Int {
  var i = 0;
  while i < s.sessions.len() {
    if compare.str_compare(s.sessions[i].id, id) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Index of `key` in `entries`, or -1 when absent (byte-exact str_compare).
fn _entry_find(entries: &Vec[SessionEntry], key: Str) -> Int {
  var i = 0;
  while i < entries.len() {
    if compare.str_compare(entries[i].key, key) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Deep copy of the entries of the stored session at `at`. Str fields are
// copied element by element because Vec[Struct] `.clone()` is broken in
// v0.64.0 (access violation). The copy is independent of the store.
fn _entries_copy(s: &SessionStore, at: Int) -> Vec[SessionEntry] {
  var out = Vec[SessionEntry].new();
  var i = 0;
  while i < s.sessions[at].entries.len() {
    out.push(SessionEntry{
      key: s.sessions[at].entries[i].key;
      value: s.sessions[at].entries[i].value;
    });
    i = i + 1;
  }
  return out;
}

// Draw a fresh 128-bit id (32 lowercase hex characters) that is not stored in
// `s`. Up to 8 draws are attempted; every drawn id is checked against the
// store through _store_find. Err("session: id generation failed") when all 8
// draws collide (with a working CSPRNG this signals a broken id source, not
// capacity).
fn _generate_id(s: &SessionStore) -> Result[Str, Str] {
  var attempt = 0;
  var chosen = "";
  while attempt < 8 && chosen.len() == 0 {
    let bytes = crypto.secure_random_bytes(16);
    let candidate = _hex_encode(&bytes);
    if _store_find(s, candidate) < 0 {
      chosen = candidate;
    }
    attempt = attempt + 1;
  }
  if chosen.len() == 0 {
    return Err(_ERR_ID_GEN);
  }
  return Ok(chosen);
}

// --------------------------------------------------
//  Store lifecycle
// --------------------------------------------------

/// Create an empty session store with default lifetime `ttl_ms`.
/// Params: ttl_ms - lifetime applied to created sessions, in milliseconds;
/// values <= 0 are clamped to 1.
/// Returns: a store with no sessions and the clamped ttl.
/// Error case: none.
/// Complexity: O(1).
pub fn session_store_new(ttl_ms: Int) -> SessionStore {
  var ttl = ttl_ms;
  if ttl < 1 {
    ttl = 1;
  }
  return SessionStore{ sessions: Vec[Session].new(); ttl_ms: ttl; };
}

/// Default lifetime applied by create/touch/rotate, in milliseconds (>= 1).
/// Params: s - the store.
/// Returns: the configured ttl_ms.
/// Error case: none.
/// Complexity: O(1).
pub fn session_store_ttl_ms(s: &SessionStore) -> Int {
  return s.ttl_ms;
}

/// Number of stored sessions, expired-but-unswept ones included. Does not
/// consult a clock and does not prune.
/// Params: s - the store.
/// Returns: the stored session count.
/// Error case: none.
/// Complexity: O(1).
pub fn session_count(s: &SessionStore) -> Int {
  return s.sessions.len();
}

/// True when `id` is exactly 32 bytes, each in 0-9a-f (lowercase; uppercase
/// hex is rejected).
/// Params: id - the candidate session id.
/// Returns: true when the id has the exact shape session_create produces.
/// Error case: none.
/// Complexity: O(id length).
pub fn session_id_valid(id: Str) -> Bool {
  if id.len() != _ID_LEN {
    return false;
  }
  var i = 0;
  while i < id.len() {
    let b = _byte(id, i);
    let digit = b >= 48 && b <= 57;
    let lower = b >= 97 && b <= 102;
    if !digit && !lower {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Create a session at `now_ms` with an empty entry list.
/// Params: s - the store to mutate; now_ms - caller clock reading.
/// Returns: Ok(id), the new 32-character lowercase-hex session id; the
/// session expires at now_ms + session_store_ttl_ms(s).
/// Error case: Err("session: id generation failed") when 8 consecutive
/// secure id draws all collide with stored sessions; nothing is stored.
/// Complexity: O(stored sessions) per id draw (linear collision scan).
pub fn session_create(s: &mut SessionStore, now_ms: Int) -> Result[Str, Str] {
  let r = _generate_id(s);
  if !r.is_ok {
    return Err(_ERR_ID_GEN);
  }
  let id = r.value;
  let expires = now_ms + s.ttl_ms;
  let sess = Session{
    id: id;
    entries: Vec[SessionEntry].new();
    created_ms: now_ms;
    expires_ms: expires;
  };
  s.sessions.push(sess);
  let last = s.sessions.len() - 1;
  let out_id = s.sessions[last].id;
  return Ok(out_id);
}

/// Look up a session by id.
/// Params: s - the store; id - the session id; now_ms - caller clock reading.
/// Returns: Some(session) with its entries in insertion order when the id is
/// stored and live (now_ms < expires_ms); None when absent or expired. The
/// returned session is an independent copy: mutating it never changes the
/// store and mutating the store never changes it.
/// Error case: none.
/// Complexity: O(stored sessions + entries).
pub fn session_get(s: &SessionStore, id: Str, now_ms: Int) -> Option[Session] {
  let at = _store_find(s, id);
  if at < 0 {
    return None;
  }
  if now_ms >= s.sessions[at].expires_ms {
    return None;
  }
  let entries = _entries_copy(s, at);
  let keep_id = s.sessions[at].id;
  let keep_created = s.sessions[at].created_ms;
  let keep_expires = s.sessions[at].expires_ms;
  let out = Session{
    id: keep_id;
    entries: entries;
    created_ms: keep_created;
    expires_ms: keep_expires;
  };
  return Some(out);
}

/// Set `key` = `value` on a live session. An existing key is overwritten in
/// place (insertion position preserved), a new key is appended. Setting never
/// extends the expiry.
/// Params: s - the store to mutate; id - session id; key - entry key;
/// value - entry value; now_ms - caller clock reading.
/// Returns: true when the entry was written; false when the id is absent or
/// expired at now_ms (nothing is written).
/// Error case: none.
/// Complexity: O(stored sessions + entries).
pub fn session_set(s: &mut SessionStore, id: Str, key: Str, value: Str, now_ms: Int) -> Bool {
  let at = _store_find(s, id);
  if at < 0 {
    return false;
  }
  if now_ms >= s.sessions[at].expires_ms {
    return false;
  }
  var entries = _entries_copy(s, at);
  let e = _entry_find(&entries, key);
  if e >= 0 {
    entries[e] = SessionEntry{ key: key; value: value; };
  } else {
    entries.push(SessionEntry{ key: key; value: value; });
  }
  let keep_id = s.sessions[at].id;
  let keep_created = s.sessions[at].created_ms;
  let keep_expires = s.sessions[at].expires_ms;
  s.sessions[at] = Session{
    id: keep_id;
    entries: entries;
    created_ms: keep_created;
    expires_ms: keep_expires;
  };
  return true;
}

/// Read one entry value from a live session.
/// Params: s - the store; id - session id; key - entry key; now_ms - caller
/// clock reading.
/// Returns: Some(value) of the first entry whose key equals `key` when the
/// session is stored and live; None when the session is absent, expired, or
/// holds no such key.
/// Error case: none.
/// Complexity: O(stored sessions + entries).
pub fn session_value(s: &SessionStore, id: Str, key: Str, now_ms: Int) -> Option[Str] {
  let at = _store_find(s, id);
  if at < 0 {
    return None;
  }
  if now_ms >= s.sessions[at].expires_ms {
    return None;
  }
  var i = 0;
  while i < s.sessions[at].entries.len() {
    if compare.str_compare(s.sessions[at].entries[i].key, key) == 0 {
      let v = s.sessions[at].entries[i].value;
      return Some(v);
    }
    i = i + 1;
  }
  return None;
}

/// Slide a live session's expiry: expires_ms = now_ms + ttl_ms.
/// Params: s - the store to mutate; id - session id; now_ms - caller clock
/// reading.
/// Returns: true when the session was stored and live at now_ms (its expiry
/// is replaced even if that shortens it); false when absent or expired at
/// now_ms (nothing is written).
/// Error case: none.
/// Complexity: O(stored sessions).
pub fn session_touch(s: &mut SessionStore, id: Str, now_ms: Int) -> Bool {
  let at = _store_find(s, id);
  if at < 0 {
    return false;
  }
  if now_ms >= s.sessions[at].expires_ms {
    return false;
  }
  s.sessions[at].expires_ms = now_ms + s.ttl_ms;
  return true;
}

/// Remove the stored session with `id`, expired or not (removal needs no
/// clock and ignores expiry).
/// Params: s - the store to mutate; id - session id.
/// Returns: true when a stored session was removed; false when absent.
/// Error case: none.
/// Complexity: O(stored sessions).
pub fn session_remove(s: &mut SessionStore, id: Str) -> Bool {
  let at = _store_find(s, id);
  if at < 0 {
    return false;
  }
  s.sessions.remove(at);
  return true;
}

/// Rotate a live session: mint a new id, carry the entries over, reset
/// created_ms and expires_ms, and remove the old id.
/// Params: s - the store to mutate; old_id - the session to rotate; now_ms -
/// caller clock reading.
/// Returns: Ok(new_id) when the old id was stored and live; the new session
/// holds copies of the old entries in order, created_ms = now_ms and
/// expires_ms = now_ms + ttl_ms. The old id no longer resolves.
/// Error case: Err("session: not found or expired") when old_id is absent or
/// expired at now_ms (the store is unchanged); Err("session: id generation
/// failed") when 8 consecutive secure id draws all collide (the old session
/// is left in place).
/// Complexity: O(stored sessions + entries).
pub fn session_rotate(s: &mut SessionStore, old_id: Str, now_ms: Int) -> Result[Str, Str] {
  let at = _store_find(s, old_id);
  if at < 0 {
    return Err(_ERR_ROTATE);
  }
  if now_ms >= s.sessions[at].expires_ms {
    return Err(_ERR_ROTATE);
  }
  let r = _generate_id(s);
  if !r.is_ok {
    return Err(_ERR_ID_GEN);
  }
  let new_id = r.value;
  let carried = _entries_copy(s, at);
  s.sessions.remove(at);
  let expires = now_ms + s.ttl_ms;
  let fresh = Session{
    id: new_id;
    entries: carried;
    created_ms: now_ms;
    expires_ms: expires;
  };
  s.sessions.push(fresh);
  let last = s.sessions.len() - 1;
  let out_id = s.sessions[last].id;
  return Ok(out_id);
}

/// Remove every expired stored session (now_ms >= expires_ms) and count them.
/// Params: s - the store to mutate; now_ms - caller clock reading.
/// Returns: the number of sessions removed (>= 0). At the boundary
/// now_ms == expires_ms the session is expired and is removed.
/// Error case: none.
/// Complexity: O(stored sessions).
pub fn session_prune(s: &mut SessionStore, now_ms: Int) -> Int {
  var removed = 0;
  var i = 0;
  while i < s.sessions.len() {
    if now_ms >= s.sessions[i].expires_ms {
      s.sessions.remove(i);
      removed = removed + 1;
    } else {
      i = i + 1;
    }
  }
  return removed;
}

// --------------------------------------------------
//  Cookie headers
// --------------------------------------------------

/// Render the Set-Cookie header value for a session id:
/// "name=id; Path=/; HttpOnly; SameSite=Lax; Max-Age=<n>", with "; Secure"
/// appended when `secure`.
/// Params: name - cookie name; id - session id; max_age_secs - Max-Age in
/// seconds (values <= 0 clamp to 0, which deletes the cookie); secure -
/// append the Secure attribute.
/// Returns: the exact header text; name and id are rendered raw, with no
/// escaping and no id validation.
/// Error case: none.
/// Complexity: O(name + id + digits).
pub fn session_cookie_header(name: Str, id: Str, max_age_secs: Int, secure: Bool) -> Str {
  var age = max_age_secs;
  if age <= 0 {
    age = 0;
  }
  var out = "";
  out = string.str_concat(out, name);
  out = string.str_concat(out, "=");
  out = string.str_concat(out, id);
  out = string.str_concat(out, "; Path=/; HttpOnly; SameSite=Lax; Max-Age=");
  out = string.str_concat(out, _dec_str(age));
  if secure {
    out = string.str_concat(out, "; Secure");
  }
  return out;
}

/// Render the deletion Set-Cookie header value for `name`:
/// "name=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0".
/// Params: name - cookie name (rendered raw).
/// Returns: the exact header text.
/// Error case: none.
/// Complexity: O(name length).
pub fn session_cookie_clear(name: Str) -> Str {
  var out = "";
  out = string.str_concat(out, name);
  out = string.str_concat(out, "=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0");
  return out;
}
