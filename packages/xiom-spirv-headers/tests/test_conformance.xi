// xiom.spirv.headers conformance suite -- constants-only (no DLL, no resolver).
//
// The oracle is the shipped SPIR-V header
//   C:\VulkanSDK\1.4.350.0\Include\spirv-headers\spirv.h
// (byte-identical to KhronosGroup/SPIRV-Headers @ vulkan-sdk-1.4.350.0).
// The generator (tools/gen_spirv_headers.py) parses every Spv* enum value and
// macro into the src/spv_consts_*.xi family modules and records the emitted
// counts in tools/spirv_manifest.json.  This suite checks:
//   - the emitted-count constants (SPV_CONST_COUNT etc.) against the manifest
//     numbers, plus the header version facts;
//   - spot checks of well-known values verified from the oracle header
//     (SpvOpTypeVoid == 19, SpvExecutionModelVertex == 0,
//      SpvStorageClassUniform == 2, SpvCapabilityShader == 1, ...);
//   - one bucket-boundary value per SpvOp split module;
//   - the oracle sha256 string.
//
// Build+run (no extra compiler args):
//   xiom --run tests/test_conformance.xi
//
// Module namespace note: the modules are `xiom.spirv_headers` (root) and
// `xiom.spirv_headers.<family>`, not `xiom.spirv.headers.<family>`: the
// pin's checker resolves only the LAST of several sibling imports of a
// four-segment module path (see AUDIT.md "compiler finding").  Package name
// is unaffected (`xiom.spirv.headers`).

module spirv_headers_conformance

use xiom.io;
use xiom.string.compare;
use xiom.spirv_headers;
use xiom.spirv_headers.core;
use xiom.spirv_headers.image;
use xiom.spirv_headers.fp;
use xiom.spirv_headers.decorations;
use xiom.spirv_headers.controls;
use xiom.spirv_headers.capabilities;
use xiom.spirv_headers.ops_core;
use xiom.spirv_headers.ops_4000;
use xiom.spirv_headers.ops_5000;
use xiom.spirv_headers.ops_6000;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
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

// ---- emitted counts + header facts (must match tools/spirv_manifest.json) --

fn t_meta() -> Bool {
  var ok = true;
  // tools/spirv_manifest.json: const_count=2385, enum_count=2378,
  // enum_type_count=74 (2 macros + 5 static consts + 2378 enumerators).
  if SPV_CONST_COUNT != 2385 { ok = false; }
  if SPV_ENUM_COUNT != 2378 { ok = false; }
  if SPV_ENUM_TYPE_COUNT != 74 { ok = false; }
  // Internal consistency: 7 non-enum constants (SPV_VERSION, SPV_REVISION,
  // SpvMagicNumber, SpvVersion, SpvRevision, SpvOpCodeMask, SpvWordCountShift).
  if SPV_CONST_COUNT != SPV_ENUM_COUNT + 7 { ok = false; }
  // #define SPV_VERSION 0x10600 / SPV_REVISION 1 (SPIR-V 1.6 rev 1).
  if SPV_VERSION != 0x10600 { ok = false; }
  if SPV_REVISION != 1 { ok = false; }
  // static const unsigned int facts from the header.
  if SpvMagicNumber != 0x07230203 { ok = false; }
  if SpvVersion != 0x00010600 { ok = false; }
  if SpvRevision != 1 { ok = false; }
  if SpvOpCodeMask != 0xffff { ok = false; }
  if SpvWordCountShift != 16 { ok = false; }
  // Oracle spirv.h sha256 (same value recorded in the manifest).
  if !streq(SPV_HEADER_SHA256,
      "93F82C0B51984974E60485C126945C40F264B89FD4D395A580A1BC59D211E24E") {
    ok = false;
  }
  return ok;
}

// ---- opcodes: core range (module ops_core) --------------------------------

fn t_ops_core() -> Bool {
  var ok = true;
  if SpvOpNop != 0 { ok = false; }
  if SpvOpEntryPoint != 15 { ok = false; }
  if SpvOpExecutionMode != 16 { ok = false; }
  if SpvOpTypeVoid != 19 { ok = false; }
  if SpvOpTypeInt != 21 { ok = false; }
  if SpvOpTypeFloat != 22 { ok = false; }
  if SpvOpTypeVector != 23 { ok = false; }
  if SpvOpTypeStruct != 30 { ok = false; }
  if SpvOpTypePointer != 32 { ok = false; }
  if SpvOpConstant != 43 { ok = false; }
  if SpvOpFunction != 54 { ok = false; }
  if SpvOpFunctionCall != 57 { ok = false; }
  if SpvOpVariable != 59 { ok = false; }
  if SpvOpLoad != 61 { ok = false; }
  if SpvOpStore != 62 { ok = false; }
  if SpvOpAccessChain != 65 { ok = false; }
  if SpvOpDecorate != 71 { ok = false; }
  if SpvOpVectorShuffle != 79 { ok = false; }
  if SpvOpCompositeConstruct != 80 { ok = false; }
  if SpvOpIAdd != 128 { ok = false; }
  if SpvOpFAdd != 129 { ok = false; }
  if SpvOpFMul != 133 { ok = false; }
  if SpvOpLoopMerge != 246 { ok = false; }
  if SpvOpSelectionMerge != 247 { ok = false; }
  if SpvOpLabel != 248 { ok = false; }
  if SpvOpBranch != 249 { ok = false; }
  if SpvOpBranchConditional != 250 { ok = false; }
  if SpvOpReturn != 253 { ok = false; }
  return ok;
}

