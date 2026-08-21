# xiom-bullet Audit

## Compilation Status
- `bullet.xi` -- PASSES (standalone)
- `tests/test_bullet.xi` -- PASSES (with bullet.xi)
- All files compile together: PASS

## Changes Made
No source changes needed. The test file compiles correctly when passed alongside `bullet.xi` (multi-file compilation per XIOM spec S17).

## System Dependencies

### Required: Bullet Physics SDK
- **Linux**: `apt install libbullet-dev` -> `libBulletDynamics.so`, `libBulletCollision.so`, `libLinearMath.so`
- **macOS**: `brew install bullet` -> `libBulletDynamics.dylib`, `libBulletCollision.dylib`, `libLinearMath.dylib`
- **Windows**: Build from source or use vcpkg `vcpkg install bullet3` -> `BulletDynamics.dll`, `BulletCollision.dll`, `LinearMath.dll`

### Required DLLs at Runtime
| DLL | Purpose |
|-----|---------|
| `BulletDynamics.dll` | Physics world, rigid bodies, constraints |
| `BulletCollision.dll` | Collision shapes, broadphase, narrowphase |
| `LinearMath.dll` | Vector math, transforms, quaternions |

### Link Flags
```
-l BulletDynamics -l BulletCollision -l LinearMath
```

### Compilation with Libraries
```powershell
xiom --link BulletDynamics --link BulletCollision --link LinearMath --link-path C:/path/to/bullet/lib bullet.xi program.xi
```

## FFI Bindings Mapped (bullet.xiom-bind)

| XIOM Function | C Function | Library |
|--------------|------------|---------|
| `create_world` | `btDiscreteDynamicsWorld_new` + init chain | BulletDynamics |
| `destroy_world` | (delete world + config/solver/broadphase/dispatcher) | BulletDynamics |
| `step_simulation` | `btDiscreteDynamicsWorld_stepSimulation` | BulletDynamics |
| `set_gravity` | `btDiscreteDynamicsWorld_setGravity` | BulletDynamics |
| `add_body` | `btDiscreteDynamicsWorld_addRigidBody` | BulletDynamics |
| `remove_body` | `btDiscreteDynamicsWorld_removeRigidBody` | BulletDynamics |
| `create_box_shape` | `btBoxShape_new` | BulletCollision |
| `create_sphere_shape` | `btSphereShape_new` | BulletCollision |
| `create_capsule_shape` | `btCapsuleShape_new` | BulletCollision |
| `create_plane_shape` | `btStaticPlaneShape_new` | BulletCollision |
| `create_rigid_body` | `btRigidBody_new` | BulletDynamics |
| `set_velocity` | `btRigidBody_setLinearVelocity` | BulletDynamics |
| `set_angular_velocity` | `btRigidBody_setAngularVelocity` | BulletDynamics |
| `apply_force` | `btRigidBody_applyCentralForce` | BulletDynamics |
| `apply_impulse` | `btRigidBody_applyCentralImpulse` | BulletDynamics |
| `set_restitution` | `btRigidBody_setRestitution` | BulletDynamics |
| `set_friction` | `btRigidBody_setFriction` | BulletDynamics |
| `get_position` | `btRigidBody_getWorldTransform` + transform read | BulletDynamics |

## Known Gaps
- All `bullet.xi` functions are forward declarations (`;` body) -- they require Bullet DLLs at link time and runtime.
- Tests only verify handle validity (handle != 0). No functional physics tests are possible without DLLs.
- `get_position` has no implementation body mapping to the FFI call chain (declared in bullet.xi but no corresponding `bullet.xiom-bind` entry for transform extraction).
- No cleanup/shutdown for worlds, bodies, or shapes (potential memory leak in FFI allocations).
- `create_rigid_body` in `bullet.xiom-bind` requires a motion_state pointer but the `bullet.xi` API surface does not expose motion state creation.
