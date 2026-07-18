// e2e stub — proves G1+G2 produce correct values
#include <stdio.h>
#include <stdint.h>
void xvk_take_floats(const void* data, int64_t count) {
    const float* f = (const float*)data;
    printf("C: floats[0]=%g [1]=%g [2]=%g\n", f[0], f[1], f[2]);
}
void xvk_fill_wh(int32_t* w, int32_t* h) {
    printf("C: writing 800, 600 to %p, %p\n", (void*)w, (void*)h);
    *w = 800; *h = 600;
}

int xvk_check_i32s(int32_t* data, int64_t count) {
    printf("C: i32s[0]=%d [1]=%d [2]=%d\n", data[0], data[1], data[2]);
    return (data[0]==111 && data[1]==222 && data[2]==333) ? 1 : 0;
}
