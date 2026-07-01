# axiom:protobuf — Protocol Buffers

libprotobuf FFI bindings. Serialize and deserialize structured data.

```axiom
use axiom.protobuf;

fn main() -> Result[Unit, Str] {
  let msg = ProtoMessage{ fields: Map[Int, ProtoValue].new() };
  let data = encode(&msg)?;
  let decoded = decode(&data)?;
  return Ok(());
}
```
