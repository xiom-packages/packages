// probe_all_modules.xi -- combined-build type check for every module in the
// package, including the legacy client/demo modules that no suite closure
// imports. Guards the 2026-10-10 dead-module repair (imports + current
// response types) against regressions.
//
// Run from the repo root (type check only -- a --run would need real libcurl
// for the root module's FFI externs):
//   & $env:XIOM_COMPILER --check packages\xiom-http\tests\probe_all_modules.xi
module http_all_modules_check

use xiom.http;
use xiom.http.client;
use xiom.http.cookie;
use xiom.http.demo;
use xiom.http.mime;
use xiom.http.parser;
use xiom.http.server;
use xiom.http.status;
use xiom.http.types;
use xiom.http.url;

fn main() -> Int {
  return 0;
}
