/* XIOM -- xiom.android-sys: libneuralnetworks (NNAPI) runtime bridge.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * DESIGN: self-contained runtime loader/probe for the NNAPI C API
 * (android/NeuralNetworks.h of NDK r27b).  No link-time dependency, no
 * NDK headers needed to compile: the declared surface is re-declared by
 * hand (ABI-pinned facts), loaded via dlopen/LoadLibraryA at runtime and
 * export-checked.  Handles (model/compilation/execution/device) cross as
 * Int64; u32 arrays (dimensions, operand ids) cross as little-endian
 * byte slots owned by the caller (B-series discipline).
 *
 * Declared core set (API 27, ABI-gated, 12 symbols):
 *   ANeuralNetworksModel_create/addOperand/addOperation/
 *   identifyInputsAndOutputs/setOperandValue/finish/free,
 *   ANeuralNetworksCompilation_create/finish/free,
 *   ANeuralNetworksExecution_create/free
 * Declared extension set (API 29, resolved + reported, not gated,
 * 7 symbols):
 *   ANeuralNetworks_getDeviceCount, ANeuralNetworks_getDevice,
 *   ANeuralNetworksDevice_getName/_getType/_getVersion/_getFeatureLevel,
 *   ANeuralNetworks_getRuntimeFeatureLevel
 *
 * Functional head (offline model build, no device execution):
 *   create model -> add 3 TENSOR_FLOAT32 operands -> add ADD (0,1)->2 ->
 *   identifyInputsAndOutputs -> finish -> compilation create/finish ->
 *   execution create/free.  Compilation_finish is device-dependent: its
 *   result is returned to the caller verbatim (documented device-absent
 *   path), never conflated with a bridge fault.
 *
 * Contract (flat extern "C", called from module xiom.android_sys.nnapi):
 *   int         xnn_load_named(const char* soname)   0=ok 1=absent 2=abi
 *   int         xnn_load(void)                       "libneuralnetworks.so"
 *   const char* xnn_error(void)
 *   int         xnn_core_missing_count(void)
 *   const char* xnn_core_missing(void)
 *   int         xnn_ext_count(void)
 *   int         xnn_ext_missing_count(void)
 *   const char* xnn_ext_missing(void)
 *   int64       xnn_model_create(void)               model; 0 = fail
 *   int         xnn_model_add_tensor(int64 model, int code, const uint8*
 *                                   dims_le, int dim_count,
 *                                   int scale_f32_bits, int zero_point)
 *   int         xnn_model_add_operation(int64 model, int op,
 *                                       const uint8* inputs_le, int input_count,
 *                                       const uint8* outputs_le, int output_count)
 *   int         xnn_model_identify_io(int64 model, const uint8* inputs_le,
 *                                     int input_count, const uint8* outputs_le,
 *                                     int output_count)
 *   int         xnn_model_set_scalar_i32(int64 model, int index, int32 value)
 *   int         xnn_model_finish(int64 model)
 *   void        xnn_model_free(int64 model)
 *   int64       xnn_compilation_create(int64 model)  compilation; 0 = fail
 *   int         xnn_compilation_finish(int64 compilation)
 *   void        xnn_compilation_free(int64 compilation)
 *   int64       xnn_execution_create(int64 compilation)  execution; 0 = fail
 *   void        xnn_execution_free(int64 execution)
 *   int         xnn_device_count(void)               count; -2 unresolved
 *   int         xnn_device_name(int index, uint8* out, int cap)  length
 *   int         xnn_device_type(int index)           ANeuralNetworksDeviceType
 *   int         xnn_device_version(int index, uint8* out, int cap)  length
 *   int         xnn_device_feature_level(int index)  feature level
 *   int         xnn_runtime_feature_level(void)
 *   const char* xnn_error_name(int code)
 *   void        xnn_unload(void)
 *
 * Sentinel convention: -2 = "symbol unresolved" (mapped to LOAD_ABI by
 * the module); -1 = call-time failure with the reason in xnn_error().
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
typedef HMODULE xnn_lib_t;
static xnn_lib_t xnn_dlopen(const char* name) { return LoadLibraryA(name); }
static void* xnn_dlsym(xnn_lib_t h, const char* name) {
    return h ? (void*)GetProcAddress(h, name) : 0;
}
static void xnn_dlclose(xnn_lib_t h) { if (h) FreeLibrary(h); }
#else
#include <dlfcn.h>
typedef void* xnn_lib_t;
static xnn_lib_t xnn_dlopen(const char* name) { return dlopen(name, RTLD_NOW | RTLD_LOCAL); }
static void* xnn_dlsym(xnn_lib_t h, const char* name) { return h ? dlsym(h, name) : 0; }
static void xnn_dlclose(xnn_lib_t h) { if (h) dlclose(h); }
#endif

/* -- re-declared NDK ABI facts (android/NeuralNetworks.h r27b) ------------- */

