module xiom_net_conformance_tests

use xiom.io;
use xiom.test;
use xiom.string;
use xiom.net.types;
use xiom.net.types.IpAddr;
use xiom.net.types.SocketAddr;
use xiom.net.types.IpVersion;
use xiom.net.tcp;
use xiom.net.tcp.TcpStream;
use xiom.net.tcp.TcpListener;
use xiom.net.udp;
use xiom.net.udp.UdpSocket;
use xiom.net.dns;
use xiom.net.dns.DnsResult;

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var num = n;
  var out = "";
  while num > 0 {
    var d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; } elif d == 2 { ds = "2"; } elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; } elif d == 5 { ds = "5"; } elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; } elif d == 8 { ds = "8"; } elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  return out;
}

fn report(passed: Bool, name: Str) -> Int {
  if passed { io.println("  [PASS] " + name); return 0; }
  io.println("  [FAIL] " + name); return 1;
}

fn str_eq(a: Str, b: Str) -> Bool {
  return string.str_len(a) == string.str_len(b) && string.str_contains(a, b);
}

fn str_starts_with(s: Str, prefix: Str) -> Bool {
  if string.str_len(s) < string.str_len(prefix) { return false; }
  var i: Int = 0;
  while i < string.str_len(prefix) {
    var ch_s = string.char_at(s, i);
    var ch_p = string.char_at(prefix, i);
    var ok = false;
    match ch_s { Some(cs) => { match ch_p { Some(cp) => { if cs == cp { ok = true; }; }; }; }; };
    if !ok { return false; }
    i = i + 1;
  }
  return true;
}
fn str_contains_str(s: Str, sub: Str) -> Bool {
  return string.str_contains(s, sub);
}

fn result_ok_msg[T, E](r: Result[T, E]) -> Bool {
  return r.is_ok;
}
fn result_err_msg[T, E](r: Result[T, E]) -> Bool {
  return !r.is_ok;
}

fn str_len(s: Str) -> Int {
  return string.str_len(s);
}

fn vec_len(v: &Vec[Int]) -> Int {
  return v.len();
}

fn first(arr: &Vec[Int]) -> Int {
  return arr[0];
}

fn last(arr: &Vec[Int]) -> Int {
  return arr[arr.len() - 1];
}

fn octet_at(ip: &IpAddr, idx: Int) -> Int {
  return ip.octets[idx];
}

fn vec_new_int() -> Vec[Int] {
  return Vec[Int].new();
}

fn make_buf_4() -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(0); v.push(0); v.push(0); v.push(0);
  return v;
}

fn make_buf_8() -> Vec[Int] {
  var v = Vec[Int].new();
  var i: Int = 0;
  while i < 8 { v.push(0); i = i + 1; }
  return v;
}

fn at_idx(v: &Vec[Int], idx: Int) -> Int {
  return v[idx];
}

fn u8_to_str(n: Int) -> Str {
  if n == 0 { return "0"; }
  var val = n;
  var result = "";
  if val >= 100 {
    var h = val / 100;
    if h == 1 { result = "1"; } elif h == 2 { result = "2"; }
    val = val % 100;
  }
  if val >= 10 || result != "" {
    var t = val / 10;
    if t == 0 && result != "" { result = result + "0"; }
    elif t == 1 { result = result + "1"; } elif t == 2 { result = result + "2"; }
    elif t == 3 { result = result + "3"; } elif t == 4 { result = result + "4"; }
    elif t == 5 { result = result + "5"; } elif t == 6 { result = result + "6"; }
    elif t == 7 { result = result + "7"; } elif t == 8 { result = result + "8"; }
    elif t == 9 { result = result + "9"; }
    val = val % 10;
  }
  var o = val;
  if o == 0 { result = result + "0"; }
  elif o == 1 { result = result + "1"; } elif o == 2 { result = result + "2"; }
  elif o == 3 { result = result + "3"; } elif o == 4 { result = result + "4"; }
  elif o == 5 { result = result + "5"; } elif o == 6 { result = result + "6"; }
  elif o == 7 { result = result + "7"; } elif o == 8 { result = result + "8"; }
  elif o == 9 { result = result + "9"; }
  return result;
}

// ─── Constants ───────────────────────────────────────────────────────────────

