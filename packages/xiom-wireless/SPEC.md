# xiom.wireless -- specification

Byte-level layouts actually implemented by `src/wireless.xi`, the parsing
policy, the stable error catalog and the test plan. Everything here is
parse-only: no encoding, no cryptography, no PHY.

Target: IEEE 802.11-2016 MAC frame structure (subtype numbering per
Table 9-1).

---

## 1. Scope

| Area | Implemented |
|---|---|
| Frame Control decode | yes (all fields) |
| Duration/ID | yes (raw u16) |
| Address 1..4 matrix | yes (presence by type/subtype/DS bits) |
| Sequence Control | yes (fragment 0..15, sequence 0..4095) |
| QoS Control | yes (TID, EOSP, ack policy, A-MSDU, TXOP limit) |
| HT Control | presence and offset only (4 bytes, not decoded) |
| Management fixed bodies | beacon/probe response, probe request, assoc/reassoc request/response, auth, disassoc/deauth, ATIM, action |
| Information elements | TLV walk + SSID, rates, DS, TIM, country, HT, RSN, VHT, extended capabilities, vendor |
| Unknown information elements | preserved raw (id, payload offset, length) |
| Encoding / emit | no |
| FCS, retries, aggregation, PHY | no |
| Crypto validation | no (suites reported only) |

## 2. Frame Control (2 bytes, little-endian u16)

```
u16 = version + type*4 + subtype*16 + flag_byte*256
```

| Bits | Width | Field | Values |
|---|---|---|---|
| 0..1 | 2 | protocol version | must be 0; anything else rejected |
| 2..3 | 2 | type | 0 management, 1 control, 2 data, 3 extension |
| 4..7 | 4 | subtype | per type (section 3) |
| 8 | 1 | to DS | |
| 9 | 1 | from DS | |
| 10 | 1 | more fragments | |
| 11 | 1 | retry | |
| 12 | 1 | power management | |
| 13 | 1 | more data | |
| 14 | 1 | protected frame | |
| 15 | 1 | order | HT Control present flag source |

All bitfields are extracted with divisor/modulo arithmetic; no mask touches
a raw field (v0.61.3 sign-bit bit-test limitation).

## 3. Subtype tables

### 3.1 Management (type 0)

| Subtype | Name | Body family |
|---|---|---|
| 0 | assoc-req | capability, listen interval, IEs |
| 1 | assoc-resp | capability, status, AID, IEs |
| 2 | reassoc-req | capability, listen interval, current AP, IEs |
| 3 | reassoc-resp | capability, status, AID, IEs |
| 4 | probe-req | IEs only |
| 5 | probe-resp | timestamp, beacon interval, capability, IEs |
| 6 | timing-adv | header parses; body unsupported |
| 7 | reserved | header parses; body unsupported |
| 8 | beacon | timestamp, beacon interval, capability, IEs |
| 9 | atim | empty body |
| 10 | disassoc | reason (exactly 2 bytes) |
| 11 | auth | algorithm, sequence, status, optional IEs |
| 12 | deauth | reason (exactly 2 bytes) |
| 13 | action | category, action, raw payload |
| 14 | action-no-ack | category, action, raw payload |
| 15 | reserved | header parses; body unsupported |

### 3.2 Data (type 2)

| Subtype | Name | Subtype | Name |
|---|---|---|---|
| 0 | data | 8 | qos-data |
| 1 | data+cf-ack | 9 | qos-data+cf-ack |
| 2 | data+cf-poll | 10 | qos-data+cf-poll |
| 3 | data+cf-ack+cf-poll | 11 | qos-data+cf-ack+cf-poll |
| 4 | null | 12 | qos-null |
| 5 | cf-ack | 13 | reserved (QoS control present) |
| 6 | cf-poll | 14 | qos-cf-poll |
| 7 | cf-ack+cf-poll | 15 | qos-cf-ack+cf-poll |

QoS Control is present for data subtypes 8..15 (`subtype >= 8`).

