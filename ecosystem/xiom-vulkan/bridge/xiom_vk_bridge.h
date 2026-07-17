#ifndef XIOM_VK_BRIDGE_H_
#define XIOM_VK_BRIDGE_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- lifecycle (windowed) ---- */

/* Creates GLFW window + Vulkan instance/device/swapchain/renderpass/pipelines/
 * depth/cmdbuffers/sync.  Returns app handle or 0 on failure.
 * Shader SPIR-V is consumed from the generated header xvk_shaders_generated.h
 * (see build.ps1 / build.sh). */
int64_t     xvk_app_create(const char* title, int32_t width, int32_t height);

/* Full teardown (vkDeviceWaitIdle first).  Safe to call with 0 or invalid handle. */
void        xvk_app_destroy(int64_t app);

/* Returns 1 if app is a live, initialized handle; 0 otherwise. */
int32_t     xvk_app_valid(int64_t app);

/* Static buffer describing the most recent failure across any API call. */
const char* xvk_last_error(void);

/* ---- window / events ---- */

/* glfwWindowShouldClose */
int32_t     xvk_app_should_close(int64_t app);

/* glfwPollEvents */
void        xvk_app_poll(int64_t app);

/* glfwGetTime in seconds */
double      xvk_now(void);

/* ---- device info ---- */

/* VkPhysicalDeviceType cast to int32_t (0=VK_PHYSICAL_DEVICE_TYPE_OTHER …
 *  4=VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU).  Returns -1 on invalid handle. */
int32_t     xvk_device_type(int64_t app);

/* ---- frame lifecycle (call between poll and next poll) ---- */

/* Acquire image, begin command buffer, begin render pass with current
 * clear colour.  Return values:
 *   1  = OK, draw commands may be issued.
 *   0  = skip this frame (swapchain out-of-date / resized; swapchain
 *        recreated internally, then 0 returned).
 *  -1  = fatal error (device lost etc.). */
int32_t     xvk_begin_frame(int64_t app);

/* Set the clear colour used by the next xvk_begin_frame call. */
void        xvk_set_clear_color(int64_t app, float r, float g, float b);

/* End render pass, end command buffer, submit, present, advance frame index. */
void        xvk_end_frame(int64_t app);

/* ---- 2D drawing (call after begin_frame, before end_frame) ---- */

/* Draws a triangle filling ~centre of screen with the given colour.
 * Vertex positions are hardcoded in the vertex shader via gl_VertexIndex;
 * colour is passed via push constant. */
void        xvk_draw_triangle_2d(int64_t app, float r, float g, float b);

/* ---- 3D drawing (needs the depth buffer created in app_create) ---- */

/* Draws a lit/coloured unit cube rotating by angle radians around Y
 * (and slightly around X).  MVP is computed in C and passed via push
 * constant; cube vertices are generated in-shader. */
void        xvk_draw_cube_3d(int64_t app, float angle);

/* 2D filled rectangle centred at NDC (cx,cy) with half-extents (hw,hh).
 * 6 vertices generated in-shader via gl_VertexIndex. */
void        xvk_draw_quad_2d(int64_t app, float cx, float cy,
                             float hw, float hh, float r, float g, float b);

/* 3D cube at a world transform: model = T(px,py,pz)*Ry(angle)*Rx(angle*0.3)*S(scale).
 * Reuses the existing cube pipeline + push-constant MVP. */
void        xvk_draw_cube_3d_at(int64_t app, float angle,
                                float px, float py, float pz, float scale);

/* Particle system: initialise host-visible VBO and CPU particle array for
 * `count` fountain particles.  Returns 1 on success, 0 on failure.
 * Re-initialises if count changes.  Safe to call once before the render loop. */
int32_t     xvk_particles_enable(int64_t app, int32_t count);

/* Advance particle simulation by dt seconds and draw as GL_POINTS.
 * Must be called between xvk_begin_frame / xvk_end_frame.  No-op when
 * particles are not enabled. */
void        xvk_draw_particles(int64_t app, float dt);

/* ---- OFFSCREEN path for deterministic tests (no window, no swapchain) ---- */

/* Instance + device (headless, no surface) + a VkImage colour target +
 * render pass + 2D pipeline.  Returns handle or 0. */
