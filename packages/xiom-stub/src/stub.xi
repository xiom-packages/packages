// XIOM -- xiom.stub: ordered programmable test-double stubs
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure XIOM, no FFI, no runtime hooks.
//
// A stub is a plain value. Declare ordered expectations -- a method name, an
// Int argument tuple, a cardinality (exactly / at least / at most), a canned
// return value and an optional failure message -- then invoke the stub from
// the code under test. Every invocation is appended to a numbered call log;
// calls bind to the first expectation (declaration order) whose method and
// argument tuple match and which still accepts a call. Verification produces
// structured violation reports: missing calls, unexpected calls and calls
// that overtook an unsatisfied earlier expectation (out of order).
//
// Matching is explicit: nothing intercepts real functions, so the double is
// deterministic and free of FFI.
//
// Language notes (XIOM v0.62.1): free functions only; flat parallel Vecs
// instead of Vec[StructType]; Str equality goes through
// xiom.string.compare.str_compare; every element read is bound to a typed
// local first; Ok/Err are constructed only in the leaf helpers
// _ok_int/_err_int; &mut parameters require an explicit &mut at call sites.

module xiom.stub

use xiom.string;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Cardinality modes
// --------------------------------------------------

const _ST_EXACTLY: Int = 0;
const _ST_AT_LEAST: Int = 1;
const _ST_AT_MOST: Int = 2;

// Human-readable form of a mode, for messages.
fn _mode_word(mode: Int) -> Str {
  if mode == _ST_AT_LEAST {
    return "at least";
  }
  if mode == _ST_AT_MOST {
    return "at most";
  }
  return "exactly";
}

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One stub: ordered expectations plus the numbered call log and the
/// verification violations detected while calls were recorded.
/// Expectation arrays are index-aligned in declaration order; a call records
/// its method, its argument tuple (flat, with per-call offset/length), the
/// matched expectation index (-1 when unmatched), and the sequence number is
/// its zero-based position in the log. Violation triples are appended only
/// when a violation is detected. modes are 0 = exactly, 1 = at least,
/// 2 = at most; fail_set is 0/1; lenient is 0 (strict) or 1.
pub type Stub = {
  methods: Vec[Str];
  modes: Vec[Int];
  expected: Vec[Int];
  actual: Vec[Int];
  returns: Vec[Int];
  fail_set: Vec[Int];
  fail_msgs: Vec[Str];
  arg_off: Vec[Int];
  arg_len: Vec[Int];
  arg_data: Vec[Int];
  call_methods: Vec[Str];
  call_off: Vec[Int];
  call_len: Vec[Int];
  call_data: Vec[Int];
  call_match: Vec[Int];
  ooo_seq: Vec[Int];
  ooo_taken: Vec[Int];
  ooo_matched: Vec[Int];
  extra_seq: Vec[Int];
  extra_kind: Vec[Int];
  extra_expect: Vec[Int];
  lenient: Int;
}

// --------------------------------------------------
//  Shape guards and cardinality counters
// --------------------------------------------------

// Number of index-aligned expectations (clamped to the shortest array).
fn _expect_count(m: &Stub) -> Int {
  var n = m.methods.len();
  if m.modes.len() < n { n = m.modes.len(); }
  if m.expected.len() < n { n = m.expected.len(); }
  if m.actual.len() < n { n = m.actual.len(); }
  if m.returns.len() < n { n = m.returns.len(); }
  if m.fail_set.len() < n { n = m.fail_set.len(); }
  if m.fail_msgs.len() < n { n = m.fail_msgs.len(); }
  if m.arg_off.len() < n { n = m.arg_off.len(); }
  if m.arg_len.len() < n { n = m.arg_len.len(); }
  return n;
}

// Number of recorded calls (clamped to the shortest call array).
fn _call_count(m: &Stub) -> Int {
  var n = m.call_methods.len();
  if m.call_off.len() < n { n = m.call_off.len(); }
  if m.call_len.len() < n { n = m.call_len.len(); }
  if m.call_match.len() < n { n = m.call_match.len(); }
  return n;
}

// Number of recorded unmatched calls (clamped).
fn _extra_count(m: &Stub) -> Int {
  var n = m.extra_seq.len();
  if m.extra_kind.len() < n { n = m.extra_kind.len(); }
  if m.extra_expect.len() < n { n = m.extra_expect.len(); }
  return n;
}

// Number of recorded out-of-order events (clamped).
fn _ooo_count(m: &Stub) -> Int {
  var n = m.ooo_seq.len();
  if m.ooo_taken.len() < n { n = m.ooo_taken.len(); }
  if m.ooo_matched.len() < n { n = m.ooo_matched.len(); }
  return n;
}

// --------------------------------------------------
//  Argument tuples
// --------------------------------------------------

// k-th stored argument of expectation `i`; 0 when out of range.
fn _arg_at(m: &Stub, i: Int, k: Int) -> Int {
  if i < 0 || i >= _expect_count(m) { return 0; }
  let n: Int = m.arg_len[i];
  if k < 0 || k >= n { return 0; }
  let off: Int = m.arg_off[i];
  if off < 0 || off + k >= m.arg_data.len() { return 0; }
  let v: Int = m.arg_data[off + k];
  return v;
}

