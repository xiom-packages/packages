/*
 * xiom.ozz bridge template -- combined into a single TU with the ozz headers
 * it needs (no include-path support in the xiom link line).  See SPEC.md.
 *
 * 0.4.0 caller surface: xozz_clip_build/info/sample/release let XIOM pass
 * caller keys (times + rotation/translation/scale) and sample a built clip
 * at a caller time into XIOM-owned buffers.  Built clips are owned here (a
 * slot registry) and referenced from XIOM by a plain integer handle that
 * only this TU ever turns back into a pointer (B-25).  The xozz_ prefix
 * keeps extern symbols disjoint from the public XIOM wrappers (the lzfse
 * self-recursion lesson: a wrapper named like its extern recurses).
 */
#include "ozz/base/maths/vec_float.h"
#include "ozz/base/maths/quaternion.h"
#include "ozz/base/maths/simd_math.h"
#include "ozz/base/maths/soa_transform.h"
#include "ozz/base/maths/soa_float4x4.h"
#include "ozz/base/containers/vector.h"
#include "ozz/base/span.h"
#include "ozz/base/memory/unique_ptr.h"
#include "ozz/animation/runtime/skeleton.h"
#include "ozz/animation/runtime/local_to_model_job.h"
#include "ozz/animation/runtime/animation.h"
#include "ozz/animation/runtime/sampling_job.h"
#include "ozz/animation/offline/raw_skeleton.h"
#include "ozz/animation/offline/skeleton_builder.h"
#include "ozz/animation/offline/raw_animation.h"
#include "ozz/animation/offline/animation_builder.h"

// Caller-surface rc codes (mirror the OZZ_ERR_* constants in ozz.xi).
enum {
  OZZ_RC_OK = 0,
  OZZ_RC_ARGS = -1,
  OZZ_RC_HANDLE = -2,
  OZZ_RC_KEYS = -3,
  OZZ_RC_BUILD = -4,
  OZZ_RC_CAPACITY = -5,
  OZZ_RC_TIME = -6,
  OZZ_RC_INTERNAL = -7
};

namespace {

// Clip registry: built runtime Animations owned by the bridge, referenced
// from XIOM by handle = slot index + 1 (0 and negatives are errors).
struct OzzClipSlot {
  ozz::unique_ptr<ozz::animation::Animation> anim;
};

ozz::vector<OzzClipSlot>& ozz_clip_slots() {
  static ozz::vector<OzzClipSlot> slots;
  return slots;
}

// Resolves a caller handle; NULL when unknown (released handles included).
ozz::animation::Animation* ozz_clip_lookup(int64_t _handle) {
  ozz::vector<OzzClipSlot>& slots = ozz_clip_slots();
  if (_handle <= 0 || static_cast<size_t>(_handle) > slots.size()) {
    return nullptr;
  }
  return slots[static_cast<size_t>(_handle - 1)].anim.get();
}

// Reads lane `_lane` (0..3 = X..W) of an SoA float vector.
float ozz_soa_lane(const ozz::math::SimdFloat4& _v, int _lane) {
  switch (_lane) {
    case 0: return ozz::math::GetX(_v);
    case 1: return ozz::math::GetY(_v);
    case 2: return ozz::math::GetZ(_v);
    default: return ozz::math::GetW(_v);
  }
}

// Canonical caller fixture shared by ozz_probe_caller: the root track is
// static; the child track translates y=1 -> y=3, rotates 90 degrees about Z
// and scales 1 -> 2 over one second.  Each key record is 11 floats:
// [time, rx, ry, rz, rw, tx, ty, tz, sx, sy, sz].
const float kOzzCallerCounts[2] = {1.f, 2.f};
const float kOzzCallerKeys[33] = {
    0.f, 0.f, 0.f, 0.f, 1.f, 0.f, 0.f, 0.f, 1.f, 1.f, 1.f,
    0.f, 0.f, 0.f, 0.f, 1.f, 0.f, 1.f, 0.f, 1.f, 1.f, 1.f,
    1.f, 0.f, 0.f, 0.70710678f, 0.70710678f, 0.f, 3.f, 0.f, 2.f, 2.f, 2.f,
};

}  // namespace

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

