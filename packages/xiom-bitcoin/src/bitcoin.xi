// XIOM -- xiom.bitcoin: Bitcoin wire and address structure codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM Bitcoin wire-format and address STRUCTURE codec. It parses and
// re-emits byte layouts; it never hashes, never executes scripts and never
// touches the network:
//
//   * CompactSize (canonical, minimal-length enforced) and the legacy
//     unsigned varint (non-minimal accepted, for old addr messages), plus
//     varstr (CompactSize length + payload bytes).
//   * Message framing: 4-byte network magic (mainnet, testnet3, regtest,
//     signet), 12-byte NUL-padded ASCII command, u32 payload length with a
//     documented 32 MiB cap, 4-byte checksum preserved raw. Checksum
//     VERIFICATION needs double SHA-256 and is caller-side (see README).
//   * Messages: version, verack (framing only), addr (legacy varint count),
//     inv/getdata (CompactSize count + inventory vectors), tx (legacy and
//     BIP-144 marker/flag SegWit with witness stacks), block header and
//     block (header + tx count + consumed tx stream).
//   * Script walking: opcode table, bounded push parsing (direct,
//     OP_PUSHDATA1/2/4) and output-template classification
//     (p2pkh/p2sh/p2wpkh/p2wsh/p2tr/op_return/unknown).
//   * Base58 (Bitcoin alphabet, leading-zero handling) and Bech32/Bech32m
//     witness address decoding per BIP-173/BIP-350 (polymod checksum, v0
//     20/32-byte rule and v1+ Bech32m constant).
//
// Non-goals: no SHA-256/double-SHA-256 (so no checksum verification, no
// Base58Check validation and no block hashes), no script execution or
// validation beyond structure, no P2P networking, no consensus rules, no
// ECDSA/secp256k1, no testnet4/other custom magic values (any 4-byte magic
// can be read; only the four documented networks are classified).
//
// Value range: the platform Int is signed 64-bit. u64 fields that may
// exceed it (services bitfields, nonce) are stored as their raw 8
// little-endian bytes; helpers convert them when they fit. A CompactSize
// value above INT64_MAX is rejected rather than truncated.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; there are no self methods, no lambdas, no
//     indexed function dispatch and no Vec of struct types (collections use
//     parallel Vec fields).
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results inside larger functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before arithmetic or comparison; every
//     Vec[Int] element read is bound to a typed local first.
//   * `&struct.field` is never passed where a `&Vec[UInt8]` parameter is
//     expected: fields are bound to locals first.
//   * no shifts and no bit tests on values whose sign bit may be set:
//     little-endian reads use multiply/divide by 256, big-endian reads
//     multiply by 2^24..2^0, and signed values are rebuilt with explicit
//     sign arithmetic (see _read_i32_le/_read_i64_le/_push_i64_le, which
//     round-trip the full signed 64-bit range exactly).
//   * `&mut Int` out-parameters miscompile; every helper returns its value.

module xiom.bitcoin

use xiom.string;
use xiom.string.builder;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

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

