// XIOM -- xiom.passwd: /etc/passwd parser and canonical emitter
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Model: one parsed passwd file is eight index-aligned vectors owned by
// Passwd: entry i has names[i], passwords[i], uids[i], gids[i], gecos[i],
// homes[i], shells[i] and lines[i] (its 1-based source line). Vec[StructType]
// is unsupported in this compiler, so the document is deliberately flat
// instead of a vector of entry structs. Duplicate names and duplicate uids
// are preserved in document order; there is no dedup and no last-wins
// merging.
//
// Documented subset (see SPEC.md for the exact grammar):
//   * one entry is exactly seven colon-separated fields
//     `name:passwd:uid:gid:gecos:home:shell`; there are no escapes and no
//     quoting, fields are never trimmed, so a field can never contain a
//     colon and a backslash is ordinary data;
//   * a comment line starts with `#` in the very first column and is ignored
//     (its bytes are still subject to the control-byte rule); `#` anywhere
//     else on a line is ordinary data;
//   * a blank line is empty after the CR of a CRLF pair is removed; LF and
//     CRLF line endings are accepted and a missing final newline is fine;
//   * any byte 0x00..0x1F (TAB included) or DEL (0x7F) on a line is
//     Err("passwd: control byte in line <n>") -- in the gecos field and in
//     comments too;
//   * name: 1..32 bytes matching [a-z_][a-z0-9_-]*;
//   * passwd: opaque printable text -- "x", "*", "!", a crypt hash or the
//     empty field -- stored and emitted verbatim, with no check beyond the
//     control-byte rule;
//   * uid/gid: 1..10 ASCII decimal digits with value 0..4294967295; leading
//     zeros are accepted and normalized by the emitter;
//   * gecos: opaque printable text, may be empty;
//   * home and shell: empty, or an absolute path whose first byte is `/`;
//     no other path validation is performed.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; every byte read from a Str goes through
//     _pw_byte_at and is widened as `(byte_at(s, i) as Int) & 0xFF` before
//     any comparison (a raw UInt8 compared against a constant >= 128
//     miscompiles);
//   * no `==` on Str values read from Vec[Str] elements; each is bound to a
//     typed local first and compared with compare.str_compare (BUG 17);
//   * Ok/Err for the struct-payload Result are constructed only in the leaf
//     helpers _pw_ok/_pw_err;
//   * every push on the eight index-aligned vectors is mirrored in
//     _pw_push_entry, and accessors/emit clamp against mismatched lengths so
//     a corrupted document cannot drive out-of-range reads.
//
// See SPEC.md for the model, grammar, error catalog and test plan.

module xiom.passwd

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Document model
// --------------------------------------------------

/// Parsed passwd file. The eight vectors are index-aligned per entry: entry i
/// has login name names[i] (validated, stored as written), passwd field
/// passwords[i] verbatim (may be empty, "x", "*", "!" or a hash), numeric
/// user id uids[i] and group id gids[i] (each 0..4294967295), gecos text
/// gecos[i] verbatim (may be empty), home directory homes[i] and login shell
/// shells[i] (each empty or an absolute path) and 1-based source line
/// lines[i]. Vec[StructType] is unsupported in this compiler, so the model is
/// flat instead of a vector of entry structs. Duplicate names and duplicate
/// uids are preserved in document order (no dedup, no last-wins):
/// passwd_name_index reports the first match by name and passwd_name_for_uid
/// the first match by uid.
pub type Passwd = {
  names: Vec[Str];
  passwords: Vec[Str];
  uids: Vec[Int];
  gids: Vec[Int];
  gecos: Vec[Str];
  homes: Vec[Str];
  shells: Vec[Str];
  lines: Vec[Int];
}

// --------------------------------------------------
//  Constants and byte helpers
// --------------------------------------------------

// ASCII codes used by the scanners (all compared in Int space).
const _PW_LF: Int = 10;
const _PW_CR: Int = 13;
const _PW_HASH: Int = 35;
const _PW_HYPHEN: Int = 45;
const _PW_DIGIT0: Int = 48;
const _PW_DIGIT9: Int = 57;
const _PW_COLON: Int = 58;
const _PW_SLASH: Int = 47;
const _PW_LOWER_A: Int = 97;
const _PW_LOWER_Z: Int = 122;
const _PW_UNDER: Int = 95;
const _PW_DEL: Int = 127;

