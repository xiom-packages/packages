module redis_conformance_tests

pub type Client = Int;

pub enum RedisValue {
  Nil,
  Integer(value: Int),
  String(value: Str),
  Array(items: Vec[RedisValue]),
  Error(message: Str),
}

fn connect(host: Str, port: Int) -> Result[Client, Str]
  requires: host.len() > 0
  requires: port > 0 && port < 65536
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn connect_timeout(host: Str, port: Int, timeout_sec: Float64) -> Result[Client, Str]
  requires: host.len() > 0
  requires: port > 0 && port < 65536
  requires: timeout_sec >= 0.0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn disconnect(client: Client)
  requires: client > 0
{
}

fn command(client: Client, cmd: Str) -> Result[RedisValue, Str]
  requires: client > 0
  requires: cmd.len() > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn get(client: Client, key: Str) -> Result[Option[Str], Str]
  requires: client > 0
  requires: key.len() > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn set(client: Client, key: Str, value: Str) -> Result[Int, Str]
  requires: client > 0
  requires: key.len() > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn set_ex(client: Client, key: Str, value: Str, seconds: Int) -> Result[Int, Str]
  requires: client > 0
  requires: key.len() > 0
  requires: seconds > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn del(client: Client, keys: Vec[Str]) -> Result[Int, Str]
  requires: client > 0
  requires: keys.len() > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn exists(client: Client, keys: Vec[Str]) -> Result[Int, Str]
  requires: client > 0
  requires: keys.len() > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn expire(client: Client, key: Str, seconds: Int) -> Result[Bool, Str]
  requires: client > 0
  requires: key.len() > 0
  requires: seconds > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn keys(client: Client, pattern: Str) -> Result[Vec[Str], Str]
  requires: client > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn incr(client: Client, key: Str) -> Result[Int, Str]
  requires: client > 0
  requires: key.len() > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn decr(client: Client, key: Str) -> Result[Int, Str]
  requires: client > 0
  requires: key.len() > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn hset(client: Client, hash: Str, field: Str, value: Str) -> Result[Bool, Str]
  requires: client > 0
  requires: hash.len() > 0
  requires: field.len() > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn hget(client: Client, hash: Str, field: Str) -> Result[Option[Str], Str]
  requires: client > 0
  requires: hash.len() > 0
  requires: field.len() > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn hgetall(client: Client, hash: Str) -> Result[Map[Str, Str], Str]
  requires: client > 0
  requires: hash.len() > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn lpush(client: Client, key: Str, values: Vec[Str]) -> Result[Int, Str]
  requires: client > 0
  requires: key.len() > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn rpop(client: Client, key: Str) -> Result[Option[Str], Str]
  requires: client > 0
  requires: key.len() > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn lrange(client: Client, key: Str, start: Int, stop: Int) -> Result[Vec[Str], Str]
  requires: client > 0
  requires: key.len() > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn publish(client: Client, channel: Str, message: Str) -> Result[Int, Str]
  requires: client > 0
  requires: channel.len() > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn ping(client: Client) -> Result[Str, Str]
  requires: client > 0
{
  return Err("xiom-redis: hiredis FFI bridge not linked");
}

fn test_connect_returns_err() -> Int {
  match connect("localhost", 6379) {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_connect_timeout_returns_err() -> Int {
  match connect_timeout("localhost", 6379, 5.0) {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_disconnect_valid_client() -> Int {
  disconnect(1);
  return 0;
}

fn test_command_returns_err() -> Int {
  match command(1, "PING") {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_get_returns_err() -> Int {
  match get(1, "testkey") {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_set_returns_err() -> Int {
  match set(1, "testkey", "testval") {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_set_ex_returns_err() -> Int {
  match set_ex(1, "testkey", "testval", 60) {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_del_returns_err() -> Int {
  var keys = Vec[Str].new();
  keys.push("key1");
  match del(1, keys) {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_exists_returns_err() -> Int {
  var keys = Vec[Str].new();
  keys.push("key1");
  match exists(1, keys) {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_expire_returns_err() -> Int {
  match expire(1, "testkey", 60) {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_keys_returns_err() -> Int {
  match keys(1, "*") {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_incr_returns_err() -> Int {
  match incr(1, "counter") {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_decr_returns_err() -> Int {
  match decr(1, "counter") {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_hset_returns_err() -> Int {
  match hset(1, "myhash", "field1", "val1") {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_hget_returns_err() -> Int {
  match hget(1, "myhash", "field1") {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_hgetall_returns_err() -> Int {
  match hgetall(1, "myhash") {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_lpush_returns_err() -> Int {
  var vals = Vec[Str].new();
  vals.push("item1");
  match lpush(1, "mylist", vals) {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_rpop_returns_err() -> Int {
  match rpop(1, "mylist") {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_lrange_returns_err() -> Int {
  match lrange(1, "mylist", 0, -1) {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_publish_returns_err() -> Int {
  match publish(1, "chan", "msg") {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_ping_returns_err() -> Int {
  match ping(1) {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_error_message_nonempty() -> Int {
  match get(1, "k") {
    Ok(_) => { return 1; }
    Err(msg) => {
      if msg.len() > 0 { return 0; }
      else { return 2; }
    }
  }
}

fn test_connect_empty_host() -> Int {
  match connect("", 6379) {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_connect_invalid_port() -> Int {
  match connect("localhost", 0) {
    Ok(_) => { return 1; }
    Err(_) => { return 0; }
  }
}

fn test_disconnect_zero_client() -> Int {
  disconnect(0);
  return 0;
}

fn test_redisvalue_nil_construction() -> Int {
  var v: RedisValue = Nil;
  match v {
    Nil => { return 0; }
    _ => { return 1; }
  }
}

fn test_redisvalue_error_construction() -> Int {
  var v: RedisValue = Error(message: "fail");
  match v {
    Error(message: "fail") => { return 0; }
    _ => { return 1; }
  }
}

pub fn main() -> Int {
  var failures: Int = 0;
  failures = failures + test_connect_returns_err();
  failures = failures + test_connect_timeout_returns_err();
  failures = failures + test_disconnect_valid_client();
  failures = failures + test_command_returns_err();
  failures = failures + test_get_returns_err();
  failures = failures + test_set_returns_err();
  failures = failures + test_set_ex_returns_err();
  failures = failures + test_del_returns_err();
  failures = failures + test_exists_returns_err();
  failures = failures + test_expire_returns_err();
  failures = failures + test_keys_returns_err();
  failures = failures + test_incr_returns_err();
  failures = failures + test_decr_returns_err();
  failures = failures + test_hset_returns_err();
  failures = failures + test_hget_returns_err();
  failures = failures + test_hgetall_returns_err();
  failures = failures + test_lpush_returns_err();
  failures = failures + test_rpop_returns_err();
  failures = failures + test_lrange_returns_err();
  failures = failures + test_publish_returns_err();
  failures = failures + test_ping_returns_err();
  failures = failures + test_error_message_nonempty();
  failures = failures + test_connect_empty_host();
  failures = failures + test_connect_invalid_port();
  failures = failures + test_disconnect_zero_client();
  failures = failures + test_redisvalue_nil_construction();
  failures = failures + test_redisvalue_error_construction();
  return failures;
}
