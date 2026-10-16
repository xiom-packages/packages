// XIOM -- xiom.ssl conformance tests (dynamic loader + real TLS traffic).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// CI WITHOUT OpenSSL stays green: no candidate libssl soname -> SKIP (the
// SKIP path is exercised deterministically every run via a bogus soname).
// When a libssl build is available the suite proves real functionality:
//   * PEM and DER cert/key/chain load from files AND buffers;
//   * a full client/server TLS handshake over a real loopback socket
//     (nonblocking fds driven through ssl_step), negotiated version and
//     cipher read back, app data both directions, clean shutdown 0/1/1;
//   * a full handshake over memory BIOs only (no socket at all) with
//     ciphertext moved by the test through ssl_bio_drain/ssl_bio_feed;
//   * verify modes: none, peer-with-trusted-CA (verify_result 0), and
//     peer-with-no-CA (typed handshake failure + non-OK verify_result);
//   * ALPN: wire-format helper golden, client list set, negotiated read
//     (none selected without a server callback -- the documented state).
// The fixtures are a self-signed localhost cert/key generated for tests
// only (PEM + DER; see PROVENANCE.md).
//
// Build+run (no extra compiler args: pure-XIOM loader):
//   scripts/port.ps1 -Package xiom.ssl
// The live path needs a libssl on the DLL search path (on this box:
// prepend "C:\Program Files\Git\mingw64\bin", matching the xiom.openssl
// SPEC precedent); without one the suite reports SKIP and stays green.

module ssl_conformance

use xiom.io;
use xiom.convert;
use xiom.net.socket;
use xiom.string.compare;
use xiom.ssl;

const CERT_PEM_PATH: Str = "tests/fixtures/server-cert.pem";
const KEY_PEM_PATH: Str = "tests/fixtures/server-key.pem";
const CERT_DER_PATH: Str = "tests/fixtures/server-cert.der";
const KEY_DER_PATH: Str = "tests/fixtures/server-key.der";

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn why(msg: Str) {
  io.println("    detail: " + msg);
  io.flush_stdout();
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_of(s: Str) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    out.push(s.byte_at(i));
    i = i + 1;
  }
  return out;
}

fn finish(failed: Int) -> Int {
  if failed == 0 {
    io.println("xiom.ssl: all tests passed");
  } else {
    io.println("xiom.ssl: tests failed");
  }
  return failed;
}

/// Server context with the fixture cert+key loaded from the PEM files.
fn load_server_ctx(lib: &SslLibrary) -> Result[SslContext, SslError] {
  let cr = ssl_ctx_new(lib, true);
  if !cr.is_ok { return Err(cr.error); }
  let c: SslContext = cr.value;
  let r1 = ssl_ctx_use_cert_file(lib, &c, CERT_PEM_PATH, true);
  if !r1.is_ok { ssl_ctx_free(lib, &c); return Err(r1.error); }
  let r2 = ssl_ctx_use_key_file(lib, &c, KEY_PEM_PATH, true);
  if !r2.is_ok { ssl_ctx_free(lib, &c); return Err(r2.error); }
  let r3 = ssl_ctx_check_private_key(lib, &c);
  if !r3.is_ok { ssl_ctx_free(lib, &c); return Err(r3.error); }
  return Ok(c);
}

// =========================================================================
// Loopback socket pair (scan a port range; never bind port 0 -- the stdlib
// does not expose getsockname)
// =========================================================================

type FdPair = {
  ok: Bool;
  lfd: Int;
  afd: Int;
  cfd: Int;
  port: Int;
}

fn open_pair() -> FdPair {
  var out = FdPair{ ok: false; lfd: -1; afd: -1; cfd: -1; port: 0 };
  var attempt = 46200;
  while attempt < 46280 {
    let t = socket_tcp();
    if !t.is_ok { return out; }
    let lfd0: Int = t.value;
    let b = socket_bind(lfd0, "127.0.0.1", attempt);
    if b.is_ok {
      let l = socket_listen(lfd0, 4);
      if l.is_ok {
        let c = socket_tcp();
        if !c.is_ok {
          socket_close(lfd0);
          return out;
        }
        let cfd0: Int = c.value;
        let cn = socket_connect(cfd0, "127.0.0.1", attempt);
        if cn.is_ok {
          let a = socket_accept(lfd0);
          if a.is_ok {
            out.ok = true;
            out.lfd = lfd0;
            out.cfd = cfd0;
            out.afd = a.value;
            out.port = attempt;
            return out;
          }
        }
        socket_close(cfd0);
      }
      socket_close(lfd0);
    }
    attempt = attempt + 1;
  }
  return out;
}

// =========================================================================
// Handshake pump over nonblocking socket fds
// =========================================================================

