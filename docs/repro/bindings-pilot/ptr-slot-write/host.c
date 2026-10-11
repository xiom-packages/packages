/* B-16 repro host: reads three u32s from a caller-owned buffer. */
#include <stdint.h>

#if defined(_WIN32)
__declspec(dllexport)
#endif
int xt_sum3(const uint32_t* p) { return (int)(p[0] + p[1] + p[2]); }
