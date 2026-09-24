// XIOM -- xiom.telnet: Telnet negotiation codec (RFC 854 / RFC 855 subset)
// Greenfield package: pure XIOM, no FFI, no I/O (in-memory Vec[UInt8] only).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: the negotiation layer only. The module encodes and decodes the
// IAC-led command stream -- WILL/WONT/DO/DONT option negotiation,
// subnegotiation (SB ... SE) framing and the 0xFF data-escaping rule -- and
// produces a flat event table. It implements no option semantics (NAWS,
// TTYPE, LINEMODE, terminal emulation, ...) and keeps no session state;
// callers drive that from the event table. See SPEC.md for the byte-level
// grammar, the escaping rules, the error catalog and the test plan.
//
// v0.61.3 notes that shaped this module:
//   * Free functions only; all events live in one flat struct with parallel
//     Vec fields (Vec[StructType] is unsupported in this compiler).
//   * Ok/Err for Result[TelnetEvents, Str] and Result[Vec[UInt8], Str] are
//     constructed only in the tiny leaf helpers below (constructing Results
//     directly inside other functions miscompiles).
//   * every raw byte widens through `(data[i] as Int) & 0xFF`; a bare
//     `as Int` on a UInt8 can miscompile (midi/wasm precedent).
//   * Vec element reads are bound to typed locals before comparison.
//   * no match arm builds a Vec; the SB scan is a plain while loop.

module xiom.telnet

// Telnet command bytes (RFC 854, section 4):
//   IAC 255 = "interpret as command"; WILL 251 / WONT 252 / DO 253 / DONT 254
//   begin option negotiation; SB 250 ... SE 240 delimit subnegotiation.
pub const TELNET_IAC: Int = 255;
pub const TELNET_DONT: Int = 254;
pub const TELNET_DO: Int = 253;
pub const TELNET_WONT: Int = 252;
pub const TELNET_WILL: Int = 251;
pub const TELNET_SB: Int = 250;
pub const TELNET_SE: Int = 240;

// Event kind codes carried in TelnetEvents.kinds.
const _KIND_WILL: Int = 1;
const _KIND_WONT: Int = 2;
const _KIND_DO: Int = 3;
const _KIND_DONT: Int = 4;
const _KIND_SB: Int = 5;

/// Negotiation event table: parallel vectors, one entry per event in stream
/// order, so entry i is (kinds[i], options[i], payload_offsets[i],
/// payload_lengths[i]). kinds[i] is 1 WILL, 2 WONT, 3 DO, 4 DONT or 5 SB.
/// For negotiation events payload_offsets[i] is -1 and payload_lengths[i] is
/// 0. For SB events payload_offsets[i]/payload_lengths[i] locate the RAW
/// subnegotiation payload inside the parsed input; a doubled IAC inside the
/// payload stays raw and therefore counts as two bytes. Fields are
/// implementation details: read them through the telnet_* accessors, which
/// are bounds-safe.
pub type TelnetEvents = {
  kinds: Vec[Int];
  options: Vec[Int];
  payload_offsets: Vec[Int];
  payload_lengths: Vec[Int];
}

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

// Ok(e) for Result[TelnetEvents, Str].
fn _ok_events(e: TelnetEvents) -> Result[TelnetEvents, Str] {
  return Ok(e);
}

