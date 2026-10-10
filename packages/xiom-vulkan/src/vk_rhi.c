/* xiom.vulkan RHI bring-up bridge -- MIT OR Apache-2.0, XIOM Authors.
 *
 * Engine surface (build order #1): instance -> physical device -> queue
 * family -> logical device -> command pool/buffer -> real submit + wait.
 * Deliberately includes NO Vulkan headers (the xiom link line has no -I
 * passthrough): every struct we WRITE is declared locally with exact ABI
 * layouts, and every struct the loader writes goes into oversized opaque
 * buffers or locally-declared structs.  Everything crosses the XIOM
 * boundary as scalars/strings (no out-param slots; findings B-11/B-12).
 *
 * Contract used by vulkan.xi (extern "C"):
 *   int  xr_load(const char* soname)     0=ok, 1=absent, 2=abi
 *   int  xr_instance(void)               0=ok, 1=failed (surface exts enabled when present)
 *   int  xr_pick_device(void)            0=ok, 1=no device
 *   int  xr_device_count(void)
 *   const char* xr_device_name(void)
 *   int  xr_device_type(void)
 *   unsigned xr_device_api(void)
 *   int  xr_surface_extensions(void)     1 when VK_KHR_surface + win32_surface enabled
 *   int  xr_queue_family(void)           graphics family index, -1 when none
 *   int  xr_create_device(void)          0=ok
 *   int  xr_submit_probe(void)           pool+cmd begin/end/submit/wait; 0=ok
 *   const char* xr_error(void)
 *   void xr_destroy(void)                device+instance teardown
 *   void xr_unload(void)
 */

#include <windows.h>
#include <stdint.h>
#include <string.h>

/* -- minimal Vulkan ABI ---------------------------------------------------- */

#define XR_ST_APPLICATION_INFO 0
#define XR_ST_INSTANCE_CREATE_INFO 1
#define XR_ST_DEVICE_QUEUE_CREATE_INFO 2
#define XR_ST_DEVICE_CREATE_INFO 3
#define XR_ST_SUBMIT_INFO 4
#define XR_ST_COMMAND_POOL_CREATE_INFO 39
#define XR_ST_COMMAND_BUFFER_ALLOCATE_INFO 40
#define XR_ST_COMMAND_BUFFER_BEGIN_INFO 42

#define XR_MAKE_API_VERSION(variant, major, minor, patch) \
  ((((uint32_t)(variant)) << 29) | (((uint32_t)(major)) << 22) | (((uint32_t)(minor)) << 12) | ((uint32_t)(patch)))

#define XR_QUEUE_GRAPHICS_BIT 0x00000001u
#define XR_COMMAND_POOL_CREATE_RESET_BIT 0x00000002u
#define XR_COMMAND_BUFFER_LEVEL_PRIMARY 0
#define XR_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT 0x00000001u

#define XR_ERR_INCOMPLETE 5
#define XR_OK 0

typedef struct XrApplicationInfo {
  uint32_t sType;
  const void* pNext;
  const char* pApplicationName;
  uint32_t applicationVersion;
  const char* pEngineName;
  uint32_t engineVersion;
  uint32_t apiVersion;
} XrApplicationInfo;

typedef struct XrInstanceCreateInfo {
  uint32_t sType;
  const void* pNext;
  uint32_t flags;
  const void* pApplicationInfo;
  uint32_t enabledLayerCount;
  const char* const* ppEnabledLayerNames;
  uint32_t enabledExtensionCount;
  const char* const* ppEnabledExtensionNames;
} XrInstanceCreateInfo;

typedef struct XrDeviceQueueCreateInfo {
  uint32_t sType;
  const void* pNext;
  uint32_t flags;
  uint32_t queueFamilyIndex;
  uint32_t queueCount;
  const float* pQueuePriorities;
} XrDeviceQueueCreateInfo;

typedef struct XrDeviceCreateInfo {
  uint32_t sType;
  const void* pNext;
  uint32_t flags;
  uint32_t queueCreateInfoCount;
  const XrDeviceQueueCreateInfo* pQueueCreateInfos;
  uint32_t enabledLayerCount;
  const char* const* ppEnabledLayerNames;
  uint32_t enabledExtensionCount;
  const char* const* ppEnabledExtensionNames;
  const void* pEnabledFeatures;
} XrDeviceCreateInfo;

