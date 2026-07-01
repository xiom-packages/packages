# axiom:grpc — gRPC

gRPC C Core FFI bindings. High-performance RPC framework.

```axiom
use axiom.grpc;

fn main() -> Result[Unit, Str] {
  init();
  let ch = create_channel("localhost:50051", false);
  let response = unary_call(ch, "/helloworld.Greeter/SayHello", &Vec[UInt8].new())?;
  destroy_channel(ch);
  shutdown();
  return Ok(());
}
```
