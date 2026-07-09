module xiom.grpc.client

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
  let request_bytes = Vec[UInt8].with_capacity(request.len());
  var i = 0;
  while i < request.len() {
    request_bytes.push(request[i] as UInt8);
    i = i + 1;
  };
  let raw = unary_call(channel, method, &request_bytes);
  match raw {
    Ok(bytes) => {
      var result = Vec[Int].with_capacity(bytes.len());
      var j = 0;
      while j < bytes.len() {
        result.push(bytes[j] as Int);
        j = j + 1;
      };
      Ok(result)
    }
    Err(e) => Err(e),
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
  let data_bytes = Vec[UInt8].with_capacity(data.len());
  var i = 0;
  while i < data.len() {
    data_bytes.push(data[i] as UInt8);
    i = i + 1;
  };
  let raw = send_stream(call, &data_bytes);
  match raw {
    Ok(()) => Ok(()),
    Err(e) => Err(e),
  }
}

fn grpc_stream_recv(call: Int) -> Result[Option[Vec[Int]], Str]
  requires: call != 0
{
  let raw = recv_stream(call);
  match raw {
    Ok(opt) => match opt {
      Some(bytes) => {
        var result = Vec[Int].with_capacity(bytes.len());
        var j = 0;
        while j < bytes.len() {
          result.push(bytes[j] as Int);
          j = j + 1;
        };
        Ok(Some(result))
      }
      None => Ok(None),
    }
    Err(e) => Err(e),
  }
}
