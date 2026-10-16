#!/usr/bin/env bash
# XIOM -- xiom.v4l repro: build + run the pinned-ABI probe on Linux (WSL/CI/Pi).
# Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
# Licensed under the MIT or Apache-2.0 license, at your option.
#
# Usage:  bash run-linux-abi-probe.sh <package-dir> [kernel-tree]
#   package-dir : the xiom-v4l package directory (this script lives in its
#                 docs/repro/)
#   kernel-tree : the pinned light clone (default /mnt/e/repos/linux-uapi-v6.19)
#
# The compile pulls the pin's real UAPI headers:
#   include/uapi/linux/videodev2.h + v4l2-common.h + v4l2-controls.h + bits.h
# with the docs/repro/uapi-shim overlay (headers_install-equivalent __user /
# <linux/compiler.h> handling, see uapi-shim/linux/compiler.h).
#
# Gates that run at compile time:
#   - the bridge's own _Static_asserts (pinned facts vs local struct defs)
#   - the generated 3107-fact gate (gen/v4l2_const_asserts.h) against the
#     pinned header text
# Then the runtime classification is exercised and recorded.
set -euo pipefail

PKG="${1:?usage: run-linux-abi-probe.sh <package-dir> [kernel-tree]}"
KERNEL="${2:-/mnt/e/repos/linux-uapi-v6.19}"
OUT="$PKG/docs/repro/gen/v4l2-linux-abi-probe.txt"

if ! [ -f "$KERNEL/include/uapi/linux/videodev2.h" ]; then
  echo "pinned kernel tree not found: $KERNEL" >&2
  exit 2
fi

cd /tmp
gcc -DXV_USE_REAL_UAPI -D__EXPORTED_HEADERS__ -Wall -Wextra \
  -I "$PKG/docs/repro/uapi-shim" \
  -I "$KERNEL/include/uapi" \
  -I "$KERNEL/arch/x86/include/uapi" \
  -I "$PKG/docs/repro/gen" \
  -o v4l2_abi_probe \
  "$PKG/docs/repro/v4l2_abi_probe.c" \
  "$PKG/src/v4l2_bridge.c"

./v4l2_abi_probe | tee "$OUT"
echo
echo "recorded: $OUT"
