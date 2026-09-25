// XIOM -- xiom.pem conformance tests (22 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Covers the documented API: single- and multi-block decode, canonical
// encode (64-character lines, LF, headers preserved, trailing LF), empty
// bodies and empty input, CRLF normalization, header rules, the full error
// catalog, body line-length rules, label grammar, out-of-range accessors and
// encoder-side document validation.
//
// All Str equality goes through str_compare (BUG 17 discipline: `==` on Str
// values read from a Vec lowers to a pointer comparison, so every comparison
// below is routed through streq). Every Vec[UInt8] element read is widened
// with `(x as Int) & 0xFF` before comparison.
//
// Pinned base64 expected values were cross-checked against an independent
// implementation (.NET Convert.ToBase64String): Bw==, Byw=, ByxR, ByxRdg==,
// and the 64-character ByxR... line for the deterministic 47/48-byte
// sequences used below.

module pem_tests
use xiom.io; use xiom.test; use xiom.pem;
use xiom.string; use xiom.string.compare;

// --------------------------------------------------
//  Helpers
// --------------------------------------------------

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Raw bytes of a Str (one byte per index).
fn str_bytes(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

// Deterministic byte sequence of length n; covers 0x00 and bytes >= 0x80.
fn seq_bytes(n: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < n {
    v.push(((i * 37 + 7) % 256) as UInt8);
    i = i + 1;
  }
  return v;
}

// True when v[off .. off+want.len()) equals want.
fn bytes_slice_is(v: Vec[UInt8], off: Int, want: Vec[UInt8]) -> Bool {
  if off < 0 || off + want.len() > v.len() {
    return false;
  }
  var i = 0;
  while i < want.len() {
    if (((v[off + i] as Int) & 0xFF) != ((want[i] as Int) & 0xFF)) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  return bytes_slice_is(a, 0, b);
}

// A canonical headerless block: BEGIN label, body, END label, trailing LF.
fn pem_text(label: Str, body: Str) -> Str {
  return "-----BEGIN " + label + "-----\n" + body + "\n-----END " + label + "-----\n";
}

// A canonical block with raw header lines (joined by LF) and a blank line.
fn pem_hdr_text(label: Str, hdrs: Str, body: Str) -> Str {
  if streq(body, "") {
    return "-----BEGIN " + label + "-----\n" + hdrs + "\n\n-----END " + label + "-----\n";
  }
  return "-----BEGIN " + label + "-----\n" + hdrs + "\n\n" + body + "\n-----END " + label + "-----\n";
}

// True when r is Err with exactly the message `want`.
fn doc_err_is(r: Result[PemDocument, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// True when r is Err with exactly the message `want` (Str result).
fn str_err_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  return streq(r.error, want);
}

// True when `text` parses to one block whose body bytes equal `want`.
fn dec_bytes_is(text: Str, want: Vec[UInt8]) -> Bool {
  let r = pem_decode(text);
  if !r.is_ok {
    return false;
  }
  let doc: PemDocument = r.value;
  if pem_block_count(&doc) != 1 {
    return false;
  }
  return bytes_equal(pem_decoded_bytes(&doc, 0), want);
}

// True when `text` parses to one block whose body is seq_bytes(n).
fn dec_seq_is(text: Str, n: Int) -> Bool {
  return dec_bytes_is(text, seq_bytes(n));
}

// True when decoding `text` and re-encoding yields exactly `want`.
fn reencode_is(text: Str, want: Str) -> Bool {
  let r = pem_decode(text);
  if !r.is_ok {
    return false;
  }
  let doc: PemDocument = r.value;
  let e = pem_encode(&doc);
  if !e.is_ok {
    return false;
  }
  return streq(e.value, want);
}

// --------------------------------------------------
//  Checks
// --------------------------------------------------

fn t1() -> TestResult {
  let text = pem_text("CERTIFICATE", "TWFu");
  let r = pem_decode(text);
  var ok = r.is_ok;
  if r.is_ok {
    let doc: PemDocument = r.value;
    if pem_block_count(&doc) != 1 { ok = false; }
    if !streq(pem_label(&doc, 0), "CERTIFICATE") { ok = false; }
    if pem_header_count(&doc, 0) != 0 { ok = false; }
    if pem_decoded_len(&doc, 0) != 3 { ok = false; }
    if !bytes_equal(pem_decoded_bytes(&doc, 0), str_bytes("Man")) { ok = false; }
  }
  return assert(ok, "decode: single CERTIFICATE block, accessors agree");
}

fn t2() -> TestResult {
  let text = pem_text("CERTIFICATE", "TWFu");
  var ok = reencode_is(text, text);
  let no_lf = "-----BEGIN CERTIFICATE-----\nTWFu\n-----END CERTIFICATE-----";
  if !reencode_is(no_lf, text) { ok = false; }
  return assert(ok, "encode: canonical END/trailing LF added for a final unterminated line");
}

fn t3() -> TestResult {
  let b64 = "ByxRdpvA5QovVHmew+gNMld8ocbrEDVaf6TJ7hM4XYKnzPEWO2CFqs/0GT5jiK3S9xxBZg==";
  let body = string.str_slice(b64, 0, 64) + "\n" + string.str_slice(b64, 64, 72);
  let text = pem_text("PRIVATE KEY", body);
  let r = pem_decode(text);
  var ok = r.is_ok;
  if r.is_ok {
    let doc: PemDocument = r.value;
    if pem_decoded_len(&doc, 0) != 52 { ok = false; }
    if !bytes_equal(pem_decoded_bytes(&doc, 0), seq_bytes(52)) { ok = false; }
  }
  if !reencode_is(text, text) { ok = false; }
  return assert(ok, "decode/encode: 52 bytes wrap at 64 characters and round-trip");
}

fn t4() -> TestResult {
  let bare = "-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----\n";
  let r = pem_decode(bare);
  var ok = r.is_ok;
  if r.is_ok {
    let doc: PemDocument = r.value;
    if pem_block_count(&doc) != 1 { ok = false; }
    if pem_header_count(&doc, 0) != 0 { ok = false; }
    if pem_decoded_len(&doc, 0) != 0 { ok = false; }
    if pem_decoded_bytes(&doc, 0).len() != 0 { ok = false; }
  }
  if !reencode_is(bare, bare) { ok = false; }
  let spaced = "-----BEGIN CERTIFICATE-----\n\n-----END CERTIFICATE-----\n";
  let r2 = pem_decode(spaced);
  if !r2.is_ok { ok = false; } else {
    let doc2: PemDocument = r2.value;
    if pem_header_count(&doc2, 0) != 0 { ok = false; }
    if pem_decoded_len(&doc2, 0) != 0 { ok = false; }
  }
  if !reencode_is(spaced, bare) { ok = false; }
  return assert(ok, "empty body: bare block and header-separator blank decode to zero bytes");
}

fn t5() -> TestResult {
  let t1 = pem_text("CERTIFICATE", "TWFu");
  let t2 = pem_text("PRIVATE KEY", "ByxRdpvA5QovVHmew+gNMld8ocbrEDVaf6TJ7hM4XYKnzPEWO2CFqs/0GT5jiK3S");
  let text = t1 + t2;
  let r = pem_decode(text);
  var ok = r.is_ok;
  if r.is_ok {
    let doc: PemDocument = r.value;
    if pem_block_count(&doc) != 2 { ok = false; }
    if !streq(pem_label(&doc, 0), "CERTIFICATE") { ok = false; }
    if !streq(pem_label(&doc, 1), "PRIVATE KEY") { ok = false; }
    if pem_decoded_len(&doc, 0) != 3 { ok = false; }
    if pem_decoded_len(&doc, 1) != 48 { ok = false; }
    if !bytes_equal(pem_decoded_bytes(&doc, 1), seq_bytes(48)) { ok = false; }
  }
  if !reencode_is(text, text) { ok = false; }
  if !reencode_is(t1 + "\n" + t2, text) { ok = false; }
  return assert(ok, "multi-block: two blocks in order; blank separator is ignored");
}

fn t6() -> TestResult {
  let lf = pem_hdr_text("RSA PRIVATE KEY", "Proc-Type: 4,ENCRYPTED", "TWFu");
  let crlf = string.replace(lf, "\n", "\r\n");
  var ok = reencode_is(crlf, lf);
  let mixed = "-----BEGIN CERTIFICATE-----\r\nTWFu\n-----END CERTIFICATE-----\r\n";
  if !reencode_is(mixed, pem_text("CERTIFICATE", "TWFu")) { ok = false; }
  if !doc_err_is(pem_decode(pem_text("CERTIFICATE", "TW\rFu")), "pem: invalid base64 character") { ok = false; }
  if !doc_err_is(pem_decode("-----BEGIN CERTIFICATE-----\rTWFu\r\n-----END CERTIFICATE-----\r\n"), "pem: malformed block marker") { ok = false; }
  return assert(ok, "CRLF normalization: CRLF and mixed endings decode; stray CR bytes do not");
}

fn t7() -> TestResult {
  let text = pem_hdr_text("RSA PRIVATE KEY", "Proc-Type: 4,ENCRYPTED\nDEK-Info: AES-256-CBC,0123456789ABCDEF0123456789ABCDEF", "TWFu");
  let r = pem_decode(text);
  var ok = r.is_ok;
  if r.is_ok {
    let doc: PemDocument = r.value;
    if pem_block_count(&doc) != 1 { ok = false; }
    if pem_header_count(&doc, 0) != 2 { ok = false; }
    if !streq(pem_header_line(&doc, 0, 0), "Proc-Type: 4,ENCRYPTED") { ok = false; }
    if !streq(pem_header_line(&doc, 0, 1), "DEK-Info: AES-256-CBC,0123456789ABCDEF0123456789ABCDEF") { ok = false; }
    if !streq(pem_header_line(&doc, 0, 2), "") { ok = false; }
    if pem_decoded_len(&doc, 0) != 3 { ok = false; }
  }
  if !reencode_is(text, text) { ok = false; }
  return assert(ok, "headers: raw lines preserved and re-emitted before the blank line");
}

fn t8() -> TestResult {
  let r0 = pem_decode("");
  var ok = r0.is_ok;
  if r0.is_ok {
    let d0: PemDocument = r0.value;
    if pem_block_count(&d0) != 0 { ok = false; }
    let e0 = pem_encode(&d0);
    if !e0.is_ok { ok = false; } else { if !streq(e0.value, "") { ok = false; } }
  }
  let r1 = pem_decode("\n\n\n");
  if !r1.is_ok { ok = false; } else {
    let d1: PemDocument = r1.value;
    if pem_block_count(&d1) != 0 { ok = false; }
  }
  return assert(ok, "empty input and blank-line-only input yield an empty document");
}

fn t9() -> TestResult {
  let block = pem_text("CERTIFICATE", "TWFu");
  var ok = doc_err_is(pem_decode("hello\n" + block), "pem: text outside blocks");
  if !doc_err_is(pem_decode(block + "junk\n"), "pem: text outside blocks") { ok = false; }
  if !doc_err_is(pem_decode("-----END CERTIFICATE-----\n"), "pem: text outside blocks") { ok = false; }
  if !doc_err_is(pem_decode(" \n" + block), "pem: text outside blocks") { ok = false; }
  return assert(ok, "text outside blocks: non-empty non-marker lines are rejected");
}

fn t10() -> TestResult {
  var ok = doc_err_is(pem_decode("-----BEGIN X-----\nTWFu\n-----END Y-----\n"), "pem: label mismatch");
  if !doc_err_is(pem_decode("-----BEGIN CERTIFICATE-----\nTWFu\n-----END certificate-----\n"), "pem: label mismatch") { ok = false; }
  return assert(ok, "label mismatch: END label must equal BEGIN label, case-sensitively");
}

fn t11() -> TestResult {
  var ok = doc_err_is(pem_decode("-----BEGIN CERTIFICATE-----\nTWFu\n"), "pem: unterminated block");
  if !doc_err_is(pem_decode("-----BEGIN CERTIFICATE-----\nProc-Type: 4,ENCRYPTED\n"), "pem: unterminated block") { ok = false; }
  if !doc_err_is(pem_decode("-----BEGIN CERTIFICATE-----"), "pem: unterminated block") { ok = false; }
  return assert(ok, "unterminated block: EOF before the matching END line");
}

fn t12() -> TestResult {
  var ok = doc_err_is(pem_decode(pem_text("CERTIFICATE", "TW!u")), "pem: invalid base64 character");
  if !doc_err_is(pem_decode(pem_text("CERTIFICATE", "TWF u")), "pem: invalid base64 character") { ok = false; }
  if !doc_err_is(pem_decode(pem_text("CERTIFICATE", "TWF-u")), "pem: invalid base64 character") { ok = false; }
  if !doc_err_is(pem_decode(pem_text("CERTIFICATE", "TWF_u")), "pem: invalid base64 character") { ok = false; }
  if !doc_err_is(pem_decode(pem_text("CERTIFICATE", "TW\tFu")), "pem: invalid base64 character") { ok = false; }
  return assert(ok, "invalid base64 characters: !, space, -, _, TAB are rejected");
}

fn t13() -> TestResult {
  var ok = doc_err_is(pem_decode(pem_text("CERTIFICATE", "TQ=")), "pem: bad padding");
  if !doc_err_is(pem_decode(pem_text("CERTIFICATE", "TQ===")), "pem: bad padding") { ok = false; }
  if !doc_err_is(pem_decode(pem_text("CERTIFICATE", "TQ====")), "pem: bad padding") { ok = false; }
  if !doc_err_is(pem_decode(pem_text("CERTIFICATE", "====")), "pem: bad padding") { ok = false; }
  if !doc_err_is(pem_decode(pem_text("CERTIFICATE", "AAAA====")), "pem: bad padding") { ok = false; }
  if !doc_err_is(pem_decode(pem_text("CERTIFICATE", "TQ==AAAA")), "pem: bad padding") { ok = false; }
  if !doc_err_is(pem_decode(pem_text("CERTIFICATE", "AAAAAAAA=")), "pem: bad padding") { ok = false; }
  return assert(ok, "bad padding: wrong length, leading '=', data after '='");
}

fn t14() -> TestResult {
  var ok = doc_err_is(pem_decode(pem_text("CERTIFICATE", "TR==")), "pem: non-canonical trailing bits");
  if !doc_err_is(pem_decode(pem_text("CERTIFICATE", "TWF=")), "pem: non-canonical trailing bits") { ok = false; }
  if !doc_err_is(pem_decode(pem_text("CERTIFICATE", "TWH=")), "pem: non-canonical trailing bits") { ok = false; }
  if !dec_bytes_is(pem_text("CERTIFICATE", "TWE="), str_bytes("Ma")) { ok = false; }
  return assert(ok, "non-canonical trailing bits: padded groups must carry zero low bits");
}

fn t15() -> TestResult {
  var ok = dec_bytes_is(pem_text("X", "TQ=="), str_bytes("M"));
  if !dec_bytes_is(pem_text("X", "TWFu"), str_bytes("Man")) { ok = false; }
  if !dec_seq_is(pem_text("X", "Bw=="), 1) { ok = false; }
  if !dec_seq_is(pem_text("X", "Byw="), 2) { ok = false; }
  if !dec_seq_is(pem_text("X", "ByxR"), 3) { ok = false; }
  if !dec_seq_is(pem_text("X", "ByxRdg=="), 4) { ok = false; }
  let b47 = "ByxRdpvA5QovVHmew+gNMld8ocbrEDVaf6TJ7hM4XYKnzPEWO2CFqs/0GT5jiK0=";
  let b48 = "ByxRdpvA5QovVHmew+gNMld8ocbrEDVaf6TJ7hM4XYKnzPEWO2CFqs/0GT5jiK3S";
  if !dec_seq_is(pem_text("X", b47), 47) { ok = false; }
  if !dec_seq_is(pem_text("X", b48), 48) { ok = false; }
  if !dec_seq_is(pem_text("X", b48 + "\n" + "9w=="), 49) { ok = false; }
  if !reencode_is(pem_text("X", b47), pem_text("X", b47)) { ok = false; }
  if !reencode_is(pem_text("X", b48), pem_text("X", b48)) { ok = false; }
  if !reencode_is(pem_text("X", b48 + "\n" + "9w=="), pem_text("X", b48 + "\n" + "9w==")) { ok = false; }
  return assert(ok, "pinned base64 vectors: 1, 2, 3, 4, 47, 48, 49 bytes");
}

fn t16() -> TestResult {
  var ok = doc_err_is(pem_decode("-----BEGIN RSA PRIVATE KEY-----\nTWFu\nProc-Type: 4,ENCRYPTED\n-----END RSA PRIVATE KEY-----\n"), "pem: header after body");
  if !doc_err_is(pem_decode("-----BEGIN CERTIFICATE-----\nTWFu\nX: 1\n-----END CERTIFICATE-----\n"), "pem: header after body") { ok = false; }
  return assert(ok, "header after body: a Name: value line after the body is rejected");
}

fn t17() -> TestResult {
  var ok = doc_err_is(pem_decode("-----BEGIN RSA PRIVATE KEY-----\nProc-Type: 4,ENCRYPTED\nTWFu\n-----END RSA PRIVATE KEY-----\n"), "pem: header section not terminated");
  if !doc_err_is(pem_decode("-----BEGIN RSA PRIVATE KEY-----\nProc-Type: 4,ENCRYPTED\n-----END RSA PRIVATE KEY-----\n"), "pem: header section not terminated") { ok = false; }
  if !reencode_is(pem_hdr_text("X", "Proc-Type: 4,ENCRYPTED", ""), pem_hdr_text("X", "Proc-Type: 4,ENCRYPTED", "")) { ok = false; }
  return assert(ok, "header section not terminated: headers require a blank line before the body");
}

fn t18() -> TestResult {
  var ok = doc_err_is(pem_decode("-----BEGIN CERTIFICATE-----\nTWFu\n\n-----END CERTIFICATE-----\n"), "pem: blank line in body");
  if !doc_err_is(pem_decode("-----BEGIN CERTIFICATE-----\n\n\nTWFu\n-----END CERTIFICATE-----\n"), "pem: blank line in body") { ok = false; }
  return assert(ok, "blank line in body: only the header-separator blank is allowed");
}

fn t19() -> TestResult {
  let long = string.str_repeat("A", 65);
  var ok = doc_err_is(pem_decode(pem_text("CERTIFICATE", long)), "pem: bad body line length");
  if !doc_err_is(pem_decode(pem_text("CERTIFICATE", "TWFu\nTWFu")), "pem: bad body line length") { ok = false; }
  let b48 = "ByxRdpvA5QovVHmew+gNMld8ocbrEDVaf6TJ7hM4XYKnzPEWO2CFqs/0GT5jiK3S";
  let r = pem_decode(pem_text("CERTIFICATE", b48 + "\n" + "ByxR"));
  if !r.is_ok { ok = false; } else {
    let doc: PemDocument = r.value;
    if pem_decoded_len(&doc, 0) != 51 { ok = false; }
    let got = pem_decoded_bytes(&doc, 0);
    if !bytes_slice_is(got, 0, seq_bytes(48)) { ok = false; }
    if !bytes_slice_is(got, 48, seq_bytes(3)) { ok = false; }
  }
  return assert(ok, "body line length: 64-wide lines except a final 1..64 tail");
}

fn t20() -> TestResult {
  var ok = doc_err_is(pem_decode("-----BEGIN CERTIFICATE----\nTWFu\n-----END CERTIFICATE-----\n"), "pem: malformed block marker");
  if !doc_err_is(pem_decode("-----BEGIN-----\nTWFu\n-----END-----\n"), "pem: malformed block marker") { ok = false; }
  if !doc_err_is(pem_decode("-----BEGIN BAD-LABEL-----\nTWFu\n-----END BAD-LABEL-----\n"), "pem: malformed block marker") { ok = false; }
  if !doc_err_is(pem_decode("-----BEGIN A  B-----\nTWFu\n-----END A  B-----\n"), "pem: malformed block marker") { ok = false; }
  if !doc_err_is(pem_decode("-----BEGIN  X-----\nTWFu\n-----END  X-----\n"), "pem: malformed block marker") { ok = false; }
  let r = pem_decode(pem_text("ENCRYPTED PRIVATE KEY", "TWFu"));
  if !r.is_ok { ok = false; } else {
    let doc: PemDocument = r.value;
    if !streq(pem_label(&doc, 0), "ENCRYPTED PRIVATE KEY") { ok = false; }
  }
  if !doc_err_is(pem_decode("-----BEGIN X-----\n-----BEGIN Y-----\n-----END Y-----\n-----END X-----\n"), "pem: nested block not allowed") { ok = false; }
  return assert(ok, "markers: five dashes, keywords, single-space labels, no nesting");
}

fn t21() -> TestResult {
  let text = pem_text("CERTIFICATE", "TWFu");
  let r = pem_decode(text);
  var ok = r.is_ok;
  if r.is_ok {
    let doc: PemDocument = r.value;
    if pem_block_count(&doc) != 1 { ok = false; }
    if !streq(pem_label(&doc, 5), "") { ok = false; }
    if !streq(pem_label(&doc, -1), "") { ok = false; }
    if pem_header_count(&doc, 5) != 0 { ok = false; }
    if !streq(pem_header_line(&doc, 0, 0), "") { ok = false; }
    if !streq(pem_header_line(&doc, 5, 0), "") { ok = false; }
    if pem_decoded_len(&doc, 5) != -1 { ok = false; }
    if pem_decoded_bytes(&doc, 5).len() != 0 { ok = false; }
  }
  return assert(ok, "accessors return neutrals for out-of-range indexes");
}

fn t22() -> TestResult {
  var labels = Vec[Str].new();
  labels.push("BAD-LABEL");
  var hs = Vec[Int].new();
  hs.push(0);
  var hc = Vec[Int].new();
  hc.push(0);
  var ds = Vec[Int].new();
  ds.push(0);
  var dl = Vec[Int].new();
  dl.push(0);
  var hdrs = Vec[Str].new();
  var pool = Vec[UInt8].new();
  let bad = PemDocument{ labels: labels; header_starts: hs; header_counts: hc; data_starts: ds; data_lens: dl; headers: hdrs; data: pool; };
  var ok = str_err_is(pem_encode(&bad), "pem: invalid label");
  var labels2 = Vec[Str].new();
  labels2.push("X");
  var hs2 = Vec[Int].new();
  hs2.push(0);
  var hc2 = Vec[Int].new();
  var ds2 = Vec[Int].new();
  ds2.push(0);
  var dl2 = Vec[Int].new();
  dl2.push(0);
  var hdrs2 = Vec[Str].new();
  var pool2 = Vec[UInt8].new();
  let drift = PemDocument{ labels: labels2; header_starts: hs2; header_counts: hc2; data_starts: ds2; data_lens: dl2; headers: hdrs2; data: pool2; };
  if !str_err_is(pem_encode(&drift), "pem: malformed document") { ok = false; }
  var labels3 = Vec[Str].new();
  labels3.push("X");
  var hs3 = Vec[Int].new();
  hs3.push(0);
  var hc3 = Vec[Int].new();
  hc3.push(1);
  var ds3 = Vec[Int].new();
  ds3.push(0);
  var dl3 = Vec[Int].new();
  dl3.push(0);
  var hdrs3 = Vec[Str].new();
  var pool3 = Vec[UInt8].new();
  let gap = PemDocument{ labels: labels3; header_starts: hs3; header_counts: hc3; data_starts: ds3; data_lens: dl3; headers: hdrs3; data: pool3; };
  if !str_err_is(pem_encode(&gap), "pem: malformed document") { ok = false; }
  var labels4 = Vec[Str].new();
  labels4.push("X");
  var hs4 = Vec[Int].new();
  hs4.push(0);
  var hc4 = Vec[Int].new();
  hc4.push(0);
  var ds4 = Vec[Int].new();
  ds4.push(0);
  var dl4 = Vec[Int].new();
  dl4.push(2);
  var hdrs4 = Vec[Str].new();
  var pool4 = Vec[UInt8].new();
  pool4.push(77u8);
  pool4.push(97u8);
  let good = PemDocument{ labels: labels4; header_starts: hs4; header_counts: hc4; data_starts: ds4; data_lens: dl4; headers: hdrs4; data: pool4; };
  let e = pem_encode(&good);
  if !e.is_ok { ok = false; } else { if !streq(e.value, "-----BEGIN X-----\nTWE=\n-----END X-----\n") { ok = false; } }
  return assert(ok, "encode validation: invalid labels, vector drift and bad ranges are Err");
}

// --------------------------------------------------
//  Harness
// --------------------------------------------------

fn main() -> Int {
  io.println("=== xiom.pem conformance tests ===");
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
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.pem: all tests passed");
  } else {
    io.println("xiom.pem: tests failed");
  }
  return failed;
}
