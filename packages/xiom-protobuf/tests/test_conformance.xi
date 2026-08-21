// XIOM -- Protocol Buffers Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
// 47 tests, 16 sections -- pure-XIOM varint/zigzag/wire format.

module protobuf_conformance

use xiom.io;

// =========================================================================
// Helpers
// =========================================================================

fn itoa(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n; var out = "";
  while num > 0 {
    let d = num % 10; var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out; num = num / 10;
  }
  return out;
}

// =========================================================================
// Varint -- encode to buffer, returns bytes written
// =========================================================================

fn varint_write(buf: &mut Vec[UInt8], value: Int) -> Int {
  var count: Int = 0; var v = value;
  while v >= 128 { buf.push(((v & 0x7F) | 0x80) as UInt8); v = v >> 7; count = count + 1; };
  buf.push(v as UInt8); return count + 1;
}

// =========================================================================
// Varint -- encode to new Vec
// =========================================================================

fn varint_enc(value: Int) -> Vec[UInt8] {
  var result = Vec[UInt8].new(); varint_write(&mut result, value); return result;
}

// =========================================================================
// Varint -- decode: returns (value, consumed, ok) as separate globals
// =========================================================================
var g_val: Int = 0
var g_len: Int = 0
var g_ok: Bool = false

fn varint_dec(buf: &Vec[UInt8], pos: Int) {
  g_ok = false; g_val = 0; g_len = 0;
  if pos >= buf.len() { return; };
  var result: Int = 0; var shift: Int = 0; var i = pos; var done: Bool = false;
  while i < buf.len() && !done {
    var raw = buf[i]; var b: Int = raw;
    result = result | ((b & 0x7F) << shift);
    if (b & 0x80) == 0 { g_val = result; g_len = i - pos + 1; g_ok = true; return; };
    shift = shift + 7; if shift >= 64 { return; }; i = i + 1;
  };
}

// =========================================================================
// Zigzag
// =========================================================================

fn zz_enc(s: Int) -> Int { if s >= 0 { return s * 2; }; return (-s) * 2 - 1; }
fn zz_dec(e: Int) -> Int { if (e & 1) == 0 { return e >> 1; }; return -((e >> 1) + 1); }

// =========================================================================
// Wire type constants
// =========================================================================

const WT_VARINT: Int = 0
const WT_FIXED64: Int = 1
const WT_LD: Int = 2
const WT_FIXED32: Int = 5

fn make_tag(fn_: Int, wt: Int) -> Int { return (fn_ << 3) | wt; }
fn parse_tag(tag: Int) -> (Int, Int) { return (tag >> 3, tag & 0x07); }

// =========================================================================
// Field writers
// =========================================================================

fn fw_varint(buf: &mut Vec[UInt8], fn_: Int, value: Int) {
  varint_write(buf, make_tag(fn_, WT_VARINT)); varint_write(buf, value);
}
fn fw_fixed64(buf: &mut Vec[UInt8], fn_: Int, value: Int) {
  varint_write(buf, make_tag(fn_, WT_FIXED64)); var v = value; var j: Int = 0;
  while j < 8 { buf.push((v & 0xFF) as UInt8); v = v >> 8; j = j + 1; };
}
fn fw_fixed32(buf: &mut Vec[UInt8], fn_: Int, value: Int) {
  varint_write(buf, make_tag(fn_, WT_FIXED32)); var v = value; var j: Int = 0;
  while j < 4 { buf.push((v & 0xFF) as UInt8); v = v >> 8; j = j + 1; };
}
fn fw_ld(buf: &mut Vec[UInt8], fn_: Int, data: &Vec[UInt8]) {
  varint_write(buf, make_tag(fn_, WT_LD)); varint_write(buf, data.len());
  var j: Int = 0; while j < data.len() { buf.push(data[j]); j = j + 1; };
}
fn fw_bool(buf: &mut Vec[UInt8], fn_: Int, v: Bool) {
  var iv: Int = 0; if v { iv = 1; }; fw_varint(buf, fn_, iv);
}
fn fw_sint(buf: &mut Vec[UInt8], fn_: Int, s: Int) { fw_varint(buf, fn_, zz_enc(s)); }

// =========================================================================
// Vec helpers
// =========================================================================