fn t_const_af_inet() -> TestResult {
  return assert(AF_INET == 2, "const: AF_INET == 2");
}
fn t_const_sock_stream() -> TestResult {
  return assert(SOCK_STREAM == 1, "const: SOCK_STREAM == 1");
}
fn t_const_sock_dgram() -> TestResult {
  return assert(SOCK_DGRAM == 2, "const: SOCK_DGRAM == 2");
}
fn t_const_inaddr_any() -> TestResult {
  return assert(INADDR_ANY == 0, "const: INADDR_ANY == 0");
}
fn t_const_invalid_socket() -> TestResult {
  return assert(INVALID_SOCKET == -1, "const: INVALID_SOCKET == -1");
}
fn t_const_socket_error() -> TestResult {
  return assert(SOCKET_ERROR == -1, "const: SOCKET_ERROR == -1");
}
fn t_const_somaxconn() -> TestResult {
  return assert(SOMAXCONN == 128, "const: SOMAXCONN == 128");
}

// ─── IPv4 Constructors ───────────────────────────────────────────────────────

fn t_ipv4_localhost() -> TestResult {
  var ip = ipv4(127, 0, 0, 1);
  return assert(ip.version == 4 && octet_at(&ip, 0) == 127 && octet_at(&ip, 3) == 1, "ipv4: localhost 127.0.0.1");
}
fn t_ipv4_zero() -> TestResult {
  var ip = ipv4(0, 0, 0, 0);
  return assert(ip.version == 4 && octet_at(&ip, 0) == 0 && octet_at(&ip, 3) == 0, "ipv4: 0.0.0.0");
}
fn t_ipv4_max() -> TestResult {
  var ip = ipv4(255, 255, 255, 255);
  return assert(ip.version == 4 && octet_at(&ip, 0) == 255 && octet_at(&ip, 3) == 255, "ipv4: 255.255.255.255");
}
fn t_ipv4_arbitrary() -> TestResult {
  var ip = ipv4(192, 168, 1, 100);
  return assert(ip.version == 4 && octet_at(&ip, 1) == 168 && octet_at(&ip, 2) == 1, "ipv4: 192.168.1.100");
}

// ─── IPv6 Constructor ────────────────────────────────────────────────────────

fn t_ipv6_localhost() -> TestResult {
  var ip = ipv6_from_parts(0, 0, 0, 0, 0, 0, 0, 1);
  return assert(ip.version == 6 && ip.octets.len() == 16, "ipv6: ::1");
}
fn t_ipv6_all_zero() -> TestResult {
  var ip = ipv6_from_parts(0, 0, 0, 0, 0, 0, 0, 0);
  return assert(ip.version == 6 && ip.octets.len() == 16 && octet_at(&ip, 15) == 0, "ipv6: ::");
}

// ─── IPv4 Parsing Valid ─────────────────────────────────────────────────────

fn t_parse_ipv4_localhost() -> TestResult {
  var r = ipv4_from_str("127.0.0.1");
  return assert(result_ok_msg(r), "parse: 127.0.0.1 ok");
}
fn t_parse_ipv4_zero() -> TestResult {
  var r = ipv4_from_str("0.0.0.0");
  return assert(result_ok_msg(r), "parse: 0.0.0.0 ok");
}
fn t_parse_ipv4_max() -> TestResult {
  var r = ipv4_from_str("255.255.255.255");
  return assert(result_ok_msg(r), "parse: 255.255.255.255 ok");
}
fn t_parse_ipv4_arbitrary() -> TestResult {
  var r = ipv4_from_str("192.168.1.1");
  return assert(result_ok_msg(r), "parse: 192.168.1.1 ok");
}

// ─── IPv4 Parsing Errors ────────────────────────────────────────────────────

fn t_parse_ipv4_empty() -> TestResult {
  var r = ipv4_from_str("");
  return assert(result_err_msg(r), "parse: empty string => Err");
}
fn t_parse_ipv4_garbage() -> TestResult {
  var r = ipv4_from_str("not-an-ip");
  return assert(result_err_msg(r), "parse: garbage => Err");
}
fn t_parse_ipv4_overflow() -> TestResult {
  var r = ipv4_from_str("256.0.0.1");
  return assert(result_err_msg(r), "parse: octet 256 => Err");
}
fn t_parse_ipv4_too_few() -> TestResult {
  var r = ipv4_from_str("1.2.3");
  return assert(result_err_msg(r), "parse: only 3 octets => Err");
}
fn t_parse_ipv4_too_many() -> TestResult {
  var r = ipv4_from_str("1.2.3.4.5");
  return assert(result_err_msg(r), "parse: 5 octets => Err");
}
fn t_parse_ipv4_trailing_dot() -> TestResult {
  var r = ipv4_from_str("1.2.3.4.");
  return assert(result_err_msg(r), "parse: trailing dot => Err");
}

