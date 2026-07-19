/* xvk_memory_alloc.c — VMA-style sub-allocator implementation */
#include "xvk_memory_alloc.h"
#include <stdlib.h>
#include <string.h>

static XvkMaState g_ma = {0};

/* ---- helpers ---- */

static uint32_t ma_find_memory_type(uint32_t type_filter, VkMemoryPropertyFlags props) {
    for (uint32_t i = 0; i < g_ma.mem_props.memoryTypeCount; i++) {
        if ((type_filter & (1 << i)) &&
            (g_ma.mem_props.memoryTypes[i].propertyFlags & props) == props) {
            return i;
        }
    }
    return UINT32_MAX;
}

static XvkMaPool* get_or_create_pool(uint32_t mem_type_index, VkMemoryPropertyFlags props) {
    for (int i = 0; i < g_ma.pool_count; i++) {
        if (g_ma.pools[i] && g_ma.pools[i]->memory_type_index == mem_type_index)
            return g_ma.pools[i];
    }
    XvkMaPool* pool = calloc(1, sizeof(XvkMaPool));
    if (!pool) return NULL;
    pool->memory_type_index = mem_type_index;
    pool->properties = props;
    g_ma.pools[g_ma.pool_count++] = pool;
    return pool;
}

static XvkMaBlock* alloc_block(XvkMaPool* pool, VkDeviceSize size, int is_linear) {
    if (pool->block_count >= XVK_MA_MAX_BLOCKS) return NULL;

    VkMemoryAllocateInfo ai = {0};
    ai.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
    ai.allocationSize = size;
    ai.memoryTypeIndex = pool->memory_type_index;

    VkDeviceMemory mem = VK_NULL_HANDLE;
    if (vkAllocateMemory(g_ma.device, &ai, NULL, &mem) != VK_SUCCESS)
        return NULL;

    XvkMaBlock* block = calloc(1, sizeof(XvkMaBlock));
    block->memory = mem;
    block->size = size;
    block->is_linear = is_linear;
    block->memory_type = pool->memory_type_index;
    block->used = 0;

    if (is_linear) {
        /* Linear allocator: try to map if host-visible */
        if (pool->properties & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) {
            vkMapMemory(g_ma.device, mem, 0, size, 0, &block->mapped);
        }
    } else {
        /* Free-list: start with one free chunk covering the whole block */
        block->free_offset = 0;
        block->free_size = size;
    }

    pool->blocks[pool->block_count++] = block;
    return block;
}

/* ---- linear allocation ---- */

static VkDeviceSize linear_allocate(XvkMaBlock* block, VkDeviceSize size, VkDeviceSize alignment) {
    VkDeviceSize offset = (block->used + alignment - 1) & ~(alignment - 1);
    if (offset + size > block->size) return (VkDeviceSize)-1;
    block->used = offset + size;
    return offset;
}

/* ---- free-list allocation (first-fit) ---- */

static VkDeviceSize freelist_allocate(XvkMaBlock* block, VkDeviceSize size, VkDeviceSize alignment) {
    XvkMaBlock* prev = NULL;
    XvkMaBlock* curr = block;
    while (curr) {
        VkDeviceSize offset = (curr->free_offset + alignment - 1) & ~(alignment - 1);
        VkDeviceSize aligned_size = size + (offset - curr->free_offset);
        if (aligned_size <= curr->free_size) {
            /* Carve out from this free chunk */
            if (aligned_size < curr->free_size) {
                /* Remainder becomes a new free chunk */
                XvkMaBlock* remainder = calloc(1, sizeof(XvkMaBlock));
                remainder->free_offset = offset + size;
                remainder->free_size = curr->free_size - aligned_size;
                remainder->next_free = curr->next_free;
                curr->free_size = offset - curr->free_offset;
                curr->next_free = remainder;
            }
            return offset;
        }
        prev = curr;
        curr = curr->next_free;
    }
    return (VkDeviceSize)-1;
}

/* ---- public API ---- */

int32_t xvk_ma_init(int64_t physical_device, int64_t device) {
    memset(&g_ma, 0, sizeof(g_ma));
    g_ma.phys_dev = (VkPhysicalDevice)(intptr_t)physical_device;
    g_ma.device    = (VkDevice)(intptr_t)device;
    vkGetPhysicalDeviceMemoryProperties(g_ma.phys_dev, &g_ma.mem_props);
    return VK_SUCCESS;
}

