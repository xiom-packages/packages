module xiom.grpc.server
use xiom.grpc;
use xiom.grpc.types.GrpcServerConfig;

pub fn grpc_server_new(addr: Str) -> Result[GrpcServer, GrpcStatus]
  requires: addr.len() > 0
{
  server_new(addr)
}

pub fn grpc_server_register(server: &GrpcServer, service: Str, methods: Int) -> Result[Unit, GrpcStatus]
  requires: server != 0
  requires: service.len() > 0
{
  server_register_service(server, service, methods)
}

pub fn grpc_server_start(server: &GrpcServer) -> Result[Unit, GrpcStatus]
  requires: server != 0
{
  server_start(server)
}

pub fn grpc_server_shutdown(server: GrpcServer) -> Result[Unit, GrpcStatus]
  requires: server != 0
{
  server_shutdown(server)
}

pub fn grpc_server_config(addr: Str, port: Int) -> GrpcServerConfig
  requires: addr.len() > 0
  requires: port > 0
{
  GrpcServerConfig { addr: addr.clone(); port: port; }
}

pub fn grpc_server_address(cfg: &GrpcServerConfig) -> Str
{
  cfg.addr + ":" + cfg.port.to_str()
}
