# xiom.gazebo -- SPEC

**Phase**: 3 (Robotics) | **Priority**: Medium
**Status**: Implemented | **Depends on**: xiom.ffi, xiom.io, xiom.test

Gazebo -- Robot simulation engine (gz-sim / Ignition Gazebo). System-installed. Week effort.

## Files

| File | Lines | Description |
|------|-------|------------|
| `gazebo.xi` | 174 | Core module: 4 types, 12 extern "C" FFI declarations, 14 safe wrapper functions |
| `tests/test_conformance.xi` | 437 | 47 conformance tests across 6 sections |
| `ROADMAP.md` | 29 | Roadmap and next steps |
| `SPEC.md` | -- | This file |

## Types (4)

- `World` -- opaque handle (Int)
- `Model` -- opaque handle (Int)
- `Joint` -- opaque handle (Int)
- `Sensor` -- opaque handle (Int)

## Constants (9)

- `JOINT_FIXED`, `JOINT_REVOLUTE`, `JOINT_PRISMATIC`, `JOINT_BALL`
- `SENSOR_CAMERA`, `SENSOR_LIDAR`, `SENSOR_IMU`, `SENSOR_CONTACT`, `SENSOR_FORCE_TORQUE`

## extern "C" FFI (12)

`gz_init`, `gz_fini`, `gz_world_create`, `gz_world_destroy`, `gz_world_step`, `gz_world_set_gravity`, `gz_world_get_gravity`, `gz_model_create`, `gz_model_destroy`, `gz_model_set_pose`, `gz_joint_create`, `gz_joint_set_force`, `gz_sensor_create`, `gz_sensor_read`

## Public API (14 functions)

`init`, `shutdown`, `create_world`, `destroy_world`, `step_simulation`, `set_gravity`, `get_gravity`, `create_model`, `destroy_model`, `model_set_pose`, `create_joint`, `joint_set_force`, `create_sensor`, `sensor_read`

## Contracts (23)

20 requires + 3 ensures across 14 functions.

## Test Suite (47 tests)

- Section 1: Type declarations (4)
- Section 2: API presence (14)
- Section 3: Contract declarations (14)
- Section 4: Constant values (3)
- Section 5: Runtime behavior (10)
- Section 6: Edge cases (2)
