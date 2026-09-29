// XIOM -- xiom.mock: expectation and call-recording test doubles
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Greenfield package: pure XIOM, no FFI, no runtime hooks.
//
// A mock is a plain value: declare expectations with a name and a cardinality
// (exactly N, at least N, at most N), record calls as they happen, then ask
// whether the expectations were met. Matching is by name and is
// case-sensitive; call arguments are captured as opaque text. Nothing here
// intercepts real functions -- the code under test must call the mock
// explicitly, which keeps the double deterministic and free of FFI.
//
// Language notes (XIOM v0.61.3): free functions only; flat parallel Vecs
// instead of Vec[StructType]; Str equality goes through
// xiom.string.compare.str_compare; every element read is bound to a typed
// local first; Ok/Err are constructed only in the leaf helpers
// _ok_int/_err_int.

module xiom.mock

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

const _MK_EXACTLY: Int = 0;
const _MK_AT_LEAST: Int = 1;
const _MK_AT_MOST: Int = 2;

// Human-readable form of a mode, for messages.
fn _mode_word(mode: Int) -> Str {
  if mode == _MK_AT_LEAST {
    return "at least";
  }
  if mode == _MK_AT_MOST {
    return "at most";
  }
  return "exactly";
}

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// One mock: expectations plus the recorded call log.
/// Expectations are index-aligned across names / modes / expected / actual,
/// in declaration order. Every recorded call appends to call_names and
/// call_args; a call whose name matches an expectation increments that
/// expectation's actual count, and a call that matches nothing is also
/// appended to unexpected_names / unexpected_args. modes are 0 = exactly,
/// 1 = at least, 2 = at most.
pub type Mock = {
  names: Vec[Str];
  modes: Vec[Int];
  expected: Vec[Int];
  actual: Vec[Int];
  call_names: Vec[Str];
  call_args: Vec[Str];
  unexpected_names: Vec[Str];
  unexpected_args: Vec[Str];
}

// --------------------------------------------------
//  Construction and expectations
// --------------------------------------------------

/// A fresh mock with no expectations and no recorded calls.
/// Params: none.
/// Returns: an empty Mock.
/// Error case: none.
/// Complexity: O(1).
pub fn mock_new() -> Mock {
  return Mock{
    names: Vec[Str].new();
    modes: Vec[Int].new();
    expected: Vec[Int].new();
    actual: Vec[Int].new();
    call_names: Vec[Str].new();
    call_args: Vec[Str].new();
    unexpected_names: Vec[Str].new();
    unexpected_args: Vec[Str].new();
  };
}

// Number of index-aligned expectations.
fn _expect_count(m: &Mock) -> Int {
  var n = m.names.len();
  if m.modes.len() < n {
    n = m.modes.len();
  }
  if m.expected.len() < n {
    n = m.expected.len();
  }
  if m.actual.len() < n {
    n = m.actual.len();
  }
  return n;
}

