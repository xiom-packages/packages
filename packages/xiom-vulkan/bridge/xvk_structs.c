#include "xvk_structs.h"

#include <stdlib.h>
#include <string.h>

static uint8_t* xvk_struct_ptr(int64_t handle, int64_t offset)
{
    if (handle == 0 || offset < 0) return NULL;
    return (uint8_t*)(intptr_t)handle + offset;
}

int64_t xvk_alloc(int64_t size_bytes)
{
    if (size_bytes <= 0) return 0;
    void* p = calloc(1, (size_t)size_bytes);
    return (int64_t)(intptr_t)p;
}

void xvk_free(int64_t handle)
{
    if (handle == 0) return;
    free((void*)(intptr_t)handle);
}

void xvk_write_u32(int64_t handle, int64_t offset, int32_t value)
{
    uint8_t* dst = xvk_struct_ptr(handle, offset);
    if (!dst) return;
    uint32_t v = (uint32_t)value;
    memcpy(dst, &v, sizeof(v));
}

void xvk_write_u64(int64_t handle, int64_t offset, int64_t value)
{
    uint8_t* dst = xvk_struct_ptr(handle, offset);
    if (!dst) return;
    uint64_t v = (uint64_t)value;
    memcpy(dst, &v, sizeof(v));
}

void xvk_write_f32(int64_t handle, int64_t offset, float value)
{
    uint8_t* dst = xvk_struct_ptr(handle, offset);
    if (!dst) return;
    memcpy(dst, &value, sizeof(value));
}

void xvk_write_str(int64_t handle, int64_t offset, const char* str)
{
    uint8_t* dst = xvk_struct_ptr(handle, offset);
    if (!dst) return;
    char* copy = NULL;
    if (str) {
        size_t len = strlen(str) + 1;
        copy = (char*)malloc(len);
        if (copy) memcpy(copy, str, len);
    }
    uint64_t v = (uint64_t)(uintptr_t)copy;
    memcpy(dst, &v, sizeof(v));
}

void xvk_write_handle(int64_t handle, int64_t offset, int64_t vk_handle)
{
    xvk_write_u64(handle, offset, vk_handle);
}

void xvk_write_array(int64_t handle, int64_t offset, int64_t src_handle, int64_t elem_count, int64_t elem_size)
{
    uint8_t* dst = xvk_struct_ptr(handle, offset);
    if (!dst || src_handle == 0) return;
    if (elem_count <= 0 || elem_size <= 0) return;
    const void* src = (const void*)(intptr_t)src_handle;
    memcpy(dst, src, (size_t)elem_count * (size_t)elem_size);
}

int32_t xvk_read_u32(int64_t handle, int64_t offset)
{
    const uint8_t* src = xvk_struct_ptr(handle, offset);
    if (!src) return 0;
    uint32_t v = 0;
    memcpy(&v, src, sizeof(v));
    return (int32_t)v;
}

int64_t xvk_read_u64(int64_t handle, int64_t offset)
{
    const uint8_t* src = xvk_struct_ptr(handle, offset);
    if (!src) return 0;
    uint64_t v = 0;
    memcpy(&v, src, sizeof(v));
    return (int64_t)v;
}

float xvk_read_f32(int64_t handle, int64_t offset)
{
    const uint8_t* src = xvk_struct_ptr(handle, offset);
    if (!src) return 0.0f;
    float v = 0.0f;
    memcpy(&v, src, sizeof(v));
    return v;
}

void xvk_set_sType(int64_t handle, int32_t sType_value)
{
    xvk_write_u32(handle, 0, sType_value);
}

void xvk_set_pNext(int64_t handle, int64_t pNext_handle)
{
    xvk_write_u64(handle, 8, pNext_handle);
}
