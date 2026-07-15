module xiom.grpc.client
use xiom.grpc;

fn grpc_init()
{
  init();
}

fn grpc_shutdown()
{
  shutdown();
}

fn grpc_channel_create(target: Str, secure: Bool) -> Result[Int, Str]
  requires: target.len() > 0
{
  Ok(create_channel(target, secure))
}

fn grpc_channel_destroy(channel: Int)
  requires: channel != 0
{
  destroy_channel(channel);
}

fn grpc_unary_call(channel: Int, method: Str, request: &Vec[Int]) -> Result[Vec[Int], Str]
  requires: channel != 0
  requires: method.len() > 0
{
  var raw: Result[Vec[Int], Str] = unary_call(channel, method, request);
  if raw.is_ok() {
    var bytes: Vec[Int] = raw.unwrap();
    var result = Vec[Int]::new();
    var j = 0;
    while j < bytes.len() {
      result.push(bytes[j]);
      j = j + 1;
    };
    Ok(result)
  } else {
    Err("unary call failed")
  }
}

fn grpc_stream_call(channel: Int, method: Str) -> Result[Int, Str]
  requires: channel != 0
  requires: method.len() > 0
{
  stream_call(channel, method)
}

fn grpc_stream_send(call: Int, data: &Vec[Int]) -> Result[Unit, Str]
  requires: call != 0
{
  var raw: Result[Unit, Str] = send_stream(call, data);
  if raw.is_ok() {
    Ok(())
  } else {
    Err("stream send failed")
  }
}

fn grpc_stream_recv(call: Int) -> Result[Option[Vec[Int]], Str]
  requires: call != 0
{
  var raw: Result[Option[Vec[Int]], Str] = recv_stream(call);
  if raw.is_ok() {
    var opt: Option[Vec[Int]] = raw.unwrap();
    if opt.is_some() {
      var bytes: Vec[Int] = opt.unwrap();
      var result = Vec[Int]::new();
      var j = 0;
      while j < bytes.len() {
        result.push(bytes[j]);
        j = j + 1;
      };
      Ok(Some(result))
    } else {
      Ok(None)
    }
  } else {
    Err("stream recv failed")
  }
}
