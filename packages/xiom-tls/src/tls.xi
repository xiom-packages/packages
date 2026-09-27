// XIOM -- xiom.tls: TLS record and handshake structure parser (no crypto)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM structural parser for the TLS record layer (RFC 8446 section 5)
// and the TLS 1.2 / 1.3 handshake messages and extensions listed in SPEC.md.
// It performs NO cryptography: no key exchange math, no AEAD, no signatures,
// no certificate validation (that is xiom.pki territory; this module exposes
// the DER slices by offset/length). It copies bytes, reports byte offsets and
// rejects malformed structure with deterministic Err(Str) messages that carry
// the offending offset ("tls: <reason> at <offset>").
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no Vec[StructType], no
//     Vec[fn] dispatch, no `match` in the library (if/elif chains only);
//   * every public type is FLAT: fields are Int/Bool/Vec[Int]/Vec[UInt8]
//     only. A struct field of struct type triggers the "cannot store borrow
//     in struct" warning, so a hello's extension list is returned as bounds
//     (ext_off/ext_end) and the caller parses it with tls_parse_extensions;
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing a Result inside a larger function miscompiles);
//   * every byte read from a Vec[UInt8] is widened with `(x as Int) & 0xFF`;
//   * a struct's Vec field is bound to a typed local before it is passed as
//     a `&Vec[UInt8]` parameter (`&struct.field` is not trusted);
//   * `&mut Int` out-params are avoided (miscompiled): functions return
//     values; TlsHandshakeBuffer has only Vec fields and is mutated through
//     a `&mut TlsHandshakeBuffer` parameter;
//   * 24-bit and 32-bit lengths are composed with explicit multiplication,
//     never with shifts; division is truncating.

module xiom.tls

use xiom.convert.int;

// --------------------------------------------------
//  Record layer constants
// --------------------------------------------------

/// Content type 20: change_cipher_spec.
pub const TLS_CONTENT_TYPE_CHANGE_CIPHER_SPEC: Int = 20;
/// Content type 21: alert.
pub const TLS_CONTENT_TYPE_ALERT: Int = 21;
/// Content type 22: handshake.
pub const TLS_CONTENT_TYPE_HANDSHAKE: Int = 22;
/// Content type 23: application_data.
pub const TLS_CONTENT_TYPE_APPLICATION_DATA: Int = 23;
/// Content type 24: heartbeat.
pub const TLS_CONTENT_TYPE_HEARTBEAT: Int = 24;

/// Record header size in bytes: type(1) version(2) length(2).
pub const TLS_RECORD_HEADER_LEN: Int = 5;
/// Largest legal TLSPlaintext fragment: 2^14.
pub const TLS_MAX_FRAGMENT_LEN: Int = 16384;
/// Handshake message header size in bytes: type(1) length(3).
pub const TLS_HANDSHAKE_HEADER_LEN: Int = 4;

// Legacy protocol version values (0x0301..0x0304). TLS 1.3 records use the
// legacy version 0x0303 on the wire; 0x0304 is accepted structurally.

/// Legacy version 0x0301: TLS 1.0.
pub const TLS_LEGACY_VERSION_TLS10: Int = 769;
/// Legacy version 0x0302: TLS 1.1.
pub const TLS_LEGACY_VERSION_TLS11: Int = 770;
/// Legacy version 0x0303: TLS 1.2.
pub const TLS_LEGACY_VERSION_TLS12: Int = 771;
/// Legacy version 0x0304: TLS 1.3.
pub const TLS_LEGACY_VERSION_TLS13: Int = 772;
/// The version code that means TLS 1.3 in supported_versions.
pub const TLS_VERSION_TLS13: Int = 772;

// --------------------------------------------------
//  Handshake message types
// --------------------------------------------------

/// Handshake type 0: hello_request.
pub const TLS_HS_HELLO_REQUEST: Int = 0;
/// Handshake type 1: client_hello.
pub const TLS_HS_CLIENT_HELLO: Int = 1;
/// Handshake type 2: server_hello.
pub const TLS_HS_SERVER_HELLO: Int = 2;
/// Handshake type 4: new_session_ticket.
pub const TLS_HS_NEW_SESSION_TICKET: Int = 4;
/// Handshake type 5: end_of_early_data.
pub const TLS_HS_END_OF_EARLY_DATA: Int = 5;
/// Handshake type 8: encrypted_extensions.
pub const TLS_HS_ENCRYPTED_EXTENSIONS: Int = 8;
/// Handshake type 11: certificate.
pub const TLS_HS_CERTIFICATE: Int = 11;
/// Handshake type 12: server_key_exchange.
pub const TLS_HS_SERVER_KEY_EXCHANGE: Int = 12;
/// Handshake type 13: certificate_request.
pub const TLS_HS_CERTIFICATE_REQUEST: Int = 13;
/// Handshake type 14: server_hello_done.
pub const TLS_HS_SERVER_HELLO_DONE: Int = 14;
/// Handshake type 15: certificate_verify.
pub const TLS_HS_CERTIFICATE_VERIFY: Int = 15;
/// Handshake type 16: client_key_exchange.
pub const TLS_HS_CLIENT_KEY_EXCHANGE: Int = 16;
/// Handshake type 20: finished.
pub const TLS_HS_FINISHED: Int = 20;
/// Handshake type 24: key_update.
pub const TLS_HS_KEY_UPDATE: Int = 24;
/// Handshake type 25: compressed_certificate.
pub const TLS_HS_COMPRESSED_CERTIFICATE: Int = 25;
/// Handshake type 254: message_hash.
pub const TLS_HS_MESSAGE_HASH: Int = 254;

// --------------------------------------------------
//  Extension types
// --------------------------------------------------

/// Extension 0x0000: server_name (SNI).
pub const TLS_EXT_SERVER_NAME: Int = 0;
/// Extension 0x000a: supported_groups.
pub const TLS_EXT_SUPPORTED_GROUPS: Int = 10;
/// Extension 0x000d: signature_algorithms.
pub const TLS_EXT_SIGNATURE_ALGORITHMS: Int = 13;
/// Extension 0x0010: application_layer_protocol_negotiation (ALPN).
pub const TLS_EXT_ALPN: Int = 16;
/// Extension 0x0029: pre_shared_key (must be the last extension).
pub const TLS_EXT_PRE_SHARED_KEY: Int = 41;
/// Extension 0x002b: supported_versions.
pub const TLS_EXT_SUPPORTED_VERSIONS: Int = 43;
/// Extension 0x0033: key_share.
pub const TLS_EXT_KEY_SHARE: Int = 51;

// --------------------------------------------------
//  Alert levels
// --------------------------------------------------

/// Alert level 1: warning.
pub const TLS_ALERT_LEVEL_WARNING: Int = 1;
/// Alert level 2: fatal.
pub const TLS_ALERT_LEVEL_FATAL: Int = 2;

// --------------------------------------------------
//  Parsed structure types (all flat; see the module header)
// --------------------------------------------------

/// Parsed TLS record header. `start` is the header offset in the source
/// buffer, `fragment_off` the first fragment byte (start + 5) and `end` the
/// first byte after the fragment (start + 5 + length). `version` is the
/// legacy version in 0x0301..0x0304.
pub type TlsRecord = {
  content_type: Int;
  version: Int;
  length: Int;
  start: Int;
  fragment_off: Int;
  end: Int;
}

/// Parsed handshake message envelope: `msg_type`, the declared 24-bit body
/// `length`, `start` (message offset), `body_off` (start + 4) and `total`
/// (4 + length, the number of consumed bytes).
pub type TlsHandshake = {
  msg_type: Int;
  length: Int;
  start: Int;
  body_off: Int;
  total: Int;
}

/// Parsed alert: `level` (1 warning, 2 fatal) and `description` code. The
/// description is not restricted to the known catalog; use
/// tls_alert_level_name / tls_alert_description_name for labels.
pub type TlsAlert = {
  level: Int;
  description: Int;
}

/// Flat extension list. Extension `i` has type `types[i]`, length `lens[i]`
/// and its raw body bytes are the `lens[i]` bytes of `bytes` starting at
/// `starts[i]`. Unknown extensions are preserved verbatim in `bytes`.
pub type TlsExtensions = {
  types: Vec[Int];
  starts: Vec[Int];
  lens: Vec[Int];
  bytes: Vec[UInt8];
}

/// Parsed ClientHello. `random` is the 32-byte random; `session_id` 0..32
/// bytes; `cipher_suites` and `compression_methods` are the advertised
/// values. When `ext_present` is true the extension block occupies
/// [ext_off, ext_end) in the source buffer and starts with its 16-bit list
/// length; parse it with tls_parse_extensions. `total` is 4 + body length.
pub type TlsClientHello = {
  legacy_version: Int;
  random: Vec[UInt8];
  session_id: Vec[UInt8];
  cipher_suites: Vec[Int];
  compression_methods: Vec[Int];
  ext_present: Bool;
  ext_off: Int;
  ext_end: Int;
  total: Int;
}

