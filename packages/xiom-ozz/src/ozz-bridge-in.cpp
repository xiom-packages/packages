/*
 * xiom.ozz bridge template -- combined into a single TU with the ozz headers
 * it needs (no include-path support in the xiom link line).  See SPEC.md.
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

int ozz_probe_all() {
  int r = 0;
  if (!ozz_probe_math()) r |= 1;
  if (!ozz_probe_skeleton()) r |= 2;
  if (!ozz_probe_local_to_model()) r |= 4;
  if (!ozz_probe_clip()) r |= 8;
  return r;
}

} /* extern "C" */
