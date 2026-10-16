// XIOM -- xiom.ssl: libssl-class TLS context bindings via dynamic loader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN DECISION (crypto/network sector): **system-library path**, not
// vendored -- the xiom.openssl pattern applied to libssl. OpenSSL's source
// tree is far too large and configuration-heavy to vendor, while libssl
// builds are ubiquitous on Windows (Git for Windows ships libssl-3-x64.dll
// beside libcrypto-3-x64.dll). The loader tries the common sonames in
// order and the suite reports SKIP when none is present, so CI without
// OpenSSL stays green.
//
// All XIOM `unsafe`/`extern` live in this single module (G5); every call is
// an fn-pointer cast over `xiom.ffi.dl`, exactly like xiom.openssl.
// Out-parameters are XIOM-owned byte slots (`with_len`, byte-indexed
// read/write helpers below); foreign buffers copy out through the ffi
// SafePtr bounds-checked helpers. Handles and resolved symbols are Ints
// (B-series discipline: never cast to pointers outside a call site).
//
// Classification:
//   SSL_LOAD_ABSENT -> no candidate libssl soname loaded -> SKIP
//   SSL_LOAD_ABI    -> a candidate loaded but entry points are missing -> FAIL
//   operational failures -> typed SslError { kind, message }
//
// Coverage (phase 1, accepted ask REL-20261015-2211-packages): server +
// client contexts; cert/key/chain load (PEM/DER, files AND buffers);
// handshake driving over a stream fd (SSL_accept/SSL_connect step) and over
// memory BIOs (transport-agnostic pump, composes with xiom.transport);
// ALPN set + negotiated read; verify modes (none/peer + failure reporting);
// clean shutdown; typed errors.  Streaming/session reuse/OCSP are later
// phases (ROADMAP.md).
//
// Documented limitation: OpenSSL selects the server-side ALPN protocol only
// through an SSL_CTX_set_alpn_select_cb C callback; the XIOM FFI has no
// callback bridging (2026-10 lane survey: no shipped package passes a
// function pointer to C), so server-side SELECTION is out of the declared
// surface.  Client set-list + negotiated read on both ends ARE bound and
// tested; a server without a selector negotiates ALPN "none"
// (alpn_selected == ""), which the suite asserts.
//
// G2 pin (SPEC.md): candidate soname list + entry-point set + local sample
// (Git for Windows 3.2.4 libssl-3-x64.dll / libcrypto-3-x64.dll, both
// 3.2.4) + upstream OpenSSL oracle clone (E:\repos\openssl @ tag
// openssl-3.2.4 = commit 8ac4271233ecec5aa0468a5e7ae38dd642ebf365;
// Apache-2.0; nothing vendored -- constants declared locally).

module xiom.ssl

use xiom.ffi.dl;
use xiom.ffi;
use xiom.net.socket;

// =========================================================================
// Identity
// =========================================================================

/// OpenSSL_version query type OPENSSL_VERSION (oracle: opensslv.h).
const OSSL_VERSION_TYPE_OPENSSL: Int = 0;

// =========================================================================
// Classification and error kinds
// =========================================================================

pub const SSL_LOAD_ABSENT: Int = 0;      // no candidate loaded -> SKIP
pub const SSL_LOAD_ABI: Int = 1;         // entry points missing -> FAIL
pub const SSL_ERR_ALLOC: Int = 2;        // context/stream allocation failed
pub const SSL_ERR_CERT: Int = 3;         // cert/key/chain/CA load failed
pub const SSL_ERR_ALPN: Int = 4;         // ALPN list rejected by the build
pub const SSL_ERR_HANDSHAKE: Int = 5;    // fatal handshake failure (incl. verify)
pub const SSL_ERR_WANT_READ: Int = 6;    // non-fatal: retry when readable
pub const SSL_ERR_WANT_WRITE: Int = 7;   // non-fatal: retry when writable
pub const SSL_ERR_IO: Int = 8;           // read/write/shutdown fatal failure

/// Handshake step state codes (SslStep.want).
pub const SSL_WANT_NONE: Int = 0;
pub const SSL_WANT_READ: Int = 1;
pub const SSL_WANT_WRITE: Int = 2;

/// SSL_get_error codes this module branches on (oracle: ssl.h.in).
pub const SSL_ERROR_NONE: Int = 0;
pub const SSL_ERROR_SSL: Int = 1;
pub const SSL_ERROR_WANT_READ: Int = 2;
pub const SSL_ERROR_WANT_WRITE: Int = 3;
pub const SSL_ERROR_SYSCALL: Int = 5;
pub const SSL_ERROR_ZERO_RETURN: Int = 6;

/// SSL_CTX_use_*_file file types (oracle: x509.h.in X509_FILETYPE_*).
pub const SSL_FILETYPE_PEM: Int = 1;
pub const SSL_FILETYPE_ASN1: Int = 2;

/// Verify modes (oracle: ssl.h.in SSL_VERIFY_*).
pub const SSL_VERIFY_NONE: Int = 0;
pub const SSL_VERIFY_PEER: Int = 1;
pub const SSL_VERIFY_FAIL_IF_NO_PEER_CERT: Int = 2;

/// SSL_ctrl command: SNI host name (oracle: ssl.h.in
/// SSL_CTRL_SET_TLSEXT_HOSTNAME).
pub const SSL_CTRL_SET_TLSEXT_HOSTNAME: Int = 55;

/// SNI name type (oracle: tls1.h TLSEXT_NAMETYPE_host_name).
pub const TLSEXT_NAMETYPE_host_name: Int = 0;

/// SSL_CTX_ctrl command: append an extra chain certificate.  The pushed
/// X509 is owned by the context on success (add0 semantics; oracle:
/// ssl.h.in macro + s3_lib.c ssl3_ctx_ctrl).
pub const SSL_CTRL_EXTRA_CHAIN_CERT: Int = 14;

/// BIO_ctrl pending-bytes query (oracle: bio.h.in BIO_CTRL_PENDING).
pub const BIO_CTRL_PENDING: Int = 10;

/// X509 verification result codes surfaced by ssl_get_verify_result
/// (oracle: x509_vfy.h.in).
pub const X509_V_OK: Int = 0;
pub const X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT: Int = 2;
pub const X509_V_ERR_CERT_NOT_YET_VALID: Int = 9;
pub const X509_V_ERR_CERT_HAS_EXPIRED: Int = 10;
pub const X509_V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT: Int = 18;
pub const X509_V_ERR_SELF_SIGNED_CERT_IN_CHAIN: Int = 19;
pub const X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY: Int = 20;
pub const X509_V_ERR_UNABLE_TO_VERIFY_LEAF_SIGNATURE: Int = 21;

// =========================================================================
// Types
// =========================================================================

/// A typed ssl failure: load classification or operational error.
pub type SslError = {
  kind: Int;
  message: Str;
}

/// Identity of the loaded build (reported by the libcrypto companion).
pub type SslInfo = {
  version: Str;
  version_num: Int;
}

