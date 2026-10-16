// XIOM -- xiom.android-sys: libicu head (A12 text surface) -- DECLARED
// SUBSET BY DESIGN.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: runtime-load unit for the declared ICU subset (NDK r27b
// unicode/ustring.h + uchar.h + utypes.h, ICU 75.1), backed by the
// self-contained bridge `src/icu_bridge.c`.  UTF-16 crossings are
// little-endian byte slots owned by the caller (B-series discipline).
//
//   declared subset (6 symbols, all __INTRODUCED_IN(31) in the NDK)
//     u_errorName, u_strlen, u_strToUTF8, u_strFromUTF8, u_toupper,
//     u_tolower
//
// SONAME NOTE: Android ships the ICU C API as libandroidicu.so (the
// soname the NDK -licuuc alias resolves to); libicuuc.so carries the C++
// ICU API only.  The loader targets libandroidicu.so and reports the
// declared subset resolution explicitly.
//
// SUBSET POLICY (honest claim for owners/engines): this module proves
// the platform UTF-8/UTF-16 text plumbing (decode, encode, length,
// simple case mapping) -- it is NOT a collation/formatting/break-
// iteration binding.  The rest of the ICU C API is a documented delta
// (SPEC.md).  Because the NDK marks the whole declared subset API 31+,
// pre-31 platforms classify ICU_GATED: an explicit SKIP with the missing
// names recorded -- never a silent skip and never a false FAIL.
//
// Classification (the suite maps it to markers):
//   ICU_LOAD_ABSENT -> SKIP   (runtime missing; CI stays green)
//   ICU_GATED       -> SKIP   (present, subset version-gated; names shown)
//   ICU_OK          -> live checks (UTF roundtrip + case mapping)
//   ICU_CALL        -> Err    (live call failure, UErrorCode named)

module xiom.android_sys.icu

use xiom.android_sys;

extern "C" {
  fn xic_load_named(soname: *UInt8) -> Int32;
  fn xic_load() -> Int32;
  fn xic_error() -> *UInt8;
  fn xic_declared_total() -> Int32;
  fn xic_required_missing_count() -> Int32;
  fn xic_required_missing() -> *UInt8;
  fn xic_optional_missing_count() -> Int32;
  fn xic_optional_missing() -> *UInt8;
  fn xic_error_name(code: Int32) -> *UInt8;
  fn xic_strlen(units_le: *UInt8, unit_count: Int32) -> Int32;
  fn xic_utf8_to_utf16(text: *UInt8, out: *UInt8, out_cap: Int32, size_slot: *UInt8) -> Int32;
  fn xic_utf16_to_utf8(units_le: *UInt8, unit_count: Int32, out: *UInt8, out_cap: Int32, size_slot: *UInt8) -> Int32;
  fn xic_toupper(cp: Int32) -> Int32;
  fn xic_tolower(cp: Int32) -> Int32;
  fn xic_unload();
}

// =========================================================================
// Identity and classification
// =========================================================================

pub const ICU_SONAME: Str = "libandroidicu.so";

pub const ICU_LOAD_ABSENT: Int = 0; // runtime lib missing -> SKIP
pub const ICU_GATED: Int = 1;       // subset version-gated (API 31+) -> SKIP + names
pub const ICU_CALL: Int = 2;        // live call failed (UErrorCode named)

pub type IcuRuntime = {
  declared_total: Int;             // declared subset size (6 at r27b)
  required_missing: Int;           // gated symbols unresolved (0 = live path)
  required_missing_names: Str;
  optional_missing: Int;           // opportunistic symbols unresolved
  optional_missing_names: Str;
}

// =========================================================================
// UErrorCode (unicode/utypes.h, ICU 75.1) -- the subset-relevant values
// =========================================================================

