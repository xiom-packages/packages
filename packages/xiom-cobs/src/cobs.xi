// XIOM -- xiom.cobs: consistent overhead byte stuffing (COBS) for framing
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI) COBS codec for one frame at a time: encode a payload
// into a byte sequence that never contains 0x00, and decode it back. The
// 0x00 byte is the frame delimiter on the wire; the caller appends one to a
// finished frame (and strips it before decoding) -- these helpers do not add
// or remove delimiters. See SPEC.md for the algorithm, boundary rules, error
// catalog and test plan.
//
// Encoding shape: a frame is a sequence of blocks; each block is one code
// byte followed by (code - 1) non-zero data bytes. A code byte below 255
// implies a 0x00 byte after the block (unless the block is the last one); a
// code byte of 255 carries a full 254-byte run and implies no 0x00. The
// encoder does not emit a redundant empty block when the input ends exactly
// on a 254-byte run boundary, so 254 non-zero bytes encode as [0xFF] + 254
// data bytes (255 bytes total). The decoder accepts both that minimal form
// and the padded form with a trailing 0x01 code byte.
//
// v0.61.3 notes that shaped this module:
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles).
//   * the encoder never assigns to a vector index: every block is scanned to
//     completion first, so its code byte is known before it is pushed (no
//     placeholder fixups, no Vec index writes).
//   * every Vec[UInt8] element read is widened with `as Int` before use.

module xiom.cobs

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// --------------------------------------------------
//  Encoding
// --------------------------------------------------

/// COBS-encode `data`. The output never contains 0x00: every byte is either
/// a code byte (1..255) or a non-zero payload byte. Empty input encodes to
/// the single code byte 0x01 (a complete empty frame). A run of non-zero
/// bytes of length L (1 <= L <= 254) is emitted as [L + 1][the L bytes]; a
/// code byte of 255 is exactly a 254-byte run and implies no following zero
/// byte. A 0x00 in the input is never emitted: it is implied by a code byte
/// below 255, or, when it follows a full 255-code block or ends the input,
/// by an explicit empty code-1 block. The exact output length is
/// cobs_encoded_size(data).
pub fn cobs_encode(data: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = data.len();
  if n == 0 {
    // Empty payload: a lone final code byte 0x01.
    out.push(1 as UInt8);
    return out;
  }
  var i = 0;
  while i < n {
    // Scan one block: at most 254 consecutive non-zero bytes.
    var j = i;
    while j < n && (data[j] as Int) != 0 && (j - i) < 254 {
      j = j + 1;
    }
    let run = j - i;
    out.push((run + 1) as UInt8);
    var k = i;
    while k < j {
      out.push(data[k]);
      k = k + 1;
    }
    if j == n {
      // The code byte just pushed is the final code byte.
      i = n;
    } else if (data[j] as Int) != 0 {
      // The run hit the 254 cap; the next block starts at j.
      i = j;
    } else {
      // data[j] is 0x00. A code byte below 255 implies it only when a
      // following block exists; a full 255-code block or a trailing 0x00
      // needs an explicit empty code-1 block, which decodes as the zero.
      if run == 254 {
        out.push(1 as UInt8);
      }
      if j + 1 == n {
        out.push(1 as UInt8);
        i = n;
      } else {
        i = j + 1;
      }
    }
  }
  return out;
}

// --------------------------------------------------
//  Decoding
// --------------------------------------------------

/// Decode one COBS frame (delimiter already stripped). Empty input decodes
/// to an empty vector. Err("cobs: zero byte in frame") when any input byte
/// is 0x00; Err("cobs: truncated frame") when a code byte declares more
/// payload bytes than remain. On Ok the result is the original payload.
/// A padded frame whose final block is an empty code-1 block (as produced by
/// encoders that always close with a code byte) decodes to the same payload.
pub fn cobs_decode(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  let n = data.len();
  var i = 0;
  while i < n {
    if (data[i] as Int) == 0 {
      return _err_bytes("cobs: zero byte in frame");
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  i = 0;
  while i < n {
    let code = data[i] as Int;
    i = i + 1;
    let payload = code - 1;
    if n - i < payload {
      return _err_bytes("cobs: truncated frame");
    }
    var k = 0;
    while k < payload {
      out.push(data[i]);
      i = i + 1;
      k = k + 1;
    }
    if code < 255 && i < n {
      out.push(0 as UInt8);
    }
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Size helpers
// --------------------------------------------------

/// Exact encoded length of `data`: always equal to
/// cobs_encode(data).len(). Computed in one pass without allocating the
/// frame. An empty input is 1 (the lone final code byte).
pub fn cobs_encoded_size(data: &Vec[UInt8]) -> Int {
  let n = data.len();
  var size = n + 1;
  var run = 0;
  var i = 0;
  while i < n {
    if (data[i] as Int) == 0 {
      run = 0;
    } else {
      run = run + 1;
      if run == 254 {
        run = 0;
        if i + 1 < n {
          size = size + 1;
        }
      }
    }
    i = i + 1;
  }
  return size;
}

/// True when `data` contains no 0x00 byte, i.e. when it is a valid COBS
/// frame body (empty input is vacuously encoded). Necessary but not
/// sufficient for decodability: cobs_decode still rejects truncated code
/// bytes.
pub fn cobs_is_encoded(data: &Vec[UInt8]) -> Bool {
  let n = data.len();
  var i = 0;
  while i < n {
    if (data[i] as Int) == 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Largest payload (in bytes) whose WORST-CASE encoded frame fits in
/// `frame_len` bytes; frame_len below 2 yields 0. The worst case is an
/// all-non-zero payload, which needs 1 code byte per 254 payload bytes plus
/// the final code byte, so the result is the largest n with
/// n + 1 + (n - 1) / 254 <= frame_len (n >= 1). Payloads containing 0x00
/// bytes are never longer for the same input length. The returned value is
/// never negative.
pub fn cobs_max_payload_for(frame_len: Int) -> Int {
  if frame_len <= 1 {
    return 0;
  }
  let q = (frame_len - 2) / 255;
  var r = frame_len - 2 - q * 255;
  if r > 253 {
    r = 253;
  }
  return 254 * q + r + 1;
}
