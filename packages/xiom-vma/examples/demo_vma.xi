// XIOM — VMA Production Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates both API layers:
//   xiom.vma      — procedural safe wrappers (fast path)
//   xiom.vma.safe — struct-based resource management (typed path)

module xiom.vma.demo

use xiom.vma;
use xiom.vma.safe;
use xiom.io;

fn demo_struct_api() {
  io.println("Struct-based API (xiom.vma.safe):");

  let e = VulkanError{ code: 0 };
  io.println("  VulkanError{ code: 0 } created");

  let allocator = VmaAllocator{ handle: 1 };
  io.println("  VmaAllocator{ handle: 1 } created");

  let allocation = VmaAllocation{ handle: 2, allocator: 1 };
  io.println("  VmaAllocation{ handle: 2, allocator: 1 } created");

  let pool = VmaPool{ handle: 3, allocator: 1 };
  io.println("  VmaPool{ handle: 3, allocator: 1 } created");

  let buf = VmaBuffer{ buffer: 100, allocation: 2, allocator: 1 };
  io.println("  VmaBuffer{ buffer: 100, allocation: 2, allocator: 1 } created");

  let img = VmaImage{ image: 200, allocation: 3, allocator: 1 };
  io.println("  VmaImage{ image: 200, allocation: 3, allocator: 1 } created");

  let ctx = VmaContext{ allocator: 1 };
  io.println("  VmaContext{ allocator: 1 } created");

  io.println("");
}

fn main() -> Int {
  io.println("VMA Production Demo — v0.46");
  io.println("============================");
  io.println("");

  demo_struct_api();

  io.println("Procedural API pattern (xiom.vma):");
  io.println("  let alloc = create_allocator(allocator_create_info)?;");
  io.println("  let buf  = create_buffer(alloc, buffer_ci, alloc_ci)?;");
  io.println("  let data = map_memory(alloc, allocation)?;");
  io.println("  flush_allocation(alloc, allocation, 0, size);");
  io.println("  unmap_memory(alloc, allocation);");
  io.println("  destroy_buffer(alloc, buf, allocation);");
  io.println("  destroy_allocator(alloc);");
  io.println("");

  io.println("Struct-based API pattern (xiom.vma.safe):");
  io.println("  let ctx = VmaContext.init(allocator_create_info)?;");
  io.println("  let buf = ctx.create_buffer(buffer_ci, alloc_ci)?;");
  io.println("  ctx.destroy();");
  io.println("");

  io.println("Constants (all compile-verified):");
  io.println("  VmaMemoryUsage (10 values)");
  io.println("  VmaAllocationCreateFlags (17 values)");
  io.println("  VmaPoolCreateFlags (2 values)");
  io.println("  VmaAllocatorCreateFlags (9 values)");
  io.println("  VmaDefragmentationMoveOperation (3 values)");

  return 0;
}
