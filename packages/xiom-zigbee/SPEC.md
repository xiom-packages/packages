# xiom.zigbee -- specification

Structure codec for the ZigBee protocol stack: IEEE 802.15.4 MAC frames,
ZigBee NWK headers and ZigBee APS headers. This document describes the
byte-level layouts actually implemented by `src/zigbee.xi` and tested by
`tests/test_conformance.xi` (26 checks). It is the source of truth for the
error catalog and the sentinel conventions.

**Status:** implemented, `port.ps1` green on XIOM 0.61.3 (26/26).
**Scope:** header structure only. No decryption, no FCS verification, no
security processing, no MAC command payload decoding, no NWK/APS command
payload decoding, no key management.

## 1. Conventions

* All multi-byte integers are little-endian on the wire and are decoded with
  pure arithmetic (`+ - * / %`), never with `&` masks.
* Every parse error message carries the absolute byte offset of the first
  byte that could not be satisfied: `"zigbee: <reason> at byte <N>"`.
* `consumed` in every parsed struct is the number of bytes the parse
  consumed from the input; on success this is the whole input, because each
  parse function treats its buffer as exactly one frame/header plus its
  payload span. Callers with concatenated data must slice first.
* Absent optional fields use `-1` (Int fields) or the empty vector (byte
  fields); `Bool` fields default to `false`.
* Extended 64-bit addresses are kept as raw 8-byte copies (`Vec[UInt8]`,
  most significant byte last on the wire, i.e. address bytes in the order
  transmitted) because a 64-bit value with bit 63 set does not fit the
  signed `Int` result type.
* Input buffers passed to the three parse functions:
  * `mac_parse`: a complete PSDU -- MAC header, payload and the trailing
    2-byte FCS.
  * `nwk_parse`: exactly one NWK frame, typically the MAC payload.
  * `aps_parse`: exactly one APS frame, typically the NWK payload.

## 2. IEEE 802.15.4 MAC

### 2.1 Frame control (2 bytes, little-endian)

| Bits  | Field                        | Extraction                    |
|-------|------------------------------|-------------------------------|
| 0..2  | Frame type                   | `v % 8`                       |
| 3     | Security enabled             | `(v / 8) % 2`                 |
| 4     | Frame pending                | `(v / 16) % 2`                |
| 5     | Ack request                  | `(v / 32) % 2`                |
| 6     | PAN ID compression           | `(v / 64) % 2`                |
| 7..9  | Reserved (bit 8 = 802.15.4-2015 sequence-number suppression, bit 9 = IE present) | `(v / 128) % 8` |
| 10..11| Destination addressing mode  | `(v / 1024) % 4`              |
| 12..13| Frame version                | `(v / 4096) % 4`              |
| 14..15| Source addressing mode       | `(v / 16384) % 4`             |

Frame type: 0 beacon, 1 data, 2 acknowledgement, 3 MAC command. Types 4..7
(802.15.4-2015 reserved/multipurpose/fragment/extended) are rejected:
`zigbee: unsupported mac frame type at byte 0`.

Addressing modes: 0 absent, 2 short (16-bit), 3 extended (64-bit); mode 1
(reserved) is rejected: `zigbee: bad mac addressing mode at byte 0`.

Frame control bit 8 or bit 9 set is rejected (`... sequence number
suppression unsupported ...`, `... information elements unsupported ...`)
because both change the header length in ways this codec does not walk.

### 2.2 Sequence number

One byte at offset 2, always present in the frames this codec accepts.

### 2.3 Addressing fields

Walked in this order, with `limit = data.len() - 2` (the FCS boundary):

1. destination PAN ID (2 bytes) -- if destination mode != 0;
2. destination address (2 or 8 bytes) -- if destination mode != 0;
3. source PAN ID (2 bytes) -- if source mode != 0 **and not** (PAN ID
   compression and destination mode != 0). With PAN ID compression and both
   addresses present the source PAN is omitted from the wire and
   `mac_src_pan` echoes the destination PAN ID;
4. source address (2 or 8 bytes) -- if source mode != 0.

### 2.4 Auxiliary security header (opaque)

