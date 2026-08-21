// XIOM -- OpenSSL Binding (TLS / Cryptography)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Phase 4 (Enterprise): Pure SPEC -> implementation.
// Provides safe XIOM wrappers over system-installed libssl / libcrypto.
// All C-interop goes through extern "C" -> unsafe blocks.

module xiom.openssl

use xiom.string;
use xiom.core;

// -- Opaque handle types -----------------------------------------------------

pub type SslContext    = Int;
pub type SslConnection = Int;
pub type SslBio        = Int;

// -- Error type --------------------------------------------------------------

pub type SslError = {
  code: Int;
  message: Str;
}

// -- Extern "C" block (libssl + libcrypto) -----------------------------------

extern "C" {
  fn malloc(size: UInt) -> *UInt8;
  fn free(ptr: *UInt8);

  // Init / teardown
  fn SSL_library_init() -> Int;
  fn SSL_load_error_strings();

  // Method
  fn TLS_client_method() -> *UInt8;

  // Context
  fn SSL_CTX_new(method: *UInt8) -> Int;
  fn SSL_CTX_free(ctx: Int);

  // Connection lifecycle
  fn SSL_new(ctx: Int) -> Int;
  fn SSL_set_fd(ssl: Int, fd: Int) -> Int;
  fn SSL_set_bio(ssl: Int, rbio: Int, wbio: Int);
  fn SSL_connect(ssl: Int) -> Int;
  fn SSL_accept(ssl: Int) -> Int;
  fn SSL_shutdown(ssl: Int) -> Int;
  fn SSL_free(ssl: Int);

  // I/O
  fn SSL_read(ssl: Int, buf: *UInt8, num: Int) -> Int;
  fn SSL_write(ssl: Int, buf: *UInt8, num: Int) -> Int;

  // BIO (for internal connect)
  fn BIO_new_connect(host_port: *UInt8) -> Int;
  fn BIO_read(bio: Int, buf: *UInt8, num: Int) -> Int;
  fn BIO_write(bio: Int, buf: *UInt8, num: Int) -> Int;
  fn BIO_free(bio: Int) -> Int;

  // Error reporting
  fn ERR_get_error() -> Int;
  fn ERR_error_string(e: Int, buf: *UInt8) -> *UInt8;

  // Hashing (crypto)
  fn SHA256(d: *UInt8, n: UInt, md: *UInt8) -> *UInt8;
  fn EVP_MD_CTX_new() -> Int;
}

// -- Safe wrappers -----------------------------------------------------------

pub fn init() {
  unsafe {
    SSL_library_init();
    SSL_load_error_strings();
  }
}

/// Allocate a new client-side SSL context.
/// method: raw pointer to a TLS method (e.g. TLS_client_method()).
pub fn ctx_new(method: Int) -> SslContext
  requires: method != 0
{
  unsafe {
    let raw = SSL_CTX_new(method as *UInt8);
    return raw;
  }
}

/// Allocate a new client-side SSL context with TLS client method.
/// Convenience wrapper -- calls init() + TLS_client_method() + ctx_new().
pub fn ctx_new_client() -> SslContext {
  init();
  unsafe {
    let method = TLS_client_method();
    let ctx = SSL_CTX_new(method);
    return ctx;
  }
}

/// Establish a TLS connection to host:port.
/// Internally builds a C-string, creates a BIO + SSL object wired together.
/// The returned SslConnection must be freed via ssl_shutdown + ssl_free.
pub fn connect(ctx: SslContext, host: Str, port: Int) -> Result[SslConnection, SslError]
  requires: host.len() > 0
  requires: port > 0
{
  var host_port = host + ":" + core.to_string(port);
  var cstr: [1024]UInt8;
  var i = 0;
  let hlen = host_port.len();
  while i < hlen && i < 1023 {
    cstr[i] = host_port.byte_at(i);
    i = i + 1;
  }
  cstr[i] = 0 as UInt8;
  unsafe {
    let bio = BIO_new_connect(&cstr as *UInt8);
    if bio == 0 {
      return Err(SslError{ code: -1; message: "BIO_new_connect failed"; });
    }
    let ssl = SSL_new(ctx);
    if ssl == 0 {
      BIO_free(bio);
      return Err(SslError{ code: -2; message: "SSL_new failed"; });
    }
    SSL_set_bio(ssl, bio, bio);
    let rc = SSL_connect(ssl);
    if rc <= 0 {
      let err_code = ERR_get_error();
      SSL_free(ssl);
      return Err(SslError{ code: err_code; message: "SSL_connect failed"; });
    }
    return Ok(ssl);
  }
}

/// Read up to 4096 bytes from an SSL connection into buf.
/// Returns the number of bytes read.
pub fn read(ssl: SslConnection, buf: &mut Vec[UInt8]) -> Result[Int, SslError]
  requires: ssl != 0
{
  unsafe {
    var recv_buf: [4096]UInt8;
    let n = SSL_read(ssl, &recv_buf as *UInt8, 4096);
    if n <= 0 {
      return Err(SslError{ code: ERR_get_error(); message: "SSL_read failed"; });
    }
    var i = 0;
    while i < n {
      buf.push(recv_buf[i]);
      i = i + 1;
    }
    return Ok(n);
  }
}

