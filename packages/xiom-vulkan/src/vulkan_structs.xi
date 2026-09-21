// XIOM -- Vulkan Struct Builders
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Typed helpers for building VK create-info structs.
// Because XIOM lacks C struct support, all operations write scalar values at
// known byte offsets through the C bridge (xvk_alloc / xvk_write_*).
//
// LAYOUT NOTE: All `build_*` create-info builders use the REAL Vulkan
// x86_64 C ABI layout (natural alignment: sType at 0, pNext at 8, pointers
// 8-byte aligned). The returned Int handles are raw C pointers that can be
// passed directly to vkCreate* / vkAllocate* / vkQueueSubmit etc.
// Free them with free_struct() once the Vulkan call has returned.
//
// VK constants used (literal values to avoid cross-module const gaps):
//   VK_STRUCTURE_TYPE_* sType tags are inlined per builder (see comments;
//   authoritative list: src/vulkan_constants_all.xi)
//   VK_API_VERSION_1_0 = 4194304  (0x00400000)
//   VK_API_VERSION_1_4 = 4210688  (0x00404000)

module xiom.vulkan.structs

// ---------------------------------------------------------------------------
// C bridge externs (bridge/xvk_structs.c) -- raw struct memory helpers
// ---------------------------------------------------------------------------

extern "C" {
  // Allocate `size` bytes of zero-filled C heap memory. Returns 0 on failure.
  fn xvk_alloc(size: Int) -> Int;
  // Free memory previously returned by xvk_alloc.
  fn xvk_free(p: Int);
  // Write a 32-bit value at (base + offset).
  fn xvk_write_u32(base: Int, offset: Int, value: Int32);
  // Write a 64-bit value (pointer / handle / VkDeviceSize) at (base + offset).
  fn xvk_write_u64(base: Int, offset: Int, value: Int);
  // Write a 32-bit float at (base + offset).
  fn xvk_write_f32(base: Int, offset: Int, value: Float32);
  // Store a NUL-terminated copy of `value` and write its pointer at (base + offset).
  fn xvk_write_str(base: Int, offset: Int, value: Str);
  // Write the VkStructureType tag at offset 0.
  fn xvk_set_sType(base: Int, s_type: Int32);
  // Write the pNext chain pointer at offset 8.
  fn xvk_set_pNext(base: Int, p_next: Int);
  // Read-back helpers (debugging / struct inspection).
  fn xvk_read_u32(base: Int, offset: Int) -> Int32;
  fn xvk_read_u64(base: Int, offset: Int) -> Int;
  fn xvk_read_f32(base: Int, offset: Int) -> Float32;
}

// ---------------------------------------------------------------------------
// Thin wrappers over the bridge externs (single unsafe site per primitive)
// ---------------------------------------------------------------------------

// Allocate a struct block via the C bridge. Returns 0 on failure.
fn xalloc(size: Int) -> Int
  requires: size > 0
{
  return unsafe { xvk_alloc(size) };
}

// Free a bridge allocation (no-op for 0).
fn xfree(p: Int) {
  if p != 0 {
    unsafe { xvk_free(p); }
  }
}

// Write an Int32 field at (base + offset).
fn xw32(base: Int, offset: Int, value: Int32) {
  unsafe { xvk_write_u32(base, offset, value); }
}

// Write a 64-bit field (pointer / handle / size) at (base + offset).
fn xw64(base: Int, offset: Int, value: Int) {
  unsafe { xvk_write_u64(base, offset, value); }
}

// Write a Float32 field at (base + offset).
fn xwf32(base: Int, offset: Int, value: Float32) {
  unsafe { xvk_write_f32(base, offset, value); }
}

// Write a raw C string at (base + offset).
// The bridge stores a malloc'd copy, so `s` need not outlive the struct.
fn xwstr(base: Int, offset: Int, s: Str) {
  unsafe { xvk_write_str(base, offset, s); }
}

// Write the sType tag (offset 0).
fn xstype(base: Int, s_type: Int32) {
  unsafe { xvk_set_sType(base, s_type); }
}

// Write the pNext pointer (offset 8).
fn xpnext(base: Int, p_next: Int) {
  unsafe { xvk_set_pNext(base, p_next); }
}

// Public read-back helpers for inspecting built structs.
pub fn read_u32(base: Int, offset: Int) -> Int32
  requires: base != 0
{
  return unsafe { xvk_read_u32(base, offset) };
}

pub fn read_u64(base: Int, offset: Int) -> Int
  requires: base != 0
{
  return unsafe { xvk_read_u64(base, offset) };
}

pub fn read_f32(base: Int, offset: Int) -> Float32
  requires: base != 0
{
  return unsafe { xvk_read_f32(base, offset) };
}

// ---------------------------------------------------------------------------
// Internal: build a `const char*` pointer array via the bridge.
// Allocates `count * 8` bytes and writes each string's raw C pointer.
// Returns 0 for an empty vec (valid Vulkan NULL for ppEnabledLayerNames etc.)
// and 0 on allocation failure.
// ---------------------------------------------------------------------------

fn build_cstr_array(strings: Vec[Str]) -> Int {
  let count = strings.len();
  if count == 0 { return 0; }
  let buf = xalloc(count * 8);
  if buf == 0 { return 0; }
  var i = 0;
  while i < count {
    xwstr(buf, i * 8, strings[i]);
    i = i + 1;
  }
  return buf;
}

// ---------------------------------------------------------------------------
// VkApplicationInfo
//
// Layout (48 bytes, natural alignment):
//   Offset    Field                  Type      Value
//       0     sType                  Int32     VK_STRUCTURE_TYPE_APPLICATION_INFO (0)
//       4     (padding)
//       8     pNext                  Int       0
//      16     pApplicationName       Int       raw str ptr
//      24     applicationVersion     Int32     VK_API_VERSION_1_0
//      28     (padding)
//      32     pEngineName            Int       raw str ptr
//      40     engineVersion          Int32     VK_API_VERSION_1_0
//      44     apiVersion             Int32     caller-supplied
// ---------------------------------------------------------------------------

pub fn build_application_info(app_name: Str, engine_name: Str, api_version: Int32) -> Int {
  let s = xalloc(48);
  if s == 0 { return 0; }
  xstype(s, 0);                  // sType = VK_STRUCTURE_TYPE_APPLICATION_INFO
  xpnext(s, 0);                  // pNext = null
  xwstr(s, 16, app_name);        // pApplicationName
  xw32(s, 24, 4194304);          // applicationVersion = VK_API_VERSION_1_0
  xwstr(s, 32, engine_name);     // pEngineName
  xw32(s, 40, 4194304);          // engineVersion = VK_API_VERSION_1_0
  xw32(s, 44, api_version);      // apiVersion (e.g. 4210688 = VK_API_VERSION_1_4)
  return s;
}

