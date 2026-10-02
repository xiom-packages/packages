// XIOM -- xiom.i2p: pure I2P SAM v3 message and session state model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets, no crypto, no threads) MODEL of the I2P
// SAM v3 client protocol surface:
//
//   * destinations and addresses: the canonical 516-character base64
//     destination string (387 raw bytes = 256-byte encryption public key +
//     128-byte signing public key + 3-byte null certificate), the 52-char
//     lowercase base32 form of a 32-byte destination hash, the ".b32.i2p"
//     and ".i2p" naming rules, and an in-memory address book (name ->
//     destination mappings);
//   * SAM v3 line framing: "VERB SUBCOMMAND [KEY=value ...]\n" with
//     bounded keys and values, double-quoted values when a value contains
//     spaces, quotes or backslashes, and printable-ASCII-only payloads;
//   * reply codes: the RESULT=... names of the SAM v3 replies (OK,
//     INVALID_KEY, DUPLICATE_ID, TIMEOUT, I2P_ERROR, ...), looked up in
//     both directions;
//   * the session lifecycle: HELLO VERSION and SESSION CREATE/ADD/REMOVE
//     with session ids, styles STREAM/DATAGRAM/RAW and NEW/ACTIVE/CLOSED/
//     FAILED state transitions driven by SESSION STATUS replies;
//   * the stream state model: STREAM CONNECT/ACCEPT/FORWARD construction,
//     CONNECTING/ACCEPTING/FORWARDING/OPEN/FAILED/CLOSED transitions driven
//     by STREAM STATUS replies and inbound connections;
//   * the lease-set shape: a destination plus up to 16 leases (peer router
//     hash, tunnel id, end date) held as three parallel Vecs.
//
// What this module deliberately does NOT do:
//   * no transport: it never opens a socket, never dials the SAM bridge and
//     never performs I/O; the caller moves the built lines to its own
//     transport and feeds replies back in;
//   * no cryptography: keys, hashes and signatures are opaque byte strings;
//     nothing is encrypted, signed, verified or hashed (a 32-byte "hash" is
//     whatever the caller supplies);
//   * no destination key-certificate forms: only the canonical null-
//     certificate 387-byte / 516-character destination is modelled (an
//     EdDSA key-certificate destination has a different length and is a
//     documented non-goal for 0.1.0);
//   * no I2CP/router interaction, no streaming library, no datagram
//     reassembly, no clock.
//
// This module also hand-rolls base64 and base32 because the stdlib encoding
// modules are not part of the verified package link closure, and it avoids
// floats, match expressions, methods, lambdas and Vec[StructType].
//
// v0.62.2 notes that shaped this module:
//   * Ok/Err construction is confined to the leaf helpers (_ok_*/_err_*);
//   * every byte read from a Str or Vec[UInt8] widens once with
//     `(x as Int) & 0xFF` before comparison or arithmetic;
//   * Str values are never compared with `==` and Vec[Str] elements are
//     always bound to typed locals before use (BUG-17 discipline);
//   * `&mut Vec` parameters carry an explicit `&mut` at every call site;
//   * no `mut` in patterns, no overloading, no builtin shadowing, no global
//     Vec[Str], all loops bounded by input length or a constant.

module xiom.i2p

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Sizes (I2P common structures, canonical null-cert form)
// --------------------------------------------------

/// Length of the encryption public key inside a destination.
pub const I2P_ENC_PUBKEY_LEN: Int = 256;

/// Length of the signing public key inside a destination.
pub const I2P_SIGN_PUBKEY_LEN: Int = 128;

/// Length of the destination key material (encryption + signing key).
pub const I2P_KEY_MATERIAL_LEN: Int = 384;

/// Length of a destination certificate header (type byte + u16 length).
pub const I2P_CERT_HEADER_LEN: Int = 3;

/// Raw length of a canonical destination (384 + 3-byte null certificate).
pub const I2P_DEST_LEN: Int = 387;

/// Length of the canonical base64 destination string (387 bytes, no pad).
pub const I2P_DEST_B64_LEN: Int = 516;

/// Length of a destination hash (SHA-256 output) used by b32 addresses.
pub const I2P_HASH_LEN: Int = 32;

/// Length of the base32 label inside a ".b32.i2p" address.
pub const I2P_B32_LABEL_LEN: Int = 52;

/// Length of a b32 address including the ".b32.i2p" suffix.
pub const I2P_B32_HOST_LEN: Int = 60;

/// Length of a base64 router-hash lease peer field (32 bytes + pad).
pub const I2P_PEER_B64_LEN: Int = 44;

/// Longest line this model accepts, newline included.
pub const I2P_MAX_SAM_LINE: Int = 4096;

/// Longest session or stream id this model accepts.
pub const I2P_MAX_ID_LEN: Int = 64;

/// Longest SAM field key this model accepts.
pub const I2P_MAX_KEY_LEN: Int = 64;

/// Longest SAM field value this model accepts.
pub const I2P_MAX_VALUE_LEN: Int = 2048;

/// Largest number of fields in one SAM line this model accepts.
pub const I2P_MAX_FIELDS: Int = 64;

/// Largest number of SESSION CREATE options this model accepts.
pub const I2P_MAX_OPTIONS: Int = 32;

/// Largest number of extra (SESSION ADD) destinations per session.
pub const I2P_MAX_EXTRA_DESTS: Int = 8;

/// Largest number of entries in an address book.
pub const I2P_MAX_BOOK_ENTRIES: Int = 256;

/// Largest number of leases in a lease set (I2P maximum).
pub const I2P_LEASESET_MAX_LEASES: Int = 16;

/// Largest TCP port accepted by STREAM FORWARD.
pub const I2P_MAX_PORT: Int = 65535;

/// Largest 32-bit unsigned value (tunnel id and expiry bounds).
pub const I2P_MAX_U32: Int = 4294967295;

/// Longest accepted ".i2p" hostname (DNS-form bound).
pub const I2P_MAX_HOST_LEN: Int = 255;

/// Longest accepted hostname label.
pub const I2P_MAX_LABEL_LEN: Int = 63;

/// Total length of a null destination certificate (header only).
pub const I2P_NULL_CERT_LEN: Int = 0;

// --------------------------------------------------
//  Certificate types
// --------------------------------------------------

pub const I2P_CERT_NULL: Int = 0;
pub const I2P_CERT_HASHCASH: Int = 1;
pub const I2P_CERT_HIDDEN: Int = 2;
pub const I2P_CERT_SIGNED: Int = 3;
pub const I2P_CERT_MULTIPLE: Int = 4;
pub const I2P_CERT_KEY: Int = 5;

/// Highest certificate type this model names.
pub const I2P_CERT_TYPE_MAX: Int = 5;

// --------------------------------------------------
//  Signature types (I2P common structures table)
// --------------------------------------------------

pub const I2P_SIG_DSA_SHA1: Int = 0;
pub const I2P_SIG_ECDSA_SHA256_P256: Int = 1;
pub const I2P_SIG_ECDSA_SHA384_P384: Int = 2;
pub const I2P_SIG_ECDSA_SHA512_P521: Int = 3;
pub const I2P_SIG_EDDSA_SHA512_ED25519: Int = 4;
pub const I2P_SIG_RSA_SHA256_2048: Int = 5;
pub const I2P_SIG_RSA_SHA384_3072: Int = 6;
pub const I2P_SIG_RSA_SHA512_4096: Int = 7;
pub const I2P_SIG_EDDSA_SHA512_ED25519PH: Int = 8;
pub const I2P_SIG_REDDSA_SHA512_ED25519: Int = 9;

/// Highest signature type this model names.
pub const I2P_SIG_TYPE_MAX: Int = 9;

// --------------------------------------------------
//  Session styles and states
// --------------------------------------------------

pub const I2P_STYLE_STREAM: Int = 0;
pub const I2P_STYLE_DATAGRAM: Int = 1;
pub const I2P_STYLE_RAW: Int = 2;

pub const I2P_SESSION_NEW: Int = 0;
pub const I2P_SESSION_ACTIVE: Int = 1;
pub const I2P_SESSION_CLOSED: Int = 2;
pub const I2P_SESSION_FAILED: Int = 3;

// --------------------------------------------------
//  Stream states and directions
// --------------------------------------------------

pub const I2P_STREAM_NEW: Int = 0;
pub const I2P_STREAM_CONNECTING: Int = 1;
pub const I2P_STREAM_ACCEPTING: Int = 2;
pub const I2P_STREAM_FORWARDING: Int = 3;
pub const I2P_STREAM_OPEN: Int = 4;
pub const I2P_STREAM_FAILED: Int = 5;
pub const I2P_STREAM_CLOSED: Int = 6;

pub const I2P_DIR_CONNECT: Int = 0;
pub const I2P_DIR_ACCEPT: Int = 1;
pub const I2P_DIR_FORWARD: Int = 2;

// --------------------------------------------------
//  Address kinds
// --------------------------------------------------

pub const I2P_ADDR_INVALID: Int = 0;
pub const I2P_ADDR_B64_DEST: Int = 1;
pub const I2P_ADDR_B32_HOST: Int = 2;
pub const I2P_ADDR_I2P_HOST: Int = 3;

// --------------------------------------------------
//  SAM v3 result codes
// --------------------------------------------------

pub const I2P_RESULT_OK: Int = 0;
pub const I2P_RESULT_INVALID_KEY: Int = 1;
pub const I2P_RESULT_DUPLICATE_DEST: Int = 2;
pub const I2P_RESULT_INVALID_SIGTYPE: Int = 3;
pub const I2P_RESULT_DUPLICATE_ID: Int = 4;
pub const I2P_RESULT_INVALID_ID: Int = 5;
pub const I2P_RESULT_CANT_REACH_PEER: Int = 6;
pub const I2P_RESULT_PEER_NOT_FOUND: Int = 7;
pub const I2P_RESULT_TIMEOUT: Int = 8;
pub const I2P_RESULT_ALREADY_ACCEPTING: Int = 9;
pub const I2P_RESULT_NO_LEASESET: Int = 10;
pub const I2P_RESULT_KEY_NOT_FOUND: Int = 11;
pub const I2P_RESULT_NOVERSION: Int = 12;
pub const I2P_RESULT_I2P_ERROR: Int = 13;

/// Highest named result code.
pub const I2P_RESULT_MAX: Int = 13;

/// Code returned by sam_result_code for an unknown name.
pub const I2P_RESULT_UNKNOWN: Int = -1;

// --------------------------------------------------
//  Private byte constants and alphabets
// --------------------------------------------------

const _I2P_LF: Int = 10;
const _I2P_CR: Int = 13;
const _I2P_TAB: Int = 9;
const _I2P_SPACE: Int = 32;
const _I2P_DQUOTE: Int = 34;
const _I2P_PLUS: Int = 43;
const _I2P_MINUS: Int = 45;
const _I2P_DOT: Int = 46;
const _I2P_SLASH: Int = 47;
const _I2P_DIGIT_0: Int = 48;
const _I2P_DIGIT_9: Int = 57;
const _I2P_EQ: Int = 61;
const _I2P_UPPER_A: Int = 65;
const _I2P_UPPER_Z: Int = 90;
const _I2P_BSLASH: Int = 92;
const _I2P_UNDERSCORE: Int = 95;
const _I2P_LOWER_A: Int = 97;
const _I2P_LOWER_Z: Int = 122;
const _I2P_TILDE: Int = 126;
const _I2P_B64_PAD: Int = 61;

