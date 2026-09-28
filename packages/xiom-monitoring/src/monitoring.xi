// XIOM -- xiom.monitoring: Prometheus/OpenMetrics text exposition parser
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: implement xiom.monitoring as a real, tested, pure-XIOM parser
// for the Prometheus text exposition format and the OpenMetrics text format.
// Scope: the line-oriented text formats only (parser, no rendering, no HTTP,
// no protobuf). Non-goals: scraping transports, metric serialization,
// timezone conversion, UTF-8 validation (see SPEC.md).
//
// Model: a parsed document is a flat value (MonDoc) whose family table and
// sample list are stored as PARALLEL VECTORS (Vec[StructType] and
// Vec[Float64] are unsupported in this compiler): family `f` has name
// `fam_names[f]`, TYPE `fam_types[f]` ("" when undeclared), HELP raw text
// `fam_helps[f]`, unescaped HELP `fam_help_texts[f]`, UNIT `fam_units[f]`;
// sample `s` has name `sample_name[s]`, family `sample_fam[s]`, part
// `sample_part[s]` (0 plain, 1 bucket, 2 sum, 3 count, 4 created, 5
// quantile), the raw value span `sample_value_raw[s]`, the parsed value
// (kind / mantissa / decimal exponent / overflow flag), the optional
// millisecond timestamp, the source line and byte offsets; label `l` belongs
// to `label_sample[l]` with name `label_names[l]`, unescaped value
// `label_values[l]`, wire value `label_values_raw[l]` and byte spans;
// exemplars mirror labels with `ex_sample` linking back to the sample.
//
// Value representation: every finite value is stored as a signed integer
// mantissa and a base-10 exponent (value = mant * 10^exp) plus a kind code
// (0 finite, 1 +Inf, 2 -Inf, 3 NaN). `mon_*_value_micro` scales to integer
// micro-units (1e-6) truncating toward zero and saturating at the Int range
// limits; `mon_*_value_float` returns a scalar Float64 built from mant/exp
// (Float64 scalars are allowed; Vec[Float64] is not).
//
// Families: samples are grouped by metric name. `# TYPE x histogram` also
// captures `x_bucket` (part 1), `x_sum` (2) and `x_count` (3);
// `# TYPE x summary` also captures `x_sum`/`x_count`, while `x{quantile=...}`
// stays on the exact family. `x_created` samples are plain samples (part 4)
// with no special semantics. Declarations must precede the samples they
// describe, as in every real exposition; a `# TYPE` after its samples does
// not retroactively re-group them.
//
// Histogram rules: `x_bucket` requires an `le` label when `x` is declared
// histogram; `le` must parse as a finite value or exactly `+Inf`; the bucket
// boundaries of a family must be strictly increasing (compared in
// micro-units, `+Inf` last), and duplicates/regressions are rejected with
// offsets. Summary quantile label values must parse as finite values inside
// [0, 1]. A plain sample of a declared histogram (or a summary sample
// without `quantile`) is rejected.
//
// Errors are deterministic strings "monitoring: <reason> at <byte offset>"
// where the offset is absolute in the parsed input. `mon_parse` is strict
// (first error aborts); `mon_parse_lenient` collects every error and keeps
// the samples that did parse. `mon_parse_line` parses exactly one line and
// reports offsets relative to that line.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no self methods, no lambdas, no Vec[StructType];
//   * every byte is read through xiom.string.byte_at into an Int domain
//     (widened and masked with & 0xFF) and compared against masked Int
//     constants, so no UInt8 >= 128 is ever compared raw;
//   * Str equality never uses `==` on a value read from a Vec[Str] element
//     (BUG 17 lowers that to pointer comparison): every comparison goes
//     through xiom.string.compare.str_compare after binding the element to a
//     typed local;
//   * Ok/Err for every Result[...] are constructed only in the tiny leaf
//     helpers below; parsers return plain scan structs with an err/pos pair;
//   * `&mut Int` out-params are avoided entirely -- helpers return values;
//   * truncating Int division is implemented explicitly (sign stripped).

module xiom.monitoring

use xiom.string;
use xiom.string.compare;
use xiom.convert.int;
use xiom.convert.float;
use xiom.math.constants;

// --------------------------------------------------
//  Masked byte constants (Int domain)
// --------------------------------------------------

const _MON_LF: Int = 10;
const _MON_CR: Int = 13;
const _MON_TAB: Int = 9;
const _MON_SP: Int = 32;
const _MON_DQUOTE: Int = 34;
const _MON_HASH: Int = 35;
const _MON_PLUS: Int = 43;
const _MON_COMMA: Int = 44;
const _MON_DASH: Int = 45;
const _MON_DOT: Int = 46;
const _MON_ZERO: Int = 48;
const _MON_NINE: Int = 57;
const _MON_COLON: Int = 58;
const _MON_UPPER_A: Int = 65;
const _MON_UPPER_E: Int = 69;
const _MON_UPPER_Z: Int = 90;
const _MON_BACKSLASH: Int = 92;
const _MON_UNDERSCORE: Int = 95;
const _MON_LOWER_A: Int = 97;
const _MON_LOWER_E: Int = 101;
const _MON_LOWER_N: Int = 110;
const _MON_LOWER_Z: Int = 122;
const _MON_LBRACE: Int = 123;
const _MON_RBRACE: Int = 125;
const _MON_EQ: Int = 61;

// Decimal precision limits.
const _MON_DIGIT_CAP: Int = 18;
const _MON_EXP_CAP: Int = 1000000;
const _MON_MUL10_LIMIT: Int = 922337203685477580;
const _MON_I64_MAX: Int = 9223372036854775807;
const _MON_MICRO_SCALE: Int = 6;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One parsed value token. `mant`/`exp` represent a finite value exactly as
/// written when `over` is false (value = mant * 10^exp); when more than 18
/// significant digits were present `over` is true and the stored value is a
/// truncation of the written text. `kind` is 0 finite, 1 +Inf, 2 -Inf,
/// 3 NaN (for the specials mant/exp are 0).
pub type MonValue = {
  raw: Str;
  kind: Int;
  neg: Bool;
  mant: Int;
  exp: Int;
  over: Bool;
}

/// One parsed exposition line. `kind` is 0 blank, 1 comment, 2 HELP,
/// 3 TYPE, 4 UNIT, 5 EOF, 6 sample. Directive fields hold the declared
/// name/type/unit and the raw plus unescaped HELP text; sample fields hold
/// the metric name, its syntactic part, the value (raw span plus parsed
/// form), the optional timestamp and the label/exemplar parallel vectors.
/// Offsets are byte offsets into the line text.
pub type MonLine = {
  kind: Int;
  name: Str;
  name_at: Int;
  part: Int;
  type_text: Str;
  type_at: Int;
  help_raw: Str;
  help_text: Str;
  help_at: Int;
  unit_text: Str;
  unit_at: Int;
  value_raw: Str;
  value_kind: Int;
  value_mant: Int;
  value_exp: Int;
  value_over: Bool;
  value_at: Int;
  value_len: Int;
  has_ts: Bool;
  ts: Int;
  ts_at: Int;
  ts_len: Int;
  label_names: Vec[Str];
  label_values: Vec[Str];
  label_values_raw: Vec[Str];
  label_name_at: Vec[Int];
  label_name_len: Vec[Int];
  label_value_at: Vec[Int];
  label_value_len: Vec[Int];
  ex_count: Int;
  ex_value_raw: Str;
  ex_value_kind: Int;
  ex_value_mant: Int;
  ex_value_exp: Int;
  ex_value_over: Bool;
  ex_has_ts: Bool;
  ex_ts: Int;
  ex_at: Int;
  ex_len: Int;
  ex_label_names: Vec[Str];
  ex_label_values: Vec[Str];
  ex_label_at: Vec[Int];
  ex_label_len: Vec[Int];
  at: Int;
  len: Int;
}

/// One parsed exposition document. Parallel-vector tables: families,
/// samples, labels and exemplars (see the module header).
/// `err_msgs`/`err_lines`/`err_ats` are the collected errors of the lenient
/// walk; `line_count` and `byte_count` record how much input was consumed;
/// `eof_seen`/`eof_at` record the OpenMetrics `# EOF` marker. The `fam_le_*`
/// triple is parser state used by the monotonic bucket-ordering check (last
/// boundary seen per family).
pub type MonDoc = {
  line_count: Int;
  byte_count: Int;
  eof_seen: Bool;
  eof_at: Int;
  err_msgs: Vec[Str];
  err_lines: Vec[Int];
  err_ats: Vec[Int];
  fam_names: Vec[Str];
  fam_types: Vec[Str];
  fam_has_type: Vec[Bool];
  fam_helps: Vec[Str];
  fam_help_texts: Vec[Str];
  fam_has_help: Vec[Bool];
  fam_units: Vec[Str];
  fam_has_unit: Vec[Bool];
  fam_le_seen: Vec[Bool];
  fam_le_micro: Vec[Int];
  fam_le_inf: Vec[Bool];
  sample_fam: Vec[Int];
  sample_name: Vec[Str];
  sample_part: Vec[Int];
  sample_value_raw: Vec[Str];
  sample_value_kind: Vec[Int];
  sample_value_mant: Vec[Int];
  sample_value_exp: Vec[Int];
  sample_value_over: Vec[Bool];
  sample_has_ts: Vec[Bool];
  sample_ts: Vec[Int];
  sample_line: Vec[Int];
  sample_at: Vec[Int];
  sample_len: Vec[Int];
  sample_ex_count: Vec[Int];
  sample_le_raw: Vec[Str];
  sample_le_micro: Vec[Int];
  sample_le_inf: Vec[Bool];
  sample_has_le: Vec[Bool];
  sample_quantile_raw: Vec[Str];
  sample_quantile_micro: Vec[Int];
  sample_has_quantile: Vec[Bool];
  label_sample: Vec[Int];
  label_names: Vec[Str];
  label_values: Vec[Str];
  label_values_raw: Vec[Str];
  label_name_at: Vec[Int];
  label_name_len: Vec[Int];
  label_value_at: Vec[Int];
  label_value_len: Vec[Int];
  ex_sample: Vec[Int];
  ex_values_raw: Vec[Str];
  ex_value_kind: Vec[Int];
  ex_value_mant: Vec[Int];
  ex_value_exp: Vec[Int];
  ex_value_over: Vec[Bool];
  ex_has_ts: Vec[Bool];
  ex_ts: Vec[Int];
  ex_at: Vec[Int];
  ex_len: Vec[Int];
  ex_label_ex: Vec[Int];
  ex_label_names: Vec[Str];
  ex_label_values: Vec[Str];
  ex_label_values_raw: Vec[Str];
  ex_label_name_at: Vec[Int];
  ex_label_name_len: Vec[Int];
  ex_label_value_at: Vec[Int];
  ex_label_value_len: Vec[Int];
}

// --------------------------------------------------
//  Internal scan results (plain values, no Result)
// --------------------------------------------------

// One scanned value token: parsed fields plus the error reason/offset when
// `ok` is false. `next` is the byte after the token.
type _VScan = {
  ok: Bool;
  kind: Int;
  neg: Bool;
  mant: Int;
  exp: Int;
  over: Bool;
  err: Str;
  pos: Int;
  next: Int;
}

// One scanned millisecond timestamp: `value` or `err`/`pos`.
type _TsScan = {
  ok: Bool;
  value: Int;
  err: Str;
  pos: Int;
}

// One scanned `name="value"` label: decoded `value`, wire `value_raw`, the
// byte spans of the name and the escaped value, and `next` (the byte after
// the closing quote).
type _LScan = {
  ok: Bool;
  name: Str;
  value: Str;
  value_raw: Str;
  name_at: Int;
  name_len: Int;
  value_at: Int;
  value_len: Int;
  next: Int;
  err: Str;
  pos: Int;
}

