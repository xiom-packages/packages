#define _CRT_SECURE_NO_WARNINGS

#include <stdint.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include <vulkan/vulkan.h>
#define GLFW_INCLUDE_VULKAN
#include <GLFW/glfw3.h>

#include "xiom_vk_bridge.h"

/* ------------------------------------------------------------------ */
/*  Generated SPIR-V header — produced by build.ps1 / build.sh       */
/* ------------------------------------------------------------------ */
/*  Exported symbols:
 *    extern const unsigned int xvk_triangle_vert_spv[];
 *    extern const unsigned int xvk_triangle_vert_spv_len;   // bytes
 *    extern const unsigned int xvk_triangle_frag_spv[];
 *    extern const unsigned int xvk_triangle_frag_spv_len;
 *    extern const unsigned int xvk_cube_vert_spv[];
 *    extern const unsigned int xvk_cube_vert_spv_len;
 *    extern const unsigned int xvk_cube_frag_spv[];
 *    extern const unsigned int xvk_cube_frag_spv_len;
 *    extern const unsigned int xvk_quad_vert_spv[];
 *    extern const unsigned int xvk_quad_vert_spv_len;
 *    extern const unsigned int xvk_quad_frag_spv[];
 *    extern const unsigned int xvk_quad_frag_spv_len;
 *    extern const unsigned int xvk_particle_vert_spv[];
 *    extern const unsigned int xvk_particle_vert_spv_len;
 *    extern const unsigned int xvk_particle_frag_spv[];
 *    extern const unsigned int xvk_particle_frag_spv_len;
 */
#include "xvk_shaders_generated.h"

/* Fallback declarations for Phase 1 shaders — defined by generated header when
 * build.ps1/build.sh runs; these externs ensure the bridge compiles without
 * the header having been regenerated.  Linker errors will occur if the symbols
 * are actually referenced without the header having been generated. */
#ifndef XVK_PHASE1_SHADERS_DECLARED
#define XVK_PHASE1_SHADERS_DECLARED
extern const unsigned int xvk_particle_render_vert_spv[];
extern const unsigned int xvk_particle_render_vert_spv_len;
extern const unsigned int xvk_particle_render_frag_spv[];
extern const unsigned int xvk_particle_render_frag_spv_len;
extern const unsigned int xvk_compute_particles_spv[];
extern const unsigned int xvk_compute_particles_spv_len;
extern const unsigned int xvk_texture_quad_vert_spv[];
extern const unsigned int xvk_texture_quad_vert_spv_len;
extern const unsigned int xvk_texture_quad_frag_spv[];
extern const unsigned int xvk_texture_quad_frag_spv_len;
extern const unsigned int xvk_uniform_cube_vert_spv[];
extern const unsigned int xvk_uniform_cube_vert_spv_len;
extern const unsigned int xvk_uniform_cube_frag_spv[];
extern const unsigned int xvk_uniform_cube_frag_spv_len;
#endif

/* ------------------------------------------------------------------ */
/*  Constants                                                         */
/* ------------------------------------------------------------------ */
#define XVK_MAGIC               0x58564B01u
#define XVK_MAX_FRAMES          2
#define XVK_BUFFER_MAGIC        0x42554601u
#define XVK_IMAGE_MAGIC         0x494D4701u
#define XVK_IMAGEVIEW_MAGIC     0x56494557u
#define XVK_SAMPLER_MAGIC       0x534D5001u
#define XVK_SHADER_MAGIC        0x53484401u
#define XVK_PIPELINE_MAGIC      0x50495001u
#define XVK_PLAYOUT_MAGIC       0x504C4159u
#define XVK_DESC_LAYOUT_MAGIC   0x44534301u
#define XVK_DESC_POOL_MAGIC     0x44535001u
#define XVK_DESC_SET_MAGIC      0x44535301u
#define XVK_RENDERPASS_MAGIC    0x52504153u
#define XVK_FRAMEBUFFER_MAGIC   0x46524255u
#ifndef M_PI
#  define M_PI 3.14159265358979323846
#endif

/* ------------------------------------------------------------------ */
/*  Error state (static — last failure across all calls)              */
/* ------------------------------------------------------------------ */
static char g_xvk_error[512] = "";

static void xvk_set_error(const char* msg)
{
    strncpy(g_xvk_error, msg, sizeof(g_xvk_error) - 1);
    g_xvk_error[sizeof(g_xvk_error) - 1] = '\0';
}

static void xvk_set_error_fmt(const char* fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    vsnprintf(g_xvk_error, sizeof(g_xvk_error), fmt, args);
    va_end(args);
    g_xvk_error[sizeof(g_xvk_error) - 1] = '\0';
}

/* ------------------------------------------------------------------ */
/*  Particle CPU state (fountain simulation)                           */
/* ------------------------------------------------------------------ */
typedef struct {
    float x, y;       /* NDC position */
    float vx, vy;     /* NDC velocity */
    float r, g, b;    /* colour */
    float life;       /* remaining time in seconds */
} Particle;

/* ------------------------------------------------------------------ */
/*  New resource handle types (Phase 1)                                */
/* ------------------------------------------------------------------ */
typedef struct {
    uint32_t magic;
    VkBuffer buffer;
    VkDeviceMemory memory;
    VkDeviceSize size;
    int mapped;
    void* mapped_ptr;
} XvkBuffer;

typedef struct {
    uint32_t magic;
    VkImage image;
    VkDeviceMemory memory;
    VkFormat format;
    VkExtent2D extent;
    uint32_t mip_levels;
} XvkImage;

typedef struct {
    uint32_t magic;
    VkImageView view;
} XvkImageView;

typedef struct {
    uint32_t magic;
    VkSampler sampler;
} XvkSampler;

typedef struct {
    uint32_t magic;
    VkShaderModule module;
} XvkShaderModule;

typedef struct {
    uint32_t magic;
    VkPipelineLayout layout;
} XvkPipelineLayout;

typedef struct {
    uint32_t magic;
    VkPipeline pipeline;
    VkPipelineBindPoint bind_point;
} XvkPipeline;

typedef struct {
    uint32_t magic;
    VkDescriptorSetLayout layout;
} XvkDescSetLayout;

typedef struct {
    uint32_t magic;
    VkDescriptorPool pool;
} XvkDescPool;

typedef struct {
    uint32_t magic;
    VkDescriptorSet set;
} XvkDescSet;

typedef struct {
    uint32_t magic;
    VkRenderPass render_pass;
} XvkRenderPass;

typedef struct {
    uint32_t magic;
    VkFramebuffer framebuffer;
} XvkFramebuffer;

/* ------------------------------------------------------------------ */
/*  App structure  (shared by windowed + offscreen paths)             */
/* ------------------------------------------------------------------ */
typedef struct XvkApp {
    uint32_t            magic;
    int                 is_offscreen;       /* 1 = offscreen-only renderer */

    /* instance / device */
    VkInstance          instance;
    VkPhysicalDevice    phys_dev;
    VkDevice            device;
    VkQueue             graphics_queue;
    VkQueue             present_queue;
    uint32_t            graphics_family;
    uint32_t            present_family;
    VkPhysicalDeviceMemoryProperties mem_props;
    int                 device_type;        /* VkPhysicalDeviceType */

    /* windowing */
    GLFWwindow*         window;
    VkSurfaceKHR        surface;

    /* swapchain */
    VkSwapchainKHR      swapchain;
    VkFormat            swapchain_fmt;
    VkExtent2D          swapchain_extent;
    VkImage*            swapchain_images;
    VkImageView*        swapchain_image_views;
    int                 swapchain_image_count;

    /* depth */
    VkImage             depth_image;
    VkDeviceMemory      depth_memory;
    VkImageView         depth_image_view;
    VkFormat            depth_format;

    /* render pass & pipelines (windowed) */
    VkRenderPass        render_pass;
    VkPipelineLayout    pipe_layout_2d;
    VkPipeline          pipeline_2d;
    VkPipelineLayout    pipe_layout_3d;
    VkPipeline          pipeline_3d;

    /* quad pipeline (windowed 2D rectangle) */
    VkPipelineLayout    pipe_layout_quad;
    VkPipeline          pipeline_quad;

    /* particle pipeline + resources */
    int32_t             particle_count;
    VkBuffer            particle_vbo;
    VkDeviceMemory      particle_mem;
    void*               particle_mapped;
    VkPipeline          particle_pipeline;
    VkPipelineLayout    particle_layout;
    Particle*           particles;          /* CPU-side state array */

    /* framebuffers (one per swapchain image) */
    VkFramebuffer*      framebuffers;

    /* command */
    VkCommandPool       cmd_pool;
    VkCommandBuffer*    cmd_buffers;        /* one per swapchain image */

    /* sync objects (per-frame) */
    VkSemaphore*        image_available;
    VkSemaphore*        render_finished;
    VkFence*            in_flight_fences;
    int                 frame_index;

    /* state */
    float               clear_r, clear_g, clear_b;
    int                 recording;          /* non-zero between begin/end_frame */
    int                 in_render_pass;     /* non-zero when inside a render pass */
    uint32_t            current_image;      /* image index for current frame */

    /* --- offscreen-only members --- */
    int                 offs_w, offs_h;
    VkImage             offs_image;
    VkDeviceMemory      offs_memory;
    VkImageView         offs_image_view;
    VkRenderPass        offs_render_pass;
    VkPipeline          offs_pipeline;
    VkFramebuffer       offs_framebuffer;
    VkBuffer            offs_readback;
    VkDeviceMemory      offs_readback_mem;
    void*               offs_mapped;        /* persistent map */
    VkCommandBuffer     offs_cmd;
    VkFence             offs_fence;
} XvkApp;

/* ------------------------------------------------------------------ */
/*  Handle helpers                                                     */
/* ------------------------------------------------------------------ */
static XvkApp* xvk_from_handle(int64_t h)
{
    if (h == 0) return NULL;
    XvkApp* a = (XvkApp*)(intptr_t)h;
    if (a->magic != XVK_MAGIC) return NULL;
    return a;
}

static int64_t xvk_to_handle(XvkApp* a)
{
    return (int64_t)(intptr_t)a;
}

/* ------------------------------------------------------------------ */
/*  Math helpers  (column-major float[16] matrices)                   */
/* ------------------------------------------------------------------ */
static void mat4_identity(float m[16])
{
    memset(m, 0, 16 * sizeof(float));
    m[0] = m[5] = m[10] = m[15] = 1.0f;
}

/* C = A * B  (column-major) */
static void mat4_mul(float c[16], const float a[16], const float b[16])
{
    for (int col = 0; col < 4; ++col) {
        for (int row = 0; row < 4; ++row) {
            float sum = 0.0f;
            for (int k = 0; k < 4; ++k) {
                sum += a[k * 4 + row] * b[col * 4 + k];
            }
            c[col * 4 + row] = sum;
        }
    }
}

/* Vulkan perspective: Y flipped, depth mapped to [0,1].             */
static void mat4_perspective(float m[16], float fov_y, float aspect,
                              float near, float far)
{
    float t = 1.0f / tanf(fov_y * 0.5f);
    memset(m, 0, 16 * sizeof(float));
    m[0]  = t / aspect;                       /* [0][0] */
    m[5]  = -t;                               /* [1][1] — Y flip */
    m[10] = far / (far - near);               /* [2][2] */
    m[11] = 1.0f;                             /* [2][3] — w division */
    m[14] = -near * far / (far - near);       /* [3][2] */
}

/* Standard gluLookAt, same convention as OpenGL.  View-space Y goes   *
 * down (the projection matrix handles the flip).                      */
static void mat4_look_at(float m[16],
                          float ex, float ey, float ez,
                          float cx, float cy, float cz,
                          float ux, float uy, float uz)
{
    float f[3] = { cx - ex, cy - ey, cz - ez };
    float flen = sqrtf(f[0]*f[0] + f[1]*f[1] + f[2]*f[2]);
    if (flen < 1e-8f) { flen = 1.0f; }
    f[0] /= flen; f[1] /= flen; f[2] /= flen;

    float r[3] = {
        f[1] * uz - f[2] * uy,
        f[2] * ux - f[0] * uz,
        f[0] * uy - f[1] * ux
    };
    float rlen = sqrtf(r[0]*r[0] + r[1]*r[1] + r[2]*r[2]);
    if (rlen < 1e-8f) { rlen = 1.0f; }
    r[0] /= rlen; r[1] /= rlen; r[2] /= rlen;

    float u[3] = {
        r[1] * f[2] - r[2] * f[1],
        r[2] * f[0] - r[0] * f[2],
        r[0] * f[1] - r[1] * f[0]
    };

    memset(m, 0, 16 * sizeof(float));
    m[0]  = r[0]; m[4]  = u[0]; m[8]  = -f[0];
    m[1]  = r[1]; m[5]  = u[1]; m[9]  = -f[1];
    m[2]  = r[2]; m[6]  = u[2]; m[10] = -f[2];
    m[12] = -(r[0]*ex + r[1]*ey + r[2]*ez);
    m[13] = -(u[0]*ex + u[1]*ey + u[2]*ez);
    m[14] =  (f[0]*ex + f[1]*ey + f[2]*ez);
    m[15] = 1.0f;
}

/* Right-multiply m by a rotation around Y:  m = m * rotateY(angle).  */
static void mat4_rotate_y(float m[16], float angle)
{
    float c = cosf(angle), s = sinf(angle);
    float rot[16];
    mat4_identity(rot);
    rot[0]  = c;   rot[2]  = -s;   /* col 0 = [c,0,-s,0]^T */
    rot[8]  = s;   rot[10] = c;    /* col 2 = [s,0, c,0]^T */
    float tmp[16];
    mat4_mul(tmp, m, rot);
    memcpy(m, tmp, sizeof(tmp));
}

/* Set m to a translation matrix T(tx,ty,tz).  */
static void mat4_translation(float m[16], float tx, float ty, float tz)
{
    memset(m, 0, 16 * sizeof(float));
    m[0]  = 1.0f;
    m[5]  = 1.0f;
    m[10] = 1.0f;
    m[15] = 1.0f;
    m[12] = tx;
    m[13] = ty;
    m[14] = tz;
}

/* Right-multiply m by a uniform scale:  m = m * diag(s,s,s,1).       */
static void mat4_scale_right(float m[16], float s)
{
    for (int j = 0; j < 3; ++j) {
        int idx = j * 4;
        m[idx]   *= s;
        m[idx+1] *= s;
        m[idx+2] *= s;
        m[idx+3] *= s;
    }
}

/* Right-multiply m by a rotation around X:  m = m * rotateX(angle).  */
static void mat4_rotate_x(float m[16], float angle)
{
    float c = cosf(angle), s = sinf(angle);
    float rot[16];
    mat4_identity(rot);
    rot[5]  = c;   rot[6]  = s;    /* col 1 = [0,c, s,0]^T */
    rot[9]  = -s;  rot[10] = c;    /* col 2 = [0,-s,c,0]^T */
    float tmp[16];
    mat4_mul(tmp, m, rot);
    memcpy(m, tmp, sizeof(tmp));
}

/* ------------------------------------------------------------------ */
/*  Queue family helpers                                               */
/* ------------------------------------------------------------------ */
static int find_queue_families(VkPhysicalDevice pd, VkSurfaceKHR surface,
                                uint32_t* gfx, uint32_t* pres)
{
    uint32_t n = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(pd, &n, NULL);
    VkQueueFamilyProperties* props = (VkQueueFamilyProperties*)
        malloc(n * sizeof(VkQueueFamilyProperties));
    if (!props) return 0;
    vkGetPhysicalDeviceQueueFamilyProperties(pd, &n, props);

    int found_gfx = 0, found_pres = 0;
    for (uint32_t i = 0; i < n; ++i) {
        if (!found_gfx && (props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT)) {
            *gfx = i;
            found_gfx = 1;
        }
        if (!found_pres && surface != VK_NULL_HANDLE) {
            VkBool32 supp = VK_FALSE;
            vkGetPhysicalDeviceSurfaceSupportKHR(pd, i, surface, &supp);
            if (supp) {
                *pres = i;
                found_pres = 1;
            }
        }
        if (found_gfx && (found_pres || surface == VK_NULL_HANDLE)) break;
    }
    free(props);
    return found_gfx;
}

/* ------------------------------------------------------------------ */
/*  Instance creation (with optional validation)                      */
/* ------------------------------------------------------------------ */
static VkInstance create_instance(const char* app_name, int* have_validation)
{
    *have_validation = 0;

    /* Check env var for validation */
    const char* env = getenv("XVK_VALIDATION");
    int want_validation = (env && env[0] == '1');

    VkApplicationInfo app_info = {0};
    app_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app_info.pApplicationName = app_name;
    app_info.applicationVersion = 1;
    app_info.pEngineName = "XIOM-Vulkan-Bridge";
    app_info.engineVersion = 1;
    app_info.apiVersion = VK_API_VERSION_1_0;

    /* Extensions from GLFW */
    uint32_t glfw_ext_count = 0;
    const char** glfw_ext = glfwGetRequiredInstanceExtensions(&glfw_ext_count);
    if (!glfw_ext) {
        xvk_set_error("glfwGetRequiredInstanceExtensions returned NULL");
        return VK_NULL_HANDLE;
    }

    VkInstanceCreateInfo ci = {0};
    ci.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    ci.pApplicationInfo = &app_info;
    ci.enabledExtensionCount = glfw_ext_count;
    ci.ppEnabledExtensionNames = glfw_ext;

    /* Validation layers — optional, fail-soft */
    const char* layer_name = "VK_LAYER_KHRONOS_validation";
    VkLayerProperties* layers = NULL;
    uint32_t layer_count = 0;
    vkEnumerateInstanceLayerProperties(&layer_count, NULL);
    int layer_avail = 0;
    if (layer_count > 0) {
        layers = (VkLayerProperties*)malloc(
            layer_count * sizeof(VkLayerProperties));
        if (layers) {
            vkEnumerateInstanceLayerProperties(&layer_count, layers);
            for (uint32_t i = 0; i < layer_count; ++i) {
                if (strcmp(layers[i].layerName, layer_name) == 0) {
                    layer_avail = 1;
                    break;
                }
            }
            free(layers);
        }
    }

    if (want_validation && layer_avail) {
        ci.enabledLayerCount = 1;
        ci.ppEnabledLayerNames = &layer_name;
        *have_validation = 1;
    }

    VkInstance inst = VK_NULL_HANDLE;
    VkResult res = vkCreateInstance(&ci, NULL, &inst);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateInstance failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    printf("XIOM-Vulkan-Bridge: instance created (validation=%d)\n",
           *have_validation);
    return inst;
}

/* ------------------------------------------------------------------ */
/*  Physical device selection                                          */
/* ------------------------------------------------------------------ */
static int pick_physical_device(VkInstance inst, VkSurfaceKHR surface,
                                 VkPhysicalDevice* out_pd, int* out_type)
{
    uint32_t n = 0;
    vkEnumeratePhysicalDevices(inst, &n, NULL);
    if (n == 0) {
        xvk_set_error("no Vulkan-capable physical devices found");
        return 0;
    }
    VkPhysicalDevice* devs = (VkPhysicalDevice*)
        malloc(n * sizeof(VkPhysicalDevice));
    vkEnumeratePhysicalDevices(inst, &n, devs);

    int chosen = -1;
    for (uint32_t i = 0; i < n; ++i) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(devs[i], &props);
        printf("  GPU %u: %s  (type %d)\n", i, props.deviceName,
               props.deviceType);

        uint32_t gfx, pres;
        if (find_queue_families(devs[i], surface, &gfx, &pres)) {
            if (surface == VK_NULL_HANDLE || surface != VK_NULL_HANDLE) {
                /* Always pick first suitable.  Preference: discrete > integrated */
                if (chosen < 0 ||
                    props.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU) {
                    chosen = (int)i;
                }
                /* Also record device type */
                if (chosen == (int)i) {
                    *out_type = (int)props.deviceType;
                }
            }
        }
    }

    if (chosen < 0) {
        free(devs);
        xvk_set_error("no suitable GPU found (need graphics queue)");
        return 0;
    }

    *out_pd = devs[chosen];
    VkPhysicalDeviceProperties props;
    vkGetPhysicalDeviceProperties(*out_pd, &props);
    printf("XIOM-Vulkan-Bridge: selected GPU = %s\n", props.deviceName);
    free(devs);
    return 1;
}

