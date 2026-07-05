xiom-opencv: XIOM OpenCV Bindings v0.1.0

== Overview ==

xiom-opencv provides XIOM bindings to the OpenCV computer vision library.
The package is organized into four modules:

  - xiom.opencv.types: Core types for images (Image, ColorSpace), geometry
    (Rect, Point2i, Size2i), and feature detection (KeyPoint, MatchedPoints).
  - xiom.opencv.io: Image I/O and color conversion via `extern "C"` stubs
    to OpenCV. All functions return stubbed results until the native library
    is linked.
  - xiom.opencv.features: Feature detection, descriptor matching, and
    homography estimation via `extern "C"` stubs.
  - xiom.opencv.filters: Pure XIOM implementations of basic image filters
    (box blur, grayscale, binary threshold, Sobel edges, nearest-neighbor
    resize). No FFI dependency.

Layer: 3.5 (Ecosystem Libraries)
Package: xiom-opencv
Namespace: xiom.opencv.*

== OpenCV Installation ==

=== Linux (Ubuntu/Debian) ===

  sudo apt update
  sudo apt install libopencv-dev

  Verify:
    pkg-config --modversion opencv4

=== Linux (Fedora/RHEL) ===

  sudo dnf install opencv-devel

=== macOS ===

  brew install opencv

=== Windows ===

  vcpkg install opencv:x64-windows

  Or download pre-built binaries from https://opencv.org/releases/

=== XIOM Build Integration ===

  xiomc myprogram.xi $(pkg-config --cflags --libs opencv4)

== Module Specifications ==

=== 1. xiom.opencv.types — Core Types ===

Types:
  Image:        { data: Vec[Int]; width: Int; height: Int; channels: Int; }
    Pixel values in range 0..255 per channel. Row-major layout.
    Index: (y * width + x) * channels + c.
  ColorSpace:   RGB | BGR | Grayscale | HSV | YUV
  Rect:         { x: Int; y: Int; w: Int; h: Int; }
  Point2i:      { x: Int; y: Int; }
  Size2i:       { w: Int; h: Int; }
  KeyPoint:     { pt: Point2i; size: Float32; angle: Float32;
                  response: Float32; octave: Int; }
  MatchedPoints:{ query: Vec[Point2i]; train: Vec[Point2i];
                  distances: Vec[Float32]; }

Functions:
  image_new(width, height, channels) -> Image
    Creates a zero-filled (black) image.
    requires: width > 0, height > 0, channels > 0

  image_from_vec(data, w, h, c) -> Image
    Wraps a pixel vector into an Image. No copy — moves ownership.
    requires: data.len() > 0, w > 0, h > 0, c > 0
    ensures: result.data.len() == data.len()

  image_region(img: &Image, roi: &Rect) -> Image
    Extracts a rectangular region (crop). Deep-copies pixel data.
    requires: roi.x + roi.w <= img.width, roi.y + roi.h <= img.height

  image_size(img: &Image) -> Size2i
    Returns { w: img.width; h: img.height; }

Convenience constructors:
  rect_new(x, y, w, h) -> Rect
  point2i_new(x, y) -> Point2i
  size2i_new(w, h) -> Size2i

=== 2. xiom.opencv.io — Image I/O (FFI) ===

All functions return stubbed results until OpenCV is linked.

extern "C" FFI symbols:
  cv_c_imread(path_ptr, path_len) -> *UInt8
  cv_c_imwrite(path_ptr, path_len, img_ptr) -> Int
  cv_c_resize(img_ptr, w, h) -> *UInt8
  cv_c_cvt_color(img_ptr, from, to) -> *UInt8
  cv_c_free(ptr)

Functions:
  cv_imread(path: Str) -> Result[Image, Str]
    STUB — Returns a 1x1x3 black image. Will read PNG, JPEG, BMP, etc.

  cv_imwrite(path: Str, img: &Image) -> Result[Unit, Str]
    STUB — Returns Ok. Will encode to PNG/JPEG based on extension.

  cv_resize(img: &Image, w: Int, h: Int) -> Result[Image, Str]
    STUB — Returns a zero-filled image of target size.
    requires: w > 0, h > 0

  cv_cvt_color(img: &Image, from: ColorSpace, to: ColorSpace) -> Result[Image, Str]
    STUB — Returns clone if from==to, else zero image.
    Channels adjust automatically (Grayscale = 1, others = 3).

=== 3. xiom.opencv.features — Feature Detection (FFI) ===

extern "C" FFI symbols:
  cv_c_detect_keypoints(img_ptr, threshold) -> *UInt8
  cv_c_match_descriptors(desc1_ptr, desc2_ptr, count) -> *UInt8
  cv_c_homography(matches_ptr) -> *UInt8
  cv_c_free_features(ptr)

Functions:
  cv_detect_keypoints(img: &Image, threshold: Float32) -> Result[Vec[KeyPoint], Str]
    STUB — Returns empty vector. Requires: threshold > 0.0.

  cv_match_descriptors(desc1: &Vec[Float32], desc2: &Vec[Float32]) -> Result[MatchedPoints, Str]
    STUB — Returns empty MatchedPoints.
    requires: desc1.len() > 0, desc2.len() > 0

  cv_homography(matches: &MatchedPoints) -> Result[Vec[Float32], Str]
    STUB — Returns identity 3x3 matrix [1,0,0, 0,1,0, 0,0,1].
    requires: matches.query.len() >= 4

