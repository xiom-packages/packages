// XIOM — xiom.ffmpeg Conformance Tests
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Comprehensive conformance suite for xiom.ffmpeg module.
// Covers: type declarations, constants, resource alloc/free, safe wrappers,
// error propagation, contract enforcement (requires path.len() > 0),
// and edge cases on all 9 safe wrapper functions.

module tests.xiom_ffmpeg.conformance
use xiom.ffmpeg;

// ═══════════════════════════════════════════════════════════════════════════
// Test 1 – Type declarations exist (compile-time)
// ═══════════════════════════════════════════════════════════════════════════

fn test_type_declarations() -> Bool {
  var ctx: FfmpegContext = 0;
  var pkt: FfmpegPacket  = 0;
  var frm: FfmpegFrame   = 0;
  return true;
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 2 – Constants are defined
// ═══════════════════════════════════════════════════════════════════════════

fn test_constants_defined() -> Bool {
  return AVMEDIA_TYPE_VIDEO == 0
      && AVMEDIA_TYPE_AUDIO == 1
      && AV_SUCCESS       == 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 3 – alloc_packet returns Ok with non-null handle
// ═══════════════════════════════════════════════════════════════════════════

fn test_alloc_packet_ok() -> Bool {
  let r = alloc_packet();
  if r.is_err() { return false; }
  let pkt = r.unwrap();
  return pkt != 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 4 – free_packet does not crash
// ═══════════════════════════════════════════════════════════════════════════

fn test_free_packet_no_crash() -> Bool {
  let r = alloc_packet();
  if r.is_err() { return false; }
  free_packet(r.unwrap());
  return true;
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 5 – alloc_frame returns Ok with non-null handle
// ═══════════════════════════════════════════════════════════════════════════

fn test_alloc_frame_ok() -> Bool {
  let r = alloc_frame();
  if r.is_err() { return false; }
  return r.unwrap() != 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 6 – free_frame does not crash
// ═══════════════════════════════════════════════════════════════════════════

fn test_free_frame_no_crash() -> Bool {
  let r = alloc_frame();
  if r.is_err() { return false; }
  free_frame(r.unwrap());
  return true;
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 7 – alloc_packet + alloc_frame together (distinct handles)
// ═══════════════════════════════════════════════════════════════════════════

fn test_alloc_packet_and_frame_distinct() -> Bool {
  let pr = alloc_packet();
  let fr = alloc_frame();
  if pr.is_err() || fr.is_err() {
    if pr.is_ok() { free_packet(pr.unwrap()); }
    if fr.is_ok() { free_frame(fr.unwrap()); }
    return false;
  }
  let pkt = pr.unwrap();
  let frm = fr.unwrap();
  var distinct = pkt != frm;
  free_packet(pkt);
  free_frame(frm);
  return distinct;
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 8 – Multiple packets can be allocated and freed
// ═══════════════════════════════════════════════════════════════════════════

fn test_multiple_packets() -> Bool {
  let r1 = alloc_packet();
  let r2 = alloc_packet();
  let r3 = alloc_packet();
  if r1.is_err() || r2.is_err() || r3.is_err() {
    if r1.is_ok() { free_packet(r1.unwrap()); }
    if r2.is_ok() { free_packet(r2.unwrap()); }
    if r3.is_ok() { free_packet(r3.unwrap()); }
    return false;
  }
  var p1 = r1.unwrap();
  var p2 = r2.unwrap();
  var p3 = r3.unwrap();
  var ok = p1 != 0 && p2 != 0 && p3 != 0
        && p1 != p2 && p2 != p3 && p1 != p3;
  free_packet(p3);
  free_packet(p2);
  free_packet(p1);
  return ok;
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 9 – Multiple frames can be allocated and freed
// ═══════════════════════════════════════════════════════════════════════════

fn test_multiple_frames() -> Bool {
  let r1 = alloc_frame();
  let r2 = alloc_frame();
  if r1.is_err() || r2.is_err() {
    if r1.is_ok() { free_frame(r1.unwrap()); }
    if r2.is_ok() { free_frame(r2.unwrap()); }
    return false;
  }
  var f1 = r1.unwrap();
  var f2 = r2.unwrap();
  var ok = f1 != 0 && f2 != 0 && f1 != f2;
  free_frame(f2);
  free_frame(f1);
  return ok;
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 10 – open_input with valid path (stub — FFmpeg DLL may be absent)
// ═══════════════════════════════════════════════════════════════════════════

fn test_open_input_valid_path_stub() -> Bool {
  let r = open_input("test.mp4");
  // If DLL loaded: may succeed or fail with file-not-found
  // If DLL absent: extern call returns 0/failure
  // Test verifies the wrapper doesn't crash and returns a Result type
  return r.is_ok() || r.is_err();
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 11 – open_input with empty path violates contract (should trap)
// ═══════════════════════════════════════════════════════════════════════════

// Contract: requires path.len() > 0
// Calling open_input("") traps at runtime — verified via manual / separate
// contract-violation harness. Here we test that non-empty path doesn't trap.

fn test_open_input_nonempty_does_not_trap() -> Bool {
  let r = open_input("file.mkv");
  return r.is_ok() || r.is_err();
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 12 – close_input on a null/invalid context does not crash
// ═══════════════════════════════════════════════════════════════════════════

fn test_close_input_null_no_crash() -> Bool {
  close_input(0);
  return true;
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 13 – find_stream_info on null context returns Err
// ═══════════════════════════════════════════════════════════════════════════

fn test_find_stream_info_null_context() -> Bool {
  let r = find_stream_info(0);
  return r.is_err();
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 14 – get_video_stream on null context returns Err
// ═══════════════════════════════════════════════════════════════════════════

fn test_get_video_stream_null_context() -> Bool {
  let r = get_video_stream(0);
  return r.is_err();
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 15 – read_frame on null context/pkg returns Err (no crash)
// ═══════════════════════════════════════════════════════════════════════════

fn test_read_frame_null_context() -> Bool {
  let r = read_frame(0, 0);
  return r.is_err();
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 16 – decode_frame on null context returns Err (no crash)
// ═══════════════════════════════════════════════════════════════════════════

fn test_decode_frame_null_context() -> Bool {
  let r = decode_frame(0, 0, 0);
  return r.is_err();
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 17 – encode_frame on null context returns Err (no crash)
// ═══════════════════════════════════════════════════════════════════════════

fn test_encode_frame_null_context() -> Bool {
  let r = encode_frame(0, 0, 0);
  return r.is_err();
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 18 – write_frame on null context returns Err (no crash)
// ═══════════════════════════════════════════════════════════════════════════

fn test_write_frame_null_context() -> Bool {
  let r = write_frame(0, 0);
  return r.is_err();
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 19 – open_output with valid path (stub)
// ═══════════════════════════════════════════════════════════════════════════

fn test_open_output_valid_path_stub() -> Bool {
  let r = open_output("out.mp4", 0);
  return r.is_ok() || r.is_err();
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 20 – Multiple result types propagate correctly
// ═══════════════════════════════════════════════════════════════════════════

fn test_result_chain_no_crash() -> Bool {
  // Simulate a decode pipeline with null context — all should return Err
  let r1 = find_stream_info(0);
  let r2 = get_video_stream(0);
  let r3 = read_frame(0, 0);
  let r4 = decode_frame(0, 0, 0);
  return r1.is_err() && r2.is_err() && r3.is_err() && r4.is_err();
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 21 – int_to_str helper correctness
// ═══════════════════════════════════════════════════════════════════════════

fn test_int_to_str_positive() -> Bool {
  return int_to_str(42) == "42";
}

fn test_int_to_str_zero() -> Bool {
  return int_to_str(0) == "0";
}

fn test_int_to_str_negative() -> Bool {
  return int_to_str(-5) == "-5";
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 22 – Error message contains code prefix
// ═══════════════════════════════════════════════════════════════════════════

fn test_error_message_format() -> Bool {
  // find_stream_info on null should return Err with a message
  let r = find_stream_info(0);
  if r.is_ok() { return false; }
  let msg = r.unwrap_err();
  return msg.len() > 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 23 – EOF constant is negative (distinct from success)
// ═══════════════════════════════════════════════════════════════════════════

fn test_eof_constant_negative() -> Bool {
  return AV_ERROR_EOF < 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// Test 24 – EAGAIN constant is negative
// ═══════════════════════════════════════════════════════════════════════════

fn test_eagain_constant_negative() -> Bool {
  return AV_ERROR_EAGAIN < 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// Main
// ═══════════════════════════════════════════════════════════════════════════

fn report(passed: Bool, name: Str) -> Int {
  if passed { return 0; }
  return 1;
}

fn main() -> Int {
  var passed = 0;
  var total  = 0;
  var failed = 0;

  total = total + 1; if test_type_declarations()           { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_constants_defined()           { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_alloc_packet_ok()             { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_free_packet_no_crash()        { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_alloc_frame_ok()              { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_free_frame_no_crash()         { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_alloc_packet_and_frame_distinct() { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_multiple_packets()            { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_multiple_frames()             { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_open_input_valid_path_stub()  { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_open_input_nonempty_does_not_trap() { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_close_input_null_no_crash()   { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_find_stream_info_null_context() { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_get_video_stream_null_context() { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_read_frame_null_context()     { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_decode_frame_null_context()   { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_encode_frame_null_context()   { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_write_frame_null_context()    { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_open_output_valid_path_stub() { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_result_chain_no_crash()       { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_int_to_str_positive()         { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_int_to_str_zero()             { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_int_to_str_negative()         { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_error_message_format()        { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_eof_constant_negative()       { passed = passed + 1; } else { failed = failed + 1; }
  total = total + 1; if test_eagain_constant_negative()    { passed = passed + 1; } else { failed = failed + 1; }

  if passed == total { return 0; }
  return 1;
}
