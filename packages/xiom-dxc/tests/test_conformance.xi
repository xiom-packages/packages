// xiom.dxc conformance suite -- 100% COM surface + runtime probes.
//
// Two layers:
//   1. SURFACE (DLL-independent): the bridge's bound-method table must equal
//      the dxcapi.h oracle counts (printed as `bound=N/N`), per interface.
//      The bridge is compiled/ linked through port.args.json, so every
//      generated wrapper is type-checked and link-resolved here -- 128
//      methods across 27 interfaces.
//   2. RUNTIME (SKIP-green when dxcompiler.dll is absent): resolve
//      DxcCreateInstance at runtime, create IDxcUtils + IDxcCompiler3, compile
//      a trivial HLSL vertex shader from a string, check the DXIL container
//      magic byte-indexed, drive the error path, reflection, disassembly and
//      version info.
//
// Discipline: every out-param lands in an XIOM-owned slot read byte-indexed
// little-endian (B-11..B-20); no foreign pointer is ever read from XIOM.
//
// Build+run through the runner (compiles src/dxc_probe.c + src/dxc_bridge.cpp):
//   scripts/port.ps1 -Package xiom.dxc -TimeoutSec 900

module dxc_conformance

use xiom.io;
use xiom.dxc;
use xiom.dxc.gen_support;
use xiom.dxc.gen_runtime;
use xiom.dxc.gen_blob;
use xiom.dxc.gen_handler;
use xiom.dxc.gen_legacy;
use xiom.dxc.gen_utils;
use xiom.dxc.gen_compiler3;
use xiom.dxc.gen_result;
use xiom.dxc.gen_container;
use xiom.dxc.gen_optimizer;
use xiom.dxc.gen_validator;
use xiom.dxc.gen_pdb;
use xiom.dxc.gen_pdb2;

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

// =========================================================================
// SURFACE (no DLL needed)
// =========================================================================

fn test_surface_counts() -> Int {
  let bound = dxc_method_count();
  let oracle = DXC_ORACLE_METHODS;
  io.println("bound=" + dxc_i2s(bound) + "/" + dxc_i2s(oracle));
  io.flush_stdout();
  return report(bound == oracle && oracle == 128,
    "surface: bridge table == dxcapi.h oracle methods (bound=" + dxc_i2s(bound) + "/" + dxc_i2s(oracle) + ")");
}

fn test_surface_per_interface() -> Int {
  let ifaces = dxc_interface_count();
  var mismatches: Int = 0;
  var named: Int = 0;
  var total: Int = 0;
  var i = 0;
  while i < ifaces {
    let oracle = dxc_oracle_iface_count(i);
    let bucket = dxc_interface_method_count(i as Int32);
    if oracle != bucket { mismatches = mismatches + 1; }
    total = total + bucket;
    if dxc_interface_name(i as Int32).len() > 0 { named = named + 1; }
    i = i + 1;
  }
  let ok = mismatches == 0 && named == ifaces && total == DXC_ORACLE_METHODS
    && ifaces == DXC_ORACLE_INTERFACES;
  return report(ok,
    "surface: per-interface buckets match the oracle (" + dxc_i2s(ifaces) + " interfaces, " + dxc_i2s(total) + " methods)");
}

fn test_surface_names() -> Int {
  let n = dxc_method_count();
  var all_named = true;
  var i = 0;
  while i < n {
    if dxc_method_name(i as Int32).len() == 0 { all_named = false; }
    i = i + 1;
  }
  let first = dxc_method_name(0);
  let ok = all_named && first == "IDxcBlob::GetBufferPointer";
  return report(ok, "surface: every table entry carries its `Iface::Method` name (first=" + first + ")");
}

fn test_surface_tables() -> Int {
  let ok = dxc_iid_count() == DXC_ORACLE_INTERFACES
    && dxc_clsid_count() == 12
    && dxc_iid_index("IDxcCompiler3") >= 0
    && dxc_iid_index("IDxcResult") >= 0
    && dxc_iid_index("IDxcPdbUtils2") >= 0
    && dxc_clsid_index("CLSID_DxcCompiler") >= 0
    && dxc_clsid_index("CLSID_DxcUtils") >= 0
    && dxc_clsid_index("CLSID_DxcPdbUtils") >= 0
    && dxc_free_function_count() == 2
    && dxc_free_function_name(0) == "DxcCreateInstance"
    && dxc_free_function_name(1) == "DxcCreateInstance2";
  return report(ok, "surface: IID (27) + CLSID (12) tables and the 2 free functions are bound");
}

