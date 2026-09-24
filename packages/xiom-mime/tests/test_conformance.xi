// XIOM -- xiom.mime conformance tests (22 checks)
// Port task: prove the pure-XIOM xiom.mime module against its documented
// normalization, extension-mapping and class-check rules.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 5. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so every comparison
// below is routed through streq and every Vec[Str] read is bound to an
// explicitly typed local before use.

module mime_tests
use xiom.io; use xiom.test; use xiom.mime;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when ext maps to the wanted media type.
fn type_is(ext: Str, want: Str) -> Bool {
  return streq(mime_type_for_extension(ext), want);
}

// True when the media type maps to the wanted primary extension.
fn ext_is(m: Str, want: Str) -> Bool {
  return streq(mime_extension_for(m), want);
}

// Round-trip every extension in `exts` through type_for_extension and back.
fn all_round_trip(exts: &Vec[Str]) -> Bool {
  var ok = true;
  var i = 0;
  while i < exts.len() {
    let e: Str = exts[i];
    let got: Str = mime_extension_for(mime_type_for_extension(e));
    if !streq(got, e) { ok = false; }
    i = i + 1;
  }
  return ok;
}

// The 26 primary extensions exercised by the round-trip check.
fn round_trip_exts() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("txt"); v.push("csv"); v.push("tsv"); v.push("html"); v.push("css");
  v.push("js"); v.push("md"); v.push("json"); v.push("xml"); v.push("pdf");
  v.push("png"); v.push("jpg"); v.push("gif"); v.push("webp"); v.push("svg");
  v.push("ico"); v.push("bmp"); v.push("ppm"); v.push("wav"); v.push("mp3");
  v.push("ogg"); v.push("flac"); v.push("mp4"); v.push("webm"); v.push("zip");
  v.push("tar");
  return v;
}

// The 37 extensions named by the package task, plus the fallback-only "bin".
fn mandatory_exts() -> Vec[Str] {
  var v = Vec[Str].new();
  v.push("txt"); v.push("html"); v.push("css"); v.push("js"); v.push("json");
  v.push("xml"); v.push("csv"); v.push("tsv"); v.push("md"); v.push("pdf");
  v.push("png"); v.push("jpg"); v.push("jpeg"); v.push("gif"); v.push("webp");
  v.push("svg"); v.push("ico"); v.push("bmp"); v.push("ppm"); v.push("wav");
  v.push("mp3"); v.push("ogg"); v.push("flac"); v.push("mp4"); v.push("webm");
  v.push("zip"); v.push("gz"); v.push("tar"); v.push("wasm"); v.push("toml");
  v.push("yaml"); v.push("yml"); v.push("ini"); v.push("sh"); v.push("exe");
  v.push("dll"); v.push("bin");
  return v;
}

fn t1() -> TestResult {
  var ok = streq(mime_normalize("Text/HTML"), "text/html");
  if !streq(mime_normalize("  text/plain  "), "text/plain") { ok = false; }
  if !streq(mime_normalize("\tAPPLICATION/JSON\n"), "application/json") { ok = false; }
  if !streq(mime_normalize("audio/MPEG"), "audio/mpeg") { ok = false; }
  return assert(ok, "normalize: trim and lowercase");
}

fn t2() -> TestResult {
  var ok = streq(mime_normalize("text/html; charset=UTF-8"), "text/html");
  if !streq(mime_normalize("  Application/JSON ; boundary=xyz  "), "application/json") { ok = false; }
  if !streq(mime_normalize("text/plain;charset=utf-8;q=0.5"), "text/plain") { ok = false; }
  if !streq(mime_normalize("IMAGE/PNG;BLAH=1"), "image/png") { ok = false; }
  return assert(ok, "normalize: drop parameter section and trim again");
}

fn t3() -> TestResult {
  var ok = streq(mime_normalize(""), "");
  if !streq(mime_normalize("   "), "") { ok = false; }
  if !streq(mime_normalize(";"), "") { ok = false; }
  if !streq(mime_normalize("; charset=x"), "") { ok = false; }
  if !streq(mime_normalize("  ;  a=b"), "") { ok = false; }
  return assert(ok, "normalize: empty and parameter-only inputs");
}

fn t4() -> TestResult {
  var ok = type_is("txt", "text/plain");
  if !type_is(".txt", "text/plain") { ok = false; }
  if !type_is("TXT", "text/plain") { ok = false; }
  if !type_is(".PNG", "image/png") { ok = false; }
  if !type_is(".JpG", "image/jpeg") { ok = false; }
  if !type_is("  .Md  ", "text/markdown") { ok = false; }
  if !type_is("..Json", "application/json") { ok = false; }
  return assert(ok, "type_for_extension: case, dot tolerance and spaces");
}

