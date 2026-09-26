// XIOM -- xiom.hid conformance tests (16 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Port task: prove the pure-XIOM xiom.hid report-descriptor codec against a
// hand-built canonical mouse fixture, a push/pop fixture, a long-item
// fixture, an every-documented-tag fixture, and the documented error
// catalog.
//
// Covers: item count/type/tag/size/data accessors, unsigned + per-width
// signed + nibble-signed interpretations, data-byte and whole-item byte
// copies, collection depth, collection kind, Push/Pop balance per item,
// Usage Page tracking through Push/Pop, usage IDs, the collection depth cap
// boundary, byte-exact round-trips (mouse, push/pop, long item, all-tags),
// the emitter's drift guard, and every documented error (truncated item,
// truncated long item, reserved size/type/tag, pop without push, end
// collection without collection, depth cap, unterminated collection,
// unbalanced push, out-of-range accessors).
//
// Error texts are compared with compare.str_compare (BUG 17 discipline:
// `==` on a Str read from a Vec lowers to a pointer comparison); every
// Vec[Int] element read is bound to a typed local.

module hid_tests
use xiom.io; use xiom.test;
use xiom.hid;
use xiom.string.compare;
use xiom.encoding.hex;

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// Expected bytes for a hex string ("" on malformed input; the test then
// fails on the byte comparison).
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: UInt8 = a[i];
    let y: UInt8 = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

// Parse `data` and require the error text `want`.
fn err_is(data: &Vec[UInt8], want: Str) -> Bool {
  let r = hid_parse(data);
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

// Parse `data`; true when accepted.
fn parses(data: &Vec[UInt8]) -> Bool {
  let r = hid_parse(data);
  return r.is_ok;
}

// Parse and emit `data` back; true when the rebuilt bytes equal the input.
fn roundtrip(data: &Vec[UInt8]) -> Bool {
  let r = hid_parse(data);
  if !r.is_ok {
    return false;
  }
  let d: HidDescriptor = r.value;
  let e = hid_emit(&d);
  if !e.is_ok {
    return false;
  }
  let out: Vec[UInt8] = e.value;
  return bytes_equal(&out, data);
}

// Concatenate hid_item_bytes over every item; a valid store must reassemble
// the source stream exactly.
fn concat_item_bytes(d: &HidDescriptor) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < hid_item_count(d) {
    let r = hid_item_bytes(d, i);
    if r.is_ok {
      let b: Vec[UInt8] = r.value;
      var k = 0;
      while k < b.len() {
        out.push(b[k]);
        k = k + 1;
      }
    }
    i = i + 1;
  }
  return out;
}

// --------------------------------------------------
//  Fixtures
// --------------------------------------------------

// Canonical 50-byte mouse report descriptor: Usage Page (Generic Desktop),
// Usage (Mouse), two nested Collections, a 3-button field and a 2-axis
// field. 26 items.
fn mouse_hex() -> Str {
  return "05010902a1010901a100050919012903150025019503750181029501750581030501093009311581257f750895028106c0c0";
}

// Push/Pop fixture: the Button usage page is pushed over and popped back,
// so the Usage after the Pop must resolve to the restored Generic Desktop
// page. 7 items, 11 bytes.
fn pushpop_hex() -> Str {
  return "05010930a405090901b40931";
}

// Long-item fixture: Usage, a 4-byte long item (tag 0x55, payload
// deadbeef) and Input. 3 items, 11 bytes.
fn long_hex() -> Str {
  return "0901fe0455deadbeef8102";
}

// Every documented short tag once (24 global/local/main items plus Push,
// Pop and Collection/End Collection): 27 items, 51 bytes. No reserved tag
// appears, so the fixture must parse.
fn alltags_hex() -> Str {
  return "05011500257f3500457f5500650f750885019501a4b4090119012902390149015901790189019901a901a10081029102b102c0";
}