// ---------------------------------------------------------------------------
// VkInstanceCreateInfo
//
// Layout (64 bytes, natural alignment):
//   Offset    Field                     Type      Value
//       0     sType                     Int32     VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO (1)
//       8     pNext                     Int       0
//      16     flags                     Int32     0
//      24     pApplicationInfo          Int       app_info ptr or 0
//      32     enabledLayerCount         Int32
//      40     ppEnabledLayerNames       Int       layer ptr-array or 0
//      48     enabledExtensionCount     Int32
//      56     ppEnabledExtensionNames   Int       ext ptr-array or 0
// ---------------------------------------------------------------------------

pub fn build_instance_create_info(app_info: Int, layers: Vec[Str], extensions: Vec[Str]) -> Int {
  let layer_names = build_cstr_array(layers);
  if layers.len() > 0 {
    if layer_names == 0 { return 0; }
  }
  let ext_names = build_cstr_array(extensions);
  if extensions.len() > 0 {
    if ext_names == 0 { return 0; }
  }

  let s = xalloc(64);
  if s == 0 { return 0; }
  xstype(s, 1);                            // sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
  xpnext(s, 0);                            // pNext = null
  xw32(s, 16, 0);                          // flags = 0
  xw64(s, 24, app_info);                   // pApplicationInfo
  xw32(s, 32, layers.len() as Int32);      // enabledLayerCount
  xw64(s, 40, layer_names);                // ppEnabledLayerNames
  xw32(s, 48, extensions.len() as Int32);  // enabledExtensionCount
  xw64(s, 56, ext_names);                  // ppEnabledExtensionNames
  return s;
}

// ---------------------------------------------------------------------------
// VkDescriptorSetLayoutBinding
//
// Layout (24 bytes):
//   Offset    Field                 Type
//       0     binding               Int32
//       4     descriptorType        Int32
//       8     descriptorCount       Int32
//      12     stageFlags            Int32
//      16     pImmutableSamplers    Int       (always 0 / null)
// ---------------------------------------------------------------------------

pub fn build_desc_set_layout_binding(
  binding: Int32,
  desc_type: Int32,
  count: Int32,
  stages: Int32
) -> Int {
  let s = xalloc(24);
  if s == 0 { return 0; }
  xw32(s, 0, binding);
  xw32(s, 4, desc_type);
  xw32(s, 8, count);
  xw32(s, 12, stages);
  xw64(s, 16, 0);  // pImmutableSamplers = null
  return s;
}

// ---------------------------------------------------------------------------
// VkDeviceQueueCreateInfo
//
// Layout (40 bytes, natural alignment):
//   Offset    Field                Type      Value
//       0     sType                Int32     VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO (2)
//       8     pNext                Int       0
//      16     flags                Int32     0
//      20     queueFamilyIndex     Int32
//      24     queueCount           Int32
//      32     pQueuePriorities     Int       ptr to `count` Float32s (bridge-allocated)
// ---------------------------------------------------------------------------

pub fn build_device_queue_create_info(family: Int32, count: Int32, priority: Float32) -> Int {
  let n = count as Int;
  if n <= 0 { return 0; }
  let priorities = xalloc(n * 4);
  if priorities == 0 { return 0; }
  var i = 0;
  while i < n {
    xwf32(priorities, i * 4, priority);
    i = i + 1;
  }

  let s = xalloc(40);
  if s == 0 {
    xfree(priorities);
    return 0;
  }
  xstype(s, 2);              // sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO
  xpnext(s, 0);              // pNext = null
  xw32(s, 16, 0);            // flags = 0
  xw32(s, 20, family);       // queueFamilyIndex
  xw32(s, 24, count);        // queueCount
  xw64(s, 32, priorities);   // pQueuePriorities (same priority for every queue)
  return s;
}

// ---------------------------------------------------------------------------
// VkDeviceCreateInfo
//
// Layout (72 bytes, natural alignment):
//   Offset    Field                     Type      Value
//       0     sType                     Int32     VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO (3)
//       8     pNext                     Int       0
//      16     flags                     Int32     0
//      20     queueCreateInfoCount      Int32
//      24     pQueueCreateInfos         Int       contiguous VkDeviceQueueCreateInfo array
//      32     enabledLayerCount         Int32     0 (deprecated)
//      40     ppEnabledLayerNames       Int       0 (deprecated)
//      48     enabledExtensionCount     Int32
//      56     ppEnabledExtensionNames   Int       ext ptr-array or 0
//      64     pEnabledFeatures          Int       VkPhysicalDeviceFeatures ptr or 0
// ---------------------------------------------------------------------------

pub fn build_device_create_info(queue_infos: Int, queue_count: Int32, extensions: Vec[Str], features: Int) -> Int {
  let ext_names = build_cstr_array(extensions);
  if extensions.len() > 0 {
    if ext_names == 0 { return 0; }
  }

  let s = xalloc(72);
  if s == 0 { return 0; }
  xstype(s, 3);                            // sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO
  xpnext(s, 0);                            // pNext = null
  xw32(s, 16, 0);                          // flags = 0
  xw32(s, 20, queue_count);                // queueCreateInfoCount
  xw64(s, 24, queue_infos);                // pQueueCreateInfos
  xw32(s, 32, 0);                          // enabledLayerCount (deprecated) = 0
  xw64(s, 40, 0);                          // ppEnabledLayerNames (deprecated) = null
  xw32(s, 48, extensions.len() as Int32);  // enabledExtensionCount
  xw64(s, 56, ext_names);                  // ppEnabledExtensionNames
  xw64(s, 64, features);                   // pEnabledFeatures
  return s;
}

// ---------------------------------------------------------------------------
// VkBufferCreateInfo
//
// Layout (56 bytes, natural alignment):
//   Offset    Field                    Type      Value
//       0     sType                    Int32     VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO (12)
//       8     pNext                    Int       0
//      16     flags                    Int32     0
//      24     size                     Int       VkDeviceSize
//      32     usage                    Int32
//      36     sharingMode              Int32
//      40     queueFamilyIndexCount    Int32
//      48     pQueueFamilyIndices      Int       ptr to Int32 array or 0
// ---------------------------------------------------------------------------

pub fn build_buffer_create_info(size: Int, usage: Int32, sharing_mode: Int32, queue_family_count: Int32, queue_families: Int) -> Int {
  let s = xalloc(56);
  if s == 0 { return 0; }
  xstype(s, 12);                     // sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO
  xpnext(s, 0);                      // pNext = null
  xw32(s, 16, 0);                    // flags = 0
  xw64(s, 24, size);                 // size
  xw32(s, 32, usage);                // usage
  xw32(s, 36, sharing_mode);         // sharingMode
  xw32(s, 40, queue_family_count);   // queueFamilyIndexCount
  xw64(s, 48, queue_families);       // pQueueFamilyIndices
  return s;
}