// ---- opcodes: extension buckets (modules ops_4000/5000/6000) --------------

fn t_ops_buckets() -> Bool {
  var ok = true;
  // ops_4000: first vendor-assigned value and a well-known EXT op.
  if SpvOpColorAttachmentReadEXT != 4160 { ok = false; }
  if SpvOpTerminateInvocation != 4416 { ok = false; }
  // ops_5000: AMD group op + NV partition + KHR ray query entry.
  if SpvOpGroupIAddNonUniformAMD != 5000 { ok = false; }
  if SpvOpGroupNonUniformPartitionNV != 5296 { ok = false; }
  // ops_6000: KHR ray-query readback ops + the SpvOpMax sentinel.
  if SpvOpRayQueryGetRayTMinKHR != 6016 { ok = false; }
  if SpvOpRayQueryGetIntersectionTKHR != 6018 { ok = false; }
  if SpvOpMax != 0x7fffffff { ok = false; }
  return ok;
}

// ---- execution model / storage class / addressing (module core) ------------

fn t_models_storage() -> Bool {
  var ok = true;
  if SpvExecutionModelVertex != 0 { ok = false; }
  if SpvExecutionModelFragment != 4 { ok = false; }
  if SpvExecutionModelGLCompute != 5 { ok = false; }
  if SpvExecutionModeOriginUpperLeft != 7 { ok = false; }
  if SpvExecutionModeLocalSize != 17 { ok = false; }
  if SpvStorageClassUniformConstant != 0 { ok = false; }
  if SpvStorageClassUniform != 2 { ok = false; }
  if SpvStorageClassWorkgroup != 4 { ok = false; }
  if SpvStorageClassFunction != 7 { ok = false; }
  if SpvStorageClassPushConstant != 9 { ok = false; }
  if SpvStorageClassStorageBuffer != 12 { ok = false; }
  if SpvAddressingModelLogical != 0 { ok = false; }
  return ok;
}

// ---- memory model / source language / dims (module core) -------------------

fn t_memory_source_dim() -> Bool {
  var ok = true;
  if SpvMemoryModelGLSL450 != 1 { ok = false; }
  if SpvMemoryModelVulkan != 3 { ok = false; }
  if SpvSourceLanguageGLSL != 2 { ok = false; }
  if SpvSourceLanguageHLSL != 5 { ok = false; }
  if SpvSourceLanguageSlang != 11 { ok = false; }
  if SpvSourceLanguageRust != 13 { ok = false; }
  if SpvDim2D != 1 { ok = false; }
  if SpvDim3D != 2 { ok = false; }
  return ok;
}

// ---- capabilities (module capabilities) ------------------------------------

fn t_capabilities() -> Bool {
  var ok = true;
  if SpvCapabilityMatrix != 0 { ok = false; }
  if SpvCapabilityShader != 1 { ok = false; }
  if SpvCapabilityGeometry != 2 { ok = false; }
  if SpvCapabilityFloat64 != 10 { ok = false; }
  if SpvCapabilityInt64 != 11 { ok = false; }
  if SpvCapabilityGroups != 18 { ok = false; }
  if SpvCapabilityStorageImageExtendedFormats != 49 { ok = false; }
  if SpvCapabilityRayTracingKHR != 4479 { ok = false; }
  if SpvCapabilityMeshShadingNV != 5266 { ok = false; }
  if SpvCapabilityVulkanMemoryModel != 5345 { ok = false; }
  return ok;
}

// ---- decorations + built-ins (module decorations) --------------------------

