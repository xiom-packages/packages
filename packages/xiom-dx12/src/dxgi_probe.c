/* xiom.dx12 DXGI bridge -- MIT OR Apache-2.0, XIOM Authors.
 *
 * dxgi.dll runtime loader + factory/adapter/WARP probe + a hidden-window
 * BGRA8/FIFO swapchain probe (CreateSwapChainForHwnd -> GetBuffer ->
 * GetDesc1 -> Present).  Deliberately includes NO dxgi.h/d3d12.h: the
 * minimal COM ABI (IIDs, vtable slots, struct layouts) is declared locally
 * and the objects are driven through raw vtable pointers, so the bridge
 * compiles with nothing but <windows.h> and has no import dependencies
 * beyond kernel32/user32.
 *
 * ABI sources: Windows SDK 10.0.26100.0 shared dxgi*.h (see PROVENANCE.md);
 * DirectX-Headers @ 461ef513 for the d3d12 side (device/queue creation is
 * delegated to the dx12_probe.c exports).
 *
 * Slot map (absolute, from the pinned headers; own-method plan verified):
 *   IDXGIObject:        2 Release
 *   IDXGIFactory2:     12 EnumAdapters1, 15 CreateSwapChainForHwnd
 *   IDXGIFactory4:     27 EnumWarpAdapter
 *   IDXGIAdapter1:     10 GetDesc1
 *   IDXGISwapChain:     8 Present, 9 GetBuffer, 12 GetDesc
 *   IDXGISwapChain1:   18 GetDesc1
 *
 * Contract used by dxgi.xi (extern "C"):
 *   int         xd12_load_dxgi_named(const char* soname) 0=ok, 1=absent, 2=abi
 *   int         xd12_load_dxgi(void)
 *   const char* xd12_dxgi_error(void)
 *   void*       xd12_resolve_dxgi(const char* name)
 *   int         xd12_dxgi_iid(int which, unsigned char* dst16)
 *   int         xd12_dxgi_factory_probe(unsigned flags) 0=ok, 1=failed, 2=abi
 *   long long   xd12_dxgi_factory_ptr(void)
 *   int         xd12_dxgi_adapter_count(void)
 *   long long   xd12_dxgi_enum_adapter(int index)
 *   long long   xd12_dxgi_warp_adapter(void)
 *   int         xd12_dxgi_warp_device_probe(void) 0=ok, 1=no warp dev, 2=failed
 *   int         xd12_swapchain_probe(int w, int h) 0=ok, 1=no device, 2=failed, 3=abi
 *   getters: xd12_swapchain_hr / _present_hr / _buffer_hr / _getdesc_hr /
 *            _desc_width / _desc_height / _desc_format
 *   int         xd12_dxgi_warp_ok(void)  last EnumWarpAdapter result
 *   void        xd12_dxgi_unload(void)
 */

#include <windows.h>
#include <stdint.h>
#include <string.h>

#include "dxgi_iids.inc"

typedef struct Xd12Guid {
  uint32_t d1;
  uint16_t d2;
  uint16_t d3;
  unsigned char d4[8];
} Xd12Guid;

static const Xd12Guid IID_XD12_FACTORY2 = {
  0x50c83a1c, 0xe072, 0x4c48, {0x87, 0xb0, 0x36, 0x30, 0xfa, 0x36, 0xa6, 0xd0}
};
static const Xd12Guid IID_XD12_FACTORY4 = {
  0x1bc6ea02, 0xef36, 0x464f, {0xbf, 0x0c, 0x21, 0xca, 0x39, 0xe5, 0x16, 0x8a}
};
static const Xd12Guid IID_XD12_ADAPTER1 = {
  0x29038f61, 0x3839, 0x4626, {0x91, 0xfd, 0x08, 0x68, 0x79, 0x01, 0x1a, 0x05}
};
static const Xd12Guid IID_XD12_RESOURCE = {
  0x696442be, 0xa72e, 0x4059, {0xbc, 0x79, 0x5b, 0x5c, 0x98, 0x04, 0x0f, 0xad}
};
static const Xd12Guid IID_XD12_DEVICE = {
  0x189819f1, 0x1db6, 0x4b57, {0xbe, 0x54, 0x18, 0x21, 0x33, 0x9b, 0x85, 0xf7}
};
static const Xd12Guid IID_XD12_QUEUE = {
  0x0ec870a6, 0x5d7e, 0x4c22, {0x8c, 0xfc, 0x5b, 0xaa, 0xe0, 0x76, 0x16, 0xed}
};