When frame control bit 3 is set, the bytes after the addressing fields begin
with the auxiliary security header. Its length depends on the key identifier
mode and frame counter suppression and is **not** decoded. `mac_parse`
records `aux_present = true` and `aux_off` (equal to `payload_off`) and
leaves the auxiliary header plus the secured payload in the MAC payload
span. Beacon fields and the MAC command identifier are not parsed for a
secured frame (they are inside the opaque span).

### 2.5 FCS

The last two bytes of the input are the FCS. They are located at
`fcs_off = data.len() - 2` and are **never verified** (no CRC-16
implementation is applied). `mac_fcs_bytes` returns them as read;
`mac_fcs_value` returns their little-endian value.

### 2.6 Beacon payload

Parsed only for frame type 0 without the security bit; the payload begins
immediately after the addressing fields.

Superframe specification (2 bytes LE at `payload_off`):

| Bits   | Field                  | Accessor                |
|--------|------------------------|-------------------------|
| 0..3   | Beacon order           | `mac_beacon_order`      |
| 4..7   | Superframe order       | `mac_superframe_order`  |
| 8..11  | Final CAP slot         | `mac_final_cap_slot`    |
| 12     | Battery life extension | `mac_battery_life`      |
| 14     | PAN coordinator        | `mac_pan_coordinator`   |
| 15     | Association permit     | `mac_assoc_permit`      |

GTS field (1 byte): bits 0..2 = descriptor count, bit 7 = GTS permit
(`mac_gts_permit`). Each descriptor is 3 bytes: 16-bit short address
(`mac_gts_addr`), then a byte whose bits 0..3 are the starting slot
(`mac_gts_start_slot`) and bits 4..7 the length (`mac_gts_length`).

Pending address field (1 byte): bits 0..2 = number of 16-bit short addresses
(`mac_pending_short_count`), bits 4..6 = number of 64-bit extended addresses
(`mac_pending_ext_count`). The short addresses follow (2 bytes each,
`mac_pending_short`), then the extended addresses (8 raw bytes each,
`mac_pending_ext_byte`).

`mac_beacon_end` is the offset just past the pending address list; any
remaining bytes up to `fcs_off` stay in the payload span as "beacon extra".

A GTS or pending count that cannot possibly fit before `fcs_off` is
`zigbee: impossible mac length at byte N` (N = offset of the list to read).

### 2.7 MAC command frames

Parsed only for frame type 3 without the security bit. The first payload
byte at `payload_off` is the command identifier (`mac_command_id`); the
remaining payload bytes up to `fcs_off` are the raw command payload
(`mac_command_data_off`, `mac_command_data_len`). A command frame without
that byte is `zigbee: truncated mac command frame at byte N`.

| ID   | Name                          |
|------|-------------------------------|
| 0x01 | Association request           |
| 0x02 | Association response          |
| 0x03 | Disassociation notification   |
| 0x04 | Data request                  |
| 0x05 | PAN ID conflict notification  |
| 0x06 | Orphan notification           |
| 0x07 | Beacon request                |
| 0x08 | Coordinator realignment       |
| 0x09 | GTS request                   |
| else | Reserved (`mac_command_name`) |

### 2.8 MAC error catalog

| Message                                                    | Trigger |
|------------------------------------------------------------|---------|
| `zigbee: truncated mac frame at byte N`                    | FCF, sequence number or an addressing field does not fit before the FCS |
| `zigbee: truncated mac beacon at byte N`                   | superframe/GTS/pending field does not fit |
| `zigbee: truncated mac command frame at byte N`            | command frame without its identifier byte |
| `zigbee: impossible mac length at byte N`                  | beacon list count cannot fit before the FCS |
| `zigbee: bad mac addressing mode at byte 0`                | addressing mode 1 |
| `zigbee: unsupported mac frame type at byte 0`             | frame type 4..7 |
| `zigbee: mac sequence number suppression unsupported at byte 0` | FCF bit 8 |
| `zigbee: mac information elements unsupported at byte 0`   | FCF bit 9 |
| `zigbee: mac payload out of bounds at byte N`              | `mac_payload` with a shorter buffer |
| `zigbee: mac fcs out of bounds at byte N`                  | `mac_fcs_bytes` / `mac_fcs_value` with a shorter buffer |

### 2.9 MAC classification helpers

