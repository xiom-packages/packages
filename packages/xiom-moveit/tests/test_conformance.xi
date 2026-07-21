// XIOM — xiom.moveit conformance test suite
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// 12 conformance tests covering: type declarations, module lifecycle,
// collision object creation, motion planning contracts,
// shape constants, and plan trajectory queries.
// Returns 0 on full pass, nonzero on first failure.

module xiom.moveit.test_conformance
use xiom.moveit

// ============================================================
// Section 1 — Type declarations (4)
// ============================================================

fn test_type_robot_model() -> Bool {
  var m: RobotModel = 0
  m = m
  return true
}

fn test_type_planning_scene() -> Bool {
  var s: PlanningScene = 0
  s = s
  return true
}

fn test_type_motion_plan() -> Bool {
  var p: MotionPlan = 0
  p = p
  return true
}

fn test_type_collision_object() -> Bool {
  var c: CollisionObject = 0
  c = c
  return true
}

// ============================================================
// Section 2 — Shape constants (2)
// ============================================================

fn test_shape_constants_distinct() -> Bool {
  return SHAPE_BOX == 0 &&
         SHAPE_SPHERE == 1 &&
         SHAPE_CYLINDER == 2 &&
         SHAPE_MESH == 3
}

fn test_shape_constants_range() -> Bool {
  return SHAPE_BOX != SHAPE_SPHERE &&
         SHAPE_SPHERE != SHAPE_CYLINDER &&
         SHAPE_CYLINDER != SHAPE_MESH
}

// ============================================================
// Section 3 — Robot model lifecycle (2)
// ============================================================

fn test_robot_model_load_free() -> Bool {
  let m = robot_model_load(0, 0)
  if m == 0 { return false }
  robot_model_free(m)
  return true
}

fn test_robot_model_joint_count() -> Bool {
  let m = robot_model_load(0, 0)
  if m == 0 { return false }
  let count = robot_model_joint_count(m)
  robot_model_free(m)
  return count == 7
}

// ============================================================
// Section 4 — Planning scene lifecycle (3)
// ============================================================

fn test_planning_scene_create_free() -> Bool {
  let s = planning_scene_create()
  if s == 0 { return false }
  planning_scene_free(s)
  return true
}

fn test_scene_set_robot_model() -> Bool {
  let s = planning_scene_create()
  let m = robot_model_load(0, 0)
  if s == 0 || m == 0 {
    return false
  }
  let ok = scene_set_robot_model(s, m)
  planning_scene_free(s)
  robot_model_free(m)
  return ok
}

fn test_scene_add_collision_objects() -> Bool {
  let s = planning_scene_create()
  if s == 0 { return false }
  let m = robot_model_load(0, 0)
  if m == 0 {
    planning_scene_free(s)
    return false
  }
  let _ = scene_set_robot_model(s, m)
  let box = scene_add_box(s, 0.0, 0.0, 0.5, 1.0, 1.0, 0.2)
  let sphere = scene_add_sphere(s, 1.0, 0.0, 0.8, 0.3)
  let ok = box != 0 && sphere != 0 && box != sphere
  planning_scene_free(s)
  robot_model_free(m)
  return ok
}

// ============================================================
// Section 5 — Motion planning (3)
// ============================================================

fn test_plan_valid() -> Bool {
  let s = planning_scene_create()
  let m = robot_model_load(0, 0)
  if s == 0 || m == 0 {
    return false
  }
  let _ = scene_set_robot_model(s, m)
  var start = Vec[Float64].new()
  var goal = Vec[Float64].new()
  var i = 0
  while i < 7 {
    start.push(0.0)
    goal.push(0.0)
    i = i + 1
  }
  match plan(s, m, &start, &goal, PLAN_TIME_DEFAULT) {
    Ok(p) => {
      plan_free(p)
      robot_model_free(m)
      planning_scene_free(s)
      return true
    }
    Err(_) => {
      robot_model_free(m)
      planning_scene_free(s)
      return false
    }
  }
}

