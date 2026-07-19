#include "xvk_shader_compile.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <io.h>
#define popen _popen
#define pclose _pclose
#else
#include <unistd.h>
#include <sys/wait.h>
#endif

static const char* stage_map(const char* stage) {
    static const char* map[][2] = {
        {"vertex",        "vert"},
        {"fragment",      "frag"},
        {"compute",        "comp"},
        {"tessecontrol",  "tesc"},
        {"tesseeval",      "tese"},
        {"geometry",      "geom"},
        {"raygen",        "rgen"},
        {"anyhit",        "rahit"},
        {"closesthit",    "rchit"},
        {"miss",          "rmiss"},
        {"intersection",  "rint"},
        {"callable",      "rcall"},
        {"task",          "task"},
        {"mesh",          "mesh"},
        {NULL, NULL}
    };
    for (int i = 0; map[i][0]; i++) {
        if (strcmp(stage, map[i][0]) == 0) return map[i][1];
    }
    return "vert"; /* default */
}

static const char* detect_stage_from_ext(const char* filepath) {
    const char* ext = strrchr(filepath, '.');
    if (!ext) return "vert";
    ext++; /* skip the '.' */
    static const char* ext_to_stage[][2] = {
        {"vert", "vertex"},   {"frag", "fragment"}, {"comp", "compute"},
        {"tesc", "tessecontrol"}, {"tese", "tesseeval"}, {"geom", "geometry"},
        {"rgen", "raygen"},   {"rahit", "anyhit"},   {"rchit", "closesthit"},
        {"rmiss", "miss"},    {"rint", "intersection"}, {"rcall", "callable"},
        {"task", "task"},     {"mesh", "mesh"},
        {NULL, NULL}
    };
    for (int i = 0; ext_to_stage[i][0]; i++) {
        if (strcmp(ext, ext_to_stage[i][0]) == 0) return ext_to_stage[i][1];
    }
    return "vertex";
}

/* Find glslc on the system:
 * 1. VULKAN_SDK environment variable + /Bin/glslc(.exe)
 * 2. PATH search for glslc */
static int find_glslc(char* out_path, size_t out_size) {
#ifdef _WIN32
    const char* vk_sdk = getenv("VULKAN_SDK");
    if (vk_sdk) {
        snprintf(out_path, out_size, "%s\\Bin\\glslc.exe", vk_sdk);
        if (GetFileAttributesA(out_path) != INVALID_FILE_ATTRIBUTES) return 0;
    }
    /* Try PATH */
    return 1; /* will be resolved by popen/path search */
#else
    const char* vk_sdk = getenv("VULKAN_SDK");
    if (vk_sdk) {
        snprintf(out_path, out_size, "%s/bin/glslc", vk_sdk);
        if (access(out_path, X_OK) == 0) return 0;
    }
    strncpy(out_path, "glslc", out_size);
    return 0;
#endif
}

/* Run glslc with source piped via stdin, capture stdout.
 * Returns allocated buffer with SPIR-V + size prefix, or NULL on failure. */
