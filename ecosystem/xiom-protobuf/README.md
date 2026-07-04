# xiom:protobuf — Protocol Buffers

libprotobuf FFI bindings. Serialize and deserialize structured data.

```xiom
use xiom.protobuf;

fn main() -> Result[Unit, Str] {
  let msg = ProtoMessage{ fields: Map[Int, ProtoValue].new() };
  let data = encode(&msg)?;
  let decoded = decode(&data)?;
  return Ok(());
}
```