type PumpOutcome = {
  srv_done: Bool;
  cli_done: Bool;
  srv_err: Bool;
  cli_err: Bool;
  srv_kind: Int;
  cli_kind: Int;
  srv_msg: Str;
  cli_msg: Str;
  rounds: Int;
}

fn pump_fd(lib: &SslLibrary, srv: &SslStream, cli: &SslStream, srv_fd: Int, cli_fd: Int) -> PumpOutcome {
  var out = PumpOutcome{
    srv_done: false; cli_done: false; srv_err: false; cli_err: false;
    srv_kind: -1; cli_kind: -1; srv_msg: ""; cli_msg: ""; rounds: 0;
  };
  var i = 0;
  while i < 3000 {
    if (out.srv_done && out.cli_done) || out.srv_err || out.cli_err { break; }
    var srv_want = 0;
    var cli_want = 0;
    if !out.srv_done && !out.srv_err {
      let rs = ssl_step(lib, srv, true);
      if rs.is_ok {
        let st: SslStep = rs.value;
        if st.done { out.srv_done = true; } else { srv_want = st.want; }
      } else {
        out.srv_err = true;
        out.srv_kind = rs.error.kind;
        out.srv_msg = rs.error.message;
      }
    }
    if !out.cli_done && !out.cli_err {
      let rc = ssl_step(lib, cli, false);
      if rc.is_ok {
        let st2: SslStep = rc.value;
        if st2.done { out.cli_done = true; } else { cli_want = st2.want; }
      } else {
        out.cli_err = true;
        out.cli_kind = rc.error.kind;
        out.cli_msg = rc.error.message;
      }
    }
    if (out.srv_done && out.cli_done) || out.srv_err || out.cli_err { break; }
    if srv_want == SSL_WANT_WRITE || cli_want == SSL_WANT_WRITE {
      var wfds: Vec[Int] = Vec[Int].new();
      if !out.srv_done && !out.srv_err { wfds.push(srv_fd); }
      if !out.cli_done && !out.cli_err { wfds.push(cli_fd); }
      let pw = socket_poll_write(&wfds, 20);
      let _ = pw;
    } else {
      var fds: Vec[Int] = Vec[Int].new();
      if !out.srv_done && !out.srv_err { fds.push(srv_fd); }
      if !out.cli_done && !out.cli_err { fds.push(cli_fd); }
      let pr = socket_poll_read(&fds, 20);
      let _ = pr;
    }
    i = i + 1;
    out.rounds = i;
  }
  return out;
}

// =========================================================================
// Cert/key/chain/CA load matrix (PEM/DER x files/buffers)
// =========================================================================