typedef struct XNN_Model ANeuralNetworksModel;
typedef struct XNN_Compilation ANeuralNetworksCompilation;
typedef struct XNN_Execution ANeuralNetworksExecution;
typedef struct XNN_Device ANeuralNetworksDevice;

typedef struct XNN_OperandType {
    int32_t type;              /* ANeuralNetworksOperandCode */
    uint32_t dimensionCount;   /* rank; 0 for scalars */
    const uint32_t* dimensions;
    float scale;               /* TENSOR_QUANT8_ASYMM family */
    int32_t zeroPoint;
} XNN_OperandType;

/* ANeuralNetworksOperationType / ErrorCode / DeviceType values used here
 * (android/NeuralNetworksTypes.h r27b; pinned constants). */
#define XNN_OP_ADD 0
#define XNN_OP_MUL 18
#define XNN_TENSOR_FLOAT32 3
#define XNN_FLOAT32 0
#define XNN_INT32 1
#define XNN_UINT32 2
#define XNN_TENSOR_INT32 4
#define XNN_DEVICE_UNKNOWN 0
#define XNN_DEVICE_OTHER 1
#define XNN_DEVICE_CPU 2
#define XNN_DEVICE_GPU 3
#define XNN_DEVICE_ACCELERATOR 4

#define XNN_MAX_IDS 64

/* -- resolved function pointers -------------------------------------------- */

typedef int (*PFN_model_create)(ANeuralNetworksModel**);
typedef int (*PFN_model_add_operand)(ANeuralNetworksModel*, const XNN_OperandType*);
typedef int (*PFN_model_add_operation)(ANeuralNetworksModel*, int32_t, uint32_t,
                                       const uint32_t*, uint32_t, const uint32_t*);
typedef int (*PFN_model_identify_io)(ANeuralNetworksModel*, uint32_t, const uint32_t*,
                                     uint32_t, const uint32_t*);
typedef int (*PFN_model_set_operand_value)(ANeuralNetworksModel*, int32_t, const void*, size_t);
typedef int (*PFN_model_finish)(ANeuralNetworksModel*);
typedef void (*PFN_model_free)(ANeuralNetworksModel*);
typedef int (*PFN_comp_create)(ANeuralNetworksModel*, ANeuralNetworksCompilation**);
typedef int (*PFN_comp_finish)(ANeuralNetworksCompilation*);
typedef void (*PFN_comp_free)(ANeuralNetworksCompilation*);
typedef int (*PFN_exec_create)(ANeuralNetworksCompilation*, ANeuralNetworksExecution**);
typedef void (*PFN_exec_free)(ANeuralNetworksExecution*);
typedef int (*PFN_device_count)(uint32_t*);
typedef int (*PFN_device_get)(uint32_t, ANeuralNetworksDevice**);
typedef int (*PFN_device_name)(const ANeuralNetworksDevice*, const char**);
typedef int (*PFN_device_type)(const ANeuralNetworksDevice*, int32_t*);
typedef int (*PFN_device_version)(const ANeuralNetworksDevice*, const char**);
typedef int (*PFN_device_feature)(const ANeuralNetworksDevice*, int64_t*);
typedef int32_t (*PFN_runtime_feature)(void);

/* -- bridge state ------------------------------------------------------------ */

