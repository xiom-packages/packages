/* xiom.vulkan probe bridge -- MIT OR Apache-2.0, XIOM Authors.
 *
 * Capability probe for the Vulkan loader.  Deliberately includes NO Vulkan
 * headers: the minimal structs used for instance creation are declared here
 * (we are the writer), and everything the loader writes back goes into
 * oversized opaque buffers, so the bridge compiles on machines without the
 * Vulkan SDK.  Libraries are resolved at runtime (LoadLibraryA +
 * vkGetInstanceProcAddr), so there are no import dependencies beyond
 * kernel32 and no --link flags.
 *
 * Contract used by vulkan.xi (extern "C"):
 *   int  xvk_load_named(const char* soname)  0=ok, 1=absent, 2=abi
 *   const char* xvk_error(void)
 *   unsigned xvk_api_version(void)           packed VK_MAKE_API_VERSION
 *   int  xvk_extension_count(void)
 *   const char* xvk_extension_head(void)     first up to 4 names, comma-joined
 *   int  xvk_has_extension(const char* name) 1=present, 0=absent, -1=failure
 *   int  xvk_layer_count(void)
 *   int  xvk_instance_probe(void)            0=ok, 1=no instance/device, 2=internal
 *   int  xvk_device_count(void)
 *   const char* xvk_device_name(void)
 *   int  xvk_device_type(void)
 *   unsigned xvk_device_api_version(void)
 *   void xvk_unload(void)
 */

#include <windows.h>
#include <stdint.h>
#include <string.h>

/* -- minimal Vulkan ABI (we only construct instance-create structs) ------- */

#define XVK_STRUCTURE_TYPE_APPLICATION_INFO 0
#define XVK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO 1
#define XVK_MAKE_API_VERSION(variant, major, minor, patch) \
  ((((uint32_t)(variant)) << 29) | (((uint32_t)(major)) << 22) | (((uint32_t)(minor)) << 12) | ((uint32_t)(patch)))

typedef struct XvkApplicationInfo {
  uint32_t sType;
  const void* pNext;
  const char* pApplicationName;
  uint32_t applicationVersion;
  const char* pEngineName;
  uint32_t engineVersion;
  uint32_t apiVersion;
} XvkApplicationInfo;

typedef struct XvkInstanceCreateInfo {
  uint32_t sType;
  const void* pNext;
  uint32_t flags;
  const void* pApplicationInfo;
  uint32_t enabledLayerCount;
  const char* const* ppEnabledLayerNames;
  uint32_t enabledExtensionCount;
  const char* const* ppEnabledExtensionNames;
} XvkInstanceCreateInfo;

typedef struct XvkExtensionProperties {
  char extensionName[256];
  uint32_t specVersion;
} XvkExtensionProperties;

typedef struct XvkLayerProperties {
  char layerName[256];
  uint32_t specVersion;
  uint32_t implementationVersion;
  char description[256];
} XvkLayerProperties;

typedef void* (WINAPI *PFN_vkGetInstanceProcAddr)(void* instance, const char* name);
typedef uint32_t (WINAPI *PFN_vkEnumerateInstanceVersion)(uint32_t* out);
typedef int (WINAPI *PFN_vkEnumerateInstanceExtensionProperties)(const char* layer, uint32_t* count, XvkExtensionProperties* props);
typedef int (WINAPI *PFN_vkEnumerateInstanceLayerProperties)(uint32_t* count, XvkLayerProperties* props);
typedef int (WINAPI *PFN_vkCreateInstance)(const XvkInstanceCreateInfo* ci, const void* alloc, void** out);
typedef void (WINAPI *PFN_vkDestroyInstance)(void* instance, const void* alloc);
typedef int (WINAPI *PFN_vkEnumeratePhysicalDevices)(void* instance, uint32_t* count, void** devices);
typedef void (WINAPI *PFN_vkGetPhysicalDeviceProperties)(void* device, void* props);

/* VkPhysicalDeviceProperties: apiVersion(0) driverVersion(4) vendorID(8)
 * deviceID(12) deviceType(16) deviceName(20, 256 bytes).  The loader writes
 * the full struct (~900 bytes); we receive into an oversized buffer. */
#define XVK_DEVTYPE_OFFSET 16
#define XVK_DEVNAME_OFFSET 20
#define XVK_DEVNAME_CAP 256

static HMODULE m_lib = 0;
static PFN_vkGetInstanceProcAddr p_gipa = 0;
static PFN_vkEnumerateInstanceVersion p_enum_version = 0;
static PFN_vkEnumerateInstanceExtensionProperties p_enum_ext = 0;
static PFN_vkEnumerateInstanceLayerProperties p_enum_layer = 0;
static PFN_vkCreateInstance p_create_instance = 0;