// k-th stored argument of call `i`; 0 when out of range.
fn _call_arg_at(m: &Stub, i: Int, k: Int) -> Int {
  if i < 0 || i >= _call_count(m) { return 0; }
  let n: Int = m.call_len[i];
  if k < 0 || k >= n { return 0; }
  let off: Int = m.call_off[i];
  if off < 0 || off + k >= m.call_data.len() { return 0; }
  let v: Int = m.call_data[off + k];
  return v;
}

// Rendering of an argument tuple: "" for arity 0, else "(a, b, ...)".
fn _args_desc(n: Int, a0: Int, a1: Int, a2: Int) -> Str {
  if n == 0 { return ""; }
  if n == 1 { return "(" + int_to_string(a0) + ")"; }
  if n == 2 { return "(" + int_to_string(a0) + ", " + int_to_string(a1) + ")"; }
  return "(" + int_to_string(a0) + ", " + int_to_string(a1) + ", " + int_to_string(a2) + ")";
}

// Argument tuple of expectation `i`, rendered.
fn _expect_args_desc(m: &Stub, i: Int) -> Str {
  let n: Int = m.arg_len[i];
  return _args_desc(n, _arg_at(m, i, 0), _arg_at(m, i, 1), _arg_at(m, i, 2));
}

// Argument tuple of call `i`, rendered.
fn _call_args_desc(m: &Stub, i: Int) -> Str {
  let n: Int = m.call_len[i];
  return _args_desc(n, _call_arg_at(m, i, 0), _call_arg_at(m, i, 1), _call_arg_at(m, i, 2));
}

// --------------------------------------------------
//  Matching internals
// --------------------------------------------------

// True when expectation `i` satisfies its cardinality. An exactly-N
// expectation is met at N matched calls, an at-least-N one at >= N, and an
// at-most-N one is always met (binding never exceeds N).
fn _sat(m: &Stub, i: Int) -> Bool {
  let mode: Int = m.modes[i];
  let exp: Int = m.expected[i];
  let act: Int = m.actual[i];
  if mode == _ST_AT_LEAST {
    return act >= exp;
  }
  if mode == _ST_AT_MOST {
    return true;
  }
  return act == exp;
}

// Case-sensitive method-name equality.
fn _method_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when expectation `i` has the given method and argument tuple.
fn _expect_matches(m: &Stub, i: Int, method: Str, nargs: Int, a0: Int, a1: Int, a2: Int) -> Bool {
  let meth: Str = m.methods[i];
  if !_method_eq(meth, method) { return false; }
  let n: Int = m.arg_len[i];
  if n != nargs { return false; }
  if n > 0 && _arg_at(m, i, 0) != a0 { return false; }
  if n > 1 && _arg_at(m, i, 1) != a1 { return false; }
  if n > 2 && _arg_at(m, i, 2) != a2 { return false; }
  return true;
}

// True when expectation `i` still accepts a call: at-least always does,
// exactly/at-most only below their declared count.
fn _accepts(m: &Stub, i: Int) -> Bool {
  let mode: Int = m.modes[i];
  if mode == _ST_AT_LEAST { return true; }
  let act: Int = m.actual[i];
  let exp: Int = m.expected[i];
  return act < exp;
}

