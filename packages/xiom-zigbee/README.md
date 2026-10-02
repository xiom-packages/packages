# xiom.zigbee

Pure-XIOM (no FFI) structure codec for the ZigBee protocol stack: IEEE
802.15.4 MAC frames, ZigBee NWK headers and ZigBee APS headers.

> **Status:** `incubating` -- conformance-tested (26/26); published at `v0.1.3` on the XIOM registry.
> **Honest scope:** this package parses **structure** only. It does not
> decrypt anything, does not verify the MAC FCS, does not implement
> AES-CCM* or key management, and does not decode MAC/NWK/APS command
> payloads. Secured bytes are reported as opaque spans. See
> [SPEC.md](SPEC.md) for the exact byte layouts, the error catalog and the
> full non-goals list.

## What it does

| Layer | Parsed |
|-------|--------|
| IEEE 802.15.4 MAC | frame control, sequence number, short (16-bit) and extended (64-bit) addressing, PAN ID compression, opaque auxiliary security header, payload span, trailing FCS (located, not verified), beacon superframe spec / GTS / pending addresses, MAC command identifier table |
| ZigBee NWK | frame control, protocol version, discover route, 16-bit destination/source, radius, sequence, optional 64-bit IEEE addresses, multicast control, source route subframe, NWK command identifier table, raw payload span |
| ZigBee APS | frame control, delivery mode, destination endpoint, group address, cluster/profile identifiers, source endpoint, APS counter, extended-header fragmentation bits, raw payload span |

Classification helpers cover the MAC broadcast address (`0xFFFF`), the NWK
broadcast addresses (`0xFFFB..0xFFFD`, `0xFFFF`) and the APS group ranges
(`0x0001..0xFFF7` assignable, `0xFFFF` broadcast group).

## Layout

```
xiom-zigbee/
  package.xi                  manifest (xiom.zigbee 0.1.0)
  src/zigbee.xi               the codec (dependency-free)
  tests/test_conformance.xi   26 conformance checks
  SPEC.md                     byte-level layouts and error catalog
  README.md                   this file
```

## Usage

```xiom
use xiom.zigbee;

// data: a complete PSDU including the trailing 2-byte FCS
let mr = mac_parse(&data);
if !mr.is_ok {
  io.println("mac: " + mr.error);   // e.g. "zigbee: truncated mac frame at byte 5"
  return;
}
let m: MacFrame = mr.value;

// The MAC payload usually carries a NWK frame.
let np = mac_payload(&data, &m);
if np.is_ok {
  let nwkbuf: Vec[UInt8] = np.value;
  let nr = nwk_parse(&nwkbuf);
  if nr.is_ok {
    let n: NwkFrame = nr.value;
    io.println("nwk dest=" + ... + " src=" + ...);   // use the accessors
    let ap = nwk_payload(&nwkbuf, &n);
    if ap.is_ok {
      let apsbuf: Vec[UInt8] = ap.value;
      let ar = aps_parse(&apsbuf);
      if ar.is_ok {
        let a: ApsFrame = ar.value;
        // aps_cluster_id(&a), aps_profile_id(&a), aps_payload(&apsbuf, &a), ...
      }
    }
  }
}
```

Every parsed struct is a flat value type; all access are free functions
(`mac_frame_type(&m)`, `nwk_dest(&n)`, `aps_cluster_id(&a)`, ...). Fields
that are absent come back as `-1` or an empty vector, so callers never need
to inspect the struct directly.

### Error model

* Every parse error is a stable `Str` carrying the absolute byte offset of
  the first byte that could not be satisfied, for example
  `"zigbee: truncated mac frame at byte 9"`.
* `mac_parse` rejects truncation, the reserved addressing mode 1, MAC frame
  types 4..7, FCF bits 8/9 (802.15.4-2015 sequence-number suppression and
  header IEs) and impossible beacon counts.
* `nwk_parse` rejects truncation, NWK frame types 2/3, impossible source
  route relay counts and unsecured command frames without a command id.
* `aps_parse` rejects truncation, APS frame type 3, delivery mode 3 and a
  truncated extended header.
* Span extraction (`mac_payload`, `nwk_payload`, `aps_payload`, FCS)
  re-checks bounds against the buffer it is given.

## Testing

From the repository root:

```powershell
& .\scripts\port.ps1 -Package xiom.zigbee
```

The suite builds all frame buffers in-test (no capture files) and prints one
`[PASS]` line per check.

## License

MIT OR Apache-2.0. See the repository root `LICENSE-MIT` and
`LICENSE-APACHE`.
