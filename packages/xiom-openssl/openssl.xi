// XIOM -- xiom.openssl: OpenSSL (libcrypto) bindings via dynamic loader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN DECISION (crypto/media sector): **system-library path**, not
// vendored. OpenSSL's source tree is far too large/configuration-heavy to
// vendor into a package, while libcrypto builds are ubiquitous on Windows
// (Git for Windows, Python, many apps). The loader tries the common OpenSSL
// 3.x / 1.1.x sonames in order and the suite reports SKIP when none is
// present, so CI without OpenSSL stays green.
//
// All XIOM `unsafe`/`extern` live in this single module (G5); every call is
// an fn-pointer cast over `xiom.ffi.dl`.
//
// Classification:
//   OSSL_LOAD_ABSENT  -> no candidate soname loaded -> SKIP
//   OSSL_LOAD_ABI     -> a candidate loaded but entry points are missing -> FAIL
//   OSSL_PROBE_FAILED -> API present but behaved unexpectedly -> FAIL
//
// Coverage (pilot): version string + packed version number, a real SHA-256
// functional check (SHA256 of "abc" compared against the published digest),
// and a CSPRNG call (RAND_bytes).  TLS contexts/BIOs/EVP and the certificate
// surface are Phase 2 (ROADMAP.md).
//
// G2 pin (SPEC.md): candidate soname list + entry-point set + local samples
// (Git 3.2.4 / DaVinci 1.1.1n / Python 1.1.1g) + upstream OpenSSL
// (Apache-2.0; nothing vendored).

module xiom.openssl

use xiom.ffi.dl;

// =========================================================================
// Identity and candidate sonames
// =========================================================================

pub const OSSL_VERSION_TYPE_OPENSSL: Int = 0; // OPENSSL_VERSION

pub const OSSL_LOAD_ABSENT: Int = 0;    // no candidate loaded -> SKIP
pub const OSSL_LOAD_ABI: Int = 1;       // entry points missing -> FAIL
pub const OSSL_PROBE_FAILED: Int = 2;   // API behaved unexpectedly -> FAIL

pub type OsslLoadError = {
  kind: Int;
  message: Str;
}

pub type OsslInfo = {
  version: Str;
  version_num: Int;
  sha256_ok: Bool;
  rand_ok: Bool;
}

/// A loaded libcrypto.  Owned by the caller; release with `ossl_close`.
pub type OsslLibrary = {
  handle: Int;
  soname: Str;
  p_version: Int;
  p_version_num: Int;
  p_sha256: Int;
  p_rand_bytes: Int;
}

// =========================================================================
// Slot helpers (XIOM-owned out-buffers; no malloc/free in confined blocks)
// =========================================================================

fn slot_new(n: Int) -> Vec[UInt8]
  requires: n > 0
  requires: n <= 256
{
  var s: Vec[UInt8] = Vec[UInt8].new();
  var i: Int = 0;
  while i < n {
    s.push(0 as UInt8);
    i = i + 1;
  }
  return s;
}