/* ------------------------------------------------------------------ */
/*  Logical device creation                                            */
/* ------------------------------------------------------------------ */
static VkDevice create_device(VkPhysicalDevice pd, uint32_t gfx_family,
                               uint32_t pres_family, VkSurfaceKHR surface)
{
    float q_priority = 1.0f;
    uint32_t families[2];
    int n_families = 0;
    families[n_families++] = gfx_family;
    if (pres_family != gfx_family && surface != VK_NULL_HANDLE)
        families[n_families++] = pres_family;

    VkDeviceQueueCreateInfo qci[2];
    for (int i = 0; i < n_families; ++i) {
        qci[i].sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci[i].pNext = NULL;
        qci[i].flags = 0;
        qci[i].queueFamilyIndex = families[i];
        qci[i].queueCount = 1;
        qci[i].pQueuePriorities = &q_priority;
    }

    /* Device extensions needed */
    const char* dev_exts[2];
    int n_dev_exts = 0;
    dev_exts[n_dev_exts++] = VK_KHR_SWAPCHAIN_EXTENSION_NAME;
    /* VK_KHR_MAINTENANCE1 is core in 1.1+ — omit for 1.0 compat */

    VkPhysicalDeviceFeatures features = {0};

    VkDeviceCreateInfo dci = {0};
    dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    dci.queueCreateInfoCount = (uint32_t)n_families;
    dci.pQueueCreateInfos = qci;
    dci.enabledExtensionCount = (uint32_t)n_dev_exts;
    dci.ppEnabledExtensionNames = dev_exts;
    dci.pEnabledFeatures = &features;

    VkDevice dev = VK_NULL_HANDLE;
    VkResult res = vkCreateDevice(pd, &dci, NULL, &dev);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateDevice failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    return dev;
}

/* ------------------------------------------------------------------ */
/*  Surface creation via GLFW                                          */
/* ------------------------------------------------------------------ */
static VkSurfaceKHR create_surface(VkInstance inst, GLFWwindow* win)
{
    VkSurfaceKHR surf = VK_NULL_HANDLE;
    VkResult res = glfwCreateWindowSurface(inst, win, NULL, &surf);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("glfwCreateWindowSurface failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    return surf;
}

/* ------------------------------------------------------------------ */
/*  Swapchain helpers                                                  */
/* ------------------------------------------------------------------ */
static VkSurfaceFormatKHR pick_swapchain_fmt(VkPhysicalDevice pd,
                                              VkSurfaceKHR surface)
{
    uint32_t n = 0;
    vkGetPhysicalDeviceSurfaceFormatsKHR(pd, surface, &n, NULL);
    VkSurfaceFormatKHR* fmts = (VkSurfaceFormatKHR*)
        malloc(n * sizeof(VkSurfaceFormatKHR));
    vkGetPhysicalDeviceSurfaceFormatsKHR(pd, surface, &n, fmts);

    VkSurfaceFormatKHR chosen = {0};
    chosen.format = VK_FORMAT_B8G8R8A8_UNORM;
    chosen.colorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;

    for (uint32_t i = 0; i < n; ++i) {
        if (fmts[i].format == VK_FORMAT_B8G8R8A8_UNORM &&
            fmts[i].colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
            chosen = fmts[i];
            break;
        }
    }
    free(fmts);
    return chosen;
}

static VkPresentModeKHR pick_present_mode(VkPhysicalDevice pd,
                                           VkSurfaceKHR surface)
{
    uint32_t n = 0;
    vkGetPhysicalDeviceSurfacePresentModesKHR(pd, surface, &n, NULL);
    VkPresentModeKHR* modes = (VkPresentModeKHR*)
        malloc(n * sizeof(VkPresentModeKHR));
    vkGetPhysicalDeviceSurfacePresentModesKHR(pd, surface, &n, modes);

    VkPresentModeKHR chosen = VK_PRESENT_MODE_FIFO_KHR; /* guaranteed */
    for (uint32_t i = 0; i < n; ++i) {
        if (modes[i] == VK_PRESENT_MODE_MAILBOX_KHR) {
            chosen = modes[i];
            break;
        }
    }
    free(modes);
    return chosen;
}

static VkExtent2D pick_extent(VkPhysicalDevice pd, VkSurfaceKHR surface,
                               GLFWwindow* win)
{
    VkSurfaceCapabilitiesKHR caps;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pd, surface, &caps);

    if (caps.currentExtent.width != UINT32_MAX)
        return caps.currentExtent;

    /* If width/height are max uint32, the window manager lets us choose. */
    int w, h;
    glfwGetFramebufferSize(win, &w, &h);
    VkExtent2D ext = {
        (uint32_t)(w < 0 ? 0 : w),
        (uint32_t)(h < 0 ? 0 : h)
    };
    ext.width  = ext.width  < caps.minImageExtent.width  ? caps.minImageExtent.width  : ext.width;
    ext.height = ext.height < caps.minImageExtent.height ? caps.minImageExtent.height : ext.height;
    ext.width  = ext.width  > caps.maxImageExtent.width  ? caps.maxImageExtent.width  : ext.width;
    ext.height = ext.height > caps.maxImageExtent.height ? caps.maxImageExtent.height : ext.height;
    return ext;
}

/* ------------------------------------------------------------------ */
/*  Depth resource creation                                            */
/* ------------------------------------------------------------------ */
static VkFormat find_depth_format(VkPhysicalDevice pd)
{
    VkFormat candidates[] = {
        VK_FORMAT_D32_SFLOAT,
        VK_FORMAT_D24_UNORM_S8_UINT,
        VK_FORMAT_D16_UNORM
    };
    for (int i = 0; i < 3; ++i) {
        VkFormatProperties p;
        vkGetPhysicalDeviceFormatProperties(pd, candidates[i], &p);
        if (p.optimalTilingFeatures & VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT)
            return candidates[i];
    }
    return VK_FORMAT_UNDEFINED;
}

static uint32_t find_memory_type(const VkPhysicalDeviceMemoryProperties* mp,
                                  uint32_t type_filter,
                                  VkMemoryPropertyFlags props)
{
    for (uint32_t i = 0; i < mp->memoryTypeCount; ++i) {
        if ((type_filter & (1u << i)) &&
            (mp->memoryTypes[i].propertyFlags & props) == props)
            return i;
    }
    return UINT32_MAX;
}

/* Create depth image + memory + view.  Returns 1 on success. */
static int create_depth_resources(XvkApp* a)
{
    VkFormat df = find_depth_format(a->phys_dev);
    if (df == VK_FORMAT_UNDEFINED) {
        xvk_set_error("no suitable depth format found");
        return 0;
    }
    a->depth_format = df;

    VkImageCreateInfo ici = {0};
    ici.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ici.imageType = VK_IMAGE_TYPE_2D;
    ici.format = df;
    ici.extent.width  = a->swapchain_extent.width;
    ici.extent.height = a->swapchain_extent.height;
    ici.extent.depth  = 1;
    ici.mipLevels = 1;
    ici.arrayLayers = 1;
    ici.samples = VK_SAMPLE_COUNT_1_BIT;
    ici.tiling = VK_IMAGE_TILING_OPTIMAL;
    ici.usage = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    VkResult res = vkCreateImage(a->device, &ici, NULL, &a->depth_image);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateImage (depth) failed: %d", (int)res);
        return 0;
    }

    VkMemoryRequirements mr;
    vkGetImageMemoryRequirements(a->device, a->depth_image, &mr);
    uint32_t mi = find_memory_type(&a->mem_props, mr.memoryTypeBits,
                                    VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (mi == UINT32_MAX) {
        xvk_set_error("no device-local memory for depth image");
        vkDestroyImage(a->device, a->depth_image, NULL);
        a->depth_image = VK_NULL_HANDLE;
        return 0;
    }

    VkMemoryAllocateInfo mai = {0};
    mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    mai.allocationSize = mr.size;
    mai.memoryTypeIndex = mi;
    res = vkAllocateMemory(a->device, &mai, NULL, &a->depth_memory);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkAllocateMemory (depth) failed: %d", (int)res);
        vkDestroyImage(a->device, a->depth_image, NULL);
        a->depth_image = VK_NULL_HANDLE;
        return 0;
    }

    vkBindImageMemory(a->device, a->depth_image, a->depth_memory, 0);

    VkImageViewCreateInfo ivci = {0};
    ivci.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    ivci.image = a->depth_image;
    ivci.viewType = VK_IMAGE_VIEW_TYPE_2D;
    ivci.format = df;
    ivci.subresourceRange.aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT;
    if (df == VK_FORMAT_D24_UNORM_S8_UINT || df == VK_FORMAT_D32_SFLOAT_S8_UINT)
        ivci.subresourceRange.aspectMask |= VK_IMAGE_ASPECT_STENCIL_BIT;
    ivci.subresourceRange.baseMipLevel = 0;
    ivci.subresourceRange.levelCount = 1;
    ivci.subresourceRange.baseArrayLayer = 0;
    ivci.subresourceRange.layerCount = 1;

    res = vkCreateImageView(a->device, &ivci, NULL, &a->depth_image_view);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateImageView (depth) failed: %d", (int)res);
        vkFreeMemory(a->device, a->depth_memory, NULL);
        a->depth_memory = VK_NULL_HANDLE;
        vkDestroyImage(a->device, a->depth_image, NULL);
        a->depth_image = VK_NULL_HANDLE;
        return 0;
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/*  Render pass (windowed)                                             */
/* ------------------------------------------------------------------ */
static VkRenderPass create_render_pass(VkDevice dev, VkFormat colour_fmt,
                                        VkFormat depth_fmt)
{
    VkAttachmentDescription att[2] = {{0}};
    /* Colour */
    att[0].format         = colour_fmt;
    att[0].samples        = VK_SAMPLE_COUNT_1_BIT;
    att[0].loadOp         = VK_ATTACHMENT_LOAD_OP_CLEAR;
    att[0].storeOp        = VK_ATTACHMENT_STORE_OP_STORE;
    att[0].stencilLoadOp  = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    att[0].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    att[0].initialLayout  = VK_IMAGE_LAYOUT_UNDEFINED;
    att[0].finalLayout    = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    /* Depth */
    att[1].format         = depth_fmt;
    att[1].samples        = VK_SAMPLE_COUNT_1_BIT;
    att[1].loadOp         = VK_ATTACHMENT_LOAD_OP_CLEAR;
    att[1].storeOp        = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    att[1].stencilLoadOp  = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    att[1].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    att[1].initialLayout  = VK_IMAGE_LAYOUT_UNDEFINED;
    att[1].finalLayout    = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

    VkAttachmentReference col_ref = {0};
    col_ref.attachment = 0;
    col_ref.layout     = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    VkAttachmentReference depth_ref = {0};
    depth_ref.attachment = 1;
    depth_ref.layout     = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

    VkSubpassDescription subpass = {0};
    subpass.pipelineBindPoint    = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments    = &col_ref;
    subpass.pDepthStencilAttachment = &depth_ref;

    VkSubpassDependency dep = {0};
    dep.srcSubpass    = VK_SUBPASS_EXTERNAL;
    dep.dstSubpass    = 0;
    dep.srcStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                        VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    dep.dstStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                        VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    dep.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT |
                        VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;

    VkRenderPassCreateInfo rpci = {0};
    rpci.sType           = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    rpci.attachmentCount = 2;
    rpci.pAttachments    = att;
    rpci.subpassCount    = 1;
    rpci.pSubpasses      = &subpass;
    rpci.dependencyCount = 1;
    rpci.pDependencies   = &dep;

    VkRenderPass rp = VK_NULL_HANDLE;
    VkResult res = vkCreateRenderPass(dev, &rpci, NULL, &rp);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateRenderPass failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    return rp;
}

/* ------------------------------------------------------------------ */
/*  Shader module helper                                               */
/* ------------------------------------------------------------------ */
static VkShaderModule create_shader_module(VkDevice dev,
                                            const unsigned int* code,
                                            unsigned int code_size_bytes)
{
    VkShaderModuleCreateInfo smci = {0};
    smci.sType    = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
    smci.codeSize = code_size_bytes;
    smci.pCode    = code;
    VkShaderModule sm = VK_NULL_HANDLE;
    VkResult res = vkCreateShaderModule(dev, &smci, NULL, &sm);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateShaderModule failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    return sm;
}

/* ------------------------------------------------------------------ */
/*  Pipeline helpers (2D and 3D)                                       */
/* ------------------------------------------------------------------ */

static VkPipelineLayout create_pipeline_layout(VkDevice dev,
                                                VkPushConstantRange* pcrs,
                                                uint32_t pcr_count)
{
    VkPipelineLayoutCreateInfo plci = {0};
    plci.sType                  = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    plci.pushConstantRangeCount = pcr_count;
    plci.pPushConstantRanges    = pcrs;
    VkPipelineLayout pl = VK_NULL_HANDLE;
    VkResult res = vkCreatePipelineLayout(dev, &plci, NULL, &pl);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreatePipelineLayout failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    return pl;
}

static VkPipeline create_graphics_pipeline(VkDevice dev,
    VkPipelineLayout layout, VkRenderPass rp,
    VkShaderModule vert, VkShaderModule frag,
    uint32_t width, uint32_t height,
    int enable_depth)
{
    VkPipelineShaderStageCreateInfo stages[2] = {{0}};
    stages[0].sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage  = VK_SHADER_STAGE_VERTEX_BIT;
    stages[0].module = vert;
    stages[0].pName  = "main";
    stages[1].sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage  = VK_SHADER_STAGE_FRAGMENT_BIT;
    stages[1].module = frag;
    stages[1].pName  = "main";

    /* No vertex buffers — built-in vertex data via gl_VertexIndex */
    VkPipelineVertexInputStateCreateInfo vi = {0};
    vi.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;

    VkPipelineInputAssemblyStateCreateInfo ia = {0};
    ia.sType    = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    ia.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;

    VkViewport vp = {0};
    vp.x        = 0.0f;
    vp.y        = 0.0f;
    vp.width    = (float)width;
    vp.height   = (float)height;
    vp.minDepth = 0.0f;
    vp.maxDepth = 1.0f;

    VkRect2D scissor = {0};
    scissor.offset.x      = 0;
    scissor.offset.y      = 0;
    scissor.extent.width  = width;
    scissor.extent.height = height;

    VkPipelineViewportStateCreateInfo vs = {0};
    vs.sType         = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    vs.viewportCount = 1;
    vs.pViewports    = &vp;
    vs.scissorCount  = 1;
    vs.pScissors     = &scissor;

    VkPipelineRasterizationStateCreateInfo rs = {0};
    rs.sType                   = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rs.polygonMode             = VK_POLYGON_MODE_FILL;
    rs.cullMode                = VK_CULL_MODE_BACK_BIT;
    rs.frontFace               = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    rs.lineWidth               = 1.0f;

    VkPipelineMultisampleStateCreateInfo ms = {0};
    ms.sType                = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

    VkPipelineDepthStencilStateCreateInfo ds = {0};
    ds.sType                 = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
    ds.depthTestEnable       = enable_depth ? VK_TRUE : VK_FALSE;
    ds.depthWriteEnable      = enable_depth ? VK_TRUE : VK_FALSE;
    ds.depthCompareOp        = VK_COMPARE_OP_LESS;
    ds.depthBoundsTestEnable = VK_FALSE;
    ds.stencilTestEnable     = VK_FALSE;

    VkPipelineColorBlendAttachmentState cb = {0};
    cb.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                        VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
    cb.blendEnable = VK_FALSE;

    VkPipelineColorBlendStateCreateInfo cbs = {0};
    cbs.sType           = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    cbs.attachmentCount = 1;
    cbs.pAttachments    = &cb;

    VkGraphicsPipelineCreateInfo gpci = {0};
    gpci.sType               = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    gpci.stageCount          = 2;
    gpci.pStages             = stages;
    gpci.pVertexInputState   = &vi;
    gpci.pInputAssemblyState = &ia;
    gpci.pViewportState      = &vs;
    gpci.pRasterizationState = &rs;
    gpci.pMultisampleState   = &ms;
    gpci.pDepthStencilState  = &ds;
    gpci.pColorBlendState    = &cbs;
    gpci.layout              = layout;
    gpci.renderPass          = rp;
    gpci.subpass             = 0;

    VkPipeline pipe = VK_NULL_HANDLE;
    VkResult res = vkCreateGraphicsPipelines(dev, VK_NULL_HANDLE,
                                              1, &gpci, NULL, &pipe);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateGraphicsPipelines failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    return pipe;
}

