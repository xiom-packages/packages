// XIOM -- xiom.audit: hash-chained append-only audit log with verification and export
// Port task: replace the xiom.audit placeholder with a pure-XIOM module (no FFI).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Contract (see SPEC.md for the full definition):
//   - append-only log of Str entries; every entry is chained to its predecessor
//     with FNV-1a 32-bit over UTF-8 bytes:
//       h(i) = fnv1a(decimal(h(i-1)) + ":" + entry(i)),  h(-1) = 0
//   - the log is tamper-EVIDENT only: an attacker who can rewrite the whole
//     vector can recompute a consistent chain. Detection requires the head hash
//     to be stored and compared somewhere the attacker does not control
//     (external anchoring). There are no secrets and no authentication here.
//   - FNV-1a 32-bit is a checksum, NOT a cryptographic hash: it is cheap to
//     forge and must not be used against a motivated adversary.
//
// Pure XIOM, free functions only (v0.61.x has no methods). Entries and hashes
// are kept index-aligned: entries[i] is hashed by hashes[i].

module xiom.audit

use xiom.string;
use xiom.convert;

/// Append-only audit log. `entries` holds the payloads in append order;
/// `hashes[i]` is the chain hash of `entries[i]`. Fields are implementation
/// details: construct through audit_new and mutate through audit_append.
/// Invariant: hashes.len() == entries.len() for a log built through this API.
pub type AuditLog = {
  entries: Vec[Str];
  hashes: Vec[Int];
}

/// FNV-1a 32-bit hash over the UTF-8 bytes of `s`, as a non-negative Int
/// in [0, 2^32-1].
/// FNV-1a: hash = offset_basis; for each byte: hash ^= byte; hash *= prime.
///   offset_basis (32-bit) = 2166136261 (0x811C9DC5)
///   prime        (32-bit) = 16777619   (0x01000193)
/// All arithmetic is masked to 32 bits with 0xFFFFFFFF.
/// Params: s - the text to hash (byte-exact UTF-8; empty string allowed).
/// Returns: the 32-bit hash value, always non-negative.
/// Error case: none. Complexity: O(s.len()).
pub fn audit_hash_fnv1a(s: Str) -> Int {
  var hash = 2166136261;
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i) as Int;
    hash = hash ^ b;
    hash = (hash * 16777619) & 4294967295;
    i = i + 1;
  }
  return hash;
}

/// Create an empty audit log (zero entries, zero hashes). Complexity: O(1).
pub fn audit_new() -> AuditLog {
  return AuditLog{ entries: Vec[Str].new(); hashes: Vec[Int].new(); };
}

/// Append one entry and chain it to the current head.
/// The new hash is fnv1a(decimal(prev) + ":" + entry) where `prev` is the
/// previous entry's hash, or 0 when the log was empty. Both the entry and its
/// hash are stored; the hash is returned to the caller (useful as an anchor
/// for compare-and-continue protocols).
/// Params: log - the mutable log; entry - the payload (empty allowed).
/// Returns: the hash of the appended entry (same value as audit_hash(log, n-1)).
/// Error case: none. Complexity: O(|decimal(prev)| + entry.len()).
pub fn audit_append(log: &mut AuditLog, entry: Str) -> Int {
  var prev: Int = 0;
  let n = log.hashes.len();
  if n > 0 {
    let last: Int = log.hashes[n - 1];
    prev = last;
  }
  let payload = convert.int_to_string(prev) + ":" + entry;
  let h = audit_hash_fnv1a(payload);
  log.entries.push(entry);
  log.hashes.push(h);
  return h;
}

/// Number of entries in the log. Complexity: O(1).
pub fn audit_len(log: &AuditLog) -> Int {
  return log.entries.len();
}

/// Entry at zero-based index `i`, or "" when `i` is negative or >= audit_len.
/// Params: log - the log; i - zero-based index.
/// Returns: the entry, or "" out of range.
/// Error case: none. Complexity: O(1).
pub fn audit_entry(log: &AuditLog, i: Int) -> Str {
  if i < 0 {
    return "";
  }
  if i >= log.entries.len() {
    return "";
  }
  return log.entries[i];
}

