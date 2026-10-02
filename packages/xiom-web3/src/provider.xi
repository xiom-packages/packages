// XIOM -- xiom.web3.provider: blockchain provider request/response model
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// MODEL ONLY -- nothing in this module opens a socket. It validates provider
// configuration (http/ws/ipc endpoint shape, chain id, timeout), builds the
// canonical compact JSON-RPC 2.0 request text, and scans a response envelope
// back with a byte-wise member scanner (not a JSON parser): integer id with
// optional request-id matching, a scalar result value, or an error object
// with integer code and string message. Objects/arrays as `result` and
// non-canonical quantity text are rejected/documented. Raw `result` text is
// returned verbatim for the caller's own decoder.

module xiom.web3.provider

use xiom.string;
use xiom.string.builder;
use xiom.convert;

/// Provider transport kind: plain HTTP(S) endpoint.
pub const PROVIDER_HTTP: Int = 0;
/// Provider transport kind: WebSocket endpoint (modeled, not opened).
pub const PROVIDER_WS: Int = 1;
/// Provider transport kind: local IPC socket or pipe path.
pub const PROVIDER_IPC: Int = 2;
/// Largest accepted provider timeout, in milliseconds.
pub const PROVIDER_MAX_TIMEOUT_MS: Int = 3600000;

/// Validated provider configuration; no connection is ever made here.
pub type ProviderConfig = {
  kind: Int;
  url: Str;
  chain_id: Int;
  timeout_ms: Int;
}

/// Validated JSON-RPC request. `params` is raw JSON array text supplied by
/// the caller and inserted verbatim.
pub type RpcRequest = {
  id: Int;
  method: Str;
  params: Str;
}

/// Decoded JSON-RPC response. `ok` selects the member: `result_json` (raw
/// scalar JSON text) or `error_code` / `error_message`.
pub type RpcResponse = {
  id: Int;
  ok: Bool;
  result_json: Str;
  error_code: Int;
  error_message: Str;
}

// Ok(v) for Result[ProviderConfig, Str] (leaf helper, trap 6).
fn _ok_cfg(v: ProviderConfig) -> Result[ProviderConfig, Str] {
  return Ok(v);
}

// Err(m) for Result[ProviderConfig, Str].
fn _err_cfg(m: Str) -> Result[ProviderConfig, Str] {
  return Err(m);
}