`mac_short_class(addr)`: 0 ordinary, 1 broadcast (`0xFFFF`), 2 no-address
(`0xFFFE`, 802.15.4 `NO_ADDR16`). `mac_short_is_broadcast` tests `0xFFFF`.
Names via `mac_short_class_name`.

## 3. ZigBee NWK

### 3.1 Frame control (2 bytes, little-endian)

| Bits   | Field                      | Extraction           |
|--------|----------------------------|----------------------|
| 0..1   | Frame type                 | `v % 4`              |
| 2..5   | Protocol version           | `(v / 4) % 16`       |
| 6..7   | Discover route             | `(v / 64) % 4`       |
| 8      | Multicast                  | `(v / 256) % 2`      |
| 9      | Security                   | `(v / 512) % 2`      |
| 10     | Source route               | `(v / 1024) % 2`     |
| 11     | Destination IEEE address   | `(v / 2048) % 2`     |
| 12     | Source IEEE address        | `(v / 4096) % 2`     |
| 13     | End device initiator (r21) | `(v / 8192) % 2`     |

Frame type: 0 data, 1 NWK command; 2 and 3 (inter-PAN) are rejected:
`zigbee: unsupported nwk frame type at byte 0`.

### 3.2 Header order

1. frame control (2);
2. destination address (2, LE);
3. source address (2, LE);
4. radius (1);
5. sequence number (1);
6. destination IEEE address (8 raw bytes) -- if bit 11;
7. source IEEE address (8 raw bytes) -- if bit 12;
8. multicast control (1) -- if bit 8;
9. source route subframe -- if bit 10.

### 3.3 Multicast control

| Bits  | Field                  | Accessor                  |
|-------|------------------------|---------------------------|
| 0..1  | Multicast mode         | `nwk_multicast_mode`      |
| 2..4  | Non-member radius      | `nwk_multicast_radius`    |
| 5..7  | Max non-member radius  | `nwk_multicast_max_radius`|

`nwk_multicast_control` returns the raw byte; all four accessors return -1
when the multicast flag is clear.

### 3.4 Source route subframe

Relay count (1 byte), relay list (`count` x 2-byte LE addresses,
`nwk_relay`), relay index (1 byte, `nwk_relay_index`). A count whose list
plus index cannot fit in the remaining buffer is
`zigbee: impossible nwk length at byte N` (N = first relay list byte).
`nwk_relay_count` and `nwk_relay_index` are -1 when the subframe is absent.

### 3.5 Payload and command identifiers

The payload span is [payload_off, data.len()). For an unsecured NWK command
frame the first payload byte is the command identifier
(`nwk_command_id`); a command frame without it is
`zigbee: truncated nwk command at byte N`. A secured command frame keeps
`command_id = -1` (the payload is opaque). NWK payload is never decrypted.

| ID   | Name                         |  ID  | Name                        |
|------|------------------------------|------|-----------------------------|
| 0x01 | Route request                | 0x09 | Network report              |
| 0x02 | Route reply                  | 0x0a | Network update              |
| 0x03 | Network status               | 0x0b | End device timeout request  |
| 0x04 | Leave                        | 0x0c | End device timeout response |
| 0x05 | Route record                 | 0x0d | Link power delta            |
| 0x06 | Rejoin request               | 0x0e | Commissioning request       |
| 0x07 | Rejoin response              | 0x0f | Commissioning response      |
| 0x08 | Link status                  | else | Reserved                    |

### 3.6 NWK error catalog

| Message                                        | Trigger |
|------------------------------------------------|---------|
| `zigbee: truncated nwk frame at byte N`        | any header field crosses the buffer end |
| `zigbee: impossible nwk length at byte N`      | source route relay count cannot fit |
| `zigbee: unsupported nwk frame type at byte 0` | frame type 2 or 3 |
| `zigbee: truncated nwk command at byte N`      | unsecured command frame without its identifier byte |
| `zigbee: nwk payload out of bounds at byte N`  | `nwk_payload` with a shorter buffer |

### 3.7 NWK address classification

`nwk_addr_class(addr)`: 0 unicast, 1 broadcast to all devices (`0xFFFF`),
2 low-power routers (`0xFFFB`), 3 routers (`0xFFFC`), 4 rx-on-when-idle
devices (`0xFFFD`), 5 reserved broadcast range (`0xFFF8..0xFFFE`, excluding
the three defined broadcasts). `nwk_is_broadcast` tests `0xFFFF`. Names via
`nwk_addr_class_name`.