// Signed-interpretation fixture: 15 81 (Logical Min -127 as 1 byte),
// 25 7f (Logical Max 127), 16 ffff (Logical Min -1 as 2 bytes),
// 26 0080 (Logical Max -32768 as 2 bytes), 65 0f / 65 07 / 65 f8
// (Unit Exponent nibble-signed -1 / 7 / -8). 7 items, 16 bytes.
fn interp_hex() -> Str {
  return "1581257f16ffff260080650f650765f8";
}

// `open` Collection items (data 0) followed by `close` End Collection
// items, used for the nesting-depth boundary.
fn nested_collections(open: Int, close: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < open {
    v.push(161 as UInt8);
    v.push(0 as UInt8);
    i = i + 1;
  }
  i = 0;
  while i < close {
    v.push(192 as UInt8);
    i = i + 1;
  }
  return v;
}

// --------------------------------------------------
//  Tests
// --------------------------------------------------

fn t1() -> TestResult {
  let data = hb(mouse_hex());
  let r = hid_parse(&data);
  if !r.is_ok { return assert(false, "mouse fixture must parse"); }
  let d: HidDescriptor = r.value;
  var ok = hid_item_count(&d) == 26;
  if hid_item_type(&d, 0) != HID_TYPE_GLOBAL { ok = false; }
  if hid_item_tag(&d, 0) != HID_GLOBAL_USAGE_PAGE { ok = false; }
  if hid_item_size(&d, 0) != 1 { ok = false; }
  if hid_item_data(&d, 0) != 1 { ok = false; }
  if hid_item_type(&d, 2) != HID_TYPE_MAIN { ok = false; }
  if hid_item_tag(&d, 2) != HID_MAIN_COLLECTION { ok = false; }
  if hid_item_data(&d, 2) != 1 { ok = false; }
  if hid_item_type(&d, 3) != HID_TYPE_LOCAL { ok = false; }
  if hid_item_tag(&d, 3) != HID_LOCAL_USAGE { ok = false; }
  if hid_item_tag(&d, 12) != HID_MAIN_INPUT { ok = false; }
  if hid_item_size(&d, 24) != 0 { ok = false; }
  if hid_item_tag(&d, 25) != HID_MAIN_END_COLLECTION { ok = false; }
  let rebuilt = concat_item_bytes(&d);
  if !bytes_equal(&rebuilt, &data) { ok = false; }
  if !roundtrip(&data) { ok = false; }
  return assert(ok, "canonical mouse fixture: 26 items, pinned headers, byte-exact round-trip");
}

fn t2() -> TestResult {
  let data = hb(mouse_hex());
  let r = hid_parse(&data);
  if !r.is_ok { return assert(false, "mouse fixture must parse"); }
  let d: HidDescriptor = r.value;
  var ok = hid_item_depth(&d, 0) == 0;
  if hid_item_depth(&d, 1) != 0 { ok = false; }
  if hid_item_depth(&d, 2) != 0 { ok = false; }
  if hid_item_depth(&d, 3) != 1 { ok = false; }
  if hid_item_depth(&d, 4) != 1 { ok = false; }
  if hid_item_depth(&d, 5) != 2 { ok = false; }
  if hid_item_depth(&d, 23) != 2 { ok = false; }
  if hid_item_depth(&d, 24) != 1 { ok = false; }
  if hid_item_depth(&d, 25) != 0 { ok = false; }
  if hid_item_depth(&d, 26) != -1 { ok = false; }
  return assert(ok, "collection depth is pinned across the mouse fixture");
}

fn t3() -> TestResult {
  let data = hb(mouse_hex());
  let r = hid_parse(&data);
  if !r.is_ok { return assert(false, "mouse fixture must parse"); }
  let d: HidDescriptor = r.value;
  var ok = hid_item_usage_page(&d, 0) == 1;
  if hid_item_usage_page(&d, 4) != 1 { ok = false; }
  if hid_item_usage_page(&d, 5) != 9 { ok = false; }
  if hid_item_usage_page(&d, 15) != 9 { ok = false; }
  if hid_item_usage_page(&d, 16) != 1 { ok = false; }
  if hid_item_usage_page(&d, 25) != 1 { ok = false; }
  if hid_item_usage_page(&d, 26) != 0 { ok = false; }
  return assert(ok, "usage page tracks the global Usage Page items");
}

