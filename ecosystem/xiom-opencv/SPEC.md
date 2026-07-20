# xiom-opencv — SPEC

**Phase**: 1 (Core Foundation) | **Priority**: HIGH
**Status**: SPEC only — no implementation yet
**Depends on**: xiom.ffi (stdlib)

## What it wraps
OpenCV — computer vision library (C++ API).
Image/video I/O, processing, feature detection, object tracking.

## Dependencies

| What | How | Size |
|------|-----|------|
| OpenCV | System-installed. `winget install OpenCV`, `apt install libopencv-dev` | ~500MB |
| C++ compiler | For building C++ bridge | — |

## Bundling strategy
**System-installed only.** OpenCV is large (500MB+). Never bundle.

## API surface

```xiom
module xiom.opencv

// Image I/O
pub fn imread(path: Str) -> Result[Mat, Str]
pub fn imwrite(path: Str, img: &Mat) -> Result[Unit, Str]
pub fn mat_new(rows: Int, cols: Int, typ: Int) -> Result[Mat, Str]
pub fn mat_free(m: Mat)

// Image processing
pub fn resize(src: &Mat, w: Int, h: Int) -> Result[Mat, Str]
pub fn cvt_color(src: &Mat, code: Int) -> Result[Mat, Str]
pub fn gaussian_blur(src: &Mat, ksize: (Int, Int), sigma: Float64) -> Result[Mat, Str]
pub fn threshold(src: &Mat, thresh: Float64, maxval: Float64, typ: Int) -> Result[Mat, Str]

// Feature detection
pub fn canny(src: &Mat, t1: Float64, t2: Float64) -> Result[Mat, Str]
pub fn good_features_to_track(src: &Mat, max_corners: Int, quality: Float64, min_dist: Float64) -> Result[Vec[(Float32, Float32)], Str]

// Video
pub fn video_capture_new(source: Int) -> Result[VideoCapture, Str]  // 0 = webcam
pub fn video_capture_read(cap: &mut VideoCapture) -> Result[Mat, Str]
pub fn video_capture_free(cap: VideoCapture)

// Drawing
pub fn circle(img: &mut Mat, center: (Int, Int), radius: Int, color: (Int, Int, Int))
pub fn rectangle(img: &mut Mat, pt1: (Int, Int), pt2: (Int, Int), color: (Int, Int, Int))
pub fn put_text(img: &mut Mat, text: Str, org: (Int, Int), font: Int, scale: Float64, color: (Int, Int, Int))
```

## Contract coverage target
- File paths: `requires: io.file_exists(path)` for read
- Mat dimensions: `requires: m.cols > 0 && m.rows > 0`
- Color code validation: enum constants for BGR2GRAY, BGR2RGB, etc.

## Phased roadmap

| Phase | What | Effort |
|-------|------|--------|
| 1 | Image I/O, basic processing (resize, blur, threshold) | Weekend |
| 2 | Feature detection, video capture | Weekend |
| 3 | Object tracking, camera calibration, stereo | Week |
| 4 | DNN module (OpenCV's built-in ONNX inference) | Weekend |
