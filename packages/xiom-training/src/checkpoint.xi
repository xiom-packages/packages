// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// XIOM -- xiom.training.checkpoint: model/optimizer capture and text codec
// Part of the xiom.training package.
//
// A checkpoint holds the step, an ASCII tag, the model weights and the
// optimizer momenta. Capture copies both vectors through one push site
// (they cannot drift) and restore returns fresh copies. The text codec is
// strict: "xtr1|<step>|<tag>|<n>|<w0>,...|<m0>,..." with a validated tag
// alphabet, exact entry counts, manual integer parsing (no NUL bytes can be
// produced or accepted) and no trailing fields.

module xiom.training.checkpoint

use xiom.training;
use xiom.string;
use xiom.string.compare;
use xiom.string.split;
use xiom.convert;

/// A training checkpoint: step, tag, model weights and optimizer momenta.
/// weights and momenta are parallel; ckpt_new is the only constructor and
/// enforces equal lengths.
pub type Ckpt = {
  step: Int;
  tag: Str;
  weights: Vec[Int];
  momenta: Vec[Int];
}

fn _ckpt_make(step: Int, tag: Str, weights: Vec[Int], momenta: Vec[Int]) -> Ckpt {
  return Ckpt{ step: step; tag: tag; weights: weights; momenta: momenta; };
}

fn _ok_ckpt(c: Ckpt) -> Result[Ckpt, Str] {
  return Ok(c);
}

fn _err_ckpt(m: Str) -> Result[Ckpt, Str] {
  return Err(m);
}

