module xiom.grpc.server
use xiom.grpc.types.GrpcServer;

fn grpc_server_create(addr: Str, port: Int) -> Result[GrpcServer, Str]
  requires: addr.len() > 0
  requires: port > 0
{
  Ok(GrpcServer { addr: addr.clone(); port: port; })
}

fn grpc_server_register(server: &GrpcServer, service: Str, handler: fn(&GrpcRequest) -> Result[GrpcResponse, Str]) -> Result[Unit, Str]
  requires: service.len() > 0
{
  Ok(())
}

fn grpc_server_start(server: &GrpcServer) -> Result[Unit, Str]
{
  Ok(())
}

fn grpc_server_stop(server: &GrpcServer) -> Result[Unit, Str]
{
  Ok(())
}

fn grpc_server_wait(server: &GrpcServer) -> Result[Unit, Str]
{
  Ok(())
}

fn grpc_server_address(server: &GrpcServer) -> Str
{
  server.addr + ":" + server.port.to_str()
}