### 3.3 Control (type 1) -- IEEE 802.11-2016 Table 9-1

| Subtype | Name | Structure implemented |
|---|---|---|
| 0..1 | reserved | rejected (`unsupported control subtype`) |
| 2 | trigger | named; not structurally decoded (rejected) |
| 3 | tack | named; not structurally decoded (rejected) |
| 4 | beamforming-report-poll | named; not structurally decoded (rejected) |
| 5 | vht-ndp-announcement | named; not structurally decoded (rejected) |
| 6 | control-frame-extension | named; not structurally decoded (rejected) |
| 7 | control-wrapper | named; not structurally decoded (rejected) |
| 8 | bar | 2 addresses (RA, TA) |
| 9 | ba | 2 addresses (RA, TA) |
| 10 | ps-poll | 2 addresses (BSSID, TA); Duration/ID carries the AID |
| 11 | rts | 2 addresses (RA, TA) |
| 12 | cts | 1 address (RA) |
| 13 | ack | 1 address (RA) |
| 14 | cf-end | 1 address (RA) |
| 15 | cf-end+cf-ack | 1 address (RA) |

Subtypes 2..7 are named by `wireless_subtype_name(1, s)` but their layouts
are variable or extension specific (Trigger, TACK, beamforming report poll,
VHT NDP announcement, control frame extension, control wrapper), so
`wireless_parse` rejects them with `unsupported control subtype` instead of
guessing a fixed header length. For CF-End and CF-End + CF-Ack the parser
consumes a single address; any BSSID bytes that follow stay in the raw body
span.

### 3.4 Extension (type 3)

Subtype 0 is named `dmg-beacon`; all other values are `reserved`. The MAC
header is parsed with the data addressing matrix and the data QoS rule; the
body is never decoded.

## 4. MAC header layouts and consumed counts

`header_len` is the number of bytes consumed by the MAC header; `body_off`
equals it and `body_len` is the remaining buffer length.

| Frame | Fields | Header length |
|---|---|---|
| Management | FC, duration, addr1..3, sequence | 24 (+4 HT when order set) |
| Control, CTS/ACK/CF-End/CF-End+CF-Ack | FC, duration, addr1 | 10 |
| Control, BAR/BA/PS-Poll/RTS | FC, duration, addr1, addr2 | 16 |
| Data, 3 addresses | FC, duration, addr1..3, sequence | 24 |
| Data, 4 addresses (to DS + from DS) | + addr4 | 30 |
| QoS data (subtype >= 8) | + QoS control | +2 |
| Order bit set on QoS data or management | + HT control | +4 |

Control frames carry **no** Sequence Control field; `seq_control`,
`fragment_number` and `sequence_number` are -1 for them.

## 5. Addressing matrix

| Type | Condition | Addresses |
|---|---|---|
| Management | always | 3 (RA, TA, BSSID); DS bits must be 0 |
| Control | subtype 12/13/14/15 (CTS/ACK/CF-End/CF-End+CF-Ack) | 1 (RA) |
| Control | subtype 8..11 (BAR/BA/PS-Poll/RTS) | 2 (RA, TA and BSSID/TA for PS-Poll); DS bits must be 0 |
| Control | 0..7 | rejected (unsupported control subtype) |
| Data / extension | to DS = 0, from DS = 0 | 3 |
| Data / extension | to DS = 1, from DS = 0 | 3 |
| Data / extension | to DS = 0, from DS = 1 | 3 |
| Data / extension | to DS = 1, from DS = 1 | 4 |

A management or control frame with either DS bit set is rejected
(`invalid ds bits ...`). Addresses are stored as 6-byte `Vec[UInt8]`
values; absent addresses are empty vectors and `wireless_address` reports
`wireless: address absent`.

## 6. Duration/ID, Sequence Control, QoS Control, HT Control