/* ------------------------------------------------------------------ */
/*  Framebuffers                                                       */
/* ------------------------------------------------------------------ */
static int create_framebuffers(XvkApp* a)
{
    a->framebuffers = (VkFramebuffer*)malloc(
        a->swapchain_image_count * sizeof(VkFramebuffer));
    if (!a->framebuffers) {
        xvk_set_error("malloc failed for framebuffers");
        return 0;
    }

    for (int i = 0; i < a->swapchain_image_count; ++i) {
        VkImageView attachments[2] = {
            a->swapchain_image_views[i],
            a->depth_image_view
        };
        VkFramebufferCreateInfo fci = {0};
        fci.sType           = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        fci.renderPass      = a->render_pass;
        fci.attachmentCount = 2;
        fci.pAttachments    = attachments;
        fci.width           = a->swapchain_extent.width;
        fci.height          = a->swapchain_extent.height;
        fci.layers          = 1;

        VkResult res = vkCreateFramebuffer(a->device, &fci, NULL,
                                            &a->framebuffers[i]);
        if (res != VK_SUCCESS) {
            xvk_set_error_fmt("vkCreateFramebuffer[%d] failed: %d", i, (int)res);
            /* clean up earlier framebuffers */
            for (int j = 0; j < i; ++j)
                vkDestroyFramebuffer(a->device, a->framebuffers[j], NULL);
            free(a->framebuffers);
            a->framebuffers = NULL;
            return 0;
        }
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/*  Command pool / command buffers                                     */
/* ------------------------------------------------------------------ */
static VkCommandPool create_cmd_pool(VkDevice dev, uint32_t family)
{
    VkCommandPoolCreateInfo cpci = {0};
    cpci.sType            = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    cpci.flags            = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    cpci.queueFamilyIndex = family;
    VkCommandPool pool = VK_NULL_HANDLE;
    VkResult res = vkCreateCommandPool(dev, &cpci, NULL, &pool);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateCommandPool failed: %d", (int)res);
        return VK_NULL_HANDLE;
    }
    return pool;
}

static int allocate_cmd_buffers(VkDevice dev, VkCommandPool pool,
                                 VkCommandBuffer* bufs, int count)
{
    VkCommandBufferAllocateInfo cbai = {0};
    cbai.sType              = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    cbai.commandPool        = pool;
    cbai.level              = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    cbai.commandBufferCount = (uint32_t)count;
    VkResult res = vkAllocateCommandBuffers(dev, &cbai, bufs);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkAllocateCommandBuffers failed: %d", (int)res);
        return 0;
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/*  Sync objects                                                       */
/* ------------------------------------------------------------------ */
static int create_sync_objects(VkDevice dev, int count,
    VkSemaphore* image_avail, VkSemaphore* render_fin, VkFence* fences)
{
    VkSemaphoreCreateInfo sci = {0};
    sci.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;

    VkFenceCreateInfo fci = {0};
    fci.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    fci.flags = VK_FENCE_CREATE_SIGNALED_BIT;

    for (int i = 0; i < count; ++i) {
        VkResult r;
        r = vkCreateSemaphore(dev, &sci, NULL, &image_avail[i]);
        if (r != VK_SUCCESS) {
            xvk_set_error_fmt("vkCreateSemaphore (avail) failed: %d", (int)r);
            return 0;
        }
        r = vkCreateSemaphore(dev, &sci, NULL, &render_fin[i]);
        if (r != VK_SUCCESS) {
            xvk_set_error_fmt("vkCreateSemaphore (render) failed: %d", (int)r);
            vkDestroySemaphore(dev, image_avail[i], NULL);
            return 0;
        }
        r = vkCreateFence(dev, &fci, NULL, &fences[i]);
        if (r != VK_SUCCESS) {
            xvk_set_error_fmt("vkCreateFence failed: %d", (int)r);
            vkDestroySemaphore(dev, image_avail[i], NULL);
            vkDestroySemaphore(dev, render_fin[i], NULL);
            return 0;
        }
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/*  Swapchain creation                                                 */
/* ------------------------------------------------------------------ */
static int create_swapchain(XvkApp* a)
{
    VkSurfaceCapabilitiesKHR caps;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(a->phys_dev, a->surface, &caps);

    VkSurfaceFormatKHR fmt = pick_swapchain_fmt(a->phys_dev, a->surface);
    VkPresentModeKHR   pm  = pick_present_mode(a->phys_dev, a->surface);
    VkExtent2D         ext = pick_extent(a->phys_dev, a->surface, a->window);

    a->swapchain_fmt    = fmt.format;
    a->swapchain_extent = ext;

    uint32_t desired = caps.minImageCount + 1;
    if (caps.maxImageCount > 0 && desired > caps.maxImageCount)
        desired = caps.maxImageCount;

    VkSwapchainCreateInfoKHR sci = {0};
    sci.sType            = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
    sci.surface          = a->surface;
    sci.minImageCount    = desired;
    sci.imageFormat      = fmt.format;
    sci.imageColorSpace  = fmt.colorSpace;
    sci.imageExtent      = ext;
    sci.imageArrayLayers = 1;
    sci.imageUsage       = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    sci.preTransform     = caps.currentTransform;
    sci.compositeAlpha   = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    sci.presentMode      = pm;
    sci.clipped          = VK_TRUE;

    /* Queue family sharing */
    uint32_t families[2] = {
        a->graphics_family, a->present_family
    };
    if (a->graphics_family != a->present_family) {
        sci.imageSharingMode      = VK_SHARING_MODE_CONCURRENT;
        sci.queueFamilyIndexCount = 2;
        sci.pQueueFamilyIndices   = families;
    } else {
        sci.imageSharingMode      = VK_SHARING_MODE_EXCLUSIVE;
        sci.queueFamilyIndexCount = 0;
    }

    VkResult res = vkCreateSwapchainKHR(a->device, &sci, NULL, &a->swapchain);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateSwapchainKHR failed: %d", (int)res);
        return 0;
    }

    /* Retrieve images */
    vkGetSwapchainImagesKHR(a->device, a->swapchain, &desired, NULL);
    a->swapchain_image_count = (int)desired;
    a->swapchain_images = (VkImage*)malloc(desired * sizeof(VkImage));
    if (!a->swapchain_images) {
        xvk_set_error("malloc failed for swapchain_images");
        return 0;
    }
    vkGetSwapchainImagesKHR(a->device, a->swapchain, &desired,
                            a->swapchain_images);

    /* Image views */
    a->swapchain_image_views = (VkImageView*)malloc(
        desired * sizeof(VkImageView));
    if (!a->swapchain_image_views) {
        xvk_set_error("malloc failed for swapchain_image_views");
        return 0;
    }
    for (uint32_t i = 0; i < desired; ++i) {
        VkImageViewCreateInfo ivci = {0};
        ivci.sType    = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
        ivci.image    = a->swapchain_images[i];
        ivci.viewType = VK_IMAGE_VIEW_TYPE_2D;
        ivci.format   = fmt.format;
        ivci.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
        ivci.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
        ivci.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
        ivci.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;
        ivci.subresourceRange.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
        ivci.subresourceRange.baseMipLevel   = 0;
        ivci.subresourceRange.levelCount     = 1;
        ivci.subresourceRange.baseArrayLayer = 0;
        ivci.subresourceRange.layerCount     = 1;

        VkResult r = vkCreateImageView(a->device, &ivci, NULL,
                                        &a->swapchain_image_views[i]);
        if (r != VK_SUCCESS) {
            xvk_set_error_fmt("vkCreateImageView[%u] failed: %d", i, (int)r);
            return 0;
        }
    }
    return 1;
}

/* ------------------------------------------------------------------ */
/*  Cleanup swapchain resources (preserve device etc.)                 */
/* ------------------------------------------------------------------ */
static void cleanup_swapchain(XvkApp* a)
{
    vkDeviceWaitIdle(a->device);

    for (int i = 0; i < a->swapchain_image_count; ++i) {
        if (a->framebuffers && a->framebuffers[i])
            vkDestroyFramebuffer(a->device, a->framebuffers[i], NULL);
        if (a->swapchain_image_views && a->swapchain_image_views[i])
            vkDestroyImageView(a->device, a->swapchain_image_views[i], NULL);
    }
    free(a->framebuffers);        a->framebuffers        = NULL;
    free(a->swapchain_image_views); a->swapchain_image_views = NULL;
    free(a->swapchain_images);    a->swapchain_images    = NULL;
    a->swapchain_image_count = 0;

    if (a->depth_image_view)
        vkDestroyImageView(a->device, a->depth_image_view, NULL);
    if (a->depth_image)
        vkDestroyImage(a->device, a->depth_image, NULL);
    if (a->depth_memory)
        vkFreeMemory(a->device, a->depth_memory, NULL);
    a->depth_image_view = VK_NULL_HANDLE;
    a->depth_image      = VK_NULL_HANDLE;
    a->depth_memory     = VK_NULL_HANDLE;

    if (a->swapchain)
        vkDestroySwapchainKHR(a->device, a->swapchain, NULL);
    a->swapchain = VK_NULL_HANDLE;

    /* Note: image views are destroyed above. */
}

/* ------------------------------------------------------------------ */
/*  Swapchain recreation                                               */
/* ------------------------------------------------------------------ */
static int recreate_swapchain(XvkApp* a)
{
    /* Save old count before cleanup_swapchain resets it to 0 */
    int old_count = a->swapchain_image_count;

    cleanup_swapchain(a);

    /* Re-allocate command buffers (the old ones were tied to the old
     * swapchain and must be freed before the pool is reused). */
    if (a->cmd_buffers) {
        vkFreeCommandBuffers(a->device, a->cmd_pool,
                             (uint32_t)old_count,
                             a->cmd_buffers);
        free(a->cmd_buffers);
        a->cmd_buffers = NULL;
    }

    if (!create_swapchain(a))
        return 0;
    if (!create_depth_resources(a))
        return 0;
    if (!create_framebuffers(a))
        return 0;

    a->cmd_buffers = (VkCommandBuffer*)malloc(
        a->swapchain_image_count * sizeof(VkCommandBuffer));
    if (!a->cmd_buffers) { xvk_set_error("malloc failed for cmd_buffers"); return 0; }
    if (!allocate_cmd_buffers(a->device, a->cmd_pool,
                               a->cmd_buffers, a->swapchain_image_count))
        return 0;
    return 1;
}

/* ------------------------------------------------------------------ */
/*  Full teardown of EVERYTHING (except the app struct itself)        */
/* ------------------------------------------------------------------ */
static void xvk_app_cleanup_internal(XvkApp* a)
{
    if (!a || a->magic != XVK_MAGIC) return;

    /* Join all GPU work before tearing down resources */
    if (a->device != VK_NULL_HANDLE)
        vkDeviceWaitIdle(a->device);

    /* --- Sync objects --- */
    if (a->image_available) {
        for (int i = 0; i < XVK_MAX_FRAMES; ++i) {
            if (a->image_available[i])
                vkDestroySemaphore(a->device, a->image_available[i], NULL);
            if (a->render_finished[i])
                vkDestroySemaphore(a->device, a->render_finished[i], NULL);
            if (a->in_flight_fences[i])
                vkDestroyFence(a->device, a->in_flight_fences[i], NULL);
        }
        free(a->image_available);  a->image_available  = NULL;
        free(a->render_finished);  a->render_finished  = NULL;
        free(a->in_flight_fences); a->in_flight_fences = NULL;
    }

    /* --- Command buffers & pool --- */
    if (a->cmd_buffers) {
        if (a->cmd_pool)
            vkFreeCommandBuffers(a->device, a->cmd_pool,
                                 (uint32_t)a->swapchain_image_count,
                                 a->cmd_buffers);
        free(a->cmd_buffers);
        a->cmd_buffers = NULL;
    }
    if (a->cmd_pool) {
        vkDestroyCommandPool(a->device, a->cmd_pool, NULL);
        a->cmd_pool = VK_NULL_HANDLE;
    }

    /* --- Framebuffers --- */
    if (a->framebuffers) {
        for (int i = 0; i < a->swapchain_image_count; ++i)
            if (a->framebuffers[i])
                vkDestroyFramebuffer(a->device, a->framebuffers[i], NULL);
        free(a->framebuffers);
        a->framebuffers = NULL;
    }

    /* --- Pipelines & layouts --- */
    if (a->pipeline_2d)  vkDestroyPipeline(a->device, a->pipeline_2d, NULL);
    if (a->pipeline_3d)  vkDestroyPipeline(a->device, a->pipeline_3d, NULL);
    if (a->pipe_layout_2d) vkDestroyPipelineLayout(a->device, a->pipe_layout_2d, NULL);
    if (a->pipe_layout_3d) vkDestroyPipelineLayout(a->device, a->pipe_layout_3d, NULL);
    if (a->pipe_layout_quad) vkDestroyPipelineLayout(a->device, a->pipe_layout_quad, NULL);
    if (a->particle_layout)   vkDestroyPipelineLayout(a->device, a->particle_layout, NULL);
    a->pipeline_2d    = VK_NULL_HANDLE;
    a->pipeline_3d    = VK_NULL_HANDLE;
    a->pipe_layout_2d = VK_NULL_HANDLE;
    a->pipe_layout_3d = VK_NULL_HANDLE;
    a->pipe_layout_quad = VK_NULL_HANDLE;
    a->particle_layout   = VK_NULL_HANDLE;

    /* --- Particle GPU resources --- */
    if (a->particle_pipeline) vkDestroyPipeline(a->device, a->particle_pipeline, NULL);
    if (a->pipeline_quad)     vkDestroyPipeline(a->device, a->pipeline_quad, NULL);
    if (a->particle_vbo)      vkDestroyBuffer(a->device, a->particle_vbo, NULL);
    if (a->particle_mem) {
        if (a->particle_mapped) vkUnmapMemory(a->device, a->particle_mem);
        vkFreeMemory(a->device, a->particle_mem, NULL);
    }
    free(a->particles);
    a->particle_pipeline = VK_NULL_HANDLE;
    a->pipeline_quad     = VK_NULL_HANDLE;
    a->particle_vbo      = VK_NULL_HANDLE;
    a->particle_mem      = VK_NULL_HANDLE;
    a->particle_mapped   = NULL;
    a->particles         = NULL;
    a->particle_count    = 0;

    /* --- Render pass --- */
    if (a->render_pass)
        vkDestroyRenderPass(a->device, a->render_pass, NULL);
    a->render_pass = VK_NULL_HANDLE;

    /* --- Swapchain resources --- */
    cleanup_swapchain(a);

    /* --- Offscreen resources --- */
    if (a->is_offscreen) {
        if (a->offs_fence)
            vkDestroyFence(a->device, a->offs_fence, NULL);
        if (a->offs_cmd && a->cmd_pool)
            vkFreeCommandBuffers(a->device, a->cmd_pool, 1, &a->offs_cmd);
        if (a->offs_pipeline)
            vkDestroyPipeline(a->device, a->offs_pipeline, NULL);
        if (a->offs_render_pass)
            vkDestroyRenderPass(a->device, a->offs_render_pass, NULL);
        if (a->offs_framebuffer)
            vkDestroyFramebuffer(a->device, a->offs_framebuffer, NULL);
        if (a->offs_mapped && a->offs_readback_mem)
            vkUnmapMemory(a->device, a->offs_readback_mem);
        if (a->offs_readback)
            vkDestroyBuffer(a->device, a->offs_readback, NULL);
        if (a->offs_readback_mem)
            vkFreeMemory(a->device, a->offs_readback_mem, NULL);
        if (a->offs_image_view)
            vkDestroyImageView(a->device, a->offs_image_view, NULL);
        if (a->offs_image)
            vkDestroyImage(a->device, a->offs_image, NULL);
        if (a->offs_memory)
            vkFreeMemory(a->device, a->offs_memory, NULL);
        a->offs_fence        = VK_NULL_HANDLE;
        a->offs_cmd          = VK_NULL_HANDLE;
        a->offs_pipeline     = VK_NULL_HANDLE;
        a->offs_render_pass  = VK_NULL_HANDLE;
        a->offs_framebuffer  = VK_NULL_HANDLE;
        a->offs_mapped       = NULL;
        a->offs_readback     = VK_NULL_HANDLE;
        a->offs_readback_mem = VK_NULL_HANDLE;
        a->offs_image_view   = VK_NULL_HANDLE;
        a->offs_image        = VK_NULL_HANDLE;
        a->offs_memory       = VK_NULL_HANDLE;
    }

    /* --- Device --- */
    if (a->device)  vkDestroyDevice(a->device, NULL);
    a->device = VK_NULL_HANDLE;

    /* --- Surface --- */
    if (a->surface) {
        vkDestroySurfaceKHR(a->instance, a->surface, NULL);
        a->surface = VK_NULL_HANDLE;
    }

    /* --- Window --- */
    if (a->window) {
        glfwDestroyWindow(a->window);
        a->window = NULL;
    }

    /* --- Instance --- */
    if (a->instance)
        vkDestroyInstance(a->instance, NULL);
    a->instance = VK_NULL_HANDLE;

    /* Terminate GLFW.  If already terminated this is a no-op. */
    glfwTerminate();

    a->magic = 0;
}

/* ================================================================== */
/*  PUBLIC ABI FUNCTIONS                                              */
/* ================================================================== */

/* ---- xvk_app_create ---- */
int64_t xvk_app_create(const char* title, int32_t width, int32_t height)
{
    XvkApp* a = (XvkApp*)calloc(1, sizeof(XvkApp));
    if (!a) {
        xvk_set_error("calloc failed");
        return 0;
    }

    /* Initialise GLFW */
    if (!glfwInit()) {
        xvk_set_error("glfwInit failed");
        free(a);
        return 0;
    }
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    a->window = glfwCreateWindow(width, height, title ? title : "XIOM Vulkan",
                                 NULL, NULL);
    if (!a->window) {
        xvk_set_error("glfwCreateWindow failed");
        glfwTerminate();
        free(a);
        return 0;
    }

    /* Instance */
    int have_val = 0;
    a->instance = create_instance(title ? title : "XIOM App", &have_val);
    if (!a->instance) goto fail;

    /* Surface */
    a->surface = create_surface(a->instance, a->window);
    if (!a->surface) goto fail;

    /* Physical device */
    if (!pick_physical_device(a->instance, a->surface,
                               &a->phys_dev, &a->device_type))
        goto fail;

    /* Queue families */
    if (!find_queue_families(a->phys_dev, a->surface,
                              &a->graphics_family, &a->present_family))
        goto fail;

    /* Logical device */
    a->device = create_device(a->phys_dev,
                               a->graphics_family, a->present_family,
                               a->surface);
    if (!a->device) goto fail;

    /* Queues */
    vkGetDeviceQueue(a->device, a->graphics_family, 0, &a->graphics_queue);
    vkGetDeviceQueue(a->device, a->present_family, 0, &a->present_queue);

    /* Memory properties */
    vkGetPhysicalDeviceMemoryProperties(a->phys_dev, &a->mem_props);

    /* Swapchain */
    if (!create_swapchain(a)) goto fail;

    /* Depth resources */
    if (!create_depth_resources(a)) goto fail;

    /* Render pass */
    a->render_pass = create_render_pass(a->device, a->swapchain_fmt,
                                         a->depth_format);
    if (!a->render_pass) goto fail;

    /* Shader modules */
    VkShaderModule tri_vert = create_shader_module(a->device,
        xvk_triangle_vert_spv, xvk_triangle_vert_spv_len);
    VkShaderModule tri_frag = create_shader_module(a->device,
        xvk_triangle_frag_spv, xvk_triangle_frag_spv_len);
    VkShaderModule cube_vert = create_shader_module(a->device,
        xvk_cube_vert_spv, xvk_cube_vert_spv_len);
    VkShaderModule cube_frag = create_shader_module(a->device,
        xvk_cube_frag_spv, xvk_cube_frag_spv_len);

    if (!tri_vert || !tri_frag || !cube_vert || !cube_frag) {
        if (tri_vert) vkDestroyShaderModule(a->device, tri_vert, NULL);
        if (tri_frag) vkDestroyShaderModule(a->device, tri_frag, NULL);
        if (cube_vert) vkDestroyShaderModule(a->device, cube_vert, NULL);
        if (cube_frag) vkDestroyShaderModule(a->device, cube_frag, NULL);
        goto fail;
    }

    /* Pipeline layouts */
    VkPushConstantRange pc_range_2d = {0};
    pc_range_2d.stageFlags = VK_SHADER_STAGE_VERTEX_BIT;
    pc_range_2d.offset     = 0;
    pc_range_2d.size       = 16;   /* vec4 colour */

    a->pipe_layout_2d = create_pipeline_layout(a->device, &pc_range_2d, 1);
    if (!a->pipe_layout_2d) goto fail_shaders;

    VkPushConstantRange pc_range_3d = {0};
    pc_range_3d.stageFlags = VK_SHADER_STAGE_VERTEX_BIT;
    pc_range_3d.offset     = 0;
    pc_range_3d.size       = 64;   /* mat4 mvp */

    a->pipe_layout_3d = create_pipeline_layout(a->device, &pc_range_3d, 1);
    if (!a->pipe_layout_3d) goto fail_shaders;

    /* Pipelines */
    a->pipeline_2d = create_graphics_pipeline(a->device,
        a->pipe_layout_2d, a->render_pass,
        tri_vert, tri_frag, width, height, 0);
    if (!a->pipeline_2d) goto fail_shaders;

    a->pipeline_3d = create_graphics_pipeline(a->device,
        a->pipe_layout_3d, a->render_pass,
        cube_vert, cube_frag, width, height, 1);
    if (!a->pipeline_3d) goto fail_shaders;

    /* Done with shader modules (they remain alive for pipeline caching) */
    vkDestroyShaderModule(a->device, tri_vert, NULL);
    vkDestroyShaderModule(a->device, tri_frag, NULL);
    vkDestroyShaderModule(a->device, cube_vert, NULL);
    vkDestroyShaderModule(a->device, cube_frag, NULL);

    /* --- Quad pipeline (windowed 2D rectangle, no depth) --- */
    {
        VkShaderModule qv = create_shader_module(a->device,
            xvk_quad_vert_spv, xvk_quad_vert_spv_len);
        VkShaderModule qf = create_shader_module(a->device,
            xvk_quad_frag_spv, xvk_quad_frag_spv_len);
        if (!qv || !qf) {
            if (qv) vkDestroyShaderModule(a->device, qv, NULL);
            if (qf) vkDestroyShaderModule(a->device, qf, NULL);
            goto fail;
        }
        VkPushConstantRange pcr = {0};
        pcr.stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT;
        pcr.offset     = 0;
        pcr.size       = 32;   /* rect[4] + color[4] */
        a->pipe_layout_quad = create_pipeline_layout(a->device, &pcr, 1);
        if (!a->pipe_layout_quad) {
            vkDestroyShaderModule(a->device, qv, NULL);
            vkDestroyShaderModule(a->device, qf, NULL);
            goto fail;
        }
        a->pipeline_quad = create_graphics_pipeline(a->device,
            a->pipe_layout_quad, a->render_pass,
            qv, qf, width, height, 0);
        vkDestroyShaderModule(a->device, qv, NULL);
        vkDestroyShaderModule(a->device, qf, NULL);
        if (!a->pipeline_quad) goto fail;
    }

    /* --- Particle pipeline (windowed only) --- */
    {
        VkShaderModule pv = create_shader_module(a->device,
            xvk_particle_vert_spv, xvk_particle_vert_spv_len);
        VkShaderModule pf = create_shader_module(a->device,
            xvk_particle_frag_spv, xvk_particle_frag_spv_len);
        if (!pv || !pf) {
            if (pv) vkDestroyShaderModule(a->device, pv, NULL);
            if (pf) vkDestroyShaderModule(a->device, pf, NULL);
            goto fail;
        }

        /* Pipeline layout — no push constants, no descriptor sets */
        {
            VkPipelineLayoutCreateInfo plci = {0};
            plci.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
            VkResult res = vkCreatePipelineLayout(a->device, &plci, NULL,
                                                   &a->particle_layout);
            if (res != VK_SUCCESS) {
                xvk_set_error_fmt("vkCreatePipelineLayout (particle) failed: %d", (int)res);
                vkDestroyShaderModule(a->device, pv, NULL);
                vkDestroyShaderModule(a->device, pf, NULL);
                goto fail;
            }
        }

        /* Vertex input state */
        VkVertexInputBindingDescription bind = {0};
        bind.binding   = 0;
        bind.stride    = 20;   /* pos[2] + color[3] */
        bind.inputRate = VK_VERTEX_INPUT_RATE_VERTEX;

        VkVertexInputAttributeDescription attrs[2] = {{0}};
        attrs[0].location = 0;
        attrs[0].binding  = 0;
        attrs[0].format   = VK_FORMAT_R32G32_SFLOAT;
        attrs[0].offset   = 0;
        attrs[1].location = 1;
        attrs[1].binding  = 0;
        attrs[1].format   = VK_FORMAT_R32G32B32_SFLOAT;
        attrs[1].offset   = 8;

        VkPipelineVertexInputStateCreateInfo vi = {0};
        vi.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
        vi.vertexBindingDescriptionCount   = 1;
        vi.pVertexBindingDescriptions      = &bind;
        vi.vertexAttributeDescriptionCount = 2;
        vi.pVertexAttributeDescriptions    = attrs;

        /* Shader stages */
        VkPipelineShaderStageCreateInfo stages[2] = {{0}};
        stages[0].sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stages[0].stage  = VK_SHADER_STAGE_VERTEX_BIT;
        stages[0].module = pv;
        stages[0].pName  = "main";
        stages[1].sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stages[1].stage  = VK_SHADER_STAGE_FRAGMENT_BIT;
        stages[1].module = pf;
        stages[1].pName  = "main";

        /* Input assembly — POINT_LIST */
        VkPipelineInputAssemblyStateCreateInfo ia = {0};
        ia.sType    = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
        ia.topology = VK_PRIMITIVE_TOPOLOGY_POINT_LIST;

        /* Viewport & scissor */
        VkViewport vp = {0};
        vp.x        = 0.0f;
        vp.y        = 0.0f;
        vp.width    = (float)width;
        vp.height   = (float)height;
        vp.minDepth = 0.0f;
        vp.maxDepth = 1.0f;

        VkRect2D scissor = {0};
        scissor.offset.x      = 0;
        scissor.offset.y      = 0;
        scissor.extent.width  = (uint32_t)width;
        scissor.extent.height = (uint32_t)height;

        VkPipelineViewportStateCreateInfo vs = {0};
        vs.sType         = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
        vs.viewportCount = 1;
        vs.pViewports    = &vp;
        vs.scissorCount  = 1;
        vs.pScissors     = &scissor;

        /* Rasterisation — no culling for points */
        VkPipelineRasterizationStateCreateInfo rs = {0};
        rs.sType                   = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
        rs.polygonMode             = VK_POLYGON_MODE_FILL;
        rs.cullMode                = VK_CULL_MODE_NONE;
        rs.frontFace               = VK_FRONT_FACE_COUNTER_CLOCKWISE;
        rs.lineWidth               = 1.0f;

        VkPipelineMultisampleStateCreateInfo ms = {0};
        ms.sType                = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
        ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

        /* No depth test */
        VkPipelineDepthStencilStateCreateInfo ds = {0};
        ds.sType                 = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
        ds.depthTestEnable       = VK_FALSE;
        ds.depthWriteEnable      = VK_FALSE;

        VkPipelineColorBlendAttachmentState cb = {0};
        cb.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                            VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
        cb.blendEnable = VK_FALSE;

        VkPipelineColorBlendStateCreateInfo cbs = {0};
        cbs.sType           = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
        cbs.attachmentCount = 1;
        cbs.pAttachments    = &cb;

        VkGraphicsPipelineCreateInfo gpci = {0};
        gpci.sType               = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
        gpci.stageCount          = 2;
        gpci.pStages             = stages;
        gpci.pVertexInputState   = &vi;
        gpci.pInputAssemblyState = &ia;
        gpci.pViewportState      = &vs;
        gpci.pRasterizationState = &rs;
        gpci.pMultisampleState   = &ms;
        gpci.pDepthStencilState  = &ds;
        gpci.pColorBlendState    = &cbs;
        gpci.layout              = a->particle_layout;
        gpci.renderPass          = a->render_pass;
        gpci.subpass             = 0;

        VkResult res = vkCreateGraphicsPipelines(a->device, VK_NULL_HANDLE,
                                                  1, &gpci, NULL,
                                                  &a->particle_pipeline);
        vkDestroyShaderModule(a->device, pv, NULL);
        vkDestroyShaderModule(a->device, pf, NULL);
        if (res != VK_SUCCESS) {
            xvk_set_error_fmt("vkCreateGraphicsPipelines (particle) failed: %d", (int)res);
            goto fail;
        }
    }

    /* Framebuffers */
    if (!create_framebuffers(a)) goto fail;

    /* Command pool */
    a->cmd_pool = create_cmd_pool(a->device, a->graphics_family);
    if (!a->cmd_pool) goto fail;

    /* Command buffers (one per swapchain image) */
    a->cmd_buffers = (VkCommandBuffer*)malloc(
        a->swapchain_image_count * sizeof(VkCommandBuffer));
    if (!a->cmd_buffers) { xvk_set_error("malloc failed for cmd_buffers"); goto fail; }
    if (!allocate_cmd_buffers(a->device, a->cmd_pool,
                               a->cmd_buffers, a->swapchain_image_count))
        goto fail;

    /* Sync */
    a->image_available = (VkSemaphore*)malloc(XVK_MAX_FRAMES * sizeof(VkSemaphore));
    a->render_finished = (VkSemaphore*)malloc(XVK_MAX_FRAMES * sizeof(VkSemaphore));
    a->in_flight_fences= (VkFence*)malloc(XVK_MAX_FRAMES * sizeof(VkFence));
    if (!a->image_available || !a->render_finished || !a->in_flight_fences) {
        xvk_set_error("malloc failed for sync objects");
        goto fail;
    }
    memset(a->image_available, 0, XVK_MAX_FRAMES * sizeof(VkSemaphore));
    memset(a->render_finished, 0, XVK_MAX_FRAMES * sizeof(VkSemaphore));
    memset(a->in_flight_fences, 0, XVK_MAX_FRAMES * sizeof(VkFence));
    if (!create_sync_objects(a->device, XVK_MAX_FRAMES,
                              a->image_available,
                              a->render_finished,
                              a->in_flight_fences))
        goto fail;

    a->clear_r = 0.0f;
    a->clear_g = 0.0f;
    a->clear_b = 0.0f;
    a->frame_index     = 0;
    a->recording       = 0;
    a->in_render_pass  = 0;
    a->magic       = XVK_MAGIC;
    a->is_offscreen = 0;

    xvk_set_error("");
    return xvk_to_handle(a);

fail_shaders:
    vkDestroyShaderModule(a->device, tri_vert, NULL);
    vkDestroyShaderModule(a->device, tri_frag, NULL);
    vkDestroyShaderModule(a->device, cube_vert, NULL);
    vkDestroyShaderModule(a->device, cube_frag, NULL);
    /* fall through */
fail:
    xvk_app_cleanup_internal(a);
    free(a);
    return 0;
}

/* ---- xvk_app_destroy ---- */
void xvk_app_destroy(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return;
    xvk_app_cleanup_internal(a);
    free(a);
}

/* ---- xvk_app_valid ---- */
int32_t xvk_app_valid(int64_t app_h)
{
    return xvk_from_handle(app_h) != NULL ? 1 : 0;
}

/* ---- xvk_last_error ---- */
const char* xvk_last_error(void)
{
    return g_xvk_error;
}

/* ---- window / events ---- */
int32_t xvk_app_should_close(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->window) return 1;
    return glfwWindowShouldClose(a->window) ? 1 : 0;
}

void xvk_app_poll(int64_t app_h)
{
    (void)app_h;
    glfwPollEvents();
}

double xvk_now(void)
{
    return glfwGetTime();
}

/* ---- device type ---- */
int32_t xvk_device_type(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    return a ? a->device_type : -1;
}

/* ---- set_clear_color ---- */
void xvk_set_clear_color(int64_t app_h, float r, float g, float b)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return;
    a->clear_r = r;
    a->clear_g = g;
    a->clear_b = b;
}

/* ---- begin_frame ---- */
int32_t xvk_begin_frame(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return -1;

    /* Check for window resize */
    if (a->window) {
        int w, h;
        glfwGetFramebufferSize(a->window, &w, &h);
        if (w != (int)a->swapchain_extent.width ||
            h != (int)a->swapchain_extent.height) {
            if (!recreate_swapchain(a)) return -1;
            return 0;  /* skip this frame */
        }
    }

    VkSemaphore avail = a->image_available[a->frame_index];
    VkFence    fence  = a->in_flight_fences[a->frame_index];

    /* Wait for the current frame's fence */
    vkWaitForFences(a->device, 1, &fence, VK_TRUE, UINT64_MAX);
    vkResetFences(a->device, 1, &fence);

    /* Acquire next image */
    uint32_t img_idx = 0;
    VkResult res = vkAcquireNextImageKHR(a->device, a->swapchain,
                                          UINT64_MAX, avail,
                                          VK_NULL_HANDLE, &img_idx);
    if (res == VK_ERROR_OUT_OF_DATE_KHR || res == VK_SUBOPTIMAL_KHR) {
        recreate_swapchain(a);
        return 0;  /* skip */
    }
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkAcquireNextImageKHR failed: %d", (int)res);
        return -1;
    }

    /* Store current image index for end_frame */
    a->current_image = img_idx;

    /* Reset and begin command buffer */
    VkCommandBuffer cb = a->cmd_buffers[img_idx];
    vkResetCommandBuffer(cb, 0);

    VkCommandBufferBeginInfo cbbi = {0};
    cbbi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    cbbi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    if (vkBeginCommandBuffer(cb, &cbbi) != VK_SUCCESS) {
        xvk_set_error("vkBeginCommandBuffer failed");
        return -1;
    }

    /* Begin render pass */
    VkClearValue clears[2];
    clears[0].color.float32[0] = a->clear_r;
    clears[0].color.float32[1] = a->clear_g;
    clears[0].color.float32[2] = a->clear_b;
    clears[0].color.float32[3] = 1.0f;
    clears[1].depthStencil.depth   = 1.0f;
    clears[1].depthStencil.stencil = 0;

    VkRenderPassBeginInfo rpbi = {0};
    rpbi.sType       = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    rpbi.renderPass  = a->render_pass;
    rpbi.framebuffer = a->framebuffers[img_idx];
    rpbi.renderArea.offset.x = 0;
    rpbi.renderArea.offset.y = 0;
    rpbi.renderArea.extent   = a->swapchain_extent;
    rpbi.clearValueCount     = 2;
    rpbi.pClearValues        = clears;

    vkCmdBeginRenderPass(cb, &rpbi, VK_SUBPASS_CONTENTS_INLINE);
    a->recording      = 1;
    a->in_render_pass = 1;

    /* Keep a->current_image already set above */

    return 1;
}

