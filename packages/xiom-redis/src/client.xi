module xiom.redis.client

pub type RedisConn = {
  handle: Int;
  host: Str;
  port: Int;
}

pub enum RedisValue {
  Nil,
  Integer(value: Int),
  String(value: Str),
  Array(items: Vec[RedisValue]),
  Error(message: Str),
}

fn connect(host: Str, port: Int) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn connect_timeout(host: Str, port: Int, timeout_sec: Float64) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn disconnect(client: Int) {
}

fn command(client: Int, cmd: Str) -> Result[RedisValue, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn get(client: Int, key: Str) -> Result[Option[Str], Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn rset(client: Int, key: Str, value: Str) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn set_ex(client: Int, key: Str, value: Str, seconds: Int) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn rdel(client: Int, keys: Vec[Str]) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn exists(client: Int, keys: Vec[Str]) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn expire(client: Int, key: Str, seconds: Int) -> Result[Bool, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn keys(client: Int, pattern: Str) -> Result[Vec[Str], Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn incr(client: Int, key: Str) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn decr(client: Int, key: Str) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn hset(client: Int, hash: Str, field: Str, value: Str) -> Result[Bool, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn hget(client: Int, hash: Str, field: Str) -> Result[Option[Str], Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn hgetall(client: Int, hash: Str) -> Result[Map[Str, Str], Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn lpush(client: Int, key: Str, values: Vec[Str]) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn rpop(client: Int, key: Str) -> Result[Option[Str], Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn lrange(client: Int, key: Str, start: Int, stop: Int) -> Result[Vec[Str], Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn publish(client: Int, channel: Str, message: Str) -> Result[Int, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn ping(client: Int) -> Result[Str, Str] {
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn redis_connect(host: Str, port: Int) -> Result[RedisConn, Str] {
  var raw = connect(host, port);
  match raw {
    Ok(handle) => return Ok(RedisConn { handle: handle, host: host, port: port }),
    Err(e) => return Err(e),
  }
}

fn redis_connect_timeout(host: Str, port: Int, timeout_sec: Float64) -> Result[RedisConn, Str] {
  var raw = connect_timeout(host, port, timeout_sec);
  match raw {
    Ok(handle) => return Ok(RedisConn { handle: handle, host: host, port: port }),
    Err(e) => return Err(e),
  }
}

fn redis_disconnect(conn: &mut RedisConn) {
  disconnect(conn.handle);
  conn.handle = 0;
}

fn redis_ping(conn: &RedisConn) -> Result[Str, Str] {
  return ping(conn.handle);
}

fn redis_get(conn: &RedisConn, key: Str) -> Result[Option[Str], Str] {
  return get(conn.handle, key);
}

fn redis_set(conn: &RedisConn, key: Str, value: Str) -> Result[Int, Str] {
  return rset(conn.handle, key, value);
}

fn redis_set_ex(conn: &RedisConn, key: Str, value: Str, seconds: Int) -> Result[Int, Str] {
  return set_ex(conn.handle, key, value, seconds);
}

fn redis_del(conn: &RedisConn, keys: &Vec[Str]) -> Result[Int, Str] {
  var copy = Vec[Str].new();
  var i: Int = 0;
  while i < keys.len() {
    copy.push(keys[i]);
    i = i + 1;
  };
  return rdel(conn.handle, copy);
}

fn redis_exists(conn: &RedisConn, keys: &Vec[Str]) -> Result[Int, Str] {
  var copy = Vec[Str].new();
  var i: Int = 0;
  while i < keys.len() {
    copy.push(keys[i]);
    i = i + 1;
  };
  return exists(conn.handle, copy);
}

fn redis_expire(conn: &RedisConn, key: Str, seconds: Int) -> Result[Bool, Str] {
  return expire(conn.handle, key, seconds);
}

fn redis_keys(conn: &RedisConn, pattern: Str) -> Result[Vec[Str], Str] {
  return keys(conn.handle, pattern);
}

fn redis_incr(conn: &RedisConn, key: Str) -> Result[Int, Str] {
  return incr(conn.handle, key);
}

fn redis_decr(conn: &RedisConn, key: Str) -> Result[Int, Str] {
  return decr(conn.handle, key);
}

fn redis_hset(conn: &RedisConn, hash: Str, field: Str, value: Str) -> Result[Bool, Str] {
  return hset(conn.handle, hash, field, value);
}

fn redis_hget(conn: &RedisConn, hash: Str, field: Str) -> Result[Option[Str], Str] {
  return hget(conn.handle, hash, field);
}

fn redis_hgetall(conn: &RedisConn, hash: Str) -> Result[Map[Str, Str], Str] {
  return hgetall(conn.handle, hash);
}

fn redis_lpush(conn: &RedisConn, key: Str, values: &Vec[Str]) -> Result[Int, Str] {
  var copy = Vec[Str].new();
  var i: Int = 0;
  while i < values.len() {
    copy.push(values[i]);
    i = i + 1;
  };
  return lpush(conn.handle, key, copy);
}

fn redis_rpop(conn: &RedisConn, key: Str) -> Result[Option[Str], Str] {
  return rpop(conn.handle, key);
}

fn redis_lrange(conn: &RedisConn, key: Str, start: Int, stop: Int) -> Result[Vec[Str], Str] {
  return lrange(conn.handle, key, start, stop);
}

fn redis_publish(conn: &RedisConn, channel: Str, message: Str) -> Result[Int, Str] {
  return publish(conn.handle, channel, message);
}

fn redis_command(conn: &RedisConn, cmd: Str) -> Result[RedisValue, Str] {
  return command(conn.handle, cmd);
}