fn t5() -> TestResult {
  var ok = type_is("html", "text/html");
  if !type_is("css", "text/css") { ok = false; }
  if !type_is("js", "text/javascript") { ok = false; }
  if !type_is("json", "application/json") { ok = false; }
  if !type_is("xml", "application/xml") { ok = false; }
  if !type_is("csv", "text/csv") { ok = false; }
  if !type_is("tsv", "text/tab-separated-values") { ok = false; }
  if !type_is("md", "text/markdown") { ok = false; }
  return assert(ok, "mapping: core text and structured-text extensions");
}

fn t6() -> TestResult {
  var ok = type_is("pdf", "application/pdf");
  if !type_is("png", "image/png") { ok = false; }
  if !type_is("gif", "image/gif") { ok = false; }
  if !type_is("webp", "image/webp") { ok = false; }
  if !type_is("svg", "image/svg+xml") { ok = false; }
  if !type_is("ico", "image/x-icon") { ok = false; }
  if !type_is("bmp", "image/bmp") { ok = false; }
  if !type_is("ppm", "image/x-portable-pixmap") { ok = false; }
  return assert(ok, "mapping: documents and images");
}

fn t7() -> TestResult {
  var ok = type_is("wav", "audio/wav");
  if !type_is("mp3", "audio/mpeg") { ok = false; }
  if !type_is("ogg", "audio/ogg") { ok = false; }
  if !type_is("flac", "audio/flac") { ok = false; }
  if !type_is("mp4", "video/mp4") { ok = false; }
  if !type_is("webm", "video/webm") { ok = false; }
  if !type_is("mkv", "video/x-matroska") { ok = false; }
  return assert(ok, "mapping: audio and video extensions");
}

fn t8() -> TestResult {
  var ok = type_is("zip", "application/zip");
  if !type_is("gz", "application/gzip") { ok = false; }
  if !type_is("tar", "application/x-tar") { ok = false; }
  if !type_is("wasm", "application/wasm") { ok = false; }
  if !type_is("toml", "application/toml") { ok = false; }
  if !type_is("yaml", "application/yaml") { ok = false; }
  if !type_is("yml", "application/yaml") { ok = false; }
  if !type_is("ini", "text/plain") { ok = false; }
  if !type_is("sh", "application/x-sh") { ok = false; }
  if !type_is("exe", "application/vnd.microsoft.portable-executable") { ok = false; }
  if !type_is("dll", "application/vnd.microsoft.portable-executable") { ok = false; }
  if !type_is("bin", "application/octet-stream") { ok = false; }
  return assert(ok, "mapping: archives, config, executables and blobs");
}

fn t9() -> TestResult {
  var ok = type_is("xyz", "application/octet-stream");
  if !type_is("", "application/octet-stream") { ok = false; }
  if !type_is(".", "application/octet-stream") { ok = false; }
  if !type_is("...", "application/octet-stream") { ok = false; }
  if !type_is("tar.gz", "application/octet-stream") { ok = false; }
  if !type_is("PNG.", "application/octet-stream") { ok = false; }
  if !type_is("   ", "application/octet-stream") { ok = false; }
  return assert(ok, "type_for_extension: unknown/empty fall back to octet-stream");
}

fn t10() -> TestResult {
  var ok = ext_is("text/html", "html");
  if !ext_is("text/html; charset=utf-8", "html") { ok = false; }
  if !ext_is("TEXT/PLAIN", "txt") { ok = false; }
  if !ext_is("  image/png  ", "png") { ok = false; }
  if !ext_is("application/json", "json") { ok = false; }
  if !ext_is("application/json; profile=x", "json") { ok = false; }
  return assert(ok, "extension_for: normalized lookup with parameters and case");
}

fn t11() -> TestResult {
  var ok = ext_is("image/jpeg", "jpg");
  if !ext_is("application/yaml", "yaml") { ok = false; }
  if !ext_is("audio/ogg", "ogg") { ok = false; }
  if !ext_is("audio/midi", "midi") { ok = false; }
  if !ext_is("image/tiff", "tiff") { ok = false; }
  if !ext_is("application/octet-stream", "bin") { ok = false; }
  if !ext_is("application/x-ndjson", "jsonl") { ok = false; }
  return assert(ok, "extension_for: primary extension per media type");
}

fn t12() -> TestResult {
  var ok = ext_is("", "");
  if !ext_is("   ", "") { ok = false; }
  if !ext_is("; charset=x", "") { ok = false; }
  if !ext_is("application/x-nonexistent", "") { ok = false; }
  if !ext_is("image/png2", "") { ok = false; }
  return assert(ok, "extension_for: unknown and empty inputs yield empty string");
}

