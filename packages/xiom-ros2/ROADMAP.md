# xiom.ros2 Roadmap

## Current State -- v0.1.0 (SPEC)

| Component | Status | Notes |
|-----------|--------|-------|
| `xiom.ros2` module | SPEC | Full API surface declared: 12 public functions, 12 extern FFI stubs, 5 type aliases |
| Init / Shutdown | Stub | `init`, `shutdown` -- return Err until C bridge linked |
| Node Lifecycle | Stub | `create_node`, `destroy_node` -- contracts for name.len()>0, node>0 |
| Publisher | Stub | `create_publisher`, `destroy_publisher`, `publish` -- topic/msg contracts |
| Subscriber | Stub | `create_subscription`, `destroy_subscription` -- topic contract |
| Spin | Stub | `spin_once` -- contracts for node>0, timeout_ms>=0 |
| Service | Stub | `create_service`, `destroy_service` -- service_name contract |
| C Bridge | Missing | `ros2_bridge.c` not yet implemented -- all FFI stubs return Err |

### Contracts Coverage

- **12 public functions**
- **11 functions** guarded by `requires:` contracts (92%)
- **12 extern "C"** function declarations for rcl/rclc FFI
- Missing contract: `init()` -- returns Result, no input to validate

### Test Coverage

- **37 conformance tests** in `tests/test_conformance.xi`
- Covers: types (5), init/shutdown stubs (2), node lifecycle stubs (2), publisher stubs (3), subscriber stubs (2), spin stub (1), service stubs (2), contract declarations (11), error handling (2), lifecycle simulation (1), pub-sub simulation (1), FFI declaration smoke (5)

---

## v0.2.0 -- C Bridge Implementation

- [ ] Create `ros2_bridge.c` with thin FFI wrappers around rcl/rclc
- [ ] Build system: CMake integration for ROS 2 linking (`ament_cmake`)
- [ ] Wire `init()` -> CFFI `rcl_init()`
- [ ] Wire `shutdown()` -> CFFI `rcl_shutdown()`
- [ ] Wire `create_node()` -> CFFI `rcl_create_node()`
- [ ] Replace Err stubs with actual FFI call + error translation
- [ ] Tests: run against live ROS 2 (`rclcpp` installed via apt/choco)

## v0.3.0 -- Publisher / Subscriber

- [ ] Wire `create_publisher()` -> CFFI `rcl_create_publisher()`
- [ ] Wire `publish()` -> CFFI `rcl_publish()` with message serialisation
- [ ] Wire `create_subscription()` -> CFFI `rcl_create_subscription()` with callback
- [ ] Wire `spin_once()` -> CFFI `rcl_spin_once()`
- [ ] Map rcl_ret_t errors -> human-readable Str
- [ ] Tests: pub/sub roundtrip on `/chatter` topic

## v0.4.0 -- Services

- [ ] Wire `create_service()` -> CFFI `rcl_create_service()`
- [ ] Wire `destroy_service()` -> CFFI `rcl_destroy_service()`
- [ ] Add `take_request()` / `send_response()` wrappers
- [ ] Tests: service call/response roundtrip (`add_two_ints`)

## v0.5.0 -- Quality-of-Service & Parameters

- [ ] QoS profile type: `QosProfile { reliability, durability, history, depth }`
- [ ] `create_publisher_with_qos()` / `create_subscription_with_qos()`
- [ ] ROS 2 parameter server wrappers (`rcl_params_get`, `rcl_params_set`)
- [ ] Tests: QoS reliability (reliable vs best-effort)

## v0.6.0 -- Serialisation & Message Types

- [ ] StdMsgs wrapper: `String`, `Int32`, `Float64`, `Bool`
- [ ] Custom message codegen from `.msg` / `.idl` files
- [ ] Vec[UInt8] <-> ROS 2 message marshaling
- [ ] Tests: roundtrip serialisation for std_msgs/String

## v1.0.0 -- Stable Release

- [ ] All above features complete
- [ ] 90%+ test coverage on all modules
- [ ] Full API documentation
- [ ] Cross-platform CI: Windows (choco), Linux (apt), macOS (brew)
- [ ] ROS 2 Humble + Iron + Jazzy compatibility matrix
- [ ] Security audit of all `unsafe` blocks
- [ ] Formal contract verification (xiom-verify) on public API

---

## Backlog / Future

| Feature | Priority | Notes |
|---------|----------|-------|
| Actions (goal-oriented) | Medium | `rcl_action_create`, feedback/result streaming |
| Lifecycle nodes | Medium | Managed nodes with configure/activate/deactivate states |
| TF2 transforms | High | `tf2_ros` buffer + broadcaster/listener |
| Composition | Medium | Node composition via `rclcpp_components` |
| Intra-process comms | Medium | Zero-copy pub/sub within the same process |
| Time/Timers | High | `rcl_timer_init`, ROS clock abstraction |
| Executors | Medium | Multi-threaded executor, callback groups |
| Launch system | Low | `.launch.py` generation from XIOM DAG |
| RViz visualisation | Low | Marker message publishers |
| rosbag2 | Low | Playback / recording of topic data |

---

## Dependency Graph

```
xiom.ros2 (this package)
  |-- xiom-std (stdlib: string, collections, ptr)
  |-- rcl + rclc C libraries (ROS 2 Humble+, system-installed)
  |-- rosidl_typesupport (message type support)
  `-- ros2_bridge.c (thin C FFI wrapper)
```
