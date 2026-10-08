/* xiom.directx12 probe bridge -- MIT OR Apache-2.0, XIOM Authors.
 *
 * Capability probe for Direct3D 12 / DXGI.  Deliberately includes NO
 * d3d12.h/dxgi.h: the minimal ABI (entry-point signatures, IIDs, vtable slot
 * offsets, struct layouts) is declared locally and verified against the
 * pinned Windows SDK headers (see SPEC.md).  Libraries are resolved at
 * runtime (LoadLibraryA + GetProcAddress), so there are no import
 * dependencies beyond kernel32 and no --link flags.
 *
 * Contract used by directx12.xi (extern "C"):
 *   int  xd12_load_named(const char* d3d12_soname, const char* dxgi_soname)
 *                                            0=ok, 1=absent, 2=abi
 *   const char* xd12_error(void)
 *   int  xd12_device_probe(void)             0=ok, 1=no device, 2=internal
 *   int  xd12_feature_level(void)            highest accepted D3D_FEATURE_LEVEL
 *   const char* xd12_adapter_name(void)      first adapter description (UTF-8)
 *   unsigned xd12_vendor_id(void)
 *   unsigned xd12_device_id(void)
 *   int  xd12_adapter_count(void)
 *   void xd12_unload(void)
 *
 * Feature levels are probed by descending attempts (12_2 -> 11_0): the first
 * level D3D12CreateDevice accepts is the device's capability.
 */

#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* -- minimal ABI (verified against SDK 10.0.22621.0) ---------------------- */

#define XD12_FEATURE_LEVEL_11_0 0xb000
#define XD12_FEATURE_LEVEL_11_1 0xb100
#define XD12_FEATURE_LEVEL_12_0 0xc000
#define XD12_FEATURE_LEVEL_12_1 0xc100
#define XD12_FEATURE_LEVEL_12_2 0xc200

/* MIDL_INTERFACE("189819f1-1db6-4b57-be54-1821339b85f7") ID3D12Device */
/* MIDL_INTERFACE("770aae78-f26f-4dba-a829-253c83d1b387") IDXGIFactory1 */
typedef struct Xd12Guid {
  uint32_t d1;
  uint16_t d2;
  uint16_t d3;
  unsigned char d4[8];
} Xd12Guid;

static const Xd12Guid IID_XD12_ID3D12Device = {
  0x189819f1, 0x1db6, 0x4b57, {0xbe, 0x54, 0x18, 0x21, 0x33, 0x9b, 0x85, 0xf7}
};
static const Xd12Guid IID_XD12_IDXGIFACTORY1 = {
  0x770aae78, 0xf26f, 0x4dba, {0xa8, 0x29, 0x25, 0x3c, 0x83, 0xd1, 0xb3, 0x87}
};

/* DXGI_ADAPTER_DESC: WCHAR Description[128] (0), UINT VendorId (256),
 * UINT DeviceId (260). */
#define XD12_DESC_OFFSET_VENDOR 256
#define XD12_DESC_OFFSET_DEVICE 260
#define XD12_DESC_BUFSIZE 1024

typedef int32_t (WINAPI *PFN_D3D12CreateDevice)(void* adapter, uint32_t min_feature_level,
                                                const Xd12Guid*, void** device);
typedef int32_t (WINAPI *PFN_CreateDXGIFactory1)(const Xd12Guid*, void** factory);

typedef uint32_t (WINAPI *PFN_Release)(void*);
typedef int32_t (WINAPI *PFN_EnumAdapters1)(void*, uint32_t, void**);
typedef int32_t (WINAPI *PFN_GetDesc)(void*, void*);

/* vtable slots as in the dx11 probe: IDXGIFactory1 12 = EnumAdapters1,
 * IDXGIAdapter 8 = GetDesc (IUnknown 0-2). */

static HMODULE m_d3d = 0;
static HMODULE m_dxgi = 0;
static PFN_D3D12CreateDevice p_create_device = 0;
static PFN_CreateDXGIFactory1 p_create_factory1 = 0;

static char s_error[512];
static int s_feature_level = -1;
static char s_adapter_name[256];
static uint32_t s_vendor_id = 0;
static uint32_t s_device_id = 0;
static int s_adapter_count = 0;

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
  m_d3d = 0;
  m_dxgi = 0;
  p_create_device = 0;
  p_create_factory1 = 0;
  s_feature_level = -1;
  s_adapter_name[0] = 0;
  s_vendor_id = 0;
  s_device_id = 0;
  s_adapter_count = 0;
}

