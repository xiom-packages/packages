// XIOM -- xiom.odbc: ODBC driver-manager capability probe (dynamic loader).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: dynamic loader path (same pattern as xiom.sdl3 / xiom.glfw). The
// package does NOT link odbc32 at build time and needs no headers: constants
// are declared locally (ODBC spec), `odbc_load` resolves `odbc32.dll` through
// `xiom.ffi.dl`, and every call is an fn-pointer cast inside this single
// module -- the ONLY module in the package with `unsafe` (G5).
//
// Classification:
//   ODBC_LOAD_ABSENT -> driver manager missing -> SKIP (CI stays green)
//   ODBC_LOAD_ABI    -> entry points missing -> FAIL
// (No device/connection stage: driver-manager info is connection-free.)
//
// Coverage (pilot): environment handle + ODBC version attribute, ODBC
// version string (SQL_ODBC_VER), driver enumeration (SQLDrivers) with a name
// head, and DSN enumeration (SQLDataSources) count.  Connection/execution
// (SQLConnect, SQLExecDirect) and diagnostics text are Phase 2 (ROADMAP.md).
//
// G2 pin (SPEC.md): soname `odbc32.dll` + resolved entry-point set + the
// ODBC constants used + local System32 DLL sample.

module xiom.odbc

use xiom.ffi.dl;

// =========================================================================
// Identity and ODBC constants (ODBC spec; declared locally)
// =========================================================================

pub const ODBC_SONAME: Str = "odbc32.dll";

pub const SQL_SUCCESS: Int = 0;
pub const SQL_SUCCESS_WITH_INFO: Int = 1;
pub const SQL_NO_DATA: Int = 100;
pub const SQL_NULL_HANDLE: Int = 0;
pub const SQL_HANDLE_ENV: Int = 1;
pub const SQL_HANDLE_DBC: Int = 2;
pub const SQL_ATTR_ODBC_VERSION: Int = 200;
pub const SQL_OV_ODBC3: Int = 3;
pub const SQL_FETCH_NEXT: Int = 1;
pub const SQL_FETCH_FIRST: Int = 2;
pub const SQL_ODBC_VER: Int = 10;

pub const ODBC_LOAD_ABSENT: Int = 0; // driver manager missing -> SKIP
pub const ODBC_LOAD_ABI: Int = 1;    // entry points missing -> FAIL

pub type OdbcLoadError = {
  kind: Int;
  message: Str;
}

pub type OdbcInfo = {
  version: Str;
  driver_count: Int;
  driver_head: Str;
  dsn_count: Int;
}

/// A loaded ODBC driver manager.  Owned by the caller; release with
/// `odbc_close`.
pub type OdbcLibrary = {
  handle: Int;
  p_alloc_handle: Int;
  p_set_env_attr: Int;
  p_drivers: Int;
  p_data_sources: Int;
  p_get_info: Int;
  p_free_handle: Int;
}

// =========================================================================
// Out-param slot helpers (XIOM-owned buffers; no malloc/free)
// =========================================================================

