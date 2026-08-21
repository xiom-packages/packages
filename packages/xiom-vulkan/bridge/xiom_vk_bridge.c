#include "xvk_bridge.h"

/* AAA features -- memory sub-allocator (Phase 7.1) */
#include "xvk_memory_alloc.c"

/* Phase 7.3 -- Runtime shader compilation toolchain */
#include "xvk_shader_compile.c"

/* Phase 7.4 -- Texture loading pipeline */
#include "xvk_texture.c"

/* Phase 8.3 -- Font/text rendering */
#include "xvk_font.c"

/* Image loader (PNG/JPG/BMP/TGA via stb_image) */
#include "xvk_image.c"

/* 3D Camera system */
#include "xvk_camera.c"

/* OBJ Mesh loader */
#include "xvk_mesh.c"

#include "xvk_util.c"
#include "xvk_math.c"
#include "xvk_instance.c"
#include "xvk_swapchain.c"
#include "xvk_pipeline.c"
#include "xvk_renderpass.c"
#include "xvk_descriptor.c"
#include "xvk_buffer.c"
#include "xvk_command.c"
#include "xvk_query.c"
#include "xvk_legacy.c"
#include "xvk_offscreen.c"
#include "xvk_frame.c"
#include "xvk_app.c"

/* Struct marshalling + direct VK bindings */
#include "xvk_structs.c"
#include "xvk_bind_instance.c"
#include "xvk_bind_device.c"
#include "xvk_bind_swapchain.c"
#include "xvk_bind_buffer.c"
#include "xvk_bind_image.c"
#include "xvk_bind_memory.c"
#include "xvk_bind_pipeline.c"
#include "xvk_bind_descriptor.c"
#include "xvk_bind_renderpass.c"
#include "xvk_bind_command.c"
#include "xvk_bind_sync.c"
#include "xvk_bind_query.c"
#include "xvk_bind_extensions.c"
#include "xvk_bind_raytracing.c"
