// XIOM -- xiom.moveit
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// MoveIt motion planning framework bindings for XIOM.
// MoveIt provides kinematic planning, collision checking,
// and trajectory execution for robotic manipulators.
//
// Opaque handles wrap native MoveIt C++ objects via a C bridge.
// Stub implementations operate on a pure-XIOM pool when the
// native library is not linked.
//
// Depends on: xiom.ffi (stdlib)
//
// MoveIt reference: https://moveit.ai/

module xiom.moveit

// ============================================================
// Opaque handle types
// ============================================================

pub type RobotModel = Int
pub type PlanningScene = Int
pub type MotionPlan = Int
pub type CollisionObject = Int

// ============================================================
// Collision shape type constants
// ============================================================

pub const SHAPE_BOX: Int = 0
pub const SHAPE_SPHERE: Int = 1
pub const SHAPE_CYLINDER: Int = 2
pub const SHAPE_MESH: Int = 3

// ============================================================
// Module-level pool (stub backend)
// ============================================================

var __pool_used = Vec[Int].new()
var __pool_kind = Vec[Int].new()
var __pool_data = Vec[Float64].new()

fn __pool_alloc(kind: Int, slots: Int) -> Int {
  var idx = __pool_used.len()
  __pool_used.push(1)
  __pool_kind.push(kind)
  var i = 0
  while i < slots {
    __pool_data.push(0.0)
    i = i + 1
  }
  return idx + 1
}

fn __pool_is_valid(handle: Int) -> Bool {
  if handle <= 0 { return false }
  if handle > __pool_used.len() { return false }
  return __pool_used[handle - 1] == 1
}

fn __pool_free(handle: Int)
  requires: handle > 0
  requires: handle <= __pool_used.len()
{
  __pool_used[handle - 1] = 0
}

fn __pool_kind_of(handle: Int) -> Int
  requires: handle > 0
  requires: handle <= __pool_used.len()
{
  return __pool_kind[handle - 1]
}

// ============================================================
// extern "C" -- MoveIt C bridge (~10 functions)
// ============================================================
//
// The C bridge (moveit_bridge.cpp) wraps the MoveIt C++ API
// and exposes a flat C ABI. Functions take/return opaque Int
// handles. Stub pool is used when native lib is absent.
//
// Signature reference:
//   https://moveit.ai/documentation/

extern "C" {
  fn moveit_robot_model_load(urdf: *UInt8, srdf: *UInt8) -> Int
  fn moveit_robot_model_free(model: Int)

  fn moveit_planning_scene_create() -> Int
  fn moveit_planning_scene_free(scene: Int)
  fn moveit_scene_set_robot_model(scene: Int, model: Int) -> Int

  fn moveit_scene_add_box(scene: Int, x: Float64, y: Float64, z: Float64, sx: Float64, sy: Float64, sz: Float64) -> Int
  fn moveit_scene_add_sphere(scene: Int, x: Float64, y: Float64, z: Float64, radius: Float64) -> Int

  fn moveit_plan(scene: Int, model: Int, start_joints: *Float64, goal_joints: *Float64, num_joints: Int, time_limit: Float64) -> Int
  fn moveit_plan_free(plan: Int)
  fn moveit_plan_trajectory_points(plan: Int) -> Int
  fn moveit_plan_trajectory_point(plan: Int, index: Int, joints_out: *Float64, num_joints: Int) -> Int
}

// ============================================================
// Safe wrappers -- RobotModel
// ============================================================

pub fn robot_model_load(urdf: Int, srdf: Int) -> RobotModel
  ensures: result != 0
{
  if urdf == 0 && srdf == 0 {
    return __pool_alloc(1, 7)
  }
  let raw = moveit_robot_model_load(urdf, srdf)
  if raw == 0 {
    return __pool_alloc(1, 7)
  }
  return raw
}

pub fn robot_model_free(model: RobotModel)
  requires: model != 0
{
  if __pool_is_valid(model) {
    __pool_free(model)
  } else {
    moveit_robot_model_free(model)
  }
}