/* ---- end_frame ---- */
void xvk_end_frame(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording) return;

    uint32_t img_idx = a->current_image;
    VkCommandBuffer cb = a->cmd_buffers[img_idx];

    vkCmdEndRenderPass(cb);
    a->in_render_pass = 0;
    if (vkEndCommandBuffer(cb) != VK_SUCCESS) {
        xvk_set_error("vkEndCommandBuffer failed");
        a->recording = 0;
        return;
    }
    a->recording = 0;

    /* Submit */
    VkSemaphore          wait_sems[] = { a->image_available[a->frame_index] };
    VkPipelineStageFlags wait_stages[] = { VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT };
    VkSemaphore          sig_sems[]  = { a->render_finished[a->frame_index] };

    VkSubmitInfo si = {0};
    si.sType                = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.waitSemaphoreCount   = 1;
    si.pWaitSemaphores      = wait_sems;
    si.pWaitDstStageMask    = wait_stages;
    si.commandBufferCount   = 1;
    si.pCommandBuffers      = &cb;
    si.signalSemaphoreCount = 1;
    si.pSignalSemaphores    = sig_sems;

    VkFence fence = a->in_flight_fences[a->frame_index];

    if (vkQueueSubmit(a->graphics_queue, 1, &si, fence) != VK_SUCCESS) {
        xvk_set_error("vkQueueSubmit failed");
    }

    /* Present */
    VkSwapchainKHR swapchains[] = { a->swapchain };
    VkPresentInfoKHR pi = {0};
    pi.sType              = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
    pi.waitSemaphoreCount = 1;
    pi.pWaitSemaphores    = sig_sems;
    pi.swapchainCount     = 1;
    pi.pSwapchains        = swapchains;
    pi.pImageIndices      = &img_idx;

    VkResult res = vkQueuePresentKHR(a->present_queue, &pi);
    if (res == VK_ERROR_OUT_OF_DATE_KHR || res == VK_SUBOPTIMAL_KHR) {
        recreate_swapchain(a);
    }

    a->frame_index = (a->frame_index + 1) % XVK_MAX_FRAMES;
}

/* ---- draw_triangle_2d ---- */
void xvk_draw_triangle_2d(int64_t app_h, float r, float g, float b)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording) return;

    VkCommandBuffer cb = a->cmd_buffers[a->current_image];

    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, a->pipeline_2d);

    float colour[4] = { r, g, b, 1.0f };
    vkCmdPushConstants(cb, a->pipe_layout_2d, VK_SHADER_STAGE_VERTEX_BIT,
                       0, 16, colour);
    vkCmdDraw(cb, 3, 1, 0, 0);
}

/* ---- draw_cube_3d ---- */
void xvk_draw_cube_3d(int64_t app_h, float angle)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording) return;

    /* Compute MVP on CPU */
    float aspect = (float)a->swapchain_extent.width /
                   (float)a->swapchain_extent.height;

    float model[16], view[16], proj[16], tmp[16], mvp[16];
    mat4_identity(model);
    mat4_rotate_y(model, angle);
    mat4_rotate_x(model, angle * 0.3f);

    mat4_look_at(view, 2.0f, 2.0f, 2.0f,   /* eye */
                       0.0f, 0.0f, 0.0f,   /* centre */
                       0.0f, 1.0f, 0.0f);  /* up */

    mat4_perspective(proj, 45.0f * (float)M_PI / 180.0f, aspect, 0.1f, 10.0f);

    mat4_mul(tmp, view, model);
    mat4_mul(mvp, proj, tmp);

    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, a->pipeline_3d);
    vkCmdPushConstants(cb, a->pipe_layout_3d, VK_SHADER_STAGE_VERTEX_BIT,
                       0, 64, mvp);
    vkCmdDraw(cb, 36, 1, 0, 0);
}

/* ---- draw_quad_2d ---- */
void xvk_draw_quad_2d(int64_t app_h, float cx, float cy,
                       float hw, float hh, float r, float g, float b)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording) return;

    VkCommandBuffer cb = a->cmd_buffers[a->current_image];

    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, a->pipeline_quad);

    float pc[8] = { cx, cy, hw, hh, r, g, b, 1.0f };
    vkCmdPushConstants(cb, a->pipe_layout_quad,
                       VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                       0, 32, pc);
    vkCmdDraw(cb, 6, 1, 0, 0);
}

/* ---- draw_cube_3d_at ---- */
void xvk_draw_cube_3d_at(int64_t app_h, float angle,
                          float px, float py, float pz, float scale)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording) return;

    float aspect = (float)a->swapchain_extent.width /
                   (float)a->swapchain_extent.height;

    float model[16], view[16], proj[16], tmp[16], mvp[16];

    mat4_translation(model, px, py, pz);
    mat4_rotate_y(model, angle);
    mat4_rotate_x(model, angle * 0.3f);
    mat4_scale_right(model, scale);
    /* model = T(px,py,pz) * Ry(angle) * Rx(angle*0.3) * S(scale) */

    mat4_look_at(view, 2.0f, 2.0f, 2.0f,
                       0.0f, 0.0f, 0.0f,
                       0.0f, 1.0f, 0.0f);
    mat4_perspective(proj, 45.0f * (float)M_PI / 180.0f, aspect, 0.1f, 10.0f);

    mat4_mul(tmp, view, model);
    mat4_mul(mvp, proj, tmp);

    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, a->pipeline_3d);
    vkCmdPushConstants(cb, a->pipe_layout_3d, VK_SHADER_STAGE_VERTEX_BIT,
                       0, 64, mvp);
    vkCmdDraw(cb, 36, 1, 0, 0);
}

/* ------------------------------------------------------------------ */
/*  Particle helpers                                                    */
/* ------------------------------------------------------------------ */

/* Deterministic xorshift-style PRNG producing floats in [0,1).
 * Seeded by (index * constant + offset) for reproducibility. */
static float xvk_pfrand(int idx, int offset)
{
    uint32_t x = (uint32_t)(idx * 2654435761u + offset * 1013904223u);
    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    return (float)(x & 0x7FFF) / 32768.0f;
}

