# xiom-opencv -- ROADMAP

**Version:** 0.1.0 | **Status:** In Development | **Last Updated:** 2026-07-21

---

## Phase 0 -- Core Foundation [DONE]

| Task | Status |
|------|--------|
| Image type (row-major, 0..255 per channel) | Done |
| Geometry types (Rect, Point2i, Size2i) | Done |
| KeyPoint, MatchedPoints types | Done |
| ColorSpace enum (RGB, BGR, Grayscale, HSV, YUV) | Done |
| `image_new` -- zero-initialized image | Done |
| `image_from_vec` -- wrap pixel buffer | Done |
| `image_region` -- crop ROI | Done |
| `image_size` -- dimensions accessor | Done |
| `rect_new`, `point2i_new`, `size2i_new` constructors | Done |
| Contract coverage on all constructors and accessors | Done |

## Phase 1 -- Pure XIOM Filters [DONE]

| Function | Algorithm | Status |
|----------|-----------|--------|
| `blur` | Box blur (mean filter), border clamping | Done |
| `grayscale` | ITU-R BT.601 luminance (R\*77+G\*150+B\*29)/256 | Done |
| `threshold` | Binary threshold (> thresh ? max_val : 0) | Done |
| `sobel_edges` | 3x3 Sobel Gx/Gy, integer sqrt magnitude | Done |
| `resize_nearest` | Nearest-neighbor interpolation | Done |
| Contracts: kernel_size odd>0, channels>=3, thresh>=0, 1-channel, w>0 h>0 | Done |

## Phase 2 -- FFI Bridge & I/O [IN PROGRESS]

| Task | Status |
|------|--------|
| `extern "C"` declarations for OpenCV symbols | Done |
| `cv_imread` -- stub, returns dummy 1x1 Image | Done |
| `cv_imwrite` -- stub, returns Ok(true) | Done |
| `cv_resize` -- stub, returns empty Image at target size | Done |
| `cv_cvt_color` -- stub, identity copy or grayscale stub | Done |
| `color_space_to_int` -- enum->int mapping helper | Done |
| Contracts: non-empty path, valid image, w>0, h>0, channels>0 | Done |
| Native C bridge implementation (libxiom_opencv_core) | TODO |
| Actual imread/imwrite via `cv::imread`/`cv::imwrite` | TODO |
| Actual resize via `cv::resize` with interpolation enum | TODO |
| Actual cvtColor via `cv::cvtColor` for all 5 color spaces | TODO |
| OpenCV build integration (pkg-config, vcpkg, CMake) | TODO |

## Phase 3 -- Feature Detection [IN PROGRESS]

| Task | Status |
|------|--------|
| `extern "C"` declarations for feature symbols | Done |
| `cv_detect_keypoints` -- stub, returns empty Vec[KeyPoint] | Done |
| `cv_match_descriptors` -- stub, returns empty MatchedPoints | Done |
| `cv_homography` -- stub, returns 3x3 identity matrix | Done |
| Contracts: threshold>0, non-empty descriptors, >=4 matches | Done |
| Native bridge: ORB/SIFT/AKAZE keypoint detection | TODO |
| Native bridge: descriptor matching (FLANN/BFMatcher) | TODO |
| Native bridge: findHomography with RANSAC | TODO |
| KeyPoint->XIOM struct conversion | TODO |
| MatchedPoints->XIOM struct conversion | TODO |

## Phase 4 -- Advanced Filters [PLANNED]

| Task | Priority |
|------|----------|
| Gaussian blur (`gaussian_blur`) | High |
| Median filter (`median_blur`) | Medium |
| Bilateral filter (`bilateral_filter`) | Low |
| Morphological ops (erode, dilate, open, close) | High |
| Canny edge detection (`canny`) | High |
| Hough line/circle transforms | Medium |
| Bilinear and bicubic resize (`resize_bilinear`, `resize_bicubic`) | Medium |
| Histogram equalization (`equalize_hist`) | Medium |
| Adaptive threshold (`adaptive_threshold`) | Low |