int64_t     xvk_offscreen_create(int32_t width, int32_t height);

/* Render one triangle frame into the offscreen image, then copy image to
 * a host-visible buffer.  Return 1=OK, 0/-1 on error. */
int32_t     xvk_offscreen_render_triangle(int64_t app, float r, float g, float b);

/* Return packed 0xRRGGBBAA of the pixel at (x, y) from the last
 * offscreen render.  (0,0) is top-left. */
uint32_t    xvk_offscreen_pixel(int64_t app, int32_t x, int32_t y);

/* FNV-1a hash over the whole rendered image buffer, for golden-image
 * tests. */
uint64_t    xvk_offscreen_hash(int64_t app);

/* Destroy offscreen resources.  Safe to call with 0 or invalid handle. */
void        xvk_offscreen_destroy(int64_t app);

/* ================================================================== */
/*  PHASE 1 — Production Bridge API                                   */
/* ================================================================== */

/* All resource handles are opaque int64_t values (0 = null/invalid).
 * Creation functions return 0 on failure; check xvk_last_error().
 * Destroy functions are safe to call with handle == 0. */

/* ---- buffers ---- */

/* Create a GPU buffer (vertex, index, uniform, or storage).
 *   usage: 1=vertex, 2=index, 4=uniform, 8=storage
 *   memory: 1=device-local, 2=host-visible+coherent, 3=host-visible+cached
 * Returns buffer handle or 0 on failure. */
int64_t xvk_buffer_create(int64_t app, int64_t size, int32_t usage, int32_t memory);
void    xvk_buffer_destroy(int64_t app, int64_t buf);
int64_t xvk_buffer_size(int64_t app, int64_t buf);

/* Map an entire host-visible buffer. Returns 0 on failure.
 * The mapped region becomes an opaque int64_t cookie for write/read. */
int64_t xvk_buffer_map(int64_t app, int64_t buf);
void    xvk_buffer_unmap(int64_t app, int64_t buf);

/* Write data into a mapped buffer at byte offset. data is raw bytes. */
void    xvk_buffer_write(int64_t app, int64_t buf, int64_t offset,
                         const void* data, int64_t data_size);
/* Read data from a mapped buffer at byte offset into out buf. */
void    xvk_buffer_read(int64_t app, int64_t buf, int64_t offset,
                        void* out, int64_t out_size);

/* ---- images & views ---- */

/* Create a 2D image with given format (1=RGBA8_UNORM, 2=RGBA8_SRGB,
 *   3=RGBA32_SFLOAT, 4=R32_SFLOAT, 5=D32_SFLOAT).
 *   usage: 1=sampled, 2=color-attachment, 4=depth-attachment, 8=transfer-src, 16=transfer-dst, 32=storage
 *   mip_levels: 1 for no mipmaps. */
int64_t xvk_image_create_2d(int64_t app, int32_t width, int32_t height,
                             int32_t format, int32_t usage, int32_t mip_levels);
void    xvk_image_destroy(int64_t app, int64_t img);

/* Create an image view for the given image. aspect: 1=color, 2=depth. */
int64_t xvk_image_view_create(int64_t app, int64_t img, int32_t format, int32_t aspect);
void    xvk_image_view_destroy(int64_t app, int64_t view);

/* ---- samplers ---- */

/* Create a sampler. filter: 0=nearest, 1=linear. address: 0=repeat, 1=clamp-edge, 2=clamp-border.
 *   mip_mode: 0=nearest, 1=linear. max_lod: max LOD level (0 for none). */
int64_t xvk_sampler_create(int64_t app, int32_t filter, int32_t address_u,
                            int32_t address_v, int32_t mip_mode, float max_lod);
void    xvk_sampler_destroy(int64_t app, int64_t sampler);

/* ---- shader modules ---- */

/* Create a shader module from SPIR-V bytecode. code points to uint32 array, size is byte count. */
int64_t xvk_shader_create(int64_t app, const unsigned int* code, int32_t code_size);
/* Create a shader module from an embedded SPIR-V array by name.
 * Names match the generated symbols from xvk_shaders_generated.h
 * (e.g. "triangle_vert", "texture_quad_frag", "compute_particles"). */
int64_t xvk_shader_create_named(int64_t app, const char* name);
void    xvk_shader_destroy(int64_t app, int64_t shader);