/// Parsed ServerHello, same shape as TlsClientHello except the server picks
/// one `cipher_suite` and one `compression_method`.
pub type TlsServerHello = {
  legacy_version: Int;
  random: Vec[UInt8];
  session_id: Vec[UInt8];
  cipher_suite: Int;
  compression_method: Int;
  ext_present: Bool;
  ext_off: Int;
  ext_end: Int;
  total: Int;
}

/// Parsed EncryptedExtensions (TLS 1.3): the body is exactly one extension
/// block that occupies [body_off, body_off + list_len + 2) in the source
/// buffer; `total` is 4 + body length.
pub type TlsEncryptedExtensions = {
  body_off: Int;
  list_len: Int;
  total: Int;
}

/// Parsed Certificate (TLS 1.2 shape): a 24-bit certificate-list length and
/// 24-bit certificate entries. Certificate `i` is the `cert_lens[i]` DER
/// bytes of the source buffer starting at `cert_starts[i]` (absolute
/// offsets). `list_len` is the declared list length; `total` is 4 + body.
pub type TlsCertificate = {
  body_off: Int;
  list_len: Int;
  cert_starts: Vec[Int];
  cert_lens: Vec[Int];
  total: Int;
}

/// Parsed ServerKeyExchange / ClientKeyExchange body (opaque). `curve_type`
/// and `named_curve` are hints: for an ECDHE ServerKeyExchange the first
/// byte is curve_type 3 (named_curve) followed by the 16-bit group id. For
/// every other shape both are -1 and the body stays opaque.
pub type TlsKeyExchange = {
  msg_type: Int;
  curve_type: Int;
  named_curve: Int;
  body_off: Int;
  body_len: Int;
  total: Int;
}

/// Parsed Finished body (opaque verify_data slice).
pub type TlsFinished = {
  body_off: Int;
  body_len: Int;
  total: Int;
}

/// Parsed NewSessionTicket (TLS 1.3 shape): lifetime and age_add are 32-bit,
/// the nonce and ticket are slices of the source buffer, and the trailing
/// extension block occupies [ext_off, ext_end).
pub type TlsNewSessionTicket = {
  lifetime: Int;
  age_add: Int;
  nonce_off: Int;
  nonce_len: Int;
  ticket_off: Int;
  ticket_len: Int;
  ext_off: Int;
  ext_end: Int;
  total: Int;
}

