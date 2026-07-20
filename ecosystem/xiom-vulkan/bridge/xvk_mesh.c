#include "xvk_mesh.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include <vulkan/vulkan.h>

typedef struct {
    VkBuffer        vbo, ibo;
    VkDeviceMemory  vbo_mem, ibo_mem;
    int32_t         vert_count;
    int32_t         idx_count;
} XvkMesh;

/* Simple OBJ parser: reads v, f lines. Computes flat normals. */
static int parse_obj(const char* path, float** out_verts, int* out_vcount,
                     uint32_t** out_indices, int* out_icount)
{
    FILE* f = fopen(path, "r");
    if (!f) return 0;

    /* Two-pass: first count, then allocate */
    char line[512];
    int vc = 0, fc = 0, tc = 0;
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == 'v' && line[1] == ' ') vc++;
        else if (line[0] == 'f' && line[1] == ' ') fc++;
    }

    if (vc == 0 || fc == 0) { fclose(f); return 0; }

    float* verts_raw = (float*)malloc((size_t)vc * 3 * sizeof(float));
    int* fv = (int*)calloc((size_t)fc * 3, sizeof(int));

    rewind(f);
    int vi = 0, fi = 0;
    while (fgets(line, sizeof(line), f)) {
        if (line[0] == 'v' && line[1] == ' ') {
            float x, y, z;
            if (sscanf(line + 2, "%f %f %f", &x, &y, &z) == 3) {
                verts_raw[vi*3] = x; verts_raw[vi*3+1] = y; verts_raw[vi*3+2] = z;
                vi++;
            }
        } else if (line[0] == 'f' && line[1] == ' ') {
            int a, b, c;
            if (sscanf(line + 2, "%d %d %d", &a, &b, &c) == 3) {
                fv[fi*3] = a-1; fv[fi*3+1] = b-1; fv[fi*3+2] = c-1;
                fi++;
            }
        }
    }
    fclose(f);

    /* Build interleaved vertex data: position(3) + normal(3) = 6 floats/vert */
    int total_verts = fc * 3;
    float* vdata = (float*)calloc((size_t)total_verts * 6, sizeof(float));
    uint32_t* idata = (uint32_t*)malloc((size_t)total_verts * sizeof(uint32_t));

    for (int i = 0; i < total_verts; i++) idata[i] = (uint32_t)i;

    for (int fi = 0; fi < fc; fi++) {
        int a = fv[fi*3], b = fv[fi*3+1], c = fv[fi*3+2];
        /* Compute face normal */
        float v1[3] = { verts_raw[b*3]-verts_raw[a*3], verts_raw[b*3+1]-verts_raw[a*3+1], verts_raw[b*3+2]-verts_raw[a*3+2] };
        float v2[3] = { verts_raw[c*3]-verts_raw[a*3], verts_raw[c*3+1]-verts_raw[a*3+1], verts_raw[c*3+2]-verts_raw[a*3+2] };
        float nx = v1[1]*v2[2] - v1[2]*v2[1];
        float ny = v1[2]*v2[0] - v1[0]*v2[2];
        float nz = v1[0]*v2[1] - v1[1]*v2[0];
        float nl = sqrtf(nx*nx + ny*ny + nz*nz);
        if (nl > 0.0001f) { nx /= nl; ny /= nl; nz /= nl; }

        for (int j = 0; j < 3; j++) {
            int vidx = fv[fi*3+j];
            int out = (fi*3+j) * 6;
            vdata[out]   = verts_raw[vidx*3];
            vdata[out+1] = verts_raw[vidx*3+1];
            vdata[out+2] = verts_raw[vidx*3+2];
            vdata[out+3] = nx;
            vdata[out+4] = ny;
            vdata[out+5] = nz;
        }
    }

    free(verts_raw);
    free(fv);

    *out_verts = vdata;
    *out_vcount = total_verts;
    *out_indices = idata;
    *out_icount = total_verts;
    return 1;
}

static uint32_t find_memory_type_vk(VkPhysicalDevice phys_dev, uint32_t type_bits,
                                     VkMemoryPropertyFlags props)
{
    VkPhysicalDeviceMemoryProperties mp;
    vkGetPhysicalDeviceMemoryProperties(phys_dev, &mp);
    for (uint32_t i = 0; i < mp.memoryTypeCount; i++) {
        if ((type_bits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & props) == props)
            return i;
    }
    return 0;
}