// ---------------------------------------------------------------------------
// VkImageCreateInfo
//
// Layout (88 bytes, natural alignment):
//   Offset    Field                    Type      Value
//       0     sType                    Int32     VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO (14)
//       8     pNext                    Int       0
//      16     flags                    Int32     0
//      20     imageType                Int32
//      24     format                   Int32
//      28     extent.width             Int32
//      32     extent.height            Int32
//      36     extent.depth             Int32
//      40     mipLevels                Int32
//      44     arrayLayers              Int32
//      48     samples                  Int32
//      52     tiling                   Int32
//      56     usage                    Int32
//      60     sharingMode              Int32
//      64     queueFamilyIndexCount    Int32
//      72     pQueueFamilyIndices      Int       ptr to Int32 array or 0
//      80     initialLayout            Int32
// ---------------------------------------------------------------------------

pub fn build_image_create_info(
  image_type: Int32,
  format: Int32,
  extent_w: Int32,
  extent_h: Int32,
  extent_d: Int32,
  mip_levels: Int32,
  array_layers: Int32,
  samples: Int32,
  tiling: Int32,
  usage: Int32,
  sharing_mode: Int32,
  queue_family_count: Int32,
  queue_families: Int,
  initial_layout: Int32
) -> Int {
  let s = xalloc(88);
  if s == 0 { return 0; }
  xstype(s, 14);                     // sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO
  xpnext(s, 0);                      // pNext = null
  xw32(s, 16, 0);                    // flags = 0
  xw32(s, 20, image_type);           // imageType
  xw32(s, 24, format);               // format
  xw32(s, 28, extent_w);             // extent.width
  xw32(s, 32, extent_h);             // extent.height
  xw32(s, 36, extent_d);             // extent.depth
  xw32(s, 40, mip_levels);           // mipLevels
  xw32(s, 44, array_layers);         // arrayLayers
  xw32(s, 48, samples);              // samples
  xw32(s, 52, tiling);               // tiling
  xw32(s, 56, usage);                // usage
  xw32(s, 60, sharing_mode);         // sharingMode
  xw32(s, 64, queue_family_count);   // queueFamilyIndexCount
  xw64(s, 72, queue_families);       // pQueueFamilyIndices
  xw32(s, 80, initial_layout);       // initialLayout
  return s;
}

// ---------------------------------------------------------------------------
// VkImageViewCreateInfo
//
// Layout (80 bytes, natural alignment):
//   Offset    Field                           Type      Value
//       0     sType                           Int32     VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO (15)
//       8     pNext                           Int       0
//      16     flags                           Int32     0
//      24     image                           Int       VkImage handle
//      32     viewType                        Int32
//      36     format                          Int32
//      40     components.r                    Int32
//      44     components.g                    Int32
//      48     components.b                    Int32
//      52     components.a                    Int32
//      56     subresourceRange.aspectMask     Int32
//      60     subresourceRange.baseMipLevel   Int32
//      64     subresourceRange.levelCount     Int32     VK_REMAINING_MIP_LEVELS
//      68     subresourceRange.baseArrayLayer Int32
//      72     subresourceRange.layerCount     Int32
// ---------------------------------------------------------------------------

pub fn build_image_view_create_info(
  image: Int,
  view_type: Int32,
  format: Int32,
  components_r: Int32,
  components_g: Int32,
  components_b: Int32,
  components_a: Int32,
  subresource_aspect: Int32,
  subresource_mip: Int32,
  subresource_layer: Int32,
  subresource_layers: Int32
) -> Int {
  let s = xalloc(80);
  if s == 0 { return 0; }
  // VK_REMAINING_MIP_LEVELS = 0xFFFFFFFF: view covers all mips from base.
  let remaining_mips: Int32 = (0 - 1) as Int32;
  xstype(s, 15);                     // sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO
  xpnext(s, 0);                      // pNext = null
  xw32(s, 16, 0);                    // flags = 0
  xw64(s, 24, image);                // image
  xw32(s, 32, view_type);            // viewType
  xw32(s, 36, format);               // format
  xw32(s, 40, components_r);         // components.r
  xw32(s, 44, components_g);         // components.g
  xw32(s, 48, components_b);         // components.b
  xw32(s, 52, components_a);         // components.a
  xw32(s, 56, subresource_aspect);   // subresourceRange.aspectMask
  xw32(s, 60, subresource_mip);      // subresourceRange.baseMipLevel
  xw32(s, 64, remaining_mips);       // subresourceRange.levelCount
  xw32(s, 68, subresource_layer);    // subresourceRange.baseArrayLayer
  xw32(s, 72, subresource_layers);   // subresourceRange.layerCount
  return s;
}

// ---------------------------------------------------------------------------
// VkSamplerCreateInfo
//
// Layout (80 bytes, natural alignment):
//   Offset    Field                      Type      Value
//       0     sType                      Int32     VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO (31)
//       8     pNext                      Int       0
//      16     flags                      Int32     0
//      20     magFilter                  Int32
//      24     minFilter                  Int32
//      28     mipmapMode                 Int32
//      32     addressModeU               Int32
//      36     addressModeV               Int32
//      40     addressModeW               Int32
//      44     mipLodBias                 Float32
//      48     anisotropyEnable           Int32     1 if anisotropy > 0
//      52     maxAnisotropy              Float32   anisotropy as Float32
//      56     compareEnable              Int32
//      60     compareOp                  Int32
//      64     minLod                     Float32
//      68     maxLod                     Float32
//      72     borderColor                Int32
//      76     unnormalizedCoordinates    Int32
// ---------------------------------------------------------------------------

pub fn build_sampler_create_info(
  mag_filter: Int32,
  min_filter: Int32,
  mipmap_mode: Int32,
  address_u: Int32,
  address_v: Int32,
  address_w: Int32,
  mip_lod_bias: Float32,
  anisotropy: Int32,
  compare_enable: Int32,
  compare_op: Int32,
  min_lod: Float32,
  max_lod: Float32,
  border_color: Int32,
  unnormalized: Int32
) -> Int {
  let s = xalloc(80);
  if s == 0 { return 0; }
  var aniso_enable: Int32 = 0;
  if anisotropy > 0 { aniso_enable = 1; }
  xstype(s, 31);                          // sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO
  xpnext(s, 0);                           // pNext = null
  xw32(s, 16, 0);                         // flags = 0
  xw32(s, 20, mag_filter);                // magFilter
  xw32(s, 24, min_filter);                // minFilter
  xw32(s, 28, mipmap_mode);               // mipmapMode
  xw32(s, 32, address_u);                 // addressModeU
  xw32(s, 36, address_v);                 // addressModeV
  xw32(s, 40, address_w);                 // addressModeW
  xwf32(s, 44, mip_lod_bias);             // mipLodBias
  xw32(s, 48, aniso_enable);              // anisotropyEnable
  xwf32(s, 52, anisotropy as Float32);    // maxAnisotropy
  xw32(s, 56, compare_enable);            // compareEnable
  xw32(s, 60, compare_op);                // compareOp
  xwf32(s, 64, min_lod);                  // minLod
  xwf32(s, 68, max_lod);                  // maxLod
  xw32(s, 72, border_color);              // borderColor
  xw32(s, 76, unnormalized);              // unnormalizedCoordinates
  return s;
}