```
Duration/ID   u16 little-endian, raw                       (2 bytes)
              on a PS-Poll the AID is the low 14 bits
              (bits 14..15 are marker bits): see
              wireless_ps_poll_aid
Sequence      u16 little-endian: fragment = v % 16,
              sequence = v / 16                            (2 bytes)
QoS Control   u16 little-endian:
                TID          = v % 16                      bits 0..3
                EOSP         = (v / 16) % 2                bit 4
                ack policy   = (v / 32) % 4                bits 5..6
                A-MSDU       = (v / 128) % 2               bit 7
                TXOP limit   = v / 256                     bits 8..15
HT Control    4 bytes, presence flagged, not decoded
```

`ht_control_present` is true when the Order bit is set on a QoS data frame
or on any management frame. `qos_control_off` / `ht_control_off` record the
absolute field offsets (-1 when absent).

## 7. Management body fixed fields

Offsets are relative to the start of the body (`body_off`).

| Family | Minimum | Layout |
|---|---|---|
| beacon-like (5, 8) | 12 | timestamp u64 (byte 7 < 128), interval u16, capability u16, IEs |
| probe-req (4) | 0 | IEs from body start |
| assoc-req (0) | 4 | capability u16, listen interval u16, IEs |
| reassoc-req (2) | 10 | capability u16, listen interval u16, current AP 6 bytes, IEs |
| assoc-resp (1, 3) | 6 | capability u16, status u16, AID u16, IEs |
| auth (11) | 6 | algorithm u16, sequence u16, status u16, optional IEs |
| disassoc/deauth (10, 12) | exactly 2 | reason u16, no IEs |
| action (13, 14) | 2 | category byte, action byte, raw payload |
| ATIM (9) | exactly 0 | no fields |

Capability bit names exposed by the accessors: 0 ESS, 1 IBSS, 4 privacy,
5 short preamble, 8 spectrum management, 9 QoS, 10 short slot time,
11 APSD, 12 radio measurement, 13 DSSS-OFDM; the generic
`wireless_capability_bit(cap, bit)` covers bits 0..15.

## 8. Information element TLV walk

```
element    := id:u8  length:u8  payload[length]
```

The walk covers `[ie_area_off, ie_area_off + ie_area_len)` and records
`ie_ids`, `ie_offsets` (absolute payload offsets) and `ie_lengths` for every
element in order. `wireless_ie_payload(data, m, i)` returns any element's
raw payload, so unknown ids are preserved exactly.

### 8.1 Decoded elements

| Id | Name | Validation | Decoded fields |
|---|---|---|---|
| 0 | SSID | none | `ssid` (first occurrence; may be empty) |
| 1 | supported rates | none | `rates` (first occurrence) |
| 3 | DS parameter set | length == 1 | `ds_channel` |
| 5 | TIM | length >= 2 | `tim_dtim_count`, `tim_dtim_period`, bitmap offset/len (`len - 2`, may be 0) |
| 7 | country | length >= 3 and (len-3) % 3 == 0 | `country_code` (first two bytes packed), `country_triplets` |
| 45 | HT capabilities | length == 26 | `ht_info` (u16), `ht_ampdu` (byte 2) |
| 48 | RSN | see 8.2 | `rsn_version`, `rsn_group`, `rsn_pairwise[]`, `rsn_akm[]`, `rsn_capabilities`, `rsn_pmkid_count` |
| 127 | extended capabilities | length >= 1 | `ext_len` |
| 191 | VHT capabilities | length == 12 | `vht_info` (u32) |
| 221 | vendor specific | length >= 4 | `vendor_ouis[]`, `vendor_types[]`, WPA/WMM flags |

### 8.2 RSN element layout (id 48)

```
version        u16
group cipher   OUI[3] + type[1]
pairwise count u16 (must be >= 1)
pairwise[]     count * (OUI[3] + type[1])
AKM count      u16 (must be >= 1)
AKM[]          count * (OUI[3] + type[1])
capabilities   u16
PMKID count    u16 (optional; present only when bytes remain)
PMKIDs         count * 16
group mgmt     OUI[3] + type[1] (optional 4 bytes)
```

