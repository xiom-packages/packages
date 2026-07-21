#ifndef XVK_STRUCTS_H_
#define XVK_STRUCTS_H_

#include <stdint.h>

/*
 * Generic struct marshalling layer for the XIOM <-> Vulkan FFI boundary.
 *
 * XIOM has no C struct support, so Vulkan structs are built from XIOM code
 * via raw byte-offset pointer arithmetic. All handles are int64_t values
 * holding raw pointers (0 = NULL/invalid).
 */

/* Allocate zeroed memory of given size. Returns handle (int64_t pointer). */
int64_t xvk_alloc(int64_t size_bytes);

/* Free allocated memory. */
void xvk_free(int64_t handle);

/* Write a uint32 at byte offset within the struct. */
void xvk_write_u32(int64_t handle, int64_t offset, int32_t value);

/* Write a uint64 (pointer/handle) at byte offset. */
void xvk_write_u64(int64_t handle, int64_t offset, int64_t value);

/* Write a float32 at byte offset. */
void xvk_write_f32(int64_t handle, int64_t offset, float value);

/* Write a null-terminated string at byte offset (stores pointer to malloc'd copy). */
void xvk_write_str(int64_t handle, int64_t offset, const char* str);

/* Write a pointer/handle field (same as write_u64 but semantically for VK handles). */
void xvk_write_handle(int64_t handle, int64_t offset, int64_t vk_handle);

/* Write an array of structs at byte offset (copies count*elem_size bytes from src). */
void xvk_write_array(int64_t handle, int64_t offset, int64_t src_handle, int64_t elem_count, int64_t elem_size);

/* Read a uint32 from byte offset. */
int32_t xvk_read_u32(int64_t handle, int64_t offset);

/* Read a uint64 from byte offset. */
int64_t xvk_read_u64(int64_t handle, int64_t offset);

/* Read a float32 from byte offset. */
float xvk_read_f32(int64_t handle, int64_t offset);

/* Set the sType field (uint32 at offset 0) — convenience for all VK structs. */
void xvk_set_sType(int64_t handle, int32_t sType_value);

/* Set the pNext field (uint64 at offset 8 in 64-bit) — convenience. */
void xvk_set_pNext(int64_t handle, int64_t pNext_handle);

#endif