/// One loaded libssl and its resolved entry points plus the libcrypto
/// companion used for PEM/BIO/error helpers.  Owned by the caller; release
/// with `ssl_close`.
pub type SslLibrary = {
  handle: Int;
  soname: Str;
  crypto_handle: Int;
  crypto_soname: Str;
  p_tls_server_method: Int;
  p_tls_client_method: Int;
  p_ctx_new: Int;
  p_ctx_free: Int;
  p_ctx_ctrl: Int;
  p_ctx_set_verify: Int;
  p_get_verify_result: Int;
  p_ctx_use_cert_file: Int;
  p_ctx_use_key_file: Int;
  p_ctx_use_chain_file: Int;
  p_ctx_check_private_key: Int;
  p_ctx_use_certificate: Int;
  p_ctx_use_private_key: Int;
  p_ctx_use_certificate_asn1: Int;
  p_ctx_load_verify_locations: Int;
  p_ctx_set_alpn_protos: Int;
  p_get0_alpn_selected: Int;
  p_new: Int;
  p_free: Int;
  p_set_fd: Int;
  p_set_bio: Int;
  p_accept: Int;
  p_connect: Int;
  p_read: Int;
  p_write: Int;
  p_shutdown: Int;
  p_get_error: Int;
  p_get_version: Int;
  p_get_current_cipher: Int;
  p_cipher_get_name: Int;
  p_ctrl: Int;
  p_bio_new: Int;
  p_bio_s_mem: Int;
  p_bio_read: Int;
  p_bio_write: Int;
  p_bio_ctrl: Int;
  p_bio_new_mem_buf: Int;
  p_bio_free: Int;
  p_pem_read_bio_x509: Int;
  p_pem_read_bio_private_key: Int;
  p_d2i_auto_private_key: Int;
  p_d2i_x509: Int;
  p_x509_free: Int;
  p_evp_pkey_free: Int;
  p_err_get_error: Int;
  p_err_error_string_n: Int;
  p_crypto_version: Int;
  p_crypto_version_num: Int;
}

/// A TLS context (SSL_CTX*).  Owned; release with `ssl_ctx_free`.
pub type SslContext = {
  ctx: Int;
  server: Bool;
}

/// One TLS stream (SSL*).  `fd` is the bound stream descriptor (>= 0 after
/// `ssl_set_fd`) or -1 when the stream rides memory BIOs
/// (`ssl_set_bio_mem`, which fills rbio/wbio; the stream owns them and
/// SSL_free releases them).
pub type SslStream = {
  ssl: Int;
  fd: Int;
  rbio: Int;
  wbio: Int;
}

/// One handshake step outcome: done, or waiting for readiness.
pub type SslStep = {
  done: Bool;
  want: Int;
}

// =========================================================================
// Slot helpers (XIOM-owned out-buffers; byte-indexed reads/writes)
// =========================================================================

/// n zero bytes in an XIOM-owned slot.
/// Complexity: O(n).
fn slot(n: Int) -> Vec[UInt8]
  requires: n > 0
  requires: n <= 65536
{
  return Vec[UInt8].with_len(n);
}

/// Byte-indexed little-endian u64 read from an owned slot.
/// Complexity: O(1).
fn rd_u64_le(buf: &Vec[UInt8], off: Int) -> Int
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

