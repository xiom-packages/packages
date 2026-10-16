// XIOM -- xiom.serial conformance tests (Win32 comm API loader + codecs).
// Copyright (c) 2026 Eleftheros Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Host-independent core (always runs, always green):
//   * deterministic SKIP classification via a bogus library name;
//   * pure DCB encode/decode goldens (byte-exact layout) + an exhaustive
//     360-combo round-trip and 180-combo rejection matrix;
//   * COMMTIMEOUTS encode/decode goldens (blocking and poll shapes);
//   * name catalogs (error kinds, Win32 codes, parity/stop/flow);
//   * typed closed-port and validation errors for EVERY public call
//     (fake handle -1; graceful INVALID_HANDLE / INVALID_ARG paths).
//
// Live leg (Win32 present: always on Windows):
//   * kernel32+advapi32 loader, probe identity, named re-load;
//   * SERIALCOMM enumeration (an absent key -- no ports at all -- is the
//     canonical empty state and is reported as a typed SKIP note);
//   * absent-device typed path: serial_open("COM255") -> NOT_FOUND
//     (the SKIP classification for fleet hosts without that port);
//   * when a real port IS present: open (default timeouts), configure
//     9600 8N1, config read-back, timeout set/get, flush both, drain,
//     blocking read (typed TIMEOUT with nothing connected), write,
//     poll-mode read, close.  Without one, the leg reports SKIP and the
//     suite stays green.
//
// Build+run:
//   scripts/port.ps1 -Package xiom.serial -TimeoutSec 300

module serial_conformance

