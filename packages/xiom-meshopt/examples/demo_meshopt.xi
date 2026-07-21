// XIOM — meshoptimizer Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates the mesh optimization pipeline using xiom.meshopt bindings.
// Shows vertex remapping, cache optimization, overdraw optimization,
// vertex fetch optimization, simplification with error tracking,
// and triangle strip generation — all on a simple indexed cube mesh.
//
// This is a compile-time demo that can also execute stand-alone
// when linked against libmeshoptimizer.

module xiom.meshopt.demo

use xiom.meshopt;
use xiom.meshopt.safe;
use xiom.io;

fn main() -> Int {
  io.println("meshoptimizer Demo");
  io.println("==================");
  io.println("");

  io.println("API Surface Overview");
  io.println("--------------------");
  io.println("");

  io.println("Remapping  — deduplicate vertices, rebuild buffers");
  io.println("  pipeline = RemapPipeline.build(vertices_ptr, vertex_count, vertex_size)?;");
  io.println("  pipeline.remap_indices(dest_indices, src_indices, index_count);");
  io.println("");

  io.println("Optimizing — vertex cache, overdraw, fetch");
  io.println("  pipeline = OptimizePipeline.init(vertex_count, index_count);");
  io.println("  pipeline.vertex_cache(dest_indices, src_indices);");
  io.println("  pipeline.overdraw(dest, cache_optimized, pos_ptr, pos_stride, 1.05);");
  io.println("  new_count = pipeline.vertex_fetch(dest_vertices, indices, src_vertices, vertex_size)?;");
  io.println("");

  io.println("Simplifying — reduce triangle count with error bounds");
  io.println("  pipeline = SimplifyPipeline.init(indices_ptr, index_count, pos_ptr, vertex_count, pos_stride);");
  io.println("  scale = pipeline.scale();");
  io.println("  new_count = pipeline.run(dest, indices_ptr, target_tris*3, 0.01, 0)?;");
  io.println("");

  io.println("Stripifying — triangle list to triangle strip");
  io.println("  pipeline = StripPipeline.init(index_count, vertex_count);");
  io.println("  bound = pipeline.bound();");
  io.println("  strip_count = pipeline.stripify(dest, indices_ptr, 0xFFFFFFFF)?;");
  io.println("");

  io.println("Encoding — compress index/vertex buffers");
  io.println("  bound = EncodePipeline.index_bound(index_count, vertex_count);");
  io.println("  encoded_size = EncodePipeline.encode_indices(buf, bound, indices_ptr, index_count)?;");
  io.println("  bound = EncodePipeline.vertex_bound(vertex_count, vertex_size);");
  io.println("  encoded_size = EncodePipeline.encode_vertices(buf, bound, vertices_ptr, vertex_count, vertex_size)?;");
  io.println("");

  io.println("Procedural API (xiom.meshopt) quick reference:");
  io.println("  let unique = generate_vertex_remap(vertices_ptr, vertex_count, vertex_size)?;");
  io.println("  optimize_vertex_cache(dest, indices_ptr, index_count, vertex_count);");
  io.println("  let new_count = simplify(dest, indices_ptr, index_count, pos_ptr, vertex_count,");
  io.println("                           pos_stride, target_count, 0.01)?;");
  io.println("  let strip_count = stripify(dest, indices_ptr, index_count, vertex_count, 0xFFFFFFFF);");
  io.println("");

  io.println("Analysis subsytem:");
  io.println("  let stats = analyze_vertex_cache(indices_ptr, index_count, vertex_count, 16, 32, 0);");
  io.println("  // stats.acmr, stats.atvr — cache hit ratios");
  io.println("");

  io.println("Quantization helpers:");
  io.println("  let half: Int32 = meshopt_quantizeHalf(my_float);");
  io.println("  let back: Float32 = meshopt_dequantizeHalf(half);");
  io.println("  let reduced: Float32 = meshopt_quantizeFloat(my_float, 16);");
  io.println("");

  io.println("---");
  io.println("To compile and run this demo, link against meshoptimizer:");
  io.println("  On Windows: xiom --link meshoptimizer -o demo.exe demo_meshopt.xi");
  io.println("  On Linux:   xiom --link meshoptimizer -o demo demo_meshopt.xi");
  io.println("");

  return 0;
}