/* ---- particles_enable ---- */
int32_t xvk_particles_enable(int64_t app_h, int32_t count)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || count <= 0) return 0;

    /* Re-initialise only when count changes */
    if (a->particle_count == count && a->particles) return 1;

    /* Tear down old resources */
    if (a->particle_vbo)      vkDestroyBuffer(a->device, a->particle_vbo, NULL);
    if (a->particle_mem) {
        if (a->particle_mapped) vkUnmapMemory(a->device, a->particle_mem);
        vkFreeMemory(a->device, a->particle_mem, NULL);
    }
    free(a->particles);
    a->particle_vbo      = VK_NULL_HANDLE;
    a->particle_mem      = VK_NULL_HANDLE;
    a->particle_mapped   = NULL;
    a->particles         = NULL;
    a->particle_count    = 0;

    /* Create vertex buffer (host-visible, coherent) */
    VkDeviceSize buf_size = (VkDeviceSize)count * 20;
    {
        VkBufferCreateInfo bci = {0};
        bci.sType       = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
        bci.size        = buf_size;
        bci.usage       = VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
        bci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
        VkResult res = vkCreateBuffer(a->device, &bci, NULL, &a->particle_vbo);
        if (res != VK_SUCCESS) {
            xvk_set_error_fmt("vkCreateBuffer (particle VBO) failed: %d", (int)res);
            return 0;
        }
    }

    VkMemoryRequirements mr;
    vkGetBufferMemoryRequirements(a->device, a->particle_vbo, &mr);
    uint32_t mi = find_memory_type(&a->mem_props, mr.memoryTypeBits,
                                    VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                                    VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (mi == UINT32_MAX) {
        xvk_set_error("no host-visible coherent memory for particle VBO");
        vkDestroyBuffer(a->device, a->particle_vbo, NULL);
        a->particle_vbo = VK_NULL_HANDLE;
        return 0;
    }

    {
        VkMemoryAllocateInfo mai = {0};
        mai.sType           = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
        mai.allocationSize  = mr.size;
        mai.memoryTypeIndex = mi;
        VkResult res = vkAllocateMemory(a->device, &mai, NULL, &a->particle_mem);
        if (res != VK_SUCCESS) {
            xvk_set_error_fmt("vkAllocateMemory (particle) failed: %d", (int)res);
            vkDestroyBuffer(a->device, a->particle_vbo, NULL);
            a->particle_vbo = VK_NULL_HANDLE;
            return 0;
        }
    }

    vkBindBufferMemory(a->device, a->particle_vbo, a->particle_mem, 0);
    vkMapMemory(a->device, a->particle_mem, 0, buf_size, 0, &a->particle_mapped);

    /* Allocate CPU particle array */
    a->particles = (Particle*)malloc((size_t)count * sizeof(Particle));
    if (!a->particles) {
        xvk_set_error("malloc failed for particle CPU array");
        vkUnmapMemory(a->device, a->particle_mem);
        vkFreeMemory(a->device, a->particle_mem, NULL);
        vkDestroyBuffer(a->device, a->particle_vbo, NULL);
        a->particle_vbo    = VK_NULL_HANDLE;
        a->particle_mem    = VK_NULL_HANDLE;
        a->particle_mapped = NULL;
        return 0;
    }

    /* Initialise fountain state */
    for (int32_t i = 0; i < count; ++i) {
        Particle* p = &a->particles[i];
        p->x    = (xvk_pfrand(i, 0) - 0.5f) * 0.2f;    /* ~ ±0.1 around centre */
        p->y    = 0.9f;                                   /* near bottom of NDC */
        p->vx   = (xvk_pfrand(i, 1) - 0.5f) * 0.5f;      /* small horizontal jitter */
        p->vy   = -(0.3f + xvk_pfrand(i, 2) * 0.5f);     /* upward (negative Y) */
        p->r    = 0.8f + xvk_pfrand(i, 3) * 0.2f;        /* warm colours */
        p->g    = 0.3f + xvk_pfrand(i, 4) * 0.3f;
        p->b    = 0.1f;
        p->life = xvk_pfrand(i, 5) * 2.0f;                /* 0..2 s */
    }

    a->particle_count = count;
    xvk_set_error("");
    return 1;
}

/* ---- draw_particles ---- */
void xvk_draw_particles(int64_t app_h, float dt)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording || !a->particles || a->particle_count <= 0)
        return;

    const float GRAVITY = 0.8f;   /* pulls DOWN (+Y in NDC) */
    int count = a->particle_count;
    Particle* parts = a->particles;

    /* GPU vertex format: { float pos[2]; float color[3]; } — 20 bytes */
    typedef struct { float pos[2]; float color[3]; } GPUParticle;

    /* Update simulation on CPU */
    for (int32_t i = 0; i < count; ++i) {
        Particle* p = &parts[i];
        p->vy  += GRAVITY * dt;
        p->x   += p->vx * dt;
        p->y   += p->vy * dt;
        p->life -= dt;

        /* Respawn when dead or off-screen */
        if (p->life <= 0.0f || p->y > 1.05f) {
            uint32_t r = (uint32_t)(i * 2654435761u + 9999991u);
            r ^= r << 13; r ^= r >> 17; r ^= r << 5; float r0 = (float)(r & 0x7FFF) / 32768.0f;
            r ^= r << 13; r ^= r >> 17; r ^= r << 5; float r1 = (float)(r & 0x7FFF) / 32768.0f;
            r ^= r << 13; r ^= r >> 17; r ^= r << 5; float r2 = (float)(r & 0x7FFF) / 32768.0f;
            r ^= r << 13; r ^= r >> 17; r ^= r << 5; float r3 = (float)(r & 0x7FFF) / 32768.0f;
            r ^= r << 13; r ^= r >> 17; r ^= r << 5; float r4 = (float)(r & 0x7FFF) / 32768.0f;
            p->x    = (r0 - 0.5f) * 0.2f;
            p->y    = 0.9f;
            p->vx   = (r1 - 0.5f) * 0.5f;
            p->vy   = -(0.3f + r2 * 0.5f);
            p->r    = 0.8f + r3 * 0.2f;
            p->g    = 0.3f + r4 * 0.3f;
            /* p->b stays 0.1f */
            p->life = 0.5f + r2 * 1.5f;   /* shorter lifespan after respawn */
        }
    }

    /* Write updated positions & colours into mapped vertex buffer.
     * NOTE: With 2 frames in-flight, writing to a single persistently-mapped
     * buffer here is safe because begin_frame waits on the in-flight fence
     * for the current frame before we modify it.  A production solution would
     * use per-frame shadow buffers or a ring-buffer. */
    GPUParticle* gpu = (GPUParticle*)a->particle_mapped;
    for (int32_t i = 0; i < count; ++i) {
        gpu[i].pos[0]   = parts[i].x;
        gpu[i].pos[1]   = parts[i].y;
        gpu[i].color[0] = parts[i].r;
        gpu[i].color[1] = parts[i].g;
        gpu[i].color[2] = parts[i].b;
    }

    /* Record draw commands */
    VkDeviceSize offset = 0;
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, a->particle_pipeline);
    vkCmdBindVertexBuffers(cb, 0, 1, &a->particle_vbo, &offset);
    vkCmdDraw(cb, (uint32_t)count, 1, 0, 0);
}

/* ================================================================== */
/*  OFFSCREEN PATH                                                     */
/* ================================================================== */

static int create_offscreen_rendertarget(XvkApp* a)
{
    VkImageCreateInfo ici = {0};
    ici.sType         = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ici.imageType     = VK_IMAGE_TYPE_2D;
    ici.format        = VK_FORMAT_B8G8R8A8_UNORM;
    ici.extent.width  = (uint32_t)a->offs_w;
    ici.extent.height = (uint32_t)a->offs_h;
    ici.extent.depth  = 1;
    ici.mipLevels     = 1;
    ici.arrayLayers   = 1;
    ici.samples       = VK_SAMPLE_COUNT_1_BIT;
    ici.tiling        = VK_IMAGE_TILING_OPTIMAL;
    ici.usage         = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT |
                        VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    VkResult res = vkCreateImage(a->device, &ici, NULL, &a->offs_image);
    if (res != VK_SUCCESS) { xvk_set_error_fmt("offscreen vkCreateImage: %d", (int)res); return 0; }

    VkMemoryRequirements mr;
    vkGetImageMemoryRequirements(a->device, a->offs_image, &mr);
    uint32_t mi = find_memory_type(&a->mem_props, mr.memoryTypeBits,
                                    VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (mi == UINT32_MAX) { xvk_set_error("no device mem for offscreen image"); return 0; }

    VkMemoryAllocateInfo mai = {0};
    mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    mai.allocationSize   = mr.size;
    mai.memoryTypeIndex  = mi;
    res = vkAllocateMemory(a->device, &mai, NULL, &a->offs_memory);
    if (res != VK_SUCCESS) { xvk_set_error_fmt("offscreen vkAllocateMemory: %d", (int)res); return 0; }
    vkBindImageMemory(a->device, a->offs_image, a->offs_memory, 0);

    VkImageViewCreateInfo ivci = {0};
    ivci.sType    = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    ivci.image    = a->offs_image;
    ivci.viewType = VK_IMAGE_VIEW_TYPE_2D;
    ivci.format   = VK_FORMAT_B8G8R8A8_UNORM;
    ivci.subresourceRange.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
    ivci.subresourceRange.baseMipLevel   = 0;
    ivci.subresourceRange.levelCount     = 1;
    ivci.subresourceRange.baseArrayLayer = 0;
    ivci.subresourceRange.layerCount     = 1;
    res = vkCreateImageView(a->device, &ivci, NULL, &a->offs_image_view);
    if (res != VK_SUCCESS) { xvk_set_error_fmt("offscreen vkCreateImageView: %d", (int)res); return 0; }
    return 1;
}

static VkRenderPass create_offscreen_render_pass(VkDevice dev, VkFormat fmt)
{
    VkAttachmentDescription att = {0};
    att.format         = fmt;
    att.samples        = VK_SAMPLE_COUNT_1_BIT;
    att.loadOp         = VK_ATTACHMENT_LOAD_OP_CLEAR;
    att.storeOp        = VK_ATTACHMENT_STORE_OP_STORE;
    att.stencilLoadOp  = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
    att.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    att.initialLayout  = VK_IMAGE_LAYOUT_UNDEFINED;
    att.finalLayout    = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;  /* for readback */

    VkAttachmentReference col_ref = {0};
    col_ref.attachment = 0;
    col_ref.layout     = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

    VkSubpassDescription subpass = {0};
    subpass.pipelineBindPoint    = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount = 1;
    subpass.pColorAttachments    = &col_ref;

    VkSubpassDependency dep = {0};
    dep.srcSubpass    = VK_SUBPASS_EXTERNAL;
    dep.dstSubpass    = 0;
    dep.srcStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dep.dstStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    dep.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

    VkRenderPassCreateInfo rpci = {0};
    rpci.sType           = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    rpci.attachmentCount = 1;
    rpci.pAttachments    = &att;
    rpci.subpassCount    = 1;
    rpci.pSubpasses      = &subpass;
    rpci.dependencyCount = 1;
    rpci.pDependencies   = &dep;

    VkRenderPass rp = VK_NULL_HANDLE;
    VkResult res = vkCreateRenderPass(dev, &rpci, NULL, &rp);
    if (res != VK_SUCCESS) { xvk_set_error_fmt("offscreen vkCreateRenderPass: %d", (int)res); return VK_NULL_HANDLE; }
    return rp;
}

/* ---- xvk_offscreen_create ---- */
int64_t xvk_offscreen_create(int32_t width, int32_t height)
{
    XvkApp* a = (XvkApp*)calloc(1, sizeof(XvkApp));
    if (!a) { xvk_set_error("calloc failed"); return 0; }

    /* GLFW not strictly needed for headless, but we init for consistency */
    if (!glfwInit()) {
        xvk_set_error("glfwInit failed");
        free(a);
        return 0;
    }

    /* Instance (headless — GLFW ext list is fine; it just returns platform
     * extensions which we need for later if we show window, but for offscreen
     * they're harmless.) */
    int have_val = 0;
    a->instance = create_instance("XIOM Offscreen", &have_val);
    if (!a->instance) { glfwTerminate(); free(a); return 0; }

    /* Pick physical device (VK_NULL_HANDLE surface = headless mode) */
    if (!pick_physical_device(a->instance, VK_NULL_HANDLE,
                               &a->phys_dev, &a->device_type))
        goto offs_fail;

    /* Queue families (headless — no surface needed for present) */
    if (!find_queue_families(a->phys_dev, VK_NULL_HANDLE,
                              &a->graphics_family, &a->present_family))
        goto offs_fail;
    a->present_family = a->graphics_family; /* headless: reuse graphics */

    /* Logical device (no swapchain extension needed) */
    {
        float q_priority = 1.0f;
        VkDeviceQueueCreateInfo qci = {0};
        qci.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        qci.queueFamilyIndex = a->graphics_family;
        qci.queueCount = 1;
        qci.pQueuePriorities = &q_priority;

        VkDeviceCreateInfo dci = {0};
        dci.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        dci.queueCreateInfoCount = 1;
        dci.pQueueCreateInfos = &qci;
        dci.pEnabledFeatures = &(VkPhysicalDeviceFeatures){0};

        VkResult res = vkCreateDevice(a->phys_dev, &dci, NULL, &a->device);
        if (res != VK_SUCCESS) {
            xvk_set_error_fmt("offscreen vkCreateDevice failed: %d", (int)res);
            goto offs_fail;
        }
    }

    vkGetDeviceQueue(a->device, a->graphics_family, 0, &a->graphics_queue);
    a->present_queue = a->graphics_queue;
    vkGetPhysicalDeviceMemoryProperties(a->phys_dev, &a->mem_props);

    a->offs_w = width;
    a->offs_h = height;

    /* Offscreen colour target */
    if (!create_offscreen_rendertarget(a)) goto offs_fail;

    /* Offscreen render pass (colour-only, final layout = TRANSFER_SRC) */
    a->offs_render_pass = create_offscreen_render_pass(a->device,
                                                         VK_FORMAT_B8G8R8A8_UNORM);
    if (!a->offs_render_pass) goto offs_fail;

    /* Offscreen framebuffer */
    {
        VkFramebufferCreateInfo fci = {0};
        fci.sType           = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
        fci.renderPass      = a->offs_render_pass;
        fci.attachmentCount = 1;
        fci.pAttachments    = &a->offs_image_view;
        fci.width           = (uint32_t)width;
        fci.height          = (uint32_t)height;
        fci.layers          = 1;
        VkResult res = vkCreateFramebuffer(a->device, &fci, NULL,
                                            &a->offs_framebuffer);
        if (res != VK_SUCCESS) {
            xvk_set_error_fmt("offscreen vkCreateFramebuffer: %d", (int)res);
            goto offs_fail;
        }
    }

    /* Shader modules */
    VkShaderModule tri_vert = create_shader_module(a->device,
        xvk_triangle_vert_spv, xvk_triangle_vert_spv_len);
    VkShaderModule tri_frag = create_shader_module(a->device,
        xvk_triangle_frag_spv, xvk_triangle_frag_spv_len);
    if (!tri_vert || !tri_frag) {
        if (tri_vert) vkDestroyShaderModule(a->device, tri_vert, NULL);
        if (tri_frag) vkDestroyShaderModule(a->device, tri_frag, NULL);
        goto offs_fail;
    }

    /* Pipeline layout (shared — same push constant as 2D) */
    VkPushConstantRange pc_range = {0};
    pc_range.stageFlags = VK_SHADER_STAGE_VERTEX_BIT;
    pc_range.offset     = 0;
    pc_range.size       = 16;
    a->pipe_layout_2d = create_pipeline_layout(a->device, &pc_range, 1);
    if (!a->pipe_layout_2d) {
        vkDestroyShaderModule(a->device, tri_vert, NULL);
        vkDestroyShaderModule(a->device, tri_frag, NULL);
        goto offs_fail;
    }

    /* Offscreen 2D pipeline (no depth test) */
    a->offs_pipeline = create_graphics_pipeline(a->device,
        a->pipe_layout_2d, a->offs_render_pass,
        tri_vert, tri_frag, width, height, 0);
    vkDestroyShaderModule(a->device, tri_vert, NULL);
    vkDestroyShaderModule(a->device, tri_frag, NULL);

    if (!a->offs_pipeline) goto offs_fail;

    /* Command pool */
    a->cmd_pool = create_cmd_pool(a->device, a->graphics_family);
    if (!a->cmd_pool) goto offs_fail;

    /* One command buffer */
    if (!allocate_cmd_buffers(a->device, a->cmd_pool, &a->offs_cmd, 1))
        goto offs_fail;

    /* Readback buffer (host-visible, coherent) */
    VkDeviceSize buf_size = (VkDeviceSize)(width * height * 4);
    VkBufferCreateInfo bci = {0};
    bci.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bci.size  = buf_size;
    bci.usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    bci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    VkResult res = vkCreateBuffer(a->device, &bci, NULL, &a->offs_readback);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("offscreen vkCreateBuffer: %d", (int)res);
        goto offs_fail;
    }

    VkMemoryRequirements bmr;
    vkGetBufferMemoryRequirements(a->device, a->offs_readback, &bmr);
    uint32_t bmi = find_memory_type(&a->mem_props, bmr.memoryTypeBits,
                                     VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                                     VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (bmi == UINT32_MAX) { xvk_set_error("no host mem for readback"); goto offs_fail; }

    VkMemoryAllocateInfo bmai = {0};
    bmai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    bmai.allocationSize  = bmr.size;
    bmai.memoryTypeIndex = bmi;
    res = vkAllocateMemory(a->device, &bmai, NULL, &a->offs_readback_mem);
    if (res != VK_SUCCESS) { xvk_set_error_fmt("offscreen alloc readback mem: %d", (int)res); goto offs_fail; }
    vkBindBufferMemory(a->device, a->offs_readback, a->offs_readback_mem, 0);

    /* Persistent map */
    vkMapMemory(a->device, a->offs_readback_mem, 0, buf_size, 0, &a->offs_mapped);

    /* Fence */
    VkFenceCreateInfo fci = {0};
    fci.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
    res = vkCreateFence(a->device, &fci, NULL, &a->offs_fence);
    if (res != VK_SUCCESS) { xvk_set_error_fmt("offscreen vkCreateFence: %d", (int)res); goto offs_fail; }

    a->magic        = XVK_MAGIC;
    a->is_offscreen = 1;
    a->clear_r = a->clear_g = a->clear_b = 0.0f;
    xvk_set_error("");
    return xvk_to_handle(a);

offs_fail:
    xvk_app_cleanup_internal(a);
    free(a);
    return 0;
}

/* ---- xvk_offscreen_render_triangle ---- */
int32_t xvk_offscreen_render_triangle(int64_t app_h, float r, float g, float b)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->is_offscreen) return -1;

    /* Wait for any previous offscreen work */
    if (a->offs_fence) {
        vkWaitForFences(a->device, 1, &a->offs_fence, VK_TRUE, UINT64_MAX);
        vkResetFences(a->device, 1, &a->offs_fence);
    }

    VkCommandBuffer cb = a->offs_cmd;
    vkResetCommandBuffer(cb, 0);

    VkCommandBufferBeginInfo cbbi = {0};
    cbbi.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    cbbi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    if (vkBeginCommandBuffer(cb, &cbbi) != VK_SUCCESS) {
        xvk_set_error("offscreen vkBeginCommandBuffer failed");
        return 0;
    }

    VkClearValue clear;
    clear.color.float32[0] = 0.0f;
    clear.color.float32[1] = 0.0f;
    clear.color.float32[2] = 0.0f;
    clear.color.float32[3] = 1.0f;

    VkRenderPassBeginInfo rpbi = {0};
    rpbi.sType       = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    rpbi.renderPass  = a->offs_render_pass;
    rpbi.framebuffer = a->offs_framebuffer;
    rpbi.renderArea.offset.x = 0;
    rpbi.renderArea.offset.y = 0;
    rpbi.renderArea.extent.width  = (uint32_t)a->offs_w;
    rpbi.renderArea.extent.height = (uint32_t)a->offs_h;
    rpbi.clearValueCount     = 1;
    rpbi.pClearValues        = &clear;
    vkCmdBeginRenderPass(cb, &rpbi, VK_SUBPASS_CONTENTS_INLINE);

    /* Bind pipeline and draw */
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, a->offs_pipeline);
    float colour[4] = { r, g, b, 1.0f };
    vkCmdPushConstants(cb, a->pipe_layout_2d, VK_SHADER_STAGE_VERTEX_BIT,
                       0, 16, colour);
    vkCmdDraw(cb, 3, 1, 0, 0);

    vkCmdEndRenderPass(cb);

    /* Transition image to TRANSFER_SRC (render pass final layout already
     * does this, but we need to ensure the barrier is visible to copy).
     * Since finalLayout = TRANSFER_SRC_OPTIMAL in the render pass, the
     * implicit barrier at render pass end handles this. */
    /* Issue an explicit memory barrier for the copy command anyway. */
    VkImageMemoryBarrier imb = {0};
    imb.sType               = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    imb.srcAccessMask       = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
    imb.dstAccessMask       = VK_ACCESS_TRANSFER_READ_BIT;
    imb.oldLayout           = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    imb.newLayout           = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    imb.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    imb.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    imb.image               = a->offs_image;
    imb.subresourceRange.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
    imb.subresourceRange.baseMipLevel   = 0;
    imb.subresourceRange.levelCount     = 1;
    imb.subresourceRange.baseArrayLayer = 0;
    imb.subresourceRange.layerCount     = 1;
    vkCmdPipelineBarrier(cb,
        VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        VK_PIPELINE_STAGE_TRANSFER_BIT,
        0, 0, NULL, 0, NULL, 1, &imb);

    /* Copy image to buffer */
    VkBufferImageCopy bic = {0};
    bic.bufferOffset      = 0;
    bic.bufferRowLength   = 0;
    bic.bufferImageHeight = 0;
    bic.imageSubresource.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
    bic.imageSubresource.mipLevel       = 0;
    bic.imageSubresource.baseArrayLayer = 0;
    bic.imageSubresource.layerCount     = 1;
    bic.imageOffset.x = 0;
    bic.imageOffset.y = 0;
    bic.imageOffset.z = 0;
    bic.imageExtent.width  = (uint32_t)a->offs_w;
    bic.imageExtent.height = (uint32_t)a->offs_h;
    bic.imageExtent.depth  = 1;
    vkCmdCopyImageToBuffer(cb, a->offs_image,
                           VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                           a->offs_readback, 1, &bic);

    if (vkEndCommandBuffer(cb) != VK_SUCCESS) {
        xvk_set_error("offscreen vkEndCommandBuffer failed");
        return 0;
    }

    VkSubmitInfo si = {0};
    si.sType              = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    si.commandBufferCount = 1;
    si.pCommandBuffers    = &cb;
    VkResult res = vkQueueSubmit(a->graphics_queue, 1, &si, a->offs_fence);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("offscreen vkQueueSubmit failed: %d", (int)res);
        return 0;
    }

    /* Wait for completion */
    vkWaitForFences(a->device, 1, &a->offs_fence, VK_TRUE, UINT64_MAX);
    return 1;
}

