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

#ifdef __cplusplus
}
#endif

#endif /* XIOM_VK_BRIDGE_H_ */
