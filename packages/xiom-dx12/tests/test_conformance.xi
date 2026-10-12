// xiom.dx12 conformance suite -- foundation probe + generated surface.
//
// Stages:
//   probe      -- symbols / device (D3D12CreateDevice 11_0) / node count /
//                 allocator out-param roundtrip / SKIP classification
//   surface    -- 0.2.0: generated COM wrappers over the live device:
//                 GetNodeCount, CreateCommandQueue (+ Release), and the
//                 free-function path (D3D12SerializeRootSignature + blob)
//   missing    -- DX12_LOAD_ABSENT (SKIP; bogus soname, deterministic)
//   no adapter -- DX12_LOAD_NO_DEVICE (SKIP)
//
// Run: scripts/port.ps1 -Package xiom.dx12
//  or: xiom --run tests/test_conformance.xi --c-source <abs>/src/dx12_probe.c
//      --c-source <abs>/src/d3d12_calls.c

module dx12_conformance

use xiom.io;
use xiom.convert;
use xiom.test;
use xiom.ffi;
use xiom.dx12;
use xiom.dx12.functions;
use xiom.dx12.iface_01;
use xiom.dx12.iface_02;
use xiom.dx12.iface_03;
use xiom.dx12.iface_04;
use xiom.dx12.iface_05;
use xiom.dx12.iface_06;
use xiom.dx12.iface_07;
use xiom.dx12.iface_08;
use xiom.dx12.iface_09;
use xiom.dx12.iface_10;
use xiom.dx12.iface_11;
use xiom.dx12.iface_12;
use xiom.dx12.consts_1;
use xiom.dx12.consts_2;
use xiom.dx12.consts_3;
use xiom.dx12.consts_4;
use xiom.dx12.consts_5;

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

fn t_constants() -> Bool {
  var ok = true;
  if D3D_FEATURE_LEVEL_11_0 != 0xB000 { ok = false; }
  if D3D_FEATURE_LEVEL_11_1 != 0xB100 { ok = false; }
  if D3D_FEATURE_LEVEL_12_0 != 0xC000 { ok = false; }
  if D3D_FEATURE_LEVEL_12_2 != 0xC200 { ok = false; }
  if D3D12_COMMAND_LIST_TYPE_DIRECT != 0 { ok = false; }
  if D3D12_COMMAND_LIST_TYPE_BUNDLE != 1 { ok = false; }
  if D3D12_COMMAND_LIST_TYPE_COMPUTE != 2 { ok = false; }
  if D3D12_COMMAND_LIST_TYPE_COPY != 3 { ok = false; }
  if DX12_SONAME != "d3d12.dll" { ok = false; }
  return ok;
}

