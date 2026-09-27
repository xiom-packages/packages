# xiom.ssh2 -- wire format specification

This document describes the byte-level layouts that `src/ssh2.xi` actually
implements. It is a structure codec only: no crypto, no MAC verification, no
bignum math, no session state (see README.md for the scope boundary).

Notation: `u8` = one octet, `u32` = unsigned big-endian four octets, `str` =
`u32 length` + that many bytes, `mpint` = `str` carrying raw two's-complement
big-endian bytes, `nl` = `str` carrying a comma-joined US-ASCII name-list.

## 1. Field primitives (RFC 4251 section 5)

| Type | Encoding | Implementation notes |
|------|----------|----------------------|
| `byte` | 1 octet | widened with `(x as Int) & 0xFF` on read; low 8 bits on write |
| `boolean` | 1 octet | `0` = false, any non-zero = true; written as `1`/`0` |
| `uint32` | 4 octets BE | composed as `b0*16777216 + b1*65536 + b2*256 + b3`; never shifts |
| `string` | `u32 len` + bytes | binary safe: NUL, CR, LF, bytes >= 128 preserved |
| `mpint` | `u32 len` + bytes | raw only; `ssh2_mpint_is_negative` = first byte >= 0x80; length 0 = value 0 |
| `name-list` | `u32 len` + bytes | empty list legal; each present name non-empty, printable ASCII 0x21..0x7E; no leading/trailing/double comma |

Readers: `ssh2_read_byte/boolean/uint32` return the value;
`ssh2_read_string/mpint/name_list` return a copy;
`ssh2_read_string_slice/mpint_slice/name_list_slice` return
`{start, len, total}` where `start = field_off + 4` and `total = 4 + len`
(bytes consumed). `ssh2_slice_bytes` copies a slice out.

Writers: `ssh2_write_byte/boolean/uint32/string/mpint/name_list` append to a
buffer. `uint32` writes the low 32 bits (caller keeps values in
0..4294967295).

## 2. Binary packet frame (RFC 4253 section 6)

```
offset      size            field
off+0       4               u32 packet_length
off+4       1               u8  padding_length
off+5       payload_len     payload          (message type included)
off+5+n     padding_length  padding          (not interpreted)
off+5+n+pl  mac_len         MAC              (NOT parsed; mac_off = end)
```

- `payload_len = packet_length - padding_length - 1`
- `total = 4 + packet_length` (bytes consumed by the frame; MAC excluded)
- `end = off + total`, `mac_off = end`

Validation order in `ssh2_parse_packet`:

| Check | Error |
|-------|-------|
| `off < 0` | `ssh2: negative offset` |
| fewer than 4 bytes for the length block | `ssh2: truncated packet header at <off>` |
| `packet_length < 1` | `ssh2: packet length underflow at <off>` |
| `packet_length > 35000` | `ssh2: packet too long at <off>` |
| `padding_length < 4` | `ssh2: padding too short at <off>` |
| `packet_length < padding_length + 1` | `ssh2: packet length underflow at <off>` |
| `off + 4 + packet_length > buffer` | `ssh2: truncated packet payload at <off>` |

Constants: `SSH2_PACKET_HEADER_LEN = 5`, `SSH2_MIN_PADDING = 4`,
`SSH2_MAX_PADDING = 255`, `SSH2_MAX_PACKET_LENGTH = 35000`,
`SSH2_DEFAULT_BLOCK_SIZE = 8`, `SSH2_MAX_BLOCK_SIZE = 16`.

Alignment: RFC 4253 requires the length block (`4 + packet_length`) to be a
multiple of 8, or of the cipher block size (16 for AES) once encryption is
active. The parser does **not** enforce alignment (the block size is a
session property); use `ssh2_packet_is_aligned(p, block)`. The writer helpers
choose a legal count: `ssh2_packet_padding_for(payload_len, block)` returns
the smallest pad >= 4 that aligns, clamping `block` up to 8;
`ssh2_write_packet(payload, padding_len)` writes an exact frame with zero
padding and no validation; `ssh2_write_packet_aligned(payload, block)` uses
the computed count.

