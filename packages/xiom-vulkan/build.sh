#!/usr/bin/env bash
#
# build.sh -- Build the xiom-vulkan bridge and XIOM target (demo / test).
#
# Pipeline:
#   1. Compile GLSL shaders to SPIR-V via glslc
#   2. Generate bridge/xvk_shaders_generated.h with uint32 SPIR-V arrays
#   3. Compile the C bridge to an object file
#   4. Build the XIOM target with xiom
#
# Usage:
#   ./build.sh                    # demo2d (default)
#   ./build.sh demo3d             # 3D spinning cube
#   ./build.sh test               # offscreen test
#   ./build.sh test --run         # build + run test
#   ./build.sh particles --run    # GPU particle fountain
#   ./build.sh shapes --run       # animated 2D quads + triangle
#   ./build.sh cubes --run        # field of spinning 3D cubes
#   GLFW_DIR=/path ./build.sh     # custom GLFW path
#
# Prerequisites:
#   - Vulkan SDK >= 1.3  (via $VULKAN_SDK or system paths)
#   - glslc  (from Vulkan SDK: $VULKAN_SDK/bin/glslc, or on PATH)
#   - GLFW 3.4 dev libraries  (via pkg-config or $GLFW_DIR)
#   - clang / LLVM
#   - Rust toolchain (for cargo run -p xiom)
#
# On Linux, most distros ship libvulkan-dev and libglfw3-dev.
# The script prefers pkg-config for GLFW flags and auto-detects
# Vulkan system paths; if $VULKAN_SDK is set it uses that instead.
#
# On macOS with MoltenVK, set VULKAN_SDK and ensure glslc is on PATH.
# GLFW can be installed via HomeBrew:  brew install glfw
#==============================================================================#

set -euo pipefail

# ---- helpers ----------------------------------------------------------------
die() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[build] $*"; }

# ---- paths ------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$SCRIPT_DIR"
BRIDGE_DIR="$ROOT_DIR/bridge"
SHADER_DIR="$BRIDGE_DIR/shaders"
SPV_DIR="$BRIDGE_DIR/spv"
GEN_HEADER="$BRIDGE_DIR/xvk_shaders_generated.h"
BRIDGE_SRC="$BRIDGE_DIR/xiom_vk_bridge.c"

# ---- target selection -------------------------------------------------------
TARGET="${1:-demo2d}"
shift 1 2>/dev/null || true
RUN_MODE=0
for arg in "$@"; do
    case "$arg" in
        --run) RUN_MODE=1 ;;
        *)     die "Unknown argument: $arg" ;;
    esac
done

case "$TARGET" in
    demo2d)
        ENTRY_FILE="$ROOT_DIR/examples/demo_2d.xi"
        OUT_NAME="demo_2d"
        ;;
    demo3d)
        ENTRY_FILE="$ROOT_DIR/examples/demo_3d.xi"
        OUT_NAME="demo_3d"
        ;;
    test)
        ENTRY_FILE="$ROOT_DIR/tests/test_vulkan.xi"
        OUT_NAME="test_vulkan"
        ;;
    particles)
        ENTRY_FILE="$ROOT_DIR/examples/demo_particles.xi"
        OUT_NAME="demo_particles"
        ;;
    shapes)
        ENTRY_FILE="$ROOT_DIR/examples/demo_shapes.xi"
        OUT_NAME="demo_shapes"
        ;;
    cubes)
        ENTRY_FILE="$ROOT_DIR/examples/demo_cubes.xi"
        OUT_NAME="demo_cubes"
        ;;
    *)
        die "Unknown target '$TARGET'. Valid: demo2d, demo3d, test, particles, shapes, cubes"
        ;;
esac
OUT_EXE="$ROOT_DIR/$OUT_NAME"

# ---- resolve Vulkan SDK -----------------------------------------------------
if [ -n "${VULKAN_SDK:-}" ]; then
    info "Vulkan SDK: $VULKAN_SDK"
    VK_INCLUDE="$VULKAN_SDK/include"
    VK_LIB="$VULKAN_SDK/lib"
    if [ ! -d "$VK_INCLUDE" ]; then
        die "Vulkan SDK include not found at '$VK_INCLUDE'"
    fi
else
    # System paths (Linux / macOS via MoltenVK)
    VK_INCLUDE="/usr/include"
    VK_LIB="/usr/lib"
    info "Vulkan SDK not set, using system paths"
fi

# glslc
GLSL_CANDIDATES=()
if [ -n "${VULKAN_SDK:-}" ]; then
    GLSL_CANDIDATES+=("$VULKAN_SDK/bin/glslc")
fi
GLSL_CANDIDATES+=("$(command -v glslc 2>/dev/null || true)")
GLSLC=""
for c in "${GLSL_CANDIDATES[@]}"; do
    if [ -n "$c" ] && [ -x "$c" ]; then
        GLSLC="$c"
        break
    fi
done
if [ -z "$GLSLC" ]; then
    die "glslc not found.  Set VULKAN_SDK or install glslc on PATH."