// Longest accepted login name (the classic shadow-utils / useradd default;
// deliberately stricter than the kernel's 255-byte LOGIN_NAME_MAX).
const _PW_MAX_NAME: Int = 32;
// Largest accepted uid/gid (2^32 - 1).
const _PW_MAX_ID: Int = 4294967295;
// System-user predicate boundary: uid < 1000.
const _PW_SYSTEM_ID_MAX: Int = 1000;

// Read byte i of s widened to Int space (0..255). Every byte read in this
// module goes through here, so byte comparisons never touch UInt8 values.
fn _pw_byte_at(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

fn _pw_is_digit(c: Int) -> Bool {
  return c >= _PW_DIGIT0 && c <= _PW_DIGIT9;
}

fn _pw_is_lower(c: Int) -> Bool {
  return c >= _PW_LOWER_A && c <= _PW_LOWER_Z;
}

// --------------------------------------------------
//  Result leaf helpers
// --------------------------------------------------

// v0.61.3 constructors for the struct-payload Result: Ok/Err are built only in
// these tiny wrappers, never inside a larger function.

fn _pw_ok(d: Passwd) -> Result[Passwd, Str] {
  return Ok(d);
}

fn _pw_err(m: Str) -> Result[Passwd, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Field validation
// --------------------------------------------------

// True when s is a valid login name: 1..32 bytes, first byte a lowercase
// ASCII letter or underscore, later bytes also digits and hyphen. No other
// restriction is applied (in particular a trailing hyphen is allowed); a
// letter case check is exact, so uppercase is rejected.
fn _pw_valid_name(s: Str) -> Bool {
  let n = s.len();
  if n < 1 || n > _PW_MAX_NAME { return false; }
  let first = _pw_byte_at(s, 0);
  if !_pw_is_lower(first) && first != _PW_UNDER { return false; }
  var i = 1;
  while i < n {
    let c = _pw_byte_at(s, i);
    if !_pw_is_lower(c) && !_pw_is_digit(c) && c != _PW_UNDER && c != _PW_HYPHEN {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Parse a uid/gid field. Returns the value for 1..10 ASCII decimal digits
// (leading zeros accepted) when it does not exceed 4294967295; otherwise -1.
// 0 is a real value, so callers must test `< 0`, not `== 0`.
fn _pw_parse_id(s: Str) -> Int {
  let n = s.len();
  if n < 1 || n > 10 { return -1; }
  var v = 0;
  var i = 0;
  while i < n {
    let c = _pw_byte_at(s, i);
    if !_pw_is_digit(c) { return -1; }
    v = v * 10 + (c - _PW_DIGIT0);
    i = i + 1;
  }
  if v > _PW_MAX_ID { return -1; }
  return v;
}

// True when s is empty or starts with `/`. This is the only rule for the home
// and shell fields: no normalization, no existence check and no `/etc/shells`
// membership check is performed.
fn _pw_abs_or_empty(s: Str) -> Bool {
  if s.len() == 0 { return true; }
  return _pw_byte_at(s, 0) == _PW_SLASH;
}

// --------------------------------------------------
//  Line scanning
// --------------------------------------------------

// True when s[start, stop) contains a control byte: 0x00..0x1F (TAB included)
// or DEL. The CR of a CRLF pair is removed by the caller before this runs.
fn _pw_line_has_control(s: Str, start: Int, stop: Int) -> Bool {
  var i = start;
  while i < stop {
    let c = _pw_byte_at(s, i);
    if c < 32 { return true; }
    if c == _PW_DEL { return true; }
    i = i + 1;
  }
  return false;
}

// --------------------------------------------------
//  Parsing
// --------------------------------------------------

// Append one parsed entry. Every index-aligned vector is pushed here, so the
// eight vectors cannot drift apart.
fn _pw_push_entry(doc: &mut Passwd, name: Str, password: Str, uid: Int, gid: Int, gecos: Str, home: Str, shell: Str, line: Int) {
  doc.names.push(name);
  doc.passwords.push(password);
  doc.uids.push(uid);
  doc.gids.push(gid);
  doc.gecos.push(gecos);
  doc.homes.push(home);
  doc.shells.push(shell);
  doc.lines.push(line);
}

/// Parse a passwd file.
/// Params: text - the whole file (LF or CRLF line endings; a missing final
/// newline is accepted).
/// Returns: Ok(Passwd) for a document in the documented subset, including an
/// empty one and one with only comments/blank lines. Every entry line
/// contributes exactly seven fields and its 1-based source line, in document
/// order. Duplicate names and duplicate uids are preserved.
/// Error case: the first failing line in document order, with an exact ASCII
/// message: "passwd: control byte in line <n>" for a byte 0x00..0x1F (TAB
/// included) or DEL anywhere on the line, comments included; "passwd: wrong
/// field count in line <n>" when the line does not have exactly seven
/// colon-separated fields; "passwd: bad name: <field>" for an empty or
/// over-long name or one outside [a-z_][a-z0-9_-]*; "passwd: bad uid:
/// <field>" and "passwd: bad gid: <field>" for a field that is not 1..10
/// decimal digits or exceeds 4294967295; "passwd: bad home: <field>" and
/// "passwd: bad shell: <field>" for a non-empty field that does not start
/// with `/`. Within a line the checks run control byte, field count, then the
/// fields left to right (name, uid, gid, home, shell; passwd and gecos have
/// no rule of their own). <field> is the offending field exactly as written.
/// Examples: "root:x:0:0:root:/root:/bin/bash\n" -> Ok with one entry;
/// "root:x:0:0:root:/root\n" -> Err("passwd: wrong field count in line 1");
/// "a:x:0:0:g:home:/bin/sh\n" -> Err("passwd: bad home: home").
/// Complexity: O(text.len()).
pub fn passwd_parse(text: Str) -> Result[Passwd, Str] {
  var doc = Passwd{
    names: Vec[Str].new();
    passwords: Vec[Str].new();
    uids: Vec[Int].new();
    gids: Vec[Int].new();
    gecos: Vec[Str].new();
    homes: Vec[Str].new();
    shells: Vec[Str].new();
    lines: Vec[Int].new();
  };
  let n = text.len();
  var line_no = 1;
  var start = 0;
  var i = 0;
  while i <= n {
    if i == n || _pw_byte_at(text, i) == _PW_LF {
      var stop = i;
      if stop > start && _pw_byte_at(text, stop - 1) == _PW_CR {
        stop = stop - 1;
      }
      if stop > start {
        let is_comment = _pw_byte_at(text, start) == _PW_HASH;
        if _pw_line_has_control(text, start, stop) {
          return _pw_err("passwd: control byte in line " + convert.int_to_string(line_no));
        }
        if !is_comment {
          var colons = 0;
          var c = start;
          while c < stop {
            if _pw_byte_at(text, c) == _PW_COLON { colons = colons + 1; }
            c = c + 1;
          }
          if colons != 6 {
            return _pw_err("passwd: wrong field count in line " + convert.int_to_string(line_no));
          }
          var fields = Vec[Str].new();
          var fs = start;
          var f = start;
          while f <= stop {
            if f == stop || _pw_byte_at(text, f) == _PW_COLON {
              fields.push(string.str_slice(text, fs, f));
              fs = f + 1;
            }
            f = f + 1;
          }
          let raw_name: Str = fields[0];
          let password: Str = fields[1];
          let raw_uid: Str = fields[2];
          let raw_gid: Str = fields[3];
          let gecos: Str = fields[4];
          let raw_home: Str = fields[5];
          let raw_shell: Str = fields[6];
          if !_pw_valid_name(raw_name) {
            return _pw_err("passwd: bad name: " + raw_name);
          }
          let uid = _pw_parse_id(raw_uid);
          if uid < 0 {
            return _pw_err("passwd: bad uid: " + raw_uid);
          }
          let gid = _pw_parse_id(raw_gid);
          if gid < 0 {
            return _pw_err("passwd: bad gid: " + raw_gid);
          }
          if !_pw_abs_or_empty(raw_home) {
            return _pw_err("passwd: bad home: " + raw_home);
          }
          if !_pw_abs_or_empty(raw_shell) {
            return _pw_err("passwd: bad shell: " + raw_shell);
          }
          _pw_push_entry(&mut doc, raw_name, password, uid, gid, gecos, raw_home, raw_shell, line_no);
        }
      }
      line_no = line_no + 1;
      start = i + 1;
    }
    i = i + 1;
  }
  return _pw_ok(doc);
}

// --------------------------------------------------
//  Accessors
// --------------------------------------------------

/// Number of entries in the document.
/// Params: d - parsed document.
/// Returns: the entry count; a corrupted document reports the smallest of the
/// eight index-aligned vectors, so trailing rows are ignored rather than read
/// out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn passwd_entry_count(d: &Passwd) -> Int {
  var n = d.names.len();
  if d.passwords.len() < n { n = d.passwords.len(); }
  if d.uids.len() < n { n = d.uids.len(); }
  if d.gids.len() < n { n = d.gids.len(); }
  if d.gecos.len() < n { n = d.gecos.len(); }
  if d.homes.len() < n { n = d.homes.len(); }
  if d.shells.len() < n { n = d.shells.len(); }
  if d.lines.len() < n { n = d.lines.len(); }
  return n;
}

/// Login name of entry i, exactly as written.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: Some(name) for 0 <= i < passwd_entry_count(d), else None.
/// Error case: none.
/// Examples: entry "root:x:0:0:root:/root:/bin/bash" -> Some("root").
/// Complexity: O(1).
pub fn passwd_name(d: &Passwd, i: Int) -> Option[Str] {
  if i < 0 || i >= passwd_entry_count(d) { return None; }
  let v: Str = d.names[i];
  return Some(v);
}

/// Passwd field of entry i, exactly as written and with no interpretation.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: Some(text) for 0 <= i < passwd_entry_count(d), else None. The
/// empty field is a real value, so it is Some("") rather than None; "x", "*",
/// "!", a crypt hash and any other printable text are all stored verbatim,
/// and no shadow-file lookup, lock detection or hashing is performed.
/// Error case: none.
/// Examples: entry "a::1:1:g:/h:/s" -> Some("").
/// Complexity: O(1).
pub fn passwd_password(d: &Passwd, i: Int) -> Option[Str] {
  if i < 0 || i >= passwd_entry_count(d) { return None; }
  let v: Str = d.passwords[i];
  return Some(v);
}

/// Numeric user id of entry i.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: Some(uid) with 0 <= uid <= 4294967295 for 0 <= i <
/// passwd_entry_count(d), else None. 0 is a real value (root), so an
/// out-of-range index is reported as None rather than 0.
/// Error case: none.
/// Complexity: O(1).
pub fn passwd_uid(d: &Passwd, i: Int) -> Option[Int] {
  if i < 0 || i >= passwd_entry_count(d) { return None; }
  let v: Int = d.uids[i];
  return Some(v);
}

/// Numeric group id of entry i.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: Some(gid) with 0 <= gid <= 4294967295 for 0 <= i <
/// passwd_entry_count(d), else None.
/// Error case: none.
/// Complexity: O(1).
pub fn passwd_gid(d: &Passwd, i: Int) -> Option[Int] {
  if i < 0 || i >= passwd_entry_count(d) { return None; }
  let v: Int = d.gids[i];
  return Some(v);
}

/// Gecos field of entry i (the free-text comment field), verbatim.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: Some(text) for 0 <= i < passwd_entry_count(d), else None. The
/// empty field is a real value, so it is Some("") rather than None; spaces,
/// commas, `#` and non-ASCII bytes are preserved.
/// Error case: none.
/// Complexity: O(1).
pub fn passwd_gecos(d: &Passwd, i: Int) -> Option[Str] {
  if i < 0 || i >= passwd_entry_count(d) { return None; }
  let v: Str = d.gecos[i];
  return Some(v);
}

/// Home directory of entry i, verbatim.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: Some(path) for 0 <= i < passwd_entry_count(d), else None. The
/// field is empty or an absolute path (first byte `/`); the empty field is a
/// real value, so it is Some("") rather than None.
/// Error case: none.
/// Complexity: O(1).
pub fn passwd_home(d: &Passwd, i: Int) -> Option[Str] {
  if i < 0 || i >= passwd_entry_count(d) { return None; }
  let v: Str = d.homes[i];
  return Some(v);
}

/// Login shell of entry i, verbatim.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: Some(path) for 0 <= i < passwd_entry_count(d), else None. The
/// field is empty or an absolute path (first byte `/`); the empty field is a
/// real value, so it is Some("") rather than None.
/// Error case: none.
/// Complexity: O(1).
pub fn passwd_shell(d: &Passwd, i: Int) -> Option[Str] {
  if i < 0 || i >= passwd_entry_count(d) { return None; }
  let v: Str = d.shells[i];
  return Some(v);
}

/// 1-based source line number of entry i.
/// Params: d - parsed document; i - zero-based entry index.
/// Returns: the line number for 0 <= i < passwd_entry_count(d), else 0.
/// Blank and comment lines are counted, so this is the physical line.
/// Error case: none.
/// Complexity: O(1).
pub fn passwd_line(d: &Passwd, i: Int) -> Int {
  if i < 0 || i >= passwd_entry_count(d) { return 0; }
  let v: Int = d.lines[i];
  return v;
}

// --------------------------------------------------
//  Lookups
// --------------------------------------------------

/// Zero-based index of the first entry whose login name equals `name`.
/// Params: d - parsed document; name - login name query.
/// Returns: the first matching entry index in document order, or -1 when no
/// entry matches. Comparison is byte-exact and case-sensitive (login names
/// are stored lowercase, so an uppercase query cannot match). Duplicate names
/// are preserved by the parser, so this is a documented first-match policy.
/// Error case: none.
/// Examples: two "dup" entries -> 0.
/// Complexity: O(entries * name length).
pub fn passwd_name_index(d: &Passwd, name: Str) -> Int {
  let n = passwd_entry_count(d);
  var i = 0;
  while i < n {
    let nm: Str = d.names[i];
    if compare.str_compare(nm, name) == 0 { return i; }
    i = i + 1;
  }
  return -1;
}

/// Home directory of the first entry whose login name equals `name`.
/// Params: d - parsed document; name - login name query.
/// Returns: Some(home) for the first match in document order, else None.
/// Matching follows passwd_name_index, so it is byte-exact and
/// case-sensitive; a duplicate name resolves to its first entry.
/// Error case: none.
/// Examples: "dup" -> Some("/home/first") when that entry comes first.
/// Complexity: O(entries * name length).
pub fn passwd_home_for_name(d: &Passwd, name: Str) -> Option[Str] {
  let i = passwd_name_index(d, name);
  if i < 0 { return None; }
  let v: Str = d.homes[i];
  return Some(v);
}

/// Login shell of the first entry whose login name equals `name`.
/// Params: d - parsed document; name - login name query.
/// Returns: Some(shell) for the first match in document order, else None.
/// Matching follows passwd_name_index.
/// Error case: none.
/// Examples: "dup" -> Some("/bin/bash") when that entry comes first.
/// Complexity: O(entries * name length).
pub fn passwd_shell_for_name(d: &Passwd, name: Str) -> Option[Str] {
  let i = passwd_name_index(d, name);
  if i < 0 { return None; }
  let v: Str = d.shells[i];
  return Some(v);
}

/// Uid of the first entry whose login name equals `name`.
/// Params: d - parsed document; name - login name query.
/// Returns: Some(uid) for the first match in document order, else None.
/// Matching follows passwd_name_index.
/// Error case: none.
/// Examples: "dup" -> Some(1000) when that entry comes first.
/// Complexity: O(entries * name length).
pub fn passwd_uid_for_name(d: &Passwd, name: Str) -> Option[Int] {
  let i = passwd_name_index(d, name);
  if i < 0 { return None; }
  let v: Int = d.uids[i];
  return Some(v);
}

/// Number of entries whose uid equals `uid`.
/// Params: d - parsed document; uid - numeric uid query.
/// Returns: the count of entries with that uid, in document order; 0 when no
/// entry matches. Duplicate uids are preserved by the parser, so one uid can
/// name several entries. A negative uid simply matches nothing.
/// Error case: none.
/// Examples: two entries with uid 1000 -> 2.
/// Complexity: O(entries).
pub fn passwd_uid_count(d: &Passwd, uid: Int) -> Int {
  let n = passwd_entry_count(d);
  var count = 0;
  var i = 0;
  while i < n {
    let v: Int = d.uids[i];
    if v == uid { count = count + 1; }
    i = i + 1;
  }
  return count;
}

/// Login names of every entry whose uid equals `uid`, in document order.
/// Params: d - parsed document; uid - numeric uid query.
/// Returns: a fresh Vec of names (empty when nothing matches); duplicate
/// names are kept, one element per entry. A negative uid matches nothing.
/// Error case: none.
/// Examples: two entries with uid 1000 -> ["a", "b"].
/// Complexity: O(entries).
pub fn passwd_names_for_uid(d: &Passwd, uid: Int) -> Vec[Str] {
  var out = Vec[Str].new();
  let n = passwd_entry_count(d);
  var i = 0;
  while i < n {
    let v: Int = d.uids[i];
    if v == uid {
      let nm: Str = d.names[i];
      out.push(nm);
    }
    i = i + 1;
  }
  return out;
}

/// Login name of the first entry whose uid equals `uid`.
/// Params: d - parsed document; uid - numeric uid query.
/// Returns: Some(name) for the first match in document order, else None
/// (also for an absent or negative uid). Duplicate uids resolve to the first
/// entry; use passwd_names_for_uid for every match.
/// Error case: none.
/// Examples: entries "a" and "b" both with uid 1000 -> Some("a").
/// Complexity: O(entries).
pub fn passwd_name_for_uid(d: &Passwd, uid: Int) -> Option[Str] {
  let n = passwd_entry_count(d);
  var i = 0;
  while i < n {
    let v: Int = d.uids[i];
    if v == uid {
      let nm: Str = d.names[i];
      return Some(nm);
    }
    i = i + 1;
  }
  return None;
}

/// Number of system-user entries: those whose uid is below 1000.
/// Params: d - parsed document.
/// Returns: the count of entries with uid < 1000. The predicate is the
/// conventional login.defs UID_MIN boundary; it is documented, advisory and
/// purely numeric -- names, shells and gecos are not interpreted, and each
/// duplicate entry counts once. uid 0 (root) counts as a system user.
/// Error case: none.
/// Examples: uids 0, 999, 1000, 65534 -> 2.
/// Complexity: O(entries).
pub fn passwd_system_user_count(d: &Passwd) -> Int {
  let n = passwd_entry_count(d);
  var count = 0;
  var i = 0;
  while i < n {
    let v: Int = d.uids[i];
    if v < _PW_SYSTEM_ID_MAX { count = count + 1; }
    i = i + 1;
  }
  return count;
}

// --------------------------------------------------
//  Emitting
// --------------------------------------------------

/// Emit a document in the canonical passwd form.
/// Params: d - parsed document.
/// Returns: one line per entry, the seven fields joined by single colons
/// (`name:passwd:uid:gid:gecos:home:shell`) and a trailing LF after every
/// line; an empty document emits "". Comments, blank lines, CRLF endings and
/// source line numbers are not preserved; every text field is written
/// verbatim (no escapes exist) and uid/gid are written as canonical decimal,
/// so leading zeros are dropped. For a document produced by passwd_parse,
/// emit(parse(x)) is a fixed point: parsing the emitted text yields the same
/// entries and emitting that result reproduces the text byte for byte.
/// Error case: none.
/// Examples: parse("root:x:0:0:root:/root:/bin/bash\n") emits
/// "root:x:0:0:root:/root:/bin/bash\n";
/// parse("a:x:0001:0001:g:/h:/s\n") emits "a:x:1:1:g:/h:/s\n".
/// Complexity: O(total output length).
pub fn passwd_emit(d: &Passwd) -> Str {
  var out = "";
  let n = passwd_entry_count(d);
  var i = 0;
  while i < n {
    let name: Str = d.names[i];
    let password: Str = d.passwords[i];
    let uid: Int = d.uids[i];
    let gid: Int = d.gids[i];
    let gecos: Str = d.gecos[i];
    let home: Str = d.homes[i];
    let shell: Str = d.shells[i];
    var line = name;
    line = line + ":" + password;
    line = line + ":" + convert.int_to_string(uid);
    line = line + ":" + convert.int_to_string(gid);
    line = line + ":" + gecos;
    line = line + ":" + home;
    line = line + ":" + shell;
    out = out + line + "\n";
    i = i + 1;
  }
  return out;
}
