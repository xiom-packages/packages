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
use xiom.dx12.recording;
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
use xiom.dx12.structs;
use xiom.dx12.struct_meta_1;
use xiom.dx12.struct_meta_2;
use xiom.dx12.struct_meta_3;
use xiom.dx12.struct_meta_4;
use xiom.dx12.struct_meta_5;
use xiom.dx12.video;
use xiom.dx12.video_structs;
use xiom.dx12.video_consts_1;
use xiom.dx12.video_consts_2;
use xiom.dx12.video_consts_3;
use xiom.dx12.video_iface_01;
use xiom.dx12.video_iface_02;
use xiom.dx12.video_iface_03;
use xiom.dx12.video_iface_04;
use xiom.dx12.dxgi;
use xiom.dx12.dxgi_functions;
use xiom.dx12.dxgi_consts_1;
use xiom.dx12.dxgi_iface_01;
use xiom.dx12.dxgi_iface_02;
use xiom.dx12.dxgi_iface_03;
use xiom.dx12.dxgi_iface_04;
use xiom.dx12.dxgi_iface_05;
use xiom.dx12.dxgi_iface_06;

// Byte-indexed slot readers (B-16/B-17 discipline: no pointer arithmetic,
// no ptr_read at base+N; Vec indexing over the owned buffer only).
fn le16(slot: Vec[UInt8], off: Int) -> Int {
  return (slot[off] as Int) | ((slot[off + 1] as Int) << 8);
}

fn le32(slot: Vec[UInt8], off: Int) -> Int {
  return (slot[off] as Int) | ((slot[off + 1] as Int) << 8)
    | ((slot[off + 2] as Int) << 16) | ((slot[off + 3] as Int) << 24);
}

fn le64(slot: Vec[UInt8], off: Int) -> Int {
  return le32(slot, off) | (le32(slot, off + 4) << 32);
}

fn zeroed(n: Int) -> Vec[UInt8] {
  var v: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < n { v.push(0 as UInt8); i = i + 1; }
  return v;
}

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

// 0.3.0 struct metadata: the clang-dump oracle constants match the build
// compiler's sizeof for the typed-shim closure (both x64 layouts).
fn t_struct_meta_sizes() -> Bool {
  var ok = true;
  if dx12_sizeof_d3d12_resource_desc() != D3D12_SIZEOF_RESOURCE_DESC { ok = false; }
  if dx12_sizeof_d3d12_resource_desc1() != D3D12_SIZEOF_RESOURCE_DESC1 { ok = false; }
  if dx12_sizeof_d3d12_heap_desc() != D3D12_SIZEOF_HEAP_DESC { ok = false; }
  if dx12_sizeof_d3d12_heap_properties() != D3D12_SIZEOF_HEAP_PROPERTIES { ok = false; }
  if dx12_sizeof_d3d12_node_id() != D3D12_SIZEOF_NODE_ID { ok = false; }
  if dx12_sizeof_d3d12_program_identifier() != D3D12_SIZEOF_PROGRAM_IDENTIFIER { ok = false; }
  if dx12_sizeof_d3d12_command_queue_desc() != D3D12_SIZEOF_COMMAND_QUEUE_DESC { ok = false; }
  if dx12_sizeof_d3d12_descriptor_heap_desc() != D3D12_SIZEOF_DESCRIPTOR_HEAP_DESC { ok = false; }
  if dx12_sizeof_d3d12_resource_allocation_info() != D3D12_SIZEOF_RESOURCE_ALLOCATION_INFO { ok = false; }
  if dx12_sizeof_d3d12_resource_allocation_info1() != D3D12_SIZEOF_RESOURCE_ALLOCATION_INFO1 { ok = false; }
  if dx12_sizeof_d3d12_protected_resource_session_desc() != D3D12_SIZEOF_PROTECTED_RESOURCE_SESSION_DESC { ok = false; }
  if dx12_sizeof_d3d12_protected_resource_session_desc1() != D3D12_SIZEOF_PROTECTED_RESOURCE_SESSION_DESC1 { ok = false; }
  if dx12_sizeof_d3d12_shader_cache_session_desc() != D3D12_SIZEOF_SHADER_CACHE_SESSION_DESC { ok = false; }
  if dx12_sizeof_d3d12_device_configuration_desc() != D3D12_SIZEOF_DEVICE_CONFIGURATION_DESC { ok = false; }
  if dx12_sizeof_d3d12_mip_region() != D3D12_SIZEOF_MIP_REGION { ok = false; }
  if dx12_sizeof_dxgi_sample_desc() != DXGI_SIZEOF_SAMPLE_DESC { ok = false; }
  return ok;
}