typedef int32_t(WINAPI* PFN_CreateFactory2)(uint32_t flags, const Xd12Guid* riid, void** out);
typedef uint32_t(WINAPI* PFN_Release)(void* self);
typedef int32_t(WINAPI* PFN_EnumAdapters1)(void* self, uint32_t index, void** out);
typedef int32_t(WINAPI* PFN_EnumWarpAdapter)(void* self, const Xd12Guid* riid, void** out);
typedef int32_t(WINAPI* PFN_CreateSwapChainForHwnd)(void* self, void* device, void* hwnd,
    const void* desc, const void* fullscreen_desc, void* restrict_output, void** out);
typedef int32_t(WINAPI* PFN_Present)(void* self, uint32_t sync, uint32_t flags);
typedef int32_t(WINAPI* PFN_GetBuffer)(void* self, uint32_t index, const Xd12Guid* riid, void** out);
typedef void(WINAPI* PFN_GetDesc1)(void* self, void* out);
typedef int32_t(WINAPI* PFN_CreateDevice)(void* adapter, int32_t level, const Xd12Guid* riid, void** out);

/* dx12_probe.c exports (same package). */
int __cdecl xd12_load(void);
int __cdecl xd12_device_probe(void);
long long __cdecl xd12_device_ptr(void);

#ifndef DXGI_ERROR_NOT_FOUND
#define DXGI_ERROR_NOT_FOUND ((int32_t)0x887A0002)
#endif
#ifndef DXGI_STATUS_OCCLUDED
#define DXGI_STATUS_OCCLUDED ((int32_t)0x087A0001)
#endif

/* DXGI_SWAP_CHAIN_DESC1 (x64 layout pinned from the SDK header). */
typedef struct Xd12ScDesc1 {
  uint32_t Width;
  uint32_t Height;
  uint32_t Format;
  int32_t Stereo;
  uint32_t SampleCount;
  uint32_t SampleQuality;
  uint32_t BufferUsage;
  uint32_t BufferCount;
  uint32_t Scaling;
  uint32_t SwapEffect;
  uint32_t AlphaMode;
  uint32_t Flags;
} Xd12ScDesc1;

static HMODULE m_dxgi = 0;
static PFN_CreateFactory2 p_create_factory2 = 0;
static char s_error[512];
static void* s_factory = 0;
static int s_adapter_count = -1;
static int s_warp_ok = 0;

static void set_err(const char* msg) {
  if (!msg) msg = "(no message)";
  strncpy(s_error, msg, sizeof(s_error) - 1);
  s_error[sizeof(s_error) - 1] = 0;
}

static void release_object(void* obj) {
  if (!obj) return;
  void** vtbl = *(void***)obj;
  ((PFN_Release)vtbl[2])(obj);
}

static void clear_dxgi_state(void) {
  m_dxgi = 0;
  p_create_factory2 = 0;
  s_factory = 0;
  s_adapter_count = -1;
  s_warp_ok = 0;
}

int __cdecl xd12_load_dxgi_named(const char* soname) {
  clear_dxgi_state();
  if (!soname || !soname[0]) { set_err("empty soname"); return 1; }
  m_dxgi = LoadLibraryA(soname);
  if (!m_dxgi) { set_err("LoadLibrary failed for the requested soname"); return 1; }
  p_create_factory2 = (PFN_CreateFactory2)GetProcAddress(m_dxgi, "CreateDXGIFactory2");
  if (!p_create_factory2) {
    set_err("missing export: CreateDXGIFactory2");
    FreeLibrary(m_dxgi);
    clear_dxgi_state();
    return 2;
  }
  return 0;
}

int __cdecl xd12_load_dxgi(void) { return xd12_load_dxgi_named("dxgi.dll"); }

const char* __cdecl xd12_dxgi_error(void) { return s_error; }

void* __cdecl xd12_resolve_dxgi(const char* name) {
  if (!m_dxgi || !name || !name[0]) return 0;
  return (void*)GetProcAddress(m_dxgi, name);
}

int __cdecl xd12_dxgi_iid(int which, unsigned char* dst16) {
  if (!dst16 || which < 0 || which >= g_xd12_dxgi_iid_count) return -1;
  memcpy(dst16, g_xd12_dxgi_iids[which], 16);
  return 0;
}

/* CreateDXGIFactory2 -> IDXGIFactory2 (kept live); then count adapters via
 * IDXGIFactory2::EnumAdapters1 (slot 12) and probe IDXGIFactory4::
 * EnumWarpAdapter (slot 27) through a QueryInterface for IID_IDXGIFactory4. */
