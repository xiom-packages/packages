#ifndef XVK_TYPES_H_
#define XVK_TYPES_H_

#include <stdint.h>
#include <vulkan/vulkan.h>
#define GLFW_INCLUDE_VULKAN
#include <GLFW/glfw3.h>

#define XVK_MAGIC               0x58564B01u
#define XVK_MAX_FRAMES          2
#define XVK_BUFFER_MAGIC        0x42554601
#define XVK_IMAGE_MAGIC         0x494D4701
#define XVK_IMAGEVIEW_MAGIC     0x56494557
#define XVK_SAMPLER_MAGIC       0x534D5001
#define XVK_SHADER_MAGIC        0x53484401
#define XVK_PIPELINE_MAGIC      0x50495001
#define XVK_PLAYOUT_MAGIC       0x504C4159
#define XVK_DESC_LAYOUT_MAGIC   0x44534301
#define XVK_DESC_POOL_MAGIC     0x44535001
#define XVK_DESC_SET_MAGIC      0x44535301
#define XVK_RENDERPASS_MAGIC    0x52504153
#define XVK_FRAMEBUFFER_MAGIC   0x46524255
#ifndef M_PI
#  define M_PI 3.14159265358979323846
#endif

typedef struct {
    float x, y;
    float vx, vy;
    float r, g, b;
    float life;
} Particle;

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

typedef struct XvkApp {
    uint32_t            magic;
    int                 is_offscreen;

    VkInstance          instance;
    VkPhysicalDevice    phys_dev;
    VkDevice            device;
    VkQueue             graphics_queue;
    VkQueue             present_queue;
    uint32_t            graphics_family;
    uint32_t            present_family;
    VkPhysicalDeviceMemoryProperties mem_props;
    int                 device_type;

    GLFWwindow*         window;
    VkSurfaceKHR        surface;

    VkSwapchainKHR      swapchain;
    VkFormat            swapchain_fmt;
    VkExtent2D          swapchain_extent;
    VkImage*            swapchain_images;
    VkImageView*        swapchain_image_views;
    int                 swapchain_image_count;

    VkImage             depth_image;
    VkDeviceMemory      depth_memory;
    VkImageView         depth_image_view;
    VkFormat            depth_format;

    VkRenderPass        render_pass;
    VkPipelineLayout    pipe_layout_2d;
    VkPipeline          pipeline_2d;
    VkPipelineLayout    pipe_layout_3d;
    VkPipeline          pipeline_3d;

    VkPipelineLayout    pipe_layout_quad;
    VkPipeline          pipeline_quad;

    int32_t             particle_count;
    VkBuffer            particle_vbo;
    VkDeviceMemory      particle_mem;
    void*               particle_mapped;
    VkPipeline          particle_pipeline;
    VkPipelineLayout    particle_layout;
    Particle*           particles;

    VkFramebuffer*      framebuffers;

    VkCommandPool       cmd_pool;
    VkCommandBuffer*    cmd_buffers;

    VkSemaphore*        image_available;
    VkSemaphore*        render_finished;
    VkFence*            in_flight_fences;
    int                 frame_index;

    float               clear_r, clear_g, clear_b;
    int                 recording;
    int                 in_render_pass;
    uint32_t            current_image;

    int                 offs_w, offs_h;
    VkImage             offs_image;
    VkDeviceMemory      offs_memory;
    VkImageView         offs_image_view;
    VkRenderPass        offs_render_pass;
    VkPipeline          offs_pipeline;
    VkFramebuffer       offs_framebuffer;
    VkBuffer            offs_readback;
    VkDeviceMemory      offs_readback_mem;
    void*               offs_mapped;
    VkCommandBuffer     offs_cmd;
    VkFence             offs_fence;

    /* Input state (Phase 8.2) — updated per-frame in xvk_app_poll */
    double              mouse_x, mouse_y;
    int                 mouse_btn[3];  /* 0=left, 1=right, 2=middle */
    int                 key_escape, key_space, key_w, key_a, key_s, key_d;
} XvkApp;

#endif