// Lowest-index expectation that matches the call and still accepts it, or -1.
fn _bind(m: &Stub, method: Str, nargs: Int, a0: Int, a1: Int, a2: Int) -> Int {
  var i = 0;
  let n = _expect_count(m);
  while i < n {
    if _expect_matches(m, i, method, nargs, a0, a1, a2) {
      if _accepts(m, i) {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// Lowest-index expectation with the given matcher, ignoring cardinality
// (used to tell an exhausted matcher from an unknown call), or -1.
fn _match_any(m: &Stub, method: Str, nargs: Int, a0: Int, a1: Int, a2: Int) -> Int {
  var i = 0;
  let n = _expect_count(m);
  while i < n {
    if _expect_matches(m, i, method, nargs, a0, a1, a2) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Construction and expectations
// --------------------------------------------------

/// A fresh stub with no expectations, no calls and strict invocation.
/// Params: none.
/// Returns: an empty Stub.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_new() -> Stub {
  return Stub{
    methods: Vec[Str].new();
    modes: Vec[Int].new();
    expected: Vec[Int].new();
    actual: Vec[Int].new();
    returns: Vec[Int].new();
    fail_set: Vec[Int].new();
    fail_msgs: Vec[Str].new();
    arg_off: Vec[Int].new();
    arg_len: Vec[Int].new();
    arg_data: Vec[Int].new();
    call_methods: Vec[Str].new();
    call_off: Vec[Int].new();
    call_len: Vec[Int].new();
    call_data: Vec[Int].new();
    call_match: Vec[Int].new();
    ooo_seq: Vec[Int].new();
    ooo_taken: Vec[Int].new();
    ooo_matched: Vec[Int].new();
    extra_seq: Vec[Int].new();
    extra_kind: Vec[Int].new();
    extra_expect: Vec[Int].new();
    lenient: 0;
  };
}

/// Set the unmatched-call policy. Strict (the default) makes an invocation
/// with no matching expectation return Err; lenient makes it return Ok(0).
/// Either way the call is recorded and reported as an extra call.
/// Params: m - the stub; on - true for lenient.
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_set_lenient(m: &mut Stub, on: Bool) {
  if on {
    m.lenient = 1;
  } else {
    m.lenient = 0;
  }
}

/// Whether unmatched invocations return Ok(0) instead of Err.
/// Params: m - the stub.
/// Returns: true when lenient.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_is_lenient(m: &Stub) -> Bool {
  return m.lenient != 0;
}

// Validate and append one expectation; "" on success, else the message.
fn _expect(m: &mut Stub, method: Str, mode: Int, times: Int, nargs: Int,
           a0: Int, a1: Int, a2: Int, returns: Int, fail_flag: Int, fail_msg: Str) -> Str {
  if method.len() == 0 {
    return "stub: empty method";
  }
  if times < 0 {
    return "stub: negative times " + int_to_string(times);
  }
  if nargs < 0 || nargs > 3 {
    return "stub: arity out of range " + int_to_string(nargs);
  }
  if fail_flag != 0 && fail_msg.len() == 0 {
    return "stub: empty failure message";
  }
  m.methods.push(method);
  m.modes.push(mode);
  m.expected.push(times);
  m.actual.push(0);
  m.returns.push(returns);
  m.fail_set.push(fail_flag);
  m.fail_msgs.push(fail_msg);
  let off = m.arg_data.len();
  m.arg_off.push(off);
  m.arg_len.push(nargs);
  if nargs > 0 { m.arg_data.push(a0); }
  if nargs > 1 { m.arg_data.push(a1); }
  if nargs > 2 { m.arg_data.push(a2); }
  return "";
}

/// Declare that `method` with zero arguments is called exactly `times` times
/// and returns `returns` each time.
/// Params: m - the stub; method - non-empty method name; times - count
/// (>= 0); returns - canned return value.
/// Returns: Ok(index) with the expectation's declaration index.
/// Error case: Err("stub: empty method"); Err("stub: negative times <n>").
/// A failed call never mutates the stub.
/// Complexity: O(1).
pub fn stub_expect0(m: &mut Stub, method: Str, times: Int, returns: Int) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_EXACTLY, times, 0, 0, 0, 0, returns, 0, "");
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// Exactly `times` calls with one argument; see stub_expect0.
/// Params: m - the stub; method - non-empty method name; a0 - the argument;
/// times - count (>= 0); returns - canned return value.
/// Returns: Ok(index).
/// Error case: as stub_expect0.
/// Complexity: O(1).
pub fn stub_expect1(m: &mut Stub, method: Str, a0: Int, times: Int, returns: Int) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_EXACTLY, times, 1, a0, 0, 0, returns, 0, "");
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// Exactly `times` calls with two arguments; see stub_expect0.
/// Params: m - the stub; method - non-empty method name; a0, a1 - the
/// arguments; times - count (>= 0); returns - canned return value.
/// Returns: Ok(index).
/// Error case: as stub_expect0.
/// Complexity: O(1).
pub fn stub_expect2(m: &mut Stub, method: Str, a0: Int, a1: Int, times: Int, returns: Int) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_EXACTLY, times, 2, a0, a1, 0, returns, 0, "");
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// Exactly `times` calls with three arguments; see stub_expect0.
/// Params: m - the stub; method - non-empty method name; a0, a1, a2 - the
/// arguments; times - count (>= 0); returns - canned return value.
/// Returns: Ok(index).
/// Error case: as stub_expect0.
/// Complexity: O(1).
pub fn stub_expect3(m: &mut Stub, method: Str, a0: Int, a1: Int, a2: Int, times: Int, returns: Int) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_EXACTLY, times, 3, a0, a1, a2, returns, 0, "");
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// At least `times` calls with zero arguments; see stub_expect0.
/// Params: m - the stub; method - non-empty method name; times - minimum
/// count (>= 0); returns - canned return value.
/// Returns: Ok(index).
/// Error case: as stub_expect0.
/// Complexity: O(1).
pub fn stub_expect_at_least0(m: &mut Stub, method: Str, times: Int, returns: Int) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_AT_LEAST, times, 0, 0, 0, 0, returns, 0, "");
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// At least `times` calls with one argument; see stub_expect0.
/// Params: m - the stub; method - non-empty method name; a0 - the argument;
/// times - minimum count (>= 0); returns - canned return value.
/// Returns: Ok(index).
/// Error case: as stub_expect0.
/// Complexity: O(1).
pub fn stub_expect_at_least1(m: &mut Stub, method: Str, a0: Int, times: Int, returns: Int) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_AT_LEAST, times, 1, a0, 0, 0, returns, 0, "");
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// At least `times` calls with two arguments; see stub_expect0.
/// Params: m - the stub; method - non-empty method name; a0, a1 - the
/// arguments; times - minimum count (>= 0); returns - canned return value.
/// Returns: Ok(index).
/// Error case: as stub_expect0.
/// Complexity: O(1).
pub fn stub_expect_at_least2(m: &mut Stub, method: Str, a0: Int, a1: Int, times: Int, returns: Int) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_AT_LEAST, times, 2, a0, a1, 0, returns, 0, "");
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// At least `times` calls with three arguments; see stub_expect0.
/// Params: m - the stub; method - non-empty method name; a0, a1, a2 - the
/// arguments; times - minimum count (>= 0); returns - canned return value.
/// Returns: Ok(index).
/// Error case: as stub_expect0.
/// Complexity: O(1).
pub fn stub_expect_at_least3(m: &mut Stub, method: Str, a0: Int, a1: Int, a2: Int, times: Int, returns: Int) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_AT_LEAST, times, 3, a0, a1, a2, returns, 0, "");
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// At most `times` calls with zero arguments; see stub_expect0.
/// Params: m - the stub; method - non-empty method name; times - maximum
/// count (>= 0); returns - canned return value.
/// Returns: Ok(index).
/// Error case: as stub_expect0.
/// Complexity: O(1).
pub fn stub_expect_at_most0(m: &mut Stub, method: Str, times: Int, returns: Int) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_AT_MOST, times, 0, 0, 0, 0, returns, 0, "");
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// At most `times` calls with one argument; see stub_expect0.
/// Params: m - the stub; method - non-empty method name; a0 - the argument;
/// times - maximum count (>= 0); returns - canned return value.
/// Returns: Ok(index).
/// Error case: as stub_expect0.
/// Complexity: O(1).
pub fn stub_expect_at_most1(m: &mut Stub, method: Str, a0: Int, times: Int, returns: Int) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_AT_MOST, times, 1, a0, 0, 0, returns, 0, "");
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// At most `times` calls with two arguments; see stub_expect0.
/// Params: m - the stub; method - non-empty method name; a0, a1 - the
/// arguments; times - maximum count (>= 0); returns - canned return value.
/// Returns: Ok(index).
/// Error case: as stub_expect0.
/// Complexity: O(1).
pub fn stub_expect_at_most2(m: &mut Stub, method: Str, a0: Int, a1: Int, times: Int, returns: Int) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_AT_MOST, times, 2, a0, a1, 0, returns, 0, "");
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// At most `times` calls with three arguments; see stub_expect0.
/// Params: m - the stub; method - non-empty method name; a0, a1, a2 - the
/// arguments; times - maximum count (>= 0); returns - canned return value.
/// Returns: Ok(index).
/// Error case: as stub_expect0.
/// Complexity: O(1).
pub fn stub_expect_at_most3(m: &mut Stub, method: Str, a0: Int, a1: Int, a2: Int, times: Int, returns: Int) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_AT_MOST, times, 3, a0, a1, a2, returns, 0, "");
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// Declare that `method` with zero arguments is called exactly once and
/// fails: the invocation returns Err(`message`) verbatim.
/// Params: m - the stub; method - non-empty method name; message - the
/// non-empty failure text.
/// Returns: Ok(index).
/// Error case: Err("stub: empty method"); Err("stub: empty failure message").
/// Complexity: O(1).
pub fn stub_expect_fail0(m: &mut Stub, method: Str, message: Str) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_EXACTLY, 1, 0, 0, 0, 0, 0, 1, message);
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// Exactly-once failing call with one argument; see stub_expect_fail0.
/// Params: m - the stub; method - non-empty method name; a0 - the argument;
/// message - the non-empty failure text.
/// Returns: Ok(index).
/// Error case: as stub_expect_fail0.
/// Complexity: O(1).
pub fn stub_expect_fail1(m: &mut Stub, method: Str, a0: Int, message: Str) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_EXACTLY, 1, 1, a0, 0, 0, 0, 1, message);
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// Exactly-once failing call with two arguments; see stub_expect_fail0.
/// Params: m - the stub; method - non-empty method name; a0, a1 - the
/// arguments; message - the non-empty failure text.
/// Returns: Ok(index).
/// Error case: as stub_expect_fail0.
/// Complexity: O(1).
pub fn stub_expect_fail2(m: &mut Stub, method: Str, a0: Int, a1: Int, message: Str) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_EXACTLY, 1, 2, a0, a1, 0, 0, 1, message);
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// Exactly-once failing call with three arguments; see stub_expect_fail0.
/// Params: m - the stub; method - non-empty method name; a0, a1, a2 - the
/// arguments; message - the non-empty failure text.
/// Returns: Ok(index).
/// Error case: as stub_expect_fail0.
/// Complexity: O(1).
pub fn stub_expect_fail3(m: &mut Stub, method: Str, a0: Int, a1: Int, a2: Int, message: Str) -> Result[Int, Str] {
  let err = _expect(m, method, _ST_EXACTLY, 1, 3, a0, a1, a2, 0, 1, message);
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

// --------------------------------------------------
//  Invocation
// --------------------------------------------------

// Record one call and update the bookkeeping. Returns the matched
// expectation index or -1. The call log, the matched/unmatched accounting and
// any out-of-order violation are updated exactly once per call.
fn _invoke(m: &mut Stub, method: Str, nargs: Int, a0: Int, a1: Int, a2: Int) -> Int {
  let seq = _call_count(m);
  m.call_methods.push(method);
  let off = m.call_data.len();
  m.call_off.push(off);
  m.call_len.push(nargs);
  if nargs > 0 { m.call_data.push(a0); }
  if nargs > 1 { m.call_data.push(a1); }
  if nargs > 2 { m.call_data.push(a2); }
  let idx = _bind(m, method, nargs, a0, a1, a2);
  m.call_match.push(idx);
  if idx >= 0 {
    let act: Int = m.actual[idx];
    m.actual[idx] = act + 1;
    var j = 0;
    var overtaken = -1;
    while j < idx {
      if !_sat(m, j) {
        if overtaken < 0 {
          overtaken = j;
        }
      }
      j = j + 1;
    }
    if overtaken >= 0 {
      m.ooo_seq.push(seq);
      m.ooo_taken.push(overtaken);
      m.ooo_matched.push(idx);
    }
    return idx;
  }
  let any = _match_any(m, method, nargs, a0, a1, a2);
  m.extra_seq.push(seq);
  if any >= 0 {
    m.extra_kind.push(1);
    m.extra_expect.push(any);
  } else {
    m.extra_kind.push(0);
    m.extra_expect.push(-1);
  }
  return -1;
}

// Violation-array index of the extra entry for call `seq`, or -1.
fn _extra_entry_for_call(m: &Stub, seq: Int) -> Int {
  var k = 0;
  let n = _extra_count(m);
  while k < n {
    let s: Int = m.extra_seq[k];
    if s == seq {
      return k;
    }
    k = k + 1;
  }
  return -1;
}

// Message for the unmatched call `seq`: unknown call, or exhausted matcher.
fn _unmatched_message(m: &Stub, seq: Int) -> Str {
  if seq < 0 || seq >= _call_count(m) {
    return "stub: unexpected call";
  }
  let meth: Str = m.call_methods[seq];
  let desc = _call_args_desc(m, seq);
  let base = "stub: unexpected call '" + meth + desc + "' (call #" + int_to_string(seq) + ")";
  let k = _extra_entry_for_call(m, seq);
  if k < 0 {
    return base;
  }
  let kind: Int = m.extra_kind[k];
  if kind == 0 {
    return base;
  }
  let ex: Int = m.extra_expect[k];
  if ex < 0 {
    return base;
  }
  return base + ": matching expectation #" + int_to_string(ex) + " is exhausted";
}

/// Invoke a zero-argument method. The call is always recorded and accounted;
/// it binds to the first expectation (declaration order) whose method and
/// argument tuple match and which still accepts a call. A bound expectation
/// with a failure action returns Err with its programmed message verbatim; a
/// bound success expectation returns Ok with its canned value; an unmatched
/// call returns Err (strict, the default) or Ok(0) (lenient).
/// Params: m - the stub; method - the method name (may be empty).
/// Returns: Result[Int, Str] as above.
/// Error case: strict unmatched Err("stub: unexpected call '<m>' (call #<n>)"
/// [...]); a bound failure action's programmed message.
/// Complexity: O(expectations).
pub fn stub_invoke0(m: &mut Stub, method: Str) -> Result[Int, Str] {
  let idx = _invoke(m, method, 0, 0, 0, 0);
  if idx < 0 {
    if m.lenient != 0 {
      return _ok_int(0);
    }
    let seq = _call_count(m) - 1;
    return _err_int(_unmatched_message(m, seq));
  }
  let fs: Int = m.fail_set[idx];
  if fs != 0 {
    let msg: Str = m.fail_msgs[idx];
    return _err_int(msg);
  }
  let v: Int = m.returns[idx];
  return _ok_int(v);
}

/// Invoke a one-argument method; see stub_invoke0.
/// Params: m - the stub; method - the method name; a0 - the argument.
/// Returns: Result[Int, Str] as in stub_invoke0.
/// Error case: as stub_invoke0.
/// Complexity: O(expectations).
pub fn stub_invoke1(m: &mut Stub, method: Str, a0: Int) -> Result[Int, Str] {
  let idx = _invoke(m, method, 1, a0, 0, 0);
  if idx < 0 {
    if m.lenient != 0 {
      return _ok_int(0);
    }
    let seq = _call_count(m) - 1;
    return _err_int(_unmatched_message(m, seq));
  }
  let fs: Int = m.fail_set[idx];
  if fs != 0 {
    let msg: Str = m.fail_msgs[idx];
    return _err_int(msg);
  }
  let v: Int = m.returns[idx];
  return _ok_int(v);
}

/// Invoke a two-argument method; see stub_invoke0.
/// Params: m - the stub; method - the method name; a0, a1 - the arguments.
/// Returns: Result[Int, Str] as in stub_invoke0.
/// Error case: as stub_invoke0.
/// Complexity: O(expectations).
pub fn stub_invoke2(m: &mut Stub, method: Str, a0: Int, a1: Int) -> Result[Int, Str] {
  let idx = _invoke(m, method, 2, a0, a1, 0);
  if idx < 0 {
    if m.lenient != 0 {
      return _ok_int(0);
    }
    let seq = _call_count(m) - 1;
    return _err_int(_unmatched_message(m, seq));
  }
  let fs: Int = m.fail_set[idx];
  if fs != 0 {
    let msg: Str = m.fail_msgs[idx];
    return _err_int(msg);
  }
  let v: Int = m.returns[idx];
  return _ok_int(v);
}

/// Invoke a three-argument method; see stub_invoke0.
/// Params: m - the stub; method - the method name; a0, a1, a2 - the
/// arguments.
/// Returns: Result[Int, Str] as in stub_invoke0.
/// Error case: as stub_invoke0.
/// Complexity: O(expectations).
pub fn stub_invoke3(m: &mut Stub, method: Str, a0: Int, a1: Int, a2: Int) -> Result[Int, Str] {
  let idx = _invoke(m, method, 3, a0, a1, a2);
  if idx < 0 {
    if m.lenient != 0 {
      return _ok_int(0);
    }
    let seq = _call_count(m) - 1;
    return _err_int(_unmatched_message(m, seq));
  }
  let fs: Int = m.fail_set[idx];
  if fs != 0 {
    let msg: Str = m.fail_msgs[idx];
    return _err_int(msg);
  }
  let v: Int = m.returns[idx];
  return _ok_int(v);
}

// --------------------------------------------------
//  Expectation accessors
// --------------------------------------------------

/// Number of declared expectations.
/// Params: m - the stub.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_expectation_count(m: &Stub) -> Int {
  return _expect_count(m);
}