/// Reassembly buffer for handshake bytes that span records. `messages` holds
/// every completed handshake message (header included) concatenated in
/// arrival order; message `i` starts at `starts[i]` and is `lens[i]` bytes
/// long. `pending` holds the incomplete trailing bytes.
pub type TlsHandshakeBuffer = {
  pending: Vec[UInt8];
  messages: Vec[UInt8];
  starts: Vec[Int];
  lens: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[TlsRecord, Str].
fn _ok_rec(v: TlsRecord) -> Result[TlsRecord, Str] {
  return Ok(v);
}

// Err(m) for Result[TlsRecord, Str].
fn _err_rec(m: Str) -> Result[TlsRecord, Str] {
  return Err(m);
}

// Ok(v) for Result[TlsHandshake, Str].
fn _ok_hs(v: TlsHandshake) -> Result[TlsHandshake, Str] {
  return Ok(v);
}

// Err(m) for Result[TlsHandshake, Str].
fn _err_hs(m: Str) -> Result[TlsHandshake, Str] {
  return Err(m);
}

// Ok(v) for Result[TlsAlert, Str].
fn _ok_alert(v: TlsAlert) -> Result[TlsAlert, Str] {
  return Ok(v);
}

// Err(m) for Result[TlsAlert, Str].
fn _err_alert(m: Str) -> Result[TlsAlert, Str] {
  return Err(m);
}

// Ok(v) for Result[TlsExtensions, Str].
fn _ok_exts(v: TlsExtensions) -> Result[TlsExtensions, Str] {
  return Ok(v);
}

// Err(m) for Result[TlsExtensions, Str].
fn _err_exts(m: Str) -> Result[TlsExtensions, Str] {
  return Err(m);
}

// Ok(v) for Result[TlsClientHello, Str].
fn _ok_ch(v: TlsClientHello) -> Result[TlsClientHello, Str] {
  return Ok(v);
}

// Err(m) for Result[TlsClientHello, Str].
fn _err_ch(m: Str) -> Result[TlsClientHello, Str] {
  return Err(m);
}

// Ok(v) for Result[TlsServerHello, Str].
fn _ok_sh(v: TlsServerHello) -> Result[TlsServerHello, Str] {
  return Ok(v);
}

// Err(m) for Result[TlsServerHello, Str].
fn _err_sh(m: Str) -> Result[TlsServerHello, Str] {
  return Err(m);
}

// Ok(v) for Result[TlsEncryptedExtensions, Str].
fn _ok_ee(v: TlsEncryptedExtensions) -> Result[TlsEncryptedExtensions, Str] {
  return Ok(v);
}

// Err(m) for Result[TlsEncryptedExtensions, Str].
fn _err_ee(m: Str) -> Result[TlsEncryptedExtensions, Str] {
  return Err(m);
}

// Ok(v) for Result[TlsCertificate, Str].
fn _ok_cert(v: TlsCertificate) -> Result[TlsCertificate, Str] {
  return Ok(v);
}

// Err(m) for Result[TlsCertificate, Str].
fn _err_cert(m: Str) -> Result[TlsCertificate, Str] {
  return Err(m);
}

// Ok(v) for Result[TlsKeyExchange, Str].
fn _ok_kx(v: TlsKeyExchange) -> Result[TlsKeyExchange, Str] {
  return Ok(v);
}

// Err(m) for Result[TlsKeyExchange, Str].
fn _err_kx(m: Str) -> Result[TlsKeyExchange, Str] {
  return Err(m);
}

// Ok(v) for Result[TlsFinished, Str].
fn _ok_fin(v: TlsFinished) -> Result[TlsFinished, Str] {
  return Ok(v);
}

// Err(m) for Result[TlsFinished, Str].
fn _err_fin(m: Str) -> Result[TlsFinished, Str] {
  return Err(m);
}

// Ok(v) for Result[TlsNewSessionTicket, Str].
fn _ok_nst(v: TlsNewSessionTicket) -> Result[TlsNewSessionTicket, Str] {
  return Ok(v);
}

// Err(m) for Result[TlsNewSessionTicket, Str].
fn _err_nst(m: Str) -> Result[TlsNewSessionTicket, Str] {
  return Err(m);
}

// Ok(v) for Result[(Int, Int), Str].
fn _ok_pair(v: (Int, Int)) -> Result[(Int, Int), Str] {
  return Ok(v);
}

// Err(m) for Result[(Int, Int), Str].
fn _err_pair(m: Str) -> Result[(Int, Int), Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// "tls: <msg> at <off>" -- every structural error carries its byte offset.
fn _at(msg: Str, off: Int) -> Str {
  return msg + " at " + int_to_base(off, 10);
}

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned big-endian u16 at [pos, pos+2); callers guarantee the bounds.
fn _read_u16(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 256 + _byte(data, pos + 1);
}

// Unsigned big-endian u24 at [pos, pos+3); callers guarantee the bounds.
fn _read_u24(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 65536 + _byte(data, pos + 1) * 256 + _byte(data, pos + 2);
}

// Unsigned big-endian u32 at [pos, pos+4); callers guarantee the bounds.
fn _read_u32(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 16777216 + _byte(data, pos + 1) * 65536 + _byte(data, pos + 2) * 256 + _byte(data, pos + 3);
}

// Append the bytes [start, start+len) of `src` to `out`.
fn _push_range(out: &mut Vec[UInt8], src: &Vec[UInt8], start: Int, len: Int) {
  var i = 0;
  while i < len {
    out.push(src[start + i]);
    i = i + 1;
  }
}

// --------------------------------------------------
//  Names
// --------------------------------------------------

/// Human name of a TLS content type (20..24), or "" when unknown.
/// Complexity: O(1).
pub fn tls_content_type_name(t: Int) -> Str {
  if t == TLS_CONTENT_TYPE_CHANGE_CIPHER_SPEC {
    return "change_cipher_spec";
  }
  if t == TLS_CONTENT_TYPE_ALERT {
    return "alert";
  }
  if t == TLS_CONTENT_TYPE_HANDSHAKE {
    return "handshake";
  }
  if t == TLS_CONTENT_TYPE_APPLICATION_DATA {
    return "application_data";
  }
  if t == TLS_CONTENT_TYPE_HEARTBEAT {
    return "heartbeat";
  }
  return "";
}

/// True when `t` is a record content type accepted by this parser (20..24).
/// Complexity: O(1).
pub fn tls_content_type_ok(t: Int) -> Bool {
  return t >= TLS_CONTENT_TYPE_CHANGE_CIPHER_SPEC && t <= TLS_CONTENT_TYPE_HEARTBEAT;
}

/// Name of a legacy protocol version: "TLS 1.0" (0x0301) through
/// "TLS 1.3" (0x0304), "SSL 3.0" for 0x0300, else "". Complexity: O(1).
pub fn tls_legacy_version_name(v: Int) -> Str {
  if v == 768 {
    return "SSL 3.0";
  }
  if v == TLS_LEGACY_VERSION_TLS10 {
    return "TLS 1.0";
  }
  if v == TLS_LEGACY_VERSION_TLS11 {
    return "TLS 1.1";
  }
  if v == TLS_LEGACY_VERSION_TLS12 {
    return "TLS 1.2";
  }
  if v == TLS_LEGACY_VERSION_TLS13 {
    return "TLS 1.3";
  }
  return "";
}

/// Alias of tls_legacy_version_name. Complexity: O(1).
pub fn tls_version_name(v: Int) -> Str {
  return tls_legacy_version_name(v);
}

/// True when `v` is in the accepted legacy-version range 0x0301..0x0304.
/// Complexity: O(1).
pub fn tls_legacy_version_ok(v: Int) -> Bool {
  return v >= TLS_LEGACY_VERSION_TLS10 && v <= TLS_LEGACY_VERSION_TLS13;
}

/// True when `v` is exactly 0x0304 (the supported_versions code for TLS 1.3).
/// Complexity: O(1).
pub fn tls_version_is_tls13(v: Int) -> Bool {
  return v == TLS_VERSION_TLS13;
}

// True when `t` is one of the handshake message types this parser names.
fn _handshake_type_known(t: Int) -> Bool {
  if t == TLS_HS_HELLO_REQUEST {
    return true;
  }
  if t == TLS_HS_CLIENT_HELLO {
    return true;
  }
  if t == TLS_HS_SERVER_HELLO {
    return true;
  }
  if t == TLS_HS_NEW_SESSION_TICKET {
    return true;
  }
  if t == TLS_HS_END_OF_EARLY_DATA {
    return true;
  }
  if t == TLS_HS_ENCRYPTED_EXTENSIONS {
    return true;
  }
  if t == TLS_HS_CERTIFICATE {
    return true;
  }
  if t == TLS_HS_SERVER_KEY_EXCHANGE {
    return true;
  }
  if t == TLS_HS_CERTIFICATE_REQUEST {
    return true;
  }
  if t == TLS_HS_SERVER_HELLO_DONE {
    return true;
  }
  if t == TLS_HS_CERTIFICATE_VERIFY {
    return true;
  }
  if t == TLS_HS_CLIENT_KEY_EXCHANGE {
    return true;
  }
  if t == TLS_HS_FINISHED {
    return true;
  }
  if t == TLS_HS_KEY_UPDATE {
    return true;
  }
  if t == TLS_HS_COMPRESSED_CERTIFICATE {
    return true;
  }
  if t == TLS_HS_MESSAGE_HASH {
    return true;
  }
  return false;
}

/// Human name of a handshake message type (RFC 8446 section 4), or "" when
/// unknown. Complexity: O(1).
pub fn tls_handshake_type_name(t: Int) -> Str {
  if t == TLS_HS_HELLO_REQUEST {
    return "hello_request";
  }
  if t == TLS_HS_CLIENT_HELLO {
    return "client_hello";
  }
  if t == TLS_HS_SERVER_HELLO {
    return "server_hello";
  }
  if t == TLS_HS_NEW_SESSION_TICKET {
    return "new_session_ticket";
  }
  if t == TLS_HS_END_OF_EARLY_DATA {
    return "end_of_early_data";
  }
  if t == TLS_HS_ENCRYPTED_EXTENSIONS {
    return "encrypted_extensions";
  }
  if t == TLS_HS_CERTIFICATE {
    return "certificate";
  }
  if t == TLS_HS_SERVER_KEY_EXCHANGE {
    return "server_key_exchange";
  }
  if t == TLS_HS_CERTIFICATE_REQUEST {
    return "certificate_request";
  }
  if t == TLS_HS_SERVER_HELLO_DONE {
    return "server_hello_done";
  }
  if t == TLS_HS_CERTIFICATE_VERIFY {
    return "certificate_verify";
  }
  if t == TLS_HS_CLIENT_KEY_EXCHANGE {
    return "client_key_exchange";
  }
  if t == TLS_HS_FINISHED {
    return "finished";
  }
  if t == TLS_HS_KEY_UPDATE {
    return "key_update";
  }
  if t == TLS_HS_COMPRESSED_CERTIFICATE {
    return "compressed_certificate";
  }
  if t == TLS_HS_MESSAGE_HASH {
    return "message_hash";
  }
  return "";
}

/// "warning" for level 1, "fatal" for level 2, else "". Complexity: O(1).
pub fn tls_alert_level_name(level: Int) -> Str {
  if level == TLS_ALERT_LEVEL_WARNING {
    return "warning";
  }
  if level == TLS_ALERT_LEVEL_FATAL {
    return "fatal";
  }
  return "";
}

/// Name of an alert description code (RFC 8446 section 6), or "" when
/// unknown. Complexity: O(1).
pub fn tls_alert_description_name(d: Int) -> Str {
  if d == 0 {
    return "close_notify";
  }
  if d == 10 {
    return "unexpected_message";
  }
  if d == 20 {
    return "bad_record_mac";
  }
  if d == 21 {
    return "decryption_failed";
  }
  if d == 22 {
    return "record_overflow";
  }
  if d == 30 {
    return "decompression_failure";
  }
  if d == 40 {
    return "handshake_failure";
  }
  if d == 41 {
    return "no_certificate";
  }
  if d == 42 {
    return "bad_certificate";
  }
  if d == 43 {
    return "unsupported_certificate";
  }
  if d == 44 {
    return "certificate_revoked";
  }
  if d == 45 {
    return "certificate_expired";
  }
  if d == 46 {
    return "certificate_unknown";
  }
  if d == 47 {
    return "illegal_parameter";
  }
  if d == 48 {
    return "unknown_ca";
  }
  if d == 49 {
    return "access_denied";
  }
  if d == 50 {
    return "decode_error";
  }
  if d == 51 {
    return "decrypt_error";
  }
  if d == 60 {
    return "export_restriction";
  }
  if d == 70 {
    return "protocol_version";
  }
  if d == 71 {
    return "insufficient_security";
  }
  if d == 80 {
    return "internal_error";
  }
  if d == 86 {
    return "inappropriate_fallback";
  }
  if d == 90 {
    return "user_canceled";
  }
  if d == 100 {
    return "no_renegotiation";
  }
  if d == 109 {
    return "missing_extension";
  }
  if d == 110 {
    return "unsupported_extension";
  }
  if d == 111 {
    return "certificate_unobtainable";
  }
  if d == 112 {
    return "unrecognized_name";
  }
  if d == 113 {
    return "bad_certificate_status_response";
  }
  if d == 114 {
    return "bad_certificate_hash_value";
  }
  if d == 115 {
    return "unknown_psk_identity";
  }
  if d == 116 {
    return "certificate_required";
  }
  if d == 120 {
    return "no_application_protocol";
  }
  return "";
}

/// Name of a TLS extension type, or "" when unknown. Complexity: O(1).
pub fn tls_ext_type_name(t: Int) -> Str {
  if t == TLS_EXT_SERVER_NAME {
    return "server_name";
  }
  if t == TLS_EXT_SUPPORTED_GROUPS {
    return "supported_groups";
  }
  if t == TLS_EXT_SIGNATURE_ALGORITHMS {
    return "signature_algorithms";
  }
  if t == TLS_EXT_ALPN {
    return "application_layer_protocol_negotiation";
  }
  if t == TLS_EXT_PRE_SHARED_KEY {
    return "pre_shared_key";
  }
  if t == TLS_EXT_SUPPORTED_VERSIONS {
    return "supported_versions";
  }
  if t == TLS_EXT_KEY_SHARE {
    return "key_share";
  }
  return "";
}

/// Name of a supported group / named curve, or "" when unknown.
/// Complexity: O(1).
pub fn tls_group_name(g: Int) -> Str {
  if g == 22 {
    return "secp256k1";
  }
  if g == 23 {
    return "secp256r1";
  }
  if g == 24 {
    return "secp384r1";
  }
  if g == 25 {
    return "secp521r1";
  }
  if g == 29 {
    return "x25519";
  }
  if g == 30 {
    return "x448";
  }
  if g == 256 {
    return "ffdhe2048";
  }
  if g == 257 {
    return "ffdhe3072";
  }
  if g == 258 {
    return "ffdhe4096";
  }
  if g == 259 {
    return "ffdhe6144";
  }
  if g == 260 {
    return "ffdhe8192";
  }
  return "";
}

/// Name of a signature scheme (RFC 8446 section 4.2.3), or "" when unknown.
/// Complexity: O(1).
pub fn tls_signature_scheme_name(s: Int) -> Str {
  if s == 513 {
    return "rsa_pkcs1_sha1";
  }
  if s == 515 {
    return "ecdsa_sha1";
  }
  if s == 1025 {
    return "rsa_pkcs1_sha256";
  }
  if s == 1027 {
    return "ecdsa_secp256r1_sha256";
  }
  if s == 1281 {
    return "rsa_pkcs1_sha384";
  }
  if s == 1283 {
    return "ecdsa_secp384r1_sha384";
  }
  if s == 1537 {
    return "rsa_pkcs1_sha512";
  }
  if s == 1539 {
    return "ecdsa_secp521r1_sha512";
  }
  if s == 2052 {
    return "rsa_pss_rsae_sha256";
  }
  if s == 2053 {
    return "rsa_pss_rsae_sha384";
  }
  if s == 2054 {
    return "rsa_pss_rsae_sha512";
  }
  if s == 2055 {
    return "ed25519";
  }
  if s == 2056 {
    return "ed448";
  }
  if s == 2057 {
    return "rsa_pss_pss_sha256";
  }
  if s == 2058 {
    return "rsa_pss_pss_sha384";
  }
  if s == 2059 {
    return "rsa_pss_pss_sha512";
  }
  return "";
}

// --------------------------------------------------
//  Record layer
// --------------------------------------------------

/// Parse one TLS record header at `off` and bind its fragment.
///
/// Returns: Ok(record) with `start = off`, `fragment_off = off + 5` and
/// `end = off + 5 + length`. The content type must be 20..24, the legacy
/// version 0x0301..0x0304, the length must be 1..2^14 and the whole fragment
/// must be inside the buffer.
/// Errors, all suffixed " at <offset>": "tls: negative offset" for off < 0;
/// "tls: truncated record header"; "tls: bad content type";
/// "tls: bad record version"; "tls: zero-length record";
/// "tls: record overlength"; "tls: truncated record fragment".
/// Complexity: O(1).
pub fn tls_parse_record(data: &Vec[UInt8], off: Int) -> Result[TlsRecord, Str] {
  if off < 0 {
    return _err_rec("tls: negative offset");
  }
  if off + TLS_RECORD_HEADER_LEN > data.len() {
    return _err_rec(_at("tls: truncated record header", off));
  }
  let ct = _byte(data, off);
  if !tls_content_type_ok(ct) {
    return _err_rec(_at("tls: bad content type", off));
  }
  let ver = _read_u16(data, off + 1);
  if !tls_legacy_version_ok(ver) {
    return _err_rec(_at("tls: bad record version", off));
  }
  let len = _read_u16(data, off + 3);
  if len == 0 {
    return _err_rec(_at("tls: zero-length record", off));
  }
  if len > TLS_MAX_FRAGMENT_LEN {
    return _err_rec(_at("tls: record overlength", off));
  }
  if off + TLS_RECORD_HEADER_LEN + len > data.len() {
    return _err_rec(_at("tls: truncated record fragment", off));
  }
  return _ok_rec(TlsRecord{
    content_type: ct;
    version: ver;
    length: len;
    start: off;
    fragment_off: off + TLS_RECORD_HEADER_LEN;
    end: off + TLS_RECORD_HEADER_LEN + len;
  });
}

/// Copy of the record fragment bytes. Returns an empty vector when the
/// record's bounds do not fit `data` (a record from a different buffer).
/// Complexity: O(length).
pub fn tls_record_fragment(data: &Vec[UInt8], r: &TlsRecord) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if r.start < 0 || r.length < 0 || r.fragment_off < 0 || r.end > data.len() {
    return out;
  }
  _push_range(&mut out, data, r.fragment_off, r.length);
  return out;
}

// --------------------------------------------------
//  Alert / ChangeCipherSpec
// --------------------------------------------------

/// Decode a two-byte alert body at `off`.
///
/// Returns: Ok(alert) with the level (1 warning / 2 fatal) and description
/// code. Unknown description codes are preserved.
/// Errors: "tls: negative offset"; "tls: truncated alert at <offset>" when
/// fewer than two bytes are available; "tls: bad alert level at <offset>"
/// when the level is neither 1 nor 2.
/// Complexity: O(1).
pub fn tls_parse_alert(data: &Vec[UInt8], off: Int) -> Result[TlsAlert, Str] {
  if off < 0 {
    return _err_alert("tls: negative offset");
  }
  if off + 2 > data.len() {
    return _err_alert(_at("tls: truncated alert", off));
  }
  let level = _byte(data, off);
  let desc = _byte(data, off + 1);
  if level != TLS_ALERT_LEVEL_WARNING && level != TLS_ALERT_LEVEL_FATAL {
    return _err_alert(_at("tls: bad alert level", off));
  }
  return _ok_alert(TlsAlert{ level: level; description: desc; });
}

/// Decode a ChangeCipherSpec body: exactly one byte, 0x01.
///
/// Errors: "tls: negative offset"; "tls: truncated change cipher spec at
/// <offset>"; "tls: bad change cipher spec byte at <offset>".
/// Complexity: O(1).
pub fn tls_parse_change_cipher_spec(data: &Vec[UInt8], off: Int) -> Result[Unit, Str] {
  if off < 0 {
    return _err_unit("tls: negative offset");
  }
  if off + 1 > data.len() {
    return _err_unit(_at("tls: truncated change cipher spec", off));
  }
  let b = _byte(data, off);
  if b != 1 {
    return _err_unit(_at("tls: bad change cipher spec byte", off));
  }
  return _ok_unit();
}

// --------------------------------------------------
//  Extension block
// --------------------------------------------------

/// Parse an extension block: a 16-bit list length at `off` followed by
/// `uint16 type, uint16 length, bytes` entries, ending exactly at `end`.
///
/// Returns: Ok(extensions) with every entry's type, length and raw bytes
/// (unknown extensions preserved). If pre_shared_key (0x0029) appears it
/// must be the final extension (RFC 8446 section 4.2.11).
/// Errors: "tls: negative offset"; "tls: extension block out of bounds at
/// <offset>" when `end` exceeds the buffer; "tls: truncated extension block
/// at <offset>" when the length prefix does not fit; "tls: extension block
/// length mismatch at <offset>" when the declared length does not consume
/// [off+2, end); "tls: truncated extension header at <offset>";
/// "tls: truncated extension body at <offset>"; "tls: duplicate extension at
/// <offset>"; "tls: pre_shared_key not last at <offset>".
/// Complexity: O(entries^2 + block length).
pub fn tls_parse_extensions(data: &Vec[UInt8], off: Int, end: Int) -> Result[TlsExtensions, Str] {
  if off < 0 {
    return _err_exts("tls: negative offset");
  }
  if end > data.len() || end < off {
    return _err_exts(_at("tls: extension block out of bounds", off));
  }
  if off + 2 > end {
    return _err_exts(_at("tls: truncated extension block", off));
  }
  let total = _read_u16(data, off);
  if off + 2 + total != end {
    return _err_exts(_at("tls: extension block length mismatch", off));
  }
  var types = Vec[Int].new();
  var starts = Vec[Int].new();
  var lens = Vec[Int].new();
  var bytes = Vec[UInt8].new();
  var pos = off + 2;
  while pos < end {
    if pos + 4 > end {
      return _err_exts(_at("tls: truncated extension header", pos));
    }
    let t = _read_u16(data, pos);
    let l = _read_u16(data, pos + 2);
    if pos + 4 + l > end {
      return _err_exts(_at("tls: truncated extension body", pos));
    }
    let i = 0;
    while i < types.len() {
      let prev: Int = types[i];
      if prev == t {
        return _err_exts(_at("tls: duplicate extension", pos));
      }
      i = i + 1;
    }
    if t == TLS_EXT_PRE_SHARED_KEY && pos + 4 + l != end {
      return _err_exts(_at("tls: pre_shared_key not last", pos));
    }
    types.push(t);
    starts.push(bytes.len());
    lens.push(l);
    _push_range(&mut bytes, data, pos + 4, l);
    pos = pos + 4 + l;
  }
  return _ok_exts(TlsExtensions{ types: types; starts: starts; lens: lens; bytes: bytes; });
}

/// Number of extensions in `e`. Complexity: O(1).
pub fn tls_ext_count(e: &TlsExtensions) -> Int {
  return e.types.len();
}

/// Type code of extension `i`, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn tls_ext_type_at(e: &TlsExtensions, i: Int) -> Int {
  if i < 0 || i >= e.types.len() {
    return -1;
  }
  let t: Int = e.types[i];
  return t;
}