// ─── IPv4 Formatting ────────────────────────────────────────────────────────

fn t_fmt_ipv4_127() -> TestResult {
  var ip = ipv4(127, 0, 0, 1);
  var s = ipv4_to_str(&ip);
  return assert(str_eq(s, "127.0.0.1"), "fmt: 127.0.0.1");
}
fn t_fmt_ipv4_all() -> TestResult {
  var ip = ipv4(255, 255, 255, 255);
  var s = ipv4_to_str(&ip);
  return assert(str_len(s) > 10, "fmt: 255.255.255.255 length > 10");
}

// ─── IP Version Checks ──────────────────────────────────────────────────────

fn t_version_v4() -> TestResult {
  var ip = ipv4(10, 0, 0, 1);
  return assert(ip.is_v4(), "version: ipv4 is_v4");
}
fn t_version_v6() -> TestResult {
  var ip = ipv6_from_parts(0, 0, 0, 0, 0, 0, 0, 1);
  return assert(ip.is_v6(), "version: ipv6 is_v6");
}
fn t_version_v4_not_v6() -> TestResult {
  var ip = ipv4(1, 2, 3, 4);
  return assert(!ip.is_v6(), "version: ipv4 not is_v6");
}

// ─── SocketAddr Construction ────────────────────────────────────────────────

fn t_sockaddr_http() -> TestResult {
  var ip = ipv4(93, 184, 216, 34);
  var addr = socket_addr(ip, 80);
  return assert(addr.port == 80, "sockaddr: port 80");
}
fn t_sockaddr_max_port() -> TestResult {
  var ip = ipv4(127, 0, 0, 1);
  var addr = socket_addr(ip, 65535);
  return assert(addr.port == 65535, "sockaddr: port 65535");
}
fn t_sockaddr_port_1() -> TestResult {
  var ip = ipv4(0, 0, 0, 0);
  var addr = socket_addr(ip, 1);
  return assert(addr.port == 1, "sockaddr: port 1");
}

// ─── SocketAddr Parsing Valid ───────────────────────────────────────────────

fn t_parse_sockaddr_http() -> TestResult {
  var r = socket_addr_from_str("127.0.0.1:8080");
  return assert(result_ok_msg(r), "parse sockaddr: 127.0.0.1:8080 ok");
}
fn t_parse_sockaddr_zero() -> TestResult {
  var r = socket_addr_from_str("0.0.0.0:80");
  return assert(result_ok_msg(r), "parse sockaddr: 0.0.0.0:80 ok");
}

// ─── SocketAddr Parsing Errors ──────────────────────────────────────────────

fn t_parse_sockaddr_empty() -> TestResult {
  var r = socket_addr_from_str("");
  return assert(result_err_msg(r), "parse sockaddr: empty => Err");
}
fn t_parse_sockaddr_no_colon() -> TestResult {
  var r = socket_addr_from_str("127.0.0.1");
  return assert(result_err_msg(r), "parse sockaddr: missing colon => Err");
}
fn t_parse_sockaddr_no_ip() -> TestResult {
  var r = socket_addr_from_str(":8080");
  return assert(result_err_msg(r), "parse sockaddr: missing IP => Err");
}
fn t_parse_sockaddr_no_port() -> TestResult {
  var r = socket_addr_from_str("127.0.0.1:");
  return assert(result_err_msg(r), "parse sockaddr: missing port => Err");
}
fn t_parse_sockaddr_port_overflow() -> TestResult {
  var r = socket_addr_from_str("127.0.0.1:99999");
  return assert(result_err_msg(r), "parse sockaddr: port overflow => Err");
}
fn t_parse_sockaddr_bad_port_char() -> TestResult {
  var r = socket_addr_from_str("127.0.0.1:abc");
  return assert(result_err_msg(r), "parse sockaddr: non-digit port => Err");
}