pub const U_ZERO_ERROR: Int = 0;
pub const U_ILLEGAL_ARGUMENT_ERROR: Int = 1;
pub const U_INVALID_CHAR_FOUND: Int = 10;
pub const U_TRUNCATED_CHAR_FOUND: Int = 11;
pub const U_ILLEGAL_CHAR_FOUND: Int = 12;
pub const U_BUFFER_OVERFLOW_ERROR: Int = 15;
pub const U_STRING_NOT_TERMINATED_WARNING: Int = -124;

/// Human name of a UErrorCode value (u_errorName; e.g.
/// "U_ZERO_ERROR").  Empty string when the symbol is unresolved.
/// Complexity: O(1).
pub fn icu_error_name(code: Int) -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xic_error_name(code as Int32)); }
}

// =========================================================================
// Internal slot helpers
// =========================================================================

fn _ic_zeros(n: Int) -> Vec[UInt8] {
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn _ic_u64_le(buf: &Vec[UInt8], pos: Int) -> Int {
  var v: Int = 0;
  var shift: Int = 1;
  var i = 0;
  while i < 8 {
    v = v + ((buf[pos + i] as Int) & 255) * shift;
    shift = shift * 256;
    i = i + 1;
  }
  return v;
}

fn _ic_append(dst: &mut Vec[UInt8], src: &Vec[UInt8], n: Int) {
  var i = 0;
  while i < n && i < src.len() {
    dst.push(src[i]);
    i = i + 1;
  }
}

// =========================================================================
// Probe API
// =========================================================================

/// Probe an explicitly named ICU runtime (bogus names exercise the
/// ABSENT/SKIP classification deterministically).  A present library with
/// an incomplete required subset reports Ok with the missing counts --
/// callers classify GATED off it (the suite maps that to SKIP + names).
/// Complexity: O(load + declared set).
pub fn icu_probe_named(soname: Str) -> Result[IcuRuntime, AndroidSysError]
  requires: soname.len() > 0
{
  let rc = unsafe { xic_load_named(soname.c_str()) as Int };
  if rc != 0 {
    let msg = unsafe { Str::from_c_str(xic_error()) };
    return Err(AndroidSysError{ kind: ANDROID_SYS_LOAD_ABSENT, errno_code: 0, message: msg });
  }
  let total = unsafe { xic_declared_total() as Int };
  let req_missing = unsafe { xic_required_missing_count() as Int };
  let req_names = unsafe { Str::from_c_str(xic_required_missing()) };
  let opt_missing = unsafe { xic_optional_missing_count() as Int };
  let opt_names = unsafe { Str::from_c_str(xic_optional_missing()) };
  return Ok(IcuRuntime{
    declared_total: total,
    required_missing: req_missing,
    required_missing_names: req_names,
    optional_missing: opt_missing,
    optional_missing_names: opt_names,
  });
}

/// Probe the default ICU runtime (libandroidicu.so).  On Windows the
/// probe classifies ABSENT (SKIP).
/// Complexity: O(load + declared set).
pub fn icu_probe() -> Result[IcuRuntime, AndroidSysError]
  requires: true
{
  return icu_probe_named(ICU_SONAME);
}

/// The last bridge error summary (empty when clean).
/// Complexity: O(1).
pub fn icu_error() -> Str
  requires: true
{
  unsafe { return Str::from_c_str(xic_error()); }
}

/// Release any runtime handles held by the bridge.  Safe when nothing is
/// loaded.
/// Complexity: O(1).
pub fn icu_unload()
  requires: true
{
  unsafe { xic_unload(); }
}

// =========================================================================
// Declared subset (u_strlen / u_strToUTF8 / u_strFromUTF8 /
// u_toupper / u_tolower)
// =========================================================================

/// Length in UTF-16 code units of an owned LE u16 slot (u_strlen; the
/// bridge NUL-terminates a scratch copy, so embedded terminators end the
/// count).  u_strlen is an OPTIONAL subset symbol: the NDK header
/// announces it but the API-36 platform shim does not export it (dynsym
/// evidence in docs/repro/android-sys-probe) -> Err(ICU_GATED, reason)
/// when unavailable; never a faked count.
/// Complexity: O(units).
pub fn icu_utf16_length(units: &mut Vec[UInt8]) -> Result[Int, AndroidSysError]
  requires: units.len() % 2 == 0
{
  let n = unsafe { xic_strlen(units.as_mut_ptr(), (units.len() / 2) as Int32) as Int };
  if n == -2 {
    return Err(AndroidSysError{ kind: ICU_GATED, errno_code: 0, message: icu_error() });
  }
  if n < 0 {
    return Err(AndroidSysError{ kind: ICU_CALL, errno_code: 0, message: icu_error() });
  }
  return Ok(n);
}

/// Decode UTF-8 `text` into an owned UTF-16 LE byte slot
/// (u_strFromUTF8).  Ok(units) with units.len()/2 code units.
/// Complexity: O(text).
pub fn icu_utf8_to_utf16(text: Str) -> Result[Vec[UInt8], AndroidSysError]
  requires: text.len() > 0
{
  let cap = text.len() * 4 + 2;
  var dst = _ic_zeros(cap);
  var slot = _ic_zeros(8);
  let rc = unsafe {
    xic_utf8_to_utf16(text.c_str(), dst.as_mut_ptr(), cap as Int32, slot.as_mut_ptr()) as Int
  };
  if rc == -2 {
    return Err(AndroidSysError{ kind: ICU_GATED, errno_code: 0, message: icu_error() });
  }
  if rc != 0 {
    return Err(AndroidSysError{ kind: ICU_CALL, errno_code: 0, message: icu_error() });
  }
  let n = _ic_u64_le(&slot, 0);
  var out: Vec[UInt8] = Vec[UInt8].new();
  _ic_append(&mut out, &dst, n);
  return Ok(out);
}

/// Encode an owned UTF-16 LE byte slot back to UTF-8 (u_strToUTF8).
/// Ok(text) with the NUL-terminated payload decoded.
/// Complexity: O(units).
pub fn icu_utf16_to_utf8(units: &mut Vec[UInt8]) -> Result[Str, AndroidSysError]
  requires: units.len() % 2 == 0
{
  let cap = units.len() * 3 + 4;
  var dst = _ic_zeros(cap);
  var slot = _ic_zeros(8);
  let rc = unsafe {
    xic_utf16_to_utf8(units.as_mut_ptr(), (units.len() / 2) as Int32, dst.as_mut_ptr(), cap as Int32, slot.as_mut_ptr()) as Int
  };
  if rc == -2 {
    return Err(AndroidSysError{ kind: ICU_GATED, errno_code: 0, message: icu_error() });
  }
  if rc != 0 {
    return Err(AndroidSysError{ kind: ICU_CALL, errno_code: 0, message: icu_error() });
  }
  let n = _ic_u64_le(&slot, 0);
  var out: Vec[UInt8] = Vec[UInt8].new();
  _ic_append(&mut out, &dst, n);
  return Ok(Str::from_utf8(out));
}

/// Simple uppercase mapping of a code point (u_toupper).
/// Complexity: O(1).
pub fn icu_toupper(cp: Int) -> Result[Int, AndroidSysError]
  requires: cp >= 0
{
  let rc = unsafe { xic_toupper(cp as Int32) as Int };
  if rc == -2 {
    return Err(AndroidSysError{ kind: ICU_GATED, errno_code: 0, message: icu_error() });
  }
  return Ok(rc);
}

/// Simple lowercase mapping of a code point (u_tolower).
/// Complexity: O(1).
pub fn icu_tolower(cp: Int) -> Result[Int, AndroidSysError]
  requires: cp >= 0
{
  let rc = unsafe { xic_tolower(cp as Int32) as Int };
  if rc == -2 {
    return Err(AndroidSysError{ kind: ICU_GATED, errno_code: 0, message: icu_error() });
  }
  return Ok(rc);
}