// ---------------------------------------------------------------------------
// VkShaderModuleCreateInfo
//
// Layout (40 bytes, natural alignment):
//   Offset    Field       Type      Value
//       0     sType       Int32     VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO (16)
//       8     pNext       Int       0
//      16     flags       Int32     0
//      24     codeSize    Int       byte size of SPIR-V blob (size_t)
//      32     pCode       Int       ptr to SPIR-V words
// ---------------------------------------------------------------------------

pub fn build_shader_module_create_info(code_size: Int, code_data: Int) -> Int {
  let s = xalloc(40);
  if s == 0 { return 0; }
  xstype(s, 16);          // sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO
  xpnext(s, 0);           // pNext = null
  xw32(s, 16, 0);         // flags = 0
  xw64(s, 24, code_size); // codeSize
  xw64(s, 32, code_data); // pCode
  return s;
}

// ---------------------------------------------------------------------------
// VkPipelineLayoutCreateInfo
//
// Layout (48 bytes, natural alignment):
//   Offset    Field                     Type      Value
//       0     sType                     Int32     VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO (30)
//       8     pNext                     Int       0
//      16     flags                     Int32     0
//      20     setLayoutCount            Int32
//      24     pSetLayouts               Int       ptr to VkDescriptorSetLayout array or 0
//      32     pushConstantRangeCount    Int32
//      40     pPushConstantRanges       Int       ptr to VkPushConstantRange array or 0
// ---------------------------------------------------------------------------

pub fn build_pipeline_layout_create_info(set_layout_count: Int32, set_layouts: Int, push_constant_range_count: Int32, push_constant_ranges: Int) -> Int {
  let s = xalloc(48);
  if s == 0 { return 0; }
  xstype(s, 30);                          // sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO
  xpnext(s, 0);                           // pNext = null
  xw32(s, 16, 0);                         // flags = 0
  xw32(s, 20, set_layout_count);          // setLayoutCount
  xw64(s, 24, set_layouts);               // pSetLayouts
  xw32(s, 32, push_constant_range_count); // pushConstantRangeCount
  xw64(s, 40, push_constant_ranges);      // pPushConstantRanges
  return s;
}

// ---------------------------------------------------------------------------
// VkDescriptorSetLayoutBinding (bridge-allocated variant; no sType/pNext)
//
// Layout (24 bytes, natural alignment):
//   Offset    Field                 Type      Value
//       0     binding               Int32
//       4     descriptorType        Int32
//       8     descriptorCount       Int32
//      12     stageFlags            Int32
//      16     pImmutableSamplers    Int       ptr to VkSampler array or 0
// ---------------------------------------------------------------------------

pub fn build_descriptor_set_layout_binding(binding: Int32, desc_type: Int32, count: Int32, stage_flags: Int32, samplers: Int) -> Int {
  let s = xalloc(24);
  if s == 0 { return 0; }
  xw32(s, 0, binding);       // binding
  xw32(s, 4, desc_type);     // descriptorType
  xw32(s, 8, count);         // descriptorCount
  xw32(s, 12, stage_flags);  // stageFlags
  xw64(s, 16, samplers);     // pImmutableSamplers
  return s;
}

// ---------------------------------------------------------------------------
// VkDescriptorSetLayoutCreateInfo
//
// Layout (32 bytes, natural alignment):
//   Offset    Field           Type      Value
//       0     sType           Int32     VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO (32)
//       8     pNext           Int       0
//      16     flags           Int32     0
//      20     bindingCount    Int32
//      24     pBindings       Int       contiguous VkDescriptorSetLayoutBinding array
// ---------------------------------------------------------------------------

pub fn build_descriptor_set_layout_create_info(binding_count: Int32, bindings: Int) -> Int {
  let s = xalloc(32);
  if s == 0 { return 0; }
  xstype(s, 32);             // sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO
  xpnext(s, 0);              // pNext = null
  xw32(s, 16, 0);            // flags = 0
  xw32(s, 20, binding_count); // bindingCount
  xw64(s, 24, bindings);     // pBindings
  return s;
}

// ---------------------------------------------------------------------------
// VkDescriptorPoolSize (no sType/pNext)
//
// Layout (8 bytes):
//   Offset    Field              Type
//       0     type               Int32
//       4     descriptorCount    Int32
// ---------------------------------------------------------------------------

pub fn build_descriptor_pool_size(desc_type: Int32, count: Int32) -> Int {
  let s = xalloc(8);
  if s == 0 { return 0; }
  xw32(s, 0, desc_type);  // type
  xw32(s, 4, count);      // descriptorCount
  return s;
}

// ---------------------------------------------------------------------------
// VkDescriptorPoolCreateInfo
//
// Layout (40 bytes, natural alignment):
//   Offset    Field            Type      Value
//       0     sType            Int32     VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO (33)
//       8     pNext            Int       0
//      16     flags            Int32
//      20     maxSets          Int32
//      24     poolSizeCount    Int32
//      32     pPoolSizes       Int       contiguous VkDescriptorPoolSize array
// ---------------------------------------------------------------------------

pub fn build_descriptor_pool_create_info(flags: Int32, max_sets: Int32, pool_size_count: Int32, pool_sizes: Int) -> Int {
  let s = xalloc(40);
  if s == 0 { return 0; }
  xstype(s, 33);               // sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO
  xpnext(s, 0);                // pNext = null
  xw32(s, 16, flags);          // flags
  xw32(s, 20, max_sets);       // maxSets
  xw32(s, 24, pool_size_count); // poolSizeCount
  xw64(s, 32, pool_sizes);     // pPoolSizes
  return s;
}

// ---------------------------------------------------------------------------
// VkDescriptorSetAllocateInfo
//
// Layout (40 bytes, natural alignment):
//   Offset    Field                 Type      Value
//       0     sType                 Int32     VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO (34)
//       8     pNext                 Int       0
//      16     descriptorPool        Int       VkDescriptorPool handle
//      24     descriptorSetCount    Int32
//      32     pSetLayouts           Int       ptr to VkDescriptorSetLayout array
// ---------------------------------------------------------------------------

pub fn build_descriptor_set_allocate_info(pool: Int, set_layout_count: Int32, set_layouts: Int) -> Int {
  let s = xalloc(40);
  if s == 0 { return 0; }
  xstype(s, 34);                 // sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO
  xpnext(s, 0);                  // pNext = null
  xw64(s, 16, pool);             // descriptorPool
  xw32(s, 24, set_layout_count); // descriptorSetCount
  xw64(s, 32, set_layouts);      // pSetLayouts
  return s;
}

