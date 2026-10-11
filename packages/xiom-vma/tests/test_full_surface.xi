// xiom.vma full-surface suite -- 100% of the top-level vma* API (oracle:
// Vulkan SDK 1.4.350.0 include/vma/vk_mem_alloc.h, VMA v3.3.0).
//
// Coverage check: bridge-exposed wrapper count == oracle count, printed as
// `bound=N/N`; link proof references every generated wrapper.  Functional
// probes run the package's RHI path through the generated wrappers:
// device setup -> vmaCreateAllocator -> vmaCreateBuffer ->
// vmaGetAllocationInfo -> vmaDestroyBuffer -> vmaDestroyAllocator ->
// teardown, plus the null-argument error path.
//
// Build+run (the --c-source entry rides in port.args.json):
//   scripts/port.ps1 -Package xiom.vma -Suite tests/test_full_surface.xi

module vma_full_surface

use xiom.io;
use xiom.test;
use xiom.vma.full_ffi;
use xiom.vma.full_rhi;
use xiom.vma.full_buffer;

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

fn i2s(n: Int) -> Str {
  if n == 0 { return "0"; }
  var neg = false;
  var v = n;
  if v < 0 {
    neg = true;
    v = 0 - v;
  }
  var buf = "";
  while v > 0 {
    let digit = v % 10;
    v = v / 10;
    if digit == 0 { buf = "0" + buf; }
    elif digit == 1 { buf = "1" + buf; }
    elif digit == 2 { buf = "2" + buf; }
    elif digit == 3 { buf = "3" + buf; }
    elif digit == 4 { buf = "4" + buf; }
    elif digit == 5 { buf = "5" + buf; }
    elif digit == 6 { buf = "6" + buf; }
    elif digit == 7 { buf = "7" + buf; }
    elif digit == 8 { buf = "8" + buf; }
    elif digit == 9 { buf = "9" + buf; }
  }
  if neg { return "-" + buf; }
  return buf;
}

fn main() -> Int {
  io.println("=== xiom.vma full-surface tests (oracle vk_mem_alloc.h v3.3.0) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // ---- 1. coverage: oracle vs bound vs link -------------------------------
  let oracle = surface_oracle();
  let bound = surface_count();
  let linked = link_proof_count();
  io.println("bound=" + i2s(bound) + "/" + i2s(oracle));
  io.flush_stdout();

  failed = failed + report(bound == oracle,
    "coverage: bridge exports == oracle (" + i2s(bound) + "/" + i2s(oracle) + ")");
  failed = failed + report(oracle == VMA_FULL_ORACLE_COUNT,
    "coverage: runtime oracle == generated const (" + i2s(oracle) + ")");
  failed = failed + report(linked == oracle,
    "coverage: every wrapper linked (" + i2s(linked) + ")");
  failed = failed + report(VMA_FULL_ORACLE_COUNT == 72,
    "coverage: oracle pinned at 72 (SDK 1.4.350.0 vk_mem_alloc.h)");

  let n0 = "vmaImportVulkanFunctionsFromVolk";
  let n1 = "vmaCreateAllocator";
  let nl = "vmaFreeStatsString";
  failed = failed + report(surface_name_is(0, n0),
    "surface: export[0] == " + n0);
  failed = failed + report(surface_name_is(1, n1),
    "surface: export[1] == " + n1);
  failed = failed + report(surface_name_is(oracle - 1, nl),
    "surface: export[last] == " + nl);

  // ---- 2. null-argument error path (bridge guards) ------------------------
  let mask = error_probe_mask();
  failed = failed + report(mask == ERROR_PROBE_EXPECTED,
    "error path: null-arg guard bitmask == 0 (" + i2s(mask) + ")");

  // Direct call from XIOM through a generated family wrapper: all-null args
  // are classified by the bridge guard, never a crash.
  let direct: Int32 = vma_full_create_buffer(0, 0, 0, 0, 0, 0);
  failed = failed + report(direct == VK_ERROR_INITIALIZATION_FAILED,
    "error path: typed wrapper null args -> " + i2s(direct as Int));

  // ---- 3. RHI path on the live device (or SKIP classification) ------------
  let slot = rhi_setup();
  if slot <= RHI_SKIP_LOADER {
    failed = failed + report(true, "rhi: SKIP -- loader/device/queue absent (" + i2s(slot) + ")");
  } elif slot <= 0 {
    failed = failed + report(false, "rhi: setup failed (" + i2s(slot) + ")");
  } else {
    let r1 = rhi_allocator_create(slot);
    failed = failed + report(r1 == VK_SUCCESS,
      "rhi: vmaCreateAllocator (wrapper) res=" + i2s(r1 as Int));
    let a = rhi_slot_allocator(slot);
    failed = failed + report(a != 0, "rhi: allocator handle non-null");
    if r1 == VK_SUCCESS {
      let r2 = rhi_buffer_create(slot, 65536);
      failed = failed + report(r2 == VK_SUCCESS,
        "rhi: vmaCreateBuffer (wrapper) res=" + i2s(r2 as Int));
      let buf = rhi_buffer_handle(slot);
      let alloc = rhi_allocation_handle(slot);
      failed = failed + report(buf != 0 && alloc != 0, "rhi: buffer + allocation handles");
      let r3 = rhi_allocation_info(slot);
      failed = failed + report(r3 == 0,
        "rhi: vmaGetAllocationInfo (wrapper)");
      let sz = rhi_info_size(slot);
      failed = failed + report(sz == 65536,
        "rhi: getAllocationInfo size = " + i2s(sz));
      let mt = rhi_info_memory_type(slot);
      failed = failed + report(mt >= 0,
        "rhi: getAllocationInfo memoryType = " + i2s(mt as Int));
      let dm = rhi_info_device_memory(slot);
      failed = failed + report(dm != 0, "rhi: getAllocationInfo deviceMemory bound");
      let wr = rhi_win32_handle_probe(slot);
      failed = failed + report(wr == VK_SUCCESS || wr == VK_ERROR_FEATURE_NOT_PRESENT,
        "rhi: vmaGetMemoryWin32Handle probe res=" + i2s(wr as Int));
      let rd = rhi_buffer_destroy(slot);
      failed = failed + report(rd == 0, "rhi: vmaDestroyBuffer (wrapper)");
    }
    let ra = rhi_allocator_destroy(slot);
    failed = failed + report(ra == 0, "rhi: vmaDestroyAllocator (wrapper)");
    let rt = rhi_teardown(slot);
    failed = failed + report(rt == 0, "rhi: device teardown");
  }

  if failed == 0 {
    io.println("xiom.vma full surface: all tests passed");
  } else {
    io.println("xiom.vma full surface: tests failed (" + i2s(failed) + ")");
  }
  return failed;
}