Minimum length 20 bytes. Every count is validated against the remaining
payload; any leftover after the optional group-management suite is an
error. Cipher suites are exposed as `OUI*256 + type` (`wireless_suite_oui`
and `wireless_suite_type` split them; `wireless_suite_oui_byte(s, i)` reads
the OUI bytes).

Recognized vendor OUIs/types: `00:50:F2` type 1 marks WPA, `00:50:F2`
type 2 marks WMM.

## 9. Error catalog (stable strings)

Offsets in messages are absolute indexes into the parsed buffer; lengths are
decimal.

### 9.1 Header (from `wireless_parse`)

| Condition | Message |
|---|---|
| buffer shorter than the minimum header | `wireless: truncated frame at offset 0: need N bytes, have M` |
| protocol version != 0 | `wireless: bad protocol version V` |
| management frame with a DS bit set | `wireless: invalid ds bits for management frame` |
| control frame with a DS bit set | `wireless: invalid ds bits for control frame` |
| control subtype 0..7 | `wireless: unsupported control subtype S` (0..1 reserved, 2..7 named but not structurally decoded) |
| QoS control byte missing | `wireless: truncated qos control at offset O: need 2 bytes, have M` |
| HT control bytes missing | `wireless: truncated ht control at offset O: need 4 bytes, have M` |

### 9.2 Management body (`wireless_parse_mgmt`)

| Condition | Message |
|---|---|
| not a management frame | `wireless: not a management frame` |
| reserved management subtype | `wireless: unsupported management subtype S` |
| fixed body too short | `wireless: truncated management body at offset O: need N bytes, have M` |
| beacon timestamp bit 63 set | `wireless: timestamp out of range at offset O` |
| trailing bytes on an exact-length body | `wireless: unexpected management body bytes at offset O: N` |
| IE header split by the body end | `wireless: truncated ie header at offset O: need 2 bytes, have M` |
| IE payload crosses the body end | `wireless: bad ie length at offset O: ie I length L exceeds M remaining bytes` |
| DS element length != 1 | `wireless: bad ds parameter set ie length at offset O: L` |
| TIM element length < 2 | `wireless: bad tim ie length at offset O: L` |
| country element length < 3 or not 3 + 3k | `wireless: bad country ie length at offset O: L` |
| HT capabilities length != 26 | `wireless: bad ht capabilities ie length at offset O: L` |
| VHT capabilities length != 12 | `wireless: bad vht capabilities ie length at offset O: L` |
| extended capabilities length < 1 | `wireless: bad extended capabilities ie length at offset O: L` |
| vendor element length < 4 | `wireless: bad vendor ie length at offset O: L` |
| RSN length < 20 or a count overflows | `wireless: bad rsn ie length at offset O: L` |
| pairwise count 0 | `wireless: bad rsn pairwise count at offset O: C` |
| AKM count 0 | `wireless: bad rsn akm count at offset O: C` |
| PMKID list overflows | `wireless: bad rsn pmkid count at offset O: C` |
| bytes after the RSN fields | `wireless: trailing bytes in rsn ie at offset O` |

### 9.3 Accessor errors

`wireless: address index out of range`, `wireless: address absent`,
`wireless: body out of bounds`, `wireless: ie index out of range`,
`wireless: ie absent`, `wireless: ie out of bounds`,
`wireless: ssid ie absent`, `wireless: supported rates ie absent`,
`wireless: ds parameter set ie absent`, `wireless: tim ie absent`,
`wireless: tim bitmap out of bounds`, `wireless: country ie absent`,
`wireless: rsn ie absent`, `wireless: rsn pairwise index out of range`,
`wireless: rsn akm index out of range`,
`wireless: ht capabilities ie absent`, `wireless: vht capabilities ie absent`,
`wireless: extended capabilities ie absent`, `wireless: vendor index out of range`.

## 10. Parsing policy

1. All bounds are checked before any byte is read; every rejection names
   the offset and the missing length where meaningful.