fn t13() -> TestResult {
  let exts = round_trip_exts();
  return assert(all_round_trip(&exts), "round-trip: 26 primary extension pairs");
}

fn t14() -> TestResult {
  var ok = mime_is_text("text/plain");
  if !mime_is_text("TEXT/HTML; charset=utf-8") { ok = false; }
  if mime_is_text("application/json") { ok = false; }
  if mime_is_text("image/png") { ok = false; }
  if mime_is_text("") { ok = false; }
  return assert(ok, "class text: true for text/*, false elsewhere");
}

fn t15() -> TestResult {
  var ok = mime_is_image("image/png");
  if !mime_is_image("IMAGE/JPEG") { ok = false; }
  if !mime_is_image(" image/svg+xml ; charset=utf-8") { ok = false; }
  if mime_is_image("text/plain") { ok = false; }
  if mime_is_image("application/pdf") { ok = false; }
  if mime_is_image("") { ok = false; }
  return assert(ok, "class image: true for image/*, false elsewhere");
}

fn t16() -> TestResult {
  var ok = mime_is_audio("audio/mpeg");
  if !mime_is_audio("audio/wav") { ok = false; }
  if !mime_is_audio("AUDIO/OGG; q=1") { ok = false; }
  if mime_is_audio("video/mp4") { ok = false; }
  if mime_is_audio("text/plain") { ok = false; }
  if mime_is_audio("") { ok = false; }
  return assert(ok, "class audio: true for audio/*, false elsewhere");
}

fn t17() -> TestResult {
  var ok = mime_is_video("video/mp4");
  if !mime_is_video("VIDEO/WEBM") { ok = false; }
  if !mime_is_video("video/x-matroska; codec=x") { ok = false; }
  if mime_is_video("audio/mpeg") { ok = false; }
  if mime_is_video("image/gif") { ok = false; }
  if mime_is_video("") { ok = false; }
  return assert(ok, "class video: true for video/*, false elsewhere");
}

fn t18() -> TestResult {
  var ok = mime_is_application("application/json");
  if !mime_is_application("APPLICATION/PDF") { ok = false; }
  if !mime_is_application("application/octet-stream") { ok = false; }
  if !mime_is_application("application/zip; name=x") { ok = false; }
  if mime_is_application("text/csv") { ok = false; }
  if mime_is_application("image/png") { ok = false; }
  if mime_is_application("audio/wav") { ok = false; }
  if mime_is_application("video/mp4") { ok = false; }
  return assert(ok, "class application: true for application/*, false elsewhere");
}

fn t19() -> TestResult {
  var ok = mime_is_text("text/plain;charset=utf-8");
  if !mime_is_image("Image/PNG; x=1") { ok = false; }
  if !mime_is_audio("Audio/MP3") { ok = false; }
  if !mime_is_video("  video/webm  ") { ok = false; }
  if !mime_is_application("Application/JSON ; boundary=z") { ok = false; }
  if mime_is_text("application/json") { ok = false; }
  if mime_is_video("audio/mpeg") { ok = false; }
  return assert(ok, "class checks: parameters, case and surrounding spaces");
}

fn t20() -> TestResult {
  let count = mime_type_count();
  let again = mime_type_count();
  var ok = count == 82;
  if count < 45 { ok = false; }
  if again != count { ok = false; }
  return assert(ok, "count: 82 curated entries and stable across calls");
}

fn t21() -> TestResult {
  var ok = streq(mime_normalize(""), "");
  if !streq(mime_type_for_extension(""), "application/octet-stream") { ok = false; }
  if !streq(mime_extension_for(""), "") { ok = false; }
  if mime_is_text("") { ok = false; }
  if mime_is_image("") { ok = false; }
  if mime_is_audio("") { ok = false; }
  if mime_is_video("") { ok = false; }
  if mime_is_application("") { ok = false; }
  return assert(ok, "empty inputs: deterministic results across the API");
}

fn t22() -> TestResult {
  let exts = mandatory_exts();
  var ok = true;
  var i = 0;
  while i < exts.len() {
    let e: Str = exts[i];
    let got: Str = mime_type_for_extension(e);
    if got.len() == 0 { ok = false; }
    if streq(got, "application/octet-stream") {
      if !streq(e, "bin") { ok = false; }
    }
    i = i + 1;
  }
  return assert(ok, "mandatory extension list resolves (only bin is octet-stream)");
}

fn main() -> Int {
  io.println("=== xiom.mime conformance tests ===");
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
    io.println("xiom.mime: all tests passed");
  } else {
    io.println("xiom.mime: tests failed");
  }
  return failed;
}