## 3. Message envelope (`ssh2_parse_message`)

Payload begins with the message type byte. `Ssh2Message` carries:
`msg_type`, `known`, `start`, `payload_off = start + 5`, `payload_len`,
`body_off = payload_off + 1`, `body_len = payload_len - 1`,
`total = 4 + packet_length`, `packet_length`, `padding_length`,
`mac_off = start + total`, and `raw` = a verbatim copy of the payload
(message type included).

- `known` is true for the catalog below; unknown numbers are preserved raw
  and are not an error.
- Known numbers are additionally validated by running the matching typed
  parser; a structural body error surfaces with its byte offset.
- `payload_len < 1` is `ssh2: empty payload at <off>`.

## 4. Message catalog

All typed parsers require their own message number, otherwise
`ssh2: not a <name> message at <off>`. "strict" means trailing bytes after
the last field are `ssh2: trailing bytes at <cursor>`; "raw tail" means the
remaining bytes are copied into `extra`/`data` and may be empty.

| # | Message | Body layout implemented | Tail |
|---|---------|-------------------------|------|
| 1 | SSH_MSG_DISCONNECT | `u32 reason; str description; str language` | strict |
| 2 | SSH_MSG_IGNORE | `str data` | strict |
| 3 | SSH_MSG_UNIMPLEMENTED | `u32 sequence` | strict |
| 4 | SSH_MSG_DEBUG | `boolean always_display; str message; str language` | strict |
| 5 | SSH_MSG_SERVICE_REQUEST | `str service` | strict |
| 6 | SSH_MSG_SERVICE_ACCEPT | `str service` | strict |
| 20 | SSH_MSG_KEXINIT | `16-byte cookie; nl kex; nl host_key; nl enc_c2s; nl enc_s2c; nl mac_c2s; nl mac_s2c; nl comp_c2s; nl comp_s2c; nl lang_c2s; nl lang_s2c; boolean first_kex_packet_follows; u32 reserved` | strict |
| 21 | SSH_MSG_NEWKEYS | (empty) | strict |
| 30 | SSH_MSG_KEXDH_INIT | `mpint e` | strict |
| 31 | SSH_MSG_KEXDH_REPLY | `str K_S; mpint f; str signature` | strict |
| 30 | SSH_MSG_KEX_ECDH_INIT | `str Q_C` | strict |
| 31 | SSH_MSG_KEX_ECDH_REPLY | `str K_S; str Q_S; str signature` | strict |
| 50 | SSH_MSG_USERAUTH_REQUEST | `str user; str service; str method; <method-specific>` | see 5.1 |
| 51 | SSH_MSG_USERAUTH_FAILURE | `nl methods; boolean partial` (list may be empty) | strict |
| 52 | SSH_MSG_USERAUTH_SUCCESS | (empty) | strict |
| 53 | SSH_MSG_USERAUTH_BANNER | `str message; str language` | strict |
| 80 | SSH_MSG_GLOBAL_REQUEST | `str name; boolean want_reply; <raw request data>` | raw tail |
| 81 | SSH_MSG_REQUEST_SUCCESS | `<raw response data>` | raw tail |
| 82 | SSH_MSG_REQUEST_FAILURE | (empty) | strict |
| 90 | SSH_MSG_CHANNEL_OPEN | `str type; u32 sender; u32 window; u32 max_packet; <type-specific>` | see 5.2 |
| 91 | SSH_MSG_CHANNEL_OPEN_CONFIRMATION | `u32 recipient; u32 sender; u32 window; u32 max_packet; <raw type-specific>` | raw tail |
| 92 | SSH_MSG_CHANNEL_OPEN_FAILURE | `u32 recipient; u32 reason; str description; str language` | strict |
| 93 | SSH_MSG_CHANNEL_WINDOW_ADJUST | `u32 recipient; u32 bytes` | strict |
| 94 | SSH_MSG_CHANNEL_DATA | `u32 recipient; str data` | strict |
| 95 | SSH_MSG_CHANNEL_EXTENDED_DATA | `u32 recipient; u32 data_type; str data` | strict |
| 96 | SSH_MSG_CHANNEL_EOF | `u32 recipient` | strict |
| 97 | SSH_MSG_CHANNEL_CLOSE | `u32 recipient` | strict |
| 98 | SSH_MSG_CHANNEL_REQUEST | `u32 recipient; str request; boolean want_reply; <request-specific>` | see 5.3 |
| 99 | SSH_MSG_CHANNEL_SUCCESS | `u32 recipient` | strict |
| 100 | SSH_MSG_CHANNEL_FAILURE | `u32 recipient` | strict |

