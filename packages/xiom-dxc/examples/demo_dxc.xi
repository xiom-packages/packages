// XIOM -- DXC Production Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates DXC shader compilation lifecycle using the
// xiom.dxc and xiom.dxc.safe APIs (C bridge backed).
// Requires dxcompiler.dll in the library path at runtime.

module xiom.dxc.demo

use xiom.dxc;
use xiom.dxc.safe;
use xiom.io;

fn main() -> Int {
  io.println("DXC Shader Compiler Production Demo");
  io.println("===================================");
  io.println("");

  // Procedural API demo (following xiom.vma pattern)
  // Step 1: Create compiler instance.
  let comp_result = create_compiler();
  match comp_result {
    Err(err) => {
      io.println("(expected) Compiler creation returned error -- code:");
      io.println(result_to_string(0));
      io.println("");
      io.println("In production: ensure dxcompiler.dll is in PATH and dxc_bridge.o is linked.");
    }
    Ok(compiler) => {
      io.println("Compiler created (procedural API).");

      let utils_result = create_utils();
      match utils_result {
        Err(_) => {
          io.println("Utils creation failed.");
        }
        Ok(utils) => {
          io.println("Utils created.");

          // Step 2: Test that the handles are valid.
          let ref_count = add_ref(compiler);
          io.println("Compiler AddRef returned ref count.");
          release(compiler);

          io.println("Compliation/validation/reflection steps documented below.");

          release(utils);
        }
      }

      release(compiler);
    }
  }

  // Struct-based API demo (requires actual dxcompiler.dll at runtime)
  io.println("");
  let ctx_result = DxcContext.init();
  match ctx_result {
    Err(_) => {
      io.println("DxcContext.init() returned error (expected without dxcompiler.dll)");
    }
    Ok(ctx) => {
      io.println("DxcContext created via struct-based API.");
      release(ctx.utils);
      release(ctx.compiler);
    }
  }

  io.println("");
  io.println("Struct-based API (xiom.dxc.safe) pattern:");
  io.println("  let ctx = DxcContext.init()?;");
  io.println("  let compiler = ctx.create_compiler();");
  io.println("  let utils = ctx.create_utils();");
  io.println("  let handler = utils.create_default_include_handler()?;");
  io.println("  let args = utils.build_arguments(src_name, entry, target, ...);");
  io.println("  let result = compiler.compile(p_source, p_args, arg_count, p_handler)?;");
  io.println("  if result.has_output(DXC_OUT_OBJECT) {");
  io.println("    let object = result.get_output(DXC_OUT_OBJECT)?;");
  io.println("    let data = object.get_buffer_pointer();");
  io.println("  }");
  io.println("  ctx.destroy();");
  io.println("");

  io.println("Procedural API (xiom.dxc) pattern:");
  io.println("  let compiler = create_compiler()?;");
  io.println("  let result = compiler_compile(compiler, p_source, p_args, arg_count, 0)?;");
  io.println("  if result_has_output(result, DXC_OUT_OBJECT) {");
  io.println("    let blob = result_get_output_blob(result, DXC_OUT_OBJECT)?;");
  io.println("  }");
  io.println("  let errors = get_errors_as_utf8(result)?;");
  io.println("  release(compiler);");
  io.println("");

  io.println("C Bridge Architecture:");
  io.println("  XIOM .xi  -->  extern \"C\" fn  -->  dxc_bridge.c  -->  COM vtable");
  io.println("  All COM method calls go through dxc_bridge.c thin wrappers.");
  io.println("  The bridge compiles with clang++ against dxcapi.h + dxcompiler.lib.");
  io.println("");

  io.println("API Surface Bound:");
  io.println("  165 extern function declarations (2 DLL exports + 34 GUIDs + 129 COM methods)");
  io.println("  24 COM interfaces (IUnknown through IDxcPdbUtils2)");
  io.println("  12 safe struct resource types with create/destroy lifecycle");
  io.println("  14 constants (DXC_OUT_KIND), 9 FOURCC parts, 5 validator flags");

  return 0;
}