fn test_cert_loads(lib: &SslLibrary) -> Int {
  var failed = 0;
  let cert_pem_r = io.read_file(CERT_PEM_PATH);
  let key_pem_r = io.read_file(KEY_PEM_PATH);
  let cert_der_r = io.read_file_bytes(CERT_DER_PATH);
  let key_der_r = io.read_file_bytes(KEY_DER_PATH);
  if !cert_pem_r.is_ok { why("cert pem read: " + cert_pem_r.error.message + " (code " + to_string(cert_pem_r.error.code) + ")"); }
  if !key_pem_r.is_ok { why("key pem read: " + key_pem_r.error.message + " (code " + to_string(key_pem_r.error.code) + ")"); }
  if !cert_der_r.is_ok { why("cert der read: " + cert_der_r.error.message + " (code " + to_string(cert_der_r.error.code) + ")"); }
  if !key_der_r.is_ok { why("key der read: " + key_der_r.error.message + " (code " + to_string(key_der_r.error.code) + ")"); }
  if !cert_pem_r.is_ok || !key_pem_r.is_ok || !cert_der_r.is_ok || !key_der_r.is_ok {
    return report(false, "fixtures: cannot read tests/fixtures/* (cwd must be the package dir)");
  }
  let cert_pem: Str = cert_pem_r.value;
  let key_pem: Str = key_pem_r.value;
  let cert_der: Vec[UInt8] = cert_der_r.value;
  let key_der: Vec[UInt8] = key_der_r.value;

  // PEM files.
  let c1 = ssl_ctx_new(lib, true);
  if !c1.is_ok {
    return report(false, "ctx: server context creation failed: " + c1.error.message);
  }
  let ctx1: SslContext = c1.value;
  let r11 = ssl_ctx_use_cert_file(lib, &ctx1, CERT_PEM_PATH, true);
  let r12 = ssl_ctx_use_key_file(lib, &ctx1, KEY_PEM_PATH, true);
  let r13 = ssl_ctx_check_private_key(lib, &ctx1);
  failed = failed + report(r11.is_ok && r12.is_ok && r13.is_ok,
    "cert-files-pem: cert+key load from PEM files; check_private_key matches");
  if !r11.is_ok { why(r11.error.message); }
  if !r12.is_ok { why(r12.error.message); }
  if !r13.is_ok { why(r13.error.message); }
  ssl_ctx_free(lib, &ctx1);

  // PEM buffers.
  let c2 = ssl_ctx_new(lib, true);
  if !c2.is_ok {
    return failed + report(false, "ctx: second server context failed: " + c2.error.message);
  }
  let ctx2: SslContext = c2.value;
  let r21 = ssl_ctx_use_cert_pem(lib, &ctx2, cert_pem);
  let r22 = ssl_ctx_use_key_pem(lib, &ctx2, key_pem);
  let r23 = ssl_ctx_check_private_key(lib, &ctx2);
  failed = failed + report(r21.is_ok && r22.is_ok && r23.is_ok,
    "cert-buffers-pem: cert+key load from PEM buffers (memory BIO + PEM_read_bio_*)");
  if !r21.is_ok { why(r21.error.message); }
  if !r22.is_ok { why(r22.error.message); }
  if !r23.is_ok { why(r23.error.message); }
  ssl_ctx_free(lib, &ctx2);

  // DER files.
  let c3 = ssl_ctx_new(lib, true);
  if !c3.is_ok {
    return failed + report(false, "ctx: third server context failed: " + c3.error.message);
  }
  let ctx3: SslContext = c3.value;
  let r31 = ssl_ctx_use_cert_file(lib, &ctx3, CERT_DER_PATH, false);
  let r32 = ssl_ctx_use_key_file(lib, &ctx3, KEY_DER_PATH, false);
  let r33 = ssl_ctx_check_private_key(lib, &ctx3);
  failed = failed + report(r31.is_ok && r32.is_ok && r33.is_ok,
    "cert-files-der: cert+key load from DER files (SSL_FILETYPE_ASN1)");
  if !r31.is_ok { why(r31.error.message); }
  if !r32.is_ok { why(r32.error.message); }
  if !r33.is_ok { why(r33.error.message); }
  ssl_ctx_free(lib, &ctx3);

  // DER buffers.
  let c4 = ssl_ctx_new(lib, true);
  if !c4.is_ok {
    return failed + report(false, "ctx: fourth server context failed: " + c4.error.message);
  }
  let ctx4: SslContext = c4.value;
  let r41 = ssl_ctx_use_cert_der(lib, &ctx4, &cert_der);
  let r42 = ssl_ctx_use_key_der(lib, &ctx4, &key_der);
  let r43 = ssl_ctx_check_private_key(lib, &ctx4);
  failed = failed + report(r41.is_ok && r42.is_ok && r43.is_ok,
    "cert-buffers-der: cert (ASN1) + key (d2i_AutoPrivateKey) load from DER buffers");
  if !r41.is_ok { why(r41.error.message); }
  if !r42.is_ok { why(r42.error.message); }
  if !r43.is_ok { why(r43.error.message); }
  ssl_ctx_free(lib, &ctx4);

  // Chain buffers (self-signed: the same cert joins the chain).
  let c5 = ssl_ctx_new(lib, true);
  if !c5.is_ok {
    return failed + report(false, "ctx: fifth server context failed: " + c5.error.message);
  }
  let ctx5: SslContext = c5.value;
  let r51 = ssl_ctx_use_cert_file(lib, &ctx5, CERT_PEM_PATH, true);
  let r52 = ssl_ctx_use_key_file(lib, &ctx5, KEY_PEM_PATH, true);
  let r53 = ssl_ctx_add_chain_pem(lib, &ctx5, cert_pem);
  let r54 = ssl_ctx_add_chain_der(lib, &ctx5, &cert_der);
  failed = failed + report(r51.is_ok && r52.is_ok && r53.is_ok && r54.is_ok,
    "chain-buffers: extra chain cert appended from PEM and DER buffers");
  if !r53.is_ok { why(r53.error.message); }
  if !r54.is_ok { why(r54.error.message); }
  ssl_ctx_free(lib, &ctx5);

  // Trust anchors: CA file loads; an absent file is a typed SSL_ERR_CERT.
  let c6 = ssl_ctx_new(lib, false);
  if !c6.is_ok {
    return failed + report(false, "ctx: client context failed: " + c6.error.message);
  }
  let ctx6: SslContext = c6.value;
  let r61 = ssl_ctx_load_verify_locations(lib, &ctx6, CERT_PEM_PATH, "");
  let r62 = ssl_ctx_load_verify_locations(lib, &ctx6, "tests/fixtures/absent-ca-bundle.pem", "");
  failed = failed + report(r61.is_ok && !r62.is_ok && r62.error.kind == SSL_ERR_CERT,
    "verify-locations: CA file loads; absent file is a typed SSL_ERR_CERT");
  if !r61.is_ok { why(r61.error.message); }
  if r62.is_ok { why("absent CA bundle unexpectedly loaded"); }
  ssl_ctx_free(lib, &ctx6);

  return failed;
}