fn t_generated_consts() -> Bool {
  var ok = true;
  if D3D12_FILL_MODE_SOLID != 3 { ok = false; }
  if D3D12_HEAP_TYPE_DEFAULT != 1 { ok = false; }
  if D3D12_HEAP_TYPE_UPLOAD != 2 { ok = false; }
  if D3D12_RESOURCE_STATE_COMMON != 0 { ok = false; }
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.dx12 conformance tests (probe + generated surface) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: feature levels + command list types + soname");

  // SKIP-path classification, deterministic on every host (bogus soname).
  let missing = dx12_probe_named("xiom-absent-dx12-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly produced a device");
  } else {
    failed = failed + report(missing.error.kind == DX12_LOAD_ABSENT,
      "skip-path: absent runtime classified as DX12_LOAD_ABSENT (SKIP)");
  }

  // Default runtime probe.
  let p = dx12_probe();
  if p.is_ok {
    let info: Dx12DeviceInfo = p.value;
    failed = failed + report(info.node_count >= 1,
      "device: D3D12CreateDevice ok (node_count=" + to_string(info.node_count) + ")");
    failed = failed + report(info.allocator_ok,
      "device: CreateCommandAllocator out-param roundtrip + Release");
  } else {
    if p.error.kind == DX12_LOAD_ABSENT {
      failed = failed + report(true, "probe: SKIP -- d3d12 runtime not present (" + p.error.message + ")");
    } else if p.error.kind == DX12_LOAD_NO_DEVICE {
      failed = failed + report(true, "probe: SKIP -- no D3D12-capable adapter (" + p.error.message + ")");
    } else {
      failed = failed + report(false, "probe: failed -- " + p.error.message);
    }
  }

  // 0.2.0: generated surface -- COM calls through the slot shims against a
  // KEPT-LIVE device (dx12_open_device leaves the runtime + device loaded).
  let od = dx12_open_device();
  if od.is_ok {
    let dev = dx12_device_ptr();
    failed = failed + report(dev != 0, "surface: live ID3D12Device pointer");
    failed = failed + report(t_generated_consts(),
      "surface: generated consts (FILL_MODE_SOLID/HEAP_TYPE/RESOURCE_STATE)");
    if dev != 0 {
      let nodes = d3d12_device_get_node_count(dev);
      failed = failed + report(nodes >= 1,
        "surface: d3d12_device_get_node_count = " + to_string(nodes as Int));

      // CreateCommandQueue with a zeroed D3D12_COMMAND_QUEUE_DESC (16 bytes:
      // Type=DIRECT, Priority=0, Flags=0, NodeMask=0) + IID slot + out slot.
      var desc: Vec[UInt8] = Vec[UInt8].new();
      var i = 0;
      while i < 16 { desc.push(0 as UInt8); i = i + 1; }
      var iid: Vec[UInt8] = Vec[UInt8].new();
      i = 0;
      while i < 16 { iid.push(0 as UInt8); i = i + 1; }
      let ir = dx12_iid(2, iid.as_mut_ptr()); // 2 = ID3D12CommandQueue
      var outq: Vec[UInt8] = Vec[UInt8].new();
      i = 0;
      while i < 8 { outq.push(0 as UInt8); i = i + 1; }
      let hr = d3d12_device_create_command_queue(dev, desc.as_mut_ptr(), iid.as_mut_ptr(), outq.as_mut_ptr());
      let q = unsafe { ffi.ptr_read_u64_le(outq.as_mut_ptr()) };
      failed = failed + report(ir == 0 && hr == 0 && q != 0,
        "surface: CreateCommandQueue hr=" + to_string(hr as Int) + " (queue live)");
      if q != 0 {
        let rc = d3d12_object_release(q);
        failed = failed + report(rc == 0, "surface: queue Release -> refcount 0");
      }
    }

    // Free-function path (generated wrapper): serialize an empty root
    // signature -- zeroed D3D12_ROOT_SIGNATURE_DESC (40B with padding),
    // version 1.0 -- through the normalized shim.  The blob pointer proof
    // is enough here; the typed bridge probe below reads the size/magic.
    var rsdesc: Vec[UInt8] = Vec[UInt8].new();
    var k = 0;
    while k < 40 { rsdesc.push(0 as UInt8); k = k + 1; }
    var blob: Vec[UInt8] = Vec[UInt8].new();
    var err: Vec[UInt8] = Vec[UInt8].new();
    k = 0;
    while k < 8 { blob.push(0 as UInt8); err.push(0 as UInt8); k = k + 1; }
    let hr2 = d3d12_serialize_root_signature(rsdesc.as_mut_ptr(), 1, blob.as_mut_ptr(), err.as_mut_ptr());
    let blobp = unsafe { ffi.ptr_read_u64_le(blob.as_mut_ptr()) };
    let errp = unsafe { ffi.ptr_read_u64_le(err.as_mut_ptr()) };
    failed = failed + report(hr2 == 0 && blobp != 0,
      "surface: D3D12SerializeRootSignature wrapper hr=" + to_string(hr2 as Int));
    if blobp != 0 {
      let _r1 = d3d12_object_release(blobp);
    }
    if errp != 0 {
      let _r2 = d3d12_object_release(errp);
    }

    // Trusted witness: typed struct building + blob read in the bridge
    // (1-root-constant signature; RTS0 magic + non-zero size).
    let rrc = dx12_root_signature_probe();
    let rsz = dx12_root_signature_size();
    let rmagic = dx12_root_signature_magic();
    failed = failed + report(rrc == 0 && rsz > 0 && rmagic != 0,
      "surface: root signature serialized (size=" + to_string(rsz) + " magic=0x" + to_string(rmagic) + ")");
    dx12_unload();
  } else if od.error.kind == DX12_LOAD_ABSENT || od.error.kind == DX12_LOAD_NO_DEVICE {
    failed = failed + report(true, "surface: SKIP -- device unavailable (" + od.error.message + ")");
  } else {
    failed = failed + report(false, "surface: open failed -- " + od.error.message);
  }

  // Unload must be safe even after a failed probe.
  dx12_unload();
  failed = failed + report(true, "loader: unload path exercised");

  if failed == 0 {
    io.println("xiom.dx12: all tests passed");
  } else {
    io.println("xiom.dx12: tests failed");
  }
  return failed;
}
