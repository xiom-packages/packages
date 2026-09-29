# xiom.wireless

> **Status:** `incubating` -- conformance-tested (33/33); published at `v0.1.1` on the XIOM registry.
> **Scope:** the *structure* of an IEEE 802.11 MAC frame -- Frame Control,
> Duration/ID, the Address 1..4 matrix, Sequence Control, the optional QoS
> control and HT control fields, the fixed fields of the common management
> bodies and the information element TLV walk.
> **Not in scope:** cryptography (RSN/WPA suites are reported, never
> verified), PHY, FCS checking, frame transmission/encoding, association
> state machines, driver/`iw`/`wpa_supplicant` bindings.
> **Deps:** none in the library module; the tests use `xiom.std` only.
> **Subtype table:** IEEE 802.11-2016 Table 9-1 for every frame type. The
> control slots 2..7 (Trigger, TACK, beamforming report poll, VHT NDP
> announcement, control frame extension, control wrapper) are named but not
> structurally decoded, so they are rejected rather than guessed; subtypes
> 0..1 are reserved. SPEC.md records the table.

## What it is

`xiom.wireless` answers structural questions about 802.11 frames without
guessing: how long is the MAC header for this type/subtype/DS combination,
which addresses are present, is there a QoS Control field, what are the
TID/EOSP/ack-policy/TXOP values, is there a 4-byte HT Control field, what
fixed fields does the management body carry, and which information elements
follow.

The module is deliberately parse-only. Nothing is encoded, no checksum is
computed, and no security suite is evaluated. Unknown information elements
are preserved raw: the walk records id, absolute payload offset and payload
length for every element in order, so an application can decode an element
this package does not know.

```xi
use xiom.io; use xiom.wireless; use xiom.convert.int;

fn dump(data: &Vec[UInt8]) {
  let fr = wireless_parse(data);
  if !fr.is_ok {
    io.println("wireless: " + fr.error);
    return;
  }
  let f: WirelessFrame = fr.value;
  io.println(wireless_type_name(f.frame_type) + " / " + wireless_subtype_name(f.frame_type, f.subtype));
  io.println("header " + int_to_string(wireless_header_length(&f)) + " bytes, body " + int_to_string(wireless_body_length(&f)) + " bytes");

  if f.frame_type == WIRELESS_TYPE_MANAGEMENT {
    let mr = wireless_parse_mgmt(data);
    if mr.is_ok {
      let m: WirelessMgmt = mr.value;
      let sr = wireless_ssid(&m);
      if sr.is_ok {
        let ssid: Vec[UInt8] = sr.value;   // raw bytes, any encoding
        ...
      }
    }
  }
}
```

## API

### Frame structure

| Function | Returns | Description |
|---|---|---|
| `wireless_parse(data)` | `Result[WirelessFrame, Str]` | Parse the MAC header at offset 0; `header_len` is the consumed count, `body_off`/`body_len` locate the body. |
| `wireless_frame_type(f)` / `wireless_subtype(f)` / `wireless_protocol_version(f)` | `Int` | Frame Control fields. |
| `wireless_flag(f, bit)` | `Bool` | Flag bits 0..7 (to-ds, from-ds, more-fragments, retry, power-management, more-data, protected, order). |
| `wireless_duration_id(f)` | `Int` | Duration/ID as read; carries the AID on a PS-Poll. |
| `wireless_ps_poll_aid(f)` | `Result[Int, Str]` | AID from a PS-Poll Duration/ID (low 14 bits); `Err` on any other frame. |
| `wireless_address_count(f)` | `Int` | 1..4 addresses present. |
| `wireless_address(f, index)` | `Result[Vec[UInt8], Str]` | Copy of address 1..4; `Err` when absent. |
| `wireless_address_byte(f, index, byte)` | `Int` | One address byte, -1 when absent. |
| `wireless_sequence_control(f)` / `wireless_fragment_number(f)` / `wireless_sequence_number(f)` | `Int` | Sequence Control split (fragment low 4 bits, sequence high 12); -1 on control frames. |
| `wireless_qos_present(f)` / `wireless_tid(f)` / `wireless_eosp(f)` / `wireless_ack_policy(f)` / `wireless_a_msdu_present(f)` / `wireless_txop_limit(f)` | `Bool`/`Int` | QoS Control decode (data subtypes 8..15). |
| `wireless_ht_control_present(f)` | `Bool` | True when the Order bit marks a 4-byte HT Control field. |
| `wireless_header_length(f)` / `wireless_body_offset(f)` / `wireless_body_length(f)` | `Int` | Consumed counts and body span. |
| `wireless_body(data, f)` | `Result[Vec[UInt8], Str]` | Copy of the body bytes. |

### Management bodies and information elements