fn t4() -> TestResult {
  let data = hb(mouse_hex());
  let r = hid_parse(&data);
  if !r.is_ok { return assert(false, "mouse fixture must parse"); }
  let d: HidDescriptor = r.value;
  var ok = hid_item_collection_kind(&d, 2) == 1;
  if hid_item_collection_kind(&d, 4) != 0 { ok = false; }
  if hid_item_collection_kind(&d, 3) != -1 { ok = false; }
  if hid_item_collection_kind(&d, 0) != -1 { ok = false; }
  if hid_item_collection_kind(&d, 26) != -1 { ok = false; }
  if hid_item_usage(&d, 1) != 2 { ok = false; }
  if hid_item_usage(&d, 6) != 1 { ok = false; }
  if hid_item_usage(&d, 7) != 3 { ok = false; }
  if hid_item_usage(&d, 17) != 48 { ok = false; }
  if hid_item_usage(&d, 18) != 49 { ok = false; }
  if hid_item_usage(&d, 0) != -1 { ok = false; }
  if hid_item_usage(&d, 12) != -1 { ok = false; }
  return assert(ok, "collection kinds and usage IDs are pinned");
}

fn t5() -> TestResult {
  let data = hb(interp_hex());
  let r = hid_parse(&data);
  if !r.is_ok { return assert(false, "interpretation fixture must parse"); }
  let d: HidDescriptor = r.value;
  var ok = hid_item_data(&d, 0) == 129;
  if hid_item_data_signed(&d, 0) != -127 { ok = false; }
  if hid_item_data(&d, 1) != 127 { ok = false; }
  if hid_item_data_signed(&d, 1) != 127 { ok = false; }
  if hid_item_data(&d, 2) != 65535 { ok = false; }
  if hid_item_data_signed(&d, 2) != -1 { ok = false; }
  if hid_item_data(&d, 3) != 32768 { ok = false; }
  if hid_item_data_signed(&d, 3) != -32768 { ok = false; }
  if hid_item_size(&d, 2) != 2 { ok = false; }
  if hid_item_data(&d, 4) != 15 { ok = false; }
  if hid_item_data_nibble_signed(&d, 4) != -1 { ok = false; }
  if hid_item_data_nibble_signed(&d, 5) != 7 { ok = false; }
  if hid_item_data(&d, 6) != 248 { ok = false; }
  if hid_item_data_nibble_signed(&d, 6) != -8 { ok = false; }
  let m = hb(mouse_hex());
  let mr = hid_parse(&m);
  if !mr.is_ok { return assert(false, "mouse fixture must parse"); }
  let md: HidDescriptor = mr.value;
  if hid_item_data_signed(&md, 24) != 0 { ok = false; }
  if hid_item_data_nibble_signed(&md, 24) != 0 { ok = false; }
  if hid_item_data_signed(&md, 99) != 0 { ok = false; }
  if hid_item_data_nibble_signed(&md, 99) != 0 { ok = false; }
  return assert(ok, "unsigned, per-width signed and nibble-signed interpretations");
}

fn t6() -> TestResult {
  let data = hb(pushpop_hex());
  let r = hid_parse(&data);
  if !r.is_ok { return assert(false, "push/pop fixture must parse"); }
  let d: HidDescriptor = r.value;
  var ok = hid_item_count(&d) == 7;
  if hid_item_stack(&d, 0) != 0 { ok = false; }
  if hid_item_stack(&d, 1) != 0 { ok = false; }
  if hid_item_stack(&d, 2) != 1 { ok = false; }
  if hid_item_stack(&d, 3) != 1 { ok = false; }
  if hid_item_stack(&d, 4) != 1 { ok = false; }
  if hid_item_stack(&d, 5) != 0 { ok = false; }
  if hid_item_stack(&d, 6) != 0 { ok = false; }
  if hid_item_usage_page(&d, 0) != 1 { ok = false; }
  if hid_item_usage_page(&d, 2) != 1 { ok = false; }
  if hid_item_usage_page(&d, 3) != 9 { ok = false; }
  if hid_item_usage_page(&d, 4) != 9 { ok = false; }
  if hid_item_usage_page(&d, 5) != 1 { ok = false; }
  if hid_item_usage_page(&d, 6) != 1 { ok = false; }
  if hid_item_usage(&d, 1) != 48 { ok = false; }
  if hid_item_usage(&d, 4) != 1 { ok = false; }
  if hid_item_usage(&d, 6) != 49 { ok = false; }
  if !roundtrip(&data) { ok = false; }
  return assert(ok, "push/pop balance and usage page save/restore are pinned");
}