typedef struct XrSubmitInfo {
  uint32_t sType;
  const void* pNext;
  uint32_t waitSemaphoreCount;
  const void* pWaitSemaphores;
  const void* pWaitDstStageMask;
  uint32_t commandBufferCount;
  const void* pCommandBuffers;
  uint32_t signalSemaphoreCount;
  const void* pSignalSemaphores;
} XrSubmitInfo;

typedef struct XrCommandPoolCreateInfo {
  uint32_t sType;
  const void* pNext;
  uint32_t flags;
  uint32_t queueFamilyIndex;
} XrCommandPoolCreateInfo;

typedef struct XrCommandBufferAllocateInfo {
  uint32_t sType;
  const void* pNext;
  void* commandPool;
  uint32_t level;
  uint32_t commandBufferCount;
} XrCommandBufferAllocateInfo;

typedef struct XrCommandBufferBeginInfo {
  uint32_t sType;
  const void* pNext;
  uint32_t flags;
  const void* pInheritanceInfo;
} XrCommandBufferBeginInfo;

typedef struct XrExtensionProperties {
  char extensionName[256];
  uint32_t specVersion;
} XrExtensionProperties;

/* VkPhysicalDeviceProperties offsets (Vulkan 1.0 layout). */
#define XR_PDP_API_VERSION_OFF 0
#define XR_PDP_DEVICE_TYPE_OFF 16
#define XR_PDP_DEVICE_NAME_OFF 20
#define XR_PDP_DEVICE_NAME_CAP 256

/* VkQueueFamilyProperties: flags(0) queueCount(4) timestampValidBits(8). */
#define XR_QFP_FLAGS_OFF 0
#define XR_QFP_COUNT_OFF 4
#define XR_QFP_SIZE 24

typedef void* (WINAPI* PFN_vkGetInstanceProcAddr)(void*, const char*);
typedef void* (WINAPI* PFN_vkGetDeviceProcAddr)(void*, const char*);
typedef int (WINAPI* PFN_EnumerateInstanceExtensionProperties)(const char*, uint32_t*, XrExtensionProperties*);

static HMODULE m_lib = 0;
static PFN_vkGetInstanceProcAddr p_gipa = 0;
static PFN_vkGetDeviceProcAddr p_gdpa = 0;
static PFN_EnumerateInstanceExtensionProperties p_enum_ext = 0;

static void* s_instance = 0;
static void* s_phys = 0;
static void* s_device = 0;
static void* s_queue = 0;
static void* s_pool = 0;
static void* s_cmd = 0;
static int s_devices = 0;
static int s_surface_exts = 0;
static int s_family = -1;
static int s_device_type = -1;
static unsigned s_device_api = 0;
static char s_device_name[XR_PDP_DEVICE_NAME_CAP];
static char s_error[512];

static void set_err(const char* msg) {
  if (!msg) msg = "(no message)";
  strncpy(s_error, msg, sizeof(s_error) - 1);
  s_error[sizeof(s_error) - 1] = 0;
}

static void* gipa(void* instance, const char* name) {
  if (!p_gipa) return 0;
  return p_gipa(instance, name);
}

/* Device-level entry points must be resolved with vkGetDeviceProcAddr; the
 * 1.4.x loaders reject a VkDevice passed to vkGetInstanceProcAddr (VUID
 * vkGetInstanceProcAddr-instance-parameter). */
static void* gdpa_lookup(const char* name) {
  if (!p_gdpa || !s_device) return 0;
  return p_gdpa(s_device, name);
}

static int ext_present(const char* name) {
  uint32_t count = 0;
  if (!p_enum_ext) return 0;
  if (p_enum_ext(0, &count, 0) != XR_OK || count == 0 || count > 4096) return 0;
  XrExtensionProperties* props = (XrExtensionProperties*)malloc(sizeof(XrExtensionProperties) * count);
  if (!props) return 0;
  uint32_t got = count;
  int found = 0;
  if (p_enum_ext(0, &got, props) == XR_OK) {
    for (uint32_t i = 0; i < got; i++) {
      if (strcmp(props[i].extensionName, name) == 0) { found = 1; break; }
    }
  }
  free(props);
  return found;
}

