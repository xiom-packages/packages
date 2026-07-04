# xiom:redis — Redis

hiredis FFI bindings for XIOM. Key-value store, pub/sub, lists, hashes.

```xiom
use xiom.redis;

fn main() -> Int {
  let client = connect("localhost", 6379)?;
  set(client, "key", "value")?;
  let val = get(client, "key")?;
  incr(client, "counter")?;
  lpush(client, "queue", ["task1", "task2"])?;
  disconnect(client);
  return 0;
}
```