fn test_plan_mismatched_joint_counts() -> Bool {
  let s = planning_scene_create()
  let m = robot_model_load(0, 0)
  if s == 0 || m == 0 {
    return false
  }
  let _ = scene_set_robot_model(s, m)
  var start = Vec[Float64].new()
  var goal = Vec[Float64].new()
  start.push(0.0)
  start.push(0.0)
  goal.push(0.0)
  match plan(s, m, &start, &goal, PLAN_TIME_FAST) {
    Ok(_) => {
      robot_model_free(m)
      planning_scene_free(s)
      return false
    }
    Err(_) => {
      robot_model_free(m)
      planning_scene_free(s)
      return true
    }
  }
}

fn test_plan_time_limit_positive() -> Bool {
  let s = planning_scene_create()
  let m = robot_model_load(0, 0)
  if s == 0 || m == 0 {
    return false
  }
  let _ = scene_set_robot_model(s, m)
  var start = Vec[Float64].new()
  var goal = Vec[Float64].new()
  start.push(0.0)
  goal.push(0.0)
  match plan(s, m, &start, &goal, 0.0) {
    Ok(_) => {
      robot_model_free(m)
      planning_scene_free(s)
      return false
    }
    Err(_) => {
      robot_model_free(m)
      planning_scene_free(s)
      return true
    }
  }
}

// ============================================================
// Section 6 — Trajectory queries (2)
// ============================================================

fn test_plan_trajectory_points() -> Bool {
  let s = planning_scene_create()
  let m = robot_model_load(0, 0)
  if s == 0 || m == 0 {
    return false
  }
  let _ = scene_set_robot_model(s, m)
  var start = Vec[Float64].new()
  var goal = Vec[Float64].new()
  var i = 0
  while i < 7 {
    start.push(0.0)
    goal.push(0.0)
    i = i + 1
  }
  match plan(s, m, &start, &goal, PLAN_TIME_DEFAULT) {
    Ok(p) => {
      let pts = plan_trajectory_points(p)
      let ok = pts == 2
      plan_free(p)
      robot_model_free(m)
      planning_scene_free(s)
      return ok
    }
    Err(_) => {
      robot_model_free(m)
      planning_scene_free(s)
      return false
    }
  }
}

fn test_plan_trajectory_point_read() -> Bool {
  let s = planning_scene_create()
  let m = robot_model_load(0, 0)
  if s == 0 || m == 0 {
    return false
  }
  let _ = scene_set_robot_model(s, m)
  var start = Vec[Float64].new()
  var goal = Vec[Float64].new()
  var i = 0
  while i < 7 {
    start.push(0.0)
    goal.push(1.0)
    i = i + 1
  }
  match plan(s, m, &start, &goal, PLAN_TIME_DEFAULT) {
    Ok(p) => {
      var joints = Vec[Float64].new()
      var k = 0
      while k < 7 {
        joints.push(0.0)
        k = k + 1
      }
      plan_trajectory_point(p, 0, &mut joints)
      let all_zero = joints[0] == 0.0 && joints[3] == 0.0 && joints[6] == 0.0
      plan_free(p)
      robot_model_free(m)
      planning_scene_free(s)
      return all_zero
    }
    Err(_) => {
      robot_model_free(m)
      planning_scene_free(s)
      return false
    }
  }
}

// ============================================================
// Test runner
// ============================================================

fn main() -> Int {
  if !test_type_robot_model() { return 1 }
  if !test_type_planning_scene() { return 2 }
  if !test_type_motion_plan() { return 3 }
  if !test_type_collision_object() { return 4 }
  if !test_shape_constants_distinct() { return 5 }
  if !test_shape_constants_range() { return 6 }
  if !test_robot_model_load_free() { return 7 }
  if !test_robot_model_joint_count() { return 8 }
  if !test_planning_scene_create_free() { return 9 }
  if !test_scene_set_robot_model() { return 10 }
  if !test_scene_add_collision_objects() { return 11 }
  if !test_plan_valid() { return 12 }
  if !test_plan_mismatched_joint_counts() { return 13 }
  if !test_plan_time_limit_positive() { return 14 }
  if !test_plan_trajectory_points() { return 15 }
  if !test_plan_trajectory_point_read() { return 16 }
  return 0
}