fn t_decorations_builtins() -> Bool {
  var ok = true;
  if SpvDecorationSpecId != 1 { ok = false; }
  if SpvDecorationBlock != 2 { ok = false; }
  if SpvDecorationBuiltIn != 11 { ok = false; }
  if SpvDecorationLocation != 30 { ok = false; }
  if SpvDecorationBinding != 33 { ok = false; }
  if SpvDecorationDescriptorSet != 34 { ok = false; }
  if SpvDecorationOffset != 35 { ok = false; }
  if SpvBuiltInPosition != 0 { ok = false; }
  if SpvBuiltInFragCoord != 15 { ok = false; }
  if SpvBuiltInWorkgroupSize != 25 { ok = false; }
  if SpvBuiltInGlobalInvocationId != 28 { ok = false; }
  if SpvBuiltInVertexIndex != 42 { ok = false; }
  return ok;
}

// ---- image families (module image) -----------------------------------------

fn t_image() -> Bool {
  var ok = true;
  if SpvImageFormatUnknown != 0 { ok = false; }
  if SpvImageFormatRgba32f != 1 { ok = false; }
  if SpvImageChannelOrderR != 0 { ok = false; }
  if SpvImageChannelOrderRGBA != 5 { ok = false; }
  if SpvImageChannelDataTypeSnormInt8 != 0 { ok = false; }
  if SpvImageOperandsMaskNone != 0 { ok = false; }
  if SpvImageOperandsBiasMask != 0x00000001 { ok = false; }
  if SpvImageOperandsLodMask != 0x00000002 { ok = false; }
  return ok;
}

// ---- control/memory masks (module controls) --------------------------------

fn t_masks() -> Bool {
  var ok = true;
  if SpvMemorySemanticsAcquireReleaseMask != 0x00000008 { ok = false; }
  if SpvMemorySemanticsSequentiallyConsistentMask != 0x00000010 { ok = false; }
  if SpvMemorySemanticsUniformMemoryMask != 0x00000040 { ok = false; }
  if SpvMemoryAccessVolatileMask != 0x00000001 { ok = false; }
  if SpvFunctionControlInlineMask != 0x00000001 { ok = false; }
  if SpvSelectionControlFlattenMask != 0x00000001 { ok = false; }
  if SpvLoopControlUnrollMask != 0x00000001 { ok = false; }
  if SpvLoopControlDontUnrollMask != 0x00000002 { ok = false; }
  if SpvRayFlagsOpaqueKHRMask != 0x00000001 { ok = false; }
  return ok;
}

// ---- fp/misc modes (modules fp + controls) ---------------------------------

fn t_misc_modes() -> Bool {
  var ok = true;
  if SpvFPFastMathModeNotNaNMask != 0x00000001 { ok = false; }
  if SpvFPFastMathModeFastMask != 0x00000010 { ok = false; }
  if SpvFPRoundingModeRTE != 0 { ok = false; }
  if SpvSamplerFilterModeLinear != 1 { ok = false; }
  if SpvScopeDevice != 1 { ok = false; }
  if SpvGroupOperationReduce != 0 { ok = false; }
  if SpvKernelEnqueueFlagsNoWait != 0 { ok = false; }
  if SpvLinkageTypeExport != 0 { ok = false; }
  if SpvAccessQualifierReadOnly != 0 { ok = false; }
  if SpvFunctionParameterAttributeNoAlias != 4 { ok = false; }
  if SpvCooperativeMatrixUseMatrixAKHR != 0 { ok = false; }
  if SpvStoreCacheControlWriteBackINTEL != 2 { ok = false; }
  if SpvRayQueryCommittedIntersectionTypeRayQueryCommittedIntersectionTriangleKHR
      != 1 {
    ok = false;
  }
  return ok;
}

fn main() -> Int {
  io.println("=== xiom.spirv.headers conformance tests (constants-only) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + report(t_meta(),
    "meta: emitted counts vs manifest (const=" + to_string(SPV_CONST_COUNT)
      + " enum=" + to_string(SPV_ENUM_COUNT) + " types="
      + to_string(SPV_ENUM_TYPE_COUNT) + ", SPV_VERSION=0x10600, sha256 ok)");
  failed = failed + report(t_ops_core(), "ops_core: 28 well-known core opcodes");
  failed = failed + report(t_ops_buckets(), "ops buckets: 4xxx/5xxx/6xxx + SpvOpMax sentinel");
  failed = failed + report(t_models_storage(), "core: execution models/modes + storage classes");
  failed = failed + report(t_memory_source_dim(), "core: memory models + source languages + dims");
  failed = failed + report(t_capabilities(), "capabilities: core + extension values");
  failed = failed + report(t_decorations_builtins(), "decorations + built-ins");
  failed = failed + report(t_image(), "image: formats/channel orders/operand masks");
  failed = failed + report(t_masks(), "controls: memory/function/selection/loop/ray masks");
  failed = failed + report(t_misc_modes(), "fp/misc: fast-math/rounding/scope/group/store modes");

  if failed == 0 {
    io.println("xiom.spirv.headers: all tests passed");
  } else {
    io.println("xiom.spirv.headers: tests failed");
  }
  return failed;
}