// =========================================================================
// Full handshake over a real loopback socket: verify-none, SNI, ALPN set,
// version/cipher, app data both ways, clean shutdown 0/1/1
// =========================================================================

fn test_fd_tls(lib: &SslLibrary) -> Int {
  var failed = 0;
  let sc = load_server_ctx(lib);
  if !sc.is_ok {
    return report(false, "fd: server context/cert load failed: " + sc.error.message);
  }
  let sctx: SslContext = sc.value;
  let cc = ssl_ctx_new(lib, false);
  if !cc.is_ok {
    ssl_ctx_free(lib, &sctx);
    return report(false, "fd: client context failed: " + cc.error.message);
  }
  let cctx: SslContext = cc.value;
  ssl_ctx_set_verify(lib, &cctx, SSL_VERIFY_NONE);

  // ALPN client list, wire format, set on the ctx BEFORE ssl_new (SSL_new
  // copies the ctx list to the stream).
  var names: Vec[Str] = Vec[Str].new();
  names.push("h2");
  names.push("http/1.1");
  let aw = ssl_alpn_wire(&names);
  var alpn_set_ok = false;
  if aw.is_ok {
    let wire: Vec[UInt8] = aw.value;
    let ar = ssl_ctx_set_alpn_protos(lib, &cctx, &wire);
    alpn_set_ok = ar.is_ok;
    if !ar.is_ok { why(ar.error.message); }
  } else {
    why(aw.error);
  }

  let pair = open_pair();
  if !pair.ok {
    ssl_ctx_free(lib, &cctx);
    ssl_ctx_free(lib, &sctx);
    return report(false, "fd: no loopback port available (scan 46200-46279)");
  }

  let ns = ssl_new(lib, &sctx);
  let nc = ssl_new(lib, &cctx);
  if !ns.is_ok || !nc.is_ok {
    if !ns.is_ok { why(ns.error.message); }
    if !nc.is_ok { why(nc.error.message); }
    socket_close(pair.afd);
    socket_close(pair.cfd);
    socket_close(pair.lfd);
    ssl_ctx_free(lib, &cctx);
    ssl_ctx_free(lib, &sctx);
    return report(false, "fd: SSL_new failed");
  }
  var srv: SslStream = ns.value;
  var cli: SslStream = nc.value;

  let sf = ssl_set_fd(lib, &mut srv, pair.afd);
  let cf = ssl_set_fd(lib, &mut cli, pair.cfd);
  let hn = ssl_set_hostname(lib, &cli, "127.0.0.1");
  var setup_ok = sf.is_ok && cf.is_ok && hn.is_ok;
  if !sf.is_ok { why(sf.error.message); }
  if !cf.is_ok { why(cf.error.message); }
  if !hn.is_ok { why(hn.error.message); }
  failed = failed + report(setup_ok, "fd-setup: SSL_set_fd both ends + SNI hostname set");
  if !setup_ok {
    ssl_free(lib, &srv);
    ssl_free(lib, &cli);
    socket_close(pair.afd);
    socket_close(pair.cfd);
    socket_close(pair.lfd);
    ssl_ctx_free(lib, &cctx);
    ssl_ctx_free(lib, &sctx);
    return failed;
  }

  // Nonblocking fds: the step pump is the handshake driver.
  let nb1 = socket_set_nonblocking(pair.afd, true);
  let nb2 = socket_set_nonblocking(pair.cfd, true);
  let _ = nb1;
  let _ = nb2;

  let out = pump_fd(lib, &srv, &cli, pair.afd, pair.cfd);
  var hs_ok = out.srv_done && out.cli_done && !out.srv_err && !out.cli_err;
  failed = failed + report(hs_ok,
    "fd-handshake: full TLS handshake over loopback (" + to_string(out.rounds) + " rounds)");
  if !hs_ok {
    why("srv_done=" + bool_str(out.srv_done) + " cli_done=" + bool_str(out.cli_done));
    if out.srv_err { why("server: " + out.srv_msg); }
    if out.cli_err { why("client: " + out.cli_msg); }
  }

  if hs_ok {
    let sv = ssl_get_version(lib, &srv);
    let cv = ssl_get_version(lib, &cli);
    failed = failed + report(streq(sv, cv) && sv.len() > 0,
      "fd-version: " + sv + " on both ends");
    let sic = ssl_get_cipher(lib, &srv);
    let cic = ssl_get_cipher(lib, &cli);
    failed = failed + report(streq(sic, cic) && sic.len() > 0,
      "fd-cipher: " + sic + " on both ends");

    // App data both directions (nonblocking fds; ssl_write/ssl_read wait on
    // WANT internally with a bounded poll).
    let ping = bytes_of("xiom-ssl-ping");
    let w1 = ssl_write(lib, &cli, &ping);
    let r1 = ssl_read(lib, &srv, 64);
    var ping_ok = false;
    if w1.is_ok && r1.is_ok {
      let got: Vec[UInt8] = r1.value;
      ping_ok = w1.value == 13 && got.len() == 13 && streq(Str::from_utf8(got), "xiom-ssl-ping");
    } else {
      if !w1.is_ok { why(w1.error.message); }
      if !r1.is_ok { why(r1.error.message); }
    }
    let pong = bytes_of("xiom-ssl-pong");
    let w2 = ssl_write(lib, &srv, &pong);
    let r2 = ssl_read(lib, &cli, 64);
    var pong_ok = false;
    if w2.is_ok && r2.is_ok {
      let got2: Vec[UInt8] = r2.value;
      pong_ok = w2.value == 13 && got2.len() == 13 && streq(Str::from_utf8(got2), "xiom-ssl-pong");
    } else {
      if !w2.is_ok { why(w2.error.message); }
      if !r2.is_ok { why(r2.error.message); }
    }
    failed = failed + report(ping_ok && pong_ok,
      "fd-data: encrypted app data both directions (ping + pong)");

    // ALPN: client offered h2/http1.1; the server has no selector callback
    // (documented limitation) so ALPN negotiates "none" on both ends.
    let sa = ssl_alpn_selected(lib, &srv);
    let ca = ssl_alpn_selected(lib, &cli);
    var alpn_ok = alpn_set_ok && sa.is_ok && ca.is_ok;
    if alpn_ok {
      if sa.value.len() != 0 || ca.value.len() != 0 { alpn_ok = false; }
    } else {
      if !sa.is_ok { why(sa.error.message); }
      if !ca.is_ok { why(ca.error.message); }
    }
    failed = failed + report(alpn_ok,
      "fd-alpn: client list accepted; negotiated read is empty (no server selector)");

    // Clean shutdown: server close_notify first (0), client completes (1),
    // server completes on its next call (1).
    let f0 = ssl_shutdown(lib, &srv);
    var first_ok = false;
    if f0.is_ok {
      if f0.value == 0 { first_ok = true; }
    } else {
      if f0.error.kind == SSL_ERR_WANT_READ || f0.error.kind == SSL_ERR_WANT_WRITE { first_ok = true; }
    }
    var srv_code = 0;
    var cli_code = 0;
    var sdone = false;
    var cdone = false;
    var shut_fail = false;
    var k = 0;
    while k < 800 && !(sdone && cdone) && !shut_fail {
      if !sdone {
        let sr = ssl_shutdown(lib, &srv);
        if sr.is_ok {
          srv_code = sr.value;
          if srv_code == 1 { sdone = true; }
        } else {
          if sr.error.kind == SSL_ERR_WANT_READ || sr.error.kind == SSL_ERR_WANT_WRITE {
            srv_code = 0;
          } else {
            shut_fail = true;
            why("server shutdown: " + sr.error.message);
          }
        }
      }
      if !cdone && !shut_fail {
        let cr2 = ssl_shutdown(lib, &cli);
        if cr2.is_ok {
          cli_code = cr2.value;
          if cli_code == 1 { cdone = true; }
        } else {
          if cr2.error.kind == SSL_ERR_WANT_READ || cr2.error.kind == SSL_ERR_WANT_WRITE {
            cli_code = 0;
          } else {
            shut_fail = true;
            why("client shutdown: " + cr2.error.message);
          }
        }
      }
      if sdone && cdone { break; }
      var fds: Vec[Int] = Vec[Int].new();
      if !sdone { fds.push(pair.afd); }
      if !cdone { fds.push(pair.cfd); }
      let pr = socket_poll_read(&fds, 10);
      let _ = pr;
      k = k + 1;
    }
    failed = failed + report(first_ok && sdone && cdone && srv_code == 1 && cli_code == 1,
      "fd-shutdown: close_notify both ways (server 0 first, then 1/1 complete)");
  }

  ssl_free(lib, &srv);
  ssl_free(lib, &cli);
  socket_close(pair.afd);
  socket_close(pair.cfd);
  socket_close(pair.lfd);
  ssl_ctx_free(lib, &cctx);
  ssl_ctx_free(lib, &sctx);
  return failed;
}

