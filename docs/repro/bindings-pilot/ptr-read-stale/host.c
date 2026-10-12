#include <stdint.h>

/* B-24 repro host: write 8 bytes through a caller-owned pointer. */
void __cdecl poke8(unsigned char* dst, uint64_t v) { *(uint64_t*)dst = v; }