fn t7() -> TestResult {
  let pop_only = hb("b4");
  var ok = err_is(&pop_only, "hid: pop without push");
  let push_only = hb("a4");
  if !err_is(&push_only, "hid: unbalanced push") { ok = false; }
  let pair = hb("a4b4");
  if !parses(&pair) { ok = false; }
  if !roundtrip(&pair) { ok = false; }
  let r = hid_parse(&pair);
  if !r.is_ok { return assert(false, "push/pop pair must parse"); }
  let d: HidDescriptor = r.value;
  if hid_item_count(&d) != 2 { ok = false; }
  if hid_item_stack(&d, 0) != 1 { ok = false; }
  if hid_item_stack(&d, 1) != 0 { ok = false; }
  return assert(ok, "pop without push and an unbalanced push are rejected");
}

fn t8() -> TestResult {
  let stray = hb("c0");
  var ok = err_is(&stray, "hid: end collection without collection");
  let open = hb("a100");
  if !err_is(&open, "hid: unterminated collection") { ok = false; }
  let pair = hb("a100c0");
  if !parses(&pair) { ok = false; }
  if !roundtrip(&pair) { ok = false; }
  let r = hid_parse(&pair);
  if !r.is_ok { return assert(false, "collection pair must parse"); }
  let d: HidDescriptor = r.value;
  if hid_item_count(&d) != 2 { ok = false; }
  if hid_item_depth(&d, 0) != 0 { ok = false; }
  if hid_item_depth(&d, 1) != 0 { ok = false; }
  if hid_item_collection_kind(&d, 0) != 0 { ok = false; }
  return assert(ok, "collection balance: stray End Collection and unterminated Collection");
}

fn t9() -> TestResult {
  let at_cap = nested_collections(32, 32);
  var ok = parses(&at_cap);
  if !roundtrip(&at_cap) { ok = false; }
  if hid_max_collection_depth() != 32 { ok = false; }
  let over_cap = nested_collections(33, 33);
  if !err_is(&over_cap, "hid: collection nesting exceeds limit of 32") { ok = false; }
  let unclosed = nested_collections(32, 0);
  if !err_is(&unclosed, "hid: unterminated collection") { ok = false; }
  let r = hid_parse(&at_cap);
  if !r.is_ok { return assert(false, "32-deep fixture must parse"); }
  let d: HidDescriptor = r.value;
  if hid_item_count(&d) != 64 { ok = false; }
  if hid_item_depth(&d, 31) != 31 { ok = false; }
  if hid_item_depth(&d, 32) != 31 { ok = false; }
  if hid_item_depth(&d, 63) != 0 { ok = false; }
  return assert(ok, "collection depth cap: 32 accepted, 33 rejected");
}