static void** vtbl_of(void* obj) {
  return (void**)(*((void***)obj));
}

static void release_obj(void* obj) {
  if (!obj) return;
  PFN_Release release = (PFN_Release)vtbl_of(obj)[2];
  release(obj);
}

int __cdecl xd12_load_named(const char* d3d12_soname, const char* dxgi_soname) {
  clear_state();
  if (!d3d12_soname || !d3d12_soname[0] || !dxgi_soname || !dxgi_soname[0]) {
    set_err("empty soname");
    return 1;
  }
  m_d3d = LoadLibraryA(d3d12_soname);
  if (!m_d3d) { set_err("LoadLibrary failed: d3d12 soname"); return 1; }
  p_create_device = (PFN_D3D12CreateDevice)GetProcAddress(m_d3d, "D3D12CreateDevice");
  if (!p_create_device) { set_err("missing export: D3D12CreateDevice"); FreeLibrary(m_d3d); clear_state(); return 2; }

  m_dxgi = LoadLibraryA(dxgi_soname);
  if (!m_dxgi) { set_err("LoadLibrary failed: dxgi soname"); FreeLibrary(m_d3d); clear_state(); return 1; }
  p_create_factory1 = (PFN_CreateDXGIFactory1)GetProcAddress(m_dxgi, "CreateDXGIFactory1");
  if (!p_create_factory1) { set_err("missing export: CreateDXGIFactory1"); FreeLibrary(m_dxgi); FreeLibrary(m_d3d); clear_state(); return 2; }
  return 0;
}

int __cdecl xd12_load(void) {
  return xd12_load_named("d3d12.dll", "dxgi.dll");
}

const char* __cdecl xd12_error(void) { return s_error; }

int __cdecl xd12_device_probe(void) {
  if (!p_create_device || !p_create_factory1) return 2;

  /* Adapter enumeration + first-adapter description via DXGI. */
  void* factory = 0;
  int32_t hr = p_create_factory1(&IID_XD12_IDXGIFACTORY1, &factory);
  if (hr >= 0 && factory) {
    PFN_EnumAdapters1 enum_adapters1 = (PFN_EnumAdapters1)vtbl_of(factory)[12];
    for (uint32_t i = 0; i < 16; i++) {
      void* adapter = 0;
      int32_t ar = enum_adapters1(factory, i, &adapter);
      if (ar < 0 || !adapter) break;
      s_adapter_count++;
      if (i == 0) {
        unsigned char desc[XD12_DESC_BUFSIZE];
        memset(desc, 0, sizeof(desc));
        PFN_GetDesc get_desc = (PFN_GetDesc)vtbl_of(adapter)[8];
        if (get_desc(adapter, desc) >= 0) {
          WideCharToMultiByte(65001 /*CP_UTF8*/, 0, (const wchar_t*)desc, -1,
                              s_adapter_name, sizeof(s_adapter_name), 0, 0);
          memcpy(&s_vendor_id, desc + XD12_DESC_OFFSET_VENDOR, 4);
          memcpy(&s_device_id, desc + XD12_DESC_OFFSET_DEVICE, 4);
        }
      }
      release_obj(adapter);
    }
    release_obj(factory);
  }

  /* Descending feature-level attempts: the first accepted level is the max. */
  static const uint32_t levels[5] = {
    XD12_FEATURE_LEVEL_12_2, XD12_FEATURE_LEVEL_12_1, XD12_FEATURE_LEVEL_12_0,
    XD12_FEATURE_LEVEL_11_1, XD12_FEATURE_LEVEL_11_0
  };
  for (int i = 0; i < 5; i++) {
    void* device = 0;
    hr = p_create_device(0, levels[i], &IID_XD12_ID3D12Device, &device);
    if (hr >= 0 && device) {
      s_feature_level = (int)levels[i];
      release_obj(device);
      return 0;
    }
  }
  set_err_hr("D3D12CreateDevice", hr);
  return 1;
}

int __cdecl xd12_feature_level(void) { return s_feature_level; }
const char* __cdecl xd12_adapter_name(void) { return s_adapter_name; }
unsigned __cdecl xd12_vendor_id(void) { return (unsigned)s_vendor_id; }
unsigned __cdecl xd12_device_id(void) { return (unsigned)s_device_id; }
int __cdecl xd12_adapter_count(void) { return s_adapter_count; }

void __cdecl xd12_unload(void) {
  if (m_dxgi) FreeLibrary(m_dxgi);
  if (m_d3d) FreeLibrary(m_d3d);
  clear_state();
}