// Standard base64 alphabet (RFC 4648 section 4), 64 bytes.
const _I2P_B64_ALPHABET: Str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// Lowercase unpadded base32 alphabet (RFC 4648 section 6), 32 bytes.
const _I2P_B32_ALPHABET: Str = "abcdefghijklmnopqrstuvwxyz234567";

// --------------------------------------------------
//  Small shared helpers
// --------------------------------------------------

// Byte of a Str at pos, widened to 0..255. Callers guarantee the bounds.
fn _byte(s: Str, pos: Int) -> Int {
  return (string.byte_at(s, pos) as Int) & 0xFF;
}

// Byte of a Vec[UInt8] at pos, widened to 0..255. Callers guarantee bounds.
fn _vbyte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Decimal text of v (sign/digits only; never 0x00).
fn _int_str(v: Int) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_int(&mut out, v);
  return builder.sb_to_str(&out);
}

// "<what> at offset <off>": the offset-bearing error convention. Callers
// pass the full "i2p: ..." what text.
fn _err_at(what: Str, off: Int) -> Str {
  return what + " at offset " + _int_str(off);
}

// True when byte c is printable ASCII 0x20..0x7E.
fn _printable(c: Int) -> Bool {
  if c < _I2P_SPACE { return false; }
  if c > _I2P_TILDE { return false; }
  return true;
}