KEXINIT extra rule: the eight algorithm name-lists (kex, host key, enc
c2s/s2c, MAC c2s/s2c, compression c2s/s2c) must be non-empty, otherwise
`ssh2: empty algorithm name-list at <field_off>`; the two language lists may
be empty. A cookie shorter than 16 bytes is
`ssh2: truncated cookie at <body_off>`.

Message numbers 30/31 are shared between classic DH and ECDH; the envelope's
generic validation accepts either shape (one blob for 30, three blobs for
31). The dedicated parsers apply their own semantics:
`ssh2_parse_kexdh_init/kexdh_reply` enforce the classic check that the DH
value is a positive mpint (a negative value is
`ssh2: negative DH value at <field_off>`), while
`ssh2_parse_kex_ecdh_init/ecdh_reply` treat Q_C/Q_S as opaque strings.

### 4.1 Disconnect reason codes (parsed as u32, no validation)

`1 HOST_NOT_ALLOWED_TO_CONNECT`, `2 PROTOCOL_ERROR`,
`3 KEY_EXCHANGE_FAILED`, `4 RESERVED`, `5 MAC_ERROR`,
`6 COMPRESSION_ERROR`, `7 SERVICE_NOT_AVAILABLE`,
`8 PROTOCOL_VERSION_NOT_SUPPORTED`, `9 HOST_KEY_NOT_VERIFIABLE`,
`10 CONNECTION_LOST`, `11 BY_APPLICATION`, `12 TOO_MANY_CONNECTIONS`,
`13 AUTH_CANCELLED_BY_USER`, `14 NO_MORE_AUTH_METHODS_AVAILABLE`,
`15 ILLEGAL_USER_NAME`. Names/messages via
`ssh2_disconnect_reason_name/message` ("" for unknown codes).

## 5. Type-specific layouts

### 5.1 USERAUTH_REQUEST method bodies

| method | layout | decoded fields |
|--------|--------|----------------|
| `password` (flag false) | `boolean 0; str password` | `secret` = password |
| `password` (flag true) | `boolean 1; str old; str new` | `old_password` = old, `secret` = new |
| `publickey` | `boolean has_sig; str algorithm; str key_blob [; str signature]` | `algorithm`, `secret` = key_blob, `signature` (empty when absent), `has_signature` |
| anything else | opaque | `decoded = false`, `extra` = raw tail |

### 5.2 CHANNEL_OPEN type-specific bodies

| type | layout | decoded fields |
|------|--------|----------------|
| `session` | (nothing) | strict |
| `direct-tcpip` | `str host_to_connect; u32 port; str originator_ip; u32 originator_port` | `host`, `port`, `origin`, `origin_port` |
| `forwarded-tcpip` | `str connected_address; u32 connected_port; str originator_address; u32 originator_port` | `host`, `port`, `origin`, `origin_port` |
| anything else | opaque | `decoded = false`, `extra` = raw tail |