fn t_dxgi_consts() -> Bool {
  var ok = true;
  if DXGI_FORMAT_B8G8R8A8_UNORM != 0x57 { ok = false; }
  if DXGI_FORMAT_R8G8B8A8_UNORM != 0x1C { ok = false; } // generated const module
  if DXGI_SWAP_EFFECT_FLIP_DISCARD != 4 { ok = false; }
  if DXGI_USAGE_RENDER_TARGET_OUTPUT != 0x20 { ok = false; }
  if DXGI_SONAME != "dxgi.dll" { ok = false; }
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.dx12 conformance tests (probe + generated surface) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_constants(), "constants: feature levels + command list types + soname");

  // Error path: the bridge guards NULL handles -- ID3DBlob::GetBufferSize on
  // NULL is -1.  Also exercises the B-23 C-origin NULL handle
  // (`dx12_null_ptr()`; the XIOM `null` literal marshals garbage to C).
  failed = failed + report(dx12_blob_size(dx12_null_ptr()) == -1,
    "error: blob_size(NULL) -> -1 (guarded)");

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

      // CreateCommandQueue with a D3D12_COMMAND_QUEUE_DESC (16 bytes:
      // Type=DIRECT, Priority=1, Flags=0, NodeMask=0) + IID slot + out slot.
      // The desc is built with the poke helpers (C-side offset writes into an
      // owned slot -- B-16/B-17 discipline).
      var desc = zeroed(16);
      dx12_poke_u32(desc.as_mut_ptr(), 0, 0 as UInt32);   // Type = DIRECT
      dx12_poke_u32(desc.as_mut_ptr(), 4, 100 as UInt32); // Priority = HIGH (0/100 are the valid enum values)
      var iid = zeroed(16);
      let ir = dx12_iid(2, iid.as_mut_ptr()); // 2 = ID3D12CommandQueue
      var outq = zeroed(8);
      let hr = d3d12_device_create_command_queue(dev, desc.as_mut_ptr(), iid.as_mut_ptr(), outq.as_mut_ptr());
      let q = le64(outq, 0);
      failed = failed + report(ir == 0 && hr == 0 && q != 0,
        "surface: CreateCommandQueue hr=" + to_string(hr as Int) + " (queue live)");
      if q != 0 {
        // 0.3.0: GetDesc-family sret normal form (typed shim -> owned slot).
        var qout = zeroed(16);
        let qgr = d3d12_command_queue_get_desc(q, qout.as_mut_ptr());
        let qtype = le32(qout, D3D12_OFF_COMMAND_QUEUE_DESC_TYPE);
        let qprio = le32(qout, D3D12_OFF_COMMAND_QUEUE_DESC_PRIORITY);
        failed = failed + report(qgr == 0 && qtype == 0 && qprio == 100,
          "struct: CommandQueue::GetDesc sret (type=" + to_string(qtype) + " priority=" + to_string(qprio) + ")");
        // 0.4.0: command recording -- allocator + command list + fence.
        // Object handles cross as `Int` params (B-25 workaround: on
        // v0.64.4 `Int as *UInt8` is not value-preserving; the fidelity
        // check below witnesses the `Int` path).  Submission goes through
        // the generated surface; the single-entry command-list array is
        // built in an owned slot (B-24 discipline).
        var fbuf = zeroed(8);
        let fp1 = fbuf.as_mut_ptr();
        let fv1 = dx12_ptr_value(fp1);
        let fv3 = dx12_ptr_value_i(unsafe { fp1 as Int });
        failed = failed + report(fv1 == fv3,
          "recording: handle fidelity (Int params preserve addresses)");

        var aiid = zeroed(16);
        let ar = dx12_iid(1, aiid.as_mut_ptr()); // 1 = ID3D12CommandAllocator
        var aslot = zeroed(8);
        let ahr = d3d12_device_create_command_allocator(dev, 0, aiid.as_mut_ptr(), aslot.as_mut_ptr());
        let alloc = le64(aslot, 0);
        failed = failed + report(ar == 0 && ahr == 0 && alloc != 0,
          "recording: command allocator created (hr=" + to_string(ahr as Int) + ")");
        if alloc != 0 {
          let rst = d3d12_command_allocator_reset(alloc);
          failed = failed + report(rst == 0, "recording: allocator Reset (hr=0)");

          var liid = zeroed(16);
          let lr = dx12_iid(4, liid.as_mut_ptr()); // 4 = ID3D12GraphicsCommandList
          var lslot = zeroed(8);
          let lhr = d3d12_device_create_command_list(dev, 0, 0, alloc, 0, liid.as_mut_ptr(), lslot.as_mut_ptr());
          let clist = le64(lslot, 0);
          failed = failed + report(lr == 0 && lhr == 0 && clist != 0,
            "recording: graphics command list created (hr=" + to_string(lhr as Int) + ")");
          if clist != 0 {
            let chr = d3d12_graphics_command_list_close(clist);
            failed = failed + report(chr == 0, "recording: command list Close (hr=0)");

            // Submit the (empty) list, then fence-signal it and wait.
            dx12_execute_one(q, clist);

            var fiid = zeroed(16);
            let fr = dx12_iid(6, fiid.as_mut_ptr()); // 6 = ID3D12Fence
            var fslot = zeroed(8);
            let fhr = d3d12_device_create_fence(dev, 0 as UInt64, 0, fiid.as_mut_ptr(), fslot.as_mut_ptr());
            let fence = le64(fslot, 0);
            let fv0 = d3d12_fence_get_completed_value(fence);
            failed = failed + report(fr == 0 && fhr == 0 && fence != 0 && fv0 == 0,
              "recording: fence created (initial value 0)");
            if fence != 0 {
              let shr = d3d12_command_queue_signal(q, fence, 1 as UInt64);
              let wr = dx12_fence_wait(fence, 1 as UInt64, 5000);
              let fvc = d3d12_fence_get_completed_value(fence);
              failed = failed + report(shr == 0 && wr == 0 && fvc >= 1,
                "recording: queue signal + fence wait (hr=" + to_string(shr as Int) + " wait=" + to_string(wr) + " completed=" + to_string(fvc as Int) + ")");
              let _ = d3d12_object_release(fence);
            }
            let _ = d3d12_object_release(clist);
          }
          let _ = d3d12_object_release(alloc);
        }

        let rc = d3d12_object_release(q);
        failed = failed + report(rc == 0, "surface: queue Release -> refcount 0");

        // Error path: D3D12_COMMAND_QUEUE_PRIORITY=1 is not a valid enum
        // value (only 0/100/10000 are accepted) -- the runtime rejects it
        // (E_INVALIDARG), no queue is produced and the HRESULT is never
        // swallowed (SPEC sec. 2/6).
        var baddesc = zeroed(16);
        dx12_poke_u32(baddesc.as_mut_ptr(), 0, 0 as UInt32); // Type = DIRECT
        dx12_poke_u32(baddesc.as_mut_ptr(), 4, 1 as UInt32); // Priority = invalid
        var badout = zeroed(8);
        let badhr = d3d12_device_create_command_queue(dev, baddesc.as_mut_ptr(), iid.as_mut_ptr(), badout.as_mut_ptr());
        let badq = le64(badout, 0);
        failed = failed + report(badhr != 0 && badq == 0,
          "error: CreateCommandQueue priority=1 rejected (hr!=0)");
      }

      // 0.3.0: committed buffer resource + ID3D12Resource::GetDesc roundtrip.
      var rdesc = zeroed(D3D12_SIZEOF_RESOURCE_DESC);
      dx12_poke_u32(rdesc.as_mut_ptr(), D3D12_OFF_RESOURCE_DESC_DIMENSION, 1 as UInt32); // BUFFER
      dx12_poke_u64(rdesc.as_mut_ptr(), D3D12_OFF_RESOURCE_DESC_WIDTH, 256 as UInt64);
      dx12_poke_u32(rdesc.as_mut_ptr(), D3D12_OFF_RESOURCE_DESC_HEIGHT, 1 as UInt32);
      // DepthOrArraySize @28 + MipLevels @30 in one u32 poke (1, 1).
      dx12_poke_u32(rdesc.as_mut_ptr(), D3D12_OFF_RESOURCE_DESC_DEPTH_OR_ARRAY_SIZE, 0x00010001 as UInt32);
      dx12_poke_u32(rdesc.as_mut_ptr(), D3D12_OFF_RESOURCE_DESC_SAMPLE_DESC, 1 as UInt32); // Count=1
      dx12_poke_u32(rdesc.as_mut_ptr(), D3D12_OFF_RESOURCE_DESC_LAYOUT, 1 as UInt32); // ROW_MAJOR (buffers)
      var hprops = zeroed(D3D12_SIZEOF_HEAP_PROPERTIES);
      dx12_poke_u32(hprops.as_mut_ptr(), 0, 1 as UInt32); // D3D12_HEAP_TYPE_DEFAULT
      var res = zeroed(8);
      var riid = zeroed(16);
      let ir2 = dx12_iid(5, riid.as_mut_ptr()); // 5 = ID3D12Resource
      // pOptimizedClearValue must be NULL for buffers; pass the bridge null
      // (the XIOM `null` literal marshals garbage on v0.64.4 -- B-23).
      let nullp = dx12_null_ptr();
      let chrr = d3d12_device_create_committed_resource(dev, hprops.as_mut_ptr(), 0,
        rdesc.as_mut_ptr(), 0, nullp, riid.as_mut_ptr(), res.as_mut_ptr());
      let resp = le64(res, 0);
      failed = failed + report(ir2 == 0 && chrr == 0 && resp != 0,
        "struct: CreateCommittedResource(buffer 256B) hr=" + to_string(chrr as Int));
      if resp != 0 {
        var rout = zeroed(D3D12_SIZEOF_RESOURCE_DESC);
        let rgr = d3d12_resource_get_desc(resp, rout.as_mut_ptr());
        let dim = le32(rout, D3D12_OFF_RESOURCE_DESC_DIMENSION);
        let width = le64(rout, D3D12_OFF_RESOURCE_DESC_WIDTH);
        let mips = le16(rout, D3D12_OFF_RESOURCE_DESC_MIP_LEVELS);
        let lay = le32(rout, D3D12_OFF_RESOURCE_DESC_LAYOUT);
        failed = failed + report(rgr == 0 && dim == 1 && width == 256 && mips == 1 && lay == 1,
          "struct: Resource::GetDesc sret (dim=" + to_string(dim) + " width=" + to_string(width)
          + " mips=" + to_string(mips) + ")");
        let _rr = d3d12_object_release(resp);
      }

      // Error path: a buffer whose Layout stays UNKNOWN (0) is rejected by
      // CreateCommittedResource (E_INVALIDARG; SPEC sec. 2/6) -- no resource
      // is produced and the HRESULT is surfaced, never swallowed.
      var badrd = zeroed(D3D12_SIZEOF_RESOURCE_DESC);
      dx12_poke_u32(badrd.as_mut_ptr(), D3D12_OFF_RESOURCE_DESC_DIMENSION, 1 as UInt32);
      dx12_poke_u64(badrd.as_mut_ptr(), D3D12_OFF_RESOURCE_DESC_WIDTH, 256 as UInt64);
      dx12_poke_u32(badrd.as_mut_ptr(), D3D12_OFF_RESOURCE_DESC_HEIGHT, 1 as UInt32);
      dx12_poke_u32(badrd.as_mut_ptr(), D3D12_OFF_RESOURCE_DESC_DEPTH_OR_ARRAY_SIZE, 0x00010001 as UInt32);
      dx12_poke_u32(badrd.as_mut_ptr(), D3D12_OFF_RESOURCE_DESC_SAMPLE_DESC, 1 as UInt32);
      var badres = zeroed(8);
      let badchr = d3d12_device_create_committed_resource(dev, hprops.as_mut_ptr(), 0,
        badrd.as_mut_ptr(), 0, nullp, riid.as_mut_ptr(), badres.as_mut_ptr());
      let badresp = le64(badres, 0);
      failed = failed + report(badchr != 0 && badresp == 0,
        "error: CreateCommittedResource UNKNOWN layout rejected (hr!=0)");

      // 0.3.0: GetResourceAllocationInfo sret + by-pointer desc param.
      var aout = zeroed(D3D12_SIZEOF_RESOURCE_ALLOCATION_INFO);
      let ahr = d3d12_device_get_resource_allocation_info(dev, 0, 1, rdesc.as_mut_ptr(), aout.as_mut_ptr());
      let asize = le64(aout, D3D12_OFF_RESOURCE_ALLOCATION_INFO_SIZE_IN_BYTES);
      let aalign = le64(aout, D3D12_OFF_RESOURCE_ALLOCATION_INFO_ALIGNMENT);
      failed = failed + report(ahr == 0 && asize == 65536 && aalign == 65536,
        "struct: GetResourceAllocationInfo sret (size=" + to_string(asize) + " align=" + to_string(aalign) + ")");

      // 0.3.0: GetCustomHeapProperties sret (no-arg struct return).  For the
      // DEFAULT heap type the runtime returns CUSTOM (4) properties.
      var hpout = zeroed(D3D12_SIZEOF_HEAP_PROPERTIES);
      let hhr = d3d12_device_get_custom_heap_properties(dev, 0, 1, hpout.as_mut_ptr());
      let hptype = le32(hpout, D3D12_OFF_HEAP_PROPERTIES_TYPE);
      failed = failed + report(hhr == 0 && hptype == 4,
        "struct: GetCustomHeapProperties sret (heap_type=" + to_string(hptype) + ")");
    }

    failed = failed + report(t_struct_meta_sizes(),
      "struct: oracle-vs-build sizeof cross-check (16 closure structs)");

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
    let blobp = le64(blob, 0);
    let errp = le64(err, 0);
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

  // 0.3.0 (b): DXGI -- factory/adapter/WARP/swapchain on dxgi.dll.
  failed = failed + report(t_dxgi_consts(),
    "dxgi: consts (BGRA8/FLIP_DISCARD/soname)");
  let dmissing = dxgi_probe_named("xiom-absent-dxgi-probe-xyz.dll");
  if dmissing.is_ok {
    failed = failed + report(false, "dxgi skip-path: bogus soname unexpectedly produced a factory");
  } else {
    failed = failed + report(dmissing.error.kind == DXGI_LOAD_ABSENT,
      "dxgi skip-path: absent runtime classified as DXGI_LOAD_ABSENT (SKIP)");
  }
  let df = dxgi_open_factory();
  if df.is_ok {
    let finfo: DxgiFactoryInfo = df.value;
    failed = failed + report(dxgi_factory_ptr() != 0,
      "dxgi: live IDXGIFactory2 pointer");
    failed = failed + report(finfo.adapter_count >= 1,
      "dxgi: EnumAdapters1 count=" + to_string(finfo.adapter_count));
    // adapter 0: generated wrapper (pointer-form GetDesc1) + struct meta read
    let a0 = dxgi_enum_adapter(0);
    failed = failed + report(a0 != 0, "dxgi: EnumAdapters1(0) adapter live");
    // Error path: an out-of-range index yields 0 (DXGI_ERROR_NOT_FOUND is
    // mapped to a null adapter -- never a stray pointer; SPEC sec. 6).
    let oob = dxgi_enum_adapter(9999);
    failed = failed + report(oob == 0, "error: EnumAdapters1(9999) out of range -> 0");
    if a0 != 0 {
      var adesc = zeroed(DXGI_SIZEOF_ADAPTER_DESC1);
      let dhr = dxgi_adapter1_get_desc1(a0, adesc.as_mut_ptr());
      let vendor = le32(adesc, DXGI_OFF_ADAPTER_DESC1_VENDOR_ID);
      failed = failed + report(dhr == 0 && vendor != 0,
        "dxgi: Adapter1::GetDesc1 vendor=" + to_string(vendor) + " (decimal)");
      let _ra = dxgi_object_release(a0);
    }
    // WARP adapter (IDXGIFactory4) + a real D3D12 device on it
    let warp = dxgi_warp_adapter();
    failed = failed + report(finfo.warp && warp != 0, "dxgi: EnumWarpAdapter live");
    if warp != 0 {
      var wdesc = zeroed(DXGI_SIZEOF_ADAPTER_DESC1);
      let whr = dxgi_adapter1_get_desc1(warp, wdesc.as_mut_ptr());
      let wvendor = le32(wdesc, DXGI_OFF_ADAPTER_DESC1_VENDOR_ID);
      // 0x1414 (Microsoft) == 5140 decimal; keep the message decimal.
      failed = failed + report(whr == 0 && wvendor == 5140,
        "dxgi: WARP vendor=" + to_string(wvendor) + " (expect 5140 == 0x1414)");
      let _rw = dxgi_object_release(warp);
    }
    let wdev = dxgi_warp_device_probe();
    failed = failed + report(wdev == 0,
      "dxgi: D3D12CreateDevice(WARP) ok (warp_status=" + to_string(wdev) + ")");
    // hidden-window BGRA8/FIFO swapchain + GetBuffer + GetDesc1 + Present
    let scst = dxgi_swapchain_probe(640, 480);
    if scst == DXGI_SWAPCHAIN_OK {
      let shr = dxgi_swapchain_hr();
      let bhr = dxgi_swapchain_buffer_hr();
      let phr = dxgi_swapchain_present_hr();
      let dw = dxgi_swapchain_desc_width();
      let dh = dxgi_swapchain_desc_height();
      let dform = dxgi_swapchain_desc_format();
      let present_ok = phr == 0 || phr == 0x087A0001; // OCCLUDED is fine (hidden)
      failed = failed + report(shr == 0 && bhr == 0 && present_ok && dw == 640 && dh == 480 && dform == 0x57,
        "dxgi: BGRA8/FIFO swapchain (swap=" + to_string(shr) + " buffer=" + to_string(bhr)
        + " present=" + to_string(phr) + " " + to_string(dw) + "x" + to_string(dh) + ")");
    } else if scst == DXGI_SWAPCHAIN_NO_DEVICE {
      failed = failed + report(true, "dxgi swapchain: SKIP -- no D3D12 device");
    } else {
      failed = failed + report(false, "dxgi swapchain: failed status=" + to_string(scst));
    }
  } else if df.error.kind == DXGI_LOAD_ABSENT {
    failed = failed + report(true, "dxgi: SKIP -- dxgi runtime not present (" + df.error.message + ")");
  } else {
    failed = failed + report(false, "dxgi: failed -- " + df.error.message);
  }
  dxgi_unload();

  // 0.3.0 (c): d3d12video.h slice -- ID3D12VideoDevice QI + a real
  // VIDEO_DECODE command list through the core device + generated wrappers.
  let vp = dx12_video_probe();
  if vp == DX12_VIDEO_OK {
    failed = failed + report(true, "video: ID3D12VideoDevice QI ok");
    // The chain (type-4 allocator -> CreateCommandList with the video IID)
    // is created C-side; the pointer comes back as a RETURN value (reliable)
    // and the generated video wrappers drive it (B-24: out-pointer reads are
    // not reliable on the XIOM side).
    let vlist = dx12_video_cmdlist_create();
    let vhr = dx12_video_cmdlist_hr();
    failed = failed + report(vhr == 0 && vlist != 0,
      "video: CreateCommandList(VIDEO_DECODE) hr=" + to_string(vhr));
    if vlist != 0 {
      let vclose = d3d12_video_decode_command_list_close(vlist);
      failed = failed + report(vclose == 0,
        "video: VideoDecodeCommandList::Close hr=" + to_string(vclose as Int));
      let _vr = d3d12_object_release(vlist);
    }
    dx12_video_cmdlist_cleanup();
  } else if vp == DX12_VIDEO_NO_DEVICE {
    failed = failed + report(true, "video: SKIP -- no D3D12 device");
  } else {
    failed = failed + report(false, "video: QI failed status=" + to_string(vp));
  }
  dx12_unload();

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
