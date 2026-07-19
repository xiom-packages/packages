/* xvk_memory_alloc.h — VMA-style memory sub-allocator for production use
 * Phase 7.1: Eliminates vkAllocateMemory count limits via block sub-allocation.
 *
 * Architecture:
 *   - Large VkDeviceMemory blocks pre-allocated per memory type
 *   - Linear allocator for per-frame transient data (DEVICE_LOCAL, ring buffer)
 *   - Free-list allocator for persistent resources (HOST_VISIBLE, general pool)
 *   - Automatic memory type selection from VkMemoryRequirements
 *
 * Usage:
 *   1. xvk_ma_init(physical_device, device) — one-time init
 *   2. xvk_ma_allocate_buffer(create_info, flags, &buf, &mem, &offset)
 *   3. xvk_ma_map(mem, offset, size) — map for CPU access
 *   4. xvk_ma_unmap(mem)
 *   5. xvk_ma_free_buffer(buf, mem)
 *   6. xvk_ma_destroy() — cleanup all pools
 */
#ifndef XVK_MA_H_
#define XVK_MA_H_

#include <stdint.h>
#include <vulkan/vulkan.h>

#define XVK_MA_MAX_HEAPS      4
#define XVK_MA_MAX_MEM_TYPES  32
#define XVK_MA_BLOCK_SIZE     (64ULL * 1024 * 1024)  /* 64 MB default block */
#define XVK_MA_LINEAR_SIZE    (16ULL * 1024 * 1024)  /* 16 MB linear ring */
#define XVK_MA_MAX_BLOCKS     16

/* Memory block — one VkDeviceMemory allocation */
typedef struct XvkMaBlock {
    VkDeviceMemory      memory;
    VkDeviceSize        size;
    VkDeviceSize        used;        // linear: next free offset; free-list: used bytes
    uint32_t            memory_type;
    void*               mapped;      // NULL if not host-visible
    int                 is_linear;   // 1 = ring/linear, 0 = free-list
    struct XvkMaBlock*  next_free;   // free-list: next free chunk
    VkDeviceSize        free_offset; // free-list: offset of this free chunk
    VkDeviceSize        free_size;   // free-list: size of this free chunk
} XvkMaBlock;

/* Pool — collection of blocks for one memory type */
typedef struct XvkMaPool {
    XvkMaBlock*         blocks[XVK_MA_MAX_BLOCKS];
    int                 block_count;
    VkMemoryPropertyFlags properties;
    uint32_t            memory_type_index;
} XvkMaPool;

/* Main allocator state */
typedef struct XvkMaState {
    VkPhysicalDevice            phys_dev;
    VkDevice                    device;
    VkPhysicalDeviceMemoryProperties mem_props;
    XvkMaPool*                  pools[XVK_MA_MAX_MEM_TYPES];
    int                         pool_count;
} XvkMaState;

/* Public API */

/* Initialize allocator. Call once after device creation. */
int32_t xvk_ma_init(int64_t physical_device, int64_t device);

/* Allocate a VkBuffer with sub-allocated memory.
 *   create_info: VkBufferCreateInfo* struct
 *   flags: 0 = default, 1 = DEVICE_LOCAL preferred, 2 = HOST_VISIBLE preferred
 *   out_buffer: receives VkBuffer handle
 *   out_memory: receives VkDeviceMemory handle (block memory)
 *   out_offset: receives byte offset within the block
 * Returns VK_SUCCESS or error code. */
int32_t xvk_ma_allocate_buffer(int64_t create_info, int32_t flags,
                                int64_t out_buffer, int64_t out_memory, int64_t out_offset);

/* Allocate a VkImage with sub-allocated memory (linear allocation only).
 *   create_info: VkImageCreateInfo* struct
 *   flags: as above
 *   out_image: receives VkImage handle
 *   out_memory: receives VkDeviceMemory handle
 * Returns VK_SUCCESS or error code. */
int32_t xvk_ma_allocate_image(int64_t create_info, int32_t flags,
                               int64_t out_image, int64_t out_memory);

/* Free a buffer allocated via xvk_ma_allocate_buffer. */
void xvk_ma_free_buffer(int64_t buffer, int64_t memory);

/* Free an image allocated via xvk_ma_allocate_image. */
void xvk_ma_free_image(int64_t image, int64_t memory);

/* Map a sub-allocation for CPU access. offset must be the one returned by allocate.
 * Returns: pointer as int64_t, or 0 on failure. */
int64_t xvk_ma_map(int64_t memory, int64_t offset, int64_t size);

/* Unmap a previously mapped allocation. */
void xvk_ma_unmap(int64_t memory);

/* Return the total bytes allocated across all pools. */
int64_t xvk_ma_total_allocated();

/* Destroy the allocator, freeing all pools and blocks. Call on shutdown. */
void xvk_ma_destroy();

#endif /* XVK_MA_H_ */