/// Body length of extension `i`, or -1 when `i` is out of range.
/// Complexity: O(1).
pub fn tls_ext_len(e: &TlsExtensions, i: Int) -> Int {
  if i < 0 || i >= e.lens.len() {
    return -1;
  }
  let l: Int = e.lens[i];
  return l;
}

/// Raw body bytes of extension `i` (a copy), or an empty vector when `i` is
/// out of range or its range does not fit. Complexity: O(length).
pub fn tls_ext_bytes(e: &TlsExtensions, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 || i >= e.types.len() || i >= e.starts.len() || i >= e.lens.len() {
    return out;
  }
  let s: Int = e.starts[i];
  let l: Int = e.lens[i];
  let pool: Vec[UInt8] = e.bytes;
  if s < 0 || l < 0 || s + l > pool.len() {
    return out;
  }
  _push_range(&mut out, &pool, s, l);
  return out;
}

/// Index of the first extension of type `t`, or -1 when absent.
/// Complexity: O(entries).
pub fn tls_ext_find(e: &TlsExtensions, t: Int) -> Int {
  var i = 0;
  while i < e.types.len() {
    let cur: Int = e.types[i];
    if cur == t {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when the stored range of extension `i` fits the byte pool.
fn _ext_range_ok(e: &TlsExtensions, i: Int) -> Bool {
  if i < 0 || i >= e.types.len() || i >= e.starts.len() || i >= e.lens.len() {
    return false;
  }
  let s: Int = e.starts[i];
  let l: Int = e.lens[i];
  if s < 0 || l < 0 || s + l > e.bytes.len() {
    return false;
  }
  return true;
}

// True when [s, s+l) is a well-formed ServerNameList: u16 list length equal
// to l-2, then (name_type, u16 length, bytes) entries that end exactly at
// s + l.
fn _sni_list_ok(pool: &Vec[UInt8], s: Int, l: Int) -> Bool {
  if l < 2 {
    return false;
  }
  if _read_u16(pool, s) != l - 2 {
    return false;
  }
  var pos = s + 2;
  let end = s + l;
  while pos < end {
    if pos + 3 > end {
      return false;
    }
    let nl = _read_u16(pool, pos + 1);
    pos = pos + 3;
    if pos + nl > end {
      return false;
    }
    pos = pos + nl;
  }
  return pos == end;
}

/// SNI host name of extension `i` (bytes of the first host_name ServerName),
/// or an empty vector when `i` is not a well-formed server_name extension.
/// Complexity: O(length).
pub fn tls_ext_sni_host_name(e: &TlsExtensions, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if !_ext_range_ok(e, i) {
    return out;
  }
  let t: Int = e.types[i];
  if t != TLS_EXT_SERVER_NAME {
    return out;
  }
  let s: Int = e.starts[i];
  let l: Int = e.lens[i];
  let pool: Vec[UInt8] = e.bytes;
  if !_sni_list_ok(&pool, s, l) {
    return out;
  }
  let name_type = _byte(&pool, s + 2);
  if name_type != 0 {
    return out;
  }
  let nl = _read_u16(&pool, s + 3);
  _push_range(&mut out, &pool, s + 5, nl);
  return out;
}

// Read a u16 list body: [s, s+l) must be u16 list_len followed by
// list_len/2 big-endian u16 values with list_len == l - 2 and even.
fn _read_u16_list(pool: &Vec[UInt8], s: Int, l: Int, out: &mut Vec[Int]) {
  if l < 2 {
    return;
  }
  let list_len = _read_u16(pool, s);
  if list_len != l - 2 || list_len % 2 != 0 {
    return;
  }
  var pos = s + 2;
  let end = s + l;
  while pos + 2 <= end {
    out.push(_read_u16(pool, pos));
    pos = pos + 2;
  }
}

/// supported_groups values of extension `i` (each 0..65535), or an empty
/// vector when `i` is not a well-formed supported_groups extension.
/// Complexity: O(length).
pub fn tls_ext_supported_groups(e: &TlsExtensions, i: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if !_ext_range_ok(e, i) {
    return out;
  }
  let t: Int = e.types[i];
  if t != TLS_EXT_SUPPORTED_GROUPS {
    return out;
  }
  let s: Int = e.starts[i];
  let l: Int = e.lens[i];
  let pool: Vec[UInt8] = e.bytes;
  _read_u16_list(&pool, s, l, &mut out);
  return out;
}

/// signature_algorithms values of extension `i`, or an empty vector when
/// `i` is not a well-formed signature_algorithms extension.
/// Complexity: O(length).
pub fn tls_ext_signature_algorithms(e: &TlsExtensions, i: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if !_ext_range_ok(e, i) {
    return out;
  }
  let t: Int = e.types[i];
  if t != TLS_EXT_SIGNATURE_ALGORITHMS {
    return out;
  }
  let s: Int = e.starts[i];
  let l: Int = e.lens[i];
  let pool: Vec[UInt8] = e.bytes;
  _read_u16_list(&pool, s, l, &mut out);
  return out;
}

// True when [s, s+l) is a well-formed ALPN ProtocolNameList.
fn _alpn_list_ok(pool: &Vec[UInt8], s: Int, l: Int) -> Bool {
  if l < 2 {
    return false;
  }
  if _read_u16(pool, s) != l - 2 {
    return false;
  }
  var pos = s + 2;
  let end = s + l;
  while pos < end {
    let el = _byte(pool, pos);
    pos = pos + 1;
    if pos + el > end {
      return false;
    }
    pos = pos + el;
  }
  return pos == end;
}

/// Number of protocol names in an ALPN extension `i`, or 0 when `i` is not
/// a well-formed ALPN extension. Complexity: O(length).
pub fn tls_ext_alpn_count(e: &TlsExtensions, i: Int) -> Int {
  if !_ext_range_ok(e, i) {
    return 0;
  }
  let t: Int = e.types[i];
  if t != TLS_EXT_ALPN {
    return 0;
  }
  let s: Int = e.starts[i];
  let l: Int = e.lens[i];
  let pool: Vec[UInt8] = e.bytes;
  if !_alpn_list_ok(&pool, s, l) {
    return 0;
  }
  var count = 0;
  var pos = s + 2;
  let end = s + l;
  while pos < end {
    let el = _byte(&pool, pos);
    count = count + 1;
    pos = pos + 1 + el;
  }
  return count;
}

/// Protocol name `j` (0-based) of an ALPN extension `i`, or an empty vector
/// when `i` is not a well-formed ALPN extension or `j` is out of range.
/// Complexity: O(length).
pub fn tls_ext_alpn_name(e: &TlsExtensions, i: Int, j: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if !_ext_range_ok(e, i) || j < 0 {
    return out;
  }
  let t: Int = e.types[i];
  if t != TLS_EXT_ALPN {
    return out;
  }
  let s: Int = e.starts[i];
  let l: Int = e.lens[i];
  let pool: Vec[UInt8] = e.bytes;
  if !_alpn_list_ok(&pool, s, l) {
    return out;
  }
  var pos = s + 2;
  let end = s + l;
  var idx = 0;
  while pos < end {
    let el = _byte(&pool, pos);
    if idx == j {
      _push_range(&mut out, &pool, pos + 1, el);
      return out;
    }
    idx = idx + 1;
    pos = pos + 1 + el;
  }
  return out;
}

/// supported_versions list of a ClientHello extension `i` (each a u16
/// version code), or an empty vector when `i` is not the ClientHello shape
/// (one-byte list length followed by u16 values). For the ServerHello shape
/// use tls_ext_selected_version. Complexity: O(length).
pub fn tls_ext_supported_versions(e: &TlsExtensions, i: Int) -> Vec[Int] {
  var out = Vec[Int].new();
  if !_ext_range_ok(e, i) {
    return out;
  }
  let t: Int = e.types[i];
  if t != TLS_EXT_SUPPORTED_VERSIONS {
    return out;
  }
  let s: Int = e.starts[i];
  let l: Int = e.lens[i];
  let pool: Vec[UInt8] = e.bytes;
  if l < 1 {
    return out;
  }
  let list_len = _byte(&pool, s);
  if list_len != l - 1 || list_len % 2 != 0 {
    return out;
  }
  var pos = s + 1;
  let end = s + l;
  while pos + 2 <= end {
    out.push(_read_u16(&pool, pos));
    pos = pos + 2;
  }
  return out;
}

/// Selected version of a ServerHello supported_versions extension `i`
/// (exactly two body bytes), or -1 when `i` is not that shape.
/// Complexity: O(1).
pub fn tls_ext_selected_version(e: &TlsExtensions, i: Int) -> Int {
  if !_ext_range_ok(e, i) {
    return -1;
  }
  let t: Int = e.types[i];
  if t != TLS_EXT_SUPPORTED_VERSIONS {
    return -1;
  }
  let l: Int = e.lens[i];
  if l != 2 {
    return -1;
  }
  let s: Int = e.starts[i];
  let pool: Vec[UInt8] = e.bytes;
  return _read_u16(&pool, s);
}

// True when [s, s+l) is a well-formed ClientHello key_share list: u16 list
// length equal to l-2, then (u16 group, u16 key length, bytes) entries that
// end exactly at s + l.
fn _key_share_list_ok(pool: &Vec[UInt8], s: Int, l: Int) -> Bool {
  if l < 2 {
    return false;
  }
  if _read_u16(pool, s) != l - 2 {
    return false;
  }
  var pos = s + 2;
  let end = s + l;
  while pos < end {
    if pos + 4 > end {
      return false;
    }
    let kl = _read_u16(pool, pos + 2);
    pos = pos + 4;
    if pos + kl > end {
      return false;
    }
    pos = pos + kl;
  }
  return pos == end;
}

/// Number of key_share entries of a ClientHello extension `i`, or 0 when
/// `i` is not the ClientHello shape. Complexity: O(length).
pub fn tls_ext_key_share_count(e: &TlsExtensions, i: Int) -> Int {
  if !_ext_range_ok(e, i) {
    return 0;
  }
  let t: Int = e.types[i];
  if t != TLS_EXT_KEY_SHARE {
    return 0;
  }
  let s: Int = e.starts[i];
  let l: Int = e.lens[i];
  let pool: Vec[UInt8] = e.bytes;
  if !_key_share_list_ok(&pool, s, l) {
    return 0;
  }
  var count = 0;
  var pos = s + 2;
  let end = s + l;
  while pos < end {
    let kl = _read_u16(&pool, pos + 2);
    count = count + 1;
    pos = pos + 4 + kl;
  }
  return count;
}

/// Group id of key_share entry `j` of a ClientHello extension `i`, or -1
/// when `i` is not the ClientHello shape or `j` is out of range.
/// Complexity: O(length).
pub fn tls_ext_key_share_group_at(e: &TlsExtensions, i: Int, j: Int) -> Int {
  if !_ext_range_ok(e, i) || j < 0 {
    return -1;
  }
  let t: Int = e.types[i];
  if t != TLS_EXT_KEY_SHARE {
    return -1;
  }
  let s: Int = e.starts[i];
  let l: Int = e.lens[i];
  let pool: Vec[UInt8] = e.bytes;
  if !_key_share_list_ok(&pool, s, l) {
    return -1;
  }
  var pos = s + 2;
  let end = s + l;
  var idx = 0;
  while pos < end {
    let g = _read_u16(&pool, pos);
    let kl = _read_u16(&pool, pos + 2);
    if idx == j {
      return g;
    }
    idx = idx + 1;
    pos = pos + 4 + kl;
  }
  return -1;
}

/// Key exchange bytes of key_share entry `j` of a ClientHello extension `i`
/// (a copy), or an empty vector when `i` is not the ClientHello shape or `j`
/// is out of range. Complexity: O(length).
pub fn tls_ext_key_share_bytes(e: &TlsExtensions, i: Int, j: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if !_ext_range_ok(e, i) || j < 0 {
    return out;
  }
  let t: Int = e.types[i];
  if t != TLS_EXT_KEY_SHARE {
    return out;
  }
  let s: Int = e.starts[i];
  let l: Int = e.lens[i];
  let pool: Vec[UInt8] = e.bytes;
  if !_key_share_list_ok(&pool, s, l) {
    return out;
  }
  var pos = s + 2;
  let end = s + l;
  var idx = 0;
  while pos < end {
    let kl = _read_u16(&pool, pos + 2);
    if idx == j {
      _push_range(&mut out, &pool, pos + 4, kl);
      return out;
    }
    idx = idx + 1;
    pos = pos + 4 + kl;
  }
  return out;
}

/// Selected group of a HelloRetryRequest key_share extension `i` (exactly
/// two body bytes), or -1 when `i` is not that shape. Complexity: O(1).
pub fn tls_ext_key_share_selected_group(e: &TlsExtensions, i: Int) -> Int {
  if !_ext_range_ok(e, i) {
    return -1;
  }
  let t: Int = e.types[i];
  if t != TLS_EXT_KEY_SHARE {
    return -1;
  }
  let l: Int = e.lens[i];
  if l != 2 {
    return -1;
  }
  let s: Int = e.starts[i];
  let pool: Vec[UInt8] = e.bytes;
  return _read_u16(&pool, s);
}

// --------------------------------------------------
//  Handshake envelope and messages
// --------------------------------------------------

/// Parse the four-byte handshake header at `off`: message type, 24-bit body
/// length and the body bounds.
///
/// Returns: Ok(message) with `start = off`, `body_off = off + 4` and
/// `total = 4 + length` (the consumed byte count; the next message starts at
/// `start + total`). The message type must be one named in SPEC.md and the
/// declared body must fit the buffer.
/// Errors: "tls: negative offset"; "tls: truncated handshake header at
/// <offset>"; "tls: bad handshake type at <offset>"; "tls: truncated
/// handshake body at <offset>".
/// Complexity: O(1).
pub fn tls_parse_handshake(data: &Vec[UInt8], off: Int) -> Result[TlsHandshake, Str] {
  if off < 0 {
    return _err_hs("tls: negative offset");
  }
  if off + TLS_HANDSHAKE_HEADER_LEN > data.len() {
    return _err_hs(_at("tls: truncated handshake header", off));
  }
  let t = _byte(data, off);
  if !_handshake_type_known(t) {
    return _err_hs(_at("tls: bad handshake type", off));
  }
  let len = _read_u24(data, off + 1);
  if off + TLS_HANDSHAKE_HEADER_LEN + len > data.len() {
    return _err_hs(_at("tls: truncated handshake body", off));
  }
  return _ok_hs(TlsHandshake{
    msg_type: t;
    length: len;
    start: off;
    body_off: off + TLS_HANDSHAKE_HEADER_LEN;
    total: TLS_HANDSHAKE_HEADER_LEN + len;
  });
}

/// Offset of the byte just after `h` (start + total); feed it back to
/// tls_parse_handshake to consume the next message of a multi-message
/// buffer. Complexity: O(1).
pub fn tls_handshake_next(h: &TlsHandshake) -> Int {
  return h.start + h.total;
}

/// Parse a ClientHello (handshake type 1, RFC 8446 section 4.1.2).
///
/// Returns: Ok(ClientHello) with the legacy version, the 32-byte random, the
/// 0..32-byte session id, the cipher suites, the compression methods and the
/// bounds of the extension block (ext_present false when the body ends after
/// the compression methods, as TLS 1.2 permits). Every list is validated to
/// consume exactly the declared bytes and the whole body must be consumed.
/// Errors: the handshake-envelope errors, "tls: not a client hello at
/// <offset>", "tls: truncated client hello at <offset>", "tls: bad session
/// id length at <offset>" (above 32), "tls: bad cipher suites length at
/// <offset>" (zero or odd), "tls: bad compression methods length at
/// <offset>" (zero), "tls: truncated extension block at <offset>",
/// "tls: extension block length mismatch at <offset>".
/// Complexity: O(body length).
pub fn tls_parse_client_hello(data: &Vec[UInt8], off: Int) -> Result[TlsClientHello, Str] {
  let er = tls_parse_handshake(data, off);
  if !er.is_ok {
    return _err_ch(er.error);
  }
  let h: TlsHandshake = er.value;
  if h.msg_type != TLS_HS_CLIENT_HELLO {
    return _err_ch(_at("tls: not a client hello", off));
  }
  let end = h.start + h.total;
  var pos = h.body_off;
  if pos + 2 > end {
    return _err_ch(_at("tls: truncated client hello", pos));
  }
  let legacy = _read_u16(data, pos);
  pos = pos + 2;
  if pos + 32 > end {
    return _err_ch(_at("tls: truncated client hello", pos));
  }
  var random = Vec[UInt8].new();
  _push_range(&mut random, data, pos, 32);
  pos = pos + 32;
  if pos + 1 > end {
    return _err_ch(_at("tls: truncated client hello", pos));
  }
  let sid_len = _byte(data, pos);
  if sid_len > 32 {
    return _err_ch(_at("tls: bad session id length", pos));
  }
  pos = pos + 1;
  if pos + sid_len > end {
    return _err_ch(_at("tls: truncated client hello", pos));
  }
  var session_id = Vec[UInt8].new();
  _push_range(&mut session_id, data, pos, sid_len);
  pos = pos + sid_len;
  if pos + 2 > end {
    return _err_ch(_at("tls: truncated client hello", pos));
  }
  let cs_len = _read_u16(data, pos);
  if cs_len < 2 || cs_len % 2 != 0 {
    return _err_ch(_at("tls: bad cipher suites length", pos));
  }
  pos = pos + 2;
  if pos + cs_len > end {
    return _err_ch(_at("tls: truncated client hello", pos));
  }
  var suites = Vec[Int].new();
  var k = 0;
  while k + 2 <= cs_len {
    suites.push(_read_u16(data, pos + k));
    k = k + 2;
  }
  pos = pos + cs_len;
  if pos + 1 > end {
    return _err_ch(_at("tls: truncated client hello", pos));
  }
  let cm_len = _byte(data, pos);
  if cm_len < 1 {
    return _err_ch(_at("tls: bad compression methods length", pos));
  }
  pos = pos + 1;
  if pos + cm_len > end {
    return _err_ch(_at("tls: truncated client hello", pos));
  }
  var methods = Vec[Int].new();
  var m = 0;
  while m < cm_len {
    methods.push(_byte(data, pos + m));
    m = m + 1;
  }
  pos = pos + cm_len;
  var ext_present = false;
  var ext_off = end;
  var ext_end = end;
  if pos < end {
    if pos + 2 > end {
      return _err_ch(_at("tls: truncated extension block", pos));
    }
    let ext_len = _read_u16(data, pos);
    if pos + 2 + ext_len != end {
      return _err_ch(_at("tls: extension block length mismatch", pos));
    }
    ext_present = true;
    ext_off = pos;
    ext_end = end;
  }
  return _ok_ch(TlsClientHello{
    legacy_version: legacy;
    random: random;
    session_id: session_id;
    cipher_suites: suites;
    compression_methods: methods;
    ext_present: ext_present;
    ext_off: ext_off;
    ext_end: ext_end;
    total: h.total;
  });
}

/// Parse a ServerHello (handshake type 2). Same shape as a ClientHello
/// except the server selects one cipher suite and one compression method.
///
/// Errors: the ClientHello error catalog with "server hello" wording:
/// "tls: not a server hello at <offset>", "tls: truncated server hello at
/// <offset>", "tls: bad session id length at <offset>", "tls: truncated
/// extension block at <offset>", "tls: extension block length mismatch at
/// <offset>".
/// Complexity: O(body length).
pub fn tls_parse_server_hello(data: &Vec[UInt8], off: Int) -> Result[TlsServerHello, Str] {
  let er = tls_parse_handshake(data, off);
  if !er.is_ok {
    return _err_sh(er.error);
  }
  let h: TlsHandshake = er.value;
  if h.msg_type != TLS_HS_SERVER_HELLO {
    return _err_sh(_at("tls: not a server hello", off));
  }
  let end = h.start + h.total;
  var pos = h.body_off;
  if pos + 2 > end {
    return _err_sh(_at("tls: truncated server hello", pos));
  }
  let legacy = _read_u16(data, pos);
  pos = pos + 2;
  if pos + 32 > end {
    return _err_sh(_at("tls: truncated server hello", pos));
  }
  var random = Vec[UInt8].new();
  _push_range(&mut random, data, pos, 32);
  pos = pos + 32;
  if pos + 1 > end {
    return _err_sh(_at("tls: truncated server hello", pos));
  }
  let sid_len = _byte(data, pos);
  if sid_len > 32 {
    return _err_sh(_at("tls: bad session id length", pos));
  }
  pos = pos + 1;
  if pos + sid_len > end {
    return _err_sh(_at("tls: truncated server hello", pos));
  }
  var session_id = Vec[UInt8].new();
  _push_range(&mut session_id, data, pos, sid_len);
  pos = pos + sid_len;
  if pos + 3 > end {
    return _err_sh(_at("tls: truncated server hello", pos));
  }
  let suite = _read_u16(data, pos);
  pos = pos + 2;
  let method = _byte(data, pos);
  pos = pos + 1;
  var ext_present = false;
  var ext_off = end;
  var ext_end = end;
  if pos < end {
    if pos + 2 > end {
      return _err_sh(_at("tls: truncated extension block", pos));
    }
    let ext_len = _read_u16(data, pos);
    if pos + 2 + ext_len != end {
      return _err_sh(_at("tls: extension block length mismatch", pos));
    }
    ext_present = true;
    ext_off = pos;
    ext_end = end;
  }
  return _ok_sh(TlsServerHello{
    legacy_version: legacy;
    random: random;
    session_id: session_id;
    cipher_suite: suite;
    compression_method: method;
    ext_present: ext_present;
    ext_off: ext_off;
    ext_end: ext_end;
    total: h.total;
  });
}

/// Parse an EncryptedExtensions message (TLS 1.3, handshake type 8): the
/// body is exactly one extension block.
///
/// Returns: Ok(message) with the block bounds; parse the block with
/// tls_parse_extensions(data, body_off, body_off + list_len + 2).
/// Errors: the handshake-envelope errors, "tls: not encrypted extensions at
/// <offset>", "tls: truncated extension block at <offset>",
/// "tls: extension block length mismatch at <offset>".
/// Complexity: O(1).
pub fn tls_parse_encrypted_extensions(data: &Vec[UInt8], off: Int) -> Result[TlsEncryptedExtensions, Str] {
  let er = tls_parse_handshake(data, off);
  if !er.is_ok {
    return _err_ee(er.error);
  }
  let h: TlsHandshake = er.value;
  if h.msg_type != TLS_HS_ENCRYPTED_EXTENSIONS {
    return _err_ee(_at("tls: not encrypted extensions", off));
  }
  let end = h.start + h.total;
  if h.body_off + 2 > end {
    return _err_ee(_at("tls: truncated extension block", h.body_off));
  }
  let list_len = _read_u16(data, h.body_off);
  if h.body_off + 2 + list_len != end {
    return _err_ee(_at("tls: extension block length mismatch", h.body_off));
  }
  return _ok_ee(TlsEncryptedExtensions{ body_off: h.body_off; list_len: list_len; total: h.total; });
}

/// Parse a Certificate message in the TLS 1.2 shape (handshake type 11):
/// a 24-bit certificate-list length followed by 24-bit-prefixed DER
/// entries. The list must fill the body exactly and every entry must fit.
///
/// Returns: Ok(certificate) with per-certificate absolute offsets and
/// lengths into the source buffer. DER content is opaque: a TLS 1.3
/// Certificate carries a request context before the list and is rejected by
/// this parser (see SPEC.md); X.509 parsing belongs to xiom.pki (referenced
/// in README.md).
/// Errors: the handshake-envelope errors, "tls: not a certificate at
/// <offset>", "tls: truncated certificate list at <offset>",
/// "tls: certificate list length mismatch at <offset>",
/// "tls: truncated certificate entry at <offset>".
/// Complexity: O(body length).
pub fn tls_parse_certificate(data: &Vec[UInt8], off: Int) -> Result[TlsCertificate, Str] {
  let er = tls_parse_handshake(data, off);
  if !er.is_ok {
    return _err_cert(er.error);
  }
  let h: TlsHandshake = er.value;
  if h.msg_type != TLS_HS_CERTIFICATE {
    return _err_cert(_at("tls: not a certificate", off));
  }
  let end = h.start + h.total;
  if h.body_off + 3 > end {
    return _err_cert(_at("tls: truncated certificate list", h.body_off));
  }
  let list_len = _read_u24(data, h.body_off);
  if h.body_off + 3 + list_len != end {
    return _err_cert(_at("tls: certificate list length mismatch", h.body_off));
  }
  var cert_starts = Vec[Int].new();
  var cert_lens = Vec[Int].new();
  var pos = h.body_off + 3;
  while pos < end {
    if pos + 3 > end {
      return _err_cert(_at("tls: truncated certificate entry", pos));
    }
    let cl = _read_u24(data, pos);
    if pos + 3 + cl > end {
      return _err_cert(_at("tls: truncated certificate entry", pos));
    }
    cert_starts.push(pos + 3);
    cert_lens.push(cl);
    pos = pos + 3 + cl;
  }
  return _ok_cert(TlsCertificate{
    body_off: h.body_off;
    list_len: list_len;
    cert_starts: cert_starts;
    cert_lens: cert_lens;
    total: h.total;
  });
}

/// Copy of DER certificate `i` of `c` as sliced from the source buffer, or
/// an empty vector when `i` is out of range or the slice does not fit
/// `data`. Complexity: O(length).
pub fn tls_certificate_der(data: &Vec[UInt8], c: &TlsCertificate, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 || i >= c.cert_starts.len() || i >= c.cert_lens.len() {
    return out;
  }
  let s: Int = c.cert_starts[i];
  let l: Int = c.cert_lens[i];
  if s < 0 || l < 0 || s + l > data.len() {
    return out;
  }
  _push_range(&mut out, data, s, l);
  return out;
}

/// Parse a ServerKeyExchange body (handshake type 12) as an opaque slice,
/// with an ECDHE hint: when the first body byte is curve_type 3
/// (named_curve), the following u16 is exposed as `named_curve`. For any
/// other shape both hint fields stay -1 (for named_curve) and curve_type
/// keeps the raw first byte. The signature and parameters stay opaque.
///
/// Errors: the handshake-envelope errors, "tls: not a server key exchange at
/// <offset>", "tls: truncated key exchange body at <offset>" (fewer than
/// three body bytes).
/// Complexity: O(1).
pub fn tls_parse_server_key_exchange(data: &Vec[UInt8], off: Int) -> Result[TlsKeyExchange, Str] {
  let er = tls_parse_handshake(data, off);
  if !er.is_ok {
    return _err_kx(er.error);
  }
  let h: TlsHandshake = er.value;
  if h.msg_type != TLS_HS_SERVER_KEY_EXCHANGE {
    return _err_kx(_at("tls: not a server key exchange", off));
  }
  if h.length < 3 {
    return _err_kx(_at("tls: truncated key exchange body", h.body_off));
  }
  let curve_type = _byte(data, h.body_off);
  var named_curve = -1;
  if curve_type == 3 {
    named_curve = _read_u16(data, h.body_off + 1);
  }
  return _ok_kx(TlsKeyExchange{
    msg_type: h.msg_type;
    curve_type: curve_type;
    named_curve: named_curve;
    body_off: h.body_off;
    body_len: h.length;
    total: h.total;
  });
}

/// Parse a ClientKeyExchange body (handshake type 16) as an opaque slice
/// (no curve hint: the client key share is algorithm-dependent).
///
/// Errors: the handshake-envelope errors, "tls: not a client key exchange at
/// <offset>", "tls: empty key exchange body at <offset>".
/// Complexity: O(1).
pub fn tls_parse_client_key_exchange(data: &Vec[UInt8], off: Int) -> Result[TlsKeyExchange, Str] {
  let er = tls_parse_handshake(data, off);
  if !er.is_ok {
    return _err_kx(er.error);
  }
  let h: TlsHandshake = er.value;
  if h.msg_type != TLS_HS_CLIENT_KEY_EXCHANGE {
    return _err_kx(_at("tls: not a client key exchange", off));
  }
  if h.length < 1 {
    return _err_kx(_at("tls: empty key exchange body", h.body_off));
  }
  return _ok_kx(TlsKeyExchange{
    msg_type: h.msg_type;
    curve_type: -1;
    named_curve: -1;
    body_off: h.body_off;
    body_len: h.length;
    total: h.total;
  });
}

/// Parse a Finished body (handshake type 20) as an opaque verify_data
/// slice. The verify_data length depends on the cipher suite, so only an
/// empty body is rejected.
///
/// Errors: the handshake-envelope errors, "tls: not a finished message at
/// <offset>", "tls: empty finished body at <offset>".
/// Complexity: O(1).
pub fn tls_parse_finished(data: &Vec[UInt8], off: Int) -> Result[TlsFinished, Str] {
  let er = tls_parse_handshake(data, off);
  if !er.is_ok {
    return _err_fin(er.error);
  }
  let h: TlsHandshake = er.value;
  if h.msg_type != TLS_HS_FINISHED {
    return _err_fin(_at("tls: not a finished message", off));
  }
  if h.length < 1 {
    return _err_fin(_at("tls: empty finished body", h.body_off));
  }
  return _ok_fin(TlsFinished{ body_off: h.body_off; body_len: h.length; total: h.total; });
}

/// Parse a NewSessionTicket message (handshake type 4) in the TLS 1.3 shape:
/// lifetime(4) age_add(4) nonce<0..255> ticket<1..65535> extensions<0..65535>.
/// The extension block must fill the rest of the body exactly.
///
/// Errors: the handshake-envelope errors, "tls: not a new session ticket at
/// <offset>", "tls: truncated new session ticket at <offset>", "tls: bad
/// ticket length at <offset>", "tls: extension block length mismatch at
/// <offset>".
/// Complexity: O(1).
pub fn tls_parse_new_session_ticket(data: &Vec[UInt8], off: Int) -> Result[TlsNewSessionTicket, Str] {
  let er = tls_parse_handshake(data, off);
  if !er.is_ok {
    return _err_nst(er.error);
  }
  let h: TlsHandshake = er.value;
  if h.msg_type != TLS_HS_NEW_SESSION_TICKET {
    return _err_nst(_at("tls: not a new session ticket", off));
  }
  let end = h.start + h.total;
  var pos = h.body_off;
  if pos + 13 > end {
    return _err_nst(_at("tls: truncated new session ticket", pos));
  }
  let lifetime = _read_u32(data, pos);
  pos = pos + 4;
  let age_add = _read_u32(data, pos);
  pos = pos + 4;
  let nonce_len = _byte(data, pos);
  pos = pos + 1;
  if pos + nonce_len + 2 > end {
    return _err_nst(_at("tls: truncated new session ticket", pos));
  }
  let nonce_off = pos;
  pos = pos + nonce_len;
  let ticket_off_len_at = pos;
  let ticket_len = _read_u16(data, pos);
  pos = pos + 2;
  if ticket_len < 1 {
    return _err_nst(_at("tls: bad ticket length", ticket_off_len_at));
  }
  if pos + ticket_len + 2 > end {
    return _err_nst(_at("tls: truncated new session ticket", pos));
  }
  let ticket_off = pos;
  pos = pos + ticket_len;
  let ext_len = _read_u16(data, pos);
  if pos + 2 + ext_len != end {
    return _err_nst(_at("tls: extension block length mismatch", pos));
  }
  return _ok_nst(TlsNewSessionTicket{
    lifetime: lifetime;
    age_add: age_add;
    nonce_off: nonce_off;
    nonce_len: nonce_len;
    ticket_off: ticket_off;
    ticket_len: ticket_len;
    ext_off: pos;
    ext_end: end;
    total: h.total;
  });
}

// --------------------------------------------------
//  Buffered handshake reassembly
// --------------------------------------------------

/// New, empty reassembly buffer. Complexity: O(1).
pub fn tls_handshake_buffer_new() -> TlsHandshakeBuffer {
  return TlsHandshakeBuffer{
    pending: Vec[UInt8].new();
    messages: Vec[UInt8].new();
    starts: Vec[Int].new();
    lens: Vec[Int].new();
  };
}

/// Feed one record fragment carrying handshake bytes into `buf` and emit
/// every complete handshake message it completes. Messages may span any
/// number of records and a record may complete several messages.
///
/// Returns: Ok(n) with n = the number of messages completed by this call
/// (0 when more bytes are needed).
/// Errors: Err("tls: not a handshake fragment") when `content_type` is not
/// 22 (handshake).
/// Complexity: O(fragment length + emitted bytes).
pub fn tls_hsbuf_feed(buf: &mut TlsHandshakeBuffer, content_type: Int, fragment: &Vec[UInt8]) -> Result[Int, Str] {
  if content_type != TLS_CONTENT_TYPE_HANDSHAKE {
    return _err_int("tls: not a handshake fragment");
  }
  var i = 0;
  while i < fragment.len() {
    buf.pending.push(fragment[i]);
    i = i + 1;
  }
  var emitted = 0;
  var consumed = 0;
  let plen = buf.pending.len();
  while plen - consumed >= 4 {
    let b0 = (buf.pending[consumed + 1] as Int) & 0xFF;
    let b1 = (buf.pending[consumed + 2] as Int) & 0xFF;
    let b2 = (buf.pending[consumed + 3] as Int) & 0xFF;
    let mlen = b0 * 65536 + b1 * 256 + b2;
    if plen - consumed < 4 + mlen {
      break;
    }
    let start = buf.messages.len();
    var k = 0;
    while k < 4 + mlen {
      buf.messages.push(buf.pending[consumed + k]);
      k = k + 1;
    }
    buf.starts.push(start);
    buf.lens.push(4 + mlen);
    consumed = consumed + 4 + mlen;
    emitted = emitted + 1;
  }
  if consumed > 0 {
    var rest = Vec[UInt8].new();
    var k = consumed;
    while k < plen {
      rest.push(buf.pending[k]);
      k = k + 1;
    }
    buf.pending = rest;
  }
  return _ok_int(emitted);
}

/// Parse the record at `off` in `data`, require it to carry handshake bytes
/// and feed its fragment into `buf`.
///
/// Returns: Ok((next, n)) with `next` = the offset just after the record and
/// n = the number of messages completed by this call.
/// Errors: the record-parser errors, "tls: not a handshake record at
/// <offset>" for any other content type, and the feed errors.
/// Complexity: O(record length).
pub fn tls_hsbuf_feed_record(buf: &mut TlsHandshakeBuffer, data: &Vec[UInt8], off: Int) -> Result[(Int, Int), Str] {
  let rr = tls_parse_record(data, off);
  if !rr.is_ok {
    return _err_pair(rr.error);
  }
  let rec: TlsRecord = rr.value;
  if rec.content_type != TLS_CONTENT_TYPE_HANDSHAKE {
    return _err_pair(_at("tls: not a handshake record", off));
  }
  var frag = Vec[UInt8].new();
  _push_range(&mut frag, data, rec.fragment_off, rec.length);
  let fr = tls_hsbuf_feed(buf, TLS_CONTENT_TYPE_HANDSHAKE, &frag);
  if !fr.is_ok {
    return _err_pair(fr.error);
  }
  return _ok_pair((rec.end, fr.value));
}

/// Number of complete handshake messages currently buffered.
/// Complexity: O(1).
pub fn tls_hsbuf_count(b: &TlsHandshakeBuffer) -> Int {
  return b.lens.len();
}

/// Number of buffered bytes that do not yet form a complete message.
/// Complexity: O(1).
pub fn tls_hsbuf_pending_len(b: &TlsHandshakeBuffer) -> Int {
  return b.pending.len();
}

/// Length in bytes of buffered message `i` (header included), or -1 when `i`
/// is out of range. Complexity: O(1).
pub fn tls_hsbuf_message_len(b: &TlsHandshakeBuffer, i: Int) -> Int {
  if i < 0 || i >= b.lens.len() {
    return -1;
  }
  let l: Int = b.lens[i];
  return l;
}

/// Message type byte of buffered message `i`, or -1 when `i` is out of
/// range or its range does not fit. Complexity: O(1).
pub fn tls_hsbuf_message_type(b: &TlsHandshakeBuffer, i: Int) -> Int {
  if i < 0 || i >= b.lens.len() || i >= b.starts.len() {
    return -1;
  }
  let s: Int = b.starts[i];
  let l: Int = b.lens[i];
  if s < 0 || l < 4 || s + l > b.messages.len() {
    return -1;
  }
  let b0 = (b.messages[s] as Int) & 0xFF;
  return b0;
}

/// Copy of buffered message `i` (header included), or an empty vector when
/// `i` is out of range. The copy is standalone: parse it with
/// tls_parse_handshake(data, 0) and offsets are relative to the copy.
/// Complexity: O(length).
pub fn tls_hsbuf_message(b: &TlsHandshakeBuffer, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 || i >= b.lens.len() || i >= b.starts.len() {
    return out;
  }
  let s: Int = b.starts[i];
  let l: Int = b.lens[i];
  let pool: Vec[UInt8] = b.messages;
  if s < 0 || l < 0 || s + l > pool.len() {
    return out;
  }
  _push_range(&mut out, &pool, s, l);
  return out;
}

/// Drop every buffered message and pending byte.
/// Complexity: O(1).
pub fn tls_hsbuf_reset(buf: &mut TlsHandshakeBuffer) {
  buf.pending = Vec[UInt8].new();
  buf.messages = Vec[UInt8].new();
  buf.starts = Vec[Int].new();
  buf.lens = Vec[Int].new();
}