=== 4. xiom.opencv.filters — Image Filters (Pure XIOM) ===

Fully implemented in pure XIOM. No FFI dependency.

Functions:
  blur(img: &Image, kernel_size: Int) -> Image
    Box blur (mean filter). Averages each pixel with its neighbors in
    a kernel_size × kernel_size window. Handles borders by clamping.
    requires: kernel_size > 0, kernel_size % 2 == 1

  grayscale(img: &Image) -> Image
    RGB to grayscale using luminance weights (ITU-R BT.601):
    Gray = (R*77 + G*150 + B*29) / 256. Output has 1 channel.
    requires: img.channels >= 3

  threshold(img: &Image, thresh: Int, max_val: Int) -> Image
    Binary threshold: pixel > thresh → max_val, else 0.
    requires: thresh >= 0, max_val >= 0

  sobel_edges(img: &Image) -> Image
    Sobel edge detection using 3×3 kernels for Gx and Gy.
    Magnitude = sqrt(Gx^2 + Gy^2), approximated with integer sqrt.
    Border pixels (1-pixel margin) are not processed (remain black).
    requires: img.channels == 1

  resize_nearest(img: &Image, w: Int, h: Int) -> Image
    Nearest-neighbor interpolation to scale image to target (w, h).
    requires: w > 0, h > 0

== Limitations ==

1. FFI Stubs: All OpenCV C API calls return dummy values. Requires the
   OpenCV native library and a C bridge layer.
2. Int Pixels: Image data is Vec[Int] (0..255 per channel). No float images.
3. Single-Channel Sobel: Sobel filter requires grayscale input (1 channel).
4. No Color Conversion: cv_cvt_color returns stub results for non-identity
   conversions. Pure XIOM grayscale() handles RGB→Gray only.
5. Simple Resize: resize_nearest uses nearest-neighbor interpolation. No
   bilinear/bicubic/Lanczos.
6. No Descriptor Computation: Feature detection is a stub. Descriptor
   computation (SIFT, ORB, etc.) is not implemented.
7. No Video: Only static images. No video capture, webcam, or frame streams.
8. No Drawing: No line, circle, rectangle, text drawing functions.

== API Conventions ==

- Image functions: operate on &Image, return new Image (functional style).
  Exception: set_pixel uses &mut Image (internal only).
- FFI functions: return Result[T, Str] for fallible operations.
- Filters are pure XIOM: no `unsafe`, no `extern "C"`, no runtime deps.
- Constructor pattern: `type_new(args) -> Type` with requires contracts.
- Geometry types: value semantics, no references needed for small types.

== Production Readiness ==

| Feature                        | Status    | Notes                       |
|--------------------------------|-----------|-----------------------------|
| Image type                     | Complete  | Vec[Int], row-major         |
| ColorSpace enum                | Complete  | 5 variants                  |
| Geometry types                 | Complete  | Rect, Point2i, Size2i       |
| KeyPoint type                  | Complete  | Struct definition           |
| MatchedPoints type             | Complete  | Struct definition           |
| image_new / image_from_vec     | Complete  | Pure XIOM                   |
| image_region (crop)            | Complete  | Pure XIOM, bounds checked   |
| box blur filter                | Complete  | Pure XIOM, border handled   |
| grayscale filter               | Complete  | Pure XIOM, BT.601 weights   |
| binary threshold               | Complete  | Pure XIOM                   |
| Sobel edge detection           | Complete  | Pure XIOM, integer approx   |
| nearest-neighbor resize        | Complete  | Pure XIOM                   |
| OpenCV FFI stubs               | Complete  | extern "C" declarations     |
| cv_imread / cv_imwrite         | Stub      | Needs native OpenCV         |
| cv_resize (OpenCV)             | Stub      | Needs native OpenCV         |
| cv_cvt_color (OpenCV)          | Stub      | Needs native OpenCV         |
| Feature detection              | Stub      | Needs native OpenCV         |
| Descriptor matching            | Stub      | Needs native OpenCV         |
| Homography estimation          | Stub      | Needs native OpenCV         |
| Video capture                  | Not yet   | Needs cv::VideoCapture FFI  |
| Drawing functions              | Not yet   | Needs cv::line, cv::circle  |
| GUI (imshow, waitKey)          | Not yet   | Needs highgui FFI           |

== What's Left for v1.0 ==

1. **OpenCV FFI bridge** — Native C bridge for all cv_c_* symbols.
2. **OpenCV resize** — Bilinear/bicubic interpolation via cv::resize.
3. **Full color conversion** — RGB↔BGR↔HSV↔YUV via cv::cvtColor.
4. **Feature extraction** — SIFT, ORB, AKAZE keypoints and descriptors.
5. **Video I/O** — Webcam capture and video file reading/writing.
6. **Drawing primitives** — Line, circle, rectangle, text overlay.
7. **More filters** — Gaussian blur, median, bilateral, morphological ops.
8. **Float images** — Support for Float32 and Float64 pixel types.
