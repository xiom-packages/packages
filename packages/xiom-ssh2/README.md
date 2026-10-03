# xiom.ssh2

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.3` on the XIOM registry.
> **Scope:** SSH-2 transport, authentication and connection-layer message
> **structure** codec (RFC 4251 / 4253 / 4252 / 4254). Pure XIOM, no FFI.
> **Deps:** stdlib only (`xiom.convert.int`, `xiom.string`,
> `xiom.string.compare`; tests use `xiom.test`, `xiom.io`,
> `xiom.encoding.hex`).

## What this is (honest scope)

This package is a **wire-format codec**, not an SSH client or server. It
encodes and parses the *structure* of SSH-2 messages:

- the binary packet frame (`packet_length`, `padding_length`, payload,
  padding) with the structural length checks of RFC 4253 section 6;
- the RFC 4251 field primitives: `byte`, `boolean`, `uint32`, `string`,
  `mpint`, `name-list`;
- the message bodies of the transport (DISCONNECT, IGNORE, UNIMPLEMENTED,
  DEBUG, KEXINIT, KEXDH/ECDH init+reply, NEWKEYS), authentication (SERVICE_*,
  USERAUTH_REQUEST password/publickey, USERAUTH_FAILURE/SUCCESS/BANNER) and
  connection layers (GLOBAL_REQUEST and responses, CHANNEL_OPEN matrix,
  OPEN_CONFIRMATION/FAILURE, WINDOW_ADJUST, CHANNEL_REQUEST matrix,
  SUCCESS/FAILURE, DATA/EXTENDED_DATA/EOF/CLOSE);
- one-message-at-a-time parsing with consumed byte counts
  (`ssh2_parse_message`) and byte-offset error messages
  (`"ssh2: <reason> at <offset>"`); unknown message numbers are preserved
  raw (`known = false`).

It deliberately does **not** do:

- **any cryptography**: no key exchange math, no Diffie-Hellman, no
  signatures, no MAC computation or verification, no cipher;
- **MAC parsing**: `ssh2_parse_packet` stops at the frame
  (`mac_off = end`); the caller, who knows the negotiated MAC algorithm,
  must consume the MAC bytes;
- **bignum math**: `mpint` values are carried as raw two's-complement bytes.
  The only sign inspection offered is `ssh2_mpint_is_negative`;
- **random padding**: `ssh2_write_packet*` writes zero bytes as padding and
  `ssh2_write_packet_aligned` picks a legal pad *count*. A real transport
  must replace padding with random bytes;
- **session state**: no sequence numbers, windows, channels, or buffering.
  Everything is stateless functions over byte buffers.

## Layout

```
packages/xiom-ssh2/
  package.xi            manifest (xiom.ssh2, 0.1.0)
  src/ssh2.xi           the whole codec (module xiom.ssh2)
  tests/test_conformance.xi   24 synthetic-packet tests
  README.md             this file
  SPEC.md               byte-level layouts actually implemented
  .gitignore            byte-for-byte copy of xiom-hello
```

## Quick start

Parse a packet frame and then the message inside it:

```xiom
use xiom.ssh2;

// buf holds one received frame (or several messages back to back)
let pr = ssh2_parse_packet(&buf, 0);
if pr.is_ok {
  let p: Ssh2Packet = pr.value;
  // p.total = 4 + packet_length; p.mac_off = end (MAC not parsed)

  // decode the message (validates known bodies structurally)
  let mr = ssh2_parse_message(&buf, 0);
  if mr.is_ok {
    let m: Ssh2Message = mr.value;
    // m.msg_type, m.known, m.raw (payload copy), m.total
  }
}
```

Decode the bodies you understand:

```xiom
let kr = ssh2_parse_kexinit(&buf, 0);
if kr.is_ok {
  let k: Ssh2KexInit = kr.value;
  // k.kex_algorithms is a raw comma-joined name-list
  if ssh2_name_list_contains(&k.kex_algorithms, &bytes_of("curve25519-sha256")) { ... }
}

let cr = ssh2_parse_channel_request(&buf, 0);
if cr.is_ok {
  let c: Ssh2ChannelRequest = cr.value;
  // c.decoded tells whether the request-specific fields were understood
  // (pty-req/env/exec/shell/subsystem/window-change); otherwise c.extra
  // holds the raw tail.
}
```

Build messages (zero padding, 8-byte aligned):

```xiom
let pkt = ssh2_encode_kexinit(&cookie, &kex, &host_keys, &enc_c2s, &enc_s2c,
                              &mac_c2s, &mac_s2c, &comp_c2s, &comp_s2c,
                              &lang_c2s, &lang_s2c, false, 0);
let chan = ssh2_encode_channel_open_session(0, 2 * 1024 * 1024, 32768);
let data = ssh2_encode_channel_data(0, &payload_bytes);
```

Primitives round-trip for callers that need raw fields:

```xiom
let s = ssh2_read_string_slice(&buf, off);       // consumed = s.total
let v = ssh2_read_mpint(&buf, off);              // raw bytes
var out = Vec[UInt8].new();
ssh2_write_uint32(&mut out, 35000);
ssh2_write_name_list(&mut out, &list);
```

## Error convention

Every structural failure is `Err(Str)` shaped
`"ssh2: <reason> at <offset>"`, where `<offset>` is an absolute byte offset in
the buffer you passed in. `"ssh2: negative offset"` is the one error without
an offset. Typical reasons: `truncated packet header`, `packet length
underflow`, `padding too short`, `packet too long`, `truncated packet
payload`, `truncated string length`, `truncated string`, `bad name-list`,
`trailing bytes`, `not a <message> message`, `empty payload`,
`negative DH value`.

## Testing

```
# from the repo root
& .\scripts\port.ps1 -Package xiom.ssh2
```

Expected tail:

```
port: PASS (passed=24 failed=0 program_exit=0 exit=0)
```

## License

MIT OR Apache-2.0. Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
