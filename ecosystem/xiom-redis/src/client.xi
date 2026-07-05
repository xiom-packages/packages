module xiom.redis.client

pub type RedisConn = {
  handle: Int;
  host: Str;
  port: Int;
} derive[Clone]

fn redis_connect(host: Str, port: Int) -> Result[RedisConn, Str]
  requires: host.len() > 0
  requires: port > 0
  ensures: result.is_ok() implies result.unwrap().handle != 0
{
  let raw = connect(host, port);
  match raw {
    Ok(handle) => Ok(RedisConn { handle: handle; host: host.clone(); port: port; }),
    Err(e) => Err(e),
  }
}

fn redis_connect_timeout(host: Str, port: Int, timeout_sec: Float64) -> Result[RedisConn, Str]
  requires: port > 0
  ensures: result.is_ok() implies result.unwrap().handle != 0
{
  let raw = connect_timeout(host, port, timeout_sec);
  match raw {
    Ok(handle) => Ok(RedisConn { handle: handle; host: host.clone(); port: port; }),
    Err(e) => Err(e),
  }
}

fn redis_disconnect(conn: &mut RedisConn)
  requires: conn.handle != 0
{
  disconnect(conn.handle);
  conn.handle = 0;
}

fn redis_ping(conn: &RedisConn) -> Result[Str, Str]
  requires: conn.handle != 0
{
  ping(conn.handle)
}

fn redis_get(conn: &RedisConn, key: Str) -> Result[Option[Str], Str]
  requires: conn.handle != 0
  requires: key.len() > 0
{
  get(conn.handle, key)
}

fn redis_set(conn: &RedisConn, key: Str, value: Str) -> Result[Unit, Str]
  requires: conn.handle != 0
  requires: key.len() > 0
{
  set(conn.handle, key, value)
}

fn redis_set_ex(conn: &RedisConn, key: Str, value: Str, seconds: Int) -> Result[Unit, Str]
  requires: conn.handle != 0
  requires: key.len() > 0
{
  set_ex(conn.handle, key, value, seconds)
}

fn redis_del(conn: &RedisConn, keys: &Vec[Str]) -> Result[Int, Str]
  requires: conn.handle != 0
{
  del(conn.handle, keys.clone())
}

fn redis_exists(conn: &RedisConn, keys: &Vec[Str]) -> Result[Int, Str]
  requires: conn.handle != 0
{
  exists(conn.handle, keys.clone())
}

fn redis_expire(conn: &RedisConn, key: Str, seconds: Int) -> Result[Bool, Str]
  requires: conn.handle != 0
  requires: key.len() > 0
{
  expire(conn.handle, key, seconds)
}

fn redis_keys(conn: &RedisConn, pattern: Str) -> Result[Vec[Str], Str]
  requires: conn.handle != 0
{
  keys(conn.handle, pattern)
}

fn redis_incr(conn: &RedisConn, key: Str) -> Result[Int, Str]
  requires: conn.handle != 0
  requires: key.len() > 0
{
  incr(conn.handle, key)
}

fn redis_decr(conn: &RedisConn, key: Str) -> Result[Int, Str]
  requires: conn.handle != 0
  requires: key.len() > 0
{
  decr(conn.handle, key)
}

fn redis_hset(conn: &RedisConn, hash: Str, field: Str, value: Str) -> Result[Bool, Str]
  requires: conn.handle != 0
  requires: hash.len() > 0
  requires: field.len() > 0
{
  hset(conn.handle, hash, field, value)
}

fn redis_hget(conn: &RedisConn, hash: Str, field: Str) -> Result[Option[Str], Str]
  requires: conn.handle != 0
  requires: hash.len() > 0
  requires: field.len() > 0
{
  hget(conn.handle, hash, field)
}

fn redis_hgetall(conn: &RedisConn, hash: Str) -> Result[Map[Str, Str], Str]
  requires: conn.handle != 0
  requires: hash.len() > 0
{
  hgetall(conn.handle, hash)
}

fn redis_lpush(conn: &RedisConn, key: Str, values: &Vec[Str]) -> Result[Int, Str]
  requires: conn.handle != 0
  requires: key.len() > 0
{
  lpush(conn.handle, key, values.clone())
}

fn redis_rpop(conn: &RedisConn, key: Str) -> Result[Option[Str], Str]
  requires: conn.handle != 0
  requires: key.len() > 0
{
  rpop(conn.handle, key)
}

fn redis_lrange(conn: &RedisConn, key: Str, start: Int, stop: Int) -> Result[Vec[Str], Str]
  requires: conn.handle != 0
  requires: key.len() > 0
{
  lrange(conn.handle, key, start, stop)
}

fn redis_publish(conn: &RedisConn, channel: Str, message: Str) -> Result[Int, Str]
  requires: conn.handle != 0
  requires: channel.len() > 0
{
  publish(conn.handle, channel, message)
}

fn redis_command(conn: &RedisConn, cmd: Str) -> Result[RedisValue, Str]
  requires: conn.handle != 0
  requires: cmd.len() > 0
{
  command(conn.handle, cmd)
}
