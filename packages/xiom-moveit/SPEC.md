# xiom-moveit -- SPEC

**Phase**: 3 (Robotics) | **Priority**: Medium
**Status**: Implemented | **Depends on**: xiom.ffi

MoveIt -- Motion planning framework. System-installed. Week effort.

## Files

| File | Lines | Description |
|------|-------|------------|
| `moveit.xi` | 237 | Core module: 4 types, 10 extern "C" FFI declarations, 13 safe wrapper functions |
| `tests/test_conformance.xi` | 274 | 16 conformance tests across 6 sections |
| `ROADMAP.md` | 54 | Roadmap and next steps |
| `SPEC.md` | -- | This file |

## Types (4)

- `RobotModel` -- opaque handle (Int)
- `PlanningScene` -- opaque handle (Int)
- `MotionPlan` -- opaque handle (Int)
- `CollisionObject` -- opaque handle (Int)

## Constants (6)

- `SHAPE_BOX`, `SHAPE_SPHERE`, `SHAPE_CYLINDER`, `SHAPE_MESH`
- `PLAN_TIME_DEFAULT` (5.0), `PLAN_TIME_FAST` (1.0)

## extern "C" FFI (10)

`moveit_robot_model_load`, `moveit_robot_model_free`, `moveit_planning_scene_create`, `moveit_planning_scene_free`, `moveit_scene_set_robot_model`, `moveit_scene_add_box`, `moveit_scene_add_sphere`, `moveit_plan`, `moveit_plan_free`, `moveit_plan_trajectory_points`, `moveit_plan_trajectory_point`

## Public API (13 functions)

`robot_model_load`, `robot_model_free`, `robot_model_joint_count`, `planning_scene_create`, `planning_scene_free`, `scene_set_robot_model`, `scene_add_box`, `scene_add_sphere`, `plan`, `plan_free`, `plan_trajectory_points`, `plan_trajectory_point`

## Contracts (16)

15 requires + 2 ensures across 13 functions.

## Test Suite (16 tests)

- Section 1: Type declarations (4)
- Section 2: Shape constants (2)
- Section 3: Robot model lifecycle (2)
- Section 4: Planning scene lifecycle (3)
- Section 5: Motion planning (3)
- Section 6: Trajectory queries (2)
