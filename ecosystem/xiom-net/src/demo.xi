module xiom.net.demo

fn str_to_bytes(s: Str) -> Vec[Int] {
  var buf = Vec[Int].new();
  var i: Int = 0;
  var len: Int = s.len();
  while i < len {
    buf.push(s[i]);
    i = i + 1;
  };
  return buf;
}

fn bytes_to_str(buf: &Vec[Int], n: Int) -> Str {
  var result: Str = "";
  var i: Int = 0;
  while i < n && i < buf.len() {
    var c: Int = buf[i];
    if c >= 32 && c <= 126 {
      var ch: Str = "";
      if c == 32 { ch = " "; }
      elif c == 33 { ch = "!"; }
      elif c == 34 { ch = "\""; }
      elif c == 35 { ch = "#"; }
      elif c == 36 { ch = "$"; }
      elif c == 37 { ch = "%"; }
      elif c == 38 { ch = "&"; }
      elif c == 39 { ch = "'"; }
      elif c == 40 { ch = "("; }
      elif c == 41 { ch = ")"; }
      elif c == 42 { ch = "*"; }
      elif c == 43 { ch = "+"; }
      elif c == 44 { ch = ","; }
      elif c == 45 { ch = "-"; }
      elif c == 46 { ch = "."; }
      elif c == 47 { ch = "/"; }
      elif c == 48 { ch = "0"; }
      elif c == 49 { ch = "1"; }
      elif c == 50 { ch = "2"; }
      elif c == 51 { ch = "3"; }
      elif c == 52 { ch = "4"; }
      elif c == 53 { ch = "5"; }
      elif c == 54 { ch = "6"; }
      elif c == 55 { ch = "7"; }
      elif c == 56 { ch = "8"; }
      elif c == 57 { ch = "9"; }
      elif c == 58 { ch = ":"; }
      elif c == 59 { ch = ";"; }
      elif c == 60 { ch = "<"; }
      elif c == 61 { ch = "="; }
      elif c == 62 { ch = ">"; }
      elif c == 63 { ch = "?"; }
      elif c == 64 { ch = "@"; }
      elif c == 65 { ch = "A"; }
      elif c == 66 { ch = "B"; }
      elif c == 67 { ch = "C"; }
      elif c == 68 { ch = "D"; }
      elif c == 69 { ch = "E"; }
      elif c == 70 { ch = "F"; }
      elif c == 71 { ch = "G"; }
      elif c == 72 { ch = "H"; }
      elif c == 73 { ch = "I"; }
      elif c == 74 { ch = "J"; }
      elif c == 75 { ch = "K"; }
      elif c == 76 { ch = "L"; }
      elif c == 77 { ch = "M"; }
      elif c == 78 { ch = "N"; }
      elif c == 79 { ch = "O"; }
      elif c == 80 { ch = "P"; }
      elif c == 81 { ch = "Q"; }
      elif c == 82 { ch = "R"; }
      elif c == 83 { ch = "S"; }
      elif c == 84 { ch = "T"; }
      elif c == 85 { ch = "U"; }
      elif c == 86 { ch = "V"; }
      elif c == 87 { ch = "W"; }
      elif c == 88 { ch = "X"; }
      elif c == 89 { ch = "Y"; }
      elif c == 90 { ch = "Z"; }
      elif c == 91 { ch = "["; }
      elif c == 92 { ch = "\\"; }
      elif c == 93 { ch = "]"; }
      elif c == 94 { ch = "^"; }
      elif c == 95 { ch = "_"; }
      elif c == 96 { ch = "`"; }
      elif c == 97 { ch = "a"; }
      elif c == 98 { ch = "b"; }
      elif c == 99 { ch = "c"; }
      elif c == 100 { ch = "d"; }
      elif c == 101 { ch = "e"; }
      elif c == 102 { ch = "f"; }
      elif c == 103 { ch = "g"; }
      elif c == 104 { ch = "h"; }
      elif c == 105 { ch = "i"; }
      elif c == 106 { ch = "j"; }
      elif c == 107 { ch = "k"; }
      elif c == 108 { ch = "l"; }
      elif c == 109 { ch = "m"; }
      elif c == 110 { ch = "n"; }
      elif c == 111 { ch = "o"; }
      elif c == 112 { ch = "p"; }
      elif c == 113 { ch = "q"; }
      elif c == 114 { ch = "r"; }
      elif c == 115 { ch = "s"; }
      elif c == 116 { ch = "t"; }
      elif c == 117 { ch = "u"; }
      elif c == 118 { ch = "v"; }
      elif c == 119 { ch = "w"; }
      elif c == 120 { ch = "x"; }
      elif c == 121 { ch = "y"; }
      elif c == 122 { ch = "z"; }
      elif c == 123 { ch = "{"; }
      elif c == 124 { ch = "|"; }
      elif c == 125 { ch = "}"; }
      elif c == 126 { ch = "~"; };
      result = result + ch;
    } elif c == 10 {
      result = result + "\n";
    } elif c == 13 {
      result = result + "\r";
    } else {
      result = result + ".";
    };
    i = i + 1;
  };
  return result;
}

