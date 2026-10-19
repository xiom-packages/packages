// XIOM -- xiom.firmata conformance tests
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// No hardware and no transport are required. The suite is fixture-driven:
// recorded byte traces under tests/fixtures/*.hex are parsed into byte
// streams, fed to the transport-agnostic session, and decoded. The pure
// encoders are checked against byte goldens (including the concatenated
// host-command stream). A transport is never opened; when a real device is
// absent the suite simply stays on the pure leg (the explicit SKIP note
// "transport: SKIP ..." is reported as a pass, never a failure).
//
// Coverage map: docs/COVERAGE.md lists one or more checks for every public
// function and constant family in the 0.1.0 surface.
//
// Build+run:
//   scripts/port.ps1 -Package xiom.firmata -TimeoutSec 300

module firmata_conformance

use xiom.io;
use xiom.convert;
use xiom.string;
use xiom.string.compare;
use xiom.encoding.hex;
use xiom.firmata;

// =========================================================================
// Harness
// =========================================================================

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

fn finish(failed: Int) -> Int {
  if failed == 0 {
    io.println("xiom.firmata: all tests passed");
  } else {
    io.println("xiom.firmata: tests failed");
  }
  return failed;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_eq(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Hex literal -> bytes (test-side only; empty on a bad literal).
fn hx(s: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(s);
  if r.is_ok {
    return r.value;
  }
  return Vec[UInt8].new();
}

fn is_hex(actual: &Vec[UInt8], expected: Str) -> Bool {
  let want = hx(expected);
  return bytes_eq(actual, &want);
}

fn err_bytes_is(r: Result[Vec[UInt8], FirmataError], kind: Int) -> Bool {
  if r.is_ok {
    return false;
  }
  return r.error.kind == kind;
}

fn err_int_is(r: Result[Int, FirmataError], kind: Int) -> Bool {
  if r.is_ok {
    return false;
  }
  return r.error.kind == kind;
}

fn err_msg_is(r: Result[FirmataMessage, FirmataError], kind: Int) -> Bool {
  if r.is_ok {
    return false;
  }
  return r.error.kind == kind;
}

fn err_bool_is(r: Result[Bool, FirmataError], kind: Int) -> Bool {
  if r.is_ok {
    return false;
  }
  return r.error.kind == kind;
}

fn tail(data: &Vec[UInt8], start: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = start;
  while i < data.len() {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

fn take(data: &Vec[UInt8], n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n && i < data.len() {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// =========================================================================
// Fixtures
// =========================================================================

fn hex_nibble(b: Int) -> Int {
  if b >= 48 && b <= 57 {
    return b - 48;
  }
  if b >= 65 && b <= 70 {
    return b - 55;
  }
  if b >= 97 && b <= 102 {
    return b - 87;
  }
  return -1;
}

// Parse a .hex fixture: hex digit pairs become bytes; '#' starts a comment
// that ends at the next line break; all other characters are ignored.
fn parse_hex(data: &Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  var out = Vec[UInt8].new();
  var hi = -1;
  var in_comment = false;
  var i = 0;
  while i < data.len() {
    let b = (data[i] as Int) & 0xFF;
    if b == 10 || b == 13 {
      in_comment = false;
    } else {
      if !in_comment {
        if b == 35 {
          in_comment = true;
        } else {
          let n = hex_nibble(b);
          if n >= 0 {
            if hi < 0 {
              hi = n;
            } else {
              out.push((hi * 16 + n) as UInt8);
              hi = -1;
            }
          }
        }
      }
    }
    i = i + 1;
  }
  if hi >= 0 {
    return Err("odd hex digit count in fixture");
  }
  return Ok(out);
}

fn load_fixture(name: Str) -> Result[Vec[UInt8], Str] {
  let p1 = "tests/fixtures/" + name;
  let r1 = io.read_file_bytes(p1);
  if r1.is_ok {
    let raw1: Vec[UInt8] = r1.value;
    return parse_hex(&raw1);
  }
  let p2 = "packages/xiom-firmata/tests/fixtures/" + name;
  let r2 = io.read_file_bytes(p2);
  if r2.is_ok {
    let raw2: Vec[UInt8] = r2.value;
    return parse_hex(&raw2);
  }
  return Err("fixture not found: " + name);
}

fn test_fixtures() -> Int {
  var failed = 0;
  let names = Vec[Str].new();
  names.push("handshake.hex");
  names.push("io_reports.hex");
  names.push("strings.hex");
  names.push("host_commands.hex");
  names.push("noise.hex");
  var i = 0;
  while i < names.len() {
    let n: Str = names[i];
    let r = load_fixture(n);
    var ok = r.is_ok;
    if ok {
      let b: Vec[UInt8] = r.value;
      ok = b.len() > 0;
      if !ok {
        why("fixture parsed empty: " + n);
      }
    } else {
      why(r.error);
    }
    failed = failed + report(ok, "fixture: " + n + " parses to a non-empty byte stream");
    i = i + 1;
  }
  return failed;
}

// =========================================================================
// Encoders
// =========================================================================

fn test_encoders() -> Int {
  var failed = 0;
  var ok = false;

  ok = is_hex(&firmata_encode_version_query(), "f9");
  failed = failed + report(ok, "encode: version query -> f9");

  ok = is_hex(&firmata_encode_firmware_query(), "f079f7");
  failed = failed + report(ok, "encode: firmware query -> f0 79 f7");

  let m1 = firmata_encode_set_pin_mode(13, FIRMATA_MODE_OUTPUT);
  ok = false;
  if m1.is_ok {
    ok = is_hex(&m1.value, "f40d01");
  }
  failed = failed + report(ok, "encode: SET_PIN_MODE pin 13 OUTPUT -> f4 0d 01");

  let m2 = firmata_encode_set_pin_mode(14, FIRMATA_MODE_ANALOG);
  ok = false;
  if m2.is_ok {
    ok = is_hex(&m2.value, "f40e02");
  }
  failed = failed + report(ok, "encode: SET_PIN_MODE pin 14 ANALOG -> f4 0e 02");

  let m3 = firmata_encode_set_pin_mode(9, FIRMATA_MODE_PWM);
  ok = false;
  if m3.is_ok {
    ok = is_hex(&m3.value, "f40903");
  }
  failed = failed + report(ok, "encode: SET_PIN_MODE pin 9 PWM -> f4 09 03");

  failed = failed + report(err_bytes_is(firmata_encode_set_pin_mode(128, 1), FIRMATA_ERR_OUT_OF_RANGE), "encode: SET_PIN_MODE pin 128 rejected (OUT_OF_RANGE)");
  failed = failed + report(err_bytes_is(firmata_encode_set_pin_mode(1, 128), FIRMATA_ERR_OUT_OF_RANGE), "encode: SET_PIN_MODE mode 128 rejected (OUT_OF_RANGE)");
  failed = failed + report(err_bytes_is(firmata_encode_set_pin_mode(-1, 1), FIRMATA_ERR_OUT_OF_RANGE), "encode: SET_PIN_MODE negative pin rejected");

  let d1 = firmata_encode_digital_write(13, true);
  ok = false;
  if d1.is_ok {
    ok = is_hex(&d1.value, "f50d01");
  }
  failed = failed + report(ok, "encode: SET_DIGITAL_PIN_VALUE pin 13 HIGH -> f5 0d 01");

  let d2 = firmata_encode_digital_write(0, false);
  ok = false;
  if d2.is_ok {
    ok = is_hex(&d2.value, "f50000");
  }
  failed = failed + report(ok, "encode: SET_DIGITAL_PIN_VALUE pin 0 LOW -> f5 00 00");
  failed = failed + report(err_bytes_is(firmata_encode_digital_write(128, true), FIRMATA_ERR_OUT_OF_RANGE), "encode: SET_DIGITAL_PIN_VALUE pin 128 rejected");

  let p1 = firmata_encode_digital_port_write(1, 0x2A);
  ok = false;
  if p1.is_ok {
    ok = is_hex(&p1.value, "912a00");
  }
  failed = failed + report(ok, "encode: DIGITAL_MESSAGE port 1 mask 0x2A -> 91 2a 00");

  let p2 = firmata_encode_digital_port_write(0, FIRMATA_MAX_14BIT);
  ok = false;
  if p2.is_ok {
    ok = is_hex(&p2.value, "907f7f");
  }
  failed = failed + report(ok, "encode: DIGITAL_MESSAGE port 0 mask 16383 -> 90 7f 7f");
  failed = failed + report(err_bytes_is(firmata_encode_digital_port_write(16, 0), FIRMATA_ERR_OUT_OF_RANGE), "encode: DIGITAL_MESSAGE port 16 rejected");
  failed = failed + report(err_bytes_is(firmata_encode_digital_port_write(0, 16384), FIRMATA_ERR_OUT_OF_RANGE), "encode: DIGITAL_MESSAGE mask 16384 rejected");

  let w1 = firmata_encode_pwm_write(9, 1023);
  ok = false;
  if w1.is_ok {
    ok = is_hex(&w1.value, "e97f07");
  }
  failed = failed + report(ok, "encode: PWM pin 9 value 1023 -> e9 7f 07");

  let w2 = firmata_encode_pwm_write(15, FIRMATA_MAX_14BIT);
  ok = false;
  if w2.is_ok {
    ok = is_hex(&w2.value, "ef7f7f");
  }
  failed = failed + report(ok, "encode: PWM pin 15 value 16383 -> ef 7f 7f");
  failed = failed + report(err_bytes_is(firmata_encode_pwm_write(16, 0), FIRMATA_ERR_OUT_OF_RANGE), "encode: PWM pin 16 rejected");
  failed = failed + report(err_bytes_is(firmata_encode_pwm_write(9, 16384), FIRMATA_ERR_OUT_OF_RANGE), "encode: PWM value 16384 rejected");

  let a1 = firmata_encode_analog_report(0, true);
  ok = false;
  if a1.is_ok {
    ok = is_hex(&a1.value, "c001");
  }
  failed = failed + report(ok, "encode: REPORT_ANALOG channel 0 enable -> c0 01");

  let a2 = firmata_encode_analog_report(15, false);
  ok = false;
  if a2.is_ok {
    ok = is_hex(&a2.value, "cf00");
  }
  failed = failed + report(ok, "encode: REPORT_ANALOG channel 15 disable -> cf 00");
  failed = failed + report(err_bytes_is(firmata_encode_analog_report(16, true), FIRMATA_ERR_OUT_OF_RANGE), "encode: REPORT_ANALOG channel 16 rejected");

  let r1 = firmata_encode_digital_report(1, true);
  ok = false;
  if r1.is_ok {
    ok = is_hex(&r1.value, "d101");
  }
  failed = failed + report(ok, "encode: REPORT_DIGITAL port 1 enable -> d1 01");

  let r2 = firmata_encode_digital_report(15, false);
  ok = false;
  if r2.is_ok {
    ok = is_hex(&r2.value, "df00");
  }
  failed = failed + report(ok, "encode: REPORT_DIGITAL port 15 disable -> df 00");
  failed = failed + report(err_bytes_is(firmata_encode_digital_report(16, true), FIRMATA_ERR_OUT_OF_RANGE), "encode: REPORT_DIGITAL port 16 rejected");

  ok = is_hex(&firmata_encode_system_reset(), "ff");
  failed = failed + report(ok, "encode: SYSTEM_RESET -> ff");

  // Golden concatenation: the same sequence recorded in host_commands.hex.
  var stream = Vec[UInt8].new();
  let e1 = firmata_encode_version_query();
  stream.extend(&e1);
  let e2 = firmata_encode_firmware_query();
  stream.extend(&e2);
  let e3 = firmata_encode_set_pin_mode(13, FIRMATA_MODE_OUTPUT);
  if e3.is_ok { let b: Vec[UInt8] = e3.value; stream.extend(&b); }
  let e4 = firmata_encode_set_pin_mode(14, FIRMATA_MODE_ANALOG);
  if e4.is_ok { let b: Vec<UInt8> = e4.value; stream.extend(&b); }
  let e5 = firmata_encode_set_pin_mode(9, FIRMATA_MODE_PWM);
  if e5.is_ok { let b: Vec<UInt8> = e5.value; stream.extend(&b); }
  let e6 = firmata_encode_digital_write(13, true);
  if e6.is_ok { let b: Vec<UInt8> = e6.value; stream.extend(&b); }
  let e7 = firmata_encode_digital_write(0, false);
  if e7.is_ok { let b: Vec<UInt8> = e7.value; stream.extend(&b); }
  let e8 = firmata_encode_digital_port_write(1, 0x2A);
  if e8.is_ok { let b: Vec<UInt8> = e8.value; stream.extend(&b); }
  let e9 = firmata_encode_pwm_write(9, 1023);
  if e9.is_ok { let b: Vec<UInt8> = e9.value; stream.extend(&b); }
  let e10 = firmata_encode_pwm_write(15, 16383);
  if e10.is_ok { let b: Vec<UInt8> = e10.value; stream.extend(&b); }
  let e11 = firmata_encode_analog_report(0, true);
  if e11.is_ok { let b: Vec<UInt8> = e11.value; stream.extend(&b); }
  let e12 = firmata_encode_analog_report(15, false);
  if e12.is_ok { let b: Vec<UInt8> = e12.value; stream.extend(&b); }
  let e13 = firmata_encode_digital_report(1, true);
  if e13.is_ok { let b: Vec<UInt8> = e13.value; stream.extend(&b); }
  let e14 = firmata_encode_digital_report(15, false);
  if e14.is_ok { let b: Vec<UInt8> = e14.value; stream.extend(&b); }
  let e15 = firmata_encode_system_reset();
  stream.extend(&e15);

  let gf = load_fixture("host_commands.hex");
  ok = false;
  if gf.is_ok {
    let want: Vec[UInt8] = gf.value;
    ok = bytes_eq(&stream, &want);
    if !ok {
      why("host command stream length " + to_string(stream.len()) + " != fixture " + to_string(want.len()));
    }
  } else {
    why(gf.error);
  }
  failed = failed + report(ok, "encode: full host command stream matches the recorded golden fixture");

  return failed;
}

// =========================================================================
// Framing
// =========================================================================

fn test_frame_len() -> Int {
  var failed = 0;
  var ok = false;

  let v = hx("f90205");
  let lr = firmata_frame_len(&v);
  ok = lr.is_ok;
  if ok {
    ok = lr.value == 3;
  }
  failed = failed + report(ok, "frame_len: version report -> 3");

  let d = hx("910100");
  let lr2 = firmata_frame_len(&d);
  ok = lr2.is_ok;
  if ok {
    ok = lr2.value == 3;
  }
  failed = failed + report(ok, "frame_len: digital report -> 3");

  let a = hx("e00000");
  let lr3 = firmata_frame_len(&a);
  ok = lr3.is_ok;
  if ok {
    ok = lr3.value == 3;
  }
  failed = failed + report(ok, "frame_len: analog report -> 3");

  let pm = hx("f40d01");
  let lr4 = firmata_frame_len(&pm);
  ok = lr4.is_ok;
  if ok {
    ok = lr4.value == 3;
  }
  failed = failed + report(ok, "frame_len: SET_PIN_MODE -> 3");

  let pv = hx("f50d01");
  let lr5 = firmata_frame_len(&pv);
  ok = lr5.is_ok;
  if ok {
    ok = lr5.value == 3;
  }
  failed = failed + report(ok, "frame_len: SET_DIGITAL_PIN_VALUE -> 3");

  let ra = hx("c001");
  let lr6 = firmata_frame_len(&ra);
  ok = lr6.is_ok;
  if ok {
    ok = lr6.value == 2;
  }
  failed = failed + report(ok, "frame_len: REPORT_ANALOG -> 2");

  let rd = hx("d101");
  let lr7 = firmata_frame_len(&rd);
  ok = lr7.is_ok;
  if ok {
    ok = lr7.value == 2;
  }
  failed = failed + report(ok, "frame_len: REPORT_DIGITAL -> 2");

  let sr = hx("ff");
  let lr8 = firmata_frame_len(&sr);
  ok = lr8.is_ok;
  if ok {
    ok = lr8.value == 1;
  }
  failed = failed + report(ok, "frame_len: SYSTEM_RESET -> 1");

  let rt = hx("f8");
  let lr9 = firmata_frame_len(&rt);
  ok = lr9.is_ok;
  if ok {
    ok = lr9.value == 1;
  }
  failed = failed + report(ok, "frame_len: MIDI realtime clock -> 1 (Other)");

  let shortv = hx("f902");
  let lrs = firmata_frame_len(&shortv);
  ok = lrs.is_ok;
  if ok {
    ok = lrs.value == 0;
  }
  failed = failed + report(ok, "frame_len: short version report -> 0 (need more)");

  let empty = Vec[UInt8].new();
  let lre = firmata_frame_len(&empty);
  ok = lre.is_ok;
  if ok {
    ok = lre.value == 0;
  }
  failed = failed + report(ok, "frame_len: empty buffer -> 0 (need more)");

  let sy = hx("f0790205");
  let lry = firmata_frame_len(&sy);
  ok = lry.is_ok;
  if ok {
    ok = lry.value == 0;
  }
  failed = failed + report(ok, "frame_len: unterminated sysex -> 0 (need more)");

  let sy2 = hx("f0790205f7");
  let lry2 = firmata_frame_len(&sy2);
  ok = lry2.is_ok;
  if ok {
    ok = lry2.value == 5;
  }
  failed = failed + report(ok, "frame_len: terminated sysex -> 5");

  failed = failed + report(err_int_is(firmata_frame_len(&hx("00")), FIRMATA_ERR_BAD_STATUS), "frame_len: data byte 0x00 as status -> BAD_STATUS");
  failed = failed + report(err_int_is(firmata_frame_len(&hx("80")), FIRMATA_ERR_BAD_STATUS), "frame_len: status 0x80 (MIDI note-off) -> BAD_STATUS");
  failed = failed + report(err_int_is(firmata_frame_len(&hx("f07902f9")), FIRMATA_ERR_BAD_SYSEX), "frame_len: sysex interrupted by 0xF9 -> BAD_SYSEX");

  return failed;
}

// =========================================================================
// Decode
// =========================================================================

fn test_decode_handshake() -> Int {
  var failed = 0;
  var ok = false;
  let fr = load_fixture("handshake.hex");
  if !fr.is_ok {
    why(fr.error);
    return report(false, "decode: handshake fixture");
  }
  let stream: Vec[UInt8] = fr.value;

  // Frame 0: version.
  let lr = firmata_frame_len(&stream);
  var n = 0;
  if lr.is_ok {
    n = lr.value;
  }
  let f0 = take(&stream, n);
  let d0 = firmata_decode_frame(&f0);
  ok = false;
  if d0.is_ok {
    match d0.value {
      Version(v) => { ok = v.major == 2 && v.minor == 5; }
      _ => { ok = false; }
    }
  }
  failed = failed + report(ok, "decode: REPORT_VERSION -> 2.5");

  // Frame 1: firmware.
  let rest = tail(&stream, n);
  let lr2 = firmata_frame_len(&rest);
  var n2 = 0;
  if lr2.is_ok {
    n2 = lr2.value;
  }
  let f1 = take(&rest, n2);
  let d1 = firmata_decode_frame(&f1);
  ok = false;
  if d1.is_ok {
    match d1.value {
      Firmware(f) => {
        ok = f.major == 2 && f.minor == 5 && str_eq(f.name, "StandardFirmata");
        if !ok {
          why("firmware name/version mismatch: " + to_string(f.major) + "." + to_string(f.minor) + " " + f.name);
        }
      }
      _ => { ok = false; }
    }
  }
  failed = failed + report(ok, "decode: REPORT_FIRMWARE -> 2.5 StandardFirmata");

  // Specific decoders on the same bytes.
  let vd = firmata_decode_version_message(&f0);
  ok = false;
  if vd.is_ok {
    ok = vd.value.major == 2 && vd.value.minor == 5;
  }
  failed = failed + report(ok, "decode_version_message: returns the version struct");

  let fd = firmata_decode_firmware_message(&f1);
  ok = false;
  if fd.is_ok {
    ok = str_eq(fd.value.name, "StandardFirmata");
  }
  failed = failed + report(ok, "decode_firmware_message: returns the firmware struct");

  return failed;
}

fn test_decode_io() -> Int {
  var failed = 0;
  var ok = false;
  let fr = load_fixture("io_reports.hex");
  if !fr.is_ok {
    why(fr.error);
    return report(false, "decode: io_reports fixture");
  }
  let stream: Vec[UInt8] = fr.value;

  // Frame 0: digital port 0, pin 0 high.
  let lr = firmata_frame_len(&stream);
  var n = 0;
  if lr.is_ok { n = lr.value; }
  let f0 = take(&stream, n);
  let d0 = firmata_decode_digital_message(&f0);
  ok = false;
  if d0.is_ok {
    ok = d0.value.port == 0 && d0.value.mask == 1;
  }
  failed = failed + report(ok, "decode_digital_message: port 0 mask 1");

  // Frame 1: digital port 1, pin 13 high (mask 0x20).
  let rest1 = tail(&stream, n);
  let lr1 = firmata_frame_len(&rest1);
  var n1 = 0;
  if lr1.is_ok { n1 = lr1.value; }
  let f1 = take(&rest1, n1);
  let d1 = firmata_decode_frame(&f1);
  ok = false;
  if d1.is_ok {
    match d1.value {
      Digital(d) => { ok = d.port == 1 && d.mask == 0x20; }
      _ => { ok = false; }
    }
  }
  failed = failed + report(ok, "decode: DIGITAL_MESSAGE port 1 mask 0x20 (pin 13)");

  // Frame 2: digital port 15, mask 3 (high group bits preserved).
  let rest2 = tail(&rest1, n1);
  let lr2 = firmata_frame_len(&rest2);
  var n2 = 0;
  if lr2.is_ok { n2 = lr2.value; }
  let f2 = take(&rest2, n2);
  let d2 = firmata_decode_frame(&f2);
  ok = false;
  if d2.is_ok {
    match d2.value {
      Digital(d) => { ok = d.port == 15 && d.mask == 3; }
      _ => { ok = false; }
    }
  }
  failed = failed + report(ok, "decode: DIGITAL_MESSAGE port 15 mask 3");

  // Frame 3: analog channel 0 = 42.
  let rest3 = tail(&rest2, n2);
  let lr3 = firmata_frame_len(&rest3);
  var n3 = 0;
  if lr3.is_ok { n3 = lr3.value; }
  let f3 = take(&rest3, n3);
  let a0 = firmata_decode_analog_message(&f3);
  ok = false;
  if a0.is_ok {
    ok = a0.value.channel == 0 && a0.value.value == 42;
  }
  failed = failed + report(ok, "decode_analog_message: channel 0 = 42");

  // Frame 4: analog channel 1 = 1023.
  let rest4 = tail(&rest3, n3);
  let lr4 = firmata_frame_len(&rest4);
  var n4 = 0;
  if lr4.is_ok { n4 = lr4.value; }
  let f4 = take(&rest4, n4);
  let d4 = firmata_decode_frame(&f4);
  ok = false;
  if d4.is_ok {
    match d4.value {
      Analog(a) => { ok = a.channel == 1 && a.value == 1023; }
      _ => { ok = false; }
    }
  }
  failed = failed + report(ok, "decode: ANALOG_MESSAGE channel 1 = 1023 (7-bit pair)");

  // Frame 5: analog channel 2 = 1024.
  let rest5 = tail(&rest4, n4);
  let lr5 = firmata_frame_len(&rest5);
  var n5 = 0;
  if lr5.is_ok { n5 = lr5.value; }
  let f5 = take(&rest5, n5);
  let d5 = firmata_decode_frame(&f5);
  ok = false;
  if d5.is_ok {
    match d5.value {
      Analog(a) => { ok = a.channel == 2 && a.value == 1024; }
      _ => { ok = false; }
    }
  }
  failed = failed + report(ok, "decode: ANALOG_MESSAGE channel 2 = 1024 (msb group)");

  // Frame 6: report analog channel 3 enabled.
  let rest6 = tail(&rest5, n5);
  let lr6 = firmata_frame_len(&rest6);
  var n6 = 0;
  if lr6.is_ok { n6 = lr6.value; }
  let f6 = take(&rest6, n6);
  let d6 = firmata_decode_frame(&f6);
  ok = false;
  if d6.is_ok {
    match d6.value {
      ReportAnalog(r) => { ok = r.channel == 3 && r.enabled; }
      _ => { ok = false; }
    }
  }
  failed = failed + report(ok, "decode: REPORT_ANALOG channel 3 enabled");

  // Frame 7: report digital port 2 disabled.
  let rest7 = tail(&rest6, n6);
  let lr7 = firmata_frame_len(&rest7);
  var n7 = 0;
  if lr7.is_ok { n7 = lr7.value; }
  let f7 = take(&rest7, n7);
  let d7 = firmata_decode_frame(&f7);
  ok = false;
  if d7.is_ok {
    match d7.value {
      ReportDigital(r) => { ok = r.channel == 2 && !r.enabled; }
      _ => { ok = false; }
    }
  }
  failed = failed + report(ok, "decode: REPORT_DIGITAL port 2 disabled");

  // Frame 8: set pin mode 13 OUTPUT.
  let rest8 = tail(&rest7, n7);
  let lr8 = firmata_frame_len(&rest8);
  var n8 = 0;
  if lr8.is_ok { n8 = lr8.value; }
  let f8 = take(&rest8, n8);
  let d8 = firmata_decode_frame(&f8);
  ok = false;
  if d8.is_ok {
    match d8.value {
      SetPinMode(pm) => { ok = pm.pin == 13 && pm.mode == FIRMATA_MODE_OUTPUT; }
      _ => { ok = false; }
    }
  }
  failed = failed + report(ok, "decode: SET_PIN_MODE pin 13 OUTPUT");

  // Frame 9: set digital pin 13 HIGH.
  let rest9 = tail(&rest8, n8);
  let lr9 = firmata_frame_len(&rest9);
  var n9 = 0;
  if lr9.is_ok { n9 = lr9.value; }
  let f9 = take(&rest9, n9);
  let d9 = firmata_decode_frame(&f9);
  ok = false;
  if d9.is_ok {
    match d9.value {
      SetDigitalPin(pv) => { ok = pv.pin == 13 && pv.value == 1; }
      _ => { ok = false; }
    }
  }
  failed = failed + report(ok, "decode: SET_DIGITAL_PIN_VALUE pin 13 HIGH");

  // Frame 10: system reset.
  let rest10 = tail(&rest9, n9);
  let lr10 = firmata_frame_len(&rest10);
  var n10 = 0;
  if lr10.is_ok { n10 = lr10.value; }
  let f10 = take(&rest10, n10);
  let d10 = firmata_decode_frame(&f10);
  ok = false;
  if d10.is_ok {
    match d10.value {
      SystemReset => { ok = true; }
      _ => { ok = false; }
    }
  }
  failed = failed + report(ok, "decode: SYSTEM_RESET");

  // Frame 11: MIDI clock -> Other.
  let rest11 = tail(&rest10, n10);
  let lr11 = firmata_frame_len(&rest11);
  var n11 = 0;
  if lr11.is_ok { n11 = lr11.value; }
  let f11 = take(&rest11, n11);
  let d11 = firmata_decode_frame(&f11);
  ok = false;
  if d11.is_ok {
    match d11.value {
      Other(o) => { ok = o.command == 0xF8 && o.length == 1; }
      _ => { ok = false; }
    }
  }
  failed = failed + report(ok, "decode: MIDI realtime 0xF8 -> Other(1)");

  // Frame 12: capability query -> Other sysex id 0x6B.
  let rest12 = tail(&rest11, n11);
  let lr12 = firmata_frame_len(&rest12);
  var n12 = 0;
  if lr12.is_ok { n12 = lr12.value; }
  let f12 = take(&rest12, n12);
  let d12 = firmata_decode_frame(&f12);
  ok = false;
  if d12.is_ok {
    match d12.value {
      Other(o) => { ok = o.command == 0x6B && o.length == 0; }
      _ => { ok = false; }
    }
  }
  failed = failed + report(ok, "decode: CAPABILITY_QUERY sysex -> Other(0x6B, 0)");

  let total = stream.len();
  let consumed = n + n1 + n2 + n3 + n4 + n5 + n6 + n7 + n8 + n9 + n10 + n11 + n12;
  failed = failed + report(consumed == total, "decode: io_reports trace consumed exactly (" + to_string(consumed) + "/" + to_string(total) + " bytes)");

  return failed;
}

fn test_decode_strings() -> Int {
  var failed = 0;
  var ok = false;
  let fr = load_fixture("strings.hex");
  if !fr.is_ok {
    why(fr.error);
    return report(false, "decode: strings fixture");
  }
  let stream: Vec[UInt8] = fr.value;

  let lr = firmata_frame_len(&stream);
  var n = 0;
  if lr.is_ok { n = lr.value; }
  let f0 = take(&stream, n);
  let s0 = firmata_decode_string_message(&f0);
  ok = false;
  if s0.is_ok {
    ok = str_eq(s0.value, "READY");
    if !ok { why("got: " + s0.value); }
  }
  failed = failed + report(ok, "decode_string_message: \"READY\"");

  let rest1 = tail(&stream, n);
  let lr1 = firmata_frame_len(&rest1);
  var n1 = 0;
  if lr1.is_ok { n1 = lr1.value; }
  let f1 = take(&rest1, n1);
  let s1 = firmata_decode_string_message(&f1);
  ok = false;
  if s1.is_ok {
    ok = str_eq(s1.value, "é");
    if !ok { why("got: " + s1.value); }
  }
  failed = failed + report(ok, "decode_string_message: 14-bit U+00E9 -> UTF-8 two-byte sequence");

  let rest2 = tail(&rest1, n1);
  let lr2 = firmata_frame_len(&rest2);
  var n2 = 0;
  if lr2.is_ok { n2 = lr2.value; }
  let f2 = take(&rest2, n2);
  let s2 = firmata_decode_string_message(&f2);
  ok = false;
  if s2.is_ok {
    ok = str_eq(s2.value, "A");
    if !ok { why("got: " + s2.value); }
  }
  failed = failed + report(ok, "decode_string_message: NUL terminates (\"A\\0B\" -> \"A\")");

  let rest3 = tail(&rest2, n2);
  let lr3 = firmata_frame_len(&rest3);
  var n3 = 0;
  if lr3.is_ok { n3 = lr3.value; }
  let f3 = take(&rest3, n3);
  let s3 = firmata_decode_string_message(&f3);
  ok = false;
  if s3.is_ok {
    ok = s3.value.len() == 0;
  }
  failed = failed + report(ok, "decode_string_message: empty payload -> empty string");

  return failed;
}

fn test_decode_errors() -> Int {
  var failed = 0;

  failed = failed + report(err_msg_is(firmata_decode_frame(&hx("f902")), FIRMATA_ERR_TRUNCATED), "decode: short version frame -> TRUNCATED");
  failed = failed + report(err_msg_is(firmata_decode_frame(&hx("f9020500")), FIRMATA_ERR_INVALID_ARG), "decode: trailing byte after version -> INVALID_ARG");
  failed = failed + report(err_msg_is(firmata_decode_frame(&hx("f40d80")), FIRMATA_ERR_BAD_STATUS), "decode: status byte inside a fixed frame -> BAD_STATUS");
  failed = failed + report(err_msg_is(firmata_decode_frame(&hx("f50d02")), FIRMATA_ERR_OUT_OF_RANGE), "decode: SET_DIGITAL_PIN_VALUE 2 -> OUT_OF_RANGE");
  failed = failed + report(err_msg_is(firmata_decode_frame(&hx("f0f7")), FIRMATA_ERR_BAD_SYSEX), "decode: empty sysex -> BAD_SYSEX");
  failed = failed + report(err_msg_is(firmata_decode_frame(&hx("f07902f7")), FIRMATA_ERR_BAD_SYSEX), "decode: firmware report with 1 payload byte -> BAD_SYSEX");
  failed = failed + report(err_msg_is(firmata_decode_frame(&hx("f0790205530074f7")), FIRMATA_ERR_BAD_STRING), "decode: firmware name with odd 7-bit length -> BAD_STRING");
  failed = failed + report(err_msg_is(firmata_decode_frame(&hx("f071410042f7")), FIRMATA_ERR_BAD_STRING), "decode: string with odd 7-bit length -> BAD_STRING");
  failed = failed + report(err_msg_is(firmata_decode_frame(&hx("00")), FIRMATA_ERR_BAD_STATUS), "decode: data byte as status -> BAD_STATUS");

  // Firmware query (zero payload) is a well-framed Other, not a firmware report.
  let fq = firmata_decode_frame(&hx("f079f7"));
  var ok = false;
  if fq.is_ok {
    match fq.value {
      Other(o) => { ok = o.command == 0x79 && o.length == 0; }
      _ => { ok = false; }
    }
  }
  failed = failed + report(ok, "decode: firmware query (no payload) -> Other(0x79, 0)");

  // Specific decoders reject the wrong well-formed type.
  let wrong = firmata_decode_version_message(&hx("e00000"));
  ok = false;
  if !wrong.is_ok {
    ok = wrong.error.kind == FIRMATA_ERR_UNSUPPORTED;
  }
  failed = failed + report(ok, "decode_version_message: analog frame -> UNSUPPORTED");

  let wrong2 = firmata_decode_digital_message(&hx("f90205"));
  ok = false;
  if !wrong2.is_ok {
    ok = wrong2.error.kind == FIRMATA_ERR_UNSUPPORTED;
  }
  failed = failed + report(ok, "decode_digital_message: version frame -> UNSUPPORTED");

  let wrong3 = firmata_decode_analog_message(&hx("910100"));
  ok = false;
  if !wrong3.is_ok {
    ok = wrong3.error.kind == FIRMATA_ERR_UNSUPPORTED;
  }
  failed = failed + report(ok, "decode_analog_message: digital frame -> UNSUPPORTED");

  let wrong4 = firmata_decode_string_message(&hx("f90205"));
  ok = false;
  if !wrong4.is_ok {
    ok = wrong4.error.kind == FIRMATA_ERR_UNSUPPORTED;
  }
  failed = failed + report(ok, "decode_string_message: version frame -> UNSUPPORTED");

  let wrong5 = firmata_decode_firmware_message(&hx("f90205"));
  ok = false;
  if !wrong5.is_ok {
    ok = wrong5.error.kind == FIRMATA_ERR_UNSUPPORTED;
  }
  failed = failed + report(ok, "decode_firmware_message: version frame -> UNSUPPORTED");

  return failed;
}

// =========================================================================
// Helpers and catalogs
// =========================================================================

fn test_helpers() -> Int {
  var failed = 0;
  var ok = false;

  let m1 = firmata_digital_mask_pin(0x2A, 1);
  ok = m1.is_ok;
  if ok { ok = m1.value; }
  failed = failed + report(ok, "digital_mask_pin: mask 0x2A bit 1 set");

  let m2 = firmata_digital_mask_pin(0x2A, 0);
  ok = m2.is_ok;
  if ok { ok = !m2.value; }
  failed = failed + report(ok, "digital_mask_pin: mask 0x2A bit 0 clear");

  let m3 = firmata_digital_mask_pin(0x2A, 5);
  ok = m3.is_ok;
  if ok { ok = m3.value; }
  failed = failed + report(ok, "digital_mask_pin: mask 0x2A bit 5 set");

  let m4 = firmata_digital_mask_pin(0x2A, 13);
  ok = m4.is_ok;
  if ok { ok = !m4.value; }
  failed = failed + report(ok, "digital_mask_pin: mask 0x2A bit 13 clear");

  failed = failed + report(err_bool_is(firmata_digital_mask_pin(16384, 0), FIRMATA_ERR_OUT_OF_RANGE), "digital_mask_pin: mask 16384 rejected");
  failed = failed + report(err_bool_is(firmata_digital_mask_pin(0, 14), FIRMATA_ERR_OUT_OF_RANGE), "digital_mask_pin: bit 14 rejected");
  failed = failed + report(err_bool_is(firmata_digital_mask_pin(0, -1), FIRMATA_ERR_OUT_OF_RANGE), "digital_mask_pin: negative bit rejected");

  // Error-kind catalog (one check for the whole catalog).
  var names_ok = true;
  if !str_eq(firmata_error_name(FIRMATA_ERR_INVALID_ARG), "INVALID_ARG") { names_ok = false; }
  if !str_eq(firmata_error_name(FIRMATA_ERR_OUT_OF_RANGE), "OUT_OF_RANGE") { names_ok = false; }
  if !str_eq(firmata_error_name(FIRMATA_ERR_TRUNCATED), "TRUNCATED") { names_ok = false; }
  if !str_eq(firmata_error_name(FIRMATA_ERR_BAD_STATUS), "BAD_STATUS") { names_ok = false; }
  if !str_eq(firmata_error_name(FIRMATA_ERR_BAD_SYSEX), "BAD_SYSEX") { names_ok = false; }
  if !str_eq(firmata_error_name(FIRMATA_ERR_BAD_STRING), "BAD_STRING") { names_ok = false; }
  if !str_eq(firmata_error_name(FIRMATA_ERR_UNSUPPORTED), "UNSUPPORTED") { names_ok = false; }
  if !str_eq(firmata_error_name(FIRMATA_ERR_BUFFER_FULL), "BUFFER_FULL") { names_ok = false; }
  if !str_eq(firmata_error_name(99), "UNKNOWN") { names_ok = false; }
  failed = failed + report(names_ok, "error_name: 8 kinds + UNKNOWN");

  // Mode catalog 0..11 + unknown.
  var modes_ok = true;
  if !str_eq(firmata_mode_name(FIRMATA_MODE_INPUT), "INPUT") { modes_ok = false; }
  if !str_eq(firmata_mode_name(FIRMATA_MODE_OUTPUT), "OUTPUT") { modes_ok = false; }
  if !str_eq(firmata_mode_name(FIRMATA_MODE_ANALOG), "ANALOG") { modes_ok = false; }
  if !str_eq(firmata_mode_name(FIRMATA_MODE_PWM), "PWM") { modes_ok = false; }
  if !str_eq(firmata_mode_name(FIRMATA_MODE_SERVO), "SERVO") { modes_ok = false; }
  if !str_eq(firmata_mode_name(FIRMATA_MODE_SHIFT), "SHIFT") { modes_ok = false; }
  if !str_eq(firmata_mode_name(FIRMATA_MODE_I2C), "I2C") { modes_ok = false; }
  if !str_eq(firmata_mode_name(FIRMATA_MODE_ONEWIRE), "ONEWIRE") { modes_ok = false; }
  if !str_eq(firmata_mode_name(FIRMATA_MODE_STEPPER), "STEPPER") { modes_ok = false; }
  if !str_eq(firmata_mode_name(FIRMATA_MODE_ENCODER), "ENCODER") { modes_ok = false; }
  if !str_eq(firmata_mode_name(FIRMATA_MODE_SERIAL), "SERIAL") { modes_ok = false; }
  if !str_eq(firmata_mode_name(FIRMATA_MODE_PULLUP), "PULLUP") { modes_ok = false; }
  if !str_eq(firmata_mode_name(0x0C), "UNKNOWN") { modes_ok = false; }
  failed = failed + report(modes_ok, "mode_name: 12 named modes + UNKNOWN");

  return failed;
}

// =========================================================================
// Session
// =========================================================================

fn test_session_new() -> Int {
  var failed = 0;
  let s = firmata_session_new();
  var ok = s.ports.len() == FIRMATA_SESSION_PORTS;
  if ok {
    var i = 0;
    while i < s.ports.len() {
      if s.ports[i] != 0 {
        ok = false;
      }
      i = i + 1;
    }
  }
  if ok { ok = s.rx_limit == FIRMATA_RX_LIMIT_DEFAULT; }
  if ok { ok = firmata_session_pending(&s) == 0; }
  if ok { ok = !firmata_session_is_ready(&s); }
  failed = failed + report(ok, "session_new: 16 zeroed ports, default rx limit, not ready");

  var s2 = firmata_session_new();
  s2.rx_limit = 2;
  let big = hx("f90205");
  let fr = firmata_session_feed(&mut s2, &big);
  var limit_ok = false;
  if !fr.is_ok {
    limit_ok = fr.error.kind == FIRMATA_ERR_BUFFER_FULL;
  }
  limit_ok = limit_ok && firmata_session_pending(&s2) == 0;
  failed = failed + report(limit_ok, "session_feed: rx_limit exceeded -> BUFFER_FULL, nothing appended");
  return failed;
}

fn test_session_handshake() -> Int {
  var failed = 0;
  let fr = load_fixture("handshake.hex");
  if !fr.is_ok {
    why(fr.error);
    return report(false, "session: handshake fixture");
  }
  let stream: Vec[UInt8] = fr.value;
  var s = firmata_session_new();

  let hq = firmata_session_begin_handshake(&mut s);
  let out = firmata_session_take_output(&mut s);
  let out_ok = is_hex(&out, "f9f079f7");
  failed = failed + report(out_ok, "session_begin_handshake: queues f9 f0 79 f7");
  let out2 = firmata_session_take_output(&mut s);
  failed = failed + report(out2.len() == 0, "take_output: second drain is empty");

  let empty = Vec[UInt8].new();
  let fe = firmata_session_feed(&mut s, &empty);
  var ok = fe.is_ok;
  if ok { ok = fe.value == 0; }
  failed = failed + report(ok, "session_feed: empty input -> Ok(0)");

  let f = firmata_session_feed(&mut s, &stream);
  ok = f.is_ok;
  if ok { ok = f.value == stream.len(); }
  failed = failed + report(ok, "session_feed: accepts the recorded handshake trace (" + to_string(stream.len()) + " bytes)");

  let p1 = firmata_session_poll(&mut s);
  ok = false;
  if p1.is_ok {
    let o = p1.value;
    if o.is_some {
      match o.value {
        Version(v) => { ok = v.major == 2 && v.minor == 5; }
        _ => { ok = false; }
      }
    }
  }
  failed = failed + report(ok, "session_poll: first handshake message is Version 2.5");

  let p2 = firmata_session_poll(&mut s);
  ok = false;
  if p2.is_ok {
    let o = p2.value;
    if o.is_some {
      match o.value {
        Firmware(fw) => { ok = str_eq(fw.name, "StandardFirmata"); }
        _ => { ok = false; }
      }
    }
  }
  failed = failed + report(ok, "session_poll: second handshake message is the firmware report");

  let p3 = firmata_session_poll(&mut s);
  ok = p3.is_ok;
  if ok { ok = !p3.value.is_some; }
  failed = failed + report(ok, "session_poll: no third message on the trace");

  ok = firmata_session_is_ready(&s);
  ok = ok && s.version_received && s.firmware_received;
  ok = ok && s.version_major == 2 && s.version_minor == 5;
  ok = ok && str_eq(s.firmware_name, "StandardFirmata");
  failed = failed + report(ok, "session: ready after both handshake reports; version and name recorded");
  failed = failed + report(firmata_session_pending(&s) == 0, "session_pending: 0 after consuming the trace");

  // Chunked feed: one byte at a time, polling after each byte.
  var s2 = firmata_session_new();
  var msgs = 0;
  var chunk_ok = true;
  var i = 0;
  while i < stream.len() {
    var one = Vec[UInt8].new();
    one.push(stream[i]);
    let cf = firmata_session_feed(&mut s2, &one);
    if !cf.is_ok {
      chunk_ok = false;
    }
    var polling = true;
    while polling {
      let pr = firmata_session_poll(&mut s2);
      if !pr.is_ok {
        chunk_ok = false;
        polling = false;
      } else {
        if pr.value.is_some {
          msgs = msgs + 1;
        } else {
          polling = false;
        }
      }
    }
    i = i + 1;
  }
  chunk_ok = chunk_ok && msgs == 2 && firmata_session_is_ready(&s2);
  failed = failed + report(chunk_ok, "session: byte-at-a-time feed yields exactly 2 messages and ready");

  return failed;
}

fn test_session_commands() -> Int {
  var failed = 0;
  var s = firmata_session_new();
  var ok = false;

  let pm = firmata_session_set_pin_mode(&mut s, 13, FIRMATA_MODE_OUTPUT);
  ok = pm.is_ok;
  if ok { ok = is_hex(&firmata_session_take_output(&mut s), "f40d01"); }
  failed = failed + report(ok, "session_set_pin_mode: queues f4 0d 01");

  let dw1 = firmata_session_digital_write(&mut s, 13, true);
  ok = dw1.is_ok;
  if ok { ok = is_hex(&firmata_session_take_output(&mut s), "912000"); }
  ok = ok && s.ports[1] == 0x20;
  failed = failed + report(ok, "session_digital_write: pin 13 HIGH -> 91 20 00, shadow port 1 = 0x20");

  let dw2 = firmata_session_digital_write(&mut s, 8, true);
  ok = dw2.is_ok;
  if ok { ok = is_hex(&firmata_session_take_output(&mut s), "912100"); }
  ok = ok && s.ports[1] == 0x21;
  failed = failed + report(ok, "session_digital_write: pin 8 HIGH -> 91 21 00 (shadow accumulates)");

  let dw3 = firmata_session_digital_write(&mut s, 13, false);
  ok = dw3.is_ok;
  if ok { ok = is_hex(&firmata_session_take_output(&mut s), "910100"); }
  ok = ok && s.ports[1] == 0x01;
  failed = failed + report(ok, "session_digital_write: pin 13 LOW -> 91 01 00 (bit cleared)");

  // Incoming digital report updates the shadow, so the next write includes it.
  let incoming = hx("900100");
  let inf = firmata_session_feed(&mut s, &incoming);
  let inp = firmata_session_poll(&mut s);
  ok = inf.is_ok && inp.is_ok;
  if ok { ok = inp.value.is_some; }
  if ok { ok = s.ports[0] == 0x01; }
  let dw4 = firmata_session_digital_write(&mut s, 2, true);
  if ok { ok = dw4.is_ok; }
  if ok { ok = is_hex(&firmata_session_take_output(&mut s), "900500"); }
  failed = failed + report(ok, "session_digital_write: incoming 90 01 00 updates shadow; pin 2 HIGH -> 90 05 00");

  let pw = firmata_session_pwm_write(&mut s, 9, 1023);
  ok = pw.is_ok;
  if ok { ok = is_hex(&firmata_session_take_output(&mut s), "e97f07"); }
  failed = failed + report(ok, "session_pwm_write: queues e9 7f 07");

  let ar = firmata_session_enable_analog_report(&mut s, 0, true);
  ok = ar.is_ok;
  if ok { ok = is_hex(&firmata_session_take_output(&mut s), "c001"); }
  failed = failed + report(ok, "session_enable_analog_report: queues c0 01");

  let dr = firmata_session_enable_digital_report(&mut s, 1, true);
  ok = dr.is_ok;
  if ok { ok = is_hex(&firmata_session_take_output(&mut s), "d101"); }
  failed = failed + report(ok, "session_enable_digital_report: queues d1 01");

  // Invalid arguments queue nothing.
  let inv1 = firmata_session_set_pin_mode(&mut s, 128, 0);
  let inv2 = firmata_session_digital_write(&mut s, 200, true);
  let inv3 = firmata_session_pwm_write(&mut s, 16, 0);
  let inv4 = firmata_session_enable_analog_report(&mut s, 16, true);
  let inv5 = firmata_session_enable_digital_report(&mut s, 16, true);
  var inv_ok = !inv1.is_ok && !inv2.is_ok && !inv3.is_ok && !inv4.is_ok && !inv5.is_ok;
  inv_ok = inv_ok && firmata_session_take_output(&mut s).len() == 0;
  inv_ok = inv_ok && inv1.error.kind == FIRMATA_ERR_OUT_OF_RANGE;
  inv_ok = inv_ok && inv2.error.kind == FIRMATA_ERR_OUT_OF_RANGE;
  inv_ok = inv_ok && inv3.error.kind == FIRMATA_ERR_OUT_OF_RANGE;
  inv_ok = inv_ok && inv4.error.kind == FIRMATA_ERR_OUT_OF_RANGE;
  inv_ok = inv_ok && inv5.error.kind == FIRMATA_ERR_OUT_OF_RANGE;
  failed = failed + report(inv_ok, "session commands: 5 invalid arguments -> OUT_OF_RANGE and queue nothing");

  // A hand-built session with a corrupt (short) port shadow must not index
  // out of bounds; it returns a typed error instead of panicking.
  var broken = FirmataSession{
    rx: Vec[UInt8].new();
    out: Vec[UInt8].new();
    ports: Vec[Int].new();
    rx_limit: 16;
    version_received: false;
    version_major: 0;
    version_minor: 0;
    firmware_received: false;
    firmware_name: "";
  };
  let bw = firmata_session_digital_write(&mut broken, 0, true);
  var bridge_ok = false;
  if !bw.is_ok {
    bridge_ok = bw.error.kind == FIRMATA_ERR_INVALID_ARG;
  }
  bridge_ok = bridge_ok && firmata_session_take_output(&mut broken).len() == 0;
  failed = failed + report(bridge_ok, "session_digital_write: uninitialized port shadow -> INVALID_ARG (no panic)");

  // Reset clears state but preserves the configured limit.
  s.rx_limit = 123;
  firmata_session_reset(&mut s);
  ok = firmata_session_pending(&s) == 0;
  ok = ok && firmata_session_take_output(&mut s).len() == 0;
  ok = ok && s.ports.len() == FIRMATA_SESSION_PORTS && s.ports[0] == 0 && s.ports[1] == 0;
  ok = ok && !firmata_session_is_ready(&s) && !s.version_received && !s.firmware_received;
  ok = ok && s.version_major == 0 && s.version_minor == 0 && s.firmware_name.len() == 0;
  ok = ok && s.rx_limit == 123;
  failed = failed + report(ok, "session_reset: clears rx/out/ports/handshake, preserves rx_limit");

  return failed;
}

fn test_session_resync() -> Int {
  var failed = 0;
  var ok = false;

  let nf = load_fixture("noise.hex");
  if !nf.is_ok {
    why(nf.error);
    return report(false, "session: noise fixture");
  }
  let noise: Vec<UInt8> = nf.value;
  var s = firmata_session_new();
  let feed = firmata_session_feed(&mut s, &noise);
  ok = feed.is_ok;
  let e1 = firmata_session_poll(&mut s);
  ok = ok && !e1.is_ok && e1.error.kind == FIRMATA_ERR_BAD_STATUS;
  let e2 = firmata_session_poll(&mut s);
  ok = ok && !e2.is_ok && e2.error.kind == FIRMATA_ERR_BAD_STATUS;
  let m3 = firmata_session_poll(&mut s);
  ok = ok && m3.is_ok && m3.value.is_some;
  if ok {
    match m3.value.value {
      Version(v) => { ok = v.major == 2 && v.minor == 5; }
      _ => { ok = false; }
    }
  }
  ok = ok && firmata_session_pending(&s) == 0;
  failed = failed + report(ok, "session_poll: 2 garbage bytes -> 2 BAD_STATUS, then Version (resync)");

  // An interrupted sysex: F0 79 02 then the 0xF9 status of the next frame.
  var s2 = firmata_session_new();
  let intr = hx("f07902f90205");
  let f2 = firmata_session_feed(&mut s2, &intr);
  ok = f2.is_ok;
  let x1 = firmata_session_poll(&mut s2);
  ok = ok && !x1.is_ok && x1.error.kind == FIRMATA_ERR_BAD_SYSEX;
  let x2 = firmata_session_poll(&mut s2);
  ok = ok && !x2.is_ok && x2.error.kind == FIRMATA_ERR_BAD_STATUS;
  let x3 = firmata_session_poll(&mut s2);
  ok = ok && !x3.is_ok && x3.error.kind == FIRMATA_ERR_BAD_STATUS;
  let x4 = firmata_session_poll(&mut s2);
  ok = ok && x4.is_ok && x4.value.is_some;
  if ok {
    match x4.value.value {
      Version(v) => { ok = v.major == 2 && v.minor == 5; }
      _ => { ok = false; }
    }
  }
  failed = failed + report(ok, "session_poll: interrupted sysex resyncs to the next Version frame");

  // Incomplete sysex returns None until the END_SYSEX arrives.
  var s3 = firmata_session_new();
  let part = hx("f0790205");
  let fp = firmata_session_feed(&mut s3, &part);
  ok = fp.is_ok;
  let none = firmata_session_poll(&mut s3);
  ok = ok && none.is_ok && !none.value.is_some;
  let endb = hx("f7");
  let fe = firmata_session_feed(&mut s3, &endb);
  ok = ok && fe.is_ok;
  let fw = firmata_session_poll(&mut s3);
  ok = ok && fw.is_ok && fw.value.is_some;
  if ok {
    match fw.value.value {
      Firmware(f) => { ok = f.major == 2 && f.minor == 5 && f.name.len() == 0; }
      _ => { ok = false; }
    }
  }
  ok = ok && s3.firmware_received && !firmata_session_is_ready(&s3);
  let vframe = hx("f90205");
  let vf = firmata_session_feed(&mut s3, &vframe);
  let vp = firmata_session_poll(&mut s3);
  ok = ok && vf.is_ok && vp.is_ok && vp.value.is_some;
  if ok {
    match vp.value.value {
      Version(v) => { ok = v.major == 2 && v.minor == 5; }
      _ => { ok = false; }
    }
  }
  ok = ok && firmata_session_is_ready(&s3);
  failed = failed + report(ok, "session_poll: incomplete sysex -> None, END_SYSEX -> firmware; then Version makes the session ready");

  // A malformed frame is consumed entirely, so the next frame decodes.
  var s4 = firmata_session_new();
  let bad = hx("f071410042f7f90205");
  let fb = firmata_session_feed(&mut s4, &bad);
  ok = fb.is_ok;
  let b1 = firmata_session_poll(&mut s4);
  ok = ok && !b1.is_ok && b1.error.kind == FIRMATA_ERR_BAD_STRING;
  let b2 = firmata_session_poll(&mut s4);
  ok = ok && b2.is_ok && b2.value.is_some;
  if ok {
    match b2.value.value {
      Version(v) => { ok = v.major == 2 && v.minor == 5; }
      _ => { ok = false; }
    }
  }
  ok = ok && firmata_session_pending(&s4) == 0;
  failed = failed + report(ok, "session_poll: malformed frame consumed -> BAD_STRING, then Version");

  return failed;
}

fn test_transport_absent() -> Int {
  // The package has no transport dependency: absence of hardware is the
  // normal pure-leg state, reported as an explicit SKIP note (a pass).
  let s = firmata_session_new();
  let ok = firmata_session_pending(&s) == 0 && !firmata_session_is_ready(&s);
  io.println("    note: no serial transport is opened; a real device would feed bytes into this session");
  return report(ok, "transport: SKIP -- no hardware/transport required (inject bytes with firmata_session_feed)");
}

pub fn main() -> Int {
  io.println("=== xiom.firmata conformance tests (pure-XIOM Firmata 2.x host bindings) ===");
  io.flush_stdout();
  var failed: Int = 0;
  failed = failed + test_fixtures();
  failed = failed + test_encoders();
  failed = failed + test_frame_len();
  failed = failed + test_decode_handshake();
  failed = failed + test_decode_io();
  failed = failed + test_decode_strings();
  failed = failed + test_decode_errors();
  failed = failed + test_helpers();
  failed = failed + test_session_new();
  failed = failed + test_session_handshake();
  failed = failed + test_session_commands();
  failed = failed + test_session_resync();
  failed = failed + test_transport_absent();
  return finish(failed);
}