int __cdecl xd12_dxgi_factory_probe(unsigned flags) {
  if (!p_create_factory2) return 2;
  if (s_factory) return 0;
  void* fac = 0;
  int32_t hr = p_create_factory2(flags, &IID_XD12_FACTORY2, &fac);
  if (hr != 0 || !fac) {
    set_err("CreateDXGIFactory2 failed");
    return 1;
  }
  void** vtbl = *(void***)fac;
  int count = 0;
  for (;;) {
    void* ad = 0;
    int32_t hr2 = ((PFN_EnumAdapters1)vtbl[12])(fac, (uint32_t)count, &ad);
    if (hr2 == DXGI_ERROR_NOT_FOUND) break;
    if (hr2 != 0) { set_err("EnumAdapters1 failed"); release_object(fac); return 1; }
    release_object(ad);
    count++;
    if (count > 64) break; /* defensive cap */
  }
  /* WARP adapter via IDXGIFactory4 (available on Win10+). */
  void* fac4 = 0;
  int32_t qhr = ((int32_t(WINAPI*)(void*, const Xd12Guid*, void**))vtbl[0])(fac, &IID_XD12_FACTORY4, &fac4);
  if (qhr == 0 && fac4) {
    void** v4 = *(void***)fac4;
    void* warp = 0;
    int32_t whr = ((PFN_EnumWarpAdapter)v4[27])(fac4, &IID_XD12_ADAPTER1, &warp);
    s_warp_ok = (whr == 0 && warp) ? 1 : 0;
    release_object(warp);
    release_object(fac4);
  } else {
    s_warp_ok = 0;
  }
  s_factory = fac;
  s_adapter_count = count;
  return 0;
}

long long __cdecl xd12_dxgi_factory_ptr(void) {
  return (long long)(intptr_t)s_factory;
}

int __cdecl xd12_dxgi_adapter_count(void) { return s_adapter_count; }

long long __cdecl xd12_dxgi_enum_adapter(int index) {
  if (!s_factory || index < 0) return 0;
  void** vtbl = *(void***)s_factory;
  void* ad = 0;
  int32_t hr = ((PFN_EnumAdapters1)vtbl[12])(s_factory, (uint32_t)index, &ad);
  if (hr != 0) return 0;
  return (long long)(intptr_t)ad;
}

long long __cdecl xd12_dxgi_warp_adapter(void) {
  if (!s_factory) return 0;
  void** vtbl = *(void***)s_factory;
  void* warp = 0;
  int32_t hr = ((PFN_EnumWarpAdapter)vtbl[27])(s_factory, &IID_XD12_ADAPTER1, &warp);
  if (hr != 0) return 0;
  return (long long)(intptr_t)warp;
}

/* D3D12 device on the WARP adapter (adapter-less hosts reach a real device). */
int __cdecl xd12_dxgi_warp_device_probe(void) {
  long long warp = xd12_dxgi_warp_adapter();
  if (!warp) return 1;
  int lr = xd12_load();
  if (lr != 0) return 2;
  PFN_CreateDevice cd = (PFN_CreateDevice)GetProcAddress(
      GetModuleHandleA("d3d12.dll"), "D3D12CreateDevice");
  if (!cd) return 2;
  void* dev = 0;
  int32_t hr = cd((void*)(intptr_t)warp, 0xB000, &IID_XD12_DEVICE, &dev);
  release_object((void*)(intptr_t)warp);
  if (hr != 0 || !dev) { set_err("D3D12CreateDevice(WARP) failed"); return 2; }
  release_object(dev);
  return 0;
}

/* Hidden-window BGRA8/FIFO swapchain probe.  Uses the dx12_probe.c device
 * path, then IDXGIFactory2::CreateSwapChainForHwnd (slot 15),
 * IDXGISwapChain1::GetBuffer (slot 9), GetDesc1 (slot 18, x64 member
 * return: RDX out pointer) and Present (slot 8). */
static int s_swap_hr = -1;
static int s_present_hr = -1;
static int s_buffer_hr = -1;
static int s_getdesc_hr = -1;
static int s_desc_width = -1;
static int s_desc_height = -1;
static int s_desc_format = -1;

