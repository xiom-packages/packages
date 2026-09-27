# xiom.gpio

> **Status:** IMPLEMENTED -- harness-green with compiler v0.61.3
> (`port: PASS (passed=21 failed=0)`).
> **Scope:** pure-XIOM structure codec for the Linux GPIO character-device
> uAPI v2 (`include/uapi/linux/gpio.h`): `gpiochip_info`, the v2 line flags,
> attributes, config, line info, line requests, line events and the
> bits/mask pair. No device access, no ioctl, no file I/O, no FFI.
> **Deps:** `xiom.std` (the library module imports `xiom.convert`,
> `xiom.string` and `xiom.string.builder`).

## What it is

`xiom.gpio` encodes and decodes the fixed-size structures that the Linux
GPIO character device exchanges through `/dev/gpiochip*` ioctls and `read`,
so callers can build requests and inspect kernel results without touching
the device layer:

- `gpiochip_info` (68 bytes) -- chip name/label C strings and line count;
- `gpio_v2_line_info` (256 bytes) -- name, consumer, line offset, the flag
  bitmap and the attribute array;
- `gpio_v2_line_attribute` (16 bytes) and `gpio_v2_line_config`
  (272 bytes) -- the FLAGS, OUTPUT_VALUES and DEBOUNCE attribute kinds;
- `gpio_v2_line_request` (592 bytes) -- offsets, consumer, config,
  num_lines, event_buffer_size and fd, encode and decode;
- `gpio_v2_line_event` (48 bytes) -- 64-bit timestamps, event id and both
  sequence numbers;
- `gpio_v2_line_values` (16 bytes) -- the bits/mask pair used for default
  output values (the v2 form of the old `default_values` array).

The layout is explicitly little-endian. The real ioctl interface passes the
structs in native byte order; this package fixes one layout so buffers are
portable between build and test hosts. Every decoder validates the exact
size, rejects nonzero padding and returns `Err(Str)` messages that carry the
byte offset of the offending field.

The v2 line flags implemented are bits 0..12: `USED`, `ACTIVE_LOW`,
`INPUT`, `OUTPUT`, `EDGE_RISING`, `EDGE_FALLING`, `OPEN_DRAIN`,
`OPEN_SOURCE`, `BIAS_PULL_UP`, `BIAS_PULL_DOWN`, `BIAS_DISABLED`,
`EVENT_CLOCK_REALTIME`, `EVENT_CLOCK_HTE`. The uAPI has no REQUESTED line
flag; `REQUESTED` is the line-changed event type
`GPIO_V2_LINE_CHANGED_REQUESTED` (1), exposed by
`gpio_line_changed_type_name` with `RELEASED` and `CONFIG`.

## API

