# xiom-opencv

> OpenCV bindings for XIOM — computer vision with compute-time safety.

[![XIOM](https://img.shields.io/badge/XIOM-v0.22.1-blue)](https://github.com/xiom-lang/XIOM)
[![License](https://img.shields.io/badge/license-MIT%2FApache--2.0-blue.svg)](LICENSE)

## Overview

xiom-opencv provides computer vision capabilities to XIOM — image I/O,
feature detection, geometric transformations, and image filtering.

**Dual tier**: Pure XIOM filters (blur, grayscale, threshold, Sobel edges,
nearest-neighbor resize) work without any dependency. FFI tier provides
OpenCV integration for I/O, advanced processing, and feature extraction.

## Installation

```bash
xiom install xiom-opencv
```

## Dependencies

### System Libraries

OpenCV library is required for FFI-backed I/O and advanced features.
Without it, pure XIOM filters still work; only FFI functions return dummy values.

| OS | Command |
|----|---------|
| **Windows** | `vcpkg install opencv:x64-windows` |
| **Ubuntu/Debian** | `sudo apt install libopencv-dev` |
| **Fedora** | `sudo dnf install opencv-devel` |
| **macOS** | `brew install opencv` |

### Build Integration

```bash
xiom myprogram.xi $(pkg-config --cflags --libs opencv4)
```

## Quick Start

```xiom
use xiom.opencv.types;
use xiom.opencv.filters;

fn main() -> Int {
  var img = image_new(256, 256, 3);

  var gray = grayscale(&img);
  var blurred = blur(&gray, 5);
  var edges = sobel_edges(&blurred);
  var binary = threshold(&edges, 50, 255);

  return 0;
}
```

## API Reference

### Core Types (xiom.opencv.types)

| Type | Description |
|------|-------------|
| `Image` | { data: Vec[Int], width, height, channels } |
| `ColorSpace` | Enum: RGB, BGR, Grayscale, HSV, YUV |
| `Rect` | { x, y, w, h } |
| `Point2i` | { x, y } |
| `Size2i` | { w, h } |
| `KeyPoint` | { pt, size, angle, response, octave } |
| `MatchedPoints` | { query, train, distances } |

| Function | Description |
|----------|-------------|
| `image_new(w, h, c)` | Create black image |
| `image_from_vec(data, w, h, c)` | Wrap pixel data |
| `image_region(img, roi)` | Crop region |
| `image_size(img)` | Get image dimensions |

### I/O (xiom.opencv.io)

| Function | Status |
|----------|--------|
| `cv_imread(path)` | Stub — Read image from file |
| `cv_imwrite(path, img)` | Stub — Write image to file |
| `cv_resize(img, w, h)` | Stub — Resize image |
| `cv_cvt_color(img, from, to)` | Stub — Convert color space |

### Features (xiom.opencv.features)

| Function | Status |
|----------|--------|
| `cv_detect_keypoints(img, threshold)` | Stub — Detect keypoints |
| `cv_match_descriptors(d1, d2)` | Stub — Match descriptors |
| `cv_homography(matches)` | Stub — Estimate homography |

### Filters (xiom.opencv.filters) — Pure XIOM

| Function | Description |
|----------|-------------|
| `blur(img, kernel_size)` | Box blur (mean filter) |
| `grayscale(img)` | RGB to grayscale (BT.601) |
| `threshold(img, thresh, max_val)` | Binary threshold |
| `sobel_edges(img)` | Sobel edge detection |
| `resize_nearest(img, w, h)` | Nearest-neighbor resize |

## Safety Contracts

- `image_new`, `image_from_vec`: requires width > 0, height > 0, channels > 0
- `image_region`: requires roi bounds within image dimensions
- `blur`: requires odd kernel_size > 0
- `grayscale`: requires channels >= 3
- `sobel_edges`: requires single-channel (grayscale) input
- `threshold`: requires thresh >= 0, max_val >= 0
- `resize_nearest`: requires w > 0, h > 0
- `cv_resize`: requires w > 0, h > 0
- `cv_detect_keypoints`: requires threshold > 0.0
- `cv_homography`: requires at least 4 point matches

## Production Readiness

| Feature | Status | Notes |
|---------|--------|-------|
| Image type | Complete | Row-major, 0..255 per channel |
| Geometry types | Complete | Rect, Point2i, Size2i |
| image_new/from_vec/region | Complete | Pure XIOM |
| Box blur | Complete | Pure XIOM, border handled |
| Grayscale conversion | Complete | BT.601 luminance weights |
| Binary threshold | Complete | Pure XIOM |
| Sobel edge detection | Complete | Pure XIOM, integer sqrt |
| Nearest-neighbor resize | Complete | Pure XIOM |
| OpenCV FFI stubs | Complete | extern "C" declarations |
| Image I/O | Stub | Needs native OpenCV |
| OpenCV resize/color convert | Stub | Needs native OpenCV |
| Feature detection | Stub | Needs native OpenCV |
| Video capture | Not yet | Needs cv::VideoCapture |
| Drawing functions | Not yet | line, circle, text |
| GUI display | Not yet | imshow, waitKey |

### What's Left for v1.0

1. **OpenCV FFI bridge** — Native C bridge for all cv_c_* symbols
2. **OpenCV resize** — Bilinear/bicubic interpolation
3. **Full color conversion** — RGB↔BGR↔HSV↔YUV
4. **Feature extraction** — SIFT, ORB, AKAZE
5. **Video I/O** — Webcam, video file read/write
6. **Drawing primitives** — Line, circle, rectangle, text
7. **More filters** — Gaussian blur, median, bilateral, morphology

## Build & Run

```bash
# With OpenCV (recommended for production)
xiom myprogram.xi $(pkg-config --cflags --libs opencv4)

# Without OpenCV (pure XIOM filters only)
xiom --run myprogram.xi
```

## Links

- **Organization**: [github.com/xiom-lang](https://github.com/xiom-lang)
- **Language**: [github.com/xiom-lang/XIOM](https://github.com/xiom-lang/XIOM)
- **OpenCV**: [opencv.org](https://opencv.org)

## License

MIT OR Apache-2.0