/// Method name of expectation `i`.
/// Params: m - the stub; i - the zero-based declaration index.
/// Returns: the name; "" out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_expect_method(m: &Stub, i: Int) -> Str {
  if i < 0 || i >= _expect_count(m) {
    return "";
  }
  let v: Str = m.methods[i];
  return v;
}

/// Cardinality mode of expectation `i`.
/// Params: m - the stub; i - the zero-based declaration index.
/// Returns: 0 = exactly, 1 = at least, 2 = at most; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_expect_mode(m: &Stub, i: Int) -> Int {
  if i < 0 || i >= _expect_count(m) {
    return -1;
  }
  let v: Int = m.modes[i];
  return v;
}

/// Declared count of expectation `i`.
/// Params: m - the stub; i - the zero-based declaration index.
/// Returns: the count; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_expect_times(m: &Stub, i: Int) -> Int {
  if i < 0 || i >= _expect_count(m) {
    return -1;
  }
  let v: Int = m.expected[i];
  return v;
}

/// Matched call count of expectation `i`.
/// Params: m - the stub; i - the zero-based declaration index.
/// Returns: the count; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_expect_actual(m: &Stub, i: Int) -> Int {
  if i < 0 || i >= _expect_count(m) {
    return -1;
  }
  let v: Int = m.actual[i];
  return v;
}