// One scanned `# ...` line. `kind` is 0 comment, 2 HELP, 3 TYPE, 4 UNIT,
// 5 EOF. For HELP, `text` is the raw wire text and `text_text` the
// unescaped text. For TYPE, `text` is the type word. For UNIT, `text` is
// the unit.
type _DScan = {
  kind: Int;
  name: Str;
  name_at: Int;
  text: Str;
  text_text: Str;
  text_at: Int;
  err: Str;
  pos: Int;
}

// One physical line span: [start, end) content (CR stripped) and `next`.
type _Span = {
  start: Int;
  end: Int;
  next: Int;
  blank: Bool;
}

// One scanned sample expression (everything after the leading whitespace of
// a non-directive line), with all parallel label/exemplar vectors.
type _SScan = {
  ok: Bool;
  part: Int;
  name: Str;
  name_at: Int;
  end_at: Int;
  value_at: Int;
  value_len: Int;
  value_kind: Int;
  value_mant: Int;
  value_exp: Int;
  value_over: Bool;
  value_neg: Bool;
  has_ts: Bool;
  ts: Int;
  ts_at: Int;
  ts_len: Int;
  ex_present: Bool;
  ex_at: Int;
  ex_len: Int;
  ex_value_at: Int;
  ex_value_len: Int;
  ex_value_kind: Int;
  ex_value_mant: Int;
  ex_value_exp: Int;
  ex_value_over: Bool;
  ex_has_ts: Bool;
  ex_ts: Int;
  labels: Vec[Str];
  label_values: Vec[Str];
  label_values_raw: Vec[Str];
  label_name_at: Vec[Int];
  label_name_len: Vec[Int];
  label_value_at: Vec[Int];
  label_value_len: Vec[Int];
  ex_label_names: Vec[Str];
  ex_label_values: Vec[Str];
  ex_label_values_raw: Vec[Str];
  ex_label_name_at: Vec[Int];
  ex_label_name_len: Vec[Int];
  ex_label_value_at: Vec[Int];
  ex_label_value_len: Vec[Int];
  err: Str;
  pos: Int;
}

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

fn _ok_doc(v: MonDoc) -> Result[MonDoc, Str] {
  return Ok(v);
}

fn _err_doc(m: Str) -> Result[MonDoc, Str] {
  return Err(m);
}

fn _ok_line(v: MonLine) -> Result[MonLine, Str] {
  return Ok(v);
}

fn _err_line(m: Str) -> Result[MonLine, Str] {
  return Err(m);
}

fn _ok_value(v: MonValue) -> Result[MonValue, Str] {
  return Ok(v);
}

fn _err_value(m: Str) -> Result[MonValue, Str] {
  return Err(m);
}

fn _ok_float(v: Float64) -> Result[Float64, Str] {
  return Ok(v);
}

fn _err_float(m: Str) -> Result[Float64, Str] {
  return Err(m);
}

// "monitoring: <reason> at <pos>"; the deterministic shape of every error.
fn _err_at(reason: Str, pos: Int) -> Str {
  return "monitoring: " + reason + " at " + int_to_string(pos);
}

// --------------------------------------------------
//  Byte and line helpers (Int domain, masked)
// --------------------------------------------------

// Byte `i` of `s` as a masked Int (0..255).
fn _byte(s: Str, i: Int) -> Int {
  return (string.byte_at(s, i) as Int) & 0xFF;
}

// ASCII decimal digit.
fn _is_digit(b: Int) -> Bool {
  return b >= _MON_ZERO && b <= _MON_NINE;
}

// ASCII letter (A-Z or a-z).
fn _is_alpha(b: Int) -> Bool {
  if b >= _MON_UPPER_A && b <= _MON_UPPER_Z {
    return true;
  }
  return b >= _MON_LOWER_A && b <= _MON_LOWER_Z;
}

// ASCII letter or digit.
fn _is_alnum(b: Int) -> Bool {
  if _is_alpha(b) {
    return true;
  }
  return _is_digit(b);
}

// Space or tab.
fn _is_ws(b: Int) -> Bool {
  return b == _MON_SP || b == _MON_TAB;
}

// First non-space/tab byte at or after `i`, or `end`.
fn _skip_ws(s: Str, i: Int, end: Int) -> Int {
  var k = i;
  while k < end && _is_ws(_byte(s, k)) {
    k = k + 1;
  }
  return k;
}

