#include "xvk_descriptor.h"
#include <stdlib.h>

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