int ozz_probe_clip() {
  using namespace ozz::math;
  ozz::unique_ptr<ozz::animation::Skeleton> skel = ozz_build_probe_skeleton();
  if (!skel) return 0;
  if (skel->num_joints() != 2) return 0;

  // Two-track raw clip: the child translates y=1 -> y=3 over one second.
  ozz::animation::offline::RawAnimation raw;
  raw.duration = 1.f;
  raw.tracks.resize(2);
  raw.tracks[0].translations.resize(2);
  raw.tracks[0].translations[0].time = 0.f;
  raw.tracks[0].translations[0].value = Float3(0.f, 0.f, 0.f);
  raw.tracks[0].translations[1].time = 1.f;
  raw.tracks[0].translations[1].value = Float3(0.f, 0.f, 0.f);
  raw.tracks[1].translations.resize(2);
  raw.tracks[1].translations[0].time = 0.f;
  raw.tracks[1].translations[0].value = Float3(0.f, 1.f, 0.f);
  raw.tracks[1].translations[1].time = 1.f;
  raw.tracks[1].translations[1].value = Float3(0.f, 3.f, 0.f);
  if (!raw.Validate()) return 0;

  ozz::animation::offline::AnimationBuilder builder;
  ozz::unique_ptr<ozz::animation::Animation> anim = builder(raw);
  if (!anim) return 0;
  if (anim->num_tracks() != 2) return 0;
  if (anim->duration() < 0.99f || anim->duration() > 1.01f) return 0;

  ozz::vector<SoaTransform> output(anim->num_soa_tracks(), SoaTransform::identity());
  ozz::animation::SamplingJob::Context context(anim->num_tracks());
  ozz::animation::SamplingJob job;
  job.animation = anim.get();
  job.context = &context;
  job.output = ozz::make_span(output);

  // Midpoint: linear interpolation -> child y == 2, root stays at 0.
  job.ratio = 0.5f;
  if (!job.Run()) return 0;
  const float root_y = GetX(output[0].translation.y);
  const float mid_y = GetY(output[0].translation.y);
  if (root_y < -0.001f || root_y > 0.001f) return 0;
  if (mid_y < 1.999f || mid_y > 2.001f) return 0;

  // End: child y == 3.
  job.ratio = 1.f;
  if (!job.Run()) return 0;
  const float end_y = GetY(output[0].translation.y);
  if (end_y < 2.999f || end_y > 3.001f) return 0;
  return 1;
}

// --- caller surface (0.4.0) -------------------------------------------------

// Builds a runtime Animation of `_track_count` tracks from caller keys into
// registry-owned storage.  `_counts[t]` is track t's key count (as float);
// `_keys` holds every track's records back to back, 11 floats each:
// [time, rx, ry, rz, rw, tx, ty, tz, sx, sy, sz].  All three channels of a
// track share the record times; RawAnimation requires strictly ascending
// times within [0, duration].  Returns a handle > 0 or a negative rc.
int64_t xozz_clip_build(int32_t _track_count, const float* _counts,
                        const float* _keys, int32_t _key_float_count,
                        float _duration) {
  if (_track_count <= 0 || !_counts || !_keys || _key_float_count <= 0) {
    return OZZ_RC_ARGS;
  }
  if (!(_duration > 0.f)) {  // Rejects NaN too (the builder needs duration > 0).
    return OZZ_RC_ARGS;
  }
  int total_keys = 0;
  for (int32_t t = 0; t < _track_count; ++t) {
    const float count = _counts[t];
    if (!(count >= 1.f) || count > 1000000.f) return OZZ_RC_ARGS;
    total_keys += static_cast<int>(count);
  }
  if (total_keys * 11 != _key_float_count) return OZZ_RC_ARGS;

  ozz::animation::offline::RawAnimation raw;
  raw.duration = _duration;
  raw.tracks.resize(static_cast<size_t>(_track_count));
  int record = 0;
  for (int32_t t = 0; t < _track_count; ++t) {
    const int count = static_cast<int>(_counts[t]);
    ozz::animation::offline::RawAnimation::JointTrack& track =
        raw.tracks[static_cast<size_t>(t)];
    track.rotations.resize(static_cast<size_t>(count));
    track.translations.resize(static_cast<size_t>(count));
    track.scales.resize(static_cast<size_t>(count));
    for (int k = 0; k < count; ++k, ++record) {
      const float* r = _keys + static_cast<size_t>(record) * 11;
      const float time = r[0];
      track.rotations[static_cast<size_t>(k)].time = time;
      track.rotations[static_cast<size_t>(k)].value =
          ozz::math::Quaternion(r[1], r[2], r[3], r[4]);
      track.translations[static_cast<size_t>(k)].time = time;
      track.translations[static_cast<size_t>(k)].value =
          ozz::math::Float3(r[5], r[6], r[7]);
      track.scales[static_cast<size_t>(k)].time = time;
      track.scales[static_cast<size_t>(k)].value =
          ozz::math::Float3(r[8], r[9], r[10]);
    }
  }
  if (!raw.Validate()) return OZZ_RC_KEYS;

  ozz::animation::offline::AnimationBuilder builder;
  ozz::unique_ptr<ozz::animation::Animation> anim = builder(raw);
  if (!anim) return OZZ_RC_BUILD;

  ozz::vector<OzzClipSlot>& slots = ozz_clip_slots();
  if (slots.size() >= 65535) return OZZ_RC_INTERNAL;
  OzzClipSlot slot;
  slot.anim = std::move(anim);
  slots.push_back(std::move(slot));
  return static_cast<int64_t>(slots.size());
}