### 5.3 CHANNEL_REQUEST request-specific bodies

| request | layout | decoded fields |
|---------|--------|----------------|
| `pty-req` | `str TERM; u32 cols; u32 rows; u32 width_px; u32 height_px; str modes` | `text0` = TERM, `u32_0..3`, `text1` = raw terminal modes |
| `env` | `str name; str value` | `text0`, `text1` |
| `exec` | `str command` | `text0` |
| `shell` | (nothing) | strict |
| `subsystem` | `str subsystem` | `text0` |
| `window-change` | `u32 cols; u32 rows; u32 width_px; u32 height_px` | `u32_0..3` |
| anything else | opaque | `decoded = false`, `extra` = raw tail |

## 6. Error catalog

All errors are `Err(Str)` shaped `"ssh2: <reason> at <offset>"` except
`ssh2: negative offset`. Offsets are absolute in the buffer passed to the
function.

Packet: `truncated packet header`, `packet length underflow`,
`padding too short`, `packet too long`, `truncated packet payload`.

Fields: `truncated byte`, `truncated boolean`, `truncated uint32`,
`truncated string length`, `truncated string`, `truncated mpint length`,
`truncated mpint`, `truncated name-list length`, `truncated name-list`,
`bad name-list`. The `<what>` in the length/content errors is `string`,
`mpint` or `name-list`.

Messages: `empty payload`, `not a <name> message`, `truncated cookie`,
`empty algorithm name-list`, `negative DH value`, `trailing bytes`,
`unknown message type` (internal dispatch safety net; unreachable for known
numbers).

## 7. Encoders (all return 8-byte aligned packets, zero padding)

`ssh2_encode_disconnect`, `ssh2_encode_ignore`,
`ssh2_encode_unimplemented`, `ssh2_encode_debug`, `ssh2_encode_kexinit`,
`ssh2_encode_kexdh_init`, `ssh2_encode_kexdh_reply`,
`ssh2_encode_kex_ecdh_init`, `ssh2_encode_kex_ecdh_reply`,
`ssh2_encode_newkeys`, `ssh2_encode_service_request`,
`ssh2_encode_service_accept`, `ssh2_encode_userauth_password`,
`ssh2_encode_userauth_password_change`, `ssh2_encode_userauth_publickey`,
`ssh2_encode_userauth_failure`, `ssh2_encode_userauth_success`,
`ssh2_encode_banner`, `ssh2_encode_global_request`,
`ssh2_encode_request_success`, `ssh2_encode_request_failure`,
`ssh2_encode_channel_open_session`,
`ssh2_encode_channel_open_direct_tcpip`,
`ssh2_encode_channel_open_forwarded_tcpip`,
`ssh2_encode_channel_open_confirmation`,
`ssh2_encode_channel_open_failure`, `ssh2_encode_window_adjust`,
`ssh2_encode_channel_pty_req`, `ssh2_encode_channel_env`,
`ssh2_encode_channel_exec`, `ssh2_encode_channel_shell`,
`ssh2_encode_channel_subsystem`, `ssh2_encode_channel_window_change`,
`ssh2_encode_channel_success`, `ssh2_encode_channel_failure`,
`ssh2_encode_channel_eof`, `ssh2_encode_channel_close`,
`ssh2_encode_channel_data`, `ssh2_encode_channel_extended_data`.

## 8. Explicitly out of scope

- Crypto: KEX math, host key verification, signatures, MAC, ciphers.
- MAC parsing/verification (`mac_off = end`; caller consumes).
- Random padding generation (writers emit 0x00; caller replaces).
- zlib compression, rekeying policy, sequence numbers, window accounting.
- SSH_MSG_KEX_DH_GEX_* (RFC 4419), SSH_MSG_USERAUTH_* remaining methods
  (keyboard-interactive, hostbased), agent/X11 channel payload decode
  (unknown channel types are preserved raw via `extra`).
