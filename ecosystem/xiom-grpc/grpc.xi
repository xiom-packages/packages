// XIOM — gRPC Bindings
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.
module xiom.grpc

pub type Channel = Int;
pub type Call = Int;

pub fn init();
pub fn shutdown();
pub fn create_channel(target: Str, secure: Bool) -> Int;
pub fn destroy_channel(channel: Int);
pub fn unary_call(channel: Int, method: Str, request: &Vec[Int]) -> Result[Vec[Int], Str];
pub fn stream_call(channel: Int, method: Str) -> Result[Int, Str];
pub fn send_stream(call: Int, data: &Vec[Int]) -> Result[Unit, Str];
pub fn recv_stream(call: Int) -> Result[Option[Vec[Int]], Str];