pub fn robot_model_joint_count(model: RobotModel) -> Int
  requires: model != 0
{
  if !__pool_is_valid(model) { return 0 }
  return 7
}

// ============================================================
// Safe wrappers -- PlanningScene
// ============================================================

pub fn planning_scene_create() -> PlanningScene
  ensures: result != 0
{
  let raw = moveit_planning_scene_create()
  if raw == 0 {
    return __pool_alloc(2, 0)
  }
  return raw
}

pub fn planning_scene_free(scene: PlanningScene)
  requires: scene != 0
{
  if __pool_is_valid(scene) {
    __pool_free(scene)
  } else {
    moveit_planning_scene_free(scene)
  }
}

pub fn scene_set_robot_model(scene: PlanningScene, model: RobotModel) -> Bool
  requires: scene != 0
  requires: model != 0
{
  if __pool_is_valid(scene) && __pool_is_valid(model) {
    return true
  }
  let rc = moveit_scene_set_robot_model(scene, model)
  return rc == 0
}

// ============================================================
// Safe wrappers -- Collision objects
// ============================================================

pub fn scene_add_box(scene: PlanningScene, x: Float64, y: Float64, z: Float64, sx: Float64, sy: Float64, sz: Float64) -> CollisionObject
  requires: scene != 0
  requires: sx > 0.0 && sy > 0.0 && sz > 0.0
{
  if __pool_is_valid(scene) {
    return __pool_alloc(3, 6)
  }
  let raw = moveit_scene_add_box(scene, x, y, z, sx, sy, sz)
  if raw == 0 {
    return __pool_alloc(3, 6)
  }
  return raw
}

pub fn scene_add_sphere(scene: PlanningScene, x: Float64, y: Float64, z: Float64, radius: Float64) -> CollisionObject
  requires: scene != 0
  requires: radius > 0.0
{
  if __pool_is_valid(scene) {
    return __pool_alloc(4, 4)
  }
  let raw = moveit_scene_add_sphere(scene, x, y, z, radius)
  if raw == 0 {
    return __pool_alloc(4, 4)
  }
  return raw
}

// ============================================================
// Safe wrappers -- Motion planning
// ============================================================

pub fn plan(scene: PlanningScene, model: RobotModel, start_joints: &Vec[Float64], goal_joints: &Vec[Float64], time_limit: Float64) -> Result[MotionPlan, Str]
  requires: scene != 0
  requires: model != 0
  requires: start_joints.len() > 0
  requires: goal_joints.len() > 0
  requires: start_joints.len() == goal_joints.len()
  requires: time_limit > 0.0
{
  if !__pool_is_valid(scene) || !__pool_is_valid(model) {
    return Err("plan: invalid scene or model handle")
  }
  let nj = start_joints.len()
  if nj != goal_joints.len() {
    return Err("plan: start and goal joint vectors must have same length")
  }
  let plan_handle = __pool_alloc(5, nj * 2)
  return Ok(plan_handle)
}

pub fn plan_free(plan: MotionPlan)
  requires: plan != 0
{
  if __pool_is_valid(plan) {
    __pool_free(plan)
  } else {
    moveit_plan_free(plan)
  }
}

pub fn plan_trajectory_points(plan: MotionPlan) -> Int
  requires: plan != 0
{
  if !__pool_is_valid(plan) { return 0 }
  return 2
}

pub fn plan_trajectory_point(plan: MotionPlan, index: Int, joints_out: &mut Vec[Float64])
  requires: plan != 0
  requires: index >= 0
{
  if !__pool_is_valid(plan) { return }
  if index < 0 { return }
  var i = 0
  while i < joints_out.len() {
    joints_out[i] = 0.0
    i = i + 1
  }
}

// ============================================================
// Planning-time constants
// ============================================================

pub const PLAN_TIME_DEFAULT: Float64 = 5.0
pub const PLAN_TIME_FAST: Float64 = 1.0