// Ok(v) for Result[Vec[Int], Str].
fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_ints(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[MessageHeader, Str].
fn _ok_header(v: MessageHeader) -> Result[MessageHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[MessageHeader, Str].
fn _err_header(m: Str) -> Result[MessageHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[NetAddress, Str].
fn _ok_netaddr(v: NetAddress) -> Result[NetAddress, Str] {
  return Ok(v);
}

// Err(m) for Result[NetAddress, Str].
fn _err_netaddr(m: Str) -> Result[NetAddress, Str] {
  return Err(m);
}

// Ok(v) for Result[VersionMessage, Str].
fn _ok_version(v: VersionMessage) -> Result[VersionMessage, Str] {
  return Ok(v);
}

// Err(m) for Result[VersionMessage, Str].
fn _err_version(m: Str) -> Result[VersionMessage, Str] {
  return Err(m);
}

// Ok(v) for Result[AddressList, Str].
fn _ok_addrs(v: AddressList) -> Result[AddressList, Str] {
  return Ok(v);
}

// Err(m) for Result[AddressList, Str].
fn _err_addrs(m: Str) -> Result[AddressList, Str] {
  return Err(m);
}

// Ok(v) for Result[InvList, Str].
fn _ok_inv(v: InvList) -> Result[InvList, Str] {
  return Ok(v);
}

// Err(m) for Result[InvList, Str].
fn _err_inv(m: Str) -> Result[InvList, Str] {
  return Err(m);
}

// Ok(v) for Result[Tx, Str].
fn _ok_tx(v: Tx) -> Result[Tx, Str] {
  return Ok(v);
}

// Err(m) for Result[Tx, Str].
fn _err_tx(m: Str) -> Result[Tx, Str] {
  return Err(m);
}

// Ok(v) for Result[BlockHeader, Str].
fn _ok_bh(v: BlockHeader) -> Result[BlockHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[BlockHeader, Str].
fn _err_bh(m: Str) -> Result[BlockHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[Block, Str].
fn _ok_block(v: Block) -> Result[Block, Str] {
  return Ok(v);
}

// Err(m) for Result[Block, Str].
fn _err_block(m: Str) -> Result[Block, Str] {
  return Err(m);
}

// Ok(v) for Result[ScriptDoc, Str].
fn _ok_script(v: ScriptDoc) -> Result[ScriptDoc, Str] {
  return Ok(v);
}

// Err(m) for Result[ScriptDoc, Str].
fn _err_script(m: Str) -> Result[ScriptDoc, Str] {
  return Err(m);
}

// Ok(v) for Result[Bech32Data, Str].
fn _ok_bech32(v: Bech32Data) -> Result[Bech32Data, Str] {
  return Ok(v);
}

// Err(m) for Result[Bech32Data, Str].
fn _err_bech32(m: Str) -> Result[Bech32Data, Str] {
  return Err(m);
}

// Ok(v) for Result[SegwitAddress, Str].
fn _ok_segwit(v: SegwitAddress) -> Result[SegwitAddress, Str] {
  return Ok(v);
}

// Err(m) for Result[SegwitAddress, Str].
fn _err_segwit(m: Str) -> Result[SegwitAddress, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// Maximum accepted message payload, in bytes (32 MiB). Chosen as a
/// documented local cap, not a consensus rule. Frames that declare a larger
/// payload are rejected before any payload is read.
pub const BITCOIN_MAX_PAYLOAD: Int = 33554432;

/// Message header size on the wire: 4 magic + 12 command + 4 length + 4
/// checksum.
pub const BITCOIN_HEADER_SIZE: Int = 24;

/// Command field size on the wire, in bytes.
pub const BITCOIN_COMMAND_LEN: Int = 12;

/// Checksum field size on the wire, in bytes.
pub const BITCOIN_CHECKSUM_LEN: Int = 4;

/// Block header size on the wire, in bytes.
pub const BITCOIN_BLOCK_HEADER_SIZE: Int = 80;

/// Mainnet network magic bytes F9 BE B4 D9, read big-endian as an Int.
pub const BITCOIN_MAGIC_MAINNET: Int = 4190024921;

/// Testnet3 network magic bytes 0B 11 09 07.
pub const BITCOIN_MAGIC_TESTNET3: Int = 185665799;

/// Regtest network magic bytes FA BF B5 DA.
pub const BITCOIN_MAGIC_REGTEST: Int = 4206867930;

/// Default signet network magic bytes 0A 03 CF 40.
pub const BITCOIN_MAGIC_SIGNET: Int = 168021824;

/// Maximum accepted addr message entry count (Bitcoin Core MAX_ADDR_TO_SEND
/// is 1000).
pub const BITCOIN_MAX_ADDR_COUNT: Int = 1000;

/// Maximum accepted inv/getdata vector count (Bitcoin Core MAX_INV_SZ is
/// 50000).
pub const BITCOIN_MAX_INV_COUNT: Int = 50000;

/// Maximum accepted input count, output count or per-input witness item
/// count in one transaction (documented local cap, not consensus).
pub const BITCOIN_MAX_TX_IO: Int = 1000000;

/// Maximum accepted transaction count in one block (documented local cap,
/// not consensus).
pub const BITCOIN_MAX_BLOCK_TXS: Int = 1000000;

/// Maximum accepted Base58 input length, in characters. Longer strings are
/// rejected before the O(n^2) conversion runs.
pub const BITCOIN_MAX_BASE58_LEN: Int = 1024;

/// Inventory type: transaction (MSG_TX).
pub const INV_TYPE_TX: Int = 1;

/// Inventory type: block (MSG_BLOCK).
pub const INV_TYPE_BLOCK: Int = 2;

/// Inventory type: filtered block (MSG_FILTERED_BLOCK).
pub const INV_TYPE_FILTERED_BLOCK: Int = 3;

/// Inventory type: compact block (MSG_CMPCT_BLOCK).
pub const INV_TYPE_CMPCT_BLOCK: Int = 4;

/// Script opcode OP_0 (also OP_FALSE): pushes an empty byte vector.
pub const OP_0: Int = 0x00;

/// Script opcode OP_FALSE, the same byte value as OP_0.
pub const OP_FALSE: Int = 0x00;

/// Script opcode OP_PUSHDATA1: one length byte follows.
pub const OP_PUSHDATA1: Int = 0x4C;

/// Script opcode OP_PUSHDATA2: a 2-byte little-endian length follows.
pub const OP_PUSHDATA2: Int = 0x4D;

/// Script opcode OP_PUSHDATA4: a 4-byte little-endian length follows.
pub const OP_PUSHDATA4: Int = 0x4E;

/// Script opcode OP_1NEGATE: pushes the number -1.
pub const OP_1NEGATE: Int = 0x4F;

/// Script opcode OP_1: pushes the number 1.
pub const OP_1: Int = 0x51;

/// Script opcode OP_16: pushes the number 16.
pub const OP_16: Int = 0x60;

/// Script opcode OP_RETURN.
pub const OP_RETURN: Int = 0x6A;

/// Script opcode OP_DUP.
pub const OP_DUP: Int = 0x76;

/// Script opcode OP_EQUAL.
pub const OP_EQUAL: Int = 0x87;

/// Script opcode OP_EQUALVERIFY.
pub const OP_EQUALVERIFY: Int = 0x88;

/// Script opcode OP_HASH160.
pub const OP_HASH160: Int = 0xA9;

/// Script opcode OP_CHECKSIG.
pub const OP_CHECKSIG: Int = 0xAC;

/// Script opcode OP_CHECKMULTISIG.
pub const OP_CHECKMULTISIG: Int = 0xAE;

/// Script opcode OP_CHECKLOCKTIMEVERIFY (BIP-65).
pub const OP_CHECKLOCKTIMEVERIFY: Int = 0xB1;

/// Script opcode OP_CHECKSEQUENCEVERIFY (BIP-112).
pub const OP_CHECKSEQUENCEVERIFY: Int = 0xB2;

/// Bech32 checksum variant selector (BIP-173 constant 1).
pub const BECH32_VARIANT_BECH32: Int = 0;

/// Bech32m checksum variant selector (BIP-350 constant 0x2bc830a3).
pub const BECH32_VARIANT_BECH32M: Int = 1;

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Append the low 8 bits of `v` (v is expected in 0..255).
fn _push_u8(out: &mut Vec[UInt8], v: Int) {
  out.push((v % 256) as UInt8);
}

// Append v as 2 little-endian bytes (0 <= v <= 65535).
fn _push_u16_le(out: &mut Vec[UInt8], v: Int) {
  _push_u8(out, v % 256);
  _push_u8(out, (v / 256) % 256);
}

// Append v as 4 little-endian bytes (0 <= v <= 4294967295).
fn _push_u32_le(out: &mut Vec[UInt8], v: Int) {
  _push_u8(out, v % 256);
  _push_u8(out, (v / 256) % 256);
  _push_u8(out, (v / 65536) % 256);
  _push_u8(out, (v / 16777216) % 256);
}

// Append v as 4 big-endian bytes (0 <= v <= 4294967295); ports and the
// network magic use this order.
fn _push_u32_be(out: &mut Vec[UInt8], v: Int) {
  _push_u8(out, (v / 16777216) % 256);
  _push_u8(out, (v / 65536) % 256);
  _push_u8(out, (v / 256) % 256);
  _push_u8(out, v % 256);
}

// Append v as 8 little-endian bytes (0 <= v <= INT64_MAX).
fn _push_u64_le(out: &mut Vec[UInt8], v: Int) {
  var t = v;
  var i = 0;
  while i < 8 {
    _push_u8(out, t % 256);
    t = t / 256;
    i = i + 1;
  }
}

// Append v as 4 little-endian bytes, two's complement for negatives.
fn _push_i32_le(out: &mut Vec[UInt8], v: Int) {
  var w = v;
  if v < 0 {
    w = v + 4294967296;
  }
  _push_u32_le(out, w);
}

// Append v as 8 little-endian bytes, two's complement for the full signed
// 64-bit range (INT64_MIN..INT64_MAX). The negative case adds 2^63 by
// subtracting INT64_MIN, which cannot overflow, and sets bit 63 of the top
// byte arithmetically (no shifts).
fn _push_i64_le(out: &mut Vec[UInt8], v: Int) {
  var w = v;
  var neg = false;
  if v < 0 {
    neg = true;
    w = v - (0 - 9223372036854775807 - 1);
  }
  var i = 0;
  while i < 8 {
    var b = w % 256;
    if neg && i == 7 {
      b = b + 128;
    }
    _push_u8(out, b);
    w = w / 256;
    i = i + 1;
  }
}

// Append every byte of `v` to `out`.
fn _push_vec(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Copy bytes [from, to) of `v`.
fn _copy_slice(v: &Vec[UInt8], from: Int, to: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = from;
  while i < to {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Reader
// --------------------------------------------------

/// Bounds-checked cursor over a byte buffer. The buffer is owned by the
/// reader; offsets in every error message and accessor refer to it.
pub type Reader = {
  data: Vec[UInt8];
  pos: Int;
}

/// Create a reader at offset 0 over `data`.
pub fn reader_new(data: Vec[UInt8]) -> Reader {
  return Reader{ data: data; pos: 0; };
}

/// Current byte offset.
pub fn reader_pos(r: &Reader) -> Int {
  let p: Int = r.pos;
  return p;
}

/// Total buffer length in bytes.
pub fn reader_len(r: &Reader) -> Int {
  return r.data.len();
}

/// Unconsumed byte count.
pub fn reader_remaining(r: &Reader) -> Int {
  return r.data.len() - r.pos;
}

/// Read one byte and advance; Err("bitcoin: truncated at offset N").
pub fn reader_byte(r: &mut Reader) -> Result[Int, Str] {
  if r.pos >= r.data.len() {
    return _err_int("bitcoin: truncated at offset " + convert.int_to_string(r.pos));
  }
  let b: UInt8 = r.data[r.pos];
  r.pos = r.pos + 1;
  return _ok_int((b as Int) & 0xFF);
}

/// Read `n` bytes and advance. `n < 0` is Err("bitcoin: negative length at
/// offset N"); fewer than `n` remaining is Err("bitcoin: truncated at
/// offset N").
pub fn reader_take(r: &mut Reader, n: Int) -> Result[Vec[UInt8], Str] {
  if n < 0 {
    return _err_bytes("bitcoin: negative length at offset " + convert.int_to_string(r.pos));
  }
  let avail = r.data.len() - r.pos;
  if n > avail {
    return _err_bytes("bitcoin: truncated at offset " + convert.int_to_string(r.pos));
  }
  var out = Vec[UInt8].new();
  let stop = r.pos + n;
  var i = r.pos;
  while i < stop {
    out.push(r.data[i]);
    i = i + 1;
  }
  r.pos = stop;
  return _ok_bytes(out);
}

/// Skip `n` bytes and return the new offset; same errors as reader_take.
pub fn reader_skip(r: &mut Reader, n: Int) -> Result[Int, Str] {
  if n < 0 {
    return _err_int("bitcoin: negative length at offset " + convert.int_to_string(r.pos));
  }
  let avail = r.data.len() - r.pos;
  if n > avail {
    return _err_int("bitcoin: truncated at offset " + convert.int_to_string(r.pos));
  }
  r.pos = r.pos + n;
  return _ok_int(r.pos);
}

// --------------------------------------------------
//  Little-endian and big-endian reads
// --------------------------------------------------

// Read 2 little-endian bytes as 0..65535.
fn _read_u16_le(r: &mut Reader) -> Result[Int, Str] {
  if r.data.len() - r.pos < 2 {
    return _err_int("bitcoin: truncated at offset " + convert.int_to_string(r.pos));
  }
  let b0: UInt8 = r.data[r.pos];
  let b1: UInt8 = r.data[r.pos + 1];
  let x0 = (b0 as Int) & 0xFF;
  let x1 = (b1 as Int) & 0xFF;
  r.pos = r.pos + 2;
  return _ok_int(x0 + x1 * 256);
}

// Read 4 little-endian bytes as 0..4294967295.
fn _read_u32_le(r: &mut Reader) -> Result[Int, Str] {
  if r.data.len() - r.pos < 4 {
    return _err_int("bitcoin: truncated at offset " + convert.int_to_string(r.pos));
  }
  let b0: UInt8 = r.data[r.pos];
  let b1: UInt8 = r.data[r.pos + 1];
  let b2: UInt8 = r.data[r.pos + 2];
  let b3: UInt8 = r.data[r.pos + 3];
  let x0 = (b0 as Int) & 0xFF;
  let x1 = (b1 as Int) & 0xFF;
  let x2 = (b2 as Int) & 0xFF;
  let x3 = (b3 as Int) & 0xFF;
  r.pos = r.pos + 4;
  return _ok_int(x0 + x1 * 256 + x2 * 65536 + x3 * 16777216);
}

// Read 4 big-endian bytes as 0..4294967295 (network magic).
fn _read_u32_be(r: &mut Reader) -> Result[Int, Str] {
  if r.data.len() - r.pos < 4 {
    return _err_int("bitcoin: truncated at offset " + convert.int_to_string(r.pos));
  }
  let b0: UInt8 = r.data[r.pos];
  let b1: UInt8 = r.data[r.pos + 1];
  let b2: UInt8 = r.data[r.pos + 2];
  let b3: UInt8 = r.data[r.pos + 3];
  let x0 = (b0 as Int) & 0xFF;
  let x1 = (b1 as Int) & 0xFF;
  let x2 = (b2 as Int) & 0xFF;
  let x3 = (b3 as Int) & 0xFF;
  r.pos = r.pos + 4;
  return _ok_int(x0 * 16777216 + x1 * 65536 + x2 * 256 + x3);
}

// Read 2 big-endian bytes as 0..65535 (port).
fn _read_u16_be(r: &mut Reader) -> Result[Int, Str] {
  if r.data.len() - r.pos < 2 {
    return _err_int("bitcoin: truncated at offset " + convert.int_to_string(r.pos));
  }
  let b0: UInt8 = r.data[r.pos];
  let b1: UInt8 = r.data[r.pos + 1];
  let x0 = (b0 as Int) & 0xFF;
  let x1 = (b1 as Int) & 0xFF;
  r.pos = r.pos + 2;
  return _ok_int(x0 * 256 + x1);
}

// Read 4 little-endian bytes as a signed Int (version, start_height).
fn _read_i32_le(r: &mut Reader) -> Result[Int, Str] {
  let v = _read_u32_le(r);
  if !v.is_ok {
    return _err_int(v.error);
  }
  let n: Int = v.value;
  if n >= 2147483648 {
    return _ok_int(n - 4294967296);
  }
  return _ok_int(n);
}

// Read 8 little-endian bytes as raw bytes (u64 fields whose value may not
// fit the signed Int).
fn _read_u64_le_raw(r: &mut Reader) -> Result[Vec[UInt8], Str] {
  return reader_take(r, 8);
}

// Read 8 little-endian bytes as a signed 64-bit Int (full two's complement
// range, rebuilt with explicit sign arithmetic).
fn _read_i64_le(r: &mut Reader) -> Result[Int, Str] {
  let raw = _read_u64_le_raw(r);
  if !raw.is_ok {
    return _err_int(raw.error);
  }
  let v: Vec[UInt8] = raw.value;
  let b7: UInt8 = v[7];
  let hi = (b7 as Int) & 0xFF;
  var lo: Int = 0;
  var place = 1;
  var i = 0;
  while i < 7 {
    let b: UInt8 = v[i];
    lo = lo + ((b as Int) & 0xFF) * place;
    place = place * 256;
    i = i + 1;
  }
  let p64 = 72057594037927936;
  if hi >= 128 {
    return _ok_int(lo + (hi - 256) * p64);
  }
  return _ok_int(lo + hi * p64);
}

// Read 8 little-endian bytes as a non-negative Int; rejects values whose
// bit 63 is set (they do not fit the signed Int). `off` is the offset
// reported in the error (the varint's first byte).
fn _read_u64_int(r: &mut Reader, off: Int) -> Result[Int, Str] {
  let raw = _read_u64_le_raw(r);
  if !raw.is_ok {
    return _err_int(raw.error);
  }
  let v: Vec[UInt8] = raw.value;
  let b7: UInt8 = v[7];
  let hi = (b7 as Int) & 0xFF;
  if hi >= 128 {
    return _err_int("bitcoin: unsigned 64-bit value exceeds signed 64-bit range at offset " + convert.int_to_string(off));
  }
  var lo: Int = 0;
  var place = 1;
  var i = 0;
  while i < 7 {
    let b: UInt8 = v[i];
    lo = lo + ((b as Int) & 0xFF) * place;
    place = place * 256;
    i = i + 1;
  }
  return _ok_int(lo + hi * 72057594037927936);
}

// --------------------------------------------------
//  u64 helpers (services bitfields, nonces)
// --------------------------------------------------

/// True when 8 raw little-endian bytes hold a value that fits the signed
/// 64-bit Int (bit 63 clear). False for any other length.
pub fn bitcoin_u64_fits_int(raw: &Vec[UInt8]) -> Bool {
  if raw.len() != 8 {
    return false;
  }
  let b: UInt8 = raw[7];
  let hi = (b as Int) & 0xFF;
  return hi < 128;
}

/// Value of 8 raw little-endian bytes when it fits the signed 64-bit Int;
/// -1 when it does not fit (bit 63 set) or the length is not 8. Use
/// bitcoin_u64_fits_int to distinguish the marker from a real value first.
pub fn bitcoin_u64_to_int(raw: &Vec[UInt8]) -> Int {
  if !bitcoin_u64_fits_int(raw) {
    return -1;
  }
  var v: Int = 0;
  var place = 1;
  var i = 0;
  while i < 8 {
    let b: UInt8 = raw[i];
    v = v + ((b as Int) & 0xFF) * place;
    if i < 7 {
      place = place * 256;
    }
    i = i + 1;
  }
  return v;
}

/// Encode a non-negative Int as 8 little-endian bytes; an empty vector is
/// returned for a negative value (not representable as u64).
pub fn bitcoin_u64_le_bytes(v: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if v < 0 {
    return out;
  }
  _push_u64_le(&mut out, v);
  return out;
}

// --------------------------------------------------
//  CompactSize and legacy varints
// --------------------------------------------------

// Shared varint body. `canonical` enforces minimal-length encodings
// (CompactSize); false accepts non-minimal forms (legacy addr varint).
// 0xFC is direct, 0xFD carries u16, 0xFE carries u32, 0xFF carries u64,
// all little-endian.
fn _varint_body(r: &mut Reader, canonical: Bool) -> Result[Int, Str] {
  let start = r.pos;
  let first = reader_byte(r);
  if !first.is_ok {
    return _err_int(first.error);
  }
  let f: Int = first.value;
  if f < 253 {
    return _ok_int(f);
  }
  if f == 253 {
    let v = _read_u16_le(r);
    if !v.is_ok {
      return _err_int(v.error);
    }
    let n: Int = v.value;
    if canonical && n < 253 {
      return _err_int("bitcoin: non-canonical compact size at offset " + convert.int_to_string(start));
    }
    return _ok_int(n);
  }
  if f == 254 {
    let v = _read_u32_le(r);
    if !v.is_ok {
      return _err_int(v.error);
    }
    let n: Int = v.value;
    if canonical && n < 65536 {
      return _err_int("bitcoin: non-canonical compact size at offset " + convert.int_to_string(start));
    }
    return _ok_int(n);
  }
  let v = _read_u64_int(r, start);
  if !v.is_ok {
    return _err_int(v.error);
  }
  let n: Int = v.value;
  if canonical && n < 4294967296 {
    return _err_int("bitcoin: non-canonical compact size at offset " + convert.int_to_string(start));
  }
  return _ok_int(n);
}

/// Read one canonical CompactSize integer: 0x00..0xFC direct, 0xFD + u16
/// LE, 0xFE + u32 LE, 0xFF + u64 LE. Non-minimal encodings are rejected
/// with Err("bitcoin: non-canonical compact size at offset N"); values
/// above INT64_MAX are rejected with Err("bitcoin: unsigned 64-bit value
/// exceeds signed 64-bit range at offset N").
pub fn compact_size_read(r: &mut Reader) -> Result[Int, Str] {
  return _varint_body(r, true);
}

/// Read the legacy unsigned varint used by pre-0.6 addr messages: the same
/// 0xFD/0xFE/0xFF prefixes as CompactSize but non-minimal encodings are
/// accepted. Values above INT64_MAX are still rejected (platform Int
/// limit).
pub fn varint_legacy_read(r: &mut Reader) -> Result[Int, Str] {
  return _varint_body(r, false);
}

/// Append `n` as a canonical CompactSize integer. Negative values append
/// nothing (documented no-op).
pub fn compact_size_write(out: &mut Vec[UInt8], n: Int) {
  if n < 0 {
    return;
  }
  if n < 253 {
    _push_u8(out, n);
    return;
  }
  if n <= 65535 {
    _push_u8(out, 253);
    _push_u16_le(out, n);
    return;
  }
  if n <= 4294967295 {
    _push_u8(out, 254);
    _push_u32_le(out, n);
    return;
  }
  _push_u8(out, 255);
  _push_u64_le(out, n);
}

/// Encoded byte length of the canonical CompactSize for `n`; 0 for negative
/// values.
pub fn compact_size_encoded_len(n: Int) -> Int {
  if n < 0 {
    return 0;
  }
  if n < 253 {
    return 1;
  }
  if n <= 65535 {
    return 3;
  }
  if n <= 4294967295 {
    return 5;
  }
  return 9;
}

/// Append `n` as a legacy unsigned varint. The encoding produced is
/// identical to the canonical one; the decoder is what accepts non-minimal
/// forms.
pub fn varint_legacy_write(out: &mut Vec[UInt8], n: Int) {
  compact_size_write(out, n);
}

/// Read a varstr: CompactSize length followed by that many payload bytes.
pub fn varstr_read(r: &mut Reader) -> Result[Vec[UInt8], Str] {
  let len = compact_size_read(r);
  if !len.is_ok {
    return _err_bytes(len.error);
  }
  let n: Int = len.value;
  return reader_take(r, n);
}

/// Append bytes as a varstr (CompactSize length + payload).
pub fn varstr_write(out: &mut Vec[UInt8], data: &Vec[UInt8]) {
  compact_size_write(out, data.len());
  _push_vec(out, data);
}

// --------------------------------------------------
//  Message framing
// --------------------------------------------------

/// Name of the network for a 4-byte big-endian magic value; "unknown" for
/// any other value.
pub fn bitcoin_network_name(magic: Int) -> Str {
  if magic == BITCOIN_MAGIC_MAINNET {
    return "mainnet";
  }
  if magic == BITCOIN_MAGIC_TESTNET3 {
    return "testnet";
  }
  if magic == BITCOIN_MAGIC_REGTEST {
    return "regtest";
  }
  if magic == BITCOIN_MAGIC_SIGNET {
    return "signet";
  }
  return "unknown";
}

/// True when `magic` is one of the four documented network magics.
pub fn bitcoin_magic_known(magic: Int) -> Bool {
  if magic == BITCOIN_MAGIC_MAINNET {
    return true;
  }
  if magic == BITCOIN_MAGIC_TESTNET3 {
    return true;
  }
  if magic == BITCOIN_MAGIC_REGTEST {
    return true;
  }
  if magic == BITCOIN_MAGIC_SIGNET {
    return true;
  }
  return false;
}

/// Parsed 24-byte message header. The 4-byte checksum is preserved raw
/// (verification needs double SHA-256 and is caller-side).
pub type MessageHeader = {
  magic: Int;
  command: Str;
  command_raw: Vec[UInt8];
  payload_len: Int;
  checksum: Vec[UInt8];
  payload_start: Int;
}

/// Read a message header and require `expected_magic` (big-endian). The
/// command is 12 NUL-padded bytes: non-NUL bytes must be printable ASCII
/// (0x20..0x7E) and NULs must be trailing. The payload length must not
/// exceed BITCOIN_MAX_PAYLOAD. The payload itself is NOT consumed:
/// payload_start is the offset where it begins.
/// Errors (with byte offsets): truncated header; wrong network magic; bad
/// command character; bad command padding; payload length above the cap.
pub fn message_header_read(r: &mut Reader, expected_magic: Int) -> Result[MessageHeader, Str] {
  let start = r.pos;
  let m = _read_u32_be(r);
  if !m.is_ok {
    return _err_header(m.error);
  }
  let magic: Int = m.value;
  if magic != expected_magic {
    return _err_header("bitcoin: wrong network magic at offset " + convert.int_to_string(start));
  }
  let c = reader_take(r, 12);
  if !c.is_ok {
    return _err_header(c.error);
  }
  let cb: Vec[UInt8] = c.value;
  var nul_at = -1;
  var i = 0;
  while i < 12 {
    let b: UInt8 = cb[i];
    let x = (b as Int) & 0xFF;
    if nul_at < 0 {
      if x == 0 {
        nul_at = i;
      } elif x < 32 || x > 126 {
        return _err_header("bitcoin: bad command character at offset " + convert.int_to_string(start + 4 + i));
      }
    } else {
      if x != 0 {
        return _err_header("bitcoin: bad command padding at offset " + convert.int_to_string(start + 4 + i));
      }
    }
    i = i + 1;
  }
  if nul_at < 0 {
    nul_at = 12;
  }
  var sb = Vec[UInt8].new();
  i = 0;
  while i < nul_at {
    sb.push(cb[i]);
    i = i + 1;
  }
  let command = builder.sb_to_str(&sb);
  let pl = _read_u32_le(r);
  if !pl.is_ok {
    return _err_header(pl.error);
  }
  let payload_len: Int = pl.value;
  if payload_len > BITCOIN_MAX_PAYLOAD {
    return _err_header("bitcoin: payload length " + convert.int_to_string(payload_len) + " exceeds cap " + convert.int_to_string(BITCOIN_MAX_PAYLOAD) + " at offset " + convert.int_to_string(r.pos - 4));
  }
  let ck = reader_take(r, 4);
  if !ck.is_ok {
    return _err_header(ck.error);
  }
  let header = MessageHeader{
    magic: magic;
    command: command;
    command_raw: cb;
    payload_len: payload_len;
    checksum: ck.value;
    payload_start: r.pos;
  };
  return _ok_header(header);
}

/// Read the payload announced by `h` from the reader's current position
/// and advance. Truncation is Err("bitcoin: truncated at offset N").
pub fn message_payload_read(r: &mut Reader, h: &MessageHeader) -> Result[Vec[UInt8], Str] {
  let n: Int = h.payload_len;
  return reader_take(r, n);
}

/// Offset one past the header's payload (payload_start + payload_len); no
/// buffer access, so it is safe for any header.
pub fn message_payload_end(h: &MessageHeader) -> Int {
  let s: Int = h.payload_start;
  let n: Int = h.payload_len;
  return s + n;
}

/// Write a 24-byte message header. `magic` is a 4-byte big-endian value
/// (0..4294967295), `command` is at most 12 printable ASCII bytes and is
/// NUL-padded, `payload_len` is a u32, and `checksum` must be exactly 4
/// bytes. Returns the number of bytes written (24).
/// Errors: Err("bitcoin: magic out of range"); Err("bitcoin: command longer
/// than 12 bytes"); Err("bitcoin: bad command character"); Err("bitcoin:
/// payload length out of range"); Err("bitcoin: checksum must be 4 bytes").
pub fn message_header_write(out: &mut Vec[UInt8], magic: Int, command: Str, payload_len: Int, checksum: &Vec[UInt8]) -> Result[Int, Str] {
  if magic < 0 || magic > 4294967295 {
    return _err_int("bitcoin: magic out of range");
  }
  let cl = command.len();
  if cl > 12 {
    return _err_int("bitcoin: command longer than 12 bytes");
  }
  var cb = Vec[UInt8].new();
  var i = 0;
  while i < cl {
    let b: UInt8 = string.byte_at(command, i);
    let x = (b as Int) & 0xFF;
    if x < 32 || x > 126 {
      return _err_int("bitcoin: bad command character");
    }
    cb.push(b);
    i = i + 1;
  }
  if payload_len < 0 || payload_len > 4294967295 {
    return _err_int("bitcoin: payload length out of range");
  }
  if checksum.len() != 4 {
    return _err_int("bitcoin: checksum must be 4 bytes");
  }
  let before = out.len();
  _push_u32_be(out, magic);
  i = 0;
  while i < 12 {
    if i < cl {
      out.push(cb[i]);
    } else {
      _push_u8(out, 0);
    }
    i = i + 1;
  }
  _push_u32_le(out, payload_len);
  i = 0;
  while i < 4 {
    let b: UInt8 = checksum[i];
    out.push(b);
    i = i + 1;
  }
  return _ok_int(out.len() - before);
}

// --------------------------------------------------
//  Network addresses
// --------------------------------------------------

/// A net_addr: optional 4-byte timestamp (addr messages only, -1 when
/// absent), an 8-byte little-endian services bitfield kept raw, a 16-byte
/// IP address, and a big-endian u16 port.
pub type NetAddress = {
  time: Int;
  services: Vec[UInt8];
  ip: Vec[UInt8];
  port: Int;
}

/// Read a net_addr. `with_time` adds the u32 LE timestamp used by addr
/// message entries (the version message uses false).
pub fn net_address_read(r: &mut Reader, with_time: Bool) -> Result[NetAddress, Str] {
  var time = -1;
  if with_time {
    let t = _read_u32_le(r);
    if !t.is_ok {
      return _err_netaddr(t.error);
    }
    time = t.value;
  }
  let svc = reader_take(r, 8);
  if !svc.is_ok {
    return _err_netaddr(svc.error);
  }
  let ip = reader_take(r, 16);
  if !ip.is_ok {
    return _err_netaddr(ip.error);
  }
  let port = _read_u16_be(r);
  if !port.is_ok {
    return _err_netaddr(port.error);
  }
  let na = NetAddress{
    time: time;
    services: svc.value;
    ip: ip.value;
    port: port.value;
  };
  return _ok_netaddr(na);
}

/// The 4 IPv4 bytes when `ip` is an IPv4-mapped IPv6 address
/// (00..00 ff ff a.b.c.d); an empty vector otherwise.
pub fn net_address_ipv4(ip: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if ip.len() != 16 {
    return out;
  }
  var i = 0;
  while i < 10 {
    let b: UInt8 = ip[i];
    if ((b as Int) & 0xFF) != 0 {
      return out;
    }
    i = i + 1;
  }
  let b10: UInt8 = ip[10];
  let b11: UInt8 = ip[11];
  if ((b10 as Int) & 0xFF) != 255 {
    return out;
  }
  if ((b11 as Int) & 0xFF) != 255 {
    return out;
  }
  i = 12;
  while i < 16 {
    out.push(ip[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  version message
// --------------------------------------------------

/// A parsed `version` message. u64 services and nonce are kept as 8 raw
/// little-endian bytes (see bitcoin_u64_to_int). addr_recv/addr_from carry
/// time -1 (net_addr form). relay is -1 when the optional trailing byte is
/// absent, else 0 or 1.
pub type VersionMessage = {
  version: Int;
  services: Vec[UInt8];
  timestamp: Int;
  addr_recv: NetAddress;
  addr_from: NetAddress;
  nonce: Vec[UInt8];
  user_agent: Vec[UInt8];
  start_height: Int;
  relay: Int;
}

/// Read a `version` payload: i32 version, u64 services, i64 timestamp,
/// addr_recv, addr_from, u64 nonce, varstr user_agent, i32 start_height,
/// optional relay byte (normalized to 0/1).
pub fn version_message_read(r: &mut Reader) -> Result[VersionMessage, Str] {
  let v = _read_i32_le(r);
  if !v.is_ok {
    return _err_version(v.error);
  }
  let svc = reader_take(r, 8);
  if !svc.is_ok {
    return _err_version(svc.error);
  }
  let ts = _read_i64_le(r);
  if !ts.is_ok {
    return _err_version(ts.error);
  }
  let recv = net_address_read(r, false);
  if !recv.is_ok {
    return _err_version(recv.error);
  }
  let from = net_address_read(r, false);
  if !from.is_ok {
    return _err_version(from.error);
  }
  let non = reader_take(r, 8);
  if !non.is_ok {
    return _err_version(non.error);
  }
  let ua = varstr_read(r);
  if !ua.is_ok {
    return _err_version(ua.error);
  }
  let sh = _read_i32_le(r);
  if !sh.is_ok {
    return _err_version(sh.error);
  }
  var relay = -1;
  if r.data.len() - r.pos >= 1 {
    let rb = reader_byte(r);
    if !rb.is_ok {
      return _err_version(rb.error);
    }
    let b: Int = rb.value;
    if b == 0 {
      relay = 0;
    } else {
      relay = 1;
    }
  }
  let vm = VersionMessage{
    version: v.value;
    services: svc.value;
    timestamp: ts.value;
    addr_recv: recv.value;
    addr_from: from.value;
    nonce: non.value;
    user_agent: ua.value;
    start_height: sh.value;
    relay: relay;
  };
  return _ok_version(vm);
}

// --------------------------------------------------
//  addr message
// --------------------------------------------------

/// A parsed `addr` payload as parallel vectors (one entry per index): u32
/// timestamp, u64 services raw, 16-byte IP, u16 port.
pub type AddressList = {
  count: Int;
  times: Vec[Int];
  services: Vec[Vec[UInt8]];
  ips: Vec[Vec[UInt8]];
  ports: Vec[Int];
}

/// Read an `addr` payload: a LEGACY unsigned varint count (non-minimal
/// accepted; the modern CompactSize is not used here) followed by
/// time + net_addr entries. Counts above BITCOIN_MAX_ADDR_COUNT are
/// rejected.
pub fn addr_message_read(r: &mut Reader) -> Result[AddressList, Str] {
  let cnt = varint_legacy_read(r);
  if !cnt.is_ok {
    return _err_addrs(cnt.error);
  }
  let count: Int = cnt.value;
  if count > BITCOIN_MAX_ADDR_COUNT {
    return _err_addrs("bitcoin: count " + convert.int_to_string(count) + " exceeds cap " + convert.int_to_string(BITCOIN_MAX_ADDR_COUNT) + " at offset " + convert.int_to_string(r.pos));
  }
  var times = Vec[Int].new();
  var services = Vec[Vec[UInt8]].new();
  var ips = Vec[Vec[UInt8]].new();
  var ports = Vec[Int].new();
  var i = 0;
  while i < count {
    let na = net_address_read(r, true);
    if !na.is_ok {
      return _err_addrs(na.error);
    }
    let entry = na.value;
    let t: Int = entry.time;
    let svc: Vec[UInt8] = entry.services;
    let ip: Vec[UInt8] = entry.ip;
    let port: Int = entry.port;
    times.push(t);
    services.push(svc);
    ips.push(ip);
    ports.push(port);
    i = i + 1;
  }
  let out = AddressList{
    count: count;
    times: times;
    services: services;
    ips: ips;
    ports: ports;
  };
  return _ok_addrs(out);
}

// --------------------------------------------------
//  inv / getdata messages
// --------------------------------------------------

/// A parsed `inv` or `getdata` payload: CompactSize count plus parallel
/// type and 32-byte-hash vectors.
pub type InvList = {
  count: Int;
  types: Vec[Int];
  hashes: Vec[Vec[UInt8]];
}

/// Read an inv/getdata payload: CompactSize count, then for each vector a
/// u32 LE type and a 32-byte hash. Counts above BITCOIN_MAX_INV_COUNT are
/// rejected (the count of 0 is accepted and yields an empty list).
pub fn inv_message_read(r: &mut Reader) -> Result[InvList, Str] {
  let cnt = compact_size_read(r);
  if !cnt.is_ok {
    return _err_inv(cnt.error);
  }
  let count: Int = cnt.value;
  if count > BITCOIN_MAX_INV_COUNT {
    return _err_inv("bitcoin: count " + convert.int_to_string(count) + " exceeds cap " + convert.int_to_string(BITCOIN_MAX_INV_COUNT) + " at offset " + convert.int_to_string(r.pos));
  }
  var types = Vec[Int].new();
  var hashes = Vec[Vec[UInt8]].new();
  var i = 0;
  while i < count {
    let ty = _read_u32_le(r);
    if !ty.is_ok {
      return _err_inv(ty.error);
    }
    let hh = reader_take(r, 32);
    if !hh.is_ok {
      return _err_inv(hh.error);
    }
    types.push(ty.value);
    hashes.push(hh.value);
    i = i + 1;
  }
  let out = InvList{ count: count; types: types; hashes: hashes; };
  return _ok_inv(out);
}

/// Read a `getdata` payload (identical layout to inv).
pub fn getdata_message_read(r: &mut Reader) -> Result[InvList, Str] {
  return inv_message_read(r);
}

/// Lowercase name of an inventory type code; "unknown" otherwise.
pub fn inv_type_name(t: Int) -> Str {
  if t == INV_TYPE_TX {
    return "tx";
  }
  if t == INV_TYPE_BLOCK {
    return "block";
  }
  if t == INV_TYPE_FILTERED_BLOCK {
    return "filtered_block";
  }
  if t == INV_TYPE_CMPCT_BLOCK {
    return "cmpct_block";
  }
  return "unknown";
}

/// True when `t` is one of the four documented inventory type codes.
pub fn inv_type_known(t: Int) -> Bool {
  if t == INV_TYPE_TX {
    return true;
  }
  if t == INV_TYPE_BLOCK {
    return true;
  }
  if t == INV_TYPE_FILTERED_BLOCK {
    return true;
  }
  if t == INV_TYPE_CMPCT_BLOCK {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Transactions
// --------------------------------------------------

/// A parsed transaction. Legacy layout is version, inputs, outputs,
/// locktime; SegWit (BIP-144) adds the 0x00 marker and 0x01 flag after the
/// version and a witness stack per input before the locktime. Inputs,
/// outputs and witness items are parallel vectors (no Vec of structs):
/// witness_counts[i] is input i's item count and witness_flat_start[i] is
/// the index of its first item in witness_items. byte_len is the exact
/// number of wire bytes consumed.
pub type Tx = {
  version: Int;
  segwit: Bool;
  in_count: Int;
  in_prev_hash: Vec[Vec[UInt8]];
  in_prev_index: Vec[Int];
  in_script: Vec[Vec[UInt8]];
  in_sequence: Vec[Int];
  out_count: Int;
  out_value: Vec[Int];
  out_script: Vec[Vec[UInt8]];
  witness_counts: Vec[Int];
  witness_flat_start: Vec[Int];
  witness_items: Vec[Vec[UInt8]];
  locktime: Int;
  byte_len: Int;
}

/// Read one transaction (legacy or BIP-144 SegWit). Rejects: truncation;
/// a zero-input transaction without a witness flag; a witness flag other
/// than 0x01; a zero-input witness transaction; input, output or witness
/// item counts above BITCOIN_MAX_TX_IO. Elements are read sequentially
/// and the returned byte_len covers exactly the consumed bytes.
pub fn tx_read(r: &mut Reader) -> Result[Tx, Str] {
  let start = r.pos;
  let v = _read_i32_le(r);
  if !v.is_ok {
    return _err_tx(v.error);
  }
  let version: Int = v.value;
  var segwit = false;
  let c0 = compact_size_read(r);
  if !c0.is_ok {
    return _err_tx(c0.error);
  }
  var in_count: Int = c0.value;
  if in_count == 0 {
    let flag_off = r.pos;
    let fb = reader_byte(r);
    if !fb.is_ok {
      return _err_tx("bitcoin: truncated witness flag at offset " + convert.int_to_string(flag_off));
    }
    let flag: Int = fb.value;
    if flag == 0 {
      return _err_tx("bitcoin: zero-input transaction without witness flag at offset " + convert.int_to_string(flag_off));
    }
    if flag != 1 {
      return _err_tx("bitcoin: unsupported witness flag " + convert.int_to_string(flag) + " at offset " + convert.int_to_string(flag_off));
    }
    segwit = true;
    let c1 = compact_size_read(r);
    if !c1.is_ok {
      return _err_tx(c1.error);
    }
    in_count = c1.value;
    if in_count == 0 {
      return _err_tx("bitcoin: zero-input witness transaction at offset " + convert.int_to_string(start));
    }
  }
  if in_count > BITCOIN_MAX_TX_IO {
    return _err_tx("bitcoin: count " + convert.int_to_string(in_count) + " exceeds cap " + convert.int_to_string(BITCOIN_MAX_TX_IO) + " at offset " + convert.int_to_string(r.pos));
  }
  var in_prev_hash = Vec[Vec[UInt8]].new();
  var in_prev_index = Vec[Int].new();
  var in_script = Vec[Vec[UInt8]].new();
  var in_sequence = Vec[Int].new();
  var i = 0;
  while i < in_count {
    let ph = reader_take(r, 32);
    if !ph.is_ok {
      return _err_tx(ph.error);
    }
    let idx = _read_u32_le(r);
    if !idx.is_ok {
      return _err_tx(idx.error);
    }
    let sc = varstr_read(r);
    if !sc.is_ok {
      return _err_tx(sc.error);
    }
    let sq = _read_u32_le(r);
    if !sq.is_ok {
      return _err_tx(sq.error);
    }
    in_prev_hash.push(ph.value);
    in_prev_index.push(idx.value);
    in_script.push(sc.value);
    in_sequence.push(sq.value);
    i = i + 1;
  }
  let oc = compact_size_read(r);
  if !oc.is_ok {
    return _err_tx(oc.error);
  }
  let out_count: Int = oc.value;
  if out_count > BITCOIN_MAX_TX_IO {
    return _err_tx("bitcoin: count " + convert.int_to_string(out_count) + " exceeds cap " + convert.int_to_string(BITCOIN_MAX_TX_IO) + " at offset " + convert.int_to_string(r.pos));
  }
  var out_value = Vec[Int].new();
  var out_script = Vec[Vec[UInt8]].new();
  i = 0;
  while i < out_count {
    let val = _read_i64_le(r);
    if !val.is_ok {
      return _err_tx(val.error);
    }
    let osc = varstr_read(r);
    if !osc.is_ok {
      return _err_tx(osc.error);
    }
    out_value.push(val.value);
    out_script.push(osc.value);
    i = i + 1;
  }
  var witness_counts = Vec[Int].new();
  var witness_flat_start = Vec[Int].new();
  var witness_items = Vec[Vec[UInt8]].new();
  if segwit {
    i = 0;
    while i < in_count {
      let wc = compact_size_read(r);
      if !wc.is_ok {
        return _err_tx(wc.error);
      }
      let items: Int = wc.value;
      if items > BITCOIN_MAX_TX_IO {
        return _err_tx("bitcoin: count " + convert.int_to_string(items) + " exceeds cap " + convert.int_to_string(BITCOIN_MAX_TX_IO) + " at offset " + convert.int_to_string(r.pos));
      }
      witness_counts.push(items);
      witness_flat_start.push(witness_items.len());
      var j = 0;
      while j < items {
        let it = varstr_read(r);
        if !it.is_ok {
          return _err_tx(it.error);
        }
        witness_items.push(it.value);
        j = j + 1;
      }
      i = i + 1;
    }
  }
  let lt = _read_u32_le(r);
  if !lt.is_ok {
    return _err_tx(lt.error);
  }
  let tx = Tx{
    version: version;
    segwit: segwit;
    in_count: in_count;
    in_prev_hash: in_prev_hash;
    in_prev_index: in_prev_index;
    in_script: in_script;
    in_sequence: in_sequence;
    out_count: out_count;
    out_value: out_value;
    out_script: out_script;
    witness_counts: witness_counts;
    witness_flat_start: witness_flat_start;
    witness_items: witness_items;
    locktime: lt.value;
    byte_len: r.pos - start;
  };
  return _ok_tx(tx);
}

/// Append a transaction in the same wire layout tx_read accepts (marker
/// 0x00 + flag 0x01 are emitted when `segwit` is set). Returns the number
/// of bytes appended. Callers must pass values produced by tx_read or
/// built with non-negative u32 fields.
pub fn tx_write(out: &mut Vec[UInt8], t: &Tx) -> Int {
  let before = out.len();
  let version: Int = t.version;
  _push_i32_le(out, version);
  let segwit: Bool = t.segwit;
  if segwit {
    _push_u8(out, 0);
    _push_u8(out, 1);
  }
  let in_count: Int = t.in_count;
  compact_size_write(out, in_count);
  var i = 0;
  while i < in_count {
    let ph: Vec[UInt8] = t.in_prev_hash[i];
    _push_vec(out, &ph);
    let idx: Int = t.in_prev_index[i];
    _push_u32_le(out, idx);
    let sc: Vec[UInt8] = t.in_script[i];
    varstr_write(out, &sc);
    let sq: Int = t.in_sequence[i];
    _push_u32_le(out, sq);
    i = i + 1;
  }
  let out_count: Int = t.out_count;
  compact_size_write(out, out_count);
  i = 0;
  while i < out_count {
    let val: Int = t.out_value[i];
    _push_i64_le(out, val);
    let sc: Vec[UInt8] = t.out_script[i];
    varstr_write(out, &sc);
    i = i + 1;
  }
  if segwit {
    i = 0;
    while i < in_count {
      let wc: Int = t.witness_counts[i];
      compact_size_write(out, wc);
      let ws: Int = t.witness_flat_start[i];
      var j = 0;
      while j < wc {
        let it: Vec[UInt8] = t.witness_items[ws + j];
        varstr_write(out, &it);
        j = j + 1;
      }
      i = i + 1;
    }
  }
  let lt: Int = t.locktime;
  _push_u32_le(out, lt);
  return out.len() - before;
}

// --------------------------------------------------
//  Block header and block
// --------------------------------------------------

/// An 80-byte block header. The block hash needs double SHA-256 and is
/// caller-side.
pub type BlockHeader = {
  version: Int;
  prev_hash: Vec[UInt8];
  merkle_root: Vec[UInt8];
  time: Int;
  bits: Int;
  nonce: Int;
}

/// Read an 80-byte block header (i32 version, 32-byte prev hash, 32-byte
/// merkle root, u32 time, u32 bits, u32 nonce).
pub fn block_header_read(r: &mut Reader) -> Result[BlockHeader, Str] {
  let v = _read_i32_le(r);
  if !v.is_ok {
    return _err_bh(v.error);
  }
  let ph = reader_take(r, 32);
  if !ph.is_ok {
    return _err_bh(ph.error);
  }
  let mr = reader_take(r, 32);
  if !mr.is_ok {
    return _err_bh(mr.error);
  }
  let tm = _read_u32_le(r);
  if !tm.is_ok {
    return _err_bh(tm.error);
  }
  let bt = _read_u32_le(r);
  if !bt.is_ok {
    return _err_bh(bt.error);
  }
  let no = _read_u32_le(r);
  if !no.is_ok {
    return _err_bh(no.error);
  }
  let bh = BlockHeader{
    version: v.value;
    prev_hash: ph.value;
    merkle_root: mr.value;
    time: tm.value;
    bits: bt.value;
    nonce: no.value;
  };
  return _ok_bh(bh);
}

/// Append an 80-byte block header. Returns the number of bytes appended.
pub fn block_header_write(out: &mut Vec[UInt8], h: &BlockHeader) -> Int {
  let before = out.len();
  let version: Int = h.version;
  _push_i32_le(out, version);
  let ph: Vec[UInt8] = h.prev_hash;
  _push_vec(out, &ph);
  let mr: Vec[UInt8] = h.merkle_root;
  _push_vec(out, &mr);
  let tm: Int = h.time;
  _push_u32_le(out, tm);
  let bt: Int = h.bits;
  _push_u32_le(out, bt);
  let no: Int = h.nonce;
  _push_u32_le(out, no);
  return out.len() - before;
}

/// A parsed block: the header, the transaction count, and the consumed tx
/// stream span. tx_bytes_start/tx_bytes_end are offsets in the source
/// buffer; re-read individual transactions with a fresh Reader positioned
/// at tx_bytes_start and tx_read. byte_len covers header + count + stream.
pub type Block = {
  header: BlockHeader;
  tx_count: Int;
  tx_bytes_start: Int;
  tx_bytes_end: Int;
  byte_len: Int;
}

/// Read a block: header, CompactSize tx count (capped at
/// BITCOIN_MAX_BLOCK_TXS) and then the whole tx stream, consuming exactly
/// the transaction bytes (each tx is parsed, so the span is validated).
pub fn block_read(r: &mut Reader) -> Result[Block, Str] {
  let start = r.pos;
  let hd = block_header_read(r);
  if !hd.is_ok {
    return _err_block(hd.error);
  }
  let header: BlockHeader = hd.value;
  let cnt = compact_size_read(r);
  if !cnt.is_ok {
    return _err_block(cnt.error);
  }
  let tx_count: Int = cnt.value;
  if tx_count > BITCOIN_MAX_BLOCK_TXS {
    return _err_block("bitcoin: count " + convert.int_to_string(tx_count) + " exceeds cap " + convert.int_to_string(BITCOIN_MAX_BLOCK_TXS) + " at offset " + convert.int_to_string(r.pos));
  }
  let stream_start = r.pos;
  var i = 0;
  while i < tx_count {
    let t = tx_read(r);
    if !t.is_ok {
      return _err_block(t.error);
    }
    i = i + 1;
  }
  let blk = Block{
    header: header;
    tx_count: tx_count;
    tx_bytes_start: stream_start;
    tx_bytes_end: r.pos;
    byte_len: r.pos - start;
  };
  return _ok_block(blk);
}

// --------------------------------------------------
//  Script walking
// --------------------------------------------------

/// A parsed script as parallel per-instruction vectors plus a copy of the
/// source bytes. `opcode` is the raw byte; `push_len` is -1 for a non-push
/// instruction, 0 for OP_0, 1 for OP_1NEGATE/OP_1..OP_16, and otherwise
/// the number of data bytes the push places on the stack;
/// `data_start`/`data_end` delimit the explicit data bytes (-1 when there
/// are none).
pub type ScriptDoc = {
  script: Vec[UInt8];
  script_len: Int;
  op_count: Int;
  opcode: Vec[Int];
  push_len: Vec[Int];
  data_start: Vec[Int];
  data_end: Vec[Int];
}

/// Walk a script, parsing every push with bounds checks: direct pushes
/// (0x01..0x4B), OP_PUSHDATA1 (1 length byte), OP_PUSHDATA2 (2 LE bytes)
/// and OP_PUSHDATA4 (4 LE bytes). All other bytes are accepted as bare
/// opcodes; no script semantics are evaluated.
/// Errors: Err("bitcoin: truncated pushdata at offset N") when the length
/// field is incomplete; Err("bitcoin: script push exceeds script at offset
/// N") when the pushed data runs past the end.
pub fn script_parse(script: &Vec[UInt8]) -> Result[ScriptDoc, Str] {
  let n = script.len();
  let source = _copy_slice(script, 0, n);
  var opcode = Vec[Int].new();
  var push_len = Vec[Int].new();
  var data_start = Vec[Int].new();
  var data_end = Vec[Int].new();
  var pos = 0;
  while pos < n {
    let ob: UInt8 = script[pos];
    let op = (ob as Int) & 0xFF;
    let op_off = pos;
    pos = pos + 1;
    var plen = -1;
    var ds = -1;
    var de = -1;
    if op <= 0x4B {
      if pos + op > n {
        return _err_script("bitcoin: script push exceeds script at offset " + convert.int_to_string(op_off));
      }
      plen = op;
      ds = pos;
      de = pos + op;
      pos = pos + op;
    } elif op == OP_PUSHDATA1 {
      if pos + 1 > n {
        return _err_script("bitcoin: truncated pushdata at offset " + convert.int_to_string(op_off));
      }
      let lb: UInt8 = script[pos];
      let len = (lb as Int) & 0xFF;
      pos = pos + 1;
      if pos + len > n {
        return _err_script("bitcoin: script push exceeds script at offset " + convert.int_to_string(op_off));
      }
      plen = len;
      ds = pos;
      de = pos + len;
      pos = pos + len;
    } elif op == OP_PUSHDATA2 {
      if pos + 2 > n {
        return _err_script("bitcoin: truncated pushdata at offset " + convert.int_to_string(op_off));
      }
      let lb0: UInt8 = script[pos];
      let lb1: UInt8 = script[pos + 1];
      let len = ((lb0 as Int) & 0xFF) + ((lb1 as Int) & 0xFF) * 256;
      pos = pos + 2;
      if pos + len > n {
        return _err_script("bitcoin: script push exceeds script at offset " + convert.int_to_string(op_off));
      }
      plen = len;
      ds = pos;
      de = pos + len;
      pos = pos + len;
    } elif op == OP_PUSHDATA4 {
      if pos + 4 > n {
        return _err_script("bitcoin: truncated pushdata at offset " + convert.int_to_string(op_off));
      }
      let lb0: UInt8 = script[pos];
      let lb1: UInt8 = script[pos + 1];
      let lb2: UInt8 = script[pos + 2];
      let lb3: UInt8 = script[pos + 3];
      let len = ((lb0 as Int) & 0xFF) + ((lb1 as Int) & 0xFF) * 256 + ((lb2 as Int) & 0xFF) * 65536 + ((lb3 as Int) & 0xFF) * 16777216;
      pos = pos + 4;
      if len > n - pos {
        return _err_script("bitcoin: script push exceeds script at offset " + convert.int_to_string(op_off));
      }
      plen = len;
      ds = pos;
      de = pos + len;
      pos = pos + len;
    } elif op == OP_1NEGATE {
      plen = 1;
    } elif op >= OP_1 && op <= OP_16 {
      plen = 1;
    }
    opcode.push(op);
    push_len.push(plen);
    data_start.push(ds);
    data_end.push(de);
  }
  let doc = ScriptDoc{
    script: source;
    script_len: n;
    op_count: opcode.len();
    opcode: opcode;
    push_len: push_len;
    data_start: data_start;
    data_end: data_end;
  };
  return _ok_script(doc);
}

/// Raw opcode byte of instruction `i`; -1 when out of range.
pub fn script_opcode(doc: &ScriptDoc, i: Int) -> Int {
  if i < 0 || i >= doc.opcode.len() {
    return -1;
  }
  let v: Int = doc.opcode[i];
  return v;
}

/// Push length of instruction `i`: -1 not a push, 0 OP_0, 1 for
/// OP_1NEGATE/OP_1..OP_16, otherwise the pushed data byte count; -1 when
/// out of range.
pub fn script_push_len(doc: &ScriptDoc, i: Int) -> Int {
  if i < 0 || i >= doc.push_len.len() {
    return -1;
  }
  let v: Int = doc.push_len[i];
  return v;
}

/// Copy of the explicit data bytes of instruction `i` (empty for pushes
/// without explicit data and for out-of-range indices).
pub fn script_data(doc: &ScriptDoc, i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 || i >= doc.push_len.len() {
    return out;
  }
  let len: Int = doc.push_len[i];
  if len <= 0 {
    return out;
  }
  let from: Int = doc.data_start[i];
  let to: Int = doc.data_end[i];
  let src: Vec[UInt8] = doc.script;
  var k = from;
  while k < to {
    out.push(src[k]);
    k = k + 1;
  }
  return out;
}

/// True when every instruction is a push (OP_0, OP_1NEGATE, OP_1..OP_16 or
/// a data push), i.e. BIP-62 push-only scriptSig shape.
pub fn script_is_push_only(doc: &ScriptDoc) -> Bool {
  var i = 0;
  while i < doc.push_len.len() {
    let v: Int = doc.push_len[i];
    if v < 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// Lowercase name of an opcode byte from the documented table; direct
/// pushes (0x01..0x4B) report "OP_PUSHBYTES" (their length is in
/// push_len), anything else "OP_UNKNOWN".
pub fn script_op_name(op: Int) -> Str {
  if op == OP_0 {
    return "OP_0";
  }
  if op == OP_1NEGATE {
    return "OP_1NEGATE";
  }
  if op >= 1 && op <= 0x4B {
    return "OP_PUSHBYTES";
  }
  if op == OP_PUSHDATA1 {
    return "OP_PUSHDATA1";
  }
  if op == OP_PUSHDATA2 {
    return "OP_PUSHDATA2";
  }
  if op == OP_PUSHDATA4 {
    return "OP_PUSHDATA4";
  }
  if op >= OP_1 && op <= OP_16 {
    return "OP_" + convert.int_to_string(op - OP_1 + 1);
  }
  if op == OP_RETURN {
    return "OP_RETURN";
  }
  if op == OP_DUP {
    return "OP_DUP";
  }
  if op == OP_EQUAL {
    return "OP_EQUAL";
  }
  if op == OP_EQUALVERIFY {
    return "OP_EQUALVERIFY";
  }
  if op == OP_HASH160 {
    return "OP_HASH160";
  }
  if op == OP_CHECKSIG {
    return "OP_CHECKSIG";
  }
  if op == OP_CHECKMULTISIG {
    return "OP_CHECKMULTISIG";
  }
  if op == OP_CHECKLOCKTIMEVERIFY {
    return "OP_CHECKLOCKTIMEVERIFY";
  }
  if op == OP_CHECKSEQUENCEVERIFY {
    return "OP_CHECKSEQUENCEVERIFY";
  }
  return "OP_UNKNOWN";
}

// Template code of a script: 0 unknown, 1 p2pkh, 2 p2sh, 3 p2wpkh,
// 4 p2wsh, 5 p2tr, 6 op_return.
fn _script_class_code(script: &Vec[UInt8]) -> Int {
  let n = script.len();
  if n < 1 {
    return 0;
  }
  let b0: UInt8 = script[0];
  let x0 = (b0 as Int) & 0xFF;
  if x0 == OP_RETURN {
    return 6;
  }
  if n == 25 {
    let b1: UInt8 = script[1];
    let b2: UInt8 = script[2];
    let b23: UInt8 = script[23];
    let b24: UInt8 = script[24];
    if x0 == OP_DUP && ((b1 as Int) & 0xFF) == OP_HASH160 && ((b2 as Int) & 0xFF) == 20 && ((b23 as Int) & 0xFF) == OP_EQUALVERIFY && ((b24 as Int) & 0xFF) == OP_CHECKSIG {
      return 1;
    }
    return 0;
  }
  if n == 23 {
    let b1: UInt8 = script[1];
    let b22: UInt8 = script[22];
    if x0 == OP_HASH160 && ((b1 as Int) & 0xFF) == 20 && ((b22 as Int) & 0xFF) == OP_EQUAL {
      return 2;
    }
    return 0;
  }
  if n == 22 {
    let b1: UInt8 = script[1];
    if x0 == OP_0 && ((b1 as Int) & 0xFF) == 20 {
      return 3;
    }
    return 0;
  }
  if n == 34 {
    let b1: UInt8 = script[1];
    if x0 == OP_0 && ((b1 as Int) & 0xFF) == 32 {
      return 4;
    }
    if x0 == OP_1 && ((b1 as Int) & 0xFF) == 32 {
      return 5;
    }
    return 0;
  }
  return 0;
}

/// Classify a scriptPubKey template: "p2pkh", "p2sh", "p2wpkh", "p2wsh",
/// "p2tr", "op_return" or "unknown".
pub fn script_classify(script: &Vec[UInt8]) -> Str {
  let code = _script_class_code(script);
  if code == 1 {
    return "p2pkh";
  }
  if code == 2 {
    return "p2sh";
  }
  if code == 3 {
    return "p2wpkh";
  }
  if code == 4 {
    return "p2wsh";
  }
  if code == 5 {
    return "p2tr";
  }
  if code == 6 {
    return "op_return";
  }
  return "unknown";
}

/// Payload of a recognized template: the 20-byte hash of p2pkh/p2sh/
/// p2wpkh or the 32-byte hash of p2wsh/p2tr; empty otherwise (op_return
/// and unknown).
pub fn script_template_payload(script: &Vec[UInt8]) -> Vec[UInt8] {
  let code = _script_class_code(script);
  if code == 1 {
    return _copy_slice(script, 3, 23);
  }
  if code == 2 || code == 3 {
    return _copy_slice(script, 2, 22);
  }
  if code == 4 || code == 5 {
    return _copy_slice(script, 2, 34);
  }
  return Vec[UInt8].new();
}

// --------------------------------------------------
//  Base58
// --------------------------------------------------

/// The Bitcoin Base58 alphabet (58 characters, no "0", "O", "I" or "l").
pub fn base58_alphabet() -> Str {
  return "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
}

// Base58 digit value (0..57) of a byte; -1 outside the alphabet.
fn _base58_value(b: Int) -> Int {
  let alpha = base58_alphabet();
  var i = 0;
  while i < 58 {
    let a = (string.byte_at(alpha, i) as Int) & 0xFF;
    if a == b {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

/// Encode bytes as Base58 (Bitcoin alphabet). Each leading 0x00 byte
/// becomes one leading "1"; the remaining bytes are written as a minimal
/// base-58 number. Empty input yields "". Total; O(n^2) worst case.
pub fn base58_encode(data: &Vec[UInt8]) -> Str {
  let n = data.len();
  if n == 0 {
    return "";
  }
  var zeros = 0;
  while zeros < n {
    let b: UInt8 = data[zeros];
    if ((b as Int) & 0xFF) != 0 {
      break;
    }
    zeros = zeros + 1;
  }
  var work = Vec[Int].new();
  var i = 0;
  while i < n {
    let b: UInt8 = data[i];
    work.push((b as Int) & 0xFF);
    i = i + 1;
  }
  var digits = Vec[Int].new();
  var start = zeros;
  while start < n {
    var remainder = 0;
    var j = start;
    while j < n {
      let w: Int = work[j];
      let acc = remainder * 256 + w;
      work[j] = acc / 58;
      remainder = acc % 58;
      j = j + 1;
    }
    digits.push(remainder);
    while start < n {
      let w: Int = work[start];
      if w != 0 {
        break;
      }
      start = start + 1;
    }
  }
  var out = Vec[UInt8].new();
  var z = 0;
  while z < zeros {
    _push_u8(&mut out, 49);
    z = z + 1;
  }
  let alpha = base58_alphabet();
  var k = digits.len() - 1;
  while k >= 0 {
    let d: Int = digits[k];
    out.push(string.byte_at(alpha, d));
    k = k - 1;
  }
  return builder.sb_to_str(&out);
}

/// Decode Base58 text (Bitcoin alphabet). Each leading "1" becomes one
/// leading 0x00; the remaining characters form a big-endian byte value
/// with no leading zeros. Empty input yields an empty vector.
/// Errors: Err("bitcoin: base58 input too long") above
/// BITCOIN_MAX_BASE58_LEN characters; Err("bitcoin: base58 invalid
/// character at offset N") for any byte outside the alphabet.
pub fn base58_decode(s: Str) -> Result[Vec[UInt8], Str] {
  let n = s.len();
  if n > BITCOIN_MAX_BASE58_LEN {
    return _err_bytes("bitcoin: base58 input too long");
  }
  var zeros = 0;
  while zeros < n {
    let b = (string.byte_at(s, zeros) as Int) & 0xFF;
    if b != 49 {
      break;
    }
    zeros = zeros + 1;
  }
  var bytes = Vec[Int].new();
  var i = zeros;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    let v = _base58_value(b);
    if v < 0 {
      return _err_bytes("bitcoin: base58 invalid character at offset " + convert.int_to_string(i));
    }
    var carry = v;
    var k = 0;
    while k < bytes.len() {
      let cur: Int = bytes[k];
      let acc = cur * 58 + carry;
      bytes[k] = acc % 256;
      carry = acc / 256;
      k = k + 1;
    }
    while carry > 0 {
      bytes.push(carry % 256);
      carry = carry / 256;
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  var z = 0;
  while z < zeros {
    _push_u8(&mut out, 0);
    z = z + 1;
  }
  var bi = bytes.len() - 1;
  while bi >= 0 {
    let v: Int = bytes[bi];
    _push_u8(&mut out, v);
    bi = bi - 1;
  }
  return _ok_bytes(out);
}

/// True when every byte of `s` is in the Bitcoin Base58 alphabet; true
/// for empty input. No length cap is applied here.
pub fn base58_is_valid(s: Str) -> Bool {
  let n = s.len();
  var i = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if _base58_value(b) < 0 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

/// All bytes of a decoded Base58Check-shaped blob except its trailing
/// 4-byte checksum; empty when the blob is shorter than 4 bytes. The
/// returned bytes are the payload (for a P2PKH address: 1 version byte +
/// 20 hash bytes).
pub fn base58_payload(raw: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = raw.len();
  if n < 4 {
    return out;
  }
  var i = 0;
  while i < n - 4 {
    out.push(raw[i]);
    i = i + 1;
  }
  return out;
}

/// The trailing 4 checksum bytes of a decoded Base58Check-shaped blob;
/// empty when shorter than 4 bytes. Verification needs double SHA-256 and
/// is caller-side.
pub fn base58_checksum(raw: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let n = raw.len();
  if n < 4 {
    return out;
  }
  var i = n - 4;
  while i < n {
    out.push(raw[i]);
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Bech32 / Bech32m
// --------------------------------------------------

/// The Bech32 data alphabet, index = 5-bit value.
pub fn bech32_charset() -> Str {
  return "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
}

/// A decoded Bech32/Bech32m string. `hrp` is lowercase (all-uppercase
/// input is folded), `variant` is BECH32_VARIANT_BECH32 or
/// BECH32_VARIANT_BECH32M, and `values` is the 5-bit data part with the
/// 6 checksum symbols removed.
pub type Bech32Data = {
  hrp: Str;
  variant: Int;
  values: Vec[Int];
}

// 2^k for 0 <= k <= 30 (replaces every shift).
fn _pow2(k: Int) -> Int {
  var r = 1;
  var i = 0;
  while i < k {
    r = r * 2;
    i = i + 1;
  }
  return r;
}

// 5-bit value of an already case-folded data byte; -1 when not in the
// Bech32 alphabet.
fn _bech32_value(b: Int) -> Int {
  let cset = bech32_charset();
  var i = 0;
  while i < 32 {
    if (((string.byte_at(cset, i) as Int) & 0xFF) == b) {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// hrp-expand (BIP-173): high 3 bits of each byte, 0, low 5 bits.
fn _bech32_expand(hrp: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  let n = hrp.len();
  var i = 0;
  while i < n {
    out.push(((string.byte_at(hrp, i) as Int) & 0xFF) / 32);
    i = i + 1;
  }
  out.push(0);
  i = 0;
  while i < n {
    out.push(((string.byte_at(hrp, i) as Int) & 0xFF) % 32);
    i = i + 1;
  }
  return out;
}

// BIP-173 polymod without shifts: the top value is chk / 2^25, the check
// value becomes (chk % 2^25) * 32 + v, and GEN[i] is XORed when bit i of
// the extracted top value is set.
fn _bech32_polymod(values: &Vec[Int]) -> Int {
  var chk = 1;
  let n = values.len();
  var i = 0;
  while i < n {
    let v: Int = values[i];
    let top = chk / 33554432;
    chk = (chk % 33554432) * 32 + v;
    if top % 2 == 1 { chk = chk ^ 0x3b6a57b2; }
    if (top / 2) % 2 == 1 { chk = chk ^ 0x26508e6d; }
    if (top / 4) % 2 == 1 { chk = chk ^ 0x1ea119fa; }
    if (top / 8) % 2 == 1 { chk = chk ^ 0x3d4233dd; }
    if (top / 16) % 2 == 1 { chk = chk ^ 0x2a1462b3; }
    i = i + 1;
  }
  return chk;
}

// The 6 checksum symbols of (hrp, data) under `constant`.
fn _bech32_checksum(hrp: Str, data: &Vec[Int], constant: Int) -> Vec[Int] {
  var values = _bech32_expand(hrp);
  let n = data.len();
  var i = 0;
  while i < n {
    let v: Int = data[i];
    values.push(v);
    i = i + 1;
  }
  var z = 0;
  while z < 6 {
    values.push(0);
    z = z + 1;
  }
  let pm = _bech32_polymod(&values) ^ constant;
  var out = Vec[Int].new();
  var k = 0;
  while k < 6 {
    out.push((pm / _pow2(5 * (5 - k))) % 32);
    k = k + 1;
  }
  return out;
}

/// BIP-173 convertbits: regroup `data` from `frombits`-wide units into
/// `tobits`-wide units, most significant bit first. With pad=true a
/// partial trailing group is zero-padded and emitted; with pad=false it
/// must be fewer than `frombits` zero bits or the input is rejected.
/// Errors: invalid bits; convertbits overflow (value out of range);
/// invalid padding.
pub fn bech32_convertbits(data: &Vec[Int], frombits: Int, tobits: Int, pad: Bool) -> Result[Vec[Int], Str] {
  if frombits < 1 || frombits > 8 {
    return _err_ints("bitcoin: bech32 invalid bits");
  }
  if tobits < 1 || tobits > 8 {
    return _err_ints("bitcoin: bech32 invalid bits");
  }
  let fpow = _pow2(frombits);
  let tpow = _pow2(tobits);
  let accmask = _pow2(frombits + tobits - 1);
  var out = Vec[Int].new();
  var acc = 0;
  var bits = 0;
  var i = 0;
  while i < data.len() {
    let value: Int = data[i];
    if value < 0 || value >= fpow {
      return _err_ints("bitcoin: bech32 convertbits overflow");
    }
    acc = (acc * fpow + value) % accmask;
    bits = bits + frombits;
    while bits >= tobits {
      bits = bits - tobits;
      out.push((acc / _pow2(bits)) % tpow);
    }
    i = i + 1;
  }
  if pad {
    if bits > 0 {
      out.push((acc * _pow2(tobits - bits)) % tpow);
    }
  } else {
    if bits >= frombits {
      return _err_ints("bitcoin: bech32 invalid padding");
    }
    if (acc * _pow2(tobits - bits)) % tpow != 0 {
      return _err_ints("bitcoin: bech32 invalid padding");
    }
  }
  return _ok_ints(out);
}

/// Convert 8-bit bytes to 5-bit Bech32 symbols (convertbits 8->5,
/// pad=true; total).
pub fn bech32_bytes_to_symbols(data: &Vec[UInt8]) -> Vec[Int] {
  var ints = Vec[Int].new();
  var i = 0;
  while i < data.len() {
    let b: UInt8 = data[i];
    ints.push((b as Int) & 0xFF);
    i = i + 1;
  }
  let conv = bech32_convertbits(&ints, 8, 5, true);
  if !conv.is_ok {
    return Vec[Int].new();
  }
  let vals: Vec[Int] = conv.value;
  return vals;
}

/// Convert 5-bit symbols to bytes (convertbits 5->8, pad=false, strict).
pub fn bech32_symbols_to_bytes(data: &Vec[Int]) -> Result[Vec[UInt8], Str] {
  let conv = bech32_convertbits(data, 5, 8, false);
  if !conv.is_ok {
    return _err_bytes(conv.error);
  }
  let vals: Vec[Int] = conv.value;
  var out = Vec[UInt8].new();
  var i = 0;
  while i < vals.len() {
    let b: Int = vals[i];
    _push_u8(&mut out, b);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Encode `hrp` and 5-bit `data` symbols as Bech32 (variant 0) or
/// Bech32m (variant 1), lowercase. The result length is
/// hrp.len() + 1 + data.len() + 6 and must not exceed 90.
/// Errors: bad variant; invalid hrp length; invalid hrp character; mixed
/// case (uppercase HRP); invalid data value; bad length.
pub fn bech32_encode(hrp: Str, data: &Vec[Int], variant: Int) -> Result[Str, Str] {
  if variant != BECH32_VARIANT_BECH32 && variant != BECH32_VARIANT_BECH32M {
    return _err_str("bitcoin: bech32 bad variant");
  }
  let hl = hrp.len();
  if hl < 1 || hl > 83 {
    return _err_str("bitcoin: bech32 invalid hrp length");
  }
  var i = 0;
  while i < hl {
    let b = (string.byte_at(hrp, i) as Int) & 0xFF;
    if b < 33 || b > 126 {
      return _err_str("bitcoin: bech32 invalid hrp character");
    }
    if b >= 65 && b <= 90 {
      return _err_str("bitcoin: bech32 mixed case");
    }
    i = i + 1;
  }
  let n = data.len();
  i = 0;
  while i < n {
    let v: Int = data[i];
    if v < 0 || v > 31 {
      return _err_str("bitcoin: bech32 invalid data value");
    }
    i = i + 1;
  }
  if hl + n + 7 > 90 {
    return _err_str("bitcoin: bech32 bad length");
  }
  var constant = 1;
  if variant == BECH32_VARIANT_BECH32M {
    constant = 0x2bc830a3;
  }
  let cset = bech32_charset();
  var out = Vec[UInt8].new();
  i = 0;
  while i < hl {
    out.push(string.byte_at(hrp, i));
    i = i + 1;
  }
  _push_u8(&mut out, 49);
  let cs = _bech32_checksum(hrp, data, constant);
  i = 0;
  while i < n {
    let v: Int = data[i];
    out.push(string.byte_at(cset, v));
    i = i + 1;
  }
  i = 0;
  while i < 6 {
    let v: Int = cs[i];
    out.push(string.byte_at(cset, v));
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&out));
}

/// Decode Bech32 or Bech32m text, detecting the variant from the checksum
/// (no string is valid under both constants, so the variant is unique).
/// Validation order: total length 8..90, mixed case, last "1" separator
/// with non-empty HRP, data part of at least 6 characters, HRP bytes in
/// 33..126, data alphabet, checksum. All-uppercase input is folded to
/// lowercase.
/// Errors: bad length; mixed case; missing separator; invalid hrp
/// character; invalid data character; bad checksum.
pub fn bech32_decode(s: Str) -> Result[Bech32Data, Str] {
  let n = s.len();
  if n < 8 || n > 90 {
    return _err_bech32("bitcoin: bech32 bad length");
  }
  var has_lower = false;
  var has_upper = false;
  var i = 0;
  while i < n {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b >= 97 && b <= 122 { has_lower = true; }
    if b >= 65 && b <= 90 { has_upper = true; }
    i = i + 1;
  }
  if has_lower && has_upper {
    return _err_bech32("bitcoin: bech32 mixed case");
  }
  var pos = -1;
  i = n - 1;
  while i >= 0 {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b == 49 {
      pos = i;
      break;
    }
    i = i - 1;
  }
  if pos < 1 {
    return _err_bech32("bitcoin: bech32 missing separator");
  }
  if n - pos - 1 < 6 {
    return _err_bech32("bitcoin: bech32 bad length");
  }
  var hrp_bytes = Vec[UInt8].new();
  i = 0;
  while i < pos {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b < 33 || b > 126 {
      return _err_bech32("bitcoin: bech32 invalid hrp character");
    }
    if b >= 65 && b <= 90 {
      hrp_bytes.push((b + 32) as UInt8);
    } else {
      hrp_bytes.push(b as UInt8);
    }
    i = i + 1;
  }
  let hrp = builder.sb_to_str(&hrp_bytes);
  var values = Vec[Int].new();
  i = pos + 1;
  while i < n {
    var b = (string.byte_at(s, i) as Int) & 0xFF;
    if b >= 65 && b <= 90 {
      b = b + 32;
    }
    let v = _bech32_value(b);
    if v < 0 {
      return _err_bech32("bitcoin: bech32 invalid data character");
    }
    values.push(v);
    i = i + 1;
  }
  var all = _bech32_expand(hrp);
  i = 0;
  while i < values.len() {
    let v: Int = values[i];
    all.push(v);
    i = i + 1;
  }
  let pm = _bech32_polymod(&all);
  var variant = -1;
  if pm == 1 {
    variant = BECH32_VARIANT_BECH32;
  } elif pm == 0x2bc830a3 {
    variant = BECH32_VARIANT_BECH32M;
  }
  if variant < 0 {
    return _err_bech32("bitcoin: bech32 bad checksum");
  }
  var payload = Vec[Int].new();
  let plen = values.len() - 6;
  i = 0;
  while i < plen {
    let v: Int = values[i];
    payload.push(v);
    i = i + 1;
  }
  let out = Bech32Data{ hrp: hrp; variant: variant; values: payload; };
  return _ok_bech32(out);
}

/// Lowercase HRP of a decoded string.
pub fn bech32_hrp(v: &Bech32Data) -> Str {
  let h: Str = v.hrp;
  return h;
}

/// Variant of a decoded string (BECH32_VARIANT_BECH32 or
/// BECH32_VARIANT_BECH32M).
pub fn bech32_variant(v: &Bech32Data) -> Int {
  let x: Int = v.variant;
  return x;
}

/// 5-bit data symbols of a decoded string, checksum removed.
pub fn bech32_values(v: &Bech32Data) -> Vec[Int] {
  let d: Vec[Int] = v.values;
  return d;
}

// --------------------------------------------------
//  SegWit addresses (BIP-173 / BIP-350)
// --------------------------------------------------

/// A decoded SegWit address: HRP, witness version 0..16, witness program
/// bytes, and the checksum variant that was used (Bech32 for v0, Bech32m
/// for v1+).
pub type SegwitAddress = {
  hrp: Str;
  witver: Int;
  program: Vec[UInt8];
  variant: Int;
}

/// Decode a SegWit address from Bech32/Bech32m text.
/// Rules (BIP-173/BIP-350): witness version 0..16; program 2..40 bytes;
/// version 0 requires the Bech32 constant and a 20- or 32-byte program;
/// version 1+ requires Bech32m. The 5->8 conversion is strict (no
/// non-zero padding).
/// Errors: every bech32_decode error; missing witness version; version
/// out of range; wrong variant for the version; program length out of
/// range or wrong for v0; invalid padding.
pub fn segwit_decode(s: Str) -> Result[SegwitAddress, Str] {
  let d = bech32_decode(s);
  if !d.is_ok {
    return _err_segwit(d.error);
  }
  let b: Bech32Data = d.value;
  let vals: Vec[Int] = b.values;
  if vals.len() == 0 {
    return _err_segwit("bitcoin: bech32 missing witness version");
  }
  let witver: Int = vals[0];
  if witver < 0 || witver > 16 {
    return _err_segwit("bitcoin: bech32 witness version out of range");
  }
  var data5 = Vec[Int].new();
  var i = 1;
  while i < vals.len() {
    let v: Int = vals[i];
    data5.push(v);
    i = i + 1;
  }
  let conv = bech32_convertbits(&data5, 5, 8, false);
  if !conv.is_ok {
    return _err_segwit(conv.error);
  }
  let prog_ints: Vec[Int] = conv.value;
  var program = Vec[UInt8].new();
  i = 0;
  while i < prog_ints.len() {
    let x: Int = prog_ints[i];
    _push_u8(&mut program, x);
    i = i + 1;
  }
  let plen = program.len();
  if plen < 2 || plen > 40 {
    return _err_segwit("bitcoin: bech32 witness program length out of range");
  }
  let variant: Int = b.variant;
  if witver == 0 {
    if variant != BECH32_VARIANT_BECH32 {
      return _err_segwit("bitcoin: bech32 wrong variant for witness v0");
    }
    if plen != 20 && plen != 32 {
      return _err_segwit("bitcoin: bech32 bad witness v0 program length");
    }
  } else {
    if variant != BECH32_VARIANT_BECH32M {
      return _err_segwit("bitcoin: bech32 wrong variant for witness v1+");
    }
  }
  let h: Str = b.hrp;
  let out = SegwitAddress{ hrp: h; witver: witver; program: program; variant: variant; };
  return _ok_segwit(out);
}

/// Encode a SegWit address: witness version 0..16 and a 2..40 byte
/// program; version 0 must be 20 or 32 bytes and uses Bech32, version 1+
/// uses Bech32m.
/// Errors: version out of range; program length out of range or wrong for
/// v0; plus every bech32_encode error.
pub fn segwit_encode(hrp: Str, witver: Int, program: &Vec[UInt8]) -> Result[Str, Str] {
  if witver < 0 || witver > 16 {
    return _err_str("bitcoin: bech32 witness version out of range");
  }
  let plen = program.len();
  if plen < 2 || plen > 40 {
    return _err_str("bitcoin: bech32 witness program length out of range");
  }
  var variant = BECH32_VARIANT_BECH32M;
  if witver == 0 {
    variant = BECH32_VARIANT_BECH32;
    if plen != 20 && plen != 32 {
      return _err_str("bitcoin: bech32 bad witness v0 program length");
    }
  }
  var data = Vec[Int].new();
  data.push(witver);
  let sym = bech32_bytes_to_symbols(program);
  var i = 0;
  while i < sym.len() {
    let v: Int = sym[i];
    data.push(v);
    i = i + 1;
  }
  return bech32_encode(hrp, &data, variant);
}

/// HRP of a decoded SegWit address.
pub fn segwit_hrp(v: &SegwitAddress) -> Str {
  let h: Str = v.hrp;
  return h;
}

/// Witness version 0..16 of a decoded SegWit address.
pub fn segwit_witver(v: &SegwitAddress) -> Int {
  let x: Int = v.witver;
  return x;
}

/// Witness program bytes of a decoded SegWit address.
pub fn segwit_program(v: &SegwitAddress) -> Vec[UInt8] {
  let p: Vec[UInt8] = v.program;
  return p;
}
