module xiom.grpc.client
use xiom.grpc;

pub fn grpc_channel_create(target: Str) -> Result[GrpcChannel, GrpcStatus]
  requires: target.len() > 0
{
  channel_create(target)
}

pub fn grpc_channel_destroy(channel: GrpcChannel)
  requires: channel != 0
{
  channel_destroy(channel);
}

pub fn grpc_call_create(channel: GrpcChannel, method: Str) -> Result[GrpcCall, GrpcStatus]
  requires: channel != 0
  requires: method.len() > 0
{
  call_create(channel, method)
}

pub fn grpc_call_destroy(call: GrpcCall)
  requires: call != 0
{
  call_destroy(call);
}

pub fn grpc_call_cancel(call: GrpcCall) -> Result[Unit, GrpcStatus]
  requires: call != 0
{
  call_cancel(call)
}