/* ---- pipeline layouts ---- */

/* Create a pipeline layout.
 *   push_size: 0 for no push constants, otherwise size in bytes.
 *   push_stages: 1=vertex, 2=fragment, 3=both, 4=compute
 *   desc_layout_count: number of descriptor set layouts in desc_layouts array.
 *   desc_layouts: array of descriptor set layout handles (may be NULL if count=0). */
int64_t xvk_pipeline_layout_create(int64_t app, int32_t push_size, int32_t push_stages,
                                    int32_t desc_layout_count, const int64_t* desc_layouts);
void    xvk_pipeline_layout_destroy(int64_t app, int64_t layout);

/* ---- descriptor set layouts ---- */

/* Create a descriptor set layout from binding definitions.
 *   bindings: flat array of int32: [binding0, type0, count0, stage0, binding1, ...]
 *     type: 0=uniform-buffer, 1=storage-buffer, 2=combined-image-sampler, 3=storage-image
 *     stage: 1=vertex, 2=fragment, 3=both, 4=compute
 *   count: number of bindings (length of bindings array is count*4). */
int64_t xvk_desc_set_layout_create(int64_t app, const int32_t* bindings, int32_t count);
void    xvk_desc_set_layout_destroy(int64_t app, int64_t layout);

/* ---- pipelines ---- */

/* Pipeline vertex input config. Each attribute: [location, binding, format, offset]. */
/* format: 1=float2, 2=float3, 3=float4, 4=uint8_4norm, 5=int32 */
/* bindings: array of [binding, stride, input_rate(0=vertex,1=instance)]
 *   binding_count: number of bindings
 *   attributes: flat array of [loc, bind, fmt, offset]
 *   attr_count: number of attributes */

/* Create a graphics pipeline with full configuration.
 *   topology: 0=triangle-list, 1=point-list, 2=line-list
 *   cull_mode: 0=none, 1=front, 2=back
 *   depth_test: 0=off, 1=on
 *   depth_write: 0=off, 1=on
 *   blend_enable: 0=off, 1=alpha-blend
 *   vertex_shader, fragment_shader: shader module handles
 *   layout: pipeline layout handle
 *   render_pass: render pass handle
 *   bindings: vertex binding descriptions (may be NULL)
 *   binding_count: number of vertex bindings
 *   attributes: vertex attribute descriptions (may be NULL)
 *   attr_count: number of vertex attributes */
int64_t xvk_pipeline_create_graphics(int64_t app,
    int32_t topology, int32_t cull_mode, int32_t depth_test, int32_t depth_write,
    int32_t blend_enable,
    int64_t vertex_shader, int64_t fragment_shader,
    int64_t layout, int64_t render_pass,
    const int32_t* bindings, int32_t binding_count,
    const int32_t* attributes, int32_t attr_count);
void    xvk_pipeline_destroy(int64_t app, int64_t pipeline);

/* ---- compute pipelines ---- */

/* Create a compute pipeline from a compute shader module and layout. */
int64_t xvk_pipeline_create_compute(int64_t app, int64_t shader, int64_t layout);
void    xvk_compute_dispatch(int64_t app, int64_t pipeline, int64_t layout,
                              int32_t x, int32_t y, int32_t z);

/* ---- descriptor pool & sets ---- */

/* Create a descriptor pool.
 *   pool_sizes: flat array of [type, count] pairs
 *     type: 0=uniform-buffer, 1=storage-buffer, 2=combined-image-sampler
 *   max_sets: maximum number of sets that can be allocated from this pool */
int64_t xvk_desc_pool_create(int64_t app, const int32_t* pool_sizes, int32_t size_count,
                              int32_t max_sets);
void    xvk_desc_pool_destroy(int64_t app, int64_t pool);

/* Allocate descriptor sets from a pool.
 *   layouts: array of descriptor set layout handles
 *   count: number of layouts (= number of sets to allocate) */
int64_t xvk_desc_set_allocate(int64_t app, int64_t pool, int64_t layout);
void    xvk_desc_set_free(int64_t app, int64_t pool, int64_t set);