// Writes [duration, num_tracks, num_joints] into `_out` (>= 3 floats).
int xozz_clip_info(int64_t _handle, float* _out, int32_t _out_cap) {
  if (!_out || _out_cap < 3) return OZZ_RC_ARGS;
  ozz::animation::Animation* anim = ozz_clip_lookup(_handle);
  if (!anim) return OZZ_RC_HANDLE;
  _out[0] = anim->duration();
  _out[1] = static_cast<float>(anim->num_tracks());
  _out[2] = static_cast<float>(anim->num_tracks());
  return OZZ_RC_OK;
}

// Samples the clip at `_time` (seconds; within [0, duration]) and writes the
// per-joint local pose into `_out` (>= num_tracks * 10 floats):
// rotation xyzw (4) + translation xyz (3) + scale xyz (3) per joint.
int xozz_clip_sample(int64_t _handle, float _time, float* _out,
                     int32_t _out_cap) {
  if (!_out || _out_cap <= 0) return OZZ_RC_ARGS;
  ozz::animation::Animation* anim = ozz_clip_lookup(_handle);
  if (!anim) return OZZ_RC_HANDLE;
  const int joints = anim->num_tracks();
  if (joints <= 0) return OZZ_RC_INTERNAL;
  if (_out_cap < joints * 10) return OZZ_RC_CAPACITY;
  if (!(_time >= 0.f)) return OZZ_RC_TIME;  // Rejects NaN too.
  const float duration = anim->duration();
  if (_time > duration) return OZZ_RC_TIME;

  const float ratio = _time / duration;  // duration > 0 (builder contract).
  ozz::vector<ozz::math::SoaTransform> locals(
      static_cast<size_t>(anim->num_soa_tracks()),
      ozz::math::SoaTransform::identity());
  ozz::animation::SamplingJob::Context context(joints);
  ozz::animation::SamplingJob job;
  job.animation = anim;
  job.context = &context;
  job.ratio = ratio;
  job.output = ozz::make_span(locals);
  if (!job.Run()) return OZZ_RC_INTERNAL;

  for (int j = 0; j < joints; ++j) {
    const ozz::math::SoaTransform& t = locals[static_cast<size_t>(j >> 2)];
    const int lane = j & 3;
    float* o = _out + static_cast<size_t>(j) * 10;
    o[0] = ozz_soa_lane(t.rotation.x, lane);
    o[1] = ozz_soa_lane(t.rotation.y, lane);
    o[2] = ozz_soa_lane(t.rotation.z, lane);
    o[3] = ozz_soa_lane(t.rotation.w, lane);
    o[4] = ozz_soa_lane(t.translation.x, lane);
    o[5] = ozz_soa_lane(t.translation.y, lane);
    o[6] = ozz_soa_lane(t.translation.z, lane);
    o[7] = ozz_soa_lane(t.scale.x, lane);
    o[8] = ozz_soa_lane(t.scale.y, lane);
    o[9] = ozz_soa_lane(t.scale.z, lane);
  }
  return OZZ_RC_OK;
}

// Releases a clip slot; the handle is unknown afterwards.
int xozz_clip_release(int64_t _handle) {
  ozz::vector<OzzClipSlot>& slots = ozz_clip_slots();
  if (_handle <= 0 || static_cast<size_t>(_handle) > slots.size()) {
    return OZZ_RC_HANDLE;
  }
  OzzClipSlot& slot = slots[static_cast<size_t>(_handle - 1)];
  if (!slot.anim) return OZZ_RC_HANDLE;
  slot.anim.reset();
  return OZZ_RC_OK;
}