static xnn_lib_t g_lib = 0;
static char g_error[512] = {0};
static char g_missing[512] = {0};
static char g_ext_missing[512] = {0};
static int g_missing_count = 0;
static int g_ext_missing_count = 0;

static PFN_model_create p_model_create = 0;
static PFN_model_add_operand p_model_add_operand = 0;
static PFN_model_add_operation p_model_add_operation = 0;
static PFN_model_identify_io p_model_identify_io = 0;
static PFN_model_set_operand_value p_model_set_operand_value = 0;
static PFN_model_finish p_model_finish = 0;
static PFN_model_free p_model_free = 0;
static PFN_comp_create p_comp_create = 0;
static PFN_comp_finish p_comp_finish = 0;
static PFN_comp_free p_comp_free = 0;
static PFN_exec_create p_exec_create = 0;
static PFN_exec_free p_exec_free = 0;
static PFN_device_count p_device_count = 0;
static PFN_device_get p_device_get = 0;
static PFN_device_name p_device_name = 0;
static PFN_device_type p_device_type = 0;
static PFN_device_version p_device_version = 0;
static PFN_device_feature p_device_feature = 0;
static PFN_runtime_feature p_runtime_feature = 0;

static const char* k_core_export_set[] = {
    "ANeuralNetworksModel_create",
    "ANeuralNetworksModel_addOperand",
    "ANeuralNetworksModel_addOperation",
    "ANeuralNetworksModel_identifyInputsAndOutputs",
    "ANeuralNetworksModel_setOperandValue",
    "ANeuralNetworksModel_finish",
    "ANeuralNetworksModel_free",
    "ANeuralNetworksCompilation_create",
    "ANeuralNetworksCompilation_finish",
    "ANeuralNetworksCompilation_free",
    "ANeuralNetworksExecution_create",
    "ANeuralNetworksExecution_free",
};
#define XNN_CORE_EXPORT_COUNT (sizeof(k_core_export_set) / sizeof(k_core_export_set[0]))

static const char* k_ext_export_set[] = {
    "ANeuralNetworks_getDeviceCount",
    "ANeuralNetworks_getDevice",
    "ANeuralNetworksDevice_getName",
    "ANeuralNetworksDevice_getType",
    "ANeuralNetworksDevice_getVersion",
    "ANeuralNetworksDevice_getFeatureLevel",
    "ANeuralNetworks_getRuntimeFeatureLevel",
};
#define XNN_EXT_EXPORT_COUNT (sizeof(k_ext_export_set) / sizeof(k_ext_export_set[0]))

static void xnn_set_error(const char* msg) {
    snprintf(g_error, sizeof(g_error), "%s", msg);
}

void xnn_unload(void); /* defined at the bottom; used by xnn_load_lib */

/* -- load / classify --------------------------------------------------------- */

static void xnn_join_missing(char* buf, size_t cap, const char* name, int* count) {
    size_t used = strlen(buf);
    snprintf(buf + used, cap - used, "%s%s", used ? "," : "", name);
    *count += 1;
}

