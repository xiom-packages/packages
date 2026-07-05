module xiom.net.types

pub enum IpVersion {
  V4,
  V6,
} derive[Clone]

pub type IpAddr = {
  octets: Vec[Int];
  version: Int;
} derive[Clone]

pub type SocketAddr = {
  ip: IpAddr;
  port: Int;
} derive[Clone]

pub fn IpAddr.is_v4() -> Bool {
  return version == 4;
}

pub fn IpAddr.is_v6() -> Bool {
  return version == 6;
}

pub fn ipv4(a: Int, b: Int, c: Int, d: Int) -> IpAddr
  requires: a >= 0 && a <= 255
  requires: b >= 0 && b <= 255
  requires: c >= 0 && c <= 255
  requires: d >= 0 && d <= 255
{
  var octets = Vec[Int].new();
  octets.push(a);
  octets.push(b);
  octets.push(c);
  octets.push(d);
  return IpAddr{ octets: octets, version: 4 };
}

pub fn ipv6_from_parts(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int, g: Int, h: Int) -> IpAddr
  requires: a >= 0 && a <= 65535
  requires: b >= 0 && b <= 65535
  requires: c >= 0 && c <= 65535
  requires: d >= 0 && d <= 65535
  requires: e >= 0 && e <= 65535
  requires: f >= 0 && f <= 65535
  requires: g >= 0 && g <= 65535
  requires: h >= 0 && h <= 65535
{
  var octets = Vec[Int].new();
  octets.push((a >> 8) & 0xFF);
  octets.push(a & 0xFF);
  octets.push((b >> 8) & 0xFF);
  octets.push(b & 0xFF);
  octets.push((c >> 8) & 0xFF);
  octets.push(c & 0xFF);
  octets.push((d >> 8) & 0xFF);
  octets.push(d & 0xFF);
  octets.push((e >> 8) & 0xFF);
  octets.push(e & 0xFF);
  octets.push((f >> 8) & 0xFF);
  octets.push(f & 0xFF);
  octets.push((g >> 8) & 0xFF);
  octets.push(g & 0xFF);
  octets.push((h >> 8) & 0xFF);
  octets.push(h & 0xFF);
  return IpAddr{ octets: octets, version: 6 };
}

fn char_is_digit(c: Int) -> Bool {
  return c >= '0' && c <= '9';
}

fn str_to_int_part(s: Str, start: Int, end: Int) -> Result[(Int, Int), Str] {
  var result: Int = 0;
  var i: Int = start;
  var consumed: Int = 0;
  while i < end && char_is_digit(s[i]) {
    result = result * 10 + (s[i] - '0');
    if result > 255 { return Err("octet value exceeds 255"); };
    i = i + 1;
    consumed = consumed + 1;
  };
  if consumed == 0 { return Err("expected digit"); };
  return Ok((result, consumed));
}

pub fn ipv4_from_str(s: Str) -> Result[IpAddr, Str]
  requires: s.len() > 0
{
  var octets = Vec[Int].new();
  var i: Int = 0;
  var len: Int = s.len();
  var octet_count: Int = 0;
  while i < len && octet_count < 4 {
    var part = str_to_int_part(s, i, len);
    match part {
      Ok((value, consumed)) => {
        octets.push(value);
        octet_count = octet_count + 1;
        i = i + consumed;
        if octet_count < 4 && i < len {
          if s[i] != '.' { return Err("expected '.' separator between octets"); };
          i = i + 1;
          if i >= len { return Err("unexpected end after '.'"); };
        };
      },
      Err(msg) => { return Err(msg); },
    }
  };
  if octet_count != 4 { return Err("IPv4 address must have exactly 4 octets"); };
  if i < len { return Err("trailing characters after IPv4 address"); };
  return Ok(IpAddr{ octets: octets, version: 4 });
}

