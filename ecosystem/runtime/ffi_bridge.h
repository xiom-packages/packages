// XIOM FFI Bridge — Converts XIOM Vec/Str to C pointers
// Link with: xiomc program.xi ffi_bridge.c -l sqlite3 -l crypto -l curl -l ws2_32
#ifndef XIOM_FFI_BRIDGE_H
#define XIOM_FFI_BRIDGE_H
#include <stdint.h>
#include <stddef.h>

// Vec layout in XIOM: { void* data; int64_t len; int64_t cap; }
typedef struct { void* data; int64_t len; int64_t cap; } XiomVec;

// Extract raw pointer from XIOM Vec
void*   xiom_vec_ptr(XiomVec vec);
int64_t xiom_vec_len(XiomVec vec);

// Allocate/free native memory
void*   xiom_alloc(int64_t size_bytes);
void    xiom_free_ptr(void* ptr);

// Byte-level buffer access
uint8_t xiom_read_byte(void* buf, int64_t offset);
void    xiom_write_byte(void* buf, int64_t offset, uint8_t value);

// Copy data between XIOM Vec and C buffer
void    xiom_copy_from_vec(void* c_buf, XiomVec vec, int64_t offset, int64_t count);
void    xiom_copy_to_vec(XiomVec vec, void* c_buf, int64_t count);

// Create XIOM Vec from C data (returns Vec for XIOM to use)
XiomVec xiom_vec_from_c(void* data, int64_t len);

// String conversion
char*   xiom_str_to_cstr(const char* xiom_str, int64_t len);
void    xiom_free_cstr(char* cstr);

// Error handling for FFI calls
void    xiom_ffi_panic(const char* msg);
int32_t xiom_ffi_ok(void);  // returns 0 (success)

#endif