## 4. ZigBee APS

### 4.1 Frame control (1 byte)

| Bits  | Field                       | Extraction      |
|-------|-----------------------------|-----------------|
| 0..1  | Frame type                  | `v % 4`         |
| 2..3  | Delivery mode               | `(v / 4) % 4`   |
| 4     | Ack format (2004: indirect) | `(v / 16) % 2`  |
| 5     | Security                    | `(v / 32) % 2`  |
| 6     | Ack request                 | `(v / 64) % 2`  |
| 7     | Extended header present     | `v / 128 == 1`  |

Frame type: 0 data, 1 command, 2 acknowledgement; 3 (inter-PAN) is rejected:
`zigbee: unsupported aps frame type at byte 0`. Delivery mode: 0 unicast,
1 broadcast, 2 group; 3 is rejected:
`zigbee: bad aps delivery mode at byte 0`.

### 4.2 Field presence

Data and command frames:

1. destination endpoint (1) -- only in unicast mode;
2. group address (2, LE) -- only in group mode;
3. cluster identifier (2, LE);
4. profile identifier (2, LE);
5. source endpoint (1);
6. APS counter (1).

Acknowledgement frames: destination endpoint (1), APS counter (1).

### 4.3 Extended header

When bit 7 is set, the first extended-header byte is the fragmentation field
(bits 0..1; 0 none, 1 first, 2 middle, 3 last) and, when fragmentation is
not none, the next byte is the block number. Both are stored
(`aps_ext_frag_bits`, `aps_ext_block`); any further extended-header content
is left in the payload span. Missing bytes are
`zigbee: truncated aps extended header at byte N`.

### 4.4 APS error catalog

| Message                                            | Trigger |
|----------------------------------------------------|---------|
| `zigbee: truncated aps frame at byte N`            | a header field crosses the buffer end |
| `zigbee: truncated aps extended header at byte N`  | fragmentation or block byte missing |
| `zigbee: unsupported aps frame type at byte 0`     | frame type 3 |
| `zigbee: bad aps delivery mode at byte 0`          | delivery mode 3 |
| `zigbee: aps payload out of bounds at byte N`      | `aps_payload` with a shorter buffer |

### 4.5 APS group classification

`aps_group_class(addr)`: 0 reserved (`0x0000`), 1 assignable group
(`0x0001..0xFFF7`, the ZigBee group range), 2 reserved range
(`0xFFF8..0xFFFE`), 3 broadcast group (`0xFFFF`, "all groups"), 4 out of
range (negative or above `0xFFFF`). Names via `aps_group_class_name`.

## 5. API index

