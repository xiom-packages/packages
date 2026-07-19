#ifndef XVK_SHADER_COMPILE_H_
#define XVK_SHADER_COMPILE_H_

#include <stdint.h>

/*
 * Phase 7.3: Runtime shader compilation via glslc subprocess.
 *
 * Invokes glslc (Vulkan SDK's shader compiler) as a subprocess to compile
 * GLSL source code to SPIR-V at runtime. Source can be passed as a string
 * (stdin pipe) or a file path.
 *
 * Return format: [8 bytes: int64_t byte_size][byte_size bytes: uint32_t SPIR-V]
 * The returned pointer is a heap allocation (malloc); free with
 * xvk_free_spirv_result(). Returns 0 on failure.
 *
 * Stage strings map to glslc -fshader-stage=:
 *   "vertex", "fragment", "compute", "tessecontrol", "tesseeval", "geometry",
 *   "rgen", "rahit", "rchit", "rmiss", "rint", "rcall", "task", "mesh"
 */

/* Compile GLSL source string to SPIR-V.
 * source:  NUL-terminated GLSL source code (e.g. "#version 450\nvoid main(){...}").
 * stage:   shader stage name (e.g. "vertex", "fragment", "compute").
 * flags:   reserved for future use (pass 0).
 * Returns: heap pointer to [size: int64_t | spirv_bytes: uint8_t[]], or 0 on failure. */
int64_t xvk_compile_glsl_to_spirv(const char* source, const char* stage, int64_t flags);

/* Compile a GLSL source file (.vert/.frag/.comp) to SPIR-V.
 * filepath: path to the GLSL source file on disk.
 * stage:    shader stage name (use "" to auto-detect from extension).
 * flags:    reserved for future use (pass 0).
 * Returns: heap pointer or 0 on failure. */
int64_t xvk_compile_glsl_file_to_spirv(const char* filepath, const char* stage, int64_t flags);

/* Free a SPIR-V result buffer returned by xvk_compile_glsl_to_spirv or
 * xvk_compile_glsl_file_to_spirv. No-op on 0. */
void xvk_free_spirv_result(int64_t result_ptr);

#endif