/* ---- xvk_offscreen_pixel ---- */
uint32_t xvk_offscreen_pixel(int64_t app_h, int32_t x, int32_t y)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->is_offscreen || !a->offs_mapped) return 0;
    if (x < 0 || x >= a->offs_w || y < 0 || y >= a->offs_h) return 0;

    /* Buffer stores B8G8R8A8_UNORM.  Read as uint32. */
    uint32_t* pixels = (uint32_t*)a->offs_mapped;
    uint32_t bgra = pixels[(uint32_t)y * (uint32_t)a->offs_w + (uint32_t)x];

    /* Convert BGRA -> RGBA: 0xBBGGRRAA -> 0xRRGGBBAA */
    uint32_t b = (bgra >> 0)  & 0xFF;
    uint32_t g = (bgra >> 8)  & 0xFF;
    uint32_t rv = (bgra >> 16) & 0xFF;
    uint32_t av = (bgra >> 24) & 0xFF;
    return (rv << 24) | (g << 16) | (b << 8) | av;
}

/* ---- xvk_offscreen_hash ---- */
uint64_t xvk_offscreen_hash(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->is_offscreen || !a->offs_mapped) return 0;

    uint64_t hash = 0xCBF29CE484222325ULL;  /* FNV-1a offset basis */
    uint32_t count = (uint32_t)(a->offs_w * a->offs_h * 4);
    unsigned char* buf = (unsigned char*)a->offs_mapped;

    for (uint32_t i = 0; i < count; ++i) {
        hash ^= (uint64_t)buf[i];
        hash *= 0x100000001B3ULL;           /* FNV-1a prime */
    }
    return hash;
}

/* ---- xvk_offscreen_destroy ---- */
void xvk_offscreen_destroy(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return;
    xvk_app_cleanup_internal(a);
    free(a);
}

/* ================================================================== */
/*  PHASE 1 — Production Bridge Implementations                       */
/* ================================================================== */

/* ------------------------------------------------------------------ */
/*  Resource handle helpers                                            */
/* ------------------------------------------------------------------ */

#define XVK_HANDLE_IMPL(T, magic, field)                                        \
    static T* xvk_##field##_from_handle(int64_t h) {                            \
        if (h == 0) return NULL;                                                \
        T* p = (T*)(intptr_t)h;                                                  \
        if (p->magic != magic) return NULL;                                     \
        return p;                                                               \
    }                                                                           \
    static int64_t xvk_##field##_to_handle(T* p) {                              \
        return p ? (int64_t)(intptr_t)p : 0;                                    \
    }

XVK_HANDLE_IMPL(XvkBuffer,       XVK_BUFFER_MAGIC,       buffer)
XVK_HANDLE_IMPL(XvkImage,        XVK_IMAGE_MAGIC,        image)
XVK_HANDLE_IMPL(XvkImageView,    XVK_IMAGEVIEW_MAGIC,    view)
XVK_HANDLE_IMPL(XvkSampler,      XVK_SAMPLER_MAGIC,      sampler)
XVK_HANDLE_IMPL(XvkShaderModule, XVK_SHADER_MAGIC,       shader)
XVK_HANDLE_IMPL(XvkPipeline,     XVK_PIPELINE_MAGIC,     pipeline)
XVK_HANDLE_IMPL(XvkPipelineLayout, XVK_PLAYOUT_MAGIC,    playout)
XVK_HANDLE_IMPL(XvkDescSetLayout,  XVK_DESC_LAYOUT_MAGIC,  dslayout)
XVK_HANDLE_IMPL(XvkDescPool,  XVK_DESC_POOL_MAGIC,  descpool)
XVK_HANDLE_IMPL(XvkDescSet,   XVK_DESC_SET_MAGIC,   descset)
XVK_HANDLE_IMPL(XvkRenderPass,  XVK_RENDERPASS_MAGIC,  rp)
XVK_HANDLE_IMPL(XvkFramebuffer, XVK_FRAMEBUFFER_MAGIC, fb)

/* ------------------------------------------------------------------ */
/*  Format & enum helpers                                              */
/* ------------------------------------------------------------------ */
static VkFormat xvk_map_format(int32_t f) {
    switch (f) {
        case 1: return VK_FORMAT_R8G8B8A8_UNORM;
        case 2: return VK_FORMAT_R8G8B8A8_SRGB;
        case 3: return VK_FORMAT_R32G32B32A32_SFLOAT;
        case 4: return VK_FORMAT_R32_SFLOAT;
        case 5: return VK_FORMAT_D32_SFLOAT;
        default: return VK_FORMAT_R8G8B8A8_UNORM;
    }
}

static VkImageUsageFlags xvk_map_image_usage(int32_t u) {
    VkImageUsageFlags f = 0;
    if (u & 1)  f |= VK_IMAGE_USAGE_SAMPLED_BIT;
    if (u & 2)  f |= VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    if (u & 4)  f |= VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT;
    if (u & 8)  f |= VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    if (u & 16) f |= VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    if (u & 32) f |= VK_IMAGE_USAGE_STORAGE_BIT;
    return f ? f : VK_IMAGE_USAGE_SAMPLED_BIT;
}

static VkBufferUsageFlags xvk_map_buffer_usage(int32_t u) {
    VkBufferUsageFlags f = 0;
    if (u & 1) f |= VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
    if (u & 2) f |= VK_BUFFER_USAGE_INDEX_BUFFER_BIT;
    if (u & 4) f |= VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT;
    if (u & 8) f |= VK_BUFFER_USAGE_STORAGE_BUFFER_BIT;
    if (u & 16) f |= VK_BUFFER_USAGE_TRANSFER_SRC_BIT;
    if (u & 32) f |= VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    return f ? f : VK_BUFFER_USAGE_VERTEX_BUFFER_BIT;
}

static VkMemoryPropertyFlags xvk_map_memory_props(int32_t m) {
    if (m == 1) return VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    if (m == 2) return VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    if (m == 3) return VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_CACHED_BIT;
    return VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
}

static VkFilter xvk_map_filter(int32_t f) { return f == 1 ? VK_FILTER_LINEAR : VK_FILTER_NEAREST; }
static VkSamplerAddressMode xvk_map_address(int32_t a) {
    if (a == 1) return VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE;
    if (a == 2) return VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_BORDER;
    return VK_SAMPLER_ADDRESS_MODE_REPEAT;
}
static VkSamplerMipmapMode xvk_map_mip(int32_t m) { return m == 1 ? VK_SAMPLER_MIPMAP_MODE_LINEAR : VK_SAMPLER_MIPMAP_MODE_NEAREST; }

static VkPrimitiveTopology xvk_map_topology(int32_t t) {
    if (t == 1) return VK_PRIMITIVE_TOPOLOGY_POINT_LIST;
    if (t == 2) return VK_PRIMITIVE_TOPOLOGY_LINE_LIST;
    return VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
}

static VkFormat xvk_map_vertex_format(int32_t f) {
    switch (f) {
        case 1: return VK_FORMAT_R32G32_SFLOAT;
        case 2: return VK_FORMAT_R32G32B32_SFLOAT;
        case 3: return VK_FORMAT_R32G32B32A32_SFLOAT;
        case 4: return VK_FORMAT_R8G8B8A8_UNORM;
        case 5: return VK_FORMAT_R32_SINT;
        default: return VK_FORMAT_R32G32B32A32_SFLOAT;
    }
}

static VkIndexType xvk_map_index_type(int32_t t) {
    return t == 1 ? VK_INDEX_TYPE_UINT32 : VK_INDEX_TYPE_UINT16;
}

static VkDescriptorType xvk_map_desc_type(int32_t t) {
    if (t == 1) return VK_DESCRIPTOR_TYPE_STORAGE_BUFFER;
    if (t == 2) return VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    if (t == 3) return VK_DESCRIPTOR_TYPE_STORAGE_IMAGE;
    return VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER;
}

static VkShaderStageFlags xvk_map_stage_flags(int32_t s) {
    VkShaderStageFlags f = 0;
    if (s & 1) f |= VK_SHADER_STAGE_VERTEX_BIT;
    if (s & 2) f |= VK_SHADER_STAGE_FRAGMENT_BIT;
    if (s & 4) f |= VK_SHADER_STAGE_COMPUTE_BIT;
    return f ? f : (VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT);
}

static VkImageLayout xvk_map_image_layout(int32_t l) {
    switch (l) {
        case 1: return VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        case 2: return VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
        case 3: return VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        case 4: return VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        case 5: return VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
        case 6: return VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        default: return VK_IMAGE_LAYOUT_UNDEFINED;
    }
}

static VkImageAspectFlags xvk_map_aspect(int32_t a) {
    if (a == 2) return VK_IMAGE_ASPECT_DEPTH_BIT;
    return VK_IMAGE_ASPECT_COLOR_BIT;
}

/* ------------------------------------------------------------------ */
/*  BUFFERS                                                            */
/* ------------------------------------------------------------------ */
int64_t xvk_buffer_create(int64_t app_h, int64_t size, int32_t usage, int32_t memory)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || size <= 0) return 0;

    XvkBuffer* b = (XvkBuffer*)calloc(1, sizeof(XvkBuffer));
    if (!b) { xvk_set_error("calloc buffer"); return 0; }

    VkBufferCreateInfo bci = {0};
    bci.sType       = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bci.size        = (VkDeviceSize)size;
    bci.usage       = xvk_map_buffer_usage(usage);
    bci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;

    VkResult res = vkCreateBuffer(a->device, &bci, NULL, &b->buffer);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateBuffer: %d", (int)res);
        free(b); return 0;
    }

    VkMemoryRequirements mr;
    vkGetBufferMemoryRequirements(a->device, b->buffer, &mr);
    VkMemoryPropertyFlags props = xvk_map_memory_props(memory);
    uint32_t mi = find_memory_type(&a->mem_props, mr.memoryTypeBits, props);
    if (mi == UINT32_MAX) {
        xvk_set_error("no suitable memory type for buffer");
        vkDestroyBuffer(a->device, b->buffer, NULL); free(b); return 0;
    }

    VkMemoryAllocateInfo mai = {0};
    mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    mai.allocationSize  = mr.size;
    mai.memoryTypeIndex = mi;
    res = vkAllocateMemory(a->device, &mai, NULL, &b->memory);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkAllocateMemory(buf): %d", (int)res);
        vkDestroyBuffer(a->device, b->buffer, NULL); free(b); return 0;
    }
    vkBindBufferMemory(a->device, b->buffer, b->memory, 0);

    b->size  = (VkDeviceSize)size;
    b->magic = XVK_BUFFER_MAGIC;
    return xvk_buffer_to_handle(b);
}

void xvk_buffer_destroy(int64_t app_h, int64_t buf_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    if (!a || !b) return;
    if (b->mapped && b->mapped_ptr) vkUnmapMemory(a->device, b->memory);
    if (b->buffer)  vkDestroyBuffer(a->device, b->buffer, NULL);
    if (b->memory)  vkFreeMemory(a->device, b->memory, NULL);
    b->magic = 0;
    free(b);
}

int64_t xvk_buffer_size(int64_t app_h, int64_t buf_h)
{
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    (void)app_h;
    return b ? (int64_t)b->size : 0;
}

int64_t xvk_buffer_map(int64_t app_h, int64_t buf_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    if (!a || !b) return 0;
    if (b->mapped) return 1;
    VkResult res = vkMapMemory(a->device, b->memory, 0, b->size, 0, &b->mapped_ptr);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkMapMemory: %d", (int)res);
        return 0;
    }
    b->mapped = 1;
    return 1;
}

void xvk_buffer_unmap(int64_t app_h, int64_t buf_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    if (!a || !b || !b->mapped) return;
    vkUnmapMemory(a->device, b->memory);
    b->mapped = 0;
    b->mapped_ptr = NULL;
}

void xvk_buffer_write(int64_t app_h, int64_t buf_h, int64_t offset,
                       const void* data, int64_t data_size)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    if (!a || !b || !b->mapped_ptr) return;
    if (offset + data_size > (int64_t)b->size) return;
    memcpy((char*)b->mapped_ptr + offset, data, (size_t)data_size);
}

void xvk_buffer_read(int64_t app_h, int64_t buf_h, int64_t offset,
                      void* out, int64_t out_size)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    if (!a || !b || !b->mapped_ptr) return;
    if (offset + out_size > (int64_t)b->size) return;
    memcpy(out, (char*)b->mapped_ptr + offset, (size_t)out_size);
}

/* ------------------------------------------------------------------ */
/*  IMAGES & VIEWS                                                     */
/* ------------------------------------------------------------------ */
int64_t xvk_image_create_2d(int64_t app_h, int32_t width, int32_t height,
                            int32_t format, int32_t usage, int32_t mip_levels)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || width <= 0 || height <= 0) return 0;

    XvkImage* img = (XvkImage*)calloc(1, sizeof(XvkImage));
    if (!img) { xvk_set_error("calloc image"); return 0; }

    VkImageCreateInfo ici = {0};
    ici.sType         = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
    ici.imageType     = VK_IMAGE_TYPE_2D;
    ici.format        = xvk_map_format(format);
    ici.extent.width  = (uint32_t)width;
    ici.extent.height = (uint32_t)height;
    ici.extent.depth  = 1;
    ici.mipLevels     = (uint32_t)(mip_levels > 0 ? mip_levels : 1);
    ici.arrayLayers   = 1;
    ici.samples       = VK_SAMPLE_COUNT_1_BIT;
    ici.tiling        = VK_IMAGE_TILING_OPTIMAL;
    ici.usage         = xvk_map_image_usage(usage);
    ici.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;

    VkResult res = vkCreateImage(a->device, &ici, NULL, &img->image);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateImage: %d", (int)res);
        free(img); return 0;
    }

    VkMemoryRequirements mr;
    vkGetImageMemoryRequirements(a->device, img->image, &mr);
    uint32_t mi = find_memory_type(&a->mem_props, mr.memoryTypeBits,
                                    VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);
    if (mi == UINT32_MAX) {
        xvk_set_error("no device-local memory for image");
        vkDestroyImage(a->device, img->image, NULL); free(img); return 0;
    }

    VkMemoryAllocateInfo mai = {0};
    mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    mai.allocationSize  = mr.size;
    mai.memoryTypeIndex = mi;
    res = vkAllocateMemory(a->device, &mai, NULL, &img->memory);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkAllocateMemory(img): %d", (int)res);
        vkDestroyImage(a->device, img->image, NULL); free(img); return 0;
    }
    vkBindImageMemory(a->device, img->image, img->memory, 0);

    img->format     = xvk_map_format(format);
    img->extent.width  = (uint32_t)width;
    img->extent.height = (uint32_t)height;
    img->mip_levels = (uint32_t)(mip_levels > 0 ? mip_levels : 1);
    img->magic      = XVK_IMAGE_MAGIC;
    return xvk_image_to_handle(img);
}

void xvk_image_destroy(int64_t app_h, int64_t img_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkImage* img = xvk_image_from_handle(img_h);
    if (!a || !img) return;
    if (img->image)  vkDestroyImage(a->device, img->image, NULL);
    if (img->memory) vkFreeMemory(a->device, img->memory, NULL);
    img->magic = 0;
    free(img);
}

int64_t xvk_image_view_create(int64_t app_h, int64_t img_h, int32_t format, int32_t aspect)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkImage* img = xvk_image_from_handle(img_h);
    if (!a || !img) return 0;

    XvkImageView* v = (XvkImageView*)calloc(1, sizeof(XvkImageView));
    if (!v) { xvk_set_error("calloc view"); return 0; }

    VkImageViewCreateInfo ivci = {0};
    ivci.sType    = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
    ivci.image    = img->image;
    ivci.viewType = VK_IMAGE_VIEW_TYPE_2D;
    ivci.format   = (format > 0) ? xvk_map_format(format) : img->format;
    ivci.subresourceRange.aspectMask     = xvk_map_aspect(aspect);
    ivci.subresourceRange.baseMipLevel   = 0;
    ivci.subresourceRange.levelCount     = img->mip_levels;
    ivci.subresourceRange.baseArrayLayer = 0;
    ivci.subresourceRange.layerCount     = 1;

    VkResult res = vkCreateImageView(a->device, &ivci, NULL, &v->view);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateImageView: %d", (int)res);
        free(v); return 0;
    }
    v->magic = XVK_IMAGEVIEW_MAGIC;
    return xvk_view_to_handle(v);
}

void xvk_image_view_destroy(int64_t app_h, int64_t view_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkImageView* v = xvk_view_from_handle(view_h);
    if (!a || !v) return;
    if (v->view) vkDestroyImageView(a->device, v->view, NULL);
    v->magic = 0;
    free(v);
}