fn vec_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() { return false; }; var i: Int = 0;
  while i < a.len() { if a[i] != b[i] { return false; }; i = i + 1; }; return true;
}
fn v1(a: Int) -> Vec[UInt8] { var v = Vec[UInt8].new(); v.push(a as UInt8); return v; }
fn v2(a: Int, b: Int) -> Vec[UInt8] { var v = Vec[UInt8].new(); v.push(a as UInt8); v.push(b as UInt8); return v; }
fn v3(a: Int, b: Int, c: Int) -> Vec[UInt8] { var v = Vec[UInt8].new(); v.push(a as UInt8); v.push(b as UInt8); v.push(c as UInt8); return v; }

// =========================================================================
// Runner
// =========================================================================

var t_pass: Int = 0
var t_fail: Int = 0

fn chk(cond: Bool, name: Str) {
  if cond { t_pass = t_pass + 1; io.println("  [PASS] " + name); }
  else { t_fail = t_fail + 1; io.println("  [FAIL] " + name); };
}

fn main() -> Int {
  var buf: Vec[UInt8];
  var ok: Bool; var fn_: Int; var wt: Int; var d: Vec[UInt8];

  // S1: varint encode (6)
  buf = varint_enc(0); chk(vec_eq(&buf, &v1(0)), "varint: enc(0)=[0x00]");
  buf = varint_enc(1); chk(vec_eq(&buf, &v1(1)), "varint: enc(1)=[0x01]");
  buf = varint_enc(127); chk(vec_eq(&buf, &v1(127)), "varint: enc(127)=[0x7F]");
  buf = varint_enc(128); chk(vec_eq(&buf, &v2(0x80, 1)), "varint: enc(128)=[0x80,0x01]");
  buf = varint_enc(300); chk(vec_eq(&buf, &v2(0xAC, 2)), "varint: enc(300)=[0xAC,0x02]");
  buf = varint_enc(1000000); chk(buf.len() > 0 && buf.len() <= 5, "varint: enc(1M) valid");

  // S2: varint decode (5)
  buf = v1(0); varint_dec(&buf, 0); chk(g_ok && g_val == 0 && g_len == 1, "varint: dec([0x00])=(0,1)");
  buf = v1(1); varint_dec(&buf, 0); chk(g_ok && g_val == 1 && g_len == 1, "varint: dec([0x01])=(1,1)");
  buf = v1(127); varint_dec(&buf, 0); chk(g_ok && g_val == 127 && g_len == 1, "varint: dec([0x7F])=(127,1)");
  buf = v2(0x80, 1); varint_dec(&buf, 0); chk(g_ok && g_val == 128 && g_len == 2, "varint: dec(128)=(128,2)");
  buf = v2(0xAC, 2); varint_dec(&buf, 0); chk(g_ok && g_val == 300 && g_len == 2, "varint: dec(300)=(300,2)");

  // S3: varint roundtrip (4)
  buf = varint_enc(0); varint_dec(&buf, 0); chk(g_ok && g_val == 0, "varint: rt(0)");
  buf = varint_enc(42); varint_dec(&buf, 0); chk(g_ok && g_val == 42, "varint: rt(42)");
  buf = varint_enc(65535); varint_dec(&buf, 0); chk(g_ok && g_val == 65535, "varint: rt(65535)");
  buf = varint_enc(999999); varint_dec(&buf, 0); chk(g_ok && g_val == 999999, "varint: rt(999999)");

  // S4: varint errors (2)
  buf = Vec[UInt8].new(); varint_dec(&buf, 0); chk(!g_ok, "varint: empty buf => false");
  buf = Vec[UInt8].new(); buf.push(0x80 as UInt8); varint_dec(&buf, 0); chk(!g_ok, "varint: truncated => false");

  // S5: zigzag encode (5)
  chk(zz_enc(0) == 0, "zz: enc(0)=0");
  chk(zz_enc(-1) == 1, "zz: enc(-1)=1");
  chk(zz_enc(1) == 2, "zz: enc(1)=2");
  chk(zz_enc(-2) == 3, "zz: enc(-2)=3");
  chk(zz_enc(5) + 1 == zz_enc(-5), "zz: enc(5)+1==enc(-5)");

  // S6: zigzag decode (4)
  chk(zz_dec(0) == 0, "zz: dec(0)=0");
  chk(zz_dec(1) == -1, "zz: dec(1)=-1");
  chk(zz_dec(2) == 1, "zz: dec(2)=1");
  chk(zz_dec(3) == -2, "zz: dec(3)=-2");

  // S7: wire type constants (4)
  chk(WT_VARINT == 0, "wt: Varint=0");
  chk(WT_FIXED64 == 1, "wt: Fixed64=1");
  chk(WT_FIXED32 == 5, "wt: Fixed32=5");
  chk(WT_LD == 2, "wt: L-D=2");

  // S8: wire tag (4)
  chk(make_tag(1, WT_VARINT) == 8, "tag: (1,V)=8");
  chk(make_tag(2, WT_LD) == 18, "tag: (2,L)=18");
  chk(make_tag(5, WT_FIXED32) == 0x2D, "tag: (5,F)=0x2D");
  let(tfn, twt) = parse_tag(make_tag(1, WT_VARINT)); chk(tfn == 1 && twt == 0, "tag: parse rt");

  // S9: write_field_varint (3)
  buf = Vec[UInt8].new(); fw_varint(&mut buf, 1, 42); chk(buf.len() == 2, "fwv: 2B");
  buf = Vec[UInt8].new(); fw_varint(&mut buf, 1, 42); chk(buf.len() >= 1 && buf[0] == 8, "fwv: tag=8");
  buf = Vec[UInt8].new(); fw_varint(&mut buf, 1, 42); chk(buf.len() >= 2 && buf[1] == 42, "fwv: val=42");

  // S10: write_field_ld (2)
  d = v3(65, 66, 67); buf = Vec[UInt8].new(); fw_ld(&mut buf, 2, &d); chk(buf.len() > 0, "fwl: output");
  buf = Vec[UInt8].new(); fw_ld(&mut buf, 2, &d); chk(buf.len() >= 2 && buf[0] == 0x12 as UInt8 && buf[1] == 3, "fwl: tag=0x12,len=3");

  // S11: write_field_fixed (2)
  buf = Vec[UInt8].new(); fw_fixed32(&mut buf, 5, 0x01020304); chk(buf.len() == 5, "fwf32: 5B");
  buf = Vec[UInt8].new(); fw_fixed64(&mut buf, 3, 42); chk(buf.len() == 9, "fwf64: 9B");

  // S12: bool (2)
  buf = Vec[UInt8].new(); fw_bool(&mut buf, 1, true); chk(buf.len() >= 2 && buf[1] == 1, "fbool: T=>1");
  buf = Vec[UInt8].new(); fw_bool(&mut buf, 1, false); chk(buf.len() >= 2 && buf[1] == 0, "fbool: F=>0");

  // S13: multi (1)
  buf = Vec[UInt8].new(); fw_varint(&mut buf, 1, 10); fw_varint(&mut buf, 2, 20); fw_varint(&mut buf, 3, 30);
  chk(buf.len() >= 6, "multi: 3 varints");

  // S14: sint (2)
  buf = Vec[UInt8].new(); fw_sint(&mut buf, 1, -42); chk(buf.len() > 0, "fsint(-42)");
  buf = Vec[UInt8].new(); fw_sint(&mut buf, 1, 0); chk(buf.len() >= 2, "fsint(0)");

  // S15: zigzag roundtrip edges (2)
  chk(zz_dec(zz_enc(-1000)) == -1000 && zz_dec(zz_enc(1000)) == 1000, "zz: rt edges");
  chk(zz_dec(zz_enc(-1)) == -1 && zz_dec(zz_enc(42)) == 42, "zz: rt -1, 42");

  // S16: write+read varint roundtrip (1)
  buf = Vec[UInt8].new(); fw_varint(&mut buf, 1, 999);
  varint_dec(&buf, 0);
  let(pfn, pwt) = parse_tag(g_val); ok = g_ok && pfn == 1 && pwt == 0;
  if ok { varint_dec(&buf, g_len); ok = g_ok && g_val == 999; };
  chk(ok, "varrt: field1=999 rt");

  // Summary
  let total = t_pass + t_fail;
  io.println("  " + itoa(t_pass) + "/" + itoa(total) + " passed");
  if t_fail > 0 { io.println("  " + itoa(t_fail) + " FAILED"); };
  return t_fail;
}
