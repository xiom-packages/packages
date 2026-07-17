// stub bridge for FFI validation — prints what C receives
#include <stdio.h>
#include <stdint.h>
#include <string.h>

void xvk_take_floats(int64_t data, int64_t count) {
    printf("C-SIDE ptr=%p count=%lld\n", (void*)data, (long long)count);
    fflush(stdout);
    if (data && count > 0 && count < 64) {
        // interpret as float32 array
        float* f = (float*)data;
        printf("  as-f32:");
        for (int i = 0; i < (int)count && i < 8; i++) printf(" %g", f[i]);
        printf("\n");
        // interpret as f64 array
        double* d = (double*)data;
        printf("  as-f64:");
        for (int i = 0; i < (int)count && i < 8; i++) printf(" %g", d[i]);
        printf("\n");
        // interpret as i64 array
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
    if (w > 4096) { *(int32_t*)w = 800; }  // only write if it looks like a pointer
    if (h > 4096) { *(int32_t*)h = 600; }
    printf("C-SIDE out wrote\n");
    fflush(stdout);
}