/* ------------------------------------------------------------------ */
/*  SAMPLERS                                                           */
/* ------------------------------------------------------------------ */
int64_t xvk_sampler_create(int64_t app_h, int32_t filter, int32_t address_u,
                           int32_t address_v, int32_t mip_mode, float max_lod)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return 0;

    XvkSampler* s = (XvkSampler*)calloc(1, sizeof(XvkSampler));
    if (!s) { xvk_set_error("calloc sampler"); return 0; }

    VkSamplerCreateInfo sci = {0};
    sci.sType                   = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
    sci.magFilter               = xvk_map_filter(filter);
    sci.minFilter               = xvk_map_filter(filter);
    sci.addressModeU            = xvk_map_address(address_u);
    sci.addressModeV            = xvk_map_address(address_v);
    sci.addressModeW            = xvk_map_address(address_u);
    sci.mipmapMode              = xvk_map_mip(mip_mode);
    sci.anisotropyEnable        = VK_FALSE;
    sci.maxAnisotropy           = 1.0f;
    sci.borderColor             = VK_BORDER_COLOR_FLOAT_OPAQUE_BLACK;
    sci.unnormalizedCoordinates = VK_FALSE;
    sci.compareEnable           = VK_FALSE;
    sci.compareOp               = VK_COMPARE_OP_ALWAYS;
    sci.minLod                  = 0.0f;
    sci.maxLod                  = max_lod > 0.0f ? max_lod : VK_LOD_CLAMP_NONE;
    sci.mipLodBias              = 0.0f;

    VkResult res = vkCreateSampler(a->device, &sci, NULL, &s->sampler);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateSampler: %d", (int)res);
        free(s); return 0;
    }
    s->magic = XVK_SAMPLER_MAGIC;
    return xvk_sampler_to_handle(s);
}

void xvk_sampler_destroy(int64_t app_h, int64_t sampler_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkSampler* s = xvk_sampler_from_handle(sampler_h);
    if (!a || !s) return;
    if (s->sampler) vkDestroySampler(a->device, s->sampler, NULL);
    s->magic = 0;
    free(s);
}

/* ------------------------------------------------------------------ */
/*  SHADER MODULES                                                     */
/* ------------------------------------------------------------------ */
int64_t xvk_shader_create(int64_t app_h, const unsigned int* code, int32_t code_size)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !code || code_size <= 0) return 0;
    return (int64_t)(intptr_t)create_shader_module(a->device, code, (unsigned int)code_size);
}

int64_t xvk_shader_create_named(int64_t app_h, const char* name)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !name) return 0;

    /* Lookup table mapping name strings to embedded SPIR-V arrays.
     * Automatically extended by build.ps1 / build.sh when new shaders are added. */
    static const struct {
        const char* name;
        const unsigned int* code;
        unsigned int size;
    } table[] = {
        {"triangle_vert",      xvk_triangle_vert_spv,      xvk_triangle_vert_spv_len},
        {"triangle_frag",      xvk_triangle_frag_spv,      xvk_triangle_frag_spv_len},
        {"cube_vert",          xvk_cube_vert_spv,          xvk_cube_vert_spv_len},
        {"cube_frag",          xvk_cube_frag_spv,          xvk_cube_frag_spv_len},
        {"quad_vert",          xvk_quad_vert_spv,          xvk_quad_vert_spv_len},
        {"quad_frag",          xvk_quad_frag_spv,          xvk_quad_frag_spv_len},
        {"particle_vert",      xvk_particle_vert_spv,      xvk_particle_vert_spv_len},
        {"particle_frag",      xvk_particle_frag_spv,      xvk_particle_frag_spv_len},
        {"particle_render_vert", xvk_particle_render_vert_spv, xvk_particle_render_vert_spv_len},
        {"particle_render_frag", xvk_particle_render_frag_spv, xvk_particle_render_frag_spv_len},
        {"compute_particles",  xvk_compute_particles_spv,  xvk_compute_particles_spv_len},
        {"texture_quad_vert",  xvk_texture_quad_vert_spv,  xvk_texture_quad_vert_spv_len},
        {"texture_quad_frag",  xvk_texture_quad_frag_spv,  xvk_texture_quad_frag_spv_len},
        {"uniform_cube_vert",  xvk_uniform_cube_vert_spv,  xvk_uniform_cube_vert_spv_len},
        {"uniform_cube_frag",  xvk_uniform_cube_frag_spv,  xvk_uniform_cube_frag_spv_len},
    };
    int n = sizeof(table) / sizeof(table[0]);

    for (int i = 0; i < n; ++i) {
        if (strcmp(table[i].name, name) == 0 && table[i].code && table[i].size > 0) {
            return (int64_t)(intptr_t)create_shader_module(a->device, table[i].code, table[i].size);
        }
    }
    xvk_set_error_fmt("shader_create_named: unknown shader '%s'", name);
    return 0;
}

void xvk_shader_destroy(int64_t app_h, int64_t shader_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !shader_h) return;
    VkShaderModule sm = (VkShaderModule)(intptr_t)shader_h;
    vkDestroyShaderModule(a->device, sm, NULL);
}

/* ------------------------------------------------------------------ */
/*  PIPELINE LAYOUT                                                    */
/* ------------------------------------------------------------------ */
int64_t xvk_pipeline_layout_create(int64_t app_h, int32_t push_size, int32_t push_stages,
                                   int32_t desc_layout_count, const int64_t* desc_layouts)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a) return 0;

    XvkPipelineLayout* pl = (XvkPipelineLayout*)calloc(1, sizeof(XvkPipelineLayout));
    if (!pl) { xvk_set_error("calloc pipeline layout"); return 0; }

    VkPushConstantRange pcr = {0};
    int pcr_count = 0;
    if (push_size > 0) {
        pcr.stageFlags = xvk_map_stage_flags(push_stages);
        pcr.offset     = 0;
        pcr.size       = (uint32_t)push_size;
        pcr_count      = 1;
    }

    VkDescriptorSetLayout* dsl = NULL;
    if (desc_layout_count > 0 && desc_layouts) {
        dsl = (VkDescriptorSetLayout*)malloc((size_t)desc_layout_count * sizeof(VkDescriptorSetLayout));
        for (int i = 0; i < desc_layout_count; ++i) {
            XvkDescSetLayout* dl = xvk_dslayout_from_handle(desc_layouts[i]);
            dsl[i] = dl ? dl->layout : VK_NULL_HANDLE;
        }
    }

    VkPipelineLayoutCreateInfo plci = {0};
    plci.sType                  = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO;
    plci.setLayoutCount         = (uint32_t)desc_layout_count;
    plci.pSetLayouts            = dsl;
    plci.pushConstantRangeCount = (uint32_t)pcr_count;
    plci.pPushConstantRanges    = pcr_count ? &pcr : NULL;

    VkResult res = vkCreatePipelineLayout(a->device, &plci, NULL, &pl->layout);
    if (dsl) free(dsl);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreatePipelineLayout: %d", (int)res);
        free(pl); return 0;
    }
    pl->magic = XVK_PLAYOUT_MAGIC;
    return xvk_playout_to_handle(pl);
}

void xvk_pipeline_layout_destroy(int64_t app_h, int64_t layout_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipelineLayout* pl = xvk_playout_from_handle(layout_h);
    if (!a || !pl) return;
    if (pl->layout) vkDestroyPipelineLayout(a->device, pl->layout, NULL);
    pl->magic = 0;
    free(pl);
}

/* ------------------------------------------------------------------ */
/*  DESCRIPTOR SET LAYOUT                                              */
/* ------------------------------------------------------------------ */
int64_t xvk_desc_set_layout_create(int64_t app_h, const int32_t* bindings, int32_t count)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !bindings || count <= 0) return 0;

    XvkDescSetLayout* dl = (XvkDescSetLayout*)calloc(1, sizeof(XvkDescSetLayout));
    if (!dl) { xvk_set_error("calloc desc layout"); return 0; }

    VkDescriptorSetLayoutBinding* b = (VkDescriptorSetLayoutBinding*)
        malloc((size_t)count * sizeof(VkDescriptorSetLayoutBinding));
    if (!b) { free(dl); xvk_set_error("malloc bindings"); return 0; }

    for (int i = 0; i < count; ++i) {
        int off = i * 4;
        b[i].binding            = (uint32_t)bindings[off];
        b[i].descriptorType     = xvk_map_desc_type(bindings[off + 1]);
        b[i].descriptorCount    = (uint32_t)(bindings[off + 2] > 0 ? bindings[off + 2] : 1);
        b[i].stageFlags         = xvk_map_stage_flags(bindings[off + 3]);
        b[i].pImmutableSamplers = NULL;
    }

    VkDescriptorSetLayoutCreateInfo lci = {0};
    lci.sType        = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO;
    lci.bindingCount = (uint32_t)count;
    lci.pBindings    = b;

    VkResult res = vkCreateDescriptorSetLayout(a->device, &lci, NULL, &dl->layout);
    free(b);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateDescriptorSetLayout: %d", (int)res);
        free(dl); return 0;
    }
    dl->magic = XVK_DESC_LAYOUT_MAGIC;
    return xvk_dslayout_to_handle(dl);
}

void xvk_desc_set_layout_destroy(int64_t app_h, int64_t layout_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkDescSetLayout* dl = xvk_dslayout_from_handle(layout_h);
    if (!a || !dl) return;
    if (dl->layout) vkDestroyDescriptorSetLayout(a->device, dl->layout, NULL);
    dl->magic = 0;
    free(dl);
}

/* ------------------------------------------------------------------ */
/*  PIPELINES                                                          */
/* ------------------------------------------------------------------ */
int64_t xvk_pipeline_create_graphics(int64_t app_h,
    int32_t topology, int32_t cull_mode, int32_t depth_test, int32_t depth_write,
    int32_t blend_enable,
    int64_t vertex_shader_h, int64_t fragment_shader_h,
    int64_t layout_h, int64_t render_pass_h,
    const int32_t* bindings, int32_t binding_count,
    const int32_t* attributes, int32_t attr_count)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipelineLayout* pl = xvk_playout_from_handle(layout_h);
    XvkRenderPass* rp = xvk_rp_from_handle(render_pass_h);
    if (!a || !pl || !rp) return 0;
    if (!vertex_shader_h || !fragment_shader_h) { xvk_set_error("shader handles required"); return 0; }

    XvkPipeline* p = (XvkPipeline*)calloc(1, sizeof(XvkPipeline));
    if (!p) { xvk_set_error("calloc pipeline"); return 0; }

    /* Shader stages */
    VkPipelineShaderStageCreateInfo stages[2] = {{0}};
    stages[0].sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[0].stage  = VK_SHADER_STAGE_VERTEX_BIT;
    stages[0].module = (VkShaderModule)(intptr_t)vertex_shader_h;
    stages[0].pName  = "main";
    stages[1].sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stages[1].stage  = VK_SHADER_STAGE_FRAGMENT_BIT;
    stages[1].module = (VkShaderModule)(intptr_t)fragment_shader_h;
    stages[1].pName  = "main";

    /* Vertex input */
    VkVertexInputBindingDescription* vb = NULL;
    VkVertexInputAttributeDescription* va = NULL;
    if (binding_count > 0 && bindings) {
        vb = (VkVertexInputBindingDescription*)malloc((size_t)binding_count * sizeof(VkVertexInputBindingDescription));
        for (int i = 0; i < binding_count; ++i) {
            vb[i].binding   = (uint32_t)bindings[i * 3];
            vb[i].stride    = (uint32_t)bindings[i * 3 + 1];
            vb[i].inputRate = bindings[i * 3 + 2] == 1 ? VK_VERTEX_INPUT_RATE_INSTANCE : VK_VERTEX_INPUT_RATE_VERTEX;
        }
    }
    if (attr_count > 0 && attributes) {
        va = (VkVertexInputAttributeDescription*)malloc((size_t)attr_count * sizeof(VkVertexInputAttributeDescription));
        for (int i = 0; i < attr_count; ++i) {
            va[i].location = (uint32_t)attributes[i * 4];
            va[i].binding  = (uint32_t)attributes[i * 4 + 1];
            va[i].format   = xvk_map_vertex_format(attributes[i * 4 + 2]);
            va[i].offset   = (uint32_t)attributes[i * 4 + 3];
        }
    }

    VkPipelineVertexInputStateCreateInfo vi = {0};
    vi.sType = VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO;
    vi.vertexBindingDescriptionCount   = (uint32_t)binding_count;
    vi.pVertexBindingDescriptions      = vb;
    vi.vertexAttributeDescriptionCount = (uint32_t)attr_count;
    vi.pVertexAttributeDescriptions    = va;

    VkPipelineInputAssemblyStateCreateInfo ia = {0};
    ia.sType    = VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO;
    ia.topology = xvk_map_topology(topology);

    VkViewport vp = {0};
    vp.x = 0; vp.y = 0;
    vp.width  = (float)a->swapchain_extent.width;
    vp.height = (float)a->swapchain_extent.height;
    vp.minDepth = 0.0f;
    vp.maxDepth = 1.0f;

    VkRect2D sc = {0};
    sc.extent = a->swapchain_extent;

    VkPipelineViewportStateCreateInfo vs = {0};
    vs.sType         = VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO;
    vs.viewportCount = 1; vs.pViewports = &vp;
    vs.scissorCount  = 1; vs.pScissors  = &sc;

    VkPipelineRasterizationStateCreateInfo rs = {0};
    rs.sType       = VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
    rs.polygonMode = VK_POLYGON_MODE_FILL;
    rs.cullMode    = cull_mode == 1 ? VK_CULL_MODE_FRONT_BIT :
                     cull_mode == 2 ? VK_CULL_MODE_BACK_BIT : VK_CULL_MODE_NONE;
    rs.frontFace   = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    rs.lineWidth   = 1.0f;

    VkPipelineMultisampleStateCreateInfo ms = {0};
    ms.sType                = VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
    ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;

    VkPipelineDepthStencilStateCreateInfo ds = {0};
    ds.sType                 = VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO;
    ds.depthTestEnable       = depth_test ? VK_TRUE : VK_FALSE;
    ds.depthWriteEnable      = depth_write ? VK_TRUE : VK_FALSE;
    ds.depthCompareOp        = VK_COMPARE_OP_LESS;

    VkPipelineColorBlendAttachmentState cb = {0};
    cb.colorWriteMask = VK_COLOR_COMPONENT_R_BIT | VK_COLOR_COMPONENT_G_BIT |
                        VK_COLOR_COMPONENT_B_BIT | VK_COLOR_COMPONENT_A_BIT;
    if (blend_enable) {
        cb.blendEnable         = VK_TRUE;
        cb.srcColorBlendFactor = VK_BLEND_FACTOR_SRC_ALPHA;
        cb.dstColorBlendFactor = VK_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
        cb.colorBlendOp        = VK_BLEND_OP_ADD;
        cb.srcAlphaBlendFactor = VK_BLEND_FACTOR_ONE;
        cb.dstAlphaBlendFactor = VK_BLEND_FACTOR_ZERO;
        cb.alphaBlendOp        = VK_BLEND_OP_ADD;
    } else {
        cb.blendEnable = VK_FALSE;
    }

    VkPipelineColorBlendStateCreateInfo cbs = {0};
    cbs.sType           = VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
    cbs.attachmentCount = 1;
    cbs.pAttachments    = &cb;

    VkPipelineDynamicStateCreateInfo dyn = {0};
    dyn.sType = VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO;

    VkGraphicsPipelineCreateInfo gpci = {0};
    gpci.sType               = VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO;
    gpci.stageCount          = 2;
    gpci.pStages             = stages;
    gpci.pVertexInputState   = &vi;
    gpci.pInputAssemblyState = &ia;
    gpci.pViewportState      = &vs;
    gpci.pRasterizationState = &rs;
    gpci.pMultisampleState   = &ms;
    gpci.pDepthStencilState  = &ds;
    gpci.pColorBlendState    = &cbs;
    gpci.pDynamicState       = &dyn;
    gpci.layout              = pl->layout;
    gpci.renderPass          = rp->render_pass;
    gpci.subpass             = 0;

    VkResult res = vkCreateGraphicsPipelines(a->device, VK_NULL_HANDLE, 1, &gpci, NULL, &p->pipeline);
    if (vb) free(vb);
    if (va) free(va);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateGraphicsPipelines: %d", (int)res);
        free(p); return 0;
    }
    p->bind_point = VK_PIPELINE_BIND_POINT_GRAPHICS;
    p->magic = XVK_PIPELINE_MAGIC;
    return xvk_pipeline_to_handle(p);
}

int64_t xvk_pipeline_create_compute(int64_t app_h, int64_t shader_h, int64_t layout_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipelineLayout* pl = xvk_playout_from_handle(layout_h);
    if (!a || !pl || !shader_h) return 0;

    XvkPipeline* p = (XvkPipeline*)calloc(1, sizeof(XvkPipeline));
    if (!p) { xvk_set_error("calloc compute pipeline"); return 0; }

    VkPipelineShaderStageCreateInfo stage = {0};
    stage.sType  = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
    stage.stage  = VK_SHADER_STAGE_COMPUTE_BIT;
    stage.module = (VkShaderModule)(intptr_t)shader_h;
    stage.pName  = "main";

    VkComputePipelineCreateInfo cpci = {0};
    cpci.sType  = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO;
    cpci.stage  = stage;
    cpci.layout = pl->layout;

    VkResult res = vkCreateComputePipelines(a->device, VK_NULL_HANDLE, 1, &cpci, NULL, &p->pipeline);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateComputePipelines: %d", (int)res);
        free(p); return 0;
    }
    p->bind_point = VK_PIPELINE_BIND_POINT_COMPUTE;
    p->magic = XVK_PIPELINE_MAGIC;
    return xvk_pipeline_to_handle(p);
}

void xvk_pipeline_destroy(int64_t app_h, int64_t pipeline_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipeline* p = xvk_pipeline_from_handle(pipeline_h);
    if (!a || !p) return;
    if (p->pipeline) vkDestroyPipeline(a->device, p->pipeline, NULL);
    p->magic = 0;
    free(p);
}

/* ------------------------------------------------------------------ */
/*  DESCRIPTOR POOL & SETS                                             */
/* ------------------------------------------------------------------ */
int64_t xvk_desc_pool_create(int64_t app_h, const int32_t* pool_sizes, int32_t size_count,
                             int32_t max_sets)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !pool_sizes || size_count <= 0) return 0;

    XvkDescPool* dp = (XvkDescPool*)calloc(1, sizeof(XvkDescPool));
    if (!dp) { xvk_set_error("calloc desc pool"); return 0; }

    VkDescriptorPoolSize* sizes = (VkDescriptorPoolSize*)
        malloc((size_t)(size_count / 2) * sizeof(VkDescriptorPoolSize));
    if (!sizes) { free(dp); return 0; }
    int sc = 0;
    for (int i = 0; i < size_count; i += 2) {
        sizes[sc].type            = xvk_map_desc_type(pool_sizes[i]);
        sizes[sc].descriptorCount = (uint32_t)pool_sizes[i + 1];
        ++sc;
    }

    VkDescriptorPoolCreateInfo pci = {0};
    pci.sType         = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO;
    pci.maxSets       = (uint32_t)max_sets;
    pci.poolSizeCount = (uint32_t)sc;
    pci.pPoolSizes    = sizes;
    pci.flags         = VK_DESCRIPTOR_POOL_CREATE_FREE_DESCRIPTOR_SET_BIT;

    VkResult res = vkCreateDescriptorPool(a->device, &pci, NULL, &dp->pool);
    free(sizes);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateDescriptorPool: %d", (int)res);
        free(dp); return 0;
    }
    dp->magic = XVK_DESC_POOL_MAGIC;
    return xvk_descpool_to_handle(dp);
}

