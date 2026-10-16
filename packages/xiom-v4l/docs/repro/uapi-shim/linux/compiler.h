/* XIOM -- xiom.v4l repro shim: linux/compiler.h for the pinned UAPI parse.
 * Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
 * Licensed under the MIT or Apache-2.0 license, at your option.
 *
 * WHY THIS FILE EXISTS
 * The pinned kernel tag (torvalds/linux v6.19) `include/uapi/linux/videodev2.h`
 * line 63 contains `#include <linux/compiler.h>`, and that header is not part
 * of the UAPI tree at the pin (verified: `git ls-tree v6.19
 * include/uapi/linux/compiler.h` is empty).  Upstream consumers never see the
 * line: `make headers_install` post-processes UAPI headers (see
 * scripts/headers_install.sh) and strips kernel-internal includes and the
 * `__user` annotation before installing them (Ubuntu's installed
 * /usr/include/linux/videodev2.h carries neither).
 *
 * To evaluate the PINNED header text verbatim (upstream-first; no retyping),
 * the repro toolchain pre-includes this overlay dir ahead of the pinned tree.
 * It provides exactly the macro surface that headers_install removes:
 * `__user` expands to nothing.  Beyond `__user`, videodev2.h at the pin only
 * relies on compiler builtins (`__attribute__`) and its own conditionals.
 */
#ifndef _XV_UAPI_SHIM_LINUX_COMPILER_H
#define _XV_UAPI_SHIM_LINUX_COMPILER_H

#define __user

#endif /* _XV_UAPI_SHIM_LINUX_COMPILER_H */
