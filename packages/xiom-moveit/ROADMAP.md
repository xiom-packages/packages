# xiom.moveit -- ROADMAP

**Phase**: 3 (Robotics) | **Status**: In Progress

## Completed
- [x] SPEC.md -- scope and dependency declaration
- [x] moveit.xi -- `module xiom.moveit`: 4 types (RobotModel, PlanningScene, MotionPlan, CollisionObject), 4 shape constants, 10 extern "C" FFI declarations, 13 safe wrapper functions with requires/ensures contracts
- [x] tests/test_conformance.xi -- 16 conformance tests (compile-time and runtime)

## Next Steps
- [ ] Build C bridge library (`moveit_bridge`) for xiom FFI ABI compatibility
- [ ] Add URDF/SRDF file loading (`moveit_robot_model_load_from_file`)
- [ ] Add joint limits query (`moveit_robot_model_get_joint_limits`)
- [ ] Add link/collision geometry enumeration
- [ ] Add Cartesian path planning (`moveit_plan_cartesian`)
- [ ] Add plan execution status (`moveit_execute`, `moveit_get_execution_status`)
- [ ] Add collision checking (`moveit_check_collision`)
- [ ] Add kinematic group support (`moveit_robot_model_get_group_names`)
- [ ] Add planning scene differencing (`moveit_scene_diff`, `moveit_scene_apply_diff`)
- [ ] Add mesh collision object loading from STL/DAE
- [ ] Performance benchmarks (complex scenes, 7-DOF arms)
- [ ] CI/CD integration with MoveIt system install

## Dependencies
- `xiom.ffi` -- FFI type definitions and marshaling
- System: MoveIt 2 (ROS 2 Humble+) or standalone libmoveit

## API Surface

| Function | Signature | Contracts | Status |
|----------|-----------|-----------|--------|
| `robot_model_load` | `(urdf: Int, srdf: Int) -> RobotModel` | `ensures result != 0` | [OK] |
| `robot_model_free` | `(model: RobotModel)` | `requires model != 0` | [OK] |
| `robot_model_joint_count` | `(model: RobotModel) -> Int` | `requires model != 0` | [OK] |
| `planning_scene_create` | `() -> PlanningScene` | `ensures result != 0` | [OK] |
| `planning_scene_free` | `(scene: PlanningScene)` | `requires scene != 0` | [OK] |
| `scene_set_robot_model` | `(scene: PlanningScene, model: RobotModel) -> Bool` | `requires scene != 0, model != 0` | [OK] |
| `scene_add_box` | `(scene, x, y, z, sx, sy, sz) -> CollisionObject` | `requires scene != 0, sx > 0, sy > 0, sz > 0` | [OK] |
| `scene_add_sphere` | `(scene, x, y, z, radius) -> CollisionObject` | `requires scene != 0, radius > 0` | [OK] |
| `plan` | `(scene, model, start, goal, time_limit) -> Result[MotionPlan, Str]` | `requires 6 preconditions` | [OK] |
| `plan_free` | `(plan: MotionPlan)` | `requires plan != 0` | [OK] |
| `plan_trajectory_points` | `(plan: MotionPlan) -> Int` | `requires plan != 0` | [OK] |
| `plan_trajectory_point` | `(plan, index, joints_out)` | `requires plan != 0, index >= 0` | [OK] |

## Extern "C" Surface

| C Function | XIOM Signature |
|------------|---------------|
| `moveit_robot_model_load` | `(urdf: *UInt8, srdf: *UInt8) -> Int` |
| `moveit_robot_model_free` | `(model: Int)` |
| `moveit_planning_scene_create` | `() -> Int` |
| `moveit_planning_scene_free` | `(scene: Int)` |
| `moveit_scene_set_robot_model` | `(scene: Int, model: Int) -> Int` |
| `moveit_scene_add_box` | `(scene, x, y, z, sx, sy, sz) -> Int` |
| `moveit_scene_add_sphere` | `(scene, x, y, z, radius) -> Int` |
| `moveit_plan` | `(scene, model, start, goal, nj, time) -> Int` |
| `moveit_plan_free` | `(plan: Int)` |
| `moveit_plan_trajectory_points` | `(plan: Int) -> Int` |
| `moveit_plan_trajectory_point` | `(plan, idx, joints_out, nj) -> Int` |