| Function | Returns | Description |
|---|---|---|
| `wireless_parse_mgmt(data)` | `Result[WirelessMgmt, Str]` | Header + fixed fields + IE walk. |
| `wireless_timestamp(m)` / `wireless_beacon_interval(m)` / `wireless_capability(m)` | `Int` | Beacon/probe-response fixed fields; -1 when absent. |
| `wireless_cap_ess(m)` ... `wireless_capability_bit(cap, bit)` | `Bool` | Capability bits (ESS, IBSS, privacy, short preamble, spectrum management, QoS, short slot, APSD, radio measurement, DSSS-OFDM, ...). |
| `wireless_status_code(m)` / `wireless_reason_code(m)` | `Int` | Status/reason fields; -1 when absent. |
| `wireless_status_name(code)` / `wireless_reason_name(code)` | `Str` | Stable code tables (status 0..70, reason 0..40). |
| `wireless_auth_algorithm(m)` / `wireless_auth_sequence(m)` | `Int` | Authentication fixed fields. |
| `wireless_auth_algorithm_name(a)` | `Str` | open-system / shared-key / fast-bss-transition / sae / fils-shared-key / fils-shared-key-pfs. |
| `wireless_listen_interval(m)` / `wireless_aid(m)` | `Int` | Association request/response fields; -1 when absent. |
| `wireless_current_ap(m)` | `Vec[UInt8]` | Reassociation current AP address (empty otherwise). |
| `wireless_action_category(m)` / `wireless_action_code(m)` | `Int` | Action fixed fields; -1 when absent. |
| `wireless_ie_count(m)` / `wireless_ie_id(m, i)` / `wireless_ie_offset(m, i)` / `wireless_ie_length(m, i)` / `wireless_ie_find(m, id)` / `wireless_ie_present(m, id)` | `Int`/`Bool` | TLV pool accessors. |
| `wireless_ie_payload(data, m, i)` / `wireless_ie_payload_of(data, m, id)` | `Result[Vec[UInt8], Str]` | Raw payload of any element (unknown ids included). |
| `wireless_ssid(m)` | `Result[Vec[UInt8], Str]` | Raw SSID bytes (may be empty for a wildcard probe request). |
| `wireless_rates(m)` / `wireless_rate_is_basic(b)` / `wireless_rate_half_mbps(b)` | `Result[Vec[UInt8], Str]`/`Bool`/`Int` | Supported rates payload and per-byte decode (0.5 Mbps units, bit 7 basic). |
| `wireless_ds_channel(m)` | `Result[Int, Str]` | DS parameter set channel (element 3). |
| `wireless_tim_dtim_count(m)` / `wireless_tim_dtim_period(m)` / `wireless_tim_bitmap_len(m)` / `wireless_tim_bitmap(data, m)` | `Result[Int, Str]`/`Result[Vec[UInt8], Str]` | TIM DTIM fields and bitmap presence (element 5). |
| `wireless_country_code(m)` / `wireless_country_triplets(m)` | `Result[Int, Str]` | Country code as packed ASCII and channel-triplet count (element 7). |
| `wireless_rsn_version(m)` / `wireless_rsn_group(m)` / `wireless_rsn_pairwise_count(m)` / `wireless_rsn_pairwise(m, i)` / `wireless_rsn_akm_count(m)` / `wireless_rsn_akm(m, i)` / `wireless_rsn_capabilities(m)` / `wireless_rsn_pmkid_count(m)` | `Result[Int, Str]`/`Int` | RSN decode (element 48). Cipher suites are combined `OUI*256 + type` identifiers. |
| `wireless_suite_oui(s)` / `wireless_suite_type(s)` / `wireless_suite_oui_byte(s, i)` | `Int` | Split a combined suite identifier. |
| `wireless_ht_cap_info(m)` / `wireless_ht_ampdu(m)` / `wireless_vht_cap_info(m)` / `wireless_ext_cap_len(m)` | `Result[Int, Str]` | HT (45, 26 bytes), VHT (191, 12 bytes) and extended capabilities (127) decode. |
| `wireless_vendor_count(m)` / `wireless_vendor_oui(m, i)` / `wireless_vendor_type(m, i)` / `wireless_vendor_wpa(m)` / `wireless_vendor_wmm(m)` | `Int`/`Result[Int, Str]`/`Bool` | Vendor elements (221); WPA is `00:50:F2` type 1 and WMM is `00:50:F2` type 2. |

`wireless_type_name(t)` / `wireless_subtype_name(t, s)` / `wireless_flag_name(bit)` /
`wireless_ie_name(id)` / `wireless_body_kind_name(kind)` /
`wireless_ack_policy_name(p)` / `wireless_version()` complete the naming API.

## Tests

```
xiom --run tests/test_conformance.xi
```

33 checks, all fixtures assembled byte by byte in the test file: beacon with
SSID/rates/DS/RSN, probe request/response (TIM), open-system and SAE
authentication, association/reassociation frames and responses,
disassoc/deauth, ATIM, action, QoS data (with and without HT control),
4-address WDS data, the control frames BAR/BA/PS-Poll/RTS/CTS/ACK/CF-End/
CF-End+CF-Ack (including the PS-Poll AID helper), plus malformed cases:
truncation at every header stage, malformed IE framing, impossible element
lengths, invalid DS bits, reserved subtypes and unknown elements preserved
raw.

## Honest limitations

- Parse only: there is no encoder, no FCS handling and no PHY.
- The Beacon timestamp is a u64 read into a signed `Int`; a timestamp with
  bit 63 set is rejected (`wireless: timestamp out of range at offset O`).
  The same convention as `xiom.radiotap`'s TSFT field.
- The Association Response AID is stored as the raw 16-bit field; bits
  14..15 (reserved by the standard) are preserved, not masked.
- Extension frames (type 3) use the data addressing matrix and carry no
  decoded body; only the DMG beacon subtype is named.
- Reserved management subtypes 6 (timing advertisement), 7 and 15 parse as
  headers but their bodies are rejected as unsupported.
- Cipher suites are reported as `OUI*256 + type` identifiers; no suite is
  validated, and no cryptographic operation is performed.
- Control subtypes 0..1 are reserved and rejected. Subtypes 2..7 (Trigger,
  TACK, beamforming report poll, VHT NDP announcement, control frame
  extension, control wrapper) are named in the subtype table but not
  structurally decoded: their layouts are variable or extension specific,
  so `wireless_parse` rejects them instead of guessing a header length.
- CF-End and CF-End + CF-Ack use a single address (RA) in this package's
  matrix; any BSSID bytes that follow remain in the raw body span.
- No `Str` is ever built for a MAC address or SSID: address and element
  bytes stay raw `Vec[UInt8]` values so any encoding survives.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