// Index of the first expectation named `name`, or -1.
fn _index(m: &Mock, name: Str) -> Int {
  var i = 0;
  let n = _expect_count(m);
  while i < n {
    let cur: Str = m.names[i];
    if compare.str_compare(cur, name) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Validate and append one expectation; "" on success, else the message.
fn _expect(m: &mut Mock, name: Str, mode: Int, times: Int) -> Str {
  if name.len() == 0 {
    return "mock: empty name";
  }
  if times < 0 {
    return "mock: negative times " + int_to_string(times);
  }
  if _index(m, name) >= 0 {
    return "mock: duplicate expectation '" + name + "'";
  }
  m.names.push(name);
  m.modes.push(mode);
  m.expected.push(times);
  m.actual.push(0);
  return "";
}

/// Declare an expectation that the named call happens exactly `times` times.
/// Params: m - the mock; name - the non-empty call name; times - the count
/// (must be >= 0).
/// Returns: Ok(index) with the expectation's declaration index.
/// Error case: Err("mock: empty name"); Err("mock: negative times <n>");
/// Err("mock: duplicate expectation '<name>'") when the name is already
/// declared. A failed call never mutates the mock.
/// Complexity: O(expectations).
pub fn mock_expect(m: &mut Mock, name: Str, times: Int) -> Result[Int, Str] {
  let err = _expect(m, name, _MK_EXACTLY, times);
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// Declare an expectation that the named call happens at least `times` times.
/// Params: m - the mock; name - the non-empty call name; times - the minimum
/// count (must be >= 0).
/// Returns: Ok(index) with the expectation's declaration index.
/// Error case: as mock_expect.
/// Complexity: O(expectations).
pub fn mock_expect_at_least(m: &mut Mock, name: Str, times: Int) -> Result[Int, Str] {
  let err = _expect(m, name, _MK_AT_LEAST, times);
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

/// Declare an expectation that the named call happens at most `times` times.
/// Params: m - the mock; name - the non-empty call name; times - the maximum
/// count (must be >= 0).
/// Returns: Ok(index) with the expectation's declaration index.
/// Error case: as mock_expect.
/// Complexity: O(expectations).
pub fn mock_expect_at_most(m: &mut Mock, name: Str, times: Int) -> Result[Int, Str] {
  let err = _expect(m, name, _MK_AT_MOST, times);
  if err.len() > 0 {
    return _err_int(err);
  }
  return _ok_int(_expect_count(m) - 1);
}

// --------------------------------------------------
//  Recording
// --------------------------------------------------

/// Record one call. The call is appended to the call log; when its name
/// matches an expectation, that expectation's actual count grows; otherwise
/// it is also recorded as unexpected.
/// Params: m - the mock; name - the call name (may be empty); args - an
/// opaque argument description (may be empty).
/// Returns: nothing.
/// Error case: none (recording is never rejected; verification is a separate
/// step).
/// Complexity: O(expectations).
pub fn mock_record(m: &mut Mock, name: Str, args: Str) {
  m.call_names.push(name);
  m.call_args.push(args);
  let idx = _index(m, name);
  if idx < 0 {
    m.unexpected_names.push(name);
    m.unexpected_args.push(args);
  } else {
    let a: Int = m.actual[idx];
    m.actual[idx] = a + 1;
  }
}

/// Number of recorded calls, expected or not.
/// Params: m - the mock.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(1).
pub fn mock_call_total(m: &Mock) -> Int {
  var n = m.call_names.len();
  if m.call_args.len() < n {
    n = m.call_args.len();
  }
  return n;
}

/// Name of recorded call `i`, in record order.
/// Params: m - the mock; i - the zero-based call index.
/// Returns: the name; "" out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn mock_call_name(m: &Mock, i: Int) -> Str {
  if i < 0 || i >= mock_call_total(m) {
    return "";
  }
  let v: Str = m.call_names[i];
  return v;
}

/// Arguments text of recorded call `i`.
/// Params: m - the mock; i - the zero-based call index.
/// Returns: the text; "" out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn mock_call_args(m: &Mock, i: Int) -> Str {
  if i < 0 || i >= mock_call_total(m) {
    return "";
  }
  let v: Str = m.call_args[i];
  return v;
}

/// Number of recorded calls with a given name, matched or unexpected.
/// Params: m - the mock; name - the call name (case-sensitive).
/// Returns: the count.
/// Error case: none.
/// Complexity: O(calls).
pub fn mock_call_count(m: &Mock, name: Str) -> Int {
  var c = 0;
  var i = 0;
  let n = mock_call_total(m);
  while i < n {
    let cur: Str = m.call_names[i];
    if compare.str_compare(cur, name) == 0 {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

// --------------------------------------------------
//  Unexpected calls
// --------------------------------------------------

// Number of index-aligned unexpected calls.
fn _unexpected_count(m: &Mock) -> Int {
  var n = m.unexpected_names.len();
  if m.unexpected_args.len() < n {
    n = m.unexpected_args.len();
  }
  return n;
}

/// Number of recorded calls that matched no expectation.
/// Params: m - the mock.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(1).
pub fn mock_unexpected_count(m: &Mock) -> Int {
  return _unexpected_count(m);
}

/// Name of unexpected call `i`, in record order.
/// Params: m - the mock; i - the zero-based index.
/// Returns: the name; "" out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn mock_unexpected_name(m: &Mock, i: Int) -> Str {
  if i < 0 || i >= _unexpected_count(m) {
    return "";
  }
  let v: Str = m.unexpected_names[i];
  return v;
}

/// Arguments text of unexpected call `i`.
/// Params: m - the mock; i - the zero-based index.
/// Returns: the text; "" out of range.
/// Error case: none.
/// Complexity: O(1).
pub fn mock_unexpected_args(m: &Mock, i: Int) -> Str {
  if i < 0 || i >= _unexpected_count(m) {
    return "";
  }
  let v: Str = m.unexpected_args[i];
  return v;
}

/// Message for the first unexpected call, or "" when there was none.
/// Params: m - the mock.
/// Returns: "mock: unexpected call '<name>'".
/// Error case: none.
/// Complexity: O(1).
pub fn mock_unexpected_message(m: &Mock) -> Str {
  if _unexpected_count(m) == 0 {
    return "";
  }
  let name: Str = m.unexpected_names[0];
  return "mock: unexpected call '" + name + "'";
}

// --------------------------------------------------
//  Expectation accessors
// --------------------------------------------------

/// Number of declared expectations.
/// Params: m - the mock.
/// Returns: the count.
/// Error case: none.
/// Complexity: O(1).
pub fn mock_expectation_count(m: &Mock) -> Int {
  return _expect_count(m);
}

/// Declaration index of the expectation named `name`, or -1.
/// Params: m - the mock; name - the expectation name (case-sensitive).
/// Returns: the index, or -1 when there is no such expectation.
/// Error case: none.
/// Complexity: O(expectations).
pub fn mock_expectation_index(m: &Mock, name: Str) -> Int {
  return _index(m, name);
}

/// Declared cardinality mode of the expectation named `name`.
/// Params: m - the mock; name - the expectation name.
/// Returns: 0 = exactly, 1 = at least, 2 = at most; -1 when there is no such
/// expectation.
/// Error case: none.
/// Complexity: O(expectations).
pub fn mock_mode(m: &Mock, name: Str) -> Int {
  let idx = _index(m, name);
  if idx < 0 {
    return -1;
  }
  let v: Int = m.modes[idx];
  return v;
}

/// Declared count of the expectation named `name`.
/// Params: m - the mock; name - the expectation name.
/// Returns: the expected count; -1 when there is no such expectation.
/// Error case: none.
/// Complexity: O(expectations).
pub fn mock_expected(m: &Mock, name: Str) -> Int {
  let idx = _index(m, name);
  if idx < 0 {
    return -1;
  }
  let v: Int = m.expected[idx];
  return v;
}

/// Matched call count of the expectation named `name`.
/// Params: m - the mock; name - the expectation name.
/// Returns: the actual count; -1 when there is no such expectation.
/// Error case: none.
/// Complexity: O(expectations).
pub fn mock_actual(m: &Mock, name: Str) -> Int {
  let idx = _index(m, name);
  if idx < 0 {
    return -1;
  }
  let v: Int = m.actual[idx];
  return v;
}

// --------------------------------------------------
//  Verification
// --------------------------------------------------

// True when expectation `i` satisfies its cardinality.
fn _is_met(m: &Mock, i: Int) -> Bool {
  let mode: Int = m.modes[i];
  let exp: Int = m.expected[i];
  let act: Int = m.actual[i];
  if mode == _MK_AT_LEAST {
    return act >= exp;
  }
  if mode == _MK_AT_MOST {
    return act <= exp;
  }
  return act == exp;
}

/// Number of expectations that are not satisfied.
/// Params: m - the mock.
/// Returns: the count; 0 when every expectation is met. Unexpected calls do
/// not count here (see mock_unexpected_count).
/// Error case: none.
/// Complexity: O(expectations).
pub fn mock_unmet_count(m: &Mock) -> Int {
  var c = 0;
  var i = 0;
  let n = _expect_count(m);
  while i < n {
    if !_is_met(m, i) {
      c = c + 1;
    }
    i = i + 1;
  }
  return c;
}

/// True when every declared expectation is met.
/// Params: m - the mock.
/// Returns: the flag.
/// Error case: none.
/// Complexity: O(expectations).
pub fn mock_verified(m: &Mock) -> Bool {
  return mock_unmet_count(m) == 0;
}

/// Message for the first unmet expectation, in declaration order, or "" when
/// everything is met.
/// Params: m - the mock.
/// Returns: "mock: unmet expectation '<name>': expected <mode> <n>, got <m>"
/// where <mode> is "exactly", "at least" or "at most".
/// Error case: none.
/// Complexity: O(expectations).
pub fn mock_verify_message(m: &Mock) -> Str {
  var i = 0;
  let n = _expect_count(m);
  while i < n {
    if !_is_met(m, i) {
      let name: Str = m.names[i];
      let mode: Int = m.modes[i];
      let exp: Int = m.expected[i];
      let act: Int = m.actual[i];
      return "mock: unmet expectation '" + name + "': expected "
        + _mode_word(mode) + " " + int_to_string(exp)
        + ", got " + int_to_string(act);
    }
    i = i + 1;
  }
  return "";
}

// --------------------------------------------------
//  Reset
// --------------------------------------------------

/// Forget every recorded call and every actual count; expectations stay
/// declared (with actual counts back at 0) so a test can reuse the mock.
/// Params: m - the mock to reset.
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(expectations).
pub fn mock_reset(m: &mut Mock) {
  m.call_names = Vec[Str].new();
  m.call_args = Vec[Str].new();
  m.unexpected_names = Vec[Str].new();
  m.unexpected_args = Vec[Str].new();
  var i = 0;
  let n = _expect_count(m);
  while i < n {
    m.actual[i] = 0;
    i = i + 1;
  }
}

/// Forget everything: expectations and recorded calls. The mock becomes
/// equivalent to a fresh mock_new().
/// Params: m - the mock to clear.
/// Returns: nothing.
/// Error case: none.
/// Complexity: O(1).
pub fn mock_clear(m: &mut Mock) {
  m.names = Vec[Str].new();
  m.modes = Vec[Int].new();
  m.expected = Vec[Int].new();
  m.actual = Vec[Int].new();
  m.call_names = Vec[Str].new();
  m.call_args = Vec[Str].new();
  m.unexpected_names = Vec[Str].new();
  m.unexpected_args = Vec[Str].new();
}