Parsers: `mac_parse`, `nwk_parse`, `aps_parse`.
Span extraction: `mac_payload`, `mac_fcs_bytes`, `mac_fcs_value`,
`nwk_payload`, `aps_payload`.
Version marker: `zigbee_version` (1).
MAC accessors: `mac_frame_type`, `mac_security_enabled`, `mac_frame_pending`,
`mac_ack_request`, `mac_pan_compression`, `mac_reserved_bits`,
`mac_frame_version`, `mac_dest_mode`, `mac_src_mode`, `mac_seq`,
`mac_dest_pan`, `mac_src_pan`, `mac_dest_short`, `mac_src_short`,
`mac_dest_ext_byte`, `mac_src_ext_byte`, `mac_dest_ext_len`,
`mac_src_ext_len`, `mac_aux_security_present`, `mac_aux_security_off`,
`mac_header_len`, `mac_payload_off`, `mac_payload_len`, `mac_fcs_off`,
`mac_consumed`, `mac_beacon_order`, `mac_superframe_order`,
`mac_final_cap_slot`, `mac_battery_life`, `mac_pan_coordinator`,
`mac_assoc_permit`, `mac_gts_permit`, `mac_gts_count`, `mac_gts_addr`,
`mac_gts_start_slot`, `mac_gts_length`, `mac_pending_short_count`,
`mac_pending_ext_count`, `mac_pending_short`, `mac_pending_ext_byte`,
`mac_beacon_end`, `mac_command_id`, `mac_command_data_off`,
`mac_command_data_len`, `mac_command_name`, `mac_frame_type_name`,
`mac_addr_mode_name`, `mac_frame_version_name`, `mac_short_class`,
`mac_short_class_name`, `mac_short_is_broadcast`.
NWK accessors: `nwk_frame_type`, `nwk_frame_type_name`,
`nwk_protocol_version`, `nwk_discover_route`, `nwk_multicast`,
`nwk_security_enabled`, `nwk_source_route`, `nwk_dest_ieee_present`,
`nwk_src_ieee_present`, `nwk_end_device_initiator`, `nwk_dest`, `nwk_src`,
`nwk_radius`, `nwk_seq`, `nwk_dest_ext_byte`, `nwk_src_ext_byte`,
`nwk_dest_ext_len`, `nwk_src_ext_len`, `nwk_multicast_control`,
`nwk_multicast_mode`, `nwk_multicast_radius`, `nwk_multicast_max_radius`,
`nwk_relay_count`, `nwk_relay`, `nwk_relay_index`, `nwk_command_id`,
`nwk_command_name`, `nwk_header_len`, `nwk_payload_off`, `nwk_payload_len`,
`nwk_consumed`, `nwk_addr_class`, `nwk_addr_class_name`, `nwk_is_broadcast`.
APS accessors: `aps_frame_type`, `aps_frame_type_name`, `aps_delivery_mode`,
`aps_delivery_name`, `aps_ack_format`, `aps_security_enabled`,
`aps_ack_request`, `aps_ext_header_present`, `aps_dest_endpoint`,
`aps_group_addr`, `aps_cluster_id`, `aps_profile_id`, `aps_src_endpoint`,
`aps_counter`, `aps_ext_frag_bits`, `aps_ext_block`, `aps_header_len`,
`aps_payload_off`, `aps_payload_len`, `aps_consumed`, `aps_group_class`,
`aps_group_class_name`.

## 6. Test plan

`tests/test_conformance.xi` (26 checks, all synthetic buffers built in-test):

1. MAC data frame, short addressing, every field pinned.
2. PAN ID compression (source PAN echoed, byte count).
3. Extended addresses (both directions, byte values >= 0x80).
4. Acknowledgement frame.
5. MAC command frame, command identifier table and data span.
6. Beacon: superframe spec, GTS descriptor, pending short/extended addresses.
7. Secured frame: opaque auxiliary security header, beacon/command skipped.
8. Rejections: bad addressing modes, frame types 4..7, FCF bits 8/9.
9. Truncation: every short prefix rejected, exact offsets, short-header case.
10. Impossible beacon GTS/pending counts.
11. Sentinel accessors (-1) and out-of-bounds span extraction.
12. MAC names and short-address classes.
13. NWK data frame.
14. NWK command frame with IEEE addresses, multicast control and source route.
15. NWK rejections: types 2/3, short-header truncation, relay overflow,
    missing command id.
16. NWK names and broadcast address classes.
17. NWK payload bounds and secured command frames.
18. APS unicast data frame.
19. APS broadcast frame (no destination endpoint).
20. APS group frame (group address present).
21. APS acknowledgement frame.
22. APS frame control flags (ack format, security, ack request).
23. APS extended header fragmentation + block number.
24. APS rejections: type 3, delivery 3, truncation, extended-header
    truncation, payload bounds.
25. APS names and group address classes.
26. Cross-layer MAC -> NWK -> APS parse chain plus FCS accessor.

## 7. Caveats and non-goals

* The FCS is never verified; a frame with a wrong FCS still parses.
* AES-CCM* security is not implemented; secured payloads stay opaque and
  are reported as such.
* 802.15.4-2015 header IEs and payload IEs, sequence-number suppression,
  multipurpose/fragment/extended frame types and information-element
  addressing are out of scope (rejected or unsupported by construction).
* Beacon frames are only decoded when unsecured; a secured beacon keeps
  `beacon_*` = -1.
* MAC command payloads and NWK/APS command payloads are returned as raw
  spans; their internal structure is out of scope.
* APS extended headers are decoded only for the fragmentation field; other
  extended-header content remains in the payload span.
* The APS source endpoint is treated as present for every data/command
  frame (unicast, broadcast and group) and absent for acknowledgements.
* Input must be a single frame; concatenated frames are not split (there is
  no length field to split on without FCS verification or PHY metadata).