// ---------------------------------------------------------------------------
// VkWriteDescriptorSet (buffer flavor: pBufferInfo set, others null)
//
// Layout (64 bytes, natural alignment):
//   Offset    Field                Type      Value
//       0     sType                Int32     VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET (35)
//       8     pNext                Int       0
//      16     dstSet               Int       VkDescriptorSet handle
//      24     dstBinding           Int32
//      28     dstArrayElement      Int32
//      32     descriptorCount      Int32
//      36     descriptorType       Int32
//      40     pImageInfo           Int       0
//      48     pBufferInfo          Int       contiguous VkDescriptorBufferInfo array
//      56     pTexelBufferView     Int       0
// ---------------------------------------------------------------------------

pub fn build_write_descriptor_set_buffer(dst_set: Int, binding: Int32, element: Int32, desc_type: Int32, buffer_info_count: Int32, buffer_infos: Int) -> Int {
  let s = xalloc(64);
  if s == 0 { return 0; }
  xstype(s, 35);                  // sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET
  xpnext(s, 0);                   // pNext = null
  xw64(s, 16, dst_set);           // dstSet
  xw32(s, 24, binding);           // dstBinding
  xw32(s, 28, element);           // dstArrayElement
  xw32(s, 32, buffer_info_count); // descriptorCount
  xw32(s, 36, desc_type);         // descriptorType
  xw64(s, 40, 0);                 // pImageInfo = null
  xw64(s, 48, buffer_infos);      // pBufferInfo
  xw64(s, 56, 0);                 // pTexelBufferView = null
  return s;
}

// ---------------------------------------------------------------------------
// VkRenderPassCreateInfo -- simplified; the caller builds the attachment,
// subpass, and dependency arrays separately.
//
// Layout (64 bytes, natural alignment):
//   Offset    Field              Type      Value
//       0     sType              Int32     VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO (38)
//       8     pNext              Int       0
//      16     flags              Int32     0
//      20     attachmentCount    Int32
//      24     pAttachments       Int       VkAttachmentDescription array or 0
//      32     subpassCount       Int32
//      40     pSubpasses         Int       VkSubpassDescription array
//      48     dependencyCount    Int32
//      56     pDependencies      Int       VkSubpassDependency array or 0
// ---------------------------------------------------------------------------

pub fn build_render_pass_create_info(attachment_count: Int32, attachments: Int, subpass_count: Int32, subpasses: Int, dependency_count: Int32, dependencies: Int) -> Int {
  let s = xalloc(64);
  if s == 0 { return 0; }
  xstype(s, 38);                  // sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO
  xpnext(s, 0);                   // pNext = null
  xw32(s, 16, 0);                 // flags = 0
  xw32(s, 20, attachment_count);  // attachmentCount
  xw64(s, 24, attachments);       // pAttachments
  xw32(s, 32, subpass_count);     // subpassCount
  xw64(s, 40, subpasses);         // pSubpasses
  xw32(s, 48, dependency_count);  // dependencyCount
  xw64(s, 56, dependencies);      // pDependencies
  return s;
}

// ---------------------------------------------------------------------------
// VkFramebufferCreateInfo
//
// Layout (64 bytes, natural alignment):
//   Offset    Field              Type      Value
//       0     sType              Int32     VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO (37)
//       8     pNext              Int       0
//      16     flags              Int32     0
//      24     renderPass         Int       VkRenderPass handle
//      32     attachmentCount    Int32
//      40     pAttachments       Int       ptr to VkImageView array
//      48     width              Int32
//      52     height             Int32
//      56     layers             Int32
// ---------------------------------------------------------------------------

pub fn build_framebuffer_create_info(render_pass: Int, attachment_count: Int32, attachments: Int, width: Int32, height: Int32, layers: Int32) -> Int {
  let s = xalloc(64);
  if s == 0 { return 0; }
  xstype(s, 37);                  // sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO
  xpnext(s, 0);                   // pNext = null
  xw32(s, 16, 0);                 // flags = 0
  xw64(s, 24, render_pass);       // renderPass
  xw32(s, 32, attachment_count);  // attachmentCount
  xw64(s, 40, attachments);       // pAttachments
  xw32(s, 48, width);             // width
  xw32(s, 52, height);            // height
  xw32(s, 56, layers);            // layers
  return s;
}

// ---------------------------------------------------------------------------
// VkCommandPoolCreateInfo
//
// Layout (24 bytes, natural alignment):
//   Offset    Field               Type      Value
//       0     sType               Int32     VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO (39)
//       8     pNext               Int       0
//      16     flags               Int32
//      20     queueFamilyIndex    Int32
// ---------------------------------------------------------------------------

pub fn build_command_pool_create_info(flags: Int32, queue_family: Int32) -> Int {
  let s = xalloc(24);
  if s == 0 { return 0; }
  xstype(s, 39);              // sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO
  xpnext(s, 0);               // pNext = null
  xw32(s, 16, flags);         // flags
  xw32(s, 20, queue_family);  // queueFamilyIndex
  return s;
}

// ---------------------------------------------------------------------------
// VkCommandBufferAllocateInfo
//
// Layout (32 bytes, natural alignment):
//   Offset    Field                 Type      Value
//       0     sType                 Int32     VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO (40)
//       8     pNext                 Int       0
//      16     commandPool           Int       VkCommandPool handle
//      24     level                 Int32
//      28     commandBufferCount    Int32
// ---------------------------------------------------------------------------

pub fn build_command_buffer_allocate_info(pool: Int, level: Int32, count: Int32) -> Int {
  let s = xalloc(32);
  if s == 0 { return 0; }
  xstype(s, 40);       // sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO
  xpnext(s, 0);        // pNext = null
  xw64(s, 16, pool);   // commandPool
  xw32(s, 24, level);  // level
  xw32(s, 28, count);  // commandBufferCount
  return s;
}

// ---------------------------------------------------------------------------
// VkFenceCreateInfo
//
// Layout (24 bytes, natural alignment):
//   Offset    Field    Type      Value
//       0     sType    Int32     VK_STRUCTURE_TYPE_FENCE_CREATE_INFO (8)
//       8     pNext    Int       0
//      16     flags    Int32     e.g. VK_FENCE_CREATE_SIGNALED_BIT (1)
// ---------------------------------------------------------------------------

pub fn build_fence_create_info(flags: Int32) -> Int {
  let s = xalloc(24);
  if s == 0 { return 0; }
  xstype(s, 8);        // sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO
  xpnext(s, 0);        // pNext = null
  xw32(s, 16, flags);  // flags
  return s;
}

// ---------------------------------------------------------------------------
// VkSemaphoreCreateInfo
//
// Layout (24 bytes, natural alignment):
//   Offset    Field    Type      Value
//       0     sType    Int32     VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO (9)
//       8     pNext    Int       0
//      16     flags    Int32     reserved, 0
// ---------------------------------------------------------------------------

pub fn build_semaphore_create_info(flags: Int32) -> Int {
  let s = xalloc(24);
  if s == 0 { return 0; }
  xstype(s, 9);        // sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO
  xpnext(s, 0);        // pNext = null
  xw32(s, 16, flags);  // flags
  return s;
}