/// Canned return value of expectation `i`.
/// Params: m - the stub; i - the zero-based declaration index.
/// Returns: the value; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_expect_return(m: &Stub, i: Int) -> Int {
  if i < 0 || i >= _expect_count(m) {
    return -1;
  }
  let v: Int = m.returns[i];
  return v;
}

/// Whether expectation `i` has a failure action.
/// Params: m - the stub; i - the zero-based declaration index.
/// Returns: the flag; false out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_expect_has_failure(m: &Stub, i: Int) -> Bool {
  if i < 0 || i >= _expect_count(m) {
    return false;
  }
  let v: Int = m.fail_set[i];
  return v != 0;
}

/// Programmed failure message of expectation `i`.
/// Params: m - the stub; i - the zero-based declaration index.
/// Returns: the message; "" when there is none or the index is out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_expect_failure(m: &Stub, i: Int) -> Str {
  if i < 0 || i >= _expect_count(m) {
    return "";
  }
  let v: Str = m.fail_msgs[i];
  return v;
}

/// Arity of expectation `i`.
/// Params: m - the stub; i - the zero-based declaration index.
/// Returns: the argument count; 0 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_expect_arg_count(m: &Stub, i: Int) -> Int {
  if i < 0 || i >= _expect_count(m) {
    return 0;
  }
  let v: Int = m.arg_len[i];
  return v;
}