int __cdecl xd12_swapchain_probe(int width, int height) {
  s_swap_hr = s_present_hr = s_buffer_hr = s_getdesc_hr = -1;
  s_desc_width = s_desc_height = s_desc_format = -1;
  if (!p_create_factory2) return 3;
  if (!s_factory) {
    int fr = xd12_dxgi_factory_probe(0);
    if (fr != 0) return 3;
  }
  if (xd12_load() != 0) return 1;
  if (xd12_device_probe() != 0) return 1;
  void* dev = (void*)(intptr_t)xd12_device_ptr();
  if (!dev) return 1;

  /* command queue on the device (slot 8, DIRECT, priority 0) */
  void* queue = 0;
  struct { int32_t Type; int32_t Priority; int32_t Flags; uint32_t NodeMask; } qd;
  memset(&qd, 0, sizeof(qd));
  int32_t qhr = ((int32_t(WINAPI*)(void*, const void*, const Xd12Guid*, void**))
      (*(void***)dev)[8])(dev, &qd, &IID_XD12_QUEUE, &queue);
  if (qhr != 0 || !queue) { set_err("CreateCommandQueue failed for swapchain"); return 2; }

  /* hidden window */
  WNDCLASSEXA wc;
  memset(&wc, 0, sizeof(wc));
  wc.cbSize = sizeof(wc);
  wc.lpfnWndProc = DefWindowProcA;
  wc.hInstance = GetModuleHandleA(0);
  wc.lpszClassName = "Xd12SwapchainProbe";
  RegisterClassExA(&wc);
  HWND hwnd = CreateWindowExA(0, wc.lpszClassName, "xd12-probe",
      WS_OVERLAPPEDWINDOW, 0, 0, width, height, 0, 0, wc.hInstance, 0);
  if (!hwnd) { release_object(queue); set_err("CreateWindowEx failed"); return 2; }

  Xd12ScDesc1 sd;
  memset(&sd, 0, sizeof(sd));
  sd.Width = (uint32_t)width;
  sd.Height = (uint32_t)height;
  sd.Format = 0x57;      /* DXGI_FORMAT_B8G8R8A8_UNORM */
  sd.SampleCount = 1;
  sd.BufferUsage = 0x20; /* DXGI_USAGE_RENDER_TARGET_OUTPUT */
  sd.BufferCount = 2;
  sd.Scaling = 0;        /* DXGI_SCALING_STRETCH */
  sd.SwapEffect = 4;     /* DXGI_SWAP_EFFECT_FLIP_DISCARD */
  void** vtbl = *(void***)s_factory;
  void* sc = 0;
  s_swap_hr = ((PFN_CreateSwapChainForHwnd)vtbl[15])(s_factory, queue, hwnd,
      &sd, 0, 0, &sc);
  if (s_swap_hr != 0 || !sc) {
    DestroyWindow(hwnd);
    release_object(queue);
    return 2;
  }
  void** sv = *(void***)sc;

  /* back buffer roundtrip: GetBuffer(0) -> Release (D3D12 swapchain buffers
   * are IID_ID3D12Resource). */
  void* bb = 0;
  s_buffer_hr = ((PFN_GetBuffer)sv[9])(sc, 0, &IID_XD12_RESOURCE, &bb);
  if (bb) release_object(bb);

  /* GetDesc1 (sret via RDX for the 48-byte struct) */
  struct { uint32_t Width; uint32_t Height; uint32_t Format; int32_t Stereo;
           uint32_t sc, sq, usage, buffers, scaling, swapEffect, alpha, flags; } got;
  memset(&got, 0, sizeof(got));
  ((PFN_GetDesc1)sv[18])(sc, &got);
  s_getdesc_hr = 0;
  s_desc_width = (int)got.Width;
  s_desc_height = (int)got.Height;
  s_desc_format = (int)got.Format;

  /* present once (occluded is success-ish for a hidden window) */
  s_present_hr = ((PFN_Present)sv[8])(sc, 1, 0);

  release_object(sc);
  DestroyWindow(hwnd);
  release_object(queue);
  return 0;
}

int __cdecl xd12_swapchain_hr(void) { return s_swap_hr; }
int __cdecl xd12_swapchain_present_hr(void) { return s_present_hr; }
int __cdecl xd12_swapchain_buffer_hr(void) { return s_buffer_hr; }
int __cdecl xd12_swapchain_getdesc_hr(void) { return s_getdesc_hr; }
int __cdecl xd12_swapchain_desc_width(void) { return s_desc_width; }
int __cdecl xd12_swapchain_desc_height(void) { return s_desc_height; }
int __cdecl xd12_swapchain_desc_format(void) { return s_desc_format; }

int __cdecl xd12_dxgi_warp_ok(void) { return s_warp_ok; }

void __cdecl xd12_dxgi_unload(void) {
  if (s_factory) { release_object(s_factory); s_factory = 0; }
  if (m_dxgi) { FreeLibrary(m_dxgi); m_dxgi = 0; }
  clear_dxgi_state();
}