// =========================================================================
// Verify modes: peer + trusted CA (verify_result 0) and peer + no CA
// (typed handshake failure with non-OK verify_result)
// =========================================================================

fn test_verify_trusted(lib: &SslLibrary) -> Int {
  let sc = load_server_ctx(lib);
  if !sc.is_ok {
    return report(false, "verify-peer: server context failed: " + sc.error.message);
  }
  let sctx: SslContext = sc.value;
  let cc = ssl_ctx_new(lib, false);
  if !cc.is_ok {
    ssl_ctx_free(lib, &sctx);
    return report(false, "verify-peer: client context failed: " + cc.error.message);
  }
  let cctx: SslContext = cc.value;
  ssl_ctx_set_verify(lib, &cctx, SSL_VERIFY_PEER);
  let vl = ssl_ctx_load_verify_locations(lib, &cctx, CERT_PEM_PATH, "");
  if !vl.is_ok {
    ssl_ctx_free(lib, &cctx);
    ssl_ctx_free(lib, &sctx);
    return report(false, "verify-peer: CA load failed: " + vl.error.message);
  }

  let pair = open_pair();
  if !pair.ok {
    ssl_ctx_free(lib, &cctx);
    ssl_ctx_free(lib, &sctx);
    return report(false, "verify-peer: no loopback port available");
  }
  let ns = ssl_new(lib, &sctx);
  let nc = ssl_new(lib, &cctx);
  if !ns.is_ok || !nc.is_ok {
    socket_close(pair.afd);
    socket_close(pair.cfd);
    socket_close(pair.lfd);
    ssl_ctx_free(lib, &cctx);
    ssl_ctx_free(lib, &sctx);
    return report(false, "verify-peer: SSL_new failed");
  }
  var srv: SslStream = ns.value;
  var cli: SslStream = nc.value;
  let sf = ssl_set_fd(lib, &mut srv, pair.afd);
  let cf = ssl_set_fd(lib, &mut cli, pair.cfd);
  let _ = sf;
  let _ = cf;
  let nb1 = socket_set_nonblocking(pair.afd, true);
  let nb2 = socket_set_nonblocking(pair.cfd, true);
  let _ = nb1;
  let _ = nb2;

  let out = pump_fd(lib, &srv, &cli, pair.afd, pair.cfd);
  let vr = ssl_get_verify_result(lib, &cli);
  var ok = out.srv_done && out.cli_done && !out.srv_err && !out.cli_err && vr == X509_V_OK;
  if ok {
    ok = streq(ssl_get_version(lib, &cli), ssl_get_version(lib, &srv));
  }
  if !ok {
    if out.cli_err { why("client: " + out.cli_msg); }
    if out.srv_err { why("server: " + out.srv_msg); }
    why("verify_result=" + to_string(vr) + " (" + ssl_verify_result_name(vr) + ")");
  }
  let res = report(ok,
    "verify-peer: trusted CA accepted; verify_result=0; handshake completes");

  ssl_free(lib, &srv);
  ssl_free(lib, &cli);
  socket_close(pair.afd);
  socket_close(pair.cfd);
  socket_close(pair.lfd);
  ssl_ctx_free(lib, &cctx);
  ssl_ctx_free(lib, &sctx);
  return res;
}

