// XIOM — VMA Production Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates VMA lifecycle using the xiom.vma and xiom.vma.safe APIs.
// A compile-time demo showing the pattern used in every production engine.
// Requires a Vulkan instance/device to actually execute — this skeleton shows
// the correct API structure.

module xiom.vma.demo

use xiom.vma;
use xiom.vma.safe;
use xiom.io;

fn main() -> Int {
  io.println("VMA Production Demo");
  io.println("===================");
  io.println("");

  // Step 1: Create the VMA allocator.
  // In production, the create_info struct is populated from Vulkan initialization:
  //   - physicalDevice from vkEnumeratePhysicalDevices
  //   - device from vkCreateDevice
  //   - instance from vkCreateInstance
  //   - vulkanApiVersion set to the target Vulkan version
  // Here we pass 0 (null pointer) to demonstrate the fallback path.
  let alloc_result = create_allocator(0);
  match alloc_result {
    Err(err) => {
      io.println("(expected) Allocator creation returned error — no Vulkan device");
      io.println("In production: populate VmaAllocatorCreateInfo and pass it to create_allocator.");
      io.println("");
    }
    Ok(alloc) => {
      io.println("Allocator created.");

      let buf_result = create_buffer(alloc, 0, 0);
      match buf_result {
        Err(_) => {
          io.println("Buffer creation returned error (no create info)");
        }
        Ok(buf) => {
          io.println("Buffer created.");

          // Map, write data, flush, unmap:
          //   let data = map_memory(alloc, allocation)?;
          //   flush_allocation(alloc, allocation, 0, size);
          //   unmap_memory(alloc, allocation);

          destroy_buffer(alloc, buf, 0);
          io.println("Buffer destroyed.");
        }
      }

      destroy_allocator(alloc);
      io.println("Allocator destroyed.");
    }
  }

  io.println("");
  io.println("Struct-based API (xiom.vma.safe) pattern:");
  io.println("  let ctx = VmaContext.init(allocator_create_info)?;");
  io.println("  let buf = ctx.create_buffer(buffer_ci, alloc_ci)?;");
  io.println("  ctx.destroy();");
  io.println("");

  io.println("Procedural API (xiom.vma) pattern:");
  io.println("  let alloc = create_allocator(allocator_create_info)?;");
  io.println("  let buf = create_buffer(alloc, buffer_ci, alloc_ci)?;");
  io.println("  let data = map_memory(alloc, allocation)?;");
  io.println("  flush_allocation(alloc, allocation, 0, size);");
  io.println("  unmap_memory(alloc, allocation);");
  io.println("  destroy_buffer(alloc, buf, allocation);");
  io.println("  destroy_allocator(alloc);");

  return 0;
}
