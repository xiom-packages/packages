module xiom.net.dns

pub type DnsResult = {
  hostname: Str;
  addresses: Vec[IpAddr];
} derive[Clone]

pub fn dns_resolve(hostname: Str) -> Result[DnsResult, Str]
  requires: hostname.len() > 0
{
  return Err("DNS requires OS resolver FFI — implement dns_resolve in Layer 2 via platform resolver API (getaddrinfo/gethostbyname)");
}

pub fn dns_reverse(ip: IpAddr) -> Result[Str, Str] {
  return Err("DNS requires OS resolver FFI — implement dns_reverse in Layer 2 via platform resolver API (getnameinfo/gethostbyaddr)");
}