/// Write data to an SSL connection.
/// Returns the number of bytes written.
pub fn write(ssl: SslConnection, data: &Vec[UInt8]) -> Result[Int, SslError]
  requires: ssl != 0
  requires: data.len() > 0
{
  var raw_buf: [65536]UInt8;
  var i = 0;
  let dlen = data.len();
  if dlen > 65536 {
    return Err(SslError{ code: -3; message: "data too large for stack buffer"; });
  }
  while i < dlen {
    raw_buf[i] = data[i];
    i = i + 1;
  }
  unsafe {
    let n = SSL_write(ssl, &raw_buf as *UInt8, dlen);
    if n <= 0 {
      return Err(SslError{ code: ERR_get_error(); message: "SSL_write failed"; });
    }
    return Ok(n);
  }
}

/// Accept an SSL connection on an existing fd (server-side).
/// The caller provides an already-connected socket fd.
pub fn accept(ctx: SslContext, fd: Int) -> Result[SslConnection, SslError]
  requires: ctx != 0
  requires: fd >= 0
{
  unsafe {
    let ssl = SSL_new(ctx);
    if ssl == 0 {
      return Err(SslError{ code: -2; message: "SSL_new failed"; });
    }
    if SSL_set_fd(ssl, fd) <= 0 {
      SSL_free(ssl);
      return Err(SslError{ code: ERR_get_error(); message: "SSL_set_fd failed"; });
    }
    if SSL_accept(ssl) <= 0 {
      let err_code = ERR_get_error();
      SSL_free(ssl);
      return Err(SslError{ code: err_code; message: "SSL_accept failed"; });
    }
    return Ok(ssl);
  }
}

/// Graceful SSL shutdown. Returns 0 on success.
pub fn ssl_shutdown(ssl: SslConnection) -> Int
  requires: ssl != 0
{
  unsafe {
    return SSL_shutdown(ssl);
  }
}

/// Free an SSL connection object.
pub fn ssl_free(ssl: SslConnection)
  requires: ssl != 0
{
  unsafe { SSL_free(ssl); }
}

/// Free an SSL context object.
pub fn ctx_free(ctx: SslContext)
  requires: ctx != 0
{
  unsafe { SSL_CTX_free(ctx); }
}

/// Retrieve the last OpenSSL error code.
pub fn get_error_code() -> Int {
  unsafe { return ERR_get_error(); }
}

/// Retrieve a human-readable error string for an OpenSSL error code.
pub fn get_error_string(error_code: Int) -> Str {
  unsafe {
    var buf: [256]UInt8;
    ERR_error_string(error_code, &buf as *UInt8);
    var i = 0;
    while i < 256 && buf[i] != 0 as UInt8 {
      i = i + 1;
    }
    var chars: Vec[UInt8] = Vec[UInt8].new();
    var j = 0;
    while j < i {
      chars.push(buf[j]);
      j = j + 1;
    }
    return Str.from_utf8(chars);
  }
}

/// Compute SHA-256 hash of data.
/// Returns a 32-byte digest.
pub fn sha256(data: &Vec[UInt8]) -> Vec[UInt8]
  requires: data.len() > 0
  ensures:  result.len() == 32
{
  var digest: [32]UInt8;
  unsafe {
    SHA256(data.data, data.len() as UInt, &digest as *UInt8);
  }
  var result = Vec[UInt8].new();
  var i = 0;
  while i < 32 {
    result.push(digest[i]);
    i = i + 1;
  }
  return result;
}

/// Allocate a new EVP message digest context.
pub fn evp_md_ctx_new() -> Int {
  unsafe { return EVP_MD_CTX_new(); }
}

/// BIO connect helper (low-level).
pub fn bio_new_connect(host: Str, port: Int) -> SslBio
  requires: host.len() > 0
  requires: port > 0
{
  var host_port = host + ":" + core.to_string(port);
  var cstr: [1024]UInt8;
  var i = 0;
  let hlen = host_port.len();
  while i < hlen && i < 1023 {
    cstr[i] = host_port.byte_at(i);
    i = i + 1;
  }
  cstr[i] = 0 as UInt8;
  unsafe {
    return BIO_new_connect(&cstr as *UInt8);
  }
}

/// BIO read.
pub fn bio_read(bio: SslBio, buf: &mut Vec[UInt8]) -> Result[Int, SslError]
  requires: bio != 0
{
  unsafe {
    var recv_buf: [4096]UInt8;
    let n = BIO_read(bio, &recv_buf as *UInt8, 4096);
    if n <= 0 {
      return Err(SslError{ code: -4; message: "BIO_read failed"; });
    }
    var i = 0;
    while i < n {
      buf.push(recv_buf[i]);
      i = i + 1;
    }
    return Ok(n);
  }
}

/// BIO write.
pub fn bio_write(bio: SslBio, data: &Vec[UInt8]) -> Result[Int, SslError]
  requires: bio != 0
  requires: data.len() > 0
{
  var raw_buf: [65536]UInt8;
  var i = 0;
  let dlen = data.len();
  if dlen > 65536 {
    return Err(SslError{ code: -3; message: "data too large for stack buffer"; });
  }
  while i < dlen {
    raw_buf[i] = data[i];
    i = i + 1;
  }
  unsafe {
    let n = BIO_write(bio, &raw_buf as *UInt8, dlen);
    if n <= 0 {
      return Err(SslError{ code: -4; message: "BIO_write failed"; });
    }
    return Ok(n);
  }
}

/// BIO free.
pub fn bio_free(bio: SslBio) -> Int
  requires: bio != 0
{
  unsafe { return BIO_free(bio); }
}
