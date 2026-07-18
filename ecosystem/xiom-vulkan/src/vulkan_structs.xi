// XIOM — Vulkan Struct Builders
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Typed helpers for building VK create-info structs via raw pointer arithmetic.
// Because XIOM lacks C struct support, all operations use ptr.write at known
// byte offsets based on Vulkan struct layouts (x86_64, packed alignment).
//
// VK constants used (literal values to avoid cross-module const gaps):
//   VK_STRUCTURE_TYPE_APPLICATION_INFO     = 0
//   VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO = 1
//   VK_API_VERSION_1_0 = 4194304  (0x00400000)
//   VK_API_VERSION_1_4 = 4210688  (0x00404000)

module xiom.vulkan.structs

use xiom.alloc;
use xiom.ptr;

// ---------------------------------------------------------------------------
// Primitive write helpers
// ---------------------------------------------------------------------------

// Allocate zero-filled memory for a struct of the given byte size.
fn alloc_struct(size: Int) -> Int
  requires: size > 0
{
  return alloc.alloc_zeroed(size);
}

// Write an Int32 value at (base + offset).
fn write_i32(base: Int, offset: Int, value: Int32) {
  unsafe { ptr.write((base + offset) as *Int32, value); }
}

// Write an Int value (64-bit handle / pointer) at (base + offset).
fn write_i64(base: Int, offset: Int, value: Int) {
  unsafe { ptr.write((base + offset) as *Int, value); }
}

// Write a Float32 value at (base + offset).
fn write_f32(base: Int, offset: Int, value: Float32) {
  unsafe { ptr.write((base + offset) as *Float32, value); }
}

// Write a raw string pointer (null-terminated C string) at (base + offset).
// The caller must ensure `s` outlives the struct.
fn write_str(base: Int, offset: Int, s: Str) {
  unsafe { ptr.write((base + offset) as *Int, s as *UInt8 as Int); }
}

// ---------------------------------------------------------------------------
// Internal: build a `const char*` pointer array from Vec[Str]
//
// Allocates `count * 8` bytes and writes each string's raw C pointer.
// Returns 0 for an empty vec (valid Vulkan NULL for ppEnabledLayerNames etc.).
// ---------------------------------------------------------------------------

fn build_str_ptr_array(strings: Vec[Str]) -> Int {
  let count = strings.len();
  if count == 0 { return 0; }
  let buf = alloc.alloc(count * 8);
  var i = 0;
  while i < count {
    unsafe { ptr.write((buf + i * 8) as *Int, strings[i] as *UInt8 as Int); }
    i = i + 1;
  }
  return buf;
}

// ---------------------------------------------------------------------------
// VkApplicationInfo (internal helper)
//
// Layout (40 bytes, packed):
//   Offset    Field                  Type      Value
//       0     sType                  Int32     VK_STRUCTURE_TYPE_APPLICATION_INFO (0)
//       4     pNext                  Int       0
//      12     pApplicationName       Int       raw str ptr
//      20     applicationVersion     Int32     VK_API_VERSION_1_0
//      24     pEngineName            Int       raw str ptr
//      32     engineVersion          Int32     VK_API_VERSION_1_0
//      36     apiVersion             Int32     VK_API_VERSION_1_4
// ---------------------------------------------------------------------------

fn build_application_info(app_name: Str, engine_name: Str) -> Int {
  let info = alloc_struct(40);
  write_i32(info, 0, 0);            // sType = VK_STRUCTURE_TYPE_APPLICATION_INFO
  write_i64(info, 4, 0);            // pNext = null
  write_str(info, 12, app_name);    // pApplicationName
  write_i32(info, 20, 4194304);     // applicationVersion = VK_API_VERSION_1_0
  write_str(info, 24, engine_name); // pEngineName
  write_i32(info, 32, 4194304);     // engineVersion = VK_API_VERSION_1_0
  write_i32(info, 36, 4210688);     // apiVersion = VK_API_VERSION_1_4
  return info;
}

// ---------------------------------------------------------------------------
// VkInstanceCreateInfo
//
// Layout (56 bytes, packed):
//   Offset    Field                     Type      Value
//       0     sType                     Int32     VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO (1)
//       4     pNext                     Int       0
//      12     flags                     Int32     0
//      16     pApplicationInfo          Int       app_info ptr or 0
//      24     enabledLayerCount         Int32
//      28..31 padding (zeroed)
//      32     ppEnabledLayerNames       Int       layer ptr-array or 0
//      40     enabledExtensionCount     Int32
//      44..47 padding (zeroed)
//      48     ppEnabledExtensionNames   Int       ext ptr-array or 0
// ---------------------------------------------------------------------------

pub fn build_instance_create_info(
  app_name: Str,
  engine_name: Str,
  layers: Vec[Str],
  extensions: Vec[Str],
) -> Int {
  let app_info = build_application_info(app_name, engine_name);
  let layer_names = build_str_ptr_array(layers);
  let ext_names = build_str_ptr_array(extensions);

  let info = alloc_struct(56);
  write_i32(info, 0, 1);                    // sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO
  write_i64(info, 4, 0);                    // pNext = null
  write_i32(info, 12, 0);                   // flags = 0
  write_i64(info, 16, app_info);            // pApplicationInfo
  write_i32(info, 24, layers.len() as Int32); // enabledLayerCount
  // bytes 28..31: padding (already zeroed by alloc_zeroed)
  write_i64(info, 32, layer_names);         // ppEnabledLayerNames
  write_i32(info, 40, extensions.len() as Int32); // enabledExtensionCount
  // bytes 44..47: padding (already zeroed by alloc_zeroed)
  write_i64(info, 48, ext_names);           // ppEnabledExtensionNames
  return info;
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
  stages: Int32,
) -> Int {
  let s = alloc_struct(24);
  write_i32(s, 0, binding);
  write_i32(s, 4, desc_type);
  write_i32(s, 8, count);
  write_i32(s, 12, stages);
  write_i64(s, 16, 0);  // pImmutableSamplers = null
  return s;
}