fn t10() -> TestResult {
  let data = hb(long_hex());
  let r = hid_parse(&data);
  if !r.is_ok { return assert(false, "long-item fixture must parse"); }
  let d: HidDescriptor = r.value;
  var ok = hid_item_count(&d) == 3;
  if hid_item_type(&d, 1) != HID_TYPE_LONG { ok = false; }
  if hid_item_tag(&d, 1) != 85 { ok = false; }
  if hid_item_size(&d, 1) != 4 { ok = false; }
  if hid_item_data(&d, 1) != 0 { ok = false; }
  if hid_item_data_signed(&d, 1) != 0 { ok = false; }
  if hid_item_depth(&d, 1) != 0 { ok = false; }
  if hid_item_usage_page(&d, 1) != 0 { ok = false; }
  let payload = hb("deadbeef");
  let db = hid_item_data_bytes(&d, 1);
  if !db.is_ok { ok = false; } else {
    let v: Vec[UInt8] = db.value;
    if !bytes_equal(&v, &payload) { ok = false; }
  }
  let whole = hb("fe0455deadbeef");
  let ib = hid_item_bytes(&d, 1);
  if !ib.is_ok { ok = false; } else {
    let v2: Vec[UInt8] = ib.value;
    if !bytes_equal(&v2, &whole) { ok = false; }
  }
  if !roundtrip(&data) { ok = false; }
  let empty_long = hb("fe00ff");
  if !parses(&empty_long) { ok = false; }
  if !roundtrip(&empty_long) { ok = false; }
  let er = hid_parse(&empty_long);
  if !er.is_ok { return assert(false, "empty long item must parse"); }
  let ed: HidDescriptor = er.value;
  if hid_item_size(&ed, 0) != 0 { ok = false; }
  if hid_item_tag(&ed, 0) != 255 { ok = false; }
  let empty_payload = Vec[UInt8].new();
  let edb = hid_item_data_bytes(&ed, 0);
  if !edb.is_ok { ok = false; } else {
    let v3: Vec[UInt8] = edb.value;
    if !bytes_equal(&v3, &empty_payload) { ok = false; }
  }
  return assert(ok, "long items: tag/size/payload preserved verbatim, byte-exact round-trip");
}

fn t11() -> TestResult {
  let bare = hb("fe");
  var ok = err_is(&bare, "hid: truncated long item");
  let no_tag = hb("fe00");
  if !err_is(&no_tag, "hid: truncated long item") { ok = false; }
  let short_payload = hb("fe0455dead");
  if !err_is(&short_payload, "hid: truncated long item") { ok = false; }
  let one_short = hb("fe0201aa");
  if !err_is(&one_short, "hid: truncated long item") { ok = false; }
  return assert(ok, "long items with a missing header byte or a short payload are rejected");
}

fn t12() -> TestResult {
  let truncated1 = hb("05");
  var ok = err_is(&truncated1, "hid: truncated item");
  let truncated2 = hb("95");
  if !err_is(&truncated2, "hid: truncated item") { ok = false; }
  let truncated3 = hb("1a");
  if !err_is(&truncated3, "hid: truncated item") { ok = false; }
  let size_reserved = hb("03");
  if !err_is(&size_reserved, "hid: reserved item size") { ok = false; }
  let size_reserved2 = hb("83");
  if !err_is(&size_reserved2, "hid: reserved item size") { ok = false; }
  let size_first = hb("ff");
  if !err_is(&size_first, "hid: reserved item size") { ok = false; }
  let type_reserved = hb("0e");
  if !err_is(&type_reserved, "hid: reserved item type") { ok = false; }
  let tag_reserved1 = hb("00");
  if !err_is(&tag_reserved1, "hid: reserved item tag") { ok = false; }
  let tag_reserved2 = hb("68");
  if !err_is(&tag_reserved2, "hid: reserved item tag") { ok = false; }
  let tag_reserved3 = hb("c4");
  if !err_is(&tag_reserved3, "hid: reserved item tag") { ok = false; }
  let valid = hb("0501");
  if !parses(&valid) { ok = false; }
  return assert(ok, "short-item truncation and the reserved size/type/tag checks");
}

