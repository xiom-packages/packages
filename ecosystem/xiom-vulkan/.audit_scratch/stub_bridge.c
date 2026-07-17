// stub bridge for FFI validation — prints what C receives
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

void xvk_take_floats(int64_t data, int64_t count) {
    printf("C-SIDE ptr=%p count=%lld\n", (void*)data, (long long)count);
    fflush(stdout);
    if (data && count > 0 && count < 64) {
        float* f = (float*)data;
        printf("  as-f32:");
        for (int i = 0; i < (int)count && i < 8; i++) printf(" %g", f[i]);
        printf("\n");
        double* d = (double*)data;
        printf("  as-f64:");
        for (int i = 0; i < (int)count && i < 8; i++) printf(" %g", d[i]);
        printf("\n");
        int64_t* q = (int64_t*)data;
        printf("  as-i64:");
        for (int i = 0; i < (int)count && i < 8; i++) printf(" %lld", (long long)q[i]);
        printf("\n");
        fflush(stdout);
    }
}

void xvk_probe_out(int64_t w, int64_t h) {
    printf("C-SIDE out w=%lld h=%lld\n", (long long)w, (long long)h);
    fflush(stdout);
    if (w > 4096) { *(int32_t*)w = 800; }
    if (h > 4096) { *(int32_t*)h = 600; }
    printf("C-SIDE out wrote\n");
    fflush(stdout);
}

int xvk_take_f32_scalar(float a, float b) {
    printf("C-SIDE f32 a=%g b=%g\n", a, b); fflush(stdout);
    return (a == 1.5f && b == 0.25f) ? 1 : 0;
}
int xvk_take_f64_scalar(double a) {
    printf("C-SIDE f64 a=%g\n", a); fflush(stdout);
    return (a == 2.75) ? 1 : 0;
}

void xvk_recv_i32s(int32_t* data, int64_t count) {
    printf("C-SIDE i32s:"); for (int i=0;i<(int)count;i++) printf(" %d", data[i]);
    printf("\n"); fflush(stdout);
    if (count >= 2) { data[0] = 800; data[1] = 600; }
}
void xvk_recv_f32s(float* data, int64_t count) {
    printf("C-SIDE f32s:"); for (int i=0;i<(int)count;i++) printf(" %g", data[i]);
    printf("\n"); fflush(stdout);
}
void xvk_recv_i64s(int64_t* data, int64_t count) {
    printf("C-SIDE i64s:"); for (int i=0;i<(int)count;i++) printf(" %lld", (long long)data[i]);
    printf("\n"); fflush(stdout);
}

static float* g_staging = 0;
int64_t xvk_staging_create(int64_t bytes) {
    g_staging = (float*)calloc(1, (size_t)bytes);
    return (int64_t)g_staging;
}
void xvk_staging_destroy(int64_t st) { free((void*)st); }
void xvk_staging_set_f32(int64_t st, int64_t index, float value) { ((float*)st)[index] = value; }
float xvk_staging_get_f32(int64_t st, int64_t index) { return ((float*)st)[index]; }
void xvk_staging_set_i32(int64_t st, int64_t index, int64_t value) { ((int32_t*)st)[index] = (int32_t)value; }
int64_t xvk_staging_get_i32(int64_t st, int64_t index) { return ((int32_t*)st)[index]; }
void xvk_staging_set_i64(int64_t st, int64_t index, int64_t value) { ((int64_t*)st)[index] = value; }
int64_t xvk_staging_check_f32(int64_t st, int64_t index, float expected) {
    float got = ((float*)st)[index];
    printf("C-SIDE check[%lld] got=%g expected=%g\n", (long long)index, got, expected); fflush(stdout);
    return got == expected ? 1 : 0;
}