// Caller-surface probe: build from the canonical fixture, sample at t=0 and
// t=duration, check the typed bounds/handle/capacity rcs, then verify
// build + sample determinism across two clips and a released handle.
int ozz_probe_caller() {
  int64_t clip = xozz_clip_build(2, kOzzCallerCounts, kOzzCallerKeys, 33, 1.f);
  if (clip <= 0) return 0;

  float info[3];
  if (xozz_clip_info(clip, info, 3) != OZZ_RC_OK) return 0;
  if (info[0] < 0.99f || info[0] > 1.01f) return 0;
  if (info[1] != 2.f || info[2] != 2.f) return 0;

  float pose[20];
  // t = 0: both joints at their first keys.
  if (xozz_clip_sample(clip, 0.f, pose, 20) != OZZ_RC_OK) return 0;
  if (pose[0] > 0.0001f || pose[0] < -0.0001f) return 0;
  if (pose[3] < 0.9999f || pose[3] > 1.0001f) return 0;
  if (pose[15] < 0.9999f || pose[15] > 1.0001f) return 0;  // child y == 1
  if (pose[17] < 0.9999f || pose[17] > 1.0001f) return 0;  // child scale 1
  if (pose[12] > 0.0001f || pose[12] < -0.0001f) return 0;
  if (pose[13] < 0.9999f || pose[13] > 1.0001f) return 0;

  // t = duration: child y == 3, scale 2, 90-degree Z rotation.  Ozz stores
  // keyframes quantized (rotation components ~1.6e-4, time ratios ~2^-12),
  // so end values land within 1e-3 of the caller keys -- the same tolerance
  // the fixed-scenario clip probe uses.
  if (xozz_clip_sample(clip, 1.f, pose, 20) != OZZ_RC_OK) return 0;
  if (pose[15] < 2.999f || pose[15] > 3.001f) return 0;
  if (pose[17] < 1.999f || pose[17] > 2.001f) return 0;
  if (pose[12] < 0.7061f || pose[12] > 0.7081f) return 0;
  if (pose[13] < 0.7061f || pose[13] > 0.7081f) return 0;

  // Bounds and handles: typed rcs, never a write past the cap.
  if (xozz_clip_sample(clip, 1.5f, pose, 20) != OZZ_RC_TIME) return 0;
  if (xozz_clip_sample(clip, -0.25f, pose, 20) != OZZ_RC_TIME) return 0;
  if (xozz_clip_sample(9999, 0.5f, pose, 20) != OZZ_RC_HANDLE) return 0;
  if (xozz_clip_sample(clip, 0.5f, pose, 19) != OZZ_RC_CAPACITY) return 0;

  // Determinism: a second build of the same data samples identically, and
  // resampling one clip is stable.
  int64_t clip2 = xozz_clip_build(2, kOzzCallerCounts, kOzzCallerKeys, 33, 1.f);
  if (clip2 <= 0) return 0;
  float a[20];
  float b[20];
  if (xozz_clip_sample(clip, 0.5f, a, 20) != OZZ_RC_OK) return 0;
  if (xozz_clip_sample(clip2, 0.5f, b, 20) != OZZ_RC_OK) return 0;
  for (int i = 0; i < 20; ++i) {
    if (a[i] != b[i]) return 0;
  }
  if (xozz_clip_sample(clip, 0.5f, b, 20) != OZZ_RC_OK) return 0;
  for (int i = 0; i < 20; ++i) {
    if (a[i] != b[i]) return 0;
  }

  // Release contract.
  if (xozz_clip_release(clip) != OZZ_RC_OK) return 0;
  if (xozz_clip_sample(clip, 0.5f, pose, 20) != OZZ_RC_HANDLE) return 0;
  if (xozz_clip_release(clip) != OZZ_RC_HANDLE) return 0;
  if (xozz_clip_release(clip2) != OZZ_RC_OK) return 0;

  // Rejected builds: bad duration, bad track count, bad buffer length, and
  // key times outside [0, duration].
  if (xozz_clip_build(2, kOzzCallerCounts, kOzzCallerKeys, 33, 0.f) != OZZ_RC_ARGS) return 0;
  if (xozz_clip_build(0, kOzzCallerCounts, kOzzCallerKeys, 33, 1.f) != OZZ_RC_ARGS) return 0;
  if (xozz_clip_build(2, kOzzCallerCounts, kOzzCallerKeys, 32, 1.f) != OZZ_RC_ARGS) return 0;
  float late_keys[33];
  for (int i = 0; i < 33; ++i) late_keys[i] = kOzzCallerKeys[i];
  late_keys[2 * 11] = 2.f;  // Last key time beyond the duration.
  if (xozz_clip_build(2, kOzzCallerCounts, late_keys, 33, 1.f) != OZZ_RC_KEYS) return 0;
  return 1;
}

int ozz_probe_all() {
  int r = 0;
  if (!ozz_probe_math()) r |= 1;
  if (!ozz_probe_skeleton()) r |= 2;
  if (!ozz_probe_local_to_model()) r |= 4;
  if (!ozz_probe_clip()) r |= 8;
  if (!ozz_probe_caller()) r |= 16;
  return r;
}

} /* extern "C" */