fn u8_to_str(n: Int) -> Str {
  var num: Int = n;
  var hundreds: Int = num / 100;
  num = num % 100;
  var tens: Int = num / 10;
  var ones: Int = num % 10;
  var result: Str = "";
  if hundreds > 0 {
    if hundreds == 1 { result = "1"; }
    elif hundreds == 2 { result = "2"; };
    tens = num / 10;
    ones = num % 10;
    if tens == 0 { result = result + "0"; }
    elif tens == 1 { result = result + "1"; }
    elif tens == 2 { result = result + "2"; }
    elif tens == 3 { result = result + "3"; }
    elif tens == 4 { result = result + "4"; }
    elif tens == 5 { result = result + "5"; }
    elif tens == 6 { result = result + "6"; }
    elif tens == 7 { result = result + "7"; }
    elif tens == 8 { result = result + "8"; }
    elif tens == 9 { result = result + "9"; };
    if ones == 0 { result = result + "0"; }
    elif ones == 1 { result = result + "1"; }
    elif ones == 2 { result = result + "2"; }
    elif ones == 3 { result = result + "3"; }
    elif ones == 4 { result = result + "4"; }
    elif ones == 5 { result = result + "5"; }
    elif ones == 6 { result = result + "6"; }
    elif ones == 7 { result = result + "7"; }
    elif ones == 8 { result = result + "8"; }
    elif ones == 9 { result = result + "9"; };
  } elif tens > 0 {
    if tens == 1 { result = "1"; }
    elif tens == 2 { result = "2"; }
    elif tens == 3 { result = "3"; }
    elif tens == 4 { result = "4"; }
    elif tens == 5 { result = "5"; }
    elif tens == 6 { result = "6"; }
    elif tens == 7 { result = "7"; }
    elif tens == 8 { result = "8"; }
    elif tens == 9 { result = "9"; };
    if ones == 0 { result = result + "0"; }
    elif ones == 1 { result = result + "1"; }
    elif ones == 2 { result = result + "2"; }
    elif ones == 3 { result = result + "3"; }
    elif ones == 4 { result = result + "4"; }
    elif ones == 5 { result = result + "5"; }
    elif ones == 6 { result = result + "6"; }
    elif ones == 7 { result = result + "7"; }
    elif ones == 8 { result = result + "8"; }
    elif ones == 9 { result = result + "9"; };
  } else {
    if ones == 0 { result = "0"; }
    elif ones == 1 { result = "1"; }
    elif ones == 2 { result = "2"; }
    elif ones == 3 { result = "3"; }
    elif ones == 4 { result = "4"; }
    elif ones == 5 { result = "5"; }
    elif ones == 6 { result = "6"; }
    elif ones == 7 { result = "7"; }
    elif ones == 8 { result = "8"; }
    elif ones == 9 { result = "9"; };
  };
  return result;
}

pub fn ipv4_to_str(ip: &IpAddr) -> Str
  requires: ip.version == 4
  requires: ip.octets.len() == 4
{
  var a = ip.octets[0];
  var b = ip.octets[1];
  var c = ip.octets[2];
  var d = ip.octets[3];
  return u8_to_str(a) + "." + u8_to_str(b) + "." + u8_to_str(c) + "." + u8_to_str(d);
}

pub fn socket_addr(ip: IpAddr, port: Int) -> SocketAddr
  requires: port > 0
  requires: port < 65536
{
  return SocketAddr{ ip: ip, port: port };
}

pub fn socket_addr_from_str(s: Str) -> Result[SocketAddr, Str]
  requires: s.len() > 0
{
  var len: Int = s.len();
  var colon_pos: Int = -1;
  var i: Int = 0;
  while i < len && colon_pos == -1 {
    if s[i] == ':' { colon_pos = i; };
    i = i + 1;
  };
  if colon_pos == -1 { return Err("missing port separator ':'"); };
  if colon_pos == 0 { return Err("missing IP address before ':'"); };
  if colon_pos == len - 1 { return Err("missing port number after ':'"); };

  var ip_result = ipv4_from_str_part(s, 0, colon_pos);
  var ip = ip_result?;

  var port_str: Str = "";
  var j: Int = colon_pos + 1;
  while j < len {
    if !char_is_digit(s[j]) { return Err("invalid character in port number"); };
    port_str = port_str + digit_to_char_str(s[j] - '0');
    j = j + 1;
  };
  var port: Int = str_to_int(port_str);
  if port > 65535 { return Err("port number exceeds 65535"); };

  return Ok(SocketAddr{ ip: ip, port: port });
}

fn ipv4_from_str_part(s: Str, start: Int, end: Int) -> Result[IpAddr, Str] {
  var octets = Vec[Int].new();
  var i: Int = start;
  var octet_count: Int = 0;
  if i >= end { return Err("empty IP address"); };
  while i < end && octet_count < 4 {
    var part = str_to_int_part(s, i, end);
    match part {
      Ok((value, consumed)) => {
        octets.push(value);
        octet_count = octet_count + 1;
        i = i + consumed;
        if octet_count < 4 && i < end {
          if s[i] != '.' { return Err("expected '.' separator between octets"); };
          i = i + 1;
          if i >= end { return Err("unexpected end after '.'"); };
        };
      },
      Err(msg) => { return Err(msg); },
    }
  };
  if octet_count != 4 { return Err("IPv4 address must have exactly 4 octets"); };
  if i < end { return Err("trailing characters in IP address"); };
  return Ok(IpAddr{ octets: octets, version: 4 });
}

