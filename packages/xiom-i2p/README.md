# xiom.i2p

> **Status:** `incubating` -- conformance-tested (24/24); published at `v0.1.0` on the XIOM registry.

Pure-XIOM **message and state model** of the I2P SAM v3 client protocol.
It builds and parses the text lines a SAM client exchanges with the SAM
bridge, validates I2P destination and `.i2p` address strings, and models
sessions, streams, the address book (naming store) and the lease-set shape.

**Transport is out of scope.** This package never opens a socket, never
performs I/O, never does cryptography and never touches a clock. The caller
moves built lines over its own transport and feeds replies back in.

```
HELLO VERSION MIN=3.0 MAX=3.3
        |
        v   sam_parse_line / sam_build_line
   I2pMessage{ verb, sub, keys[], values[] }
        |
        v   sam_reply_code / sam_msg_field
   reply code + fields
        |
        v   session_status / stream_status
   I2pSession / I2pStream state machines
```

## What is modelled

| Area | API |
| --- | --- |
| Canonical destination (516-char base64 / 387 bytes) | `dest_parse_b64`, `dest_to_b64`, `dest_cert_type`, `dest_cert_len`, `dest_is_null_cert`, `dest_sig_type`, `dest_sig_type_name`, `dest_enc_key`, `dest_sign_key` |
| Hand-rolled codecs | `b64_encode`, `b64_decode`, `b32_encode`, `b32_decode` |
| `.i2p` addresses | `addr_kind`, `addr_is_b64`, `addr_is_b32_host`, `addr_is_i2p_host`, `addr_b32_host`, `addr_b32_hash` |
| SAM v3 line framing | `sam_parse_line`, `sam_build_line`, `sam_msg_count`, `sam_msg_field`, `sam_msg_has`, `sam_is_reply` |
| Reply codes | `sam_result_name`, `sam_result_code`, `sam_result_is_ok`, `sam_reply_code`, `sam_reply_message` |
| Versions | `sam_version_pack`, `sam_version_parse` |
| Command builders | `sam_hello_line`, `sam_dest_generate_line`, `sam_session_create_line`, `sam_session_add_line`, `sam_session_remove_line`, `sam_stream_connect_line`, `sam_stream_accept_line`, `sam_stream_forward_line`, `sam_naming_lookup_line` |
| Sessions | `session_create`, `session_status`, `session_add_dest`, `session_remove_dest`, `session_close`, accessors, style/state name tables |
| Streams | `stream_connect`, `stream_accept`, `stream_forward`, `stream_status`, `stream_inbound`, `stream_close`, `stream_set_silent`, `stream_can_send`, `stream_state_name` |
| Address book | `book_new`, `book_set`, `book_get`, `book_remove`, `book_contains`, `book_count`, accessors |
| Lease set | `leaseset_new`, `leaseset_add`, `leaseset_all_expired`, accessors |

## Example

```xiom
use xiom.i2p;
use xiom.string.compare;

// Hello / version negotiation.
let hello = sam_hello_line(sam_version_pack(3, 0), sam_version_pack(3, 3));
let ready = !hello.is_ok;

// Parse a reply line from your own transport.
let reply = sam_parse_line("SESSION STATUS RESULT=OK DESTINATION=AAAA...\n");
if reply.is_ok {
  let m: I2pMessage = reply.value;
  let code = sam_reply_code(&m);          // Ok(0) for OK
  let dest = sam_msg_field(&m, "DESTINATION");
}

// Create and activate a STREAM session (destination string from DEST GENERATE).
let s0 = session_create("my-session", I2P_STYLE_STREAM, dest_str, &opt_keys, &opt_values);
if s0.is_ok {
  let sess: I2pSession = s0.value;          // bind before passing by reference
  let line = sam_session_create_line(&sess);
  let active = session_status(&sess, I2P_RESULT_OK);

  // Connect, then move CONNECTING -> OPEN on "STREAM STATUS RESULT=OK".
  let st = stream_connect(&active, "s1", peer_dest);
  if st.is_ok {
    let astr: I2pStream = st.value;
    let opened = stream_status(&astr, I2P_RESULT_OK);
    let may_send = stream_can_send(&opened);
  }
}
```

## Build and test

From the repository root:

```powershell
.\scripts\port.ps1 -Package xiom-i2p -TimeoutSec 60
```

The suite is `tests/test_conformance.xi` (24 deterministic checks: RFC 4648
base64/base32 vectors and error cases, destination layout, naming rules,
framing KATs, reply tables, session/stream transitions, address book and
lease set). Expected final line:

```
port: PASS (passed=24 failed=0 program_exit=0 exit=0)
```

## Files

```
package.xi               manifest (name "xiom.i2p", 0.1.0, category network)
src/i2p.xi               module xiom.i2p (single module; no sibling imports)
tests/test_conformance.xi module i2p_tests (24 checks)
SPEC.md                  SAM v3 subset, wire rules, non-goals
```

## Dependencies

Only `xiom.std` (platform dependency): `xiom.string`,
`xiom.string.builder` and `xiom.string.compare` in the library; the tests
add `xiom.test` and `xiom.io`. Base64 and base32 are hand-rolled and
KAT-pinned because the stdlib encoding modules are not part of the verified
package link closure.

## License

MIT OR Apache-2.0. Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