int __cdecl xr_load(const char* soname) {
  memset(s_device_name, 0, sizeof(s_device_name));
  s_device_type = -1; s_device_api = 0; s_devices = 0; s_family = -1; s_surface_exts = 0;
  if (!soname || !soname[0]) { set_err("empty soname"); return 1; }
  m_lib = LoadLibraryA(soname);
  if (!m_lib) { set_err("LoadLibrary failed for the requested soname"); return 1; }
  p_gipa = (PFN_vkGetInstanceProcAddr)GetProcAddress(m_lib, "vkGetInstanceProcAddr");
  if (!p_gipa) { set_err("missing export: vkGetInstanceProcAddr"); FreeLibrary(m_lib); m_lib = 0; return 2; }
  p_enum_ext = (PFN_EnumerateInstanceExtensionProperties)gipa(0, "vkEnumerateInstanceExtensionProperties");
  if (!p_enum_ext) { set_err("missing: vkEnumerateInstanceExtensionProperties"); FreeLibrary(m_lib); m_lib = 0; return 2; }
  return 0;
}

int __cdecl xr_instance(void) {
  typedef int (WINAPI* PFN_CreateInstance)(const XrInstanceCreateInfo*, const void*, void**);
  PFN_CreateInstance create = (PFN_CreateInstance)gipa(0, "vkCreateInstance");
  if (!create) { set_err("missing: vkCreateInstance"); return 1; }

  const char* want[2];
  uint32_t n = 0;
  int have_surface = ext_present("VK_KHR_surface");
  int have_win32 = ext_present("VK_KHR_win32_surface");
  if (have_surface && have_win32) {
    want[n++] = "VK_KHR_surface";
    want[n++] = "VK_KHR_win32_surface";
  }
  s_surface_exts = (n == 2) ? 1 : 0;

  XrApplicationInfo app;
  memset(&app, 0, sizeof(app));
  app.sType = XR_ST_APPLICATION_INFO;
  app.pApplicationName = "xiom-vulkan-rhi";
  app.applicationVersion = 1;
  app.pEngineName = "xiom";
  app.engineVersion = 1;
  app.apiVersion = XR_MAKE_API_VERSION(0, 1, 0, 0);

  XrInstanceCreateInfo ci;
  memset(&ci, 0, sizeof(ci));
  ci.sType = XR_ST_INSTANCE_CREATE_INFO;
  ci.pApplicationInfo = &app;
  ci.enabledExtensionCount = n;
  ci.ppEnabledExtensionNames = want;

  void* instance = 0;
  int rc = create(&ci, 0, &instance);
  if (rc != XR_OK || !instance) {
    set_err("vkCreateInstance failed (no compatible driver?)");
    return 1;
  }
  s_instance = instance;
  return 0;
}

int __cdecl xr_pick_device(void) {
  typedef int (WINAPI* PFN_EnumPhys)(void*, uint32_t*, void**);
  typedef void (WINAPI* PFN_GetProps)(void*, void*);
  PFN_EnumPhys enum_dev = (PFN_EnumPhys)gipa(s_instance, "vkEnumeratePhysicalDevices");
  PFN_GetProps get_props = (PFN_GetProps)gipa(s_instance, "vkGetPhysicalDeviceProperties");
  if (!enum_dev || !get_props) { set_err("missing device enumeration entry points"); return 1; }

  uint32_t count = 0;
  int rc = enum_dev(s_instance, &count, 0);
  if (rc != XR_OK && rc != XR_ERR_INCOMPLETE) { set_err("vkEnumeratePhysicalDevices(count) failed"); return 1; }
  s_devices = (int)count;
  if (count == 0) { set_err("no Vulkan physical devices"); return 1; }
  if (count > 16) count = 16;
  void* devices[16];
  memset(devices, 0, sizeof(devices));
  uint32_t got = count;
  rc = enum_dev(s_instance, &got, devices);
  if ((rc != XR_OK && rc != XR_ERR_INCOMPLETE) || got == 0 || !devices[0]) {
    set_err("vkEnumeratePhysicalDevices(list) failed");
    return 1;
  }

  /* Prefer the first discrete GPU, else the first device. */
  int chosen = 0;
  for (uint32_t i = 0; i < got; i++) {
    if (!devices[i]) continue;
    unsigned char buf[2048];
    memset(buf, 0, sizeof(buf));
    get_props(devices[i], buf);
    int dtype = 0;
    memcpy(&dtype, buf + XR_PDP_DEVICE_TYPE_OFF, 4);
    if (dtype == 2 /* DISCRETE_GPU */) { chosen = (int)i; break; }
  }
  s_phys = devices[chosen];

  unsigned char buf[2048];
  memset(buf, 0, sizeof(buf));
  get_props(s_phys, buf);
  memcpy(&s_device_api, buf + XR_PDP_API_VERSION_OFF, 4);
  memcpy(&s_device_type, buf + XR_PDP_DEVICE_TYPE_OFF, 4);
  strncpy(s_device_name, (const char*)(buf + XR_PDP_DEVICE_NAME_OFF), XR_PDP_DEVICE_NAME_CAP - 1);
  s_device_name[XR_PDP_DEVICE_NAME_CAP - 1] = 0;

  /* Graphics queue family (first one advertising VK_QUEUE_GRAPHICS_BIT). */
  typedef void (WINAPI* PFN_GetQueueFamilies)(void*, uint32_t*, void*);
  PFN_GetQueueFamilies get_fams = (PFN_GetQueueFamilies)gipa(s_instance, "vkGetPhysicalDeviceQueueFamilyProperties");
  if (!get_fams) { set_err("missing: vkGetPhysicalDeviceQueueFamilyProperties"); return 1; }
  uint32_t fam_count = 0;
  get_fams(s_phys, &fam_count, 0);
  if (fam_count == 0 || fam_count > 64) { set_err("no queue families"); return 1; }
  unsigned char fams[64 * XR_QFP_SIZE];
  memset(fams, 0, sizeof(fams));
  get_fams(s_phys, &fam_count, fams);
  s_family = -1;
  for (uint32_t i = 0; i < fam_count; i++) {
    uint32_t flags = 0;
    memcpy(&flags, fams + i * XR_QFP_SIZE + XR_QFP_FLAGS_OFF, 4);
    if (flags & XR_QUEUE_GRAPHICS_BIT) { s_family = (int)i; break; }
  }
  if (s_family < 0) { set_err("no graphics queue family"); return 1; }
  return 0;
}