// ---------------------------------------------------------------------------
// VkSwapchainCreateInfoKHR
//
// Layout (104 bytes, natural alignment):
//   Offset    Field                    Type      Value
//       0     sType                    Int32     VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR (1000001000)
//       8     pNext                    Int       0
//      16     flags                    Int32     0
//      24     surface                  Int       VkSurfaceKHR handle
//      32     minImageCount            Int32
//      36     imageFormat              Int32
//      40     imageColorSpace          Int32
//      44     imageExtent.width        Int32
//      48     imageExtent.height       Int32
//      52     imageArrayLayers         Int32
//      56     imageUsage               Int32
//      60     imageSharingMode         Int32
//      64     queueFamilyIndexCount    Int32
//      72     pQueueFamilyIndices      Int       ptr to Int32 array or 0
//      80     preTransform             Int32
//      84     compositeAlpha           Int32
//      88     presentMode              Int32
//      92     clipped                  Int32
//      96     oldSwapchain             Int       VkSwapchainKHR handle or 0
// ---------------------------------------------------------------------------

pub fn build_swapchain_create_info(
  surface: Int,
  min_image_count: Int32,
  format: Int32,
  color_space: Int32,
  extent_w: Int32,
  extent_h: Int32,
  array_layers: Int32,
  usage: Int32,
  sharing_mode: Int32,
  queue_family_count: Int32,
  queue_families: Int,
  pre_transform: Int32,
  composite_alpha: Int32,
  present_mode: Int32,
  clipped: Int32,
  old_swapchain: Int
) -> Int {
  let s = xalloc(104);
  if s == 0 { return 0; }
  xstype(s, 1000001000);             // sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR
  xpnext(s, 0);                      // pNext = null
  xw32(s, 16, 0);                    // flags = 0
  xw64(s, 24, surface);              // surface
  xw32(s, 32, min_image_count);      // minImageCount
  xw32(s, 36, format);               // imageFormat
  xw32(s, 40, color_space);          // imageColorSpace
  xw32(s, 44, extent_w);             // imageExtent.width
  xw32(s, 48, extent_h);             // imageExtent.height
  xw32(s, 52, array_layers);         // imageArrayLayers
  xw32(s, 56, usage);                // imageUsage
  xw32(s, 60, sharing_mode);         // imageSharingMode
  xw32(s, 64, queue_family_count);   // queueFamilyIndexCount
  xw64(s, 72, queue_families);       // pQueueFamilyIndices
  xw32(s, 80, pre_transform);        // preTransform
  xw32(s, 84, composite_alpha);      // compositeAlpha
  xw32(s, 88, present_mode);         // presentMode
  xw32(s, 92, clipped);              // clipped
  xw64(s, 96, old_swapchain);        // oldSwapchain
  return s;
}

// ---------------------------------------------------------------------------
// VkQueryPoolCreateInfo
//
// Layout (32 bytes, natural alignment):
//   Offset    Field                 Type      Value
//       0     sType                 Int32     VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO (11)
//       8     pNext                 Int       0
//      16     flags                 Int32
//      20     queryType             Int32
//      24     queryCount            Int32
//      28     pipelineStatistics    Int32
// ---------------------------------------------------------------------------

pub fn build_query_pool_create_info(flags: Int32, query_type: Int32, count: Int32, pipeline_stats: Int32) -> Int {
  let s = xalloc(32);
  if s == 0 { return 0; }
  xstype(s, 11);                // sType = VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO
  xpnext(s, 0);                 // pNext = null
  xw32(s, 16, flags);           // flags
  xw32(s, 20, query_type);      // queryType
  xw32(s, 24, count);           // queryCount
  xw32(s, 28, pipeline_stats);  // pipelineStatistics
  return s;
}

// ---------------------------------------------------------------------------
// VkMemoryAllocateInfo
//
// Layout (32 bytes, natural alignment):
//   Offset    Field              Type      Value
//       0     sType              Int32     VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO (5)
//       8     pNext              Int       0
//      16     allocationSize     Int       VkDeviceSize
//      24     memoryTypeIndex    Int32
// ---------------------------------------------------------------------------

pub fn build_memory_allocate_info(size: Int, memory_type_index: Int32) -> Int {
  let s = xalloc(32);
  if s == 0 { return 0; }
  xstype(s, 5);                    // sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO
  xpnext(s, 0);                    // pNext = null
  xw64(s, 16, size);               // allocationSize
  xw32(s, 24, memory_type_index);  // memoryTypeIndex
  return s;
}

// ---------------------------------------------------------------------------
// VkMappedMemoryRange
//
// Layout (40 bytes, natural alignment):
//   Offset    Field     Type      Value
//       0     sType     Int32     VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE (6)
//       8     pNext     Int       0
//      16     memory    Int       VkDeviceMemory handle
//      24     offset    Int       VkDeviceSize
//      32     size      Int       VkDeviceSize (or VK_WHOLE_SIZE)
// ---------------------------------------------------------------------------

pub fn build_mapped_memory_range(memory: Int, offset: Int, size: Int) -> Int {
  let s = xalloc(40);
  if s == 0 { return 0; }
  xstype(s, 6);         // sType = VK_STRUCTURE_TYPE_MAPPED_MEMORY_RANGE
  xpnext(s, 0);         // pNext = null
  xw64(s, 16, memory);  // memory
  xw64(s, 24, offset);  // offset
  xw64(s, 32, size);    // size
  return s;
}

// ---------------------------------------------------------------------------
// VkSubmitInfo
//
// Layout (72 bytes, natural alignment):
//   Offset    Field                   Type      Value
//       0     sType                   Int32     VK_STRUCTURE_TYPE_SUBMIT_INFO (4)
//       8     pNext                   Int       0
//      16     waitSemaphoreCount      Int32
//      24     pWaitSemaphores         Int       ptr to VkSemaphore array or 0
//      32     pWaitDstStageMask       Int       ptr to Int32 stage-mask array or 0
//      40     commandBufferCount      Int32
//      48     pCommandBuffers         Int       ptr to VkCommandBuffer array
//      56     signalSemaphoreCount    Int32
//      64     pSignalSemaphores       Int       ptr to VkSemaphore array or 0
// ---------------------------------------------------------------------------

pub fn build_submit_info(wait_sem_count: Int32, wait_sems: Int, wait_stages: Int, cmd_buf_count: Int32, cmd_bufs: Int, signal_sem_count: Int32, signal_sems: Int) -> Int {
  let s = xalloc(72);
  if s == 0 { return 0; }
  xstype(s, 4);                   // sType = VK_STRUCTURE_TYPE_SUBMIT_INFO
  xpnext(s, 0);                   // pNext = null
  xw32(s, 16, wait_sem_count);    // waitSemaphoreCount
  xw64(s, 24, wait_sems);         // pWaitSemaphores
  xw64(s, 32, wait_stages);       // pWaitDstStageMask
  xw32(s, 40, cmd_buf_count);     // commandBufferCount
  xw64(s, 48, cmd_bufs);          // pCommandBuffers
  xw32(s, 56, signal_sem_count);  // signalSemaphoreCount
  xw64(s, 64, signal_sems);       // pSignalSemaphores
  return s;
}

