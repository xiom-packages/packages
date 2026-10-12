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
 *   long long   xd12_device_ptr(void)    the live ID3D12Device* (0 = none)
 *   void*       xd12_resolve(const char* name)  lazy free-function resolver
 *   int         xd12_iid(int which, unsigned char* dst16)  core IID bytes
 *   int         xd12_blob_size(void* blob)  ID3DBlob::GetBufferSize (slot 4)
 *   void        xd12_unload(void)        releases the device if held
 */

#include <windows.h>
#include <stdint.h>
#include <string.h>

#include "d3d12_iids.inc"

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

/* -- generated-surface helpers ------------------------------------------- */

void* __cdecl xd12_resolve(const char* name) {
  if (!m_d3d12 || !name || !name[0]) return 0;
  return (void*)GetProcAddress(m_d3d12, name);
}

long long __cdecl xd12_device_ptr(void) {
  return (long long)(intptr_t)s_device;
}

int __cdecl xd12_iid(int which, unsigned char* dst16) {
  if (!dst16 || which < 0 || which >= g_xd12_iid_count) return -1;
  memcpy(dst16, g_xd12_iids[which], 16);
  return 0;
}

int __cdecl xd12_blob_size(void* blob) {
  typedef uint32_t (WINAPI *FN)(void*);
  if (!blob) return -1;
  void** vtbl = *(void***)blob;
  FN f = (FN)vtbl[4]; /* ID3D10Blob::GetBufferSize */
  return (int)f(blob);
}

long long __cdecl xd12_blob_size64(void* blob) {
  typedef uintptr_t (WINAPI *FN)(void*);
  if (!blob) return -1;
  void** vtbl = *(void***)blob;
  FN f = (FN)vtbl[4];
  return (long long)f(blob);
}

long long __cdecl xd12_blob_head64(void* blob) {
  typedef void* (WINAPI *FN)(void*);
  if (!blob) return 0;
  void** vtbl = *(void***)blob;
  FN fp = (FN)vtbl[3]; /* GetBufferPointer */
  unsigned char* p = (unsigned char*)fp(blob);
  unsigned long long v = 0;
  if (!p) return -1;
  memcpy(&v, p, 8);
  return (long long)v;
}

/* Typed root-signature serialize probe: builds a 1-root-constant
 * D3D12_ROOT_SIGNATURE_DESC locally (byte-accurate x64 layout), serializes
 * via D3D12SerializeRootSignature, reads the blob size through the
 * ID3D10Blob vtable, releases everything.  Witness: s_rs_size > 0. */
static int s_rs_size = -1;
static unsigned long long s_rs_magic = 0;

int __cdecl xd12_root_signature_probe(void) {
  typedef int32_t (WINAPI *FSer)(const void*, int32_t, void**, void**);
  typedef uintptr_t (WINAPI *FSize)(void*);
  typedef void* (WINAPI *FPtr)(void*);
  if (!m_d3d12) return 2;
  FSer ser = (FSer)GetProcAddress(m_d3d12, "D3D12SerializeRootSignature");
  if (!ser) return 2;

  struct { uint32_t NumParameters; void* pParameters; uint32_t NumStaticSamplers;
           void* pStaticSamplers; int32_t Flags; } desc;
  memset(&desc, 0, sizeof(desc));
  struct { int32_t Type; unsigned char uni[16]; int32_t Vis; unsigned char pad[4]; } param;
  memset(&param, 0, sizeof(param));
  param.Type = 0; /* D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS */
  *(uint32_t*)(param.uni + 8) = 1; /* Constants.Num32BitValues (ShaderRegister@0, RegisterSpace@4) */
  desc.NumParameters = 1;
  desc.pParameters = &param;

  void* blob = 0;
  void* err = 0;
  int32_t hr = ser(&desc, 1 /* D3D_ROOT_SIGNATURE_VERSION_1 */, &blob, &err);
  if (hr != 0 || !blob) {
    s_rs_size = -1;
    if (err) release_object(err);
    return 1;
  }
  void** vtbl = *(void***)blob;
  s_rs_size = (int)(((FSize)vtbl[4])(blob) & 0x7FFFFFFF);
  unsigned char* data = (unsigned char*)((FPtr)vtbl[3])(blob);
  if (data) memcpy(&s_rs_magic, data, 8);
  release_object(blob);
  if (err) release_object(err);
  return 0;
}

int __cdecl xd12_root_signature_size(void) { return s_rs_size; }

long long __cdecl xd12_root_signature_magic(void) { return (long long)s_rs_magic; }

void __cdecl xd12_poke_u32(unsigned char* dst, int off, unsigned int v) {
  if (!dst || off < 0) return;
  memcpy(dst + off, &v, 4);
}

void __cdecl xd12_poke_u64(unsigned char* dst, int off, unsigned long long v) {
  if (!dst || off < 0) return;
  memcpy(dst + off, &v, 8);
}

void __cdecl xd12_unload(void) {
  if (s_device) { release_object(s_device); s_device = 0; }
  if (m_d3d12) { FreeLibrary(m_d3d12); m_d3d12 = 0; }
  clear_state();
}