int32_t xvk_ma_allocate_buffer(int64_t create_info, int32_t flags,
                                int64_t out_buf_h, int64_t out_mem_h, int64_t out_off_h) {
    if (!g_ma.device || !create_info) return VK_ERROR_INITIALIZATION_FAILED;
    VkBufferCreateInfo* bci = (VkBufferCreateInfo*)(intptr_t)create_info;
    VkDevice dev = g_ma.device;

    /* Create buffer */
    VkBuffer buf = VK_NULL_HANDLE;
    VkResult res = vkCreateBuffer(dev, bci, NULL, &buf);
    if (res != VK_SUCCESS) return res;

    /* Get memory requirements */
    VkMemoryRequirements reqs;
    vkGetBufferMemoryRequirements(dev, buf, &reqs);

    /* Select memory type */
    VkMemoryPropertyFlags want = (flags == 1) ? VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT :
                                 (flags == 2) ? (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT) :
                                 VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    uint32_t mem_type = ma_find_memory_type(reqs.memoryTypeBits, want);
    if (mem_type == UINT32_MAX && (want & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) {
        /* Fall back to any available type */
        mem_type = ma_find_memory_type(reqs.memoryTypeBits, 0);
    }
    if (mem_type == UINT32_MAX) { vkDestroyBuffer(dev, buf, NULL); return VK_ERROR_OUT_OF_DEVICE_MEMORY; }

    VkMemoryPropertyFlags props = g_ma.mem_props.memoryTypes[mem_type].propertyFlags;
    int is_host_visible = (props & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) != 0;
    XvkMaPool* pool = get_or_create_pool(mem_type, props);
    if (!pool) { vkDestroyBuffer(dev, buf, NULL); return VK_ERROR_OUT_OF_HOST_MEMORY; }

    /* Pick allocation strategy: linear for large/simple, free-list for small/reusable */
    VkDeviceSize block_size = XVK_MA_BLOCK_SIZE;
    if (is_host_visible) block_size = XVK_MA_LINEAR_SIZE;
    int use_linear = is_host_visible || reqs.size > (block_size / 4);

    /* Try existing blocks first, allocate new block if needed */
    XvkMaBlock* block = NULL;
    VkDeviceSize offset = (VkDeviceSize)-1;
    int bi;
    for (bi = 0; bi < pool->block_count; bi++) {
        XvkMaBlock* blk = pool->blocks[bi];
        if (blk->is_linear == use_linear) {
            if (use_linear)
                offset = linear_allocate(blk, reqs.size, reqs.alignment);
            else
                offset = freelist_allocate(blk, reqs.size, reqs.alignment);
            if (offset != (VkDeviceSize)-1) { block = blk; break; }
        }
    }
    if (!block) {
        /* Allocate new block */
        block = alloc_block(pool, block_size, use_linear);
        if (!block) { vkDestroyBuffer(dev, buf, NULL); return VK_ERROR_OUT_OF_DEVICE_MEMORY; }
        if (use_linear)
            offset = linear_allocate(block, reqs.size, reqs.alignment);
        else
            offset = freelist_allocate(block, reqs.size, reqs.alignment);
    }

    if (offset == (VkDeviceSize)-1) {
        vkDestroyBuffer(dev, buf, NULL);
        return VK_ERROR_OUT_OF_DEVICE_MEMORY;
    }

    /* Bind */
    res = vkBindBufferMemory(dev, buf, block->memory, offset);
    if (res != VK_SUCCESS) {
        vkDestroyBuffer(dev, buf, NULL);
        return res;
    }

    /* Write outputs */
    *(int64_t*)(intptr_t)out_buf_h  = (int64_t)(uint64_t)buf;
    *(int64_t*)(intptr_t)out_mem_h  = (int64_t)(uint64_t)block->memory;
    *(int64_t*)(intptr_t)out_off_h = (int64_t)offset;
    return VK_SUCCESS;
}

int32_t xvk_ma_allocate_image(int64_t create_info, int32_t flags,
                               int64_t out_img_h, int64_t out_mem_h) {
    if (!g_ma.device || !create_info) return VK_ERROR_INITIALIZATION_FAILED;
    VkImageCreateInfo* ici = (VkImageCreateInfo*)(intptr_t)create_info;
    VkDevice dev = g_ma.device;

    VkImage img = VK_NULL_HANDLE;
    VkResult res = vkCreateImage(dev, ici, NULL, &img);
    if (res != VK_SUCCESS) return res;

    VkMemoryRequirements reqs;
    vkGetImageMemoryRequirements(dev, img, &reqs);

    VkMemoryPropertyFlags want = VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT;
    uint32_t mem_type = ma_find_memory_type(reqs.memoryTypeBits, want);
    if (mem_type == UINT32_MAX)
        mem_type = ma_find_memory_type(reqs.memoryTypeBits, 0);
    if (mem_type == UINT32_MAX) { vkDestroyImage(dev, img, NULL); return VK_ERROR_OUT_OF_DEVICE_MEMORY; }

    XvkMaPool* pool = get_or_create_pool(mem_type,
        g_ma.mem_props.memoryTypes[mem_type].propertyFlags);
    if (!pool) { vkDestroyImage(dev, img, NULL); return VK_ERROR_OUT_OF_HOST_MEMORY; }

    /* Images always use linear allocation (large, contiguous) */
    XvkMaBlock* block = NULL;
    VkDeviceSize offset = (VkDeviceSize)-1;
    for (int i = 0; i < pool->block_count; i++) {
        XvkMaBlock* blk = pool->blocks[i];
        if (blk->is_linear) {
            offset = linear_allocate(blk, reqs.size, reqs.alignment);
            if (offset != (VkDeviceSize)-1) { block = blk; break; }
        }
    }
    if (!block) {
        block = alloc_block(pool, XVK_MA_BLOCK_SIZE, 1);
        if (!block) { vkDestroyImage(dev, img, NULL); return VK_ERROR_OUT_OF_DEVICE_MEMORY; }
        offset = linear_allocate(block, reqs.size, reqs.alignment);
    }

    res = vkBindImageMemory(dev, img, block->memory, offset);
    if (res != VK_SUCCESS) {
        vkDestroyImage(dev, img, NULL);
        return res;
    }

    *(int64_t*)(intptr_t)out_img_h = (int64_t)(uint64_t)img;
    *(int64_t*)(intptr_t)out_mem_h = (int64_t)(uint64_t)block->memory;
    return VK_SUCCESS;
}

void xvk_ma_free_buffer(int64_t buffer, int64_t memory) {
    if (buffer) vkDestroyBuffer(g_ma.device, (VkBuffer)(uint64_t)buffer, NULL);
    /* Free-list blocks mark memory as free; linear blocks are not individually freed */
    for (int p = 0; p < g_ma.pool_count; p++) {
        if (!g_ma.pools[p]) continue;
        for (int b = 0; b < g_ma.pools[p]->block_count; b++) {
            XvkMaBlock* blk = g_ma.pools[p]->blocks[b];
            if (blk->memory == (VkDeviceMemory)(uint64_t)memory && !blk->is_linear) {
                /* Free-list: add back as free chunk */
                XvkMaBlock* free_chunk = calloc(1, sizeof(XvkMaBlock));
                free_chunk->free_offset = 0; /* simplified — production needs offset tracking */
                free_chunk->free_size = blk->size;
                free_chunk->next_free = blk->next_free;
                blk->next_free = free_chunk;
                return;
            }
        }
    }
}

void xvk_ma_free_image(int64_t image, int64_t memory) {
    if (image) vkDestroyImage(g_ma.device, (VkImage)(uint64_t)image, NULL);
    (void)memory; /* linear blocks don't track individual frees */
}

int64_t xvk_ma_map(int64_t memory, int64_t offset, int64_t size) {
    void* ptr = NULL;
    VkResult res = vkMapMemory(g_ma.device, (VkDeviceMemory)(uint64_t)memory,
                                (VkDeviceSize)offset, (VkDeviceSize)size, 0, &ptr);
    if (res != VK_SUCCESS) return 0;
    return (int64_t)(intptr_t)ptr;
}

void xvk_ma_unmap(int64_t memory) {
    vkUnmapMemory(g_ma.device, (VkDeviceMemory)(uint64_t)memory);
}

int64_t xvk_ma_total_allocated() {
    int64_t total = 0;
    for (int p = 0; p < g_ma.pool_count; p++) {
        if (!g_ma.pools[p]) continue;
        for (int b = 0; b < g_ma.pools[p]->block_count; b++)
            total += (int64_t)g_ma.pools[p]->blocks[b]->size;
    }
    return total;
}

void xvk_ma_destroy() {
    for (int p = 0; p < g_ma.pool_count; p++) {
        if (!g_ma.pools[p]) continue;
        for (int b = 0; b < g_ma.pools[p]->block_count; b++) {
            XvkMaBlock* blk = g_ma.pools[p]->blocks[b];
            if (blk->mapped) vkUnmapMemory(g_ma.device, blk->memory);
            if (blk->memory) vkFreeMemory(g_ma.device, blk->memory, NULL);
            /* Free free-list chunks */
            XvkMaBlock* curr = blk->next_free;
            while (curr) { XvkMaBlock* next = curr->next_free; free(curr); curr = next; }
            free(blk);
        }
        free(g_ma.pools[p]);
    }
    memset(&g_ma, 0, sizeof(g_ma));
}
