// XIOM -- xiom.serial ABI probe (temporary; not part of the suite).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves, on the pinned v0.64.5 slot, that the dl loader can drive the
// Win32 comm API ABI end to end: GetCurrentProcessId round trip,
// GetLastError capture, CreateFileA on an absent device (typed errno), and
// advapi32 RegOpenKeyExA on the SERIALCOMM key.

module probe_abi

use xiom.ffi.dl;
use xiom.io;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  if neg { return "-" + out; }
  return out;
}

pub fn main() -> Int {
  io.println("=== serial abi probe ===");

  let h = dl.dl_open("kernel32.dll");
  if !h.is_ok {
    io.println("FAIL kernel32: " + h.error);
    return 1;
  }
  let kh: Int = h.value;
  io.println("step1: kernel32.dll loaded (handle non-zero)");

  let s1 = dl.dl_sym(kh, "GetCurrentProcessId");
  if !s1.is_ok {
    io.println("FAIL sym GetCurrentProcessId: " + s1.error);
    return 1;
  }
  unsafe {
    let f1 = s1.value as fn() -> UInt32;
    let pid = f1();
    io.println("step2: GetCurrentProcessId -> " + int_to_str(pid as Int));
  }

  let s2 = dl.dl_sym(kh, "GetLastError");
  if !s2.is_ok {
    io.println("FAIL sym GetLastError: " + s2.error);
    return 1;
  }
  unsafe {
    let f2 = s2.value as fn() -> UInt32;
    io.println("step3: GetLastError pre -> " + int_to_str(f2() as Int));
  }

  let s3 = dl.dl_sym(kh, "CreateFileA");
  if !s3.is_ok {
    io.println("FAIL sym CreateFileA: " + s3.error);
    return 1;
  }
  var path = "\\\\.\\COM99";
  var hf: Int = 0;
  var last: Int = 0;
  unsafe {
    let f3 = s3.value as fn(*UInt8, UInt32, UInt32, Int, UInt32, UInt32, Int) -> Int;
    let r = f3(path as *UInt8, 3221225472 as UInt32, 0, 0, 3, 0, 0);
    let f2b = s2.value as fn() -> UInt32;
    last = f2b() as Int;
    hf = r;
  }
  io.println("step4: CreateFileA(COM99) -> handle=" + int_to_str(hf) + " err=" + int_to_str(last));

  let a = dl.dl_open("advapi32.dll");
  if !a.is_ok {
    io.println("FAIL advapi32: " + a.error);
    return 1;
  }
  let ah: Int = a.value;
  io.println("step5: advapi32.dll loaded");

  let s4 = dl.dl_sym(ah, "RegOpenKeyExA");
  if !s4.is_ok {
    io.println("FAIL sym RegOpenKeyExA: " + s4.error);
    return 1;
  }
  var key_slot: Vec[UInt8] = Vec[UInt8].with_len(8);
  var rc: Int = 0;
  unsafe {
    let f4 = s4.value as fn(Int, *UInt8, UInt32, UInt32, *UInt8) -> UInt32;
    let sub = "HARDWARE\\DEVICEMAP\\SERIALCOMM";
    rc = f4(2147483650, sub as *UInt8, 0 as UInt32, 131097 as UInt32, key_slot.as_mut_ptr()) as Int;
  }
  io.println("step6: RegOpenKeyExA(SERIALCOMM) -> rc=" + int_to_str(rc));

  let s5 = dl.dl_sym(a.value, "RegCloseKey");
  if s5.is_ok {
    unsafe {
      let f5 = s5.value as fn(Int) -> UInt32;
      if rc == 0 {
        let fh = key_slot.as_mut_ptr();
        let key = ffi_read_u64(fh);
        io.println("step7: key handle=" + int_to_str(key));
        let cr = f5(key) as Int;
        io.println("step8: RegCloseKey -> rc=" + int_to_str(cr));
      }
    }
  }
  io.println("=== probe done ===");
  return 0;
}

// Local raw read helper (probe-local; module ffi helpers come later).
fn ffi_read_u64(p: *UInt8) -> Int
  requires: p != null
{
  unsafe {
    let b0 = p[0] as Int;
    let b1 = p[1] as Int;
    let b2 = p[2] as Int;
    let b3 = p[3] as Int;
    let b4 = p[4] as Int;
    let b5 = p[5] as Int;
    let b6 = p[6] as Int;
    let b7 = p[7] as Int;
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
         | (b4 << 32) | (b5 << 40) | (b6 << 48) | (b7 << 56);
  }
}