fi
info "glslc: $GLSLC"

# ---- resolve GLFW -----------------------------------------------------------
if pkg-config --exists glfw3 2>/dev/null; then
    GLFW_CFLAGS="$(pkg-config --cflags glfw3)"
    GLFW_LIBS="$(pkg-config --libs glfw3)"
    info "GLFW via pkg-config: $GLFW_CFLAGS"
elif [ -n "${GLFW_DIR:-}" ]; then
    GLFW_DIR="${GLFW_DIR%/}"  # strip trailing slash
    GLFW_INCLUDE="$GLFW_DIR/include"
    if [ ! -d "$GLFW_INCLUDE" ]; then
        # Common mistake: GLFW_DIR set to the lib subfolder instead of root.
        # Walk up one level and try again.
        GLFW_PARENT="$(dirname "$GLFW_DIR")"
        if [ -n "$GLFW_PARENT" ] && [ -d "$GLFW_PARENT/include" ]; then
            info "[build] GLFW_DIR was set to '$GLFW_DIR' but 'include/' is at '$GLFW_PARENT'. Auto-correcting."
            GLFW_DIR="$GLFW_PARENT"
            GLFW_INCLUDE="$GLFW_DIR/include"
        fi
    fi
    if [ ! -d "$GLFW_INCLUDE" ]; then
        die "GLFW include not found at '$GLFW_INCLUDE'.  Set GLFW_DIR to the root (the folder containing include/GLFW/glfw3.h)."
    fi
    GLFW_LIB="$GLFW_DIR/lib"
    GLFW_CFLAGS="-I$GLFW_INCLUDE"
    GLFW_LIBS="-L$GLFW_LIB -lglfw3"
    info "GLFW dir: $GLFW_DIR"
else
    # Fallback: assume system paths (Linux)
    GLFW_CFLAGS=""
    GLFW_LIBS="-lglfw3"
    info "GLFW: assuming system paths (pkg-config unavailable, GLFW_DIR unset)"
fi
    GLFW_CFLAGS="-I$GLFW_INCLUDE"
    GLFW_LIBS="-L$GLFW_LIB -lglfw3"
    info "GLFW dir: $GLFW_DIR"
else
    # Fallback: assume system paths (Linux)
    GLFW_CFLAGS=""
    GLFW_LIBS="-lglfw3"
    info "GLFW: assuming system paths (pkg-config unavailable, GLFW_DIR unset)"
fi

# ---- resolve clang ----------------------------------------------------------
CLANG="$(command -v clang 2>/dev/null || true)"
if [ -z "$CLANG" ]; then
    die "clang not found on PATH.  Install LLVM."
fi
info "clang: $CLANG"

# ---- resolve Vulkan link library --------------------------------------------
# Linux: -l vulkan, macOS with MoltenVK: -l MoltenVK or framework
UNAME_S="$(uname -s)"
case "$UNAME_S" in
    Linux)  VK_LINK="-lvulkan" ;;
    Darwin) VK_LINK="-lvulkan" ;;  # MoltenVK via Vulkan SDK or system
    *)      VK_LINK="-lvulkan" ;;
esac

# ---- STEP 1: Compile shaders ------------------------------------------------
info ""
info "=== STEP 1: Compile GLSL shaders to SPIR-V ==="
mkdir -p "$SPV_DIR"

declare -A SHADER_MAP
SHADER_MAP["triangle_vert"]="$SHADER_DIR/triangle.vert"
SHADER_MAP["triangle_frag"]="$SHADER_DIR/triangle.frag"
SHADER_MAP["cube_vert"]="$SHADER_DIR/cube.vert"
SHADER_MAP["cube_frag"]="$SHADER_DIR/cube.frag"
SHADER_MAP["quad_vert"]="$SHADER_DIR/quad.vert"
SHADER_MAP["quad_frag"]="$SHADER_DIR/quad.frag"
SHADER_MAP["particle_vert"]="$SHADER_DIR/particle.vert"
SHADER_MAP["particle_frag"]="$SHADER_DIR/particle.frag"

# We compile each shader twice: once to binary .spv for verification,
# and once with -mfmt=num to get uint32 words without endianness issues.

# Array to hold generated header lines
HEADER_LINES=()
HEADER_LINES+=("// AUTO-GENERATED -- do not edit")
HEADER_LINES+=("#ifndef XVK_SHADERS_GENERATED_H_")
HEADER_LINES+=("#define XVK_SHADERS_GENERATED_H_")
HEADER_LINES+=("")