static int xnn_finish_load(void) {
    g_missing_count = 0;
    g_missing[0] = 0;
    g_ext_missing_count = 0;
    g_ext_missing[0] = 0;
    for (size_t i = 0; i < XNN_CORE_EXPORT_COUNT; i++) {
        if (!xnn_dlsym(g_lib, k_core_export_set[i])) {
            xnn_join_missing(g_missing, sizeof(g_missing), k_core_export_set[i], &g_missing_count);
        }
    }
    for (size_t i = 0; i < XNN_EXT_EXPORT_COUNT; i++) {
        if (!xnn_dlsym(g_lib, k_ext_export_set[i])) {
            xnn_join_missing(g_ext_missing, sizeof(g_ext_missing), k_ext_export_set[i],
                             &g_ext_missing_count);
        }
    }
    p_model_create = (PFN_model_create)xnn_dlsym(g_lib, "ANeuralNetworksModel_create");
    p_model_add_operand =
        (PFN_model_add_operand)xnn_dlsym(g_lib, "ANeuralNetworksModel_addOperand");
    p_model_add_operation =
        (PFN_model_add_operation)xnn_dlsym(g_lib, "ANeuralNetworksModel_addOperation");
    p_model_identify_io = (PFN_model_identify_io)xnn_dlsym(
        g_lib, "ANeuralNetworksModel_identifyInputsAndOutputs");
    p_model_set_operand_value = (PFN_model_set_operand_value)xnn_dlsym(
        g_lib, "ANeuralNetworksModel_setOperandValue");
    p_model_finish = (PFN_model_finish)xnn_dlsym(g_lib, "ANeuralNetworksModel_finish");
    p_model_free = (PFN_model_free)xnn_dlsym(g_lib, "ANeuralNetworksModel_free");
    p_comp_create = (PFN_comp_create)xnn_dlsym(g_lib, "ANeuralNetworksCompilation_create");
    p_comp_finish = (PFN_comp_finish)xnn_dlsym(g_lib, "ANeuralNetworksCompilation_finish");
    p_comp_free = (PFN_comp_free)xnn_dlsym(g_lib, "ANeuralNetworksCompilation_free");
    p_exec_create = (PFN_exec_create)xnn_dlsym(g_lib, "ANeuralNetworksExecution_create");
    p_exec_free = (PFN_exec_free)xnn_dlsym(g_lib, "ANeuralNetworksExecution_free");
    p_device_count = (PFN_device_count)xnn_dlsym(g_lib, "ANeuralNetworks_getDeviceCount");
    p_device_get = (PFN_device_get)xnn_dlsym(g_lib, "ANeuralNetworks_getDevice");
    p_device_name = (PFN_device_name)xnn_dlsym(g_lib, "ANeuralNetworksDevice_getName");
    p_device_type = (PFN_device_type)xnn_dlsym(g_lib, "ANeuralNetworksDevice_getType");
    p_device_version = (PFN_device_version)xnn_dlsym(g_lib, "ANeuralNetworksDevice_getVersion");
    p_device_feature =
        (PFN_device_feature)xnn_dlsym(g_lib, "ANeuralNetworksDevice_getFeatureLevel");
    p_runtime_feature =
        (PFN_runtime_feature)xnn_dlsym(g_lib, "ANeuralNetworks_getRuntimeFeatureLevel");
    if (g_missing_count != 0) {
        xnn_set_error(g_missing);
        return 2;
    }
    xnn_set_error("");
    return 0;
}

static int xnn_load_lib(const char* soname) {
    xnn_unload();
    g_lib = xnn_dlopen(soname);
    if (!g_lib) {
        snprintf(g_error, sizeof(g_error), "absent: %s", soname);
        return 1;
    }
    return xnn_finish_load();
}

int xnn_load_named(const char* soname) {
    if (!soname) {
        xnn_set_error("null soname");
        return 2;
    }
    return xnn_load_lib(soname);
}

int xnn_load(void) { return xnn_load_lib("libneuralnetworks.so"); }

const char* xnn_error(void) { return g_error; }

int xnn_core_missing_count(void) { return g_missing_count; }

const char* xnn_core_missing(void) { return g_missing; }

int xnn_ext_count(void) { return (int)XNN_EXT_EXPORT_COUNT; }

int xnn_ext_missing_count(void) { return g_ext_missing_count; }

const char* xnn_ext_missing(void) { return g_ext_missing; }

/* -- u32 little-endian slot helpers ------------------------------------------ */

static int xnn_read_ids(const uint8_t* slot, int count, uint32_t* out) {
    if (!slot || count <= 0 || count > XNN_MAX_IDS) return 0;
    for (int i = 0; i < count; i++) {
        const uint8_t* b = slot + (size_t)i * 4u;
        out[i] = (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) |
                 ((uint32_t)b[3] << 24);
    }
    return 1;
}

/* -- functional head ---------------------------------------------------------- */

int64_t xnn_model_create(void) {
    if (!p_model_create) { xnn_set_error("ANeuralNetworksModel_create unresolved"); return 0; }
    ANeuralNetworksModel* m = 0;
    int rc = p_model_create(&m);
    if (rc != 0 || !m) {
        snprintf(g_error, sizeof(g_error), "ANeuralNetworksModel_create rc=%d", rc);
        return 0;
    }
    return (int64_t)(intptr_t)m;
}

