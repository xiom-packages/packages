/* xiom.dx12 foundation probe bridge -- MIT OR Apache-2.0, XIOM Authors.
 *
 * Foundation probe for Direct3D 12 (d3d12.dll at runtime).  Deliberately
 * includes NO d3d12.h: the minimal COM ABI (IIDs, vtable slots, the
 * D3D12CreateDevice signature) is declared locally and the objects are
 * driven through raw vtable pointers, so the bridge compiles with nothing
 * but <windows.h> and has no import dependencies beyond kernel32.  This
 * follows the xiom.dxc COM precedent.
 *
 * ABI source: microsoft/DirectX-Headers @ 461ef513
 * (include/directx/d3d12.h, SHA256 AFA193D3...; pinned in PROVENANCE.md):
 *   D3D12CreateDevice(IUnknown* pAdapter, D3D_FEATURE_LEVEL, REFIID, void**)
 *   IID_ID3D12Device          189819f1-1db6-4b57-be54-1821339b85f7
 *   IID_ID3D12CommandAllocator 6102dee4-af59-4b09-b999-b44d73f09b24
 *   ID3D12Device vtable: 0 QI, 1 AddRef, 2 Release, 3 GetPrivateData,
 *     4 SetPrivateData, 5 SetPrivateDataInterface, 6 SetName,
 *     7 GetNodeCount, 8 CreateCommandQueue, 9 CreateCommandAllocator, ...
 *   ID3D12CommandAllocator: IUnknown + ID3D12Object, 7 Reset, 8 GetDesc.
 *   D3D_FEATURE_LEVEL_11_0 = 0xB000; D3D12_COMMAND_LIST_TYPE_DIRECT = 0.
 *
 * Contract used by dx12.xi (extern "C"):
 *   int         xd12_load_named(const char* soname)  0=ok, 1=absent, 2=abi
 *   int         xd12_load(void)
 *   const char* xd12_error(void)
 *   int         xd12_device_probe(void)  0=ok, 1=no device, 2=internal
 *   int         xd12_device_node_count(void)
 *   int         xd12_allocator_ok(void)  1 when the allocator roundtrip ran
 *   void        xd12_unload(void)        releases the device if held
 */

#include <windows.h>
#include <stdint.h>
#include <string.h>

typedef struct Xd12Guid {
  uint32_t d1;
  uint16_t d2;
  uint16_t d3;
  unsigned char d4[8];
} Xd12Guid;

static const Xd12Guid IID_XD12_DEVICE = {
  0x189819f1, 0x1db6, 0x4b57, {0xbe, 0x54, 0x18, 0x21, 0x33, 0x9b, 0x85, 0xf7}
};
static const Xd12Guid IID_XD12_COMMAND_ALLOCATOR = {
  0x6102dee4, 0xaf59, 0x4b09, {0xb9, 0x99, 0xb4, 0x4d, 0x73, 0xf0, 0x9b, 0x24}
};

typedef int32_t (WINAPI *PFN_CreateDevice)(void* adapter, int32_t min_feature_level,
                                           const Xd12Guid* riid, void** out);
typedef uint32_t (WINAPI *PFN_Release)(void* self);
typedef uint32_t (WINAPI *PFN_GetNodeCount)(void* self);
typedef int32_t (WINAPI *PFN_CreateCommandAllocator)(void* self, int32_t type,
                                                     const Xd12Guid* riid, void** out);

static HMODULE m_d3d12 = 0;
static PFN_CreateDevice p_create_device = 0;
static char s_error[512];
static void* s_device = 0;
static int s_node_count = 0;
static int s_allocator_ok = 0;

static void set_err(const char* msg) {
  if (!msg) msg = "(no message)";
  strncpy(s_error, msg, sizeof(s_error) - 1);
  s_error[sizeof(s_error) - 1] = 0;
}

static void clear_state(void) {
  m_d3d12 = 0;
  p_create_device = 0;
  s_device = 0;
  s_node_count = 0;
  s_allocator_ok = 0;
}

static void release_object(void* obj) {
  if (!obj) return;
  void** vtbl = *(void***)obj;
  PFN_Release release = (PFN_Release)vtbl[2];
  release(obj);
}

int __cdecl xd12_load_named(const char* soname) {
  clear_state();
  if (!soname || !soname[0]) { set_err("empty soname"); return 1; }
  m_d3d12 = LoadLibraryA(soname);
  if (!m_d3d12) { set_err("LoadLibrary failed for the requested soname"); return 1; }
  p_create_device = (PFN_CreateDevice)GetProcAddress(m_d3d12, "D3D12CreateDevice");
  if (!p_create_device) {
    set_err("missing export: D3D12CreateDevice");
    FreeLibrary(m_d3d12);
    clear_state();
    return 2;
  }
  return 0;
}

int __cdecl xd12_load(void) { return xd12_load_named("d3d12.dll"); }

const char* __cdecl xd12_error(void) { return s_error; }

int __cdecl xd12_device_probe(void) {
  if (!p_create_device) return 2;
  if (s_device) return 0;
  void* dev = 0;
  /* NULL adapter = the default adapter; 11_0 is the D3D12 minimum level. */
  int32_t hr = p_create_device(0, 0xB000, &IID_XD12_DEVICE, &dev);
  if (hr != 0 || !dev) {
    set_err("D3D12CreateDevice failed (no D3D12-capable adapter or runtime)");
    return 1;
  }

  void** vtbl = *(void***)dev;
  PFN_GetNodeCount get_nodes = (PFN_GetNodeCount)vtbl[7];
  s_node_count = (int)get_nodes(dev);

  /* Out-param interface roundtrip: ID3D12Device::CreateCommandAllocator. */
  PFN_CreateCommandAllocator create_alloc = (PFN_CreateCommandAllocator)vtbl[9];
  void* alloc = 0;
  int32_t hr2 = create_alloc(dev, 0 /* D3D12_COMMAND_LIST_TYPE_DIRECT */,
                             &IID_XD12_COMMAND_ALLOCATOR, &alloc);
  s_allocator_ok = (hr2 == 0 && alloc != 0) ? 1 : 0;
  if (alloc) release_object(alloc);

  s_device = dev;
  return 0;
}

int __cdecl xd12_device_node_count(void) { return s_node_count; }
int __cdecl xd12_allocator_ok(void) { return s_allocator_ok; }

void __cdecl xd12_unload(void) {
  if (s_device) { release_object(s_device); s_device = 0; }
  if (m_d3d12) { FreeLibrary(m_d3d12); m_d3d12 = 0; }
  clear_state();
}