// ─── sockaddr_in Binary ─────────────────────────────────────────────────────

fn t_sockaddr_in_len() -> TestResult {
  var ip = ipv4(192, 168, 1, 1);
  var addr = socket_addr(ip, 8080);
  var raw = build_sockaddr_in(&addr);
  return assert(vec_len(&raw) == 16, "sockaddr_in: 16 bytes");
}
fn t_sockaddr_in_roundtrip() -> TestResult {
  var ip = ipv4(10, 20, 30, 40);
  var addr = socket_addr(ip, 9090);
  var raw = build_sockaddr_in(&addr);
  var parsed = parse_sockaddr_in(&raw);
  var ok = false;
  match parsed {
    Ok(sa) => {
      ok = sa.port == 9090 && octet_at(&sa.ip, 0) == 10 && octet_at(&sa.ip, 3) == 40;
    }
    Err(_) => { ok = false; }
  }
  return assert(ok, "sockaddr_in: roundtrip 10.20.30.40:9090");
}
fn t_sockaddr_in_parse_short() -> TestResult {
  var short = make_buf_8();
  var r = parse_sockaddr_in(&short);
  return assert(result_err_msg(r), "sockaddr_in: short buffer => Err");
}
fn t_sockaddr_in_any() -> TestResult {
  var raw = build_sockaddr_in_any(3000);
  return assert(vec_len(&raw) == 16, "sockaddr_in_any: 16 bytes for INADDR_ANY");
}

// ─── Error Codes ────────────────────────────────────────────────────────────

fn t_error_refused() -> TestResult {
  return assert(str_eq(ws_error_to_str(10061), "connection refused"), "err: 10061 connection refused");
}
fn t_error_timed_out() -> TestResult {
  return assert(str_eq(ws_error_to_str(10060), "connection timed out"), "err: 10060 connection timed out");
}
fn t_error_perm_denied() -> TestResult {
  return assert(str_eq(ws_error_to_str(10013), "permission denied"), "err: 10013 permission denied");
}
fn t_error_addr_in_use() -> TestResult {
  return assert(str_eq(ws_error_to_str(10048), "address in use"), "err: 10048 address in use");
}
fn t_error_unknown() -> TestResult {
  var s = ws_error_to_str(0);
  return assert(str_starts_with(s, "unknown"), "err: 0 => unknown");
}

// ─── DNS Stubs ──────────────────────────────────────────────────────────────

fn t_dns_resolve_stub() -> TestResult {
  var r = dns_resolve("example.com");
  return assert(result_err_msg(r), "dns: resolve returns Err (stub)");
}
fn t_dns_reverse_stub() -> TestResult {
  var ip = ipv4(8, 8, 8, 8);
  var r = dns_reverse(ip);
  return assert(result_err_msg(r), "dns: reverse returns Err (stub)");
}

// ─── TCP Types ──────────────────────────────────────────────────────────────

fn t_tcp_stream_default() -> TestResult {
  var s = TcpStream{ fd: -1, connected: false, remote: SocketAddr{ ip: ipv4(0, 0, 0, 0), port: 0 } };
  var ok = !tcp_is_connected(&s) && s.fd == -1;
  return assert(ok, "tcp: default TcpStream not connected");
}
fn t_tcp_listener_default() -> TestResult {
  var l = TcpListener{ fd: -1, bound: false, addr: SocketAddr{ ip: ipv4(0, 0, 0, 0), port: 0 } };
  var ok = !l.bound && l.fd == -1;
  return assert(ok, "tcp: default TcpListener not bound");
}
fn t_tcp_remote_addr() -> TestResult {
  var ip = ipv4(1, 2, 3, 4);
  var addr = socket_addr(ip, 9999);
  var s = TcpStream{ fd: 42, connected: true, remote: addr };
  var ra = tcp_remote_addr(&s);
  return assert(ra.port == 9999 && octet_at(&ra.ip, 0) == 1, "tcp: remote_addr on connected stream");
}

// ─── UDP Types ──────────────────────────────────────────────────────────────

fn t_udp_socket_default() -> TestResult {
  var s = UdpSocket{ fd: -1, bound: false };
  return assert(s.fd == -1 && !s.bound, "udp: default UdpSocket not bound");
}

