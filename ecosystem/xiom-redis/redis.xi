module xiom.redis

pub type Client = Int;

pub enum RedisValue {
  Nil,
  Integer(value: Int),
  String(value: Str),
  Array(items: Vec[RedisValue]),
  Error(message: Str),
}

pub fn connect(host: Str, port: Int) -> Result[Client, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked — redisConnect requires native runtime");
}

pub fn connect_timeout(host: Str, port: Int, timeout_sec: Float64) -> Result[Client, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn disconnect(client: Client) {
}

pub fn command(client: Client, cmd: Str) -> Result[RedisValue, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn get(client: Client, key: Str) -> Result[Option[Str], Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn set(client: Client, key: Str, value: Str) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn set_ex(client: Client, key: Str, value: Str, seconds: Int) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn del(client: Client, keys: Vec[Str]) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn exists(client: Client, keys: Vec[Str]) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn expire(client: Client, key: Str, seconds: Int) -> Result[Bool, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn keys(client: Client, pattern: Str) -> Result[Vec[Str], Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn incr(client: Client, key: Str) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn decr(client: Client, key: Str) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn hset(client: Client, hash: Str, field: Str, value: Str) -> Result[Bool, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn hget(client: Client, hash: Str, field: Str) -> Result[Option[Str], Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn hgetall(client: Client, hash: Str) -> Result[Map[Str, Str], Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn lpush(client: Client, key: Str, values: Vec[Str]) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn rpop(client: Client, key: Str) -> Result[Option[Str], Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn lrange(client: Client, key: Str, start: Int, stop: Int) -> Result[Vec[Str], Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn publish(client: Client, channel: Str, message: Str) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub fn ping(client: Client) -> Result[Str, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

pub const REPLY_STRING: Int = 1;
pub const REPLY_ARRAY: Int = 2;
pub const REPLY_INTEGER: Int = 3;
pub const REPLY_NIL: Int = 4;
pub const REPLY_ERROR: Int = 6;