int64_t xvk_mesh_load(int64_t device, int64_t phys_dev, const char* filepath)
{
    float* vdata = NULL; int vc = 0;
    uint32_t* idata = NULL; int ic = 0;
    if (!parse_obj(filepath, &vdata, &vc, &idata, &ic)) return 0;

    VkDevice dev = (VkDevice)(intptr_t)device;
    VkPhysicalDevice pd = (VkPhysicalDevice)(intptr_t)phys_dev;

    XvkMesh* m = (XvkMesh*)calloc(1, sizeof(XvkMesh));
    if (!m) { free(vdata); free(idata); return 0; }

    VkDeviceSize vb_size = (VkDeviceSize)vc * 6 * sizeof(float);
    VkDeviceSize ib_size = (VkDeviceSize)ic * sizeof(uint32_t);

    /* Vertex buffer */
    VkBufferCreateInfo bci = {0};
    bci.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO;
    bci.size  = vb_size;
    bci.usage = VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    bci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    if (vkCreateBuffer(dev, &bci, NULL, &m->vbo) != VK_SUCCESS) goto fail;

    VkMemoryRequirements mr;
    vkGetBufferMemoryRequirements(dev, m->vbo, &mr);
    VkMemoryAllocateInfo mai = {0};
    mai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    mai.allocationSize = mr.size;
    mai.memoryTypeIndex = find_memory_type_vk(pd, mr.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (vkAllocateMemory(dev, &mai, NULL, &m->vbo_mem) != VK_SUCCESS) goto fail;
    if (vkBindBufferMemory(dev, m->vbo, m->vbo_mem, 0) != VK_SUCCESS) goto fail;

    void* ptr = NULL;
    if (vkMapMemory(dev, m->vbo_mem, 0, vb_size, 0, &ptr) != VK_SUCCESS) goto fail;
    memcpy(ptr, vdata, (size_t)vb_size);
    vkUnmapMemory(dev, m->vbo_mem);

    /* Index buffer */
    bci.size = ib_size;
    bci.usage = VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT;
    if (vkCreateBuffer(dev, &bci, NULL, &m->ibo) != VK_SUCCESS) goto fail;

    vkGetBufferMemoryRequirements(dev, m->ibo, &mr);
    mai.allocationSize = mr.size;
    mai.memoryTypeIndex = find_memory_type_vk(pd, mr.memoryTypeBits,
        VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);
    if (vkAllocateMemory(dev, &mai, NULL, &m->ibo_mem) != VK_SUCCESS) goto fail;
    if (vkBindBufferMemory(dev, m->ibo, m->ibo_mem, 0) != VK_SUCCESS) goto fail;

    ptr = NULL;
    if (vkMapMemory(dev, m->ibo_mem, 0, ib_size, 0, &ptr) != VK_SUCCESS) goto fail;
    memcpy(ptr, idata, (size_t)ib_size);
    vkUnmapMemory(dev, m->ibo_mem);

    m->vert_count = vc;
    m->idx_count  = ic;

    free(vdata);
    free(idata);
    return (int64_t)(intptr_t)m;

fail:
    if (m->vbo) vkDestroyBuffer(dev, m->vbo, NULL);
    if (m->vbo_mem) vkFreeMemory(dev, m->vbo_mem, NULL);
    if (m->ibo) vkDestroyBuffer(dev, m->ibo, NULL);
    if (m->ibo_mem) vkFreeMemory(dev, m->ibo_mem, NULL);
    free(m);
    free(vdata);
    free(idata);
    return 0;
}

int32_t xvk_mesh_vertex_count(int64_t mesh) {
    XvkMesh* m = (XvkMesh*)(intptr_t)mesh;
    return m ? m->vert_count : 0;
}
int32_t xvk_mesh_index_count(int64_t mesh) {
    XvkMesh* m = (XvkMesh*)(intptr_t)mesh;
    return m ? m->idx_count : 0;
}
int64_t xvk_mesh_vertex_buffer(int64_t mesh) {
    XvkMesh* m = (XvkMesh*)(intptr_t)mesh;
    return m ? (int64_t)(uintptr_t)m->vbo : 0;
}
int64_t xvk_mesh_index_buffer(int64_t mesh) {
    XvkMesh* m = (XvkMesh*)(intptr_t)mesh;
    return m ? (int64_t)(uintptr_t)m->ibo : 0;
}

void xvk_mesh_draw(int64_t app_h, int64_t mesh) {
    /* Requires caller to bind pipeline + push constants first.
     * This just binds vertex/index buffers and draws. */
    XvkMesh* m = (XvkMesh*)(intptr_t)mesh;
    /* Stub — actual draw requires pipeline binding from caller */
    (void)app_h; (void)m;
}

void xvk_mesh_destroy(int64_t device, int64_t mesh) {
    if (!mesh) return;
    XvkMesh* m = (XvkMesh*)(intptr_t)mesh;
    VkDevice dev = (VkDevice)(intptr_t)device;
    if (m->vbo) vkDestroyBuffer(dev, m->vbo, NULL);
    if (m->vbo_mem) vkFreeMemory(dev, m->vbo_mem, NULL);
    if (m->ibo) vkDestroyBuffer(dev, m->ibo, NULL);
    if (m->ibo_mem) vkFreeMemory(dev, m->ibo_mem, NULL);
    free(m);
}