fn test_verify_fail(lib: &SslLibrary) -> Int {
  let sc = load_server_ctx(lib);
  if !sc.is_ok {
    return report(false, "verify-fail: server context failed: " + sc.error.message);
  }
  let sctx: SslContext = sc.value;
  let cc = ssl_ctx_new(lib, false);
  if !cc.is_ok {
    ssl_ctx_free(lib, &sctx);
    return report(false, "verify-fail: client context failed: " + cc.error.message);
  }
  let cctx: SslContext = cc.value;
  // Peer verification ON, but NO trust anchors loaded: the self-signed
  // server cert must be rejected mid-handshake.
  ssl_ctx_set_verify(lib, &cctx, SSL_VERIFY_PEER);

  let pair = open_pair();
  if !pair.ok {
    ssl_ctx_free(lib, &cctx);
    ssl_ctx_free(lib, &sctx);
    return report(false, "verify-fail: no loopback port available");
  }
  let ns = ssl_new(lib, &sctx);
  let nc = ssl_new(lib, &cctx);
  if !ns.is_ok || !nc.is_ok {
    socket_close(pair.afd);
    socket_close(pair.cfd);
    socket_close(pair.lfd);
    ssl_ctx_free(lib, &cctx);
    ssl_ctx_free(lib, &sctx);
    return report(false, "verify-fail: SSL_new failed");
  }
  var srv: SslStream = ns.value;
  var cli: SslStream = nc.value;
  let sf = ssl_set_fd(lib, &mut srv, pair.afd);
  let cf = ssl_set_fd(lib, &mut cli, pair.cfd);
  let _ = sf;
  let _ = cf;
  let nb1 = socket_set_nonblocking(pair.afd, true);
  let nb2 = socket_set_nonblocking(pair.cfd, true);
  let _ = nb1;
  let _ = nb2;

  let out = pump_fd(lib, &srv, &cli, pair.afd, pair.cfd);
  let vr = ssl_get_verify_result(lib, &cli);
  var ok = out.cli_err && out.cli_kind == SSL_ERR_HANDSHAKE && vr != 0;
  if !ok {
    why("cli_err=" + bool_str(out.cli_err) + " kind=" + to_string(out.cli_kind) + " verify_result=" + to_string(vr));
    if out.cli_msg.len() > 0 { why("client: " + out.cli_msg); }
  }
  let res = report(ok,
    "verify-fail: untrusted self-signed cert rejected (typed handshake error, verify_result=" + to_string(vr) + ")");

  ssl_free(lib, &srv);
  ssl_free(lib, &cli);
  socket_close(pair.afd);
  socket_close(pair.cfd);
  socket_close(pair.lfd);
  ssl_ctx_free(lib, &cctx);
  ssl_ctx_free(lib, &sctx);
  return res;
}