int xnn_model_add_tensor(int64_t model, int code, const uint8_t* dims_le, int dim_count,
                         int scale_f32_bits, int zero_point) {
    if (!p_model_add_operand) { xnn_set_error("ANeuralNetworksModel_addOperand unresolved"); return -2; }
    if (!model) { xnn_set_error("null model handle"); return -1; }
    if (dim_count < 0 || dim_count > 6) { xnn_set_error("rank must be 0..6"); return -1; }
    if (dim_count > 0 && !dims_le) { xnn_set_error("null dims slot"); return -1; }
    uint32_t dims[6];
    for (int i = 0; i < dim_count; i++) {
        const uint8_t* b = dims_le + (size_t)i * 4u;
        dims[i] = (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) |
                  ((uint32_t)b[3] << 24);
    }
    XNN_OperandType t;
    t.type = (int32_t)code;
    t.dimensionCount = (uint32_t)dim_count;
    t.dimensions = dim_count > 0 ? dims : 0;
    {
        uint32_t bits = (uint32_t)scale_f32_bits;
        memcpy(&t.scale, &bits, sizeof(float));
    }
    t.zeroPoint = (int32_t)zero_point;
    int rc = p_model_add_operand((ANeuralNetworksModel*)(intptr_t)model, &t);
    if (rc != 0) {
        snprintf(g_error, sizeof(g_error), "ANeuralNetworksModel_addOperand rc=%d", rc);
    }
    return rc;
}

int xnn_model_add_operation(int64_t model, int op, const uint8_t* inputs_le, int input_count,
                            const uint8_t* outputs_le, int output_count) {
    if (!p_model_add_operation) { xnn_set_error("ANeuralNetworksModel_addOperation unresolved"); return -2; }
    if (!model) { xnn_set_error("null model handle"); return -1; }
    uint32_t ins[XNN_MAX_IDS];
    uint32_t outs[XNN_MAX_IDS];
    if (!xnn_read_ids(inputs_le, input_count, ins) ||
        !xnn_read_ids(outputs_le, output_count, outs)) {
        xnn_set_error("operand id array invalid (count 1..64, LE u32)");
        return -1;
    }
    int rc = p_model_add_operation((ANeuralNetworksModel*)(intptr_t)model, (int32_t)op,
                                   (uint32_t)input_count, ins, (uint32_t)output_count, outs);
    if (rc != 0) {
        snprintf(g_error, sizeof(g_error), "ANeuralNetworksModel_addOperation rc=%d", rc);
    }
    return rc;
}

int xnn_model_identify_io(int64_t model, const uint8_t* inputs_le, int input_count,
                          const uint8_t* outputs_le, int output_count) {
    if (!p_model_identify_io) {
        xnn_set_error("ANeuralNetworksModel_identifyInputsAndOutputs unresolved");
        return -2;
    }
    if (!model) { xnn_set_error("null model handle"); return -1; }
    uint32_t ins[XNN_MAX_IDS];
    uint32_t outs[XNN_MAX_IDS];
    if (!xnn_read_ids(inputs_le, input_count, ins) ||
        !xnn_read_ids(outputs_le, output_count, outs)) {
        xnn_set_error("operand id array invalid (count 1..64, LE u32)");
        return -1;
    }
    int rc = p_model_identify_io((ANeuralNetworksModel*)(intptr_t)model, (uint32_t)input_count,
                                 ins, (uint32_t)output_count, outs);
    if (rc != 0) {
        snprintf(g_error, sizeof(g_error),
                 "ANeuralNetworksModel_identifyInputsAndOutputs rc=%d", rc);
    }
    return rc;
}

int xnn_model_set_scalar_i32(int64_t model, int index, int32_t value) {
    if (!p_model_set_operand_value) {
        xnn_set_error("ANeuralNetworksModel_setOperandValue unresolved");
        return -2;
    }
    if (!model) { xnn_set_error("null model handle"); return -1; }
    if (index < 0) { xnn_set_error("negative operand index"); return -1; }
    int rc = p_model_set_operand_value((ANeuralNetworksModel*)(intptr_t)model, (int32_t)index,
                                       &value, sizeof(value));
    if (rc != 0) {
        snprintf(g_error, sizeof(g_error),
                 "ANeuralNetworksModel_setOperandValue(index=%d) rc=%d", index, rc);
    }
    return rc;
}