fn slot_new(n: Int) -> Vec[UInt8]
  requires: n > 0
  requires: n <= 512
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn read_u16_le(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 2
{
  let b0 = buf[0] as Int;
  let b1 = buf[1] as Int;
  return b0 | (b1 << 8);
}

fn read_u64_le(buf: &Vec[UInt8]) -> Int
  requires: buf.len() >= 8
{
  let b0 = buf[0] as Int;
  let b1 = buf[1] as Int;
  let b2 = buf[2] as Int;
  let b3 = buf[3] as Int;
  let b4 = buf[4] as Int;
  let b5 = buf[5] as Int;
  let b6 = buf[6] as Int;
  let b7 = buf[7] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
       | (b4 << 32) | (b5 << 40) | (b6 << 48) | (b7 << 56);
}

// =========================================================================
// Loader
// =========================================================================

/// Load an explicitly named driver manager (bogus names exercise the
/// ABSENT/SKIP classification deterministically on any host).
/// Complexity: O(symbols).
pub fn odbc_load_named(soname: Str) -> Result[OdbcLibrary, OdbcLoadError]
  requires: soname.len() > 0
{
  let h = dl.dl_open(soname);
  if !h.is_ok {
    return Err(OdbcLoadError{ kind: ODBC_LOAD_ABSENT; message: h.error });
  }
  let handle: Int = h.value;

  let a1 = dl.dl_sym(handle, "SQLAllocHandle");
  if !a1.is_ok { var ig = dl.dl_close(handle); return Err(OdbcLoadError{ kind: ODBC_LOAD_ABI; message: "SQLAllocHandle: " + a1.error }); }
  let a2 = dl.dl_sym(handle, "SQLSetEnvAttr");
  if !a2.is_ok { var ig = dl.dl_close(handle); return Err(OdbcLoadError{ kind: ODBC_LOAD_ABI; message: "SQLSetEnvAttr: " + a2.error }); }
  let a3 = dl.dl_sym(handle, "SQLDrivers");
  if !a3.is_ok { var ig = dl.dl_close(handle); return Err(OdbcLoadError{ kind: ODBC_LOAD_ABI; message: "SQLDrivers: " + a3.error }); }
  let a4 = dl.dl_sym(handle, "SQLDataSources");
  if !a4.is_ok { var ig = dl.dl_close(handle); return Err(OdbcLoadError{ kind: ODBC_LOAD_ABI; message: "SQLDataSources: " + a4.error }); }
  let a5 = dl.dl_sym(handle, "SQLGetInfo");
  if !a5.is_ok { var ig = dl.dl_close(handle); return Err(OdbcLoadError{ kind: ODBC_LOAD_ABI; message: "SQLGetInfo: " + a5.error }); }
  let a6 = dl.dl_sym(handle, "SQLFreeHandle");
  if !a6.is_ok { var ig = dl.dl_close(handle); return Err(OdbcLoadError{ kind: ODBC_LOAD_ABI; message: "SQLFreeHandle: " + a6.error }); }

  return Ok(OdbcLibrary{
    handle: handle,
    p_alloc_handle: a1.value,
    p_set_env_attr: a2.value,
    p_drivers: a3.value,
    p_data_sources: a4.value,
    p_get_info: a5.value,
    p_free_handle: a6.value,
  });
}

/// Load the default driver manager (`odbc32.dll`).
/// Complexity: O(symbols).
pub fn odbc_load() -> Result[OdbcLibrary, OdbcLoadError]
  requires: true
{
  return odbc_load_named(ODBC_SONAME);
}

/// Release the driver-manager handle.
/// Complexity: O(1).
pub fn odbc_close(lib: &OdbcLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return dl.dl_close(lib.handle);
}

// =========================================================================
// Probe
// =========================================================================

/// Probe the driver manager: ODBC version string, installed-driver count +
/// name head, and configured-DSN count.
/// Complexity: O(drivers + DSNs).
pub fn odbc_probe(lib: &OdbcLibrary) -> Result[OdbcInfo, Str]
  requires: lib.handle != 0
{
  unsafe {
    let f_alloc = lib.p_alloc_handle as fn(Int, Int, *UInt8) -> Int32;
    let f_setenv = lib.p_set_env_attr as fn(Int, Int, Int, Int) -> Int32;
    let f_getinfo = lib.p_get_info as fn(Int, Int, *UInt8, Int, *UInt8) -> Int32;
    let f_drivers = lib.p_drivers as fn(Int, Int, *UInt8, Int, *UInt8, *UInt8, Int, *UInt8) -> Int32;
    let f_datasrc = lib.p_data_sources as fn(Int, Int, *UInt8, Int, *UInt8, *UInt8, Int, *UInt8) -> Int32;
    let f_freeh = lib.p_free_handle as fn(Int, Int) -> Int32;

    var henv_slot = slot_new(8);
    let rc1 = f_alloc(SQL_HANDLE_ENV, SQL_NULL_HANDLE, henv_slot.as_mut_ptr());
    if rc1 != 0 && rc1 != 1 {
      return Err("odbc: SQLAllocHandle(ENV) rc=" + int_to_str(rc1 as Int));
    }
    let henv = read_u64_le(&henv_slot);

    let rc2 = f_setenv(henv, SQL_ATTR_ODBC_VERSION, SQL_OV_ODBC3, 0);
    if rc2 != 0 && rc2 != 1 {
      var ig1 = f_freeh(SQL_HANDLE_ENV, henv);
      return Err("odbc: SQLSetEnvAttr(ODBC3) rc=" + int_to_str(rc2 as Int));
    }

    var hdbc_slot = slot_new(8);
    let rc3 = f_alloc(SQL_HANDLE_DBC, henv, hdbc_slot.as_mut_ptr());
    if rc3 != 0 && rc3 != 1 {
      var ig2 = f_freeh(SQL_HANDLE_ENV, henv);
      return Err("odbc: SQLAllocHandle(DBC) rc=" + int_to_str(rc3 as Int));
    }
    let hdbc = read_u64_le(&hdbc_slot);

    // ODBC driver-manager version string (connection-free info type).
    var version = "";
    var vbuf = slot_new(256);
    var vlen = slot_new(2);
    let rc4 = f_getinfo(hdbc, SQL_ODBC_VER, vbuf.as_mut_ptr(), 256, vlen.as_mut_ptr());
    if rc4 == 0 || rc4 == 1 {
      version = Str::from_c_str(vbuf.as_mut_ptr());
    }

    // Driver enumeration (SQLDrivers is environment-scoped).
    var dbuf = slot_new(256);
    var dlen = slot_new(2);
    var abuf = slot_new(256);
    var alen = slot_new(2);
    var count = 0;
    var head = "";
    var direction = SQL_FETCH_FIRST;
    var looping = true;
    while looping {
      let rc5 = f_drivers(henv, direction, dbuf.as_mut_ptr(), 256, dlen.as_mut_ptr(), abuf.as_mut_ptr(), 256, alen.as_mut_ptr());
      if rc5 == SQL_NO_DATA {
        looping = false;
      } elif rc5 != 0 && rc5 != 1 {
        var ig3 = f_freeh(SQL_HANDLE_DBC, hdbc);
        var ig4 = f_freeh(SQL_HANDLE_ENV, henv);
        return Err("odbc: SQLDrivers rc=" + int_to_str(rc5 as Int));
      } else {
        count = count + 1;
        if count <= 3 {
          if head.len() > 0 { head = head + ", "; }
          head = head + Str::from_c_str(dbuf.as_mut_ptr());
        }
        direction = SQL_FETCH_NEXT;
        if count >= 64 { looping = false; }
      }
    }

    // Configured DSNs (usually zero on developer machines; still reported).
    var sbuf = slot_new(256);
    var slen = slot_new(2);
    var dsc = slot_new(256);
    var dsc2 = slot_new(2);
    var dsn_count = 0;
    var dir2 = SQL_FETCH_FIRST;
    var looping2 = true;
    while looping2 {
      let rc6 = f_datasrc(henv, dir2, sbuf.as_mut_ptr(), 256, slen.as_mut_ptr(), dsc.as_mut_ptr(), 256, dsc2.as_mut_ptr());
      if rc6 == SQL_NO_DATA {
        looping2 = false;
      } elif rc6 != 0 && rc6 != 1 {
        looping2 = false;
      } else {
        dsn_count = dsn_count + 1;
        dir2 = SQL_FETCH_NEXT;
        if dsn_count >= 256 { looping2 = false; }
      }
    }

    var ig5 = f_freeh(SQL_HANDLE_DBC, hdbc);
    var ig6 = f_freeh(SQL_HANDLE_ENV, henv);

    return Ok(OdbcInfo{
      version: version,
      driver_count: count,
      driver_head: head,
      dsn_count: dsn_count,
    });
  }
}

/// Probe an explicitly named driver manager.
/// Complexity: O(drivers + DSNs).
pub fn odbc_probe_named(soname: Str) -> Result[OdbcInfo, OdbcLoadError]
  requires: soname.len() > 0
{
  let l = odbc_load_named(soname);
  if !l.is_ok {
    return Err(l.error);
  }
  let lib: OdbcLibrary = l.value;
  let p = odbc_probe(&lib);
  let cl = odbc_close(&lib);
  if !p.is_ok {
    // Probe failures on a loaded manager are reported as ABI-level errors:
    // the exports exist but the manager refused the basic calls.
    return Err(OdbcLoadError{ kind: ODBC_LOAD_ABI; message: p.error });
  }
  if !cl.is_ok {
    return Err(OdbcLoadError{ kind: ODBC_LOAD_ABI; message: cl.error });
  }
  return Ok(p.value);
}

/// Probe the default driver manager (`odbc32.dll`).
/// Complexity: O(drivers + DSNs).
pub fn odbc_probe_default() -> Result[OdbcInfo, OdbcLoadError]
  requires: true
{
  return odbc_probe_named(ODBC_SONAME);
}


// Local integer-to-string (stdlib convert.to_string must not be called inside
// the confined block: intermediate Str values can alias stale arena memory
// -- same workaround as the sqlite FFI module).
fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  if neg { return "-" + out; }
  return out;
}