// True when every byte of s is printable ASCII (empty input: true).
fn _printable_str(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if !_printable(_byte(s, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Independent copy of a Vec[Str] (never aliases the source buffer).
fn _copy_strs(src: &Vec[Str]) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < src.len() {
    let v: Str = src[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

// Index of the first element of v equal to x (str_compare), or -1.
fn _str_index(v: &Vec[Str], x: Str) -> Int {
  var i = 0;
  while i < v.len() {
    let e: Str = v[i];
    if compare.str_compare(e, x) == 0 {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when v contains an element equal to x (str_compare).
fn _str_in(v: &Vec[Str], x: Str) -> Bool {
  return _str_index(v, x) >= 0;
}

// True when s ends with the literal suffix (byte comparison).
fn _ends_with(s: Str, suffix: Str) -> Bool {
  let ns = s.len();
  let nf = suffix.len();
  if nf > ns { return false; }
  var i = 0;
  while i < nf {
    if _byte(s, ns - nf + i) != _byte(suffix, i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Append the bytes of s to out.
fn _push_str(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// --------------------------------------------------
//  Message, destination, session, stream and store types
// --------------------------------------------------

/// One parsed SAM v3 line: `verb` and `sub` are the first two
/// space-separated tokens, and `keys[i]`/`values[i]` are the KEY=value
/// fields in wire order (parallel Vec[Str] fields keep Vec[StructType] out
/// of the compiler path; a missing subcommand is a parse error, so both
/// strings are always present).
pub type I2pMessage = {
  verb: Str;
  sub: Str;
  keys: Vec[Str];
  values: Vec[Str];
}

/// One canonical destination: exactly 387 raw bytes (256-byte encryption
/// public key, 128-byte signing public key, 3-byte null certificate).
pub type I2pDestination = {
  data: Vec[UInt8];
}

/// One SAM session. `dests[0]` is the primary destination; the rest are
/// SESSION ADD destinations (at most I2P_MAX_EXTRA_DESTS of them).
/// `option_keys`/`option_values` hold SESSION CREATE options in wire order.
pub type I2pSession = {
  session_id: Str;
  style: Int;
  state: Int;
  dests: Vec[Str];
  option_keys: Vec[Str];
  option_values: Vec[Str];
}

/// One stream operation on a STREAM session. `direction` is one of the
/// I2P_DIR_* constants, `dest_b64` the target for CONNECT ("" otherwise),
/// `peer` the accepted peer hash for inbound connections, `port` the
/// forwarded local port (0 otherwise).
pub type I2pStream = {
  stream_id: Str;
  session_id: Str;
  style: Int;
  state: Int;
  direction: Int;
  dest_b64: Str;
  peer: Str;
  port: Int;
  silent: Bool;
}

/// One address book: names[i] maps to dests[i] (parallel Vec[Str] fields).
pub type I2pAddressBook = {
  names: Vec[Str];
  dests: Vec[Str];
}

/// One lease set: the owning destination plus parallel lease arrays. There
/// are always exactly leaseset_count(ls) entries in each of peers,
/// tunnel_ids and end_dates; end_dates are caller-clock milliseconds.
pub type I2pLeaseSet = {
  dest_b64: Str;
  peers: Vec[Str];
  tunnel_ids: Vec[Int];
  end_dates: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
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

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[I2pDestination, Str].
fn _ok_dest(v: I2pDestination) -> Result[I2pDestination, Str] {
  return Ok(v);
}

// Err(m) for Result[I2pDestination, Str].
fn _err_dest(m: Str) -> Result[I2pDestination, Str] {
  return Err(m);
}

// Ok(v) for Result[I2pMessage, Str].
fn _ok_msg(v: I2pMessage) -> Result[I2pMessage, Str] {
  return Ok(v);
}

// Err(m) for Result[I2pMessage, Str].
fn _err_msg(m: Str) -> Result[I2pMessage, Str] {
  return Err(m);
}

// Ok(v) for Result[I2pSession, Str].
fn _ok_session(v: I2pSession) -> Result[I2pSession, Str] {
  return Ok(v);
}

// Err(m) for Result[I2pSession, Str].
fn _err_session(m: Str) -> Result[I2pSession, Str] {
  return Err(m);
}

// Ok(v) for Result[I2pStream, Str].
fn _ok_stream(v: I2pStream) -> Result[I2pStream, Str] {
  return Ok(v);
}

// Err(m) for Result[I2pStream, Str].
fn _err_stream(m: Str) -> Result[I2pStream, Str] {
  return Err(m);
}

// Ok(v) for Result[I2pAddressBook, Str].
fn _ok_book(v: I2pAddressBook) -> Result[I2pAddressBook, Str] {
  return Ok(v);
}

// Err(m) for Result[I2pAddressBook, Str].
fn _err_book(m: Str) -> Result[I2pAddressBook, Str] {
  return Err(m);
}

// Ok(v) for Result[I2pLeaseSet, Str].
fn _ok_leaseset(v: I2pLeaseSet) -> Result[I2pLeaseSet, Str] {
  return Ok(v);
}

// Err(m) for Result[I2pLeaseSet, Str].
fn _err_leaseset(m: Str) -> Result[I2pLeaseSet, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Size accessors
// --------------------------------------------------

/// Raw destination length. Params: none. Returns: 387. Error case: none.
pub fn i2p_dest_len() -> Int { return I2P_DEST_LEN; }

/// Base64 destination string length. Params: none. Returns: 516.
/// Error case: none.
pub fn i2p_dest_b64_len() -> Int { return I2P_DEST_B64_LEN; }

/// Base32 label length. Params: none. Returns: 52. Error case: none.
pub fn i2p_b32_label_len() -> Int { return I2P_B32_LABEL_LEN; }

/// Longest accepted SAM line. Params: none. Returns: 4096.
/// Error case: none.
pub fn i2p_max_sam_line() -> Int { return I2P_MAX_SAM_LINE; }

/// ".b32.i2p" suffix. Params: none. Returns: the suffix.
/// Error case: none.
pub fn i2p_b32_suffix() -> Str { return ".b32.i2p"; }

/// ".i2p" suffix. Params: none. Returns: the suffix. Error case: none.
pub fn i2p_suffix() -> Str { return ".i2p"; }

// --------------------------------------------------
//  Base64 (RFC 4648 section 4, standard alphabet, '=' padded)
// --------------------------------------------------

// Index of byte c in the base64 alphabet, or -1.
fn _b64_index(c: Int) -> Int {
  var i = 0;
  while i < 64 {
    if _byte(_I2P_B64_ALPHABET, i) == c {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Standard base64 encode with canonical '=' padding (RFC 4648 section 4).
/// Empty input yields "". Params: data - bytes to encode.
/// Returns: the base64 text. Error case: none. Complexity: O(len(data)).
pub fn b64_encode(data: &Vec[UInt8]) -> Str {
  let n = data.len();
  if n == 0 {
    return "";
  }
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let rem = n - i;
    let b0 = _vbyte(data, i);
    var b1 = 0;
    var b2 = 0;
    if rem > 1 { b1 = _vbyte(data, i + 1); }
    if rem > 2 { b2 = _vbyte(data, i + 2); }
    let t0 = b0 >> 2;
    let t1 = ((b0 & 3) << 4) | (b1 >> 4);
    let t2 = ((b1 & 15) << 2) | (b2 >> 6);
    let t3 = b2 & 63;
    sb.push(string.byte_at(_I2P_B64_ALPHABET, t0));
    sb.push(string.byte_at(_I2P_B64_ALPHABET, t1));
    if rem > 1 {
      sb.push(string.byte_at(_I2P_B64_ALPHABET, t2));
    } else {
      sb.push(_I2P_B64_PAD as UInt8);
    }
    if rem > 2 {
      sb.push(string.byte_at(_I2P_B64_ALPHABET, t3));
    } else {
      sb.push(_I2P_B64_PAD as UInt8);
    }
    i = i + 3;
  }
  return builder.sb_to_str(&sb);
}

/// Strict canonical base64 decode (RFC 4648 section 4). Rejects a length
/// that is not a multiple of 4, any character outside the alphabet, '='
/// anywhere except the final one or two positions, characters after the
/// first pad quartet, and non-zero unused bits in the last data character
/// (so every accepted text has exactly one encoding). Offsets are byte
/// offsets into `s`. Params: s - base64 text. Returns: Ok(bytes) (empty for
/// ""). Error case: Err("i2p: base64 ...") with an offset.
/// Complexity: O(len(s)).
pub fn b64_decode(s: Str) -> Result[Vec[UInt8], Str] {
  let n = s.len();
  if n == 0 {
    return _ok_bytes(Vec[UInt8].new());
  }
  if n % 4 != 0 {
    return _err_bytes("i2p: base64 length not a multiple of 4");
  }
  var pad = 0;
  if _byte(s, n - 1) == _I2P_B64_PAD {
    pad = 1;
    if _byte(s, n - 2) == _I2P_B64_PAD {
      pad = 2;
    }
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    let is_last = (i + 4 == n);
    let c0 = _b64_index(_byte(s, i));
    let c1 = _b64_index(_byte(s, i + 1));
    if c0 < 0 {
      return _err_bytes(_err_at("i2p: base64 invalid character", i));
    }
    if c1 < 0 {
      return _err_bytes(_err_at("i2p: base64 invalid character", i + 1));
    }
    var c2 = 0;
    var c3 = 0;
    var data_chars = 4;
    if is_last && pad > 0 {
      if pad == 1 {
        if _byte(s, i + 3) != _I2P_B64_PAD {
          return _err_bytes(_err_at("i2p: base64 padding expected", i + 3));
        }
        c2 = _b64_index(_byte(s, i + 2));
        if c2 < 0 {
          return _err_bytes(_err_at("i2p: base64 invalid character", i + 2));
        }
        data_chars = 3;
      } else {
        if _byte(s, i + 2) != _I2P_B64_PAD {
          return _err_bytes(_err_at("i2p: base64 padding expected", i + 2));
        }
        if _byte(s, i + 3) != _I2P_B64_PAD {
          return _err_bytes(_err_at("i2p: base64 padding expected", i + 3));
        }
        data_chars = 2;
      }
    } else {
      c2 = _b64_index(_byte(s, i + 2));
      c3 = _b64_index(_byte(s, i + 3));
      if c2 < 0 {
        return _err_bytes(_err_at("i2p: base64 invalid character", i + 2));
      }
      if c3 < 0 {
        return _err_bytes(_err_at("i2p: base64 invalid character", i + 3));
      }
    }
    if data_chars == 2 {
      if (c1 & 15) != 0 {
        return _err_bytes(_err_at("i2p: base64 non-canonical padding bits", i + 1));
      }
    }
    if data_chars == 3 {
      if (c2 & 3) != 0 {
        return _err_bytes(_err_at("i2p: base64 non-canonical padding bits", i + 2));
      }
    }
    out.push(((c0 << 2) | (c1 >> 4)) as UInt8);
    if data_chars >= 3 {
      out.push((((c1 & 15) << 4) | (c2 >> 2)) as UInt8);
    }
    if data_chars == 4 {
      out.push((((c2 & 3) << 6) | c3) as UInt8);
    }
    i = i + 4;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Base32 (RFC 4648 section 6, lowercase, unpadded)
// --------------------------------------------------

// Index of byte c in the base32 alphabet, or -1.
fn _b32_index(c: Int) -> Int {
  var i = 0;
  while i < 32 {
    if _byte(_I2P_B32_ALPHABET, i) == c {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Lowercase unpadded base32 encode (RFC 4648 section 6). Empty input
/// yields "". Params: data - bytes to encode. Returns: the base32 text.
/// Error case: none. Complexity: O(len(data)).
pub fn b32_encode(data: &Vec[UInt8]) -> Str {
  let n = data.len();
  var sb = Vec[UInt8].new();
  var acc = 0;
  var bits = 0;
  var i = 0;
  while i < n {
    acc = (acc << 8) | _vbyte(data, i);
    bits = bits + 8;
    while bits >= 5 {
      bits = bits - 5;
      let idx = (acc >> bits) & 31;
      sb.push(string.byte_at(_I2P_B32_ALPHABET, idx));
      acc = acc & ((1 << bits) - 1);
    }
    i = i + 1;
  }
  if bits > 0 {
    let idx = (acc << (5 - bits)) & 31;
    sb.push(string.byte_at(_I2P_B32_ALPHABET, idx));
  }
  return builder.sb_to_str(&sb);
}

/// Strict lowercase unpadded base32 decode (RFC 4648 section 6). Rejects
/// lengths with 1, 3 or 6 leftover characters, any character outside the
/// lowercase alphabet (uppercase included), and non-zero unused bits in the
/// final character. Offsets are byte offsets into `s`. Params: s - base32
/// text. Returns: Ok(bytes) (empty for ""). Error case:
/// Err("i2p: base32 ..."). Complexity: O(len(s)).
pub fn b32_decode(s: Str) -> Result[Vec[UInt8], Str] {
  let n = s.len();
  if n == 0 {
    return _ok_bytes(Vec[UInt8].new());
  }
  let rem = n % 8;
  if rem == 1 || rem == 3 || rem == 6 {
    return _err_bytes("i2p: base32 length invalid");
  }
  var out = Vec[UInt8].new();
  var acc = 0;
  var bits = 0;
  var i = 0;
  while i < n {
    let c = _b32_index(_byte(s, i));
    if c < 0 {
      return _err_bytes(_err_at("i2p: base32 invalid character", i));
    }
    acc = (acc << 5) | c;
    bits = bits + 5;
    while bits >= 8 {
      bits = bits - 8;
      out.push(((acc >> bits) & 0xFF) as UInt8);
      acc = acc & ((1 << bits) - 1);
    }
    i = i + 1;
  }
  if acc != 0 {
    return _err_bytes("i2p: base32 non-canonical padding bits");
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Canonical destinations
// --------------------------------------------------

// True when the 387 raw bytes carry a null certificate (type 0, length 0).
fn _dest_cert_null(v: &Vec[UInt8]) -> Bool {
  if v.len() != I2P_DEST_LEN {
    return false;
  }
  if _vbyte(v, I2P_KEY_MATERIAL_LEN) != I2P_CERT_NULL {
    return false;
  }
  if _vbyte(v, I2P_KEY_MATERIAL_LEN + 1) != 0 {
    return false;
  }
  if _vbyte(v, I2P_KEY_MATERIAL_LEN + 2) != 0 {
    return false;
  }
  return true;
}

/// Parse the canonical 516-character base64 destination string: exactly
/// 516 canonical base64 characters (no '=': 387 bytes is a multiple of 3),
/// decoding to 387 bytes whose 3-byte certificate is the null certificate
/// (type 0, length 0). Params: s - the destination string.
/// Returns: Ok(destination). Error case: Err("i2p: destination ...") or the
/// underlying base64 error (length, invalid character with offset,
/// non-canonical padding bits). Complexity: O(len(s)).
pub fn dest_parse_b64(s: Str) -> Result[I2pDestination, Str] {
  if s.len() != I2P_DEST_B64_LEN {
    return _err_dest("i2p: destination length must be 516");
  }
  let r = b64_decode(s);
  if !r.is_ok {
    return _err_dest(r.error);
  }
  let data: Vec[UInt8] = r.value;
  if data.len() != I2P_DEST_LEN {
    return _err_dest("i2p: destination must decode to 387 bytes");
  }
  if !_dest_cert_null(&data) {
    return _err_dest("i2p: destination certificate invalid");
  }
  return _ok_dest(I2pDestination{ data: data });
}

/// Encode a destination as the canonical base64 string. Params: d - the
/// destination. Returns: 516 characters for a canonical destination.
/// Error case: none (the raw bytes are encoded whatever their length).
/// Complexity: O(len(d.data)).
pub fn dest_to_b64(d: &I2pDestination) -> Str {
  let v: Vec[UInt8] = d.data;
  return b64_encode(&v);
}

/// Certificate type byte of a canonical destination (0 for the null
/// certificate). Params: d - the destination. Returns: Ok(0..5).
/// Error case: Err("i2p: destination length must be 387") for a malformed
/// in-memory destination. Complexity: O(1).
pub fn dest_cert_type(d: &I2pDestination) -> Result[Int, Str] {
  let v: Vec[UInt8] = d.data;
  if v.len() != I2P_DEST_LEN {
    return _err_int("i2p: destination length must be 387");
  }
  return _ok_int(_vbyte(&v, I2P_KEY_MATERIAL_LEN));
}

/// Certificate length field of a canonical destination (0 for the null
/// certificate). Params: d - the destination. Returns: Ok(u16).
/// Error case: Err("i2p: destination length must be 387").
/// Complexity: O(1).
pub fn dest_cert_len(d: &I2pDestination) -> Result[Int, Str] {
  let v: Vec[UInt8] = d.data;
  if v.len() != I2P_DEST_LEN {
    return _err_int("i2p: destination length must be 387");
  }
  let hi = _vbyte(&v, I2P_KEY_MATERIAL_LEN + 1);
  let lo = _vbyte(&v, I2P_KEY_MATERIAL_LEN + 2);
  return _ok_int((hi << 8) | lo);
}

/// True when the destination carries the null certificate (type 0, length
/// 0). Params: d - the destination. Returns: the predicate (false for a
/// malformed length). Error case: none. Complexity: O(1).
pub fn dest_is_null_cert(d: &I2pDestination) -> Bool {
  let v: Vec[UInt8] = d.data;
  return _dest_cert_null(&v);
}

/// Signing key type of a canonical destination. A null certificate means
/// the legacy DSA_SHA1 (0) default, the only type a 387-byte destination
/// can carry. Params: d - the destination. Returns: Ok(sig type).
/// Error case: Err("i2p: destination has no key certificate") for a
/// certificate that is not the null certificate (a key-certificate form is
/// out of scope for this model). Complexity: O(1).
pub fn dest_sig_type(d: &I2pDestination) -> Result[Int, Str] {
  if !dest_is_null_cert(d) {
    return _err_int("i2p: destination has no key certificate");
  }
  return _ok_int(I2P_SIG_DSA_SHA1);
}

/// Name of a signing key type (I2P common structures table). Params: t -
/// the type id. Returns: "DSA_SHA1", "ECDSA_SHA256_P256",
/// "ECDSA_SHA384_P384", "ECDSA_SHA512_P521", "EdDSA_SHA512_Ed25519",
/// "RSA_SHA256_2048", "RSA_SHA384_3072", "RSA_SHA512_4096",
/// "EdDSA_SHA512_Ed25519ph", "RedDSA_SHA512_Ed25519", or "UNKNOWN".
/// Error case: none. Complexity: O(1).
pub fn dest_sig_type_name(t: Int) -> Str {
  if t == I2P_SIG_DSA_SHA1 { return "DSA_SHA1"; }
  if t == I2P_SIG_ECDSA_SHA256_P256 { return "ECDSA_SHA256_P256"; }
  if t == I2P_SIG_ECDSA_SHA384_P384 { return "ECDSA_SHA384_P384"; }
  if t == I2P_SIG_ECDSA_SHA512_P521 { return "ECDSA_SHA512_P521"; }
  if t == I2P_SIG_EDDSA_SHA512_ED25519 { return "EdDSA_SHA512_Ed25519"; }
  if t == I2P_SIG_RSA_SHA256_2048 { return "RSA_SHA256_2048"; }
  if t == I2P_SIG_RSA_SHA384_3072 { return "RSA_SHA384_3072"; }
  if t == I2P_SIG_RSA_SHA512_4096 { return "RSA_SHA512_4096"; }
  if t == I2P_SIG_EDDSA_SHA512_ED25519PH { return "EdDSA_SHA512_Ed25519ph"; }
  if t == I2P_SIG_REDDSA_SHA512_ED25519 { return "RedDSA_SHA512_Ed25519"; }
  return "UNKNOWN";
}

/// Copy of the 256-byte encryption public key (empty when the in-memory
/// destination is shorter than 256 bytes). Params: d - the destination.
/// Returns: the key bytes. Error case: none. Complexity: O(256).
pub fn dest_enc_key(d: &I2pDestination) -> Vec[UInt8] {
  let v: Vec[UInt8] = d.data;
  var out = Vec[UInt8].new();
  var i = 0;
  while i < I2P_ENC_PUBKEY_LEN && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

/// Copy of the 128-byte signing public key (empty when the in-memory
/// destination is shorter than 384 bytes). Params: d - the destination.
/// Returns: the key bytes. Error case: none. Complexity: O(128).
pub fn dest_sign_key(d: &I2pDestination) -> Vec[UInt8] {
  let v: Vec[UInt8] = d.data;
  var out = Vec[UInt8].new();
  var i = I2P_ENC_PUBKEY_LEN;
  while i < I2P_KEY_MATERIAL_LEN && i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Addresses: base32 hash hosts and .i2p names
// --------------------------------------------------

/// Build the b32 host of a destination hash: 52 lowercase base32
/// characters plus ".b32.i2p". Params: hash - 32 hash bytes.
/// Returns: Ok(the host). Error case: Err("i2p: b32 address requires a
/// 32-byte hash"). Complexity: O(32).
pub fn addr_b32_host(hash: &Vec[UInt8]) -> Result[Str, Str] {
  if hash.len() != I2P_HASH_LEN {
    return _err_str("i2p: b32 address requires a 32-byte hash");
  }
  return _ok_str(b32_encode(hash) + ".b32.i2p");
}

/// Parse a b32 host into its 32 destination-hash bytes: exactly 60
/// characters (52-character lowercase unpadded base32 label plus
/// ".b32.i2p"). Params: s - the host text. Returns: Ok(32 bytes).
/// Error case: Err("i2p: b32 address ...") with the base32 error.
/// Complexity: O(60).
pub fn addr_b32_hash(s: Str) -> Result[Vec[UInt8], Str] {
  if s.len() != I2P_B32_HOST_LEN {
    return _err_bytes("i2p: b32 address must be 52 base32 characters plus .b32.i2p");
  }
  if !_ends_with(s, ".b32.i2p") {
    return _err_bytes("i2p: b32 address must be 52 base32 characters plus .b32.i2p");
  }
  let label = string.str_slice(s, 0, I2P_B32_LABEL_LEN);
  let r = b32_decode(label);
  if !r.is_ok {
    return _err_bytes(r.error);
  }
  let h: Vec[UInt8] = r.value;
  if h.len() != I2P_HASH_LEN {
    return _err_bytes("i2p: b32 address must decode to 32 bytes");
  }
  return _ok_bytes(h);
}

/// True when s is a b32 host (52 base32 characters + ".b32.i2p").
/// Params: s - the candidate. Returns: the predicate. Error case: none.
/// Complexity: O(60).
pub fn addr_is_b32_host(s: Str) -> Bool {
  let r = addr_b32_hash(s);
  return r.is_ok;
}

/// True when s is a canonical 516-character base64 destination string.
/// Params: s - the candidate. Returns: the predicate. Error case: none.
/// Complexity: O(len(s)).
pub fn addr_is_b64(s: Str) -> Bool {
  let r = dest_parse_b64(s);
  return r.is_ok;
}

// True for lowercase letters, digits and hyphen (LDH label characters).
fn _ldh_char(c: Int) -> Bool {
  if c >= _I2P_LOWER_A && c <= _I2P_LOWER_Z { return true; }
  if c >= _I2P_DIGIT_0 && c <= _I2P_DIGIT_9 { return true; }
  if c == _I2P_MINUS { return true; }
  return false;
}

// True when lab is a non-empty lowercase LDH label of at most 63 bytes
// that neither starts nor ends with a hyphen.
fn _label_ok(lab: Str) -> Bool {
  let n = lab.len();
  if n == 0 { return false; }
  if n > I2P_MAX_LABEL_LEN { return false; }
  if _byte(lab, 0) == _I2P_MINUS { return false; }
  if _byte(lab, n - 1) == _I2P_MINUS { return false; }
  var i = 0;
  while i < n {
    if !_ldh_char(_byte(lab, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// True when s is a syntactically valid ".i2p" hostname: at most 255
/// bytes, ending in ".i2p", with one or more dot-separated lowercase LDH
/// labels of 1..63 bytes each (no empty label, no leading/trailing hyphen,
/// no uppercase, no underscore, no trailing dot). Params: s - the
/// candidate. Returns: the predicate. Error case: none. Complexity:
/// O(len(s)).
pub fn addr_is_i2p_host(s: Str) -> Bool {
  let n = s.len();
  if n <= 4 { return false; }
  if n > I2P_MAX_HOST_LEN { return false; }
  if !_ends_with(s, ".i2p") { return false; }
  let body_len = n - 4;
  var start = 0;
  var i = 0;
  while i <= body_len {
    if i == body_len || _byte(s, i) == _I2P_DOT {
      let lab = string.str_slice(s, start, i);
      if !_label_ok(lab) {
        return false;
      }
      start = i + 1;
    }
    i = i + 1;
  }
  return true;
}

/// Classify an address string. Params: s - the candidate. Returns one of
/// I2P_ADDR_B64_DEST (canonical 516-character destination),
/// I2P_ADDR_B32_HOST (52 base32 characters + ".b32.i2p"), I2P_ADDR_I2P_HOST
/// (other valid ".i2p" hostname) or I2P_ADDR_INVALID. The b64 and b32 forms
/// win over the general host rule. Error case: none. Complexity: O(len(s)).
pub fn addr_kind(s: Str) -> Int {
  if addr_is_b64(s) { return I2P_ADDR_B64_DEST; }
  if addr_is_b32_host(s) { return I2P_ADDR_B32_HOST; }
  if addr_is_i2p_host(s) { return I2P_ADDR_I2P_HOST; }
  return I2P_ADDR_INVALID;
}

// --------------------------------------------------
//  SAM v3 line framing
// --------------------------------------------------

// Index of '=' in tok, or -1.
fn _eq_pos(tok: Str) -> Int {
  var i = 0;
  while i < tok.len() {
    if _byte(tok, i) == _I2P_EQ {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when tok contains '='.
fn _has_eq(tok: Str) -> Bool {
  return _eq_pos(tok) >= 0;
}

// True for letters, digits, '.', '_' and '-' (field key characters).
fn _key_char(c: Int) -> Bool {
  if c >= _I2P_UPPER_A && c <= _I2P_UPPER_Z { return true; }
  if c >= _I2P_LOWER_A && c <= _I2P_LOWER_Z { return true; }
  if c >= _I2P_DIGIT_0 && c <= _I2P_DIGIT_9 { return true; }
  if c == _I2P_DOT { return true; }
  if c == _I2P_UNDERSCORE { return true; }
  if c == _I2P_MINUS { return true; }
  return false;
}

// True when k is a valid bounded field key.
fn _key_ok(k: Str) -> Bool {
  let n = k.len();
  if n == 0 { return false; }
  if n > I2P_MAX_KEY_LEN { return false; }
  var i = 0;
  while i < n {
    if !_key_char(_byte(k, i)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when w is a printable non-empty command word of at most max bytes
// with no space and no '='.
fn _word_ok(w: Str, max: Int) -> Bool {
  let n = w.len();
  if n == 0 { return false; }
  if n > max { return false; }
  var i = 0;
  while i < n {
    let c = _byte(w, i);
    if c < _I2P_SPACE || c > _I2P_TILDE { return false; }
    if c == _I2P_SPACE { return false; }
    if c == _I2P_EQ { return false; }
    i = i + 1;
  }
  return true;
}

// Split line[0, end) into tokens appended to out: runs of spaces separate
// tokens, a double quote toggles quoted mode, and inside quoted mode a
// backslash escapes the next byte. Rejects control and non-ASCII bytes,
// an unterminated quote and a trailing backslash with byte offsets.
// Returns the number of tokens appended.
fn _sam_tokenize(line: Str, end: Int, out: &mut Vec[Str]) -> Result[Int, Str] {
  var cur = Vec[UInt8].new();
  var inq = false;
  var have = false;
  var i = 0;
  while i < end {
    let c = _byte(line, i);
    if c < _I2P_SPACE || c > _I2P_TILDE {
      return _err_int(_err_at("i2p: sam line invalid byte", i));
    }
    if inq {
      if c == _I2P_BSLASH {
        if i + 1 >= end {
          return _err_int(_err_at("i2p: sam line trailing backslash", i));
        }
        let nx = _byte(line, i + 1);
        if nx < _I2P_SPACE || nx > _I2P_TILDE {
          return _err_int(_err_at("i2p: sam line invalid escaped byte", i + 1));
        }
        cur.push(nx as UInt8);
        i = i + 2;
      } else {
        if c == _I2P_DQUOTE {
          inq = false;
        } else {
          cur.push(c as UInt8);
        }
        i = i + 1;
      }
    } else {
      if c == _I2P_SPACE {
        if have {
          out.push(builder.sb_to_str(&cur));
          cur = Vec[UInt8].new();
          have = false;
        }
        i = i + 1;
      } else {
        if c == _I2P_DQUOTE {
          inq = true;
          have = true;
        } else {
          cur.push(c as UInt8);
          have = true;
        }
        i = i + 1;
      }
    }
  }
  if inq {
    return _err_int(_err_at("i2p: sam line unterminated quote", end - 1));
  }
  if have {
    out.push(builder.sb_to_str(&cur));
  }
  return _ok_int(out.len());
}

/// Parse one SAM v3 line: "VERB SUBCOMMAND [KEY=value ...]\n". The line
/// must end in '\n' (an optional '\r' before it is accepted), be at most
/// I2P_MAX_SAM_LINE bytes and contain printable ASCII only. The first two
/// tokens are the command and subcommand; every further token must be
/// KEY=value with a key of letters/digits/'.'/'-'/'_' and a value that may
/// be empty. Values containing spaces, quotes or backslashes are written
/// double-quoted with backslash escapes by sam_build_line and are decoded
/// here. Duplicate keys are kept in order (sam_msg_field returns the
/// first). Params: line - the line text. Returns: Ok(message).
/// Error case: Err("i2p: sam ...") with a byte offset for byte-level
/// problems. Complexity: O(len(line)).
pub fn sam_parse_line(line: Str) -> Result[I2pMessage, Str] {
  let n = line.len();
  if n == 0 {
    return _err_msg("i2p: empty sam line");
  }
  if n > I2P_MAX_SAM_LINE {
    return _err_msg("i2p: sam line too long");
  }
  if _byte(line, n - 1) != _I2P_LF {
    return _err_msg("i2p: sam line not newline-terminated");
  }
  var end = n - 1;
  if end > 0 {
    if _byte(line, end - 1) == _I2P_CR {
      end = end - 1;
    }
  }
  if end == 0 {
    return _err_msg("i2p: empty sam line");
  }
  var tokens = Vec[Str].new();
  let tr = _sam_tokenize(line, end, &mut tokens);
  if !tr.is_ok {
    return _err_msg(tr.error);
  }
  let nt = tokens.len();
  if nt < 2 {
    return _err_msg("i2p: sam line needs a command and a subcommand");
  }
  let verb: Str = tokens[0];
  let sub: Str = tokens[1];
  if _has_eq(verb) {
    return _err_msg("i2p: sam command token must not be a field");
  }
  if _has_eq(sub) {
    return _err_msg("i2p: sam command token must not be a field");
  }
  var keys = Vec[Str].new();
  var values = Vec[Str].new();
  var i = 2;
  while i < nt {
    let tok: Str = tokens[i];
    let eq = _eq_pos(tok);
    if eq <= 0 {
      return _err_msg("i2p: sam field missing '='");
    }
    let k = string.str_slice(tok, 0, eq);
    let v = string.str_slice(tok, eq + 1, tok.len());
    if !_key_ok(k) {
      return _err_msg("i2p: sam field key invalid");
    }
    keys.push(k);
    values.push(v);
    i = i + 1;
  }
  return _ok_msg(I2pMessage{ verb: verb; sub: sub; keys: keys; values: values; });
}

// Append the wire form of one field value: raw bytes unless the value
// contains a space, a double quote or a backslash, in which case it is
// double-quoted and '"'/'\\' are backslash-escaped.
fn _push_field_value(out: &mut Vec[UInt8], v: Str) {
  var need = false;
  var i = 0;
  while i < v.len() {
    let c = _byte(v, i);
    if c == _I2P_SPACE || c == _I2P_DQUOTE || c == _I2P_BSLASH {
      need = true;
    }
    i = i + 1;
  }
  if !need {
    _push_str(out, v);
    return;
  }
  out.push(_I2P_DQUOTE as UInt8);
  i = 0;
  while i < v.len() {
    let c = _byte(v, i);
    if c == _I2P_DQUOTE || c == _I2P_BSLASH {
      out.push(_I2P_BSLASH as UInt8);
    }
    out.push(c as UInt8);
    i = i + 1;
  }
  out.push(_I2P_DQUOTE as UInt8);
}

/// Build one SAM v3 line: "VERB SUBCOMMAND [KEY=value ...]\n". `keys` and
/// `values` are parallel arrays and must have the same length; keys are
/// bounded identifiers, values are at most I2P_MAX_VALUE_LEN printable
/// ASCII bytes (a value containing a space, a quote or a backslash is
/// quoted and escaped, so sam_parse_line round-trips it). Params: verb and
/// sub - command words; keys, values - the fields. Returns: Ok(line).
/// Error case: Err("i2p: sam ...") for an invalid word, key or value, a
/// length mismatch, or too many fields. Complexity: O(total bytes).
pub fn sam_build_line(verb: Str, sub: Str, keys: &Vec[Str], values: &Vec[Str]) -> Result[Str, Str] {
  if !_word_ok(verb, I2P_MAX_KEY_LEN) {
    return _err_str("i2p: sam command token invalid");
  }
  if !_word_ok(sub, I2P_MAX_KEY_LEN) {
    return _err_str("i2p: sam subcommand token invalid");
  }
  if keys.len() != values.len() {
    return _err_str("i2p: sam field keys/values length mismatch");
  }
  if keys.len() > I2P_MAX_FIELDS {
    return _err_str("i2p: sam too many fields");
  }
  var out = Vec[UInt8].new();
  _push_str(&mut out, verb);
  out.push(_I2P_SPACE as UInt8);
  _push_str(&mut out, sub);
  var i = 0;
  while i < keys.len() {
    let k: Str = keys[i];
    let v: Str = values[i];
    if !_key_ok(k) {
      return _err_str("i2p: sam field key invalid");
    }
    if v.len() > I2P_MAX_VALUE_LEN {
      return _err_str("i2p: sam field value too long");
    }
    if !_printable_str(v) {
      return _err_str("i2p: sam field value has invalid byte");
    }
    out.push(_I2P_SPACE as UInt8);
    _push_str(&mut out, k);
    out.push(_I2P_EQ as UInt8);
    _push_field_value(&mut out, v);
    i = i + 1;
  }
  out.push(_I2P_LF as UInt8);
  return _ok_str(builder.sb_to_str(&out));
}

/// Number of fields in a message. Params: m - the message. Returns: the
/// count. Error case: none. Complexity: O(1).
pub fn sam_msg_count(m: &I2pMessage) -> Int {
  let ks: Vec[Str] = m.keys;
  return ks.len();
}

/// True when a message has a field named `key`. Params: m - the message;
/// key - the field name. Returns: the predicate. Error case: none.
/// Complexity: O(fields).
pub fn sam_msg_has(m: &I2pMessage, key: Str) -> Bool {
  let r = sam_msg_field(m, key);
  return r.is_ok;
}

/// Value of the first field named `key`. Params: m - the message; key - the
/// field name. Returns: Ok(value) (possibly ""). Error case:
/// Err("i2p: field not present"). Complexity: O(fields).
pub fn sam_msg_field(m: &I2pMessage, key: Str) -> Result[Str, Str] {
  let ks: Vec[Str] = m.keys;
  let vs: Vec[Str] = m.values;
  var i = 0;
  while i < ks.len() {
    let k: Str = ks[i];
    if compare.str_compare(k, key) == 0 {
      if i >= vs.len() {
        return _err_str("i2p: field not present");
      }
      let v: Str = vs[i];
      return _ok_str(v);
    }
    i = i + 1;
  }
  return _err_str("i2p: field not present");
}

// --------------------------------------------------
//  Result codes
// --------------------------------------------------

/// Name of a SAM v3 result code. Params: code - the code id. Returns:
/// "OK", "INVALID_KEY", "DUPLICATE_DEST", "INVALID_SIGTYPE",
/// "DUPLICATE_ID", "INVALID_ID", "CANT_REACH_PEER", "PEER_NOT_FOUND",
/// "TIMEOUT", "ALREADY_ACCEPTING", "NO_LEASESET", "KEY_NOT_FOUND",
/// "NOVERSION", "I2P_ERROR", or "UNKNOWN". Error case: none.
/// Complexity: O(1).
pub fn sam_result_name(code: Int) -> Str {
  if code == I2P_RESULT_OK { return "OK"; }
  if code == I2P_RESULT_INVALID_KEY { return "INVALID_KEY"; }
  if code == I2P_RESULT_DUPLICATE_DEST { return "DUPLICATE_DEST"; }
  if code == I2P_RESULT_INVALID_SIGTYPE { return "INVALID_SIGTYPE"; }
  if code == I2P_RESULT_DUPLICATE_ID { return "DUPLICATE_ID"; }
  if code == I2P_RESULT_INVALID_ID { return "INVALID_ID"; }
  if code == I2P_RESULT_CANT_REACH_PEER { return "CANT_REACH_PEER"; }
  if code == I2P_RESULT_PEER_NOT_FOUND { return "PEER_NOT_FOUND"; }
  if code == I2P_RESULT_TIMEOUT { return "TIMEOUT"; }
  if code == I2P_RESULT_ALREADY_ACCEPTING { return "ALREADY_ACCEPTING"; }
  if code == I2P_RESULT_NO_LEASESET { return "NO_LEASESET"; }
  if code == I2P_RESULT_KEY_NOT_FOUND { return "KEY_NOT_FOUND"; }
  if code == I2P_RESULT_NOVERSION { return "NOVERSION"; }
  if code == I2P_RESULT_I2P_ERROR { return "I2P_ERROR"; }
  return "UNKNOWN";
}

/// Code of a SAM v3 result name (exact, case-sensitive). Params: name -
/// the RESULT value. Returns: 0..13, or I2P_RESULT_UNKNOWN (-1) for an
/// unknown name. Error case: none. Complexity: O(1).
pub fn sam_result_code(name: Str) -> Int {
  if compare.str_compare(name, "OK") == 0 { return I2P_RESULT_OK; }
  if compare.str_compare(name, "INVALID_KEY") == 0 { return I2P_RESULT_INVALID_KEY; }
  if compare.str_compare(name, "DUPLICATE_DEST") == 0 { return I2P_RESULT_DUPLICATE_DEST; }
  if compare.str_compare(name, "INVALID_SIGTYPE") == 0 { return I2P_RESULT_INVALID_SIGTYPE; }
  if compare.str_compare(name, "DUPLICATE_ID") == 0 { return I2P_RESULT_DUPLICATE_ID; }
  if compare.str_compare(name, "INVALID_ID") == 0 { return I2P_RESULT_INVALID_ID; }
  if compare.str_compare(name, "CANT_REACH_PEER") == 0 { return I2P_RESULT_CANT_REACH_PEER; }
  if compare.str_compare(name, "PEER_NOT_FOUND") == 0 { return I2P_RESULT_PEER_NOT_FOUND; }
  if compare.str_compare(name, "TIMEOUT") == 0 { return I2P_RESULT_TIMEOUT; }
  if compare.str_compare(name, "ALREADY_ACCEPTING") == 0 { return I2P_RESULT_ALREADY_ACCEPTING; }
  if compare.str_compare(name, "NO_LEASESET") == 0 { return I2P_RESULT_NO_LEASESET; }
  if compare.str_compare(name, "KEY_NOT_FOUND") == 0 { return I2P_RESULT_KEY_NOT_FOUND; }
  if compare.str_compare(name, "NOVERSION") == 0 { return I2P_RESULT_NOVERSION; }
  if compare.str_compare(name, "I2P_ERROR") == 0 { return I2P_RESULT_I2P_ERROR; }
  return I2P_RESULT_UNKNOWN;
}

/// True when a result code is OK. Params: code - the code id. Returns: the
/// predicate. Error case: none. Complexity: O(1).
pub fn sam_result_is_ok(code: Int) -> Bool {
  return code == I2P_RESULT_OK;
}

/// Result code of a parsed reply: reads the RESULT field and maps it.
/// Params: m - the parsed reply. Returns: Ok(0..13). Error case:
/// Err("i2p: field not present") when RESULT is missing,
/// Err("i2p: unknown result code") for a name not in the table.
/// Complexity: O(fields).
pub fn sam_reply_code(m: &I2pMessage) -> Result[Int, Str] {
  let r = sam_msg_field(m, "RESULT");
  if !r.is_ok {
    return _err_int(r.error);
  }
  let name: Str = r.value;
  let code = sam_result_code(name);
  if code == I2P_RESULT_UNKNOWN {
    return _err_int("i2p: unknown result code");
  }
  return _ok_int(code);
}

/// MESSAGE field of a reply, or "" when absent. Params: m - the reply.
/// Returns: the message text. Error case: none. Complexity: O(fields).
pub fn sam_reply_message(m: &I2pMessage) -> Str {
  let r = sam_msg_field(m, "MESSAGE");
  if r.is_ok {
    let v: Str = r.value;
    return v;
  }
  return "";
}

/// True when the message is a reply (subcommand REPLY or STATUS).
/// Params: m - the message. Returns: the predicate. Error case: none.
/// Complexity: O(1).
pub fn sam_is_reply(m: &I2pMessage) -> Bool {
  if compare.str_compare(m.sub, "REPLY") == 0 { return true; }
  if compare.str_compare(m.sub, "STATUS") == 0 { return true; }
  return false;
}

// --------------------------------------------------
//  Versions
// --------------------------------------------------

/// Pack a SAM protocol version into one integer: major * 100 + minor
/// (3.3 -> 303). Params: major, minor - both 0..99. Returns: the packed
/// code. Error case: none. Complexity: O(1).
pub fn sam_version_pack(major: Int, minor: Int) -> Int {
  return major * 100 + minor;
}

// Decimal span s[a, b) bounded by cap, or -1 on a non-digit or overflow.
fn _dec_span(s: Str, a: Int, b: Int, cap: Int) -> Int {
  if a >= b { return -1; }
  var v = 0;
  var i = a;
  while i < b {
    let c = _byte(s, i);
    if c < _I2P_DIGIT_0 || c > _I2P_DIGIT_9 { return -1; }
    v = v * 10 + (c - _I2P_DIGIT_0);
    if v > cap { return -1; }
    i = i + 1;
  }
  return v;
}

/// Parse "MAJOR.MINOR" (digits only, one dot, each part <= 99) into the
/// packed code. Params: s - the version text. Returns: Ok(packed code).
/// Error case: Err("i2p: version text invalid"). Complexity: O(len(s)).
pub fn sam_version_parse(s: Str) -> Result[Int, Str] {
  let n = s.len();
  var dot = -1;
  var i = 0;
  while i < n {
    if _byte(s, i) == _I2P_DOT {
      if dot >= 0 {
        return _err_int("i2p: version text invalid");
      }
      dot = i;
    }
    i = i + 1;
  }
  if dot <= 0 || dot == n - 1 {
    return _err_int("i2p: version text invalid");
  }
  let major = _dec_span(s, 0, dot, 99);
  if major < 0 {
    return _err_int("i2p: version text invalid");
  }
  let minor = _dec_span(s, dot + 1, n, 99);
  if minor < 0 {
    return _err_int("i2p: version text invalid");
  }
  return _ok_int(major * 100 + minor);
}

// Wire text of a packed version code.
fn _ver_str(code: Int) -> Str {
  return _int_str(code / 100) + "." + _int_str(code % 100);
}

// --------------------------------------------------
//  Command line builders
// --------------------------------------------------

/// Build "HELLO VERSION MIN=<min> MAX=<max>\n". Params: min_code, max_code
/// - packed version codes. Returns: Ok(line). Error case:
/// Err("i2p: version range invalid") for negative codes or min > max.
/// Complexity: O(1).
pub fn sam_hello_line(min_code: Int, max_code: Int) -> Result[Str, Str] {
  if min_code < 0 || max_code < 0 || min_code > max_code {
    return _err_str("i2p: version range invalid");
  }
  var keys = Vec[Str].new();
  var vals = Vec[Str].new();
  keys.push("MIN");
  vals.push(_ver_str(min_code));
  keys.push("MAX");
  vals.push(_ver_str(max_code));
  return sam_build_line("HELLO", "VERSION", &keys, &vals);
}

/// Build "DEST GENERATE\n" (DEST GENERATE takes no fields in SAM v3).
/// Params: none. Returns: the line. Error case: none. Complexity: O(1).
pub fn sam_dest_generate_line() -> Str {
  return "DEST GENERATE\n";
}

/// Build "SESSION CREATE STYLE=<style> ID=<id> DESTINATION=<dest>
/// [<options...>]\n" from a session. Params: s - the session. Returns:
/// Ok(line). Error case: Err("i2p: session has no destination") for a
/// session with no destinations, or a sam_build_line error.
/// Complexity: O(options).
pub fn sam_session_create_line(s: &I2pSession) -> Result[Str, Str] {
  let ds: Vec[Str] = s.dests;
  let oks: Vec[Str] = s.option_keys;
  let ovs: Vec[Str] = s.option_values;
  if ds.len() == 0 {
    return _err_str("i2p: session has no destination");
  }
  let dest: Str = ds[0];
  var keys = Vec[Str].new();
  var vals = Vec[Str].new();
  keys.push("STYLE");
  vals.push(session_style_name(s.style));
  keys.push("ID");
  vals.push(s.session_id);
  keys.push("DESTINATION");
  vals.push(dest);
  var i = 0;
  while i < oks.len() && i < ovs.len() {
    let k: Str = oks[i];
    let v: Str = ovs[i];
    keys.push(k);
    vals.push(v);
    i = i + 1;
  }
  return sam_build_line("SESSION", "CREATE", &keys, &vals);
}

/// Build "SESSION ADD ID=<id> DESTINATION=<dest>\n" for one destination.
/// Params: s - the session; dest - a canonical destination string.
/// Returns: Ok(line). Error case: Err("i2p: session destination invalid")
/// or the destination parse error. Complexity: O(len(dest)).
pub fn sam_session_add_line(s: &I2pSession, dest: Str) -> Result[Str, Str] {
  let r = dest_parse_b64(dest);
  if !r.is_ok {
    return _err_str("i2p: session destination invalid");
  }
  var keys = Vec[Str].new();
  var vals = Vec[Str].new();
  keys.push("ID");
  vals.push(s.session_id);
  keys.push("DESTINATION");
  vals.push(dest);
  return sam_build_line("SESSION", "ADD", &keys, &vals);
}

/// Build "SESSION REMOVE ID=<id> DESTINATION=<dest>\n". Params: s - the
/// session; dest - the destination to remove. Returns: Ok(line).
/// Error case: Err("i2p: session destination invalid") or the destination
/// parse error. Complexity: O(len(dest)).
pub fn sam_session_remove_line(s: &I2pSession, dest: Str) -> Result[Str, Str] {
  let r = dest_parse_b64(dest);
  if !r.is_ok {
    return _err_str("i2p: session destination invalid");
  }
  var keys = Vec[Str].new();
  var vals = Vec[Str].new();
  keys.push("ID");
  vals.push(s.session_id);
  keys.push("DESTINATION");
  vals.push(dest);
  return sam_build_line("SESSION", "REMOVE", &keys, &vals);
}

// Append an optional SILENT=true field.
fn _push_silent(keys: &mut Vec[Str], vals: &mut Vec[Str], st: &I2pStream) {
  if st.silent {
    keys.push("SILENT");
    vals.push("true");
  }
}

/// Build "STREAM CONNECT ID=<id> DESTINATION=<peer> [SILENT=true]\n" from a
/// CONNECT stream. Params: st - the stream. Returns: Ok(line). Error case:
/// Err("i2p: stream has no target") when the stream has no destination, or
/// a sam_build_line error. Complexity: O(1).
pub fn sam_stream_connect_line(st: &I2pStream) -> Result[Str, Str] {
  let dest: Str = st.dest_b64;
  if dest.len() == 0 {
    return _err_str("i2p: stream has no target");
  }
  var keys = Vec[Str].new();
  var vals = Vec[Str].new();
  keys.push("ID");
  vals.push(st.stream_id);
  keys.push("DESTINATION");
  vals.push(dest);
  _push_silent(&mut keys, &mut vals, st);
  return sam_build_line("STREAM", "CONNECT", &keys, &vals);
}

/// Build "STREAM ACCEPT ID=<id> [SILENT=true]\n". Params: st - the stream.
/// Returns: Ok(line). Error case: a sam_build_line error.
/// Complexity: O(1).
pub fn sam_stream_accept_line(st: &I2pStream) -> Result[Str, Str] {
  var keys = Vec[Str].new();
  var vals = Vec[Str].new();
  keys.push("ID");
  vals.push(st.stream_id);
  _push_silent(&mut keys, &mut vals, st);
  return sam_build_line("STREAM", "ACCEPT", &keys, &vals);
}

/// Build "STREAM FORWARD ID=<id> PORT=<port> [SILENT=true]\n". Params: st -
/// the stream. Returns: Ok(line). Error case: a sam_build_line error.
/// Complexity: O(1).
pub fn sam_stream_forward_line(st: &I2pStream) -> Result[Str, Str] {
  var keys = Vec[Str].new();
  var vals = Vec[Str].new();
  keys.push("ID");
  vals.push(st.stream_id);
  keys.push("PORT");
  vals.push(_int_str(st.port));
  _push_silent(&mut keys, &mut vals, st);
  return sam_build_line("STREAM", "FORWARD", &keys, &vals);
}

/// Build "NAMING LOOKUP NAME=<name>\n". Params: name - a valid ".i2p" host
/// or canonical destination string. Returns: Ok(line). Error case:
/// Err("i2p: naming lookup target invalid"). Complexity: O(len(name)).
pub fn sam_naming_lookup_line(name: Str) -> Result[Str, Str] {
  if addr_kind(name) == I2P_ADDR_INVALID {
    return _err_str("i2p: naming lookup target invalid");
  }
  var keys = Vec[Str].new();
  var vals = Vec[Str].new();
  keys.push("NAME");
  vals.push(name);
  return sam_build_line("NAMING", "LOOKUP", &keys, &vals);
}

// --------------------------------------------------
//  Session lifecycle
// --------------------------------------------------

/// True when id is a valid session or stream id for this model: 1..64
/// printable ASCII bytes, no space and no '='. Params: id - the candidate.
/// Returns: the predicate. Error case: none. Complexity: O(len(id)).
pub fn stream_id_ok(id: Str) -> Bool {
  return _word_ok(id, I2P_MAX_ID_LEN);
}

/// Name of a session style. Params: style - a style id. Returns: "STREAM",
/// "DATAGRAM", "RAW" or "UNKNOWN". Error case: none. Complexity: O(1).
pub fn session_style_name(style: Int) -> Str {
  if style == I2P_STYLE_STREAM { return "STREAM"; }
  if style == I2P_STYLE_DATAGRAM { return "DATAGRAM"; }
  if style == I2P_STYLE_RAW { return "RAW"; }
  return "UNKNOWN";
}

/// Code of a session style name (exact, case-sensitive). Params: name -
/// the style text. Returns: 0/1/2, or -1 for an unknown name.
/// Error case: none. Complexity: O(1).
pub fn session_style_code(name: Str) -> Int {
  if compare.str_compare(name, "STREAM") == 0 { return I2P_STYLE_STREAM; }
  if compare.str_compare(name, "DATAGRAM") == 0 { return I2P_STYLE_DATAGRAM; }
  if compare.str_compare(name, "RAW") == 0 { return I2P_STYLE_RAW; }
  return -1;
}

/// Name of a session state. Params: state - a state id. Returns: "NEW",
/// "ACTIVE", "CLOSED", "FAILED" or "UNKNOWN". Error case: none.
/// Complexity: O(1).
pub fn session_state_name(state: Int) -> Str {
  if state == I2P_SESSION_NEW { return "NEW"; }
  if state == I2P_SESSION_ACTIVE { return "ACTIVE"; }
  if state == I2P_SESSION_CLOSED { return "CLOSED"; }
  if state == I2P_SESSION_FAILED { return "FAILED"; }
  return "UNKNOWN";
}

/// Create a session in the NEW state with one primary destination. Params:
/// id - 1..64 printable non-space bytes; style - I2P_STYLE_*; dest_b64 - a
/// canonical destination string; option_keys/option_values - SESSION CREATE
/// options in wire order (parallel, at most I2P_MAX_OPTIONS pairs, keys
/// bounded identifiers, values bounded printable ASCII). Returns:
/// Ok(session). Error case: Err("i2p: session id invalid" /
/// "i2p: unknown session style" / "i2p: session destination invalid" /
/// "i2p: session options invalid"). Complexity: O(options).
pub fn session_create(id: Str, style: Int, dest_b64: Str, option_keys: &Vec[Str], option_values: &Vec[Str]) -> Result[I2pSession, Str] {
  if !_word_ok(id, I2P_MAX_ID_LEN) {
    return _err_session("i2p: session id invalid");
  }
  if style != I2P_STYLE_STREAM && style != I2P_STYLE_DATAGRAM && style != I2P_STYLE_RAW {
    return _err_session("i2p: unknown session style");
  }
  let dr = dest_parse_b64(dest_b64);
  if !dr.is_ok {
    return _err_session("i2p: session destination invalid");
  }
  if option_keys.len() != option_values.len() {
    return _err_session("i2p: session options invalid");
  }
  if option_keys.len() > I2P_MAX_OPTIONS {
    return _err_session("i2p: session options invalid");
  }
  var i = 0;
  while i < option_keys.len() {
    let k: Str = option_keys[i];
    let v: Str = option_values[i];
    if !_key_ok(k) {
      return _err_session("i2p: session options invalid");
    }
    if v.len() > I2P_MAX_VALUE_LEN {
      return _err_session("i2p: session options invalid");
    }
    if !_printable_str(v) {
      return _err_session("i2p: session options invalid");
    }
    i = i + 1;
  }
  var dests = Vec[Str].new();
  dests.push(dest_b64);
  return _ok_session(I2pSession{
    session_id: id;
    style: style;
    state: I2P_SESSION_NEW;
    dests: dests;
    option_keys: _copy_strs(option_keys);
    option_values: _copy_strs(option_values);
  });
}

/// Apply a SESSION STATUS result code to a session: OK moves it to ACTIVE,
/// any other code moves it to FAILED, and a CLOSED session stays CLOSED.
/// Params: s - the session; code - a result code. Returns: the new
/// session. Error case: none. Complexity: O(destinations + options).
pub fn session_status(s: &I2pSession, code: Int) -> I2pSession {
  var st = s.state;
  if st != I2P_SESSION_CLOSED {
    if sam_result_is_ok(code) {
      st = I2P_SESSION_ACTIVE;
    } else {
      st = I2P_SESSION_FAILED;
    }
  }
  let ds: Vec[Str] = s.dests;
  let oks: Vec[Str] = s.option_keys;
  let ovs: Vec[Str] = s.option_values;
  return I2pSession{
    session_id: s.session_id;
    style: s.style;
    state: st;
    dests: _copy_strs(&ds);
    option_keys: _copy_strs(&oks);
    option_values: _copy_strs(&ovs);
  };
}

/// Add a SESSION ADD destination to a session. Params: s - the session;
/// dest_b64 - the extra canonical destination. Returns: Ok(session with one
/// more destination). Error case: Err("i2p: session destination invalid" /
/// "i2p: session closed" / "i2p: destination already in session" /
/// "i2p: too many session destinations"). Complexity: O(destinations).
pub fn session_add_dest(s: &I2pSession, dest_b64: Str) -> Result[I2pSession, Str] {
  let dr = dest_parse_b64(dest_b64);
  if !dr.is_ok {
    return _err_session("i2p: session destination invalid");
  }
  if s.state == I2P_SESSION_CLOSED {
    return _err_session("i2p: session closed");
  }
  let ds: Vec[Str] = s.dests;
  if _str_in(&ds, dest_b64) {
    return _err_session("i2p: destination already in session");
  }
  if ds.len() - 1 >= I2P_MAX_EXTRA_DESTS {
    return _err_session("i2p: too many session destinations");
  }
  var dests = _copy_strs(&ds);
  dests.push(dest_b64);
  let oks: Vec[Str] = s.option_keys;
  let ovs: Vec[Str] = s.option_values;
  return _ok_session(I2pSession{
    session_id: s.session_id;
    style: s.style;
    state: s.state;
    dests: dests;
    option_keys: _copy_strs(&oks);
    option_values: _copy_strs(&ovs);
  });
}

/// Remove one SESSION REMOVE destination. The primary destination cannot be
/// removed (removing the last destination would close the session in SAM;
/// this model requires an explicit session_close). Params: s - the session;
/// dest_b64 - the destination to remove. Returns: Ok(session without it).
/// Error case: Err("i2p: session closed" / "i2p: destination not in
/// session" / "i2p: cannot remove primary destination"). Complexity:
/// O(destinations).
pub fn session_remove_dest(s: &I2pSession, dest_b64: Str) -> Result[I2pSession, Str] {
  if s.state == I2P_SESSION_CLOSED {
    return _err_session("i2p: session closed");
  }
  let ds: Vec[Str] = s.dests;
  let idx = _str_index(&ds, dest_b64);
  if idx < 0 {
    return _err_session("i2p: destination not in session");
  }
  if idx == 0 {
    return _err_session("i2p: cannot remove primary destination");
  }
  var dests = Vec[Str].new();
  var i = 0;
  while i < ds.len() {
    if i != idx {
      let d: Str = ds[i];
      dests.push(d);
    }
    i = i + 1;
  }
  let oks: Vec[Str] = s.option_keys;
  let ovs: Vec[Str] = s.option_values;
  return _ok_session(I2pSession{
    session_id: s.session_id;
    style: s.style;
    state: s.state;
    dests: dests;
    option_keys: _copy_strs(&oks);
    option_values: _copy_strs(&ovs);
  });
}

/// Close a session (terminal state). Params: s - the session. Returns: the
/// closed session. Error case: none. Complexity: O(fields).
pub fn session_close(s: &I2pSession) -> I2pSession {
  let ds: Vec[Str] = s.dests;
  let oks: Vec[Str] = s.option_keys;
  let ovs: Vec[Str] = s.option_values;
  return I2pSession{
    session_id: s.session_id;
    style: s.style;
    state: I2P_SESSION_CLOSED;
    dests: _copy_strs(&ds);
    option_keys: _copy_strs(&oks);
    option_values: _copy_strs(&ovs);
  };
}

/// True when a session is ACTIVE. Params: s - the session. Returns: the
/// predicate. Error case: none. Complexity: O(1).
pub fn session_is_active(s: &I2pSession) -> Bool {
  return s.state == I2P_SESSION_ACTIVE;
}

/// Number of destinations (primary plus extras). Params: s - the session.
/// Returns: the count. Error case: none. Complexity: O(1).
pub fn session_dest_count(s: &I2pSession) -> Int {
  let ds: Vec[Str] = s.dests;
  return ds.len();
}

/// Destination at index i, or "" when out of range. Params: s - the
/// session; i - the index. Returns: the destination string. Error case:
/// none. Complexity: O(1).
pub fn session_dest_at(s: &I2pSession, i: Int) -> Str {
  let ds: Vec[Str] = s.dests;
  if i < 0 || i >= ds.len() {
    return "";
  }
  let d: Str = ds[i];
  return d;
}

/// Number of SESSION CREATE options. Params: s - the session. Returns: the
/// count. Error case: none. Complexity: O(1).
pub fn session_option_count(s: &I2pSession) -> Int {
  let oks: Vec[Str] = s.option_keys;
  return oks.len();
}

/// Option key at index i, or "" when out of range. Params: s - the
/// session; i - the index. Returns: the key. Error case: none.
/// Complexity: O(1).
pub fn session_option_key_at(s: &I2pSession, i: Int) -> Str {
  let oks: Vec[Str] = s.option_keys;
  if i < 0 || i >= oks.len() {
    return "";
  }
  let k: Str = oks[i];
  return k;
}

/// Option value at index i, or "" when out of range. Params: s - the
/// session; i - the index. Returns: the value. Error case: none.
/// Complexity: O(1).
pub fn session_option_value_at(s: &I2pSession, i: Int) -> Str {
  let ovs: Vec[Str] = s.option_values;
  if i < 0 || i >= ovs.len() {
    return "";
  }
  let v: Str = ovs[i];
  return v;
}

// --------------------------------------------------
//  Stream lifecycle (STREAM sessions)
// --------------------------------------------------

// Shared stream construction. All Vec-free fields are set here; callers
// pass the target destination and port explicitly.
fn _stream_make(s: &I2pSession, stream_id: Str, direction: Int, state: Int, dest_b64: Str, port: Int) -> I2pStream {
  return I2pStream{
    stream_id: stream_id;
    session_id: s.session_id;
    style: I2P_STYLE_STREAM;
    state: state;
    direction: direction;
    dest_b64: dest_b64;
    peer: "";
    port: port;
    silent: false;
  };
}

// Shared active-STREAM-session gate.
fn _stream_gate(s: &I2pSession) -> Result[Str, Str] {
  if !session_is_active(s) {
    return _err_str("i2p: session not active");
  }
  if s.style != I2P_STYLE_STREAM {
    return _err_str("i2p: streams require a STREAM session");
  }
  return _ok_str("");
}

/// Create a STREAM CONNECT stream in the CONNECTING state. Params: s - an
/// ACTIVE STREAM session; stream_id - the stream id; dest_b64 - the peer's
/// canonical destination. Returns: Ok(stream). Error case:
/// Err("i2p: session not active" / "i2p: streams require a STREAM session" /
/// "i2p: stream id invalid" / "i2p: stream target invalid").
/// Complexity: O(len(dest_b64)).
pub fn stream_connect(s: &I2pSession, stream_id: Str, dest_b64: Str) -> Result[I2pStream, Str] {
  let gate = _stream_gate(s);
  if !gate.is_ok {
    return _err_stream(gate.error);
  }
  if !_word_ok(stream_id, I2P_MAX_ID_LEN) {
    return _err_stream("i2p: stream id invalid");
  }
  let dr = dest_parse_b64(dest_b64);
  if !dr.is_ok {
    return _err_stream("i2p: stream target invalid");
  }
  return _ok_stream(_stream_make(s, stream_id, I2P_DIR_CONNECT, I2P_STREAM_CONNECTING, dest_b64, 0));
}

/// Create a STREAM ACCEPT stream in the ACCEPTING state. Params: s - an
/// ACTIVE STREAM session; stream_id - the stream id. Returns: Ok(stream).
/// Error case: Err("i2p: session not active" /
/// "i2p: streams require a STREAM session" / "i2p: stream id invalid").
/// Complexity: O(1).
pub fn stream_accept(s: &I2pSession, stream_id: Str) -> Result[I2pStream, Str] {
  let gate = _stream_gate(s);
  if !gate.is_ok {
    return _err_stream(gate.error);
  }
  if !_word_ok(stream_id, I2P_MAX_ID_LEN) {
    return _err_stream("i2p: stream id invalid");
  }
  return _ok_stream(_stream_make(s, stream_id, I2P_DIR_ACCEPT, I2P_STREAM_ACCEPTING, "", 0));
}

/// Create a STREAM FORWARD stream in the FORWARDING state. Params: s - an
/// ACTIVE STREAM session; stream_id - the stream id; port - the local TCP
/// port (1..65535). Returns: Ok(stream). Error case:
/// Err("i2p: session not active" / "i2p: streams require a STREAM session" /
/// "i2p: stream id invalid" / "i2p: forward port out of range").
/// Complexity: O(1).
pub fn stream_forward(s: &I2pSession, stream_id: Str, port: Int) -> Result[I2pStream, Str] {
  let gate = _stream_gate(s);
  if !gate.is_ok {
    return _err_stream(gate.error);
  }
  if !_word_ok(stream_id, I2P_MAX_ID_LEN) {
    return _err_stream("i2p: stream id invalid");
  }
  if port < 1 || port > I2P_MAX_PORT {
    return _err_stream("i2p: forward port out of range");
  }
  return _ok_stream(_stream_make(s, stream_id, I2P_DIR_FORWARD, I2P_STREAM_FORWARDING, "", port));
}

/// Apply a STREAM STATUS result code: OK moves CONNECTING to OPEN (an
/// ACCEPTING or FORWARDING stream stays ready), any other code moves the
/// stream to FAILED, and a CLOSED stream is terminal. Params: st - the
/// stream; code - a result code. Returns: the new stream. Error case: none.
/// Complexity: O(1).
pub fn stream_status(st: &I2pStream, code: Int) -> I2pStream {
  var state = st.state;
  if st.state != I2P_STREAM_CLOSED {
    if sam_result_is_ok(code) {
      if st.state == I2P_STREAM_CONNECTING {
        state = I2P_STREAM_OPEN;
      }
    } else {
      state = I2P_STREAM_FAILED;
    }
  }
  return I2pStream{
    stream_id: st.stream_id;
    session_id: st.session_id;
    style: st.style;
    state: state;
    direction: st.direction;
    dest_b64: st.dest_b64;
    peer: st.peer;
    port: st.port;
    silent: st.silent;
  };
}

/// Accept an inbound connection on an ACCEPTING stream: moves it to OPEN
/// and records the 32-byte peer router hash. Params: st - the stream;
/// peer_b64 - the base64 peer hash. Returns: Ok(open stream). Error case:
/// Err("i2p: stream not accepting" / "i2p: invalid peer hash").
/// Complexity: O(1).
pub fn stream_inbound(st: &I2pStream, peer_b64: Str) -> Result[I2pStream, Str] {
  if st.state != I2P_STREAM_ACCEPTING {
    return _err_stream("i2p: stream not accepting");
  }
  let pr = b64_decode(peer_b64);
  if !pr.is_ok {
    return _err_stream("i2p: invalid peer hash");
  }
  let h: Vec[UInt8] = pr.value;
  if h.len() != I2P_HASH_LEN {
    return _err_stream("i2p: invalid peer hash");
  }
  return _ok_stream(I2pStream{
    stream_id: st.stream_id;
    session_id: st.session_id;
    style: st.style;
    state: I2P_STREAM_OPEN;
    direction: st.direction;
    dest_b64: st.dest_b64;
    peer: peer_b64;
    port: st.port;
    silent: st.silent;
  });
}

/// Close a stream (terminal state). Params: st - the stream. Returns: the
/// closed stream. Error case: none. Complexity: O(1).
pub fn stream_close(st: &I2pStream) -> I2pStream {
  return I2pStream{
    stream_id: st.stream_id;
    session_id: st.session_id;
    style: st.style;
    state: I2P_STREAM_CLOSED;
    direction: st.direction;
    dest_b64: st.dest_b64;
    peer: st.peer;
    port: st.port;
    silent: st.silent;
  };
}

/// True when a stream is OPEN and may carry data. Params: st - the stream.
/// Returns: the predicate. Error case: none. Complexity: O(1).
pub fn stream_can_send(st: &I2pStream) -> Bool {
  return st.state == I2P_STREAM_OPEN;
}

/// Set the SILENT flag used by the STREAM CONNECT/ACCEPT/FORWARD line
/// builders. Params: st - the stream; silent - the flag. Returns: the new
/// stream. Error case: none. Complexity: O(1).
pub fn stream_set_silent(st: &I2pStream, silent: Bool) -> I2pStream {
  return I2pStream{
    stream_id: st.stream_id;
    session_id: st.session_id;
    style: st.style;
    state: st.state;
    direction: st.direction;
    dest_b64: st.dest_b64;
    peer: st.peer;
    port: st.port;
    silent: silent;
  };
}

/// Name of a stream state. Params: state - a state id. Returns: "NEW",
/// "CONNECTING", "ACCEPTING", "FORWARDING", "OPEN", "FAILED", "CLOSED" or
/// "UNKNOWN". Error case: none. Complexity: O(1).
pub fn stream_state_name(state: Int) -> Str {
  if state == I2P_STREAM_NEW { return "NEW"; }
  if state == I2P_STREAM_CONNECTING { return "CONNECTING"; }
  if state == I2P_STREAM_ACCEPTING { return "ACCEPTING"; }
  if state == I2P_STREAM_FORWARDING { return "FORWARDING"; }
  if state == I2P_STREAM_OPEN { return "OPEN"; }
  if state == I2P_STREAM_FAILED { return "FAILED"; }
  if state == I2P_STREAM_CLOSED { return "CLOSED"; }
  return "UNKNOWN";
}

// --------------------------------------------------
//  Address book (naming store shape)
// --------------------------------------------------

/// New empty address book. Params: none. Returns: the book.
/// Error case: none. Complexity: O(1).
pub fn book_new() -> I2pAddressBook {
  return I2pAddressBook{ names: Vec[Str].new(); dests: Vec[Str].new(); };
}

/// Number of name -> destination mappings. Params: b - the book. Returns:
/// the count. Error case: none. Complexity: O(1).
pub fn book_count(b: &I2pAddressBook) -> Int {
  let ns: Vec[Str] = b.names;
  return ns.len();
}

/// True when the book maps `name`. Params: b - the book; name - the
/// name. Returns: the predicate. Error case: none. Complexity: O(entries).
pub fn book_contains(b: &I2pAddressBook, name: Str) -> Bool {
  let ns: Vec[Str] = b.names;
  return _str_index(&ns, name) >= 0;
}

/// Insert or replace one mapping. The name must be a valid ".i2p" host and
/// the destination a canonical string; replacing keeps the original
/// position. Params: b - the book; name - the .i2p name; dest_b64 - the
/// canonical destination. Returns: Ok(new book). Error case:
/// Err("i2p: invalid address book name" / "i2p: invalid address book
/// destination" / "i2p: address book full"). Complexity: O(entries).
pub fn book_set(b: &I2pAddressBook, name: Str, dest_b64: Str) -> Result[I2pAddressBook, Str] {
  if !addr_is_i2p_host(name) {
    return _err_book("i2p: invalid address book name");
  }
  let dr = dest_parse_b64(dest_b64);
  if !dr.is_ok {
    return _err_book("i2p: invalid address book destination");
  }
  let ns: Vec[Str] = b.names;
  let ds: Vec[Str] = b.dests;
  let idx = _str_index(&ns, name);
  if idx < 0 && ns.len() >= I2P_MAX_BOOK_ENTRIES {
    return _err_book("i2p: address book full");
  }
  var names = Vec[Str].new();
  var dests = Vec[Str].new();
  var i = 0;
  while i < ns.len() {
    if i == idx {
      names.push(name);
      dests.push(dest_b64);
    } else {
      let n2: Str = ns[i];
      let d2: Str = ds[i];
      names.push(n2);
      dests.push(d2);
    }
    i = i + 1;
  }
  if idx < 0 {
    names.push(name);
    dests.push(dest_b64);
  }
  return _ok_book(I2pAddressBook{ names: names; dests: dests; });
}

/// Look up one mapping. Params: b - the book; name - the name. Returns:
/// Ok(destination). Error case: Err("i2p: name not in address book").
/// Complexity: O(entries).
pub fn book_get(b: &I2pAddressBook, name: Str) -> Result[Str, Str] {
  let ns: Vec[Str] = b.names;
  let ds: Vec[Str] = b.dests;
  let idx = _str_index(&ns, name);
  if idx < 0 {
    return _err_str("i2p: name not in address book");
  }
  if idx >= ds.len() {
    return _err_str("i2p: name not in address book");
  }
  let d: Str = ds[idx];
  return _ok_str(d);
}

/// Remove one mapping. Params: b - the book; name - the name. Returns:
/// Ok(new book without it). Error case:
/// Err("i2p: name not in address book"). Complexity: O(entries).
pub fn book_remove(b: &I2pAddressBook, name: Str) -> Result[I2pAddressBook, Str] {
  let ns: Vec[Str] = b.names;
  let ds: Vec[Str] = b.dests;
  let idx = _str_index(&ns, name);
  if idx < 0 {
    return _err_book("i2p: name not in address book");
  }
  var names = Vec[Str].new();
  var dests = Vec[Str].new();
  var i = 0;
  while i < ns.len() {
    if i != idx {
      let n2: Str = ns[i];
      names.push(n2);
      if i < ds.len() {
        let d2: Str = ds[i];
        dests.push(d2);
      }
    }
    i = i + 1;
  }
  return _ok_book(I2pAddressBook{ names: names; dests: dests; });
}

/// Name at index i, or "" when out of range. Params: b - the book; i -
/// the index. Returns: the name. Error case: none. Complexity: O(1).
pub fn book_name_at(b: &I2pAddressBook, i: Int) -> Str {
  let ns: Vec[Str] = b.names;
  if i < 0 || i >= ns.len() {
    return "";
  }
  let n: Str = ns[i];
  return n;
}

/// Destination at index i, or "" when out of range and "" when the
/// parallel arrays have drifted (guarded invariant). Params: b - the book;
/// i - the index. Returns: the destination. Error case: none.
/// Complexity: O(1).
pub fn book_dest_at(b: &I2pAddressBook, i: Int) -> Str {
  let ns: Vec[Str] = b.names;
  let ds: Vec[Str] = b.dests;
  if i < 0 || i >= ns.len() {
    return "";
  }
  if i >= ds.len() {
    return "";
  }
  let d: Str = ds[i];
  return d;
}

// --------------------------------------------------
//  Lease set shape
// --------------------------------------------------

// Independent copy of a Vec[Int].
fn _copy_ints(src: &Vec[Int]) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < src.len() {
    let v: Int = src[i];
    out.push(v);
    i = i + 1;
  }
  return out;
}

/// New lease set for a destination with zero leases. Params: dest_b64 - a
/// canonical destination string. Returns: Ok(lease set). Error case:
/// Err("i2p: lease set destination invalid"). Complexity: O(len(dest_b64)).
pub fn leaseset_new(dest_b64: Str) -> Result[I2pLeaseSet, Str] {
  let dr = dest_parse_b64(dest_b64);
  if !dr.is_ok {
    return _err_leaseset("i2p: lease set destination invalid");
  }
  return _ok_leaseset(I2pLeaseSet{
    dest_b64: dest_b64;
    peers: Vec[Str].new();
    tunnel_ids: Vec[Int].new();
    end_dates: Vec[Int].new();
  });
}

/// Append one lease (peer router hash, tunnel id, end date). Every push is
/// mirrored on all three parallel arrays, so the lengths never drift.
/// Params: ls - the lease set; peer_b64 - base64 of the 32-byte peer hash;
/// tunnel_id - 0..2^32-1; end_date - positive caller-clock milliseconds.
/// Returns: Ok(lease set with one more lease). Error case:
/// Err("i2p: lease set full" / "i2p: invalid lease peer hash" /
/// "i2p: invalid lease tunnel id" / "i2p: invalid lease end date").
/// Complexity: O(leases).
pub fn leaseset_add(ls: &I2pLeaseSet, peer_b64: Str, tunnel_id: Int, end_date: Int) -> Result[I2pLeaseSet, Str] {
  let ps: Vec[Str] = ls.peers;
  let ts: Vec[Int] = ls.tunnel_ids;
  let es: Vec[Int] = ls.end_dates;
  if ps.len() >= I2P_LEASESET_MAX_LEASES {
    return _err_leaseset("i2p: lease set full");
  }
  let pr = b64_decode(peer_b64);
  if !pr.is_ok {
    return _err_leaseset("i2p: invalid lease peer hash");
  }
  let h: Vec[UInt8] = pr.value;
  if h.len() != I2P_HASH_LEN {
    return _err_leaseset("i2p: invalid lease peer hash");
  }
  if tunnel_id < 0 || tunnel_id > I2P_MAX_U32 {
    return _err_leaseset("i2p: invalid lease tunnel id");
  }
  if end_date <= 0 {
    return _err_leaseset("i2p: invalid lease end date");
  }
  var peers = _copy_strs(&ps);
  var tids = _copy_ints(&ts);
  var dates = _copy_ints(&es);
  peers.push(peer_b64);
  tids.push(tunnel_id);
  dates.push(end_date);
  return _ok_leaseset(I2pLeaseSet{
    dest_b64: ls.dest_b64;
    peers: peers;
    tunnel_ids: tids;
    end_dates: dates;
  });
}

/// Number of leases. Params: ls - the lease set. Returns: the count
/// (guarded to the smallest parallel array). Error case: none.
/// Complexity: O(1).
pub fn leaseset_count(ls: &I2pLeaseSet) -> Int {
  let ps: Vec[Str] = ls.peers;
  let ts: Vec[Int] = ls.tunnel_ids;
  let es: Vec[Int] = ls.end_dates;
  var n = ps.len();
  if ts.len() < n { n = ts.len(); }
  if es.len() < n { n = es.len(); }
  return n;
}

/// Peer hash at index i, or "" when out of range. Params: ls - the lease
/// set; i - the index. Returns: the base64 peer hash. Error case: none.
/// Complexity: O(1).
pub fn leaseset_peer_at(ls: &I2pLeaseSet, i: Int) -> Str {
  let ps: Vec[Str] = ls.peers;
  if i < 0 || i >= ps.len() {
    return "";
  }
  let p: Str = ps[i];
  return p;
}

/// Tunnel id at index i, or -1 when out of range. Params: ls - the lease
/// set; i - the index. Returns: the tunnel id. Error case: none.
/// Complexity: O(1).
pub fn leaseset_tunnel_at(ls: &I2pLeaseSet, i: Int) -> Int {
  let ts: Vec[Int] = ls.tunnel_ids;
  if i < 0 || i >= ts.len() {
    return -1;
  }
  let t: Int = ts[i];
  return t;
}

/// End date at index i, or -1 when out of range. Params: ls - the lease
/// set; i - the index. Returns: the end date. Error case: none.
/// Complexity: O(1).
pub fn leaseset_enddate_at(ls: &I2pLeaseSet, i: Int) -> Int {
  let es: Vec[Int] = ls.end_dates;
  if i < 0 || i >= es.len() {
    return -1;
  }
  let t: Int = es[i];
  return t;
}

/// True when no lease has an end date strictly after now_ms (an empty
/// lease set is trivially all-expired). Params: ls - the lease set; now_ms
/// - the caller's clock. Returns: the predicate. Error case: none.
/// Complexity: O(leases).
pub fn leaseset_all_expired(ls: &I2pLeaseSet, now_ms: Int) -> Bool {
  let es: Vec[Int] = ls.end_dates;
  var i = 0;
  while i < es.len() {
    let t: Int = es[i];
    if t > now_ms {
      return false;
    }
    i = i + 1;
  }
  return true;
}