int xnn_model_finish(int64_t model) {
    if (!p_model_finish) { xnn_set_error("ANeuralNetworksModel_finish unresolved"); return -2; }    if (!model) { xnn_set_error("null model handle"); return -1; }
    int rc = p_model_finish((ANeuralNetworksModel*)(intptr_t)model);
    if (rc != 0) {
        snprintf(g_error, sizeof(g_error), "ANeuralNetworksModel_finish rc=%d", rc);
    }
    return rc;
}

void xnn_model_free(int64_t model) {
    if (p_model_free && model) p_model_free((ANeuralNetworksModel*)(intptr_t)model);
}

int64_t xnn_compilation_create(int64_t model) {
    if (!p_comp_create) { xnn_set_error("ANeuralNetworksCompilation_create unresolved"); return 0; }
    if (!model) { xnn_set_error("null model handle"); return 0; }
    ANeuralNetworksCompilation* c = 0;
    int rc = p_comp_create((ANeuralNetworksModel*)(intptr_t)model, &c);
    if (rc != 0 || !c) {
        snprintf(g_error, sizeof(g_error), "ANeuralNetworksCompilation_create rc=%d", rc);
        return 0;
    }
    return (int64_t)(intptr_t)c;
}

int xnn_compilation_finish(int64_t compilation) {
    if (!p_comp_finish) { xnn_set_error("ANeuralNetworksCompilation_finish unresolved"); return -2; }
    if (!compilation) { xnn_set_error("null compilation handle"); return -1; }
    int rc = p_comp_finish((ANeuralNetworksCompilation*)(intptr_t)compilation);
    if (rc != 0) {
        snprintf(g_error, sizeof(g_error), "ANeuralNetworksCompilation_finish rc=%d", rc);
    }
    return rc;
}

void xnn_compilation_free(int64_t compilation) {
    if (p_comp_free && compilation) p_comp_free((ANeuralNetworksCompilation*)(intptr_t)compilation);
}

int64_t xnn_execution_create(int64_t compilation) {
    if (!p_exec_create) { xnn_set_error("ANeuralNetworksExecution_create unresolved"); return 0; }
    if (!compilation) { xnn_set_error("null compilation handle"); return 0; }
    ANeuralNetworksExecution* e = 0;
    int rc = p_exec_create((ANeuralNetworksCompilation*)(intptr_t)compilation, &e);
    if (rc != 0 || !e) {
        snprintf(g_error, sizeof(g_error), "ANeuralNetworksExecution_create rc=%d", rc);
        return 0;
    }
    return (int64_t)(intptr_t)e;
}

void xnn_execution_free(int64_t execution) {
    if (p_exec_free && execution) p_exec_free((ANeuralNetworksExecution*)(intptr_t)execution);
}

/* -- device query (API 29 extension set) -------------------------------------- */

static const ANeuralNetworksDevice* xnn_get_device(int index) {
    if (!p_device_get) return 0;
    ANeuralNetworksDevice* d = 0;
    if (p_device_get((uint32_t)index, &d) != 0) return 0;
    return d;
}

int xnn_device_count(void) {
    if (!p_device_count) { xnn_set_error("ANeuralNetworks_getDeviceCount unresolved"); return -2; }
    uint32_t n = 0;
    int rc = p_device_count(&n);
    if (rc != 0) {
        snprintf(g_error, sizeof(g_error), "ANeuralNetworks_getDeviceCount rc=%d", rc);
        return -1;
    }
    return (int)n;
}

static int xnn_copy_cstr(const char* src, uint8_t* out, int cap) {
    if (!src) return -1;
    size_t n = strlen(src);
    size_t c = (size_t)cap;
    if (c > 0) {
        size_t m = n < c ? n : c;
        memcpy(out, src, m);
    }
    return (int)n;
}