// ─── DnsResult Type ─────────────────────────────────────────────────────────

fn t_dns_result_type() -> TestResult {
  var r = DnsResult{ hostname: "test", addresses: Vec[IpAddr].new() };
  return assert(r.addresses.len() == 0, "dns: DnsResult empty addresses");
}

// ─── IpVersion Enum ─────────────────────────────────────────────────────────

fn t_ipversion_v4() -> TestResult {
  var v = IpVersion.V4;
  var ok = false;
  match v {
    V4 => { ok = true; }
    V6 => { ok = false; }
  }
  return assert(ok, "enum: IpVersion.V4 match");
}
fn t_ipversion_v6() -> TestResult {
  var v = IpVersion.V6;
  var ok = false;
  match v {
    V4 => { ok = false; }
    V6 => { ok = true; }
  }
  return assert(ok, "enum: IpVersion.V6 match");
}

// ─── Type Field Access ──────────────────────────────────────────────────────

fn t_ipaddr_octets_len() -> TestResult {
  var ip = ipv4(10, 20, 30, 40);
  return assert(ip.octets.len() == 4, "types: IpAddr octets len == 4");
}
fn t_sockaddr_ip_access() -> TestResult {
  var ip = ipv4(8, 8, 8, 8);
  var addr = socket_addr(ip, 53);
  return assert(addr.ip.version == 4 && octet_at(&addr.ip, 0) == 8, "types: SocketAddr.ip access");
}

// ─── wsa_cleanup ────────────────────────────────────────────────────────────

fn t_wsa_cleanup_noop() -> TestResult {
  wsa_cleanup();
  return assert(true, "tcp: wsa_cleanup does not crash");
}

// ─── Main ───────────────────────────────────────────────────────────────────

fn main() -> Int {
  io.println("=== XIOM Net Conformance ===");
  var failed: Int = 0;
  var total: Int = 0;

  var tests = [
    t_const_af_inet, t_const_sock_stream, t_const_sock_dgram, t_const_inaddr_any,
    t_const_invalid_socket, t_const_socket_error, t_const_somaxconn,
    t_ipv4_localhost, t_ipv4_zero, t_ipv4_max, t_ipv4_arbitrary,
    t_ipv6_localhost, t_ipv6_all_zero,
    t_parse_ipv4_localhost, t_parse_ipv4_zero, t_parse_ipv4_max, t_parse_ipv4_arbitrary,
    t_parse_ipv4_empty, t_parse_ipv4_garbage, t_parse_ipv4_overflow, t_parse_ipv4_too_few, t_parse_ipv4_too_many, t_parse_ipv4_trailing_dot,
    t_fmt_ipv4_127, t_fmt_ipv4_all,
    t_version_v4, t_version_v6, t_version_v4_not_v6,
    t_sockaddr_http, t_sockaddr_max_port, t_sockaddr_port_1,
    t_parse_sockaddr_http, t_parse_sockaddr_zero,
    t_parse_sockaddr_empty, t_parse_sockaddr_no_colon, t_parse_sockaddr_no_ip, t_parse_sockaddr_no_port, t_parse_sockaddr_port_overflow, t_parse_sockaddr_bad_port_char,
    t_sockaddr_in_len, t_sockaddr_in_roundtrip, t_sockaddr_in_parse_short, t_sockaddr_in_any,
    t_error_refused, t_error_timed_out, t_error_perm_denied, t_error_addr_in_use, t_error_unknown,
    t_dns_resolve_stub, t_dns_reverse_stub,
    t_tcp_stream_default, t_tcp_listener_default, t_tcp_remote_addr,
    t_udp_socket_default,
    t_dns_result_type,
    t_ipversion_v4, t_ipversion_v6,
    t_ipaddr_octets_len, t_sockaddr_ip_access,
    t_wsa_cleanup_noop
  ];

  var i = 0;
  while i < tests.len() {
    total = total + 1;
    failed = failed + report(tests[i]().passed, tests[i]().name);
    i = i + 1;
  }
  var passed = total - failed;
  io.println("");
  io.println("XIOM Net: " + int_to_str(passed) + "/" + int_to_str(total) + " passed" + (if failed > 0 { " (" + int_to_str(failed) + " FAILED)" } else { "" }));
  return failed;
}
