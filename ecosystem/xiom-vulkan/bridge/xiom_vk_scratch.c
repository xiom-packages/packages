// xiom_vk_scratch.c — standalone scratch marshalling for v0.46 FFI
// Copyright (c) 2026 Eleftherios Notas
// No Vulkan/GLFW dependencies — pure libc.
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

static void* xvk_scratch_alloc(int64_t bytes) {
    return calloc(1, (size_t)bytes);
}

int64_t xvk_scratch_i32_create(int64_t count) {
    return (int64_t)xvk_scratch_alloc(count * 4);
}

int64_t xvk_scratch_i64_create(int64_t count) {
    return (int64_t)xvk_scratch_alloc(count * 8);
}

int64_t xvk_scratch_f32_create(int64_t count) {
    return (int64_t)xvk_scratch_alloc(count * 4);
}

int64_t xvk_scratch_u16_create(int64_t count) {
    return (int64_t)xvk_scratch_alloc(count * 2);
}

int64_t xvk_scratch_u32_create(int64_t count) {
    return (int64_t)xvk_scratch_alloc(count * 4);
}

void xvk_scratch_destroy(int64_t handle) {
    free((void*)handle);
}

void xvk_scratch_set_i32(int64_t handle, int64_t index, int32_t value) {
    ((int32_t*)handle)[index] = value;
}

int32_t xvk_scratch_get_i32(int64_t handle, int64_t index) {
    return ((int32_t*)handle)[index];
}

void xvk_scratch_set_i64(int64_t handle, int64_t index, int64_t value) {
    ((int64_t*)handle)[index] = value;
}

void xvk_scratch_set_f32(int64_t handle, int64_t index, float value) {
    ((float*)handle)[index] = value;
}

void xvk_scratch_set_u16(int64_t handle, int64_t index, uint16_t value) {
    ((uint16_t*)handle)[index] = value;
}

void xvk_scratch_set_u32(int64_t handle, int64_t index, uint32_t value) {
    ((uint32_t*)handle)[index] = value;
}

float xvk_scratch_get_f32(int64_t handle, int64_t index) {
    return ((float*)handle)[index];
}