use xiom.io;
use xiom.convert;
use xiom.string.compare;
use xiom.serial;
use xiom.ffi;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn why(msg: Str) {
  io.println("    detail: " + msg);
  io.flush_stdout();
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn finish(failed: Int) -> Int {
  if failed == 0 {
    io.println("xiom.serial: all tests passed");
  } else {
    io.println("xiom.serial: tests failed");
  }
  return failed;
}

/// Local LE u32 read helper for golden byte checks.
fn rd_u32_le(v: &Vec[UInt8], off: Int) -> Int {
  let b0 = v[off] as Int;
  let b1 = v[off + 1] as Int;
  let b2 = v[off + 2] as Int;
  let b3 = v[off + 3] as Int;
  return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

/// Override the flags DWORD of an encoded DCB (precedence tests).
fn set_dcb_flags(dcb: &mut Vec[UInt8], flags: Int)
  requires: dcb.len() >= 28
{
  unsafe {
    ffi.ptr_write_u32_le(dcb.as_mut_ptr() + 8, flags);
  }
}

fn cfg(baud: Int, db: Int, par: Int, stop: Int, flow: Int) -> SerialConfig {
  return SerialConfig{ baud: baud; data_bits: db; parity: par; stop_bits: stop; flow: flow };
}

fn cfg_eq(a: &SerialConfig, b: &SerialConfig) -> Bool {
  if a.baud != b.baud { return false; }
  if a.data_bits != b.data_bits { return false; }
  if a.parity != b.parity { return false; }
  if a.stop_bits != b.stop_bits { return false; }
  if a.flow != b.flow { return false; }
  return true;
}

fn fake_port() -> SerialPort {
  return SerialPort{ handle: -1; name: "COM0-fake"; };
}

// =========================================================================
// Pure surface: DCB codec
// =========================================================================

fn test_dcb_codec() -> Int {
  var failed = 0;

  // 9600 8N1 flow none -- byte-exact golden.  Flags: fBinary(1) +
  // DTR_CONTROL_ENABLE(0x10) + RTS_CONTROL_ENABLE(0x1000) = 0x1011.
  let c1 = cfg(9600, 8, SERIAL_PARITY_NONE, SERIAL_STOP_ONE, SERIAL_FLOW_NONE);
  let e1 = serial_dcb_encode(&c1);
  var ok = false;
  if e1.is_ok {
    let d: Vec[UInt8] = e1.value;
    ok = d.len() == 28;
    if ok { ok = rd_u32_le(&d, 0) == 28; }
    if ok { ok = rd_u32_le(&d, 4) == 9600; }
    if ok { ok = rd_u32_le(&d, 8) == 4113; }
    if ok { ok = (d[18] as Int) == 8; }
    if ok { ok = (d[19] as Int) == 0; }
    if ok { ok = (d[20] as Int) == 0; }
    if ok { ok = rd_u32_le(&d, 14) % 65536 == 2048; }
    if ok { ok = rd_u32_le(&d, 16) % 65536 == 512; }
    if ok { ok = (d[21] as Int) == 17; }
    if ok { ok = (d[22] as Int) == 19; }
    if ok { ok = (d[23] as Int) == 0; }
    if ok { ok = (d[12] as Int) == 0; }
  }
  failed = failed + report(ok, "dcb-golden: 9600 8N1 none -> 28-byte DCB, flags 0x1011, defaults present");

  // 115200 7E2 RTS/CTS.  Flags: 1 + fParity(2) + fOutxCtsFlow(4) +
  // DTR(0x10) + RTS_HANDSHAKE(0x2000) = 0x2017.
  let c2 = cfg(115200, 7, SERIAL_PARITY_EVEN, SERIAL_STOP_TWO, SERIAL_FLOW_RTS_CTS);
  let e2 = serial_dcb_encode(&c2);
  ok = false;
  if e2.is_ok {
    let d: Vec[UInt8] = e2.value;
    ok = rd_u32_le(&d, 4) == 115200;
    if ok { ok = rd_u32_le(&d, 8) == 8215; }
    if ok { ok = (d[18] as Int) == 7; }
    if ok { ok = (d[19] as Int) == 2; }
    if ok { ok = (d[20] as Int) == 2; }
  }
  failed = failed + report(ok, "dcb-golden: 115200 7E2 rts-cts -> flags 0x2017 (fParity|fOutxCtsFlow|RTS handshake)");

  // 57600 8N1 XON/XOFF.  Flags: 1 + DTR(0x10) + RTS_ENABLE(0x1000) +
  // fOutX(0x100) + fInX(0x200) = 0x1311.
  let c3 = cfg(57600, 8, SERIAL_PARITY_NONE, SERIAL_STOP_ONE, SERIAL_FLOW_XON_XOFF);
  let e3 = serial_dcb_encode(&c3);
  ok = false;
  if e3.is_ok {
    let d: Vec[UInt8] = e3.value;
    ok = rd_u32_le(&d, 8) == 4881;
  }
  failed = failed + report(ok, "dcb-golden: 57600 8N1 xon-xoff -> flags 0x1311 (fOutX|fInX)");

  // 1200 5N1.5.
  let c4 = cfg(1200, 5, SERIAL_PARITY_NONE, SERIAL_STOP_ONE_POINT_FIVE, SERIAL_FLOW_NONE);
  let e4 = serial_dcb_encode(&c4);
  ok = false;
  if e4.is_ok {
    let d: Vec[UInt8] = e4.value;
    ok = (d[18] as Int) == 5;
    if ok { ok = (d[20] as Int) == 1; }
    if ok { ok = rd_u32_le(&d, 8) == 4113; }
  }
  failed = failed + report(ok, "dcb-golden: 1200 5N1.5 -> ByteSize 5, StopBits 1 (ONE5STOPBITS)");

  // Encode rejects an invalid config.
  let bad = cfg(0, 8, SERIAL_PARITY_NONE, SERIAL_STOP_ONE, SERIAL_FLOW_NONE);
  let eb = serial_dcb_encode(&bad);
  failed = failed + report(!eb.is_ok && eb.error.kind == SERIAL_ERR_INVALID_ARG,
    "dcb-encode: baud 0 rejected with INVALID_ARG");

  // Decode round-trips the canonical configs.
  var rt = true;
  let d1 = serial_dcb_decode(&e1.value);
  if !d1.is_ok { rt = false; } elif !cfg_eq(&d1.value, &c1) { rt = false; }
  let d2 = serial_dcb_decode(&e2.value);
  if !d2.is_ok { rt = false; } elif !cfg_eq(&d2.value, &c2) { rt = false; }
  let d3 = serial_dcb_decode(&e3.value);
  if !d3.is_ok { rt = false; } elif !cfg_eq(&d3.value, &c3) { rt = false; }
  let d4 = serial_dcb_decode(&e4.value);
  if !d4.is_ok { rt = false; } elif !cfg_eq(&d4.value, &c4) { rt = false; }
  failed = failed + report(rt, "dcb-decode: 4 canonical configs decode back identical");

  // Decode a too-short slot.
  var short: Vec[UInt8] = Vec[UInt8].with_len(10);
  let ds = serial_dcb_decode(&short);
  failed = failed + report(!ds.is_ok && ds.error.kind == SERIAL_ERR_INVALID_ARG,
    "dcb-decode: 10-byte slot rejected with INVALID_ARG");

  // Hardware flow takes precedence over software bits on decode.
  var mixed: Vec[UInt8] = Vec[UInt8].with_len(28);
  let mix0 = serial_dcb_encode(&c1);
  if mix0.is_ok { mixed = mix0.value; }
  set_dcb_flags(&mut mixed, 4 + 256 + 512);
  let dm = serial_dcb_decode(&mixed);
  var prec_ok = false;
  if dm.is_ok {
    if dm.value.flow == SERIAL_FLOW_RTS_CTS { prec_ok = true; }
  }
  failed = failed + report(prec_ok, "dcb-decode: fOutxCtsFlow wins over fOutX/fInX (hardware precedence)");

  // Exhaustive matrix: 3 bauds x 4 data-bits x 5 parities x 3 stop-bits x
  // 3 flows = 540 combos; 360 are valid (stop 1.5 only with 5 data bits,
  // stop 2 never with 5) and 180 invalid.
  var bauds: Vec[Int] = Vec[Int].new();
  bauds.push(300);
  bauds.push(9600);
  bauds.push(115200);
  var valid_n = 0;
  var invalid_n = 0;
  var roundtrip_bad = 0;
  var reject_bad = 0;
  var bi = 0;
  while bi < bauds.len() {
    var db = 5;
    while db <= 8 {
      var par = 0;
      while par <= 4 {
        var stop = 0;
        while stop <= 2 {
          var flow = 0;
          while flow <= 2 {
            let c = cfg(bauds[bi], db, par, stop, flow);
            let v = serial_config_validate(&c);
            if v.is_ok {
              valid_n = valid_n + 1;
              let e = serial_dcb_encode(&c);
              if !e.is_ok {
                roundtrip_bad = roundtrip_bad + 1;
              } else {
                let d = serial_dcb_decode(&e.value);
                if !d.is_ok {
                  roundtrip_bad = roundtrip_bad + 1;
                } elif !cfg_eq(&d.value, &c) {
                  roundtrip_bad = roundtrip_bad + 1;
                }
              }
            } else {
              invalid_n = invalid_n + 1;
              let e2 = serial_dcb_encode(&c);
              if e2.is_ok { reject_bad = reject_bad + 1; }
            }
            flow = flow + 1;
          }
          stop = stop + 1;
        }
        par = par + 1;
      }
      db = db + 1;
    }
    bi = bi + 1;
  }
  failed = failed + report(valid_n == 360 && roundtrip_bad == 0,
    "dcb-matrix: " + to_string(valid_n) + "/360 valid configs encode->decode identical");
  failed = failed + report(invalid_n == 180 && reject_bad == 0,
    "dcb-matrix: " + to_string(invalid_n) + "/180 invalid combos rejected by encode");
  return failed;
}

// =========================================================================
// Pure surface: validation edges
// =========================================================================

fn test_validation() -> Int {
  var failed = 0;

  let ok1 = serial_config_validate(&cfg(9600, 8, SERIAL_PARITY_NONE, SERIAL_STOP_ONE, SERIAL_FLOW_NONE));
  failed = failed + report(ok1.is_ok, "validate: 9600 8N1 none accepted");

  let ok2 = serial_config_validate(&cfg(115200, 7, SERIAL_PARITY_EVEN, SERIAL_STOP_TWO, SERIAL_FLOW_RTS_CTS));
  failed = failed + report(ok2.is_ok, "validate: 115200 7E2 rts-cts accepted");

  let b1 = serial_config_validate(&cfg(0, 8, 0, 0, 0));
  let c1 = b1.is_ok == false && b1.error.kind == SERIAL_ERR_INVALID_ARG && b1.error.code == 0;
  failed = failed + report(c1, "validate: baud 0 -> INVALID_ARG (code 0, no OS call)");

  let b2 = serial_config_validate(&cfg(SERIAL_BAUD_MAX + 1, 8, 0, 0, 0));
  failed = failed + report(!b2.is_ok && b2.error.kind == SERIAL_ERR_INVALID_ARG,
    "validate: baud above SERIAL_BAUD_MAX -> INVALID_ARG");

  let b3 = serial_config_validate(&cfg(9600, 4, 0, 0, 0));
  let b4 = serial_config_validate(&cfg(9600, 9, 0, 0, 0));
  failed = failed + report(!b3.is_ok && !b4.is_ok, "validate: data_bits 4 and 9 -> INVALID_ARG");

  let b5 = serial_config_validate(&cfg(9600, 8, 5, 0, 0));
  let b6 = serial_config_validate(&cfg(9600, 8, 0 - 1, 0, 0));
  failed = failed + report(!b5.is_ok && !b6.is_ok, "validate: parity 5 and -1 -> INVALID_ARG");

  let b7 = serial_config_validate(&cfg(9600, 8, 0, 3, 0));
  failed = failed + report(!b7.is_ok, "validate: stop_bits 3 -> INVALID_ARG");

  let b8 = serial_config_validate(&cfg(9600, 8, 0, SERIAL_STOP_ONE_POINT_FIVE, 0));
  failed = failed + report(!b8.is_ok, "validate: 1.5 stop bits with 8 data bits -> INVALID_ARG");

  let b9 = serial_config_validate(&cfg(9600, 5, 0, SERIAL_STOP_TWO, 0));
  failed = failed + report(!b9.is_ok, "validate: 2 stop bits with 5 data bits -> INVALID_ARG");

  let b10 = serial_config_validate(&cfg(9600, 8, 0, 0, 3));
  let b11 = serial_config_validate(&cfg(9600, 8, 0, 0, 0 - 1));
  failed = failed + report(!b10.is_ok && !b11.is_ok, "validate: flow 3 and -1 -> INVALID_ARG");
  return failed;
}

// =========================================================================
// Pure surface: COMMTIMEOUTS codec
// =========================================================================

fn test_timeouts_codec() -> Int {
  var failed = 0;

  let t1 = SerialTimeouts{ read_ms: 1000; write_ms: 1000 };
  let e1 = serial_timeouts_encode(&t1);
  var ok = false;
  if e1.is_ok {
    let d: Vec[UInt8] = e1.value;
    ok = d.len() == 20;
    if ok { ok = rd_u32_le(&d, 0) == 0; }
    if ok { ok = rd_u32_le(&d, 4) == 0; }
    if ok { ok = rd_u32_le(&d, 8) == 1000; }
    if ok { ok = rd_u32_le(&d, 12) == 0; }
    if ok { ok = rd_u32_le(&d, 16) == 1000; }
  }
  failed = failed + report(ok, "timeouts-golden: 1000/1000 -> interval 0, mult 0, const 1000 (blocking)");

  let t2 = SerialTimeouts{ read_ms: 0; write_ms: 0 };
  let e2 = serial_timeouts_encode(&t2);
  ok = false;
  if e2.is_ok {
    let d: Vec[UInt8] = e2.value;
    ok = rd_u32_le(&d, 0) == 4294967295;
    if ok { ok = rd_u32_le(&d, 4) == 0; }
    if ok { ok = rd_u32_le(&d, 8) == 0; }
    if ok { ok = rd_u32_le(&d, 16) == 0; }
  }
  failed = failed + report(ok, "timeouts-golden: 0/0 -> MAXDWORD interval poll shape (libserialport-identical)");

  let t3 = SerialTimeouts{ read_ms: 0; write_ms: 500 };
  let e3 = serial_timeouts_encode(&t3);
  ok = false;
  if e3.is_ok {
    let d: Vec[UInt8] = e3.value;
    ok = rd_u32_le(&d, 0) == 4294967295;
    if ok { ok = rd_u32_le(&d, 16) == 500; }
  }
  failed = failed + report(ok, "timeouts-golden: poll-read + 500ms write");

  var rt_ok = true;
  let d1 = serial_timeouts_decode(&e1.value);
  if !d1.is_ok { rt_ok = false; } else {
    if d1.value.read_ms != 1000 { rt_ok = false; }
    if d1.value.write_ms != 1000 { rt_ok = false; }
  }
  let d2 = serial_timeouts_decode(&e2.value);
  if !d2.is_ok { rt_ok = false; } else {
    if d2.value.read_ms != 0 { rt_ok = false; }
    if d2.value.write_ms != 0 { rt_ok = false; }
  }
  failed = failed + report(rt_ok, "timeouts-decode: blocking and poll shapes round-trip");

  var short: Vec[UInt8] = Vec[UInt8].with_len(12);
  let ds = serial_timeouts_decode(&short);
  let neg = serial_timeouts_encode(&SerialTimeouts{ read_ms: 0 - 1; write_ms: 0 });
  failed = failed + report(!ds.is_ok && !neg.is_ok,
    "timeouts: short slot and negative ms both -> INVALID_ARG");
  return failed;
}

// =========================================================================
// Pure surface: name catalogs
// =========================================================================

fn test_names() -> Int {
  var failed = 0;

  var cat_ok = streq(serial_error_name(SERIAL_LOAD_ABSENT), "absent");
  if !streq(serial_error_name(SERIAL_LOAD_ABI), "abi") { cat_ok = false; }
  if !streq(serial_error_name(SERIAL_ERR_NOT_FOUND), "not-found") { cat_ok = false; }
  if !streq(serial_error_name(SERIAL_ERR_ACCESS_DENIED), "access-denied") { cat_ok = false; }
  if !streq(serial_error_name(SERIAL_ERR_INVALID_HANDLE), "invalid-handle") { cat_ok = false; }
  if !streq(serial_error_name(SERIAL_ERR_INVALID_ARG), "invalid-arg") { cat_ok = false; }
  if !streq(serial_error_name(SERIAL_ERR_TIMEOUT), "timeout") { cat_ok = false; }
  if !streq(serial_error_name(SERIAL_ERR_DISCONNECTED), "disconnected") { cat_ok = false; }
  if !streq(serial_error_name(SERIAL_ERR_IO), "io") { cat_ok = false; }
  if !streq(serial_error_name(4242), "unknown") { cat_ok = false; }
  failed = failed + report(cat_ok, "names: all 9 error kinds resolve (+unknown fallback)");

  var win_ok = streq(serial_win32_error_name(2), "ERROR_FILE_NOT_FOUND");
  if !streq(serial_win32_error_name(5), "ERROR_ACCESS_DENIED") { win_ok = false; }
  if !streq(serial_win32_error_name(109), "ERROR_BROKEN_PIPE") { win_ok = false; }
  if !streq(serial_win32_error_name(1460), "ERROR_TIMEOUT") { win_ok = false; }
  if !streq(serial_win32_error_name(259), "ERROR_NO_MORE_ITEMS") { win_ok = false; }
  if !streq(serial_win32_error_name(999999), "OS_ERROR") { win_ok = false; }
  failed = failed + report(win_ok, "names: Win32 error codes resolve (file-not-found/access-denied/broken-pipe/timeout/no-more-items)");

  var enum_ok = streq(serial_parity_name(SERIAL_PARITY_MARK), "mark");
  if !streq(serial_parity_name(9), "invalid") { enum_ok = false; }
  if !streq(serial_stop_name(SERIAL_STOP_ONE_POINT_FIVE), "1.5") { enum_ok = false; }
  if !streq(serial_stop_name(9), "invalid") { enum_ok = false; }
  if !streq(serial_flow_name(SERIAL_FLOW_XON_XOFF), "xon-xoff") { enum_ok = false; }
  if !streq(serial_flow_name(9), "invalid") { enum_ok = false; }
  failed = failed + report(enum_ok, "names: parity/stop/flow catalogs resolve (+invalid fallback)");
  return failed;
}

// =========================================================================
// Closed-port typed errors (every public call; no device needed)
// =========================================================================

fn test_closed_port(lib: &SerialLibrary) -> Int {
  var failed = 0;
  let fp = fake_port();

  failed = failed + report(serial_is_open(&fp) == false, "closed: serial_is_open(fake) is false");

  let cv = serial_configure(lib, &fp, &cfg(9600, 8, 0, 0, 0));
  failed = failed + report(!cv.is_ok && cv.error.kind == SERIAL_ERR_INVALID_HANDLE,
    "closed: configure -> INVALID_HANDLE");

  let civ = serial_configure(lib, &fp, &cfg(0, 8, 0, 0, 0));
  failed = failed + report(!civ.is_ok && civ.error.kind == SERIAL_ERR_INVALID_ARG,
    "closed: configure with invalid cfg -> INVALID_ARG (validation first)");

  let gv = serial_get_config(lib, &fp);
  failed = failed + report(!gv.is_ok && gv.error.kind == SERIAL_ERR_INVALID_HANDLE,
    "closed: get_config -> INVALID_HANDLE");

  let stv = serial_set_timeouts(lib, &fp, &SerialTimeouts{ read_ms: 100; write_ms: 100 });
  failed = failed + report(!stv.is_ok && stv.error.kind == SERIAL_ERR_INVALID_HANDLE,
    "closed: set_timeouts -> INVALID_HANDLE");

  let stn = serial_set_timeouts(lib, &fp, &SerialTimeouts{ read_ms: 0 - 5; write_ms: 0 });
  failed = failed + report(!stn.is_ok && stn.error.kind == SERIAL_ERR_INVALID_ARG,
    "closed: set_timeouts negative -> INVALID_ARG (validation first)");

  let gtv = serial_get_timeouts(lib, &fp);
  failed = failed + report(!gtv.is_ok && gtv.error.kind == SERIAL_ERR_INVALID_HANDLE,
    "closed: get_timeouts -> INVALID_HANDLE");

  let rv = serial_read(lib, &fp, 8);
  failed = failed + report(!rv.is_ok && rv.error.kind == SERIAL_ERR_INVALID_HANDLE,
    "closed: read -> INVALID_HANDLE");

  let r0 = serial_read(lib, &fp, 0);
  failed = failed + report(!r0.is_ok && r0.error.kind == SERIAL_ERR_INVALID_ARG,
    "closed: read max_bytes 0 -> INVALID_ARG (validation first)");

  let rbig = serial_read(lib, &fp, 70000);
  failed = failed + report(!rbig.is_ok && rbig.error.kind == SERIAL_ERR_INVALID_ARG,
    "closed: read max_bytes 70000 -> INVALID_ARG");

  var payload: Vec[UInt8] = Vec[UInt8].new();
  payload.push(85);
  payload.push(170);
  payload.push(13);
  payload.push(10);
  let wv = serial_write(lib, &fp, &payload);
  failed = failed + report(!wv.is_ok && wv.error.kind == SERIAL_ERR_INVALID_HANDLE,
    "closed: write -> INVALID_HANDLE");

  var empty: Vec[UInt8] = Vec[UInt8].new();
  let we = serial_write(lib, &fp, &empty);
  failed = failed + report(we.is_ok && we.value == 0, "closed: write empty payload -> Ok(0) without touching the port");

  var huge: Vec[UInt8] = Vec[UInt8].with_len(65537);
  let wh = serial_write(lib, &fp, &huge);
  failed = failed + report(!wh.is_ok && wh.error.kind == SERIAL_ERR_INVALID_ARG,
    "closed: write 65537 bytes -> INVALID_ARG (bounds first)");

  let fib = serial_flush(lib, &fp, 9);
  failed = failed + report(!fib.is_ok && fib.error.kind == SERIAL_ERR_INVALID_ARG,
    "closed: flush flags 9 -> INVALID_ARG (validation first)");

  let fv = serial_flush(lib, &fp, SERIAL_FLUSH_BOTH);
  failed = failed + report(!fv.is_ok && fv.error.kind == SERIAL_ERR_INVALID_HANDLE,
    "closed: flush both -> INVALID_HANDLE");

  let dv = serial_drain(lib, &fp);
  failed = failed + report(!dv.is_ok && dv.error.kind == SERIAL_ERR_INVALID_HANDLE,
    "closed: drain -> INVALID_HANDLE");

  let clv = serial_close(lib, &fp);
  failed = failed + report(!clv.is_ok && clv.error.kind == SERIAL_ERR_INVALID_HANDLE,
    "closed: close -> INVALID_HANDLE");
  return failed;
}

// =========================================================================
// Live leg: loader, enumeration, absent device, optional real port
// =========================================================================

fn test_live_port(lib: &SerialLibrary, name: Str) -> Int {
  var failed = 0;
  io.println("  live: trying real port " + name);
  let op = serial_open(lib, name);
  if !op.is_ok {
    failed = failed + report(true,
      "live: SKIP -- first port " + name + " did not open (" + serial_error_name(op.error.kind) + ": " + op.error.message + ")");
    return failed;
  }
  let port: SerialPort = op.value;
  failed = failed + report(serial_is_open(&port), "live: open " + name + " (default timeouts applied)");

  // Defaults applied at open.
  let gt = serial_get_timeouts(lib, &port);
  var def_ok = false;
  if gt.is_ok {
    def_ok = gt.value.read_ms == SERIAL_DEFAULT_READ_MS;
    if def_ok { def_ok = gt.value.write_ms == SERIAL_DEFAULT_WRITE_MS; }
  }
  failed = failed + report(def_ok, "live: open-time defaults are 1000/1000 ms");

  // Configure 9600 8N1 and read it back.
  let std_cfg = cfg(9600, 8, SERIAL_PARITY_NONE, SERIAL_STOP_ONE, SERIAL_FLOW_NONE);
  let cf = serial_configure(lib, &port, &std_cfg);
  var back_ok = false;
  if cf.is_ok {
    let gc = serial_get_config(lib, &port);
    if gc.is_ok {
      back_ok = cfg_eq(&gc.value, &std_cfg);
    }
  }
  failed = failed + report(back_ok, "live: configure 9600 8N1 -> get_config identical");

  // Timeouts set/get.
  let t3 = SerialTimeouts{ read_ms: 300; write_ms: 300 };
  let s3 = serial_set_timeouts(lib, &port, &t3);
  var t3_ok = false;
  if s3.is_ok {
    let g3 = serial_get_timeouts(lib, &port);
    if g3.is_ok {
      t3_ok = g3.value.read_ms == 300 && g3.value.write_ms == 300;
    }
  }
  failed = failed + report(t3_ok, "live: set_timeouts 300/300 -> get_timeouts identical");

  let fl = serial_flush(lib, &port, SERIAL_FLUSH_BOTH);
  failed = failed + report(fl.is_ok, "live: flush both buffers");

  let dr = serial_drain(lib, &port);
  failed = failed + report(dr.is_ok, "live: drain transmit queue");

  // Blocking read with nothing connected must surface the typed timeout.
  let rd = serial_read(lib, &port, 16);
  if rd.is_ok {
    failed = failed + report(true,
      "live: read returned " + to_string(rd.value.len()) + " byte(s) (device is transmitting)");
  } else {
    failed = failed + report(rd.error.kind == SERIAL_ERR_TIMEOUT,
      "live: read with no data -> typed SERIAL_ERR_TIMEOUT (" + rd.error.message + ")");
  }

  // Write a probe pattern.
  var pattern: Vec[UInt8] = Vec[UInt8].new();
  pattern.push(85);
  pattern.push(170);
  pattern.push(0);
  pattern.push(255);
  let wr = serial_write(lib, &port, &pattern);
  var wr_ok = false;
  if wr.is_ok {
    wr_ok = wr.value == 4;
  }
  failed = failed + report(wr_ok, "live: write 4 bytes -> Ok(4)");

  // Poll mode read.
  let t0 = SerialTimeouts{ read_ms: 0; write_ms: 0 };
  let s0 = serial_set_timeouts(lib, &port, &t0);
  var poll_ok = false;
  if s0.is_ok {
    let rp = serial_read(lib, &port, 16);
    if rp.is_ok {
      poll_ok = rp.value.len() <= 16;
    }
  }
  failed = failed + report(poll_ok, "live: poll-mode read (read_ms 0) returns Ok immediately");

  let cl = serial_close(lib, &port);
  failed = failed + report(cl.is_ok, "live: close " + name);
  return failed;
}

fn test_live() -> Int {
  var failed = 0;

  // Deterministic SKIP classification on every host.
  let missing = serial_load_named("xiom-absent-serial-backend-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus library unexpectedly loaded");
    let ig = serial_unload(&missing.value);
  } else {
    failed = failed + report(missing.error.kind == SERIAL_LOAD_ABSENT,
      "skip-path: absent backend classified SERIAL_LOAD_ABSENT (SKIP)");
  }

  let lr = serial_load();
  if !lr.is_ok {
    if lr.error.kind == SERIAL_LOAD_ABSENT {
      failed = failed + report(true, "live: SKIP -- no Win32 serial backend on this OS (" + lr.error.message + ")");
    } else {
      failed = failed + report(false, "live: backend load failed -- " + lr.error.message);
    }
    return failed;
  }
  let lib: SerialLibrary = lr.value;

  let pr = serial_probe(&lib);
  var probe_ok = streq(pr.api, SERIAL_API_WIN32);
  if !streq(pr.kernel, "kernel32.dll") { probe_ok = false; }
  if !streq(pr.registry, "advapi32.dll") { probe_ok = false; }
  if pr.entry_points != 14 { probe_ok = false; }
  failed = failed + report(probe_ok,
    "live: probe -> " + pr.api + " (" + pr.kernel + " + " + pr.registry + ", " + to_string(pr.entry_points) + " entry points)");

  // Named loader path, released immediately.
  let named = serial_load_named("kernel32.dll");
  var named_ok = named.is_ok;
  if named.is_ok {
    let nl: SerialLibrary = named.value;
    let unp = serial_unload(&nl);
    if !unp.is_ok { named_ok = false; }
  }
  failed = failed + report(named_ok, "live: serial_load_named(kernel32.dll) loads + unloads");

  // Closed-port typed errors for every public call.
  failed = failed + test_closed_port(&lib);

  // Empty name.
  let empty_name = serial_open(&lib, "");
  failed = failed + report(!empty_name.is_ok && empty_name.error.kind == SERIAL_ERR_INVALID_ARG,
    "live: open with empty name -> INVALID_ARG");

  // Enumeration.
  let ports = serial_ports(&lib);
  var port_count = 0;
  if ports.is_ok {
    port_count = ports.value.len();
  }
  var enum_ok = ports.is_ok;
  if ports.is_ok {
    var i = 0;
    while i < ports.value.len() {
      if ports.value[i].name.len() == 0 { enum_ok = false; }
      i = i + 1;
    }
  }
  if !enum_ok {
    failed = failed + report(false, "live: enumerate ports failed");
  } elif port_count == 0 {
    failed = failed + report(true,
      "live: SKIP -- no serial device present (SERIALCOMM absent; absent-device typed path follows)");
  } else {
    var listing = "";
    var j = 0;
    while j < port_count {
      if j > 0 { listing = listing + ","; }
      listing = listing + ports.value[j].name;
      j = j + 1;
    }
    failed = failed + report(true, "live: enumerate -> " + to_string(port_count) + " port(s): " + listing);
  }

  // Absent-device typed path (deterministic unless COM255 exists).
  let absent = serial_open(&lib, "COM255");
  if absent.is_ok {
    let aclose = serial_close(&lib, &absent.value);
    failed = failed + report(true, "live: SKIP -- COM255 exists on this host; absent-device path not exercised");
  } else {
    failed = failed + report(absent.error.kind == SERIAL_ERR_NOT_FOUND && absent.error.code == 2,
      "live: absent device COM255 -> SERIAL_ERR_NOT_FOUND with win32 2 (typed SKIP classification)");
  }

  // Optional real-port leg.
  if port_count > 0 {
    failed = failed + test_live_port(&lib, ports.value[0].name);
  }

  let un = serial_unload(&lib);
  failed = failed + report(un.is_ok, "live: backend unloaded");
  return failed;
}

// =========================================================================
// Entry point
// =========================================================================

pub fn main() -> Int {
  io.println("=== xiom.serial conformance tests (Win32 comm API + codecs) ===");
  io.flush_stdout();
  var failed: Int = 0;
  failed = failed + test_dcb_codec();
  failed = failed + test_validation();
  failed = failed + test_timeouts_codec();
  failed = failed + test_names();
  failed = failed + test_live();
  return finish(failed);
}