// =========================================================================
// Transport-agnostic handshake: memory BIOs only (no socket anywhere)
// =========================================================================

fn bio_move(lib: &SslLibrary, from: &SslStream, to: &mut SslStream) -> Result[Int, Str] {
  var moved = 0;
  var i = 0;
  while i < 64 {
    let pend = ssl_bio_pending(lib, from);
    if !pend.is_ok { return Err(pend.error.message); }
    if pend.value == 0 { return Ok(moved); }
    let chunk = ssl_bio_drain(lib, from, 16384);
    if !chunk.is_ok { return Err(chunk.error.message); }
    let data: Vec[UInt8] = chunk.value;
    if data.len() == 0 { return Ok(moved); }
    let w = ssl_bio_feed(lib, to, &data);
    if !w.is_ok { return Err(w.error.message); }
    moved = moved + data.len();
    i = i + 1;
  }
  return Ok(moved);
}

fn test_memory_bio(lib: &SslLibrary) -> Int {
  var failed = 0;
  let sc = load_server_ctx(lib);
  if !sc.is_ok {
    return report(false, "mem: server context failed: " + sc.error.message);
  }
  let sctx: SslContext = sc.value;
  let cc = ssl_ctx_new(lib, false);
  if !cc.is_ok {
    ssl_ctx_free(lib, &sctx);
    return report(false, "mem: client context failed: " + cc.error.message);
  }
  let cctx: SslContext = cc.value;
  ssl_ctx_set_verify(lib, &cctx, SSL_VERIFY_NONE);

  let ns = ssl_new(lib, &sctx);
  let nc = ssl_new(lib, &cctx);
  if !ns.is_ok || !nc.is_ok {
    ssl_ctx_free(lib, &cctx);
    ssl_ctx_free(lib, &sctx);
    return report(false, "mem: SSL_new failed");
  }
  var srv: SslStream = ns.value;
  var cli: SslStream = nc.value;
  let b1 = ssl_set_bio_mem(lib, &mut srv);
  let b2 = ssl_set_bio_mem(lib, &mut cli);
  if !b1.is_ok || !b2.is_ok {
    if !b1.is_ok { why(b1.error.message); }
    if !b2.is_ok { why(b2.error.message); }
    ssl_free(lib, &srv);
    ssl_free(lib, &cli);
    ssl_ctx_free(lib, &cctx);
    ssl_ctx_free(lib, &sctx);
    return report(false, "mem: memory-BIO setup failed");
  }

  var sdone = false;
  var cdone = false;
  var serr = false;
  var cerr = false;
  var err_msg = "";
  var rounds = 0;
  while rounds < 2000 && !serr && !cerr && !(sdone && cdone) {
    if !sdone {
      let rs = ssl_step(lib, &srv, true);
      if rs.is_ok {
        let st: SslStep = rs.value;
        if st.done { sdone = true; }
      } else {
        serr = true;
        err_msg = rs.error.message;
      }
    }
    if !serr && !cerr && !cdone {
      let rc = ssl_step(lib, &cli, false);
      if rc.is_ok {
        let st2: SslStep = rc.value;
        if st2.done { cdone = true; }
      } else {
        cerr = true;
        err_msg = rc.error.message;
      }
    }
    let m1 = bio_move(lib, &srv, &mut cli);
    let m2 = bio_move(lib, &cli, &mut srv);
    let _ = m1;
    let _ = m2;
    rounds = rounds + 1;
  }

  var hs_ok = sdone && cdone && !serr && !cerr;
  failed = failed + report(hs_ok,
    "mem-handshake: TLS handshake over memory BIOs only (" + to_string(rounds) + " pump rounds)");
  if !hs_ok {
    if err_msg.len() > 0 { why(err_msg); }
    why("srv_done=" + bool_str(sdone) + " cli_done=" + bool_str(cdone));
  }

  if hs_ok {
    let sv = ssl_get_version(lib, &srv);
    let cv = ssl_get_version(lib, &cli);
    failed = failed + report(streq(sv, cv) && sv.len() > 0,
      "mem-version: " + sv + " on both ends (no socket involved)");

    let ping = bytes_of("mem-ping");
    let w = ssl_write(lib, &cli, &ping);
    let mm = bio_move(lib, &cli, &mut srv);
    let rd = ssl_read(lib, &srv, 64);
    var io_ok = false;
    if w.is_ok && mm.is_ok && rd.is_ok {
      let got: Vec[UInt8] = rd.value;
      io_ok = got.len() == 8 && streq(Str::from_utf8(got), "mem-ping");
    } else {
      if !w.is_ok { why(w.error.message); }
      if !mm.is_ok { why(mm.error); }
      if !rd.is_ok { why(rd.error.message); }
    }
    failed = failed + report(io_ok,
      "mem-data: client app data decrypts on the server via the BIO pump");
  }

  ssl_free(lib, &srv);
  ssl_free(lib, &cli);
  ssl_ctx_free(lib, &cctx);
  ssl_ctx_free(lib, &sctx);
  return failed;
}