fn digit_to_char_str(d: Int) -> Str {
  if d == 0 { return "0"; }
  elif d == 1 { return "1"; }
  elif d == 2 { return "2"; }
  elif d == 3 { return "3"; }
  elif d == 4 { return "4"; }
  elif d == 5 { return "5"; }
  elif d == 6 { return "6"; }
  elif d == 7 { return "7"; }
  elif d == 8 { return "8"; }
  elif d == 9 { return "9"; };
  return "0";
}

fn str_to_int(s: Str) -> Int {
  var result: Int = 0;
  var i: Int = 0;
  var len: Int = s.len();
  while i < len {
    var d = s[i] - '0';
    result = result * 10 + d;
    i = i + 1;
  };
  return result;
}

pub const AF_INET: Int = 2;
pub const SOCK_STREAM: Int = 1;
pub const SOCK_DGRAM: Int = 2;
pub const INADDR_ANY: Int = 0;
pub const INVALID_SOCKET: Int = -1;
pub const SOCKET_ERROR: Int = -1;
pub const SOMAXCONN: Int = 128;

fn htons(host: Int) -> Int {
  var hi: Int = (host >> 8) & 0xFF;
  var lo: Int = host & 0xFF;
  return (lo << 8) | hi;
}

fn ntohs(net: Int) -> Int {
  return htons(net);
}

fn build_u32_be(a: Int, b: Int, c: Int, d: Int) -> Int {
  return (a << 24) | (b << 16) | (c << 8) | d;
}

pub fn build_sockaddr_in(addr: &SocketAddr) -> Vec[Int]
  requires: addr.ip.version == 4
  requires: addr.ip.octets.len() == 4
{
  var buf = Vec[Int].new();
  var port_net: Int = htons(addr.port);
  buf.push(AF_INET & 0xFF);
  buf.push((AF_INET >> 8) & 0xFF);
  buf.push(port_net & 0xFF);
  buf.push((port_net >> 8) & 0xFF);
  buf.push(addr.ip.octets[0]);
  buf.push(addr.ip.octets[1]);
  buf.push(addr.ip.octets[2]);
  buf.push(addr.ip.octets[3]);
  var z: Int = 0;
  while z < 8 {
    buf.push(0);
    z = z + 1;
  };
  return buf;
}

pub fn build_sockaddr_in_any(port: Int) -> Vec[Int]
  requires: port >= 0 && port <= 65535
{
  var any_addr = ipv4(0, 0, 0, 0);
  var addr = socket_addr(any_addr, port);
  return build_sockaddr_in(&addr);
}

pub fn parse_sockaddr_in(raw: &Vec[Int]) -> Result[SocketAddr, Str] {
  if raw.len() < 16 { return Err("sockaddr_in too short — need 16 bytes"); };
  var port_lo: Int = raw[2];
  var port_hi: Int = raw[3];
  var port_net: Int = (port_hi << 8) | port_lo;
  var port: Int = ntohs(port_net);
  var a: Int = raw[4];
  var b: Int = raw[5];
  var c: Int = raw[6];
  var d: Int = raw[7];
  var ip = ipv4(a, b, c, d);
  return Ok(socket_addr(ip, port));
}

pub fn ws_error_to_str(code: Int) -> Str {
  if code == 10013 { return "permission denied"; }
  elif code == 10022 { return "invalid argument"; }
  elif code == 10035 { return "would block"; }
  elif code == 10036 { return "in progress"; }
  elif code == 10037 { return "already in progress"; }
  elif code == 10038 { return "not a socket"; }
  elif code == 10039 { return "destination address required"; }
  elif code == 10040 { return "message too long"; }
  elif code == 10047 { return "address family not supported"; }
  elif code == 10048 { return "address in use"; }
  elif code == 10049 { return "address not available"; }
  elif code == 10050 { return "network down"; }
  elif code == 10051 { return "network unreachable"; }
  elif code == 10052 { return "network reset"; }
  elif code == 10053 { return "connection aborted"; }
  elif code == 10054 { return "connection reset"; }
  elif code == 10055 { return "no buffer space"; }
  elif code == 10056 { return "already connected"; }
  elif code == 10057 { return "not connected"; }
  elif code == 10060 { return "connection timed out"; }
  elif code == 10061 { return "connection refused"; }
  elif code == 10064 { return "host down"; }
  elif code == 10065 { return "host unreachable"; }
  elif code == 10091 { return "network subsystem unavailable"; }
  elif code == 10092 { return "Winsock version not supported"; }
  elif code == 10093 { return "WSAStartup not called"; };
  return "unknown socket error";
}
