/* xiom.dx12 video bridge -- MIT OR Apache-2.0, XIOM Authors.
 *
 * Small bridge for the d3d12video.h slice: pinned video IIDs + a QI
 * classification probe on the live ID3D12Device (no video interfaces are
 * created here; the generated `video_iface_*` wrappers drive the objects).
 *
 * Contract (extern "C"):
 *   int xd12_video_iid(int which, unsigned char* dst16)
 *   int xd12_video_probe(void)   0=ok (QI ok), 1=no device, 2=QI failed
 *
 * The IID byte images come from the generated `video_iids.inc` (pinned
 * d3d12video.h @ 461ef513).  REFIID params accept a pointer to those bytes.
 */

#include <windows.h>
#include <stdint.h>
#include <string.h>

#include "video_iids.inc"

/* dx12_probe.c exports (same package). */
int __cdecl xd12_load(void);
int __cdecl xd12_device_probe(void);
long long __cdecl xd12_device_ptr(void);

static char s_error[256];

int __cdecl xd12_video_iid(int which, unsigned char* dst16) {
  if (!dst16 || which < 0 || which >= g_xd12_video_iid_count) return -1;
  memcpy(dst16, g_xd12_video_iids[which], 16);
  return 0;
}

/* QI the live device for ID3D12VideoDevice (index 0 in the table). */
int __cdecl xd12_video_probe(void) {
  if (xd12_load() != 0) return 1;
  if (xd12_device_probe() != 0) return 1;
  void* dev = (void*)(intptr_t)xd12_device_ptr();
  if (!dev) return 1;
  void** vtbl = *(void***)dev;
  void* vdev = 0;
  typedef int32_t(WINAPI * PFN_QI)(void*, const void*, void**);
  int32_t hr = ((PFN_QI)vtbl[0])(dev, g_xd12_video_iids[0], &vdev);
  if (hr != 0 || !vdev) {
    strncpy(s_error, "QueryInterface(ID3D12VideoDevice) failed", sizeof(s_error) - 1);
    s_error[sizeof(s_error) - 1] = 0;
    return 2;
  }
  ((uint32_t(WINAPI*)(void*))(*(void***)vdev)[2])(vdev);
  return 0;
}

const char* __cdecl xd12_video_error(void) { return s_error; }

static int s_chain_hr = -1;
static void* s_chain_alloc = 0;
static void* s_chain_list = 0;

/* Full video decode command-list chain, C owns the ABI edge:
 * device -> CreateCommandAllocator(type 4) -> CreateCommandList(type 4,
 * IID_ID3D12VideoDecodeCommandList, NULL initial state).  Returns the
 * created list pointer (0 on failure); the CreateCommandList HRESULT and
 * the allocator pointer are available via the getters.  The list pointer is
 * delivered as a RETURN VALUE (reliable) so the XIOM side can drive the
 * generated video wrappers on it; consuming the allocator out-pointer on
 * the XIOM side is not reliable (B-24). */
long long __cdecl xd12_video_cmdlist_create(void) {
  s_chain_hr = -1;
  s_chain_alloc = 0;
  s_chain_list = 0;
  if (xd12_load() != 0) return 0;
  if (xd12_device_probe() != 0) return 0;
  void* dev = (void*)(intptr_t)xd12_device_ptr();
  if (!dev) return 0;
  static const unsigned char IID_ALLOC[16] = {
    0xE4, 0xDE, 0x02, 0x61, 0x59, 0xAF, 0x09, 0x4B,
    0xB9, 0x99, 0xB4, 0x4D, 0x73, 0xF0, 0x9B, 0x24
  };
  typedef int32_t(WINAPI * F_Alloc)(void*, int32_t, const void*, void**);
  int32_t ahr = ((F_Alloc)(*(void***)dev)[9])(dev, 4, IID_ALLOC, &s_chain_alloc);
  if (ahr != 0 || !s_chain_alloc) return 0;
  typedef int32_t(WINAPI * F_List)(void*, uint32_t, int32_t, void*, void*, const void*, void**);
  s_chain_hr = ((F_List)(*(void***)dev)[12])(dev, 0, 4, s_chain_alloc, 0,
                                             g_xd12_video_iids[5], &s_chain_list);
  if (s_chain_hr != 0) return 0;
  return (long long)(intptr_t)s_chain_list;
}

int __cdecl xd12_video_cmdlist_hr(void) { return s_chain_hr; }
long long __cdecl xd12_video_cmdlist_alloc(void) { return (long long)(intptr_t)s_chain_alloc; }

/* Release the chain's allocator (the list is released by the caller through
 * the generated wrappers). */
void __cdecl xd12_video_cmdlist_cleanup(void) {
  if (s_chain_alloc) {
    ((uint32_t(WINAPI*)(void*))(*(void***)s_chain_alloc)[2])(s_chain_alloc);
    s_chain_alloc = 0;
  }
  s_chain_list = 0;
}