for NAME in "${!SHADER_MAP[@]}"; do
    SRC="${SHADER_MAP[$NAME]}"
    SPV_FILE="$SPV_DIR/${NAME}.spv"

    info "  glslc: $NAME"

    # Compile to binary .spv (for verification)
    "$GLSLC" -o "$SPV_FILE" "$SRC"
    if [ ! -s "$SPV_FILE" ]; then
        die "glslc produced empty file for $NAME"
    fi

    # Check size is multiple of 4
    SPV_SIZE=$(stat -c%s "$SPV_FILE" 2>/dev/null || stat -f%z "$SPV_FILE" 2>/dev/null)
    if [ $((SPV_SIZE % 4)) -ne 0 ]; then
        die "SPIR-V $NAME has size $SPV_SIZE, not a multiple of 4!"
    fi

    # Get uint32 words via -mfmt=num (endian-safe)
    # Output is comma-separated decimal numbers, possibly with newlines
    WORDS_RAW=$("$GLSLC" -mfmt=num -o - "$SRC" 2>/dev/null)
    # Flatten whitespace and remove trailing newline
    WORDS_RAW=$(echo "$WORDS_RAW" | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')
    # Count words (comma-separated)
    WORD_COUNT=$(echo "$WORDS_RAW" | tr -cd ',' | wc -c)
    WORD_COUNT=$((WORD_COUNT + 1))
    BYTE_LEN=$((WORD_COUNT * 4))

    if [ "$BYTE_LEN" -ne "$SPV_SIZE" ]; then
        die "Word-count byte estimate ($BYTE_LEN) != file size ($SPV_SIZE) for $NAME"
    fi

    # Build the C symbols
    # -mfmt=num output is like "119734787, 131075, 524295, ..."
    SYM="xvk_${NAME}_spv"
    LEN_SYM="${SYM}_len"
    HEADER_LINES+=("const unsigned int ${SYM}[] = { ${WORDS_RAW} };")
    HEADER_LINES+=("const unsigned int ${LEN_SYM} = ${BYTE_LEN};")
    HEADER_LINES+=("")

    info "    -> ${SPV_SIZE} bytes, ${WORD_COUNT} words"
done

HEADER_LINES+=("#endif /* XVK_SHADERS_GENERATED_H_ */")
HEADER_LINES+=("")

# ---- STEP 2: Write generated header -----------------------------------------
info ""
info "=== STEP 2: Write $GEN_HEADER ==="
printf '%s\n' "${HEADER_LINES[@]}" > "$GEN_HEADER"
info "  Wrote ${#SHADER_MAP[@]} shader arrays to $GEN_HEADER"

# ---- STEP 3: Compile C bridge to object file --------------------------------
info ""
info "=== STEP 3: Compile C bridge ==="

# Determine object extension and PIC flag
BRIDGE_OBJ="$BRIDGE_DIR/xiom_vk_bridge.o"
PIC_FLAG=""
case "$UNAME_S" in
    Linux|Darwin) PIC_FLAG="-fPIC" ;;
esac

# Build clang flags
CLANG_FLAGS=(
    -c "$BRIDGE_SRC"
    -o "$BRIDGE_OBJ"
    -I "$VK_INCLUDE"
    -O2
    "$PIC_FLAG"
)
# Add GLFW flags (from pkg-config or manual)
# shellcheck disable=SC2206
CLANG_FLAGS+=($GLFW_CFLAGS)

info "  $CLANG ${CLANG_FLAGS[*]}"
"$CLANG" "${CLANG_FLAGS[@]}"
info "  -> $BRIDGE_OBJ"

# ---- STEP 4: Build XIOM target ----------------------------------------------
info ""
info "=== STEP 4: Build XIOM target ($TARGET) ==="

XI_FILES=(
    "$ENTRY_FILE"
    "$ROOT_DIR/vulkan.xi"
    "$ROOT_DIR/src/wrapper.xi"
)

# xiom: use cargo run -p xiom for dev workflow.
# Replace with "xiom" when a prebuilt binary is available.
xiom_CMD=(cargo run -p xiom --)

xiom_ARGS=(
    -o "$OUT_EXE"
    "${XI_FILES[@]}"
    --c-source "$BRIDGE_OBJ"
    --link vulkan
    --link glfw3
)

# Add link paths for Vulkan and GLFW (manual paths; pkg-config
# already added -L via GLFW_LIBS if applicable).
if [ -n "${VULKAN_SDK:-}" ]; then
    xiom_ARGS+=(--link-path "$VK_LIB")
fi

# Add GLFW lib path if not handled by pkg-config linker flags
# shellcheck disable=SC2076
if [[ ! "$GLFW_LIBS" =~ "-L" ]]; then
    if [ -n "${GLFW_LIB:-}" ]; then
        xiom_ARGS+=(--link-path "$GLFW_LIB")
    fi
fi

# For the test target, automatically run it
if [ "$TARGET" = "test" ]; then
    xiom_ARGS+=(--run)
fi

info "  ${xiom_CMD[*]} ${xiom_ARGS[*]}"
(cd "$ROOT_DIR" && "${xiom_CMD[@]}" "${xiom_ARGS[@]}")
info "SUCCESS: $OUT_EXE"

# ---- Run (optional) ---------------------------------------------------------
if [ "$RUN_MODE" -eq 1 ] && [ "$TARGET" != "test" ]; then
    info "Running $OUT_EXE ..."
    echo ""
    "$OUT_EXE"
fi