fn t13() -> TestResult {
  let data = hb(mouse_hex());
  let r = hid_parse(&data);
  if !r.is_ok { return assert(false, "mouse fixture must parse"); }
  let d: HidDescriptor = r.value;
  var ok = hid_item_type(&d, -1) == -1;
  if hid_item_type(&d, 26) != -1 { ok = false; }
  if hid_item_tag(&d, 99) != -1 { ok = false; }
  if hid_item_size(&d, 99) != -1 { ok = false; }
  if hid_item_data(&d, 99) != 0 { ok = false; }
  if hid_item_depth(&d, 99) != -1 { ok = false; }
  if hid_item_stack(&d, 99) != -1 { ok = false; }
  if hid_item_collection_kind(&d, 99) != -1 { ok = false; }
  if hid_item_usage(&d, -1) != -1 { ok = false; }
  if hid_item_usage_page(&d, 99) != 0 { ok = false; }
  if !err_bytes_is(hid_item_data_bytes(&d, 99), "hid: item index out of range") { ok = false; }
  if !err_bytes_is(hid_item_bytes(&d, -1), "hid: item index out of range") { ok = false; }
  let empty = Vec[UInt8].new();
  let er = hid_parse(&empty);
  if !er.is_ok { return assert(false, "empty stream must parse"); }
  let ed: HidDescriptor = er.value;
  if hid_item_count(&ed) != 0 { ok = false; }
  if hid_item_type(&ed, 0) != -1 { ok = false; }
  let ee = hid_emit(&ed);
  if !ee.is_ok { ok = false; } else {
    let out: Vec[UInt8] = ee.value;
    if out.len() != 0 { ok = false; }
  }
  return assert(ok, "out-of-range accessors and the empty descriptor");
}

fn t14() -> TestResult {
  let data = hb(mouse_hex());
  let r = hid_parse(&data);
  if !r.is_ok { return assert(false, "mouse fixture must parse"); }
  var ok = roundtrip(&data);
  var d1: HidDescriptor = r.value;
  let e1 = hid_emit(&d1);
  if !e1.is_ok { ok = false; }
  d1.item_tag.pop();
  if !err_bytes_is(hid_emit(&d1), "hid: invalid store") { ok = false; }
  let r2 = hid_parse(&data);
  if !r2.is_ok { return assert(false, "second parse must succeed"); }
  var d2: HidDescriptor = r2.value;
  d2.item_depth.push(0);
  if !err_bytes_is(hid_emit(&d2), "hid: invalid store") { ok = false; }
  let r3 = hid_parse(&data);
  if !r3.is_ok { return assert(false, "third parse must succeed"); }
  var d3: HidDescriptor = r3.value;
  var extra = Vec[UInt8].new();
  d3.item_raw.push(extra);
  if !err_bytes_is(hid_emit(&d3), "hid: invalid store") { ok = false; }
  let r4 = hid_parse(&data);
  if !r4.is_ok { return assert(false, "fourth parse must succeed"); }
  var d4: HidDescriptor = r4.value;
  d4.item_type[0] = 3;
  if !err_bytes_is(hid_emit(&d4), "hid: invalid store") { ok = false; }
  return assert(ok, "the emitter refuses drifted stores");
}