/// Byte-indexed little-endian u32 read from an owned slot.
/// Complexity: O(1).
fn rd_u32_le(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: off + 3 < buf.len()
{
  let b0 = buf[off] as Int;
  let b1 = buf[off + 1] as Int;
  let b2 = buf[off + 2] as Int;
  let b3 = buf[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

/// Local Int-to-Str (lane pattern, BINDINGS-COMPILER-FINDINGS: avoids
/// cross-module convert resolution traps inside confined modules).
/// Complexity: O(digits).
fn int_to_str(n: Int) -> Str
  requires: true
{
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

/// Human name for the common X509 verify result codes; "unknown" otherwise.
/// Complexity: O(1).
pub fn ssl_verify_result_name(code: Int) -> Str
  requires: true
{
  if code == X509_V_OK { return "ok"; }
  if code == X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT { return "unable to get issuer certificate"; }
  if code == X509_V_ERR_CERT_NOT_YET_VALID { return "certificate is not yet valid"; }
  if code == X509_V_ERR_CERT_HAS_EXPIRED { return "certificate has expired"; }
  if code == X509_V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT { return "self-signed certificate"; }
  if code == X509_V_ERR_SELF_SIGNED_CERT_IN_CHAIN { return "self-signed certificate in certificate chain"; }
  if code == X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY { return "unable to get local issuer certificate"; }
  if code == X509_V_ERR_UNABLE_TO_VERIFY_LEAF_SIGNATURE { return "unable to verify the first certificate"; }
  return "unknown";
}

/// Build an ALPN protocol list in wire format: each name 8-bit
/// length-prefixed, 1..255 bytes per name, at most 65535 bytes total
/// (oracle: SSL_CTX_set_alpn_select_cb.pod format notes; validated by
/// SSL_CTX_set_alpn_protos itself as "not valid per RFC" otherwise).
/// Complexity: O(total bytes).
pub fn ssl_alpn_wire(names: &Vec[Str]) -> Result[Vec[UInt8], Str]
  requires: names.len() > 0
{
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < names.len() {
    let nm = names[i];
    if nm.len() == 0 { return Err("alpn: empty protocol name"); }
    if nm.len() > 255 { return Err("alpn: protocol name longer than 255 bytes"); }
    out.push(nm.len() as UInt8);
    var j = 0;
    while j < nm.len() {
      out.push(nm.byte_at(j));
      j = j + 1;
    }
    i = i + 1;
  }
  if out.len() > 65535 { return Err("alpn: list longer than 65535 bytes"); }
  return Ok(out);
}

// =========================================================================
// Loader (multi-soname)
// =========================================================================

fn fail_load(handle: Int, message: Str) -> Result[SslLibrary, SslError]
  requires: handle != 0
  requires: message.len() > 0
{
  var ig = dl.dl_close(handle);
  return Err(SslError{ kind: SSL_LOAD_ABI; message: message });
}

fn fail_load2(handle: Int, chandle: Int, message: Str) -> Result[SslLibrary, SslError]
  requires: handle != 0
  requires: chandle != 0
  requires: message.len() > 0
{
  var ig1 = dl.dl_close(chandle);
  var ig2 = dl.dl_close(handle);
  return Err(SslError{ kind: SSL_LOAD_ABI; message: message });
}

fn sym_or(handle: Int, name: Str) -> Result[Int, Str]
  requires: handle != 0
  requires: name.len() > 0
{
  let a = dl.dl_sym(handle, name);
  if !a.is_ok { return Err(name + ": " + a.error); }
  return Ok(a.value);
}

fn try_load(soname: Str) -> Result[SslLibrary, SslError]
  requires: soname.len() > 0
{
  let h = dl.dl_open(soname);
  if !h.is_ok {
    // Not this candidate: report ABSENT so the caller can try the next one.
    return Err(SslError{ kind: SSL_LOAD_ABSENT; message: h.error });
  }
  let handle: Int = h.value;

  let n01 = sym_or(handle, "TLS_server_method");
  if !n01.is_ok { return fail_load(handle, n01.error); }
  let n02 = sym_or(handle, "TLS_client_method");
  if !n02.is_ok { return fail_load(handle, n02.error); }
  let n03 = sym_or(handle, "SSL_CTX_new");
  if !n03.is_ok { return fail_load(handle, n03.error); }
  let n04 = sym_or(handle, "SSL_CTX_free");
  if !n04.is_ok { return fail_load(handle, n04.error); }
  let n05 = sym_or(handle, "SSL_CTX_ctrl");
  if !n05.is_ok { return fail_load(handle, n05.error); }
  let n06 = sym_or(handle, "SSL_CTX_set_verify");
  if !n06.is_ok { return fail_load(handle, n06.error); }
  let n07 = sym_or(handle, "SSL_get_verify_result");
  if !n07.is_ok { return fail_load(handle, n07.error); }
  let n08 = sym_or(handle, "SSL_CTX_use_certificate_file");
  if !n08.is_ok { return fail_load(handle, n08.error); }
  let n09 = sym_or(handle, "SSL_CTX_use_PrivateKey_file");
  if !n09.is_ok { return fail_load(handle, n09.error); }
  let n10 = sym_or(handle, "SSL_CTX_use_certificate_chain_file");
  if !n10.is_ok { return fail_load(handle, n10.error); }
  let n11 = sym_or(handle, "SSL_CTX_check_private_key");
  if !n11.is_ok { return fail_load(handle, n11.error); }
  let n12 = sym_or(handle, "SSL_CTX_use_certificate");
  if !n12.is_ok { return fail_load(handle, n12.error); }
  let n13 = sym_or(handle, "SSL_CTX_use_PrivateKey");
  if !n13.is_ok { return fail_load(handle, n13.error); }
  let n14 = sym_or(handle, "SSL_CTX_use_certificate_ASN1");
  if !n14.is_ok { return fail_load(handle, n14.error); }
  let n15 = sym_or(handle, "SSL_CTX_load_verify_locations");
  if !n15.is_ok { return fail_load(handle, n15.error); }
  let n16 = sym_or(handle, "SSL_CTX_set_alpn_protos");
  if !n16.is_ok { return fail_load(handle, n16.error); }
  let n17 = sym_or(handle, "SSL_get0_alpn_selected");
  if !n17.is_ok { return fail_load(handle, n17.error); }
  let n18 = sym_or(handle, "SSL_new");
  if !n18.is_ok { return fail_load(handle, n18.error); }
  let n19 = sym_or(handle, "SSL_free");
  if !n19.is_ok { return fail_load(handle, n19.error); }
  let n20 = sym_or(handle, "SSL_set_fd");
  if !n20.is_ok { return fail_load(handle, n20.error); }
  let n21 = sym_or(handle, "SSL_set_bio");
  if !n21.is_ok { return fail_load(handle, n21.error); }
  let n22 = sym_or(handle, "SSL_accept");
  if !n22.is_ok { return fail_load(handle, n22.error); }
  let n23 = sym_or(handle, "SSL_connect");
  if !n23.is_ok { return fail_load(handle, n23.error); }
  let n24 = sym_or(handle, "SSL_read");
  if !n24.is_ok { return fail_load(handle, n24.error); }
  let n25 = sym_or(handle, "SSL_write");
  if !n25.is_ok { return fail_load(handle, n25.error); }
  let n26 = sym_or(handle, "SSL_shutdown");
  if !n26.is_ok { return fail_load(handle, n26.error); }
  let n27 = sym_or(handle, "SSL_get_error");
  if !n27.is_ok { return fail_load(handle, n27.error); }
  let n28 = sym_or(handle, "SSL_get_version");
  if !n28.is_ok { return fail_load(handle, n28.error); }
  let n29 = sym_or(handle, "SSL_get_current_cipher");
  if !n29.is_ok { return fail_load(handle, n29.error); }
  let n30 = sym_or(handle, "SSL_CIPHER_get_name");
  if !n30.is_ok { return fail_load(handle, n30.error); }
  let n31 = sym_or(handle, "SSL_ctrl");
  if !n31.is_ok { return fail_load(handle, n31.error); }

  // libcrypto companion: after libssl is in-process its dependency is
  // already loaded, so an exact-name dl_open returns that very module; the
  // candidates cover the same version spread as xiom.openssl.
  var chandle: Int = 0;
  var cname: Str = "";
  let c1 = dl.dl_open("libcrypto-3-x64.dll");
  if c1.is_ok { chandle = c1.value; cname = "libcrypto-3-x64.dll"; }
  if chandle == 0 {
    let c2 = dl.dl_open("libcrypto-1_1-x64.dll");
    if c2.is_ok { chandle = c2.value; cname = "libcrypto-1_1-x64.dll"; }
  }
  if chandle == 0 {
    let c3 = dl.dl_open("libcrypto-1_1.dll");
    if c3.is_ok { chandle = c3.value; cname = "libcrypto-1_1.dll"; }
  }
  if chandle == 0 {
    let c4 = dl.dl_open("libcrypto.dll");
    if c4.is_ok { chandle = c4.value; cname = "libcrypto.dll"; }
  }
  if chandle == 0 {
    var ig0 = dl.dl_close(handle);
    return Err(SslError{
      kind: SSL_LOAD_ABI;
      message: "libssl loaded but no libcrypto companion (tried 3-x64, 1_1-x64, 1_1, unversioned)",
    });
  }

  let c01 = sym_or(chandle, "BIO_new");
  if !c01.is_ok { return fail_load2(handle, chandle, c01.error); }
  let c02 = sym_or(chandle, "BIO_s_mem");
  if !c02.is_ok { return fail_load2(handle, chandle, c02.error); }
  let c03 = sym_or(chandle, "BIO_read");
  if !c03.is_ok { return fail_load2(handle, chandle, c03.error); }
  let c04 = sym_or(chandle, "BIO_write");
  if !c04.is_ok { return fail_load2(handle, chandle, c04.error); }
  let c05 = sym_or(chandle, "BIO_ctrl");
  if !c05.is_ok { return fail_load2(handle, chandle, c05.error); }
  let c06 = sym_or(chandle, "BIO_new_mem_buf");
  if !c06.is_ok { return fail_load2(handle, chandle, c06.error); }
  let c07 = sym_or(chandle, "BIO_free");
  if !c07.is_ok { return fail_load2(handle, chandle, c07.error); }
  let c08 = sym_or(chandle, "PEM_read_bio_X509");
  if !c08.is_ok { return fail_load2(handle, chandle, c08.error); }
  let c09 = sym_or(chandle, "PEM_read_bio_PrivateKey");
  if !c09.is_ok { return fail_load2(handle, chandle, c09.error); }
  let c10 = sym_or(chandle, "d2i_AutoPrivateKey");
  if !c10.is_ok { return fail_load2(handle, chandle, c10.error); }
  let c11 = sym_or(chandle, "d2i_X509");
  if !c11.is_ok { return fail_load2(handle, chandle, c11.error); }
  let c12 = sym_or(chandle, "X509_free");
  if !c12.is_ok { return fail_load2(handle, chandle, c12.error); }
  let c13 = sym_or(chandle, "EVP_PKEY_free");
  if !c13.is_ok { return fail_load2(handle, chandle, c13.error); }
  let c14 = sym_or(chandle, "ERR_get_error");
  if !c14.is_ok { return fail_load2(handle, chandle, c14.error); }
  let c15 = sym_or(chandle, "ERR_error_string_n");
  if !c15.is_ok { return fail_load2(handle, chandle, c15.error); }
  let c16 = sym_or(chandle, "OpenSSL_version");
  if !c16.is_ok { return fail_load2(handle, chandle, c16.error); }
  let c17 = sym_or(chandle, "OpenSSL_version_num");
  if !c17.is_ok { return fail_load2(handle, chandle, c17.error); }

  return Ok(SslLibrary{
    handle: handle;
    soname: soname;
    crypto_handle: chandle;
    crypto_soname: cname;
    p_tls_server_method: n01.value;
    p_tls_client_method: n02.value;
    p_ctx_new: n03.value;
    p_ctx_free: n04.value;
    p_ctx_ctrl: n05.value;
    p_ctx_set_verify: n06.value;
    p_get_verify_result: n07.value;
    p_ctx_use_cert_file: n08.value;
    p_ctx_use_key_file: n09.value;
    p_ctx_use_chain_file: n10.value;
    p_ctx_check_private_key: n11.value;
    p_ctx_use_certificate: n12.value;
    p_ctx_use_private_key: n13.value;
    p_ctx_use_certificate_asn1: n14.value;
    p_ctx_load_verify_locations: n15.value;
    p_ctx_set_alpn_protos: n16.value;
    p_get0_alpn_selected: n17.value;
    p_new: n18.value;
    p_free: n19.value;
    p_set_fd: n20.value;
    p_set_bio: n21.value;
    p_accept: n22.value;
    p_connect: n23.value;
    p_read: n24.value;
    p_write: n25.value;
    p_shutdown: n26.value;
    p_get_error: n27.value;
    p_get_version: n28.value;
    p_get_current_cipher: n29.value;
    p_cipher_get_name: n30.value;
    p_ctrl: n31.value;
    p_bio_new: c01.value;
    p_bio_s_mem: c02.value;
    p_bio_read: c03.value;
    p_bio_write: c04.value;
    p_bio_ctrl: c05.value;
    p_bio_new_mem_buf: c06.value;
    p_bio_free: c07.value;
    p_pem_read_bio_x509: c08.value;
    p_pem_read_bio_private_key: c09.value;
    p_d2i_auto_private_key: c10.value;
    p_d2i_x509: c11.value;
    p_x509_free: c12.value;
    p_evp_pkey_free: c13.value;
    p_err_get_error: c14.value;
    p_err_error_string_n: c15.value;
    p_crypto_version: c16.value;
    p_crypto_version_num: c17.value;
  });
}

/// Load an explicitly named libssl build (bogus names exercise the
/// ABSENT/SKIP classification deterministically on any host).
/// Complexity: O(symbols).
pub fn ssl_load_named(soname: Str) -> Result[SslLibrary, SslError]
  requires: soname.len() > 0
{
  return try_load(soname);
}

/// Load the first available libssl from the common Windows sonames:
/// OpenSSL 3.x (`libssl-3-x64.dll`), 1.1.x (`libssl-1_1-x64.dll`,
/// `libssl-1_1.dll`), and the unversioned `libssl.dll`.
/// Complexity: O(candidates * symbols).
pub fn ssl_load() -> Result[SslLibrary, SslError]
  requires: true
{
  let c1 = try_load("libssl-3-x64.dll");
  if c1.is_ok { return Ok(c1.value); }
  if c1.error.kind == SSL_LOAD_ABI { return Err(c1.error); }

  let c2 = try_load("libssl-1_1-x64.dll");
  if c2.is_ok { return Ok(c2.value); }
  if c2.error.kind == SSL_LOAD_ABI { return Err(c2.error); }

  let c3 = try_load("libssl-1_1.dll");
  if c3.is_ok { return Ok(c3.value); }
  if c3.error.kind == SSL_LOAD_ABI { return Err(c3.error); }

  let c4 = try_load("libssl.dll");
  if c4.is_ok { return Ok(c4.value); }
  if c4.error.kind == SSL_LOAD_ABI { return Err(c4.error); }

  return Err(SslError{
    kind: SSL_LOAD_ABSENT;
    message: "ssl: no libssl candidate found (tried libssl-3-x64.dll, libssl-1_1-x64.dll, libssl-1_1.dll, libssl.dll)",
  });
}

/// Release the library handles (crypto companion first, then libssl).
/// Complexity: O(1).
pub fn ssl_close(lib: &SslLibrary) -> Result[Unit, Str]
  requires: lib.handle != 0
  requires: lib.crypto_handle != 0
{
  let rc2 = dl.dl_close(lib.crypto_handle);
  let rc1 = dl.dl_close(lib.handle);
  if !rc2.is_ok { return Err(rc2.error); }
  if !rc1.is_ok { return Err(rc1.error); }
  return Ok(());
}

// =========================================================================
// Error message helpers
// =========================================================================

/// The OpenSSL error queue's first entry as a Str (""); consumes one entry.
/// Complexity: O(len).
fn err_last(lib: &SslLibrary) -> Str
  requires: lib.crypto_handle != 0
{
  unsafe {
    let f = lib.p_err_get_error as fn() -> Int;
    let e = f();
    if e == 0 { return ""; }
    var buf = slot(256);
    let f2 = lib.p_err_error_string_n as fn(Int, *UInt8, Int) -> Unit;
    f2(e, buf.as_mut_ptr(), 256);
    return Str::from_c_str(buf.as_mut_ptr());
  }
}

/// Typed error from a context string plus the OpenSSL error queue.
/// Complexity: O(len).
fn ssl_err(kind: Int, lib: &SslLibrary, context: Str) -> SslError
  requires: lib.crypto_handle != 0
  requires: context.len() > 0
{
  let m = err_last(lib);
  if m.len() == 0 { return SslError{ kind: kind; message: context }; }
  return SslError{ kind: kind; message: context + ": " + m };
}

/// Handshake failure error carrying the verify result when non-OK.
/// Complexity: O(len).
fn hs_err(lib: &SslLibrary, ssl: Int) -> SslError
  requires: lib.handle != 0
  requires: ssl != 0
{
  unsafe {
    let fv = lib.p_get_verify_result as fn(Int) -> Int;
    let rv = fv(ssl);
    let m = err_last(lib);
    var msg = "handshake failed";
    if rv != 0 {
      msg = msg + " (verify_result=" + int_to_str(rv) + ": " + ssl_verify_result_name(rv) + ")";
    }
    if m.len() > 0 { msg = msg + ": " + m; }
    return SslError{ kind: SSL_ERR_HANDSHAKE; message: msg };
  }
}

// =========================================================================
// Probe
// =========================================================================

/// Version string + packed version number of the libcrypto companion (the
/// build libssl actually pairs with).  The functional proof lives in the
/// suite: a real loopback handshake with cert/key/ALPN/verify.
/// Complexity: O(1).
pub fn ssl_probe(lib: &SslLibrary) -> Result[SslInfo, SslError]
  requires: lib.handle != 0
  requires: lib.crypto_handle != 0
{
  unsafe {
    let f = lib.p_crypto_version as fn(Int) -> *UInt8;
    var version = "";
    let vp = f(OSSL_VERSION_TYPE_OPENSSL);
    if (vp as Int) != 0 {
      version = Str::from_c_str(vp);
    }
    let fnum = lib.p_crypto_version_num as fn() -> UInt32;
    return Ok(SslInfo{
      version: version;
      version_num: fnum() as Int;
    });
  }
}

/// Load an explicitly named build and run `ssl_probe`.
/// Complexity: O(symbols + probe).
pub fn ssl_probe_named(soname: Str) -> Result[SslInfo, SslError]
  requires: soname.len() > 0
{
  let l = ssl_load_named(soname);
  if !l.is_ok {
    return Err(l.error);
  }
  let lib: SslLibrary = l.value;
  let p = ssl_probe(&lib);
  let cl = ssl_close(&lib);
  if !p.is_ok {
    return Err(p.error);
  }
  if !cl.is_ok {
    return Err(SslError{ kind: SSL_ERR_IO; message: cl.error });
  }
  return Ok(p.value);
}

/// Probe the first available candidate build.
/// Complexity: O(candidates * symbols + probe).
pub fn ssl_probe_default() -> Result[SslInfo, SslError]
  requires: true
{
  let l = ssl_load();
  if !l.is_ok {
    return Err(l.error);
  }
  let lib: SslLibrary = l.value;
  let p = ssl_probe(&lib);
  let cl = ssl_close(&lib);
  if !p.is_ok {
    return Err(p.error);
  }
  if !cl.is_ok {
    return Err(SslError{ kind: SSL_ERR_IO; message: cl.error });
  }
  return Ok(p.value);
}

// =========================================================================
// Context operations
// =========================================================================

/// Create a server or client context (TLS_server_method /
/// TLS_client_method).
/// Complexity: O(1).
pub fn ssl_ctx_new(lib: &SslLibrary, server: Bool) -> Result[SslContext, SslError]
  requires: lib.handle != 0
{
  unsafe {
    var method: Int = 0;
    if server {
      let f = lib.p_tls_server_method as fn() -> Int;
      method = f();
    } else {
      let f = lib.p_tls_client_method as fn() -> Int;
      method = f();
    }
    if method == 0 {
      return Err(SslError{ kind: SSL_ERR_ALLOC; message: "SSL method unavailable" });
    }
    let fn_new = lib.p_ctx_new as fn(Int) -> Int;
    let ctx = fn_new(method);
    if ctx == 0 {
      return Err(ssl_err(SSL_ERR_ALLOC, lib, "SSL_CTX_new failed"));
    }
    return Ok(SslContext{ ctx: ctx; server: server });
  }
}

/// Free a context.
/// Complexity: O(1).
pub fn ssl_ctx_free(lib: &SslLibrary, ctx: &SslContext)
  requires: lib.handle != 0
{
  if ctx.ctx == 0 { return; }
  unsafe {
    let f = lib.p_ctx_free as fn(Int) -> Unit;
    f(ctx.ctx);
  }
}

/// Set the peer-verification mode (SSL_VERIFY_NONE / PEER /
/// FAIL_IF_NO_PEER_CERT; the default callback is used -- callback slot NULL).
/// Complexity: O(1).
pub fn ssl_ctx_set_verify(lib: &SslLibrary, ctx: &SslContext, mode: Int)
  requires: lib.handle != 0
  requires: ctx.ctx != 0
{
  unsafe {
    let f = lib.p_ctx_set_verify as fn(Int, Int, Int) -> Unit;
    f(ctx.ctx, mode, 0);
  }
}

/// Load a certificate from a file (PEM or DER).
/// Complexity: O(file).
pub fn ssl_ctx_use_cert_file(lib: &SslLibrary, ctx: &SslContext, path: Str, pem: Bool) -> Result[Unit, SslError]
  requires: lib.handle != 0
  requires: ctx.ctx != 0
  requires: path.len() > 0
{
  var ftype = SSL_FILETYPE_ASN1;
  if pem { ftype = SSL_FILETYPE_PEM; }
  unsafe {
    let f = lib.p_ctx_use_cert_file as fn(Int, *UInt8, Int) -> Int32;
    let rc = f(ctx.ctx, path.c_str(), ftype) as Int;
    if rc == 1 { return Ok(()); }
    return Err(ssl_err(SSL_ERR_CERT, lib, "load certificate file failed: " + path));
  }
}

/// Load a private key from a file (PEM or DER).
/// Complexity: O(file).
pub fn ssl_ctx_use_key_file(lib: &SslLibrary, ctx: &SslContext, path: Str, pem: Bool) -> Result[Unit, SslError]
  requires: lib.handle != 0
  requires: ctx.ctx != 0
  requires: path.len() > 0
{
  var ftype = SSL_FILETYPE_ASN1;
  if pem { ftype = SSL_FILETYPE_PEM; }
  unsafe {
    let f = lib.p_ctx_use_key_file as fn(Int, *UInt8, Int) -> Int32;
    let rc = f(ctx.ctx, path.c_str(), ftype) as Int;
    if rc == 1 { return Ok(()); }
    return Err(ssl_err(SSL_ERR_CERT, lib, "load private key file failed: " + path));
  }
}

/// Load a PEM certificate chain (leaf + intermediates) from a file.
/// Complexity: O(file).
pub fn ssl_ctx_use_chain_file(lib: &SslLibrary, ctx: &SslContext, path: Str) -> Result[Unit, SslError]
  requires: lib.handle != 0
  requires: ctx.ctx != 0
  requires: path.len() > 0
{
  unsafe {
    let f = lib.p_ctx_use_chain_file as fn(Int, *UInt8) -> Int32;
    let rc = f(ctx.ctx, path.c_str()) as Int;
    if rc == 1 { return Ok(()); }
    return Err(ssl_err(SSL_ERR_CERT, lib, "load certificate chain file failed: " + path));
  }
}

/// Verify that the loaded private key matches the loaded certificate.
/// Complexity: O(1).
pub fn ssl_ctx_check_private_key(lib: &SslLibrary, ctx: &SslContext) -> Result[Unit, SslError]
  requires: lib.handle != 0
  requires: ctx.ctx != 0
{
  unsafe {
    let f = lib.p_ctx_check_private_key as fn(Int) -> Int32;
    let rc = f(ctx.ctx) as Int;
    if rc == 1 { return Ok(()); }
    return Err(ssl_err(SSL_ERR_CERT, lib, "certificate/private key mismatch"));
  }
}

/// Load a certificate from a PEM buffer (memory BIO + PEM_read_bio_X509;
/// the temporary X509 is released after use -- SSL_CTX_use_certificate
/// increments the reference count).
/// Complexity: O(buffer).
pub fn ssl_ctx_use_cert_pem(lib: &SslLibrary, ctx: &SslContext, pem: Str) -> Result[Unit, SslError]
  requires: lib.handle != 0
  requires: ctx.ctx != 0
  requires: pem.len() > 0
{
  unsafe {
    let fb = lib.p_bio_new_mem_buf as fn(*UInt8, Int) -> Int;
    let bio = fb(pem.c_str(), pem.len());
    if bio == 0 {
      return Err(ssl_err(SSL_ERR_CERT, lib, "certificate PEM buffer: BIO creation failed"));
    }
    let fp = lib.p_pem_read_bio_x509 as fn(Int, Int, Int, Int) -> Int;
    let x = fp(bio, 0, 0, 0);
    let fbf = lib.p_bio_free as fn(Int) -> Int32;
    var igb = fbf(bio);
    if x == 0 {
      return Err(ssl_err(SSL_ERR_CERT, lib, "certificate PEM buffer: parse failed"));
    }
    let fu = lib.p_ctx_use_certificate as fn(Int, Int) -> Int32;
    let rc = fu(ctx.ctx, x) as Int;
    let fx = lib.p_x509_free as fn(Int) -> Unit;
    fx(x);
    if rc == 1 { return Ok(()); }
    return Err(ssl_err(SSL_ERR_CERT, lib, "certificate PEM buffer: use failed"));
  }
}

/// Load a private key from a PEM buffer (memory BIO +
/// PEM_read_bio_PrivateKey; the temporary EVP_PKEY is released after use --
/// SSL_CTX_use_PrivateKey increments the reference count).
/// Complexity: O(buffer).
pub fn ssl_ctx_use_key_pem(lib: &SslLibrary, ctx: &SslContext, pem: Str) -> Result[Unit, SslError]
  requires: lib.handle != 0
  requires: ctx.ctx != 0
  requires: pem.len() > 0
{
  unsafe {
    let fb = lib.p_bio_new_mem_buf as fn(*UInt8, Int) -> Int;
    let bio = fb(pem.c_str(), pem.len());
    if bio == 0 {
      return Err(ssl_err(SSL_ERR_CERT, lib, "private key PEM buffer: BIO creation failed"));
    }
    let fp = lib.p_pem_read_bio_private_key as fn(Int, Int, Int, Int) -> Int;
    let k = fp(bio, 0, 0, 0);
    let fbf = lib.p_bio_free as fn(Int) -> Int32;
    var igb = fbf(bio);
    if k == 0 {
      return Err(ssl_err(SSL_ERR_CERT, lib, "private key PEM buffer: parse failed"));
    }
    let fu = lib.p_ctx_use_private_key as fn(Int, Int) -> Int32;
    let rc = fu(ctx.ctx, k) as Int;
    let fk = lib.p_evp_pkey_free as fn(Int) -> Unit;
    fk(k);
    if rc == 1 { return Ok(()); }
    return Err(ssl_err(SSL_ERR_CERT, lib, "private key PEM buffer: use failed"));
  }
}

/// Load a certificate from a DER buffer (SSL_CTX_use_certificate_ASN1).
/// Complexity: O(buffer).
pub fn ssl_ctx_use_cert_der(lib: &SslLibrary, ctx: &SslContext, der: &Vec[UInt8]) -> Result[Unit, SslError]
  requires: lib.handle != 0
  requires: ctx.ctx != 0
  requires: der.len() > 0
{
  unsafe {
    let f = lib.p_ctx_use_certificate_asn1 as fn(Int, Int, *UInt8) -> Int32;
    let rc = f(ctx.ctx, der.len(), &der[0] as *UInt8) as Int;
    if rc == 1 { return Ok(()); }
    return Err(ssl_err(SSL_ERR_CERT, lib, "certificate DER buffer: use failed"));
  }
}

/// Load a private key from a DER buffer (d2i_AutoPrivateKey over an
/// XIOM-owned pointer slot; PKCS#8, PKCS#1 and SEC1 containers are
/// auto-detected).  The temporary EVP_PKEY is released after use --
/// SSL_CTX_use_PrivateKey increments the reference count.
/// Complexity: O(buffer).
pub fn ssl_ctx_use_key_der(lib: &SslLibrary, ctx: &SslContext, der: &Vec[UInt8]) -> Result[Unit, SslError]
  requires: lib.handle != 0
  requires: ctx.ctx != 0
  requires: der.len() > 0
{
  unsafe {
    let p0 = &der[0] as *UInt8;
    let pi = p0 as Int;
    var in_slot = slot(8);
    var k = 0;
    while k < 8 {
      in_slot[k] = ((pi >> (8 * k)) & 255) as UInt8;
      k = k + 1;
    }
    let f = lib.p_d2i_auto_private_key as fn(*UInt8, *UInt8, Int) -> Int;
    let pkey = f(0 as *UInt8, in_slot.as_mut_ptr(), der.len());
    if pkey == 0 {
      return Err(ssl_err(SSL_ERR_CERT, lib, "private key DER buffer: parse failed"));
    }
    let fu = lib.p_ctx_use_private_key as fn(Int, Int) -> Int32;
    let rc = fu(ctx.ctx, pkey) as Int;
    let fk = lib.p_evp_pkey_free as fn(Int) -> Unit;
    fk(pkey);
    if rc == 1 { return Ok(()); }
    return Err(ssl_err(SSL_ERR_CERT, lib, "private key DER buffer: use failed"));
  }
}

/// Append an extra chain certificate from a PEM buffer.  Ownership of the
/// parsed X509 moves to the context on success (add0); on failure the
/// temporary is released here.
/// Complexity: O(buffer).
pub fn ssl_ctx_add_chain_pem(lib: &SslLibrary, ctx: &SslContext, pem: Str) -> Result[Unit, SslError]
  requires: lib.handle != 0
  requires: ctx.ctx != 0
  requires: pem.len() > 0
{
  unsafe {
    let fb = lib.p_bio_new_mem_buf as fn(*UInt8, Int) -> Int;
    let bio = fb(pem.c_str(), pem.len());
    if bio == 0 {
      return Err(ssl_err(SSL_ERR_CERT, lib, "chain PEM buffer: BIO creation failed"));
    }
    let fp = lib.p_pem_read_bio_x509 as fn(Int, Int, Int, Int) -> Int;
    let x = fp(bio, 0, 0, 0);
    let fbf = lib.p_bio_free as fn(Int) -> Int32;
    var igb = fbf(bio);
    if x == 0 {
      return Err(ssl_err(SSL_ERR_CERT, lib, "chain PEM buffer: parse failed"));
    }
    let fc = lib.p_ctx_ctrl as fn(Int, Int, Int, Int) -> Int;
    let rc = fc(ctx.ctx, SSL_CTRL_EXTRA_CHAIN_CERT, 0, x) as Int;
    if rc == 1 { return Ok(()); }
    let fx = lib.p_x509_free as fn(Int) -> Unit;
    fx(x);
    return Err(ssl_err(SSL_ERR_CERT, lib, "chain PEM buffer: append failed"));
  }
}

/// Append an extra chain certificate from a DER buffer (d2i_X509 +
/// SSL_CTX_ctrl(EXTRA_CHAIN_CERT); ownership moves to the context on
/// success).
/// Complexity: O(buffer).
pub fn ssl_ctx_add_chain_der(lib: &SslLibrary, ctx: &SslContext, der: &Vec[UInt8]) -> Result[Unit, SslError]
  requires: lib.handle != 0
  requires: ctx.ctx != 0
  requires: der.len() > 0
{
  unsafe {
    let p0 = &der[0] as *UInt8;
    let pi = p0 as Int;
    var in_slot = slot(8);
    var k = 0;
    while k < 8 {
      in_slot[k] = ((pi >> (8 * k)) & 255) as UInt8;
      k = k + 1;
    }
    let fd = lib.p_d2i_x509 as fn(*UInt8, *UInt8, Int) -> Int;
    let x = fd(0 as *UInt8, in_slot.as_mut_ptr(), der.len());
    if x == 0 {
      return Err(ssl_err(SSL_ERR_CERT, lib, "chain DER buffer: parse failed"));
    }
    let fc = lib.p_ctx_ctrl as fn(Int, Int, Int, Int) -> Int;
    let rc = fc(ctx.ctx, SSL_CTRL_EXTRA_CHAIN_CERT, 0, x) as Int;
    if rc == 1 { return Ok(()); }
    let fx = lib.p_x509_free as fn(Int) -> Unit;
    fx(x);
    return Err(ssl_err(SSL_ERR_CERT, lib, "chain DER buffer: append failed"));
  }
}

/// Load CA trust anchors (a PEM bundle file and/or a hashed directory;
/// pass "" for either to skip it -- an empty path is passed as NULL, not as
/// an empty string).
/// Complexity: O(store).
pub fn ssl_ctx_load_verify_locations(lib: &SslLibrary, ctx: &SslContext, cafile: Str, capath: Str) -> Result[Unit, SslError]
  requires: lib.handle != 0
  requires: ctx.ctx != 0
  requires: cafile.len() > 0 || capath.len() > 0
{
  unsafe {
    var ca: *UInt8 = 0 as *UInt8;
    var cp: *UInt8 = 0 as *UInt8;
    if cafile.len() > 0 { ca = cafile.c_str(); }
    if capath.len() > 0 { cp = capath.c_str(); }
    let f = lib.p_ctx_load_verify_locations as fn(Int, *UInt8, *UInt8) -> Int32;
    let rc = f(ctx.ctx, ca, cp) as Int;
    if rc == 1 { return Ok(()); }
    return Err(ssl_err(SSL_ERR_CERT, lib, "load verify locations failed"));
  }
}

/// Set the ALPN protocol list on a context (use `ssl_alpn_wire` to build
/// the wire format).  OpenSSL returns 0 on success, non-zero on failure.
/// Set it before `ssl_new`: SSL_new copies the context list to the stream.
/// Complexity: O(list).
pub fn ssl_ctx_set_alpn_protos(lib: &SslLibrary, ctx: &SslContext, wire: &Vec[UInt8]) -> Result[Unit, SslError]
  requires: lib.handle != 0
  requires: ctx.ctx != 0
  requires: wire.len() > 0
{
  unsafe {
    let f = lib.p_ctx_set_alpn_protos as fn(Int, *UInt8, Int) -> Int32;
    let rc = f(ctx.ctx, &wire[0] as *UInt8, wire.len()) as Int;
    if rc == 0 { return Ok(()); }
    return Err(ssl_err(SSL_ERR_ALPN, lib, "set ALPN protocols failed (rc " + int_to_str(rc) + ")"));
  }
}

// =========================================================================
// Stream operations
// =========================================================================

/// Create a stream on a context.
/// Complexity: O(1).
pub fn ssl_new(lib: &SslLibrary, ctx: &SslContext) -> Result[SslStream, SslError]
  requires: lib.handle != 0
  requires: ctx.ctx != 0
{
  unsafe {
    let f = lib.p_new as fn(Int) -> Int;
    let s = f(ctx.ctx);
    if s == 0 {
      return Err(ssl_err(SSL_ERR_ALLOC, lib, "SSL_new failed"));
    }
    return Ok(SslStream{ ssl: s; fd: -1; rbio: 0; wbio: 0 });
  }
}

/// Free a stream.  The bound BIO(s) are freed by libssl.
/// Complexity: O(1).
pub fn ssl_free(lib: &SslLibrary, s: &SslStream)
  requires: lib.handle != 0
{
  if s.ssl == 0 { return; }
  unsafe {
    let f = lib.p_free as fn(Int) -> Unit;
    f(s.ssl);
  }
}

/// Attach the stream to a socket descriptor (SSL_set_fd creates the
/// socket BIO pair); the descriptor is remembered for the readiness
/// polling inside `ssl_read`/`ssl_write`.
/// Complexity: O(1).
pub fn ssl_set_fd(lib: &SslLibrary, s: &mut SslStream, fd: Int) -> Result[Unit, SslError]
  requires: lib.handle != 0
  requires: s.ssl != 0
  requires: fd >= 0
{
  unsafe {
    let f = lib.p_set_fd as fn(Int, Int) -> Int32;
    let rc = f(s.ssl, fd) as Int;
    if rc != 1 { return Err(ssl_err(SSL_ERR_IO, lib, "SSL_set_fd failed")); }
    s.fd = fd;
    return Ok(());
  }
}

/// Attach the stream to a fresh memory-BIO pair (no socket).  Outgoing
/// bytes are drained with `ssl_bio_drain`, incoming bytes are fed with
/// `ssl_bio_feed` -- a transport-agnostic pump (composes with
/// xiom.transport or any user seam).  The stream owns the BIOs; SSL_free
/// releases them.
/// Complexity: O(1).
pub fn ssl_set_bio_mem(lib: &SslLibrary, s: &mut SslStream) -> Result[Unit, SslError]
  requires: lib.handle != 0
  requires: s.ssl != 0
{
  unsafe {
    let fm = lib.p_bio_s_mem as fn() -> Int;
    let method = fm();
    if method == 0 {
      return Err(SslError{ kind: SSL_ERR_ALLOC; message: "BIO_s_mem unavailable" });
    }
    let fb = lib.p_bio_new as fn(Int) -> Int;
    let rbio = fb(method);
    let wbio = fb(method);
    if rbio == 0 || wbio == 0 {
      let fbf = lib.p_bio_free as fn(Int) -> Int32;
      if rbio != 0 { var ig1 = fbf(rbio); }
      if wbio != 0 { var ig2 = fbf(wbio); }
      return Err(SslError{ kind: SSL_ERR_ALLOC; message: "BIO_new(memory) failed" });
    }
    let fsb = lib.p_set_bio as fn(Int, Int, Int) -> Unit;
    fsb(s.ssl, rbio, wbio);
    s.rbio = rbio;
    s.wbio = wbio;
    s.fd = -1;
    return Ok(());
  }
}

/// Bytes currently buffered in the stream's outgoing memory BIO.
/// Complexity: O(1).
pub fn ssl_bio_pending(lib: &SslLibrary, s: &SslStream) -> Result[Int, SslError]
  requires: lib.handle != 0
  requires: s.wbio != 0
{
  unsafe {
    let f = lib.p_bio_ctrl as fn(Int, Int, Int, Int) -> Int;
    let n = f(s.wbio, BIO_CTRL_PENDING, 0, 0);
    if n < 0 {
      return Err(ssl_err(SSL_ERR_IO, lib, "BIO_ctrl(pending) failed"));
    }
    return Ok(n);
  }
}

/// Drain up to `max` outgoing bytes from the stream's memory BIO (the
/// bytes a transport must deliver to the peer).
/// Complexity: O(n).
pub fn ssl_bio_drain(lib: &SslLibrary, s: &SslStream, max: Int) -> Result[Vec[UInt8], SslError]
  requires: lib.handle != 0
  requires: s.wbio != 0
  requires: max > 0
  requires: max <= 65536
{
  unsafe {
    var buf = slot(max);
    let f = lib.p_bio_read as fn(Int, *UInt8, Int) -> Int32;
    let rc = f(s.wbio, buf.as_mut_ptr(), max) as Int;
    if rc < 0 {
      return Err(ssl_err(SSL_ERR_IO, lib, "BIO_read(outgoing) failed"));
    }
    var out: Vec[UInt8] = Vec[UInt8].new();
    var i = 0;
    while i < rc {
      out.push(buf[i]);
      i = i + 1;
    }
    return Ok(out);
  }
}

/// Feed received bytes into the stream's incoming memory BIO.
/// Returns the count accepted.
/// Complexity: O(n).
pub fn ssl_bio_feed(lib: &SslLibrary, s: &mut SslStream, data: &Vec[UInt8]) -> Result[Int, SslError]
  requires: lib.handle != 0
  requires: s.rbio != 0
{
  if data.len() == 0 { return Ok(0); }
  unsafe {
    let f = lib.p_bio_write as fn(Int, *UInt8, Int) -> Int32;
    let rc = f(s.rbio, &data[0] as *UInt8, data.len()) as Int;
    if rc != data.len() {
      return Err(ssl_err(SSL_ERR_IO, lib, "BIO_write(incoming) failed"));
    }
    return Ok(rc);
  }
}

/// Set the SNI host name on a client stream (SSL_ctrl
/// SSL_CTRL_SET_TLSEXT_HOSTNAME).
/// Complexity: O(len).
pub fn ssl_set_hostname(lib: &SslLibrary, s: &SslStream, host: Str) -> Result[Unit, SslError]
  requires: lib.handle != 0
  requires: s.ssl != 0
  requires: host.len() > 0
{
  unsafe {
    let f = lib.p_ctrl as fn(Int, Int, Int, Int) -> Int;
    let rc = f(s.ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, TLSEXT_NAMETYPE_host_name, host.c_str() as Int) as Int;
    if rc == 1 { return Ok(()); }
    return Err(ssl_err(SSL_ERR_IO, lib, "set SNI host name failed"));
  }
}

/// Advance the handshake one step (SSL_accept for server, SSL_connect for
/// client).  Ok(done) when the handshake finished; Ok(want) with
/// SSL_WANT_READ/WRITE when the caller must wait on its transport first
/// (a socket poll, a memory-BIO byte hand-off, ...); Err on a fatal
/// failure (kind SSL_ERR_HANDSHAKE, carrying the verify result when
/// non-OK).
/// Complexity: O(handshake progress).
pub fn ssl_step(lib: &SslLibrary, s: &SslStream, server: Bool) -> Result[SslStep, SslError]
  requires: lib.handle != 0
  requires: s.ssl != 0
{
  unsafe {
    var rc: Int32 = 0;
    if server {
      let f = lib.p_accept as fn(Int) -> Int32;
      rc = f(s.ssl);
    } else {
      let f = lib.p_connect as fn(Int) -> Int32;
      rc = f(s.ssl);
    }
    if rc == 1 {
      return Ok(SslStep{ done: true; want: SSL_WANT_NONE });
    }
    let fe = lib.p_get_error as fn(Int, Int32) -> Int32;
    let err = fe(s.ssl, rc) as Int;
    if err == SSL_ERROR_WANT_READ {
      return Ok(SslStep{ done: false; want: SSL_WANT_READ });
    }
    if err == SSL_ERROR_WANT_WRITE {
      return Ok(SslStep{ done: false; want: SSL_WANT_WRITE });
    }
    if err == SSL_ERROR_ZERO_RETURN {
      return Err(SslError{ kind: SSL_ERR_HANDSHAKE; message: "handshake: peer closed the connection" });
    }
    return Err(hs_err(lib, s.ssl));
  }
}

/// Read up to `max` plaintext bytes.  Ok(empty vector) means the peer
/// closed cleanly (close_notify, SSL_ERROR_ZERO_RETURN).  On a stream with
/// a bound fd the call waits (poll on WANT_READ/WANT_WRITE, bounded); on a
/// memory-BIO stream a WANT state is reported as the typed
/// SSL_ERR_WANT_READ/WRITE error so the caller can feed bytes.
/// Complexity: O(n + wait).
pub fn ssl_read(lib: &SslLibrary, s: &SslStream, max: Int) -> Result[Vec[UInt8], SslError]
  requires: lib.handle != 0
  requires: s.ssl != 0
  requires: max > 0
  requires: max <= 65536
{
  unsafe {
    var buf = slot(max);
    let f = lib.p_read as fn(Int, *UInt8, Int) -> Int32;
    let fe = lib.p_get_error as fn(Int, Int32) -> Int32;
    var i = 0;
    while i < 4000 {
      let rc = f(s.ssl, buf.as_mut_ptr(), max) as Int;
      if rc > 0 {
        var out: Vec[UInt8] = Vec[UInt8].new();
        var j = 0;
        while j < rc {
          out.push(buf[j]);
          j = j + 1;
        }
        return Ok(out);
      }
      let err = fe(s.ssl, rc as Int32) as Int;
      if err == SSL_ERROR_ZERO_RETURN {
        var empty: Vec[UInt8] = Vec[UInt8].new();
        return Ok(empty);
      }
      if err == SSL_ERROR_WANT_READ {
        if s.fd < 0 {
          return Err(SslError{ kind: SSL_ERR_WANT_READ; message: "ssl_read: no data available (memory BIO -- feed with ssl_bio_feed)" });
        }
        var fds: Vec[Int] = Vec[Int].new();
        fds.push(s.fd);
        let pr = socket_poll_read(&fds, 25);
        let _ = pr;
      } elif err == SSL_ERROR_WANT_WRITE {
        if s.fd < 0 {
          return Err(SslError{ kind: SSL_ERR_WANT_WRITE; message: "ssl_read: retry when writable (memory BIO)" });
        }
        var wfds: Vec[Int] = Vec[Int].new();
        wfds.push(s.fd);
        let pw = socket_poll_write(&wfds, 25);
        let _ = pw;
      } else {
        return Err(ssl_err(SSL_ERR_IO, lib, "ssl_read failed"));
      }
      i = i + 1;
    }
    return Err(SslError{ kind: SSL_ERR_WANT_READ; message: "ssl_read: timed out waiting for data" });
  }
}

/// Write every byte of `data` (retrying partial writes; on a bound fd the
/// WANT states wait on a poll, bounded).  Returns the byte count written
/// (data.len()).
/// Complexity: O(n + wait).
pub fn ssl_write(lib: &SslLibrary, s: &SslStream, data: &Vec[UInt8]) -> Result[Int, SslError]
  requires: lib.handle != 0
  requires: s.ssl != 0
{
  let n = data.len();
  if n == 0 { return Ok(0); }
  unsafe {
    let f = lib.p_write as fn(Int, *UInt8, Int) -> Int32;
    let fe = lib.p_get_error as fn(Int, Int32) -> Int32;
    var total = 0;
    var i = 0;
    while i < 8000 {
      if total == n { return Ok(total); }
      let rc = f(s.ssl, &data[total] as *UInt8, n - total) as Int;
      if rc > 0 {
        total = total + rc;
        continue;
      }
      let err = fe(s.ssl, rc as Int32) as Int;
      if err == SSL_ERROR_WANT_READ {
        if s.fd < 0 {
          return Err(SslError{ kind: SSL_ERR_WANT_READ; message: "ssl_write: retry when readable (memory BIO)" });
        }
        var fds: Vec[Int] = Vec[Int].new();
        fds.push(s.fd);
        let pr = socket_poll_read(&fds, 25);
        let _ = pr;
      } elif err == SSL_ERROR_WANT_WRITE {
        if s.fd < 0 {
          return Err(SslError{ kind: SSL_ERR_WANT_WRITE; message: "ssl_write: retry when writable (memory BIO)" });
        }
        var wfds: Vec[Int] = Vec[Int].new();
        wfds.push(s.fd);
        let pw = socket_poll_write(&wfds, 25);
        let _ = pw;
      } else {
        return Err(ssl_err(SSL_ERR_IO, lib, "ssl_write failed"));
      }
      i = i + 1;
    }
    return Err(SslError{ kind: SSL_ERR_IO; message: "ssl_write: timed out with " + int_to_str(n - total) + " bytes pending" });
  }
}

/// One SSL_shutdown step.  Ok(0) = close_notify sent, peer's not received
/// yet (call again); Ok(1) = shutdown complete.  WANT states surface as
/// SSL_ERR_WANT_READ/WRITE.
/// Complexity: O(1).
pub fn ssl_shutdown(lib: &SslLibrary, s: &SslStream) -> Result[Int, SslError]
  requires: lib.handle != 0
  requires: s.ssl != 0
{
  unsafe {
    let f = lib.p_shutdown as fn(Int) -> Int32;
    let rc = f(s.ssl) as Int;
    if rc >= 0 { return Ok(rc); }
    let fe = lib.p_get_error as fn(Int, Int32) -> Int32;
    let err = fe(s.ssl, rc as Int32) as Int;
    if err == SSL_ERROR_WANT_READ {
      return Err(SslError{ kind: SSL_ERR_WANT_READ; message: "ssl_shutdown: waiting for the peer's close_notify" });
    }
    if err == SSL_ERROR_WANT_WRITE {
      return Err(SslError{ kind: SSL_ERR_WANT_WRITE; message: "ssl_shutdown: retry when writable" });
    }
    if err == SSL_ERROR_ZERO_RETURN {
      return Ok(1);
    }
    return Err(ssl_err(SSL_ERR_IO, lib, "ssl_shutdown failed"));
  }
}

/// Negotiated protocol version of the connection ("" before one exists).
/// Complexity: O(1).
pub fn ssl_get_version(lib: &SslLibrary, s: &SslStream) -> Str
  requires: lib.handle != 0
  requires: s.ssl != 0
{
  unsafe {
    let f = lib.p_get_version as fn(Int) -> *UInt8;
    let p = f(s.ssl);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// Negotiated cipher suite name ("" before handshake completion).
/// Complexity: O(1).
pub fn ssl_get_cipher(lib: &SslLibrary, s: &SslStream) -> Str
  requires: lib.handle != 0
  requires: s.ssl != 0
{
  unsafe {
    let f1 = lib.p_get_current_cipher as fn(Int) -> Int;
    let c = f1(s.ssl);
    if c == 0 { return ""; }
    let f2 = lib.p_cipher_get_name as fn(Int) -> *UInt8;
    let p = f2(c);
    if (p as Int) == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// Raw X509 verification result of the connection (X509_V_OK == 0).
/// Complexity: O(1).
pub fn ssl_get_verify_result(lib: &SslLibrary, s: &SslStream) -> Int
  requires: lib.handle != 0
  requires: s.ssl != 0
{
  unsafe {
    let f = lib.p_get_verify_result as fn(Int) -> Int;
    return f(s.ssl);
  }
}

/// The negotiated ALPN protocol ("" when none was selected).  The length
/// comes from OpenSSL's out-parameter slot; the bytes copy out through the
/// ffi SafePtr bounds-checked reader.
/// Complexity: O(len).
pub fn ssl_alpn_selected(lib: &SslLibrary, s: &SslStream) -> Result[Str, SslError]
  requires: lib.handle != 0
  requires: s.ssl != 0
{
  unsafe {
    var data_slot = slot(8);
    var len_slot = slot(8);
    let f = lib.p_get0_alpn_selected as fn(Int, *UInt8, *UInt8) -> Unit;
    f(s.ssl, data_slot.as_mut_ptr(), len_slot.as_mut_ptr());
    let p = rd_u64_le(&data_slot, 0);
    let n = rd_u32_le(&len_slot, 0);
    if p == 0 || n == 0 { return Ok(""); }
    let sp = ffi.safe_ptr_from_raw(p as *UInt8, n);
    if !sp.is_ok {
      return Err(SslError{ kind: SSL_ERR_IO; message: "alpn read: " + sp.error });
    }
    let spv: SafePtr = sp.value;
    var bytes: Vec[UInt8] = Vec[UInt8].new();
    var i = 0;
    while i < n {
      let rb = ffi.safe_ptr_read_byte(&spv, i);
      if !rb.is_ok {
        return Err(SslError{ kind: SSL_ERR_IO; message: "alpn read: " + rb.error });
      }
      bytes.push(rb.value as UInt8);
      i = i + 1;
    }
    return Ok(Str::from_utf8(bytes));
  }
}