/// Chain hash at zero-based index `i`, or -1 when `i` is negative or
/// >= audit_len. Hashes are always in [0, 2^32-1], so -1 is unambiguous.
/// Params: log - the log; i - zero-based index.
/// Returns: the hash, or -1 out of range.
/// Error case: none. Complexity: O(1).
pub fn audit_hash(log: &AuditLog, i: Int) -> Int {
  if i < 0 {
    return -1;
  }
  if i >= log.hashes.len() {
    return -1;
  }
  let h: Int = log.hashes[i];
  return h;
}

/// Hash of the most recent entry, or 0 for an empty log. 0 is also the chain
/// seed, so an empty log and a hypothetical all-zero head are indistinguishable
/// by design (see SPEC.md). Complexity: O(1).
pub fn audit_head_hash(log: &AuditLog) -> Int {
  let n = log.hashes.len();
  if n == 0 {
    return 0;
  }
  let last: Int = log.hashes[n - 1];
  return last;
}

/// Recompute the whole chain from the seed and compare it to the stored
/// hashes. Also fails when the vectors are not index-aligned (length mismatch).
/// Returns: true only when every stored hash equals the recomputed one.
/// Error case: none. Complexity: O(total entry length).
pub fn audit_verify(log: &AuditLog) -> Bool {
  if log.entries.len() != log.hashes.len() {
    return false;
  }
  var prev: Int = 0;
  var i = 0;
  while i < log.entries.len() {
    let entry = log.entries[i];
    let payload = convert.int_to_string(prev) + ":" + entry;
    let h = audit_hash_fnv1a(payload);
    let stored: Int = log.hashes[i];
    if h != stored {
      return false;
    }
    prev = h;
    i = i + 1;
  }
  return true;
}

/// Verify the prefix entries [0, up_to). `up_to` is clamped: negative values
/// mean "empty prefix" (always true) and values past the end mean "whole log".
/// A prefix that reaches past the stored hashes (a truncated hash vector)
/// fails. Returns: true when every checked link matches.
/// Error case: none. Complexity: O(sum of the checked entry lengths).
pub fn audit_verify_prefix(log: &AuditLog, up_to: Int) -> Bool {
  var limit = up_to;
  if limit < 0 {
    limit = 0;
  }
  if limit > log.entries.len() {
    limit = log.entries.len();
  }
  if log.hashes.len() < limit {
    return false;
  }
  var prev: Int = 0;
  var i = 0;
  while i < limit {
    let entry = log.entries[i];
    let payload = convert.int_to_string(prev) + ":" + entry;
    let h = audit_hash_fnv1a(payload);
    let stored: Int = log.hashes[i];
    if h != stored {
      return false;
    }
    prev = h;
    i = i + 1;
  }
  return true;
}

// Escape one export field: LF -> the two characters "\n", '|' -> "\|".
// Backslash itself is not escaped (see SPEC.md, export grammar); the export
// is line/field parseable only when entries contain neither sequence.
fn _audit_export_escape(s: Str) -> Str {
  var out = "";
  var i = 0;
  while i < s.len() {
    let b = string.byte_at(s, i) as Int;
    if b == 10 {
      out = out + "\\" + "n";
    } elif b == 124 {
      out = out + "\\" + "|";
    } else {
      out = out + string.str_slice(s, i, i + 1);
    }
    i = i + 1;
  }
  return out;
}

/// Export the whole log as text: one line per entry, joined with "\n" (no
/// trailing newline), each line "<seq>|<hash>|<entry>":
///   - seq is the zero-based index (so it equals the audit_entry index),
///   - hash is the decimal chain hash (no padding),
///   - entry is escaped: LF -> "\n" and '|' -> "\|" (backslash-prefixed).
/// An empty log exports as "". Params: log - the log.
/// Returns: the export text. Error case: none. Complexity: O(total entry length).
pub fn audit_export(log: &AuditLog) -> Str {
  var out = "";
  var i = 0;
  while i < log.entries.len() {
    if i > 0 {
      out = out + "\n";
    }
    let h: Int = log.hashes[i];
    out = out + convert.int_to_string(i) + "|" + convert.int_to_string(h) + "|" + _audit_export_escape(log.entries[i]);
    i = i + 1;
  }
  return out;
}