int xnn_device_name(int index, uint8_t* out, int cap) {
    if (!p_device_name) { xnn_set_error("ANeuralNetworksDevice_getName unresolved"); return -2; }
    const ANeuralNetworksDevice* d = xnn_get_device(index);
    if (!d) { xnn_set_error("getDevice(index) failed"); return -1; }
    const char* name = 0;
    if (p_device_name(d, &name) != 0) { xnn_set_error("Device_getName failed"); return -1; }
    return xnn_copy_cstr(name, out, cap);
}

int xnn_device_type(int index) {
    if (!p_device_type) { xnn_set_error("ANeuralNetworksDevice_getType unresolved"); return -2; }
    const ANeuralNetworksDevice* d = xnn_get_device(index);
    if (!d) { xnn_set_error("getDevice(index) failed"); return -1; }
    int32_t t = -1;
    if (p_device_type(d, &t) != 0) { xnn_set_error("Device_getType failed"); return -1; }
    return (int)t;
}

int xnn_device_version(int index, uint8_t* out, int cap) {
    if (!p_device_version) { xnn_set_error("ANeuralNetworksDevice_getVersion unresolved"); return -2; }
    const ANeuralNetworksDevice* d = xnn_get_device(index);
    if (!d) { xnn_set_error("getDevice(index) failed"); return -1; }
    const char* v = 0;
    if (p_device_version(d, &v) != 0) { xnn_set_error("Device_getVersion failed"); return -1; }
    return xnn_copy_cstr(v, out, cap);
}

int xnn_device_feature_level(int index) {
    if (!p_device_feature) {
        xnn_set_error("ANeuralNetworksDevice_getFeatureLevel unresolved");
        return -2;
    }
    const ANeuralNetworksDevice* d = xnn_get_device(index);
    if (!d) { xnn_set_error("getDevice(index) failed"); return -1; }
    int64_t lvl = -1;
    if (p_device_feature(d, &lvl) != 0) { xnn_set_error("Device_getFeatureLevel failed"); return -1; }
    return (int)lvl;
}

int xnn_runtime_feature_level(void) {
    if (!p_runtime_feature) {
        xnn_set_error("ANeuralNetworks_getRuntimeFeatureLevel unresolved");
        return -2;
    }
    return (int)p_runtime_feature();
}

/* -- error names (ANeuralNetworksErrorCode, r27b) ----------------------------- */

const char* xnn_error_name(int code) {
    switch (code) {
    case 0: return "NO_ERROR";
    case 1: return "OUT_OF_MEMORY";
    case 2: return "INCOMPLETE";
    case 3: return "UNEXPECTED_NULL";
    case 4: return "BAD_DATA";
    case 5: return "OP_FAILED";
    case 6: return "BAD_STATE";
    case 7: return "UNMAPPABLE";
    case 8: return "OUTPUT_INSUFFICIENT_SIZE";
    case 9: return "UNAVAILABLE_DEVICE";
    case 10: return "MISSED_DEADLINE_TRANSIENT";
    case 11: return "MISSED_DEADLINE_PERSISTENT";
    case 14: return "DEAD_OBJECT";
    default: {
        static char buf[48];
        snprintf(buf, sizeof(buf), "UNRECOGNIZED(%d)", code);
        return buf;
    }
    }
}

/* -- teardown ------------------------------------------------------------------ */

void xnn_unload(void) {
    if (g_lib) { xnn_dlclose(g_lib); g_lib = 0; }
    p_model_create = 0; p_model_add_operand = 0; p_model_add_operation = 0;
    p_model_identify_io = 0; p_model_set_operand_value = 0; p_model_finish = 0; p_model_free = 0;
    p_comp_create = 0; p_comp_finish = 0; p_comp_free = 0;
    p_exec_create = 0; p_exec_free = 0;
    p_device_count = 0; p_device_get = 0; p_device_name = 0; p_device_type = 0;
    p_device_version = 0; p_device_feature = 0; p_runtime_feature = 0;
    g_missing_count = 0;
    g_missing[0] = 0;
    g_ext_missing_count = 0;
    g_ext_missing[0] = 0;
}
