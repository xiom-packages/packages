// XIOM — VMA Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates VMA lifecycle: allocator creation, buffer allocation, teardown.
// This is a compile-time demo showing the API pattern — it requires a Vulkan
// instance/device to allocate from, so it runs as part of a larger Vulkan app.
// The demo shows the skeleton that any production engine would use.

module xiom.vma.demo

use xiom.vma;
use xiom.io;

fn main() -> Int {
  // In a real application, you would get these from Vulkan initialization:
  //   - physical_device: from vkEnumeratePhysicalDevices
  //   - device: from vkCreateDevice
  //   - instance: from vkCreateInstance
  //
  // The VmaAllocatorCreateInfo would be filled with:
  //   .physicalDevice = physical_device
  //   .device = device
  //   .instance = instance
  //   .vulkanApiVersion = VK_API_VERSION_1_3
  //
  // For this demo, we show the pattern using placeholder handles (0 = not yet initialized).
  // In production code, these are obtained from vkCreateDevice / vkCreateInstance.

  io.println("VMA Demo — showing the API pattern");
  io.println("===================================");
  io.println("");

  // Step 1: Create VMA allocator.
  // In production, pass a pointer to a populated VmaAllocatorCreateInfo struct.
  // The create_info must have:
  //   - physicalDevice: VkPhysicalDevice handle
  //   - device: VkDevice handle
  //   - instance: VkInstance handle (optional but recommended)
  //   - vulkanApiVersion: e.g., VK_API_VERSION_1_3
  let allocator_result = create_allocator(0);
  match allocator_result {
    Err(e) => {
      // Expected — we passed 0 (null) for the create info.
      // In a real app with valid Vulkan handles, this succeeds.
      io.println("(expected) Allocator creation returned error: no Vulkan device");
      io.println("In production: pass valid VmaAllocatorCreateInfo* to create_allocator");
      io.println("");
    }
    Ok(alloc) => {
      // Success path: allocator created.  Now allocate a buffer.
      io.println("Allocator created successfully");

      // Step 2: Create a buffer via VMA.
      // In production, pass VkBufferCreateInfo* and VmaAllocationCreateInfo*.
      let buf_result = create_buffer(alloc, 0, 0);
      match buf_result {
        Err(_) => {
          io.println("Buffer creation failed (no create info provided)");
        }
        Ok(buf) => {
          io.println("Buffer created successfully");

          // Step 3: Map the buffer's allocation for CPU access.
          // In production, use map_memory(alloc, allocation) to get a CPU pointer.
          // Then write data, flush allocation, unmap.

          // Step 4: Destroy buffer.
          destroy_buffer(alloc, buf, 0);
          io.println("Buffer destroyed");
        }
      }

      // Step 5: Destroy allocator.
      destroy_allocator(alloc);
      io.println("Allocator destroyed");
    }
  }

  io.println("");
  io.println("VMA Demo complete.");
  io.println("");
  io.println("Production usage pattern:");
  io.println("  1. let alloc = create_allocator(allocator_create_info)?;");
  io.println("  2. let buf = create_buffer(alloc, buffer_ci, alloc_ci)?;");
  io.println("  3. let data = map_memory(alloc, allocation)?;");
  io.println("  4. flush_allocation(alloc, allocation, 0, size);");
  io.println("  5. unmap_memory(alloc, allocation);");
  io.println("  6. destroy_buffer(alloc, buf, allocation);");
  io.println("  7. destroy_allocator(alloc);");

  return 0;
}