// Ok(v) for Result[RpcRequest, Str].
fn _ok_req(v: RpcRequest) -> Result[RpcRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[RpcRequest, Str].
fn _err_req(m: Str) -> Result[RpcRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[RpcResponse, Str].
fn _ok_resp(v: RpcResponse) -> Result[RpcResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[RpcResponse, Str].
fn _err_resp(m: Str) -> Result[RpcResponse, Str] {
  return Err(m);
}

// True for JSON-RPC method characters: A-Z, a-z, 0-9 and underscore.
fn _pv_is_method_char(c: Int) -> Bool {
  if c >= 65 && c <= 90 { return true; }
  if c >= 97 && c <= 122 { return true; }
  if c >= 48 && c <= 57 { return true; }
  return c == 95;
}

/// Validate a provider configuration. Errors: `web3: provider kind must be
/// 0 (http), 1 (ws) or 2 (ipc)`, `web3: provider url must not be empty`,
/// `web3: provider url scheme does not match the provider kind`,
/// `web3: provider chain id is negative`, `web3: provider timeout must be
/// 1..3600000 ms`.
pub fn provider_config(kind: Int, url: Str, chain_id: Int,
                       timeout_ms: Int) -> Result[ProviderConfig, Str] {
  if kind < 0 || kind > 2 {
    return _err_cfg("web3: provider kind must be 0 (http), 1 (ws) or 2 (ipc)");
  }
  if string.str_len(url) == 0 {
    return _err_cfg("web3: provider url must not be empty");
  }
  var scheme_ok = false;
  if kind == PROVIDER_HTTP {
    if string.str_starts_with(url, "http://") || string.str_starts_with(url, "https://") {
      scheme_ok = true;
    }
  } else if kind == PROVIDER_WS {
    if string.str_starts_with(url, "ws://") || string.str_starts_with(url, "wss://") {
      scheme_ok = true;
    }
  } else {
    if !string.str_contains(url, "://") {
      scheme_ok = true;
    }
  }
  if !scheme_ok {
    return _err_cfg("web3: provider url scheme does not match the provider kind");
  }
  if chain_id < 0 {
    return _err_cfg("web3: provider chain id is negative");
  }
  if timeout_ms < 1 || timeout_ms > PROVIDER_MAX_TIMEOUT_MS {
    return _err_cfg("web3: provider timeout must be 1..3600000 ms");
  }
  return _ok_cfg(ProviderConfig{
    kind: kind;
    url: url;
    chain_id: chain_id;
    timeout_ms: timeout_ms;
  });
}

/// Validate one request: non-negative id, method of `[A-Za-z0-9_]+`, and
/// `params` as non-empty JSON array text starting with '[' and ending with
/// ']'. Errors: `web3: rpc request id is negative`, `web3: rpc method must
/// not be empty`, `web3: rpc method contains an invalid character`,
/// `web3: rpc params must be a JSON array text`.
pub fn provider_request(id: Int, method: Str,
                        params: Str) -> Result[RpcRequest, Str] {
  if id < 0 {
    return _err_req("web3: rpc request id is negative");
  }
  let mlen = string.str_len(method);
  if mlen == 0 {
    return _err_req("web3: rpc method must not be empty");
  }
  var i = 0;
  while i < mlen {
    let c: Int = (string.byte_at(method, i) as Int) & 0xFF;
    if !_pv_is_method_char(c) {
      return _err_req("web3: rpc method contains an invalid character");
    }
    i = i + 1;
  }
  let plen = string.str_len(params);
  if plen < 2 {
    return _err_req("web3: rpc params must be a JSON array text");
  }
  let p0: Int = (string.byte_at(params, 0) as Int) & 0xFF;
  let p1: Int = (string.byte_at(params, plen - 1) as Int) & 0xFF;
  if p0 != 91 || p1 != 93 {
    return _err_req("web3: rpc params must be a JSON array text");
  }
  return _ok_req(RpcRequest{ id: id; method: method; params: params; });
}

/// Canonical compact JSON-RPC 2.0 request text (fixed member order, params
/// inserted verbatim).
pub fn provider_encode_request(req: &RpcRequest) -> Str {
  return "{\"jsonrpc\":\"2.0\",\"id\":" + convert.int_to_string(req.id)
    + ",\"method\":\"" + req.method + "\",\"params\":" + req.params + "}";
}

/// Success response constructor.
pub fn provider_response_ok(id: Int, result_json: Str) -> RpcResponse {
  return RpcResponse{
    id: id;
    ok: true;
    result_json: result_json;
    error_code: 0;
    error_message: "";
  };
}

/// Error response constructor.
pub fn provider_response_error(id: Int, code: Int, message: Str) -> RpcResponse {
  return RpcResponse{
    id: id;
    ok: false;
    result_json: "";
    error_code: code;
    error_message: message;
  };
}

// Index of the first byte of `s` at or after pos that is not JSON whitespace.
fn _pv_skip_ws(s: Str, pos: Int) -> Int {
  let n = string.str_len(s);
  var i = pos;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 32 || b == 9 || b == 10 || b == 13 {
      i = i + 1;
    } else {
      break;
    }
  }
  return i;
}

// Scan a JSON string starting at the quote at s[pos]; returns the index one
// past the closing quote, or -1 when malformed/truncated. Escapes are
// skipped byte-for-byte (two bytes), not decoded.
fn _pv_scan_string(s: Str, pos: Int) -> Int {
  let n = string.str_len(s);
  if pos >= n { return -1; }
  let q: Int = (string.byte_at(s, pos) as Int) & 0xFF;
  if q != 34 { return -1; }
  var i = pos + 1;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 92 {
      i = i + 2;
    } else if b == 34 {
      return i + 1;
    } else {
      i = i + 1;
    }
  }
  return -1;
}

// Scan a scalar JSON value (string, number, true, false, null) at s[pos];
// returns the index one past its last byte, or -1. Objects and arrays are
// deliberately outside the documented subset.
fn _pv_scan_scalar(s: Str, pos: Int) -> Int {
  let n = string.str_len(s);
  if pos >= n { return -1; }
  let b: Int = (string.byte_at(s, pos) as Int) & 0xFF;
  if b == 34 {
    return _pv_scan_string(s, pos);
  }
  if b == 123 || b == 91 {
    return -1;
  }
  var i = pos;
  while i < n {
    let c: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if c == 44 || c == 125 || c == 32 || c == 9 || c == 10 || c == 13 {
      break;
    }
    i = i + 1;
  }
  if i == pos { return -1; }
  return i;
}

// End of a bare token (number/bool/null): first of ',', '}' or whitespace.
fn _pv_token_end(s: Str, pos: Int) -> Int {
  let n = string.str_len(s);
  var i = pos;
  while i < n {
    let c: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if c == 44 || c == 125 || c == 32 || c == 9 || c == 10 || c == 13 {
      break;
    }
    i = i + 1;
  }
  return i;
}

// Find a quoted member key anywhere in the text and return the index of its
// value start (after ':' and whitespace), or -1. Keys inside string values
// are skipped. This is a member scanner, not a validating JSON parser.
fn _pv_find_key(s: Str, key: Str) -> Int {
  let n = string.str_len(s);
  let klen = string.str_len(key);
  var i = 0;
  while i < n {
    let b: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 34 {
      let e = _pv_scan_string(s, i);
      if e < 0 { return -1; }
      if e - i == klen + 2 {
        var same = true;
        var k = 0;
        while k < klen {
          let kb: Int = (string.byte_at(key, k) as Int) & 0xFF;
          let sb: Int = (string.byte_at(s, i + 1 + k) as Int) & 0xFF;
          if kb != sb {
            same = false;
            break;
          }
          k = k + 1;
        }
        if same {
          let j = _pv_skip_ws(s, e);
          if j < n {
            let c: Int = (string.byte_at(s, j) as Int) & 0xFF;
            if c == 58 {
              return _pv_skip_ws(s, j + 1);
            }
          }
        }
      }
      i = e;
    } else {
      i = i + 1;
    }
  }
  return -1;
}

// Parse a signed decimal integer token at s[pos] (used for id and error
// code). `what` names the member in the error text.
fn _pv_parse_int(s: Str, pos: Int, what: Str) -> Result[Int, Str] {
  let n = string.str_len(s);
  var i = pos;
  var neg = false;
  if i < n {
    let b0: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if b0 == 45 {
      neg = true;
      i = i + 1;
    }
  }
  var digits = 0;
  var v: Int = 0;
  while i < n {
    let c: Int = (string.byte_at(s, i) as Int) & 0xFF;
    if c < 48 || c > 57 {
      break;
    }
    var d = c - 48;
    if neg {
      d = 0 - d;
    }
    if neg {
      if v < -922337203685477580 || (v == -922337203685477580 && d < -8) {
        return Err("web3: response " + what + " is out of range");
      }
    } else {
      if v > 922337203685477580 || (v == 922337203685477580 && d > 7) {
        return Err("web3: response " + what + " is out of range");
      }
    }
    v = v * 10 + d;
    digits = digits + 1;
    i = i + 1;
  }
  if digits == 0 {
    return Err("web3: response " + what + " is not an integer");
  }
  return Ok(v);
}

/// Scan a JSON-RPC response envelope. `expected_id` >= 0 requires the id
/// member to match; pass -1 to skip the check. The documented subset:
/// `"id"` is an integer, `"result"` is a scalar value (string, number,
/// true, false, null; objects/arrays are rejected), or `"error"` is an
/// object with integer `code` and string `message`. Member key order is
/// free; escape sequences in the error message are returned raw. Errors
/// start with `web3: response`.
pub fn provider_decode_response(body: Str,
                                expected_id: Int) -> Result[RpcResponse, Str] {
  let idpos = _pv_find_key(body, "id");
  if idpos < 0 {
    return _err_resp("web3: response has no id member");
  }
  let idr = _pv_parse_int(body, idpos, "id");
  if !idr.is_ok {
    return _err_resp(idr.error);
  }
  let id: Int = idr.value;
  if expected_id >= 0 && id != expected_id {
    return _err_resp("web3: response id does not match the request id");
  }
  let rpos = _pv_find_key(body, "result");
  let epos = _pv_find_key(body, "error");
  if rpos >= 0 && epos >= 0 {
    return _err_resp("web3: response has both result and error");
  }
  if rpos >= 0 {
    let rend = _pv_scan_scalar(body, rpos);
    if rend < 0 {
      return _err_resp("web3: response result must be a scalar JSON value");
    }
    let rtext = string.str_slice(body, rpos, rend);
    return _ok_resp(provider_response_ok(id, rtext));
  }
  if epos >= 0 {
    let cpos = _pv_find_key(body, "code");
    let mpos = _pv_find_key(body, "message");
    if cpos < 0 || mpos < 0 {
      return _err_resp("web3: response error object needs code and message");
    }
    let cr = _pv_parse_int(body, cpos, "error code");
    if !cr.is_ok {
      return _err_resp(cr.error);
    }
    let mend = _pv_scan_string(body, mpos);
    if mend < 0 {
      return _err_resp("web3: response error message is not a JSON string");
    }
    let mtext = string.str_slice(body, mpos + 1, mend - 1);
    let code: Int = cr.value;
    return _ok_resp(provider_response_error(id, code, mtext));
  }
  return _err_resp("web3: response has neither result nor error member");
}

// Hex digit value 0..15, or -1.
fn _pv_hex_digit(c: Int) -> Int {
  if c >= 48 && c <= 57 { return c - 48; }
  if c >= 97 && c <= 102 { return c - 87; }
  if c >= 65 && c <= 70 { return c - 55; }
  return -1;
}

/// Parse a canonical `0x` quantity ("0x0", "0x2a"; no leading zeros, no
/// sign) into the signed 64-bit range. Errors: `web3: quantity must start
/// with 0x`, `web3: quantity has no hex digits`, `web3: quantity is not
/// canonical (leading zero)`, `web3: quantity has a non-hex character`,
/// `web3: quantity exceeds the signed 64-bit range`.
pub fn provider_parse_quantity(text: Str) -> Result[Int, Str] {
  let n = string.str_len(text);
  if n < 2 {
    return Err("web3: quantity must start with 0x");
  }
  let p0: Int = (string.byte_at(text, 0) as Int) & 0xFF;
  let p1: Int = (string.byte_at(text, 1) as Int) & 0xFF;
  if p0 != 48 || p1 != 120 {
    return Err("web3: quantity must start with 0x");
  }
  if n == 2 {
    return Err("web3: quantity has no hex digits");
  }
  let d0: Int = (string.byte_at(text, 2) as Int) & 0xFF;
  if n > 3 && d0 == 48 {
    return Err("web3: quantity is not canonical (leading zero)");
  }
  var v: Int = 0;
  var i = 2;
  while i < n {
    let c: Int = (string.byte_at(text, i) as Int) & 0xFF;
    let d: Int = _pv_hex_digit(c);
    if d < 0 {
      return Err("web3: quantity has a non-hex character");
    }
    if v > 576460752303423487 {
      return Err("web3: quantity exceeds the signed 64-bit range");
    }
    v = v * 16 + d;
    i = i + 1;
  }
  return Ok(v);
}

// Uppercase/lowercase hex character for a nibble 0..15.
fn _pv_hex_char(d: Int) -> UInt8 {
  if d < 10 {
    return (48 + d) as UInt8;
  }
  return (87 + d) as UInt8;
}

/// Canonical `0x` quantity for a non-negative Int (minimal lowercase hex);
/// negative input is `web3: quantity must be non-negative`.
pub fn provider_format_quantity(n: Int) -> Result[Str, Str] {
  if n < 0 {
    return Err("web3: quantity must be non-negative");
  }
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, "0x");
  if n == 0 {
    builder.sb_push_byte(&mut sb, 48 as UInt8);
    return Ok(builder.sb_to_str(&sb));
  }
  var digits = Vec[UInt8].new();
  var v = n;
  while v > 0 {
    digits.push((v % 16) as UInt8);
    v = v / 16;
  }
  var i = digits.len();
  while i > 0 {
    i = i - 1;
    let d: UInt8 = digits[i];
    builder.sb_push_byte(&mut sb, _pv_hex_char((d as Int) & 0xFF));
  }
  return Ok(builder.sb_to_str(&sb));
}