// True when [start, end) is empty or only spaces/tabs.
fn _blank_at(s: Str, start: Int, end: Int) -> Bool {
  var i = start;
  while i < end {
    if !_is_ws(_byte(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Span of the physical line beginning at `pos`: [start, end) without the
// trailing CR, `next` after the LF (or n), `blank` for whitespace-only.
fn _next_line(s: Str, pos: Int) -> _Span {
  let n = s.len();
  var e = pos;
  while e < n {
    if _byte(s, e) == _MON_LF {
      break;
    }
    e = e + 1;
  }
  var cend = e;
  if cend > pos && _byte(s, cend - 1) == _MON_CR {
    cend = cend - 1;
  }
  var next = e;
  if next < n {
    next = next + 1;
  }
  return _Span{ start: pos; end: cend; next: next; blank: _blank_at(s, pos, cend) };
}

// End of a metric name starting at `from`, or -1 when there is none.
// First byte: A-Z a-z '_' ':'; later bytes: those plus 0-9.
fn _metric_name_end(s: Str, from: Int, end: Int) -> Int {
  if from >= end {
    return -1;
  }
  let b0 = _byte(s, from);
  if !_is_alpha(b0) && b0 != _MON_UNDERSCORE && b0 != _MON_COLON {
    return -1;
  }
  var i = from + 1;
  while i < end {
    let b = _byte(s, i);
    if !_is_alnum(b) && b != _MON_UNDERSCORE && b != _MON_COLON {
      break;
    }
    i = i + 1;
  }
  return i;
}

// End of a label name starting at `from`, or -1 when there is none.
// First byte: A-Z a-z '_'; later bytes: those plus 0-9.
fn _label_name_end(s: Str, from: Int, end: Int) -> Int {
  if from >= end {
    return -1;
  }
  let b0 = _byte(s, from);
  if !_is_alpha(b0) && b0 != _MON_UNDERSCORE {
    return -1;
  }
  var i = from + 1;
  while i < end {
    let b = _byte(s, i);
    if !_is_alnum(b) && b != _MON_UNDERSCORE {
      break;
    }
    i = i + 1;
  }
  return i;
}

// Relative offset of the first invalid escape in `s`, or -1. Valid escapes
// are \" \\ \n (the three the exposition formats define).
fn _escape_err(s: Str) -> Int {
  var i = 0;
  while i < s.len() {
    if _byte(s, i) == _MON_BACKSLASH {
      if i + 1 >= s.len() {
        return i;
      }
      let e = _byte(s, i + 1);
      if e != _MON_DQUOTE && e != _MON_BACKSLASH && e != _MON_LOWER_N {
        return i;
      }
      i = i + 2;
    } else {
      i = i + 1;
    }
  }
  return -1;
}

// Decode \" \\ \n in `s` (callers validate first with _escape_err).
fn _unescape(s: Str) -> Str {
  var out = "";
  var i = 0;
  var seg = 0;
  while i < s.len() {
    if _byte(s, i) == _MON_BACKSLASH {
      out = out + string.str_slice(s, seg, i);
      let e = _byte(s, i + 1);
      if e == _MON_DQUOTE {
        out = out + "\"";
      } elif e == _MON_BACKSLASH {
        out = out + "\\";
      } else {
        out = out + "\n";
      }
      i = i + 2;
      seg = i;
    } else {
      i = i + 1;
    }
  }
  out = out + string.str_slice(s, seg, s.len());
  return out;
}

// 10^p for 0 <= p <= 18 (callers guard the range).
fn _pow10(p: Int) -> Int {
  var v = 1;
  var k = 0;
  while k < p {
    v = v * 10;
    k = k + 1;
  }
  return v;
}

// Truncating division toward zero, independent of native Int semantics.
fn _trunc_div(a: Int, b: Int) -> Int {
  if b == 0 {
    return 0;
  }
  var x = a;
  var y = b;
  var neg = false;
  if x < 0 {
    neg = !neg;
    x = 0 - x;
  }
  if y < 0 {
    neg = !neg;
    y = 0 - y;
  }
  let q = x / y;
  if neg {
    return 0 - q;
  }
  return q;
}

// --------------------------------------------------
//  Value and timestamp scanning
// --------------------------------------------------

// Scan the value token [from, end). Grammar:
//   value  = "+Inf" | "-Inf" | "Inf" | "NaN" | [+-] number
//   number = digits [ "." digits* ] [ (e|E) [+-] digits ]
//          | "." digits [ (e|E) [+-] digits ]
fn _scan_value(s: Str, from: Int, end: Int) -> _VScan {
  var r = _VScan{ ok: false; kind: 0; neg: false; mant: 0; exp: 0; over: false; err: ""; pos: from; next: from };
  if from >= end {
    r.err = "bad value";
    r.pos = from;
    return r;
  }
  let tok = string.str_slice(s, from, end);
  if str_compare(tok, "+Inf") == 0 {
    r.ok = true;
    r.kind = 1;
    r.next = end;
    return r;
  }
  if str_compare(tok, "-Inf") == 0 {
    r.ok = true;
    r.kind = 2;
    r.next = end;
    return r;
  }
  if str_compare(tok, "Inf") == 0 {
    r.ok = true;
    r.kind = 1;
    r.next = end;
    return r;
  }
  if str_compare(tok, "NaN") == 0 {
    r.ok = true;
    r.kind = 3;
    r.next = end;
    return r;
  }
  var i = from;
  var neg = false;
  let b0 = _byte(s, i);
  if b0 == _MON_PLUS {
    i = i + 1;
  } elif b0 == _MON_DASH {
    neg = true;
    i = i + 1;
  }
  var total = 0;
  var lead = 0;
  var sig = 0;
  var frac = 0;
  var mant = 0;
  var over = false;
  var seen_dot = false;
  var seen_digit = false;
  while i < end {
    let b = _byte(s, i);
    if b == _MON_DOT {
      if seen_dot {
        r.err = "bad value";
        r.pos = i;
        return r;
      }
      seen_dot = true;
      i = i + 1;
    } elif _is_digit(b) {
      seen_digit = true;
      total = total + 1;
      let dv = b - 48;
      if seen_dot {
        frac = frac + 1;
      }
      if sig == 0 && dv == 0 {
        lead = lead + 1;
      } elif sig < _MON_DIGIT_CAP {
        mant = mant * 10 + dv;
        sig = sig + 1;
      } else {
        if dv != 0 {
          over = true;
        }
      }
      i = i + 1;
    } else {
      break;
    }
  }
  if !seen_digit {
    r.err = "bad value";
    r.pos = from;
    return r;
  }
  var exp = total - lead - sig - frac;
  if i < end {
    let b = _byte(s, i);
    if b == _MON_UPPER_E || b == _MON_LOWER_E {
      i = i + 1;
      var eneg = false;
      if i < end {
        let sb = _byte(s, i);
        if sb == _MON_PLUS {
          i = i + 1;
        } elif sb == _MON_DASH {
          eneg = true;
          i = i + 1;
        }
      }
      let epos = i;
      var ev = 0;
      var edig = 0;
      while i < end && _is_digit(_byte(s, i)) {
        let dv2 = _byte(s, i) - 48;
        if ev > _MON_EXP_CAP {
          ev = _MON_EXP_CAP;
        } else {
          ev = ev * 10 + dv2;
          if ev > _MON_EXP_CAP {
            ev = _MON_EXP_CAP;
            over = true;
          }
        }
        edig = edig + 1;
        i = i + 1;
      }
      if edig == 0 {
        r.err = "bad value";
        r.pos = epos;
        return r;
      }
      if eneg {
        exp = exp - ev;
      } else {
        exp = exp + ev;
      }
    }
  }
  if i != end {
    r.err = "bad value";
    r.pos = i;
    return r;
  }
  if neg {
    mant = 0 - mant;
  }
  r.ok = true;
  r.kind = 0;
  r.neg = neg;
  r.mant = mant;
  r.exp = exp;
  r.over = over;
  r.next = end;
  return r;
}

// Scan the timestamp token [from, end): an integer or decimal count of
// milliseconds with an optional sign. The fractional part is truncated
// toward zero (documented precision choice: int64 milliseconds).
fn _scan_ts(s: Str, from: Int, end: Int) -> _TsScan {
  var r = _TsScan{ ok: false; value: 0; err: ""; pos: from };
  var i = from;
  var neg = false;
  if i < end {
    let b = _byte(s, i);
    if b == _MON_PLUS {
      i = i + 1;
    } elif b == _MON_DASH {
      neg = true;
      i = i + 1;
    }
  }
  var v = 0;
  var digits = 0;
  while i < end && _is_digit(_byte(s, i)) {
    let dv = _byte(s, i) - 48;
    if v > _MON_MUL10_LIMIT {
      r.err = "timestamp out of range";
      r.pos = from;
      return r;
    }
    if v == _MON_MUL10_LIMIT && dv > 7 {
      r.err = "timestamp out of range";
      r.pos = from;
      return r;
    }
    v = v * 10 + dv;
    digits = digits + 1;
    i = i + 1;
  }
  if i < end && _byte(s, i) == _MON_DOT {
    i = i + 1;
    while i < end && _is_digit(_byte(s, i)) {
      i = i + 1;
    }
  }
  if digits == 0 {
    r.err = "bad timestamp";
    r.pos = from;
    return r;
  }
  if i != end {
    r.err = "bad timestamp";
    r.pos = i;
    return r;
  }
  if neg {
    v = 0 - v;
  }
  r.ok = true;
  r.value = v;
  return r;
}

// Scale mant * 10^exp to integer micro-units (1e-6), truncating toward zero
// and saturating at the Int limits. Special values (kind != 0) yield 0; the
// caller distinguishes them by kind.
fn _micro_of(kind: Int, mant: Int, exp: Int) -> Int {
  if kind != 0 {
    return 0;
  }
  if mant == 0 {
    return 0;
  }
  let target = exp + _MON_MICRO_SCALE;
  if target >= 0 {
    if target > 19 {
      if mant > 0 {
        return _MON_I64_MAX;
      }
      return 0 - _MON_I64_MAX;
    }
    var v = mant;
    var k = 0;
    while k < target {
      if v > _MON_MUL10_LIMIT || v < (0 - _MON_MUL10_LIMIT) {
        if v > 0 {
          return _MON_I64_MAX;
        }
        return 0 - _MON_I64_MAX;
      }
      v = v * 10;
      k = k + 1;
    }
    return v;
  }
  let p = 0 - target;
  if p > 18 {
    return 0;
  }
  return _trunc_div(mant, _pow10(p));
}

// Scalar Float64 of a parsed value: mant * 10^exp for finite values, the
// IEEE specials for kinds 1/2/3. Large exponents use a bounded loop (past
// 400 decimal steps the result is 0 or an infinity anyway).
fn _float_of(kind: Int, mant: Int, exp: Int) -> Float64 {
  if kind == 1 {
    return infinity();
  }
  if kind == 2 {
    return neg_infinity();
  }
  if kind == 3 {
    return nan();
  }
  var f = int_to_float(mant);
  if exp > 0 {
    var lim = exp;
    if lim > 400 {
      lim = 400;
    }
    var k = 0;
    while k < lim {
      f = f * 10.0;
      k = k + 1;
    }
  } elif exp < 0 {
    var lim = 0 - exp;
    if lim > 400 {
      lim = 400;
    }
    var k = 0;
    while k < lim {
      f = f / 10.0;
      k = k + 1;
    }
  }
  return f;
}

// MonValue from a successful scan and its raw span.
fn _value_of(sc: _VScan, raw: Str) -> MonValue {
  return MonValue{
    raw: raw;
    kind: sc.kind;
    neg: sc.neg;
    mant: sc.mant;
    exp: sc.exp;
    over: sc.over;
  };
}

// --------------------------------------------------
//  Label scanning
// --------------------------------------------------

// Scan one `name="value"` label starting at `from`. Leading whitespace is
// skipped; the caller decides whether more labels follow.
fn _scan_label(s: Str, from: Int, end: Int) -> _LScan {
  var r = _LScan{ ok: false; name: ""; value: ""; value_raw: ""; name_at: from; name_len: 0; value_at: from; value_len: 0; next: from; err: ""; pos: from };
  var i = _skip_ws(s, from, end);
  let ne = _label_name_end(s, i, end);
  if ne < 0 {
    r.err = "bad label name";
    r.pos = i;
    return r;
  }
  r.name = string.str_slice(s, i, ne);
  r.name_at = i;
  r.name_len = ne - i;
  i = _skip_ws(s, ne, end);
  if i >= end || _byte(s, i) != _MON_EQ {
    r.err = "bad label";
    r.pos = i;
    return r;
  }
  i = i + 1;
  i = _skip_ws(s, i, end);
  if i >= end || _byte(s, i) != _MON_DQUOTE {
    r.err = "bad label quote";
    r.pos = i;
    return r;
  }
  i = i + 1;
  r.value_at = i;
  var closed = false;
  while i < end {
    let b = _byte(s, i);
    if b == _MON_DQUOTE {
      closed = true;
      break;
    }
    if b == _MON_BACKSLASH {
      let epos = i + 1;
      if epos >= end {
        r.err = "bad escape";
        r.pos = i;
        return r;
      }
      let e2 = _byte(s, epos);
      if e2 != _MON_DQUOTE && e2 != _MON_BACKSLASH && e2 != _MON_LOWER_N {
        r.err = "bad escape";
        r.pos = i;
        return r;
      }
      i = i + 2;
    } else {
      i = i + 1;
    }
  }
  if !closed {
    r.err = "unterminated label value";
    r.pos = r.value_at;
    return r;
  }
  r.value_len = i - r.value_at;
  r.value_raw = string.str_slice(s, r.value_at, i);
  r.value = _unescape(r.value_raw);
  r.next = i + 1;
  r.ok = true;
  return r;
}

// --------------------------------------------------
//  Directive scanning
// --------------------------------------------------

// True for the eight TYPE words of the two formats.
fn _type_known(t: Str) -> Bool {
  if str_compare(t, "counter") == 0 {
    return true;
  }
  if str_compare(t, "gauge") == 0 {
    return true;
  }
  if str_compare(t, "histogram") == 0 {
    return true;
  }
  if str_compare(t, "summary") == 0 {
    return true;
  }
  if str_compare(t, "untyped") == 0 {
    return true;
  }
  if str_compare(t, "info") == 0 {
    return true;
  }
  if str_compare(t, "stateset") == 0 {
    return true;
  }
  if str_compare(t, "gaugehistogram") == 0 {
    return true;
  }
  return false;
}

// Scan a `# ...` line in [start, end) (byte at `start` is '#'). Unknown
// keywords yield a plain comment (kind 1); malformed known directives fill
// err/pos.
fn _scan_directive(s: Str, start: Int, end: Int) -> _DScan {
  var r = _DScan{ kind: 1; name: ""; name_at: start; text: ""; text_text: ""; text_at: end; err: ""; pos: start };
  var i = start + 1;
  i = _skip_ws(s, i, end);
  let ks = i;
  var ke = i;
  while ke < end && _is_alpha(_byte(s, ke)) {
    ke = ke + 1;
  }
  let kw = string.str_slice(s, ks, ke);
  if kw.len() == 0 {
    return r;
  }
  if str_compare(kw, "HELP") == 0 {
    r.kind = 2;
  } elif str_compare(kw, "TYPE") == 0 {
    r.kind = 3;
  } elif str_compare(kw, "UNIT") == 0 {
    r.kind = 4;
  } elif str_compare(kw, "EOF") == 0 {
    r.kind = 5;
  } else {
    return r;
  }
  i = ke;
  if r.kind == 5 {
    let j = _skip_ws(s, i, end);
    if j != end {
      r.err = "bad EOF";
      r.pos = j;
    }
    return r;
  }
  i = _skip_ws(s, i, end);
  let ne = _metric_name_end(s, i, end);
  if ne < 0 {
    r.err = "missing metric name";
    r.pos = i;
    return r;
  }
  r.name = string.str_slice(s, i, ne);
  r.name_at = i;
  i = ne;
  if r.kind == 2 {
    i = _skip_ws(s, i, end);
    r.text_at = i;
    let raw = string.str_slice(s, i, end);
    r.text = raw;
    let bad = _escape_err(raw);
    if bad >= 0 {
      r.err = "invalid escape in HELP";
      r.pos = i + bad;
      return r;
    }
    r.text_text = _unescape(raw);
    return r;
  }
  if r.kind == 3 {
    i = _skip_ws(s, i, end);
    let ts = i;
    while i < end && _is_alpha(_byte(s, i)) {
      i = i + 1;
    }
    let tw = string.str_slice(s, ts, i);
    if !_type_known(tw) {
      r.err = "bad type";
      r.pos = ts;
      return r;
    }
    let j = _skip_ws(s, i, end);
    if j != end {
      r.err = "bad type";
      r.pos = j;
      return r;
    }
    r.text = tw;
    r.text_at = ts;
    return r;
  }
  i = _skip_ws(s, i, end);
  let us = i;
  while i < end && !_is_ws(_byte(s, i)) {
    i = i + 1;
  }
  let uw = string.str_slice(s, us, i);
  let j = _skip_ws(s, i, end);
  if j != end {
    r.err = "bad unit";
    r.pos = j;
    return r;
  }
  if uw.len() == 0 {
    r.err = "bad unit";
    r.pos = us;
    return r;
  }
  r.text = uw;
  r.text_at = us;
  return r;
}

// --------------------------------------------------
//  Sample scanning
// --------------------------------------------------

// Empty scan struct for a sample starting at `start`.
fn _new_sscan(start: Int) -> _SScan {
  return _SScan{
    ok: false; part: 0; name: ""; name_at: start; end_at: start;
    value_at: start; value_len: 0; value_kind: 0; value_mant: 0; value_exp: 0; value_over: false; value_neg: false;
    has_ts: false; ts: 0; ts_at: start; ts_len: 0;
    ex_present: false; ex_at: start; ex_len: 0;
    ex_value_at: start; ex_value_len: 0; ex_value_kind: 0; ex_value_mant: 0; ex_value_exp: 0; ex_value_over: false;
    ex_has_ts: false; ex_ts: 0;
    labels: Vec[Str].new(); label_values: Vec[Str].new(); label_values_raw: Vec[Str].new();
    label_name_at: Vec[Int].new(); label_name_len: Vec[Int].new();
    label_value_at: Vec[Int].new(); label_value_len: Vec[Int].new();
    ex_label_names: Vec[Str].new(); ex_label_values: Vec[Str].new(); ex_label_values_raw: Vec[Str].new();
    ex_label_name_at: Vec[Int].new(); ex_label_name_len: Vec[Int].new();
    ex_label_value_at: Vec[Int].new(); ex_label_value_len: Vec[Int].new();
    err: ""; pos: start;
  };
}

// Scan one sample expression on [start, end):
//   name [ "{" label { "," label } "}" ] ws value [ ws timestamp ]
//   [ ws "#" ws "{" [ label { "," label } ] "}" ws value [ ws timestamp ] ]
fn _scan_sample(s: Str, start: Int, end: Int) -> _SScan {
  var r = _new_sscan(start);
  r.end_at = end;
  var i = start;
  let ne = _metric_name_end(s, i, end);
  if ne < 0 {
    r.err = "bad metric name";
    r.pos = i;
    return r;
  }
  r.name = string.str_slice(s, i, ne);
  r.name_at = i;
  i = ne;
  if i < end && _byte(s, i) == _MON_LBRACE {
    i = i + 1;
    i = _skip_ws(s, i, end);
    if i < end && _byte(s, i) == _MON_RBRACE {
      r.err = "empty label set";
      r.pos = i;
      return r;
    }
    var done = false;
    while !done {
      if i >= end {
        r.err = "unterminated label set";
        r.pos = i;
        return r;
      }
      let ls = _scan_label(s, i, end);
      if !ls.ok {
        r.err = ls.err;
        r.pos = ls.pos;
        return r;
      }
      var k = 0;
      var dup = false;
      while k < r.labels.len() {
        let ex: Str = r.labels[k];
        if str_compare(ex, ls.name) == 0 {
          dup = true;
        }
        k = k + 1;
      }
      if dup {
        r.err = "duplicate label";
        r.pos = ls.name_at;
        return r;
      }
      r.labels.push(ls.name);
      r.label_values.push(ls.value);
      r.label_values_raw.push(ls.value_raw);
      r.label_name_at.push(ls.name_at);
      r.label_name_len.push(ls.name_len);
      r.label_value_at.push(ls.value_at);
      r.label_value_len.push(ls.value_len);
      i = _skip_ws(s, ls.next, end);
      if i >= end {
        r.err = "unterminated label set";
        r.pos = i;
        return r;
      }
      let b = _byte(s, i);
      if b == _MON_RBRACE {
        i = i + 1;
        done = true;
      } elif b == _MON_COMMA {
        i = i + 1;
        i = _skip_ws(s, i, end);
        if i < end && _byte(s, i) == _MON_RBRACE {
          r.err = "bad label";
          r.pos = i;
          return r;
        }
      } else {
        r.err = "bad label";
        r.pos = i;
        return r;
      }
    }
    if i >= end {
      r.err = "missing value";
      r.pos = i;
      return r;
    }
    let nb = _byte(s, i);
    if nb != _MON_SP && nb != _MON_TAB {
      r.err = "missing value";
      r.pos = i;
      return r;
    }
  }
  i = _skip_ws(s, i, end);
  if i >= end {
    r.err = "missing value";
    r.pos = i;
    return r;
  }
  let vs = i;
  while i < end && !_is_ws(_byte(s, i)) {
    i = i + 1;
  }
  let vsc = _scan_value(s, vs, i);
  if !vsc.ok {
    r.err = "bad value";
    r.pos = vsc.pos;
    return r;
  }
  r.value_at = vs;
  r.value_len = i - vs;
  r.value_kind = vsc.kind;
  r.value_mant = vsc.mant;
  r.value_exp = vsc.exp;
  r.value_over = vsc.over;
  r.value_neg = vsc.neg;
  i = _skip_ws(s, i, end);
  if i < end && _byte(s, i) != _MON_HASH {
    let ts0 = i;
    while i < end && !_is_ws(_byte(s, i)) {
      i = i + 1;
    }
    let tsc = _scan_ts(s, ts0, i);
    if !tsc.ok {
      r.err = tsc.err;
      r.pos = tsc.pos;
      return r;
    }
    r.has_ts = true;
    r.ts = tsc.value;
    r.ts_at = ts0;
    r.ts_len = i - ts0;
    i = _skip_ws(s, i, end);
  }
  if i < end {
    if _byte(s, i) != _MON_HASH {
      r.err = "trailing garbage";
      r.pos = i;
      return r;
    }
    r.ex_at = i;
    i = i + 1;
    i = _skip_ws(s, i, end);
    if i >= end || _byte(s, i) != _MON_LBRACE {
      r.err = "bad exemplar";
      r.pos = i;
      return r;
    }
    i = i + 1;
    i = _skip_ws(s, i, end);
    var ex_done = false;
    if i < end && _byte(s, i) == _MON_RBRACE {
      i = i + 1;
      ex_done = true;
    }
    while !ex_done {
      if i >= end {
        r.err = "bad exemplar";
        r.pos = i;
        return r;
      }
      let ls = _scan_label(s, i, end);
      if !ls.ok {
        r.err = ls.err;
        r.pos = ls.pos;
        return r;
      }
      var k2 = 0;
      var dup2 = false;
      while k2 < r.ex_label_names.len() {
        let ex2: Str = r.ex_label_names[k2];
        if str_compare(ex2, ls.name) == 0 {
          dup2 = true;
        }
        k2 = k2 + 1;
      }
      if dup2 {
        r.err = "duplicate label";
        r.pos = ls.name_at;
        return r;
      }
      r.ex_label_names.push(ls.name);
      r.ex_label_values.push(ls.value);
      r.ex_label_values_raw.push(ls.value_raw);
      r.ex_label_name_at.push(ls.name_at);
      r.ex_label_name_len.push(ls.name_len);
      r.ex_label_value_at.push(ls.value_at);
      r.ex_label_value_len.push(ls.value_len);
      i = _skip_ws(s, ls.next, end);
      if i >= end {
        r.err = "bad exemplar";
        r.pos = i;
        return r;
      }
      let b2 = _byte(s, i);
      if b2 == _MON_RBRACE {
        i = i + 1;
        ex_done = true;
      } elif b2 == _MON_COMMA {
        i = i + 1;
        i = _skip_ws(s, i, end);
        if i < end && _byte(s, i) == _MON_RBRACE {
          r.err = "bad exemplar";
          r.pos = i;
          return r;
        }
      } else {
        r.err = "bad exemplar";
        r.pos = i;
        return r;
      }
    }
    i = _skip_ws(s, i, end);
    if i >= end {
      r.err = "bad exemplar";
      r.pos = i;
      return r;
    }
    let ev0 = i;
    while i < end && !_is_ws(_byte(s, i)) {
      i = i + 1;
    }
    let evs = _scan_value(s, ev0, i);
    if !evs.ok {
      r.err = "bad exemplar value";
      r.pos = evs.pos;
      return r;
    }
    r.ex_present = true;
    r.ex_value_at = ev0;
    r.ex_value_len = i - ev0;
    r.ex_value_kind = evs.kind;
    r.ex_value_mant = evs.mant;
    r.ex_value_exp = evs.exp;
    r.ex_value_over = evs.over;
    i = _skip_ws(s, i, end);
    if i < end {
      let ts1 = i;
      while i < end && !_is_ws(_byte(s, i)) {
        i = i + 1;
      }
      let tsc2 = _scan_ts(s, ts1, i);
      if !tsc2.ok {
        r.err = tsc2.err;
        r.pos = tsc2.pos;
        return r;
      }
      r.ex_has_ts = true;
      r.ex_ts = tsc2.value;
      i = _skip_ws(s, i, end);
    }
    if i != end {
      r.err = "trailing garbage";
      r.pos = i;
      return r;
    }
    r.ex_len = end - r.ex_at;
  }
  r.part = _syntactic_part(r.name);
  if r.part == 0 {
    var qk = 0;
    while qk < r.labels.len() {
      let qn: Str = r.labels[qk];
      if str_compare(qn, "quantile") == 0 {
        r.part = 5;
      }
      qk = qk + 1;
    }
  }
  r.ok = true;
  return r;
}

// --------------------------------------------------
//  Names, parts and families
// --------------------------------------------------

// Syntactic part of a metric name: 1 `_bucket`, 2 `_sum`, 3 `_count`,
// 4 `_created`, 0 otherwise (the bare base of every suffix is nonempty).
fn _syntactic_part(name: Str) -> Int {
  let n = name.len();
  if n > 7 {
    let t1: Str = string.str_slice(name, n - 7, n);
    if str_compare(t1, "_bucket") == 0 {
      return 1;
    }
  }
  if n > 4 {
    let t2: Str = string.str_slice(name, n - 4, n);
    if str_compare(t2, "_sum") == 0 {
      return 2;
    }
  }
  if n > 6 {
    let t3: Str = string.str_slice(name, n - 6, n);
    if str_compare(t3, "_count") == 0 {
      return 3;
    }
  }
  if n > 8 {
    let t4: Str = string.str_slice(name, n - 8, n);
    if str_compare(t4, "_created") == 0 {
      return 4;
    }
  }
  return 0;
}

// The declared base name of a part-1..4 sample ("" when the name cannot be
// a suffix, which cannot happen for names produced by _syntactic_part).
fn _base_of(name: Str, part: Int) -> Str {
  let n = name.len();
  if part == 1 && n > 7 {
    return string.str_slice(name, 0, n - 7);
  }
  if part == 2 && n > 4 {
    return string.str_slice(name, 0, n - 4);
  }
  if part == 3 && n > 6 {
    return string.str_slice(name, 0, n - 6);
  }
  if part == 4 && n > 8 {
    return string.str_slice(name, 0, n - 8);
  }
  return "";
}

// Index of a label by name in a scanned sample, or -1 (case-sensitive).
fn _sscan_label_index(ss: &_SScan, want: Str) -> Int {
  var i = 0;
  while i < ss.labels.len() {
    let nm: Str = ss.labels[i];
    if str_compare(nm, want) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Document state and application
// --------------------------------------------------

// Empty document.
fn _new_doc() -> MonDoc {
  return MonDoc{
    line_count: 0; byte_count: 0; eof_seen: false; eof_at: 0;
    err_msgs: Vec[Str].new(); err_lines: Vec[Int].new(); err_ats: Vec[Int].new();
    fam_names: Vec[Str].new(); fam_types: Vec[Str].new(); fam_has_type: Vec[Bool].new();
    fam_helps: Vec[Str].new(); fam_help_texts: Vec[Str].new(); fam_has_help: Vec[Bool].new();
    fam_units: Vec[Str].new(); fam_has_unit: Vec[Bool].new();
    fam_le_seen: Vec[Bool].new(); fam_le_micro: Vec[Int].new(); fam_le_inf: Vec[Bool].new();
    sample_fam: Vec[Int].new(); sample_name: Vec[Str].new(); sample_part: Vec[Int].new();
    sample_value_raw: Vec[Str].new(); sample_value_kind: Vec[Int].new();
    sample_value_mant: Vec[Int].new(); sample_value_exp: Vec[Int].new(); sample_value_over: Vec[Bool].new();
    sample_has_ts: Vec[Bool].new(); sample_ts: Vec[Int].new();
    sample_line: Vec[Int].new(); sample_at: Vec[Int].new(); sample_len: Vec[Int].new();
    sample_ex_count: Vec[Int].new();
    sample_le_raw: Vec[Str].new(); sample_le_micro: Vec[Int].new();
    sample_le_inf: Vec[Bool].new(); sample_has_le: Vec[Bool].new();
    sample_quantile_raw: Vec[Str].new(); sample_quantile_micro: Vec[Int].new();
    sample_has_quantile: Vec[Bool].new();
    label_sample: Vec[Int].new(); label_names: Vec[Str].new();
    label_values: Vec[Str].new(); label_values_raw: Vec[Str].new();
    label_name_at: Vec[Int].new(); label_name_len: Vec[Int].new();
    label_value_at: Vec[Int].new(); label_value_len: Vec[Int].new();
    ex_sample: Vec[Int].new(); ex_values_raw: Vec[Str].new();
    ex_value_kind: Vec[Int].new(); ex_value_mant: Vec[Int].new();
    ex_value_exp: Vec[Int].new(); ex_value_over: Vec[Bool].new();
    ex_has_ts: Vec[Bool].new(); ex_ts: Vec[Int].new();
    ex_at: Vec[Int].new(); ex_len: Vec[Int].new();
    ex_label_ex: Vec[Int].new(); ex_label_names: Vec[Str].new();
    ex_label_values: Vec[Str].new(); ex_label_values_raw: Vec[Str].new();
    ex_label_name_at: Vec[Int].new(); ex_label_name_len: Vec[Int].new();
    ex_label_value_at: Vec[Int].new(); ex_label_value_len: Vec[Int].new();
  };
}

// Empty line value.
fn _new_line() -> MonLine {
  return MonLine{
    kind: 0; name: ""; name_at: 0; part: 0;
    type_text: ""; type_at: 0; help_raw: ""; help_text: ""; help_at: 0;
    unit_text: ""; unit_at: 0;
    value_raw: ""; value_kind: 0; value_mant: 0; value_exp: 0; value_over: false;
    value_at: 0; value_len: 0;
    has_ts: false; ts: 0; ts_at: 0; ts_len: 0;
    label_names: Vec[Str].new(); label_values: Vec[Str].new(); label_values_raw: Vec[Str].new();
    label_name_at: Vec[Int].new(); label_name_len: Vec[Int].new();
    label_value_at: Vec[Int].new(); label_value_len: Vec[Int].new();
    ex_count: 0; ex_value_raw: ""; ex_value_kind: 0; ex_value_mant: 0; ex_value_exp: 0; ex_value_over: false;
    ex_has_ts: false; ex_ts: 0; ex_at: 0; ex_len: 0;
    ex_label_names: Vec[Str].new(); ex_label_values: Vec[Str].new();
    ex_label_at: Vec[Int].new(); ex_label_len: Vec[Int].new();
    at: 0; len: 0;
  };
}

// Append one error (full message, source line, absolute offset).
fn _push_err(d: &mut MonDoc, reason: Str, at: Int, line: Int) {
  d.err_msgs.push(_err_at(reason, at));
  d.err_lines.push(line);
  d.err_ats.push(at);
}

// Family index by name, or -1 (case-sensitive).
fn _fam_find(d: &MonDoc, name: Str) -> Int {
  var i = 0;
  while i < d.fam_names.len() {
    let nm: Str = d.fam_names[i];
    if str_compare(nm, name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Append an undeclared family and return its index.
fn _new_family(d: &mut MonDoc, name: Str) -> Int {
  d.fam_names.push(name);
  d.fam_types.push("");
  d.fam_has_type.push(false);
  d.fam_helps.push("");
  d.fam_help_texts.push("");
  d.fam_has_help.push(false);
  d.fam_units.push("");
  d.fam_has_unit.push(false);
  d.fam_le_seen.push(false);
  d.fam_le_micro.push(0);
  d.fam_le_inf.push(false);
  return d.fam_names.len() - 1;
}

// Family for a sample: the exact declared name first; then the declared
// base of a `_bucket`/`_sum`/`_count`/`_created` part; otherwise a new
// undeclared family under the sample name.
fn _resolve_family(d: &mut MonDoc, name: Str, part: Int) -> Int {
  let exact = _fam_find(d, name);
  if exact >= 0 {
    return exact;
  }
  if part >= 1 && part <= 4 {
    let base = _base_of(name, part);
    if base.len() > 0 {
      let bf = _fam_find(d, base);
      if bf >= 0 {
        return bf;
      }
    }
  }
  return _new_family(d, name);
}

// Apply a parsed HELP directive (a later HELP for the same name replaces).
fn _apply_help(d: &mut MonDoc, ds: &_DScan) {
  var f = _fam_find(d, ds.name);
  if f < 0 {
    f = _new_family(d, ds.name);
  }
  d.fam_helps[f] = ds.text;
  d.fam_help_texts[f] = ds.text_text;
  d.fam_has_help[f] = true;
}

// Apply a parsed TYPE directive; a second TYPE for the same name is an
// error (recorded, declaration ignored).
fn _apply_type(d: &mut MonDoc, ds: &_DScan, line: Int) {
  var f = _fam_find(d, ds.name);
  if f < 0 {
    f = _new_family(d, ds.name);
  }
  let has: Bool = d.fam_has_type[f];
  if has {
    _push_err(d, "duplicate TYPE for \"" + ds.name + "\"", ds.name_at, line);
    return;
  }
  d.fam_types[f] = ds.text;
  d.fam_has_type[f] = true;
}

// Apply a parsed UNIT directive (the last declaration wins).
fn _apply_unit(d: &mut MonDoc, ds: &_DScan) {
  var f = _fam_find(d, ds.name);
  if f < 0 {
    f = _new_family(d, ds.name);
  }
  d.fam_units[f] = ds.text;
  d.fam_has_unit[f] = true;
}

// Apply one scanned sample to the document: family resolution, histogram
// and summary conformance checks, then the mirrored parallel pushes.
// Returns false when the sample violated a rule (the error is recorded).
fn _apply_sample(d: &mut MonDoc, text: Str, ss: &_SScan, line: Int) -> Bool {
  let part = ss.part;
  let f = _resolve_family(d, ss.name, part);
  let ftype: Str = d.fam_types[f];
  let is_hist = str_compare(ftype, "histogram") == 0;
  let is_summ = str_compare(ftype, "summary") == 0;
  let le_idx = _sscan_label_index(ss, "le");
  let q_idx = _sscan_label_index(ss, "quantile");
  var le_raw = "";
  var le_micro = 0;
  var le_inf = false;
  var has_le = false;
  var q_raw = "";
  var q_micro = 0;
  var has_q = false;
  if part == 1 && le_idx >= 0 {
    let lraw: Str = ss.label_values_raw[le_idx];
    let lscan = _scan_value(lraw, 0, lraw.len());
    let lat: Int = ss.label_value_at[le_idx];
    if !lscan.ok {
      _push_err(d, "bad le", lat + lscan.pos, line);
      return false;
    }
    if lscan.kind == 2 || lscan.kind == 3 {
      _push_err(d, "bad le", lat, line);
      return false;
    }
    has_le = true;
    le_raw = lraw;
    if lscan.kind == 1 {
      le_inf = true;
    } else {
      le_micro = _micro_of(0, lscan.mant, lscan.exp);
    }
    let seen: Bool = d.fam_le_seen[f];
    if seen {
      let last_inf: Bool = d.fam_le_inf[f];
      let last_micro: Int = d.fam_le_micro[f];
      if last_inf {
        _push_err(d, "bucket le out of order", lat, line);
        return false;
      }
      if !le_inf {
        if le_micro == last_micro {
          _push_err(d, "duplicate bucket le", lat, line);
          return false;
        }
        if le_micro < last_micro {
          _push_err(d, "bucket le out of order", lat, line);
          return false;
        }
      }
    }
  } elif part == 1 && is_hist {
    _push_err(d, "bucket without le", ss.name_at, line);
    return false;
  }
  if q_idx >= 0 {
    let qraw: Str = ss.label_values_raw[q_idx];
    let qscan = _scan_value(qraw, 0, qraw.len());
    let qat: Int = ss.label_value_at[q_idx];
    if !qscan.ok || qscan.kind != 0 {
      _push_err(d, "bad quantile", qat, line);
      return false;
    }
    q_micro = _micro_of(0, qscan.mant, qscan.exp);
    if q_micro < 0 || q_micro > 1000000 {
      _push_err(d, "bad quantile", qat, line);
      return false;
    }
    has_q = true;
    q_raw = qraw;
  }
  if part == 0 && is_hist {
    _push_err(d, "unexpected histogram sample", ss.name_at, line);
    return false;
  }
  if part == 0 && is_summ {
    _push_err(d, "summary sample without quantile", ss.name_at, line);
    return false;
  }
  if has_le {
    d.fam_le_seen[f] = true;
    d.fam_le_micro[f] = le_micro;
    d.fam_le_inf[f] = le_inf;
  }
  d.sample_fam.push(f);
  d.sample_name.push(ss.name);
  d.sample_part.push(part);
  d.sample_value_raw.push(string.str_slice(text, ss.value_at, ss.value_at + ss.value_len));
  d.sample_value_kind.push(ss.value_kind);
  d.sample_value_mant.push(ss.value_mant);
  d.sample_value_exp.push(ss.value_exp);
  d.sample_value_over.push(ss.value_over);
  d.sample_has_ts.push(ss.has_ts);
  d.sample_ts.push(ss.ts);
  d.sample_line.push(line);
  d.sample_at.push(ss.name_at);
  d.sample_len.push(ss.end_at - ss.name_at);
  var exc = 0;
  if ss.ex_present {
    exc = 1;
  }
  d.sample_ex_count.push(exc);
  d.sample_le_raw.push(le_raw);
  d.sample_le_micro.push(le_micro);
  d.sample_le_inf.push(le_inf);
  d.sample_has_le.push(has_le);
  d.sample_quantile_raw.push(q_raw);
  d.sample_quantile_micro.push(q_micro);
  d.sample_has_quantile.push(has_q);
  let si = d.sample_fam.len() - 1;
  var k = 0;
  while k < ss.labels.len() {
    let nm: Str = ss.labels[k];
    let vv: Str = ss.label_values[k];
    let vr: Str = ss.label_values_raw[k];
    let na: Int = ss.label_name_at[k];
    let nl: Int = ss.label_name_len[k];
    let va: Int = ss.label_value_at[k];
    let vl: Int = ss.label_value_len[k];
    d.label_sample.push(si);
    d.label_names.push(nm);
    d.label_values.push(vv);
    d.label_values_raw.push(vr);
    d.label_name_at.push(na);
    d.label_name_len.push(nl);
    d.label_value_at.push(va);
    d.label_value_len.push(vl);
    k = k + 1;
  }
  if ss.ex_present {
    d.ex_sample.push(si);
    d.ex_values_raw.push(string.str_slice(text, ss.ex_value_at, ss.ex_value_at + ss.ex_value_len));
    d.ex_value_kind.push(ss.ex_value_kind);
    d.ex_value_mant.push(ss.ex_value_mant);
    d.ex_value_exp.push(ss.ex_value_exp);
    d.ex_value_over.push(ss.ex_value_over);
    d.ex_has_ts.push(ss.ex_has_ts);
    d.ex_ts.push(ss.ex_ts);
    d.ex_at.push(ss.ex_at);
    d.ex_len.push(ss.ex_len);
    let ei = d.ex_sample.len() - 1;
    var e = 0;
    while e < ss.ex_label_names.len() {
      let enm: Str = ss.ex_label_names[e];
      let evv: Str = ss.ex_label_values[e];
      let evr: Str = ss.ex_label_values_raw[e];
      let ena: Int = ss.ex_label_name_at[e];
      let enl: Int = ss.ex_label_name_len[e];
      let eva: Int = ss.ex_label_value_at[e];
      let evl: Int = ss.ex_label_value_len[e];
      d.ex_label_ex.push(ei);
      d.ex_label_names.push(enm);
      d.ex_label_values.push(evv);
      d.ex_label_values_raw.push(evr);
      d.ex_label_name_at.push(ena);
      d.ex_label_name_len.push(enl);
      d.ex_label_value_at.push(eva);
      d.ex_label_value_len.push(evl);
      e = e + 1;
    }
  }
  return true;
}

// --------------------------------------------------
//  Document parsing
// --------------------------------------------------

/// Parse `text` leniently: every error is collected (with its source line
/// and absolute byte offset) and every well-formed family/sample is kept.
/// Complexity: O(len(text)).
pub fn mon_parse_lenient(text: Str) -> MonDoc {
  var d = _new_doc();
  let n = text.len();
  d.byte_count = n;
  var pos = 0;
  var line_no = 1;
  var after_eof = false;
  while pos < n {
    let sp = _next_line(text, pos);
    d.line_count = d.line_count + 1;
    if !sp.blank {
      let first = _byte(text, sp.start);
      if first == _MON_HASH {
        let ds = _scan_directive(text, sp.start, sp.end);
        if after_eof {
          if ds.err.len() == 0 && ds.kind == 5 {
            _push_err(&mut d, "duplicate EOF", sp.start, line_no);
          } else {
            _push_err(&mut d, "line after EOF", sp.start, line_no);
          }
        } elif ds.err.len() > 0 {
          _push_err(&mut d, ds.err, ds.pos, line_no);
        } else {
          if ds.kind == 5 {
            if d.eof_seen {
              _push_err(&mut d, "duplicate EOF", sp.start, line_no);
            } else {
              d.eof_seen = true;
              d.eof_at = sp.start;
            }
          } elif ds.kind == 2 {
            _apply_help(&mut d, ds);
          } elif ds.kind == 3 {
            _apply_type(&mut d, ds, line_no);
          } elif ds.kind == 4 {
            _apply_unit(&mut d, ds);
          }
        }
      } else {
        if after_eof {
          _push_err(&mut d, "sample after EOF", sp.start, line_no);
        } else {
          let ss = _scan_sample(text, sp.start, sp.end);
          if ss.err.len() > 0 {
            _push_err(&mut d, ss.err, ss.pos, line_no);
          } else {
            _apply_sample(&mut d, text, ss, line_no);
          }
        }
      }
    }
    after_eof = d.eof_seen;
    pos = sp.next;
    line_no = line_no + 1;
  }
  return d;
}

/// Parse `text` strictly: Ok(MonDoc) when there is no error, else
/// Err("monitoring: <first reason> at <offset>"). Complexity: O(len(text)).
pub fn mon_parse(text: Str) -> Result[MonDoc, Str] {
  let d = mon_parse_lenient(text);
  if d.err_msgs.len() > 0 {
    let m: Str = d.err_msgs[0];
    return _err_doc(m);
  }
  return _ok_doc(d);
}

/// True when `text` parses without any error.
pub fn mon_parse_ok(text: Str) -> Bool {
  let r = mon_parse(text);
  if r.is_ok {
    return true;
  }
  return false;
}

/// Parse exactly one line (no trailing newline needed). Offsets in the
/// result and in any error are byte offsets into `line`; a line after EOF
/// cannot be detected here (that is a document concern).
/// Complexity: O(len(line)).
pub fn mon_parse_line(line: Str) -> Result[MonLine, Str] {
  let n = line.len();
  var l = _new_line();
  l.at = 0;
  l.len = n;
  let start = _skip_ws(line, 0, n);
  if start >= n {
    l.kind = 0;
    return _ok_line(l);
  }
  if _byte(line, start) == _MON_HASH {
    let ds = _scan_directive(line, start, n);
    if ds.err.len() > 0 {
      return _err_line(_err_at(ds.err, ds.pos));
    }
    l.kind = ds.kind;
    if ds.kind == 2 {
      l.name = ds.name;
      l.name_at = ds.name_at;
      l.help_raw = ds.text;
      l.help_text = ds.text_text;
      l.help_at = ds.text_at;
    } elif ds.kind == 3 {
      l.name = ds.name;
      l.name_at = ds.name_at;
      l.type_text = ds.text;
      l.type_at = ds.text_at;
    } elif ds.kind == 4 {
      l.name = ds.name;
      l.name_at = ds.name_at;
      l.unit_text = ds.text;
      l.unit_at = ds.text_at;
    }
    return _ok_line(l);
  }
  let ss = _scan_sample(line, start, n);
  if ss.err.len() > 0 {
    return _err_line(_err_at(ss.err, ss.pos));
  }
  l.kind = 6;
  l.name = ss.name;
  l.name_at = ss.name_at;
  l.part = ss.part;
  l.value_raw = string.str_slice(line, ss.value_at, ss.value_at + ss.value_len);
  l.value_kind = ss.value_kind;
  l.value_mant = ss.value_mant;
  l.value_exp = ss.value_exp;
  l.value_over = ss.value_over;
  l.value_at = ss.value_at;
  l.value_len = ss.value_len;
  l.has_ts = ss.has_ts;
  l.ts = ss.ts;
  l.ts_at = ss.ts_at;
  l.ts_len = ss.ts_len;
  l.ex_count = 0;
  if ss.ex_present {
    l.ex_count = 1;
    l.ex_value_raw = string.str_slice(line, ss.ex_value_at, ss.ex_value_at + ss.ex_value_len);
    l.ex_value_kind = ss.ex_value_kind;
    l.ex_value_mant = ss.ex_value_mant;
    l.ex_value_exp = ss.ex_value_exp;
    l.ex_value_over = ss.ex_value_over;
    l.ex_has_ts = ss.ex_has_ts;
    l.ex_ts = ss.ex_ts;
    l.ex_at = ss.ex_at;
    l.ex_len = ss.ex_len;
  }
  var k = 0;
  while k < ss.labels.len() {
    let nm: Str = ss.labels[k];
    let vv: Str = ss.label_values[k];
    let vr: Str = ss.label_values_raw[k];
    let na: Int = ss.label_name_at[k];
    let nl: Int = ss.label_name_len[k];
    let va: Int = ss.label_value_at[k];
    let vl: Int = ss.label_value_len[k];
    l.label_names.push(nm);
    l.label_values.push(vv);
    l.label_values_raw.push(vr);
    l.label_name_at.push(na);
    l.label_name_len.push(nl);
    l.label_value_at.push(va);
    l.label_value_len.push(vl);
    k = k + 1;
  }
  var e = 0;
  while e < ss.ex_label_names.len() {
    let enm: Str = ss.ex_label_names[e];
    let evv: Str = ss.ex_label_values[e];
    let ena: Int = ss.ex_label_name_at[e];
    let enl: Int = ss.ex_label_name_len[e];
    l.ex_label_names.push(enm);
    l.ex_label_values.push(evv);
    l.ex_label_at.push(ena);
    l.ex_label_len.push(enl);
    e = e + 1;
  }
  return _ok_line(l);
}

// --------------------------------------------------
//  Value API
// --------------------------------------------------

/// Parse a single value token (integer, decimal, exponent form, `+Inf`,
/// `-Inf`, `Inf` or `NaN`). Error: Err("monitoring: bad value at <offset>")
/// with the offset inside `text`. Complexity: O(len(text)).
pub fn mon_parse_value(text: Str) -> Result[MonValue, Str] {
  let sc = _scan_value(text, 0, text.len());
  if !sc.ok {
    return _err_value(_err_at(sc.err, sc.pos));
  }
  return _ok_value(_value_of(sc, text));
}

/// Parse a single value token into a scalar Float64 (IEEE specials
/// included). Error: Err("monitoring: bad value at <offset>").
pub fn mon_parse_float(text: Str) -> Result[Float64, Str] {
  let sc = _scan_value(text, 0, text.len());
  if !sc.ok {
    return _err_float(_err_at(sc.err, sc.pos));
  }
  return _ok_float(_float_of(sc.kind, sc.mant, sc.exp));
}

/// Raw text of a parsed value (byte-exact).
pub fn mon_value_raw(v: &MonValue) -> Str {
  return v.raw;
}

/// Value kind: 0 finite, 1 +Inf, 2 -Inf, 3 NaN.
pub fn mon_value_kind(v: &MonValue) -> Int {
  return v.kind;
}

/// True for a finite value.
pub fn mon_value_is_finite(v: &MonValue) -> Bool {
  return v.kind == 0;
}

/// True for a special value (+Inf, -Inf or NaN).
pub fn mon_value_is_special(v: &MonValue) -> Bool {
  return v.kind != 0;
}

/// True for NaN.
pub fn mon_value_is_nan(v: &MonValue) -> Bool {
  return v.kind == 3;
}

/// True for +Inf.
pub fn mon_value_is_pos_inf(v: &MonValue) -> Bool {
  return v.kind == 1;
}

/// True for -Inf.
pub fn mon_value_is_neg_inf(v: &MonValue) -> Bool {
  return v.kind == 2;
}

/// Finite value scaled to integer micro-units (1e-6), truncating sub-micro
/// digits toward zero and saturating at the Int limits. Special values
/// give 0.
pub fn mon_value_micro(v: &MonValue) -> Int {
  return _micro_of(v.kind, v.mant, v.exp);
}

/// Value as a scalar Float64.
pub fn mon_value_float(v: &MonValue) -> Float64 {
  return _float_of(v.kind, v.mant, v.exp);
}

/// Kind 0: finite.
pub fn mon_kind_finite() -> Int {
  return 0;
}

/// Kind 1: +Inf.
pub fn mon_kind_pos_inf() -> Int {
  return 1;
}

/// Kind 2: -Inf.
pub fn mon_kind_neg_inf() -> Int {
  return 2;
}

/// Kind 3: NaN.
pub fn mon_kind_nan() -> Int {
  return 3;
}

/// Part 0: plain sample.
pub fn mon_part_plain() -> Int {
  return 0;
}

/// Part 1: `_bucket` sample.
pub fn mon_part_bucket() -> Int {
  return 1;
}

/// Part 2: `_sum` sample.
pub fn mon_part_sum() -> Int {
  return 2;
}

/// Part 3: `_count` sample.
pub fn mon_part_count() -> Int {
  return 3;
}

/// Part 4: `_created` sample (a plain sample with no special semantics).
pub fn mon_part_created() -> Int {
  return 4;
}

/// Part 5: plain sample carrying a `quantile` label (summary quantile).
pub fn mon_part_quantile() -> Int {
  return 5;
}

/// Line kind 0: blank.
pub fn mon_line_blank() -> Int {
  return 0;
}

/// Line kind 1: comment.
pub fn mon_line_comment() -> Int {
  return 1;
}

/// Line kind 2: `# HELP`.
pub fn mon_line_help() -> Int {
  return 2;
}

/// Line kind 3: `# TYPE`.
pub fn mon_line_type() -> Int {
  return 3;
}

/// Line kind 4: `# UNIT`.
pub fn mon_line_unit() -> Int {
  return 4;
}

/// Line kind 5: `# EOF`.
pub fn mon_line_eof() -> Int {
  return 5;
}

/// Line kind 6: sample.
pub fn mon_line_sample() -> Int {
  return 6;
}

// --------------------------------------------------
//  MonLine accessors
// --------------------------------------------------

/// Line kind (see the mon_line_* constants).
pub fn mon_line_get_kind(l: &MonLine) -> Int {
  return l.kind;
}

/// Declared or metric name of the line ("" for blank/comment/EOF).
pub fn mon_line_get_name(l: &MonLine) -> Str {
  return l.name;
}

/// Byte offset of the name in the line.
pub fn mon_line_get_name_at(l: &MonLine) -> Int {
  return l.name_at;
}

/// Syntactic part of a sample name (see the mon_part_* constants).
pub fn mon_line_get_part(l: &MonLine) -> Int {
  return l.part;
}

/// TYPE word of a `# TYPE` line.
pub fn mon_line_get_type(l: &MonLine) -> Str {
  return l.type_text;
}

/// Byte offset of the TYPE word.
pub fn mon_line_get_type_at(l: &MonLine) -> Int {
  return l.type_at;
}

/// Raw (still escaped) HELP text.
pub fn mon_line_get_help_raw(l: &MonLine) -> Str {
  return l.help_raw;
}

/// Unescaped HELP text.
pub fn mon_line_get_help_text(l: &MonLine) -> Str {
  return l.help_text;
}

/// Byte offset of the HELP text.
pub fn mon_line_get_help_at(l: &MonLine) -> Int {
  return l.help_at;
}

/// UNIT text.
pub fn mon_line_get_unit(l: &MonLine) -> Str {
  return l.unit_text;
}

/// Byte offset of the UNIT text.
pub fn mon_line_get_unit_at(l: &MonLine) -> Int {
  return l.unit_at;
}

/// Raw text of the sample value.
pub fn mon_line_get_value_raw(l: &MonLine) -> Str {
  return l.value_raw;
}

/// Sample value kind.
pub fn mon_line_get_value_kind(l: &MonLine) -> Int {
  return l.value_kind;
}

/// Sample value in micro-units (see mon_value_micro).
pub fn mon_line_get_value_micro(l: &MonLine) -> Int {
  return _micro_of(l.value_kind, l.value_mant, l.value_exp);
}

/// Sample value as a scalar Float64.
pub fn mon_line_get_value_float(l: &MonLine) -> Float64 {
  return _float_of(l.value_kind, l.value_mant, l.value_exp);
}

/// Byte offset of the sample value.
pub fn mon_line_get_value_at(l: &MonLine) -> Int {
  return l.value_at;
}

/// Byte length of the sample value.
pub fn mon_line_get_value_len(l: &MonLine) -> Int {
  return l.value_len;
}

/// True when the sample line carried a timestamp.
pub fn mon_line_get_has_timestamp(l: &MonLine) -> Bool {
  return l.has_ts;
}

/// Sample timestamp in milliseconds.
pub fn mon_line_get_timestamp(l: &MonLine) -> Int {
  return l.ts;
}

/// Byte offset of the sample timestamp.
pub fn mon_line_get_ts_at(l: &MonLine) -> Int {
  return l.ts_at;
}

/// Number of labels on the sample.
pub fn mon_line_get_label_count(l: &MonLine) -> Int {
  return l.label_names.len();
}

/// Label name at position `k` ("" out of range).
pub fn mon_line_get_label_name(l: &MonLine, k: Int) -> Str {
  if k < 0 || k >= l.label_names.len() {
    return "";
  }
  let s: Str = l.label_names[k];
  return s;
}

/// Unescaped label value at position `k`.
pub fn mon_line_get_label_value(l: &MonLine, k: Int) -> Str {
  if k < 0 || k >= l.label_values.len() {
    return "";
  }
  let s: Str = l.label_values[k];
  return s;
}

/// Raw (still escaped) label value at position `k`.
pub fn mon_line_get_label_value_raw(l: &MonLine, k: Int) -> Str {
  if k < 0 || k >= l.label_values_raw.len() {
    return "";
  }
  let s: Str = l.label_values_raw[k];
  return s;
}

/// Byte offset of the label name at position `k`.
pub fn mon_line_get_label_name_at(l: &MonLine, k: Int) -> Int {
  if k < 0 || k >= l.label_name_at.len() {
    return -1;
  }
  let v: Int = l.label_name_at[k];
  return v;
}

/// Byte offset of the escaped label value at position `k`.
pub fn mon_line_get_label_value_at(l: &MonLine, k: Int) -> Int {
  if k < 0 || k >= l.label_value_at.len() {
    return -1;
  }
  let v: Int = l.label_value_at[k];
  return v;
}

/// Case-sensitive label lookup: the position of the label, or -1.
pub fn mon_line_get_label_index(l: &MonLine, name: Str) -> Int {
  var i = 0;
  while i < l.label_names.len() {
    let nm: Str = l.label_names[i];
    if str_compare(nm, name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Case-sensitive label lookup: the unescaped value or "".
pub fn mon_line_get_label_lookup(l: &MonLine, name: Str) -> Str {
  let i = mon_line_get_label_index(l, name);
  if i < 0 {
    return "";
  }
  let s: Str = l.label_values[i];
  return s;
}

/// Number of exemplars on the line (0 or 1).
pub fn mon_line_get_exemplar_count(l: &MonLine) -> Int {
  return l.ex_count;
}

/// Number of labels on the line's exemplar.
pub fn mon_line_get_exemplar_label_count(l: &MonLine) -> Int {
  return l.ex_label_names.len();
}

/// Exemplar label name at position `k`.
pub fn mon_line_get_exemplar_label_name(l: &MonLine, k: Int) -> Str {
  if k < 0 || k >= l.ex_label_names.len() {
    return "";
  }
  let s: Str = l.ex_label_names[k];
  return s;
}

/// Exemplar label value (unescaped) at position `k`.
pub fn mon_line_get_exemplar_label_value(l: &MonLine, k: Int) -> Str {
  if k < 0 || k >= l.ex_label_values.len() {
    return "";
  }
  let s: Str = l.ex_label_values[k];
  return s;
}

/// Raw text of the exemplar value.
pub fn mon_line_get_exemplar_value_raw(l: &MonLine) -> Str {
  return l.ex_value_raw;
}

/// Exemplar value kind.
pub fn mon_line_get_exemplar_value_kind(l: &MonLine) -> Int {
  return l.ex_value_kind;
}

/// Exemplar value in micro-units.
pub fn mon_line_get_exemplar_value_micro(l: &MonLine) -> Int {
  return _micro_of(l.ex_value_kind, l.ex_value_mant, l.ex_value_exp);
}

/// Exemplar value as a scalar Float64.
pub fn mon_line_get_exemplar_value_float(l: &MonLine) -> Float64 {
  return _float_of(l.ex_value_kind, l.ex_value_mant, l.ex_value_exp);
}

/// True when the exemplar carried a timestamp.
pub fn mon_line_get_exemplar_has_timestamp(l: &MonLine) -> Bool {
  return l.ex_has_ts;
}

/// Exemplar timestamp in milliseconds.
pub fn mon_line_get_exemplar_timestamp(l: &MonLine) -> Int {
  return l.ex_ts;
}

/// Byte offset of the exemplar `#`.
pub fn mon_line_get_exemplar_at(l: &MonLine) -> Int {
  return l.ex_at;
}

/// Byte length of the exemplar text.
pub fn mon_line_get_exemplar_len(l: &MonLine) -> Int {
  return l.ex_len;
}

/// Reserved base offset of the line (0 for mon_parse_line).
pub fn mon_line_get_at(l: &MonLine) -> Int {
  return l.at;
}

/// Byte length of the line text.
pub fn mon_line_get_len(l: &MonLine) -> Int {
  return l.len;
}

// --------------------------------------------------
//  MonDoc accessors
// --------------------------------------------------

/// Number of physical lines walked (a trailing line break adds no line).
pub fn mon_doc_line_count(d: &MonDoc) -> Int {
  return d.line_count;
}

/// Number of input bytes consumed (always the input length).
pub fn mon_doc_byte_count(d: &MonDoc) -> Int {
  return d.byte_count;
}

/// True when an `# EOF` marker was seen.
pub fn mon_doc_eof_seen(d: &MonDoc) -> Bool {
  return d.eof_seen;
}

/// Byte offset of the `# EOF` marker (0 when absent).
pub fn mon_doc_eof_at(d: &MonDoc) -> Int {
  return d.eof_at;
}

/// Number of collected errors (0 for a strictly valid document).
pub fn mon_doc_error_count(d: &MonDoc) -> Int {
  return d.err_msgs.len();
}

/// Error message `k` (full "monitoring: ... at ..." text).
pub fn mon_doc_error_msg(d: &MonDoc, k: Int) -> Str {
  if k < 0 || k >= d.err_msgs.len() {
    return "";
  }
  let s: Str = d.err_msgs[k];
  return s;
}

/// Source line (1-based) of error `k`.
pub fn mon_doc_error_line(d: &MonDoc, k: Int) -> Int {
  if k < 0 || k >= d.err_lines.len() {
    return -1;
  }
  let v: Int = d.err_lines[k];
  return v;
}

/// Absolute byte offset of error `k`.
pub fn mon_doc_error_at(d: &MonDoc, k: Int) -> Int {
  if k < 0 || k >= d.err_ats.len() {
    return -1;
  }
  let v: Int = d.err_ats[k];
  return v;
}

/// Number of families (declared and auto-created).
pub fn mon_doc_family_count(d: &MonDoc) -> Int {
  return d.fam_names.len();
}

/// Family index by name, or -1 (case-sensitive).
pub fn mon_doc_family_index(d: &MonDoc, name: Str) -> Int {
  return _fam_find(d, name);
}

/// Family name at `f`.
pub fn mon_doc_family_name(d: &MonDoc, f: Int) -> Str {
  if f < 0 || f >= d.fam_names.len() {
    return "";
  }
  let s: Str = d.fam_names[f];
  return s;
}

/// Declared TYPE of family `f` ("" when there was no `# TYPE`).
pub fn mon_doc_family_type(d: &MonDoc, f: Int) -> Str {
  if f < 0 || f >= d.fam_types.len() {
    return "";
  }
  let s: Str = d.fam_types[f];
  return s;
}

/// True when family `f` has a declared TYPE.
pub fn mon_doc_family_has_type(d: &MonDoc, f: Int) -> Bool {
  if f < 0 || f >= d.fam_has_type.len() {
    return false;
  }
  let b: Bool = d.fam_has_type[f];
  return b;
}

/// Raw (still escaped) HELP text of family `f`.
pub fn mon_doc_family_help(d: &MonDoc, f: Int) -> Str {
  if f < 0 || f >= d.fam_helps.len() {
    return "";
  }
  let s: Str = d.fam_helps[f];
  return s;
}

/// Unescaped HELP text of family `f`.
pub fn mon_doc_family_help_text(d: &MonDoc, f: Int) -> Str {
  if f < 0 || f >= d.fam_help_texts.len() {
    return "";
  }
  let s: Str = d.fam_help_texts[f];
  return s;
}

/// True when family `f` has HELP text.
pub fn mon_doc_family_has_help(d: &MonDoc, f: Int) -> Bool {
  if f < 0 || f >= d.fam_has_help.len() {
    return false;
  }
  let b: Bool = d.fam_has_help[f];
  return b;
}

/// UNIT of family `f` ("" when there was no `# UNIT`).
pub fn mon_doc_family_unit(d: &MonDoc, f: Int) -> Str {
  if f < 0 || f >= d.fam_units.len() {
    return "";
  }
  let s: Str = d.fam_units[f];
  return s;
}

/// True when family `f` has a UNIT.
pub fn mon_doc_family_has_unit(d: &MonDoc, f: Int) -> Bool {
  if f < 0 || f >= d.fam_has_unit.len() {
    return false;
  }
  let b: Bool = d.fam_has_unit[f];
  return b;
}

/// Number of samples attached to family `f`.
pub fn mon_doc_family_sample_count(d: &MonDoc, f: Int) -> Int {
  var count = 0;
  var i = 0;
  while i < d.sample_fam.len() {
    let s: Int = d.sample_fam[i];
    if s == f {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

/// Global index of the `k`-th sample of family `f`, or -1.
pub fn mon_doc_family_sample_at(d: &MonDoc, f: Int, k: Int) -> Int {
  var seen = 0;
  var i = 0;
  while i < d.sample_fam.len() {
    let s: Int = d.sample_fam[i];
    if s == f {
      if seen == k {
        return i;
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return -1;
}

/// Number of samples in the document.
pub fn mon_doc_sample_count(d: &MonDoc) -> Int {
  return d.sample_fam.len();
}

/// Sample name at `i`.
pub fn mon_doc_sample_name(d: &MonDoc, i: Int) -> Str {
  if i < 0 || i >= d.sample_name.len() {
    return "";
  }
  let s: Str = d.sample_name[i];
  return s;
}

/// Family index of sample `i`.
pub fn mon_doc_sample_family(d: &MonDoc, i: Int) -> Int {
  if i < 0 || i >= d.sample_fam.len() {
    return -1;
  }
  let v: Int = d.sample_fam[i];
  return v;
}

/// Part of sample `i` (see the mon_part_* constants).
pub fn mon_doc_sample_part(d: &MonDoc, i: Int) -> Int {
  if i < 0 || i >= d.sample_part.len() {
    return -1;
  }
  let v: Int = d.sample_part[i];
  return v;
}

/// Raw text of the value of sample `i`.
pub fn mon_doc_sample_value_raw(d: &MonDoc, i: Int) -> Str {
  if i < 0 || i >= d.sample_value_raw.len() {
    return "";
  }
  let s: Str = d.sample_value_raw[i];
  return s;
}

/// Value kind of sample `i`.
pub fn mon_doc_sample_value_kind(d: &MonDoc, i: Int) -> Int {
  if i < 0 || i >= d.sample_value_kind.len() {
    return -1;
  }
  let v: Int = d.sample_value_kind[i];
  return v;
}

/// Value of sample `i` in micro-units (special values give 0).
pub fn mon_doc_sample_value_micro(d: &MonDoc, i: Int) -> Int {
  if i < 0 || i >= d.sample_value_kind.len() {
    return 0;
  }
  let k: Int = d.sample_value_kind[i];
  let m: Int = d.sample_value_mant[i];
  let e: Int = d.sample_value_exp[i];
  return _micro_of(k, m, e);
}

/// Value of sample `i` as a scalar Float64.
pub fn mon_doc_sample_value_float(d: &MonDoc, i: Int) -> Float64 {
  if i < 0 || i >= d.sample_value_kind.len() {
    return 0.0;
  }
  let k: Int = d.sample_value_kind[i];
  let m: Int = d.sample_value_mant[i];
  let e: Int = d.sample_value_exp[i];
  return _float_of(k, m, e);
}

/// True when sample `i` carried a timestamp.
pub fn mon_doc_sample_has_timestamp(d: &MonDoc, i: Int) -> Bool {
  if i < 0 || i >= d.sample_has_ts.len() {
    return false;
  }
  let b: Bool = d.sample_has_ts[i];
  return b;
}

/// Timestamp of sample `i` in milliseconds.
pub fn mon_doc_sample_timestamp(d: &MonDoc, i: Int) -> Int {
  if i < 0 || i >= d.sample_ts.len() {
    return 0;
  }
  let v: Int = d.sample_ts[i];
  return v;
}

/// 1-based source line of sample `i`.
pub fn mon_doc_sample_line(d: &MonDoc, i: Int) -> Int {
  if i < 0 || i >= d.sample_line.len() {
    return -1;
  }
  let v: Int = d.sample_line[i];
  return v;
}

/// Absolute byte offset of the name of sample `i`.
pub fn mon_doc_sample_at(d: &MonDoc, i: Int) -> Int {
  if i < 0 || i >= d.sample_at.len() {
    return -1;
  }
  let v: Int = d.sample_at[i];
  return v;
}

/// Byte length of the sample expression (name through line end).
pub fn mon_doc_sample_len(d: &MonDoc, i: Int) -> Int {
  if i < 0 || i >= d.sample_len.len() {
    return 0;
  }
  let v: Int = d.sample_len[i];
  return v;
}

/// Number of exemplars attached to sample `i` (0 or 1).
pub fn mon_doc_sample_exemplar_count(d: &MonDoc, i: Int) -> Int {
  if i < 0 || i >= d.sample_ex_count.len() {
    return 0;
  }
  let v: Int = d.sample_ex_count[i];
  return v;
}

/// True when sample `i` has a parsed `le` boundary.
pub fn mon_doc_sample_has_le(d: &MonDoc, i: Int) -> Bool {
  if i < 0 || i >= d.sample_has_le.len() {
    return false;
  }
  let b: Bool = d.sample_has_le[i];
  return b;
}

/// Raw `le` boundary text of sample `i`.
pub fn mon_doc_sample_le_raw(d: &MonDoc, i: Int) -> Str {
  if i < 0 || i >= d.sample_le_raw.len() {
    return "";
  }
  let s: Str = d.sample_le_raw[i];
  return s;
}

/// `le` boundary of sample `i` in micro-units.
pub fn mon_doc_sample_le_micro(d: &MonDoc, i: Int) -> Int {
  if i < 0 || i >= d.sample_le_micro.len() {
    return 0;
  }
  let v: Int = d.sample_le_micro[i];
  return v;
}

/// True when the `le` boundary of sample `i` is `+Inf`.
pub fn mon_doc_sample_le_inf(d: &MonDoc, i: Int) -> Bool {
  if i < 0 || i >= d.sample_le_inf.len() {
    return false;
  }
  let b: Bool = d.sample_le_inf[i];
  return b;
}

/// True when sample `i` has a parsed quantile.
pub fn mon_doc_sample_has_quantile(d: &MonDoc, i: Int) -> Bool {
  if i < 0 || i >= d.sample_has_quantile.len() {
    return false;
  }
  let b: Bool = d.sample_has_quantile[i];
  return b;
}

/// Raw quantile text of sample `i`.
pub fn mon_doc_sample_quantile_raw(d: &MonDoc, i: Int) -> Str {
  if i < 0 || i >= d.sample_quantile_raw.len() {
    return "";
  }
  let s: Str = d.sample_quantile_raw[i];
  return s;
}

/// Quantile of sample `i` in micro-units (1e-6 of the 0..1 range).
pub fn mon_doc_sample_quantile_micro(d: &MonDoc, i: Int) -> Int {
  if i < 0 || i >= d.sample_quantile_micro.len() {
    return 0;
  }
  let v: Int = d.sample_quantile_micro[i];
  return v;
}

/// Number of labels on sample `i`.
pub fn mon_doc_sample_label_count(d: &MonDoc, i: Int) -> Int {
  var count = 0;
  var k = 0;
  while k < d.label_sample.len() {
    let s: Int = d.label_sample[k];
    if s == i {
      count = count + 1;
    }
    k = k + 1;
  }
  return count;
}

// Global label index of the `k`-th label of sample `i`, or -1.
fn _label_at(d: &MonDoc, i: Int, k: Int) -> Int {
  var seen = 0;
  var j = 0;
  while j < d.label_sample.len() {
    let s: Int = d.label_sample[j];
    if s == i {
      if seen == k {
        return j;
      }
      seen = seen + 1;
    }
    j = j + 1;
  }
  return -1;
}

/// Label name at position `k` of sample `i` ("" out of range).
pub fn mon_doc_sample_label_name(d: &MonDoc, i: Int, k: Int) -> Str {
  let j = _label_at(d, i, k);
  if j < 0 {
    return "";
  }
  let s: Str = d.label_names[j];
  return s;
}

/// Unescaped label value at position `k` of sample `i`.
pub fn mon_doc_sample_label_value(d: &MonDoc, i: Int, k: Int) -> Str {
  let j = _label_at(d, i, k);
  if j < 0 {
    return "";
  }
  let s: Str = d.label_values[j];
  return s;
}

/// Raw (still escaped) label value at position `k` of sample `i`.
pub fn mon_doc_sample_label_value_raw(d: &MonDoc, i: Int, k: Int) -> Str {
  let j = _label_at(d, i, k);
  if j < 0 {
    return "";
  }
  let s: Str = d.label_values_raw[j];
  return s;
}

/// Absolute byte offset of the label name at position `k` of sample `i`.
pub fn mon_doc_sample_label_name_at(d: &MonDoc, i: Int, k: Int) -> Int {
  let j = _label_at(d, i, k);
  if j < 0 {
    return -1;
  }
  let v: Int = d.label_name_at[j];
  return v;
}

/// Absolute byte offset of the escaped label value at position `k`.
pub fn mon_doc_sample_label_value_at(d: &MonDoc, i: Int, k: Int) -> Int {
  let j = _label_at(d, i, k);
  if j < 0 {
    return -1;
  }
  let v: Int = d.label_value_at[j];
  return v;
}

/// Case-sensitive label lookup on sample `i`: the position, or -1.
pub fn mon_doc_sample_label_index(d: &MonDoc, i: Int, name: Str) -> Int {
  var seen = 0;
  var j = 0;
  while j < d.label_sample.len() {
    let s: Int = d.label_sample[j];
    if s == i {
      let nm: Str = d.label_names[j];
      if str_compare(nm, name) == 0 {
        return seen;
      }
      seen = seen + 1;
    }
    j = j + 1;
  }
  return -1;
}

/// Case-sensitive label lookup on sample `i`: the value or "".
pub fn mon_doc_sample_label_lookup(d: &MonDoc, i: Int, name: Str) -> Str {
  let k = mon_doc_sample_label_index(d, i, name);
  if k < 0 {
    return "";
  }
  return mon_doc_sample_label_value(d, i, k);
}

/// Number of labels on exemplar `k` of sample `i`.
pub fn mon_doc_exemplar_label_count(d: &MonDoc, i: Int, k: Int) -> Int {
  let ei = _ex_index(d, i, k);
  if ei < 0 {
    return 0;
  }
  var count = 0;
  var j = 0;
  while j < d.ex_label_ex.len() {
    let s: Int = d.ex_label_ex[j];
    if s == ei {
      count = count + 1;
    }
    j = j + 1;
  }
  return count;
}

// Global index of exemplar `k` of sample `i`, or -1.
fn _ex_index(d: &MonDoc, i: Int, k: Int) -> Int {
  var seen = 0;
  var j = 0;
  while j < d.ex_sample.len() {
    let s: Int = d.ex_sample[j];
    if s == i {
      if seen == k {
        return j;
      }
      seen = seen + 1;
    }
    j = j + 1;
  }
  return -1;
}

// Global index of the `p`-th label of exemplar `ei`, or -1.
fn _ex_label_at(d: &MonDoc, ei: Int, p: Int) -> Int {
  var seen = 0;
  var j = 0;
  while j < d.ex_label_ex.len() {
    let s: Int = d.ex_label_ex[j];
    if s == ei {
      if seen == p {
        return j;
      }
      seen = seen + 1;
    }
    j = j + 1;
  }
  return -1;
}

/// Exemplar label name at position `p` of exemplar `k` of sample `i`.
pub fn mon_doc_exemplar_label_name(d: &MonDoc, i: Int, k: Int, p: Int) -> Str {
  let ei = _ex_index(d, i, k);
  if ei < 0 {
    return "";
  }
  let j = _ex_label_at(d, ei, p);
  if j < 0 {
    return "";
  }
  let s: Str = d.ex_label_names[j];
  return s;
}

/// Exemplar label value (unescaped) at position `p`.
pub fn mon_doc_exemplar_label_value(d: &MonDoc, i: Int, k: Int, p: Int) -> Str {
  let ei = _ex_index(d, i, k);
  if ei < 0 {
    return "";
  }
  let j = _ex_label_at(d, ei, p);
  if j < 0 {
    return "";
  }
  let s: Str = d.ex_label_values[j];
  return s;
}

/// Raw text of the value of exemplar `k` of sample `i`.
pub fn mon_doc_exemplar_value_raw(d: &MonDoc, i: Int, k: Int) -> Str {
  let ei = _ex_index(d, i, k);
  if ei < 0 {
    return "";
  }
  let s: Str = d.ex_values_raw[ei];
  return s;
}

/// Value kind of exemplar `k` of sample `i`.
pub fn mon_doc_exemplar_value_kind(d: &MonDoc, i: Int, k: Int) -> Int {
  let ei = _ex_index(d, i, k);
  if ei < 0 {
    return -1;
  }
  let v: Int = d.ex_value_kind[ei];
  return v;
}

/// Value of exemplar `k` of sample `i` in micro-units.
pub fn mon_doc_exemplar_value_micro(d: &MonDoc, i: Int, k: Int) -> Int {
  let ei = _ex_index(d, i, k);
  if ei < 0 {
    return 0;
  }
  let kk: Int = d.ex_value_kind[ei];
  let m: Int = d.ex_value_mant[ei];
  let e: Int = d.ex_value_exp[ei];
  return _micro_of(kk, m, e);
}

/// Value of exemplar `k` of sample `i` as a scalar Float64.
pub fn mon_doc_exemplar_value_float(d: &MonDoc, i: Int, k: Int) -> Float64 {
  let ei = _ex_index(d, i, k);
  if ei < 0 {
    return 0.0;
  }
  let kk: Int = d.ex_value_kind[ei];
  let m: Int = d.ex_value_mant[ei];
  let e: Int = d.ex_value_exp[ei];
  return _float_of(kk, m, e);
}

/// True when exemplar `k` of sample `i` carried a timestamp.
pub fn mon_doc_exemplar_has_timestamp(d: &MonDoc, i: Int, k: Int) -> Bool {
  let ei = _ex_index(d, i, k);
  if ei < 0 {
    return false;
  }
  let b: Bool = d.ex_has_ts[ei];
  return b;
}

/// Timestamp of exemplar `k` of sample `i` in milliseconds.
pub fn mon_doc_exemplar_timestamp(d: &MonDoc, i: Int, k: Int) -> Int {
  let ei = _ex_index(d, i, k);
  if ei < 0 {
    return 0;
  }
  let v: Int = d.ex_ts[ei];
  return v;
}

/// Absolute byte offset of the `#` of exemplar `k` of sample `i`.
pub fn mon_doc_exemplar_at(d: &MonDoc, i: Int, k: Int) -> Int {
  let ei = _ex_index(d, i, k);
  if ei < 0 {
    return -1;
  }
  let v: Int = d.ex_at[ei];
  return v;
}

/// Byte length of exemplar `k` of sample `i`.
pub fn mon_doc_exemplar_len(d: &MonDoc, i: Int, k: Int) -> Int {
  let ei = _ex_index(d, i, k);
  if ei < 0 {
    return 0;
  }
  let v: Int = d.ex_len[ei];
  return v;
}

// --------------------------------------------------
//  Version
// --------------------------------------------------

/// Version of this package's parser.
pub fn mon_version() -> Str {
  return "0.1.0";
}

