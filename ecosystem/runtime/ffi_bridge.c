// XIOM FFI Bridge Implementation
#include "ffi_bridge.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

void* xiom_vec_ptr(XiomVec vec) {
    return vec.data;
}

int64_t xiom_vec_len(XiomVec vec) {
    return vec.len;
}

void* xiom_alloc(int64_t size_bytes) {
    if (size_bytes <= 0) return NULL;
    void* p = malloc((size_t)size_bytes);
    if (p) memset(p, 0, (size_t)size_bytes);
    return p;
}

void xiom_free_ptr(void* ptr) {
    if (ptr) free(ptr);
}

uint8_t xiom_read_byte(void* buf, int64_t offset) {
    if (!buf || offset < 0) return 0;
    return ((uint8_t*)buf)[offset];
}

void xiom_write_byte(void* buf, int64_t offset, uint8_t value) {
    if (!buf || offset < 0) return;
    ((uint8_t*)buf)[offset] = value;
}

void xiom_copy_from_vec(void* c_buf, XiomVec vec, int64_t offset, int64_t count) {
    if (!c_buf || !vec.data || offset < 0 || count <= 0) return;
    if (offset + count > vec.len) count = vec.len - offset;
    if (count <= 0) return;
    memcpy(c_buf, (uint8_t*)vec.data + offset, (size_t)count);
}

void xiom_copy_to_vec(XiomVec vec, void* c_buf, int64_t count) {
    if (!vec.data || !c_buf || count <= 0) return;
    if (count > vec.cap) count = vec.cap;
    memcpy(vec.data, c_buf, (size_t)count);
}

XiomVec xiom_vec_from_c(void* data, int64_t len) {
    XiomVec v;
    v.data = data;
    v.len = len;
    v.cap = len;
    return v;
}

char* xiom_str_to_cstr(const char* xiom_str, int64_t len) {
    if (!xiom_str || len <= 0) return NULL;
    char* cstr = (char*)malloc((size_t)len + 1);
    if (!cstr) return NULL;
    memcpy(cstr, xiom_str, (size_t)len);
    cstr[len] = '\0';
    return cstr;
}

void xiom_free_cstr(char* cstr) {
    if (cstr) free(cstr);
}

void xiom_ffi_panic(const char* msg) {
    fprintf(stderr, "XIOM FFI PANIC: %s\n", msg ? msg : "unknown error");
    abort();
}

int32_t xiom_ffi_ok(void) {
    return 0;
}
