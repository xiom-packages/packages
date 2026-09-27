# xiom.tor

> **Status:** 0.1.0 -- implemented, conformance suite green (20/20).
> **Scope:** Tor link-layer cell **structure** codec. Pure XIOM, no FFI.

`xiom.tor` decodes the framing of Tor channel cells as defined by the public
Tor specifications (spec.torproject.org): fixed-length and variable-length
cells, the VERSIONS and NETINFO handshake bodies, and the RELAY envelope with
typed payloads for the simple relay commands. It is a decoder (parser) only:
there is no encoder, no session state, and no cryptography.

## What is implemented

| Area | API |
|------|-----|
| Sizes | `tor_cell_body_len`, `tor_cell_narrow_len`, `tor_cell_wide_len`, `tor_relay_header_len`, `tor_relay_max_data_fixed`, `tor_sendme_digest_len`, `tor_max_variable_len` |
| Commands | `TOR_LINK_CMD_*` (PADDING..PADDING_NEGOTIATE), `TOR_RELAY_CMD_*` (BEGIN..EXTENDED2), `tor_link_cmd_name`, `tor_relay_cmd_name`, `tor_cell_is_variable_cmd` |
| Cells | `tor_parse_cell` (auto CircID width), `tor_parse_cell_v` (known link version) |
| Handshake | `tor_parse_versions`, `tor_versions_choose`, `tor_link_version_valid`, `tor_decode_netinfo`, `TOR_MIN_LINK_VERSION` |
| RELAY | `tor_parse_relay` (11-byte envelope, unverified digest) |
| RELAY payloads | `tor_relay_decode_begin`, `_connected`, `_end`, `_sendme`, `_resolve`, `_resolved` |
| Tables | `TOR_END_REASON_*`, `tor_end_reason_name`, `TOR_RESOLVED_TYPE_*`, `tor_resolved_type_name` |
| Text | `tor_ascii_to_str` (printable ASCII only, rejects NUL/control/>= 128) |

Cell framing:

```
narrow fixed : CircID(2) + Command(1) + Body(509)              = 512 bytes
wide fixed   : CircID(4) + Command(1) + Body(509)              = 514 bytes
variable     : CircID + Command(1) + Length(2) + Body(Length)
```

Width detection in `tor_parse_cell` follows the classic rule: if either of
the first two bytes is nonzero the cell is read as wide (4-byte CircID),
otherwise as narrow (2-byte CircID). Commands 7 (VERSIONS) and >= 128 are
variable-length; every other command is fixed-length.

## Known limitations (honest scope)

- **No cryptography.** The RELAY digest field, the `recognized` field, the
  SENDME digest and all cell bodies are opaque bytes. Nothing is verified,
  decrypted, encrypted or computed. In particular a RELAY digest of all
  zeroes is accepted, because verification needs circuit keys.
- **No circuits, streams, flow control, padding policy or I/O.** The module
  reads bytes; it never opens a socket or keeps state.
- **CERTS / AUTH_CHALLENGE / AUTHENTICATE are not decoded** (certificate
  crypto is out of scope); their command ids are recognized.
- **Width auto-detection is ambiguous for zero high halves.** A wide cell
  whose CircID high 16 bits are zero (e.g. NETINFO or zero-CircID DESTROY
  on a v4 link) cannot be told apart from a narrow cell by the byte rule.
  Use `tor_parse_cell_v(data, off, link_version)` when the negotiated link
  version is known -- that is the robust path.
- **Decode-only.** There is no cell encoder; the conformance suite builds
  synthetic cells itself.

## Usage

```xiom
use xiom.tor;

let buf = /* bytes read from the TLS stream */;
let r = tor_parse_cell(&buf, 0);
if r.is_ok {
  let cell: TorCell = r.value;
  // cell.command, cell.circ_id, cell.payload, cell.consumed
}

// RELAY: unwrap the envelope, then the typed payload.
let p: Vec[UInt8] = cell.payload;
let rr = tor_parse_relay(&p, 0);
if rr.is_ok {
  let relay: TorRelay = rr.value;
  if relay.cmd == TOR_RELAY_CMD_BEGIN {
    let d: Vec[UInt8] = relay.data;
    let br = tor_relay_decode_begin(&d);
    if br.is_ok {
      let b: TorBegin = br.value;
      // b.addr (Vec[UInt8]), b.port, b.flags, b.has_flags
    }
  }
}

// VERSIONS handshake (first cell on a fresh connection).
let vr = tor_parse_cell_v(&buf, 0, 0);   // v = 0 before negotiation
if vr.is_ok {
  let vcell: TorCell = vr.value;
  let vp: Vec[UInt8] = vcell.payload;
  let pr = tor_parse_versions(&vp, 0);
  // choose the highest common version >= 3 with tor_versions_choose
}
```

All parse errors are `Err(Str)` of the form `"tor: <what> at <offset>"`,
where the offset is relative to the buffer passed in.

## Testing

From the repository root:

```powershell
& .\scripts\port.ps1 -Package xiom.tor
```

The suite is `tests/test_conformance.xi` (20 checks): command tables,
narrow/wide fixed framing, variable framing, VERSIONS, concatenated-cell
walks, truncation and bad-length errors, the RELAY envelope, and every
typed payload decoder with malformed cases.

## Layout

```
package.xi               dotted manifest (xiom.tor)
src/tor.xi               the codec
tests/test_conformance.xi  20 synthetic-cell checks
SPEC.md                  byte-level layouts actually implemented
```