// ---------------------------------------------------------------------------
// VkPresentInfoKHR
//
// Layout (64 bytes, natural alignment):
//   Offset    Field                 Type      Value
//       0     sType                 Int32     VK_STRUCTURE_TYPE_PRESENT_INFO_KHR (1000001001)
//       8     pNext                 Int       0
//      16     waitSemaphoreCount    Int32
//      24     pWaitSemaphores       Int       ptr to VkSemaphore array or 0
//      32     swapchainCount        Int32
//      40     pSwapchains           Int       ptr to VkSwapchainKHR array
//      48     pImageIndices         Int       ptr to Int32 array
//      56     pResults              Int       0
// ---------------------------------------------------------------------------

pub fn build_present_info(wait_sem_count: Int32, wait_sems: Int, swapchain_count: Int32, swapchains: Int, image_indices: Int) -> Int {
  let s = xalloc(64);
  if s == 0 { return 0; }
  xstype(s, 1000001001);          // sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR
  xpnext(s, 0);                   // pNext = null
  xw32(s, 16, wait_sem_count);    // waitSemaphoreCount
  xw64(s, 24, wait_sems);         // pWaitSemaphores
  xw32(s, 32, swapchain_count);   // swapchainCount
  xw64(s, 40, swapchains);        // pSwapchains
  xw64(s, 48, image_indices);     // pImageIndices
  xw64(s, 56, 0);                 // pResults = null
  return s;
}

// ---------------------------------------------------------------------------
// VkRenderPassBeginInfo
//
// Layout (64 bytes, natural alignment):
//   Offset    Field                     Type      Value
//       0     sType                     Int32     VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO (43)
//       8     pNext                     Int       0
//      16     renderPass                Int       VkRenderPass handle
//      24     framebuffer               Int       VkFramebuffer handle
//      32     renderArea.offset.x       Int32
//      36     renderArea.offset.y       Int32
//      40     renderArea.extent.width   Int32
//      44     renderArea.extent.height  Int32
//      48     clearValueCount           Int32
//      56     pClearValues              Int       ptr to VkClearValue array or 0
// ---------------------------------------------------------------------------

pub fn build_render_pass_begin_info(render_pass: Int, framebuffer: Int, offset_x: Int32, offset_y: Int32, extent_w: Int32, extent_h: Int32, clear_value_count: Int32, clear_values: Int) -> Int {
  let s = xalloc(64);
  if s == 0 { return 0; }
  xstype(s, 43);                   // sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO
  xpnext(s, 0);                    // pNext = null
  xw64(s, 16, render_pass);        // renderPass
  xw64(s, 24, framebuffer);        // framebuffer
  xw32(s, 32, offset_x);           // renderArea.offset.x
  xw32(s, 36, offset_y);           // renderArea.offset.y
  xw32(s, 40, extent_w);           // renderArea.extent.width
  xw32(s, 44, extent_h);           // renderArea.extent.height
  xw32(s, 48, clear_value_count);  // clearValueCount
  xw64(s, 56, clear_values);       // pClearValues
  return s;
}

// ---------------------------------------------------------------------------
// Helper: free a struct previously returned by any build_* function.
// NOTE: does not free nested allocations (pQueuePriorities, string arrays);
// free those separately with free_struct on their handles if you kept them.
// ---------------------------------------------------------------------------

pub fn free_struct(ptr: Int) {
  xfree(ptr);
}

// =============================================================================
// Phase 7.5: Multi-thread command pool struct builders
// =============================================================================

// ---------------------------------------------------------------------------
// VkDeviceQueueInfo2 (VK 1.1+)
//
// Layout (32 bytes, x64 natural alignment):
//   Offset    Field               Type      Value
//       0     sType               Int32     48 (VK_STRUCTURE_TYPE_DEVICE_QUEUE_INFO_2)
//       8     pNext               Int       0
//      16     flags               Int32     VkDeviceQueueCreateFlags
//      20     queueFamilyIndex    Int32     target queue family
//      24     queueIndex          Int32     queue index within family
// ---------------------------------------------------------------------------

pub fn build_device_queue_info_2(family: Int32, index: Int32, flags: Int32) -> Int {
  let s = xalloc(32);
  if s == 0 { return 0; }
  xstype(s, 48);                    // sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_INFO_2
  xpnext(s, 0);                     // pNext = null
  xw32(s, 16, flags);               // flags
  xw32(s, 20, family);              // queueFamilyIndex
  xw32(s, 24, index);               // queueIndex
  return s;
}

// ---------------------------------------------------------------------------
// VkCommandBufferBeginInfo
//
// Layout (24 bytes):
//   Offset    Field               Type      Value
//       0     sType               Int32     42 (VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO)
//       8     pNext               Int       0
//      16     flags               Int32     VkCommandBufferUsageFlags (ONE_TIME_SUBMIT / SIMULTANEOUS_USE / RENDER_PASS_CONTINUE)
//      20     padding             (align)
//      24     pInheritanceInfo    Int       VkCommandBufferInheritanceInfo* (0 for primary)
// ---------------------------------------------------------------------------

pub fn build_command_buffer_begin_info(flags: Int32, inheritance_info: Int) -> Int {
  let s = xalloc(32);
  if s == 0 { return 0; }
  xstype(s, 42);                    // sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO
  xpnext(s, 0);                     // pNext = null
  xw32(s, 16, flags);               // flags
  xw64(s, 24, inheritance_info);    // pInheritanceInfo
  return s;
}

// ---------------------------------------------------------------------------
// VkCommandBufferInheritanceInfo (for secondary command buffers)
//
// Layout (56 bytes):
//   Offset    Field                     Type
//       0     sType                     Int32     41
//       8     pNext                     Int       0
//      16     renderPass                Int       VkRenderPass (0 if dynamic rendering)
//      24     subpass                   Int32
//      28     padding
//      32     framebuffer               Int       VkFramebuffer (0 if dynamic rendering)
//      40     occlusionQueryEnable      Int32
//      44     queryFlags                Int32
//      48     pipelineStatistics        Int32
// ---------------------------------------------------------------------------

pub fn build_command_buffer_inheritance_info(render_pass: Int, subpass: Int32, framebuffer: Int) -> Int {
  let s = xalloc(56);
  if s == 0 { return 0; }
  xstype(s, 41);                    // sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_INHERITANCE_INFO
  xpnext(s, 0);                     // pNext = null
  xw64(s, 16, render_pass);         // renderPass
  xw32(s, 24, subpass);             // subpass
  xw64(s, 32, framebuffer);         // framebuffer
  return s;
}

// =============================================================================
// Phase 7.4: Texture loading struct builders
// =============================================================================