fn resolve_host(hostname: Str) -> Result[IpAddr, Str] {
  var dns = dns_resolve(hostname);
  match dns {
    Ok(result) => {
      if result.addresses.len() == 0 {
        return Err("DNS returned no addresses for " + hostname);
      };
      return Ok(result.addresses[0]);
    },
    Err(msg) => {
      return Err("DNS resolution failed: " + msg);
    },
  }
}

pub fn demo_http_request() -> Result[Unit, Str] {
  var hostname: Str = "example.com";
  var port: Int = 80;

  var ip = ipv4(93, 184, 216, 34);
  var ip_result = resolve_host(hostname);
  match ip_result {
    Ok(resolved) => { ip = resolved; },
    Err(_) => {},
  };

  var addr = socket_addr(ip, port);
  var stream_result = tcp_connect(addr);
  match stream_result {
    Err(msg) => { return Err("TCP connect to " + hostname + ":80 failed: " + msg); },
    Ok(stream) => {},
  };
  var stream = stream_result?;

  var request: Str = "GET / HTTP/1.0\r\nHost: example.com\r\nConnection: close\r\n\r\n";
  var req_bytes = str_to_bytes(request);
  var write_result = tcp_write(&mut stream, &req_bytes);
  match write_result {
    Err(msg) => {
      tcp_close(stream);
      return Err("HTTP request write failed: " + msg);
    },
    Ok(n) => {},
  };

  var buf = Vec[Int].new();
  var i: Int = 0;
  while i < 4096 {
    buf.push(0);
    i = i + 1;
  };
  var total: Int = 0;
  var done: Bool = false;
  while !done {
    var read_result = tcp_read(&mut stream, &mut buf);
    match read_result {
      Err(msg) => {
        tcp_close(stream);
        return Err("HTTP response read failed: " + msg);
      },
      Ok(0) => { done = true; },
      Ok(n) => {
        total = total + n;
        if total >= 65536 { done = true; };
      },
    }
  };

  tcp_close(stream);
  return Ok(());
}

pub fn demo_echo_server() -> Result[Unit, Str] {
  var ip = ipv4(127, 0, 0, 1);
  var addr = socket_addr(ip, 8080);

  var listen_result = tcp_listen(addr);
  match listen_result {
    Err(msg) => { return Err("echo server listen on 127.0.0.1:8080 failed: " + msg); },
    Ok(listener) => {},
  };
  var listener = listen_result?;

  var client_result = tcp_accept(&mut listener);
  match client_result {
    Err(msg) => {
      tcp_listener_close(listener);
      return Err("echo server accept failed: " + msg);
    },
    Ok(client) => {},
  };
  var client = client_result?;

  var buf = Vec[Int].new();
  var i: Int = 0;
  while i < 4096 {
    buf.push(0);
    i = i + 1;
  };
  var read_result = tcp_read(&mut client, &mut buf);
  match read_result {
    Err(msg) => {
      tcp_close(client);
      tcp_listener_close(listener);
      return Err("echo server read failed: " + msg);
    },
    Ok(n) => {},
  };
  var n = read_result?;

  if n > 0 {
    var write_result = tcp_write(&mut client, &buf);
    match write_result {
      Err(msg) => {
        tcp_close(client);
        tcp_listener_close(listener);
        return Err("echo server write failed: " + msg);
      },
      Ok(written) => {},
    };
  };

  tcp_close(client);
  tcp_listener_close(listener);
  return Ok(());
}
