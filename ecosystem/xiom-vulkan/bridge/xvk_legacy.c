#include "xvk_legacy.h"
#include "xvk_math.h"
#include "xvk_camera.h"
#include <stdlib.h>
#include <string.h>

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

void xvk_draw_cube_3d(int64_t app_h, float angle)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording) return;

    float aspect = (float)a->swapchain_extent.width /
                   (float)a->swapchain_extent.height;

    float model[16], view[16], proj[16], tmp[16], mvp[16];
    mat4_identity(model);
    mat4_rotate_y(model, angle);
    mat4_rotate_x(model, angle * 0.3f);

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

    if (xvk_camera_is_active()) {
        xvk_camera_get_view((int64_t)(intptr_t)view);
        xvk_camera_get_projection((int64_t)(intptr_t)proj);
    } else {
        mat4_look_at(view, 2.0f, 2.0f, 2.0f,
                           0.0f, 0.0f, 0.0f,
                           0.0f, 1.0f, 0.0f);
        mat4_perspective(proj, 45.0f * (float)M_PI / 180.0f, aspect, 0.1f, 10.0f);
    }

    mat4_mul(tmp, view, model);
    mat4_mul(mvp, proj, tmp);

    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, a->pipeline_3d);
    vkCmdPushConstants(cb, a->pipe_layout_3d, VK_SHADER_STAGE_VERTEX_BIT,
                       0, 64, mvp);
    vkCmdDraw(cb, 36, 1, 0, 0);
}

int32_t xvk_particles_enable(int64_t app_h, int32_t count)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || count <= 0) return 0;

    if (a->particle_count == count && a->particles) return 1;

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

    for (int32_t i = 0; i < count; ++i) {
        Particle* p = &a->particles[i];
        p->x    = (xvk_pfrand(i, 0) - 0.5f) * 0.2f;
        p->y    = 0.9f;
        p->vx   = (xvk_pfrand(i, 1) - 0.5f) * 0.5f;
        p->vy   = -(0.3f + xvk_pfrand(i, 2) * 0.5f);
        p->r    = 0.8f + xvk_pfrand(i, 3) * 0.2f;
        p->g    = 0.3f + xvk_pfrand(i, 4) * 0.3f;
        p->b    = 0.1f;
        p->life = xvk_pfrand(i, 5) * 2.0f;
    }

    a->particle_count = count;
    xvk_set_error("");
    return 1;
}

void xvk_draw_particles(int64_t app_h, float dt)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording || !a->particles || a->particle_count <= 0)
        return;

    const float GRAVITY = 0.8f;
    int count = a->particle_count;
    Particle* parts = a->particles;

    typedef struct { float pos[2]; float color[3]; } GPUParticle;

    for (int32_t i = 0; i < count; ++i) {
        Particle* p = &parts[i];
        p->vy  += GRAVITY * dt;
        p->x   += p->vx * dt;
        p->y   += p->vy * dt;
        p->life -= dt;

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
            p->life = 0.5f + r2 * 1.5f;
        }
    }

    GPUParticle* gpu = (GPUParticle*)a->particle_mapped;
    for (int32_t i = 0; i < count; ++i) {
        gpu[i].pos[0]   = parts[i].x;
        gpu[i].pos[1]   = parts[i].y;
        gpu[i].color[0] = parts[i].r;
        gpu[i].color[1] = parts[i].g;
        gpu[i].color[2] = parts[i].b;
    }

    VkDeviceSize offset = 0;
    VkCommandBuffer cb = a->cmd_buffers[a->current_image];
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, a->particle_pipeline);
    vkCmdBindVertexBuffers(cb, 0, 1, &a->particle_vbo, &offset);
    vkCmdDraw(cb, (uint32_t)count, 1, 0, 0);
}

void xvk_draw_texture_quad(int64_t app_h, int64_t image_view, int64_t sampler,
                           float cx, float cy, float hw, float hh)
{
    XvkApp* a = xvk_from_handle(app_h);
    if (!a || !a->recording) return;
    if (!a->texquad_pipeline || !image_view) return;

    VkCommandBuffer cb = a->cmd_buffers[a->current_image];

    /* Update descriptor set with the current image view + sampler */
    VkDescriptorImageInfo image_info = {0};
    image_info.imageLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
    image_info.imageView   = (VkImageView)(intptr_t)image_view;
    image_info.sampler     = (VkSampler)(intptr_t)sampler;

    VkWriteDescriptorSet write = {0};
    write.sType           = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET;
    write.dstSet          = a->texquad_ds;
    write.dstBinding      = 1;
    write.descriptorCount = 1;
    write.descriptorType  = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER;
    write.pImageInfo      = &image_info;

    vkUpdateDescriptorSets(a->device, 1, &write, 0, NULL);

    /* Bind pipeline + descriptor set + push constants, then draw */
    vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_GRAPHICS, a->texquad_pipeline);
    vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_GRAPHICS,
                            a->texquad_layout, 0, 1, &a->texquad_ds, 0, NULL);

    float pc[8] = { cx, cy, hw, hh, 1.0f, 1.0f, 1.0f, 1.0f };
    vkCmdPushConstants(cb, a->texquad_layout,
                       VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT,
                       0, 32, pc);
    vkCmdDraw(cb, 6, 1, 0, 0);
}
