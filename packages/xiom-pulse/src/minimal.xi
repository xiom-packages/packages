// XIOM PULSE -- minimal example: register one route and start the loop.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The three-line PULSE shape against the carved surface: register a route,
// pass one handler to serve(), and the accept loop is running. Run it with
//
//   xiom --run src/minimal.xi
//
// then `curl http://127.0.0.1:8080/health` (PULSE_PORT / PULSE_BIND /
// PULSE_READ_TIMEOUT / PULSE_WRITE_TIMEOUT / PULSE_IDLE_TIMEOUT /
// PULSE_KEEPALIVE are honored). Stop it with one request carrying the
// header `X-Pulse-Quit: 1`.
module xiom.pulse.minimal

use xiom.pulse.app;
use xiom.pulse.http;
use xiom.pulse.router;

/// hello is the one registered handler: a JSON ok body, status 200.
fn hello(_req: &PulseRequest, _m: &PulseRoute, _body: Str) -> HandlerOut {
  return app.out_json(200, "{\"status\":\"ok\"}");
}

pub fn main() -> Int {
  let _ = app.register("GET", "/health");
  return app.serve(hello);
}