int __cdecl xr_create_device(void) {
  if (!s_phys || s_family < 0) { set_err("device not picked"); return 1; }
  typedef int (WINAPI* PFN_CreateDevice)(void*, const XrDeviceCreateInfo*, const void*, void**);
  typedef void (WINAPI* PFN_GetDeviceQueue)(void*, uint32_t, uint32_t, void**);
  PFN_CreateDevice create = (PFN_CreateDevice)gipa(s_instance, "vkCreateDevice");
  if (!create) { set_err("missing device entry points"); return 1; }

  float priority = 1.0f;
  XrDeviceQueueCreateInfo qci;
  memset(&qci, 0, sizeof(qci));
  qci.sType = XR_ST_DEVICE_QUEUE_CREATE_INFO;
  qci.queueFamilyIndex = (uint32_t)s_family;
  qci.queueCount = 1;
  qci.pQueuePriorities = &priority;

  XrDeviceCreateInfo dci;
  memset(&dci, 0, sizeof(dci));
  dci.sType = XR_ST_DEVICE_CREATE_INFO;
  dci.queueCreateInfoCount = 1;
  dci.pQueueCreateInfos = &qci;

  void* device = 0;
  int rc = create(s_phys, &dci, 0, &device);
  if (rc != XR_OK || !device) { set_err("vkCreateDevice failed"); return 1; }
  s_device = device;

  p_gdpa = (PFN_vkGetDeviceProcAddr)gipa(s_instance, "vkGetDeviceProcAddr");
  void* queue = 0;
  if (p_gdpa) {
    PFN_GetDeviceQueue get_queue_d = (PFN_GetDeviceQueue)p_gdpa(s_device, "vkGetDeviceQueue");
    if (get_queue_d) get_queue_d(s_device, (uint32_t)s_family, 0, &queue);
  }
  if (!queue) { set_err("vkGetDeviceQueue returned null"); return 1; }
  s_queue = queue;
  return 0;
}

