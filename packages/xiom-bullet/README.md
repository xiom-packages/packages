# xiom:bullet — Physics

Bullet Physics FFI bindings. Rigid body dynamics for games.

```xiom
use xiom.bullet;

fn main() -> Int {
  let world = create_world();
  set_gravity(world, 0.0, -9.81, 0.0);
  let ground = create_box_shape(50.0, 1.0, 50.0);
  let ball = create_sphere_shape(1.0);
  let body = create_rigid_body(1.0, ball);
  add_body(world, body);
  step_simulation(world, 1.0 / 60.0);
  return 0;
}
```