// =========================================================================
// RUNTIME (DLL present path; SKIP-green when absent)
// =========================================================================

fn test_skip_classification() -> Int {
  // Deterministic on every host: bogus soname -> ABSENT (the old probe path).
  let missing = dxc_probe_named("xiom-absent-dxc-probe-xyz.dll");
  if missing.is_ok {
    return report(false, "skip-path: bogus soname unexpectedly produced a compile");
  }
  return report(missing.error.kind == DXC_LOAD_ABSENT,
    "skip-path: absent compiler classified as DXC_LOAD_ABSENT (SKIP)");
}

fn test_probe_present() -> Int {
  let p = dxc_probe();
  if p.is_ok {
    let info: DxcInfo = p.value;
    return report(info.object_size > 0,
      "probe: ps_6_0 'main' -> DXIL object (" + dxc_i2s(info.object_size) + " bytes)");
  }
  if p.error.kind == DXC_LOAD_ABSENT {
    return report(true, "probe: SKIP -- compiler not present (" + p.error.message + ")");
  }
  return report(false, "probe: failed -- " + p.error.message);
}

fn test_runtime_pipeline() -> Int {
  let rc = dxc_load();
  if rc == DXC_RC_ABSENT {
    return report(true, "runtime: SKIP -- dxcompiler.dll absent (bound surface above is DLL-independent)");
  }
  if rc != DXC_RC_OK {
    return report(false, "runtime: dxcompiler.dll present but load failed -- " + dxc_error());
  }
  var failed = 0;
  failed = failed + report(dxc_resolved_free_functions() == dxc_free_function_count(),
    "runtime: DxcCreateInstance + DxcCreateInstance2 resolved at runtime");

  let utils = dxc_create_utils();
  let compiler = dxc_create_compiler();
  if utils == 0 || compiler == 0 {
    dxc_unload();
    return failed + report(false, "runtime: DxcCreateInstance(CLSID_DxcUtils/CLSID_DxcCompiler) failed -- " + dxc_error());
  }
  failed = failed + report(true, "runtime: IDxcUtils + IDxcCompiler3 created via DxcCreateInstance");

  let source = "float4 main(uint vid : SV_VertexID) : SV_Position { return float4(0.0, 0.0, 0.0, 1.0); }\n";
  let args = "-T\nvs_6_0\n-E\nmain\n";
  var src = dxc_bytes(source);

  // --- IDxcUtils::CreateBlobFromPinned + IDxcBlobEncoding::GetEncoding ---
  var pinned_slot = dxc_slot(8);
  let prc = dxc_utils_create_blob_from_pinned(utils, &mut src, src.len() as Int32, 65001 as Int32, &mut pinned_slot);
  let pinned = dxc_rd_u64(&pinned_slot);
  var pinned_ok = prc == 0 && pinned != 0;
  if prc != 0 || pinned == 0 {
    io.println("  note: CreateBlobFromPinned rc=" + dxc_i2s(prc) + " err=" + dxc_error());
  }
  if pinned_ok {
    pinned_ok = dxc_blob_get_buffer_size(pinned) == src.len();
  }
  var known_slot = dxc_slot(4);
  var page_slot = dxc_slot(4);
  if pinned_ok {
    let erc = dxc_blobencoding_get_encoding(pinned, &mut known_slot, &mut page_slot);
    pinned_ok = erc == 0 && dxc_rd_u32(&known_slot) == 1 && dxc_rd_u32(&page_slot) == 65001;
  }
  failed = failed + report(pinned_ok,
    "utils: CreateBlobFromPinned + GetEncoding round trip (utf8 pinned source)");

  // --- IDxcCompiler3::Compile + IDxcResult ---
  let iid_result = dxc_iid_index("IDxcResult");
  var status_slot = dxc_slot(4);
  var result_slot = dxc_slot(8);
  var crc = dxc_compiler3_compile(compiler, &mut src, src.len() as Int32, 0 as Int32, args, 4, 0, iid_result, &mut result_slot);
  let result = dxc_rd_u64(&result_slot);
  failed = failed + report(crc == 0 && result != 0,
    "compile: IDxcCompiler3::Compile(vs_6_0, -E main) produced an IDxcResult");
  var object_blob: Int = 0;
  var blob_ready = false;
  if result != 0 {
    let s_rc = dxc_operationresult_get_status(result, &mut status_slot);
    let status = dxc_rd_u32(&status_slot);
    failed = failed + report(s_rc == 0 && status == 0,
      "compile: GetStatus == S_OK (status=0x" + dxc_i2s(status) + ")");
    if status == 0 {
      // IDxcResult bookkeeping methods (direct scalar returns).
      let nout = dxc_result_get_num_outputs(result);
      let has_obj = dxc_result_has_output(result, 1 as Int32);
      let primary = dxc_result_primary_output(result);
      failed = failed + report(nout >= 2 && has_obj == 1 && primary == 1,
        "result: GetNumOutputs >= 2, HasOutput(OBJECT) == 1, PrimaryOutput() == DXC_OUT_OBJECT");
      var obj_slot = dxc_slot(8);
      var name_slot = dxc_slot(8);
      let blob_iid = dxc_iid_index("IDxcBlob");
      let g_rc = dxc_result_get_output(result, 1 as Int32, blob_iid, &mut obj_slot, &mut name_slot);
      object_blob = dxc_rd_u64(&obj_slot);
      if g_rc != 0 || object_blob == 0 {
        io.println("  note: GetOutput(OBJECT) rc=" + dxc_i2s(g_rc) + " err=" + dxc_error());
      }
      blob_ready = g_rc == 0 && object_blob != 0;
    }
  }
  if blob_ready {
    let size = dxc_blob_get_buffer_size(object_blob);
    var head = dxc_slot(16);
    var head_len = dxc_slot(4);
    let c_rc = dxc_blob_get_buffer_pointer(object_blob, &mut head, &mut head_len);
    let full = dxc_rd_u32(&head_len);
    let magic_ok = head[0] as Int == 68 && head[1] as Int == 88
      && head[2] as Int == 66 && head[3] as Int == 67;
    failed = failed + report(c_rc == 0 && size > 0 && size % 4 == 0 && full == size && magic_ok,
      "compile: DXC_OUT_OBJECT blob (" + dxc_i2s(size) + " bytes) starts with 'DXBC' (byte-indexed)");
  } else {
    failed = failed + report(false, "compile: no result object");
  }

  // --- error path ---
  let bad = "float4 main() : SV_Target { this is not hlsl; }\n";
  var bad_src = dxc_bytes(bad);
  var bad_status_slot = dxc_slot(4);
  var bad_result_slot = dxc_slot(8);
  let brc = dxc_compiler3_compile(compiler, &mut bad_src, bad_src.len() as Int32, 0 as Int32, args, 4, 0, iid_result, &mut bad_result_slot);
  let bad_result = dxc_rd_u64(&bad_result_slot);
  var err_ok = false;
  if brc == 0 && bad_result != 0 {
    let bs_rc = dxc_operationresult_get_status(bad_result, &mut bad_status_slot);
    let bstatus = dxc_rd_u32(&bad_status_slot);
    var err_slot = dxc_slot(8);
    var err_name = dxc_slot(8);
    let ge_rc = dxc_result_get_output(bad_result, 2 as Int32, dxc_iid_index("IDxcBlobEncoding"), &mut err_slot, &mut err_name);
    let err_blob = dxc_rd_u64(&err_slot);
    let err_size = dxc_blob_get_buffer_size(err_blob);
    var err_head = dxc_slot(16);
    var err_len = dxc_slot(4);
    let ec_rc = dxc_blob_get_buffer_pointer(err_blob, &mut err_head, &mut err_len);
    err_ok = bs_rc == 0 && bstatus != 0 && ge_rc == 0 && ec_rc == 0 && err_size > 0;
    if err_blob != 0 { dxc_release(err_blob); }
    if bad_result != 0 { dxc_release(bad_result); }
  }
  failed = failed + report(err_ok,
    "compile: bad HLSL -> nonzero status + non-empty DXC_OUT_ERRORS blob");

  // --- IDxcVersionInfo via QueryInterface ---
  var vi_ok = false;
  let vi = dxc_query_interface(compiler, dxc_iid_index("IDxcVersionInfo"));
  if vi != 0 {
    var major_slot = dxc_slot(4);
    var minor_slot = dxc_slot(4);
    var flags_slot = dxc_slot(4);
    let v1 = dxc_versioninfo_get_version(vi, &mut major_slot, &mut minor_slot);
    let v2 = dxc_versioninfo_get_flags(vi, &mut flags_slot);
    vi_ok = v1 == 0 && v2 == 0 && dxc_rd_u32(&major_slot) == 1;
    dxc_release(vi);
  }
  failed = failed + report(vi_ok,
    "version: QueryInterface(IDxcVersionInfo) -> GetVersion major == 1, GetFlags readable");

  // --- class factory coverage: every CLSID the bridge exposes ---
  var created = 0;
  var attempted = 0;
  let c_args = dxc_create_compiler_args();
  attempted = attempted + 1;
  if c_args != 0 { created = created + 1; dxc_release(c_args); }
  let c_lib = dxc_create_library();
  attempted = attempted + 1;
  if c_lib != 0 { created = created + 1; dxc_release(c_lib); } else { io.println("  note: CLSID_DxcLibrary/IDxcLibrary not creatable"); }
  let c_linker = dxc_create_linker();
  attempted = attempted + 1;
  if c_linker != 0 { created = created + 1; dxc_release(c_linker); } else { io.println("  note: CLSID_DxcLinker not creatable"); }
  let c_validator = dxc_create_validator();
  attempted = attempted + 1;
  if c_validator != 0 { created = created + 1; dxc_release(c_validator); } else { io.println("  note: CLSID_DxcValidator not creatable"); }
  let c_assembler = dxc_create_assembler();
  attempted = attempted + 1;
  if c_assembler != 0 { created = created + 1; dxc_release(c_assembler); } else { io.println("  note: CLSID_DxcAssembler not creatable"); }
  let c_refl = dxc_create_container_reflection();
  attempted = attempted + 1;
  if c_refl != 0 { created = created + 1; dxc_release(c_refl); } else { io.println("  note: CLSID_DxcContainerReflection not creatable"); }
  let c_opt = dxc_create_optimizer();
  attempted = attempted + 1;
  if c_opt != 0 { created = created + 1; dxc_release(c_opt); } else { io.println("  note: CLSID_DxcOptimizer not creatable"); }
  let c_builder = dxc_create_container_builder();
  attempted = attempted + 1;
  if c_builder != 0 { created = created + 1; dxc_release(c_builder); } else { io.println("  note: CLSID_DxcContainerBuilder not creatable"); }
  let c_pdb = dxc_create_pdb_utils();
  attempted = attempted + 1;
  if c_pdb != 0 { created = created + 1; dxc_release(c_pdb); } else { io.println("  note: CLSID_DxcPdbUtils/IDxcPdbUtils2 not creatable"); }
  failed = failed + report(created >= 9,
    "factory: " + dxc_i2s(created) + "/" + dxc_i2s(attempted) + " CLSIDs create via DxcCreateInstance");

  // --- IDxcContainerReflection on the compiled DXIL container ---
  var refl_ok = false;
  if object_blob != 0 {
    let refl = dxc_create_container_reflection();
    if refl != 0 {
      let l_rc = dxc_containerreflection_load(refl, object_blob);
      var count_slot = dxc_slot(4);
      let pc_rc = dxc_containerreflection_get_part_count(refl, &mut count_slot);
      let part_count = dxc_rd_u32(&count_slot);
      var kind_slot = dxc_slot(4);
      let dxil_fourcc = 68 + 88 * 256 + 73 * 65536 + 76 * 16777216;
      let f_rc = dxc_containerreflection_find_first_part_kind(refl, dxil_fourcc as Int32, &mut kind_slot);
      let found = dxc_rd_u32(&kind_slot);
      refl_ok = l_rc == 0 && pc_rc == 0 && part_count >= 2 && f_rc == 0 && found < part_count;
      dxc_release(refl);
    }
  }
  failed = failed + report(refl_ok,
    "container: reflection Load + GetPartCount + FindFirstPartKind('DXIL')");

  // --- IDxcCompiler3::Disassemble on the container bytes ---
  var dis_ok = false;
  if object_blob != 0 {
    var obj_probe = dxc_slot(16);
    var obj_len = dxc_slot(4);
    let cp_rc = dxc_blob_get_buffer_pointer(object_blob, &mut obj_probe, &mut obj_len);
    let total = dxc_rd_u32(&obj_len);
    var obj_copy = dxc_slot(total);
    var obj_copy_len = dxc_slot(4);
    let cp2_rc = dxc_blob_get_buffer_pointer(object_blob, &mut obj_copy, &mut obj_copy_len);
    var dis_result_slot = dxc_slot(8);
    let drc = dxc_compiler3_disassemble(compiler, &mut obj_copy, total, 0 as Int32, iid_result, &mut dis_result_slot);
    let dis_result = dxc_rd_u64(&dis_result_slot);
    if cp_rc == 0 && cp2_rc == 0 && drc == 0 && dis_result != 0 {
      var d_status = dxc_slot(4);
      let ds_rc = dxc_operationresult_get_status(dis_result, &mut d_status);
      var d_slot = dxc_slot(8);
      var d_name = dxc_slot(8);
      let dg_rc = dxc_result_get_output(dis_result, 5 as Int32, dxc_iid_index("IDxcBlob"), &mut d_slot, &mut d_name);
      let d_blob = dxc_rd_u64(&d_slot);
      let d_size = dxc_blob_get_buffer_size(d_blob);
      dis_ok = ds_rc == 0 && dxc_rd_u32(&d_status) == 0 && dg_rc == 0 && d_size > 0;
      if d_blob != 0 { dxc_release(d_blob); }
      dxc_release(dis_result);
    }
    if dis_ok == false {
      // leave a diagnostic in the failure path only
      io.println("  note: disassemble probe failed; err=" + dxc_error());
    }
  }
  failed = failed + report(dis_ok,
    "disasm: Disassemble(container) -> DXC_OUT_DISASSEMBLY blob with size > 0");

  // --- IDxcIncludeHandler (default handler, missing file = clean failure) ---
  var handler_ok = false;
  var handler_slot = dxc_slot(8);
  let h0_rc = dxc_utils_create_default_include_handler(utils, &mut handler_slot);
  let handler = dxc_rd_u64(&handler_slot);
  if h0_rc == 0 && handler != 0 {
    var inc_slot = dxc_slot(8);
    let hrc = dxc_includehandler_load_source(handler, "xiom-dxc-no-such-include.h", &mut inc_slot);
    let inc_blob = dxc_rd_u64(&inc_slot);
    handler_ok = hrc != 0 && inc_blob == 0;
    dxc_release(handler);
  }
  failed = failed + report(handler_ok,
    "handler: default include handler resolves and reports missing files as failure");

  // --- lifecycle: AddRef/Release balance ---
  let refs = dxc_addref(compiler);
  dxc_release(compiler);
  failed = failed + report(refs >= 1, "lifecycle: AddRef/Release on IDxcCompiler3");

  if object_blob != 0 { dxc_release(object_blob); }
  if result != 0 { dxc_release(result); }
  if pinned != 0 { dxc_release(pinned); }
  dxc_release(compiler);
  dxc_release(utils);
  dxc_unload();
  return failed;
}

fn main() -> Int {
  io.println("=== xiom.dxc conformance tests (100% COM surface + runtime) ===");
  io.flush_stdout();
  var total = 0;
  var failed = 0;

  let r1 = test_surface_counts();
  total = total + 1; failed = failed + r1;
  let r2 = test_surface_per_interface();
  total = total + 1; failed = failed + r2;
  let r3 = test_surface_names();
  total = total + 1; failed = failed + r3;
  let r4 = test_surface_tables();
  total = total + 1; failed = failed + r4;
  let r5 = test_skip_classification();
  total = total + 1; failed = failed + r5;
  let r6 = test_probe_present();
  total = total + 1; failed = failed + r6;
  let r7 = test_runtime_pipeline();
  total = total + 1; failed = failed + r7;

  if failed == 0 {
    io.println("xiom.dxc: all tests passed");
  } else {
    io.println("xiom.dxc: tests failed");
  }
  io.flush_stdout();
  return failed;
}
