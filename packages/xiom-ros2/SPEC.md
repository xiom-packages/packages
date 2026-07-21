# xiom-ros2 — SPEC
**Phase**: 3 (Robotics) | **Priority**: Medium
**Status**: SPEC + Skeleton (v0.1.0) | **Depends on**: xiom.ffi, xiom.test
ROS 2 — Robot Operating System middleware. System-installed. Week effort.

## Module: `xiom.ros2` (`ros2.xi`)

| Count | Entity |
|------:|--------|
| 5 | Type aliases (Node, Publisher, Subscriber, Service, Message) |
| 12 | extern "C" FFI declarations (rcl_init … rcl_destroy_service) |
| 12 | Public safe wrapper functions |
| 11 | requires contracts (92% of parameterized functions) |
| 37 | Conformance tests (`tests/test_conformance.xi`) |

### Types — opaque Int handles
- `Node`, `Publisher`, `Subscriber`, `Service`, `Message` — all `pub type X = Int`

### extern "C" block
- `rcl_init`, `rcl_shutdown`
- `rcl_create_node`, `rcl_destroy_node`
- `rcl_create_publisher`, `rcl_destroy_publisher`, `rcl_publish`
- `rcl_create_subscription`, `rcl_destroy_subscription`
- `rcl_spin_once`
- `rcl_create_service`, `rcl_destroy_service`

### Safe Wrappers (all stubs ? `Err("stub: ROS 2 C bridge not linked")`)
- `init()`, `shutdown(context)`
- `create_node(name)`, `destroy_node(node)`
- `create_publisher(node, topic)`, `destroy_publisher(publisher, node)`, `publish(publisher, message)`
- `create_subscription(node, topic)`, `destroy_subscription(subscriber, node)`
- `spin_once(node, timeout_ms)`
- `create_service(node, service_name)`, `destroy_service(service, node)`

### Contracts
- `requires: node > 0` on all node-dependent ops
- `requires: publisher > 0`, `subscriber > 0`, `service > 0` on destroy ops
- `requires: name.len() > 0`, `topic.len() > 0`, `service_name.len() > 0` on string params
- `requires: timeout_ms >= 0` on `spin_once`
- `requires: message > 0` on `publish`

### Quality Gates
- [x] Syntax: compiles with `xiom_check_xiom_syntax`
- [ ] Contracts: `xiom_verify_contracts` (requires Z3)
- [ ] Safety audit: `xiom_audit_safety_sandbox`