## Phase 5 -- Video I/O [PLANNED]

| Task | Priority |
|------|----------|
| `VideoCapture` type with `new`, `read`, `free` | High |
| Webcam capture (device 0) | High |
| Video file read (`VideoCapture(path)`) | High |
| Video file write (`VideoWriter`) | Medium |
| Frame-by-frame processing loop | High |
| Real-time filter pipeline demo | Medium |

## Phase 6 -- Drawing Primitives [PLANNED]

| Task | Priority |
|------|----------|
| `draw_line(img, pt1, pt2, color, thickness)` | High |
| `draw_circle(img, center, radius, color, thickness)` | High |
| `draw_rectangle(img, rect, color, thickness)` | High |
| `draw_text(img, text, org, font, scale, color)` | Medium |
| `draw_polyline`, `draw_fill_poly` | Low |

## Phase 7 -- GUI Display [PLANNED]

| Task | Priority |
|------|----------|
| `imshow(window_name, img)` -- HighGUI wrapper | Medium |
| `waitKey(delay_ms)` -- keyboard input | Medium |
| `namedWindow`, `destroyWindow` | Low |
| Trackbar/slider controls | Low |

## Phase 8 -- DNN & Advanced [FUTURE]

| Task | Notes |
|------|-------|
| OpenCV DNN module (ONNX inference) | dnn::readNet, forward pass |
| Camera calibration (`calibrate_camera`) | Chessboard pattern |
| Stereo vision (`StereoBM`, `StereoSGBM`) | Disparity maps |
| Object tracking (KCF, MIL, CSRT) | Single-object trackers |
| Face detection (Haar cascades, DNN) | CascadeClassifier |
| ArUco markers | Detection and pose estimation |

---

## Contract Coverage Matrix

| Count | Category |
|-------|----------|
| 19 | Total public functions |
| 12 | Functions with `requires` contracts |
| 1 | Functions with `ensures` contracts |
| 22 | Total `requires` clauses |
| 1 | Total `ensures` clauses |

### Per-Module Breakdown

| Module | Functions | Has Contracts | Missing |
|--------|-----------|---------------|---------|
| `xiom.opencv.types` | 7 | 5 | point2i_new, image_size |
| `xiom.opencv.io` | 4 | 4 | -- |
| `xiom.opencv.features` | 3 | 3 | -- |
| `xiom.opencv.filters` | 5 | 5 | -- |

---

## Test Coverage

| Module | Tests | Status |
|--------|-------|--------|
| `types` | 7 (image_new, image_from_vec, image_region, image_size, rect_new, point2i_new, size2i_new) | Done |
| `io` | 4 (cv_imread, cv_imwrite, cv_resize, cv_cvt_color) | Done |
| `features` | 3 (cv_detect_keypoints, cv_match_descriptors, cv_homography) | Done |
| `filters` | 5 (blur, grayscale, threshold, sobel_edges, resize_nearest) | Done |
| **Total** | **19** | |

---

## v0.2.0 Milestone

- [ ] Native C bridge (`cv_c_*` symbols) compiled and linked
- [ ] `cv_imread`/`cv_imwrite` working with actual image files
- [ ] `cv_resize` with bilinear interpolation
- [ ] `cv_cvt_color` for all ColorSpace variants
- [ ] Gaussian blur (pure XIOM)
- [ ] Canny edge detection (pure XIOM or FFI)

## v0.3.0 Milestone

- [ ] ORB keypoint detection via FFI
- [ ] FLANN descriptor matching via FFI
- [ ] Homography estimation with RANSAC
- [ ] Video capture from webcam
- [ ] Drawing primitives (line, circle, rectangle)

## v1.0.0 Milestone

- [ ] All FFI stubs replaced with real implementations
- [ ] Full cross-platform build system (CMake + pkg-config + vcpkg)
- [ ] Documentation for every public function
- [ ] 90%+ contract coverage on public API
- [ ] CI/CD pipeline (Linux, macOS, Windows)
- [ ] Performance benchmarks vs. native OpenCV
