// xiom.vulkan SDK100 struct-metadata check.
//
// Compiles every generated struct_meta_* module (sizes + member offsets,
// emitted by tools/gen_struct_meta.py from a clang-offsetof dump against the
// SDK headers) and spot-asserts known 64-bit Windows layouts.
//
// Run (repo root):
//   . scripts\xiom.ps1; $t=Resolve-XiomToolchain; $env:XIOM_STDLIB=$t.Stdlib
//   & $t.Xiom --run <this file abs path>

module vulkan_struct_meta_check

use xiom.io;
use xiom.convert;
use xiom.vulkan.struct_meta_1;
use xiom.vulkan.struct_meta_2;
use xiom.vulkan.struct_meta_3;
use xiom.vulkan.struct_meta_4;
use xiom.vulkan.struct_meta_5;
use xiom.vulkan.struct_meta_6;
use xiom.vulkan.struct_meta_7;
use xiom.vulkan.struct_meta_8;
use xiom.vulkan.struct_meta_9;
use xiom.vulkan.struct_meta_10;
use xiom.vulkan.struct_meta_11;
use xiom.vulkan.struct_meta_12;
use xiom.vulkan.struct_meta_13;
use xiom.vulkan.struct_meta_14;
use xiom.vulkan.struct_meta_15;
use xiom.vulkan.struct_meta_16;
use xiom.vulkan.struct_meta_17;
use xiom.vulkan.struct_meta_18;
use xiom.vulkan.struct_meta_19;

fn main() -> Int {
  var fails: Int = 0;
  if VK_SIZEOF_VK_APPLICATION_INFO != 48 { fails = fails + 1; io.println("FAIL VK_SIZEOF_VK_APPLICATION_INFO"); }
  if VK_SIZEOF_VK_INSTANCE_CREATE_INFO != 64 { fails = fails + 1; io.println("FAIL VK_SIZEOF_VK_INSTANCE_CREATE_INFO"); }
  if VK_OFF_VK_INSTANCE_CREATE_INFO_FLAGS != 16 { fails = fails + 1; io.println("FAIL VK_OFF_VK_INSTANCE_CREATE_INFO_FLAGS"); }
  if VK_OFF_VK_INSTANCE_CREATE_INFO_P_APPLICATION_INFO != 24 { fails = fails + 1; io.println("FAIL VK_OFF_VK_INSTANCE_CREATE_INFO_P_APPLICATION_INFO"); }
  if VK_SIZEOF_VK_PHYSICAL_DEVICE_PROPERTIES != 824 { fails = fails + 1; io.println("FAIL VK_SIZEOF_VK_PHYSICAL_DEVICE_PROPERTIES"); }
  if VK_OFF_VK_PHYSICAL_DEVICE_PROPERTIES_API_VERSION != 0 { fails = fails + 1; io.println("FAIL VK_OFF_VK_PHYSICAL_DEVICE_PROPERTIES_API_VERSION"); }
  if VK_SIZEOF_VK_CLEAR_COLOR_VALUE != 16 { fails = fails + 1; io.println("FAIL VK_SIZEOF_VK_CLEAR_COLOR_VALUE"); }
  if VK_OFF_VK_SWAPCHAIN_CREATE_INFO_KHR_OLD_SWAPCHAIN != 96 { fails = fails + 1; io.println("FAIL VK_OFF_VK_SWAPCHAIN_CREATE_INFO_KHR_OLD_SWAPCHAIN"); }
  if VK_SIZEOF_VK_GRAPHICS_PIPELINE_CREATE_INFO != 144 { fails = fails + 1; io.println("FAIL VK_SIZEOF_VK_GRAPHICS_PIPELINE_CREATE_INFO"); }
  if fails != 0 {
    io.println("struct-meta: FAIL (" + to_string(fails) + " spot checks)");
    return 1;
  }
  io.println("struct-meta: PASS (19 modules compiled; spot checks on known layouts)");
  return 0;
}