| Function | Returns | Description |
|---|---|---|
| `gpio_chip_info_decode(data)` | `Result[GpioChipInfo, Str]` | Decode 68 bytes; name/label trimmed at the first NUL. |
| `gpio_chip_info_encode(info)` | `Result[Vec[UInt8], Str]` | Encode a fresh 68-byte image. |
| `gpio_chip_info_encode_into(out, info)` | `Result[Unit, Str]` | Append 68 bytes atomically. |
| `gpio_name_decode(data, off)` | `Result[Str, Str]` | Decode one 32-byte C string field. |
| `gpio_name_encode_into(out, name)` | `Result[Unit, Str]` | Append one 32-byte C string field. |
| `gpio_name_fits(name)` / `gpio_consumer_name_ok(name)` | `Bool` | `<= 31` bytes (plus NUL) / also NUL-free. |
| `gpio_line_flag_set(flags, flag)` | `Bool` | Per-line flag query (division/modulo, no sign-bit ops). |
| `gpio_line_flags_decode(flags)` | `Vec[Int]` | Set flag constants, lowest bit first. |
| `gpio_line_flags_known(flags)` / `gpio_line_flags_unknown(flags)` | `Int` | Split bits 0..12 from bits 13+. |
| `gpio_line_flag_name(flag)` | `Str` | `"input"`, `"edge_rising"`, ... |
| `gpio_attr_id_name(id)` | `Str` | `"flags"`, `"output_values"`, `"debounce"`. |
| `gpio_line_changed_type_name(t)` | `Str` | `"requested"`, `"released"`, `"config"`. |
| `gpio_event_type_name(t)` | `Str` | `"rising edge"`, `"falling edge"`. |
| `gpio_line_attribute_decode(data, off)` | `Result[GpioLineAttribute, Str]` | Decode one 16-byte attribute. |
| `gpio_line_attribute_encode_into(out, id, value)` | `Result[Unit, Str]` | Append one 16-byte attribute. |
| `gpio_line_config_decode(data)` | `Result[GpioLineConfig, Str]` | Decode 272 bytes. |
| `gpio_line_config_encode(cfg)` | `Result[Vec[UInt8], Str]` | Encode a fresh 272-byte image. |
| `gpio_line_config_encode_into(out, cfg)` | `Result[Unit, Str]` | Append 272 bytes atomically. |
| `gpio_line_config_new()` | `GpioLineConfig` | Empty config. |
| `gpio_line_config_set_flags(cfg, flags)` | `Result[Unit, Str]` | Set default flags. |
| `gpio_line_config_add_attr(cfg, id, value, mask)` | `Result[Unit, Str]` | Mirrored attribute push. |
| `gpio_line_request_decode(data)` | `Result[GpioLineRequest, Str]` | Decode 592 bytes. |
| `gpio_line_request_encode(req)` | `Result[Vec[UInt8], Str]` | Encode a fresh 592-byte image. |
| `gpio_line_request_encode_into(out, req)` | `Result[Unit, Str]` | Append 592 bytes atomically. |
| `gpio_line_request_new()` | `GpioLineRequest` | Empty request. |
| `gpio_line_request_add_offset(req, offset)` | `Result[Unit, Str]` | Append an offset and bump `num_lines`. |
| `gpio_line_request_set_consumer(req, name)` | `Result[Unit, Str]` | Set the consumer name. |
| `gpio_line_request_set_config_flags(req, flags)` | `Result[Unit, Str]` | Set the default config flags. |
| `gpio_line_info_decode(data)` | `Result[GpioLineInfo, Str]` | Decode 256 bytes. |
| `gpio_line_info_encode(info)` | `Result[Vec[UInt8], Str]` | Encode a fresh 256-byte image. |
| `gpio_line_info_encode_into(out, info)` | `Result[Unit, Str]` | Append 256 bytes atomically. |
| `gpio_line_event_decode(data)` | `Result[GpioLineEvent, Str]` | Decode 48 bytes. |
| `gpio_line_event_encode(ev)` | `Result[Vec[UInt8], Str]` | Encode a fresh 48-byte image. |
| `gpio_line_event_encode_into(out, ev)` | `Result[Unit, Str]` | Append 48 bytes atomically. |
| `gpio_line_values_decode(data)` | `Result[GpioLineValues, Str]` | Decode 16 bytes. |
| `gpio_line_values_encode(values)` | `Result[Vec[UInt8], Str]` | Encode a fresh 16-byte image. |
| `gpio_line_values_encode_into(out, values)` | `Result[Unit, Str]` | Append 16 bytes atomically. |
| `gpio_attr_id_ok`, `gpio_num_attrs_ok`, `gpio_num_lines_ok`, `gpio_event_type_ok` | `Bool` | Range predicates. |
| `gpio_attr_offset_aligned(off)` / `gpio_attr_fits(off, len)` | `Bool` | Attribute alignment and size checks. |
| `gpio_u32_to_i32(v)` | `Int` | Signed view of a raw u32 image such as `fd`. |

## Usage example

Decode a `gpiochip_info` image read from `/dev/gpiochip0` (the file I/O is
the caller's job):

```xi
use xiom.gpio;

let r = gpio_chip_info_decode(&buf);        // buf holds 68 bytes
if r.is_ok {
  let c: GpioChipInfo = r.value;
  io.println(c.name + " (" + c.label + "): " + int_to_string(c.lines) + " lines");
}
```

Build a line request for two inputs with rising-edge events and a 5 ms
debounce (then feed the bytes to `GPIO_V2_GET_LINE_IOCTL` yourself):

```xi
use xiom.gpio;

var req = gpio_line_request_new();
gpio_line_request_add_offset(&mut req, 3);
gpio_line_request_add_offset(&mut req, 17);
gpio_line_request_set_consumer(&mut req, "xiom-gpio-demo");
gpio_line_request_set_config_flags(&mut req, GPIO_V2_LINE_FLAG_INPUT + GPIO_V2_LINE_FLAG_EDGE_RISING);
req.attr_ids.push(GPIO_V2_LINE_ATTR_ID_DEBOUNCE);
req.attr_values.push(5000);
req.attr_masks.push(3);
req.event_buffer_size = 16;

let e = gpio_line_request_encode(&req);
if e.is_ok {
  let bytes: Vec[UInt8] = e.value;          // 592 bytes, ready for the ioctl
}
```

Decode one event read back from the request fd:

```xi
let er = gpio_line_event_decode(&evbuf);
if er.is_ok {
  let ev: GpioLineEvent = er.value;
  io.println(gpio_event_type_name(ev.event_type) + " on line " + int_to_string(ev.line_offset));
}
```

## Tests

```
xiom --run tests/test_conformance.xi
```

21 checks, all `[PASS]`, exit 0. They build every synthetic buffer in-test
(byte by byte or from pinned hex) and cross-check decode, encode
round-trips, flag matrices, 64-bit timestamps, padding/offset errors and
truncation.

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.gpio
```

## Install / publish

```
xiom pkg install xiom.gpio@0.1.0     # consumer
xiom pkg publish                      # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