/// k-th argument of expectation `i`.
/// Params: m - the stub; i - the declaration index; k - the argument index.
/// Returns: the argument; 0 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_expect_arg(m: &Stub, i: Int, k: Int) -> Int {
  return _arg_at(m, i, k);
}

/// Whether expectation `i` currently satisfies its cardinality.
/// Params: m - the stub; i - the zero-based declaration index.
/// Returns: the flag; false out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_expect_met(m: &Stub, i: Int) -> Bool {
  if i < 0 || i >= _expect_count(m) {
    return false;
  }
  return _sat(m, i);
}

// --------------------------------------------------
//  Call-log accessors
// --------------------------------------------------

/// Number of recorded calls, matched or not.
/// Params: m - the stub.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_call_total(m: &Stub) -> Int {
  return _call_count(m);
}

/// Sequence number of call `i`: its zero-based position in the log.
/// Params: m - the stub; i - the zero-based call index.
/// Returns: the sequence number; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_call_seq(m: &Stub, i: Int) -> Int {
  if i < 0 || i >= _call_count(m) {
    return -1;
  }
  return i;
}

/// Method name of call `i`.
/// Params: m - the stub; i - the zero-based call index.
/// Returns: the name; "" out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_call_method(m: &Stub, i: Int) -> Str {
  if i < 0 || i >= _call_count(m) {
    return "";
  }
  let v: Str = m.call_methods[i];
  return v;
}

/// Arity of call `i`.
/// Params: m - the stub; i - the zero-based call index.
/// Returns: the argument count; 0 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_call_arg_count(m: &Stub, i: Int) -> Int {
  if i < 0 || i >= _call_count(m) {
    return 0;
  }
  let v: Int = m.call_len[i];
  return v;
}

/// k-th argument of call `i`.
/// Params: m - the stub; i - the call index; k - the argument index.
/// Returns: the argument; 0 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_call_arg(m: &Stub, i: Int, k: Int) -> Int {
  return _call_arg_at(m, i, k);
}

/// Expectation index that call `i` bound to.
/// Params: m - the stub; i - the zero-based call index.
/// Returns: the index, or -1 when unmatched / out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_call_match(m: &Stub, i: Int) -> Int {
  if i < 0 || i >= _call_count(m) {
    return -1;
  }
  let v: Int = m.call_match[i];
  return v;
}

/// Whether call `i` bound to an expectation.
/// Params: m - the stub; i - the zero-based call index.
/// Returns: the flag; false out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_call_matched(m: &Stub, i: Int) -> Bool {
  if i < 0 || i >= _call_count(m) {
    return false;
  }
  let v: Int = m.call_match[i];
  return v >= 0;
}