2. Management and control frames reject nonzero DS bits; data and extension
   frames use the full 00/01/10/11 matrix.
3. Control subtypes 0..7 are rejected at header level: 0..1 are reserved
   and 2..7 are named (Trigger, TACK, beamforming report poll, VHT NDP
   announcement, control frame extension, control wrapper) but not
   structurally decoded, because their layouts are variable or extension
   specific. Reserved management subtypes parse as headers and are rejected
   at body level.
4. A TLV is rejected the moment its declared length crosses the element
   area; semantic decoders then validate their own minimum/relative
   lengths (DS, TIM, country, HT, VHT, extended capabilities, vendor, RSN).
5. Unknown or undecoded elements never fail the walk; their payloads stay
   addressable through the parallel pool.
6. Nothing is written and nothing is mutated; all results are fresh values
   derived from the caller's buffer.

## 11. Test plan

`tests/test_conformance.xi` -- 33 checks, one `[PASS]` line each:

| Check | Covers |
|---|---|
| beacon header | type/subtype/version, 3 addresses, sequence split (frag 1 / seq 291), consumed 24, body 49 |
| beacon body | timestamp 4660, interval 100, capability ESS/privacy/short preamble/short slot |
| beacon IEs | pool order/offsets, SSID "TEST", rates decode, DS channel 6 |
| RSN | version 1, group CCMP, pairwise/AKM suites, capabilities, PMKID absent |
| probe response | QoS capability, SSID, DS, TIM count/period/bitmap |
| probe request | IE-only body, absent DS error, unknown element |
| open auth | algorithm 0 / seq 1 / status 0, names |
| SAE auth | algorithm 3 with trailing RSN |
| assoc req | capability, listen interval, SSID |
| assoc resp | capability, status, AID |
| reassoc req | current AP address |
| disassoc/deauth | reason names, exact-length enforcement |
| ATIM | empty body, trailing-byte rejection |
| action | category/action/payload span |
| reserved mgmt subtypes | 6, 7, 15 rejected |
| QoS data | TID 6, EOSP, ack policy 2, A-MSDU, TXOP 2, offsets |
| QoS + order | HT control offset, 30-byte header |
| WDS | to/from DS matrix, addr4 |
| null / qos-null | QoS presence rule |
| RTS | subtype 11: 16 bytes, 2 addresses, no sequence |
| CTS / ACK | subtypes 12/13: 10 bytes, 1 address |
| BAR / BA / PS-Poll | subtypes 8/9/10: 16-byte headers, 2 addresses |
| CF-End / CF-End+CF-Ack | subtypes 14/15: 10-byte headers, 1 address |
| PS-Poll AID | subtype 10: Duration/ID = AID and the helper guards |
| control subtypes 0..7 + DS bits | error catalog |
| truncation | header, QoS and HT offsets with need/have |
| malformed IE framing | truncated header, overlong length |
| impossible lengths | DS/TIM/country/RSN/HT/VHT/extended/vendor |
| unknown IEs | raw payload preservation and offsets |
| vendor | WPA/WMM recognition |
| HT/VHT/extended caps | decoded fields |
| body/address accessors | guards and copies |
| name tables | type, subtype, flag, status, reason, ack, IE, body kind |

## 12. Known limitations

- No encoder; parse only.
- Beacon timestamp must fit signed `Int` (bit 63 clear).
- PS-Poll AID extraction keeps the raw Duration/ID available; bits 14..15
  are masked out of the AID helper only.
- Extension frames reuse the data matrix; only subtype 0 is named.
- Control subtypes 0..1 are reserved and 2..7 (Trigger, TACK, beamforming
  report poll, VHT NDP announcement, control frame extension, control
  wrapper) are named but not structurally decoded; the parser rejects them
  instead of guessing a header length.
- CF-End and CF-End + CF-Ack consume a single address (RA); trailing BSSID
  bytes stay in the raw body span.
- No FCS, no fragmentation reassembly, no aggregation, no PHY, no crypto.
