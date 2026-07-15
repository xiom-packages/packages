# xiom-opencv — System Dependency Audit

> **Version:** 0.1.0 | **Compiler:** xiomc v0.45.3 | **Status:** All modules compile clean.

## Compiler Compatibility

All `.xi` source files pass `xiomc --check` with `{"status":"ok"}`.

### Fixes Applied (v0.45.3)

| File | Issue | Fix |
|------|-------|------|
| `src/io.xi` | `.clone()` on `Vec[Int]` — method not registered | Replaced with manual `copy_vec_int` helper using `Vec.push` loop |
| `src/io.xi` | `Unit` type unknown; `Ok(Unit{})` parse error | Changed `Result[Unit, Str]` → `Result[Bool, Str]`, returns `Ok(true)` |

## System Dependency: OpenCV

The FFI tier (`xiom.opencv.io`, `xiom.opencv.features`) requires **OpenCV 4.x** native library. All FFI functions are stubbed; they return dummy values until the native library is linked.

**Note:** The `xiom.opencv.filters` module is **pure XIOM** — no external dependencies. Blur, grayscale, threshold, Sobel edges, and nearest-neighbor resize work without OpenCV.

### Install Instructions

#### Windows
```powershell
# Via vcpkg (recommended)
vcpkg install opencv:x64-windows

# Or download pre-built binaries from:
# https://opencv.org/releases/

Build with:
  xiomc myprogram.xi $(pkg-config --cflags --libs opencv4)
```

#### Ubuntu / Debian
```bash
sudo apt update
sudo apt install libopencv-dev

# Verify:
pkg-config --modversion opencv4

# Build:
xiomc myprogram.xi $(pkg-config --cflags --libs opencv4)
```

#### Fedora / RHEL
```bash
sudo dnf install opencv-devel

# Build:
xiomc myprogram.xi $(pkg-config --cflags --libs opencv4)
```

#### macOS
```bash
brew install opencv

# Build:
xiomc myprogram.xi $(pkg-config --cflags --libs opencv4)
```

### Library Dependencies
- `libopencv_core.so` / `opencv_core.dll` — Core data structures
- `libopencv_imgcodecs.so` / `opencv_imgcodecs.dll` — Image I/O (imread/imwrite)
- `libopencv_imgproc.so` / `opencv_imgproc.dll` — Image processing (resize, cvtColor)
- `libopencv_features2d.so` / `opencv_features2d.dll` — Feature detection/matching
- `libopencv_calib3d.so` / `opencv_calib3d.dll` — Homography, camera calibration

### Without OpenCV
- `xiom.opencv.types` works without any dependency (pure XIOM types)
- `xiom.opencv.filters` works without any dependency (pure XIOM implementations: blur, grayscale, threshold, Sobel edges, resize_nearest)
- `xiom.opencv.io` functions return stubbed values
- `xiom.opencv.features` functions return stubbed values

## Pure XIOM Filters (No Dependency)

The following filters require **zero** system libraries:

| Function | Algorithm | Notes |
|----------|-----------|-------|
| `blur` | Box blur with border clamping | O(W*H*C*K²) |
| `grayscale` | ITU-R BT.601 luminance | R*77 + G*150 + B*29 / 256 |
| `threshold` | Binary threshold | Pixel > thresh → max_val, else 0 |
| `sobel_edges` | 3×3 Sobel Gx/Gy, integer sqrt magnitude | Requires 1-channel input |
| `resize_nearest` | Nearest-neighbor interpolation | Simple coordinate mapping |

## Production Readiness

| Module | Compiles | FFI Required |
|--------|----------|-------------|
| `xiom.opencv.types` | Yes | No |
| `xiom.opencv.filters` | Yes | No (pure XIOM) |
| `xiom.opencv.io` | Yes | OpenCV |
| `xiom.opencv.features` | Yes | OpenCV |
