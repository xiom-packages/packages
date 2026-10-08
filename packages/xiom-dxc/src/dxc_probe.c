/* xiom.dxc probe bridge -- MIT OR Apache-2.0, XIOM Authors.
 *
 * Capability probe for the DirectX Shader Compiler (dxcompiler.dll).
 * Deliberately includes NO dxcapi.h: the minimal COM ABI (CLSIDs/IIDs,
 * vtable slots, DxcBuffer) is declared locally and the objects are driven
 * through raw vtable pointers, so the bridge compiles without the Windows
 * SDK or the DXC package.  The library is resolved at runtime
 * (LoadLibraryA + GetProcAddress), so there are no import dependencies
 * beyond kernel32 and no --link flags.
 *
 * ABI source: dxcapi.h (SDK 1.4.350.0 / DirectXShaderCompiler commit
 * fe2615732); GUIDs and vtable order verified against that header, pinned in
 * SPEC.md.  IDxcCompiler3 derives from IUnknown (slots: 0 QI, 1 AddRef,
 * 2 Release, 3 Compile, 4 Disassemble).  IDxcResult derives from
 * IDxcOperationResult (slots: 3 GetStatus, 4 GetResult, 5 GetErrorBuffer,
 * 6 HasOutput, 7 GetOutput).  IDxcBlob: 3 GetBufferPointer, 4 GetBufferSize.
 *
 * Contract used by dxc.xi (extern "C"):
 *   int  xdxc_load_named(const char* soname)  0=ok, 1=absent, 2=abi
 *   const char* xdxc_error(void)
 *   int  xdxc_instance_probe(void)            0=ok, 1=no instance, 2=internal
 *   int  xdxc_compile_probe(void)             0=ok, 1=compile failed, 2=internal
 *   int  xdxc_object_size(void)               DXIL blob size from the probe
 *   void xdxc_unload(void)
 */

#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct XdxcGuid {
  uint32_t d1;
  uint16_t d2;
  uint16_t d3;
  unsigned char d4[8];
} XdxcGuid;

static const XdxcGuid CLSID_XDXC_COMPILER = {
  0x73e22d93, 0xe6ce, 0x47f3, {0xb5, 0xbf, 0xf0, 0x66, 0x4f, 0x39, 0xc1, 0xb0}
};
static const XdxcGuid IID_XDXC_COMPILER3 = {
  0x228b4687, 0x5a6a, 0x4730, {0x90, 0x0c, 0x97, 0x02, 0xb2, 0x20, 0x3f, 0x54}
};
static const XdxcGuid IID_XDXC_RESULT = {
  0x58346cda, 0xdde7, 0x4497, {0x94, 0x61, 0x6f, 0x87, 0xaf, 0x5e, 0x06, 0x59}
};
static const XdxcGuid IID_XDXC_BLOB = {
  0x8ba5fb08, 0x5195, 0x40e2, {0xac, 0x58, 0x0d, 0x98, 0x9c, 0x3a, 0x01, 0x02}
};

typedef struct XdxcBuffer {
  const void* Ptr;
  size_t Size;
  uint32_t Encoding; /* 0 = ANSI text / unknown */
} XdxcBuffer;

/* vtable slot signatures (STDMETHODCALLTYPE = __stdcall on x86; single
 * convention on x64 -- WINAPI is the portable spelling here). */
typedef int32_t (WINAPI *PFN_CreateInstance)(const XdxcGuid*, const XdxcGuid*, void**);
typedef uint32_t (WINAPI *PFN_AddRef)(void*);
typedef uint32_t (WINAPI *PFN_Release)(void*);
typedef int32_t (WINAPI *PFN_GetStatus)(void*, int32_t*);
typedef int32_t (WINAPI *PFN_GetOutput)(void*, int32_t, const XdxcGuid*, void**, void**);
typedef int32_t (WINAPI *PFN_Compile3)(void*, const XdxcBuffer*, const wchar_t* const*, uint32_t, void*, const XdxcGuid*, void**);
typedef size_t (WINAPI *PFN_GetBufferSize)(void*);

#define XDXC_OUT_OBJECT 1

static HMODULE m_lib = 0;
static PFN_CreateInstance p_create = 0;
static char s_error[512];
static int s_object_size = -1;

static void set_err(const char* msg) {
  if (!msg) msg = "(no message)";
  strncpy(s_error, msg, sizeof(s_error) - 1);
  s_error[sizeof(s_error) - 1] = 0;
}