static char s_error[512];
static uint32_t s_api_version = 0;
static int s_ext_count = 0;
static char s_ext_head[512];
static int s_layer_count = 0;
static int s_device_count = 0;
static char s_device_name[XVK_DEVNAME_CAP];
static int s_device_type = -1;
static uint32_t s_device_api_version = 0;

static void set_err(const char* msg) {
  if (!msg) msg = "(no message)";
  strncpy(s_error, msg, sizeof(s_error) - 1);
  s_error[sizeof(s_error) - 1] = 0;
}

static void clear_state(void) {
  m_lib = 0; p_gipa = 0; p_enum_version = 0; p_enum_ext = 0; p_enum_layer = 0; p_create_instance = 0;
  s_api_version = 0; s_ext_count = 0; s_ext_head[0] = 0; s_layer_count = 0;
  s_device_count = 0; s_device_name[0] = 0; s_device_type = -1; s_device_api_version = 0;
}

static void* gipa(const char* name) {
  if (!p_gipa) return 0;
  return p_gipa(0, name);
}

int __cdecl xvk_load_named(const char* soname) {
  clear_state();
  if (!soname || !soname[0]) { set_err("empty soname"); return 1; }
  m_lib = LoadLibraryA(soname);
  if (!m_lib) { set_err("LoadLibrary failed for the requested soname"); return 1; }

  p_gipa = (PFN_vkGetInstanceProcAddr)GetProcAddress(m_lib, "vkGetInstanceProcAddr");
  if (!p_gipa) { set_err("missing export: vkGetInstanceProcAddr"); FreeLibrary(m_lib); clear_state(); return 2; }

  p_enum_ext = (PFN_vkEnumerateInstanceExtensionProperties)gipa("vkEnumerateInstanceExtensionProperties");
  if (!p_enum_ext) { set_err("missing: vkEnumerateInstanceExtensionProperties"); FreeLibrary(m_lib); clear_state(); return 2; }
  p_enum_layer = (PFN_vkEnumerateInstanceLayerProperties)gipa("vkEnumerateInstanceLayerProperties");
  if (!p_enum_layer) { set_err("missing: vkEnumerateInstanceLayerProperties"); FreeLibrary(m_lib); clear_state(); return 2; }
  p_create_instance = (PFN_vkCreateInstance)gipa("vkCreateInstance");
  if (!p_create_instance) { set_err("missing: vkCreateInstance"); FreeLibrary(m_lib); clear_state(); return 2; }
  p_enum_version = (PFN_vkEnumerateInstanceVersion)gipa("vkEnumerateInstanceVersion");
  /* optional: absent on Vulkan 1.0 loaders */

  if (p_enum_version) {
    uint32_t v = 0;
    if (p_enum_version(&v) == 0 && v >= XVK_MAKE_API_VERSION(0, 1, 0, 0)) {
      s_api_version = v;
    } else {
      s_api_version = XVK_MAKE_API_VERSION(0, 1, 0, 0);
    }
  } else {
    s_api_version = XVK_MAKE_API_VERSION(0, 1, 0, 0);
  }
  return 0;
}

int __cdecl xvk_load(void) {
  return xvk_load_named("vulkan-1.dll");
}

const char* __cdecl xvk_error(void) { return s_error; }

unsigned __cdecl xvk_api_version(void) { return (unsigned)s_api_version; }

int __cdecl xvk_extension_count(void) {
  if (!p_enum_ext) return -1;
  uint32_t count = 0;
  if (p_enum_ext(0, &count, 0) != 0) { set_err("vkEnumerateInstanceExtensionProperties(count) failed"); return -1; }
  s_ext_count = (int)count;
  return s_ext_count;
}

const char* __cdecl xvk_extension_head(void) {
  s_ext_head[0] = 0;
  if (!p_enum_ext) return s_ext_head;
  uint32_t count = 0;
  if (p_enum_ext(0, &count, 0) != 0 || count == 0) return s_ext_head;
  uint32_t want = (count < 8) ? count : 8;
  XvkExtensionProperties props[8];
  memset(props, 0, sizeof(props));
  uint32_t got = want;
  int rc = p_enum_ext(0, &got, props);
  /* VK_INCOMPLETE (5) is expected when the capacity is smaller than count. */
  if ((rc != 0 && rc != 5) || got == 0) return s_ext_head;
  uint32_t shown = (got < 4) ? got : 4;
  for (uint32_t i = 0; i < shown; i++) {
    if (props[i].extensionName[0] == 0) continue;
    if (s_ext_head[0]) strncat(s_ext_head, ",", sizeof(s_ext_head) - strlen(s_ext_head) - 1);
    strncat(s_ext_head, props[i].extensionName, sizeof(s_ext_head) - strlen(s_ext_head) - 1);
  }
  return s_ext_head;
}