static unsigned char* compile_via_glslc(const char* source, int source_len,
                                         const char* stage_glslc, int source_is_file,
                                         const char* file_or_source)
{
    char glslc_path[512] = {0};
    find_glslc(glslc_path, sizeof(glslc_path));

    char cmd[2048];
    const char* glslc_exe = glslc_path[0] ? glslc_path : "glslc";

    if (source_is_file) {
        /* Compile from file: glslc -o temp.spv -fshader-stage=STAGE file.vert */
        char tmp_output[512];
        const char* tmpdir = getenv("TEMP");
        if (!tmpdir) tmpdir = getenv("TMP");
        if (!tmpdir) tmpdir = ".";
        snprintf(tmp_output, sizeof(tmp_output), "%s\\xvk_tmp_%lu.spv",
                 tmpdir, (unsigned long)GetCurrentProcessId());
#ifdef _WIN32
        snprintf(cmd, sizeof(cmd),
                 "\"%s\" -o \"%s\" -fshader-stage=%s \"%s\" 2>&1",
                 glslc_exe, tmp_output, stage_glslc, file_or_source);
#else
        snprintf(cmd, sizeof(cmd),
                 "%s -o %s -fshader-stage=%s %s 2>&1",
                 glslc_exe, tmp_output, stage_glslc, file_or_source);
#endif
        FILE* p = popen(cmd, "rb");
        if (!p) return NULL;
        /* Read error output but discard it */
        char err_buf[1024];
        fread(err_buf, 1, sizeof(err_buf)-1, p);
        int exit_code = pclose(p);

        /* Read the output .spv file */
        FILE* f = fopen(tmp_output, "rb");
        if (!f) { remove(tmp_output); return NULL; }
        fseek(f, 0, SEEK_END);
        long size = ftell(f);
        if (size <= 0 || size > (64 * 1024 * 1024)) { /* max 64MB */
            fclose(f);
            remove(tmp_output);
            return NULL;
        }
        fseek(f, 0, SEEK_SET);
        unsigned char* result = (unsigned char*)malloc(sizeof(int64_t) + (size_t)size);
        if (!result) { fclose(f); remove(tmp_output); return NULL; }
        *(int64_t*)result = (int64_t)size;
        size_t read_bytes = fread(result + sizeof(int64_t), 1, (size_t)size, f);
        fclose(f);
        remove(tmp_output);
        if (read_bytes != (size_t)size) {
            free(result);
            return NULL;
        }
        return result;
    } else {
        /* Compile from source string via stdin pipe */
        char tmp_output[512];
        const char* tmpdir = getenv("TEMP");
        if (!tmpdir) tmpdir = getenv("TMP");
        if (!tmpdir) tmpdir = ".";
        snprintf(tmp_output, sizeof(tmp_output), "%s\\xvk_tmp_%lu.spv",
                 tmpdir, (unsigned long)GetCurrentProcessId());

        /* Write source to temp file (glslc doesn't support stdin on all builds) */
        char tmp_src[512];
        snprintf(tmp_src, sizeof(tmp_src), "%s\\xvk_tmp_src_%lu.glsl",
                 tmpdir, (unsigned long)GetCurrentProcessId());
        FILE* sf = fopen(tmp_src, "wb");
        if (!sf) return NULL;
        size_t written = fwrite(source, 1, (size_t)source_len, sf);
        fclose(sf);
        if (written != (size_t)source_len) {
            remove(tmp_src);
            return NULL;
        }

        /* Run glslc on the temp file */
#ifdef _WIN32
        snprintf(cmd, sizeof(cmd),
                 "\"%s\" -o \"%s\" -fshader-stage=%s \"%s\" 2>&1",
                 glslc_exe, tmp_output, stage_glslc, tmp_src);
#else
        snprintf(cmd, sizeof(cmd),
                 "%s -o %s -fshader-stage=%s %s 2>&1",
                 glslc_exe, tmp_output, stage_glslc, tmp_src);
#endif
        FILE* p = popen(cmd, "rb");
        if (!p) { remove(tmp_src); return NULL; }
        char err_buf[1024];
        fread(err_buf, 1, sizeof(err_buf)-1, p);
        int exit_code = pclose(p);
        remove(tmp_src);

        if (exit_code != 0) {
            remove(tmp_output);
            return NULL;
        }

        /* Read the output .spv file */
        FILE* f = fopen(tmp_output, "rb");
        if (!f) { return NULL; }
        fseek(f, 0, SEEK_END);
        long size = ftell(f);
        if (size <= 0 || size > (64 * 1024 * 1024)) {
            fclose(f);
            remove(tmp_output);
            return NULL;
        }
        fseek(f, 0, SEEK_SET);
        unsigned char* result = (unsigned char*)malloc(sizeof(int64_t) + (size_t)size);
        if (!result) { fclose(f); remove(tmp_output); return NULL; }
        *(int64_t*)result = (int64_t)size;
        size_t read_bytes = fread(result + sizeof(int64_t), 1, (size_t)size, f);
        fclose(f);
        remove(tmp_output);
        if (read_bytes != (size_t)size) {
            free(result);
            return NULL;
        }
        return result;
    }
}

int64_t xvk_compile_glsl_to_spirv(const char* source, const char* stage, int64_t flags)
{
    (void)flags;
    if (!source || !source[0] || !stage || !stage[0]) return 0;

    int source_len = (int)strlen(source);
    const char* stage_c = stage_map(stage);

    unsigned char* result = compile_via_glslc(source, source_len, stage_c, 0, NULL);
    return (int64_t)(intptr_t)result;
}

int64_t xvk_compile_glsl_file_to_spirv(const char* filepath, const char* stage, int64_t flags)
{
    (void)flags;
    if (!filepath || !filepath[0]) return 0;

    const char* effective_stage = stage;
    if (!stage || !stage[0]) {
        effective_stage = detect_stage_from_ext(filepath);
    }
    const char* stage_c = stage_map(effective_stage);

    unsigned char* result = compile_via_glslc(NULL, 0, stage_c, 1, filepath);
    return (int64_t)(intptr_t)result;
}

void xvk_free_spirv_result(int64_t result_ptr)
{
    if (result_ptr) {
        free((void*)(intptr_t)result_ptr);
    }
}