static void set_err_hr(const char* what, int32_t hr) {
  char buf[512];
  int n = (int)snprintf(buf, sizeof(buf), "%s failed (hr=0x%08X)", what, (unsigned)hr);
  if (n < 0) buf[0] = 0;
  set_err(buf);
}

static void clear_state(void) {
  m_lib = 0;
  p_create = 0;
  s_object_size = -1;
}

static void** vtbl_of(void* obj) {
  return (void**)(*((void***)obj));
}

static void release_obj(void* obj) {
  if (!obj) return;
  void** vtbl = vtbl_of(obj);
  PFN_Release release = (PFN_Release)vtbl[2];
  release(obj);
}

int __cdecl xdxc_load_named(const char* soname) {
  clear_state();
  if (!soname || !soname[0]) { set_err("empty soname"); return 1; }
  m_lib = LoadLibraryA(soname);
  if (!m_lib) { set_err("LoadLibrary failed for the requested soname"); return 1; }
  p_create = (PFN_CreateInstance)GetProcAddress(m_lib, "DxcCreateInstance");
  if (!p_create) { set_err("missing export: DxcCreateInstance"); FreeLibrary(m_lib); clear_state(); return 2; }
  return 0;
}

int __cdecl xdxc_load(void) {
  return xdxc_load_named("dxcompiler.dll");
}

const char* __cdecl xdxc_error(void) { return s_error; }

int __cdecl xdxc_instance_probe(void) {
  if (!p_create) return 2;
  void* compiler = 0;
  int32_t hr = p_create(&CLSID_XDXC_COMPILER, &IID_XDXC_COMPILER3, &compiler);
  if (hr < 0 || !compiler) {
    set_err_hr("DxcCreateInstance(IDxcCompiler3)", hr);
    return 1;
  }
  release_obj(compiler);
  return 0;
}

int __cdecl xdxc_compile_probe(void) {
  if (!p_create) return 2;

  void* compiler = 0;
  int32_t hr = p_create(&CLSID_XDXC_COMPILER, &IID_XDXC_COMPILER3, &compiler);
  if (hr < 0 || !compiler) {
    set_err_hr("DxcCreateInstance(IDxcCompiler3)", hr);
    return 2;
  }

  static const char* source =
    "float4 main() : SV_Target { return float4(0.0, 1.0, 0.0, 1.0); }\n";
  static const wchar_t* args[4];
  args[0] = L"-T";
  args[1] = L"ps_6_0";
  args[2] = L"-E";
  args[3] = L"main";

  XdxcBuffer buf;
  buf.Ptr = source;
  buf.Size = strlen(source);
  buf.Encoding = 0;

  void** cvtbl = vtbl_of(compiler);
  PFN_Compile3 compile = (PFN_Compile3)cvtbl[3];

  void* result = 0;
  hr = compile(compiler, &buf, args, 4, 0, &IID_XDXC_RESULT, &result);
  if (hr < 0 || !result) {
    set_err_hr("IDxcCompiler3::Compile", hr);
    release_obj(compiler);
    return 1;
  }

  /* Overall compile status (IDxcResult : IDxcOperationResult). */
  void** rvtbl = vtbl_of(result);
  PFN_GetStatus get_status = (PFN_GetStatus)rvtbl[3];
  int32_t status = 0;
  int32_t sr = get_status(result, &status);
  if (sr < 0 || status < 0) {
    if (sr < 0) {
      set_err_hr("IDxcOperationResult::GetStatus", sr);
    } else {
      set_err_hr("shader compilation", status);
    }
    release_obj(result);
    release_obj(compiler);
    return 1;
  }

  /* DXC_OUT_OBJECT -> IDxcBlob. */
  PFN_GetOutput get_output = (PFN_GetOutput)rvtbl[7];
  void* blob = 0;
  hr = get_output(result, XDXC_OUT_OBJECT, &IID_XDXC_BLOB, &blob, 0);
  if (hr < 0 || !blob) {
    set_err_hr("IDxcResult::GetOutput(DXC_OUT_OBJECT)", hr);
    release_obj(result);
    release_obj(compiler);
    return 1;
  }

  void** bvtbl = vtbl_of(blob);
  PFN_GetBufferSize get_size = (PFN_GetBufferSize)bvtbl[4];
  size_t size = get_size(blob);
  s_object_size = (int)size;

  release_obj(blob);
  release_obj(result);
  release_obj(compiler);
  return 0;
}

int __cdecl xdxc_object_size(void) { return s_object_size; }

void __cdecl xdxc_unload(void) {
  if (m_lib) FreeLibrary(m_lib);
  clear_state();
}