// Err(m) for Result[TelnetEvents, Str].
fn _err_events(m: Str) -> Result[TelnetEvents, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// One byte of `data` at `pos`, zero-extended to 0..255. The caller
// guarantees 0 <= pos < data.len().
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Append one event with no payload slot (negotiation events).
fn _push_negotiation(kinds: &mut Vec[Int], options: &mut Vec[Int],
                     payload_offsets: &mut Vec[Int], payload_lengths: &mut Vec[Int],
                     kind: Int, option: Int) {
  kinds.push(kind);
  options.push(option);
  payload_offsets.push(-1);
  payload_lengths.push(0);
}

// Append one SB event pointing at the raw payload bytes [offset, offset+len).
fn _push_sb(kinds: &mut Vec[Int], options: &mut Vec[Int],
            payload_offsets: &mut Vec[Int], payload_lengths: &mut Vec[Int],
            option: Int, offset: Int, len: Int) {
  kinds.push(_KIND_SB);
  options.push(option);
  payload_offsets.push(offset);
  payload_lengths.push(len);
}

// --------------------------------------------------
//  Encoder
// --------------------------------------------------

/// Build a three-byte negotiation command: IAC verb option.
/// Params: verb - one of TELNET_WILL (251), TELNET_WONT (252),
/// TELNET_DO (253) or TELNET_DONT (254); option - the option code 0..255.
/// Returns: Ok([255, verb, option]).
/// Error case: Err("telnet: verb out of range") when verb is not one of the
/// four negotiation verbs (TELNET_SB and TELNET_IAC included);
/// Err("telnet: option out of range") for option outside 0..255. The verb is
/// validated first, so an invalid verb wins over an invalid option.
/// Complexity: O(1).
pub fn telnet_build_negotiation(verb: Int, option: Int) -> Result[Vec[UInt8], Str] {
  if verb != TELNET_WILL && verb != TELNET_WONT && verb != TELNET_DO && verb != TELNET_DONT {
    return _err_bytes("telnet: verb out of range");
  }
  if option < 0 || option > 255 {
    return _err_bytes("telnet: option out of range");
  }
  var out = Vec[UInt8].new();
  out.push(TELNET_IAC as UInt8);
  out.push(verb as UInt8);
  out.push(option as UInt8);
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

/// Parse a Telnet byte stream into its negotiation event table.
/// Params: data - the raw bytes of one stream chunk (client-to-server or
/// server-to-client; the codec is direction-agnostic).
/// Grammar (full statement in SPEC.md):
///   * a byte other than IAC (255) is data and is skipped;
///   * IAC IAC is an escaped data byte (0xFF) and is NOT an event;
///   * IAC WILL/WONT/DO/DONT option is one negotiation event;
///   * IAC SB option ... IAC SE is one SB event whose raw payload is
///     `payload_offsets[i] .. payload_offsets[i] + payload_lengths[i]`;
///     a doubled IAC inside the payload stays raw (two bytes, not one).
/// Returns: Ok(events) with parallel vectors in stream order.
/// Error case: Err("telnet: truncated IAC") for a bare IAC at the end;
/// Err("telnet: truncated negotiation") for IAC verb without the option
/// byte; Err("telnet: truncated subnegotiation") for IAC SB without the
/// option byte; Err("telnet: unterminated subnegotiation") when the SB
/// payload runs off the end of the input;
/// Err("telnet: IAC in subnegotiation must be followed by IAC or SE") for
/// any other byte after IAC inside SB;
/// Err("telnet: unknown IAC command") for any IAC-led byte outside the
/// modeled command set (including a stray IAC SE and RFC 854's NOP/DM/BRK/
/// IP/AO/AYT/EC/EL/GA commands, which this codec does not model).
/// Complexity: O(data length).
pub fn telnet_parse(data: &Vec[UInt8]) -> Result[TelnetEvents, Str] {
  var kinds = Vec[Int].new();
  var options = Vec[Int].new();
  var payload_offsets = Vec[Int].new();
  var payload_lengths = Vec[Int].new();
  let n = data.len();
  var i = 0;
  while i < n {
    let b = _byte(data, i);
    if b != TELNET_IAC {
      i = i + 1;
    } else {
      if i + 1 >= n {
        return _err_events("telnet: truncated IAC");
      }
      let cmd = _byte(data, i + 1);
      if cmd == TELNET_IAC {
        i = i + 2;
      } elif cmd == TELNET_WILL || cmd == TELNET_WONT || cmd == TELNET_DO || cmd == TELNET_DONT {
        if i + 2 >= n {
          return _err_events("telnet: truncated negotiation");
        }
        let opt = _byte(data, i + 2);
        var kind = _KIND_WILL;
        if cmd == TELNET_WONT {
          kind = _KIND_WONT;
        } elif cmd == TELNET_DO {
          kind = _KIND_DO;
        } elif cmd == TELNET_DONT {
          kind = _KIND_DONT;
        }
        _push_negotiation(&mut kinds, &mut options, &mut payload_offsets, &mut payload_lengths, kind, opt);
        i = i + 3;
      } elif cmd == TELNET_SB {
        if i + 2 >= n {
          return _err_events("telnet: truncated subnegotiation");
        }
        let opt = _byte(data, i + 2);
        let start = i + 3;
        var j = start;
        var closed = false;
        while j < n && !closed {
          let pb = _byte(data, j);
          if pb != TELNET_IAC {
            j = j + 1;
          } else {
            if j + 1 >= n {
              return _err_events("telnet: unterminated subnegotiation");
            }
            let nxt = _byte(data, j + 1);
            if nxt == TELNET_IAC {
              j = j + 2;
            } elif nxt == TELNET_SE {
              _push_sb(&mut kinds, &mut options, &mut payload_offsets, &mut payload_lengths, opt, start, j - start);
              i = j + 2;
              closed = true;
            } else {
              return _err_events("telnet: IAC in subnegotiation must be followed by IAC or SE");
            }
          }
        }
        if !closed {
          return _err_events("telnet: unterminated subnegotiation");
        }
      } else {
        return _err_events("telnet: unknown IAC command");
      }
    }
  }
  return _ok_events(TelnetEvents{
    kinds: kinds;
    options: options;
    payload_offsets: payload_offsets;
    payload_lengths: payload_lengths;
  });
}

// --------------------------------------------------
//  Event accessors (bounds-safe)
// --------------------------------------------------

/// Number of events in `e`. The four vectors are index-aligned by
/// construction, so this is the length of each.
/// Complexity: O(1).
pub fn telnet_event_count(e: &TelnetEvents) -> Int {
  return e.kinds.len();
}

/// Kind of event `index`: 1 WILL, 2 WONT, 3 DO, 4 DONT or 5 SB.
/// Returns: the kind, or -1 when index is negative or >= event count.
/// Complexity: O(1).
pub fn telnet_kind(e: &TelnetEvents, index: Int) -> Int {
  if index < 0 || index >= e.kinds.len() {
    return -1;
  }
  let kind: Int = e.kinds[index];
  return kind;
}

/// Option code of event `index` (0..255).
/// Returns: the option, or -1 when index is negative or >= event count.
/// Complexity: O(1).
pub fn telnet_option(e: &TelnetEvents, index: Int) -> Int {
  if index < 0 || index >= e.options.len() {
    return -1;
  }
  let option: Int = e.options[index];
  return option;
}

/// Raw payload offset of SB event `index` inside the parsed input.
/// Returns: the byte offset of the first payload byte (a doubled IAC's first
/// byte counts here), or -1 when the event is not SB or when index is
/// negative or >= event count.
/// Complexity: O(1).
pub fn telnet_payload_offset(e: &TelnetEvents, index: Int) -> Int {
  if index < 0 || index >= e.payload_offsets.len() {
    return -1;
  }
  let offset: Int = e.payload_offsets[index];
  return offset;
}

/// Raw payload length of SB event `index` in bytes (a doubled IAC counts as
/// two bytes because it stays raw).
/// Returns: the length, 0 for negotiation events, or -1 when index is
/// negative or >= event count.
/// Complexity: O(1).
pub fn telnet_payload_length(e: &TelnetEvents, index: Int) -> Int {
  if index < 0 || index >= e.payload_lengths.len() {
    return -1;
  }
  let len: Int = e.payload_lengths[index];
  return len;
}

// --------------------------------------------------
//  Data escaping
// --------------------------------------------------

/// Escape a data buffer for transmission: every 0xFF byte becomes IAC IAC
/// (255 255); all other bytes pass through unchanged.
/// Params: data - the unescaped application data.
/// Returns: a fresh buffer of length data.len() + (number of 0xFF bytes).
/// Complexity: O(data length).
pub fn telnet_escape_data(data: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = data.len();
  var i = 0;
  while i < n {
    let b = _byte(data, i);
    if b == TELNET_IAC {
      out.push(TELNET_IAC as UInt8);
      out.push(TELNET_IAC as UInt8);
    } else {
      out.push(b as UInt8);
    }
    i = i + 1;
  }
  return out;
}

/// Unescape a data buffer received from the wire: IAC IAC (255 255) becomes
/// one 0xFF byte; every other IAC sequence and every non-IAC byte passes
/// through verbatim, so a lone trailing IAC stays as one byte. Use this only
/// on a buffer that is known to be data (the parser rejects unknown IAC
/// commands), because escaping is not invertible for arbitrary streams:
/// unescape then escape leaves stray IAC-led sequences untouched, while
/// escape then unescape always round-trips.
/// Params: data - the escaped wire bytes.
/// Returns: a fresh buffer; IAC IAC pairs collapse to one 0xFF each.
/// Complexity: O(data length).
pub fn telnet_unescape_data(data: &Vec<UInt8>) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = data.len();
  var i = 0;
  while i < n {
    let b = _byte(data, i);
    if b == TELNET_IAC && i + 1 < n {
      let nxt = _byte(data, i + 1);
      if nxt == TELNET_IAC {
        out.push(TELNET_IAC as UInt8);
        i = i + 2;
      } else {
        out.push(b as UInt8);
        i = i + 1;
      }
    } else {
      out.push(b as UInt8);
      i = i + 1;
    }
  }
  return out;
}