int __cdecl xvk_has_extension(const char* name) {
  if (!name || !name[0]) return -1;
  if (!p_enum_ext) return -1;
  uint32_t count = 0;
  if (p_enum_ext(0, &count, 0) != 0) return -1;
  if (count == 0) return 0;
  if (count > 4096) count = 4096;
  XvkExtensionProperties* props = (XvkExtensionProperties*)malloc(sizeof(XvkExtensionProperties) * count);
  if (!props) { set_err("out of memory for extension scan"); return -1; }
  uint32_t got = count;
  int result = 0;
  if (p_enum_ext(0, &got, props) == 0) {
    for (uint32_t i = 0; i < got; i++) {
      if (strcmp(props[i].extensionName, name) == 0) { result = 1; break; }
    }
  } else {
    set_err("vkEnumerateInstanceExtensionProperties(list) failed");
    result = -1;
  }
  free(props);
  return result;
}

int __cdecl xvk_layer_count(void) {
  if (!p_enum_layer) return -1;
  uint32_t count = 0;
  if (p_enum_layer(&count, 0) != 0) { set_err("vkEnumerateInstanceLayerProperties failed"); return -1; }
  s_layer_count = (int)count;
  return s_layer_count;
}

int __cdecl xvk_instance_probe(void) {
  if (!p_create_instance) return 2;

  XvkApplicationInfo app;
  memset(&app, 0, sizeof(app));
  app.sType = XVK_STRUCTURE_TYPE_APPLICATION_INFO;
  app.pApplicationName = "xiom-vulkan-probe";
  app.applicationVersion = 1;
  app.pEngineName = "xiom";
  app.engineVersion = 1;
  app.apiVersion = XVK_MAKE_API_VERSION(0, 1, 0, 0);

  XvkInstanceCreateInfo ci;
  memset(&ci, 0, sizeof(ci));
  ci.sType = XVK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
  ci.pApplicationInfo = &app;

  void* instance = 0;
  int rc = p_create_instance(&ci, 0, &instance);
  if (rc != 0 || !instance) {
    set_err("vkCreateInstance failed (no compatible driver?)");
    return 1;
  }

  /* Instance-level entry points MUST be resolved with the instance handle. */
  PFN_vkEnumeratePhysicalDevices enum_dev = (PFN_vkEnumeratePhysicalDevices)p_gipa(instance, "vkEnumeratePhysicalDevices");
  PFN_vkGetPhysicalDeviceProperties get_props = (PFN_vkGetPhysicalDeviceProperties)p_gipa(instance, "vkGetPhysicalDeviceProperties");
  PFN_vkDestroyInstance destroy = (PFN_vkDestroyInstance)p_gipa(instance, "vkDestroyInstance");

  if (enum_dev) {
    uint32_t count = 0;
    int erc = enum_dev(instance, &count, 0);
    if (erc == 0 || erc == 5) {
      s_device_count = (int)count;
      if (count > 0) {
        uint32_t want = (count < 8) ? count : 8;
        void* devices[8];
        memset(devices, 0, sizeof(devices));
        uint32_t got = want;
        int erc2 = enum_dev(instance, &got, devices);
        if ((erc2 == 0 || erc2 == 5) && got > 0 && devices[0]) {
          if (get_props) {
            unsigned char buf[2048];
            memset(buf, 0, sizeof(buf));
            get_props(devices[0], buf);
            memcpy(&s_device_api_version, buf, 4);
            memcpy(&s_device_type, buf + XVK_DEVTYPE_OFFSET, 4);
            strncpy(s_device_name, (const char*)(buf + XVK_DEVNAME_OFFSET), XVK_DEVNAME_CAP - 1);
            s_device_name[XVK_DEVNAME_CAP - 1] = 0;
          }
        }
      }
    }
  }

  if (destroy) destroy(instance, 0);
  return 0;
}

int __cdecl xvk_device_count(void) { return s_device_count; }
const char* __cdecl xvk_device_name(void) { return s_device_name; }
int __cdecl xvk_device_type(void) { return s_device_type; }
unsigned __cdecl xvk_device_api_version(void) { return (unsigned)s_device_api_version; }

void __cdecl xvk_unload(void) {
  if (m_lib) FreeLibrary(m_lib);
  clear_state();
}
