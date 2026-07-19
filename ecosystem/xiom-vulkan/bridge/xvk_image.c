#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"
#include "xvk_image.h"
#include <stdlib.h>

int64_t xvk_image_load(const char* filepath,
                        int64_t out_width, int64_t out_height)
{
    if (!filepath || !out_width || !out_height) return 0;

    int w = 0, h = 0, channels = 0;
    unsigned char* pixels = stbi_load(filepath, &w, &h, &channels, 4);
    if (!pixels) return 0;

    int32_t* w_ptr = (int32_t*)(intptr_t)out_width;
    int32_t* h_ptr = (int32_t*)(intptr_t)out_height;
    if (w_ptr) *w_ptr = w;
    if (h_ptr) *h_ptr = h;

    return (int64_t)(intptr_t)pixels;
}

void xvk_image_free(int64_t pixels)
{
    if (pixels) stbi_image_free((void*)(intptr_t)pixels);
}