/* Write a buffer descriptor binding.
 *   set: descriptor set handle
 *   binding: binding number
 *   buffer: buffer handle
 *   offset, range: byte offset and range into buffer (range=0 means whole buffer)
 *   type: 0=uniform-buffer, 1=storage-buffer */
void    xvk_desc_set_write_buffer(int64_t app, int64_t set, int32_t binding,
                                   int64_t buf, int64_t offset, int64_t range,
                                   int32_t type);

/* Write an image+sampler descriptor binding.
 *   set: descriptor set handle
 *   binding: binding number
 *   sampler: sampler handle
 *   image_view: image view handle */
void    xvk_desc_set_write_image(int64_t app, int64_t set, int32_t binding,
                                  int64_t sampler, int64_t image_view);

/* ---- render passes & framebuffers ---- */

/* Create a render pass for multi-pass rendering.
 *   color_formats: flat array of [format, load_op, store_op, final_layout]
 *     format: 1=RGBA8_UNORM, 2=swapchain-format
 *     load_op: 0=clear, 1=load, 2=dont-care
 *     store_op: 0=store, 1=dont-care
 *     final_layout: 0=present, 1=color-read, 2=shader-read
 *   color_count: number of color attachments
 *   depth_format: depth format (0=none, 5=D32_SFLOAT) */
int64_t xvk_render_pass_create(int64_t app, const int32_t* color_formats,
                                int32_t color_count, int32_t depth_format);
void    xvk_render_pass_destroy(int64_t app, int64_t rp);

/* Create a framebuffer. attachments: array of image view handles [color_view, depth_view?] */
int64_t xvk_framebuffer_create(int64_t app, int64_t render_pass,
                                const int64_t* attachments, int32_t attachment_count,
                                int32_t width, int32_t height);
void    xvk_framebuffer_destroy(int64_t app, int64_t fb);

/* ---- recording commands (call between begin/end_frame or after begin_custom_pass) ---- */

/* Bind a vertex buffer to binding slot. */
void    xvk_cmd_bind_vertex_buffer(int64_t app, int32_t binding, int64_t buf, int64_t offset);
/* Bind an index buffer (always binding 0). type: 0=uint16, 1=uint32. */
void    xvk_cmd_bind_index_buffer(int64_t app, int64_t buf, int64_t offset, int32_t index_type);
/* Bind a pipeline (graphics or compute). */
void    xvk_cmd_bind_pipeline(int64_t app, int64_t pipeline);
/* Bind descriptor sets. first_set = first set number, sets = array of set handles. */
void    xvk_cmd_bind_descriptor_sets(int64_t app, int64_t layout, int32_t first_set,
                                      const int64_t* sets, int32_t set_count);
/* Push constants. size must be <= 128. */
void    xvk_cmd_push_constants(int64_t app, int64_t layout, int32_t stages,
                                int32_t offset, int32_t size, const void* data);
/* Draw indexed. */
void    xvk_cmd_draw_indexed(int64_t app, int32_t index_count, int32_t instance_count,
                              int32_t first_index, int32_t vertex_offset, int32_t first_instance);
/* Draw arrays. */
void    xvk_cmd_draw(int64_t app, int32_t vertex_count, int32_t instance_count,
                      int32_t first_vertex, int32_t first_instance);

/* ---- custom render pass recording ---- */

/* Begin a custom render pass (ends the default one first). Returns 1=OK, 0=skip, -1=error. */
int32_t xvk_begin_custom_pass(int64_t app, int64_t render_pass, int64_t framebuffer,
                               int32_t width, int32_t height,
                               float r, float g, float b);
/* End a custom render pass and return to the default. Returns 1=OK, -1=error. */
int32_t xvk_end_custom_pass(int64_t app);

/* ---- layout transitions ---- */

/* Transition image layout (barrier). old/new: 0=undefined, 1=color-read, 2=shader-read,
 *   3=transfer-src, 4=transfer-dst, 5=depth-read, 6=present. */
void    xvk_image_transition(int64_t app, int64_t img, int32_t old_layout, int32_t new_layout);

/* ---- utility ---- */

/* Return the app's swapchain width and height via out pointers. */
void    xvk_get_framebuffer_size(int64_t app, int32_t* out_width, int32_t* out_height);

#ifdef __cplusplus
}
#endif

#endif /* XIOM_VK_BRIDGE_H_ */
