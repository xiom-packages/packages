/* XIOM -- B-25 repro host: reports the pointer VALUE C receives.
 * Minimal C host for docs/repro/bindings-pilot/ptr-cast.
 * MIT OR Apache-2.0, XIOM Authors. */
#include <stdint.h>

#ifdef _WIN32
#define PT_EXPORT __declspec(dllexport)
#else
#define PT_EXPORT
#endif

/* What address does C receive for a `*UInt8` argument? */
PT_EXPORT long long __cdecl pt_see_ptr(void* p) { return (long long)(intptr_t)p; }

/* What value does C receive for an `Int64` argument? */
PT_EXPORT long long __cdecl pt_see_int(long long p) { return p; }
