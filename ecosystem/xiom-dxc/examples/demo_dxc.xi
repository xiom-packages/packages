// XIOM — DXC Production Demo
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// Demonstrates DXC shader compilation lifecycle using the
// xiom.dxc and xiom.dxc.safe APIs.
// This is a compile-time demo showing the correct API structure.
// Requires dxcompiler.dll to be in the library path at runtime.

module xiom.dxc.demo

use xiom.dxc;
use xiom.dxc.safe;
use xiom.io;

fn main() -> Int {
  io.println("DXC Shader Compiler Production Demo");
  io.println("===================================");
  io.println("");

  // Step 1: Create the DXC compiler instance.
  // In production, call DxcCompiler.create() which internally
  // calls DxcCreateInstance(CLSID_DxcCompiler, IID_IDxcCompiler3, &compiler).
  let comp_result = DxcCompiler.create();
  match comp_result {
    Err(err) => {
      io.println("(expected) Compiler creation returned error — dxcompiler.dll not loaded");
      io.println("DxcError code:");
      io.println(dxc_error_to_string(err));
      io.println("");
      io.println("In production: ensure dxcompiler.dll is in the PATH or link against dxcompiler.lib.");
    }
    Ok(compiler) => {
      io.println("Compiler created successfully.");

      // Step 2: Create the Utils instance for blob creation.
      let utils_result = DxcUtils.create();
      match utils_result {
        Err(err) => {
          io.println("Utils creation failed:");
          io.println(dxc_error_to_string(err));
        }
        Ok(utils) => {
          io.println("Utils created successfully.");

          // Step 3: Create a source blob from HLSL text.
          // In production, pass the address of a wide/utf8 string + length.
          let blob_result = create_instance(unsafe { xiom_dxc_clsid_library() }, unsafe { xiom_dxc_iid_blob() });
          match blob_result {
            Err(err) => {
              io.println("Blob creation returned error.");
            }
            Ok(blob) => {
              io.println("Blob created.");

              // Step 4: Compile shader source.
              //   let result = compiler.compile(p_source, p_arguments, arg_count, p_include_handler);
              //   This calls IDxcCompiler3::Compile via vtable dispatch.
              //   In production: pass the DxcBuffer source, compiler args, and optional include handler.
              io.println("Compile step: would call compiler.compile(p_source, p_args, arg_count, p_handler)");

              // Step 5: Get results.
              //   let status = result.get_status();
              //   if result.has_output(DXC_OUT_OBJECT) {
              //     let object = result.get_output(DXC_OUT_OBJECT);
              //   }
              //   if result.has_output(DXC_OUT_ERRORS) {
              //     let errors = result.get_output(DXC_OUT_ERRORS);
              //   }
              io.println("Result inspection: get_status(), has_output(), get_output()");

              release(blob);
            }
          }

          utils.destroy();
        }
      }

      compiler.destroy();
    }
  }

  io.println("");
  io.println("Struct-based API (xiom.dxc.safe) pattern:");
  io.println("  let ctx = DxcContext.init()?;");
  io.println("  let compiler = ctx.create_compiler();");
  io.println("  let utils = ctx.create_utils();");
  io.println("  let result = compiler.compile(p_source, p_args, arg_count, p_handler)?;");
  io.println("  let object = result.get_output(DXC_OUT_OBJECT)?;");
  io.println("  let data = object.get_buffer_pointer();");
  io.println("  ctx.destroy();");
  io.println("");

  io.println("Procedural API (xiom.dxc) pattern:");
  io.println("  let compiler = create_compiler()?;");
  io.println("  let utils = create_utils()?;");
  io.println("  let result = compiler3_compile(compiler, p_source, p_args, arg_count, 0, iid_result)?;");
  io.println("  let blob = result_get_output(result, DXC_OUT_OBJECT, iid_blob)?;");
  io.println("  let data = blob_get_buffer_pointer(blob);");
  io.println("  release(compiler);");
  io.println("");

  io.println("Key DXC Output Kinds:");
  io.println("  DXC_OUT_OBJECT = 1     — Compiled shader object (DXIL)");
  io.println("  DXC_OUT_ERRORS = 2     — Compilation errors/warnings");
  io.println("  DXC_OUT_PDB = 3        — Shader debug information");
  io.println("  DXC_OUT_DISASSEMBLY = 5 — Disassembly text");
  io.println("  DXC_OUT_HLSL = 6       — Preprocessor output");
  io.println("  DXC_OUT_REFLECTION = 8  — Shader reflection data");
  io.println("  DXC_OUT_ROOT_SIGNATURE = 9 — Serialized root signature");
  io.println("");

  io.println("COM VTable Dispatch Pattern (used internally):");
  io.println("  let vtbl = *(pObj as **Int);        // read vtable pointer");
  io.println("  let fn = *((vtbl as *Int) + idx);   // read function at index");
  io.println("  let f: fn(...) = fn as fn(...);     // cast to typed function pointer");
  io.println("  let result = f(pObj, ...);          // call via function pointer");

  return 0;
}
