// XIOM -- xiom.libpq: PostgreSQL client library bindings (dynamic loader).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: dynamic loader path (same pattern as xiom.odbc / xiom.glfw). The
// package does NOT link libpq at build time and needs no headers: constants
// are declared locally, `pq_load` resolves `libpq.dll` through `xiom.ffi.dl`,
// and every call is an fn-pointer cast inside this single module -- the ONLY
// module in the package with `unsafe` (G5).
//
// Classification:
//   PQ_LOAD_ABSENT -> client library missing -> SKIP (CI stays green)
//   PQ_LOAD_ABI    -> entry points missing -> FAIL
//   PQ_PROBE_FAILED -> exported API present but behaved unexpectedly -> FAIL
//
// Coverage (pilot): library version (connection-free) plus a connection-error
// probe against 127.0.0.1:<closed port> -- proves the real connect/status/
// error paths without requiring a PostgreSQL server.  Successful queries and
// result-set access are Phase 2 (ROADMAP.md).
//
// G2 pin (SPEC.md): soname `libpq.dll` + resolved entry-point set + local
// sample DLL(s) + upstream PostgreSQL provenance.

module xiom.libpq

use xiom.ffi.dl;

// =========================================================================
// Identity and constants (PostgreSQL libpq; declared locally)
// =========================================================================

pub const PQ_SONAME: Str = "libpq.dll";

pub const CONNECTION_OK: Int = 0;
pub const CONNECTION_BAD: Int = 1;

pub const PGRES_EMPTY_QUERY: Int = 0;
pub const PGRES_COMMAND_OK: Int = 1;
pub const PGRES_TUPLES_OK: Int = 2;

pub const PQ_LOAD_ABSENT: Int = 0;    // client library missing -> SKIP
pub const PQ_LOAD_ABI: Int = 1;       // entry points missing -> FAIL
pub const PQ_PROBE_FAILED: Int = 2;   // API present but unexpected behaviour -> FAIL

pub type PqLoadError = {
  kind: Int;
  message: Str;
}

pub type PqInfo = {
  lib_version: Int;
  connect_status: Int;
  connect_error: Str;
}

/// A loaded libpq.  Owned by the caller; release with `pq_close`.
pub type PqLibrary = {
  handle: Int;
  p_libversion: Int;
  p_connectdb: Int;
  p_status: Int;
  p_errormsg: Int;
  p_finish: Int;
  p_exec: Int;
  p_result_status: Int;
  p_ntuples: Int;
  p_nfields: Int;
  p_fname: Int;
  p_getvalue: Int;
  p_getisnull: Int;
  p_clear: Int;
}

// =========================================================================
// Loader
// =========================================================================

/// Load an explicitly named client library (bogus names exercise the
/// ABSENT/SKIP classification deterministically on any host).
/// Complexity: O(symbols).
pub fn pq_load_named(soname: Str) -> Result[PqLibrary, PqLoadError]
  requires: soname.len() > 0
{
  let h = dl.dl_open(soname);
  if !h.is_ok {
    return Err(PqLoadError{ kind: PQ_LOAD_ABSENT; message: h.error });
  }
  let handle: Int = h.value;

  let a1 = dl.dl_sym(handle, "PQlibVersion");
  if !a1.is_ok { var ig = dl.dl_close(handle); return Err(PqLoadError{ kind: PQ_LOAD_ABI; message: "PQlibVersion: " + a1.error }); }
  let a2 = dl.dl_sym(handle, "PQconnectdb");
  if !a2.is_ok { var ig = dl.dl_close(handle); return Err(PqLoadError{ kind: PQ_LOAD_ABI; message: "PQconnectdb: " + a2.error }); }
  let a3 = dl.dl_sym(handle, "PQstatus");
  if !a3.is_ok { var ig = dl.dl_close(handle); return Err(PqLoadError{ kind: PQ_LOAD_ABI; message: "PQstatus: " + a3.error }); }
  let a4 = dl.dl_sym(handle, "PQerrorMessage");
  if !a4.is_ok { var ig = dl.dl_close(handle); return Err(PqLoadError{ kind: PQ_LOAD_ABI; message: "PQerrorMessage: " + a4.error }); }
  let a5 = dl.dl_sym(handle, "PQfinish");
  if !a5.is_ok { var ig = dl.dl_close(handle); return Err(PqLoadError{ kind: PQ_LOAD_ABI; message: "PQfinish: " + a5.error }); }
  let a6 = dl.dl_sym(handle, "PQexec");
  if !a6.is_ok { var ig = dl.dl_close(handle); return Err(PqLoadError{ kind: PQ_LOAD_ABI; message: "PQexec: " + a6.error }); }
  let a7 = dl.dl_sym(handle, "PQresultStatus");
  if !a7.is_ok { var ig = dl.dl_close(handle); return Err(PqLoadError{ kind: PQ_LOAD_ABI; message: "PQresultStatus: " + a7.error }); }
  let a8 = dl.dl_sym(handle, "PQntuples");
  if !a8.is_ok { var ig = dl.dl_close(handle); return Err(PqLoadError{ kind: PQ_LOAD_ABI; message: "PQntuples: " + a8.error }); }
  let a9 = dl.dl_sym(handle, "PQnfields");
  if !a9.is_ok { var ig = dl.dl_close(handle); return Err(PqLoadError{ kind: PQ_LOAD_ABI; message: "PQnfields: " + a9.error }); }
  let a10 = dl.dl_sym(handle, "PQfname");
  if !a10.is_ok { var ig = dl.dl_close(handle); return Err(PqLoadError{ kind: PQ_LOAD_ABI; message: "PQfname: " + a10.error }); }
  let a11 = dl.dl_sym(handle, "PQgetvalue");
  if !a11.is_ok { var ig = dl.dl_close(handle); return Err(PqLoadError{ kind: PQ_LOAD_ABI; message: "PQgetvalue: " + a11.error }); }
  let a12 = dl.dl_sym(handle, "PQgetisnull");
  if !a12.is_ok { var ig = dl.dl_close(handle); return Err(PqLoadError{ kind: PQ_LOAD_ABI; message: "PQgetisnull: " + a12.error }); }
  let a13 = dl.dl_sym(handle, "PQclear");
  if !a13.is_ok { var ig = dl.dl_close(handle); return Err(PqLoadError{ kind: PQ_LOAD_ABI; message: "PQclear: " + a13.error }); }

  return Ok(PqLibrary{
    handle: handle,
    p_libversion: a1.value,
    p_connectdb: a2.value,
    p_status: a3.value,
    p_errormsg: a4.value,
    p_finish: a5.value,
    p_exec: a6.value,
    p_result_status: a7.value,
    p_ntuples: a8.value,
    p_nfields: a9.value,
    p_fname: a10.value,
    p_getvalue: a11.value,
    p_getisnull: a12.value,
    p_clear: a13.value,
  });
}