// ---------------------------------------------------------------------------
// VkBufferImageCopy
//
// Layout (56 bytes, x64 natural alignment):
//   Offset    Field                              Type
//       0     bufferOffset                       Int64
//       8     bufferRowLength                    Int32
//      12     bufferImageHeight                  Int32
//      16     imageSubresource.aspectMask        Int32
//      20     imageSubresource.mipLevel          Int32
//      24     imageSubresource.baseArrayLayer    Int32
//      28     imageSubresource.layerCount        Int32
//      32     imageOffset.x                      Int32
//      36     imageOffset.y                      Int32
//      40     imageOffset.z                      Int32
//      44     (pad)
//      48     imageExtent.width                  Int32
//      52     imageExtent.height                 Int32
//      56     imageExtent.depth                  Int32
// ---------------------------------------------------------------------------

pub fn build_buffer_image_copy(buffer_offset: Int, row_length: Int32, image_height: Int32, aspect: Int32, mip_level: Int32, base_layer: Int32, layer_count: Int32, offset_x: Int32, offset_y: Int32, offset_z: Int32, extent_w: Int32, extent_h: Int32, extent_d: Int32) -> Int {
  let s = xalloc(64);
  if s == 0 { return 0; }
  xw64(s, 0, buffer_offset);        // bufferOffset
  xw32(s, 8, row_length);           // bufferRowLength
  xw32(s, 12, image_height);        // bufferImageHeight
  xw32(s, 16, aspect);              // imageSubresource.aspectMask
  xw32(s, 20, mip_level);           // imageSubresource.mipLevel
  xw32(s, 24, base_layer);          // imageSubresource.baseArrayLayer
  xw32(s, 28, layer_count);         // imageSubresource.layerCount
  xw32(s, 32, offset_x);            // imageOffset.x
  xw32(s, 36, offset_y);            // imageOffset.y
  xw32(s, 40, offset_z);            // imageOffset.z
  xw32(s, 48, extent_w);            // imageExtent.width
  xw32(s, 52, extent_h);            // imageExtent.height
  xw32(s, 56, extent_d);            // imageExtent.depth
  return s;
}

// ---------------------------------------------------------------------------
// VkImageBlit
//
// Layout (80 bytes, x64 natural alignment):
//   Offset    Field                              Type
//     0-27    srcSubresource (same layout as above; 4x Int32)
//    28       (pad)
//    32-55    srcOffsets[2] (2x VkOffset3D = 6x Int32)
//    56-83    dstSubresource
//    84       (pad)
//    88-111   dstOffsets[2]
// ---------------------------------------------------------------------------

pub fn build_image_blit(src_aspect: Int32, src_mip: Int32, src_base_layer: Int32, src_layer_count: Int32, src_x: Int32, src_y: Int32, src_z: Int32, src_w: Int32, src_h: Int32, src_d: Int32, dst_aspect: Int32, dst_mip: Int32, dst_base_layer: Int32, dst_layer_count: Int32, dst_x: Int32, dst_y: Int32, dst_z: Int32, dst_w: Int32, dst_h: Int32, dst_d: Int32) -> Int {
  let s = xalloc(112);
  if s == 0 { return 0; }
  // srcSubresource (offset 0): 4 x Int32
  xw32(s, 0, src_aspect);           // srcSubresource.aspectMask
  xw32(s, 4, src_mip);              // srcSubresource.mipLevel
  xw32(s, 8, src_base_layer);       // srcSubresource.baseArrayLayer
  xw32(s, 12, src_layer_count);     // srcSubresource.layerCount
  // srcOffsets[0] (offset 16): 3 x Int32
  xw32(s, 16, src_x);               // srcOffsets[0].x
  xw32(s, 20, src_y);               // srcOffsets[0].y
  xw32(s, 24, src_z);               // srcOffsets[0].z
  // srcOffsets[1] (offset 28): 3 x Int32
  xw32(s, 28, src_w);               // srcOffsets[1].x
  xw32(s, 32, src_h);               // srcOffsets[1].y
  xw32(s, 36, src_d);               // srcOffsets[1].z
  // dstSubresource (offset 40): 4 x Int32
  xw32(s, 40, dst_aspect);          // dstSubresource.aspectMask
  xw32(s, 44, dst_mip);             // dstSubresource.mipLevel
  xw32(s, 48, dst_base_layer);      // dstSubresource.baseArrayLayer
  xw32(s, 52, dst_layer_count);     // dstSubresource.layerCount
  // dstOffsets[0] (offset 56): 3 x Int32
  xw32(s, 56, dst_x);               // dstOffsets[0].x
  xw32(s, 60, dst_y);               // dstOffsets[0].y
  xw32(s, 64, dst_z);               // dstOffsets[0].z
  // dstOffsets[1] (offset 68): 3 x Int32
  xw32(s, 68, dst_w);               // dstOffsets[1].x
  xw32(s, 72, dst_h);               // dstOffsets[1].y
  xw32(s, 76, dst_d);               // dstOffsets[1].z
  return s;
}

// ---------------------------------------------------------------------------
// VkImageMemoryBarrier
//
// Layout (72 bytes, x64):
//   Offset    Field                              Type
//       0     sType                              Int32     VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER (45)
//       8     pNext                              Int       0
//      16     srcAccessMask                      Int32
//      20     dstAccessMask                      Int32
//      24     oldLayout                          Int32
//      28     newLayout                          Int32
//      32     srcQueueFamilyIndex                Int32
//      36     dstQueueFamilyIndex                Int32
//      40     image                              Int64
//      48     aspectMask                         Int32
//      52     baseMipLevel                       Int32
//      56     levelCount                         Int32
//      60     baseArrayLayer                     Int32
//      64     layerCount                         Int32
// ---------------------------------------------------------------------------

pub fn build_image_memory_barrier(src_access: Int32, dst_access: Int32, old_layout: Int32, new_layout: Int32, image: Int, aspect: Int32, base_mip: Int32, level_count: Int32, base_layer: Int32, layer_count: Int32) -> Int {
  let s = xalloc(72);
  if s == 0 { return 0; }
  xstype(s, 45);                    // sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER
  xpnext(s, 0);                     // pNext = null
  xw32(s, 16, src_access);          // srcAccessMask
  xw32(s, 20, dst_access);          // dstAccessMask
  xw32(s, 24, old_layout);          // oldLayout
  xw32(s, 28, new_layout);          // newLayout
  xw32(s, 32, -1);                  // srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
  xw32(s, 36, -1);                  // dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED
  xw64(s, 40, image);               // image
  xw32(s, 48, aspect);              // subresourceRange.aspectMask
  xw32(s, 52, base_mip);            // subresourceRange.baseMipLevel
  xw32(s, 56, level_count);         // subresourceRange.levelCount
  xw32(s, 60, base_layer);          // subresourceRange.baseArrayLayer
  xw32(s, 64, layer_count);         // subresourceRange.layerCount
  return s;
}