// =========================================================================
// Small local string helper (no convert dependency inside messages)
// =========================================================================

fn bool_str(b: Bool) -> Str {
  if b { return "true"; }
  return "false";
}

// =========================================================================
// Driver
// =========================================================================

pub fn main() -> Int {
  io.println("=== xiom.ssl conformance tests (libssl dynamic loader + memory BIOs) ===");
  io.flush_stdout();
  var failed: Int = 0;

  // SKIP-path classification, deterministic on every host (bogus soname).
  let missing = ssl_load_named("xiom-absent-libssl-probe-xyz.dll");
  if missing.is_ok {
    failed = failed + report(false, "skip-path: bogus soname unexpectedly loaded");
  } else {
    failed = failed + report(missing.error.kind == SSL_LOAD_ABSENT,
      "skip-path: absent library classified as SSL_LOAD_ABSENT (SKIP)");
  }

  // Pure helpers (run on every host, no library needed).
  var names: Vec[Str] = Vec[Str].new();
  names.push("h2");
  names.push("http/1.1");
  let wire = ssl_alpn_wire(&names);
  var wire_ok = false;
  if wire.is_ok {
    let w: Vec[UInt8] = wire.value;
    if w.len() == 12 {
      if (w[0] as Int) == 2 {
        if (w[3] as Int) == 8 {
          wire_ok = true;
        }
      }
    }
  }
  failed = failed + report(wire_ok,
    "alpn-wire: [h2,http/1.1] -> 12 bytes with 8-bit length prefixes");

  var catalog_ok = streq(ssl_verify_result_name(X509_V_OK), "ok");
  if !streq(ssl_verify_result_name(X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY),
            "unable to get local issuer certificate") { catalog_ok = false; }
  if !streq(ssl_verify_result_name(12345), "unknown") { catalog_ok = false; }
  failed = failed + report(catalog_ok, "verify-catalog: X509_V names resolve");

  // Live leg.
  let lr = ssl_load();
  if !lr.is_ok {
    if lr.error.kind == SSL_LOAD_ABSENT {
      failed = failed + report(true, "live: SKIP -- no libssl candidate present (" + lr.error.message + ")");
    } else {
      failed = failed + report(false, "live: libssl load failed -- " + lr.error.message);
    }
    return finish(failed);
  }
  let lib: SslLibrary = lr.value;

  let info = ssl_probe(&lib);
  if info.is_ok {
    let i: SslInfo = info.value;
    failed = failed + report(i.version.len() > 0 && i.version_num != 0,
      "probe: " + i.version + " (num " + to_string(i.version_num) + "; " + lib.soname + " + " + lib.crypto_soname + ")");
  } else {
    failed = failed + report(false, "probe: " + info.error.message);
  }

  failed = failed + test_cert_loads(&lib);
  failed = failed + test_fd_tls(&lib);
  failed = failed + test_verify_trusted(&lib);
  failed = failed + test_verify_fail(&lib);
  failed = failed + test_memory_bio(&lib);

  let cl = ssl_close(&lib);
  failed = failed + report(cl.is_ok, "close: library handles released");
  return finish(failed);
}