/// Load the default client library (`libpq.dll`).
/// Complexity: O(symbols).
pub fn pq_load() -> Result[PqLibrary, PqLoadError]
  requires: true
{
  return pq_load_named(PQ_SONAME);
}

/// Release the client-library handle.
/// Complexity: O(1).
pub fn pq_close(lib: &PqLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return dl.dl_close(lib.handle);
}

// =========================================================================
// Probe
// =========================================================================

/// Connection-free library version (e.g. 130011 for PostgreSQL 13.11).
/// Complexity: O(1).
pub fn pq_libversion(lib: &PqLibrary) -> Int
  requires: lib.handle != 0
{
  unsafe {
    let f = lib.p_libversion as fn() -> Int32;
    return f() as Int;
  }
}

/// Connect to `conninfo` and report the status + error text, then close the
/// connection.  Used by the suite against a closed port to prove the real
/// connect/status/error path without a server.
/// Complexity: O(connect attempt).
pub fn pq_connect_report(lib: &PqLibrary, conninfo: Str) -> Result[PqInfo, Str]
  requires: lib.handle != 0
  requires: conninfo.len() > 0
{
  unsafe {
    let f_connectdb = lib.p_connectdb as fn(*UInt8) -> Int;
    let f_status = lib.p_status as fn(Int) -> Int32;
    let f_errormsg = lib.p_errormsg as fn(Int) -> *UInt8;
    let f_finish = lib.p_finish as fn(Int);

    let version = pq_libversion(lib);
    let conn = f_connectdb(conninfo.c_str());
    if conn == 0 {
      return Err("libpq: PQconnectdb returned a null connection");
    }
    let status = f_status(conn) as Int;

    var errtext = "";
    let p = f_errormsg(conn);
    if (p as Int) != 0 {
      errtext = Str::from_c_str(p);
    }
    f_finish(conn);

    return Ok(PqInfo{
      lib_version: version,
      connect_status: status,
      connect_error: errtext,
    });
  }
}

/// Default probe: version + a connection attempt against a closed local port
/// (`connect_timeout=2` keeps it bounded; nothing listens on port 1).
/// Complexity: O(connect attempt).
pub fn pq_probe(lib: &PqLibrary) -> Result[PqInfo, Str]
  requires: lib.handle != 0
{
  return pq_connect_report(lib, "host=127.0.0.1 port=1 dbname=xiom_probe user=xiom_probe connect_timeout=2");
}

/// Load the default library and run `pq_probe`; returns the probe result and
/// closes the library.
/// Complexity: O(connect attempt).
pub fn pq_probe_default() -> Result[PqInfo, PqLoadError]
  requires: true
{
  let l = pq_load();
  if !l.is_ok {
    return Err(l.error);
  }
  let lib: PqLibrary = l.value;
  let p = pq_probe(&lib);
  let cl = pq_close(&lib);
  if !p.is_ok {
    return Err(PqLoadError{ kind: PQ_PROBE_FAILED; message: p.error });
  }
  if !cl.is_ok {
    return Err(PqLoadError{ kind: PQ_PROBE_FAILED; message: cl.error });
  }
  return Ok(p.value);
}