int __cdecl xr_submit_probe(void) {
  if (!s_device || !s_queue) { set_err("device not created"); return 1; }
  typedef int (WINAPI* PFN_CreatePool)(void*, const XrCommandPoolCreateInfo*, const void*, void**);
  typedef int (WINAPI* PFN_AllocCmd)(void*, const XrCommandBufferAllocateInfo*, void**);
  typedef int (WINAPI* PFN_Begin)(void*, const XrCommandBufferBeginInfo*);
  typedef int (WINAPI* PFN_End)(void*);
  typedef int (WINAPI* PFN_Submit)(void*, uint32_t, const XrSubmitInfo*, void*);
  typedef int (WINAPI* PFN_WaitIdle)(void*);
  PFN_CreatePool create_pool = (PFN_CreatePool)gdpa_lookup("vkCreateCommandPool");
  PFN_AllocCmd alloc_cmd = (PFN_AllocCmd)gdpa_lookup("vkAllocateCommandBuffers");
  PFN_Begin begin = (PFN_Begin)gdpa_lookup("vkBeginCommandBuffer");
  PFN_End end = (PFN_End)gdpa_lookup("vkEndCommandBuffer");
  PFN_Submit submit = (PFN_Submit)gdpa_lookup("vkQueueSubmit");
  PFN_WaitIdle wait_idle = (PFN_WaitIdle)gdpa_lookup("vkQueueWaitIdle");
  if (!create_pool || !alloc_cmd || !begin || !end || !submit || !wait_idle) {
    set_err("missing command entry points");
    return 1;
  }

  XrCommandPoolCreateInfo pci;
  memset(&pci, 0, sizeof(pci));
  pci.sType = XR_ST_COMMAND_POOL_CREATE_INFO;
  pci.flags = XR_COMMAND_POOL_CREATE_RESET_BIT;
  pci.queueFamilyIndex = (uint32_t)s_family;
  void* pool = 0;
  int rc = create_pool(s_device, &pci, 0, &pool);
  if (rc != XR_OK || !pool) { set_err("vkCreateCommandPool failed"); return 1; }

  XrCommandBufferAllocateInfo ai;
  memset(&ai, 0, sizeof(ai));
  ai.sType = XR_ST_COMMAND_BUFFER_ALLOCATE_INFO;
  ai.commandPool = pool;
  ai.level = XR_COMMAND_BUFFER_LEVEL_PRIMARY;
  ai.commandBufferCount = 1;
  void* cmd = 0;
  rc = alloc_cmd(s_device, &ai, &cmd);
  if (rc != XR_OK || !cmd) { set_err("vkAllocateCommandBuffers failed"); return 1; }

  XrCommandBufferBeginInfo bi;
  memset(&bi, 0, sizeof(bi));
  bi.sType = XR_ST_COMMAND_BUFFER_BEGIN_INFO;
  bi.flags = XR_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
  rc = begin(cmd, &bi);
  if (rc != XR_OK) { set_err("vkBeginCommandBuffer failed"); return 1; }
  rc = end(cmd);
  if (rc != XR_OK) { set_err("vkEndCommandBuffer failed"); return 1; }

  XrSubmitInfo si;
  memset(&si, 0, sizeof(si));
  si.sType = XR_ST_SUBMIT_INFO;
  si.commandBufferCount = 1;
  si.pCommandBuffers = &cmd;
  rc = submit(s_queue, 1, &si, 0);
  if (rc != XR_OK) { set_err("vkQueueSubmit failed"); return 1; }
  rc = wait_idle(s_queue);
  if (rc != XR_OK) { set_err("vkQueueWaitIdle failed"); return 1; }

  s_pool = pool;
  s_cmd = cmd;
  return 0;
}

int __cdecl xr_device_count(void) { return s_devices; }
const char* __cdecl xr_device_name(void) { return s_device_name; }
int __cdecl xr_device_type(void) { return s_device_type; }
unsigned __cdecl xr_device_api(void) { return s_device_api; }
int __cdecl xr_surface_extensions(void) { return s_surface_exts; }
int __cdecl xr_queue_family(void) { return s_family; }
const char* __cdecl xr_error(void) { return s_error; }

void __cdecl xr_destroy(void) {
  if (s_device) {
    typedef void (WINAPI* PFN_DestroyPool)(void*, void*, const void*);
    typedef void (WINAPI* PFN_DestroyDevice)(void*, const void*);
    if (s_pool) {
      PFN_DestroyPool destroy_pool = (PFN_DestroyPool)gdpa_lookup("vkDestroyCommandPool");
      if (destroy_pool) destroy_pool(s_device, s_pool, 0);
      s_pool = 0; s_cmd = 0;
    }
    PFN_DestroyDevice destroy_device = (PFN_DestroyDevice)gdpa_lookup("vkDestroyDevice");
    if (destroy_device) destroy_device(s_device, 0);
    s_device = 0; s_queue = 0; p_gdpa = 0;
  }
  if (s_instance) {
    typedef void (WINAPI* PFN_DestroyInstance)(void*, const void*);
    PFN_DestroyInstance destroy_instance = (PFN_DestroyInstance)gipa(s_instance, "vkDestroyInstance");
    if (destroy_instance) destroy_instance(s_instance, 0);
    s_instance = 0; s_phys = 0;
  }
}

void __cdecl xr_unload(void) {
  if (m_lib) FreeLibrary(m_lib);
  m_lib = 0; p_gipa = 0; p_enum_ext = 0;
}