fn _ckpt_valid_tag(t: Str) -> Bool {
  let n = string.str_len(t);
  if n < 1 || n > _TR_MAX_TAG {
    return false;
  }
  var i = 0;
  while i < n {
    let b = string.byte_at(t, i);
    let c = (b as Int) & 0xFF;
    var okc = false;
    if c >= 65 && c <= 90 {
      okc = true;
    }
    if c >= 97 && c <= 122 {
      okc = true;
    }
    if c >= 48 && c <= 57 {
      okc = true;
    }
    if c == 95 || c == 45 {
      okc = true;
    }
    if !okc {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn _ckpt_push(c: &mut Ckpt, w: Int, m: Int) {
  c.weights.push(w);
  c.momenta.push(m);
}

/// Capture a checkpoint.
/// Params: step - non-negative step index; tag - 1-32 chars of
///         [A-Za-z0-9_-]; weights - model values; momenta - optimizer
///         values, same length as weights (<= 4096).
/// Returns: Ok(the checkpoint with both vectors copied).
/// Error case: Err("training: ...") for a negative step, a bad tag or
/// mismatched/oversized vectors. Complexity: O(weights.len()).
pub fn ckpt_new(step: Int, tag: Str, weights: &Vec[Int], momenta: &Vec[Int]) -> Result[Ckpt, Str] {
  if step < 0 {
    return _err_ckpt("training: checkpoint step must be non-negative");
  }
  if !_ckpt_valid_tag(tag) {
    return _err_ckpt("training: checkpoint tag must be 1-32 chars of [A-Za-z0-9_-]");
  }
  if weights.len() != momenta.len() {
    return _err_ckpt("training: checkpoint weights and momenta must have equal length");
  }
  if weights.len() > _TR_MAX_ENTRIES {
    return _err_ckpt("training: checkpoint exceeds the supported entry envelope");
  }
  var c = _ckpt_make(step, tag, Vec[Int].new(), Vec[Int].new());
  var i = 0;
  while i < weights.len() {
    let wv: Int = weights[i];
    let mv: Int = momenta[i];
    _ckpt_push(&mut c, wv, mv);
    i = i + 1;
  }
  return _ok_ckpt(c);
}

/// Checkpoint step. Complexity: O(1).
pub fn ckpt_step(c: &Ckpt) -> Int {
  return c.step;
}

/// Checkpoint tag. Complexity: O(1).
pub fn ckpt_tag(c: &Ckpt) -> Str {
  return c.tag;
}

/// Number of weights (== number of momenta in a consistent checkpoint).
pub fn ckpt_len(c: &Ckpt) -> Int {
  return c.weights.len();
}

/// True when the parallel vectors have equal length. Complexity: O(1).
pub fn ckpt_is_consistent(c: &Ckpt) -> Bool {
  return c.weights.len() == c.momenta.len();
}

/// Weight i, or TRAIN_NONE when out of range. Complexity: O(1).
pub fn ckpt_weight(c: &Ckpt, i: Int) -> Int {
  if i < 0 || i >= c.weights.len() {
    return TRAIN_NONE;
  }
  let v: Int = c.weights[i];
  return v;
}

/// Momentum i, or TRAIN_NONE when out of range. Complexity: O(1).
pub fn ckpt_momentum(c: &Ckpt, i: Int) -> Int {
  if i < 0 || i >= c.momenta.len() {
    return TRAIN_NONE;
  }
  let v: Int = c.momenta[i];
  return v;
}

/// Restore: a fresh copy of the checkpoint weights. Complexity: O(n).
pub fn ckpt_weights(c: &Ckpt) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < c.weights.len() {
    let v: Int = c.weights[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

/// Restore: a fresh copy of the checkpoint momenta. Complexity: O(n).
pub fn ckpt_momenta(c: &Ckpt) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < c.momenta.len() {
    let v: Int = c.momenta[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

// A wrapping polynomial mix used by ckpt_stamp (deterministic; overflow is
// part of the documented 64-bit wraparound).
fn _ckpt_mix(h: Int, v: Int) -> Int {
  return h * 31 + v;
}

/// Deterministic 64-bit checksum over the step, tag bytes, weights and
/// momenta, with 64-bit wraparound. Equal checkpoints have equal stamps;
/// a changed character or entry changes the stamp with overwhelming
/// probability. Not cryptographic. Complexity: O(n + tag length).
pub fn ckpt_stamp(c: &Ckpt) -> Int {
  var h: Int = 0;
  h = _ckpt_mix(h, c.step);
  let tag = c.tag;
  let tn = string.str_len(tag);
  var i = 0;
  while i < tn {
    let b = string.byte_at(tag, i);
    h = _ckpt_mix(h, (b as Int) & 0xFF);
    i = i + 1;
  }
  i = 0;
  while i < c.weights.len() {
    let wv: Int = c.weights[i];
    h = _ckpt_mix(h, wv);
    i = i + 1;
  }
  i = 0;
  while i < c.momenta.len() {
    let mv: Int = c.momenta[i];
    h = _ckpt_mix(h, mv);
    i = i + 1;
  }
  return h;
}

fn _ckpt_list_str(v: &Vec[Int]) -> Str {
  var out = "";
  var i = 0;
  while i < v.len() {
    if i > 0 {
      out = out + ",";
    }
    let x: Int = v[i];
    out = out + int_to_string(x);
    i = i + 1;
  }
  return out;
}

/// Serialize a checkpoint to one ASCII line:
/// "xtr1|<step>|<tag>|<n>|<w0>,...|<m0>,...". An empty model serializes to
/// two adjacent empty fields ("...|0||"); no NUL bytes are possible (every
/// field is digits, separators, or a validated tag).
/// Params: c - the checkpoint. Returns: the text. Error case: none.
/// Complexity: O(n).
pub fn ckpt_serialize(c: &Ckpt) -> Str {
  let ws: Vec[Int] = c.weights;
  let ms: Vec[Int] = c.momenta;
  return CKPT_MAGIC + "|" + int_to_string(c.step) + "|" + c.tag + "|" + int_to_string(ws.len()) + "|" + _ckpt_list_str(&ws) + "|" + _ckpt_list_str(&ms);
}

// Strict integer field parser: optional '-', then one or more digits, with
// an overflow guard. Leaf Result (scalar payload).
fn _ckpt_parse_int(s: Str) -> Result[Int, Str] {
  let n = string.str_len(s);
  if n == 0 {
    return Err("training: checkpoint: empty integer field");
  }
  var i = 0;
  var neg = false;
  let first = string.byte_at(s, 0);
  if ((first as Int) & 0xFF) == 45 {
    neg = true;
    i = 1;
  }
  if i >= n {
    return Err("training: checkpoint: lone sign");
  }
  var v: Int = 0;
  while i < n {
    let b = string.byte_at(s, i);
    let d = (b as Int) & 0xFF;
    if d < 48 || d > 57 {
      return Err("training: checkpoint: non-digit in integer field");
    }
    let digit = d - 48;
    if v > 922337203685477580 {
      return Err("training: checkpoint: integer field overflows");
    }
    if v == 922337203685477580 && digit > 7 {
      return Err("training: checkpoint: integer field overflows");
    }
    v = v * 10 + digit;
    i = i + 1;
  }
  if neg {
    v = 0 - v;
  }
  return Ok(v);
}

// Parse exactly n comma-separated integer entries from s (n == 0 requires an
// empty field). Rejects missing, extra and non-numeric entries.
fn _ckpt_parse_list(s: Str, n: Int) -> Result[Vec[Int], Str] {
  var out = Vec[Int].new();
  if n == 0 {
    if string.str_len(s) != 0 {
      return _err_ints("training: checkpoint: unexpected entries");
    }
    return _ok_ints(out);
  }
  var rest = s;
  var i = 0;
  while i < n {
    if i == n - 1 {
      if string.str_contains(rest, ",") {
        return _err_ints("training: checkpoint: too many entries");
      }
      let last = _ckpt_parse_int(rest);
      match last {
        Ok(x) => { out.push(x); },
        Err(e) => { return _err_ints(e); },
      }
    } else {
      if !string.str_contains(rest, ",") {
        return _err_ints("training: checkpoint: too few entries");
      }
      let (head, tail) = split.str_split_once(rest, ",");
      let item = _ckpt_parse_int(head);
      match item {
        Ok(x) => { out.push(x); },
        Err(e) => { return _err_ints(e); },
      }
      rest = tail;
    }
    i = i + 1;
  }
  return _ok_ints(out);
}

/// Parse the ckpt_serialize format back into a checkpoint, validating the
/// magic, step, tag alphabet, entry count, every integer field and the
/// absence of trailing fields.
/// Params: s - serialized checkpoint text.
/// Returns: Ok(checkpoint with fresh vectors).
/// Error case: Err("training: checkpoint: ...") for any structural or
/// numeric violation. Complexity: O(len(s)).
pub fn ckpt_parse(s: Str) -> Result[Ckpt, Str] {
  let (f1, r1) = split.str_split_once(s, "|");
  if compare.str_compare(f1, CKPT_MAGIC) != 0 {
    return _err_ckpt("training: checkpoint: bad magic");
  }
  let (f2, r2) = split.str_split_once(r1, "|");
  let step_r = _ckpt_parse_int(f2);
  match step_r {
    Ok(step) => {
      if step < 0 {
        return _err_ckpt("training: checkpoint: negative step");
      }
      let (f3, r3) = split.str_split_once(r2, "|");
      if !_ckpt_valid_tag(f3) {
        return _err_ckpt("training: checkpoint: bad tag");
      }
      let (f4, r4) = split.str_split_once(r3, "|");
      let count_r = _ckpt_parse_int(f4);
      match count_r {
        Ok(count) => {
          if count < 0 || count > _TR_MAX_ENTRIES {
            return _err_ckpt("training: checkpoint: entry count out of range");
          }
          let (f5, r5) = split.str_split_once(r4, "|");
          let (f6, r6) = split.str_split_once(r5, "|");
          if string.str_len(r6) != 0 {
            return _err_ckpt("training: checkpoint: trailing fields");
          }
          let weights_r = _ckpt_parse_list(f5, count);
          match weights_r {
            Ok(ws) => {
              let momenta_r = _ckpt_parse_list(f6, count);
              match momenta_r {
                Ok(ms) => { return _ok_ckpt(_ckpt_make(step, f3, ws, ms)); },
                Err(em) => { return _err_ckpt(em); },
              }
            },
            Err(ew) => { return _err_ckpt(ew); },
          }
        },
        Err(ec) => { return _err_ckpt(ec); },
      }
    },
    Err(es) => { return _err_ckpt(es); },
  }
  return _err_ckpt("training: checkpoint: malformed input");
}