fn t15() -> TestResult {
  let data = hb(alltags_hex());
  let r = hid_parse(&data);
  if !r.is_ok { return assert(false, "all-tags fixture must parse"); }
  let d: HidDescriptor = r.value;
  var ok = hid_item_count(&d) == 27;
  if hid_item_tag(&d, 0) != HID_GLOBAL_USAGE_PAGE { ok = false; }
  if hid_item_tag(&d, 5) != HID_GLOBAL_UNIT { ok = false; }
  if hid_item_tag(&d, 6) != HID_GLOBAL_UNIT_EXPONENT { ok = false; }
  if hid_item_data_nibble_signed(&d, 6) != -1 { ok = false; }
  if hid_item_tag(&d, 7) != HID_GLOBAL_REPORT_SIZE { ok = false; }
  if hid_item_tag(&d, 8) != HID_GLOBAL_REPORT_ID { ok = false; }
  if hid_item_tag(&d, 9) != HID_GLOBAL_REPORT_COUNT { ok = false; }
  if hid_item_stack(&d, 10) != 1 { ok = false; }
  if hid_item_stack(&d, 11) != 0 { ok = false; }
  if hid_item_tag(&d, 12) != HID_LOCAL_USAGE { ok = false; }
  if hid_item_tag(&d, 13) != HID_LOCAL_USAGE_MIN { ok = false; }
  if hid_item_tag(&d, 14) != HID_LOCAL_USAGE_MAX { ok = false; }
  if hid_item_tag(&d, 15) != HID_LOCAL_DESIGNATOR_INDEX { ok = false; }
  if hid_item_tag(&d, 16) != HID_LOCAL_DESIGNATOR_MIN { ok = false; }
  if hid_item_tag(&d, 17) != HID_LOCAL_DESIGNATOR_MAX { ok = false; }
  if hid_item_tag(&d, 18) != HID_LOCAL_STRING_INDEX { ok = false; }
  if hid_item_tag(&d, 19) != HID_LOCAL_STRING_MIN { ok = false; }
  if hid_item_tag(&d, 20) != HID_LOCAL_STRING_MAX { ok = false; }
  if hid_item_tag(&d, 21) != HID_LOCAL_DELIMITER { ok = false; }
  if hid_item_tag(&d, 22) != HID_MAIN_COLLECTION { ok = false; }
  if hid_item_collection_kind(&d, 22) != 0 { ok = false; }
  if hid_item_tag(&d, 23) != HID_MAIN_INPUT { ok = false; }
  if hid_item_tag(&d, 24) != HID_MAIN_OUTPUT { ok = false; }
  if hid_item_tag(&d, 25) != HID_MAIN_FEATURE { ok = false; }
  if hid_item_tag(&d, 26) != HID_MAIN_END_COLLECTION { ok = false; }
  if hid_item_depth(&d, 22) != 0 { ok = false; }
  if hid_item_depth(&d, 23) != 1 { ok = false; }
  if hid_item_depth(&d, 26) != 0 { ok = false; }
  if hid_item_usage_page(&d, 26) != 1 { ok = false; }
  if !roundtrip(&data) { ok = false; }
  return assert(ok, "every documented tag parses, is classified and round-trips");
}

fn t16() -> TestResult {
  let data = hb(mouse_hex());
  let r = hid_parse(&data);
  if !r.is_ok { return assert(false, "mouse fixture must parse"); }
  let d: HidDescriptor = r.value;
  var ok = true;
  let header0 = hb("0501");
  let ib0 = hid_item_bytes(&d, 0);
  if !ib0.is_ok { ok = false; } else {
    let v: Vec[UInt8] = ib0.value;
    if !bytes_equal(&v, &header0) { ok = false; }
  }
  let one = hb("01");
  let db0 = hid_item_data_bytes(&d, 0);
  if !db0.is_ok { ok = false; } else {
    let v2: Vec[UInt8] = db0.value;
    if !bytes_equal(&v2, &one) { ok = false; }
  }
  let header2 = hb("a101");
  let ib2 = hid_item_bytes(&d, 2);
  if !ib2.is_ok { ok = false; } else {
    let v3: Vec[UInt8] = ib2.value;
    if !bytes_equal(&v3, &header2) { ok = false; }
  }
  let end = hb("c0");
  let eb = hid_item_bytes(&d, 24);
  if !eb.is_ok { ok = false; } else {
    let v4: Vec[UInt8] = eb.value;
    if !bytes_equal(&v4, &end) { ok = false; }
  }
  let ed = hid_item_data_bytes(&d, 24);
  if !ed.is_ok { ok = false; } else {
    let v5: Vec[UInt8] = ed.value;
    if v5.len() != 0 { ok = false; }
  }
  let two_bytes = hb("16ffff");
  let interp = hb(interp_hex());
  let ir = hid_parse(&interp);
  if !ir.is_ok { ok = false; } else {
    let id: HidDescriptor = ir.value;
    let ib3 = hid_item_bytes(&id, 2);
    if !ib3.is_ok { ok = false; } else {
      let v6: Vec[UInt8] = ib3.value;
      if !bytes_equal(&v6, &two_bytes) { ok = false; }
    }
  }
  return assert(ok, "data-byte and whole-item byte copies are exact");
}

fn main() -> Int {
  io.println("=== xiom.hid conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.hid: all tests passed");
  } else {
    io.println("xiom.hid: tests failed");
  }
  return failed;
}
