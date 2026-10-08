/*
 * xiom.ozz bridge template -- combined into a single TU with the ozz headers
 * it needs (no include-path support in the xiom link line).  See SPEC.md.
 */
/**** start inlining ozz/base/maths/vec_float.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_MATHS_VEC_FLOAT_H_
#define OZZ_OZZ_BASE_MATHS_VEC_FLOAT_H_

#include <cassert>
#include <cmath>

/**** start inlining ozz/base/maths/math_constant.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_MATHS_MATH_CONSTANT_H_
#define OZZ_OZZ_BASE_MATHS_MATH_CONSTANT_H_

#ifndef INCLUDE_OZZ_MATH_CONSTANT_H_
#define INCLUDE_OZZ_MATH_CONSTANT_H_

namespace ozz {
namespace math {

// Defines math trigonometric constants.
static const float k2Pi = 6.283185307179586476925286766559f;
static const float kPi = 3.1415926535897932384626433832795f;
static const float kPi_2 = 1.5707963267948966192313216916398f;
static const float kPi_4 = .78539816339744830961566084581988f;
static const float kSqrt3 = 1.7320508075688772935274463415059f;
static const float kSqrt3_2 = 0.86602540378443864676372317075294f;
static const float kSqrt2 = 1.4142135623730950488016887242097f;
static const float kSqrt2_2 = 0.70710678118654752440084436210485f;

// Angle unit conversion constants.
static const float kDegreeToRadian = kPi / 180.f;
static const float kRadianToDegree = 180.f / kPi;

// Defines the square normalization tolerance value.
static const float kNormalizationToleranceSq = 1e-6f;
static const float kNormalizationToleranceEstSq = 2e-3f;

// Defines the square orthogonalisation tolerance value.
static const float kOrthogonalisationToleranceSq = 1e-16f;
}  // namespace math
}  // namespace ozz

#endif  // INCLUDE_OZZ_MATH_CONSTANT_H_
#endif  // OZZ_OZZ_BASE_MATHS_MATH_CONSTANT_H_
/**** ended inlining ozz/base/maths/math_constant.h ****/
/**** start inlining ozz/base/platform.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_PLATFORM_H_
#define OZZ_OZZ_BASE_PLATFORM_H_

// Ensures compiler supports c++11 language standards, to help user understand
// compilation error in case it's not supported.
// Unfortunately MSVC doesn't update __cplusplus, so test compiler version
// instead.
#if !((__cplusplus >= 201103L) || (_MSC_VER >= 1900))
#error "ozz-animation requires c++11 language standards."
#endif  // __cplusplus

#include <stdint.h>

#include <cassert>
#include <cstddef>

/**** start inlining ozz/base/export.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_EXPORT_H_
#define OZZ_OZZ_BASE_EXPORT_H_

#if defined(_MSC_VER) && defined(OZZ_USE_DYNAMIC_LINKING)

#ifdef OZZ_BUILD_BASE_LIB
// Import/Export for dynamic linking while building ozz
#define OZZ_BASE_DLL __declspec(dllexport)
#else
#define OZZ_BASE_DLL __declspec(dllimport)
#endif
#else  // defined(_MSC_VER) && defined(OZZ_USE_DYNAMIC_LINKING)
// Static or non msvc linking
#define OZZ_BASE_DLL
#endif  // defined(_MSC_VER) && defined(OZZ_USE_DYNAMIC_LINKING)

#endif  // OZZ_OZZ_BASE_EXPORT_H_
/**** ended inlining ozz/base/export.h ****/

namespace ozz {

// Defines a byte type, unsigned so right shift  doesn't propagate sign bit.
typedef uint8_t byte;

// Finds the number of elements of a statically allocated array.
#define OZZ_ARRAY_SIZE(_array) (sizeof(_array) / sizeof(_array[0]))

// Instructs the compiler to try to inline a function, regardless cost/benefit
// compiler analysis.
// Syntax is: "OZZ_INLINE void function();"
#if defined(_MSC_VER)
#define OZZ_INLINE __forceinline
#else
#define OZZ_INLINE inline __attribute__((always_inline))
#endif

// Tells the compiler to never inline a function.
// Syntax is: "OZZ_NO_INLINE void function();"
#if defined(_MSC_VER)
#define OZZ_NOINLINE __declspec(noinline)
#else
#define OZZ_NOINLINE __attribute__((noinline))
#endif

// Tells the compiler that the memory addressed by the restrict -qualified
// pointer is not aliased, aka no other pointer will access that same memory.
// Syntax is: void function(int* OZZ_RESTRICT _p);"
#define OZZ_RESTRICT __restrict

// Defines macro to help with DEBUG/NDEBUG syntax.
#if defined(NDEBUG)
#define OZZ_IF_DEBUG(...)
#define OZZ_IF_NDEBUG(...) __VA_ARGS__
#else  // NDEBUG
#define OZZ_IF_DEBUG(...) __VA_ARGS__
#define OZZ_IF_NDEBUG(...)
#endif  // NDEBUG

// Case sensitive wildcard string matching:
// - a ? sign matches any character, except an empty string.
// - a * sign matches any string, including an empty string.
OZZ_BASE_DLL bool strmatch(const char* _str, const char* _pattern);

// Tests whether _block is aligned to _alignment boundary.
template <typename _Ty>
OZZ_INLINE bool IsAligned(_Ty _value, size_t _alignment) {
  return (_value & (_alignment - 1)) == 0;
}
template <typename _Ty>
OZZ_INLINE bool IsAligned(_Ty* _address, size_t _alignment) {
  return (reinterpret_cast<uintptr_t>(_address) & (_alignment - 1)) == 0;
}

// Aligns _block address to the first greater address that is aligned to
// _alignment boundaries.
template <typename _Ty>
OZZ_INLINE _Ty Align(_Ty _value, size_t _alignment) {
  return static_cast<_Ty>(_value + (_alignment - 1)) & (0 - _alignment);
}
template <typename _Ty>
OZZ_INLINE _Ty* Align(_Ty* _address, size_t _alignment) {
  return reinterpret_cast<_Ty*>(
      (reinterpret_cast<uintptr_t>(_address) + (_alignment - 1)) &
      (0 - _alignment));
}

// Offset a pointer from a given number of bytes.
template <typename _Ty>
_Ty* PointerStride(_Ty* _ty, size_t _stride) {
  return reinterpret_cast<_Ty*>(reinterpret_cast<uintptr_t>(_ty) + _stride);
}
}  // namespace ozz
#endif  // OZZ_OZZ_BASE_PLATFORM_H_
/**** ended inlining ozz/base/platform.h ****/

namespace ozz {
namespace math {

// Declares a 2d float vector.
struct OZZ_BASE_DLL Float2 {
  float x, y;

  // Constructs an uninitialized vector.
  OZZ_INLINE Float2() {}

  // Constructs a vector initialized with _f value.
  explicit OZZ_INLINE Float2(float _f) : x(_f), y(_f) {}

  // Constructs a vector initialized with _x and _y values.
  OZZ_INLINE Float2(float _x, float _y) : x(_x), y(_y) {}

  // Returns a vector with all components set to 0.
  static OZZ_INLINE Float2 zero() { return Float2(0.f); }

  // Returns a vector with all components set to 1.
  static OZZ_INLINE Float2 one() { return Float2(1.f); }

  // Returns a unitary vector x.
  static OZZ_INLINE Float2 x_axis() { return Float2(1.f, 0.f); }

  // Returns a unitary vector y.
  static OZZ_INLINE Float2 y_axis() { return Float2(0.f, 1.f); }
};

// Declares a 3d float vector.
struct OZZ_BASE_DLL Float3 {
  float x, y, z;

  // Constructs an uninitialized vector.
  OZZ_INLINE Float3() {}

  // Constructs a vector initialized with _f value.
  explicit OZZ_INLINE Float3(float _f) : x(_f), y(_f), z(_f) {}

  // Constructs a vector initialized with _x, _y and _z values.
  OZZ_INLINE Float3(float _x, float _y, float _z) : x(_x), y(_y), z(_z) {}

  // Returns a vector initialized with _v.x, _v.y and _z values.
  OZZ_INLINE Float3(Float2 _v, float _z) : x(_v.x), y(_v.y), z(_z) {}

  // Returns a vector with all components set to 0.
  static OZZ_INLINE Float3 zero() { return Float3(0.f); }

  // Returns a vector with all components set to 1.
  static OZZ_INLINE Float3 one() { return Float3(1.f); }

  // Returns a unitary vector x.
  static OZZ_INLINE Float3 x_axis() { return Float3(1.f, 0.f, 0.f); }

  // Returns a unitary vector y.
  static OZZ_INLINE Float3 y_axis() { return Float3(0.f, 1.f, 0.f); }

  // Returns a unitary vector z.
  static OZZ_INLINE Float3 z_axis() { return Float3(0.f, 0.f, 1.f); }
};

// Declares a 4d float vector.
struct OZZ_BASE_DLL Float4 {
  float x, y, z, w;

  // Constructs an uninitialized vector.
  OZZ_INLINE Float4() {}

  // Constructs a vector initialized with _f value.
  explicit OZZ_INLINE Float4(float _f) : x(_f), y(_f), z(_f), w(_f) {}

  // Constructs a vector initialized with _x, _y, _z and _w values.
  OZZ_INLINE Float4(float _x, float _y, float _z, float _w)
      : x(_x), y(_y), z(_z), w(_w) {}

  // Constructs a vector initialized with _v.x, _v.y, _v.z and _w values.
  OZZ_INLINE Float4(Float3 _v, float _w) : x(_v.x), y(_v.y), z(_v.z), w(_w) {}

  // Constructs a vector initialized with _v.x, _v.y, _z and _w values.
  OZZ_INLINE Float4(Float2 _v, float _z, float _w)
      : x(_v.x), y(_v.y), z(_z), w(_w) {}

  // Returns a vector with all components set to 0.
  static OZZ_INLINE Float4 zero() { return Float4(0.f); }

  // Returns a vector with all components set to 1.
  static OZZ_INLINE Float4 one() { return Float4(1.f); }

  // Returns a unitary vector x.
  static OZZ_INLINE Float4 x_axis() { return Float4(1.f, 0.f, 0.f, 0.f); }

  // Returns a unitary vector y.
  static OZZ_INLINE Float4 y_axis() { return Float4(0.f, 1.f, 0.f, 0.f); }

  // Returns a unitary vector z.
  static OZZ_INLINE Float4 z_axis() { return Float4(0.f, 0.f, 1.f, 0.f); }

  // Returns a unitary vector w.
  static OZZ_INLINE Float4 w_axis() { return Float4(0.f, 0.f, 0.f, 1.f); }
};

// Returns per element addition of _a and _b using operator +.
OZZ_INLINE Float4 operator+(const Float4& _a, const Float4& _b) {
  return Float4(_a.x + _b.x, _a.y + _b.y, _a.z + _b.z, _a.w + _b.w);
}
OZZ_INLINE Float3 operator+(const Float3& _a, const Float3& _b) {
  return Float3(_a.x + _b.x, _a.y + _b.y, _a.z + _b.z);
}
OZZ_INLINE Float2 operator+(const Float2& _a, const Float2& _b) {
  return Float2(_a.x + _b.x, _a.y + _b.y);
}

// Returns per element subtraction of _a and _b using operator -.
OZZ_INLINE Float4 operator-(const Float4& _a, const Float4& _b) {
  return Float4(_a.x - _b.x, _a.y - _b.y, _a.z - _b.z, _a.w - _b.w);
}
OZZ_INLINE Float3 operator-(const Float3& _a, const Float3& _b) {
  return Float3(_a.x - _b.x, _a.y - _b.y, _a.z - _b.z);
}
OZZ_INLINE Float2 operator-(const Float2& _a, const Float2& _b) {
  return Float2(_a.x - _b.x, _a.y - _b.y);
}

// Returns per element negative value of _v.
OZZ_INLINE Float4 operator-(const Float4& _v) {
  return Float4(-_v.x, -_v.y, -_v.z, -_v.w);
}
OZZ_INLINE Float3 operator-(const Float3& _v) {
  return Float3(-_v.x, -_v.y, -_v.z);
}
OZZ_INLINE Float2 operator-(const Float2& _v) { return Float2(-_v.x, -_v.y); }

// Returns per element multiplication of _a and _b using operator *.
OZZ_INLINE Float4 operator*(const Float4& _a, const Float4& _b) {
  return Float4(_a.x * _b.x, _a.y * _b.y, _a.z * _b.z, _a.w * _b.w);
}
OZZ_INLINE Float3 operator*(const Float3& _a, const Float3& _b) {
  return Float3(_a.x * _b.x, _a.y * _b.y, _a.z * _b.z);
}
OZZ_INLINE Float2 operator*(const Float2& _a, const Float2& _b) {
  return Float2(_a.x * _b.x, _a.y * _b.y);
}

// Returns per element multiplication of _a and scalar value _f using
// operator *.
OZZ_INLINE Float4 operator*(const Float4& _a, float _f) {
  return Float4(_a.x * _f, _a.y * _f, _a.z * _f, _a.w * _f);
}
OZZ_INLINE Float3 operator*(const Float3& _a, float _f) {
  return Float3(_a.x * _f, _a.y * _f, _a.z * _f);
}
OZZ_INLINE Float2 operator*(const Float2& _a, float _f) {
  return Float2(_a.x * _f, _a.y * _f);
}

// Returns per element division of _a and _b using operator /.
OZZ_INLINE Float4 operator/(const Float4& _a, const Float4& _b) {
  return Float4(_a.x / _b.x, _a.y / _b.y, _a.z / _b.z, _a.w / _b.w);
}
OZZ_INLINE Float3 operator/(const Float3& _a, const Float3& _b) {
  return Float3(_a.x / _b.x, _a.y / _b.y, _a.z / _b.z);
}
OZZ_INLINE Float2 operator/(const Float2& _a, const Float2& _b) {
  return Float2(_a.x / _b.x, _a.y / _b.y);
}

// Returns per element division of _a and scalar value _f using operator/.
OZZ_INLINE Float4 operator/(const Float4& _a, float _f) {
  return Float4(_a.x / _f, _a.y / _f, _a.z / _f, _a.w / _f);
}
OZZ_INLINE Float3 operator/(const Float3& _a, float _f) {
  return Float3(_a.x / _f, _a.y / _f, _a.z / _f);
}
OZZ_INLINE Float2 operator/(const Float2& _a, float _f) {
  return Float2(_a.x / _f, _a.y / _f);
}

// Returns the (horizontal) addition of each element of _v.
OZZ_INLINE float HAdd(const Float4& _v) { return _v.x + _v.y + _v.z + _v.w; }
OZZ_INLINE float HAdd(const Float3& _v) { return _v.x + _v.y + _v.z; }
OZZ_INLINE float HAdd(const Float2& _v) { return _v.x + _v.y; }

// Returns the dot product of _a and _b.
OZZ_INLINE float Dot(const Float4& _a, const Float4& _b) {
  return _a.x * _b.x + _a.y * _b.y + _a.z * _b.z + _a.w * _b.w;
}
OZZ_INLINE float Dot(const Float3& _a, const Float3& _b) {
  return _a.x * _b.x + _a.y * _b.y + _a.z * _b.z;
}
OZZ_INLINE float Dot(const Float2& _a, const Float2& _b) {
  return _a.x * _b.x + _a.y * _b.y;
}

// Returns the cross product of _a and _b.
OZZ_INLINE Float3 Cross(const Float3& _a, const Float3& _b) {
  return Float3(_a.y * _b.z - _b.y * _a.z, _a.z * _b.x - _b.z * _a.x,
                _a.x * _b.y - _b.x * _a.y);
}

// Returns the length |_v| of _v.
OZZ_INLINE float Length(const Float4& _v) {
  const float len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  return std::sqrt(len2);
}
OZZ_INLINE float Length(const Float3& _v) {
  const float len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  return std::sqrt(len2);
}
OZZ_INLINE float Length(const Float2& _v) {
  const float len2 = _v.x * _v.x + _v.y * _v.y;
  return std::sqrt(len2);
}

// Returns the square length |_v|^2 of _v.
OZZ_INLINE float LengthSqr(const Float4& _v) {
  return _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
}
OZZ_INLINE float LengthSqr(const Float3& _v) {
  return _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
}
OZZ_INLINE float LengthSqr(const Float2& _v) {
  return _v.x * _v.x + _v.y * _v.y;
}

// Returns the normalized vector _v.
OZZ_INLINE Float4 Normalize(const Float4& _v) {
  const float len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  assert(len2 != 0.f && "_v is not normalizable");
  const float len = std::sqrt(len2);
  return Float4(_v.x / len, _v.y / len, _v.z / len, _v.w / len);
}
OZZ_INLINE Float3 Normalize(const Float3& _v) {
  const float len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  assert(len2 != 0.f && "_v is not normalizable");
  const float len = std::sqrt(len2);
  return Float3(_v.x / len, _v.y / len, _v.z / len);
}
OZZ_INLINE Float2 Normalize(const Float2& _v) {
  const float len2 = _v.x * _v.x + _v.y * _v.y;
  assert(len2 != 0.f && "_v is not normalizable");
  const float len = std::sqrt(len2);
  return Float2(_v.x / len, _v.y / len);
}

// Returns true if _v is normalized.
OZZ_INLINE bool IsNormalized(const Float4& _v) {
  const float len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  return std::abs(len2 - 1.f) < kNormalizationToleranceSq;
}
OZZ_INLINE bool IsNormalized(const Float3& _v) {
  const float len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  return std::abs(len2 - 1.f) < kNormalizationToleranceSq;
}
OZZ_INLINE bool IsNormalized(const Float2& _v) {
  const float len2 = _v.x * _v.x + _v.y * _v.y;
  return std::abs(len2 - 1.f) < kNormalizationToleranceSq;
}

// Returns the normalized vector _v if the norm of _v is not 0.
// Otherwise returns _safer.
OZZ_INLINE Float4 NormalizeSafe(const Float4& _v, const Float4& _safer) {
  assert(IsNormalized(_safer) && "_safer is not normalized");
  const float len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  if (len2 <= 0.f) {
    return _safer;
  }
  const float len = std::sqrt(len2);
  return Float4(_v.x / len, _v.y / len, _v.z / len, _v.w / len);
}
OZZ_INLINE Float3 NormalizeSafe(const Float3& _v, const Float3& _safer) {
  assert(IsNormalized(_safer) && "_safer is not normalized");
  const float len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  if (len2 <= 0.f) {
    return _safer;
  }
  const float len = std::sqrt(len2);
  return Float3(_v.x / len, _v.y / len, _v.z / len);
}
OZZ_INLINE Float2 NormalizeSafe(const Float2& _v, const Float2& _safer) {
  assert(IsNormalized(_safer) && "_safer is not normalized");
  const float len2 = _v.x * _v.x + _v.y * _v.y;
  if (len2 <= 0.f) {
    return _safer;
  }
  const float len = std::sqrt(len2);
  return Float2(_v.x / len, _v.y / len);
}

// Returns the linear interpolation of _a and _b with coefficient _f.
// _f is not limited to range [0,1].
OZZ_INLINE Float4 Lerp(const Float4& _a, const Float4& _b, float _f) {
  return Float4((_b.x - _a.x) * _f + _a.x, (_b.y - _a.y) * _f + _a.y,
                (_b.z - _a.z) * _f + _a.z, (_b.w - _a.w) * _f + _a.w);
}
OZZ_INLINE Float3 Lerp(const Float3& _a, const Float3& _b, float _f) {
  return Float3((_b.x - _a.x) * _f + _a.x, (_b.y - _a.y) * _f + _a.y,
                (_b.z - _a.z) * _f + _a.z);
}
OZZ_INLINE Float2 Lerp(const Float2& _a, const Float2& _b, float _f) {
  return Float2((_b.x - _a.x) * _f + _a.x, (_b.y - _a.y) * _f + _a.y);
}

// Returns true if the distance between _a and _b is less than _tolerance.
OZZ_INLINE bool Compare(const Float4& _a, const Float4& _b, float _tolerance) {
  const math::Float4 diff = _a - _b;
  return Dot(diff, diff) <= _tolerance * _tolerance;
}
OZZ_INLINE bool Compare(const Float3& _a, const Float3& _b, float _tolerance) {
  const math::Float3 diff = _a - _b;
  return Dot(diff, diff) <= _tolerance * _tolerance;
}
OZZ_INLINE bool Compare(const Float2& _a, const Float2& _b, float _tolerance) {
  const math::Float2 diff = _a - _b;
  return Dot(diff, diff) <= _tolerance * _tolerance;
}

// Returns true if each element of a is less than each element of _b.
OZZ_INLINE bool operator<(const Float4& _a, const Float4& _b) {
  return _a.x < _b.x && _a.y < _b.y && _a.z < _b.z && _a.w < _b.w;
}
OZZ_INLINE bool operator<(const Float3& _a, const Float3& _b) {
  return _a.x < _b.x && _a.y < _b.y && _a.z < _b.z;
}
OZZ_INLINE bool operator<(const Float2& _a, const Float2& _b) {
  return _a.x < _b.x && _a.y < _b.y;
}

// Returns true if each element of a is less or equal to each element of _b.
OZZ_INLINE bool operator<=(const Float4& _a, const Float4& _b) {
  return _a.x <= _b.x && _a.y <= _b.y && _a.z <= _b.z && _a.w <= _b.w;
}
OZZ_INLINE bool operator<=(const Float3& _a, const Float3& _b) {
  return _a.x <= _b.x && _a.y <= _b.y && _a.z <= _b.z;
}
OZZ_INLINE bool operator<=(const Float2& _a, const Float2& _b) {
  return _a.x <= _b.x && _a.y <= _b.y;
}

// Returns true if each element of a is greater than each element of _b.
OZZ_INLINE bool operator>(const Float4& _a, const Float4& _b) {
  return _a.x > _b.x && _a.y > _b.y && _a.z > _b.z && _a.w > _b.w;
}
OZZ_INLINE bool operator>(const Float3& _a, const Float3& _b) {
  return _a.x > _b.x && _a.y > _b.y && _a.z > _b.z;
}
OZZ_INLINE bool operator>(const Float2& _a, const Float2& _b) {
  return _a.x > _b.x && _a.y > _b.y;
}

// Returns true if each element of a is greater or equal to each element of _b.
OZZ_INLINE bool operator>=(const Float4& _a, const Float4& _b) {
  return _a.x >= _b.x && _a.y >= _b.y && _a.z >= _b.z && _a.w >= _b.w;
}
OZZ_INLINE bool operator>=(const Float3& _a, const Float3& _b) {
  return _a.x >= _b.x && _a.y >= _b.y && _a.z >= _b.z;
}
OZZ_INLINE bool operator>=(const Float2& _a, const Float2& _b) {
  return _a.x >= _b.x && _a.y >= _b.y;
}

// Returns true if each element of a is equal to each element of _b.
// Uses a bitwise comparison of _a and _b, no tolerance is applied.
OZZ_INLINE bool operator==(const Float4& _a, const Float4& _b) {
  return _a.x == _b.x && _a.y == _b.y && _a.z == _b.z && _a.w == _b.w;
}
OZZ_INLINE bool operator==(const Float3& _a, const Float3& _b) {
  return _a.x == _b.x && _a.y == _b.y && _a.z == _b.z;
}
OZZ_INLINE bool operator==(const Float2& _a, const Float2& _b) {
  return _a.x == _b.x && _a.y == _b.y;
}

// Returns true if each element of a is different from each element of _b.
// Uses a bitwise comparison of _a and _b, no tolerance is applied.
OZZ_INLINE bool operator!=(const Float4& _a, const Float4& _b) {
  return _a.x != _b.x || _a.y != _b.y || _a.z != _b.z || _a.w != _b.w;
}
OZZ_INLINE bool operator!=(const Float3& _a, const Float3& _b) {
  return _a.x != _b.x || _a.y != _b.y || _a.z != _b.z;
}
OZZ_INLINE bool operator!=(const Float2& _a, const Float2& _b) {
  return _a.x != _b.x || _a.y != _b.y;
}

// Returns the minimum of each element of _a and _b.
OZZ_INLINE Float4 Min(const Float4& _a, const Float4& _b) {
  return Float4(_a.x < _b.x ? _a.x : _b.x, _a.y < _b.y ? _a.y : _b.y,
                _a.z < _b.z ? _a.z : _b.z, _a.w < _b.w ? _a.w : _b.w);
}
OZZ_INLINE Float3 Min(const Float3& _a, const Float3& _b) {
  return Float3(_a.x < _b.x ? _a.x : _b.x, _a.y < _b.y ? _a.y : _b.y,
                _a.z < _b.z ? _a.z : _b.z);
}
OZZ_INLINE Float2 Min(const Float2& _a, const Float2& _b) {
  return Float2(_a.x < _b.x ? _a.x : _b.x, _a.y < _b.y ? _a.y : _b.y);
}

// Returns the maximum of each element of _a and _b.
OZZ_INLINE Float4 Max(const Float4& _a, const Float4& _b) {
  return Float4(_a.x > _b.x ? _a.x : _b.x, _a.y > _b.y ? _a.y : _b.y,
                _a.z > _b.z ? _a.z : _b.z, _a.w > _b.w ? _a.w : _b.w);
}
OZZ_INLINE Float3 Max(const Float3& _a, const Float3& _b) {
  return Float3(_a.x > _b.x ? _a.x : _b.x, _a.y > _b.y ? _a.y : _b.y,
                _a.z > _b.z ? _a.z : _b.z);
}
OZZ_INLINE Float2 Max(const Float2& _a, const Float2& _b) {
  return Float2(_a.x > _b.x ? _a.x : _b.x, _a.y > _b.y ? _a.y : _b.y);
}

// Clamps each element of _x between _a and _b.
// _a must be less or equal to b;
OZZ_INLINE Float4 Clamp(const Float4& _a, const Float4& _v, const Float4& _b) {
  const Float4 min(_v.x < _b.x ? _v.x : _b.x, _v.y < _b.y ? _v.y : _b.y,
                   _v.z < _b.z ? _v.z : _b.z, _v.w < _b.w ? _v.w : _b.w);
  return Float4(_a.x > min.x ? _a.x : min.x, _a.y > min.y ? _a.y : min.y,
                _a.z > min.z ? _a.z : min.z, _a.w > min.w ? _a.w : min.w);
}
OZZ_INLINE Float3 Clamp(const Float3& _a, const Float3& _v, const Float3& _b) {
  const Float3 min(_v.x < _b.x ? _v.x : _b.x, _v.y < _b.y ? _v.y : _b.y,
                   _v.z < _b.z ? _v.z : _b.z);
  return Float3(_a.x > min.x ? _a.x : min.x, _a.y > min.y ? _a.y : min.y,
                _a.z > min.z ? _a.z : min.z);
}
OZZ_INLINE Float2 Clamp(const Float2& _a, const Float2& _v, const Float2& _b) {
  const Float2 min(_v.x < _b.x ? _v.x : _b.x, _v.y < _b.y ? _v.y : _b.y);
  return Float2(_a.x > min.x ? _a.x : min.x, _a.y > min.y ? _a.y : min.y);
}
}  // namespace math
}  // namespace ozz
#endif  // OZZ_OZZ_BASE_MATHS_VEC_FLOAT_H_
/**** ended inlining ozz/base/maths/vec_float.h ****/
/**** start inlining ozz/base/maths/quaternion.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_MATHS_QUATERNION_H_
#define OZZ_OZZ_BASE_MATHS_QUATERNION_H_

#include <cassert>

/**** skipping file: ozz/base/maths/math_constant.h ****/
/**** start inlining ozz/base/maths/math_ex.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_MATHS_MATH_EX_H_
#define OZZ_OZZ_BASE_MATHS_MATH_EX_H_

#include <cassert>
#include <cmath>

/**** skipping file: ozz/base/platform.h ****/

namespace ozz {
namespace math {

// Returns the linear interpolation of _a and _b with coefficient _f.
// _f is not limited to range [0,1].
OZZ_INLINE float Lerp(float _a, float _b, float _f) {
  return (_b - _a) * _f + _a;
}

// Returns the minimum of _a and _b. Comparison's based on operator <.
template <typename _Ty>
OZZ_INLINE _Ty Min(_Ty _a, _Ty _b) {
  return (_a < _b) ? _a : _b;
}

// Returns the maximum of _a and _b. Comparison's based on operator <.
template <typename _Ty>
OZZ_INLINE _Ty Max(_Ty _a, _Ty _b) {
  return (_b < _a) ? _a : _b;
}

// Clamps _x between _a and _b. Comparison's based on operator <.
// Result is unknown if _a is not less or equal to _b.
template <typename _Ty>
OZZ_INLINE _Ty Clamp(_Ty _a, _Ty _x, _Ty _b) {
  const _Ty min = _x < _b ? _x : _b;
  return min < _a ? _a : min;
}

// Implements int selection, avoiding branching.
OZZ_INLINE int Select(bool _b, int _true, int _false) {
  return _false ^ (-static_cast<int>(_b) & (_true ^ _false));
}

// Implements float selection, avoiding branching.
OZZ_INLINE float Select(bool _b, float _true, float _false) {
  union {
    float f;
    int32_t i;
  } t = {_true};
  union {
    float f;
    int32_t i;
  } f = {_false};
  union {
    int32_t i;
    float f;
  } r = {f.i ^ (-static_cast<int32_t>(_b) & (t.i ^ f.i))};
  return r.f;
}

// Implements pointer selection, avoiding branching.
template <typename _Ty>
OZZ_INLINE _Ty* Select(bool _b, _Ty* _true, _Ty* _false) {
  union {
    _Ty* p;
    intptr_t i;
  } t = {_true};
  union {
    _Ty* p;
    intptr_t i;
  } f = {_false};
  union {
    intptr_t i;
    _Ty* p;
  } r = {f.i ^ (-static_cast<intptr_t>(_b) & (t.i ^ f.i))};
  return r.p;
}

// Implements const pointer selection, avoiding branching.
template <typename _Ty>
OZZ_INLINE const _Ty* Select(bool _b, const _Ty* _true, const _Ty* _false) {
  union {
    const _Ty* p;
    intptr_t i;
  } t = {_true};
  union {
    const _Ty* p;
    intptr_t i;
  } f = {_false};
  union {
    intptr_t i;
    const _Ty* p;
  } r = {f.i ^ (-static_cast<intptr_t>(_b) & (t.i ^ f.i))};
  return r.p;
}

}  // namespace math
}  // namespace ozz
#endif  // OZZ_OZZ_BASE_MATHS_MATH_EX_H_
/**** ended inlining ozz/base/maths/math_ex.h ****/
/**** skipping file: ozz/base/maths/vec_float.h ****/
/**** skipping file: ozz/base/platform.h ****/

namespace ozz {
namespace math {

struct OZZ_BASE_DLL Quaternion {
  float x, y, z, w;

  // Constructs an uninitialized quaternion.
  OZZ_INLINE Quaternion() {}

  // Constructs a quaternion from 4 floating point values.
  OZZ_INLINE Quaternion(float _x, float _y, float _z, float _w)
      : x(_x), y(_y), z(_z), w(_w) {}

  // Returns a normalized quaternion initialized from an axis angle
  // representation.
  // Assumes the axis part (x, y, z) of _axis_angle is normalized.
  // _angle.x is the angle in radian.
  static OZZ_INLINE Quaternion FromAxisAngle(const Float3& _axis, float _angle);

  // Returns a normalized quaternion initialized from an axis and angle cosine
  // representation.
  // Assumes the axis part (x, y, z) of _axis_angle is normalized.
  // _angle.x is the angle cosine in radian, it must be within [-1,1] range.
  static OZZ_INLINE Quaternion FromAxisCosAngle(const Float3& _axis,
                                                float _cos);

  // Returns a normalized quaternion initialized from an Euler representation.
  // Euler angles are ordered Heading, Elevation and Bank, or Yaw, Pitch and
  // Roll.
  static OZZ_INLINE Quaternion FromEuler(const Float3& _ypr);

  // Returns the quaternion that will rotate vector _from into vector _to,
  // around their plan perpendicular axis.The input vectors don't need to be
  // normalized, they can be null as well.
  static OZZ_INLINE Quaternion FromVectors(const Float3& _from,
                                           const Float3& _to);

  // Returns the quaternion that will rotate vector _from into vector _to,
  // around their plan perpendicular axis. The input vectors must be normalized.
  static OZZ_INLINE Quaternion FromUnitVectors(const Float3& _from,
                                               const Float3& _to);

  // Returns the identity quaternion.
  static OZZ_INLINE Quaternion identity() {
    return Quaternion(0.f, 0.f, 0.f, 1.f);
  }
};

// Returns true if each element of a is equal to each element of _b.
OZZ_INLINE bool operator==(const Quaternion& _a, const Quaternion& _b) {
  return _a.x == _b.x && _a.y == _b.y && _a.z == _b.z && _a.w == _b.w;
}

// Returns true if one element of a differs from one element of _b.
OZZ_INLINE bool operator!=(const Quaternion& _a, const Quaternion& _b) {
  return _a.x != _b.x || _a.y != _b.y || _a.z != _b.z || _a.w != _b.w;
}

// Returns the conjugate of _q. This is the same as the inverse if _q is
// normalized. Otherwise the magnitude of the inverse is 1.f/|_q|.
OZZ_INLINE Quaternion Conjugate(const Quaternion& _q) {
  return Quaternion(-_q.x, -_q.y, -_q.z, _q.w);
}

// Returns the addition of _a and _b.
OZZ_INLINE Quaternion operator+(const Quaternion& _a, const Quaternion& _b) {
  return Quaternion(_a.x + _b.x, _a.y + _b.y, _a.z + _b.z, _a.w + _b.w);
}

// Returns the multiplication of _q and a scalar _f.
OZZ_INLINE Quaternion operator*(const Quaternion& _q, float _f) {
  return Quaternion(_q.x * _f, _q.y * _f, _q.z * _f, _q.w * _f);
}

// Returns the multiplication of _a and _b. If both _a and _b are normalized,
// then the result is normalized.
OZZ_INLINE Quaternion operator*(const Quaternion& _a, const Quaternion& _b) {
  return Quaternion(_a.w * _b.x + _a.x * _b.w + _a.y * _b.z - _a.z * _b.y,
                    _a.w * _b.y + _a.y * _b.w + _a.z * _b.x - _a.x * _b.z,
                    _a.w * _b.z + _a.z * _b.w + _a.x * _b.y - _a.y * _b.x,
                    _a.w * _b.w - _a.x * _b.x - _a.y * _b.y - _a.z * _b.z);
}

// Returns the negate of _q. This represent the same rotation as q.
OZZ_INLINE Quaternion operator-(const Quaternion& _q) {
  return Quaternion(-_q.x, -_q.y, -_q.z, -_q.w);
}

// Returns true if the angle between _a and _b is less than _tolerance.
OZZ_INLINE bool Compare(const math::Quaternion& _a, const math::Quaternion& _b,
                        float _cos_half_tolerance) {
  // Computes w component of a-1 * b.
  const float cos_half_angle =
      _a.x * _b.x + _a.y * _b.y + _a.z * _b.z + _a.w * _b.w;
  return std::abs(cos_half_angle) >= _cos_half_tolerance;
}

// Returns true if _q is a normalized quaternion.
OZZ_INLINE bool IsNormalized(const Quaternion& _q) {
  const float sq_len = _q.x * _q.x + _q.y * _q.y + _q.z * _q.z + _q.w * _q.w;
  return std::abs(sq_len - 1.f) < kNormalizationToleranceSq;
}

// Returns the normalized quaternion _q.
OZZ_INLINE Quaternion Normalize(const Quaternion& _q) {
  const float sq_len = _q.x * _q.x + _q.y * _q.y + _q.z * _q.z + _q.w * _q.w;
  assert(sq_len != 0.f && "_q is not normalizable");
  const float inv_len = 1.f / std::sqrt(sq_len);
  return Quaternion(_q.x * inv_len, _q.y * inv_len, _q.z * inv_len,
                    _q.w * inv_len);
}

// Returns the normalized quaternion _q if the norm of _q is not 0.
// Otherwise returns _safer.
OZZ_INLINE Quaternion NormalizeSafe(const Quaternion& _q,
                                    const Quaternion& _safer) {
  assert(IsNormalized(_safer) && "_safer is not normalized");
  const float sq_len = _q.x * _q.x + _q.y * _q.y + _q.z * _q.z + _q.w * _q.w;
  if (sq_len == 0) {
    return _safer;
  }
  const float inv_len = 1.f / std::sqrt(sq_len);
  return Quaternion(_q.x * inv_len, _q.y * inv_len, _q.z * inv_len,
                    _q.w * inv_len);
}

OZZ_INLINE Quaternion Quaternion::FromAxisAngle(const Float3& _axis,
                                                float _angle) {
  assert(IsNormalized(_axis) && "axis is not normalized.");
  const float half_angle = _angle * .5f;
  const float half_sin = std::sin(half_angle);
  const float half_cos = std::cos(half_angle);
  return Quaternion(_axis.x * half_sin, _axis.y * half_sin, _axis.z * half_sin,
                    half_cos);
}

OZZ_INLINE Quaternion Quaternion::FromAxisCosAngle(const Float3& _axis,
                                                   float _cos) {
  assert(IsNormalized(_axis) && "axis is not normalized.");
  assert(_cos >= -1.f && _cos <= 1.f && "cos is not in [-1,1] range.");

  const float half_cos2 = (1.f + _cos) * 0.5f;
  const float half_sin = std::sqrt(1.f - half_cos2);
  return Quaternion(_axis.x * half_sin, _axis.y * half_sin, _axis.z * half_sin,
                    std::sqrt(half_cos2));
}

// Returns to an axis angle representation of quaternion _q.
// Assumes quaternion _q is normalized.
OZZ_INLINE Float4 ToAxisAngle(const Quaternion& _q) {
  assert(IsNormalized(_q));
  const float clamped_w = Clamp(-1.f, _q.w, 1.f);
  const float angle = 2.f * std::acos(clamped_w);
  const float s = std::sqrt(1.f - clamped_w * clamped_w);

  // Assuming quaternion normalized then s always positive.
  if (s < .001f) {  // Tests to avoid divide by zero.
    // If s close to zero then direction of axis is not important.
    return Float4(1.f, 0.f, 0.f, angle);
  } else {
    // Normalize axis
    const float inv_s = 1.f / s;
    return Float4(_q.x * inv_s, _q.y * inv_s, _q.z * inv_s, angle);
  }
}

OZZ_INLINE Quaternion Quaternion::FromEuler(const Float3& ypr) {
  const float half_yaw = ypr.x * .5f;
  const float c1 = std::cos(half_yaw);
  const float s1 = std::sin(half_yaw);
  const float half_pitch = ypr.y * .5f;
  const float c2 = std::cos(half_pitch);
  const float s2 = std::sin(half_pitch);
  const float half_roll = ypr.z * .5f;
  const float c3 = std::cos(half_roll);
  const float s3 = std::sin(half_roll);
  const float c1c2 = c1 * c2;
  const float s1s2 = s1 * s2;
  return Quaternion(c1c2 * s3 + s1s2 * c3, s1 * c2 * c3 + c1 * s2 * s3,
                    c1 * s2 * c3 - s1 * c2 * s3, c1c2 * c3 - s1s2 * s3);
}

// Returns to an Euler representation of quaternion _q.
// Quaternion _q does not require to be normalized.
OZZ_INLINE Float3 ToEuler(const Quaternion& _q) {
  const float sqw = _q.w * _q.w;
  const float sqx = _q.x * _q.x;
  const float sqy = _q.y * _q.y;
  const float sqz = _q.z * _q.z;
  // If normalized is one, otherwise is correction factor.
  const float unit = sqx + sqy + sqz + sqw;
  const float test = _q.x * _q.y + _q.z * _q.w;
  Float3 euler;
  if (test > .499f * unit) {  // Singularity at north pole
    euler.x = 2.f * std::atan2(_q.x, _q.w);
    euler.y = ozz::math::kPi_2;
    euler.z = 0;
  } else if (test < -.499f * unit) {  // Singularity at south pole
    euler.x = -2 * std::atan2(_q.x, _q.w);
    euler.y = -kPi_2;
    euler.z = 0;
  } else {
    euler.x = std::atan2(2.f * _q.y * _q.w - 2.f * _q.x * _q.z,
                         sqx - sqy - sqz + sqw);
    euler.y = std::asin(2.f * test / unit);
    euler.z = std::atan2(2.f * _q.x * _q.w - 2.f * _q.y * _q.z,
                         -sqx + sqy - sqz + sqw);
  }
  return euler;
}

OZZ_INLINE Quaternion Quaternion::FromVectors(const Float3& _from,
                                              const Float3& _to) {
  // http://lolengine.net/blog/2014/02/24/quaternion-from-two-vectors-final

  const float norm_from_norm_to = std::sqrt(LengthSqr(_from) * LengthSqr(_to));
  if (norm_from_norm_to < 1.e-5f) {
    return Quaternion::identity();
  }
  const float real_part = norm_from_norm_to + Dot(_from, _to);
  Quaternion quat;
  if (real_part < 1.e-6f * norm_from_norm_to) {
    // If _from and _to are exactly opposite, rotate 180 degrees around an
    // arbitrary orthogonal axis. Axis normalization can happen later, when we
    // normalize the quaternion.
    quat = std::abs(_from.x) > std::abs(_from.z)
               ? Quaternion(-_from.y, _from.x, 0.f, 0.f)
               : Quaternion(0.f, -_from.z, _from.y, 0.f);
  } else {
    const Float3 cross = Cross(_from, _to);
    quat = Quaternion(cross.x, cross.y, cross.z, real_part);
  }
  return Normalize(quat);
}

OZZ_INLINE Quaternion Quaternion::FromUnitVectors(const Float3& _from,
                                                  const Float3& _to) {
  assert(IsNormalized(_from) && IsNormalized(_to) &&
         "Input vectors must be normalized.");

  // http://lolengine.net/blog/2014/02/24/quaternion-from-two-vectors-final
  const float real_part = 1.f + Dot(_from, _to);
  if (real_part < 1.e-6f) {
    // If _from and _to are exactly opposite, rotate 180 degrees around an
    // arbitrary orthogonal axis.
    // Normalisation isn't needed, as from is already.
    return std::abs(_from.x) > std::abs(_from.z)
               ? Quaternion(-_from.y, _from.x, 0.f, 0.f)
               : Quaternion(0.f, -_from.z, _from.y, 0.f);
  } else {
    const Float3 cross = Cross(_from, _to);
    return Normalize(Quaternion(cross.x, cross.y, cross.z, real_part));
  }
}

// Returns the dot product of _a and _b.
OZZ_INLINE float Dot(const Quaternion& _a, const Quaternion& _b) {
  return _a.x * _b.x + _a.y * _b.y + _a.z * _b.z + _a.w * _b.w;
}

// Returns the linear interpolation of quaternion _a and _b with coefficient
// _f.
OZZ_INLINE Quaternion Lerp(const Quaternion& _a, const Quaternion& _b,
                           float _f) {
  return Quaternion((_b.x - _a.x) * _f + _a.x, (_b.y - _a.y) * _f + _a.y,
                    (_b.z - _a.z) * _f + _a.z, (_b.w - _a.w) * _f + _a.w);
}

// Returns the linear interpolation of quaternion _a and _b with coefficient
// _f. _a and _n must be from the same hemisphere (aka dot(_a, _b) >= 0).
OZZ_INLINE Quaternion NLerp(const Quaternion& _a, const Quaternion& _b,
                            float _f) {
  const Float4 lerp((_b.x - _a.x) * _f + _a.x, (_b.y - _a.y) * _f + _a.y,
                    (_b.z - _a.z) * _f + _a.z, (_b.w - _a.w) * _f + _a.w);
  const float sq_len =
      lerp.x * lerp.x + lerp.y * lerp.y + lerp.z * lerp.z + lerp.w * lerp.w;
  const float inv_len = 1.f / std::sqrt(sq_len);
  return Quaternion(lerp.x * inv_len, lerp.y * inv_len, lerp.z * inv_len,
                    lerp.w * inv_len);
}

// Returns the spherical interpolation of quaternion _a and _b with
// coefficient _f.
OZZ_INLINE Quaternion SLerp(const Quaternion& _a, const Quaternion& _b,
                            float _f) {
  assert(IsNormalized(_a));
  assert(IsNormalized(_b));
  // Calculate angle between them.
  float cos_half_theta = _a.x * _b.x + _a.y * _b.y + _a.z * _b.z + _a.w * _b.w;

  // If _a=_b or _a=-_b then theta = 0 and we can return _a.
  if (std::abs(cos_half_theta) >= .999f) {
    return _a;
  }

  // Calculate temporary values.
  const float half_theta = std::acos(cos_half_theta);
  const float sin_half_theta = std::sqrt(1.f - cos_half_theta * cos_half_theta);

  // If theta = pi then result is not fully defined, we could rotate around
  // any axis normal to _a or _b.
  if (sin_half_theta < .001f) {
    return Quaternion((_a.x + _b.x) * .5f, (_a.y + _b.y) * .5f,
                      (_a.z + _b.z) * .5f, (_a.w + _b.w) * .5f);
  }

  const float ratio_a = std::sin((1.f - _f) * half_theta) / sin_half_theta;
  const float ratio_b = std::sin(_f * half_theta) / sin_half_theta;

  // Calculate Quaternion.
  return Quaternion(
      ratio_a * _a.x + ratio_b * _b.x, ratio_a * _a.y + ratio_b * _b.y,
      ratio_a * _a.z + ratio_b * _b.z, ratio_a * _a.w + ratio_b * _b.w);
}

// Computes the transformation of a Quaternion and a vector _v.
// This is equivalent to carrying out the quaternion multiplications:
// _q.conjugate() * (*this) * _q
OZZ_INLINE Float3 TransformVector(const Quaternion& _q, const Float3& _v) {
  // http://www.neil.dantam.name/note/dantam-quaternion.pdf
  // _v + 2.f * cross(_q.xyz, cross(_q.xyz, _v) + _q.w * _v);
  const Float3 a(_q.y * _v.z - _q.z * _v.y + _v.x * _q.w,
                 _q.z * _v.x - _q.x * _v.z + _v.y * _q.w,
                 _q.x * _v.y - _q.y * _v.x + _v.z * _q.w);
  const Float3 b(_q.y * a.z - _q.z * a.y, _q.z * a.x - _q.x * a.z,
                 _q.x * a.y - _q.y * a.x);
  return Float3(_v.x + b.x + b.x, _v.y + b.y + b.y, _v.z + b.z + b.z);
}
}  // namespace math
}  // namespace ozz
#endif  // OZZ_OZZ_BASE_MATHS_QUATERNION_H_
/**** ended inlining ozz/base/maths/quaternion.h ****/
/**** start inlining ozz/base/maths/simd_math.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_MATHS_SIMD_MATH_H_
#define OZZ_OZZ_BASE_MATHS_SIMD_MATH_H_

/**** start inlining ozz/base/maths/internal/simd_math_config.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_MATHS_INTERNAL_SIMD_MATH_CONFIG_H_
#define OZZ_OZZ_BASE_MATHS_INTERNAL_SIMD_MATH_CONFIG_H_

/**** skipping file: ozz/base/platform.h ****/

// Avoid SIMD instruction detection if reference (aka scalar) implementation is
// forced.
#if !defined(OZZ_BUILD_SIMD_REF)

// Try to match a SSE2+ version.
#if defined(__AVX2__) || defined(OZZ_SIMD_AVX2)
#include <immintrin.h>
#define OZZ_SIMD_AVX2
#define OZZ_SIMD_AVX  // avx is available if avx2 is.
#endif

#if defined(__FMA__) || defined(OZZ_SIMD_FMA)
#include <immintrin.h>
#define OZZ_SIMD_FMA
#endif

#if defined(__AVX__) || defined(OZZ_SIMD_AVX)
#include <immintrin.h>
#define OZZ_SIMD_AVX
#define OZZ_SIMD_SSE4_2  // SSE4.2 is available if avx is.
#endif

#if defined(__SSE4_2__) || defined(OZZ_SIMD_SSE4_2)
#include <nmmintrin.h>
#define OZZ_SIMD_SSE4_2
#define OZZ_SIMD_SSE4_1  // SSE4.1 is available if SSE4.2 is.
#endif

#if defined(__SSE4_1__) || defined(OZZ_SIMD_SSE4_1)
#include <smmintrin.h>
#define OZZ_SIMD_SSE4_1
#define OZZ_SIMD_SSSE3  // SSSE3 is available if SSE4.1 is.
#endif

#if defined(__SSSE3__) || defined(OZZ_SIMD_SSSE3)
#include <tmmintrin.h>
#define OZZ_SIMD_SSSE3
#define OZZ_SIMD_SSE3  // SSE3 is available if SSSE3 is.
#endif

#if defined(__SSE3__) || defined(OZZ_SIMD_SSE3)
#include <pmmintrin.h>
#define OZZ_SIMD_SSE3
#define OZZ_SIMD_SSE2  // SSE2 is available if SSE3 is.
#endif

// x64/amd64 have SSE2 instructions
// _M_IX86_FP is 2 if /arch:SSE2, /arch:AVX or /arch:AVX2 was used.
#if defined(__SSE2__) || defined(_M_AMD64) || defined(_M_X64) || \
    (_M_IX86_FP >= 2) || defined(OZZ_SIMD_SSE2)
#include <emmintrin.h>
#define OZZ_SIMD_SSE2
#define OZZ_SIMD_SSEx  // OZZ_SIMD_SSEx is the generic flag for SSE support
#endif

// Try to match a Arm NEON
#if defined(__ARM_NEON) || defined(OZZ_SIMD_ARM_NEON)
// #include <arm_neon.h>
// #define OZZ_SIMD_ARM_NEON
#endif

// End of SIMD instruction detection
#endif  // !OZZ_BUILD_SIMD_REF

// SEE* intrinsics available
#if defined(OZZ_SIMD_SSEx)

namespace ozz {
namespace math {

// Vector of four floating point values.
typedef __m128 SimdFloat4;

// Argument type for Float4.
typedef const __m128 _SimdFloat4;

// Vector of four integer values.
typedef __m128i SimdInt4;

// Argument type for Int4.
typedef const __m128i _SimdInt4;
}  // namespace math
}  // namespace ozz

#else  // No builtin simd available

// No simd instruction set detected, switch back to reference implementation.
// OZZ_SIMD_REF is the generic flag for SIMD reference implementation.
#define OZZ_SIMD_REF

// Declares reference simd float and integer vectors outside of ozz::math, in
// order to match non-reference implementation details.

// Vector of four floating point values.
struct SimdFloat4Def {
  alignas(16) float x;
  float y;
  float z;
  float w;
};

// Vector of four integer values.
struct SimdInt4Def {
  alignas(16) int x;
  int y;
  int z;
  int w;
};

namespace ozz {
namespace math {

// Vector of four floating point values.
typedef SimdFloat4Def SimdFloat4;

// Argument type for SimdFloat4
typedef const SimdFloat4& _SimdFloat4;

// Vector of four integer values.
typedef SimdInt4Def SimdInt4;

// Argument type for SimdInt4.
typedef const SimdInt4& _SimdInt4;

}  // namespace math
}  // namespace ozz
#endif  // OZZ_SIMD_x

// Native SIMD operator already exist on some compilers, so they have to be
// disable from ozz implementation
#if !defined(OZZ_SIMD_REF) && (defined(__GNUC__) || defined(__llvm__))
#define OZZ_DISABLE_SSE_NATIVE_OPERATORS
#endif
#endif  // OZZ_OZZ_BASE_MATHS_INTERNAL_SIMD_MATH_CONFIG_H_
/**** ended inlining ozz/base/maths/internal/simd_math_config.h ****/
/**** skipping file: ozz/base/maths/quaternion.h ****/
/**** start inlining ozz/base/maths/transform.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_MATHS_TRANSFORM_H_
#define OZZ_OZZ_BASE_MATHS_TRANSFORM_H_

/**** skipping file: ozz/base/maths/quaternion.h ****/
/**** skipping file: ozz/base/maths/vec_float.h ****/
/**** skipping file: ozz/base/platform.h ****/

namespace ozz {
namespace math {

// Stores an affine transformation with separate translation, rotation and scale
// attributes.
struct OZZ_BASE_DLL Transform {
  // Translation affine transformation component.
  Float3 translation;

  // Rotation affine transformation component.
  Quaternion rotation;

  // Scale affine transformation component.
  Float3 scale;

  // Builds an identity transform.
  static OZZ_INLINE Transform identity() {
    const Transform ret = {Float3::zero(), Quaternion::identity(),
                           Float3::one()};
    return ret;
  }
};
}  // namespace math
}  // namespace ozz
#endif  // OZZ_OZZ_BASE_MATHS_TRANSFORM_H_
/**** ended inlining ozz/base/maths/transform.h ****/
/**** skipping file: ozz/base/maths/vec_float.h ****/
/**** skipping file: ozz/base/platform.h ****/

namespace ozz {
namespace math {

// Returns SIMDimplementation name has decided at library build time.
OZZ_BASE_DLL const char* SimdImplementationName();

namespace simd_float4 {
// Returns a SimdFloat4 vector with all components set to 0.
OZZ_INLINE SimdFloat4 zero();

// Returns a SimdFloat4 vector with all components set to 1.
OZZ_INLINE SimdFloat4 one();

// Returns a SimdFloat4 vector with the x component set to 1 and all the others
// to 0.
OZZ_INLINE SimdFloat4 x_axis();

// Returns a SimdFloat4 vector with the y component set to 1 and all the others
// to 0.
OZZ_INLINE SimdFloat4 y_axis();

// Returns a SimdFloat4 vector with the z component set to 1 and all the others
// to 0.
OZZ_INLINE SimdFloat4 z_axis();

// Returns a SimdFloat4 vector with the w component set to 1 and all the others
// to 0.
OZZ_INLINE SimdFloat4 w_axis();

// Loads _x, _y, _z, _w to the returned vector.
// r.x = _x
// r.y = _y
// r.z = _z
// r.w = _w
OZZ_INLINE SimdFloat4 Load(float _x, float _y, float _z, float _w);

// Loads _x to the x component of the returned vector, and sets y, z and w to 0.
// r.x = _x
// r.y = 0
// r.z = 0
// r.w = 0
OZZ_INLINE SimdFloat4 LoadX(float _x);

// Loads _x to the all the components of the returned vector.
// r.x = _x
// r.y = _x
// r.z = _x
// r.w = _x
OZZ_INLINE SimdFloat4 Load1(float _x);

// Loads the 4 values of _f to the returned vector.
// _f must be aligned to 16 bytes.
// r.x = _f[0]
// r.y = _f[1]
// r.z = _f[2]
// r.w = _f[3]
OZZ_INLINE SimdFloat4 LoadPtr(const float* _f);

// Loads the 4 values of _f to the returned vector.
// _f must be aligned to 4 bytes.
// r.x = _f[0]
// r.y = _f[1]
// r.z = _f[2]
// r.w = _f[3]
OZZ_INLINE SimdFloat4 LoadPtrU(const float* _f);

// Loads _f[0] to the x component of the returned vector, and sets y, z and w
// to 0.
// _f must be aligned to 4 bytes.
// r.x = _f[0]
// r.y = 0
// r.z = 0
// r.w = 0
OZZ_INLINE SimdFloat4 LoadXPtrU(const float* _f);

// Loads _f[0] to all the components of the returned vector.
// _f must be aligned to 4 bytes.
// r.x = _f[0]
// r.y = _f[0]
// r.z = _f[0]
// r.w = _f[0]
OZZ_INLINE SimdFloat4 Load1PtrU(const float* _f);

// Loads the 2 first value of _f to the x and y components of the returned
// vector. The remaining components are set to 0.
// _f must be aligned to 4 bytes.
// r.x = _f[0]
// r.y = _f[1]
// r.z = 0
// r.w = 0
OZZ_INLINE SimdFloat4 Load2PtrU(const float* _f);

// Loads the 3 first value of _f to the x, y and z components of the returned
// vector. The remaining components are set to 0.
// _f must be aligned to 4 bytes.
// r.x = _f[0]
// r.y = _f[1]
// r.z = _f[2]
// r.w = 0
OZZ_INLINE SimdFloat4 Load3PtrU(const float* _f);

// Loads Float2, 3, 4 to SimdFloat4. The remaining components are set to 0.
OZZ_INLINE SimdFloat4 Load(const Float2& _v) { return Load2PtrU(&_v.x); }
OZZ_INLINE SimdFloat4 Load(const Float3& _v) { return Load3PtrU(&_v.x); }
OZZ_INLINE SimdFloat4 Load(const Float4& _v) { return LoadPtrU(&_v.x); }

// Convert from integer to float.
OZZ_INLINE SimdFloat4 FromInt(_SimdInt4 _i);
}  // namespace simd_float4

// Returns the x component of _v as a float.
OZZ_INLINE float GetX(_SimdFloat4 _v);

// Returns the y component of _v as a float.
OZZ_INLINE float GetY(_SimdFloat4 _v);

// Returns the z component of _v as a float.
OZZ_INLINE float GetZ(_SimdFloat4 _v);

// Returns the w component of _v as a float.
OZZ_INLINE float GetW(_SimdFloat4 _v);

// Returns _v with the x component set to x component of _f.
OZZ_INLINE SimdFloat4 SetX(_SimdFloat4 _v, _SimdFloat4 _f);

// Returns _v with the y component set to  x component of _f.
OZZ_INLINE SimdFloat4 SetY(_SimdFloat4 _v, _SimdFloat4 _f);

// Returns _v with the z component set to  x component of _f.
OZZ_INLINE SimdFloat4 SetZ(_SimdFloat4 _v, _SimdFloat4 _f);

// Returns _v with the w component set to  x component of _f.
OZZ_INLINE SimdFloat4 SetW(_SimdFloat4 _v, _SimdFloat4 _f);

// Returns _v with the _i th component set to _f.
// _i must be in range [0,3]
OZZ_INLINE SimdFloat4 SetI(_SimdFloat4 _v, _SimdFloat4 _f, int _i);

// Stores the 4 components of _v to the four first floats of _f.
// _f must be aligned to 16 bytes.
// _f[0] = _v.x
// _f[1] = _v.y
// _f[2] = _v.z
// _f[3] = _v.w
OZZ_INLINE void StorePtr(_SimdFloat4 _v, float* _f);

// Stores the x component of _v to the first float of _f.
// _f must be aligned to 16 bytes.
// _f[0] = _v.x
OZZ_INLINE void Store1Ptr(_SimdFloat4 _v, float* _f);

// Stores x and y components of _v to the two first floats of _f.
// _f must be aligned to 16 bytes.
// _f[0] = _v.x
// _f[1] = _v.y
OZZ_INLINE void Store2Ptr(_SimdFloat4 _v, float* _f);

// Stores x, y and z components of _v to the three first floats of _f.
// _f must be aligned to 16 bytes.
// _f[0] = _v.x
// _f[1] = _v.y
// _f[2] = _v.z
OZZ_INLINE void Store3Ptr(_SimdFloat4 _v, float* _f);

// Stores the 4 components of _v to the four first floats of _f.
// _f must be aligned to 4 bytes.
// _f[0] = _v.x
// _f[1] = _v.y
// _f[2] = _v.z
// _f[3] = _v.w
OZZ_INLINE void StorePtrU(_SimdFloat4 _v, float* _f);

// Stores the x component of _v to the first float of _f.
// _f must be aligned to 4 bytes.
// _f[0] = _v.x
OZZ_INLINE void Store1PtrU(_SimdFloat4 _v, float* _f);

// Stores x and y components of _v to the two first floats of _f.
// _f must be aligned to 4 bytes.
// _f[0] = _v.x
// _f[1] = _v.y
OZZ_INLINE void Store2PtrU(_SimdFloat4 _v, float* _f);

// Stores x, y and z components of _v to the three first floats of _f.
// _f must be aligned to 4 bytes.
// _f[0] = _v.x
// _f[1] = _v.y
// _f[2] = _v.z
OZZ_INLINE void Store3PtrU(_SimdFloat4 _v, float* _f);

// Replicates x of _a to all the components of the returned vector.
OZZ_INLINE SimdFloat4 SplatX(_SimdFloat4 _v);

// Replicates y of _a to all the components of the returned vector.
OZZ_INLINE SimdFloat4 SplatY(_SimdFloat4 _v);

// Replicates z of _a to all the components of the returned vector.
OZZ_INLINE SimdFloat4 SplatZ(_SimdFloat4 _v);

// Replicates w of _a to all the components of the returned vector.
OZZ_INLINE SimdFloat4 SplatW(_SimdFloat4 _v);

// Swizzle x, y, z and w components based on compile time arguments _X, _Y, _Z
// and _W. Arguments can vary from 0 (x), to 3 (w).
template <size_t _X, size_t _Y, size_t _Z, size_t _W>
OZZ_INLINE SimdFloat4 Swizzle(_SimdFloat4 _v);

// Transposes the x components of the 4 SimdFloat4 of _in into the 1
// SimdFloat4 of _out.
OZZ_INLINE void Transpose4x1(const SimdFloat4 _in[4], SimdFloat4 _out[1]);

// Transposes x, y, z and w components of _in to the x components of _out.
// Remaining y, z and w are set to 0.
OZZ_INLINE void Transpose1x4(const SimdFloat4 _in[1], SimdFloat4 _out[4]);

// Transposes the x and y components of the 4 SimdFloat4 of _in into the 2
// SimdFloat4 of _out.
OZZ_INLINE void Transpose4x2(const SimdFloat4 _in[4], SimdFloat4 _out[2]);

// Transposes the 2 SimdFloat4 of _in into the x and y components of the 4
// SimdFloat4 of _out. Remaining z and w are set to 0.
OZZ_INLINE void Transpose2x4(const SimdFloat4 _in[2], SimdFloat4 _out[4]);

// Transposes the x, y and z components of the 4 SimdFloat4 of _in into the 3
// SimdFloat4 of _out.
OZZ_INLINE void Transpose4x3(const SimdFloat4 _in[4], SimdFloat4 _out[3]);

// Transposes the 3 SimdFloat4 of _in into the x, y and z components of the 4
// SimdFloat4 of _out. Remaining w are set to 0.
OZZ_INLINE void Transpose3x4(const SimdFloat4 _in[3], SimdFloat4 _out[4]);

// Transposes the 4 SimdFloat4 of _in into the 4 SimdFloat4 of _out.
OZZ_INLINE void Transpose4x4(const SimdFloat4 _in[4], SimdFloat4 _out[4]);

// Transposes the 16 SimdFloat4 of _in into the 16 SimdFloat4 of _out.
OZZ_INLINE void Transpose16x16(const SimdFloat4 _in[16], SimdFloat4 _out[16]);

// Multiplies _a and _b, then adds _c.
// v = (_a * _b) + _c
OZZ_INLINE SimdFloat4 MAdd(_SimdFloat4 _a, _SimdFloat4 _b, _SimdFloat4 _c);

// Multiplies _a and _b, then subs _c.
// v = (_a * _b) + _c
OZZ_INLINE SimdFloat4 MSub(_SimdFloat4 _a, _SimdFloat4 _b, _SimdFloat4 _c);

// Multiplies _a and _b, negate it, then adds _c.
// v = -(_a * _b) + _c
OZZ_INLINE SimdFloat4 NMAdd(_SimdFloat4 _a, _SimdFloat4 _b, _SimdFloat4 _c);

// Multiplies _a and _b, negate it, then subs _c.
// v = -(_a * _b) + _c
OZZ_INLINE SimdFloat4 NMSub(_SimdFloat4 _a, _SimdFloat4 _b, _SimdFloat4 _c);

// Divides the x component of _a by the _x component of _b and stores it in the
// x component of the returned vector. y, z, w of the returned vector are the
// same as _a respective components.
// r.x = _a.x / _b.x
// r.y = _a.y
// r.z = _a.z
// r.w = _a.w
OZZ_INLINE SimdFloat4 DivX(_SimdFloat4 _a, _SimdFloat4 _b);

// Computes the (horizontal) addition of x and y components of _v. The result is
// stored in the x component of the returned value. y, z, w of the returned
// vector are the same as their respective components in _v.
// r.x = _a.x + _a.y
// r.y = _a.y
// r.z = _a.z
// r.w = _a.w
OZZ_INLINE SimdFloat4 HAdd2(_SimdFloat4 _v);

// Computes the (horizontal) addition of x, y and z components of _v. The result
// is stored in the x component of the returned value. y, z, w of the returned
// vector are the same as their respective components in _v.
// r.x = _a.x + _a.y + _a.z
// r.y = _a.y
// r.z = _a.z
// r.w = _a.w
OZZ_INLINE SimdFloat4 HAdd3(_SimdFloat4 _v);

// Computes the (horizontal) addition of x and y components of _v. The result is
// stored in the x component of the returned value. y, z, w of the returned
// vector are the same as their respective components in _v.
// r.x = _a.x + _a.y + _a.z + _a.w
// r.y = _a.y
// r.z = _a.z
// r.w = _a.w
OZZ_INLINE SimdFloat4 HAdd4(_SimdFloat4 _v);

// Computes the dot product of x and y components of _v. The result is
// stored in the x component of the returned value. y, z, w of the returned
// vector are undefined.
// r.x = _a.x * _a.x + _a.y * _a.y
// r.y = ?
// r.z = ?
// r.w = ?
OZZ_INLINE SimdFloat4 Dot2(_SimdFloat4 _a, _SimdFloat4 _b);

// Computes the dot product of x, y and z components of _v. The result is
// stored in the x component of the returned value. y, z, w of the returned
// vector are undefined.
// r.x = _a.x * _a.x + _a.y * _a.y + _a.z * _a.z
// r.y = ?
// r.z = ?
// r.w = ?
OZZ_INLINE SimdFloat4 Dot3(_SimdFloat4 _a, _SimdFloat4 _b);

// Computes the dot product of x, y, z and w components of _v. The result is
// stored in the x component of the returned value. y, z, w of the returned
// vector are undefined.
// r.x = _a.x * _a.x + _a.y * _a.y + _a.z * _a.z + _a.w * _a.w
// r.y = ?
// r.z = ?
// r.w = ?
OZZ_INLINE SimdFloat4 Dot4(_SimdFloat4 _a, _SimdFloat4 _b);

// Computes the cross product of x, y and z components of _v. The result is
// stored in the x, y and z components of the returned value. w of the returned
// vector is undefined.
// r.x = _a.y * _b.z - _a.z * _b.y
// r.y = _a.z * _b.x - _a.x * _b.z
// r.z = _a.x * _b.y - _a.y * _b.x
// r.w = ?
OZZ_INLINE SimdFloat4 Cross3(_SimdFloat4 _a, _SimdFloat4 _b);

// Returns the per component estimated reciprocal of _v.
OZZ_INLINE SimdFloat4 RcpEst(_SimdFloat4 _v);

// Returns the per component estimated reciprocal of _v, where approximation is
// improved with one more new Newton-Raphson step.
OZZ_INLINE SimdFloat4 RcpEstNR(_SimdFloat4 _v);

// Returns the estimated reciprocal of the x component of _v and stores it in
// the x component of the returned vector. y, z, w of the returned vector are
// the same as their respective components in _v.
OZZ_INLINE SimdFloat4 RcpEstX(_SimdFloat4 _v);

// Returns the estimated reciprocal of the x component of _v, where
// approximation is improved with one more new Newton-Raphson step. y, z, w of
// the returned vector are undefined.
OZZ_INLINE SimdFloat4 RcpEstXNR(_SimdFloat4 _v);

// Returns the per component square root of _v.
OZZ_INLINE SimdFloat4 Sqrt(_SimdFloat4 _v);

// Returns the square root of the x component of _v and stores it in the x
// component of the returned vector. y, z, w of the returned vector are the
// same as their respective components in _v.
OZZ_INLINE SimdFloat4 SqrtX(_SimdFloat4 _v);

// Returns the per component estimated reciprocal square root of _v.
OZZ_INLINE SimdFloat4 RSqrtEst(_SimdFloat4 _v);

// Returns the per component estimated reciprocal square root of _v, where
// approximation is improved with one more new Newton-Raphson step.
OZZ_INLINE SimdFloat4 RSqrtEstNR(_SimdFloat4 _v);

// Returns the estimated reciprocal square root of the x component of _v and
// stores it in the x component of the returned vector. y, z, w of the returned
// vector are the same as their respective components in _v.
OZZ_INLINE SimdFloat4 RSqrtEstX(_SimdFloat4 _v);

// Returns the estimated reciprocal square root of the x component of _v, where
// approximation is improved with one more new Newton-Raphson step. y, z, w of
// the returned vector are undefined.
OZZ_INLINE SimdFloat4 RSqrtEstXNR(_SimdFloat4 _v);

// Returns the per element absolute value of _v.
OZZ_INLINE SimdFloat4 Abs(_SimdFloat4 _v);

// Returns the sign bit of _v.
OZZ_INLINE SimdInt4 Sign(_SimdFloat4 _v);

// Returns the per component minimum of _a and _b.
OZZ_INLINE SimdFloat4 Min(_SimdFloat4 _a, _SimdFloat4 _b);

// Returns the per component maximum of _a and _b.
OZZ_INLINE SimdFloat4 Max(_SimdFloat4 _a, _SimdFloat4 _b);

// Returns the per component minimum of _v and 0.
OZZ_INLINE SimdFloat4 Min(_SimdFloat4 _v);

// Returns the per component maximum of _v and 0.
OZZ_INLINE SimdFloat4 Max0(_SimdFloat4 _v);

// Clamps each element of _x between _a and _b.
// Result is unknown if _a is not less or equal to _b.
OZZ_INLINE SimdFloat4 Clamp(_SimdFloat4 _a, _SimdFloat4 _v, _SimdFloat4 _b);

// Computes the length of the components x and y of _v, and stores it in the x
// component of the returned vector. y, z, w of the returned vector are
// undefined.
OZZ_INLINE SimdFloat4 Length2(_SimdFloat4 _v);

// Computes the length of the components x, y and z of _v, and stores it in the
// x component of the returned vector. undefined.
OZZ_INLINE SimdFloat4 Length3(_SimdFloat4 _v);

// Computes the length of _v, and stores it in the x component of the returned
// vector. y, z, w of the returned vector are undefined.
OZZ_INLINE SimdFloat4 Length4(_SimdFloat4 _v);

// Computes the square length of the components x and y of _v, and stores it
// in the x component of the returned vector. y, z, w of the returned vector are
// undefined.
OZZ_INLINE SimdFloat4 Length2Sqr(_SimdFloat4 _v);

// Computes the square length of the components x, y and z of _v, and stores it
// in the x component of the returned vector. y, z, w of the returned vector are
// undefined.
OZZ_INLINE SimdFloat4 Length3Sqr(_SimdFloat4 _v);

// Computes the square length of the components x, y, z and w of _v, and stores
// it in the x component of the returned vector. y, z, w of the returned vector
// undefined.
OZZ_INLINE SimdFloat4 Length4Sqr(_SimdFloat4 _v);

// Returns the normalized vector of the components x and y of _v, and stores
// it in the x and y components of the returned vector. z and w of the returned
// vector are the same as their respective components in _v.
OZZ_INLINE SimdFloat4 Normalize2(_SimdFloat4 _v);

// Returns the normalized vector of the components x, y and z of _v, and stores
// it in the x, y and z components of the returned vector. w of the returned
// vector is the same as its respective component in _v.
OZZ_INLINE SimdFloat4 Normalize3(_SimdFloat4 _v);

// Returns the normalized vector _v.
OZZ_INLINE SimdFloat4 Normalize4(_SimdFloat4 _v);

// Returns the estimated normalized vector of the components x and y of _v, and
// stores it in the x and y components of the returned vector. z and w of the
// returned vector are the same as their respective components in _v.
OZZ_INLINE SimdFloat4 NormalizeEst2(_SimdFloat4 _v);

// Returns the estimated normalized vector of the components x, y and z of _v,
// and stores it in the x, y and z components of the returned vector. w of the
// returned vector is the same as its respective component in _v.
OZZ_INLINE SimdFloat4 NormalizeEst3(_SimdFloat4 _v);

// Returns the estimated normalized vector _v.
OZZ_INLINE SimdFloat4 NormalizeEst4(_SimdFloat4 _v);

// Tests if the components x and y of _v forms a normalized vector.
// Returns the result in the x component of the returned vector. y, z and w are
// set to 0.
OZZ_INLINE SimdInt4 IsNormalized2(_SimdFloat4 _v);

// Tests if the components x, y and z of _v forms a normalized vector.
// Returns the result in the x component of the returned vector. y, z and w are
// set to 0.
OZZ_INLINE SimdInt4 IsNormalized3(_SimdFloat4 _v);

// Tests if the _v is a normalized vector.
// Returns the result in the x component of the returned vector. y, z and w are
// set to 0.
OZZ_INLINE SimdInt4 IsNormalized4(_SimdFloat4 _v);

// Tests if the components x and y of _v forms a normalized vector.
// Uses the estimated normalization coefficient, that matches estimated math
// functions (RecpEst, MormalizeEst...).
// Returns the result in the x component of the returned vector. y, z and w are
// set to 0.
OZZ_INLINE SimdInt4 IsNormalizedEst2(_SimdFloat4 _v);

// Tests if the components x, y and z of _v forms a normalized vector.
// Uses the estimated normalization coefficient, that matches estimated math
// functions (RecpEst, MormalizeEst...).
// Returns the result in the x component of the returned vector. y, z and w are
// set to 0.
OZZ_INLINE SimdInt4 IsNormalizedEst3(_SimdFloat4 _v);

// Tests if the _v is a normalized vector.
// Uses the estimated normalization coefficient, that matches estimated math
// functions (RecpEst, MormalizeEst...).
// Returns the result in the x component of the returned vector. y, z and w are
// set to 0.
OZZ_INLINE SimdInt4 IsNormalizedEst4(_SimdFloat4 _v);

// Returns the normalized vector of the components x and y of _v if it is
// normalizable, otherwise returns _safe. z and w of the returned vector are
// the same as their respective components in _v.
OZZ_INLINE SimdFloat4 NormalizeSafe2(_SimdFloat4 _v, _SimdFloat4 _safe);

// Returns the normalized vector of the components x, y, z and w of _v if it is
// normalizable, otherwise returns _safe. w of the returned vector is the same
// as its respective components in _v.
OZZ_INLINE SimdFloat4 NormalizeSafe3(_SimdFloat4 _v, _SimdFloat4 _safe);

// Returns the normalized vector _v if it is normalizable, otherwise returns
// _safe.
OZZ_INLINE SimdFloat4 NormalizeSafe4(_SimdFloat4 _v, _SimdFloat4 _safe);

// Returns the estimated normalized vector of the components x and y of _v if it
// is normalizable, otherwise returns _safe. z and w of the returned vector are
// the same as their respective components in _v.
OZZ_INLINE SimdFloat4 NormalizeSafeEst2(_SimdFloat4 _v, _SimdFloat4 _safe);

// Returns the estimated normalized vector of the components x, y, z and w of _v
// if it is normalizable, otherwise returns _safe. w of the returned vector is
// the same as its respective components in _v.
OZZ_INLINE SimdFloat4 NormalizeSafeEst3(_SimdFloat4 _v, _SimdFloat4 _safe);

// Returns the estimated normalized vector _v if it is normalizable, otherwise
// returns _safe.
OZZ_INLINE SimdFloat4 NormalizeSafeEst4(_SimdFloat4 _v, _SimdFloat4 _safe);

// Computes the per element linear interpolation of _a and _b, where _alpha is
// not bound to range [0,1].
OZZ_INLINE SimdFloat4 Lerp(_SimdFloat4 _a, _SimdFloat4 _b, _SimdFloat4 _alpha);

// Computes the per element cosine of _v.
OZZ_INLINE SimdFloat4 Cos(_SimdFloat4 _v);

// Computes the cosine of the x component of _v and stores it in the x
// component of the returned vector. y, z and w of the returned vector are the
// same as their respective components in _v.
OZZ_INLINE SimdFloat4 CosX(_SimdFloat4 _v);

// Computes the per element arccosine of _v.
OZZ_INLINE SimdFloat4 ACos(_SimdFloat4 _v);

// Computes the arccosine of the x component of _v and stores it in the x
// component of the returned vector. y, z and w of the returned vector are the
// same as their respective components in _v.
OZZ_INLINE SimdFloat4 ACosX(_SimdFloat4 _v);

// Computes the per element sines of _v.
OZZ_INLINE SimdFloat4 Sin(_SimdFloat4 _v);

// Computes the sines of the x component of _v and stores it in the x
// component of the returned vector. y, z and w of the returned vector are the
// same as their respective components in _v.
OZZ_INLINE SimdFloat4 SinX(_SimdFloat4 _v);

// Computes the per element arcsine of _v.
OZZ_INLINE SimdFloat4 ASin(_SimdFloat4 _v);

// Computes the arcsine of the x component of _v and stores it in the x
// component of the returned vector. y, z and w of the returned vector are the
// same as their respective components in _v.
OZZ_INLINE SimdFloat4 ASinX(_SimdFloat4 _v);

// Computes the per element tangent of _v.
OZZ_INLINE SimdFloat4 Tan(_SimdFloat4 _v);

// Computes the tangent of the x component of _v and stores it in the x
// component of the returned vector. y, z and w of the returned vector are the
// same as their respective components in _v.
OZZ_INLINE SimdFloat4 TanX(_SimdFloat4 _v);

// Computes the per element arctangent of _v.
OZZ_INLINE SimdFloat4 ATan(_SimdFloat4 _v);

// Computes the arctangent of the x component of _v and stores it in the x
// component of the returned vector. y, z and w of the returned vector are the
// same as their respective components in _v.
OZZ_INLINE SimdFloat4 ATanX(_SimdFloat4 _v);

// Returns boolean selection of vectors _true and _false according to condition
// _b. All bits a each component of _b must have the same value (O or
// 0xffffffff) to ensure portability.
OZZ_INLINE SimdFloat4 Select(_SimdInt4 _b, _SimdFloat4 _true,
                             _SimdFloat4 _false);

// Per element "equal" comparison of _a and _b.
OZZ_INLINE SimdInt4 CmpEq(_SimdFloat4 _a, _SimdFloat4 _b);

// Per element "not equal" comparison of _a and _b.
OZZ_INLINE SimdInt4 CmpNe(_SimdFloat4 _a, _SimdFloat4 _b);

// Per element "less than" comparison of _a and _b.
OZZ_INLINE SimdInt4 CmpLt(_SimdFloat4 _a, _SimdFloat4 _b);

// Per element "less than or equal" comparison of _a and _b.
OZZ_INLINE SimdInt4 CmpLe(_SimdFloat4 _a, _SimdFloat4 _b);

// Per element "greater than" comparison of _a and _b.
OZZ_INLINE SimdInt4 CmpGt(_SimdFloat4 _a, _SimdFloat4 _b);

// Per element "greater than or equal" comparison of _a and _b.
OZZ_INLINE SimdInt4 CmpGe(_SimdFloat4 _a, _SimdFloat4 _b);

// Returns per element binary and operation of _a and _b.
// _v[0...127] = _a[0...127] & _b[0...127]
OZZ_INLINE SimdFloat4 And(_SimdFloat4 _a, _SimdFloat4 _b);

// Returns per element binary or operation of _a and _b.
// _v[0...127] = _a[0...127] | _b[0...127]
OZZ_INLINE SimdFloat4 Or(_SimdFloat4 _a, _SimdFloat4 _b);

// Returns per element binary logical xor operation of _a and _b.
// _v[0...127] = _a[0...127] ^ _b[0...127]
OZZ_INLINE SimdFloat4 Xor(_SimdFloat4 _a, _SimdFloat4 _b);

// Returns per element binary and operation of _a and _b.
// _v[0...127] = _a[0...127] & _b[0...127]
OZZ_INLINE SimdFloat4 And(_SimdFloat4 _a, _SimdInt4 _b);

// Returns per element binary and operation of _a and ~_b.
// _v[0...127] = _a[0...127] & ~_b[0...127]
OZZ_INLINE SimdFloat4 AndNot(_SimdFloat4 _a, _SimdInt4 _b);

// Returns per element binary or operation of _a and _b.
// _v[0...127] = _a[0...127] | _b[0...127]
OZZ_INLINE SimdFloat4 Or(_SimdFloat4 _a, _SimdInt4 _b);

// Returns per element binary logical xor operation of _a and _b.
// _v[0...127] = _a[0...127] ^ _b[0...127]
OZZ_INLINE SimdFloat4 Xor(_SimdFloat4 _a, _SimdInt4 _b);

namespace simd_int4 {
// Returns a SimdInt4 vector with all components set to 0.
OZZ_INLINE SimdInt4 zero();

// Returns a SimdInt4 vector with all components set to 1.
OZZ_INLINE SimdInt4 one();

// Returns a SimdInt4 vector with the x component set to 1 and all the others
// to 0.
OZZ_INLINE SimdInt4 x_axis();

// Returns a SimdInt4 vector with the y component set to 1 and all the others
// to 0.
OZZ_INLINE SimdInt4 y_axis();

// Returns a SimdInt4 vector with the z component set to 1 and all the others
// to 0.
OZZ_INLINE SimdInt4 z_axis();

// Returns a SimdInt4 vector with the w component set to 1 and all the others
// to 0.
OZZ_INLINE SimdInt4 w_axis();

// Returns a SimdInt4 vector with all components set to true (0xffffffff).
OZZ_INLINE SimdInt4 all_true();

// Returns a SimdInt4 vector with all components set to false (0).
OZZ_INLINE SimdInt4 all_false();

// Returns a SimdInt4 vector with sign bits set to 1.
OZZ_INLINE SimdInt4 mask_sign();

// Returns a SimdInt4 vector with all bits set to 1 except sign.
OZZ_INLINE SimdInt4 mask_not_sign();

// Returns a SimdInt4 vector with sign bits of x, y and z components set to 1.
OZZ_INLINE SimdInt4 mask_sign_xyz();

// Returns a SimdInt4 vector with sign bits of w component set to 1.
OZZ_INLINE SimdInt4 mask_sign_w();

// Returns a SimdInt4 vector with all bits set to 1.
OZZ_INLINE SimdInt4 mask_ffff();

// Returns a SimdInt4 vector with all bits set to 0.
OZZ_INLINE SimdInt4 mask_0000();

// Returns a SimdInt4 vector with all the bits of the x, y, z components set to
// 1, while z is set to 0.
OZZ_INLINE SimdInt4 mask_fff0();

// Returns a SimdInt4 vector with all the bits of the x component set to 1,
// while the others are set to 0.
OZZ_INLINE SimdInt4 mask_f000();

// Returns a SimdInt4 vector with all the bits of the y component set to 1,
// while the others are set to 0.
OZZ_INLINE SimdInt4 mask_0f00();

// Returns a SimdInt4 vector with all the bits of the z component set to 1,
// while the others are set to 0.
OZZ_INLINE SimdInt4 mask_00f0();

// Returns a SimdInt4 vector with all the bits of the w component set to 1,
// while the others are set to 0.
OZZ_INLINE SimdInt4 mask_000f();

// Loads _x, _y, _z, _w to the returned vector.
// r.x = _x
// r.y = _y
// r.z = _z
// r.w = _w
OZZ_INLINE SimdInt4 Load(int _x, int _y, int _z, int _w);

// Loads _x, _y, _z, _w to the returned vector using the following conversion
// rule.
// r.x = _x ? 0xffffffff:0
// r.y = _y ? 0xffffffff:0
// r.z = _z ? 0xffffffff:0
// r.w = _w ? 0xffffffff:0
OZZ_INLINE SimdInt4 Load(bool _x, bool _y, bool _z, bool _w);

// Loads _x to the x component of the returned vector using the following
// conversion rule, and sets y, z and w to 0.
// r.x = _x ? 0xffffffff:0
// r.y = 0
// r.z = 0
// r.w = 0
OZZ_INLINE SimdInt4 LoadX(bool _x);

// Loads _x to the all the components of the returned vector using the following
// conversion rule.
// r.x = _x ? 0xffffffff:0
// r.y = _x ? 0xffffffff:0
// r.z = _x ? 0xffffffff:0
// r.w = _x ? 0xffffffff:0
OZZ_INLINE SimdInt4 Load1(bool _x);

// Loads the 4 values of _f to the returned vector.
// _i must be aligned to 16 bytes.
// r.x = _i[0]
// r.y = _i[1]
// r.z = _i[2]
// r.w = _i[3]
OZZ_INLINE SimdInt4 LoadPtr(const int* _i);

// Loads _i[0] to the x component of the returned vector, and sets y, z and w
// to 0.
// _i must be aligned to 16 bytes.
// r.x = _i[0]
// r.y = 0
// r.z = 0
// r.w = 0
OZZ_INLINE SimdInt4 LoadXPtr(const int* _i);

// Loads _i[0] to all the components of the returned vector.
// _i must be aligned to 16 bytes.
// r.x = _i[0]
// r.y = _i[0]
// r.z = _i[0]
// r.w = _i[0]
OZZ_INLINE SimdInt4 Load1Ptr(const int* _i);

// Loads the 2 first value of _i to the x and y components of the returned
// vector. The remaining components are set to 0.
// _f must be aligned to 4 bytes.
// r.x = _i[0]
// r.y = _i[1]
// r.z = 0
// r.w = 0
OZZ_INLINE SimdInt4 Load2Ptr(const int* _i);

// Loads the 3 first value of _i to the x, y and z components of the returned
// vector. The remaining components are set to 0.
// _f must be aligned to 16 bytes.
// r.x = _i[0]
// r.y = _i[1]
// r.z = _i[2]
// r.w = 0
OZZ_INLINE SimdInt4 Load3Ptr(const int* _i);

// Loads the 4 values of _f to the returned vector.
// _i must be aligned to 16 bytes.
// r.x = _i[0]
// r.y = _i[1]
// r.z = _i[2]
// r.w = _i[3]
OZZ_INLINE SimdInt4 LoadPtrU(const int* _i);

// Loads _i[0] to the x component of the returned vector, and sets y, z and w
// to 0.
// _f must be aligned to 4 bytes.
// r.x = _i[0]
// r.y = 0
// r.z = 0
// r.w = 0
OZZ_INLINE SimdInt4 LoadXPtrU(const int* _i);

// Loads the 4 values of _i to the returned vector.
// _i must be aligned to 4 bytes.
// r.x = _i[0]
// r.y = _i[0]
// r.z = _i[0]
// r.w = _i[0]
OZZ_INLINE SimdInt4 Load1PtrU(const int* _i);

// Loads the 2 first value of _i to the x and y components of the returned
// vector. The remaining components are set to 0.
// _f must be aligned to 4 bytes.
// r.x = _i[0]
// r.y = _i[1]
// r.z = 0
// r.w = 0
OZZ_INLINE SimdInt4 Load2PtrU(const int* _i);

// Loads the 3 first value of _i to the x, y and z components of the returned
// vector. The remaining components are set to 0.
// _f must be aligned to 4 bytes.
// r.x = _i[0]
// r.y = _i[1]
// r.z = _i[2]
// r.w = 0
OZZ_INLINE SimdInt4 Load3PtrU(const int* _i);

// Convert from float to integer by rounding the nearest value.
OZZ_INLINE SimdInt4 FromFloatRound(_SimdFloat4 _f);

// Convert from float to integer by truncating.
OZZ_INLINE SimdInt4 FromFloatTrunc(_SimdFloat4 _f);
}  // namespace simd_int4

// Returns the x component of _v as an integer.
OZZ_INLINE int GetX(_SimdInt4 _v);

// Returns the y component of _v as a integer.
OZZ_INLINE int GetY(_SimdInt4 _v);

// Returns the z component of _v as a integer.
OZZ_INLINE int GetZ(_SimdInt4 _v);

// Returns the w component of _v as a integer.
OZZ_INLINE int GetW(_SimdInt4 _v);

// Returns _v with the x component set to x component of _i.
OZZ_INLINE SimdInt4 SetX(_SimdInt4 _v, _SimdInt4 _i);

// Returns _v with the y component set to x component of _i.
OZZ_INLINE SimdInt4 SetY(_SimdInt4 _v, _SimdInt4 _i);

// Returns _v with the z component set to x component of _i.
OZZ_INLINE SimdInt4 SetZ(_SimdInt4 _v, _SimdInt4 _i);

// Returns _v with the w component set to x component of _i.
OZZ_INLINE SimdInt4 SetW(_SimdInt4 _v, _SimdInt4 _i);

// Returns _v with the _ith component set to _i.
// _i must be in range [0,3]
OZZ_INLINE SimdInt4 SetI(_SimdInt4 _v, _SimdInt4 _i, int _ith);

// Stores the 4 components of _v to the four first integers of _i.
// _i must be aligned to 16 bytes.
// _i[0] = _v.x
// _i[1] = _v.y
// _i[2] = _v.z
// _i[3] = _v.w
OZZ_INLINE void StorePtr(_SimdInt4 _v, int* _i);

// Stores the x component of _v to the first integers of _i.
// _i must be aligned to 16 bytes.
// _i[0] = _v.x
OZZ_INLINE void Store1Ptr(_SimdInt4 _v, int* _i);

// Stores x and y components of _v to the two first integers of _i.
// _i must be aligned to 16 bytes.
// _i[0] = _v.x
// _i[1] = _v.y
OZZ_INLINE void Store2Ptr(_SimdInt4 _v, int* _i);

// Stores x, y and z components of _v to the three first integers of _i.
// _i must be aligned to 16 bytes.
// _i[0] = _v.x
// _i[1] = _v.y
// _i[2] = _v.z
OZZ_INLINE void Store3Ptr(_SimdInt4 _v, int* _i);

// Stores the 4 components of _v to the four first integers of _i.
// _i must be aligned to 4 bytes.
// _i[0] = _v.x
// _i[1] = _v.y
// _i[2] = _v.z
// _i[3] = _v.w
OZZ_INLINE void StorePtrU(_SimdInt4 _v, int* _i);

// Stores the x component of _v to the first float of _i.
// _i must be aligned to 4 bytes.
// _i[0] = _v.x
OZZ_INLINE void Store1PtrU(_SimdInt4 _v, int* _i);

// Stores x and y components of _v to the two first integers of _i.
// _i must be aligned to 4 bytes.
// _i[0] = _v.x
// _i[1] = _v.y
OZZ_INLINE void Store2PtrU(_SimdInt4 _v, int* _i);

// Stores x, y and z components of _v to the three first integers of _i.
// _i must be aligned to 4 bytes.
// _i[0] = _v.x
// _i[1] = _v.y
// _i[2] = _v.z
OZZ_INLINE void Store3PtrU(_SimdInt4 _v, int* _i);

// Replicates x of _a to all the components of the returned vector.
OZZ_INLINE SimdInt4 SplatX(_SimdInt4 _v);

// Replicates y of _a to all the components of the returned vector.
OZZ_INLINE SimdInt4 SplatY(_SimdInt4 _v);

// Replicates z of _a to all the components of the returned vector.
OZZ_INLINE SimdInt4 SplatZ(_SimdInt4 _v);

// Replicates w of _a to all the components of the returned vector.
OZZ_INLINE SimdInt4 SplatW(_SimdInt4 _v);

// Swizzle x, y, z and w components based on compile time arguments _X, _Y, _Z
// and _W. Arguments can vary from 0 (x), to 3 (w).
template <size_t _X, size_t _Y, size_t _Z, size_t _W>
OZZ_INLINE SimdInt4 Swizzle(_SimdInt4 _v);

// Creates a 4-bit mask from the most significant bits of each component of _v.
// i := sign(a3)<<3 | sign(a2)<<2 | sign(a1)<<1 | sign(a0)
OZZ_INLINE int MoveMask(_SimdInt4 _v);

// Returns true if all the components of _v are not 0.
OZZ_INLINE bool AreAllTrue(_SimdInt4 _v);

// Returns true if x, y and z components of _v are not 0.
OZZ_INLINE bool AreAllTrue3(_SimdInt4 _v);

// Returns true if x and y components of _v are not 0.
OZZ_INLINE bool AreAllTrue2(_SimdInt4 _v);

// Returns true if x component of _v is not 0.
OZZ_INLINE bool AreAllTrue1(_SimdInt4 _v);

// Returns true if all the components of _v are 0.
OZZ_INLINE bool AreAllFalse(_SimdInt4 _v);

// Returns true if x, y and z components of _v are 0.
OZZ_INLINE bool AreAllFalse3(_SimdInt4 _v);

// Returns true if x and y components of _v are 0.
OZZ_INLINE bool AreAllFalse2(_SimdInt4 _v);

// Returns true if x component of _v is 0.
OZZ_INLINE bool AreAllFalse1(_SimdInt4 _v);

// Computes the (horizontal) addition of x and y components of _v. The result is
// stored in the x component of the returned value. y, z, w of the returned
// vector are the same as their respective components in _v.
// r.x = _a.x + _a.y
// r.y = _a.y
// r.z = _a.z
// r.w = _a.w
OZZ_INLINE SimdInt4 HAdd2(_SimdInt4 _v);

// Computes the (horizontal) addition of x, y and z components of _v. The result
// is stored in the x component of the returned value. y, z, w of the returned
// vector are the same as their respective components in _v.
// r.x = _a.x + _a.y + _a.z
// r.y = _a.y
// r.z = _a.z
// r.w = _a.w
OZZ_INLINE SimdInt4 HAdd3(_SimdInt4 _v);

// Computes the (horizontal) addition of x and y components of _v. The result is
// stored in the x component of the returned value. y, z, w of the returned
// vector are the same as their respective components in _v.
// r.x = _a.x + _a.y + _a.z + _a.w
// r.y = _a.y
// r.z = _a.z
// r.w = _a.w
OZZ_INLINE SimdInt4 HAdd4(_SimdInt4 _v);

// Returns the per element absolute value of _v.
OZZ_INLINE SimdInt4 Abs(_SimdInt4 _v);

// Returns the sign bit of _v.
OZZ_INLINE SimdInt4 Sign(_SimdInt4 _v);

// Returns the per component minimum of _a and _b.
OZZ_INLINE SimdInt4 Min(_SimdInt4 _a, _SimdInt4 _b);

// Returns the per component maximum of _a and _b.
OZZ_INLINE SimdInt4 Max(_SimdInt4 _a, _SimdInt4 _b);

// Returns the per component minimum of _v and 0.
OZZ_INLINE SimdInt4 Min0(_SimdInt4 _v);

// Returns the per component maximum of _v and 0.
OZZ_INLINE SimdInt4 Max0(_SimdInt4 _v);

// Clamps each element of _x between _a and _b.
// Result is unknown if _a is not less or equal to _b.
OZZ_INLINE SimdInt4 Clamp(_SimdInt4 _a, _SimdInt4 _v, _SimdInt4 _b);

// Returns boolean selection of vectors _true and _false according to consition
// _b. All bits a each component of _b must have the same value (O or
// 0xffffffff) to ensure portability.
OZZ_INLINE SimdInt4 Select(_SimdInt4 _b, _SimdInt4 _true, _SimdInt4 _false);

// Returns per element binary and operation of _a and _b.
// _v[0...127] = _a[0...127] & _b[0...127]
OZZ_INLINE SimdInt4 And(_SimdInt4 _a, _SimdInt4 _b);

// Returns per element binary and operation of _a and ~_b.
// _v[0...127] = _a[0...127] & ~_b[0...127]
OZZ_INLINE SimdInt4 AndNot(_SimdInt4 _a, _SimdInt4 _b);

// Returns per element binary or operation of _a and _b.
// _v[0...127] = _a[0...127] | _b[0...127]
OZZ_INLINE SimdInt4 Or(_SimdInt4 _a, _SimdInt4 _b);

// Returns per element binary logical xor operation of _a and _b.
// _v[0...127] = _a[0...127] ^ _b[0...127]
OZZ_INLINE SimdInt4 Xor(_SimdInt4 _a, _SimdInt4 _b);

// Returns per element binary complement of _v.
// _v[0...127] = ~_b[0...127]
OZZ_INLINE SimdInt4 Not(_SimdInt4 _v);

// Shifts the 4 signed or unsigned 32-bit integers in a left by count _bits
// while shifting in zeros.
OZZ_INLINE SimdInt4 ShiftL(_SimdInt4 _v, int _bits);

// Shifts the 4 signed 32-bit integers in a right by count bits while shifting
// in the sign bit.
OZZ_INLINE SimdInt4 ShiftR(_SimdInt4 _v, int _bits);

// Shifts the 4 signed or unsigned 32-bit integers in a right by count bits
// while shifting in zeros.
OZZ_INLINE SimdInt4 ShiftRu(_SimdInt4 _v, int _bits);

// Per element "equal" comparison of _a and _b.
OZZ_INLINE SimdInt4 CmpEq(_SimdInt4 _a, _SimdInt4 _b);

// Per element "not equal" comparison of _a and _b.
OZZ_INLINE SimdInt4 CmpNe(_SimdInt4 _a, _SimdInt4 _b);

// Per element "less than" comparison of _a and _b.
OZZ_INLINE SimdInt4 CmpLt(_SimdInt4 _a, _SimdInt4 _b);

// Per element "less than or equal" comparison of _a and _b.
OZZ_INLINE SimdInt4 CmpLe(_SimdInt4 _a, _SimdInt4 _b);

// Per element "greater than" comparison of _a and _b.
OZZ_INLINE SimdInt4 CmpGt(_SimdInt4 _a, _SimdInt4 _b);

// Per element "greater than or equal" comparison of _a and _b.
OZZ_INLINE SimdInt4 CmpGe(_SimdInt4 _a, _SimdInt4 _b);

// Declare the 4x4 matrix type. Uses the column major convention where the
// matrix-times-vector is written v'=Mv:
// [ m.cols[0].x m.cols[1].x m.cols[2].x m.cols[3].x ]   {v.x}
// | m.cols[0].y m.cols[1].y m.cols[2].y m.cols[3].y | * {v.y}
// | m.cols[0].z m.cols[1].y m.cols[2].y m.cols[3].y |   {v.z}
// [ m.cols[0].w m.cols[1].w m.cols[2].w m.cols[3].w ]   {v.1}
struct Float4x4 {
  // Matrix columns.
  SimdFloat4 cols[4];

  // Returns the identity matrix.
  static OZZ_INLINE Float4x4 identity();

  // Returns a translation matrix.
  // _v.w is ignored.
  static OZZ_INLINE Float4x4 Translation(_SimdFloat4 _v);

  // Returns a translation matrix.
  static OZZ_INLINE Float4x4 Translation(const Float3& _v) {
    return Translation(simd_float4::Load(_v));
  }

  // Returns a scaling matrix that scales along _v.
  // _v.w is ignored.
  static OZZ_INLINE Float4x4 Scaling(_SimdFloat4 _v);

  // Returns a scaling matrix that scales along _v.
  static OZZ_INLINE Float4x4 Scaling(const Float3& _v) {
    return Scaling(simd_float4::Load3PtrU(&_v.x));
  }

  // Returns the rotation matrix built from Euler angles defined by x, y and z
  // components of _v. Euler angles are ordered Heading, Elevation and Bank, or
  // Yaw, Pitch and Roll. _v.w is ignored.
  static OZZ_INLINE Float4x4 FromEuler(_SimdFloat4 _v);

  // Returns the rotation matrix built from Euler angles defined by x, y and z
  // components of _v. Euler angles are ordered Heading, Elevation and Bank, or
  // Yaw, Pitch and Roll.
  static OZZ_INLINE Float4x4 FromEuler(const Float3& _v) {
    return FromEuler(simd_float4::Load3PtrU(&_v.x));
  }

  // Returns the rotation matrix built from axis defined by _axis.xyz and
  // _angle.x
  static OZZ_INLINE Float4x4 FromAxisAngle(_SimdFloat4 _axis,
                                           _SimdFloat4 _angle);

  // Returns the rotation matrix built from axis defined by _axis.xyz and
  // _angle
  static OZZ_INLINE Float4x4 FromAxisAngle(const Float3& _axis, float _angle) {
    return FromAxisAngle(simd_float4::Load3PtrU(&_axis.x),
                         simd_float4::Load1(_angle));
  }

  // Returns the rotation matrix built from quaternion defined by x, y, z and w
  // components of _v.
  static OZZ_INLINE Float4x4 FromQuaternion(_SimdFloat4 _v);

  // Returns the rotation matrix built from quaternion _q.
  static OZZ_INLINE Float4x4 FromQuaternion(const Quaternion& _q) {
    return FromQuaternion(simd_float4::LoadPtrU(&_q.x));
  }

  // Returns the affine transformation matrix built from split translation,
  // rotation (quaternion) and scale.
  static OZZ_INLINE Float4x4 FromAffine(_SimdFloat4 _translation,
                                        _SimdFloat4 _quaternion,
                                        _SimdFloat4 _scale);
  static OZZ_INLINE Float4x4 FromAffine(const Float3 _translation,
                                        const Quaternion& _quaternion,
                                        const Float3 _scale) {
    return FromAffine(simd_float4::Load3PtrU(&_translation.x),
                      simd_float4::LoadPtrU(&_quaternion.x),
                      simd_float4::Load3PtrU(&_scale.x));
  }
  static OZZ_INLINE Float4x4 FromAffine(const Transform& _transform) {
    return FromAffine(simd_float4::Load3PtrU(&_transform.translation.x),
                      simd_float4::LoadPtrU(&_transform.rotation.x),
                      simd_float4::Load3PtrU(&_transform.scale.x));
  }
};

// Returns the transpose of matrix _m.
OZZ_INLINE Float4x4 Transpose(const Float4x4& _m);

// Returns the inverse of matrix _m.
// If _invertible is not nullptr, its x component will be set to true if matrix
// is invertible. If _invertible is nullptr, then an assert is triggered in case
// the matrix isn't invertible.
OZZ_INLINE Float4x4 Invert(const Float4x4& _m, SimdInt4* _invertible = nullptr);

// Translates matrix _m along the axis defined by _v components.
// _v.w is ignored.
OZZ_INLINE Float4x4 Translate(const Float4x4& _m, _SimdFloat4 _v);

// Scales matrix _m along each axis with x, y, z components of _v.
// _v.w is ignored.
OZZ_INLINE Float4x4 Scale(const Float4x4& _m, _SimdFloat4 _v);

// Multiply each column of matrix _m with vector _v.
OZZ_INLINE Float4x4 ColumnMultiply(const Float4x4& _m, _SimdFloat4 _v);

// Tests if each 3 column of upper 3x3 matrix of _m is a normal matrix.
// Returns the result in the x, y and z component of the returned vector. w is
// set to 0.
OZZ_INLINE SimdInt4 IsNormalized(const Float4x4& _m);

// Tests if each 3 column of upper 3x3 matrix of _m is a normal matrix.
// Uses the estimated tolerance
// Returns the result in the x, y and z component of the returned vector. w is
// set to 0.
OZZ_INLINE SimdInt4 IsNormalizedEst(const Float4x4& _m);

// Tests if the upper 3x3 matrix of _m is an orthogonal matrix.
// A matrix that contains a reflexion cannot be considered orthogonal.
// Returns the result in the x component of the returned vector. y, z and w are
// set to 0.
OZZ_INLINE SimdInt4 IsOrthogonal(const Float4x4& _m);

// Returns the quaternion that represent the rotation of matrix _m.
// _m must be normalized and orthogonal.
// the return quaternion is normalized.
OZZ_INLINE SimdFloat4 ToQuaternion(const Float4x4& _m);

// Decompose a general 3D transformation matrix _m into its scalar, rotational
// and translational components.
// Returns false if it was not possible to decompose the matrix. This would be
// because more than 1 of the 3 first column of _m are scaled to 0.
OZZ_INLINE bool ToAffine(const Float4x4& _m, SimdFloat4* _translation,
                         SimdFloat4* _quaternion, SimdFloat4* _scale);
OZZ_INLINE bool ToAffine(const Float4x4& _m, Float3* _translation,
                         Quaternion* _quaternion, Float3* _scale) {
  SimdFloat4 translation, quaternion, scale;
  if (ToAffine(_m, &translation, &quaternion, &scale)) {
    Store3PtrU(translation, &_translation->x);
    StorePtrU(quaternion, &_quaternion->x);
    Store3PtrU(scale, &_scale->x);
    return true;
  }
  return false;
}
OZZ_INLINE bool ToAffine(const Float4x4& _m, Transform* _transform) {
  SimdFloat4 translation, quaternion, scale;
  if (ToAffine(_m, &translation, &quaternion, &scale)) {
    Store3PtrU(translation, &_transform->translation.x);
    StorePtrU(quaternion, &_transform->rotation.x);
    Store3PtrU(scale, &_transform->scale.x);
    return true;
  }
  return false;
}

// Computes the transformation of a Float4x4 matrix and a point _p.
// This is equivalent to multiplying a matrix by a SimdFloat4 with a w component
// of 1.
OZZ_INLINE ozz::math::SimdFloat4 TransformPoint(const ozz::math::Float4x4& _m,
                                                ozz::math::_SimdFloat4 _v);

// Computes the transformation of a Float4x4 matrix and a vector _v.
// This is equivalent to multiplying a matrix by a SimdFloat4 with a w component
// of 0.
OZZ_INLINE ozz::math::SimdFloat4 TransformVector(const ozz::math::Float4x4& _m,
                                                 ozz::math::_SimdFloat4 _v);

// Computes the multiplication of matrix Float4x4 and vector _v.
OZZ_INLINE ozz::math::SimdFloat4 operator*(const ozz::math::Float4x4& _m,
                                           ozz::math::_SimdFloat4 _v);

// Computes the multiplication of two matrices _a and _b.
OZZ_INLINE ozz::math::Float4x4 operator*(const ozz::math::Float4x4& _a,
                                         const ozz::math::Float4x4& _b);

// Computes the per element addition of two matrices _a and _b.
OZZ_INLINE ozz::math::Float4x4 operator+(const ozz::math::Float4x4& _a,
                                         const ozz::math::Float4x4& _b);

// Computes the per element subtraction of two matrices _a and _b.
OZZ_INLINE ozz::math::Float4x4 operator-(const ozz::math::Float4x4& _a,
                                         const ozz::math::Float4x4& _b);
}  // namespace math
}  // namespace ozz

#if !defined(OZZ_DISABLE_SSE_NATIVE_OPERATORS)
// Returns per element addition of _a and _b.
OZZ_INLINE ozz::math::SimdFloat4 operator+(ozz::math::_SimdFloat4 _a,
                                           ozz::math::_SimdFloat4 _b);

// Returns per element subtraction of _a and _b.
OZZ_INLINE ozz::math::SimdFloat4 operator-(ozz::math::_SimdFloat4 _a,
                                           ozz::math::_SimdFloat4 _b);

// Returns per element negation of _v.
OZZ_INLINE ozz::math::SimdFloat4 operator-(ozz::math::_SimdFloat4 _v);

// Returns per element multiplication of _a and _b.
OZZ_INLINE ozz::math::SimdFloat4 operator*(ozz::math::_SimdFloat4 _a,
                                           ozz::math::_SimdFloat4 _b);

// Returns per element division of _a and _b.
OZZ_INLINE ozz::math::SimdFloat4 operator/(ozz::math::_SimdFloat4 _a,
                                           ozz::math::_SimdFloat4 _b);
#endif  // !defined(OZZ_DISABLE_SSE_NATIVE_OPERATORS)

// Implement format conversions.
namespace ozz {
namespace math {
// Converts from a float to a half.
OZZ_INLINE uint16_t FloatToHalf(float _f);

// Converts from a half to a float.
OZZ_INLINE float HalfToFloat(uint16_t _h);

// Converts from a float to a half.
OZZ_INLINE SimdInt4 FloatToHalf(_SimdFloat4 _f);

// Converts from a half to a float.
OZZ_INLINE SimdFloat4 HalfToFloat(_SimdInt4 _h);
}  // namespace math
}  // namespace ozz

#if defined(OZZ_SIMD_SSEx)
/**** start inlining ozz/base/maths/internal/simd_math_sse-inl.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_MATHS_INTERNAL_SIMD_MATH_SSE_INL_H_
#define OZZ_OZZ_BASE_MATHS_INTERNAL_SIMD_MATH_SSE_INL_H_

// SIMD SSE2+ implementation, based on scalar floats.

#include <stdint.h>

#include <cassert>

// Temporarly needed while trigonometric functions aren't implemented.
#include <cmath>

/**** skipping file: ozz/base/maths/math_constant.h ****/

namespace ozz {
namespace math {

namespace simd_float4 {

// Internal macros.
// Unused components of the result vector are replicated from the first input
// argument.

#ifdef OZZ_SIMD_AVX
#define OZZ_SHUFFLE_PS1(_v, _m) _mm_permute_ps(_v, _m)
#else  // OZZ_SIMD_AVX
#define OZZ_SHUFFLE_PS1(_v, _m) _mm_shuffle_ps(_v, _v, _m)
#endif  // OZZ_SIMD_AVX

#define OZZ_SSE_SPLAT_F(_v, _i) OZZ_SHUFFLE_PS1(_v, _MM_SHUFFLE(_i, _i, _i, _i))

#define OZZ_SSE_SPLAT_I(_v, _i) \
  _mm_shuffle_epi32(_v, _MM_SHUFFLE(_i, _i, _i, _i))

// _v.x + _v.y, _v.y, _v.z, _v.w
#define OZZ_SSE_HADD2_F(_v) _mm_add_ss(_v, OZZ_SSE_SPLAT_F(_v, 1))

// _v.x + _v.y + _v.z, _v.y, _v.z, _v.w
#define OZZ_SSE_HADD3_F(_v) \
  _mm_add_ss(_mm_add_ss(_v, OZZ_SSE_SPLAT_F(_v, 2)), OZZ_SSE_SPLAT_F(_v, 1))

// _v.x + _v.y + _v.z + _v.w, ?, ?, ?
#define OZZ_SSE_HADD4_F(_v, _r)                                    \
  do {                                                             \
    const __m128 haddxyzw = _mm_add_ps(_v, _mm_movehl_ps(_v, _v)); \
    _r = _mm_add_ss(haddxyzw, OZZ_SSE_SPLAT_F(haddxyzw, 1));       \
  } while (void(0), 0)

// dot2, ?, ?, ?
#define OZZ_SSE_DOT2_F(_a, _b, _r)               \
  do {                                           \
    const __m128 ab = _mm_mul_ps(_a, _b);        \
    _r = _mm_add_ss(ab, OZZ_SSE_SPLAT_F(ab, 1)); \
                                                 \
  } while (void(0), 0)

#ifdef OZZ_SIMD_SSE4_1
// dot3, ?, ?, ?
#define OZZ_SSE_DOT3_F(_a, _b, _r) \
  do {                             \
    _r = _mm_dp_ps(_a, _b, 0x7f);  \
  } while (void(0), 0)

// dot4, ?, ?, ?
#define OZZ_SSE_DOT4_F(_a, _b, _r) \
  do {                             \
    _r = _mm_dp_ps(_a, _b, 0xff);  \
  } while (void(0), 0)

#else  // OZZ_SIMD_SSE4_1
// dot3, ?, ?, ?
#define OZZ_SSE_DOT3_F(_a, _b, _r)        \
  do {                                    \
    const __m128 ab = _mm_mul_ps(_a, _b); \
    _r = OZZ_SSE_HADD3_F(ab);             \
  } while (void(0), 0)

// dot4, ?, ?, ?
#define OZZ_SSE_DOT4_F(_a, _b, _r)        \
  do {                                    \
    const __m128 ab = _mm_mul_ps(_a, _b); \
    OZZ_SSE_HADD4_F(ab, _r);              \
  } while (void(0), 0)
#endif  // OZZ_SIMD_SSE4_1

// FMA operations
#ifdef OZZ_SIMD_FMA
#define OZZ_MADD(_a, _b, _c) _mm_fmadd_ps(_a, _b, _c)
#define OZZ_MSUB(_a, _b, _c) _mm_fmsub_ps(_a, _b, _c)
#define OZZ_NMADD(_a, _b, _c) _mm_fnmadd_ps(_a, _b, _c)
#define OZZ_NMSUB(_a, _b, _c) _mm_fnmsub_ps(_a, _b, _c)
#define OZZ_MADDX(_a, _b, _c) _mm_fmadd_ss(_a, _b, _c)
#define OZZ_MSUBX(_a, _b, _c) _mm_fmsub_ss(_a, _b, _c)
#define OZZ_NMADDX(_a, _b, _c) _mm_fnmadd_ss(_a, _b, _c)
#define OZZ_NMSUBX(_a, _b, _c) _mm_fnmsub_ss(_a, _b, _c)
#else  //  OZZ_SIMD_FMA
#define OZZ_MADD(_a, _b, _c) _mm_add_ps(_mm_mul_ps(_a, _b), _c)
#define OZZ_MSUB(_a, _b, _c) _mm_sub_ps(_mm_mul_ps(_a, _b), _c)
#define OZZ_NMADD(_a, _b, _c) _mm_sub_ps(_c, _mm_mul_ps(_a, _b))
#define OZZ_NMSUB(_a, _b, _c) (-_mm_add_ps(_mm_mul_ps(_a, _b), _c))
#define OZZ_MADDX(_a, _b, _c) _mm_add_ss(_mm_mul_ss(_a, _b), _c)
#define OZZ_MSUBX(_a, _b, _c) _mm_sub_ss(_mm_mul_ss(_a, _b), _c)
#define OZZ_NMADDX(_a, _b, _c) _mm_sub_ss(_c, _mm_mul_ss(_a, _b))
#define OZZ_NMSUBX(_a, _b, _c) (-_mm_add_ss(_mm_mul_ss(_a, _b), _c))
#endif  // OZZ_SIMD_FMA

OZZ_INLINE SimdFloat4 DivX(_SimdFloat4 _a, _SimdFloat4 _b) {
  return _mm_div_ss(_a, _b);
}

#ifdef OZZ_SIMD_SSE4_1

#define OZZ_SSE_SELECT_F(_b, _true, _false) \
  _mm_blendv_ps(_false, _true, _mm_castsi128_ps(_b))

#define OZZ_SSE_SELECT_I(_b, _true, _false) _mm_blendv_epi8(_false, _true, _b)

#else  // OZZ_SIMD_SSE4_1

#define OZZ_SSE_SELECT_F(_b, _true, _false)          \
  _mm_or_ps(_mm_and_ps(_true, _mm_castsi128_ps(_b)), \
            _mm_andnot_ps(_mm_castsi128_ps(_b), _false))

#define OZZ_SSE_SELECT_I(_b, _true, _false) \
  _mm_or_si128(_mm_and_si128(_true, _b), _mm_andnot_si128(_b, _false))

#endif  // OZZ_SIMD_SSE4_1

OZZ_INLINE SimdFloat4 zero() { return _mm_setzero_ps(); }

OZZ_INLINE SimdFloat4 one() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_castsi128_ps(
      _mm_srli_epi32(_mm_slli_epi32(_mm_cmpeq_epi32(zero, zero), 25), 2));
}

OZZ_INLINE SimdFloat4 x_axis() {
  const __m128i zero = _mm_setzero_si128();
  const __m128i one =
      _mm_srli_epi32(_mm_slli_epi32(_mm_cmpeq_epi32(zero, zero), 25), 2);
  return _mm_castsi128_ps(_mm_srli_si128(one, 12));
}

OZZ_INLINE SimdFloat4 y_axis() {
  const __m128i zero = _mm_setzero_si128();
  const __m128i one =
      _mm_srli_epi32(_mm_slli_epi32(_mm_cmpeq_epi32(zero, zero), 25), 2);
  return _mm_castsi128_ps(_mm_slli_si128(_mm_srli_si128(one, 12), 4));
}

OZZ_INLINE SimdFloat4 z_axis() {
  const __m128i zero = _mm_setzero_si128();
  const __m128i one =
      _mm_srli_epi32(_mm_slli_epi32(_mm_cmpeq_epi32(zero, zero), 25), 2);
  return _mm_castsi128_ps(_mm_slli_si128(_mm_srli_si128(one, 12), 8));
}

OZZ_INLINE SimdFloat4 w_axis() {
  const __m128i zero = _mm_setzero_si128();
  const __m128i one =
      _mm_srli_epi32(_mm_slli_epi32(_mm_cmpeq_epi32(zero, zero), 25), 2);
  return _mm_castsi128_ps(_mm_slli_si128(one, 12));
}

OZZ_INLINE SimdFloat4 Load(float _x, float _y, float _z, float _w) {
  return _mm_set_ps(_w, _z, _y, _x);
}

OZZ_INLINE SimdFloat4 LoadX(float _x) { return _mm_set_ss(_x); }

OZZ_INLINE SimdFloat4 Load1(float _x) { return _mm_set_ps1(_x); }

OZZ_INLINE SimdFloat4 LoadPtr(const float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0xf) && "Invalid alignment");
  return _mm_load_ps(_f);
}

OZZ_INLINE SimdFloat4 LoadPtrU(const float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  return _mm_loadu_ps(_f);
}

OZZ_INLINE SimdFloat4 LoadXPtrU(const float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  return _mm_load_ss(_f);
}

OZZ_INLINE SimdFloat4 Load1PtrU(const float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  return _mm_load_ps1(_f);
}

OZZ_INLINE SimdFloat4 Load2PtrU(const float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  return _mm_unpacklo_ps(_mm_load_ss(_f + 0), _mm_load_ss(_f + 1));
}

OZZ_INLINE SimdFloat4 Load3PtrU(const float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  return _mm_movelh_ps(
      _mm_unpacklo_ps(_mm_load_ss(_f + 0), _mm_load_ss(_f + 1)),
      _mm_load_ss(_f + 2));
}

OZZ_INLINE SimdFloat4 FromInt(_SimdInt4 _i) { return _mm_cvtepi32_ps(_i); }
}  // namespace simd_float4

OZZ_INLINE float GetX(_SimdFloat4 _v) { return _mm_cvtss_f32(_v); }

OZZ_INLINE float GetY(_SimdFloat4 _v) {
  return _mm_cvtss_f32(OZZ_SSE_SPLAT_F(_v, 1));
}

OZZ_INLINE float GetZ(_SimdFloat4 _v) {
  return _mm_cvtss_f32(_mm_movehl_ps(_v, _v));
}

OZZ_INLINE float GetW(_SimdFloat4 _v) {
  return _mm_cvtss_f32(OZZ_SSE_SPLAT_F(_v, 3));
}

OZZ_INLINE SimdFloat4 SetX(_SimdFloat4 _v, _SimdFloat4 _f) {
  return _mm_move_ss(_v, _f);
}

OZZ_INLINE SimdFloat4 SetY(_SimdFloat4 _v, _SimdFloat4 _f) {
  const __m128 xfnn = _mm_unpacklo_ps(_v, _f);
  return _mm_shuffle_ps(xfnn, _v, _MM_SHUFFLE(3, 2, 1, 0));
}

OZZ_INLINE SimdFloat4 SetZ(_SimdFloat4 _v, _SimdFloat4 _f) {
  const __m128 ffww = _mm_shuffle_ps(_f, _v, _MM_SHUFFLE(3, 3, 0, 0));
  return _mm_shuffle_ps(_v, ffww, _MM_SHUFFLE(2, 0, 1, 0));
}

OZZ_INLINE SimdFloat4 SetW(_SimdFloat4 _v, _SimdFloat4 _f) {
  const __m128 ffzz = _mm_shuffle_ps(_f, _v, _MM_SHUFFLE(2, 2, 0, 0));
  return _mm_shuffle_ps(_v, ffzz, _MM_SHUFFLE(0, 2, 1, 0));
}

OZZ_INLINE SimdFloat4 SetI(_SimdFloat4 _v, _SimdFloat4 _f, int _ith) {
  assert(_ith >= 0 && _ith <= 3 && "Invalid index, out of range.");
  union {
    SimdFloat4 ret;
    float af[4];
  } u = {_v};
  u.af[_ith] = _mm_cvtss_f32(_f);
  return u.ret;
}

OZZ_INLINE void StorePtr(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0xf) && "Invalid alignment");
  _mm_store_ps(_f, _v);
}

OZZ_INLINE void Store1Ptr(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0xf) && "Invalid alignment");
  _mm_store_ss(_f, _v);
}

OZZ_INLINE void Store2Ptr(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0xf) && "Invalid alignment");
  _mm_storel_pi(reinterpret_cast<__m64*>(_f), _v);
}

OZZ_INLINE void Store3Ptr(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0xf) && "Invalid alignment");
  _mm_storel_pi(reinterpret_cast<__m64*>(_f), _v);
  _mm_store_ss(_f + 2, _mm_movehl_ps(_v, _v));
}

OZZ_INLINE void StorePtrU(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  _mm_storeu_ps(_f, _v);
}

OZZ_INLINE void Store1PtrU(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  _mm_store_ss(_f, _v);
}

OZZ_INLINE void Store2PtrU(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  _mm_store_ss(_f + 0, _v);
  _mm_store_ss(_f + 1, OZZ_SSE_SPLAT_F(_v, 1));
}

OZZ_INLINE void Store3PtrU(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  _mm_store_ss(_f + 0, _v);
  _mm_store_ss(_f + 1, OZZ_SSE_SPLAT_F(_v, 1));
  _mm_store_ss(_f + 2, _mm_movehl_ps(_v, _v));
}

OZZ_INLINE SimdFloat4 SplatX(_SimdFloat4 _v) { return OZZ_SSE_SPLAT_F(_v, 0); }

OZZ_INLINE SimdFloat4 SplatY(_SimdFloat4 _v) { return OZZ_SSE_SPLAT_F(_v, 1); }

OZZ_INLINE SimdFloat4 SplatZ(_SimdFloat4 _v) { return OZZ_SSE_SPLAT_F(_v, 2); }

OZZ_INLINE SimdFloat4 SplatW(_SimdFloat4 _v) { return OZZ_SSE_SPLAT_F(_v, 3); }

template <size_t _X, size_t _Y, size_t _Z, size_t _W>
OZZ_INLINE SimdFloat4 Swizzle(_SimdFloat4 _v) {
  static_assert(_X <= 3 && _Y <= 3 && _Z <= 3 && _W <= 3,
                "Indices must be between 0 and 3");
  return OZZ_SHUFFLE_PS1(_v, _MM_SHUFFLE(_W, _Z, _Y, _X));
}

template <>
OZZ_INLINE SimdFloat4 Swizzle<0, 1, 2, 3>(_SimdFloat4 _v) {
  return _v;
}

template <>
OZZ_INLINE SimdFloat4 Swizzle<0, 1, 0, 1>(_SimdFloat4 _v) {
  return _mm_movelh_ps(_v, _v);
}

template <>
OZZ_INLINE SimdFloat4 Swizzle<2, 3, 2, 3>(_SimdFloat4 _v) {
  return _mm_movehl_ps(_v, _v);
}

template <>
OZZ_INLINE SimdFloat4 Swizzle<0, 0, 1, 1>(_SimdFloat4 _v) {
  return _mm_unpacklo_ps(_v, _v);
}

template <>
OZZ_INLINE SimdFloat4 Swizzle<2, 2, 3, 3>(_SimdFloat4 _v) {
  return _mm_unpackhi_ps(_v, _v);
}

OZZ_INLINE void Transpose4x1(const SimdFloat4 _in[4], SimdFloat4 _out[1]) {
  const __m128 xz = _mm_unpacklo_ps(_in[0], _in[2]);
  const __m128 yw = _mm_unpacklo_ps(_in[1], _in[3]);
  _out[0] = _mm_unpacklo_ps(xz, yw);
}

OZZ_INLINE void Transpose1x4(const SimdFloat4 _in[1], SimdFloat4 _out[4]) {
  const __m128 zwzw = _mm_movehl_ps(_in[0], _in[0]);
  const __m128 yyyy = OZZ_SSE_SPLAT_F(_in[0], 1);
  const __m128 wwww = OZZ_SSE_SPLAT_F(_in[0], 3);
  const __m128 zero = _mm_setzero_ps();
  _out[0] = _mm_move_ss(zero, _in[0]);
  _out[1] = _mm_move_ss(zero, yyyy);
  _out[2] = _mm_move_ss(zero, zwzw);
  _out[3] = _mm_move_ss(zero, wwww);
}

OZZ_INLINE void Transpose4x2(const SimdFloat4 _in[4], SimdFloat4 _out[2]) {
  const __m128 tmp0 = _mm_unpacklo_ps(_in[0], _in[2]);
  const __m128 tmp1 = _mm_unpacklo_ps(_in[1], _in[3]);
  _out[0] = _mm_unpacklo_ps(tmp0, tmp1);
  _out[1] = _mm_unpackhi_ps(tmp0, tmp1);
}

OZZ_INLINE void Transpose2x4(const SimdFloat4 _in[2], SimdFloat4 _out[4]) {
  const __m128 tmp0 = _mm_unpacklo_ps(_in[0], _in[1]);
  const __m128 tmp1 = _mm_unpackhi_ps(_in[0], _in[1]);
  const __m128 zero = _mm_setzero_ps();
  _out[0] = _mm_movelh_ps(tmp0, zero);
  _out[1] = _mm_movehl_ps(zero, tmp0);
  _out[2] = _mm_movelh_ps(tmp1, zero);
  _out[3] = _mm_movehl_ps(zero, tmp1);
}

OZZ_INLINE void Transpose4x3(const SimdFloat4 _in[4], SimdFloat4 _out[3]) {
  const __m128 tmp0 = _mm_unpacklo_ps(_in[0], _in[2]);
  const __m128 tmp1 = _mm_unpacklo_ps(_in[1], _in[3]);
  const __m128 tmp2 = _mm_unpackhi_ps(_in[0], _in[2]);
  const __m128 tmp3 = _mm_unpackhi_ps(_in[1], _in[3]);
  _out[0] = _mm_unpacklo_ps(tmp0, tmp1);
  _out[1] = _mm_unpackhi_ps(tmp0, tmp1);
  _out[2] = _mm_unpacklo_ps(tmp2, tmp3);
}

OZZ_INLINE void Transpose3x4(const SimdFloat4 _in[3], SimdFloat4 _out[4]) {
  const __m128 zero = _mm_setzero_ps();
  const __m128 temp0 = _mm_unpacklo_ps(_in[0], _in[1]);
  const __m128 temp1 = _mm_unpacklo_ps(_in[2], zero);
  const __m128 temp2 = _mm_unpackhi_ps(_in[0], _in[1]);
  const __m128 temp3 = _mm_unpackhi_ps(_in[2], zero);
  _out[0] = _mm_movelh_ps(temp0, temp1);
  _out[1] = _mm_movehl_ps(temp1, temp0);
  _out[2] = _mm_movelh_ps(temp2, temp3);
  _out[3] = _mm_movehl_ps(temp3, temp2);
}

OZZ_INLINE void Transpose4x4(const SimdFloat4 _in[4], SimdFloat4 _out[4]) {
  const __m128 tmp0 = _mm_unpacklo_ps(_in[0], _in[2]);
  const __m128 tmp1 = _mm_unpacklo_ps(_in[1], _in[3]);
  const __m128 tmp2 = _mm_unpackhi_ps(_in[0], _in[2]);
  const __m128 tmp3 = _mm_unpackhi_ps(_in[1], _in[3]);
  _out[0] = _mm_unpacklo_ps(tmp0, tmp1);
  _out[1] = _mm_unpackhi_ps(tmp0, tmp1);
  _out[2] = _mm_unpacklo_ps(tmp2, tmp3);
  _out[3] = _mm_unpackhi_ps(tmp2, tmp3);
}

OZZ_INLINE void Transpose16x16(const SimdFloat4 _in[16], SimdFloat4 _out[16]) {
  const __m128 tmp0 = _mm_unpacklo_ps(_in[0], _in[2]);
  const __m128 tmp1 = _mm_unpacklo_ps(_in[1], _in[3]);
  _out[0] = _mm_unpacklo_ps(tmp0, tmp1);
  _out[4] = _mm_unpackhi_ps(tmp0, tmp1);
  const __m128 tmp2 = _mm_unpackhi_ps(_in[0], _in[2]);
  const __m128 tmp3 = _mm_unpackhi_ps(_in[1], _in[3]);
  _out[8] = _mm_unpacklo_ps(tmp2, tmp3);
  _out[12] = _mm_unpackhi_ps(tmp2, tmp3);
  const __m128 tmp4 = _mm_unpacklo_ps(_in[4], _in[6]);
  const __m128 tmp5 = _mm_unpacklo_ps(_in[5], _in[7]);
  _out[1] = _mm_unpacklo_ps(tmp4, tmp5);
  _out[5] = _mm_unpackhi_ps(tmp4, tmp5);
  const __m128 tmp6 = _mm_unpackhi_ps(_in[4], _in[6]);
  const __m128 tmp7 = _mm_unpackhi_ps(_in[5], _in[7]);
  _out[9] = _mm_unpacklo_ps(tmp6, tmp7);
  _out[13] = _mm_unpackhi_ps(tmp6, tmp7);
  const __m128 tmp8 = _mm_unpacklo_ps(_in[8], _in[10]);
  const __m128 tmp9 = _mm_unpacklo_ps(_in[9], _in[11]);
  _out[2] = _mm_unpacklo_ps(tmp8, tmp9);
  _out[6] = _mm_unpackhi_ps(tmp8, tmp9);
  const __m128 tmp10 = _mm_unpackhi_ps(_in[8], _in[10]);
  const __m128 tmp11 = _mm_unpackhi_ps(_in[9], _in[11]);
  _out[10] = _mm_unpacklo_ps(tmp10, tmp11);
  _out[14] = _mm_unpackhi_ps(tmp10, tmp11);
  const __m128 tmp12 = _mm_unpacklo_ps(_in[12], _in[14]);
  const __m128 tmp13 = _mm_unpacklo_ps(_in[13], _in[15]);
  _out[3] = _mm_unpacklo_ps(tmp12, tmp13);
  _out[7] = _mm_unpackhi_ps(tmp12, tmp13);
  const __m128 tmp14 = _mm_unpackhi_ps(_in[12], _in[14]);
  const __m128 tmp15 = _mm_unpackhi_ps(_in[13], _in[15]);
  _out[11] = _mm_unpacklo_ps(tmp14, tmp15);
  _out[15] = _mm_unpackhi_ps(tmp14, tmp15);
}

OZZ_INLINE SimdFloat4 MAdd(_SimdFloat4 _a, _SimdFloat4 _b, _SimdFloat4 _c) {
  return OZZ_MADD(_a, _b, _c);
}

OZZ_INLINE SimdFloat4 MSub(_SimdFloat4 _a, _SimdFloat4 _b, _SimdFloat4 _c) {
  return OZZ_MSUB(_a, _b, _c);
}

OZZ_INLINE SimdFloat4 NMAdd(_SimdFloat4 _a, _SimdFloat4 _b, _SimdFloat4 _c) {
  return OZZ_NMADD(_a, _b, _c);
}

OZZ_INLINE SimdFloat4 NMSub(_SimdFloat4 _a, _SimdFloat4 _b, _SimdFloat4 _c) {
  return OZZ_NMSUB(_a, _b, _c);
}

OZZ_INLINE SimdFloat4 DivX(_SimdFloat4 _a, _SimdFloat4 _b) {
  return _mm_div_ss(_a, _b);
}

OZZ_INLINE SimdFloat4 HAdd2(_SimdFloat4 _v) { return OZZ_SSE_HADD2_F(_v); }

OZZ_INLINE SimdFloat4 HAdd3(_SimdFloat4 _v) { return OZZ_SSE_HADD3_F(_v); }

OZZ_INLINE SimdFloat4 HAdd4(_SimdFloat4 _v) {
  __m128 hadd4;
  OZZ_SSE_HADD4_F(_v, hadd4);
  return hadd4;
}

OZZ_INLINE SimdFloat4 Dot2(_SimdFloat4 _a, _SimdFloat4 _b) {
  __m128 dot2;
  OZZ_SSE_DOT2_F(_a, _b, dot2);
  return dot2;
}

OZZ_INLINE SimdFloat4 Dot3(_SimdFloat4 _a, _SimdFloat4 _b) {
  __m128 dot3;
  OZZ_SSE_DOT3_F(_a, _b, dot3);
  return dot3;
}

OZZ_INLINE SimdFloat4 Dot4(_SimdFloat4 _a, _SimdFloat4 _b) {
  __m128 dot4;
  OZZ_SSE_DOT4_F(_a, _b, dot4);
  return dot4;
}

OZZ_INLINE SimdFloat4 Cross3(_SimdFloat4 _a, _SimdFloat4 _b) {
  // Implementation with 3 shuffles only is based on:
  // https://geometrian.com/programming/tutorials/cross-product
  const __m128 shufa = OZZ_SHUFFLE_PS1(_a, _MM_SHUFFLE(3, 0, 2, 1));
  const __m128 shufb = OZZ_SHUFFLE_PS1(_b, _MM_SHUFFLE(3, 0, 2, 1));
  const __m128 shufc = OZZ_MSUB(_a, shufb, _mm_mul_ps(_b, shufa));
  return OZZ_SHUFFLE_PS1(shufc, _MM_SHUFFLE(3, 0, 2, 1));
}

OZZ_INLINE SimdFloat4 RcpEst(_SimdFloat4 _v) { return _mm_rcp_ps(_v); }

OZZ_INLINE SimdFloat4 RcpEstNR(_SimdFloat4 _v) {
  const __m128 nr = _mm_rcp_ps(_v);
  // Do one more Newton-Raphson step to improve precision.
  return OZZ_NMADD(_mm_mul_ps(nr, nr), _v, _mm_add_ps(nr, nr));
}

OZZ_INLINE SimdFloat4 RcpEstX(_SimdFloat4 _v) { return _mm_rcp_ss(_v); }

OZZ_INLINE SimdFloat4 RcpEstXNR(_SimdFloat4 _v) {
  const __m128 nr = _mm_rcp_ss(_v);
  // Do one more Newton-Raphson step to improve precision.
  return OZZ_NMADDX(_mm_mul_ss(nr, nr), _v, _mm_add_ss(nr, nr));
}

OZZ_INLINE SimdFloat4 Sqrt(_SimdFloat4 _v) { return _mm_sqrt_ps(_v); }

OZZ_INLINE SimdFloat4 SqrtX(_SimdFloat4 _v) { return _mm_sqrt_ss(_v); }

OZZ_INLINE SimdFloat4 RSqrtEst(_SimdFloat4 _v) { return _mm_rsqrt_ps(_v); }

OZZ_INLINE SimdFloat4 RSqrtEstNR(_SimdFloat4 _v) {
  const __m128 nr = _mm_rsqrt_ps(_v);
  // Do one more Newton-Raphson step to improve precision.
  return _mm_mul_ps(_mm_mul_ps(_mm_set_ps1(.5f), nr),
                    OZZ_NMADD(_mm_mul_ps(_v, nr), nr, _mm_set_ps1(3.f)));
}

OZZ_INLINE SimdFloat4 RSqrtEstX(_SimdFloat4 _v) { return _mm_rsqrt_ss(_v); }

OZZ_INLINE SimdFloat4 RSqrtEstXNR(_SimdFloat4 _v) {
  const __m128 nr = _mm_rsqrt_ss(_v);
  // Do one more Newton-Raphson step to improve precision.
  return _mm_mul_ss(_mm_mul_ss(_mm_set_ps1(.5f), nr),
                    OZZ_NMADDX(_mm_mul_ss(_v, nr), nr, _mm_set_ps1(3.f)));
}

OZZ_INLINE SimdFloat4 Abs(_SimdFloat4 _v) {
  const __m128i zero = _mm_setzero_si128();
  return _mm_and_ps(
      _mm_castsi128_ps(_mm_srli_epi32(_mm_cmpeq_epi32(zero, zero), 1)), _v);
}

OZZ_INLINE SimdInt4 Sign(_SimdFloat4 _v) {
  return _mm_slli_epi32(_mm_srli_epi32(_mm_castps_si128(_v), 31), 31);
}

OZZ_INLINE SimdFloat4 Length2(_SimdFloat4 _v) {
  __m128 sq_len;
  OZZ_SSE_DOT2_F(_v, _v, sq_len);
  return _mm_sqrt_ss(sq_len);
}

OZZ_INLINE SimdFloat4 Length3(_SimdFloat4 _v) {
  __m128 sq_len;
  OZZ_SSE_DOT3_F(_v, _v, sq_len);
  return _mm_sqrt_ss(sq_len);
}

OZZ_INLINE SimdFloat4 Length4(_SimdFloat4 _v) {
  __m128 sq_len;
  OZZ_SSE_DOT4_F(_v, _v, sq_len);
  return _mm_sqrt_ss(sq_len);
}

OZZ_INLINE SimdFloat4 Length2Sqr(_SimdFloat4 _v) {
  __m128 sq_len;
  OZZ_SSE_DOT2_F(_v, _v, sq_len);
  return sq_len;
}

OZZ_INLINE SimdFloat4 Length3Sqr(_SimdFloat4 _v) {
  __m128 sq_len;
  OZZ_SSE_DOT3_F(_v, _v, sq_len);
  return sq_len;
}

OZZ_INLINE SimdFloat4 Length4Sqr(_SimdFloat4 _v) {
  __m128 sq_len;
  OZZ_SSE_DOT4_F(_v, _v, sq_len);
  return sq_len;
}

OZZ_INLINE SimdFloat4 Normalize2(_SimdFloat4 _v) {
  __m128 sq_len;
  OZZ_SSE_DOT2_F(_v, _v, sq_len);
  assert(_mm_cvtss_f32(sq_len) != 0.f && "_v is not normalizable");
  const __m128 inv_len = _mm_div_ss(simd_float4::one(), _mm_sqrt_ss(sq_len));
  const __m128 inv_lenxxxx = OZZ_SSE_SPLAT_F(inv_len, 0);
  const __m128 norm = _mm_mul_ps(_v, inv_lenxxxx);
  return _mm_movelh_ps(norm, _mm_movehl_ps(_v, _v));
}

OZZ_INLINE SimdFloat4 Normalize3(_SimdFloat4 _v) {
  __m128 sq_len;
  OZZ_SSE_DOT3_F(_v, _v, sq_len);
  assert(_mm_cvtss_f32(sq_len) != 0.f && "_v is not normalizable");
  const __m128 inv_len = _mm_div_ss(simd_float4::one(), _mm_sqrt_ss(sq_len));
  const __m128 vwxyz = OZZ_SHUFFLE_PS1(_v, _MM_SHUFFLE(0, 1, 2, 3));
  const __m128 inv_lenxxxx = OZZ_SSE_SPLAT_F(inv_len, 0);
  const __m128 normwxyz = _mm_move_ss(_mm_mul_ps(vwxyz, inv_lenxxxx), vwxyz);
  return OZZ_SHUFFLE_PS1(normwxyz, _MM_SHUFFLE(0, 1, 2, 3));
}

OZZ_INLINE SimdFloat4 Normalize4(_SimdFloat4 _v) {
  __m128 sq_len;
  OZZ_SSE_DOT4_F(_v, _v, sq_len);
  assert(_mm_cvtss_f32(sq_len) != 0.f && "_v is not normalizable");
  const __m128 inv_len = _mm_div_ss(simd_float4::one(), _mm_sqrt_ss(sq_len));
  const __m128 inv_lenxxxx = OZZ_SSE_SPLAT_F(inv_len, 0);
  return _mm_mul_ps(_v, inv_lenxxxx);
}

OZZ_INLINE SimdFloat4 NormalizeEst2(_SimdFloat4 _v) {
  __m128 sq_len;
  OZZ_SSE_DOT2_F(_v, _v, sq_len);
  assert(_mm_cvtss_f32(sq_len) != 0.f && "_v is not normalizable");
  const __m128 inv_len = _mm_rsqrt_ss(sq_len);
  const __m128 inv_lenxxxx = OZZ_SSE_SPLAT_F(inv_len, 0);
  const __m128 norm = _mm_mul_ps(_v, inv_lenxxxx);
  return _mm_movelh_ps(norm, _mm_movehl_ps(_v, _v));
}

OZZ_INLINE SimdFloat4 NormalizeEst3(_SimdFloat4 _v) {
  __m128 sq_len;
  OZZ_SSE_DOT3_F(_v, _v, sq_len);
  assert(_mm_cvtss_f32(sq_len) != 0.f && "_v is not normalizable");
  const __m128 inv_len = _mm_rsqrt_ss(sq_len);
  const __m128 vwxyz = OZZ_SHUFFLE_PS1(_v, _MM_SHUFFLE(0, 1, 2, 3));
  const __m128 inv_lenxxxx = OZZ_SSE_SPLAT_F(inv_len, 0);
  const __m128 normwxyz = _mm_move_ss(_mm_mul_ps(vwxyz, inv_lenxxxx), vwxyz);
  return OZZ_SHUFFLE_PS1(normwxyz, _MM_SHUFFLE(0, 1, 2, 3));
}

OZZ_INLINE SimdFloat4 NormalizeEst4(_SimdFloat4 _v) {
  __m128 sq_len;
  OZZ_SSE_DOT4_F(_v, _v, sq_len);
  assert(_mm_cvtss_f32(sq_len) != 0.f && "_v is not normalizable");
  const __m128 inv_len = _mm_rsqrt_ss(sq_len);
  const __m128 inv_lenxxxx = OZZ_SSE_SPLAT_F(inv_len, 0);
  return _mm_mul_ps(_v, inv_lenxxxx);
}

OZZ_INLINE SimdInt4 IsNormalized2(_SimdFloat4 _v) {
  const __m128 max = _mm_set_ss(1.f + kNormalizationToleranceSq);
  const __m128 min = _mm_set_ss(1.f - kNormalizationToleranceSq);
  __m128 dot;
  OZZ_SSE_DOT2_F(_v, _v, dot);
  __m128 dotx000 = _mm_move_ss(_mm_setzero_ps(), dot);
  return _mm_castps_si128(
      _mm_and_ps(_mm_cmplt_ss(dotx000, max), _mm_cmpgt_ss(dotx000, min)));
}

OZZ_INLINE SimdInt4 IsNormalized3(_SimdFloat4 _v) {
  const __m128 max = _mm_set_ss(1.f + kNormalizationToleranceSq);
  const __m128 min = _mm_set_ss(1.f - kNormalizationToleranceSq);
  __m128 dot;
  OZZ_SSE_DOT3_F(_v, _v, dot);
  __m128 dotx000 = _mm_move_ss(_mm_setzero_ps(), dot);
  return _mm_castps_si128(
      _mm_and_ps(_mm_cmplt_ss(dotx000, max), _mm_cmpgt_ss(dotx000, min)));
}

OZZ_INLINE SimdInt4 IsNormalized4(_SimdFloat4 _v) {
  const __m128 max = _mm_set_ss(1.f + kNormalizationToleranceSq);
  const __m128 min = _mm_set_ss(1.f - kNormalizationToleranceSq);
  __m128 dot;
  OZZ_SSE_DOT4_F(_v, _v, dot);
  __m128 dotx000 = _mm_move_ss(_mm_setzero_ps(), dot);
  return _mm_castps_si128(
      _mm_and_ps(_mm_cmplt_ss(dotx000, max), _mm_cmpgt_ss(dotx000, min)));
}

OZZ_INLINE SimdInt4 IsNormalizedEst2(_SimdFloat4 _v) {
  const __m128 max = _mm_set_ss(1.f + kNormalizationToleranceEstSq);
  const __m128 min = _mm_set_ss(1.f - kNormalizationToleranceEstSq);
  __m128 dot;
  OZZ_SSE_DOT2_F(_v, _v, dot);
  __m128 dotx000 = _mm_move_ss(_mm_setzero_ps(), dot);
  return _mm_castps_si128(
      _mm_and_ps(_mm_cmplt_ss(dotx000, max), _mm_cmpgt_ss(dotx000, min)));
}

OZZ_INLINE SimdInt4 IsNormalizedEst3(_SimdFloat4 _v) {
  const __m128 max = _mm_set_ss(1.f + kNormalizationToleranceEstSq);
  const __m128 min = _mm_set_ss(1.f - kNormalizationToleranceEstSq);
  __m128 dot;
  OZZ_SSE_DOT3_F(_v, _v, dot);
  __m128 dotx000 = _mm_move_ss(_mm_setzero_ps(), dot);
  return _mm_castps_si128(
      _mm_and_ps(_mm_cmplt_ss(dotx000, max), _mm_cmpgt_ss(dotx000, min)));
}

OZZ_INLINE SimdInt4 IsNormalizedEst4(_SimdFloat4 _v) {
  const __m128 max = _mm_set_ss(1.f + kNormalizationToleranceEstSq);
  const __m128 min = _mm_set_ss(1.f - kNormalizationToleranceEstSq);
  __m128 dot;
  OZZ_SSE_DOT4_F(_v, _v, dot);
  __m128 dotx000 = _mm_move_ss(_mm_setzero_ps(), dot);
  return _mm_castps_si128(
      _mm_and_ps(_mm_cmplt_ss(dotx000, max), _mm_cmpgt_ss(dotx000, min)));
}

OZZ_INLINE SimdFloat4 NormalizeSafe2(_SimdFloat4 _v, _SimdFloat4 _safe) {
  // assert(AreAllTrue1(IsNormalized2(_safe)) && "_safe is not normalized");
  __m128 sq_len;
  OZZ_SSE_DOT2_F(_v, _v, sq_len);
  const __m128 inv_len = _mm_div_ss(simd_float4::one(), _mm_sqrt_ss(sq_len));
  const __m128 inv_lenxxxx = OZZ_SSE_SPLAT_F(inv_len, 0);
  const __m128 norm = _mm_mul_ps(_v, inv_lenxxxx);
  const __m128i cond = _mm_castps_si128(
      _mm_cmple_ps(OZZ_SSE_SPLAT_F(sq_len, 0), _mm_setzero_ps()));
  const __m128 cfalse = _mm_movelh_ps(norm, _mm_movehl_ps(_v, _v));
  return OZZ_SSE_SELECT_F(cond, _safe, cfalse);
}

OZZ_INLINE SimdFloat4 NormalizeSafe3(_SimdFloat4 _v, _SimdFloat4 _safe) {
  // assert(AreAllTrue1(IsNormalized3(_safe)) && "_safe is not normalized");
  __m128 sq_len;
  OZZ_SSE_DOT3_F(_v, _v, sq_len);
  const __m128 inv_len = _mm_div_ss(simd_float4::one(), _mm_sqrt_ss(sq_len));
  const __m128 vwxyz = OZZ_SHUFFLE_PS1(_v, _MM_SHUFFLE(0, 1, 2, 3));
  const __m128 inv_lenxxxx = OZZ_SSE_SPLAT_F(inv_len, 0);
  const __m128 normwxyz = _mm_move_ss(_mm_mul_ps(vwxyz, inv_lenxxxx), vwxyz);
  const __m128i cond = _mm_castps_si128(
      _mm_cmple_ps(OZZ_SSE_SPLAT_F(sq_len, 0), _mm_setzero_ps()));
  const __m128 cfalse = OZZ_SHUFFLE_PS1(normwxyz, _MM_SHUFFLE(0, 1, 2, 3));
  return OZZ_SSE_SELECT_F(cond, _safe, cfalse);
}

OZZ_INLINE SimdFloat4 NormalizeSafe4(_SimdFloat4 _v, _SimdFloat4 _safe) {
  // assert(AreAllTrue1(IsNormalized4(_safe)) && "_safe is not normalized");
  __m128 sq_len;
  OZZ_SSE_DOT4_F(_v, _v, sq_len);
  const __m128 inv_len = _mm_div_ss(simd_float4::one(), _mm_sqrt_ss(sq_len));
  const __m128 inv_lenxxxx = OZZ_SSE_SPLAT_F(inv_len, 0);
  const __m128i cond = _mm_castps_si128(
      _mm_cmple_ps(OZZ_SSE_SPLAT_F(sq_len, 0), _mm_setzero_ps()));
  const __m128 cfalse = _mm_mul_ps(_v, inv_lenxxxx);
  return OZZ_SSE_SELECT_F(cond, _safe, cfalse);
}

OZZ_INLINE SimdFloat4 NormalizeSafeEst2(_SimdFloat4 _v, _SimdFloat4 _safe) {
  // assert(AreAllTrue1(IsNormalizedEst2(_safe)) && "_safe is not normalized");
  __m128 sq_len;
  OZZ_SSE_DOT2_F(_v, _v, sq_len);
  const __m128 inv_len = _mm_rsqrt_ss(sq_len);
  const __m128 inv_lenxxxx = OZZ_SSE_SPLAT_F(inv_len, 0);
  const __m128 norm = _mm_mul_ps(_v, inv_lenxxxx);
  const __m128i cond = _mm_castps_si128(
      _mm_cmple_ps(OZZ_SSE_SPLAT_F(sq_len, 0), _mm_setzero_ps()));
  const __m128 cfalse = _mm_movelh_ps(norm, _mm_movehl_ps(_v, _v));
  return OZZ_SSE_SELECT_F(cond, _safe, cfalse);
}

OZZ_INLINE SimdFloat4 NormalizeSafeEst3(_SimdFloat4 _v, _SimdFloat4 _safe) {
  // assert(AreAllTrue1(IsNormalizedEst3(_safe)) && "_safe is not normalized");
  __m128 sq_len;
  OZZ_SSE_DOT3_F(_v, _v, sq_len);
  const __m128 inv_len = _mm_rsqrt_ss(sq_len);
  const __m128 vwxyz = OZZ_SHUFFLE_PS1(_v, _MM_SHUFFLE(0, 1, 2, 3));
  const __m128 inv_lenxxxx = OZZ_SSE_SPLAT_F(inv_len, 0);
  const __m128 normwxyz = _mm_move_ss(_mm_mul_ps(vwxyz, inv_lenxxxx), vwxyz);
  const __m128i cond = _mm_castps_si128(
      _mm_cmple_ps(OZZ_SSE_SPLAT_F(sq_len, 0), _mm_setzero_ps()));
  const __m128 cfalse = OZZ_SHUFFLE_PS1(normwxyz, _MM_SHUFFLE(0, 1, 2, 3));
  return OZZ_SSE_SELECT_F(cond, _safe, cfalse);
}

OZZ_INLINE SimdFloat4 NormalizeSafeEst4(_SimdFloat4 _v, _SimdFloat4 _safe) {
  // assert(AreAllTrue1(IsNormalizedEst4(_safe)) && "_safe is not normalized");
  __m128 sq_len;
  OZZ_SSE_DOT4_F(_v, _v, sq_len);
  const __m128 inv_len = _mm_rsqrt_ss(sq_len);
  const __m128 inv_lenxxxx = OZZ_SSE_SPLAT_F(inv_len, 0);
  const __m128i cond = _mm_castps_si128(
      _mm_cmple_ps(OZZ_SSE_SPLAT_F(sq_len, 0), _mm_setzero_ps()));
  const __m128 cfalse = _mm_mul_ps(_v, inv_lenxxxx);
  return OZZ_SSE_SELECT_F(cond, _safe, cfalse);
}

OZZ_INLINE SimdFloat4 Lerp(_SimdFloat4 _a, _SimdFloat4 _b, _SimdFloat4 _alpha) {
  return OZZ_MADD(_alpha, _mm_sub_ps(_b, _a), _a);
}

OZZ_INLINE SimdFloat4 Min(_SimdFloat4 _a, _SimdFloat4 _b) {
  return _mm_min_ps(_a, _b);
}

OZZ_INLINE SimdFloat4 Max(_SimdFloat4 _a, _SimdFloat4 _b) {
  return _mm_max_ps(_a, _b);
}

OZZ_INLINE SimdFloat4 Min0(_SimdFloat4 _v) {
  return _mm_min_ps(_mm_setzero_ps(), _v);
}

OZZ_INLINE SimdFloat4 Max0(_SimdFloat4 _v) {
  return _mm_max_ps(_mm_setzero_ps(), _v);
}

OZZ_INLINE SimdFloat4 Clamp(_SimdFloat4 _a, _SimdFloat4 _v, _SimdFloat4 _b) {
  return _mm_max_ps(_a, _mm_min_ps(_v, _b));
}

OZZ_INLINE SimdFloat4 Select(_SimdInt4 _b, _SimdFloat4 _true,
                             _SimdFloat4 _false) {
  return OZZ_SSE_SELECT_F(_b, _true, _false);
}

OZZ_INLINE SimdInt4 CmpEq(_SimdFloat4 _a, _SimdFloat4 _b) {
  return _mm_castps_si128(_mm_cmpeq_ps(_a, _b));
}

OZZ_INLINE SimdInt4 CmpNe(_SimdFloat4 _a, _SimdFloat4 _b) {
  return _mm_castps_si128(_mm_cmpneq_ps(_a, _b));
}

OZZ_INLINE SimdInt4 CmpLt(_SimdFloat4 _a, _SimdFloat4 _b) {
  return _mm_castps_si128(_mm_cmplt_ps(_a, _b));
}

OZZ_INLINE SimdInt4 CmpLe(_SimdFloat4 _a, _SimdFloat4 _b) {
  return _mm_castps_si128(_mm_cmple_ps(_a, _b));
}

OZZ_INLINE SimdInt4 CmpGt(_SimdFloat4 _a, _SimdFloat4 _b) {
  return _mm_castps_si128(_mm_cmpgt_ps(_a, _b));
}

OZZ_INLINE SimdInt4 CmpGe(_SimdFloat4 _a, _SimdFloat4 _b) {
  return _mm_castps_si128(_mm_cmpge_ps(_a, _b));
}

OZZ_INLINE SimdFloat4 And(_SimdFloat4 _a, _SimdFloat4 _b) {
  return _mm_and_ps(_a, _b);
}

OZZ_INLINE SimdFloat4 Or(_SimdFloat4 _a, _SimdFloat4 _b) {
  return _mm_or_ps(_a, _b);
}

OZZ_INLINE SimdFloat4 Xor(_SimdFloat4 _a, _SimdFloat4 _b) {
  return _mm_xor_ps(_a, _b);
}

OZZ_INLINE SimdFloat4 And(_SimdFloat4 _a, _SimdInt4 _b) {
  return _mm_and_ps(_a, _mm_castsi128_ps(_b));
}

OZZ_INLINE SimdFloat4 AndNot(_SimdFloat4 _a, _SimdInt4 _b) {
  return _mm_andnot_ps(_mm_castsi128_ps(_b), _a);
}

OZZ_INLINE SimdFloat4 Or(_SimdFloat4 _a, _SimdInt4 _b) {
  return _mm_or_ps(_a, _mm_castsi128_ps(_b));
}

OZZ_INLINE SimdFloat4 Xor(_SimdFloat4 _a, _SimdInt4 _b) {
  return _mm_xor_ps(_a, _mm_castsi128_ps(_b));
}

OZZ_INLINE SimdFloat4 Cos(_SimdFloat4 _v) {
  return _mm_set_ps(std::cos(GetW(_v)), std::cos(GetZ(_v)), std::cos(GetY(_v)),
                    std::cos(GetX(_v)));
}

OZZ_INLINE SimdFloat4 CosX(_SimdFloat4 _v) {
  return _mm_move_ss(_v, _mm_set_ps1(std::cos(GetX(_v))));
}

OZZ_INLINE SimdFloat4 ACos(_SimdFloat4 _v) {
  return _mm_set_ps(std::acos(GetW(_v)), std::acos(GetZ(_v)),
                    std::acos(GetY(_v)), std::acos(GetX(_v)));
}

OZZ_INLINE SimdFloat4 ACosX(_SimdFloat4 _v) {
  return _mm_move_ss(_v, _mm_set_ps1(std::acos(GetX(_v))));
}

OZZ_INLINE SimdFloat4 Sin(_SimdFloat4 _v) {
  return _mm_set_ps(std::sin(GetW(_v)), std::sin(GetZ(_v)), std::sin(GetY(_v)),
                    std::sin(GetX(_v)));
}

OZZ_INLINE SimdFloat4 SinX(_SimdFloat4 _v) {
  return _mm_move_ss(_v, _mm_set_ps1(std::sin(GetX(_v))));
}

OZZ_INLINE SimdFloat4 ASin(_SimdFloat4 _v) {
  return _mm_set_ps(std::asin(GetW(_v)), std::asin(GetZ(_v)),
                    std::asin(GetY(_v)), std::asin(GetX(_v)));
}

OZZ_INLINE SimdFloat4 ASinX(_SimdFloat4 _v) {
  return _mm_move_ss(_v, _mm_set_ps1(std::asin(GetX(_v))));
}

OZZ_INLINE SimdFloat4 Tan(_SimdFloat4 _v) {
  return _mm_set_ps(std::tan(GetW(_v)), std::tan(GetZ(_v)), std::tan(GetY(_v)),
                    std::tan(GetX(_v)));
}

OZZ_INLINE SimdFloat4 TanX(_SimdFloat4 _v) {
  return _mm_move_ss(_v, _mm_set_ps1(std::tan(GetX(_v))));
}

OZZ_INLINE SimdFloat4 ATan(_SimdFloat4 _v) {
  return _mm_set_ps(std::atan(GetW(_v)), std::atan(GetZ(_v)),
                    std::atan(GetY(_v)), std::atan(GetX(_v)));
}

OZZ_INLINE SimdFloat4 ATanX(_SimdFloat4 _v) {
  return _mm_move_ss(_v, _mm_set_ps1(std::atan(GetX(_v))));
}

namespace simd_int4 {

OZZ_INLINE SimdInt4 zero() { return _mm_setzero_si128(); }

OZZ_INLINE SimdInt4 one() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_sub_epi32(zero, _mm_cmpeq_epi32(zero, zero));
}

OZZ_INLINE SimdInt4 x_axis() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_srli_si128(_mm_sub_epi32(zero, _mm_cmpeq_epi32(zero, zero)), 12);
}

OZZ_INLINE SimdInt4 y_axis() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_slli_si128(
      _mm_srli_si128(_mm_sub_epi32(zero, _mm_cmpeq_epi32(zero, zero)), 12), 4);
}

OZZ_INLINE SimdInt4 z_axis() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_slli_si128(
      _mm_srli_si128(_mm_sub_epi32(zero, _mm_cmpeq_epi32(zero, zero)), 12), 8);
}

OZZ_INLINE SimdInt4 w_axis() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_slli_si128(_mm_sub_epi32(zero, _mm_cmpeq_epi32(zero, zero)), 12);
}

OZZ_INLINE SimdInt4 all_true() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_cmpeq_epi32(zero, zero);
}

OZZ_INLINE SimdInt4 all_false() { return _mm_setzero_si128(); }

OZZ_INLINE SimdInt4 mask_sign() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_slli_epi32(_mm_cmpeq_epi32(zero, zero), 31);
}

OZZ_INLINE SimdInt4 mask_sign_xyz() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_srli_si128(_mm_slli_epi32(_mm_cmpeq_epi32(zero, zero), 31), 4);
}

OZZ_INLINE SimdInt4 mask_sign_w() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_slli_si128(_mm_slli_epi32(_mm_cmpeq_epi32(zero, zero), 31), 12);
}

OZZ_INLINE SimdInt4 mask_not_sign() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_srli_epi32(_mm_cmpeq_epi32(zero, zero), 1);
}

OZZ_INLINE SimdInt4 mask_ffff() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_cmpeq_epi32(zero, zero);
}
OZZ_INLINE SimdInt4 mask_0000() { return _mm_setzero_si128(); }

OZZ_INLINE SimdInt4 mask_fff0() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_srli_si128(_mm_cmpeq_epi32(zero, zero), 4);
}

OZZ_INLINE SimdInt4 mask_f000() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_srli_si128(_mm_cmpeq_epi32(zero, zero), 12);
}

OZZ_INLINE SimdInt4 mask_0f00() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_srli_si128(_mm_slli_si128(_mm_cmpeq_epi32(zero, zero), 12), 8);
}

OZZ_INLINE SimdInt4 mask_00f0() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_srli_si128(_mm_slli_si128(_mm_cmpeq_epi32(zero, zero), 12), 4);
}

OZZ_INLINE SimdInt4 mask_000f() {
  const __m128i zero = _mm_setzero_si128();
  return _mm_slli_si128(_mm_cmpeq_epi32(zero, zero), 12);
}

OZZ_INLINE SimdInt4 Load(int _x, int _y, int _z, int _w) {
  return _mm_set_epi32(_w, _z, _y, _x);
}

OZZ_INLINE SimdInt4 LoadX(int _x) { return _mm_set_epi32(0, 0, 0, _x); }

OZZ_INLINE SimdInt4 Load1(int _x) { return _mm_set1_epi32(_x); }

OZZ_INLINE SimdInt4 Load(bool _x, bool _y, bool _z, bool _w) {
  return _mm_sub_epi32(_mm_setzero_si128(), _mm_set_epi32(_w, _z, _y, _x));
}

OZZ_INLINE SimdInt4 LoadX(bool _x) {
  return _mm_sub_epi32(_mm_setzero_si128(), _mm_set_epi32(0, 0, 0, _x));
}

OZZ_INLINE SimdInt4 Load1(bool _x) {
  return _mm_sub_epi32(_mm_setzero_si128(), _mm_set1_epi32(_x));
}

OZZ_INLINE SimdInt4 LoadPtr(const int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  return _mm_load_si128(reinterpret_cast<const __m128i*>(_i));
}

OZZ_INLINE SimdInt4 LoadXPtr(const int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  return _mm_cvtsi32_si128(*_i);
}

OZZ_INLINE SimdInt4 Load1Ptr(const int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  return _mm_shuffle_epi32(
      _mm_loadl_epi64(reinterpret_cast<const __m128i*>(_i)),
      _MM_SHUFFLE(0, 0, 0, 0));
}

OZZ_INLINE SimdInt4 Load2Ptr(const int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  return _mm_loadl_epi64(reinterpret_cast<const __m128i*>(_i));
}

OZZ_INLINE SimdInt4 Load3Ptr(const int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  return _mm_set_epi32(0, _i[2], _i[1], _i[0]);
}

OZZ_INLINE SimdInt4 LoadPtrU(const int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  return _mm_loadu_si128(reinterpret_cast<const __m128i*>(_i));
}

OZZ_INLINE SimdInt4 LoadXPtrU(const int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  return _mm_cvtsi32_si128(*_i);
}

OZZ_INLINE SimdInt4 Load1PtrU(const int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  return _mm_set1_epi32(*_i);
}

OZZ_INLINE SimdInt4 Load2PtrU(const int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  return _mm_set_epi32(0, 0, _i[1], _i[0]);
}

OZZ_INLINE SimdInt4 Load3PtrU(const int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  return _mm_set_epi32(0, _i[2], _i[1], _i[0]);
}

OZZ_INLINE SimdInt4 FromFloatRound(_SimdFloat4 _f) {
  return _mm_cvtps_epi32(_f);
}

OZZ_INLINE SimdInt4 FromFloatTrunc(_SimdFloat4 _f) {
  return _mm_cvttps_epi32(_f);
}
}  // namespace simd_int4

OZZ_INLINE int GetX(_SimdInt4 _v) { return _mm_cvtsi128_si32(_v); }

OZZ_INLINE int GetY(_SimdInt4 _v) {
  return _mm_cvtsi128_si32(OZZ_SSE_SPLAT_I(_v, 1));
}

OZZ_INLINE int GetZ(_SimdInt4 _v) {
  return _mm_cvtsi128_si32(_mm_unpackhi_epi32(_v, _v));
}

OZZ_INLINE int GetW(_SimdInt4 _v) {
  return _mm_cvtsi128_si32(OZZ_SSE_SPLAT_I(_v, 3));
}

OZZ_INLINE SimdInt4 SetX(_SimdInt4 _v, _SimdInt4 _i) {
  return _mm_castps_si128(
      _mm_move_ss(_mm_castsi128_ps(_v), _mm_castsi128_ps(_i)));
}

OZZ_INLINE SimdInt4 SetY(_SimdInt4 _v, _SimdInt4 _i) {
  const __m128 xfnn = _mm_castsi128_ps(_mm_unpacklo_epi32(_v, _i));
  return _mm_castps_si128(
      _mm_shuffle_ps(xfnn, _mm_castsi128_ps(_v), _MM_SHUFFLE(3, 2, 1, 0)));
}

OZZ_INLINE SimdInt4 SetZ(_SimdInt4 _v, _SimdInt4 _i) {
  const __m128 ffww = _mm_shuffle_ps(_mm_castsi128_ps(_i), _mm_castsi128_ps(_v),
                                     _MM_SHUFFLE(3, 3, 0, 0));
  return _mm_castps_si128(
      _mm_shuffle_ps(_mm_castsi128_ps(_v), ffww, _MM_SHUFFLE(2, 0, 1, 0)));
}

OZZ_INLINE SimdInt4 SetW(_SimdInt4 _v, _SimdInt4 _i) {
  const __m128 ffzz = _mm_shuffle_ps(_mm_castsi128_ps(_i), _mm_castsi128_ps(_v),
                                     _MM_SHUFFLE(2, 2, 0, 0));
  return _mm_castps_si128(
      _mm_shuffle_ps(_mm_castsi128_ps(_v), ffzz, _MM_SHUFFLE(0, 2, 1, 0)));
}

OZZ_INLINE SimdInt4 SetI(_SimdInt4 _v, _SimdInt4 _i, int _ith) {
  assert(_ith >= 0 && _ith <= 3 && "Invalid index, out of range.");
  union {
    SimdInt4 ret;
    int af[4];
  } u = {_v};
  u.af[_ith] = GetX(_i);
  return u.ret;
}

OZZ_INLINE void StorePtr(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  _mm_store_si128(reinterpret_cast<__m128i*>(_i), _v);
}

OZZ_INLINE void Store1Ptr(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  *_i = _mm_cvtsi128_si32(_v);
}

OZZ_INLINE void Store2Ptr(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  _i[0] = _mm_cvtsi128_si32(_v);
  _i[1] = _mm_cvtsi128_si32(OZZ_SSE_SPLAT_I(_v, 1));
}

OZZ_INLINE void Store3Ptr(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  _i[0] = _mm_cvtsi128_si32(_v);
  _i[1] = _mm_cvtsi128_si32(OZZ_SSE_SPLAT_I(_v, 1));
  _i[2] = _mm_cvtsi128_si32(_mm_unpackhi_epi32(_v, _v));
}

OZZ_INLINE void StorePtrU(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  _mm_storeu_si128(reinterpret_cast<__m128i*>(_i), _v);
}

OZZ_INLINE void Store1PtrU(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  *_i = _mm_cvtsi128_si32(_v);
}

OZZ_INLINE void Store2PtrU(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  _i[0] = _mm_cvtsi128_si32(_v);
  _i[1] = _mm_cvtsi128_si32(OZZ_SSE_SPLAT_I(_v, 1));
}

OZZ_INLINE void Store3PtrU(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  _i[0] = _mm_cvtsi128_si32(_v);
  _i[1] = _mm_cvtsi128_si32(OZZ_SSE_SPLAT_I(_v, 1));
  _i[2] = _mm_cvtsi128_si32(_mm_unpackhi_epi32(_v, _v));
}

OZZ_INLINE SimdInt4 SplatX(_SimdInt4 _a) { return OZZ_SSE_SPLAT_I(_a, 0); }

OZZ_INLINE SimdInt4 SplatY(_SimdInt4 _a) { return OZZ_SSE_SPLAT_I(_a, 1); }

OZZ_INLINE SimdInt4 SplatZ(_SimdInt4 _a) { return OZZ_SSE_SPLAT_I(_a, 2); }

OZZ_INLINE SimdInt4 SplatW(_SimdInt4 _a) { return OZZ_SSE_SPLAT_I(_a, 3); }

template <size_t _X, size_t _Y, size_t _Z, size_t _W>
OZZ_INLINE SimdInt4 Swizzle(_SimdInt4 _v) {
  static_assert(_X <= 3 && _Y <= 3 && _Z <= 3 && _W <= 3,
                "Indices must be between 0 and 3");
  return _mm_shuffle_epi32(_v, _MM_SHUFFLE(_W, _Z, _Y, _X));
}

template <>
OZZ_INLINE SimdInt4 Swizzle<0, 1, 2, 3>(_SimdInt4 _v) {
  return _v;
}

OZZ_INLINE int MoveMask(_SimdInt4 _v) {
  return _mm_movemask_ps(_mm_castsi128_ps(_v));
}

OZZ_INLINE bool AreAllTrue(_SimdInt4 _v) {
  return _mm_movemask_ps(_mm_castsi128_ps(_v)) == 0xf;
}

OZZ_INLINE bool AreAllTrue3(_SimdInt4 _v) {
  return (_mm_movemask_ps(_mm_castsi128_ps(_v)) & 0x7) == 0x7;
}

OZZ_INLINE bool AreAllTrue2(_SimdInt4 _v) {
  return (_mm_movemask_ps(_mm_castsi128_ps(_v)) & 0x3) == 0x3;
}

OZZ_INLINE bool AreAllTrue1(_SimdInt4 _v) {
  return (_mm_movemask_ps(_mm_castsi128_ps(_v)) & 0x1) == 0x1;
}

OZZ_INLINE bool AreAllFalse(_SimdInt4 _v) {
  return _mm_movemask_ps(_mm_castsi128_ps(_v)) == 0;
}

OZZ_INLINE bool AreAllFalse3(_SimdInt4 _v) {
  return (_mm_movemask_ps(_mm_castsi128_ps(_v)) & 0x7) == 0;
}

OZZ_INLINE bool AreAllFalse2(_SimdInt4 _v) {
  return (_mm_movemask_ps(_mm_castsi128_ps(_v)) & 0x3) == 0;
}

OZZ_INLINE bool AreAllFalse1(_SimdInt4 _v) {
  return (_mm_movemask_ps(_mm_castsi128_ps(_v)) & 0x1) == 0;
}

OZZ_INLINE SimdInt4 HAdd2(_SimdInt4 _v) {
  const __m128i hadd = _mm_add_epi32(_v, OZZ_SSE_SPLAT_I(_v, 1));
  return _mm_castps_si128(
      _mm_move_ss(_mm_castsi128_ps(_v), _mm_castsi128_ps(hadd)));
}

OZZ_INLINE SimdInt4 HAdd3(_SimdInt4 _v) {
  const __m128i hadd = _mm_add_epi32(_mm_add_epi32(_v, OZZ_SSE_SPLAT_I(_v, 1)),
                                     _mm_unpackhi_epi32(_v, _v));
  return _mm_castps_si128(
      _mm_move_ss(_mm_castsi128_ps(_v), _mm_castsi128_ps(hadd)));
}

OZZ_INLINE SimdInt4 HAdd4(_SimdInt4 _v) {
  const __m128 v = _mm_castsi128_ps(_v);
  const __m128i haddxyzw =
      _mm_add_epi32(_v, _mm_castps_si128(_mm_movehl_ps(v, v)));
  return _mm_castps_si128(_mm_move_ss(
      v,
      _mm_castsi128_ps(_mm_add_epi32(haddxyzw, OZZ_SSE_SPLAT_I(haddxyzw, 1)))));
}

OZZ_INLINE SimdInt4 Abs(_SimdInt4 _v) {
#ifdef OZZ_SIMD_SSSE3
  return _mm_abs_epi32(_v);
#else   // OZZ_SIMD_SSSE3
  const __m128i zero = _mm_setzero_si128();
  return OZZ_SSE_SELECT_I(_mm_cmplt_epi32(_v, zero), _mm_sub_epi32(zero, _v),
                          _v);
#endif  // OZZ_SIMD_SSSE3
}

OZZ_INLINE SimdInt4 Sign(_SimdInt4 _v) {
  return _mm_slli_epi32(_mm_srli_epi32(_v, 31), 31);
}

OZZ_INLINE SimdInt4 Min(_SimdInt4 _a, _SimdInt4 _b) {
#ifdef OZZ_SIMD_SSE4_1
  return _mm_min_epi32(_a, _b);
#else   // OZZ_SIMD_SSE4_1
  return OZZ_SSE_SELECT_I(_mm_cmplt_epi32(_a, _b), _a, _b);
#endif  // OZZ_SIMD_SSE4_1
}

OZZ_INLINE SimdInt4 Max(_SimdInt4 _a, _SimdInt4 _b) {
#ifdef OZZ_SIMD_SSE4_1
  return _mm_max_epi32(_a, _b);
#else   // OZZ_SIMD_SSE4_1
  return OZZ_SSE_SELECT_I(_mm_cmpgt_epi32(_a, _b), _a, _b);
#endif  // OZZ_SIMD_SSE4_1
}

OZZ_INLINE SimdInt4 Min0(_SimdInt4 _v) {
  const __m128i zero = _mm_setzero_si128();
#ifdef OZZ_SIMD_SSE4_1
  return _mm_min_epi32(zero, _v);
#else   // OZZ_SIMD_SSE4_1
  return OZZ_SSE_SELECT_I(_mm_cmplt_epi32(zero, _v), zero, _v);
#endif  // OZZ_SIMD_SSE4_1
}

OZZ_INLINE SimdInt4 Max0(_SimdInt4 _v) {
  const __m128i zero = _mm_setzero_si128();
#ifdef OZZ_SIMD_SSE4_1
  return _mm_max_epi32(zero, _v);
#else   // OZZ_SIMD_SSE4_1
  return OZZ_SSE_SELECT_I(_mm_cmpgt_epi32(zero, _v), zero, _v);
#endif  // OZZ_SIMD_SSE4_1
}

OZZ_INLINE SimdInt4 Clamp(_SimdInt4 _a, _SimdInt4 _v, _SimdInt4 _b) {
#ifdef OZZ_SIMD_SSE4_1
  return _mm_min_epi32(_mm_max_epi32(_a, _v), _b);
#else   // OZZ_SIMD_SSE4_1
  const __m128i min = OZZ_SSE_SELECT_I(_mm_cmplt_epi32(_v, _b), _v, _b);
  return OZZ_SSE_SELECT_I(_mm_cmpgt_epi32(_a, min), _a, min);
#endif  // OZZ_SIMD_SSE4_1
}

OZZ_INLINE SimdInt4 Select(_SimdInt4 _b, _SimdInt4 _true, _SimdInt4 _false) {
  return OZZ_SSE_SELECT_I(_b, _true, _false);
}

OZZ_INLINE SimdInt4 And(_SimdInt4 _a, _SimdInt4 _b) {
  return _mm_and_si128(_a, _b);
}

OZZ_INLINE SimdInt4 AndNot(_SimdInt4 _a, _SimdInt4 _b) {
  return _mm_andnot_si128(_b, _a);
}

OZZ_INLINE SimdInt4 Or(_SimdInt4 _a, _SimdInt4 _b) {
  return _mm_or_si128(_a, _b);
}

OZZ_INLINE SimdInt4 Xor(_SimdInt4 _a, _SimdInt4 _b) {
  return _mm_xor_si128(_a, _b);
}

OZZ_INLINE SimdInt4 Not(_SimdInt4 _v) {
  return _mm_xor_si128(_v, _mm_cmpeq_epi32(_v, _v));
}

OZZ_INLINE SimdInt4 ShiftL(_SimdInt4 _v, int _bits) {
  return _mm_slli_epi32(_v, _bits);
}

OZZ_INLINE SimdInt4 ShiftR(_SimdInt4 _v, int _bits) {
  return _mm_srai_epi32(_v, _bits);
}

OZZ_INLINE SimdInt4 ShiftRu(_SimdInt4 _v, int _bits) {
  return _mm_srli_epi32(_v, _bits);
}

OZZ_INLINE SimdInt4 CmpEq(_SimdInt4 _a, _SimdInt4 _b) {
  return _mm_cmpeq_epi32(_a, _b);
}

OZZ_INLINE SimdInt4 CmpNe(_SimdInt4 _a, _SimdInt4 _b) {
  const __m128i eq = _mm_cmpeq_epi32(_a, _b);
  return _mm_xor_si128(eq, _mm_cmpeq_epi32(_a, _a));
}

OZZ_INLINE SimdInt4 CmpLt(_SimdInt4 _a, _SimdInt4 _b) {
  return _mm_cmpgt_epi32(_b, _a);
}

OZZ_INLINE SimdInt4 CmpLe(_SimdInt4 _a, _SimdInt4 _b) {
  const __m128i gt = _mm_cmpgt_epi32(_a, _b);
  return _mm_xor_si128(gt, _mm_cmpeq_epi32(_a, _a));
}

OZZ_INLINE SimdInt4 CmpGt(_SimdInt4 _a, _SimdInt4 _b) {
  return _mm_cmpgt_epi32(_a, _b);
}

OZZ_INLINE SimdInt4 CmpGe(_SimdInt4 _a, _SimdInt4 _b) {
  const __m128i lt = _mm_cmpgt_epi32(_b, _a);
  return _mm_xor_si128(lt, _mm_cmpeq_epi32(_a, _a));
}

OZZ_INLINE Float4x4 Float4x4::identity() {
  const __m128i zero = _mm_setzero_si128();
  const __m128i ffff = _mm_cmpeq_epi32(zero, zero);
  const __m128i one = _mm_srli_epi32(_mm_slli_epi32(ffff, 25), 2);
  const __m128i x = _mm_srli_si128(one, 12);
  const Float4x4 ret = {{_mm_castsi128_ps(x),
                         _mm_castsi128_ps(_mm_slli_si128(x, 4)),
                         _mm_castsi128_ps(_mm_slli_si128(x, 8)),
                         _mm_castsi128_ps(_mm_slli_si128(one, 12))}};
  return ret;
}

OZZ_INLINE Float4x4 Transpose(const Float4x4& _m) {
  const __m128 tmp0 = _mm_unpacklo_ps(_m.cols[0], _m.cols[2]);
  const __m128 tmp1 = _mm_unpacklo_ps(_m.cols[1], _m.cols[3]);
  const __m128 tmp2 = _mm_unpackhi_ps(_m.cols[0], _m.cols[2]);
  const __m128 tmp3 = _mm_unpackhi_ps(_m.cols[1], _m.cols[3]);
  const Float4x4 ret = {
      {_mm_unpacklo_ps(tmp0, tmp1), _mm_unpackhi_ps(tmp0, tmp1),
       _mm_unpacklo_ps(tmp2, tmp3), _mm_unpackhi_ps(tmp2, tmp3)}};
  return ret;
}

inline Float4x4 Invert(const Float4x4& _m, SimdInt4* _invertible) {
  const __m128 _t0 =
      _mm_shuffle_ps(_m.cols[0], _m.cols[1], _MM_SHUFFLE(1, 0, 1, 0));
  const __m128 _t1 =
      _mm_shuffle_ps(_m.cols[2], _m.cols[3], _MM_SHUFFLE(1, 0, 1, 0));
  const __m128 _t2 =
      _mm_shuffle_ps(_m.cols[0], _m.cols[1], _MM_SHUFFLE(3, 2, 3, 2));
  const __m128 _t3 =
      _mm_shuffle_ps(_m.cols[2], _m.cols[3], _MM_SHUFFLE(3, 2, 3, 2));
  const __m128 c0 = _mm_shuffle_ps(_t0, _t1, _MM_SHUFFLE(2, 0, 2, 0));
  const __m128 c1 = _mm_shuffle_ps(_t1, _t0, _MM_SHUFFLE(3, 1, 3, 1));
  const __m128 c2 = _mm_shuffle_ps(_t2, _t3, _MM_SHUFFLE(2, 0, 2, 0));
  const __m128 c3 = _mm_shuffle_ps(_t3, _t2, _MM_SHUFFLE(3, 1, 3, 1));

  __m128 minor0, minor1, minor2, minor3, tmp1, tmp2;
  tmp1 = _mm_mul_ps(c2, c3);
  tmp1 = OZZ_SHUFFLE_PS1(tmp1, 0xB1);
  minor0 = _mm_mul_ps(c1, tmp1);
  minor1 = _mm_mul_ps(c0, tmp1);
  tmp1 = OZZ_SHUFFLE_PS1(tmp1, 0x4E);
  minor0 = OZZ_MSUB(c1, tmp1, minor0);
  minor1 = OZZ_MSUB(c0, tmp1, minor1);
  minor1 = OZZ_SHUFFLE_PS1(minor1, 0x4E);

  tmp1 = _mm_mul_ps(c1, c2);
  tmp1 = OZZ_SHUFFLE_PS1(tmp1, 0xB1);
  minor0 = OZZ_MADD(c3, tmp1, minor0);
  minor3 = _mm_mul_ps(c0, tmp1);
  tmp1 = OZZ_SHUFFLE_PS1(tmp1, 0x4E);
  minor0 = OZZ_NMADD(c3, tmp1, minor0);
  minor3 = OZZ_MSUB(c0, tmp1, minor3);
  minor3 = OZZ_SHUFFLE_PS1(minor3, 0x4E);

  tmp1 = _mm_mul_ps(OZZ_SHUFFLE_PS1(c1, 0x4E), c3);
  tmp1 = OZZ_SHUFFLE_PS1(tmp1, 0xB1);
  tmp2 = OZZ_SHUFFLE_PS1(c2, 0x4E);
  minor0 = OZZ_MADD(tmp2, tmp1, minor0);
  minor2 = _mm_mul_ps(c0, tmp1);
  tmp1 = OZZ_SHUFFLE_PS1(tmp1, 0x4E);
  minor0 = OZZ_NMADD(tmp2, tmp1, minor0);
  minor2 = OZZ_MSUB(c0, tmp1, minor2);
  minor2 = OZZ_SHUFFLE_PS1(minor2, 0x4E);

  tmp1 = _mm_mul_ps(c0, c1);
  tmp1 = OZZ_SHUFFLE_PS1(tmp1, 0xB1);
  minor2 = OZZ_MADD(c3, tmp1, minor2);
  minor3 = OZZ_MSUB(tmp2, tmp1, minor3);
  tmp1 = OZZ_SHUFFLE_PS1(tmp1, 0x4E);
  minor2 = OZZ_MSUB(c3, tmp1, minor2);
  minor3 = OZZ_NMADD(tmp2, tmp1, minor3);

  tmp1 = _mm_mul_ps(c0, c3);
  tmp1 = OZZ_SHUFFLE_PS1(tmp1, 0xB1);
  minor1 = OZZ_NMADD(tmp2, tmp1, minor1);
  minor2 = OZZ_MADD(c1, tmp1, minor2);
  tmp1 = OZZ_SHUFFLE_PS1(tmp1, 0x4E);
  minor1 = OZZ_MADD(tmp2, tmp1, minor1);
  minor2 = OZZ_NMADD(c1, tmp1, minor2);

  tmp1 = _mm_mul_ps(c0, tmp2);
  tmp1 = OZZ_SHUFFLE_PS1(tmp1, 0xB1);
  minor1 = OZZ_MADD(c3, tmp1, minor1);
  minor3 = OZZ_NMADD(c1, tmp1, minor3);
  tmp1 = OZZ_SHUFFLE_PS1(tmp1, 0x4E);
  minor1 = OZZ_NMADD(c3, tmp1, minor1);
  minor3 = OZZ_MADD(c1, tmp1, minor3);

  __m128 det;
  det = _mm_mul_ps(c0, minor0);
  det = _mm_add_ps(OZZ_SHUFFLE_PS1(det, 0x4E), det);
  det = _mm_add_ss(OZZ_SHUFFLE_PS1(det, 0xB1), det);
  const SimdInt4 invertible = CmpNe(det, simd_float4::zero());
  assert((_invertible || AreAllTrue1(invertible)) &&
         "Matrix is not invertible");
  if (_invertible != nullptr) {
    *_invertible = invertible;
  }
  tmp1 = OZZ_SSE_SELECT_F(invertible, RcpEstNR(det), simd_float4::zero());
  det = OZZ_NMADDX(det, _mm_mul_ss(tmp1, tmp1), _mm_add_ss(tmp1, tmp1));
  det = OZZ_SHUFFLE_PS1(det, 0x00);

  // Copy the final columns
  const Float4x4 ret = {{_mm_mul_ps(det, minor0), _mm_mul_ps(det, minor1),
                         _mm_mul_ps(det, minor2), _mm_mul_ps(det, minor3)}};
  return ret;
}

Float4x4 Float4x4::Translation(_SimdFloat4 _v) {
  const __m128i zero = _mm_setzero_si128();
  const __m128i ffff = _mm_cmpeq_epi32(zero, zero);
  const __m128i mask000f = _mm_slli_si128(ffff, 12);
  const __m128i one = _mm_srli_epi32(_mm_slli_epi32(ffff, 25), 2);
  const __m128i x = _mm_srli_si128(one, 12);
  const Float4x4 ret = {
      {_mm_castsi128_ps(x), _mm_castsi128_ps(_mm_slli_si128(x, 4)),
       _mm_castsi128_ps(_mm_slli_si128(x, 8)),
       OZZ_SSE_SELECT_F(mask000f, _mm_castsi128_ps(one), _v)}};
  return ret;
}  // math

Float4x4 Float4x4::Scaling(_SimdFloat4 _v) {
  const __m128i zero = _mm_setzero_si128();
  const __m128i ffff = _mm_cmpeq_epi32(zero, zero);
  const __m128i if000 = _mm_srli_si128(ffff, 12);
  const __m128i ione = _mm_srli_epi32(_mm_slli_epi32(ffff, 25), 2);
  const Float4x4 ret = {
      {_mm_and_ps(_v, _mm_castsi128_ps(if000)),
       _mm_and_ps(_v, _mm_castsi128_ps(_mm_slli_si128(if000, 4))),
       _mm_and_ps(_v, _mm_castsi128_ps(_mm_slli_si128(if000, 8))),
       _mm_castsi128_ps(_mm_slli_si128(ione, 12))}};
  return ret;
}  // math

OZZ_INLINE Float4x4 Translate(const Float4x4& _m, _SimdFloat4 _v) {
  const __m128 a01 = OZZ_MADD(_m.cols[0], OZZ_SSE_SPLAT_F(_v, 0),
                              _mm_mul_ps(_m.cols[1], OZZ_SSE_SPLAT_F(_v, 1)));
  const __m128 m3 = OZZ_MADD(_m.cols[2], OZZ_SSE_SPLAT_F(_v, 2), _m.cols[3]);
  const Float4x4 ret = {
      {_m.cols[0], _m.cols[1], _m.cols[2], _mm_add_ps(a01, m3)}};
  return ret;
}

OZZ_INLINE Float4x4 Scale(const Float4x4& _m, _SimdFloat4 _v) {
  const Float4x4 ret = {{_mm_mul_ps(_m.cols[0], OZZ_SSE_SPLAT_F(_v, 0)),
                         _mm_mul_ps(_m.cols[1], OZZ_SSE_SPLAT_F(_v, 1)),
                         _mm_mul_ps(_m.cols[2], OZZ_SSE_SPLAT_F(_v, 2)),
                         _m.cols[3]}};
  return ret;
}

OZZ_INLINE Float4x4 ColumnMultiply(const Float4x4& _m, _SimdFloat4 _v) {
  const Float4x4 ret = {{_mm_mul_ps(_m.cols[0], _v), _mm_mul_ps(_m.cols[1], _v),
                         _mm_mul_ps(_m.cols[2], _v),
                         _mm_mul_ps(_m.cols[3], _v)}};
  return ret;
}

inline SimdInt4 IsNormalized(const Float4x4& _m) {
  const __m128 max = _mm_set_ps1(1.f + kNormalizationToleranceSq);
  const __m128 min = _mm_set_ps1(1.f - kNormalizationToleranceSq);

  const __m128 tmp0 = _mm_unpacklo_ps(_m.cols[0], _m.cols[2]);
  const __m128 tmp1 = _mm_unpacklo_ps(_m.cols[1], _m.cols[3]);
  const __m128 tmp2 = _mm_unpackhi_ps(_m.cols[0], _m.cols[2]);
  const __m128 tmp3 = _mm_unpackhi_ps(_m.cols[1], _m.cols[3]);
  const __m128 row0 = _mm_unpacklo_ps(tmp0, tmp1);
  const __m128 row1 = _mm_unpackhi_ps(tmp0, tmp1);
  const __m128 row2 = _mm_unpacklo_ps(tmp2, tmp3);

  const __m128 dot =
      OZZ_MADD(row0, row0, OZZ_MADD(row1, row1, _mm_mul_ps(row2, row2)));
  const __m128 normalized =
      _mm_and_ps(_mm_cmplt_ps(dot, max), _mm_cmpgt_ps(dot, min));
  return _mm_castps_si128(
      _mm_and_ps(normalized, _mm_castsi128_ps(simd_int4::mask_fff0())));
}

inline SimdInt4 IsNormalizedEst(const Float4x4& _m) {
  const __m128 max = _mm_set_ps1(1.f + kNormalizationToleranceEstSq);
  const __m128 min = _mm_set_ps1(1.f - kNormalizationToleranceEstSq);

  const __m128 tmp0 = _mm_unpacklo_ps(_m.cols[0], _m.cols[2]);
  const __m128 tmp1 = _mm_unpacklo_ps(_m.cols[1], _m.cols[3]);
  const __m128 tmp2 = _mm_unpackhi_ps(_m.cols[0], _m.cols[2]);
  const __m128 tmp3 = _mm_unpackhi_ps(_m.cols[1], _m.cols[3]);
  const __m128 row0 = _mm_unpacklo_ps(tmp0, tmp1);
  const __m128 row1 = _mm_unpackhi_ps(tmp0, tmp1);
  const __m128 row2 = _mm_unpacklo_ps(tmp2, tmp3);

  const __m128 dot =
      OZZ_MADD(row0, row0, OZZ_MADD(row1, row1, _mm_mul_ps(row2, row2)));

  const __m128 normalized =
      _mm_and_ps(_mm_cmplt_ps(dot, max), _mm_cmpgt_ps(dot, min));

  return _mm_castps_si128(
      _mm_and_ps(normalized, _mm_castsi128_ps(simd_int4::mask_fff0())));
}

OZZ_INLINE SimdInt4 IsOrthogonal(const Float4x4& _m) {
  const __m128 max = _mm_set_ss(1.f + kNormalizationToleranceSq);
  const __m128 min = _mm_set_ss(1.f - kNormalizationToleranceSq);
  const __m128 zero = _mm_setzero_ps();

  // Use simd_float4::zero() if one of the normalization fails. _m will then be
  // considered not orthogonal.
  const SimdFloat4 cross = NormalizeSafe3(Cross3(_m.cols[0], _m.cols[1]), zero);
  const SimdFloat4 at = NormalizeSafe3(_m.cols[2], zero);

  SimdFloat4 dot;
  OZZ_SSE_DOT3_F(cross, at, dot);
  __m128 dotx000 = _mm_move_ss(zero, dot);
  return _mm_castps_si128(
      _mm_and_ps(_mm_cmplt_ss(dotx000, max), _mm_cmpgt_ss(dotx000, min)));
}

inline SimdFloat4 ToQuaternion(const Float4x4& _m) {
  assert(AreAllTrue3(IsNormalizedEst(_m)));
  assert(AreAllTrue1(IsOrthogonal(_m)));

  // Prepares constants.
  const __m128i zero = _mm_setzero_si128();
  const __m128i ffff = _mm_cmpeq_epi32(zero, zero);
  const __m128 half = _mm_set1_ps(0.5f);
  const __m128i mask_f000 = _mm_srli_si128(ffff, 12);
  const __m128i mask_000f = _mm_slli_si128(ffff, 12);
  const __m128 one =
      _mm_castsi128_ps(_mm_srli_epi32(_mm_slli_epi32(ffff, 25), 2));
  const __m128i mask_0f00 = _mm_slli_si128(mask_f000, 4);
  const __m128i mask_00f0 = _mm_slli_si128(mask_f000, 8);

  const __m128 xx_yy = OZZ_SSE_SELECT_F(mask_0f00, _m.cols[1], _m.cols[0]);
  const __m128 xx_yy_0010 = OZZ_SHUFFLE_PS1(xx_yy, _MM_SHUFFLE(0, 0, 1, 0));
  const __m128 xx_yy_zz_xx =
      OZZ_SSE_SELECT_F(mask_00f0, _m.cols[2], xx_yy_0010);
  const __m128 yy_zz_xx_yy =
      OZZ_SHUFFLE_PS1(xx_yy_zz_xx, _MM_SHUFFLE(1, 0, 2, 1));
  const __m128 zz_xx_yy_zz =
      OZZ_SHUFFLE_PS1(xx_yy_zz_xx, _MM_SHUFFLE(2, 1, 0, 2));

  const __m128 diag_sum =
      _mm_add_ps(_mm_add_ps(xx_yy_zz_xx, yy_zz_xx_yy), zz_xx_yy_zz);
  const __m128 diag_diff =
      _mm_sub_ps(_mm_sub_ps(xx_yy_zz_xx, yy_zz_xx_yy), zz_xx_yy_zz);
  const __m128 radicand =
      _mm_add_ps(OZZ_SSE_SELECT_F(mask_000f, diag_sum, diag_diff), one);
  const __m128 invSqrt = one / _mm_sqrt_ps(radicand);

  __m128 zy_xz_yx = OZZ_SSE_SELECT_F(mask_00f0, _m.cols[1], _m.cols[0]);
  zy_xz_yx = OZZ_SHUFFLE_PS1(zy_xz_yx, _MM_SHUFFLE(0, 1, 2, 2));
  zy_xz_yx =
      OZZ_SSE_SELECT_F(mask_0f00, OZZ_SSE_SPLAT_F(_m.cols[2], 0), zy_xz_yx);
  __m128 yz_zx_xy = OZZ_SSE_SELECT_F(mask_f000, _m.cols[1], _m.cols[0]);
  yz_zx_xy = OZZ_SHUFFLE_PS1(yz_zx_xy, _MM_SHUFFLE(0, 0, 2, 0));
  yz_zx_xy =
      OZZ_SSE_SELECT_F(mask_f000, OZZ_SSE_SPLAT_F(_m.cols[2], 1), yz_zx_xy);
  const __m128 sum = _mm_add_ps(zy_xz_yx, yz_zx_xy);
  const __m128 diff = _mm_sub_ps(zy_xz_yx, yz_zx_xy);
  const __m128 scale = _mm_mul_ps(invSqrt, half);

  const __m128 sum0 = OZZ_SHUFFLE_PS1(sum, _MM_SHUFFLE(0, 1, 2, 0));
  const __m128 sum1 = OZZ_SHUFFLE_PS1(sum, _MM_SHUFFLE(0, 0, 0, 2));
  const __m128 sum2 = OZZ_SHUFFLE_PS1(sum, _MM_SHUFFLE(0, 0, 0, 1));
  __m128 res0 = OZZ_SSE_SELECT_F(mask_000f, OZZ_SSE_SPLAT_F(diff, 0), sum0);
  __m128 res1 = OZZ_SSE_SELECT_F(mask_000f, OZZ_SSE_SPLAT_F(diff, 1), sum1);
  __m128 res2 = OZZ_SSE_SELECT_F(mask_000f, OZZ_SSE_SPLAT_F(diff, 2), sum2);
  res0 = _mm_mul_ps(OZZ_SSE_SELECT_F(mask_f000, radicand, res0),
                    OZZ_SSE_SPLAT_F(scale, 0));
  res1 = _mm_mul_ps(OZZ_SSE_SELECT_F(mask_0f00, radicand, res1),
                    OZZ_SSE_SPLAT_F(scale, 1));
  res2 = _mm_mul_ps(OZZ_SSE_SELECT_F(mask_00f0, radicand, res2),
                    OZZ_SSE_SPLAT_F(scale, 2));
  __m128 res3 = _mm_mul_ps(OZZ_SSE_SELECT_F(mask_000f, radicand, diff),
                           OZZ_SSE_SPLAT_F(scale, 3));

  const __m128 xx = OZZ_SSE_SPLAT_F(_m.cols[0], 0);
  const __m128 yy = OZZ_SSE_SPLAT_F(_m.cols[1], 1);
  const __m128 zz = OZZ_SSE_SPLAT_F(_m.cols[2], 2);
  const __m128i cond0 = _mm_castps_si128(_mm_cmpgt_ps(yy, xx));
  const __m128i cond1 =
      _mm_castps_si128(_mm_and_ps(_mm_cmpgt_ps(zz, xx), _mm_cmpgt_ps(zz, yy)));
  const __m128i cond2 = _mm_castps_si128(
      _mm_cmpgt_ps(OZZ_SSE_SPLAT_F(diag_sum, 0), _mm_castsi128_ps(zero)));
  __m128 res = OZZ_SSE_SELECT_F(cond0, res1, res0);
  res = OZZ_SSE_SELECT_F(cond1, res2, res);
  res = OZZ_SSE_SELECT_F(cond2, res3, res);

  assert(AreAllTrue1(IsNormalizedEst4(res)));
  return res;
}

inline bool ToAffine(const Float4x4& _m, SimdFloat4* _translation,
                     SimdFloat4* _quaternion, SimdFloat4* _scale) {
  const __m128 zero = _mm_setzero_ps();
  const __m128 one = simd_float4::one();
  const __m128i fff0 = simd_int4::mask_fff0();
  const __m128 max = _mm_set_ps1(kOrthogonalisationToleranceSq);
  const __m128 min = _mm_set_ps1(-kOrthogonalisationToleranceSq);

  // Extracts translation.
  *_translation = OZZ_SSE_SELECT_F(fff0, _m.cols[3], one);

  // Extracts scale.
  const __m128 m_tmp0 = _mm_unpacklo_ps(_m.cols[0], _m.cols[2]);
  const __m128 m_tmp1 = _mm_unpacklo_ps(_m.cols[1], _m.cols[3]);
  const __m128 m_tmp2 = _mm_unpackhi_ps(_m.cols[0], _m.cols[2]);
  const __m128 m_tmp3 = _mm_unpackhi_ps(_m.cols[1], _m.cols[3]);
  const __m128 m_row0 = _mm_unpacklo_ps(m_tmp0, m_tmp1);
  const __m128 m_row1 = _mm_unpackhi_ps(m_tmp0, m_tmp1);
  const __m128 m_row2 = _mm_unpacklo_ps(m_tmp2, m_tmp3);

  const __m128 dot = OZZ_MADD(
      m_row0, m_row0, OZZ_MADD(m_row1, m_row1, _mm_mul_ps(m_row2, m_row2)));
  const __m128 abs_scale = _mm_sqrt_ps(dot);

  const __m128 zero_axis =
      _mm_and_ps(_mm_cmplt_ps(dot, max), _mm_cmpgt_ps(dot, min));

  // Builds an orthonormal matrix in order to support quaternion extraction.
  Float4x4 orthonormal;
  int mask = _mm_movemask_ps(zero_axis);
  if (mask & 1) {
    if (mask & 6) {
      return false;
    }
    orthonormal.cols[1] = _mm_div_ps(_m.cols[1], OZZ_SSE_SPLAT_F(abs_scale, 1));
    orthonormal.cols[0] = Normalize3(Cross3(orthonormal.cols[1], _m.cols[2]));
    orthonormal.cols[2] =
        Normalize3(Cross3(orthonormal.cols[0], orthonormal.cols[1]));
  } else if (mask & 4) {
    if (mask & 3) {
      return false;
    }
    orthonormal.cols[0] = _mm_div_ps(_m.cols[0], OZZ_SSE_SPLAT_F(abs_scale, 0));
    orthonormal.cols[2] = Normalize3(Cross3(orthonormal.cols[0], _m.cols[1]));
    orthonormal.cols[1] =
        Normalize3(Cross3(orthonormal.cols[2], orthonormal.cols[0]));
  } else {  // Favor z axis in the default case
    if (mask & 5) {
      return false;
    }
    orthonormal.cols[2] = _mm_div_ps(_m.cols[2], OZZ_SSE_SPLAT_F(abs_scale, 2));
    orthonormal.cols[1] = Normalize3(Cross3(orthonormal.cols[2], _m.cols[0]));
    orthonormal.cols[0] =
        Normalize3(Cross3(orthonormal.cols[1], orthonormal.cols[2]));
  }
  orthonormal.cols[3] = simd_float4::w_axis();

  // Get back scale signs in case of reflexions
  const __m128 o_tmp0 =
      _mm_unpacklo_ps(orthonormal.cols[0], orthonormal.cols[2]);
  const __m128 o_tmp1 =
      _mm_unpacklo_ps(orthonormal.cols[1], orthonormal.cols[3]);
  const __m128 o_tmp2 =
      _mm_unpackhi_ps(orthonormal.cols[0], orthonormal.cols[2]);
  const __m128 o_tmp3 =
      _mm_unpackhi_ps(orthonormal.cols[1], orthonormal.cols[3]);
  const __m128 o_row0 = _mm_unpacklo_ps(o_tmp0, o_tmp1);
  const __m128 o_row1 = _mm_unpackhi_ps(o_tmp0, o_tmp1);
  const __m128 o_row2 = _mm_unpacklo_ps(o_tmp2, o_tmp3);

  const __m128 scale_dot = OZZ_MADD(
      o_row0, m_row0, OZZ_MADD(o_row1, m_row1, _mm_mul_ps(o_row2, m_row2)));

  const __m128i cond = _mm_castps_si128(_mm_cmpgt_ps(scale_dot, zero));
  const __m128 cfalse = _mm_sub_ps(zero, abs_scale);
  const __m128 scale = OZZ_SSE_SELECT_F(cond, abs_scale, cfalse);
  *_scale = OZZ_SSE_SELECT_F(fff0, scale, one);

  // Extracts quaternion.
  *_quaternion = ToQuaternion(orthonormal);
  return true;
}

inline Float4x4 Float4x4::FromEuler(_SimdFloat4 _v) {
  return Float4x4::FromAxisAngle(simd_float4::y_axis(), SplatX(_v)) *
         Float4x4::FromAxisAngle(simd_float4::x_axis(), SplatY(_v)) *
         Float4x4::FromAxisAngle(simd_float4::z_axis(), SplatZ(_v));
}

inline Float4x4 Float4x4::FromAxisAngle(_SimdFloat4 _axis, _SimdFloat4 _angle) {
  assert(AreAllTrue1(IsNormalizedEst3(_axis)));

  const __m128i zero = _mm_setzero_si128();
  const __m128i ffff = _mm_cmpeq_epi32(zero, zero);
  const __m128i ione = _mm_srli_epi32(_mm_slli_epi32(ffff, 25), 2);
  const __m128 fff0 = _mm_castsi128_ps(_mm_srli_si128(ffff, 4));
  const __m128 one = _mm_castsi128_ps(ione);
  const __m128 w_axis = _mm_castsi128_ps(_mm_slli_si128(ione, 12));

  const __m128 sin = SplatX(SinX(_angle));
  const __m128 cos = SplatX(CosX(_angle));
  const __m128 one_minus_cos = _mm_sub_ps(one, cos);

  const __m128 v0 =
      _mm_mul_ps(_mm_mul_ps(one_minus_cos,
                            OZZ_SHUFFLE_PS1(_axis, _MM_SHUFFLE(3, 0, 2, 1))),
                 OZZ_SHUFFLE_PS1(_axis, _MM_SHUFFLE(3, 1, 0, 2)));
  const __m128 r0 =
      _mm_add_ps(_mm_mul_ps(_mm_mul_ps(one_minus_cos, _axis), _axis), cos);
  const __m128 r1 = _mm_add_ps(_mm_mul_ps(sin, _axis), v0);
  const __m128 r2 = _mm_sub_ps(v0, _mm_mul_ps(sin, _axis));
  const __m128 r0fff0 = _mm_and_ps(r0, fff0);
  const __m128 r1r22120 = _mm_shuffle_ps(r1, r2, _MM_SHUFFLE(2, 1, 2, 0));
  const __m128 v1 = OZZ_SHUFFLE_PS1(r1r22120, _MM_SHUFFLE(0, 3, 2, 1));
  const __m128 r1r20011 = _mm_shuffle_ps(r1, r2, _MM_SHUFFLE(0, 0, 1, 1));
  const __m128 v2 = OZZ_SHUFFLE_PS1(r1r20011, _MM_SHUFFLE(2, 0, 2, 0));

  const __m128 t0 = _mm_shuffle_ps(r0fff0, v1, _MM_SHUFFLE(1, 0, 3, 0));
  const __m128 t1 = _mm_shuffle_ps(r0fff0, v1, _MM_SHUFFLE(3, 2, 3, 1));
  const Float4x4 ret = {{OZZ_SHUFFLE_PS1(t0, _MM_SHUFFLE(1, 3, 2, 0)),
                         OZZ_SHUFFLE_PS1(t1, _MM_SHUFFLE(1, 3, 0, 2)),
                         _mm_shuffle_ps(v2, r0fff0, _MM_SHUFFLE(3, 2, 1, 0)),
                         w_axis}};
  return ret;
}

inline Float4x4 Float4x4::FromQuaternion(_SimdFloat4 _quaternion) {
  assert(AreAllTrue1(IsNormalizedEst4(_quaternion)));

  const __m128i zero = _mm_setzero_si128();
  const __m128i ffff = _mm_cmpeq_epi32(zero, zero);
  const __m128i ione = _mm_srli_epi32(_mm_slli_epi32(ffff, 25), 2);
  const __m128 fff0 = _mm_castsi128_ps(_mm_srli_si128(ffff, 4));
  const __m128 c1110 = _mm_castsi128_ps(_mm_srli_si128(ione, 4));
  const __m128 w_axis = _mm_castsi128_ps(_mm_slli_si128(ione, 12));

  const __m128 vsum = _mm_add_ps(_quaternion, _quaternion);
  const __m128 vms = _mm_mul_ps(_quaternion, vsum);

  const __m128 r0 = _mm_sub_ps(
      _mm_sub_ps(
          c1110,
          _mm_and_ps(OZZ_SHUFFLE_PS1(vms, _MM_SHUFFLE(3, 0, 0, 1)), fff0)),
      _mm_and_ps(OZZ_SHUFFLE_PS1(vms, _MM_SHUFFLE(3, 1, 2, 2)), fff0));
  const __m128 v0 =
      _mm_mul_ps(OZZ_SHUFFLE_PS1(_quaternion, _MM_SHUFFLE(3, 1, 0, 0)),
                 OZZ_SHUFFLE_PS1(vsum, _MM_SHUFFLE(3, 2, 1, 2)));
  const __m128 v1 =
      _mm_mul_ps(OZZ_SHUFFLE_PS1(_quaternion, _MM_SHUFFLE(3, 3, 3, 3)),
                 OZZ_SHUFFLE_PS1(vsum, _MM_SHUFFLE(3, 0, 2, 1)));

  const __m128 r1 = _mm_add_ps(v0, v1);
  const __m128 r2 = _mm_sub_ps(v0, v1);

  const __m128 r1r21021 = _mm_shuffle_ps(r1, r2, _MM_SHUFFLE(1, 0, 2, 1));
  const __m128 v2 = OZZ_SHUFFLE_PS1(r1r21021, _MM_SHUFFLE(1, 3, 2, 0));
  const __m128 r1r22200 = _mm_shuffle_ps(r1, r2, _MM_SHUFFLE(2, 2, 0, 0));
  const __m128 v3 = OZZ_SHUFFLE_PS1(r1r22200, _MM_SHUFFLE(2, 0, 2, 0));

  const __m128 q0 = _mm_shuffle_ps(r0, v2, _MM_SHUFFLE(1, 0, 3, 0));
  const __m128 q1 = _mm_shuffle_ps(r0, v2, _MM_SHUFFLE(3, 2, 3, 1));
  const Float4x4 ret = {{OZZ_SHUFFLE_PS1(q0, _MM_SHUFFLE(1, 3, 2, 0)),
                         OZZ_SHUFFLE_PS1(q1, _MM_SHUFFLE(1, 3, 0, 2)),
                         _mm_shuffle_ps(v3, r0, _MM_SHUFFLE(3, 2, 1, 0)),
                         w_axis}};
  return ret;
}

inline Float4x4 Float4x4::FromAffine(_SimdFloat4 _translation,
                                     _SimdFloat4 _quaternion,
                                     _SimdFloat4 _scale) {
  assert(AreAllTrue1(IsNormalizedEst4(_quaternion)));

  const __m128i zero = _mm_setzero_si128();
  const __m128i ffff = _mm_cmpeq_epi32(zero, zero);
  const __m128i ione = _mm_srli_epi32(_mm_slli_epi32(ffff, 25), 2);
  const __m128 fff0 = _mm_castsi128_ps(_mm_srli_si128(ffff, 4));
  const __m128 c1110 = _mm_castsi128_ps(_mm_srli_si128(ione, 4));

  const __m128 vsum = _mm_add_ps(_quaternion, _quaternion);
  const __m128 vms = _mm_mul_ps(_quaternion, vsum);

  const __m128 r0 = _mm_sub_ps(
      _mm_sub_ps(
          c1110,
          _mm_and_ps(OZZ_SHUFFLE_PS1(vms, _MM_SHUFFLE(3, 0, 0, 1)), fff0)),
      _mm_and_ps(OZZ_SHUFFLE_PS1(vms, _MM_SHUFFLE(3, 1, 2, 2)), fff0));
  const __m128 v0 =
      _mm_mul_ps(OZZ_SHUFFLE_PS1(_quaternion, _MM_SHUFFLE(3, 1, 0, 0)),
                 OZZ_SHUFFLE_PS1(vsum, _MM_SHUFFLE(3, 2, 1, 2)));
  const __m128 v1 =
      _mm_mul_ps(OZZ_SHUFFLE_PS1(_quaternion, _MM_SHUFFLE(3, 3, 3, 3)),
                 OZZ_SHUFFLE_PS1(vsum, _MM_SHUFFLE(3, 0, 2, 1)));

  const __m128 r1 = _mm_add_ps(v0, v1);
  const __m128 r2 = _mm_sub_ps(v0, v1);

  const __m128 r1r21021 = _mm_shuffle_ps(r1, r2, _MM_SHUFFLE(1, 0, 2, 1));
  const __m128 v2 = OZZ_SHUFFLE_PS1(r1r21021, _MM_SHUFFLE(1, 3, 2, 0));
  const __m128 r1r22200 = _mm_shuffle_ps(r1, r2, _MM_SHUFFLE(2, 2, 0, 0));
  const __m128 v3 = OZZ_SHUFFLE_PS1(r1r22200, _MM_SHUFFLE(2, 0, 2, 0));

  const __m128 q0 = _mm_shuffle_ps(r0, v2, _MM_SHUFFLE(1, 0, 3, 0));
  const __m128 q1 = _mm_shuffle_ps(r0, v2, _MM_SHUFFLE(3, 2, 3, 1));

  const Float4x4 ret = {
      {_mm_mul_ps(OZZ_SHUFFLE_PS1(q0, _MM_SHUFFLE(1, 3, 2, 0)),
                  OZZ_SSE_SPLAT_F(_scale, 0)),
       _mm_mul_ps(OZZ_SHUFFLE_PS1(q1, _MM_SHUFFLE(1, 3, 0, 2)),
                  OZZ_SSE_SPLAT_F(_scale, 1)),
       _mm_mul_ps(_mm_shuffle_ps(v3, r0, _MM_SHUFFLE(3, 2, 1, 0)),
                  OZZ_SSE_SPLAT_F(_scale, 2)),
       _mm_movelh_ps(_translation, _mm_unpackhi_ps(_translation, c1110))}};
  return ret;
}

OZZ_INLINE ozz::math::SimdFloat4 TransformPoint(const ozz::math::Float4x4& _m,
                                                ozz::math::_SimdFloat4 _v) {
  const __m128 xxxx = _mm_mul_ps(OZZ_SSE_SPLAT_F(_v, 0), _m.cols[0]);
  const __m128 a23 = OZZ_MADD(OZZ_SSE_SPLAT_F(_v, 2), _m.cols[2], _m.cols[3]);
  const __m128 a01 = OZZ_MADD(OZZ_SSE_SPLAT_F(_v, 1), _m.cols[1], xxxx);
  return _mm_add_ps(a01, a23);
}

OZZ_INLINE ozz::math::SimdFloat4 TransformVector(const ozz::math::Float4x4& _m,
                                                 ozz::math::_SimdFloat4 _v) {
  const __m128 xxxx = _mm_mul_ps(_m.cols[0], OZZ_SSE_SPLAT_F(_v, 0));
  const __m128 zzzz = _mm_mul_ps(_m.cols[1], OZZ_SSE_SPLAT_F(_v, 1));
  const __m128 a21 = OZZ_MADD(_m.cols[2], OZZ_SSE_SPLAT_F(_v, 2), xxxx);
  return _mm_add_ps(zzzz, a21);
}

OZZ_INLINE ozz::math::SimdFloat4 operator*(const ozz::math::Float4x4& _m,
                                           ozz::math::_SimdFloat4 _v) {
  const __m128 xxxx = _mm_mul_ps(OZZ_SSE_SPLAT_F(_v, 0), _m.cols[0]);
  const __m128 zzzz = _mm_mul_ps(OZZ_SSE_SPLAT_F(_v, 2), _m.cols[2]);
  const __m128 a01 = OZZ_MADD(OZZ_SSE_SPLAT_F(_v, 1), _m.cols[1], xxxx);
  const __m128 a23 = OZZ_MADD(OZZ_SSE_SPLAT_F(_v, 3), _m.cols[3], zzzz);
  return _mm_add_ps(a01, a23);
}

inline ozz::math::Float4x4 operator*(const ozz::math::Float4x4& _a,
                                     const ozz::math::Float4x4& _b) {
  ozz::math::Float4x4 ret;
  {
    const __m128 xxxx = _mm_mul_ps(OZZ_SSE_SPLAT_F(_b.cols[0], 0), _a.cols[0]);
    const __m128 zzzz = _mm_mul_ps(OZZ_SSE_SPLAT_F(_b.cols[0], 2), _a.cols[2]);
    const __m128 a01 =
        OZZ_MADD(OZZ_SSE_SPLAT_F(_b.cols[0], 1), _a.cols[1], xxxx);
    const __m128 a23 =
        OZZ_MADD(OZZ_SSE_SPLAT_F(_b.cols[0], 3), _a.cols[3], zzzz);
    ret.cols[0] = _mm_add_ps(a01, a23);
  }
  {
    const __m128 xxxx = _mm_mul_ps(OZZ_SSE_SPLAT_F(_b.cols[1], 0), _a.cols[0]);
    const __m128 zzzz = _mm_mul_ps(OZZ_SSE_SPLAT_F(_b.cols[1], 2), _a.cols[2]);
    const __m128 a01 =
        OZZ_MADD(OZZ_SSE_SPLAT_F(_b.cols[1], 1), _a.cols[1], xxxx);
    const __m128 a23 =
        OZZ_MADD(OZZ_SSE_SPLAT_F(_b.cols[1], 3), _a.cols[3], zzzz);
    ret.cols[1] = _mm_add_ps(a01, a23);
  }
  {
    const __m128 xxxx = _mm_mul_ps(OZZ_SSE_SPLAT_F(_b.cols[2], 0), _a.cols[0]);
    const __m128 zzzz = _mm_mul_ps(OZZ_SSE_SPLAT_F(_b.cols[2], 2), _a.cols[2]);
    const __m128 a01 =
        OZZ_MADD(OZZ_SSE_SPLAT_F(_b.cols[2], 1), _a.cols[1], xxxx);
    const __m128 a23 =
        OZZ_MADD(OZZ_SSE_SPLAT_F(_b.cols[2], 3), _a.cols[3], zzzz);
    ret.cols[2] = _mm_add_ps(a01, a23);
  }
  {
    const __m128 xxxx = _mm_mul_ps(OZZ_SSE_SPLAT_F(_b.cols[3], 0), _a.cols[0]);
    const __m128 zzzz = _mm_mul_ps(OZZ_SSE_SPLAT_F(_b.cols[3], 2), _a.cols[2]);
    const __m128 a01 =
        OZZ_MADD(OZZ_SSE_SPLAT_F(_b.cols[3], 1), _a.cols[1], xxxx);
    const __m128 a23 =
        OZZ_MADD(OZZ_SSE_SPLAT_F(_b.cols[3], 3), _a.cols[3], zzzz);
    ret.cols[3] = _mm_add_ps(a01, a23);
  }
  return ret;
}

OZZ_INLINE ozz::math::Float4x4 operator+(const ozz::math::Float4x4& _a,
                                         const ozz::math::Float4x4& _b) {
  const ozz::math::Float4x4 ret = {
      {_mm_add_ps(_a.cols[0], _b.cols[0]), _mm_add_ps(_a.cols[1], _b.cols[1]),
       _mm_add_ps(_a.cols[2], _b.cols[2]), _mm_add_ps(_a.cols[3], _b.cols[3])}};
  return ret;
}

OZZ_INLINE ozz::math::Float4x4 operator-(const ozz::math::Float4x4& _a,
                                         const ozz::math::Float4x4& _b) {
  const ozz::math::Float4x4 ret = {
      {_mm_sub_ps(_a.cols[0], _b.cols[0]), _mm_sub_ps(_a.cols[1], _b.cols[1]),
       _mm_sub_ps(_a.cols[2], _b.cols[2]), _mm_sub_ps(_a.cols[3], _b.cols[3])}};
  return ret;
}
}  // namespace math
}  // namespace ozz

#if !defined(OZZ_DISABLE_SSE_NATIVE_OPERATORS)
OZZ_INLINE ozz::math::SimdFloat4 operator+(ozz::math::_SimdFloat4 _a,
                                           ozz::math::_SimdFloat4 _b) {
  return _mm_add_ps(_a, _b);
}

OZZ_INLINE ozz::math::SimdFloat4 operator-(ozz::math::_SimdFloat4 _a,
                                           ozz::math::_SimdFloat4 _b) {
  return _mm_sub_ps(_a, _b);
}

OZZ_INLINE ozz::math::SimdFloat4 operator-(ozz::math::_SimdFloat4 _v) {
  return _mm_sub_ps(_mm_setzero_ps(), _v);
}

OZZ_INLINE ozz::math::SimdFloat4 operator*(ozz::math::_SimdFloat4 _a,
                                           ozz::math::_SimdFloat4 _b) {
  return _mm_mul_ps(_a, _b);
}

OZZ_INLINE ozz::math::SimdFloat4 operator/(ozz::math::_SimdFloat4 _a,
                                           ozz::math::_SimdFloat4 _b) {
  return _mm_div_ps(_a, _b);
}
#endif  // !defined(OZZ_DISABLE_SSE_NATIVE_OPERATORS)

namespace ozz {
namespace math {
OZZ_INLINE uint16_t FloatToHalf(float _f) {
  const int h = _mm_cvtsi128_si32(FloatToHalf(_mm_set1_ps(_f)));
  return static_cast<uint16_t>(h);
}

OZZ_INLINE float HalfToFloat(uint16_t _h) {
  return _mm_cvtss_f32(HalfToFloat(_mm_set1_epi32(_h)));
}

// Half <-> Float implementation is based on:
// http://fgiesen.wordpress.com/2012/03/28/half-to-float-done-quic/.
inline SimdInt4 FloatToHalf(_SimdFloat4 _f) {
  const __m128i mask_sign = _mm_set1_epi32(0x80000000u);
  const __m128i mask_round = _mm_set1_epi32(~0xfffu);
  const __m128i f32infty = _mm_set1_epi32(255 << 23);
  const __m128 magic = _mm_castsi128_ps(_mm_set1_epi32(15 << 23));
  const __m128i nanbit = _mm_set1_epi32(0x200);
  const __m128i infty_as_fp16 = _mm_set1_epi32(0x7c00);
  const __m128 clamp = _mm_castsi128_ps(_mm_set1_epi32((31 << 23) - 0x1000));

  const __m128 msign = _mm_castsi128_ps(mask_sign);
  const __m128 justsign = _mm_and_ps(msign, _f);
  const __m128 absf = _mm_xor_ps(_f, justsign);
  const __m128 mround = _mm_castsi128_ps(mask_round);
  const __m128i absf_int = _mm_castps_si128(absf);
  const __m128i b_isnan = _mm_cmpgt_epi32(absf_int, f32infty);
  const __m128i b_isnormal = _mm_cmpgt_epi32(f32infty, _mm_castps_si128(absf));
  const __m128i inf_or_nan =
      _mm_or_si128(_mm_and_si128(b_isnan, nanbit), infty_as_fp16);
  const __m128 fnosticky = _mm_and_ps(absf, mround);
  const __m128 scaled = _mm_mul_ps(fnosticky, magic);
  // Logically, we want PMINSD on "biased", but this should gen better code
  const __m128 clamped = _mm_min_ps(scaled, clamp);
  const __m128i biased =
      _mm_sub_epi32(_mm_castps_si128(clamped), _mm_castps_si128(mround));
  const __m128i shifted = _mm_srli_epi32(biased, 13);
  const __m128i normal = _mm_and_si128(shifted, b_isnormal);
  const __m128i not_normal = _mm_andnot_si128(b_isnormal, inf_or_nan);
  const __m128i joined = _mm_or_si128(normal, not_normal);

  const __m128i sign_shift = _mm_srli_epi32(_mm_castps_si128(justsign), 16);
  return _mm_or_si128(joined, sign_shift);
}

OZZ_INLINE SimdFloat4 HalfToFloat(_SimdInt4 _h) {
  const __m128i mask_nosign = _mm_set1_epi32(0x7fff);
  const __m128 magic = _mm_castsi128_ps(_mm_set1_epi32((254 - 15) << 23));
  const __m128i was_infnan = _mm_set1_epi32(0x7bff);
  const __m128 exp_infnan = _mm_castsi128_ps(_mm_set1_epi32(255 << 23));

  const __m128i expmant = _mm_and_si128(mask_nosign, _h);
  const __m128i shifted = _mm_slli_epi32(expmant, 13);
  const __m128 scaled = _mm_mul_ps(_mm_castsi128_ps(shifted), magic);
  const __m128i b_wasinfnan = _mm_cmpgt_epi32(expmant, was_infnan);
  const __m128i sign = _mm_slli_epi32(_mm_xor_si128(_h, expmant), 16);
  const __m128 infnanexp =
      _mm_and_ps(_mm_castsi128_ps(b_wasinfnan), exp_infnan);
  const __m128 sign_inf = _mm_or_ps(_mm_castsi128_ps(sign), infnanexp);
  return _mm_or_ps(scaled, sign_inf);
}
}  // namespace math
}  // namespace ozz

#undef OZZ_SHUFFLE_PS1
#undef OZZ_SSE_SPLAT_F
#undef OZZ_SSE_HADD2_F
#undef OZZ_SSE_HADD3_F
#undef OZZ_SSE_HADD4_F
#undef OZZ_SSE_DOT2_F
#undef OZZ_SSE_DOT3_F
#undef OZZ_SSE_DOT4_F
#undef OZZ_MADD
#undef OZZ_MSUB
#undef OZZ_NMADD
#undef OZZ_NMSUB
#undef OZZ_MADDX
#undef OZZ_MSUBX
#undef OZZ_NMADDX
#undef OZZ_NMSUBX
#undef OZZ_SSE_SELECT_F
#undef OZZ_SSE_SPLAT_I
#undef OZZ_SSE_SELECT_I
#endif  // OZZ_OZZ_BASE_MATHS_INTERNAL_SIMD_MATH_SSE_INL_H_
/**** ended inlining ozz/base/maths/internal/simd_math_sse-inl.h ****/
#elif defined(OZZ_SIMD_REF)
/**** start inlining ozz/base/maths/internal/simd_math_ref-inl.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_MATHS_INTERNAL_SIMD_MATH_REF_INL_H_
#define OZZ_OZZ_BASE_MATHS_INTERNAL_SIMD_MATH_REF_INL_H_

// SIMD refence implementation, based on scalar floats.

#include <stdint.h>

#include <cassert>
#include <cmath>
#include <cstddef>

/**** skipping file: ozz/base/maths/math_constant.h ****/

namespace ozz {
namespace math {

namespace internal {
// Defines union cast helpers that are used internally for binary logical
// operations.
union SimdFI4 {
  SimdFloat4 f;
  SimdInt4 i;
};
union SimdIF4 {
  SimdInt4 i;
  SimdFloat4 f;
};
}  // namespace internal

#define OZZ_RCP_EST(_in, _out)                 \
  do {                                         \
    const float in = _in;                      \
    const union {                              \
      float f;                                 \
      int i;                                   \
    } uf = {in};                               \
    const union {                              \
      int i;                                   \
      float f;                                 \
    } ui = {(0x3f800000 * 2) - uf.i};          \
    const float fp = ui.f * (2.f - in * ui.f); \
    _out = fp * (2.f - in * fp);               \
  } while (void(0), 0)

#define OZZ_RCP_EST_NR(_in, _out)   \
  do {                              \
    float fp2;                      \
    OZZ_RCP_EST(_in, fp2);          \
    _out = fp2 * (2.f - _in * fp2); \
  } while (void(0), 0)

#define OZZ_RSQRT_EST(_in, _out)                               \
  do {                                                         \
    const float in = _in;                                      \
    union {                                                    \
      float f;                                                 \
      int i;                                                   \
    } uf = {in};                                               \
    union {                                                    \
      int i;                                                   \
      float f;                                                 \
    } ui = {0x5f3759df - (uf.i / 2)};                          \
    const float fp = ui.f * (1.5f - (in * .5f * ui.f * ui.f)); \
    _out = fp * (1.5f - (in * .5f * fp * fp));                 \
  } while (void(0), 0)

#define OZZ_RSQRT_EST_NR(_in, _out)                \
  do {                                             \
    float fp2;                                     \
    OZZ_RSQRT_EST(_in, fp2);                       \
    _out = fp2 * (1.5f - (_in * .5f * fp2 * fp2)); \
  } while (void(0), 0)

namespace simd_float4 {

OZZ_INLINE SimdFloat4 zero() {
  const SimdFloat4 ret = {0.f, 0.f, 0.f, 0.f};
  return ret;
}

OZZ_INLINE SimdFloat4 one() {
  const SimdFloat4 ret = {1.f, 1.f, 1.f, 1.f};
  return ret;
}

OZZ_INLINE SimdFloat4 x_axis() {
  const SimdFloat4 ret = {1.f, 0.f, 0.f, 0.f};
  return ret;
}

OZZ_INLINE SimdFloat4 y_axis() {
  const SimdFloat4 ret = {0.f, 1.f, 0.f, 0.f};
  return ret;
}

OZZ_INLINE SimdFloat4 z_axis() {
  const SimdFloat4 ret = {0.f, 0.f, 1.f, 0.f};
  return ret;
}

OZZ_INLINE SimdFloat4 w_axis() {
  const SimdFloat4 ret = {0.f, 0.f, 0.f, 1.f};
  return ret;
}

OZZ_INLINE SimdFloat4 Load(float _x, float _y, float _z, float _w) {
  const SimdFloat4 ret = {_x, _y, _z, _w};
  return ret;
}

OZZ_INLINE SimdFloat4 LoadX(float _x) {
  const SimdFloat4 ret = {_x, 0.f, 0.f, 0.f};
  return ret;
}

OZZ_INLINE SimdFloat4 Load1(float _x) {
  const SimdFloat4 ret = {_x, _x, _x, _x};
  return ret;
}

OZZ_INLINE SimdFloat4 LoadPtr(const float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0xf) && "Invalid alignment");
  const SimdFloat4 ret = {_f[0], _f[1], _f[2], _f[3]};
  return ret;
}

OZZ_INLINE SimdFloat4 LoadPtrU(const float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  const SimdFloat4 ret = {_f[0], _f[1], _f[2], _f[3]};
  return ret;
}

OZZ_INLINE SimdFloat4 LoadXPtrU(const float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  const SimdFloat4 ret = {*_f, 0.f, 0.f, 0.f};
  return ret;
}

OZZ_INLINE SimdFloat4 Load1PtrU(const float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  const SimdFloat4 ret = {*_f, *_f, *_f, *_f};
  return ret;
}

OZZ_INLINE SimdFloat4 Load2PtrU(const float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  const SimdFloat4 ret = {_f[0], _f[1], 0.f, 0.f};
  return ret;
}

OZZ_INLINE SimdFloat4 Load3PtrU(const float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  const SimdFloat4 ret = {_f[0], _f[1], _f[2]};
  return ret;
}

OZZ_INLINE SimdFloat4 FromInt(_SimdInt4 _i) {
  const SimdFloat4 ret = {static_cast<float>(_i.x), static_cast<float>(_i.y),
                          static_cast<float>(_i.z), static_cast<float>(_i.w)};
  return ret;
}
}  // namespace simd_float4

OZZ_INLINE float GetX(_SimdFloat4 _v) { return _v.x; }

OZZ_INLINE float GetY(_SimdFloat4 _v) { return _v.y; }

OZZ_INLINE float GetZ(_SimdFloat4 _v) { return _v.z; }

OZZ_INLINE float GetW(_SimdFloat4 _v) { return _v.w; }
OZZ_INLINE SimdFloat4 SetX(_SimdFloat4 _v, _SimdFloat4 _f) {
  const SimdFloat4 ret = {_f.x, _v.y, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 SetY(_SimdFloat4 _v, _SimdFloat4 _f) {
  const SimdFloat4 ret = {_v.x, _f.x, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 SetZ(_SimdFloat4 _v, _SimdFloat4 _f) {
  const SimdFloat4 ret = {_v.x, _v.y, _f.x, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 SetW(_SimdFloat4 _v, _SimdFloat4 _f) {
  const SimdFloat4 ret = {_v.x, _v.y, _v.z, _f.x};
  return ret;
}

OZZ_INLINE SimdFloat4 SetI(_SimdFloat4 _v, _SimdFloat4 _f, int _ith) {
  assert(_ith >= 0 && _ith <= 3 && "Invalid index, out of range.");
  SimdFloat4 ret = _v;
  (&ret.x)[_ith] = _f.x;
  return ret;
}

OZZ_INLINE void StorePtr(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0xf) && "Invalid alignment");
  _f[0] = _v.x;
  _f[1] = _v.y;
  _f[2] = _v.z;
  _f[3] = _v.w;
}

OZZ_INLINE void Store1Ptr(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0xf) && "Invalid alignment");
  _f[0] = _v.x;
}

OZZ_INLINE void Store2Ptr(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0xf) && "Invalid alignment");
  _f[0] = _v.x;
  _f[1] = _v.y;
}

OZZ_INLINE void Store3Ptr(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0xf) && "Invalid alignment");
  _f[0] = _v.x;
  _f[1] = _v.y;
  _f[2] = _v.z;
}

OZZ_INLINE void StorePtrU(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  _f[0] = _v.x;
  _f[1] = _v.y;
  _f[2] = _v.z;
  _f[3] = _v.w;
}

OZZ_INLINE void Store1PtrU(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  _f[0] = _v.x;
}

OZZ_INLINE void Store2PtrU(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  _f[0] = _v.x;
  _f[1] = _v.y;
}

OZZ_INLINE void Store3PtrU(_SimdFloat4 _v, float* _f) {
  assert(!(reinterpret_cast<uintptr_t>(_f) & 0x3) && "Invalid alignment");
  _f[0] = _v.x;
  _f[1] = _v.y;
  _f[2] = _v.z;
}

OZZ_INLINE SimdFloat4 SplatX(_SimdFloat4 _v) {
  const SimdFloat4 ret = {_v.x, _v.x, _v.x, _v.x};
  return ret;
}

OZZ_INLINE SimdFloat4 SplatY(_SimdFloat4 _v) {
  const SimdFloat4 ret = {_v.y, _v.y, _v.y, _v.y};
  return ret;
}

OZZ_INLINE SimdFloat4 SplatZ(_SimdFloat4 _v) {
  const SimdFloat4 ret = {_v.z, _v.z, _v.z, _v.z};
  return ret;
}

OZZ_INLINE SimdFloat4 SplatW(_SimdFloat4 _v) {
  const SimdFloat4 ret = {_v.w, _v.w, _v.w, _v.w};
  return ret;
}

template <size_t _X, size_t _Y, size_t _Z, size_t _W>
OZZ_INLINE SimdFloat4 Swizzle(_SimdFloat4 _v) {
  static_assert(_X <= 3 && _Y <= 3 && _Z <= 3 && _W <= 3,
                "Indices must be between 0 and 3");
  const float* pf = &_v.x;
  const SimdFloat4 ret = {pf[_X], pf[_Y], pf[_Z], pf[_W]};
  return ret;
}

OZZ_INLINE void Transpose4x1(const SimdFloat4 _in[4], SimdFloat4 _out[1]) {
  _out[0].x = _in[0].x;
  _out[0].y = _in[1].x;
  _out[0].z = _in[2].x;
  _out[0].w = _in[3].x;
}

OZZ_INLINE void Transpose1x4(const SimdFloat4 _in[1], SimdFloat4 _out[4]) {
  _out[0].x = _in[0].x;
  _out[0].y = _out[0].z = _out[0].w = 0.f;
  _out[1].x = _in[0].y;
  _out[1].y = _out[1].z = _out[1].w = 0.f;
  _out[2].x = _in[0].z;
  _out[2].y = _out[2].z = _out[2].w = 0.f;
  _out[3].x = _in[0].w;
  _out[3].y = _out[3].z = _out[3].w = 0.f;
}

OZZ_INLINE void Transpose4x2(const SimdFloat4 _in[4], SimdFloat4 _out[2]) {
  _out[0].x = _in[0].x;
  _out[0].y = _in[1].x;
  _out[0].z = _in[2].x;
  _out[0].w = _in[3].x;
  _out[1].x = _in[0].y;
  _out[1].y = _in[1].y;
  _out[1].z = _in[2].y;
  _out[1].w = _in[3].y;
}

OZZ_INLINE void Transpose2x4(const SimdFloat4 _in[2], SimdFloat4 _out[4]) {
  _out[0].x = _in[0].x;
  _out[0].y = _in[1].x;
  _out[0].z = _out[0].w = 0.f;
  _out[1].x = _in[0].y;
  _out[1].y = _in[1].y;
  _out[1].z = _out[1].w = 0.f;
  _out[2].x = _in[0].z;
  _out[2].y = _in[1].z;
  _out[2].z = _out[2].w = 0.f;
  _out[3].x = _in[0].w;
  _out[3].y = _in[1].w;
  _out[3].z = _out[3].w = 0.f;
}

OZZ_INLINE void Transpose4x3(const SimdFloat4 _in[4], SimdFloat4 _out[3]) {
  _out[0].x = _in[0].x;
  _out[0].y = _in[1].x;
  _out[0].z = _in[2].x;
  _out[0].w = _in[3].x;
  _out[1].x = _in[0].y;
  _out[1].y = _in[1].y;
  _out[1].z = _in[2].y;
  _out[1].w = _in[3].y;
  _out[2].x = _in[0].z;
  _out[2].y = _in[1].z;
  _out[2].z = _in[2].z;
  _out[2].w = _in[3].z;
}

OZZ_INLINE void Transpose3x4(const SimdFloat4 _in[3], SimdFloat4 _out[4]) {
  _out[0].x = _in[0].x;
  _out[0].y = _in[1].x;
  _out[0].z = _in[2].x;
  _out[0].w = 0.f;
  _out[1].x = _in[0].y;
  _out[1].y = _in[1].y;
  _out[1].z = _in[2].y;
  _out[1].w = 0.f;
  _out[2].x = _in[0].z;
  _out[2].y = _in[1].z;
  _out[2].z = _in[2].z;
  _out[2].w = 0.f;
  _out[3].x = _in[0].w;
  _out[3].y = _in[1].w;
  _out[3].z = _in[2].w;
  _out[3].w = 0.f;
}

OZZ_INLINE void Transpose4x4(const SimdFloat4 _in[4], SimdFloat4 _out[4]) {
  _out[0].x = _in[0].x;
  _out[1].x = _in[0].y;
  _out[2].x = _in[0].z;
  _out[3].x = _in[0].w;
  _out[0].y = _in[1].x;
  _out[1].y = _in[1].y;
  _out[2].y = _in[1].z;
  _out[3].y = _in[1].w;
  _out[0].z = _in[2].x;
  _out[1].z = _in[2].y;
  _out[2].z = _in[2].z;
  _out[3].z = _in[2].w;
  _out[0].w = _in[3].x;
  _out[1].w = _in[3].y;
  _out[2].w = _in[3].z;
  _out[3].w = _in[3].w;
}

OZZ_INLINE void Transpose16x16(const SimdFloat4 _in[16], SimdFloat4 _out[16]) {
  for (int i = 0; i < 4; ++i) {
    const int i4 = i * 4;
    _out[i4 + 0].x = *(&_in[0].x + i);
    _out[i4 + 0].y = *(&_in[1].x + i);
    _out[i4 + 0].z = *(&_in[2].x + i);
    _out[i4 + 0].w = *(&_in[3].x + i);
    _out[i4 + 1].x = *(&_in[4].x + i);
    _out[i4 + 1].y = *(&_in[5].x + i);
    _out[i4 + 1].z = *(&_in[6].x + i);
    _out[i4 + 1].w = *(&_in[7].x + i);
    _out[i4 + 2].x = *(&_in[8].x + i);
    _out[i4 + 2].y = *(&_in[9].x + i);
    _out[i4 + 2].z = *(&_in[10].x + i);
    _out[i4 + 2].w = *(&_in[11].x + i);
    _out[i4 + 3].x = *(&_in[12].x + i);
    _out[i4 + 3].y = *(&_in[13].x + i);
    _out[i4 + 3].z = *(&_in[14].x + i);
    _out[i4 + 3].w = *(&_in[15].x + i);
  }
}

OZZ_INLINE SimdFloat4 MAdd(_SimdFloat4 _a, _SimdFloat4 _b, _SimdFloat4 _c) {
  const SimdFloat4 ret = {_a.x * _b.x + _c.x, _a.y * _b.y + _c.y,
                          _a.z * _b.z + _c.z, _a.w * _b.w + _c.w};
  return ret;
}

OZZ_INLINE SimdFloat4 MSub(_SimdFloat4 _a, _SimdFloat4 _b, _SimdFloat4 _c) {
  const SimdFloat4 ret = {_a.x * _b.x - _c.x, _a.y * _b.y - _c.y,
                          _a.z * _b.z - _c.z, _a.w * _b.w - _c.w};
  return ret;
}

OZZ_INLINE SimdFloat4 NMAdd(_SimdFloat4 _a, _SimdFloat4 _b, _SimdFloat4 _c) {
  const SimdFloat4 ret = {_c.x - _a.x * _b.x, _c.y - _a.y * _b.y,
                          _c.z - _a.z * _b.z, _c.w - _a.w * _b.w};
  return ret;
}

OZZ_INLINE SimdFloat4 NMSub(_SimdFloat4 _a, _SimdFloat4 _b, _SimdFloat4 _c) {
  const SimdFloat4 ret = {-_a.x * _b.x - _c.x, -_a.y * _b.y - _c.y,
                          -_a.z * _b.z - _c.z, -_a.w * _b.w - _c.w};
  return ret;
}

OZZ_INLINE SimdFloat4 DivX(_SimdFloat4 _a, _SimdFloat4 _b) {
  const SimdFloat4 ret = {_a.x / _b.x, _a.y, _a.z, _a.w};
  return ret;
}

OZZ_INLINE SimdFloat4 HAdd2(_SimdFloat4 _v) {
  const SimdFloat4 ret = {_v.x + _v.y, _v.y, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 HAdd3(_SimdFloat4 _v) {
  const SimdFloat4 ret = {_v.x + _v.y + _v.z, _v.y, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 HAdd4(_SimdFloat4 _v) {
  const SimdFloat4 ret = {_v.x + _v.y + _v.z + _v.w, _v.x, _v.x, _v.x};
  return ret;
}

OZZ_INLINE SimdFloat4 Dot2(_SimdFloat4 _a, _SimdFloat4 _b) {
  const SimdFloat4 ret = {_a.x * _b.x + _a.y * _b.y, _a.x, _a.x, _a.x};
  return ret;
}

OZZ_INLINE SimdFloat4 Dot3(_SimdFloat4 _a, _SimdFloat4 _b) {
  const SimdFloat4 ret = {_a.x * _b.x + _a.y * _b.y + _a.z * _b.z, _a.x, _a.x,
                          _a.x};
  return ret;
}

OZZ_INLINE SimdFloat4 Dot4(_SimdFloat4 _a, _SimdFloat4 _b) {
  const SimdFloat4 ret = {_a.x * _b.x + _a.y * _b.y + _a.z * _b.z + _a.w * _b.w,
                          _a.x, _a.x, _a.x};
  return ret;
}

OZZ_INLINE SimdFloat4 Cross3(_SimdFloat4 _a, _SimdFloat4 _b) {
  const SimdFloat4 ret = {_a.y * _b.z - _a.z * _b.y, _a.z * _b.x - _a.x * _b.z,
                          _a.x * _b.y - _a.y * _b.x, _a.x};
  return ret;
}

OZZ_INLINE SimdFloat4 RcpEst(_SimdFloat4 _v) {
  SimdFloat4 ret;
  OZZ_RCP_EST(_v.x, ret.x);
  OZZ_RCP_EST(_v.y, ret.y);
  OZZ_RCP_EST(_v.z, ret.z);
  OZZ_RCP_EST(_v.w, ret.w);
  return ret;
}

OZZ_INLINE SimdFloat4 RcpEstNR(_SimdFloat4 _v) {
  SimdFloat4 ret;
  OZZ_RCP_EST_NR(_v.x, ret.x);
  OZZ_RCP_EST_NR(_v.y, ret.y);
  OZZ_RCP_EST_NR(_v.z, ret.z);
  OZZ_RCP_EST_NR(_v.w, ret.w);
  return ret;
}

OZZ_INLINE SimdFloat4 RcpEstX(_SimdFloat4 _v) {
  SimdFloat4 ret;
  OZZ_RCP_EST(_v.x, ret.x);
  ret.y = _v.y;
  ret.z = _v.z;
  ret.w = _v.w;
  return ret;
}

OZZ_INLINE SimdFloat4 RcpEstXNR(_SimdFloat4 _v) {
  SimdFloat4 ret;
  OZZ_RCP_EST(_v.x, ret.x);
  ret.y = _v.x;
  ret.z = _v.x;
  ret.w = _v.x;
  return ret;
}

OZZ_INLINE SimdFloat4 Sqrt(_SimdFloat4 _v) {
  const SimdFloat4 ret = {std::sqrt(_v.x), std::sqrt(_v.y), std::sqrt(_v.z),
                          std::sqrt(_v.w)};
  return ret;
}

OZZ_INLINE SimdFloat4 SqrtX(_SimdFloat4 _v) {
  const SimdFloat4 ret = {std::sqrt(_v.x), _v.y, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 RSqrtEst(_SimdFloat4 _v) {
  SimdFloat4 ret;
  OZZ_RSQRT_EST(_v.x, ret.x);
  OZZ_RSQRT_EST(_v.y, ret.y);
  OZZ_RSQRT_EST(_v.z, ret.z);
  OZZ_RSQRT_EST(_v.w, ret.w);
  return ret;
}

OZZ_INLINE SimdFloat4 RSqrtEstNR(_SimdFloat4 _v) {
  SimdFloat4 ret;
  OZZ_RSQRT_EST_NR(_v.x, ret.x);
  OZZ_RSQRT_EST_NR(_v.y, ret.y);
  OZZ_RSQRT_EST_NR(_v.z, ret.z);
  OZZ_RSQRT_EST_NR(_v.w, ret.w);
  return ret;
}

OZZ_INLINE SimdFloat4 RSqrtEstX(_SimdFloat4 _v) {
  SimdFloat4 ret;
  OZZ_RSQRT_EST(_v.x, ret.x);
  ret.y = _v.y;
  ret.z = _v.z;
  ret.w = _v.w;
  return ret;
}

OZZ_INLINE SimdFloat4 RSqrtEstXNR(_SimdFloat4 _v) {
  SimdFloat4 ret;
  OZZ_RSQRT_EST(_v.x, ret.x);
  ret.y = _v.x;
  ret.z = _v.x;
  ret.w = _v.x;
  return ret;
}

OZZ_INLINE SimdFloat4 Abs(_SimdFloat4 _v) {
  const SimdFloat4 ret = {std::abs(_v.x), std::abs(_v.y), std::abs(_v.z),
                          std::abs(_v.w)};
  return ret;
}

OZZ_INLINE SimdInt4 Sign(_SimdFloat4 _v) {
  internal::SimdFI4 fi = {_v};
  const SimdInt4 ret = {fi.i.x & static_cast<int>(0x80000000),
                        fi.i.y & static_cast<int>(0x80000000),
                        fi.i.z & static_cast<int>(0x80000000),
                        fi.i.w & static_cast<int>(0x80000000)};
  return ret;
}

OZZ_INLINE SimdFloat4 Length2(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y;
  const SimdFloat4 ret = {std::sqrt(sq_len), _v.x, _v.x, _v.x};
  return ret;
}

OZZ_INLINE SimdFloat4 Length3(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  const SimdFloat4 ret = {std::sqrt(sq_len), _v.x, _v.x, _v.x};
  return ret;
}

OZZ_INLINE SimdFloat4 Length4(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  const SimdFloat4 ret = {std::sqrt(sq_len), _v.x, _v.x, _v.x};
  return ret;
}

OZZ_INLINE SimdFloat4 Length2Sqr(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y;
  const SimdFloat4 ret = {sq_len, _v.x, _v.x, _v.x};
  return ret;
}

OZZ_INLINE SimdFloat4 Length3Sqr(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  const SimdFloat4 ret = {sq_len, _v.x, _v.x, _v.x};
  return ret;
}

OZZ_INLINE SimdFloat4 Length4Sqr(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  const SimdFloat4 ret = {sq_len, _v.x, _v.x, _v.x};
  return ret;
}

OZZ_INLINE SimdFloat4 Normalize2(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y;
  assert(sq_len != 0.f && "_v is not normalizable");
  const float inv_len = 1.f / std::sqrt(sq_len);
  const SimdFloat4 ret = {_v.x * inv_len, _v.y * inv_len, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 Normalize3(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  assert(sq_len != 0.f && "_v is not normalizable");
  const float inv_len = 1.f / std::sqrt(sq_len);
  const SimdFloat4 ret = {_v.x * inv_len, _v.y * inv_len, _v.z * inv_len, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 Normalize4(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  assert(sq_len != 0.f && "_v is not normalizable");
  const float inv_len = 1.f / std::sqrt(sq_len);
  const SimdFloat4 ret = {_v.x * inv_len, _v.y * inv_len, _v.z * inv_len,
                          _v.w * inv_len};
  return ret;
}

OZZ_INLINE SimdFloat4 NormalizeEst2(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y;
  assert(sq_len != 0.f && "_v is not normalizable");
  float inv_len;
  OZZ_RSQRT_EST(sq_len, inv_len);
  const SimdFloat4 ret = {_v.x * inv_len, _v.y * inv_len, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 NormalizeEst3(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  assert(sq_len != 0.f && "_v is not normalizable");
  float inv_len;
  OZZ_RSQRT_EST(sq_len, inv_len);
  const SimdFloat4 ret = {_v.x * inv_len, _v.y * inv_len, _v.z * inv_len, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 NormalizeEst4(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  assert(sq_len != 0.f && "_v is not normalizable");
  float inv_len;
  OZZ_RSQRT_EST(sq_len, inv_len);
  const SimdFloat4 ret = {_v.x * inv_len, _v.y * inv_len, _v.z * inv_len,
                          _v.w * inv_len};
  return ret;
}

OZZ_INLINE SimdInt4 IsNormalized2(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y;
  const bool normalized = std::abs(sq_len - 1.f) < kNormalizationToleranceSq;
  const SimdInt4 ret = {-static_cast<int>(normalized), 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 IsNormalized3(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  const bool normalized = std::abs(sq_len - 1.f) < kNormalizationToleranceSq;
  const SimdInt4 ret = {-static_cast<int>(normalized), 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 IsNormalized4(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  const bool normalized = std::abs(sq_len - 1.f) < kNormalizationToleranceSq;
  const SimdInt4 ret = {-static_cast<int>(normalized), 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 IsNormalizedEst2(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y;
  const bool normalized = std::abs(sq_len - 1.f) < kNormalizationToleranceEstSq;
  const SimdInt4 ret = {-static_cast<int>(normalized), 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 IsNormalizedEst3(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  const bool normalized = std::abs(sq_len - 1.f) < kNormalizationToleranceEstSq;
  const SimdInt4 ret = {-static_cast<int>(normalized), 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 IsNormalizedEst4(_SimdFloat4 _v) {
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  const bool normalized = std::abs(sq_len - 1.f) < kNormalizationToleranceEstSq;
  const SimdInt4 ret = {-static_cast<int>(normalized), 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdFloat4 NormalizeSafe2(_SimdFloat4 _v, _SimdFloat4 _safe) {
  // assert(AreAllTrue1(IsNormalized2(_safe)) && "_safe is not normalized");
  const float sq_len = _v.x * _v.x + _v.y * _v.y;
  if (sq_len == 0.f) {
    const SimdFloat4 ret = {_safe.x, _safe.y, _v.z, _v.w};
    return ret;
  }
  const float inv_len = 1.f / std::sqrt(sq_len);
  const SimdFloat4 ret = {_v.x * inv_len, _v.y * inv_len, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 NormalizeSafe3(_SimdFloat4 _v, _SimdFloat4 _safe) {
  // assert(AreAllTrue1(IsNormalized3(_safe)) && "_safe is not normalized");
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  if (sq_len == 0.f) {
    const SimdFloat4 ret = {_safe.x, _safe.y, _safe.z, _v.w};
    return ret;
  }
  const float inv_len = 1.f / std::sqrt(sq_len);
  const SimdFloat4 ret = {_v.x * inv_len, _v.y * inv_len, _v.z * inv_len, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 NormalizeSafe4(_SimdFloat4 _v, _SimdFloat4 _safe) {
  // assert(AreAllTrue1(IsNormalized4(_safe)) && "_safe is not normalized");
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  if (sq_len == 0.f) {
    return _safe;
  }
  const float inv_len = 1.f / std::sqrt(sq_len);
  const SimdFloat4 ret = {_v.x * inv_len, _v.y * inv_len, _v.z * inv_len,
                          _v.w * inv_len};
  return ret;
}

OZZ_INLINE SimdFloat4 NormalizeSafeEst2(_SimdFloat4 _v, _SimdFloat4 _safe) {
  // assert(AreAllTrue1(IsNormalizedEst2(_safe)) && "_safe is not normalized");
  const float sq_len = _v.x * _v.x + _v.y * _v.y;
  if (sq_len == 0.f) {
    const SimdFloat4 ret = {_safe.x, _safe.y, _v.z, _v.w};
    return ret;
  }
  float inv_len;
  OZZ_RSQRT_EST(sq_len, inv_len);
  const SimdFloat4 ret = {_v.x * inv_len, _v.y * inv_len, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 NormalizeSafeEst3(_SimdFloat4 _v, _SimdFloat4 _safe) {
  // assert(AreAllTrue1(IsNormalizedEst3(_safe)) && "_safe is not normalized");
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  if (sq_len == 0.f) {
    const SimdFloat4 ret = {_safe.x, _safe.y, _safe.z, _v.w};
    return ret;
  }
  float inv_len;
  OZZ_RSQRT_EST(sq_len, inv_len);
  const SimdFloat4 ret = {_v.x * inv_len, _v.y * inv_len, _v.z * inv_len, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 NormalizeSafeEst4(_SimdFloat4 _v, _SimdFloat4 _safe) {
  // assert(AreAllTrue1(IsNormalizedEst4(_safe)) && "_safe is not normalized");
  const float sq_len = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  if (sq_len == 0.f) {
    return _safe;
  }
  float inv_len;
  OZZ_RSQRT_EST(sq_len, inv_len);
  const SimdFloat4 ret = {_v.x * inv_len, _v.y * inv_len, _v.z * inv_len,
                          _v.w * inv_len};
  return ret;
}

OZZ_INLINE SimdFloat4 Lerp(_SimdFloat4 _a, _SimdFloat4 _b, _SimdFloat4 _alpha) {
  const SimdFloat4 ret = {
      (_b.x - _a.x) * _alpha.x + _a.x, (_b.y - _a.y) * _alpha.y + _a.y,
      (_b.z - _a.z) * _alpha.z + _a.z, (_b.w - _a.w) * _alpha.w + _a.w};
  return ret;
}

OZZ_INLINE SimdFloat4 Min(_SimdFloat4 _a, _SimdFloat4 _b) {
  const SimdFloat4 ret = {_a.x < _b.x ? _a.x : _b.x, _a.y < _b.y ? _a.y : _b.y,
                          _a.z < _b.z ? _a.z : _b.z, _a.w < _b.w ? _a.w : _b.w};
  return ret;
}

OZZ_INLINE SimdFloat4 Max(_SimdFloat4 _a, _SimdFloat4 _b) {
  const SimdFloat4 ret = {_a.x > _b.x ? _a.x : _b.x, _a.y > _b.y ? _a.y : _b.y,
                          _a.z > _b.z ? _a.z : _b.z, _a.w > _b.w ? _a.w : _b.w};
  return ret;
}

OZZ_INLINE SimdFloat4 Min0(_SimdFloat4 _v) {
  const SimdFloat4 ret = {_v.x < 0.f ? _v.x : 0.f, _v.y < 0.f ? _v.y : 0.f,
                          _v.z < 0.f ? _v.z : 0.f, _v.w < 0.f ? _v.w : 0.f};
  return ret;
}

OZZ_INLINE SimdFloat4 Max0(_SimdFloat4 _v) {
  const SimdFloat4 ret = {_v.x > 0.f ? _v.x : 0.f, _v.y > 0.f ? _v.y : 0.f,
                          _v.z > 0.f ? _v.z : 0.f, _v.w > 0.f ? _v.w : 0.f};
  return ret;
}

OZZ_INLINE SimdFloat4 Clamp(_SimdFloat4 _a, _SimdFloat4 _v, _SimdFloat4 _b) {
  const SimdFloat4 min = {_v.x < _b.x ? _v.x : _b.x, _v.y < _b.y ? _v.y : _b.y,
                          _v.z < _b.z ? _v.z : _b.z, _v.w < _b.w ? _v.w : _b.w};
  const SimdFloat4 r = {
      _a.x > min.x ? _a.x : min.x, _a.y > min.y ? _a.y : min.y,
      _a.z > min.z ? _a.z : min.z, _a.w > min.w ? _a.w : min.w};
  return r;
}

OZZ_INLINE SimdFloat4 Select(_SimdInt4 _b, _SimdFloat4 _true,
                             _SimdFloat4 _false) {
  using internal::SimdFI4;
  using internal::SimdIF4;

  const SimdFI4 i_true = {_true};
  const SimdFI4 i_false = {_false};
  const SimdIF4 ret = {{i_false.i.x ^ (_b.x & (i_true.i.x ^ i_false.i.x)),
                        i_false.i.y ^ (_b.y & (i_true.i.y ^ i_false.i.y)),
                        i_false.i.z ^ (_b.z & (i_true.i.z ^ i_false.i.z)),
                        i_false.i.w ^ (_b.w & (i_true.i.w ^ i_false.i.w))}};
  return ret.f;
}

OZZ_INLINE SimdInt4 CmpEq(_SimdFloat4 _a, _SimdFloat4 _b) {
  const SimdInt4 ret = {
      -static_cast<int>(_a.x == _b.x), -static_cast<int>(_a.y == _b.y),
      -static_cast<int>(_a.z == _b.z), -static_cast<int>(_a.w == _b.w)};
  return ret;
}

OZZ_INLINE SimdInt4 CmpNe(_SimdFloat4 _a, _SimdFloat4 _b) {
  const SimdInt4 ret = {
      -static_cast<int>(_a.x != _b.x), -static_cast<int>(_a.y != _b.y),
      -static_cast<int>(_a.z != _b.z), -static_cast<int>(_a.w != _b.w)};
  return ret;
}

OZZ_INLINE SimdInt4 CmpLt(_SimdFloat4 _a, _SimdFloat4 _b) {
  const SimdInt4 ret = {
      -static_cast<int>(_a.x < _b.x), -static_cast<int>(_a.y < _b.y),
      -static_cast<int>(_a.z < _b.z), -static_cast<int>(_a.w < _b.w)};
  return ret;
}

OZZ_INLINE SimdInt4 CmpLe(_SimdFloat4 _a, _SimdFloat4 _b) {
  const SimdInt4 ret = {
      -static_cast<int>(_a.x <= _b.x), -static_cast<int>(_a.y <= _b.y),
      -static_cast<int>(_a.z <= _b.z), -static_cast<int>(_a.w <= _b.w)};
  return ret;
}

OZZ_INLINE SimdInt4 CmpGt(_SimdFloat4 _a, _SimdFloat4 _b) {
  const SimdInt4 ret = {
      -static_cast<int>(_a.x > _b.x), -static_cast<int>(_a.y > _b.y),
      -static_cast<int>(_a.z > _b.z), -static_cast<int>(_a.w > _b.w)};
  return ret;
}

OZZ_INLINE SimdInt4 CmpGe(_SimdFloat4 _a, _SimdFloat4 _b) {
  const SimdInt4 ret = {
      -static_cast<int>(_a.x >= _b.x), -static_cast<int>(_a.y >= _b.y),
      -static_cast<int>(_a.z >= _b.z), -static_cast<int>(_a.w >= _b.w)};
  return ret;
}

OZZ_INLINE SimdFloat4 And(_SimdFloat4 _a, _SimdFloat4 _b) {
  const internal::SimdFI4 a = {_a};
  const internal::SimdFI4 b = {_b};
  const internal::SimdIF4 ret = {
      {a.i.x & b.i.x, a.i.y & b.i.y, a.i.z & b.i.z, a.i.w & b.i.w}};
  return ret.f;
}

OZZ_INLINE SimdFloat4 Or(_SimdFloat4 _a, _SimdFloat4 _b) {
  const internal::SimdFI4 a = {_a};
  const internal::SimdFI4 b = {_b};
  const internal::SimdIF4 ret = {
      {a.i.x | b.i.x, a.i.y | b.i.y, a.i.z | b.i.z, a.i.w | b.i.w}};
  return ret.f;
}

OZZ_INLINE SimdFloat4 Xor(_SimdFloat4 _a, _SimdFloat4 _b) {
  const internal::SimdFI4 a = {_a};
  const internal::SimdFI4 b = {_b};
  const internal::SimdIF4 ret = {
      {a.i.x ^ b.i.x, a.i.y ^ b.i.y, a.i.z ^ b.i.z, a.i.w ^ b.i.w}};
  return ret.f;
}

OZZ_INLINE SimdFloat4 And(_SimdFloat4 _a, _SimdInt4 _b) {
  const internal::SimdFI4 a = {_a};
  const internal::SimdIF4 ret = {
      {a.i.x & _b.x, a.i.y & _b.y, a.i.z & _b.z, a.i.w & _b.w}};
  return ret.f;
}

OZZ_INLINE SimdFloat4 AndNot(_SimdFloat4 _a, _SimdInt4 _b) {
  const internal::SimdFI4 a = {_a};
  const internal::SimdIF4 ret = {
      {a.i.x & ~_b.x, a.i.y & ~_b.y, a.i.z & ~_b.z, a.i.w & ~_b.w}};
  return ret.f;
}

OZZ_INLINE SimdFloat4 Or(_SimdFloat4 _a, _SimdInt4 _b) {
  const internal::SimdFI4 a = {_a};
  const internal::SimdIF4 ret = {
      {a.i.x | _b.x, a.i.y | _b.y, a.i.z | _b.z, a.i.w | _b.w}};
  return ret.f;
}

OZZ_INLINE SimdFloat4 Xor(_SimdFloat4 _a, _SimdInt4 _b) {
  const internal::SimdFI4 a = {_a};
  const internal::SimdIF4 ret = {
      {a.i.x ^ _b.x, a.i.y ^ _b.y, a.i.z ^ _b.z, a.i.w ^ _b.w}};
  return ret.f;
}

OZZ_INLINE SimdFloat4 Cos(_SimdFloat4 _v) {
  const SimdFloat4 ret = {std::cos(_v.x), std::cos(_v.y), std::cos(_v.z),
                          std::cos(_v.w)};
  return ret;
}

OZZ_INLINE SimdFloat4 CosX(_SimdFloat4 _v) {
  const SimdFloat4 ret = {std::cos(_v.x), _v.y, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 ACos(_SimdFloat4 _v) {
  const SimdFloat4 ret = {std::acos(_v.x), std::acos(_v.y), std::acos(_v.z),
                          std::acos(_v.w)};
  return ret;
}

OZZ_INLINE SimdFloat4 ACosX(_SimdFloat4 _v) {
  const SimdFloat4 ret = {std::acos(_v.x), _v.y, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 Sin(_SimdFloat4 _v) {
  const SimdFloat4 ret = {std::sin(_v.x), std::sin(_v.y), std::sin(_v.z),
                          std::sin(_v.w)};
  return ret;
}

OZZ_INLINE SimdFloat4 SinX(_SimdFloat4 _v) {
  const SimdFloat4 ret = {std::sin(_v.x), _v.y, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 ASin(_SimdFloat4 _v) {
  const SimdFloat4 ret = {std::asin(_v.x), std::asin(_v.y), std::asin(_v.z),
                          std::asin(_v.w)};
  return ret;
}

OZZ_INLINE SimdFloat4 ASinX(_SimdFloat4 _v) {
  const SimdFloat4 ret = {std::asin(_v.x), _v.y, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 Tan(_SimdFloat4 _v) {
  const SimdFloat4 ret = {std::tan(_v.x), std::tan(_v.y), std::tan(_v.z),
                          std::tan(_v.w)};
  return ret;
}

OZZ_INLINE SimdFloat4 TanX(_SimdFloat4 _v) {
  const SimdFloat4 ret = {std::tan(_v.x), _v.y, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdFloat4 ATan(_SimdFloat4 _v) {
  const SimdFloat4 ret = {std::atan(_v.x), std::atan(_v.y), std::atan(_v.z),
                          std::atan(_v.w)};
  return ret;
}

OZZ_INLINE SimdFloat4 ATanX(_SimdFloat4 _v) {
  const SimdFloat4 ret = {std::atan(_v.x), _v.y, _v.z, _v.w};
  return ret;
}

namespace simd_int4 {

OZZ_INLINE SimdInt4 zero() {
  const SimdInt4 ret = {0, 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 one() {
  const SimdInt4 ret = {1, 1, 1, 1};
  return ret;
}

OZZ_INLINE SimdInt4 x_axis() {
  const SimdInt4 ret = {1, 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 y_axis() {
  const SimdInt4 ret = {0, 1, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 z_axis() {
  const SimdInt4 ret = {0, 0, 1, 0};
  return ret;
}

OZZ_INLINE SimdInt4 w_axis() {
  const SimdInt4 ret = {0, 0, 0, 1};
  return ret;
}

OZZ_INLINE SimdInt4 all_true() {
  const SimdInt4 ret = {~0, ~0, ~0, ~0};
  return ret;
}

OZZ_INLINE SimdInt4 all_false() {
  const SimdInt4 ret = {0, 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 mask_sign() {
  const SimdInt4 ret = {
      static_cast<int>(0x80000000), static_cast<int>(0x80000000),
      static_cast<int>(0x80000000), static_cast<int>(0x80000000)};
  return ret;
}

OZZ_INLINE SimdInt4 mask_sign_xyz() {
  const SimdInt4 ret = {
      static_cast<int>(0x80000000), static_cast<int>(0x80000000),
      static_cast<int>(0x80000000), static_cast<int>(0x00000000)};
  return ret;
}

OZZ_INLINE SimdInt4 mask_sign_w() {
  const SimdInt4 ret = {
      static_cast<int>(0x00000000), static_cast<int>(0x00000000),
      static_cast<int>(0x00000000), static_cast<int>(0x80000000)};
  return ret;
}

OZZ_INLINE SimdInt4 mask_not_sign() {
  const SimdInt4 ret = {
      static_cast<int>(0x7fffffff), static_cast<int>(0x7fffffff),
      static_cast<int>(0x7fffffff), static_cast<int>(0x7fffffff)};
  return ret;
}

OZZ_INLINE SimdInt4 mask_ffff() {
  const SimdInt4 ret = {~0, ~0, ~0, ~0};
  return ret;
}

OZZ_INLINE SimdInt4 mask_fff0() {
  const SimdInt4 ret = {~0, ~0, ~0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 mask_0000() {
  const SimdInt4 ret = {0, 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 mask_f000() {
  const SimdInt4 ret = {~0, 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 mask_0f00() {
  const SimdInt4 ret = {0, ~0, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 mask_00f0() {
  const SimdInt4 ret = {0, 0, ~0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 mask_000f() {
  const SimdInt4 ret = {0, 0, 0, ~0};
  return ret;
}

OZZ_INLINE SimdInt4 Load(int _x, int _y, int _z, int _w) {
  const SimdInt4 ret = {_x, _y, _z, _w};
  return ret;
}

OZZ_INLINE SimdInt4 LoadX(int _x) {
  const SimdInt4 ret = {_x, 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 Load1(int _x) {
  const SimdInt4 ret = {_x, _x, _x, _x};
  return ret;
}

OZZ_INLINE SimdInt4 Load(bool _x, bool _y, bool _z, bool _w) {
  const SimdInt4 ret = {-static_cast<int>(_x), -static_cast<int>(_y),
                        -static_cast<int>(_z), -static_cast<int>(_w)};
  return ret;
}

OZZ_INLINE SimdInt4 LoadX(bool _x) {
  const SimdInt4 ret = {-static_cast<int>(_x), 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 Load1(bool _x) {
  const int i = -static_cast<int>(_x);
  const SimdInt4 ret = {i, i, i, i};
  return ret;
}

OZZ_INLINE SimdInt4 LoadPtr(const int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  const SimdInt4 ret = {_i[0], _i[1], _i[2], _i[3]};
  return ret;
}

OZZ_INLINE SimdInt4 LoadXPtr(const int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  const SimdInt4 ret = {*_i, 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 Load1Ptr(const int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  const SimdInt4 ret = {*_i, *_i, *_i, *_i};
  return ret;
}

OZZ_INLINE SimdInt4 Load2Ptr(const int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  const SimdInt4 ret = {_i[0], _i[1], 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 Load3Ptr(const int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  const SimdInt4 ret = {_i[0], _i[1], _i[2], 0};
  return ret;
}

OZZ_INLINE SimdInt4 LoadPtrU(const int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  const SimdInt4 ret = {_i[0], _i[1], _i[2], _i[3]};
  return ret;
}

OZZ_INLINE SimdInt4 LoadXPtrU(const int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  const SimdInt4 ret = {*_i, 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 Load1PtrU(const int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  const SimdInt4 ret = {*_i, *_i, *_i, *_i};
  return ret;
}

OZZ_INLINE SimdInt4 Load2PtrU(const int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  const SimdInt4 ret = {_i[0], _i[1], 0, 0};
  return ret;
}

OZZ_INLINE SimdInt4 Load3PtrU(const int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  const SimdInt4 ret = {_i[0], _i[1], _i[2], 0};
  return ret;
}

OZZ_INLINE SimdInt4 FromFloatRound(_SimdFloat4 _f) {
  const SimdInt4 ret = {
      static_cast<int>(floor(_f.x + .5f)), static_cast<int>(floor(_f.y + .5f)),
      static_cast<int>(floor(_f.z + .5f)), static_cast<int>(floor(_f.w + .5f))};
  return ret;
}

OZZ_INLINE SimdInt4 FromFloatTrunc(_SimdFloat4 _f) {
  const SimdInt4 ret = {static_cast<int>(_f.x), static_cast<int>(_f.y),
                        static_cast<int>(_f.z), static_cast<int>(_f.w)};
  return ret;
}
}  // namespace simd_int4

OZZ_INLINE int GetX(_SimdInt4 _v) { return _v.x; }

OZZ_INLINE int GetY(_SimdInt4 _v) { return _v.y; }

OZZ_INLINE int GetZ(_SimdInt4 _v) { return _v.z; }

OZZ_INLINE int GetW(_SimdInt4 _v) { return _v.w; }

OZZ_INLINE SimdInt4 SetX(_SimdInt4 _v, _SimdInt4 _i) {
  const SimdInt4 ret = {_i.x, _v.y, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdInt4 SetY(_SimdInt4 _v, _SimdInt4 _i) {
  const SimdInt4 ret = {_v.x, _i.x, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdInt4 SetZ(_SimdInt4 _v, _SimdInt4 _i) {
  const SimdInt4 ret = {_v.x, _v.y, _i.x, _v.w};
  return ret;
}

OZZ_INLINE SimdInt4 SetW(_SimdInt4 _v, _SimdInt4 _i) {
  const SimdInt4 ret = {_v.x, _v.y, _v.z, _i.x};
  return ret;
}

OZZ_INLINE SimdInt4 SetI(_SimdInt4 _v, _SimdInt4 _i, int _ith) {
  assert(_ith >= 0 && _ith <= 3 && "Invalid index, out of range.");
  SimdInt4 ret = _v;
  (&ret.x)[_ith] = _i.x;
  return ret;
}

OZZ_INLINE void StorePtr(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  _i[0] = _v.x;
  _i[1] = _v.y;
  _i[2] = _v.z;
  _i[3] = _v.w;
}

OZZ_INLINE void Store1Ptr(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  _i[0] = _v.x;
}

OZZ_INLINE void Store2Ptr(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  _i[0] = _v.x;
  _i[1] = _v.y;
}

OZZ_INLINE void Store3Ptr(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0xf) && "Invalid alignment");
  _i[0] = _v.x;
  _i[1] = _v.y;
  _i[2] = _v.z;
}

OZZ_INLINE void StorePtrU(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  _i[0] = _v.x;
  _i[1] = _v.y;
  _i[2] = _v.z;
  _i[3] = _v.w;
}

OZZ_INLINE void Store1PtrU(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  _i[0] = _v.x;
}

OZZ_INLINE void Store2PtrU(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  _i[0] = _v.x;
  _i[1] = _v.y;
}

OZZ_INLINE void Store3PtrU(_SimdInt4 _v, int* _i) {
  assert(!(uintptr_t(_i) & 0x3) && "Invalid alignment");
  _i[0] = _v.x;
  _i[1] = _v.y;
  _i[2] = _v.z;
}

OZZ_INLINE SimdInt4 SplatX(_SimdInt4 _a) {
  const SimdInt4 ret = {_a.x, _a.x, _a.x, _a.x};
  return ret;
}

OZZ_INLINE SimdInt4 SplatY(_SimdInt4 _a) {
  const SimdInt4 ret = {_a.y, _a.y, _a.y, _a.y};
  return ret;
}

OZZ_INLINE SimdInt4 SplatZ(_SimdInt4 _a) {
  const SimdInt4 ret = {_a.z, _a.z, _a.z, _a.z};
  return ret;
}

OZZ_INLINE SimdInt4 SplatW(_SimdInt4 _a) {
  const SimdInt4 ret = {_a.w, _a.w, _a.w, _a.w};
  return ret;
}

template <size_t _X, size_t _Y, size_t _Z, size_t _W>
OZZ_INLINE SimdInt4 Swizzle(_SimdInt4 _v) {
  static_assert(_X <= 3 && _Y <= 3 && _Z <= 3 && _W <= 3,
                "Indices must be between 0 and 3");
  const int* pi = &_v.x;
  const SimdInt4 ret = {pi[_X], pi[_Y], pi[_Z], pi[_W]};
  return ret;
}

OZZ_INLINE int MoveMask(_SimdInt4 _v) {
  return ((_v.x & 0x80000000) >> 31) | ((_v.y & 0x80000000) >> 30) |
         ((_v.z & 0x80000000) >> 29) | ((_v.w & 0x80000000) >> 28);
}

OZZ_INLINE bool AreAllTrue(_SimdInt4 _v) {
  return _v.x != 0 && _v.y != 0 && _v.z != 0 && _v.w != 0;
}

OZZ_INLINE bool AreAllTrue3(_SimdInt4 _v) {
  return _v.x != 0 && _v.y != 0 && _v.z != 0;
}

OZZ_INLINE bool AreAllTrue2(_SimdInt4 _v) { return _v.x != 0 && _v.y != 0; }

OZZ_INLINE bool AreAllTrue1(_SimdInt4 _v) { return _v.x != 0; }

OZZ_INLINE bool AreAllFalse(_SimdInt4 _v) {
  return _v.x == 0 && _v.y == 0 && _v.z == 0 && _v.w == 0;
}

OZZ_INLINE bool AreAllFalse3(_SimdInt4 _v) {
  return _v.x == 0 && _v.y == 0 && _v.z == 0;
}

OZZ_INLINE bool AreAllFalse2(_SimdInt4 _v) { return _v.x == 0 && _v.y == 0; }

OZZ_INLINE bool AreAllFalse1(_SimdInt4 _v) { return _v.x == 0; }

OZZ_INLINE SimdInt4 MAdd(_SimdInt4 _a, _SimdInt4 _b, _SimdInt4 _addend) {
  const SimdInt4 ret = {_a.x * _b.x + _addend.x, _a.y * _b.y + _addend.y,
                        _a.z * _b.z + _addend.z, _a.w * _b.w + _addend.w};
  return ret;
}

OZZ_INLINE SimdInt4 DivX(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {_a.x / _b.x, _a.y, _a.z, _a.w};
  return ret;
}

OZZ_INLINE SimdInt4 HAdd2(_SimdInt4 _v) {
  const SimdInt4 ret = {_v.x + _v.y, _v.y, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdInt4 HAdd3(_SimdInt4 _v) {
  const SimdInt4 ret = {_v.x + _v.y + _v.z, _v.y, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdInt4 HAdd4(_SimdInt4 _v) {
  const SimdInt4 ret = {_v.x + _v.y + _v.z + _v.w, _v.y, _v.z, _v.w};
  return ret;
}

OZZ_INLINE SimdInt4 Dot2(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {_a.x * _b.x + _a.y * _b.y, _a.y, _a.z, _a.w};
  return ret;
}

OZZ_INLINE SimdInt4 Dot3(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {_a.x * _b.x + _a.y * _b.y + _a.z * _b.z, _a.y, _a.z,
                        _a.w};
  return ret;
}

OZZ_INLINE SimdInt4 Dot4(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {_a.x * _b.x + _a.y * _b.y + _a.z * _b.z + _a.w * _b.w,
                        _a.y, _a.z, _a.w};
  return ret;
}
OZZ_INLINE SimdInt4 Abs(_SimdInt4 _v) {
  const SimdInt4 mash = {_v.x >> 31, _v.y >> 31, _v.z >> 31, _v.w >> 31};
  const SimdInt4 ret = {
      (_v.x + (mash.x)) ^ (mash.x), (_v.y + (mash.y)) ^ (mash.y),
      (_v.z + (mash.z)) ^ (mash.z), (_v.w + (mash.w)) ^ (mash.w)};
  return ret;
}

OZZ_INLINE SimdInt4 Sign(_SimdInt4 _v) {
  const SimdInt4 ret = {
      _v.x & static_cast<int>(0x80000000), _v.y & static_cast<int>(0x80000000),
      _v.z & static_cast<int>(0x80000000), _v.w & static_cast<int>(0x80000000)};
  return ret;
}

OZZ_INLINE SimdInt4 Min(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {_a.x < _b.x ? _a.x : _b.x, _a.y < _b.y ? _a.y : _b.y,
                        _a.z < _b.z ? _a.z : _b.z, _a.w < _b.w ? _a.w : _b.w};
  return ret;
}

OZZ_INLINE SimdInt4 Max(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {_a.x > _b.x ? _a.x : _b.x, _a.y > _b.y ? _a.y : _b.y,
                        _a.z > _b.z ? _a.z : _b.z, _a.w > _b.w ? _a.w : _b.w};
  return ret;
}

OZZ_INLINE SimdInt4 Min0(_SimdInt4 _v) {
  const SimdInt4 ret = {_v.x < 0 ? _v.x : 0, _v.y < 0 ? _v.y : 0,
                        _v.z < 0 ? _v.z : 0, _v.w < 0 ? _v.w : 0};
  return ret;
}

OZZ_INLINE SimdInt4 Max0(_SimdInt4 _v) {
  const SimdInt4 ret = {_v.x > 0 ? _v.x : 0, _v.y > 0 ? _v.y : 0,
                        _v.z > 0 ? _v.z : 0, _v.w > 0 ? _v.w : 0};
  return ret;
}

OZZ_INLINE SimdInt4 Clamp(_SimdInt4 _a, _SimdInt4 _v, _SimdInt4 _b) {
  const SimdInt4 min = {_v.x < _b.x ? _v.x : _b.x, _v.y < _b.y ? _v.y : _b.y,
                        _v.z < _b.z ? _v.z : _b.z, _v.w < _b.w ? _v.w : _b.w};
  const SimdInt4 r = {_a.x > min.x ? _a.x : min.x, _a.y > min.y ? _a.y : min.y,
                      _a.z > min.z ? _a.z : min.z, _a.w > min.w ? _a.w : min.w};
  return r;
}

OZZ_INLINE SimdInt4 Select(_SimdInt4 _b, _SimdInt4 _true, _SimdInt4 _false) {
  const SimdInt4 ret = {_false.x ^ (_b.x & (_true.x ^ _false.x)),
                        _false.y ^ (_b.y & (_true.y ^ _false.y)),
                        _false.z ^ (_b.z & (_true.z ^ _false.z)),
                        _false.w ^ (_b.w & (_true.w ^ _false.w))};
  return ret;
}

OZZ_INLINE SimdInt4 And(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {_a.x & _b.x, _a.y & _b.y, _a.z & _b.z, _a.w & _b.w};
  return ret;
}

OZZ_INLINE SimdInt4 AndNot(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {_a.x & ~_b.x, _a.y & ~_b.y, _a.z & ~_b.z, _a.w & ~_b.w};
  return ret;
}

OZZ_INLINE SimdInt4 Or(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {_a.x | _b.x, _a.y | _b.y, _a.z | _b.z, _a.w | _b.w};
  return ret;
}

OZZ_INLINE SimdInt4 Xor(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {_a.x ^ _b.x, _a.y ^ _b.y, _a.z ^ _b.z, _a.w ^ _b.w};
  return ret;
}

OZZ_INLINE SimdInt4 Not(_SimdInt4 _v) {
  const SimdInt4 ret = {~_v.x, ~_v.y, ~_v.z, ~_v.w};
  return ret;
}

OZZ_INLINE SimdInt4 ShiftL(_SimdInt4 _v, int _bits) {
  const SimdInt4 ret = {_v.x << _bits, _v.y << _bits, _v.z << _bits,
                        _v.w << _bits};
  return ret;
}

OZZ_INLINE SimdInt4 ShiftR(_SimdInt4 _v, int _bits) {
  const SimdInt4 ret = {_v.x >> _bits, _v.y >> _bits, _v.z >> _bits,
                        _v.w >> _bits};
  return ret;
}

OZZ_INLINE SimdInt4 ShiftRu(_SimdInt4 _v, int _bits) {
  const union IU {
    int i[4];
    unsigned int u[4];
  } iu = {{_v.x, _v.y, _v.z, _v.w}};
  const union UI {
    unsigned int u[4];
    int i[4];
  } ui = {
      {iu.u[0] >> _bits, iu.u[1] >> _bits, iu.u[2] >> _bits, iu.u[3] >> _bits}};
  const SimdInt4 ret = {ui.i[0], ui.i[1], ui.i[2], ui.i[3]};
  return ret;
}

OZZ_INLINE SimdInt4 CmpEq(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {
      -static_cast<int>(_a.x == _b.x), -static_cast<int>(_a.y == _b.y),
      -static_cast<int>(_a.z == _b.z), -static_cast<int>(_a.w == _b.w)};
  return ret;
}

OZZ_INLINE SimdInt4 CmpNe(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {
      -static_cast<int>(_a.x != _b.x), -static_cast<int>(_a.y != _b.y),
      -static_cast<int>(_a.z != _b.z), -static_cast<int>(_a.w != _b.w)};
  return ret;
}

OZZ_INLINE SimdInt4 CmpLt(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {
      -static_cast<int>(_a.x < _b.x), -static_cast<int>(_a.y < _b.y),
      -static_cast<int>(_a.z < _b.z), -static_cast<int>(_a.w < _b.w)};
  return ret;
}

OZZ_INLINE SimdInt4 CmpLe(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {
      -static_cast<int>(_a.x <= _b.x), -static_cast<int>(_a.y <= _b.y),
      -static_cast<int>(_a.z <= _b.z), -static_cast<int>(_a.w <= _b.w)};
  return ret;
}

OZZ_INLINE SimdInt4 CmpGt(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {
      -static_cast<int>(_a.x > _b.x), -static_cast<int>(_a.y > _b.y),
      -static_cast<int>(_a.z > _b.z), -static_cast<int>(_a.w > _b.w)};
  return ret;
}

OZZ_INLINE SimdInt4 CmpGe(_SimdInt4 _a, _SimdInt4 _b) {
  const SimdInt4 ret = {
      -static_cast<int>(_a.x >= _b.x), -static_cast<int>(_a.y >= _b.y),
      -static_cast<int>(_a.z >= _b.z), -static_cast<int>(_a.w >= _b.w)};
  return ret;
}

OZZ_INLINE Float4x4 Float4x4::identity() {
  const Float4x4 ret = {{{1.f, 0.f, 0.f, 0.f},
                         {0.f, 1.f, 0.f, 0.f},
                         {0.f, 0.f, 1.f, 0.f},
                         {0.f, 0.f, 0.f, 1.f}}};
  return ret;
}

OZZ_INLINE Float4x4 Transpose(const Float4x4& _m) {
  const Float4x4 ret = {
      {{_m.cols[0].x, _m.cols[1].x, _m.cols[2].x, _m.cols[3].x},
       {_m.cols[0].y, _m.cols[1].y, _m.cols[2].y, _m.cols[3].y},
       {_m.cols[0].z, _m.cols[1].z, _m.cols[2].z, _m.cols[3].z},
       {_m.cols[0].w, _m.cols[1].w, _m.cols[2].w, _m.cols[3].w}}};
  return ret;
}

OZZ_INLINE Float4x4 Invert(const Float4x4& _m, SimdInt4* _invertible) {
  const SimdFloat4* cols = _m.cols;
  const float a00 = cols[2].z * cols[3].w - cols[3].z * cols[2].w;
  const float a01 = cols[2].y * cols[3].w - cols[3].y * cols[2].w;
  const float a02 = cols[2].y * cols[3].z - cols[3].y * cols[2].z;
  const float a03 = cols[2].x * cols[3].w - cols[3].x * cols[2].w;
  const float a04 = cols[2].x * cols[3].z - cols[3].x * cols[2].z;
  const float a05 = cols[2].x * cols[3].y - cols[3].x * cols[2].y;
  const float a06 = cols[1].z * cols[3].w - cols[3].z * cols[1].w;
  const float a07 = cols[1].y * cols[3].w - cols[3].y * cols[1].w;
  const float a08 = cols[1].y * cols[3].z - cols[3].y * cols[1].z;
  const float a09 = cols[1].x * cols[3].w - cols[3].x * cols[1].w;
  const float a10 = cols[1].x * cols[3].z - cols[3].x * cols[1].z;
  const float a11 = cols[1].y * cols[3].w - cols[3].y * cols[1].w;
  const float a12 = cols[1].x * cols[3].y - cols[3].x * cols[1].y;
  const float a13 = cols[1].z * cols[2].w - cols[2].z * cols[1].w;
  const float a14 = cols[1].y * cols[2].w - cols[2].y * cols[1].w;
  const float a15 = cols[1].y * cols[2].z - cols[2].y * cols[1].z;
  const float a16 = cols[1].x * cols[2].w - cols[2].x * cols[1].w;
  const float a17 = cols[1].x * cols[2].z - cols[2].x * cols[1].z;
  const float a18 = cols[1].x * cols[2].y - cols[2].x * cols[1].y;

  const float b0x = cols[1].y * a00 - cols[1].z * a01 + cols[1].w * a02;
  const float b1x = -cols[1].x * a00 + cols[1].z * a03 - cols[1].w * a04;
  const float b2x = cols[1].x * a01 - cols[1].y * a03 + cols[1].w * a05;
  const float b3x = -cols[1].x * a02 + cols[1].y * a04 - cols[1].z * a05;

  const float b0y = -cols[0].y * a00 + cols[0].z * a01 - cols[0].w * a02;
  const float b1y = cols[0].x * a00 - cols[0].z * a03 + cols[0].w * a04;
  const float b2y = -cols[0].x * a01 + cols[0].y * a03 - cols[0].w * a05;
  const float b3y = cols[0].x * a02 - cols[0].y * a04 + cols[0].z * a05;

  const float b0z = cols[0].y * a06 - cols[0].z * a07 + cols[0].w * a08;
  const float b1z = -cols[0].x * a06 + cols[0].z * a09 - cols[0].w * a10;
  const float b2z = cols[0].x * a11 - cols[0].y * a09 + cols[0].w * a12;
  const float b3z = -cols[0].x * a08 + cols[0].y * a10 - cols[0].z * a12;

  const float b0w = -cols[0].y * a13 + cols[0].z * a14 - cols[0].w * a15;
  const float b1w = cols[0].x * a13 - cols[0].z * a16 + cols[0].w * a17;
  const float b2w = -cols[0].x * a14 + cols[0].y * a16 - cols[0].w * a18;
  const float b3w = cols[0].x * a15 - cols[0].y * a17 + cols[0].z * a18;

  const float det =
      cols[0].x * b0x + cols[0].y * b1x + cols[0].z * b2x + cols[0].w * b3x;
  const bool invertible = det != 0.f;
  assert((_invertible || invertible) && "Matrix is not invertible");
  if (_invertible != nullptr) {
    *_invertible = simd_int4::LoadX(invertible);
  }
  const float inv_det = invertible ? 1.f / det : 0.f;

  const Float4x4 ret = {
      {{b0x * inv_det, b0y * inv_det, b0z * inv_det, b0w * inv_det},
       {b1x * inv_det, b1y * inv_det, b1z * inv_det, b1w * inv_det},
       {b2x * inv_det, b2y * inv_det, b2z * inv_det, b2w * inv_det},
       {b3x * inv_det, b3y * inv_det, b3z * inv_det, b3w * inv_det}}};
  return ret;
}

Float4x4 Float4x4::Scaling(_SimdFloat4 _v) {
  const Float4x4 ret = {{{_v.x, 0.f, 0.f, 0.f},
                         {0.f, _v.y, 0.f, 0.f},
                         {0.f, 0.f, _v.z, 0.f},
                         {0.f, 0.f, 0.f, 1.f}}};
  return ret;
}

Float4x4 Float4x4::Translation(_SimdFloat4 _v) {
  const Float4x4 ret = {{{1.f, 0.f, 0.f, 0.f},
                         {0.f, 1.f, 0.f, 0.f},
                         {0.f, 0.f, 1.f, 0.f},
                         {_v.x, _v.y, _v.z, 1.f}}};
  return ret;
}

OZZ_INLINE Float4x4 Translate(const Float4x4& _m, _SimdFloat4 _v) {
  const Float4x4 ret = {{_m.cols[0],
                         _m.cols[1],
                         _m.cols[2],
                         {_m.cols[0].x * _v.x + _m.cols[1].x * _v.y +
                              _m.cols[2].x * _v.z + _m.cols[3].x,
                          _m.cols[0].y * _v.x + _m.cols[1].y * _v.y +
                              _m.cols[2].y * _v.z + _m.cols[3].y,
                          _m.cols[0].z * _v.x + _m.cols[1].z * _v.y +
                              _m.cols[2].z * _v.z + _m.cols[3].z,
                          _m.cols[0].w * _v.x + _m.cols[1].w * _v.y +
                              _m.cols[2].w * _v.z + _m.cols[3].w}}};
  return ret;
}

OZZ_INLINE Float4x4 Scale(const Float4x4& _m, _SimdFloat4 _v) {
  const Float4x4 ret = {{{_m.cols[0].x * _v.x, _m.cols[0].y * _v.x,
                          _m.cols[0].z * _v.x, _m.cols[0].w * _v.x},
                         {_m.cols[1].x * _v.y, _m.cols[1].y * _v.y,
                          _m.cols[1].z * _v.y, _m.cols[1].w * _v.y},
                         {_m.cols[2].x * _v.z, _m.cols[2].y * _v.z,
                          _m.cols[2].z * _v.z, _m.cols[2].w * _v.z},
                         _m.cols[3]}};
  return ret;
}

OZZ_INLINE Float4x4 ColumnMultiply(const Float4x4& _m, _SimdFloat4 _v) {
  const Float4x4 ret = {{{_m.cols[0].x * _v.x, _m.cols[0].y * _v.y,
                          _m.cols[0].z * _v.z, _m.cols[0].w * _v.w},
                         {_m.cols[1].x * _v.x, _m.cols[1].y * _v.y,
                          _m.cols[1].z * _v.z, _m.cols[1].w * _v.w},
                         {_m.cols[2].x * _v.x, _m.cols[2].y * _v.y,
                          _m.cols[2].z * _v.z, _m.cols[2].w * _v.w},
                         {_m.cols[3].x * _v.x, _m.cols[3].y * _v.y,
                          _m.cols[3].z * _v.z, _m.cols[3].w * _v.w}}};
  return ret;
}

OZZ_INLINE SimdInt4 IsNormalized(const Float4x4& _m) {
  const SimdInt4 ret = {IsNormalized3(_m.cols[0]).x,
                        IsNormalized3(_m.cols[1]).x,
                        IsNormalized3(_m.cols[2]).x, 0};
  return ret;
}

OZZ_INLINE SimdInt4 IsNormalizedEst(const Float4x4& _m) {
  const SimdInt4 ret = {IsNormalizedEst3(_m.cols[0]).x,
                        IsNormalizedEst3(_m.cols[1]).x,
                        IsNormalizedEst3(_m.cols[2]).x, 0};
  return ret;
}

OZZ_INLINE SimdInt4 IsOrthogonal(const Float4x4& _m) {
  // Use simd_float4::zero() if one of the normalization fails. _m will then be
  // considered not orthogonal.
  const SimdFloat4 cross =
      NormalizeSafe3(Cross3(_m.cols[0], _m.cols[1]), simd_float4::zero());
  const SimdFloat4 at = NormalizeSafe3(_m.cols[2], simd_float4::zero());

  const float sq_len = cross.x * at.x + cross.y * at.y + cross.z * at.z;
  const bool same = std::abs(sq_len - 1.f) < kNormalizationToleranceSq;
  const SimdInt4 ret = {-static_cast<int>(same), 0, 0, 0};
  return ret;
}

OZZ_INLINE SimdFloat4 ToQuaternion(const Float4x4& _m) {
  assert(AreAllTrue3(IsNormalized(_m)));
  assert(AreAllTrue1(IsOrthogonal(_m)));
  // Cf From Quaternion to Matrix and Back, J.M.P. van Waveren 2005.
  SimdFloat4 ret;
  if (_m.cols[0].x + _m.cols[1].y + _m.cols[2].z > .0f) {
    const float t = _m.cols[0].x + _m.cols[1].y + _m.cols[2].z + 1.0f;
    const float s = (1.f / std::sqrt(t)) * .5f;
    ret.x = (_m.cols[1].z - _m.cols[2].y) * s;
    ret.y = (_m.cols[2].x - _m.cols[0].z) * s;
    ret.z = (_m.cols[0].y - _m.cols[1].x) * s;
    ret.w = s * t;
  } else if (_m.cols[0].x > _m.cols[1].y && _m.cols[0].x > _m.cols[2].z) {
    const float t = _m.cols[0].x - _m.cols[1].y - _m.cols[2].z + 1.0f;
    const float s = (1.f / std::sqrt(t)) * .5f;
    ret.x = s * t;
    ret.y = (_m.cols[0].y + _m.cols[1].x) * s;
    ret.z = (_m.cols[2].x + _m.cols[0].z) * s;
    ret.w = (_m.cols[1].z - _m.cols[2].y) * s;
  } else if (_m.cols[1].y > _m.cols[2].z) {
    const float t = -_m.cols[0].x + _m.cols[1].y - _m.cols[2].z + 1.0f;
    const float s = (1.f / std::sqrt(t)) * .5f;
    ret.x = (_m.cols[0].y + _m.cols[1].x) * s;
    ret.y = s * t;
    ret.z = (_m.cols[1].z + _m.cols[2].y) * s;
    ret.w = (_m.cols[2].x - _m.cols[0].z) * s;
  } else {
    const float t = -_m.cols[0].x - _m.cols[1].y + _m.cols[2].z + 1.0f;
    const float s = (1.f / std::sqrt(t)) * .5f;
    ret.x = (_m.cols[2].x + _m.cols[0].z) * s;
    ret.y = (_m.cols[1].z + _m.cols[2].y) * s;
    ret.z = s * t;
    ret.w = (_m.cols[0].y - _m.cols[1].x) * s;
  }
  assert(AreAllTrue1(IsNormalizedEst4(ret)));
  return ret;
}

OZZ_INLINE bool ToAffine(const Float4x4& _m, SimdFloat4* _translation,
                         SimdFloat4* _quaternion, SimdFloat4* _scale) {
  _translation->x = _m.cols[3].x;
  _translation->y = _m.cols[3].y;
  _translation->z = _m.cols[3].z;
  _translation->w = 1.f;

  // Extracts scale.
  const float sq_scale_x = Length3Sqr(_m.cols[0]).x;
  const float scale_x = std::sqrt(sq_scale_x);
  const float sq_scale_y = Length3Sqr(_m.cols[1]).x;
  const float scale_y = std::sqrt(sq_scale_y);
  const float sq_scale_z = Length3Sqr(_m.cols[2]).x;
  const float scale_z = std::sqrt(sq_scale_z);

  // Builds an orthonormal matrix in order to support quaternion extraction.
  const bool x_zero = std::abs(sq_scale_x) < kOrthogonalisationToleranceSq;
  const bool y_zero = std::abs(sq_scale_y) < kOrthogonalisationToleranceSq;
  const bool z_zero = std::abs(sq_scale_z) < kOrthogonalisationToleranceSq;

  Float4x4 orthonormal;
  if (x_zero) {
    if (y_zero || z_zero) {
      return false;
    }
    orthonormal.cols[1].x = _m.cols[1].x / scale_y;
    orthonormal.cols[1].y = _m.cols[1].y / scale_y;
    orthonormal.cols[1].z = _m.cols[1].z / scale_y;
    orthonormal.cols[1].w = 0.f;
    orthonormal.cols[0] = Normalize3(Cross3(orthonormal.cols[1], _m.cols[2]));
    orthonormal.cols[2] =
        Normalize3(Cross3(orthonormal.cols[0], orthonormal.cols[1]));
  } else if (z_zero) {
    if (x_zero || y_zero) {
      return false;
    }
    orthonormal.cols[0].x = _m.cols[0].x / scale_x;
    orthonormal.cols[0].y = _m.cols[0].y / scale_x;
    orthonormal.cols[0].z = _m.cols[0].z / scale_x;
    orthonormal.cols[0].w = 0.f;
    orthonormal.cols[2] = Normalize3(Cross3(orthonormal.cols[0], _m.cols[1]));
    orthonormal.cols[1] =
        Normalize3(Cross3(orthonormal.cols[2], orthonormal.cols[0]));
  } else {  // Favor z axis in the default case
    if (x_zero || z_zero) {
      return false;
    }
    orthonormal.cols[2].x = _m.cols[2].x / scale_z;
    orthonormal.cols[2].y = _m.cols[2].y / scale_z;
    orthonormal.cols[2].z = _m.cols[2].z / scale_z;
    orthonormal.cols[2].w = 0.f;
    orthonormal.cols[1] = Normalize3(Cross3(orthonormal.cols[2], _m.cols[0]));
    orthonormal.cols[0] =
        Normalize3(Cross3(orthonormal.cols[1], orthonormal.cols[2]));
  }

  // orthonormal.cols[3] = simd_float4::w_axis();  Not used by ToQuaternion.

  // Get back scale signs in case of reflexions
  _scale->x =
      Dot3(orthonormal.cols[0], _m.cols[0]).x > 0.f ? scale_x : -scale_x;
  _scale->y =
      Dot3(orthonormal.cols[1], _m.cols[1]).x > 0.f ? scale_y : -scale_y;
  _scale->z =
      Dot3(orthonormal.cols[2], _m.cols[2]).x > 0.f ? scale_z : -scale_z;
  _scale->w = 1.f;

  // Extracts quaternion.
  *_quaternion = ToQuaternion(orthonormal);
  return true;
}

OZZ_INLINE Float4x4 Float4x4::FromEuler(_SimdFloat4 _v) {
  return Float4x4::FromAxisAngle(simd_float4::y_axis(), SplatX(_v)) *
         Float4x4::FromAxisAngle(simd_float4::x_axis(), SplatY(_v)) *
         Float4x4::FromAxisAngle(simd_float4::z_axis(), SplatZ(_v));
}

OZZ_INLINE Float4x4 Float4x4::FromAxisAngle(_SimdFloat4 _axis,
                                            _SimdFloat4 _angle) {
  assert(AreAllTrue1(IsNormalizedEst3(_axis)));

  const float cos = std::cos(_angle.x);
  const float sin = std::sin(_angle.x);
  const float t = 1.f - cos;

  const float a = _axis.x * _axis.y * t;
  const float b = _axis.z * sin;
  const float c = _axis.x * _axis.z * t;
  const float d = _axis.y * sin;
  const float e = _axis.y * _axis.z * t;
  const float f = _axis.x * sin;

  const Float4x4 ret = {{{cos + _axis.x * _axis.x * t, a + b, c - d, 0.f},
                         {a - b, cos + _axis.y * _axis.y * t, e + f, 0.f},
                         {c + d, e - f, cos + _axis.z * _axis.z * t, 0.f},
                         {0.f, 0.f, 0.f, 1.f}}};
  return ret;
}

OZZ_INLINE Float4x4 Float4x4::FromQuaternion(_SimdFloat4 _v) {
  assert(AreAllTrue1(IsNormalizedEst4(_v)));

  const float xx = _v.x * _v.x;
  const float xy = _v.x * _v.y;
  const float xz = _v.x * _v.z;
  const float xw = _v.x * _v.w;
  const float yy = _v.y * _v.y;
  const float yz = _v.y * _v.z;
  const float yw = _v.y * _v.w;
  const float zz = _v.z * _v.z;
  const float zw = _v.z * _v.w;

  const Float4x4 ret = {
      {{1.f - 2.f * (yy + zz), 2.f * (xy + zw), 2.f * (xz - yw), 0.f},
       {2.f * (xy - zw), 1.f - 2.f * (xx + zz), 2.f * (yz + xw), 0.f},
       {2.f * (xz + yw), 2.f * (yz - xw), 1.f - 2.f * (xx + yy), 0.f},
       {0.f, 0.f, 0.f, 1.f}}};
  return ret;
}

OZZ_INLINE Float4x4 Float4x4::FromAffine(_SimdFloat4 _translation,
                                         _SimdFloat4 _quaternion,
                                         _SimdFloat4 _scale) {
  assert(AreAllTrue1(IsNormalizedEst4(_quaternion)));

  const float xx = _quaternion.x * _quaternion.x;
  const float xy = _quaternion.x * _quaternion.y;
  const float xz = _quaternion.x * _quaternion.z;
  const float xw = _quaternion.x * _quaternion.w;
  const float yy = _quaternion.y * _quaternion.y;
  const float yz = _quaternion.y * _quaternion.z;
  const float yw = _quaternion.y * _quaternion.w;
  const float zz = _quaternion.z * _quaternion.z;
  const float zw = _quaternion.z * _quaternion.w;

  const Float4x4 ret = {
      {{_scale.x * (1.f - 2.f * (yy + zz)), _scale.x * 2.f * (xy + zw),
        _scale.x * 2.f * (xz - yw), 0.f},
       {_scale.y * 2.f * (xy - zw), _scale.y * (1.f - 2.f * (xx + zz)),
        _scale.y * (2.f * (yz + xw)), 0.f},
       {_scale.z * 2.f * (xz + yw), _scale.z * 2.f * (yz - xw),
        _scale.z * (1.f - 2.f * (xx + yy)), 0.f},
       {_translation.x, _translation.y, _translation.z, 1.f}}};
  return ret;
}

OZZ_INLINE ozz::math::SimdFloat4 TransformPoint(const ozz::math::Float4x4& _m,
                                                ozz::math::_SimdFloat4 _v) {
  const ozz::math::SimdFloat4 ret = {_m.cols[0].x * _v.x + _m.cols[1].x * _v.y +
                                         _m.cols[2].x * _v.z + _m.cols[3].x,
                                     _m.cols[0].y * _v.x + _m.cols[1].y * _v.y +
                                         _m.cols[2].y * _v.z + _m.cols[3].y,
                                     _m.cols[0].z * _v.x + _m.cols[1].z * _v.y +
                                         _m.cols[2].z * _v.z + _m.cols[3].z,
                                     _m.cols[0].w * _v.x + _m.cols[1].w * _v.y +
                                         _m.cols[2].w * _v.z + _m.cols[3].w};
  return ret;
}

OZZ_INLINE ozz::math::SimdFloat4 TransformVector(const ozz::math::Float4x4& _m,
                                                 ozz::math::_SimdFloat4 _v) {
  const ozz::math::SimdFloat4 ret = {
      _m.cols[0].x * _v.x + _m.cols[1].x * _v.y + _m.cols[2].x * _v.z,
      _m.cols[0].y * _v.x + _m.cols[1].y * _v.y + _m.cols[2].y * _v.z,
      _m.cols[0].z * _v.x + _m.cols[1].z * _v.y + _m.cols[2].z * _v.z,
      _m.cols[0].w * _v.x + _m.cols[1].w * _v.y + _m.cols[2].w * _v.z};
  return ret;
}

OZZ_INLINE ozz::math::SimdFloat4 operator*(const ozz::math::Float4x4& _m,
                                           ozz::math::_SimdFloat4 _v) {
  const ozz::math::SimdFloat4 ret = {
      _m.cols[0].x * _v.x + _m.cols[1].x * _v.y + _m.cols[2].x * _v.z +
          _m.cols[3].x * _v.w,
      _m.cols[0].y * _v.x + _m.cols[1].y * _v.y + _m.cols[2].y * _v.z +
          _m.cols[3].y * _v.w,
      _m.cols[0].z * _v.x + _m.cols[1].z * _v.y + _m.cols[2].z * _v.z +
          _m.cols[3].z * _v.w,
      _m.cols[0].w * _v.x + _m.cols[1].w * _v.y + _m.cols[2].w * _v.z +
          _m.cols[3].w * _v.w};
  return ret;
}

OZZ_INLINE ozz::math::Float4x4 operator*(const ozz::math::Float4x4& _a,
                                         const ozz::math::Float4x4& _b) {
  const ozz::math::Float4x4 ret = {
      {_a * _b.cols[0], _a * _b.cols[1], _a * _b.cols[2], _a * _b.cols[3]}};
  return ret;
}

OZZ_INLINE ozz::math::Float4x4 operator+(const ozz::math::Float4x4& _a,
                                         const ozz::math::Float4x4& _b) {
  const ozz::math::Float4x4 ret = {
      {{_a.cols[0].x + _b.cols[0].x, _a.cols[0].y + _b.cols[0].y,
        _a.cols[0].z + _b.cols[0].z, _a.cols[0].w + _b.cols[0].w},
       {_a.cols[1].x + _b.cols[1].x, _a.cols[1].y + _b.cols[1].y,
        _a.cols[1].z + _b.cols[1].z, _a.cols[1].w + _b.cols[1].w},
       {_a.cols[2].x + _b.cols[2].x, _a.cols[2].y + _b.cols[2].y,
        _a.cols[2].z + _b.cols[2].z, _a.cols[2].w + _b.cols[2].w},
       {_a.cols[3].x + _b.cols[3].x, _a.cols[3].y + _b.cols[3].y,
        _a.cols[3].z + _b.cols[3].z, _a.cols[3].w + _b.cols[3].w}}};
  return ret;
}

OZZ_INLINE ozz::math::Float4x4 operator-(const ozz::math::Float4x4& _a,
                                         const ozz::math::Float4x4& _b) {
  const ozz::math::Float4x4 ret = {
      {{_a.cols[0].x - _b.cols[0].x, _a.cols[0].y - _b.cols[0].y,
        _a.cols[0].z - _b.cols[0].z, _a.cols[0].w - _b.cols[0].w},
       {_a.cols[1].x - _b.cols[1].x, _a.cols[1].y - _b.cols[1].y,
        _a.cols[1].z - _b.cols[1].z, _a.cols[1].w - _b.cols[1].w},
       {_a.cols[2].x - _b.cols[2].x, _a.cols[2].y - _b.cols[2].y,
        _a.cols[2].z - _b.cols[2].z, _a.cols[2].w - _b.cols[2].w},
       {_a.cols[3].x - _b.cols[3].x, _a.cols[3].y - _b.cols[3].y,
        _a.cols[3].z - _b.cols[3].z, _a.cols[3].w - _b.cols[3].w}}};
  return ret;
}
}  // namespace math
}  // namespace ozz

OZZ_INLINE ozz::math::SimdFloat4 operator+(ozz::math::_SimdFloat4 _a,
                                           ozz::math::_SimdFloat4 _b) {
  const ozz::math::SimdFloat4 ret = {_a.x + _b.x, _a.y + _b.y, _a.z + _b.z,
                                     _a.w + _b.w};
  return ret;
}

OZZ_INLINE ozz::math::SimdFloat4 operator-(ozz::math::_SimdFloat4 _a,
                                           ozz::math::_SimdFloat4 _b) {
  const ozz::math::SimdFloat4 ret = {_a.x - _b.x, _a.y - _b.y, _a.z - _b.z,
                                     _a.w - _b.w};
  return ret;
}

OZZ_INLINE ozz::math::SimdFloat4 operator-(ozz::math::_SimdFloat4 _v) {
  const ozz::math::SimdFloat4 ret = {-_v.x, -_v.y, -_v.z, -_v.w};
  return ret;
}

OZZ_INLINE ozz::math::SimdFloat4 operator*(ozz::math::_SimdFloat4 _a,
                                           ozz::math::_SimdFloat4 _b) {
  const ozz::math::SimdFloat4 ret = {_a.x * _b.x, _a.y * _b.y, _a.z * _b.z,
                                     _a.w * _b.w};
  return ret;
}

OZZ_INLINE ozz::math::SimdFloat4 operator/(ozz::math::_SimdFloat4 _a,
                                           ozz::math::_SimdFloat4 _b) {
  const ozz::math::SimdFloat4 ret = {_a.x / _b.x, _a.y / _b.y, _a.z / _b.z,
                                     _a.w / _b.w};
  return ret;
}

namespace ozz {
namespace math {
// Half <-> Float implementation is based on:
// http://fgiesen.wordpress.com/2012/03/28/half-to-float-done-quic/.
OZZ_INLINE uint16_t FloatToHalf(float _f) {
  const uint32_t f32infty = 255 << 23;
  const uint32_t f16infty = 31 << 23;
  const union {
    uint32_t u;
    float f;
  } magic = {15 << 23};
  const uint32_t sign_mask = 0x80000000u;
  const uint32_t round_mask = ~0x00000fffu;

  const union {
    float f;
    uint32_t u;
  } f = {_f};
  const uint32_t sign = f.u & sign_mask;
  const uint32_t f_nosign = f.u & ~sign_mask;

  if (f_nosign >= f32infty) {  // Inf or NaN (all exponent bits set)
    // NaN->qNaN and Inf->Inf
    const uint32_t result =
        ((f_nosign > f32infty) ? 0x7e00 : 0x7c00) | (sign >> 16);
    return static_cast<uint16_t>(result);
  } else {  // (De)normalized number or zero
    const union {
      uint32_t u;
      float f;
    } rounded = {f_nosign & round_mask};
    const union {
      float f;
      uint32_t u;
    } exp = {rounded.f * magic.f};
    const uint32_t re_rounded = exp.u - round_mask;
    // Clamp to signed infinity if overflowed
    const uint32_t result =
        ((re_rounded > f16infty ? f16infty : re_rounded) >> 13) | (sign >> 16);
    return static_cast<uint16_t>(result);
  }
}

OZZ_INLINE float HalfToFloat(uint16_t _h) {
  const union {
    uint32_t u;
    float f;
  } magic = {(254 - 15) << 23};
  const union {
    uint32_t u;
    float f;
  } infnan = {(127 + 16) << 23};

  const uint32_t sign = _h & 0x8000;
  const union {
    int32_t u;
    float f;
  } exp_mant = {(_h & 0x7fff) << 13};
  const union {
    float f;
    uint32_t u;
  } adjust = {exp_mant.f * magic.f};
  // Make sure Inf/NaN survive
  const union {
    uint32_t u;
    float f;
  } result = {(adjust.f >= infnan.f ? (adjust.u | 255 << 23) : adjust.u) |
              (sign << 16)};
  return result.f;
}

OZZ_INLINE SimdInt4 FloatToHalf(_SimdFloat4 _f) {
  const ozz::math::SimdInt4 ret = {FloatToHalf(_f.x), FloatToHalf(_f.y),
                                   FloatToHalf(_f.z), FloatToHalf(_f.w)};
  return ret;
}

OZZ_INLINE SimdFloat4 HalfToFloat(_SimdInt4 _h) {
  const ozz::math::SimdFloat4 ret = {
      HalfToFloat(_h.x & 0x0000ffff), HalfToFloat(_h.y & 0x0000ffff),
      HalfToFloat(_h.z & 0x0000ffff), HalfToFloat(_h.w & 0x0000ffff)};
  return ret;
}
}  // namespace math
}  // namespace ozz

#undef OZZ_RCP_EST
#undef OZZ_RSQRT_EST
#endif  // OZZ_OZZ_BASE_MATHS_INTERNAL_SIMD_MATH_REF_INL_H_
/**** ended inlining ozz/base/maths/internal/simd_math_ref-inl.h ****/
#else
#error No simd_math implementation detected
#endif
#endif  // OZZ_OZZ_BASE_MATHS_SIMD_MATH_H_
/**** ended inlining ozz/base/maths/simd_math.h ****/
/**** start inlining ozz/base/maths/soa_transform.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_MATHS_SOA_TRANSFORM_H_
#define OZZ_OZZ_BASE_MATHS_SOA_TRANSFORM_H_

/**** start inlining ozz/base/maths/soa_float.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_MATHS_SOA_FLOAT_H_
#define OZZ_OZZ_BASE_MATHS_SOA_FLOAT_H_

#include <cassert>

/**** skipping file: ozz/base/maths/math_constant.h ****/
/**** skipping file: ozz/base/maths/simd_math.h ****/
/**** skipping file: ozz/base/platform.h ****/

namespace ozz {
namespace math {

struct SoaFloat2 {
  SimdFloat4 x, y;

  static OZZ_INLINE SoaFloat2 Load(_SimdFloat4 _x, _SimdFloat4 _y) {
    const SoaFloat2 r = {_x, _y};
    return r;
  }

  static OZZ_INLINE SoaFloat2 zero() {
    const SoaFloat2 r = {simd_float4::zero(), simd_float4::zero()};
    return r;
  }

  static OZZ_INLINE SoaFloat2 one() {
    const SoaFloat2 r = {simd_float4::one(), simd_float4::one()};
    return r;
  }

  static OZZ_INLINE SoaFloat2 x_axis() {
    const SoaFloat2 r = {simd_float4::one(), simd_float4::zero()};
    return r;
  }

  static OZZ_INLINE SoaFloat2 y_axis() {
    const SoaFloat2 r = {simd_float4::zero(), simd_float4::one()};
    return r;
  }
};

struct SoaFloat3 {
  SimdFloat4 x, y, z;

  static OZZ_INLINE SoaFloat3 Load(_SimdFloat4 _x, _SimdFloat4 _y,
                                   _SimdFloat4 _z) {
    const SoaFloat3 r = {_x, _y, _z};
    return r;
  }

  static OZZ_INLINE SoaFloat3 Load(const SoaFloat2& _v, _SimdFloat4 _z) {
    const SoaFloat3 r = {_v.x, _v.y, _z};
    return r;
  }

  static OZZ_INLINE SoaFloat3 zero() {
    const SoaFloat3 r = {simd_float4::zero(), simd_float4::zero(),
                         simd_float4::zero()};
    return r;
  }

  static OZZ_INLINE SoaFloat3 one() {
    const SoaFloat3 r = {simd_float4::one(), simd_float4::one(),
                         simd_float4::one()};
    return r;
  }

  static OZZ_INLINE SoaFloat3 x_axis() {
    const SoaFloat3 r = {simd_float4::one(), simd_float4::zero(),
                         simd_float4::zero()};
    return r;
  }

  static OZZ_INLINE SoaFloat3 y_axis() {
    const SoaFloat3 r = {simd_float4::zero(), simd_float4::one(),
                         simd_float4::zero()};
    return r;
  }

  static OZZ_INLINE SoaFloat3 z_axis() {
    const SoaFloat3 r = {simd_float4::zero(), simd_float4::zero(),
                         simd_float4::one()};
    return r;
  }
};

struct SoaFloat4 {
  SimdFloat4 x, y, z, w;

  static OZZ_INLINE SoaFloat4 Load(_SimdFloat4 _x, _SimdFloat4 _y,
                                   _SimdFloat4 _z, const SimdFloat4& _w) {
    const SoaFloat4 r = {_x, _y, _z, _w};
    return r;
  }

  static OZZ_INLINE SoaFloat4 Load(const SoaFloat3& _v, _SimdFloat4 _w) {
    const SoaFloat4 r = {_v.x, _v.y, _v.z, _w};
    return r;
  }

  static OZZ_INLINE SoaFloat4 Load(const SoaFloat2& _v, _SimdFloat4 _z,
                                   _SimdFloat4 _w) {
    const SoaFloat4 r = {_v.x, _v.y, _z, _w};
    return r;
  }

  static OZZ_INLINE SoaFloat4 zero() {
    const SimdFloat4 zero = simd_float4::zero();
    const SoaFloat4 r = {zero, zero, zero, zero};
    return r;
  }

  static OZZ_INLINE SoaFloat4 one() {
    const SimdFloat4 one = simd_float4::one();
    const SoaFloat4 r = {one, one, one, one};
    return r;
  }

  static OZZ_INLINE SoaFloat4 x_axis() {
    const SimdFloat4 zero = simd_float4::zero();
    const SoaFloat4 r = {simd_float4::one(), zero, zero, zero};
    return r;
  }

  static OZZ_INLINE SoaFloat4 y_axis() {
    const SimdFloat4 zero = simd_float4::zero();
    const SoaFloat4 r = {zero, simd_float4::one(), zero, zero};
    return r;
  }

  static OZZ_INLINE SoaFloat4 z_axis() {
    const SimdFloat4 zero = simd_float4::zero();
    const SoaFloat4 r = {zero, zero, simd_float4::one(), zero};
    return r;
  }

  static OZZ_INLINE SoaFloat4 w_axis() {
    const SimdFloat4 zero = simd_float4::zero();
    const SoaFloat4 r = {zero, zero, zero, simd_float4::one()};
    return r;
  }
};
}  // namespace math
}  // namespace ozz

// Returns per element addition of _a and _b using operator +.
OZZ_INLINE ozz::math::SoaFloat4 operator+(const ozz::math::SoaFloat4& _a,
                                          const ozz::math::SoaFloat4& _b) {
  const ozz::math::SoaFloat4 r = {_a.x + _b.x, _a.y + _b.y, _a.z + _b.z,
                                  _a.w + _b.w};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat3 operator+(const ozz::math::SoaFloat3& _a,
                                          const ozz::math::SoaFloat3& _b) {
  const ozz::math::SoaFloat3 r = {_a.x + _b.x, _a.y + _b.y, _a.z + _b.z};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat2 operator+(const ozz::math::SoaFloat2& _a,
                                          const ozz::math::SoaFloat2& _b) {
  const ozz::math::SoaFloat2 r = {_a.x + _b.x, _a.y + _b.y};
  return r;
}

// Returns per element subtraction of _a and _b using operator -.
OZZ_INLINE ozz::math::SoaFloat4 operator-(const ozz::math::SoaFloat4& _a,
                                          const ozz::math::SoaFloat4& _b) {
  const ozz::math::SoaFloat4 r = {_a.x - _b.x, _a.y - _b.y, _a.z - _b.z,
                                  _a.w - _b.w};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat3 operator-(const ozz::math::SoaFloat3& _a,
                                          const ozz::math::SoaFloat3& _b) {
  const ozz::math::SoaFloat3 r = {_a.x - _b.x, _a.y - _b.y, _a.z - _b.z};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat2 operator-(const ozz::math::SoaFloat2& _a,
                                          const ozz::math::SoaFloat2& _b) {
  const ozz::math::SoaFloat2 r = {_a.x - _b.x, _a.y - _b.y};
  return r;
}

// Returns per element negative value of _v.
OZZ_INLINE ozz::math::SoaFloat4 operator-(const ozz::math::SoaFloat4& _v) {
  const ozz::math::SoaFloat4 r = {-_v.x, -_v.y, -_v.z, -_v.w};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat3 operator-(const ozz::math::SoaFloat3& _v) {
  const ozz::math::SoaFloat3 r = {-_v.x, -_v.y, -_v.z};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat2 operator-(const ozz::math::SoaFloat2& _v) {
  const ozz::math::SoaFloat2 r = {-_v.x, -_v.y};
  return r;
}

// Returns per element multiplication of _a and _b using operator *.
OZZ_INLINE ozz::math::SoaFloat4 operator*(const ozz::math::SoaFloat4& _a,
                                          const ozz::math::SoaFloat4& _b) {
  const ozz::math::SoaFloat4 r = {_a.x * _b.x, _a.y * _b.y, _a.z * _b.z,
                                  _a.w * _b.w};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat3 operator*(const ozz::math::SoaFloat3& _a,
                                          const ozz::math::SoaFloat3& _b) {
  const ozz::math::SoaFloat3 r = {_a.x * _b.x, _a.y * _b.y, _a.z * _b.z};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat2 operator*(const ozz::math::SoaFloat2& _a,
                                          const ozz::math::SoaFloat2& _b) {
  const ozz::math::SoaFloat2 r = {_a.x * _b.x, _a.y * _b.y};
  return r;
}

// Returns per element multiplication of _a and scalar value _f using
// operator *.
OZZ_INLINE ozz::math::SoaFloat4 operator*(const ozz::math::SoaFloat4& _a,
                                          ozz::math::_SimdFloat4 _f) {
  const ozz::math::SoaFloat4 r = {_a.x * _f, _a.y * _f, _a.z * _f, _a.w * _f};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat3 operator*(const ozz::math::SoaFloat3& _a,
                                          ozz::math::_SimdFloat4 _f) {
  const ozz::math::SoaFloat3 r = {_a.x * _f, _a.y * _f, _a.z * _f};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat2 operator*(const ozz::math::SoaFloat2& _a,
                                          ozz::math::_SimdFloat4 _f) {
  const ozz::math::SoaFloat2 r = {_a.x * _f, _a.y * _f};
  return r;
}

// Multiplies _a and _b, then adds _addend.
// v = (_a * _b) + _addend
OZZ_INLINE ozz::math::SoaFloat2 MAdd(const ozz::math::SoaFloat2& _a,
                                     const ozz::math::SoaFloat2& _b,
                                     const ozz::math::SoaFloat2& _addend) {
  const ozz::math::SoaFloat2 r = {ozz::math::MAdd(_a.x, _b.x, _addend.x),
                                  ozz::math::MAdd(_a.y, _b.y, _addend.y)};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat3 MAdd(const ozz::math::SoaFloat3& _a,
                                     const ozz::math::SoaFloat3& _b,
                                     const ozz::math::SoaFloat3& _addend) {
  const ozz::math::SoaFloat3 r = {ozz::math::MAdd(_a.x, _b.x, _addend.x),
                                  ozz::math::MAdd(_a.y, _b.y, _addend.y),
                                  ozz::math::MAdd(_a.z, _b.z, _addend.z)};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat4 MAdd(const ozz::math::SoaFloat4& _a,
                                     const ozz::math::SoaFloat4& _b,
                                     const ozz::math::SoaFloat4& _addend) {
  const ozz::math::SoaFloat4 r = {ozz::math::MAdd(_a.x, _b.x, _addend.x),
                                  ozz::math::MAdd(_a.y, _b.y, _addend.y),
                                  ozz::math::MAdd(_a.z, _b.z, _addend.z),
                                  ozz::math::MAdd(_a.w, _b.w, _addend.w)};
  return r;
}

// Returns per element division of _a and _b using operator /.
OZZ_INLINE ozz::math::SoaFloat4 operator/(const ozz::math::SoaFloat4& _a,
                                          const ozz::math::SoaFloat4& _b) {
  const ozz::math::SoaFloat4 r = {_a.x / _b.x, _a.y / _b.y, _a.z / _b.z,
                                  _a.w / _b.w};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat3 operator/(const ozz::math::SoaFloat3& _a,
                                          const ozz::math::SoaFloat3& _b) {
  const ozz::math::SoaFloat3 r = {_a.x / _b.x, _a.y / _b.y, _a.z / _b.z};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat2 operator/(const ozz::math::SoaFloat2& _a,
                                          const ozz::math::SoaFloat2& _b) {
  const ozz::math::SoaFloat2 r = {_a.x / _b.x, _a.y / _b.y};
  return r;
}

// Returns per element division of _a and scalar value _f using operator/.
OZZ_INLINE ozz::math::SoaFloat4 operator/(const ozz::math::SoaFloat4& _a,
                                          ozz::math::_SimdFloat4 _f) {
  const ozz::math::SoaFloat4 r = {_a.x / _f, _a.y / _f, _a.z / _f, _a.w / _f};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat3 operator/(const ozz::math::SoaFloat3& _a,
                                          ozz::math::_SimdFloat4 _f) {
  const ozz::math::SoaFloat3 r = {_a.x / _f, _a.y / _f, _a.z / _f};
  return r;
}
OZZ_INLINE ozz::math::SoaFloat2 operator/(const ozz::math::SoaFloat2& _a,
                                          ozz::math::_SimdFloat4 _f) {
  const ozz::math::SoaFloat2 r = {_a.x / _f, _a.y / _f};
  return r;
}

// Returns true if each element of a is less than each element of _b.
OZZ_INLINE ozz::math::SimdInt4 operator<(const ozz::math::SoaFloat4& _a,
                                         const ozz::math::SoaFloat4& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpLt(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpLt(_a.y, _b.y);
  const ozz::math::SimdInt4 z = ozz::math::CmpLt(_a.z, _b.z);
  const ozz::math::SimdInt4 w = ozz::math::CmpLt(_a.w, _b.w);
  return ozz::math::And(ozz::math::And(ozz::math::And(x, y), z), w);
}
OZZ_INLINE ozz::math::SimdInt4 operator<(const ozz::math::SoaFloat3& _a,
                                         const ozz::math::SoaFloat3& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpLt(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpLt(_a.y, _b.y);
  const ozz::math::SimdInt4 z = ozz::math::CmpLt(_a.z, _b.z);
  return ozz::math::And(ozz::math::And(x, y), z);
}
OZZ_INLINE ozz::math::SimdInt4 operator<(const ozz::math::SoaFloat2& _a,
                                         const ozz::math::SoaFloat2& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpLt(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpLt(_a.y, _b.y);
  return ozz::math::And(x, y);
}

// Returns true if each element of a is less or equal to each element of _b.
OZZ_INLINE ozz::math::SimdInt4 operator<=(const ozz::math::SoaFloat4& _a,
                                          const ozz::math::SoaFloat4& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpLe(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpLe(_a.y, _b.y);
  const ozz::math::SimdInt4 z = ozz::math::CmpLe(_a.z, _b.z);
  const ozz::math::SimdInt4 w = ozz::math::CmpLe(_a.w, _b.w);
  return ozz::math::And(ozz::math::And(ozz::math::And(x, y), z), w);
}
OZZ_INLINE ozz::math::SimdInt4 operator<=(const ozz::math::SoaFloat3& _a,
                                          const ozz::math::SoaFloat3& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpLe(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpLe(_a.y, _b.y);
  const ozz::math::SimdInt4 z = ozz::math::CmpLe(_a.z, _b.z);
  return ozz::math::And(ozz::math::And(x, y), z);
}
OZZ_INLINE ozz::math::SimdInt4 operator<=(const ozz::math::SoaFloat2& _a,
                                          const ozz::math::SoaFloat2& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpLe(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpLe(_a.y, _b.y);
  return ozz::math::And(x, y);
}

// Returns true if each element of a is greater than each element of _b.
OZZ_INLINE ozz::math::SimdInt4 operator>(const ozz::math::SoaFloat4& _a,
                                         const ozz::math::SoaFloat4& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpGt(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpGt(_a.y, _b.y);
  const ozz::math::SimdInt4 z = ozz::math::CmpGt(_a.z, _b.z);
  const ozz::math::SimdInt4 w = ozz::math::CmpGt(_a.w, _b.w);
  return ozz::math::And(ozz::math::And(ozz::math::And(x, y), z), w);
}
OZZ_INLINE ozz::math::SimdInt4 operator>(const ozz::math::SoaFloat3& _a,
                                         const ozz::math::SoaFloat3& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpGt(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpGt(_a.y, _b.y);
  const ozz::math::SimdInt4 z = ozz::math::CmpGt(_a.z, _b.z);
  return ozz::math::And(ozz::math::And(x, y), z);
}
OZZ_INLINE ozz::math::SimdInt4 operator>(const ozz::math::SoaFloat2& _a,
                                         const ozz::math::SoaFloat2& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpGt(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpGt(_a.y, _b.y);
  return ozz::math::And(x, y);
}

// Returns true if each element of a is greater or equal to each element of _b.
OZZ_INLINE ozz::math::SimdInt4 operator>=(const ozz::math::SoaFloat4& _a,
                                          const ozz::math::SoaFloat4& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpGe(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpGe(_a.y, _b.y);
  const ozz::math::SimdInt4 z = ozz::math::CmpGe(_a.z, _b.z);
  const ozz::math::SimdInt4 w = ozz::math::CmpGe(_a.w, _b.w);
  return ozz::math::And(ozz::math::And(ozz::math::And(x, y), z), w);
}
OZZ_INLINE ozz::math::SimdInt4 operator>=(const ozz::math::SoaFloat3& _a,
                                          const ozz::math::SoaFloat3& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpGe(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpGe(_a.y, _b.y);
  const ozz::math::SimdInt4 z = ozz::math::CmpGe(_a.z, _b.z);
  return ozz::math::And(ozz::math::And(x, y), z);
}
OZZ_INLINE ozz::math::SimdInt4 operator>=(const ozz::math::SoaFloat2& _a,
                                          const ozz::math::SoaFloat2& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpGe(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpGe(_a.y, _b.y);
  return ozz::math::And(x, y);
}

// Returns true if each element of _a is equal to each element of _b.
// Uses a bitwise comparison of _a and _b, no tolerance is applied.
OZZ_INLINE ozz::math::SimdInt4 operator==(const ozz::math::SoaFloat4& _a,
                                          const ozz::math::SoaFloat4& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpEq(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpEq(_a.y, _b.y);
  const ozz::math::SimdInt4 z = ozz::math::CmpEq(_a.z, _b.z);
  const ozz::math::SimdInt4 w = ozz::math::CmpEq(_a.w, _b.w);
  return ozz::math::And(ozz::math::And(ozz::math::And(x, y), z), w);
}
OZZ_INLINE ozz::math::SimdInt4 operator==(const ozz::math::SoaFloat3& _a,
                                          const ozz::math::SoaFloat3& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpEq(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpEq(_a.y, _b.y);
  const ozz::math::SimdInt4 z = ozz::math::CmpEq(_a.z, _b.z);
  return ozz::math::And(ozz::math::And(x, y), z);
}
OZZ_INLINE ozz::math::SimdInt4 operator==(const ozz::math::SoaFloat2& _a,
                                          const ozz::math::SoaFloat2& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpEq(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpEq(_a.y, _b.y);
  return ozz::math::And(x, y);
}

// Returns true if each element of a is different from each element of _b.
// Uses a bitwise comparison of _a and _b, no tolerance is applied.
OZZ_INLINE ozz::math::SimdInt4 operator!=(const ozz::math::SoaFloat4& _a,
                                          const ozz::math::SoaFloat4& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpNe(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpNe(_a.y, _b.y);
  const ozz::math::SimdInt4 z = ozz::math::CmpNe(_a.z, _b.z);
  const ozz::math::SimdInt4 w = ozz::math::CmpNe(_a.w, _b.w);
  return ozz::math::Or(ozz::math::Or(ozz::math::Or(x, y), z), w);
}
OZZ_INLINE ozz::math::SimdInt4 operator!=(const ozz::math::SoaFloat3& _a,
                                          const ozz::math::SoaFloat3& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpNe(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpNe(_a.y, _b.y);
  const ozz::math::SimdInt4 z = ozz::math::CmpNe(_a.z, _b.z);
  return ozz::math::Or(ozz::math::Or(x, y), z);
}
OZZ_INLINE ozz::math::SimdInt4 operator!=(const ozz::math::SoaFloat2& _a,
                                          const ozz::math::SoaFloat2& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpNe(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpNe(_a.y, _b.y);
  return ozz::math::Or(x, y);
}

namespace ozz {
namespace math {

// Returns the (horizontal) addition of each element of _v.
OZZ_INLINE SimdFloat4 HAdd(const SoaFloat4& _v) {
  return _v.x + _v.y + _v.z + _v.w;
}
OZZ_INLINE SimdFloat4 HAdd(const SoaFloat3& _v) { return _v.x + _v.y + _v.z; }
OZZ_INLINE SimdFloat4 HAdd(const SoaFloat2& _v) { return _v.x + _v.y; }

// Returns the dot product of _a and _b.
OZZ_INLINE SimdFloat4 Dot(const SoaFloat4& _a, const SoaFloat4& _b) {
  return _a.x * _b.x + _a.y * _b.y + _a.z * _b.z + _a.w * _b.w;
}
OZZ_INLINE SimdFloat4 Dot(const SoaFloat3& _a, const SoaFloat3& _b) {
  return _a.x * _b.x + _a.y * _b.y + _a.z * _b.z;
}
OZZ_INLINE SimdFloat4 Dot(const SoaFloat2& _a, const SoaFloat2& _b) {
  return _a.x * _b.x + _a.y * _b.y;
}

// Returns the cross product of _a and _b.
OZZ_INLINE SoaFloat3 Cross(const SoaFloat3& _a, const SoaFloat3& _b) {
  const SoaFloat3 r = {_a.y * _b.z - _b.y * _a.z, _a.z * _b.x - _b.z * _a.x,
                       _a.x * _b.y - _b.x * _a.y};
  return r;
}

// Returns the length |_v| of _v.
OZZ_INLINE SimdFloat4 Length(const SoaFloat4& _v) {
  const SimdFloat4 len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  return Sqrt(len2);
}
OZZ_INLINE SimdFloat4 Length(const SoaFloat3& _v) {
  const SimdFloat4 len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  return Sqrt(len2);
}
OZZ_INLINE SimdFloat4 Length(const SoaFloat2& _v) {
  const SimdFloat4 len2 = _v.x * _v.x + _v.y * _v.y;
  return Sqrt(len2);
}

// Returns the square length |_v|^2 of _v.
OZZ_INLINE SimdFloat4 LengthSqr(const SoaFloat4& _v) {
  return _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
}
OZZ_INLINE SimdFloat4 LengthSqr(const SoaFloat3& _v) {
  return _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
}
OZZ_INLINE SimdFloat4 LengthSqr(const SoaFloat2& _v) {
  return _v.x * _v.x + _v.y * _v.y;
}

// Returns the normalized vector _v.
OZZ_INLINE SoaFloat4 Normalize(const SoaFloat4& _v) {
  const SimdFloat4 len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  assert(AreAllTrue(CmpNe(len2, simd_float4::zero())) &&
         "_v is not normalizable");
  const SimdFloat4 inv_len = math::simd_float4::one() / Sqrt(len2);
  const SoaFloat4 r = {_v.x * inv_len, _v.y * inv_len, _v.z * inv_len,
                       _v.w * inv_len};
  return r;
}
OZZ_INLINE SoaFloat3 Normalize(const SoaFloat3& _v) {
  const SimdFloat4 len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  assert(AreAllTrue(CmpNe(len2, simd_float4::zero())) &&
         "_v is not normalizable");
  const SimdFloat4 inv_len = math::simd_float4::one() / Sqrt(len2);
  const SoaFloat3 r = {_v.x * inv_len, _v.y * inv_len, _v.z * inv_len};
  return r;
}
OZZ_INLINE SoaFloat2 Normalize(const SoaFloat2& _v) {
  const SimdFloat4 len2 = _v.x * _v.x + _v.y * _v.y;
  assert(AreAllTrue(CmpNe(len2, simd_float4::zero())) &&
         "_v is not normalizable");
  const SimdFloat4 inv_len = math::simd_float4::one() / Sqrt(len2);
  const SoaFloat2 r = {_v.x * inv_len, _v.y * inv_len};
  return r;
}

// Test if each vector _v is normalized.
OZZ_INLINE math::SimdInt4 IsNormalized(const SoaFloat4& _v) {
  const SimdFloat4 len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  return CmpLt(Abs(len2 - math::simd_float4::one()),
               simd_float4::Load1(kNormalizationToleranceSq));
}
OZZ_INLINE math::SimdInt4 IsNormalized(const SoaFloat3& _v) {
  const SimdFloat4 len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  return CmpLt(Abs(len2 - math::simd_float4::one()),
               simd_float4::Load1(kNormalizationToleranceSq));
}
OZZ_INLINE math::SimdInt4 IsNormalized(const SoaFloat2& _v) {
  const SimdFloat4 len2 = _v.x * _v.x + _v.y * _v.y;
  return CmpLt(Abs(len2 - math::simd_float4::one()),
               simd_float4::Load1(kNormalizationToleranceSq));
}

// Test if each vector _v is normalized using estimated tolerance.
OZZ_INLINE math::SimdInt4 IsNormalizedEst(const SoaFloat4& _v) {
  const SimdFloat4 len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  return CmpLt(Abs(len2 - math::simd_float4::one()),
               simd_float4::Load1(kNormalizationToleranceEstSq));
}
OZZ_INLINE math::SimdInt4 IsNormalizedEst(const SoaFloat3& _v) {
  const SimdFloat4 len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  return CmpLt(Abs(len2 - math::simd_float4::one()),
               simd_float4::Load1(kNormalizationToleranceEstSq));
}
OZZ_INLINE math::SimdInt4 IsNormalizedEst(const SoaFloat2& _v) {
  const SimdFloat4 len2 = _v.x * _v.x + _v.y * _v.y;
  return CmpLt(Abs(len2 - math::simd_float4::one()),
               simd_float4::Load1(kNormalizationToleranceEstSq));
}

// Returns the normalized vector _v if the norm of _v is not 0.
// Otherwise returns _safer.
OZZ_INLINE SoaFloat4 NormalizeSafe(const SoaFloat4& _v,
                                   const SoaFloat4& _safer) {
  assert(AreAllTrue(IsNormalizedEst(_safer)) && "_safer is not normalized");
  const SimdFloat4 len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z + _v.w * _v.w;
  const math::SimdInt4 b = CmpNe(len2, math::simd_float4::zero());
  const SimdFloat4 inv_len = math::simd_float4::one() / Sqrt(len2);
  const SoaFloat4 r = {
      Select(b, _v.x * inv_len, _safer.x), Select(b, _v.y * inv_len, _safer.y),
      Select(b, _v.z * inv_len, _safer.z), Select(b, _v.w * inv_len, _safer.w)};
  return r;
}
OZZ_INLINE SoaFloat3 NormalizeSafe(const SoaFloat3& _v,
                                   const SoaFloat3& _safer) {
  assert(AreAllTrue(IsNormalizedEst(_safer)) && "_safer is not normalized");
  const SimdFloat4 len2 = _v.x * _v.x + _v.y * _v.y + _v.z * _v.z;
  const math::SimdInt4 b = CmpNe(len2, math::simd_float4::zero());
  const SimdFloat4 inv_len = math::simd_float4::one() / Sqrt(len2);
  const SoaFloat3 r = {Select(b, _v.x * inv_len, _safer.x),
                       Select(b, _v.y * inv_len, _safer.y),
                       Select(b, _v.z * inv_len, _safer.z)};
  return r;
}
OZZ_INLINE SoaFloat2 NormalizeSafe(const SoaFloat2& _v,
                                   const SoaFloat2& _safer) {
  assert(AreAllTrue(IsNormalizedEst(_safer)) && "_safer is not normalized");
  const SimdFloat4 len2 = _v.x * _v.x + _v.y * _v.y;
  const math::SimdInt4 b = CmpNe(len2, math::simd_float4::zero());
  const SimdFloat4 inv_len = math::simd_float4::one() / Sqrt(len2);
  const SoaFloat2 r = {Select(b, _v.x * inv_len, _safer.x),
                       Select(b, _v.y * inv_len, _safer.y)};
  return r;
}

// Returns the linear interpolation of _a and _b with coefficient _f.
// _f is not limited to range [0,1].
OZZ_INLINE SoaFloat4 Lerp(const SoaFloat4& _a, const SoaFloat4& _b,
                          _SimdFloat4 _f) {
  const SoaFloat4 r = {(_b.x - _a.x) * _f + _a.x, (_b.y - _a.y) * _f + _a.y,
                       (_b.z - _a.z) * _f + _a.z, (_b.w - _a.w) * _f + _a.w};
  return r;
}
OZZ_INLINE SoaFloat3 Lerp(const SoaFloat3& _a, const SoaFloat3& _b,
                          _SimdFloat4 _f) {
  const SoaFloat3 r = {(_b.x - _a.x) * _f + _a.x, (_b.y - _a.y) * _f + _a.y,
                       (_b.z - _a.z) * _f + _a.z};
  return r;
}
OZZ_INLINE SoaFloat2 Lerp(const SoaFloat2& _a, const SoaFloat2& _b,
                          _SimdFloat4 _f) {
  const SoaFloat2 r = {(_b.x - _a.x) * _f + _a.x, (_b.y - _a.y) * _f + _a.y};
  return r;
}

// Returns the minimum of each element of _a and _b.
OZZ_INLINE SoaFloat4 Min(const SoaFloat4& _a, const SoaFloat4& _b) {
  const SoaFloat4 r = {Min(_a.x, _b.x), Min(_a.y, _b.y), Min(_a.z, _b.z),
                       Min(_a.w, _b.w)};
  return r;
}
OZZ_INLINE SoaFloat3 Min(const SoaFloat3& _a, const SoaFloat3& _b) {
  const SoaFloat3 r = {Min(_a.x, _b.x), Min(_a.y, _b.y), Min(_a.z, _b.z)};
  return r;
}
OZZ_INLINE SoaFloat2 Min(const SoaFloat2& _a, const SoaFloat2& _b) {
  const SoaFloat2 r = {Min(_a.x, _b.x), Min(_a.y, _b.y)};
  return r;
}

// Returns the maximum of each element of _a and _b.
OZZ_INLINE SoaFloat4 Max(const SoaFloat4& _a, const SoaFloat4& _b) {
  const SoaFloat4 r = {Max(_a.x, _b.x), Max(_a.y, _b.y), Max(_a.z, _b.z),
                       Max(_a.w, _b.w)};
  return r;
}
OZZ_INLINE SoaFloat3 Max(const SoaFloat3& _a, const SoaFloat3& _b) {
  const SoaFloat3 r = {Max(_a.x, _b.x), Max(_a.y, _b.y), Max(_a.z, _b.z)};
  return r;
}
OZZ_INLINE SoaFloat2 Max(const SoaFloat2& _a, const SoaFloat2& _b) {
  const SoaFloat2 r = {Max(_a.x, _b.x), Max(_a.y, _b.y)};
  return r;
}

// Clamps each element of _x between _a and _b.
// _a must be less or equal to b;
OZZ_INLINE SoaFloat4 Clamp(const SoaFloat4& _a, const SoaFloat4& _v,
                           const SoaFloat4& _b) {
  return Max(_a, Min(_v, _b));
}
OZZ_INLINE SoaFloat3 Clamp(const SoaFloat3& _a, const SoaFloat3& _v,
                           const SoaFloat3& _b) {
  return Max(_a, Min(_v, _b));
}
OZZ_INLINE SoaFloat2 Clamp(const SoaFloat2& _a, const SoaFloat2& _v,
                           const SoaFloat2& _b) {
  return Max(_a, Min(_v, _b));
}
}  // namespace math
}  // namespace ozz
#endif  // OZZ_OZZ_BASE_MATHS_SOA_FLOAT_H_
/**** ended inlining ozz/base/maths/soa_float.h ****/
/**** start inlining ozz/base/maths/soa_quaternion.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_MATHS_SOA_QUATERNION_H_
#define OZZ_OZZ_BASE_MATHS_SOA_QUATERNION_H_

#include <cassert>

/**** skipping file: ozz/base/maths/soa_float.h ****/
/**** skipping file: ozz/base/platform.h ****/

namespace ozz {
namespace math {

struct SoaQuaternion {
  SimdFloat4 x, y, z, w;

  // Loads a quaternion from 4 SimdFloat4 values.
  static OZZ_INLINE SoaQuaternion Load(_SimdFloat4 _x, _SimdFloat4 _y,
                                       _SimdFloat4 _z, const SimdFloat4& _w) {
    const SoaQuaternion r = {_x, _y, _z, _w};
    return r;
  }

  // Returns the identity SoaQuaternion.
  static OZZ_INLINE SoaQuaternion identity() {
    const SimdFloat4 zero = simd_float4::zero();
    const SoaQuaternion r = {zero, zero, zero, simd_float4::one()};
    return r;
  }
};

// Returns the conjugate of _q. This is the same as the inverse if _q is
// normalized. Otherwise the magnitude of the inverse is 1.f/|_q|.
OZZ_INLINE SoaQuaternion Conjugate(const SoaQuaternion& _q) {
  const SoaQuaternion r = {-_q.x, -_q.y, -_q.z, _q.w};
  return r;
}

// Returns the negate of _q. This represent the same rotation as q.
OZZ_INLINE SoaQuaternion operator-(const SoaQuaternion& _q) {
  const SoaQuaternion r = {-_q.x, -_q.y, -_q.z, -_q.w};
  return r;
}

// Returns the 4D dot product of quaternion _a and _b.
OZZ_INLINE SimdFloat4 Dot(const SoaQuaternion& _a, const SoaQuaternion& _b) {
  return _a.x * _b.x + _a.y * _b.y + _a.z * _b.z + _a.w * _b.w;
}

// Returns true if the angle between _a and _b is less than _tolerance.
OZZ_INLINE SimdInt4 Compare(const math::SoaQuaternion& _a,
                            const math::SoaQuaternion& _b,
                            const math::SimdFloat4 _cos_half_tolerance) {
  // Computes w component of a-1 * b.
  const SimdFloat4 cos_half_angle =
      _a.x * _b.x + _a.y * _b.y + _a.z * _b.z + _a.w * _b.w;
  return math::CmpGe(math::Abs(cos_half_angle), _cos_half_tolerance);
}

// Returns the normalized SoaQuaternion _q.
OZZ_INLINE SoaQuaternion Normalize(const SoaQuaternion& _q) {
  const SimdFloat4 len2 = _q.x * _q.x + _q.y * _q.y + _q.z * _q.z + _q.w * _q.w;
  const SimdFloat4 inv_len = math::simd_float4::one() / Sqrt(len2);
  const SoaQuaternion r = {_q.x * inv_len, _q.y * inv_len, _q.z * inv_len,
                           _q.w * inv_len};
  return r;
}

// Returns the estimated normalized SoaQuaternion _q.
OZZ_INLINE SoaQuaternion NormalizeEst(const SoaQuaternion& _q) {
  const SimdFloat4 len2 = _q.x * _q.x + _q.y * _q.y + _q.z * _q.z + _q.w * _q.w;
  // Uses RSqrtEstNR (with one more Newton-Raphson step) as quaternions loose
  // much precision due to normalization.
  const SimdFloat4 inv_len = RSqrtEstNR(len2);
  const SoaQuaternion r = {_q.x * inv_len, _q.y * inv_len, _q.z * inv_len,
                           _q.w * inv_len};
  return r;
}

// Test if each quaternion of _q is normalized.
OZZ_INLINE SimdInt4 IsNormalized(const SoaQuaternion& _q) {
  const SimdFloat4 len2 = _q.x * _q.x + _q.y * _q.y + _q.z * _q.z + _q.w * _q.w;
  return CmpLt(Abs(len2 - math::simd_float4::one()),
               simd_float4::Load1(kNormalizationToleranceSq));
}

// Test if each quaternion of _q is normalized. using estimated tolerance.
OZZ_INLINE SimdInt4 IsNormalizedEst(const SoaQuaternion& _q) {
  const SimdFloat4 len2 = _q.x * _q.x + _q.y * _q.y + _q.z * _q.z + _q.w * _q.w;
  return CmpLt(Abs(len2 - math::simd_float4::one()),
               simd_float4::Load1(kNormalizationToleranceEstSq));
}

// Returns the linear interpolation of SoaQuaternion _a and _b with coefficient
// _f.
OZZ_INLINE SoaQuaternion Lerp(const SoaQuaternion& _a, const SoaQuaternion& _b,
                              _SimdFloat4 _f) {
  const SoaQuaternion r = {(_b.x - _a.x) * _f + _a.x, (_b.y - _a.y) * _f + _a.y,
                           (_b.z - _a.z) * _f + _a.z,
                           (_b.w - _a.w) * _f + _a.w};
  return r;
}

// Returns the linear interpolation of SoaQuaternion _a and _b with coefficient
// _f.
OZZ_INLINE SoaQuaternion NLerp(const SoaQuaternion& _a, const SoaQuaternion& _b,
                               _SimdFloat4 _f) {
  const SoaFloat4 lerp = {(_b.x - _a.x) * _f + _a.x, (_b.y - _a.y) * _f + _a.y,
                          (_b.z - _a.z) * _f + _a.z, (_b.w - _a.w) * _f + _a.w};
  const SimdFloat4 len2 =
      lerp.x * lerp.x + lerp.y * lerp.y + lerp.z * lerp.z + lerp.w * lerp.w;
  const SimdFloat4 inv_len = math::simd_float4::one() / Sqrt(len2);
  const SoaQuaternion r = {lerp.x * inv_len, lerp.y * inv_len, lerp.z * inv_len,
                           lerp.w * inv_len};
  return r;
}

// Returns the estimated linear interpolation of SoaQuaternion _a and _b with
// coefficient _f.
OZZ_INLINE SoaQuaternion NLerpEst(const SoaQuaternion& _a,
                                  const SoaQuaternion& _b, _SimdFloat4 _f) {
  const SoaFloat4 lerp = {(_b.x - _a.x) * _f + _a.x, (_b.y - _a.y) * _f + _a.y,
                          (_b.z - _a.z) * _f + _a.z, (_b.w - _a.w) * _f + _a.w};
  const SimdFloat4 len2 =
      lerp.x * lerp.x + lerp.y * lerp.y + lerp.z * lerp.z + lerp.w * lerp.w;
  // Uses RSqrtEstNR (with one more Newton-Raphson step) as quaternions loose
  // much precision due to normalization.
  const SimdFloat4 inv_len = RSqrtEstNR(len2);
  const SoaQuaternion r = {lerp.x * inv_len, lerp.y * inv_len, lerp.z * inv_len,
                           lerp.w * inv_len};
  return r;
}
}  // namespace math
}  // namespace ozz

// Returns the addition of _a and _b.
OZZ_INLINE ozz::math::SoaQuaternion operator+(
    const ozz::math::SoaQuaternion& _a, const ozz::math::SoaQuaternion& _b) {
  const ozz::math::SoaQuaternion r = {_a.x + _b.x, _a.y + _b.y, _a.z + _b.z,
                                      _a.w + _b.w};
  return r;
}

// Returns the multiplication of _q and scalar value _f.
OZZ_INLINE ozz::math::SoaQuaternion operator*(
    const ozz::math::SoaQuaternion& _q, const ozz::math::SimdFloat4& _f) {
  const ozz::math::SoaQuaternion r = {_q.x * _f, _q.y * _f, _q.z * _f,
                                      _q.w * _f};
  return r;
}

// Returns the multiplication of _a and _b. If both _a and _b are normalized,
// then the result is normalized.
OZZ_INLINE ozz::math::SoaQuaternion operator*(
    const ozz::math::SoaQuaternion& _a, const ozz::math::SoaQuaternion& _b) {
  const ozz::math::SoaQuaternion r = {
      _a.w * _b.x + _a.x * _b.w + _a.y * _b.z - _a.z * _b.y,
      _a.w * _b.y + _a.y * _b.w + _a.z * _b.x - _a.x * _b.z,
      _a.w * _b.z + _a.z * _b.w + _a.x * _b.y - _a.y * _b.x,
      _a.w * _b.w - _a.x * _b.x - _a.y * _b.y - _a.z * _b.z};
  return r;
}

// Returns true if each element of _a is equal to each element of _b.
// Uses a bitwise comparison of _a and _b, no tolerance is applied.
OZZ_INLINE ozz::math::SimdInt4 operator==(const ozz::math::SoaQuaternion& _a,
                                          const ozz::math::SoaQuaternion& _b) {
  const ozz::math::SimdInt4 x = ozz::math::CmpEq(_a.x, _b.x);
  const ozz::math::SimdInt4 y = ozz::math::CmpEq(_a.y, _b.y);
  const ozz::math::SimdInt4 z = ozz::math::CmpEq(_a.z, _b.z);
  const ozz::math::SimdInt4 w = ozz::math::CmpEq(_a.w, _b.w);
  return ozz::math::And(ozz::math::And(ozz::math::And(x, y), z), w);
}
#endif  // OZZ_OZZ_BASE_MATHS_SOA_QUATERNION_H_
/**** ended inlining ozz/base/maths/soa_quaternion.h ****/
/**** skipping file: ozz/base/platform.h ****/

namespace ozz {
namespace math {

// Stores an affine transformation with separate translation, rotation and scale
// attributes.
struct SoaTransform {
  SoaFloat3 translation;
  SoaQuaternion rotation;
  SoaFloat3 scale;

  static OZZ_INLINE SoaTransform identity() {
    const SoaTransform ret = {SoaFloat3::zero(), SoaQuaternion::identity(),
                              SoaFloat3::one()};
    return ret;
  }
};
}  // namespace math
}  // namespace ozz
#endif  // OZZ_OZZ_BASE_MATHS_SOA_TRANSFORM_H_
/**** ended inlining ozz/base/maths/soa_transform.h ****/
/**** start inlining ozz/base/maths/soa_float4x4.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_MATHS_SOA_FLOAT4X4_H_
#define OZZ_OZZ_BASE_MATHS_SOA_FLOAT4X4_H_

#include <cassert>

/**** skipping file: ozz/base/maths/soa_float.h ****/
/**** skipping file: ozz/base/maths/soa_quaternion.h ****/
/**** skipping file: ozz/base/platform.h ****/

namespace ozz {
namespace math {

// Declare the 4x4 soa matrix type. Uses the column major convention where the
// matrix-times-vector is written v'=Mv:
// [ m.cols[0].x m.cols[1].x m.cols[2].x m.cols[3].x ]   {v.x}
// | m.cols[0].y m.cols[1].y m.cols[2].y m.cols[3].y | * {v.y}
// | m.cols[0].z m.cols[1].y m.cols[2].y m.cols[3].y |   {v.z}
// [ m.cols[0].w m.cols[1].w m.cols[2].w m.cols[3].w ]   {v.1}
struct SoaFloat4x4 {
  // Soa matrix columns.
  SoaFloat4 cols[4];

  // Returns the identity matrix.
  static OZZ_INLINE SoaFloat4x4 identity() {
    const SimdFloat4 zero = simd_float4::zero();
    const SimdFloat4 one = simd_float4::one();
    SoaFloat4x4 ret = {{{one, zero, zero, zero},
                        {zero, one, zero, zero},
                        {zero, zero, one, zero},
                        {zero, zero, zero, one}}};
    return ret;
  }

  // Returns a scaling matrix that scales along _v.
  // _v.w is ignored.
  static OZZ_INLINE SoaFloat4x4 Scaling(const SoaFloat4& _v) {
    const SimdFloat4 zero = simd_float4::zero();
    const SimdFloat4 one = simd_float4::one();
    const SoaFloat4x4 ret = {{{_v.x, zero, zero, zero},
                              {zero, _v.y, zero, zero},
                              {zero, zero, _v.z, zero},
                              {zero, zero, zero, one}}};
    return ret;
  }

  // Returns the rotation matrix built from quaternion defined by x, y, z and w
  // components of _v.
  static OZZ_INLINE SoaFloat4x4 FromQuaternion(const SoaQuaternion& _q) {
    assert(AreAllTrue(IsNormalizedEst(_q)));

    const SimdFloat4 zero = simd_float4::zero();
    const SimdFloat4 one = simd_float4::one();
    const SimdFloat4 two = one + one;

    const SimdFloat4 xx = _q.x * _q.x;
    const SimdFloat4 xy = _q.x * _q.y;
    const SimdFloat4 xz = _q.x * _q.z;
    const SimdFloat4 xw = _q.x * _q.w;
    const SimdFloat4 yy = _q.y * _q.y;
    const SimdFloat4 yz = _q.y * _q.z;
    const SimdFloat4 yw = _q.y * _q.w;
    const SimdFloat4 zz = _q.z * _q.z;
    const SimdFloat4 zw = _q.z * _q.w;

    const SoaFloat4x4 ret = {
        {{one - two * (yy + zz), two * (xy + zw), two * (xz - yw), zero},
         {two * (xy - zw), one - two * (xx + zz), two * (yz + xw), zero},
         {two * (xz + yw), two * (yz - xw), one - two * (xx + yy), zero},
         {zero, zero, zero, one}}};
    return ret;
  }

  // Returns the affine transformation matrix built from split translation,
  // rotation (quaternion) and scale.
  static OZZ_INLINE SoaFloat4x4 FromAffine(const SoaFloat3& _translation,
                                           const SoaQuaternion& _quaternion,
                                           const SoaFloat3& _scale) {
    assert(AreAllTrue(IsNormalizedEst(_quaternion)));

    const SimdFloat4 zero = simd_float4::zero();
    const SimdFloat4 one = simd_float4::one();
    const SimdFloat4 two = one + one;

    const SimdFloat4 xx = _quaternion.x * _quaternion.x;
    const SimdFloat4 xy = _quaternion.x * _quaternion.y;
    const SimdFloat4 xz = _quaternion.x * _quaternion.z;
    const SimdFloat4 xw = _quaternion.x * _quaternion.w;
    const SimdFloat4 yy = _quaternion.y * _quaternion.y;
    const SimdFloat4 yz = _quaternion.y * _quaternion.z;
    const SimdFloat4 yw = _quaternion.y * _quaternion.w;
    const SimdFloat4 zz = _quaternion.z * _quaternion.z;
    const SimdFloat4 zw = _quaternion.z * _quaternion.w;

    const SoaFloat4x4 ret = {
        {{_scale.x * (one - two * (yy + zz)), _scale.x * two * (xy + zw),
          _scale.x * two * (xz - yw), zero},
         {_scale.y * two * (xy - zw), _scale.y * (one - two * (xx + zz)),
          _scale.y * two * (yz + xw), zero},
         {_scale.z * two * (xz + yw), _scale.z * two * (yz - xw),
          _scale.z * (one - two * (xx + yy)), zero},
         {_translation.x, _translation.y, _translation.z, one}}};
    return ret;
  }
};

// Returns the transpose of matrix _m.
OZZ_INLINE SoaFloat4x4 Transpose(const SoaFloat4x4& _m) {
  const SoaFloat4x4 ret = {
      {{_m.cols[0].x, _m.cols[1].x, _m.cols[2].x, _m.cols[3].x},
       {_m.cols[0].y, _m.cols[1].y, _m.cols[2].y, _m.cols[3].y},
       {_m.cols[0].z, _m.cols[1].z, _m.cols[2].z, _m.cols[3].z},
       {_m.cols[0].w, _m.cols[1].w, _m.cols[2].w, _m.cols[3].w}}};
  return ret;
}

// Returns the inverse of matrix _m.
// If _invertible is not nullptr, each component will be set to true if its
// respective matrix is invertible. If _invertible is nullptr, then an assert is
// triggered in case any of the 4 matrices isn't invertible.
OZZ_INLINE SoaFloat4x4 Invert(const SoaFloat4x4& _m,
                              SimdInt4* _invertible = nullptr) {
  const SoaFloat4* cols = _m.cols;
  const SimdFloat4 a00 = cols[2].z * cols[3].w - cols[3].z * cols[2].w;
  const SimdFloat4 a01 = cols[2].y * cols[3].w - cols[3].y * cols[2].w;
  const SimdFloat4 a02 = cols[2].y * cols[3].z - cols[3].y * cols[2].z;
  const SimdFloat4 a03 = cols[2].x * cols[3].w - cols[3].x * cols[2].w;
  const SimdFloat4 a04 = cols[2].x * cols[3].z - cols[3].x * cols[2].z;
  const SimdFloat4 a05 = cols[2].x * cols[3].y - cols[3].x * cols[2].y;
  const SimdFloat4 a06 = cols[1].z * cols[3].w - cols[3].z * cols[1].w;
  const SimdFloat4 a07 = cols[1].y * cols[3].w - cols[3].y * cols[1].w;
  const SimdFloat4 a08 = cols[1].y * cols[3].z - cols[3].y * cols[1].z;
  const SimdFloat4 a09 = cols[1].x * cols[3].w - cols[3].x * cols[1].w;
  const SimdFloat4 a10 = cols[1].x * cols[3].z - cols[3].x * cols[1].z;
  const SimdFloat4 a11 = cols[1].y * cols[3].w - cols[3].y * cols[1].w;
  const SimdFloat4 a12 = cols[1].x * cols[3].y - cols[3].x * cols[1].y;
  const SimdFloat4 a13 = cols[1].z * cols[2].w - cols[2].z * cols[1].w;
  const SimdFloat4 a14 = cols[1].y * cols[2].w - cols[2].y * cols[1].w;
  const SimdFloat4 a15 = cols[1].y * cols[2].z - cols[2].y * cols[1].z;
  const SimdFloat4 a16 = cols[1].x * cols[2].w - cols[2].x * cols[1].w;
  const SimdFloat4 a17 = cols[1].x * cols[2].z - cols[2].x * cols[1].z;
  const SimdFloat4 a18 = cols[1].x * cols[2].y - cols[2].x * cols[1].y;

  const SimdFloat4 b0x = cols[1].y * a00 - cols[1].z * a01 + cols[1].w * a02;
  const SimdFloat4 b1x = -cols[1].x * a00 + cols[1].z * a03 - cols[1].w * a04;
  const SimdFloat4 b2x = cols[1].x * a01 - cols[1].y * a03 + cols[1].w * a05;
  const SimdFloat4 b3x = -cols[1].x * a02 + cols[1].y * a04 - cols[1].z * a05;

  const SimdFloat4 b0y = -cols[0].y * a00 + cols[0].z * a01 - cols[0].w * a02;
  const SimdFloat4 b1y = cols[0].x * a00 - cols[0].z * a03 + cols[0].w * a04;
  const SimdFloat4 b2y = -cols[0].x * a01 + cols[0].y * a03 - cols[0].w * a05;
  const SimdFloat4 b3y = cols[0].x * a02 - cols[0].y * a04 + cols[0].z * a05;

  const SimdFloat4 b0z = cols[0].y * a06 - cols[0].z * a07 + cols[0].w * a08;
  const SimdFloat4 b1z = -cols[0].x * a06 + cols[0].z * a09 - cols[0].w * a10;
  const SimdFloat4 b2z = cols[0].x * a11 - cols[0].y * a09 + cols[0].w * a12;
  const SimdFloat4 b3z = -cols[0].x * a08 + cols[0].y * a10 - cols[0].z * a12;

  const SimdFloat4 b0w = -cols[0].y * a13 + cols[0].z * a14 - cols[0].w * a15;
  const SimdFloat4 b1w = cols[0].x * a13 - cols[0].z * a16 + cols[0].w * a17;
  const SimdFloat4 b2w = -cols[0].x * a14 + cols[0].y * a16 - cols[0].w * a18;
  const SimdFloat4 b3w = cols[0].x * a15 - cols[0].y * a17 + cols[0].z * a18;

  const SimdFloat4 det =
      cols[0].x * b0x + cols[0].y * b1x + cols[0].z * b2x + cols[0].w * b3x;
  const SimdInt4 invertible = CmpNe(det, simd_float4::zero());
  assert((_invertible || AreAllTrue(invertible)) && "Matrix is not invertible");
  if (_invertible != nullptr) {
    *_invertible = invertible;
  }
  const SimdFloat4 inv_det =
      Select(invertible, RcpEstNR(det), simd_float4::zero());

  const SoaFloat4x4 ret = {
      {{b0x * inv_det, b0y * inv_det, b0z * inv_det, b0w * inv_det},
       {b1x * inv_det, b1y * inv_det, b1z * inv_det, b1w * inv_det},
       {b2x * inv_det, b2y * inv_det, b2z * inv_det, b2w * inv_det},
       {b3x * inv_det, b3y * inv_det, b3z * inv_det, b3w * inv_det}}};

  return ret;
}

// Scales matrix _m along the axis defined by _v components.
// _v.w is ignored.
OZZ_INLINE SoaFloat4x4 Scale(const SoaFloat4x4& _m, const SoaFloat4& _v) {
  const SoaFloat4x4 ret = {{{_m.cols[0].x * _v.x, _m.cols[0].y * _v.x,
                             _m.cols[0].z * _v.x, _m.cols[0].w * _v.x},
                            {_m.cols[1].x * _v.y, _m.cols[1].y * _v.y,
                             _m.cols[1].z * _v.y, _m.cols[1].w * _v.y},
                            {_m.cols[2].x * _v.z, _m.cols[2].y * _v.z,
                             _m.cols[2].z * _v.z, _m.cols[2].w * _v.z},
                            _m.cols[3]}};
  return ret;
}
}  // namespace math
}  // namespace ozz

// Computes the multiplication of matrix Float4x4 and vector  _v.
OZZ_INLINE ozz::math::SoaFloat4 operator*(const ozz::math::SoaFloat4x4& _m,
                                          const ozz::math::SoaFloat4& _v) {
  const ozz::math::SoaFloat4 ret = {
      _m.cols[0].x * _v.x + _m.cols[1].x * _v.y + _m.cols[2].x * _v.z +
          _m.cols[3].x * _v.w,
      _m.cols[0].y * _v.x + _m.cols[1].y * _v.y + _m.cols[2].y * _v.z +
          _m.cols[3].y * _v.w,
      _m.cols[0].z * _v.x + _m.cols[1].z * _v.y + _m.cols[2].z * _v.z +
          _m.cols[3].z * _v.w,
      _m.cols[0].w * _v.x + _m.cols[1].w * _v.y + _m.cols[2].w * _v.z +
          _m.cols[3].w * _v.w};
  return ret;
}

// Computes the multiplication of two matrices _a and _b.
OZZ_INLINE ozz::math::SoaFloat4x4 operator*(const ozz::math::SoaFloat4x4& _a,
                                            const ozz::math::SoaFloat4x4& _b) {
  const ozz::math::SoaFloat4x4 ret = {
      {_a * _b.cols[0], _a * _b.cols[1], _a * _b.cols[2], _a * _b.cols[3]}};
  return ret;
}

// Computes the per element addition of two matrices _a and _b.
OZZ_INLINE ozz::math::SoaFloat4x4 operator+(const ozz::math::SoaFloat4x4& _a,
                                            const ozz::math::SoaFloat4x4& _b) {
  const ozz::math::SoaFloat4x4 ret = {
      {{_a.cols[0].x + _b.cols[0].x, _a.cols[0].y + _b.cols[0].y,
        _a.cols[0].z + _b.cols[0].z, _a.cols[0].w + _b.cols[0].w},
       {_a.cols[1].x + _b.cols[1].x, _a.cols[1].y + _b.cols[1].y,
        _a.cols[1].z + _b.cols[1].z, _a.cols[1].w + _b.cols[1].w},
       {_a.cols[2].x + _b.cols[2].x, _a.cols[2].y + _b.cols[2].y,
        _a.cols[2].z + _b.cols[2].z, _a.cols[2].w + _b.cols[2].w},
       {_a.cols[3].x + _b.cols[3].x, _a.cols[3].y + _b.cols[3].y,
        _a.cols[3].z + _b.cols[3].z, _a.cols[3].w + _b.cols[3].w}}};
  return ret;
}

// Computes the per element subtraction of two matrices _a and _b.
OZZ_INLINE ozz::math::SoaFloat4x4 operator-(const ozz::math::SoaFloat4x4& _a,
                                            const ozz::math::SoaFloat4x4& _b) {
  const ozz::math::SoaFloat4x4 ret = {
      {{_a.cols[0].x - _b.cols[0].x, _a.cols[0].y - _b.cols[0].y,
        _a.cols[0].z - _b.cols[0].z, _a.cols[0].w - _b.cols[0].w},
       {_a.cols[1].x - _b.cols[1].x, _a.cols[1].y - _b.cols[1].y,
        _a.cols[1].z - _b.cols[1].z, _a.cols[1].w - _b.cols[1].w},
       {_a.cols[2].x - _b.cols[2].x, _a.cols[2].y - _b.cols[2].y,
        _a.cols[2].z - _b.cols[2].z, _a.cols[2].w - _b.cols[2].w},
       {_a.cols[3].x - _b.cols[3].x, _a.cols[3].y - _b.cols[3].y,
        _a.cols[3].z - _b.cols[3].z, _a.cols[3].w - _b.cols[3].w}}};
  return ret;
}
#endif  // OZZ_OZZ_BASE_MATHS_SOA_FLOAT4X4_H_
/**** ended inlining ozz/base/maths/soa_float4x4.h ****/
/**** start inlining ozz/base/containers/vector.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_CONTAINERS_VECTOR_H_
#define OZZ_OZZ_BASE_CONTAINERS_VECTOR_H_

#include <vector>

/**** start inlining ozz/base/containers/std_allocator.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_CONTAINERS_STD_ALLOCATOR_H_
#define OZZ_OZZ_BASE_CONTAINERS_STD_ALLOCATOR_H_

#include <new>

/**** start inlining ozz/base/memory/allocator.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_MEMORY_ALLOCATOR_H_
#define OZZ_OZZ_BASE_MEMORY_ALLOCATOR_H_

#include <cstddef>
#include <new>
#include <utility>

/**** skipping file: ozz/base/platform.h ****/

namespace ozz {
namespace memory {

// Forwards declare Allocator class.
class Allocator;

// Defines the default allocator accessor.
OZZ_BASE_DLL Allocator* default_allocator();

// Set the default allocator, used for all dynamic allocation inside ozz.
// Returns current memory allocator, such that in can be restored if needed.
OZZ_BASE_DLL Allocator* SetDefaulAllocator(Allocator* _allocator);

// Defines an abstract allocator class.
// Implements helper methods to allocate/deallocate POD typed objects instead of
// raw memory.
// Implements New and Delete function to allocate C++ objects, as a replacement
// of new and delete operators.
class OZZ_BASE_DLL Allocator {
 public:
  // Default virtual destructor.
  virtual ~Allocator() {}

  // Next functions are the pure virtual functions that must be implemented by
  // allocator concrete classes.

  // Allocates _size bytes on the specified _alignment boundaries.
  // Allocate function conforms with standard malloc function specifications.
  virtual void* Allocate(size_t _size, size_t _alignment) = 0;

  // Frees a block that was allocated with Allocate or Reallocate.
  // Argument _block can be nullptr.
  // Deallocate function conforms with standard free function specifications.
  virtual void Deallocate(void* _block) = 0;
};
}  // namespace memory

// ozz replacement for c++ operator new with, used to allocate with an
// ozz::memory::Allocator. Delete must be used to deallocate such object.
// It can be used for constructor with no argument:
// Type* object = New<Type>();
// or any number of argument:
// Type* object = New<Type>(1,2,3,4);
template <typename _Ty, typename... _Args>
_Ty* New(_Args&&... _args) {
  void* alloc =
      memory::default_allocator()->Allocate(sizeof(_Ty), alignof(_Ty));
  return new (alloc) _Ty(std::forward<_Args>(_args)...);
}

template <typename _Ty>
void Delete(_Ty* _object) {
  if (_object) {
    // Prevents from false "unreferenced parameter" warning when _Ty has no
    // explicit destructor.
    (void)_object;
    _object->~_Ty();
    memory::default_allocator()->Deallocate(_object);
  }
}

}  // namespace ozz
#endif  // OZZ_OZZ_BASE_MEMORY_ALLOCATOR_H_
/**** ended inlining ozz/base/memory/allocator.h ****/

namespace ozz {
// Define a STL allocator compliant allocator->
template <typename _Ty>
class StdAllocator {
 public:
  typedef _Ty value_type;                     // Element type.
  typedef value_type* pointer;                // Pointer to element.
  typedef value_type& reference;              // Reference to element.
  typedef const value_type* const_pointer;    // Constant pointer to element.
  typedef const value_type& const_reference;  // Constant reference to element.
  typedef size_t size_type;                   // Quantities of elements.
  typedef ptrdiff_t difference_type;  // Difference between two pointers.

  StdAllocator() noexcept {}
  StdAllocator(const StdAllocator&) noexcept {}

  template <class _Other>
  StdAllocator(const StdAllocator<_Other>&) noexcept {}

  template <class _Other>
  struct rebind {
    typedef StdAllocator<_Other> other;
  };

  pointer address(reference _ref) const noexcept { return &_ref; }
  const_pointer address(const_reference _ref) const noexcept { return &_ref; }

  template <class _Other, class... _Args>
  void construct(_Other* _ptr, _Args&&... _args) {
    ::new (static_cast<void*>(_ptr)) _Other(std::forward<_Args>(_args)...);
  }

  template <class _Other>
  void destroy(_Other* _ptr) {
    (void)_ptr;
    _ptr->~_Other();
  }

  // Allocates array of _Count elements.
  pointer allocate(size_t _count) noexcept {
    // Makes sure to a use c like allocator, to avoid duplicated constructor
    // calls.
    return reinterpret_cast<pointer>(memory::default_allocator()->Allocate(
        sizeof(value_type) * _count, alignof(value_type)));
  }

  // Deallocates object at _Ptr, ignores size.
  void deallocate(pointer _ptr, size_type) noexcept {
    memory::default_allocator()->Deallocate(_ptr);
  }

  size_type max_size() const noexcept {
    return (~size_type(0)) / sizeof(value_type);
  }
};

// Tests for allocator equality (always true).
template <class _Ty, class _Other>
inline bool operator==(const StdAllocator<_Ty>&,
                       const StdAllocator<_Other>&) noexcept {
  return true;
}

// Tests for allocator inequality (always false).
template <class _Ty, class _Other>
inline bool operator!=(const StdAllocator<_Ty>&,
                       const StdAllocator<_Other>&) noexcept {
  return false;
}
}  // namespace ozz
#endif  // OZZ_OZZ_BASE_CONTAINERS_STD_ALLOCATOR_H_
/**** ended inlining ozz/base/containers/std_allocator.h ****/

namespace ozz {
// Redirects std::vector to ozz::vector in order to replace std default
// allocator by ozz::StdAllocator.
template <class _Ty, class _Allocator = ozz::StdAllocator<_Ty>>
using vector = std::vector<_Ty, _Allocator>;

// Extends std::vector with two functions that gives access to the begin and the
// end of its array of elements.

// Returns the mutable begin of the array of elements, or nullptr if
// vector's empty.
template <class _Ty, class _Allocator>
inline _Ty* array_begin(std::vector<_Ty, _Allocator>& _vector) {
  return _vector.data();
}

// Returns the non-mutable begin of the array of elements, or nullptr if
// vector's empty.
template <class _Ty, class _Allocator>
inline const _Ty* array_begin(const std::vector<_Ty, _Allocator>& _vector) {
  return _vector.data();
}

// Returns the mutable end of the array of elements, or nullptr if
// vector's empty. Array end is one element past the last element of the
// array, it cannot be dereferenced.
template <class _Ty, class _Allocator>
inline _Ty* array_end(std::vector<_Ty, _Allocator>& _vector) {
  return _vector.data() + _vector.size();
}

// Returns the non-mutable end of the array of elements, or nullptr if
// vector's empty. Array end is one element past the last element of the
// array, it cannot be dereferenced.
template <class _Ty, class _Allocator>
inline const _Ty* array_end(const std::vector<_Ty, _Allocator>& _vector) {
  return _vector.data() + _vector.size();
}
}  // namespace ozz
#endif  // OZZ_OZZ_BASE_CONTAINERS_VECTOR_H_
/**** ended inlining ozz/base/containers/vector.h ****/
/**** start inlining ozz/base/span.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_SPAN_H_
#define OZZ_OZZ_BASE_SPAN_H_

/**** skipping file: ozz/base/platform.h ****/

namespace ozz {

// Defines a range [begin,end[ of objects ot type _Ty.
template <typename _Ty>
struct span {
  // Constants and types
  using element_type = _Ty;
  using value_type = _Ty;
  using index_type = size_t;
  using difference_type = ptrdiff_t;
  using pointer = _Ty*;
  using const_pointer = const _Ty*;
  using reference = _Ty&;
  using const_reference = const _Ty&;
  // Iterators
  using iterator = pointer;
  using const_iterator = const_pointer;

  // Default constructor initializes range to empty.
  span() : data_(nullptr), size_(0) {}

  // Constructs a range from its extreme values.
  span(_Ty* _begin, _Ty* _end)
      : data_(_begin), size_(static_cast<size_t>(_end - _begin)) {
    assert(_begin <= _end && "Invalid range.");
  }

  // Construct a range from a pointer to a buffer and its size, ie its number of
  // elements.
  span(_Ty* _begin, size_t _size) : data_(_begin), size_(_size) {}

  // Copy constructor.
  span(const span& _other) = default;

  // Copy operator.
  void operator=(const span& _other) {
    data_ = _other.data_;
    size_ = _other.size_;
  }

  // Construct a range from a single element.
  explicit span(_Ty& _element) : data_(&_element), size_(1) {}

  // Construct a range from an array, its size is automatically deduced.
  // It isn't declared explicit as conversion is free and safe.
  template <size_t _size>
  span(_Ty (&_array)[_size]) : data_(_array), size_(_size) {}

  // Reinitialized from an array, its size is automatically deduced.
  template <size_t _size>
  void operator=(_Ty (&_array)[_size]) {
    data_ = _array;
    size_ = _size;
  }

  // Implement cast operator to allow conversions to span<const _Ty>.
  operator span<const _Ty>() const { return {data_, size_}; }

  // Subspan

  span<element_type> first(index_type _count) const {
    assert(_count <= size_ && "Count out of range");
    return {data(), _count};
  }

  span<element_type> last(index_type _count) const {
    assert(_count <= size_ && "Count out of range");
    return {data() + size_ - _count, _count};
  }

  span<element_type> subspan(index_type _offset, index_type _count) const {
    assert(_offset <= size_ && "Offset out of range");
    assert(_count <= size_ && "Count out of range");
    assert(_offset <= size_ - _count && "Offset + count out of range");
    return {data_ + _offset, _count};
  }

  // Returns a const reference to element _i of range [begin,end[.
  _Ty& operator[](size_t _i) const {
    assert(_i < size_ && "Index out of range.");
    return data_[_i];
  }

  bool empty() const { return size_ == 0; }

  // Complies with other contiguous containers.
  _Ty* data() const { return data_; }

  // Gets the number of elements of the range.
  // This size isn't stored but computed from begin and end pointers.
  size_t size() const { return size_; }

  // Gets the size in byte of the range.
  size_t size_bytes() const { return size_ * sizeof(element_type); }

  // Iterator support
  iterator begin() const { return data_; }
  iterator end() const { return data_ + size_; }

  // Front and back accessors
  reference front() const {
    assert(size_ > 0 && "Empty span.");
    return *data_;
  }
  reference back() const {
    assert(size_ > 0 && "Empty span.");
    return *(data_ + size_ - 1);
  }

 private:
  // span begin pointer.
  _Ty* data_;

  // span end pointer, should never be dereferenced.
  size_t size_;
};

// Returns a span from an array.
template <typename _Ty, size_t _Size>
inline span<_Ty> make_span(_Ty (&_arr)[_Size]) {
  return {_arr, _Size};
}

// Returns a mutable span from a container.
template <typename _Container>
inline span<typename _Container::value_type> make_span(_Container& _container) {
  return {_container.data(), _container.size()};
}

// Returns a non mutable span from a container.
template <typename _Container>
inline span<const typename _Container::value_type> make_span(
    const _Container& _container) {
  return {_container.data(), _container.size()};
}

// As bytes
template <typename _Ty>
inline span<const byte> as_bytes(const span<_Ty>& _span) {
  return {reinterpret_cast<const byte*>(_span.data()), _span.size_bytes()};
}

template <typename _Ty>
inline span<byte> as_writable_bytes(const span<_Ty>& _span) {
  // Compilation will fail here if _Ty is const. This prevents from writing to
  // const data.
  return {reinterpret_cast<byte*>(_span.data()), _span.size_bytes()};
}

// Fills a typed span from a byte source span. Source byte span is modified to
// reflect remain size.
template <typename _Ty>
inline span<_Ty> fill_span(span<byte>& _src, size_t _count) {
  assert(ozz::IsAligned(_src.data(), alignof(_Ty)) && "Invalid alignment.");
  if (!_count) {
    return {};
  }
  const span<_Ty> ret = {reinterpret_cast<_Ty*>(_src.data()), _count};
  // Validity assertion is done by span constructor.
  _src = {reinterpret_cast<byte*>(ret.end()), _src.end()};
  return ret;
}

// Fills a typed span from a byte source span. Source byte span is modified to
// reflect remain size.
template <typename _Ret, typename _Ty>
inline span<_Ret> reinterpret_span(const span<_Ty>& _src) {
  assert(ozz::IsAligned(_src.data(), alignof(_Ret)) && "Invalid alignment.");
  assert((_src.size_bytes() % sizeof(_Ret)) == 0 && "Invalid size.");

  return {reinterpret_cast<_Ret*>(_src.begin()),
          reinterpret_cast<_Ret*>(_src.end())};
}

}  // namespace ozz
#endif  // OZZ_OZZ_BASE_SPAN_H_
/**** ended inlining ozz/base/span.h ****/
/**** start inlining ozz/base/memory/unique_ptr.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_MEMORY_UNIQUE_PTR_H_
#define OZZ_OZZ_BASE_MEMORY_UNIQUE_PTR_H_

/**** skipping file: ozz/base/memory/allocator.h ****/

#include <memory>
#include <utility>

namespace ozz {

// Defaut deleter for ozz unique_ptr, uses redirected memory allocator.
template <typename _Ty>
struct Deleter {
  Deleter() {}

  template <class _Up>
  Deleter(const Deleter<_Up>&, _Ty* = nullptr) {}

  void operator()(_Ty* _ptr) const {
    ozz::Delete(_ptr);
  }
};

// Defines ozz::unique_ptr to use ozz default deleter.
template <typename _Ty, typename _Deleter = ozz::Deleter<_Ty>>
using unique_ptr = std::unique_ptr<_Ty, _Deleter>;

// Implements make_unique to use ozz redirected memory allocator.
template <typename _Ty, typename... _Args>
unique_ptr<_Ty> make_unique(_Args&&... _args) {
  return unique_ptr<_Ty>(New<_Ty>(std::forward<_Args>(_args)...));
}
}  // namespace ozz
#endif  // OZZ_OZZ_BASE_MEMORY_UNIQUE_PTR_H_
/**** ended inlining ozz/base/memory/unique_ptr.h ****/
/**** start inlining ozz/animation/runtime/skeleton.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_ANIMATION_RUNTIME_SKELETON_H_
#define OZZ_OZZ_ANIMATION_RUNTIME_SKELETON_H_

/**** start inlining ozz/animation/runtime/export.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_ANIMATION_RUNTIME_EXPORT_H_
#define OZZ_OZZ_ANIMATION_RUNTIME_EXPORT_H_

#if defined(_MSC_VER) && defined(OZZ_USE_DYNAMIC_LINKING)

#ifdef OZZ_BUILD_ANIMATION_LIB
// Import/Export for dynamic linking while building ozz
#define OZZ_ANIMATION_DLL __declspec(dllexport)
#else
#define OZZ_ANIMATION_DLL __declspec(dllimport)
#endif
#else  // defined(_MSC_VER) && defined(OZZ_USE_DYNAMIC_LINKING)
// Static or non msvc linking
#define OZZ_ANIMATION_DLL
#endif  // defined(_MSC_VER) && defined(OZZ_USE_DYNAMIC_LINKING)

#endif  // OZZ_OZZ_ANIMATION_RUNTIME_EXPORT_H_
/**** ended inlining ozz/animation/runtime/export.h ****/
/**** start inlining ozz/base/io/archive_traits.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_IO_ARCHIVE_TRAITS_H_
#define OZZ_OZZ_BASE_IO_ARCHIVE_TRAITS_H_

// Provides traits for customizing archive serialization properties: version,
// tag... See archive.h for more details.

#include <stdint.h>
#include <cstddef>

namespace ozz {
namespace io {

// Forward declaration of archive types.
class OArchive;
class IArchive;

// Default loading and saving external declaration.
// Those template implementations aim to be specialized at compilation time by
// non-member Load and save functions. For example the specialization of the
// Save() function for a type Type is:
// void Save(OArchive& _archive, const Extrusive* _test, size_t _count) {
// }
// The Load() function receives the version _version of type _Ty at the time the
// archive was saved.
// This uses polymorphism rather than template specialization to avoid
// including the file that contains the template definition.
//
// This default function call member _Ty::Load/Save function.
template <typename _Ty>
struct Extern;

// Declares the current (compile time) version of _type.
// This macro must be used inside namespace ozz::io.
// Syntax is: OZZ_IO_TYPE_VERSION(46, Foo).
#define OZZ_IO_TYPE_VERSION(_version, _type)                 \
  static_assert(_version > 0, "Version number must be > 0"); \
  namespace internal {                                       \
  template <>                                                \
  struct Version<const _type> {                              \
    enum { kValue = _version };                              \
  };                                                         \
  }  // internal

// Declares the current (compile time) version of a template _type.
// This macro must be used inside namespace ozz::io.
// OZZ_IO_TYPE_VERSION_T1(46, typename _T1, Foo<_T1>).
#define OZZ_IO_TYPE_VERSION_T1(_version, _arg0, ...)         \
  static_assert(_version > 0, "Version number must be > 0"); \
  namespace internal {                                       \
  template <_arg0>                                           \
  struct Version<const __VA_ARGS__> {                        \
    enum { kValue = _version };                              \
  };                                                         \
  }  // internal

// Declares the current (compile time) version of a template _type.
// This macro must be used inside namespace ozz::io.
// OZZ_IO_TYPE_VERSION_T2(46, typename _T1, typename _T2, Foo<_T1, _T2>).
#define OZZ_IO_TYPE_VERSION_T2(_version, _arg0, _arg1, ...)  \
  static_assert(_version > 0, "Version number must be > 0"); \
  namespace internal {                                       \
  template <_arg0, _arg1>                                    \
  struct Version<const __VA_ARGS__> {                        \
    enum { kValue = _version };                              \
  };                                                         \
                                                             \
  }  // internal

// Declares the current (compile time) version of a template _type.
// This macro must be used inside namespace ozz::io.
// OZZ_IO_TYPE_VERSION_T3(
//   46, typename _T1, typename _T2, typename _T3, Foo<_T1, _T2, _T3>).
#define OZZ_IO_TYPE_VERSION_T3(_version, _arg0, _arg1, _arg2, ...) \
  static_assert(_version > 0, "Version number must be > 0");       \
  namespace internal {                                             \
  template <_arg0, _arg1, _arg2>                                   \
  struct Version<const __VA_ARGS__> {                              \
    enum { kValue = _version };                                    \
  };                                                               \
                                                                   \
  }  // internal

// Declares the current (compile time) version of a template _type.
// This macro must be used inside namespace ozz::io.
// OZZ_IO_TYPE_VERSION_T4(
//   46, typename _T1, typename _T2, typename _T3, typename _T4,
//   Foo<_T1, _T2, _T3, _T4>).
#define OZZ_IO_TYPE_VERSION_T4(_version, _arg0, _arg1, _arg2, _arg3, ...) \
  static_assert(_version > 0, "Version number must be > 0");              \
  namespace internal {                                                    \
  template <_arg0, _arg1, _arg2, _arg3>                                   \
  struct Version<const __VA_ARGS__> {                                     \
    enum { kValue = _version };                                           \
  };                                                                      \
  }  // internal

// Declares that _type is not versionable. Its version number is 0.
// Once a type has been declared not versionable, it cannot be changed without
// braking versioning.
// This macro must be used inside namespace ozz::io.
// Syntax is: OZZ_IO_TYPE_NOT_VERSIONABLE(Foo).
#define OZZ_IO_TYPE_NOT_VERSIONABLE(_type) \
  namespace internal {                     \
  template <>                              \
  struct Version<const _type> {            \
    enum { kValue = 0 };                   \
  };                                       \
  }  // internal

// Declares that a template _type is not versionable. Its version number is 0.
// Once a type has been declared not versionable, it cannot be changed without
// braking versioning.
// This macro must be used inside namespace ozz::io.
// Syntax is:
// OZZ_IO_TYPE_NOT_VERSIONABLE_T1(typename _T1, Foo<_T1>).
#define OZZ_IO_TYPE_NOT_VERSIONABLE_T1(_arg0, ...) \
  namespace internal {                             \
  template <_arg0>                                 \
  struct Version<const __VA_ARGS__> {              \
    enum { kValue = 0 };                           \
  };                                               \
  }  // internal

// Decline non-versionable template declaration to 2 template arguments.
// Syntax is:
// OZZ_IO_TYPE_NOT_VERSIONABLE_T2(typename _T1, typename _T2, Foo<_T1, _T2>).
#define OZZ_IO_TYPE_NOT_VERSIONABLE_T2(_arg0, _arg1, ...) \
  namespace internal {                                    \
  template <_arg0, _arg1>                                 \
  struct Version<const __VA_ARGS__> {                     \
    enum { kValue = 0 };                                  \
  };                                                      \
  }  // internal

// Decline non-versionable template declaration to 3 template arguments.
// Syntax is:
// OZZ_IO_TYPE_NOT_VERSIONABLE_T3(
//   typename _T1, typename _T2, typename _T3, Foo<_T1, _T2, _T3>).
#define OZZ_IO_TYPE_NOT_VERSIONABLE_T3(_arg0, _arg1, _arg2, ...) \
  namespace internal {                                           \
  template <_arg0, _arg1, _arg2>                                 \
  struct Version<const __VA_ARGS__> {                            \
    enum { kValue = 0 };                                         \
  };                                                             \
  }  // internal

// Decline non-versionable template declaration to 4 template arguments.
// Syntax is:
// OZZ_IO_TYPE_NOT_VERSIONABLE_T4(
//   typename _T1, typename _T2, typename _T3, typename _T4,
//   Foo<_T1, _T2, _T3, _T4>).
#define OZZ_IO_TYPE_NOT_VERSIONABLE_T4(_arg0, _arg1, _arg2, _arg3, ...) \
  namespace internal {                                                  \
  template <_arg0, _arg1, _arg2, _arg3>                                 \
  struct Version<const __VA_ARGS__> {                                   \
    enum { kValue = 0 };                                                \
  };                                                                    \
  }  // internal

// Declares the tag of a template _type.
// A tag is a c-string that can be used to check the type (through its tag) of
// the next object to be read from an archive. If no tag is defined, then no
// check is performed.
// This macro must be used inside namespace ozz::io.
// OZZ_IO_TYPE_TAG("Foo", Foo).
#define OZZ_IO_TYPE_TAG(_tag, _type)                                  \
  namespace internal {                                                \
  template <>                                                         \
  struct Tag<const _type> {                                           \
    /* Length includes null terminated character to detect partial */ \
    /* tag mapping.*/                                                 \
    enum { kTagLength = OZZ_ARRAY_SIZE(_tag) };                       \
    static const char* Get() { return _tag; }                         \
  };                                                                  \
  }  // internal

namespace internal {
// Definition of version specializable template struct.
// There's no default implementation in order to force user to define it, which
// in turn forces those who want to serialize an object to include the file that
// defines it's version. This helps with detecting issues at compile time.
template <typename _Ty>
struct Version;

// Defines default tag value, which is disabled.
template <typename _Ty>
struct Tag {
  enum { kTagLength = 0 };
};
}  // namespace internal
}  // namespace io
}  // namespace ozz
#endif  // OZZ_OZZ_BASE_IO_ARCHIVE_TRAITS_H_
/**** ended inlining ozz/base/io/archive_traits.h ****/
/**** skipping file: ozz/base/platform.h ****/
/**** skipping file: ozz/base/span.h ****/

namespace ozz {
namespace io {
class IArchive;
class OArchive;
}  // namespace io
namespace math {
struct SoaTransform;
}
namespace animation {

// Forward declaration of SkeletonBuilder, used to instantiate a skeleton.
namespace offline {
class SkeletonBuilder;
}

// This runtime skeleton data structure provides a const-only access to joint
// hierarchy, joint names and rest-pose. This structure is filled by the
// SkeletonBuilder and can be serialize/deserialized.
// Joint names, rest-poses and hierarchy information are all stored in separate
// arrays of data (as opposed to joint structures for the RawSkeleton), in order
// to closely match with the way runtime algorithms use them. Joint hierarchy is
// packed as an array of parent jont indices (16 bits), stored in depth-first
// order. This is enough to traverse the whole joint hierarchy. See
// IterateJointsDF() from skeleton_utils.h that implements a depth-first
// traversal utility.
class OZZ_ANIMATION_DLL Skeleton {
 public:
  // Defines Skeleton constant values.
  enum Constants {

    // Defines the maximum number of joints.
    // This is limited in order to control the number of bits required to store
    // a joint index. Limiting the number of joints also helps handling worst
    // size cases, like when it is required to allocate an array of joints on
    // the stack.
    kMaxJoints = 1024,

    // Defines the maximum number of SoA elements required to store the maximum
    // number of joints.
    kMaxSoAJoints = (kMaxJoints + 3) / 4,

    // Defines the index of the parent of the root joint (which has no parent in
    // fact).
    kNoParent = -1,
  };

  // Builds a default skeleton.
  Skeleton() = default;

  // Allow move.
  Skeleton(Skeleton&&);
  Skeleton& operator=(Skeleton&&);

  // Disables copy and assignation.
  Skeleton(Skeleton const&) = delete;
  Skeleton& operator=(Skeleton const&) = delete;

  // Declares the public non-virtual destructor.
  ~Skeleton();

  // Returns the number of joints of *this skeleton.
  int num_joints() const { return static_cast<int>(joint_parents_.size()); }

  // Returns the number of soa elements matching the number of joints of *this
  // skeleton. This value is useful to allocate SoA runtime data structures.
  int num_soa_joints() const { return (num_joints() + 3) / 4; }

  // Returns joint's rest poses. Rest poses are stored in soa format.
  span<const math::SoaTransform> joint_rest_poses() const {
    return joint_rest_poses_;
  }

  // Returns joint's parent indices range.
  span<const int16_t> joint_parents() const { return joint_parents_; }

  // Returns joint's name collection.
  span<const char* const> joint_names() const {
    return span<const char* const>(joint_names_.begin(), joint_names_.end());
  }

  // Serialization functions.
  // Should not be called directly but through io::Archive << and >> operators.
  void Save(ozz::io::OArchive& _archive) const;
  void Load(ozz::io::IArchive& _archive, uint32_t _version);

 private:
  // Internal allocation/deallocation function.
  // Allocate returns the beginning of the contiguous buffer of names.
  char* Allocate(size_t _char_count, size_t _num_joints);
  void Deallocate();

  // SkeletonBuilder class is allowed to instantiate an Skeleton.
  friend class offline::SkeletonBuilder;

  // Allocation for the whole skeleton.
  void* allocation_ = nullptr;

  // Buffers below store joint informations in joing depth first order. Their
  // size is equal to the number of joints of the skeleton.

  // Rest pose of every joint in local space.
  span<math::SoaTransform> joint_rest_poses_;

  // Array of joint parent indexes.
  span<int16_t> joint_parents_;

  // Stores the name of every joint in an array of c-strings.
  span<char*> joint_names_;
};
}  // namespace animation

namespace io {
OZZ_IO_TYPE_VERSION(2, animation::Skeleton)
OZZ_IO_TYPE_TAG("ozz-skeleton", animation::Skeleton)
}  // namespace io
}  // namespace ozz
#endif  // OZZ_OZZ_ANIMATION_RUNTIME_SKELETON_H_
/**** ended inlining ozz/animation/runtime/skeleton.h ****/
/**** start inlining ozz/animation/runtime/local_to_model_job.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_ANIMATION_RUNTIME_LOCAL_TO_MODEL_JOB_H_
#define OZZ_OZZ_ANIMATION_RUNTIME_LOCAL_TO_MODEL_JOB_H_

/**** skipping file: ozz/animation/runtime/export.h ****/
/**** skipping file: ozz/animation/runtime/skeleton.h ****/
/**** skipping file: ozz/base/platform.h ****/
/**** skipping file: ozz/base/span.h ****/

namespace ozz {

// Forward declaration math structures.
namespace math {
struct SoaTransform;
}
namespace math {
struct Float4x4;
}

namespace animation {

// Forward declares the Skeleton object used to describe joint hierarchy.
class Skeleton;

// Computes model-space joint matrices from local-space SoaTransform.
// This job uses the skeleton to define joints parent-child hierarchy. The job
// iterates through all joints to compute their transform relatively to the
// skeleton root.
// Job inputs is an array of SoaTransform objects (in local-space), ordered like
// skeleton's joints. Job output is an array of matrices (in model-space),
// ordered like skeleton's joints. Output are matrices, because the combination
// of affine transformations can contain shearing or complex transformation
// that cannot be represented as Transform object.
struct OZZ_ANIMATION_DLL LocalToModelJob {
  // Validates job parameters. Returns true for a valid job, or false otherwise:
  // -if any input pointer, including ranges, is nullptr.
  // -if the size of the input is smaller than the skeleton's number of joints.
  // Note that this input has a SoA format.
  // -if the size of of the output is smaller than the skeleton's number of
  // joints.
  bool Validate() const;

  // Runs job's local-to-model task.
  // The job is validated before any operation is performed, see Validate() for
  // more details.
  // Returns false if job is not valid. See Validate() function.
  bool Run() const;

  // Job input.

  // The Skeleton object describing the joint hierarchy used for local to
  // model space conversion.
  const Skeleton* skeleton = nullptr;

  // The root matrix will multiply to every model space matrices, default
  // nullptr means an identity matrix. This can be used to directly compute
  // world-space transforms for example.
  const ozz::math::Float4x4* root = nullptr;

  // Defines "from" which joint the local-to-model conversion should start.
  // Default value is ozz::Skeleton::kNoParent, meaning the whole hierarchy is
  // updated. This parameter can be used to optimize update by limiting
  // conversion to part of the joint hierarchy. Note that "from" parent should
  // be a valid matrix, as it is going to be used as part of "from" joint
  // hierarchy update.
  int from = Skeleton::kNoParent;

  // Defines "to" which joint the local-to-model conversion should go, "to"
  // included. Update will end before "to" joint is reached if "to" is not part
  // of the hierarchy starting from "from". Default value is
  // ozz::animation::Skeleton::kMaxJoints, meaning the hierarchy (starting from
  // "from") is updated to the last joint.
  int to = Skeleton::kMaxJoints;

  // If true, "from" joint is not updated during job execution. Update starts
  // with all children of "from". This can be used to update a model-space
  // transform independently from the local-space one. To do so: set "from"
  // joint model-space transform matrix, and run this Job with "from_excluded"
  // to update all "from" children.
  // Default value is false.
  bool from_excluded = false;

  // The input range that store local transforms.
  span<const ozz::math::SoaTransform> input;

  // Job output.

  // The output range to be filled with model-space matrices.
  span<ozz::math::Float4x4> output;
};
}  // namespace animation
}  // namespace ozz
#endif  // OZZ_OZZ_ANIMATION_RUNTIME_LOCAL_TO_MODEL_JOB_H_
/**** ended inlining ozz/animation/runtime/local_to_model_job.h ****/
/**** start inlining ozz/animation/offline/raw_skeleton.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_ANIMATION_OFFLINE_RAW_SKELETON_H_
#define OZZ_OZZ_ANIMATION_OFFLINE_RAW_SKELETON_H_

/**** start inlining ozz/animation/offline/export.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_ANIMATION_OFFLINE_EXPORT_H_
#define OZZ_OZZ_ANIMATION_OFFLINE_EXPORT_H_

#if defined(_MSC_VER) && defined(OZZ_USE_DYNAMIC_LINKING)

#ifdef OZZ_BUILD_ANIMOFFLINE_LIB
// Import/Export for dynamic linking while building ozz
#define OZZ_ANIMOFFLINE_DLL __declspec(dllexport)
#else
#define OZZ_ANIMOFFLINE_DLL __declspec(dllimport)
#endif
#else  // defined(_MSC_VER) && defined(OZZ_USE_DYNAMIC_LINKING)
// Static or non msvc linking
#define OZZ_ANIMOFFLINE_DLL
#endif  // defined(_MSC_VER) && defined(OZZ_USE_DYNAMIC_LINKING)

#endif  // OZZ_OZZ_ANIMATION_OFFLINE_EXPORT_H_
/**** ended inlining ozz/animation/offline/export.h ****/
/**** start inlining ozz/base/containers/string.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_BASE_CONTAINERS_STRING_H_
#define OZZ_OZZ_BASE_CONTAINERS_STRING_H_

#include <string>

/**** skipping file: ozz/base/containers/std_allocator.h ****/

namespace ozz {
// Redirects std::basic_string to ozz::string in order to replace std default
// allocator by ozz::StdAllocator.
using string =
    std::basic_string<char, std::char_traits<char>, ozz::StdAllocator<char>>;
}  // namespace ozz
#endif  // OZZ_OZZ_BASE_CONTAINERS_STRING_H_
/**** ended inlining ozz/base/containers/string.h ****/
/**** skipping file: ozz/base/containers/vector.h ****/
/**** skipping file: ozz/base/io/archive_traits.h ****/
/**** skipping file: ozz/base/maths/transform.h ****/

namespace ozz {
namespace animation {
namespace offline {

// Off-line skeleton type.
// This skeleton type is not intended to be used in run time. It is used to
// define the offline skeleton object that can be converted to the runtime
// skeleton using the SkeletonBuilder. This skeleton structure exposes joints'
// hierarchy. A joint is defined with a name, a transformation (its rest_pose
// pose), and its children. Children are exposed as a public std::vector of
// joints. This same type is used for skeleton roots, also exposed from the
// public API. The public API exposed through std:vector's of joints can be used
// freely with the only restriction that the total number of joints does not
// exceed Skeleton::kMaxJoints.
struct OZZ_ANIMOFFLINE_DLL RawSkeleton {
  // Construct an empty skeleton.
  RawSkeleton();

  // The destructor is responsible for deleting the roots and their hierarchy.
  ~RawSkeleton();

  // Offline skeleton joint type.
  struct Joint {
    // Type of the list of children joints.
    typedef ozz::vector<Joint> Children;

    // Children joints.
    Children children;

    // The name of the joint.
    ozz::string name;

    // Joint rest pose transformation in local space.
    math::Transform transform;
  };

  // Tests for *this validity.
  // Returns true on success or false on failure if the number of joints exceeds
  // ozz::Skeleton::kMaxJoints.
  bool Validate() const;

  // Returns the number of joints of *this animation.
  // This function is not constant time as it iterates the hierarchy of joints
  // and counts them.
  int num_joints() const;

  // Declares the skeleton's roots. Can be empty if the skeleton has no joint.
  Joint::Children roots;
};

namespace {
// Internal function used to iterate through joint hierarchy depth-first.
template <typename _Fct>
inline void _IterHierarchyRecurseDF(
    const RawSkeleton::Joint::Children& _children,
    const RawSkeleton::Joint* _parent, _Fct& _fct) {
  for (size_t i = 0; i < _children.size(); ++i) {
    const RawSkeleton::Joint& current = _children[i];
    _fct(current, _parent);
    _IterHierarchyRecurseDF(current.children, &current, _fct);
  }
}

// Internal function used to iterate through joint hierarchy breadth-first.
template <typename _Fct>
inline void _IterHierarchyRecurseBF(
    const RawSkeleton::Joint::Children& _children,
    const RawSkeleton::Joint* _parent, _Fct& _fct) {
  for (size_t i = 0; i < _children.size(); ++i) {
    const RawSkeleton::Joint& current = _children[i];
    _fct(current, _parent);
  }
  for (size_t i = 0; i < _children.size(); ++i) {
    const RawSkeleton::Joint& current = _children[i];
    _IterHierarchyRecurseBF(current.children, &current, _fct);
  }
}
}  // namespace

// Applies a specified functor to each joint in a depth-first order.
// _Fct is of type void(const Joint& _current, const Joint* _parent) where the
// first argument is the child of the second argument. _parent is null if the
// _current joint is the root.
template <typename _Fct>
inline _Fct IterateJointsDF(const RawSkeleton& _skeleton, _Fct _fct) {
  _IterHierarchyRecurseDF(_skeleton.roots, nullptr, _fct);
  return _fct;
}

// Applies a specified functor to each joint in a breadth-first order.
// _Fct is of type void(const Joint& _current, const Joint* _parent) where the
// first argument is the child of the second argument. _parent is null if the
// _current joint is the root.
template <typename _Fct>
inline _Fct IterateJointsBF(const RawSkeleton& _skeleton, _Fct _fct) {
  _IterHierarchyRecurseBF(_skeleton.roots, nullptr, _fct);
  return _fct;
}
}  // namespace offline
}  // namespace animation
namespace io {
OZZ_IO_TYPE_VERSION(1, animation::offline::RawSkeleton)
OZZ_IO_TYPE_TAG("ozz-raw_skeleton", animation::offline::RawSkeleton)

// Should not be called directly but through io::Archive << and >> operators.
template <>
struct OZZ_ANIMOFFLINE_DLL Extern<animation::offline::RawSkeleton> {
  static void Save(OArchive& _archive,
                   const animation::offline::RawSkeleton* _skeletons,
                   size_t _count);
  static void Load(IArchive& _archive,
                   animation::offline::RawSkeleton* _skeletons, size_t _count,
                   uint32_t _version);
};
}  // namespace io
}  // namespace ozz
#endif  // OZZ_OZZ_ANIMATION_OFFLINE_RAW_SKELETON_H_
/**** ended inlining ozz/animation/offline/raw_skeleton.h ****/
/**** start inlining ozz/animation/offline/skeleton_builder.h ****/
//----------------------------------------------------------------------------//
//                                                                            //
// ozz-animation is hosted at http://github.com/guillaumeblanc/ozz-animation  //
// and distributed under the MIT License (MIT).                               //
//                                                                            //
// Copyright (c) Guillaume Blanc                                              //
//                                                                            //
// Permission is hereby granted, free of charge, to any person obtaining a    //
// copy of this software and associated documentation files (the "Software"), //
// to deal in the Software without restriction, including without limitation  //
// the rights to use, copy, modify, merge, publish, distribute, sublicense,   //
// and/or sell copies of the Software, and to permit persons to whom the      //
// Software is furnished to do so, subject to the following conditions:       //
//                                                                            //
// The above copyright notice and this permission notice shall be included in //
// all copies or substantial portions of the Software.                        //
//                                                                            //
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR //
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,   //
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL    //
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER //
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING    //
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER        //
// DEALINGS IN THE SOFTWARE.                                                  //
//                                                                            //
//----------------------------------------------------------------------------//

#ifndef OZZ_OZZ_ANIMATION_OFFLINE_SKELETON_BUILDER_H_
#define OZZ_OZZ_ANIMATION_OFFLINE_SKELETON_BUILDER_H_

/**** skipping file: ozz/animation/offline/export.h ****/
/**** skipping file: ozz/base/maths/transform.h ****/
/**** skipping file: ozz/base/memory/unique_ptr.h ****/

namespace ozz {
namespace animation {

// Forward declares the runtime skeleton type.
class Skeleton;

namespace offline {

// Forward declares the offline skeleton type.
struct RawSkeleton;

// Defines the class responsible of building Skeleton instances.
class OZZ_ANIMOFFLINE_DLL SkeletonBuilder {
 public:
  // Creates a Skeleton based on _raw_skeleton and *this builder parameters.
  // Returns a Skeleton instance on success, an empty unique_ptr on failure. See
  // RawSkeleton::Validate() for more details about failure reasons.
  // The skeleton is returned as an unique_ptr as ownership is given back to the
  // caller.
  ozz::unique_ptr<ozz::animation::Skeleton> operator()(
      const RawSkeleton& _raw_skeleton) const;
};
}  // namespace offline
}  // namespace animation
}  // namespace ozz
#endif  // OZZ_OZZ_ANIMATION_OFFLINE_SKELETON_BUILDER_H_
/**** ended inlining ozz/animation/offline/skeleton_builder.h ****/

extern "C" {

int ozz_probe_math() {
  using namespace ozz::math;
  Float3 a(1.f, 2.f, 3.f);
  Float3 b(4.f, 5.f, 6.f);
  const float d = Dot(a, b);
  const Float3 c = Cross(a, b);
  if (d != 32.f) return 0;
  if (c.x != -3.f || c.y != 6.f || c.z != -3.f) return 0;
  const Quaternion q = Quaternion::FromAxisAngle(Float3(0.f, 0.f, 1.f), 1.57079632679f);
  const Float3 r = TransformVector(q, Float3(1.f, 0.f, 0.f));
  if (r.x < -0.01f || r.x > 0.01f) return 0;
  if (r.y < 0.99f || r.y > 1.01f) return 0;
  return 1;
}

static ozz::unique_ptr<ozz::animation::Skeleton> ozz_build_probe_skeleton() {
  ozz::animation::offline::RawSkeleton raw;
  raw.roots.resize(1);
  raw.roots[0].name = "root";
  raw.roots[0].children.resize(1);
  raw.roots[0].children[0].name = "child";
  raw.roots[0].children[0].transform.translation = ozz::math::Float3(0.f, 1.f, 0.f);
  ozz::animation::offline::SkeletonBuilder builder;
  return builder(raw);
}

int ozz_probe_skeleton() {
  ozz::unique_ptr<ozz::animation::Skeleton> skel = ozz_build_probe_skeleton();
  if (!skel) return 0;
  if (skel->num_joints() != 2) return 0;
  ozz::span<const int16_t> parents = skel->joint_parents();
  if (parents[0] != -1) return 0;
  if (parents[1] != 0) return 0;
  return 1;
}

int ozz_probe_local_to_model() {
  using namespace ozz::math;
  ozz::unique_ptr<ozz::animation::Skeleton> skel = ozz_build_probe_skeleton();
  if (!skel) return 0;
  ozz::vector<SoaTransform> locals(skel->num_soa_joints(), SoaTransform::identity());
  locals[0].translation.y = simd_float4::Load(0.f, 1.f, 0.f, 0.f);
  ozz::vector<Float4x4> models(skel->num_joints());
  ozz::animation::LocalToModelJob job;
  job.skeleton = skel.get();
  job.input = ozz::make_span(locals);
  job.output = ozz::make_span(models);
  if (!job.Run()) return 0;
  if (GetX(models[0].cols[3]) != 0.f || GetY(models[0].cols[3]) != 0.f || GetZ(models[0].cols[3]) != 0.f) return 0;
  if (GetY(models[1].cols[3]) < 0.99f || GetY(models[1].cols[3]) > 1.01f) return 0;
  return 1;
}

int ozz_probe_all() {
  int r = 0;
  if (!ozz_probe_math()) r |= 1;
  if (!ozz_probe_skeleton()) r |= 2;
  if (!ozz_probe_local_to_model()) r |= 4;
  return r;
}

} /* extern "C" */
