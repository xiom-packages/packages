# xiom-gazebo — ROADMAP

**Phase**: 3 (Robotics) | **Status**: In Progress

## Completed
- [x] SPEC.md — scope and dependency declaration
- [x] gazebo.xi — `module xiom.gazebo`: 4 types (World, Model, Joint, Sensor), 12 extern "C" FFI declarations, 14 safe wrapper functions with requires/ensures contracts
- [x] tests/test_conformance.xi — 47 conformance tests (compile-time and runtime)

## Next Steps
- [ ] Build C bridge library (`libgz_bridge`) for xiom FFI ABI compatibility
- [ ] Add SDF file loading (`gz_world_load_sdf`)
- [ ] Add plugin support (`gz_world_attach_plugin`, `gz_world_detach_plugin`)
- [ ] Add joint position/velocity getters
- [ ] Add sensor data array reads (camera frames, lidar point clouds)
- [ ] Add entity tree enumeration (iterate models, joints, sensors in world)
- [ ] Add physics parameter tuning (solver iterations, step size, real-time factor)
- [ ] Performance benchmarks (10K+ body scenes)
- [ ] CI/CD integration with Gazebo Sim system install

## Dependencies
- `xiom.ffi` — FFI type definitions and marshaling
- `xiom.io` — console I/O for test runner
- `xiom.test` — assertion framework
- System: Gazebo Sim (Ignition/Garden+) or libgz-sim