void xvk_desc_pool_destroy(int64_t app_h, int64_t pool_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkDescPool* dp = xvk_descpool_from_handle(pool_h);
    if (!a || !dp) return;
    if (dp->pool) vkDestroyDescriptorPool(a->device, dp->pool, NULL);
    dp->magic = 0;
    free(dp);
}

int64_t xvk_desc_set_allocate(int64_t app_h, int64_t pool_h, int64_t layout_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkDescPool* dp = xvk_descpool_from_handle(pool_h);
    XvkDescSetLayout* dl = xvk_dslayout_from_handle(layout_h);
    if (!a || !dp || !dl) return 0;

    XvkDescSet* ds = (XvkDescSet*)calloc(1, sizeof(XvkDescSet));
    if (!ds) { xvk_set_error("calloc desc set"); return 0; }

    VkDescriptorSetLayout layout = dl->layout;
    VkDescriptorSetAllocateInfo ai = {0};
    ai.sType              = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO;
    ai.descriptorPool     = dp->pool;
    ai.descriptorSetCount = 1;
    ai.pSetLayouts        = &layout;

    VkResult res = vkAllocateDescriptorSets(a->device, &ai, &ds->set);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkAllocateDescriptorSets: %d", (int)res);
        free(ds); return 0;
    }
    ds->magic = XVK_DESC_SET_MAGIC;
    return xvk_descset_to_handle(ds);
}

void xvk_desc_set_free(int64_t app_h, int64_t pool_h, int64_t set_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkDescPool* dp = xvk_descpool_from_handle(pool_h);
    XvkDescSet* ds = xvk_descset_from_handle(set_h);
    if (!a || !dp || !ds) return;
    if (ds->set) vkFreeDescriptorSets(a->device, dp->pool, 1, &ds->set);
    ds->magic = 0;
    free(ds);
}

void xvk_desc_set_write_buffer(int64_t app_h, int64_t set_h, int32_t binding,
                               int64_t buf_h, int64_t offset, int64_t range,
                               int32_t type)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkDescSet* ds = xvk_descset_from_handle(set_h);
    XvkBuffer* b   = xvk_buffer_from_handle(buf_h);
    if (!a || !ds || !b) return;

    VkDescriptorBufferInfo dbi = {0};
    dbi.buffer = b->buffer;
    dbi.offset = (VkDeviceSize)offset;
    dbi.range  = range > 0 ? (VkDeviceSize)range : VK_WHOLE_SIZE;

    VkWriteDescriptorSet w = {0};
    w.sType           = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    w.dstSet          = ds->set;
    w.dstBinding      = (uint32_t)binding;
    w.dstArrayElement = 0;
    w.descriptorCount = 1;
    w.descriptorType  = xvk_map_desc_type(type);
    w.pBufferInfo     = &dbi;
    vkUpdateDescriptorSets(a->device, 1, &w, 0, NULL);
}

void xvk_desc_set_write_image(int64_t app_h, int64_t set_h, int32_t binding,
                              int64_t sampler_h, int64_t image_view_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkDescSet* ds = xvk_descset_from_handle(set_h);
    XvkSampler* s   = xvk_sampler_from_handle(sampler_h);
    XvkImageView* v = xvk_view_from_handle(image_view_h);
    if (!a || !ds || !v) return;

    VkDescriptorImageInfo dii = {0};
    dii.sampler     = s ? s->sampler : VK_NULL_HANDLE;
    dii.imageView   = v->view;
    dii.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;

    VkWriteDescriptorSet w = {0};
    w.sType           = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    w.dstSet          = ds->set;
    w.dstBinding      = (uint32_t)binding;
    w.dstArrayElement = 0;
    w.descriptorCount = 1;
    w.descriptorType  = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    w.pImageInfo      = &dii;
    vkUpdateDescriptorSets(a->device, 1, &w, 0, NULL);
}

/* ------------------------------------------------------------------ */
/*  COMPUTE DISPATCH                                                   */
/* ------------------------------------------------------------------ */
void xvk_compute_dispatch(int64_t app_h, int64_t pipeline_h, int64_t layout_h,
                          int32_t x, int32_t y, int32_t z)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipeline* p = xvk_pipeline_from_handle(pipeline_h);
    XvkPipelineLayout* pl = xvk_playout_from_handle(layout_h);
    if (!a || !a->recording || !p || !pl) return;

    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    if (a->in_render_pass) {
        vkCmdEndRenderPass(cb);
        a->in_render_pass = 0;
    }
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, p->pipeline);
    vkCmdDispatch(cb, (uint32_t)x, (uint32_t)y, (uint32_t)z);
}

/* ------------------------------------------------------------------ */
/*  RENDER PASSES & FRAMEBUFFERS                                       */
/* ------------------------------------------------------------------ */
int64_t xvk_render_pass_create(int64_t app_h, const int32_t* color_formats,
                               int32_t color_count, int32_t depth_format)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || color_count <= 0) return 0;

    XvkRenderPass* rp = (XvkRenderPass*)calloc(1, sizeof(XvkRenderPass));
    if (!rp) { xvk_set_error("calloc render pass"); return 0; }

    int att_count = color_count + (depth_format > 0 ? 1 : 0);
    VkAttachmentDescription* atts = (VkAttachmentDescription*)
        malloc((size_t)att_count * sizeof(VkAttachmentDescription));
    VkAttachmentReference* col_refs = (VkAttachmentReference*)
        malloc((size_t)color_count * sizeof(VkAttachmentReference));
    if (!atts || !col_refs) {
        if (atts) free(atts); if (col_refs) free(col_refs);
        free(rp); xvk_set_error("malloc attachments"); return 0;
    }
    memset(atts, 0, (size_t)att_count * sizeof(VkAttachmentDescription));

    for (int i = 0; i < color_count; ++i) {
        int off = i * 4;
        int fmt = color_formats[off];
        atts[i].format         = fmt == 2 ? a->swapchain_fmt : xvk_map_format(fmt > 0 ? fmt : 1);
        atts[i].samples        = VK_SAMPLE_COUNT_1_BIT;
        atts[i].loadOp         = color_formats[off+1] == 1 ? VK_ATTACHMENT_LOAD_OP_LOAD :
                                 color_formats[off+1] == 2 ? VK_ATTACHMENT_LOAD_OP_DONT_CARE :
                                 VK_ATTACHMENT_LOAD_OP_CLEAR;
        atts[i].storeOp        = color_formats[off+2] == 1 ? VK_ATTACHMENT_STORE_OP_DONT_CARE :
                                 VK_ATTACHMENT_STORE_OP_STORE;
        atts[i].stencilLoadOp  = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        atts[i].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        atts[i].initialLayout  = VK_IMAGE_LAYOUT_UNDEFINED;
        int fl = color_formats[off+3];
        atts[i].finalLayout    = fl == 1 ? VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL :
                                 fl == 2 ? VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL :
                                 VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        col_refs[i].attachment = (uint32_t)i;
        col_refs[i].layout     = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    }

    VkAttachmentReference depth_ref = {0};
    if (depth_format > 0) {
        int di = color_count;
        atts[di].format         = xvk_map_format(depth_format);
        atts[di].samples        = VK_SAMPLE_COUNT_1_BIT;
        atts[di].loadOp         = VK_ATTACHMENT_LOAD_OP_CLEAR;
        atts[di].storeOp        = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        atts[di].stencilLoadOp  = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        atts[di].stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        atts[di].initialLayout  = VK_IMAGE_LAYOUT_UNDEFINED;
        atts[di].finalLayout    = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
        depth_ref.attachment = (uint32_t)di;
        depth_ref.layout     = VK_IMAGE_LAYOUT_DEPTH_STENCIL_ATTACHMENT_OPTIMAL;
    }

    VkSubpassDescription subpass = {0};
    subpass.pipelineBindPoint       = VK_PIPELINE_BIND_POINT_GRAPHICS;
    subpass.colorAttachmentCount    = (uint32_t)color_count;
    subpass.pColorAttachments       = col_refs;
    subpass.pDepthStencilAttachment = depth_format > 0 ? &depth_ref : NULL;

    VkSubpassDependency dep = {0};
    dep.srcSubpass    = VK_SUBPASS_EXTERNAL;
    dep.dstSubpass    = 0;
    dep.srcStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                        VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    dep.dstStageMask  = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT |
                        VK_PIPELINE_STAGE_EARLY_FRAGMENT_TESTS_BIT;
    dep.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT |
                        VK_ACCESS_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;

    VkRenderPassCreateInfo rpci = {0};
    rpci.sType           = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
    rpci.attachmentCount = (uint32_t)att_count;
    rpci.pAttachments    = atts;
    rpci.subpassCount    = 1;
    rpci.pSubpasses      = &subpass;
    rpci.dependencyCount = 1;
    rpci.pDependencies   = &dep;

    VkResult res = vkCreateRenderPass(a->device, &rpci, NULL, &rp->render_pass);
    free(atts); free(col_refs);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateRenderPass: %d", (int)res);
        free(rp); return 0;
    }
    rp->magic = XVK_RENDERPASS_MAGIC;
    return xvk_rp_to_handle(rp);
}

void xvk_render_pass_destroy(int64_t app_h, int64_t rp_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkRenderPass* rp = xvk_rp_from_handle(rp_h);
    if (!a || !rp) return;
    if (rp->render_pass) vkDestroyRenderPass(a->device, rp->render_pass, NULL);
    rp->magic = 0;
    free(rp);
}

int64_t xvk_framebuffer_create(int64_t app_h, int64_t render_pass_h,
                               const int64_t* attachments, int32_t attachment_count,
                               int32_t width, int32_t height)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkRenderPass* rp = xvk_rp_from_handle(render_pass_h);
    if (!a || !rp || !attachments || attachment_count <= 0) return 0;

    XvkFramebuffer* fb = (XvkFramebuffer*)calloc(1, sizeof(XvkFramebuffer));
    if (!fb) { xvk_set_error("calloc framebuffer"); return 0; }

    VkImageView* views = (VkImageView*)malloc((size_t)attachment_count * sizeof(VkImageView));
    if (!views) { free(fb); return 0; }
    for (int i = 0; i < attachment_count; ++i) {
        XvkImageView* v = xvk_view_from_handle(attachments[i]);
        views[i] = v ? v->view : VK_NULL_HANDLE;
    }

    VkFramebufferCreateInfo fci = {0};
    fci.sType           = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
    fci.renderPass      = rp->render_pass;
    fci.attachmentCount = (uint32_t)attachment_count;
    fci.pAttachments    = views;
    fci.width           = (uint32_t)width;
    fci.height          = (uint32_t)height;
    fci.layers          = 1;

    VkResult res = vkCreateFramebuffer(a->device, &fci, NULL, &fb->framebuffer);
    free(views);
    if (res != VK_SUCCESS) {
        xvk_set_error_fmt("vkCreateFramebuffer: %d", (int)res);
        free(fb); return 0;
    }
    fb->magic = XVK_FRAMEBUFFER_MAGIC;
    return xvk_fb_to_handle(fb);
}

void xvk_framebuffer_destroy(int64_t app_h, int64_t fb_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkFramebuffer* fb = xvk_fb_from_handle(fb_h);
    if (!a || !fb) return;
    if (fb->framebuffer) vkDestroyFramebuffer(a->device, fb->framebuffer, NULL);
    fb->magic = 0;
    free(fb);
}

/* ------------------------------------------------------------------ */
/*  COMMAND RECORDING (between begin/end_frame)                        */
/* ------------------------------------------------------------------ */
void xvk_cmd_bind_vertex_buffer(int64_t app_h, int32_t binding, int64_t buf_h, int64_t offset)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    if (!a || !a->recording || !b) return;
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    VkDeviceSize off = (VkDeviceSize)offset;
    vkCmdBindVertexBuffers(cb, (uint32_t)binding, 1, &b->buffer, &off);
}

void xvk_cmd_bind_index_buffer(int64_t app_h, int64_t buf_h, int64_t offset, int32_t index_type)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkBuffer* b = xvk_buffer_from_handle(buf_h);
    if (!a || !a->recording || !b) return;
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdBindIndexBuffer(cb, b->buffer, (VkDeviceSize)offset, xvk_map_index_type(index_type));
}

void xvk_cmd_bind_pipeline(int64_t app_h, int64_t pipeline_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipeline* p = xvk_pipeline_from_handle(pipeline_h);
    if (!a || !a->recording || !p) return;
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdBindPipeline(cb, p->bind_point, p->pipeline);
}

void xvk_cmd_bind_descriptor_sets(int64_t app_h, int64_t layout_h, int32_t first_set,
                                  const int64_t* sets, int32_t set_count)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipelineLayout* pl = xvk_playout_from_handle(layout_h);
    if (!a || !a->recording || !pl || !sets || set_count <= 0) return;

    VkDescriptorSet* dss = (VkDescriptorSet*)malloc((size_t)set_count * sizeof(VkDescriptorSet));
    if (!dss) return;
    for (int i = 0; i < set_count; ++i) {
        XvkDescSet* ds = xvk_descset_from_handle(sets[i]);
        dss[i] = ds ? ds->set : VK_NULL_HANDLE;
    }
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, pl->layout,
                            (uint32_t)first_set, (uint32_t)set_count, dss, 0, NULL);
    free(dss);
}

void xvk_cmd_push_constants(int64_t app_h, int64_t layout_h, int32_t stages,
                             int32_t offset, int32_t size, const void* data)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkPipelineLayout* pl = xvk_playout_from_handle(layout_h);
    if (!a || !a->recording || !pl || !data || size <= 0) return;
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdPushConstants(cb, pl->layout, xvk_map_stage_flags(stages),
                       (uint32_t)offset, (uint32_t)size, data);
}

void xvk_cmd_draw_indexed(int64_t app_h, int32_t index_count, int32_t instance_count,
                          int32_t first_index, int32_t vertex_offset, int32_t first_instance)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording || !a->in_render_pass) return;
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdDrawIndexed(cb, (uint32_t)index_count, (uint32_t)instance_count,
                     (uint32_t)first_index, vertex_offset, (uint32_t)first_instance);
}

void xvk_cmd_draw(int64_t app_h, int32_t vertex_count, int32_t instance_count,
                  int32_t first_vertex, int32_t first_instance)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording || !a->in_render_pass) return;
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdDraw(cb, (uint32_t)vertex_count, (uint32_t)instance_count,
              (uint32_t)first_vertex, (uint32_t)first_instance);
}

/* ------------------------------------------------------------------ */
/*  CUSTOM RENDER PASS                                                 */
/* ------------------------------------------------------------------ */
int32_t xvk_begin_custom_pass(int64_t app_h, int64_t render_pass_h, int64_t framebuffer_h,
                              int32_t width, int32_t height,
                              float r, float g, float b)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkRenderPass* xrp = xvk_rp_from_handle(render_pass_h);
    XvkFramebuffer* xfb = xvk_fb_from_handle(framebuffer_h);
    if (!a || !a->recording || !xrp || !xfb) return -1;

    VkCommandBuffer cb = a->cmd_buffers[a->current_image];

    /* End default render pass if active */
    if (a->in_render_pass) {
        vkCmdEndRenderPass(cb);
        a->in_render_pass = 0;
    }

    VkClearValue clear = {0};
    clear.color.float32[0] = r;
    clear.color.float32[1] = g;
    clear.color.float32[2] = b;
    clear.color.float32[3] = 1.0f;

    VkRenderPassBeginInfo rpbi = {0};
    rpbi.sType       = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    rpbi.renderPass  = xrp->render_pass;
    rpbi.framebuffer = xfb->framebuffer;
    rpbi.renderArea.offset.x = 0;
    rpbi.renderArea.offset.y = 0;
    rpbi.renderArea.extent.width  = (uint32_t)width;
    rpbi.renderArea.extent.height = (uint32_t)height;
    rpbi.clearValueCount = 1;
    rpbi.pClearValues    = &clear;

    vkCmdBeginRenderPass(cb, &rpbi, VK_SUBPASS_CONTENTS_INLINE);
    a->in_render_pass = 1;
    return 1;
}

int32_t xvk_end_custom_pass(int64_t app_h)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording || !a->in_render_pass) return -1;

    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdEndRenderPass(cb);
    a->in_render_pass = 0;

    /* Re-begin the default render pass for the swapchain */
    VkClearValue clears[2];
    clears[0].color.float32[0] = a->clear_r;
    clears[0].color.float32[1] = a->clear_g;
    clears[0].color.float32[2] = a->clear_b;
    clears[0].color.float32[3] = 1.0f;
    clears[1].depthStencil.depth   = 1.0f;
    clears[1].depthStencil.stencil = 0;

    VkRenderPassBeginInfo rpbi = {0};
    rpbi.sType       = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
    rpbi.renderPass  = a->render_pass;
    rpbi.framebuffer = a->framebuffers[a->current_image];
    rpbi.renderArea.extent = a->swapchain_extent;
    rpbi.clearValueCount   = 2;
    rpbi.pClearValues      = clears;

    vkCmdBeginRenderPass(cb, &rpbi, VK_SUBPASS_CONTENTS_INLINE);
    a->in_render_pass = 1;
    return 1;
}

/* ------------------------------------------------------------------ */
/*  LAYOUT TRANSITIONS                                                 */
/* ------------------------------------------------------------------ */
void xvk_image_transition(int64_t app_h, int64_t img_h, int32_t old_layout, int32_t new_layout)
{
    XvkApp* a = xvk_from_handle(app_h);
    XvkImage* img = xvk_image_from_handle(img_h);
    if (!a || !a->recording || !img) return;

    VkImageLayout old_l = xvk_map_image_layout(old_layout);
    VkImageLayout new_l = xvk_map_image_layout(new_layout);
    if (old_l == new_l) return;

    VkImageMemoryBarrier barrier = {0};
    barrier.sType               = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    barrier.oldLayout           = old_l;
    barrier.newLayout           = new_l;
    barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    barrier.image               = img->image;
    barrier.subresourceRange.aspectMask     = VK_IMAGE_ASPECT_COLOR_BIT;
    barrier.subresourceRange.baseMipLevel   = 0;
    barrier.subresourceRange.levelCount     = img->mip_levels;
    barrier.subresourceRange.baseArrayLayer = 0;
    barrier.subresourceRange.layerCount     = 1;

    VkPipelineStageFlags src_stage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
    VkPipelineStageFlags dst_stage = VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT;

    if (old_l == VK_IMAGE_LAYOUT_UNDEFINED && new_l == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        src_stage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        dst_stage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    } else if (old_l == VK_IMAGE_LAYOUT_UNDEFINED && new_l == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL) {
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        src_stage = VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT;
        dst_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    } else if (old_l == VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL && new_l == VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL) {
        barrier.srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
        src_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        dst_stage = VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT;
    } else {
        barrier.srcAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
        barrier.dstAccessMask = VK_ACCESS_MEMORY_READ_BIT | VK_ACCESS_MEMORY_WRITE_BIT;
    }

    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdPipelineBarrier(cb, src_stage, dst_stage, 0, 0, NULL, 0, NULL, 1, &barrier);
    img->format = img->format; /* no-op, keep format field */
}

/* ------------------------------------------------------------------ */
/*  UTILITY                                                            */
/* ------------------------------------------------------------------ */
void xvk_get_framebuffer_size(int64_t app_h, int32_t* out_width, int32_t* out_height)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !out_width || !out_height) return;
    *out_width  = (int32_t)a->swapchain_extent.width;
    *out_height = (int32_t)a->swapchain_extent.height;
}
