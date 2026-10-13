/* XIOM -- minimal <strings.h> for the Windows clang target.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * SPDX-License-Identifier: MIT OR Apache-2.0
 *
 * The vendored libktx writers include <strings.h> under `#if defined(__GNUC__)`
 * (true for clang even when targeting the MSVC ABI), but the Windows UCRT has
 * no strings.h. The writers already map strncasecmp to _strnicmp for MSVC; this
 * header exists so the include resolves. tools/vendor_ktx.py rewrites the
 * directive to this file. No functions are declared here.
 */

#ifndef XIOM_KTX2_COMPAT_STRINGS_H
#define XIOM_KTX2_COMPAT_STRINGS_H

#include <string.h>

#if defined(_MSC_VER) || defined(_WIN32)
#include <ctype.h>
#ifndef strcasecmp
#define strcasecmp _stricmp
#endif
#ifndef strncasecmp
#define strncasecmp _strnicmp
#endif
#endif

#endif /* XIOM_KTX2_COMPAT_STRINGS_H */