fn read_u64_le(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: off + 7 < buf.len()
{
  let b0 = buf[off] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  let b4 = buf[off + 4] as Int;
  let b5 = buf[off + 5] as Int;
  let b6 = buf[off + 6] as Int;
  let b7 = buf[off + 7] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
       | (b4 << 32) | (b5 << 40) | (b6 << 48) | (b7 << 56);
}

// =========================================================================
// Loader (multi-soname)
// =========================================================================

fn try_load(soname: Str) -> Result[OsslLibrary, OsslLoadError]
  requires: soname.len() > 0
{
  let h = dl.dl_open(soname);
  if !h.is_ok {
    // Not this candidate: report ABSENT so the caller can try the next one.
    return Err(OsslLoadError{ kind: OSSL_LOAD_ABSENT; message: h.error });
  }
  let handle: Int = h.value;

  let a1 = dl.dl_sym(handle, "OpenSSL_version");
  if !a1.is_ok { var ig = dl.dl_close(handle); return Err(OsslLoadError{ kind: OSSL_LOAD_ABI; message: "OpenSSL_version: " + a1.error }); }
  let a2 = dl.dl_sym(handle, "OpenSSL_version_num");
  if !a2.is_ok { var ig = dl.dl_close(handle); return Err(OsslLoadError{ kind: OSSL_LOAD_ABI; message: "OpenSSL_version_num: " + a2.error }); }
  let a3 = dl.dl_sym(handle, "SHA256");
  if !a3.is_ok { var ig = dl.dl_close(handle); return Err(OsslLoadError{ kind: OSSL_LOAD_ABI; message: "SHA256: " + a3.error }); }
  let a4 = dl.dl_sym(handle, "RAND_bytes");
  if !a4.is_ok { var ig = dl.dl_close(handle); return Err(OsslLoadError{ kind: OSSL_LOAD_ABI; message: "RAND_bytes: " + a4.error }); }

  return Ok(OsslLibrary{
    handle: handle,
    soname: soname,
    p_version: a1.value,
    p_version_num: a2.value,
    p_sha256: a3.value,
    p_rand_bytes: a4.value,
  });
}

/// Load an explicitly named libcrypto build (bogus names exercise the
/// ABSENT/SKIP classification deterministically on any host).
/// Complexity: O(symbols).
pub fn ossl_load_named(soname: Str) -> Result[OsslLibrary, OsslLoadError]
  requires: soname.len() > 0
{
  return try_load(soname);
}

/// Load the first available libcrypto from the common Windows sonames:
/// OpenSSL 3.x (`libcrypto-3-x64.dll`), 1.1.x (`libcrypto-1_1-x64.dll`,
/// `libcrypto-1_1.dll`), and the unversioned `libcrypto.dll`.
/// Complexity: O(candidates * symbols).
pub fn ossl_load() -> Result[OsslLibrary, OsslLoadError]
  requires: true
{
  let c1 = try_load("libcrypto-3-x64.dll");
  if c1.is_ok { return Ok(c1.value); }
  if c1.error.kind == OSSL_LOAD_ABI { return Err(c1.error); }

  let c2 = try_load("libcrypto-1_1-x64.dll");
  if c2.is_ok { return Ok(c2.value); }
  if c2.error.kind == OSSL_LOAD_ABI { return Err(c2.error); }

  let c3 = try_load("libcrypto-1_1.dll");
  if c3.is_ok { return Ok(c3.value); }
  if c3.error.kind == OSSL_LOAD_ABI { return Err(c3.error); }

  let c4 = try_load("libcrypto.dll");
  if c4.is_ok { return Ok(c4.value); }
  if c4.error.kind == OSSL_LOAD_ABI { return Err(c4.error); }

  return Err(OsslLoadError{
    kind: OSSL_LOAD_ABSENT;
    message: "openssl: no libcrypto candidate found (tried 3-x64, 1_1-x64, 1_1, unversioned)",
  });
}

/// Release the library handle.
/// Complexity: O(1).
pub fn ossl_close(lib: &OsslLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
{
  return dl.dl_close(lib.handle);
}

// =========================================================================
// Probe
// =========================================================================

/// Version strings + SHA-256("abc") against the published digest +
/// RAND_bytes liveness.  The SHA-256 check is the functional proof: a wrong
/// or corrupted build fails it.
/// Complexity: O(1).
pub fn ossl_probe(lib: &OsslLibrary) -> Result[OsslInfo, Str]
  requires: lib.handle != 0
{
  unsafe {
    let f_version = lib.p_version as fn(Int) -> *UInt8;
    let f_version_num = lib.p_version_num as fn() -> UInt32;
    let f_sha256 = lib.p_sha256 as fn(*UInt8, Int, *UInt8) -> Int;
    let f_rand = lib.p_rand_bytes as fn(*UInt8, Int) -> Int32;

    var version = "";
    let vp = f_version(OSSL_VERSION_TYPE_OPENSSL);
    if (vp as Int) != 0 {
      version = Str::from_c_str(vp);
    }
    let version_num = f_version_num() as Int;

    /* SHA-256("abc") = ba7816bf 8f01cfea 414140de 5dae2223
     *                  b00361a3 96177a9c b410ff61 f20015ad
     * read as four little-endian u64 words. */
    let src = "abc";
    var md = slot_new(32);
    var ig1 = f_sha256(src.c_str(), 3, md.as_mut_ptr());
    var sha_ok = true;
    if read_u64_le(&md, 0) != -1527000031757436742 { sha_ok = false; }
    if read_u64_le(&md, 8) != 2531777658719584577 { sha_ok = false; }
    if read_u64_le(&md, 16) != -7171393520880516176 { sha_ok = false; }
    if read_u64_le(&md, 24) != -5974868289610903372 { sha_ok = false; }

    var rb = slot_new(16);
    let rand_rc = f_rand(rb.as_mut_ptr(), 16) as Int;

    return Ok(OsslInfo{
      version: version,
      version_num: version_num,
      sha256_ok: sha_ok,
      rand_ok: rand_rc == 1,
    });
  }
}

/// Load an explicitly named build and run `ossl_probe`.
/// Complexity: O(symbols + probe).
pub fn ossl_probe_named(soname: Str) -> Result[OsslInfo, OsslLoadError]
  requires: soname.len() > 0
{
  let l = ossl_load_named(soname);
  if !l.is_ok {
    return Err(l.error);
  }
  let lib: OsslLibrary = l.value;
  let p = ossl_probe(&lib);
  let cl = ossl_close(&lib);
  if !p.is_ok {
    return Err(OsslLoadError{ kind: OSSL_PROBE_FAILED; message: p.error });
  }
  if !cl.is_ok {
    return Err(OsslLoadError{ kind: OSSL_PROBE_FAILED; message: cl.error });
  }
  return Ok(p.value);
}

/// Probe the first available candidate build.
/// Complexity: O(candidates * symbols + probe).
pub fn ossl_probe_default() -> Result[OsslInfo, OsslLoadError]
  requires: true
{
  let l = ossl_load();
  if !l.is_ok {
    return Err(l.error);
  }
  let lib: OsslLibrary = l.value;
  let p = ossl_probe(&lib);
  let cl = ossl_close(&lib);
  if !p.is_ok {
    return Err(OsslLoadError{ kind: OSSL_PROBE_FAILED; message: p.error });
  }
  if !cl.is_ok {
    return Err(OsslLoadError{ kind: OSSL_PROBE_FAILED; message: cl.error });
  }
  return Ok(p.value);
}