/// Number of recorded calls that bound to an expectation.
/// Params: m - the stub.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(calls).
pub fn stub_matched_count(m: &Stub) -> Int {
  var c = 0;
  var i = 0;
  let n = _call_count(m);
  while i < n {
    let v: Int = m.call_match[i];
    if v >= 0 {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// Number of recorded calls that matched no accepting expectation; equal to
/// the extra-call violation count.
/// Params: m - the stub.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_unmatched_count(m: &Stub) -> Int {
  return _extra_count(m);
}

// --------------------------------------------------
//  Violation accessors
// --------------------------------------------------

// Number of expectations that are not satisfied, in declaration order.
fn _missing_count(m: &Stub) -> Int {
  var c = 0;
  var i = 0;
  let n = _expect_count(m);
  while i < n {
    if !_sat(m, i) {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

// Declaration index of the k-th unsatisfied expectation, or -1.
fn _missing_index(m: &Stub, k: Int) -> Int {
  if k < 0 || k >= _missing_count(m) {
    return -1;
  }
  var seen = 0;
  var i = 0;
  let n = _expect_count(m);
  while i < n {
    if !_sat(m, i) {
      if seen == k {
        return i;
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return -1;
}

// Message for the missing expectation `i`.
fn _missing_message(m: &Stub, i: Int) -> Str {
  let meth: Str = m.methods[i];
  let desc = _expect_args_desc(m, i);
  let mode: Int = m.modes[i];
  let exp: Int = m.expected[i];
  let act: Int = m.actual[i];
  return "stub: missing call '" + meth + desc + "': expected "
    + _mode_word(mode) + " " + int_to_string(exp) + ", got " + int_to_string(act);
}

// Message for the extra entry `k`.
fn _extra_message(m: &Stub, k: Int) -> Str {
  if k < 0 || k >= _extra_count(m) {
    return "";
  }
  let seq: Int = m.extra_seq[k];
  if seq < 0 || seq >= _call_count(m) {
    return "stub: unexpected call";
  }
  let meth: Str = m.call_methods[seq];
  let desc = _call_args_desc(m, seq);
  let base = "stub: unexpected call '" + meth + desc + "' (call #" + int_to_string(seq) + ")";
  let kind: Int = m.extra_kind[k];
  if kind == 0 {
    return base;
  }
  let ex: Int = m.extra_expect[k];
  if ex < 0 {
    return base;
  }
  return base + ": matching expectation #" + int_to_string(ex) + " is exhausted";
}

// Message for the out-of-order entry `k`.
fn _ooo_message(m: &Stub, k: Int) -> Str {
  if k < 0 || k >= _ooo_count(m) {
    return "";
  }
  let seq: Int = m.ooo_seq[k];
  let j: Int = m.ooo_taken[k];
  if seq < 0 || seq >= _call_count(m) {
    return "stub: out-of-order call";
  }
  if j < 0 || j >= _expect_count(m) {
    return "stub: out-of-order call";
  }
  let meth: Str = m.call_methods[seq];
  let desc = _call_args_desc(m, seq);
  let jm: Str = m.methods[j];
  let jd = _expect_args_desc(m, j);
  return "stub: out-of-order call '" + meth + desc + "' (call #" + int_to_string(seq)
    + "): expectation #" + int_to_string(j) + " '" + jm + jd + "' is still unsatisfied";
}

/// Number of expectations that are not satisfied (missing calls).
/// Params: m - the stub.
/// Returns: the count; at-most expectations never count (always satisfied).
/// Error case: none.
/// Complexity: O(expectations).
pub fn stub_missing_count(m: &Stub) -> Int {
  return _missing_count(m);
}

/// Declaration index of the k-th missing expectation.
/// Params: m - the stub; k - the zero-based violation index.
/// Returns: the expectation index; -1 out of range.
/// Error case: none.
/// Complexity: O(expectations).
pub fn stub_missing_index(m: &Stub, k: Int) -> Int {
  return _missing_index(m, k);
}

/// Message for the k-th missing expectation, in declaration order.
/// Params: m - the stub; k - the zero-based violation index.
/// Returns: "stub: missing call '<method><args>': expected <mode> <n>, got
/// <m>"; "" out of range.
/// Error case: none.
/// Complexity: O(expectations).
pub fn stub_missing_message(m: &Stub, k: Int) -> Str {
  let i = _missing_index(m, k);
  if i < 0 {
    return "";
  }
  return _missing_message(m, i);
}

/// Number of unexpected (unmatched) calls.
/// Params: m - the stub.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_extra_count(m: &Stub) -> Int {
  return _extra_count(m);
}

/// Sequence number of the k-th unexpected call, in call order.
/// Params: m - the stub; k - the zero-based violation index.
/// Returns: the call sequence number; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_extra_call(m: &Stub, k: Int) -> Int {
  if k < 0 || k >= _extra_count(m) {
    return -1;
  }
  let v: Int = m.extra_seq[k];
  return v;
}

/// Message for the k-th unexpected call, in call order.
/// Params: m - the stub; k - the zero-based violation index.
/// Returns: "stub: unexpected call '<method><args>' (call #<n>)", plus
/// ": matching expectation #<i> is exhausted" when a matcher existed but
/// its count was full; "" out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_extra_message(m: &Stub, k: Int) -> Str {
  return _extra_message(m, k);
}

/// Number of out-of-order events: calls that bound to expectation `i` while
/// an earlier-declared expectation `j < i` was still unsatisfied.
/// Params: m - the stub.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_out_of_order_count(m: &Stub) -> Int {
  return _ooo_count(m);
}

/// Sequence number of the k-th out-of-order call, in call order.
/// Params: m - the stub; k - the zero-based violation index.
/// Returns: the call sequence number; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_out_of_order_call(m: &Stub, k: Int) -> Int {
  if k < 0 || k >= _ooo_count(m) {
    return -1;
  }
  let v: Int = m.ooo_seq[k];
  return v;
}

/// Declaration index of the expectation that the k-th out-of-order call
/// overtook (the lowest-index unsatisfied expectation at that moment).
/// Params: m - the stub; k - the zero-based violation index.
/// Returns: the expectation index; -1 out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_out_of_order_expectation(m: &Stub, k: Int) -> Int {
  if k < 0 || k >= _ooo_count(m) {
    return -1;
  }
  let v: Int = m.ooo_taken[k];
  return v;
}

/// Message for the k-th out-of-order event, in call order.
/// Params: m - the stub; k - the zero-based violation index.
/// Returns: "stub: out-of-order call '<method><args>' (call #<n>):
/// expectation #<j> '<method><args>' is still unsatisfied"; "" out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_out_of_order_message(m: &Stub, k: Int) -> Str {
  return _ooo_message(m, k);
}

/// Total number of violations: missing + extra + out-of-order.
/// Params: m - the stub.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(expectations).
pub fn stub_violation_count(m: &Stub) -> Int {
  return _missing_count(m) + _extra_count(m) + _ooo_count(m);
}

/// True when there are no violations of any kind.
/// Params: m - the stub.
/// Returns: the flag.
/// Error case: none.
/// Complexity: O(expectations).
pub fn stub_verified(m: &Stub) -> Bool {
  return stub_violation_count(m) == 0;
}

/// Message for the first violation in reporting order: the first missing
/// expectation (declaration order), else the first unexpected call (call
/// order), else the first out-of-order event (call order).
/// Params: m - the stub.
/// Returns: the message; "" when verified.
/// Error case: none.
/// Complexity: O(expectations).
pub fn stub_verify_message(m: &Stub) -> Str {
  if _missing_count(m) > 0 {
    return _missing_message(m, _missing_index(m, 0));
  }
  if _extra_count(m) > 0 {
    return _extra_message(m, 0);
  }
  if _ooo_count(m) > 0 {
    return _ooo_message(m, 0);
  }
  return "";
}

/// Full structured violation report: one header line and one line per
/// violation, in reporting order (missing, extra, out-of-order). Every line
/// starts with "stub: ".
/// Params: m - the stub.
/// Returns: "stub: <n> violation(s):\n<line>..." with no trailing newline; ""
/// when verified.
/// Error case: none.
/// Complexity: O(expectations).
pub fn stub_report(m: &Stub) -> Str {
  let n = stub_violation_count(m);
  if n == 0 {
    return "";
  }
  var out = "stub: " + int_to_string(n) + " violation(s):";
  var k = 0;
  let mn = _missing_count(m);
  while k < mn {
    out = out + "\n" + _missing_message(m, _missing_index(m, k));
    k = k + 1;
  }
  var k2 = 0;
  let en = _extra_count(m);
  while k2 < en {
    out = out + "\n" + _extra_message(m, k2);
    k2 = k2 + 1;
  }
  var k3 = 0;
  let on = _ooo_count(m);
  while k3 < on {
    out = out + "\n" + _ooo_message(m, k3);
    k3 = k3 + 1;
  }
  return out;
}

// --------------------------------------------------
//  Reset and clear
// --------------------------------------------------

/// Forget the call log, the matched counts and every violation; expectations
/// stay declared (with actual counts back at 0) so the stub can be replayed.
/// Params: m - the stub to reset.
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(expectations).
pub fn stub_reset(m: &mut Stub) {
  m.call_methods = Vec[Str].new();
  m.call_off = Vec[Int].new();
  m.call_len = Vec[Int].new();
  m.call_data = Vec[Int].new();
  m.call_match = Vec[Int].new();
  m.ooo_seq = Vec[Int].new();
  m.ooo_taken = Vec[Int].new();
  m.ooo_matched = Vec[Int].new();
  m.extra_seq = Vec[Int].new();
  m.extra_kind = Vec[Int].new();
  m.extra_expect = Vec[Int].new();
  var i = 0;
  let n = _expect_count(m);
  while i < n {
    m.actual[i] = 0;
    i = i + 1;
  }
}

/// Forget everything: expectations, call log, violations and the lenient
/// flag. The stub becomes equivalent to a fresh stub_new().
/// Params: m - the stub to clear.
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(1).
pub fn stub_clear(m: &mut Stub) {
  m.methods = Vec[Str].new();
  m.modes = Vec[Int].new();
  m.expected = Vec[Int].new();
  m.actual = Vec[Int].new();
  m.returns = Vec[Int].new();
  m.fail_set = Vec[Int].new();
  m.fail_msgs = Vec[Str].new();
  m.arg_off = Vec[Int].new();
  m.arg_len = Vec[Int].new();
  m.arg_data = Vec[Int].new();
  m.call_methods = Vec[Str].new();
  m.call_off = Vec[Int].new();
  m.call_len = Vec[Int].new();
  m.call_data = Vec[Int].new();
  m.call_match = Vec[Int].new();
  m.ooo_seq = Vec[Int].new();
  m.ooo_taken = Vec[Int].new();
  m.ooo_matched = Vec[Int].new();
  m.extra_seq = Vec[Int].new();
  m.extra_kind = Vec[Int].new();
  m.extra_expect = Vec[Int].new();
  m.lenient = 0;
}
