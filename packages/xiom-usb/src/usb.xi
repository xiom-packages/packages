// XIOM -- xiom.usb: USB descriptor-tree parsing, validation and canonical emission
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM (no FFI) codec for USB descriptor streams (USB 2.0 / USB 3.x
// BOS subset). A stream is a sequence of descriptors, each self-described by
// bLength and bDescriptorType. usb_parse walks it, validates it and returns
// a flat Usb store built from parallel vectors (no Vec[StructType]): every
// descriptor keeps its absolute span, plus per-entity parallel vectors with
// parent links (configuration -> interface -> endpoint) and a string-
// descriptor pool. usb_emit rebuilds the canonical stream.
//
// Structured descriptors (the documented subset):
//   * DEVICE (0x01, exactly 18 bytes);
//   * CONFIGURATION (0x02, exactly 9 bytes; wTotalLength must cover the
//     configuration's children exactly);
//   * INTERFACE (0x04, exactly 9 bytes; must sit inside a configuration);
//   * ENDPOINT (0x05, exactly 7 bytes; must sit inside an interface; the
//     actual count may be less than or equal to bNumEndpoints -- the claim --
//     but may never exceed it);
//   * STRING (0x03, even bLength >= 4 whose first code unit is
//     bStringIndex; UTF-16LE code units are decoded to
//     printable ASCII with a documented replacement policy: units 0x0020
//     through 0x007E map to themselves, every other unit becomes '?').
// Raw-preserved descriptors (span + header accessors only, bytes never
// interpreted):
//   * DEVICE_QUALIFIER (0x06);
//   * BOS (0x0F) with wTotalLength and bNumDeviceCaps;
//   * DEVICE_CAPABILITY (0x10) as raw capability spans;
//   * every other unknown bDescriptorType.
// Non-goals: HID report descriptor interpretation, class-specific descriptor
// semantics, transfers/speed negotiation.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no self methods; state travels by reference.
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing struct payloads such as Result[Usb, Str] directly in
//     other functions miscompiles).
//   * every byte read from a Vec[UInt8] is widened with `(b as Int) & 0xFF`
//     before entering Int arithmetic.
//   * every Vec[Int] element read is bound to a typed local, and Str values
//     read from Vec[Str] are bound to typed locals before use (BUG 17:
//     `==` on a Str read from a Vec lowers to a pointer comparison).
//   * every push on one parallel vector is mirrored on all its siblings;
//     usb_emit refuses stores whose parallel vectors have drifted apart
//     ("usb: invalid store").
//   * decoded strings never contain 0x00, so
//     xiom.string.builder.sb_to_str never sees a NUL byte.

module xiom.usb

use xiom.string;
use xiom.string.builder;

/// Descriptor type: DEVICE.
pub const USB_DESC_DEVICE: Int = 1;
/// Descriptor type: CONFIGURATION.
pub const USB_DESC_CONFIGURATION: Int = 2;
/// Descriptor type: STRING.
pub const USB_DESC_STRING: Int = 3;
/// Descriptor type: INTERFACE.
pub const USB_DESC_INTERFACE: Int = 4;
/// Descriptor type: ENDPOINT.
pub const USB_DESC_ENDPOINT: Int = 5;
/// Descriptor type: DEVICE_QUALIFIER (raw-preserved).
pub const USB_DESC_DEVICE_QUALIFIER: Int = 6;
/// Descriptor type: BOS (raw-preserved; USB 2.0 ECN / USB 3.x).
pub const USB_DESC_BOS: Int = 15;
/// Descriptor type: DEVICE_CAPABILITY (raw-preserved; BOS child).
pub const USB_DESC_DEVICE_CAPABILITY: Int = 16;

/// Flat USB descriptor store. Every descriptor in the stream occupies one
/// entry in the global `desc_type`/`desc_off`/`desc_len` vectors, in stream
/// order; `desc_off` is the absolute offset of its bLength byte inside the
/// parse buffer. Structured descriptors additionally appear in their entity
/// vectors:
///   * device: `device_desc` is the global index (-1 when absent) plus the
///     18-byte DEVICE fields;
///   * configurations: `cfg_desc[i]` is the global index and `cfg_*[i]` the
///     9-byte CONFIGURATION fields (wTotalLength, bNumInterfaces,
///     bConfigurationValue, iConfiguration, bmAttributes, bMaxPower);
///   * interfaces: `if_desc[i]` is the global index and `if_config[i]` the
///     owning configuration ordinal; the rest are the 9-byte INTERFACE
///     fields (bNumEndpoints is the endpoint claim);
///   * endpoints: `ep_desc[e]` is the global index and `ep_interface[e]` the
///     owning interface ordinal; the rest are the 7-byte ENDPOINT fields;
///   * strings: `str_desc[i]` is the global index, `str_id[i]` the
///     bStringIndex, `str_text[i]` the decoded printable-ASCII text and
///     `str_replaced[i]` the number of code units replaced by '?';
///   * raw: `raw_desc[i]` lists the global indices of every raw-preserved
///     descriptor in stream order.
/// Fields are implementation details; callers must go through the free
/// functions below. The store holds spans into the source buffer, not
/// copies.
pub type Usb = {
  desc_type: Vec[Int];
  desc_off: Vec[Int];
  desc_len: Vec[Int];
  device_desc: Int;
  dev_bcd_usb: Int;
  dev_class: Int;
  dev_subclass: Int;
  dev_protocol: Int;
  dev_max_packet0: Int;
  dev_vendor: Int;
  dev_product: Int;
  dev_bcd_device: Int;
  dev_imanufacturer: Int;
  dev_iproduct: Int;
  dev_iserial: Int;
  dev_num_configs: Int;
  cfg_desc: Vec[Int];
  cfg_total_len: Vec[Int];
  cfg_num_interfaces: Vec[Int];
  cfg_value: Vec[Int];
  cfg_istring: Vec[Int];
  cfg_attrs: Vec[Int];
  cfg_max_power: Vec[Int];
  if_desc: Vec[Int];
  if_config: Vec[Int];
  if_number: Vec[Int];
  if_alt: Vec[Int];
  if_endpoint_claim: Vec[Int];
  if_class: Vec[Int];
  if_subclass: Vec[Int];
  if_protocol: Vec[Int];
  if_istring: Vec[Int];
  ep_desc: Vec[Int];
  ep_interface: Vec[Int];
  ep_address: Vec[Int];
  ep_attrs: Vec[Int];
  ep_max_packet: Vec[Int];
  ep_interval: Vec[Int];
  str_desc: Vec[Int];
  str_id: Vec[Int];
  str_text: Vec[Str];
  str_replaced: Vec[Int];
  raw_desc: Vec[Int];
}

// --------------------------------------------------
//  Result leaf constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Usb, Str].
fn _ok_usb(v: Usb) -> Result[Usb, Str] {
  return Ok(v);
}

// Err(m) for Result[Usb, Str].
fn _err_usb(m: Str) -> Result[Usb, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned little-endian Int of the `size` bytes at `pos`. The caller
// guarantees pos + size <= data.len().
fn _read_le(data: &Vec[UInt8], pos: Int, size: Int) -> Int {
  var v: Int = 0;
  var i = size - 1;
  while i >= 0 {
    v = v * 256 + _byte(data, pos + i);
    i = i - 1;
  }
  return v;
}

// Byte `shift` of `v` counting from the least significant byte. Arithmetic
// only: `& 0xFF` on values with bit 31 set miscompiles in v0.61.3, and this
// form is exact for negative two's-complement values.
fn _u_byte(v: Int, shift: Int) -> UInt8 {
  var q = v;
  var k = 0;
  while k < shift {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    k = k + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append the low `size` bytes of `v` in little-endian order.
fn _push_le(out: &mut Vec[UInt8], v: Int, size: Int) {
  var i = 0;
  while i < size {
    out.push(_u_byte(v, i));
    i = i + 1;
  }
}

// Append the bytes of `v`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// A single UTF-16LE code unit maps to itself only inside the printable
// ASCII range; everything else is replaced by '?'.
fn _is_printable_unit(unit: Int) -> Bool {
  if unit < 32 { return false; }
  if unit > 126 { return false; }
  return true;
}

// Decode a STRING descriptor payload (starting at bLength) into printable
// ASCII. `blen` is even and >= 4; the first code unit is bStringIndex and
// is not text. Non-printable units (including control bytes and both halves
// of a surrogate pair) each become one '?'.
fn _decode_text(data: &Vec[UInt8], off: Int, blen: Int) -> Str {
  var sb = Vec[UInt8].new();
  let units = (blen - 4) / 2;
  var i = 0;
  while i < units {
    let unit = _read_le(data, off + 4 + i * 2, 2);
    if _is_printable_unit(unit) {
      sb.push(unit as UInt8);
    } else {
      sb.push(63 as UInt8);
    }
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Number of code units replaced by '?' in a STRING descriptor payload (the
// bStringIndex unit is not text and is not counted).
fn _count_replaced(data: &Vec[UInt8], off: Int, blen: Int) -> Int {
  var n = 0;
  let units = (blen - 4) / 2;
  var i = 0;
  while i < units {
    let unit = _read_le(data, off + 4 + i * 2, 2);
    if !_is_printable_unit(unit) {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

// Byte-range predicates used by the emitter's well-formedness guard.
fn _is_byte(v: Int) -> Bool {
  if v < 0 { return false; }
  if v > 255 { return false; }
  return true;
}

fn _is_word(v: Int) -> Bool {
  if v < 0 { return false; }
  if v > 65535 { return false; }
  return true;
}

// --------------------------------------------------
//  Store construction
// --------------------------------------------------

// An empty Usb store (no device, no descriptors).
fn _usb_new() -> Usb {
  return Usb{
    desc_type: Vec[Int].new();
    desc_off: Vec[Int].new();
    desc_len: Vec[Int].new();
    device_desc: -1;
    dev_bcd_usb: 0;
    dev_class: 0;
    dev_subclass: 0;
    dev_protocol: 0;
    dev_max_packet0: 0;
    dev_vendor: 0;
    dev_product: 0;
    dev_bcd_device: 0;
    dev_imanufacturer: 0;
    dev_iproduct: 0;
    dev_iserial: 0;
    dev_num_configs: 0;
    cfg_desc: Vec[Int].new();
    cfg_total_len: Vec[Int].new();
    cfg_num_interfaces: Vec[Int].new();
    cfg_value: Vec[Int].new();
    cfg_istring: Vec[Int].new();
    cfg_attrs: Vec[Int].new();
    cfg_max_power: Vec[Int].new();
    if_desc: Vec[Int].new();
    if_config: Vec[Int].new();
    if_number: Vec[Int].new();
    if_alt: Vec[Int].new();
    if_endpoint_claim: Vec[Int].new();
    if_class: Vec[Int].new();
    if_subclass: Vec[Int].new();
    if_protocol: Vec[Int].new();
    if_istring: Vec[Int].new();
    ep_desc: Vec[Int].new();
    ep_interface: Vec[Int].new();
    ep_address: Vec[Int].new();
    ep_attrs: Vec[Int].new();
    ep_max_packet: Vec[Int].new();
    ep_interval: Vec[Int].new();
    str_desc: Vec[Int].new();
    str_id: Vec[Int].new();
    str_text: Vec[Str].new();
    str_replaced: Vec[Int].new();
    raw_desc: Vec[Int].new();
  };
}

// Record one descriptor in the global vectors and return its global index.
fn _add_descriptor(u: &mut Usb, desc_type: Int, off: Int, len: Int) -> Int {
  let idx = u.desc_type.len();
  u.desc_type.push(desc_type);
  u.desc_off.push(off);
  u.desc_len.push(len);
  return idx;
}

// Append one configuration; every parallel configuration vector receives
// exactly one push here.
fn _add_config(u: &mut Usb, desc: Int, total: Int, num_if: Int, value: Int, istring: Int, attrs: Int, max_power: Int) {
  u.cfg_desc.push(desc);
  u.cfg_total_len.push(total);
  u.cfg_num_interfaces.push(num_if);
  u.cfg_value.push(value);
  u.cfg_istring.push(istring);
  u.cfg_attrs.push(attrs);
  u.cfg_max_power.push(max_power);
}

// Append one interface; every parallel interface vector receives exactly
// one push here.
fn _add_interface(u: &mut Usb, desc: Int, config: Int, number: Int, alt: Int, claim: Int, cls: Int, subclass: Int, protocol: Int, istring: Int) {
  u.if_desc.push(desc);
  u.if_config.push(config);
  u.if_number.push(number);
  u.if_alt.push(alt);
  u.if_endpoint_claim.push(claim);
  u.if_class.push(cls);
  u.if_subclass.push(subclass);
  u.if_protocol.push(protocol);
  u.if_istring.push(istring);
}

// Append one endpoint; every parallel endpoint vector receives exactly one
// push here.
fn _add_endpoint(u: &mut Usb, desc: Int, owner: Int, address: Int, attrs: Int, max_packet: Int, interval: Int) {
  u.ep_desc.push(desc);
  u.ep_interface.push(owner);
  u.ep_address.push(address);
  u.ep_attrs.push(attrs);
  u.ep_max_packet.push(max_packet);
  u.ep_interval.push(interval);
}

// Append one string-pool entry; every parallel string vector receives
// exactly one push here.
fn _add_string(u: &mut Usb, desc: Int, id: Int, text: Str, replaced: Int) {
  u.str_desc.push(desc);
  u.str_id.push(id);
  u.str_text.push(text);
  u.str_replaced.push(replaced);
}

// Does the string pool contain bStringIndex `sid`? Index 0 ("no string") is
// always valid.
fn _string_ok(u: &Usb, sid: Int) -> Bool {
  if sid == 0 { return true; }
  var i = 0;
  while i < u.str_id.len() {
    let v: Int = u.str_id[i];
    if v == sid { return true; }
    i = i + 1;
  }
  return false;
}

// Pool ordinal of the first string descriptor with bStringIndex `sid`, or
// -1 when absent.
fn _string_pool(u: &Usb, sid: Int) -> Int {
  var i = 0;
  while i < u.str_id.len() {
    let v: Int = u.str_id[i];
    if v == sid { return i; }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Parser
// --------------------------------------------------

/// Parse and fully validate a USB descriptor stream.
///
/// On success the returned Usb stores spans into `data` (every descriptor,
/// plus the string payloads) and the decoded string texts; the source buffer
/// must stay alive for the span accessors and usb_emit. Validation covers:
/// bLength >= 2 and inside the buffer; the exact per-type descriptor lengths
/// (DEVICE 18, CONFIGURATION 9, INTERFACE 9, ENDPOINT 7, STRING even >= 4
/// with bStringIndex as its first code unit);
/// configuration wTotalLength in range and covering the configuration's
/// children exactly (no gap, no overrun); interfaces inside a configuration;
/// endpoints inside an interface; the endpoint count never exceeding the
/// interface's bNumEndpoints claim; and every nonzero string index of the
/// device, configurations and interfaces resolving to a STRING descriptor in
/// the pool. Unknown descriptor types are preserved raw and never
/// interpreted. An empty buffer yields Ok with an empty store.
///
/// Errors (all `"usb: ..."`): `truncated descriptor header`,
/// `bad descriptor length`, `truncated descriptor`,
/// `duplicate device descriptor`, `bad device descriptor length`,
/// `bad configuration descriptor length`, `bad interface descriptor length`,
/// `bad endpoint descriptor length`, `bad string descriptor length`,
/// `configuration total length out of range`,
/// `configuration total length mismatch`, `interface outside configuration`,
/// `endpoint outside interface`, `endpoint count exceeds interface claim`,
/// `string index out of range`.
/// Complexity: O(data.len()).
pub fn usb_parse(data: &Vec[UInt8]) -> Result[Usb, Str] {
  var u = _usb_new();
  let total = data.len();
  var pos = 0;
  var cur_cfg = -1;
  var cur_if = -1;
  var cfg_end = -1;
  var ep_seen = 0;
  while pos < total {
    if pos + 2 > total {
      return _err_usb("usb: truncated descriptor header");
    }
    let blen = _byte(data, pos);
    let btype = _byte(data, pos + 1);
    if blen < 2 {
      return _err_usb("usb: bad descriptor length");
    }
    if pos + blen > total {
      return _err_usb("usb: truncated descriptor");
    }
    // Close a configuration whose declared wTotalLength has been reached,
    // and reject any child that would spill past it.
    if cur_cfg >= 0 {
      if pos > cfg_end {
        return _err_usb("usb: configuration total length mismatch");
      }
      if pos == cfg_end {
        cur_cfg = -1;
        cur_if = -1;
      }
    }
    if cur_cfg >= 0 && pos + blen > cfg_end {
      return _err_usb("usb: configuration total length mismatch");
    }
    if btype == USB_DESC_CONFIGURATION && cur_cfg >= 0 {
      // A second CONFIGURATION inside an open configuration range means the
      // first one's wTotalLength never closed exactly.
      return _err_usb("usb: configuration total length mismatch");
    }
    let idx = _add_descriptor(&mut u, btype, pos, blen);
    if btype == USB_DESC_DEVICE {
      if u.device_desc >= 0 {
        return _err_usb("usb: duplicate device descriptor");
      }
      if blen != 18 {
        return _err_usb("usb: bad device descriptor length");
      }
      u.device_desc = idx;
      u.dev_bcd_usb = _read_le(data, pos + 2, 2);
      u.dev_class = _byte(data, pos + 4);
      u.dev_subclass = _byte(data, pos + 5);
      u.dev_protocol = _byte(data, pos + 6);
      u.dev_max_packet0 = _byte(data, pos + 7);
      u.dev_vendor = _read_le(data, pos + 8, 2);
      u.dev_product = _read_le(data, pos + 10, 2);
      u.dev_bcd_device = _read_le(data, pos + 12, 2);
      u.dev_imanufacturer = _byte(data, pos + 14);
      u.dev_iproduct = _byte(data, pos + 15);
      u.dev_iserial = _byte(data, pos + 16);
      u.dev_num_configs = _byte(data, pos + 17);
    } elif btype == USB_DESC_CONFIGURATION {
      if blen != 9 {
        return _err_usb("usb: bad configuration descriptor length");
      }
      let wtotal = _read_le(data, pos + 2, 2);
      if wtotal < 9 || pos + wtotal > total {
        return _err_usb("usb: configuration total length out of range");
      }
      cur_cfg = u.cfg_desc.len();
      cur_if = -1;
      cfg_end = pos + wtotal;
      _add_config(&mut u, idx, wtotal, _byte(data, pos + 4), _byte(data, pos + 5), _byte(data, pos + 6), _byte(data, pos + 7), _byte(data, pos + 8));
    } elif btype == USB_DESC_INTERFACE {
      if blen != 9 {
        return _err_usb("usb: bad interface descriptor length");
      }
      if cur_cfg < 0 {
        return _err_usb("usb: interface outside configuration");
      }
      cur_if = u.if_desc.len();
      ep_seen = 0;
      _add_interface(&mut u, idx, cur_cfg, _byte(data, pos + 2), _byte(data, pos + 3), _byte(data, pos + 4), _byte(data, pos + 5), _byte(data, pos + 6), _byte(data, pos + 7), _byte(data, pos + 8));
    } elif btype == USB_DESC_ENDPOINT {
      if blen != 7 {
        return _err_usb("usb: bad endpoint descriptor length");
      }
      if cur_if < 0 {
        return _err_usb("usb: endpoint outside interface");
      }
      ep_seen = ep_seen + 1;
      let claim: Int = u.if_endpoint_claim[cur_if];
      if ep_seen > claim {
        return _err_usb("usb: endpoint count exceeds interface claim");
      }
      _add_endpoint(&mut u, idx, cur_if, _byte(data, pos + 2), _byte(data, pos + 3), _read_le(data, pos + 4, 2), _byte(data, pos + 6));
    } elif btype == USB_DESC_STRING {
      if blen % 2 != 0 || blen < 4 {
        return _err_usb("usb: bad string descriptor length");
      }
      _add_string(&mut u, idx, _byte(data, pos + 2), _decode_text(data, pos, blen), _count_replaced(data, pos, blen));
    } else {
      u.raw_desc.push(idx);
    }
    pos = pos + blen;
  }
  if cur_cfg >= 0 && pos != cfg_end {
    return _err_usb("usb: configuration total length mismatch");
  }
  // String index bounds: every nonzero reference must resolve in the pool.
  if u.device_desc >= 0 {
    if !_string_ok(&u, u.dev_imanufacturer) {
      return _err_usb("usb: string index out of range");
    }
    if !_string_ok(&u, u.dev_iproduct) {
      return _err_usb("usb: string index out of range");
    }
    if !_string_ok(&u, u.dev_iserial) {
      return _err_usb("usb: string index out of range");
    }
  }
  var c = 0;
  while c < u.cfg_desc.len() {
    let sid: Int = u.cfg_istring[c];
    if !_string_ok(&u, sid) {
      return _err_usb("usb: string index out of range");
    }
    c = c + 1;
  }
  var i = 0;
  while i < u.if_desc.len() {
    let sid2: Int = u.if_istring[i];
    if !_string_ok(&u, sid2) {
      return _err_usb("usb: string index out of range");
    }
    i = i + 1;
  }
  return _ok_usb(u);
}

// --------------------------------------------------
//  Descriptor accessors
// --------------------------------------------------

/// Number of descriptors in the stream (structured plus raw-preserved).
pub fn usb_descriptor_count(u: &Usb) -> Int {
  return u.desc_type.len();
}

/// bDescriptorType of descriptor `i`, or -1 for an out-of-range index.
pub fn usb_descriptor_type(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.desc_type.len() {
    return -1;
  }
  let v: Int = u.desc_type[i];
  return v;
}

/// bLength of descriptor `i`, or -1 for an out-of-range index.
pub fn usb_descriptor_length(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.desc_len.len() {
    return -1;
  }
  let v: Int = u.desc_len[i];
  return v;
}

/// Absolute offset of descriptor `i`'s bLength byte in the parse buffer, or
/// -1 for an out-of-range index.
pub fn usb_descriptor_offset(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.desc_off.len() {
    return -1;
  }
  let v: Int = u.desc_off[i];
  return v;
}

/// Copy the raw bytes of descriptor `i` out of `data` (bLength bytes,
/// header included).
/// Err("usb: descriptor index out of range") for a bad index and
/// Err("usb: descriptor span out of bounds") when the recorded span does not
/// fit `data`.
pub fn usb_descriptor_bytes(data: &Vec[UInt8], u: &Usb, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= u.desc_type.len() {
    return _err_bytes("usb: descriptor index out of range");
  }
  let off: Int = u.desc_off[i];
  let len: Int = u.desc_len[i];
  if off < 0 || len < 0 || off + len > data.len() {
    return _err_bytes("usb: descriptor span out of bounds");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < len {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

// --------------------------------------------------
//  Device accessors
// --------------------------------------------------

/// True when the stream contained a DEVICE descriptor.
pub fn usb_has_device(u: &Usb) -> Bool {
  return u.device_desc >= 0;
}

/// bcdUSB of the DEVICE descriptor (0x0200 = USB 2.0), or -1 when absent.
pub fn usb_device_bcd_usb(u: &Usb) -> Int {
  if u.device_desc < 0 { return -1; }
  return u.dev_bcd_usb;
}

/// bDeviceClass, or -1 when no DEVICE descriptor is present.
pub fn usb_device_class(u: &Usb) -> Int {
  if u.device_desc < 0 { return -1; }
  return u.dev_class;
}

/// bDeviceSubClass, or -1 when no DEVICE descriptor is present.
pub fn usb_device_subclass(u: &Usb) -> Int {
  if u.device_desc < 0 { return -1; }
  return u.dev_subclass;
}

/// bDeviceProtocol, or -1 when no DEVICE descriptor is present.
pub fn usb_device_protocol(u: &Usb) -> Int {
  if u.device_desc < 0 { return -1; }
  return u.dev_protocol;
}

/// bMaxPacketSize0, or -1 when no DEVICE descriptor is present.
pub fn usb_device_max_packet0(u: &Usb) -> Int {
  if u.device_desc < 0 { return -1; }
  return u.dev_max_packet0;
}

/// idVendor, or -1 when no DEVICE descriptor is present.
pub fn usb_device_vendor(u: &Usb) -> Int {
  if u.device_desc < 0 { return -1; }
  return u.dev_vendor;
}

/// idProduct, or -1 when no DEVICE descriptor is present.
pub fn usb_device_product(u: &Usb) -> Int {
  if u.device_desc < 0 { return -1; }
  return u.dev_product;
}

/// bcdDevice, or -1 when no DEVICE descriptor is present.
pub fn usb_device_bcd_device(u: &Usb) -> Int {
  if u.device_desc < 0 { return -1; }
  return u.dev_bcd_device;
}

/// iManufacturer string index, or -1 when no DEVICE descriptor is present.
pub fn usb_device_imanufacturer(u: &Usb) -> Int {
  if u.device_desc < 0 { return -1; }
  return u.dev_imanufacturer;
}

/// iProduct string index, or -1 when no DEVICE descriptor is present.
pub fn usb_device_iproduct(u: &Usb) -> Int {
  if u.device_desc < 0 { return -1; }
  return u.dev_iproduct;
}

/// iSerialNumber string index, or -1 when no DEVICE descriptor is present.
pub fn usb_device_iserial(u: &Usb) -> Int {
  if u.device_desc < 0 { return -1; }
  return u.dev_iserial;
}

/// bNumConfigurations, or -1 when no DEVICE descriptor is present. This is
/// the declared count; it is not enforced against the number of parsed
/// configurations (partial dumps are tolerated).
pub fn usb_device_num_configurations(u: &Usb) -> Int {
  if u.device_desc < 0 { return -1; }
  return u.dev_num_configs;
}

// --------------------------------------------------
//  Configuration accessors
// --------------------------------------------------

/// Number of CONFIGURATION descriptors in the stream.
pub fn usb_configuration_count(u: &Usb) -> Int {
  return u.cfg_desc.len();
}

/// wTotalLength of configuration `c`, or -1 for an out-of-range index.
pub fn usb_configuration_total_length(u: &Usb, c: Int) -> Int {
  if c < 0 || c >= u.cfg_total_len.len() { return -1; }
  let v: Int = u.cfg_total_len[c];
  return v;
}

/// bNumInterfaces (the claim; alternate settings may add descriptors, so it
/// is not enforced against the parsed interface count), or -1 for a bad
/// index.
pub fn usb_configuration_num_interfaces(u: &Usb, c: Int) -> Int {
  if c < 0 || c >= u.cfg_num_interfaces.len() { return -1; }
  let v: Int = u.cfg_num_interfaces[c];
  return v;
}

/// bConfigurationValue, or -1 for an out-of-range index.
pub fn usb_configuration_value(u: &Usb, c: Int) -> Int {
  if c < 0 || c >= u.cfg_value.len() { return -1; }
  let v: Int = u.cfg_value[c];
  return v;
}

/// iConfiguration string index, or -1 for an out-of-range index.
pub fn usb_configuration_istring(u: &Usb, c: Int) -> Int {
  if c < 0 || c >= u.cfg_istring.len() { return -1; }
  let v: Int = u.cfg_istring[c];
  return v;
}

/// bmAttributes, or -1 for an out-of-range index.
pub fn usb_configuration_attributes(u: &Usb, c: Int) -> Int {
  if c < 0 || c >= u.cfg_attrs.len() { return -1; }
  let v: Int = u.cfg_attrs[c];
  return v;
}

/// bMaxPower in its raw 2 mA units, or -1 for an out-of-range index.
pub fn usb_configuration_max_power(u: &Usb, c: Int) -> Int {
  if c < 0 || c >= u.cfg_max_power.len() { return -1; }
  let v: Int = u.cfg_max_power[c];
  return v;
}

/// Number of INTERFACE descriptors actually present in configuration `c`,
/// or -1 for an out-of-range index.
pub fn usb_configuration_interface_count(u: &Usb, c: Int) -> Int {
  if c < 0 || c >= u.cfg_desc.len() { return -1; }
  var n = 0;
  var i = 0;
  while i < u.if_config.len() {
    let owner: Int = u.if_config[i];
    if owner == c {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

// --------------------------------------------------
//  Interface accessors
// --------------------------------------------------

/// Number of INTERFACE descriptors in the stream.
pub fn usb_interface_count(u: &Usb) -> Int {
  return u.if_desc.len();
}

/// Configuration ordinal owning interface `i`, or -1 for a bad index.
pub fn usb_interface_configuration(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.if_config.len() { return -1; }
  let v: Int = u.if_config[i];
  return v;
}

/// bInterfaceNumber, or -1 for an out-of-range index.
pub fn usb_interface_number(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.if_number.len() { return -1; }
  let v: Int = u.if_number[i];
  return v;
}

/// bAlternateSetting, or -1 for an out-of-range index.
pub fn usb_interface_alternate(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.if_alt.len() { return -1; }
  let v: Int = u.if_alt[i];
  return v;
}

/// bNumEndpoints claim of interface `i`, or -1 for a bad index.
pub fn usb_interface_endpoint_claim(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.if_endpoint_claim.len() { return -1; }
  let v: Int = u.if_endpoint_claim[i];
  return v;
}

/// Number of ENDPOINT descriptors actually owned by interface `i`, or -1
/// for a bad index.
pub fn usb_interface_endpoint_count(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.if_desc.len() { return -1; }
  var n = 0;
  var e = 0;
  while e < u.ep_interface.len() {
    let owner: Int = u.ep_interface[e];
    if owner == i {
      n = n + 1;
    }
    e = e + 1;
  }
  return n;
}

/// Claimed-minus-parsed endpoint count of interface `i` (the documented
/// tolerance: actual may be below the claim), or -1 for a bad index.
pub fn usb_interface_unlisted_endpoints(u: &Usb, i: Int) -> Int {
  let claim = usb_interface_endpoint_claim(u, i);
  if claim < 0 { return -1; }
  let actual = usb_interface_endpoint_count(u, i);
  if actual < 0 { return -1; }
  return claim - actual;
}

/// bInterfaceClass, or -1 for an out-of-range index.
pub fn usb_interface_class(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.if_class.len() { return -1; }
  let v: Int = u.if_class[i];
  return v;
}

/// bInterfaceSubClass, or -1 for an out-of-range index.
pub fn usb_interface_subclass(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.if_subclass.len() { return -1; }
  let v: Int = u.if_subclass[i];
  return v;
}

/// bInterfaceProtocol, or -1 for an out-of-range index.
pub fn usb_interface_protocol(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.if_protocol.len() { return -1; }
  let v: Int = u.if_protocol[i];
  return v;
}

/// iInterface string index, or -1 for an out-of-range index.
pub fn usb_interface_istring(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.if_istring.len() { return -1; }
  let v: Int = u.if_istring[i];
  return v;
}

// --------------------------------------------------
//  Endpoint accessors
// --------------------------------------------------

/// Number of ENDPOINT descriptors in the stream.
pub fn usb_endpoint_count(u: &Usb) -> Int {
  return u.ep_desc.len();
}

/// Interface ordinal owning endpoint `e`, or -1 for a bad index.
pub fn usb_endpoint_interface(u: &Usb, e: Int) -> Int {
  if e < 0 || e >= u.ep_interface.len() { return -1; }
  let v: Int = u.ep_interface[e];
  return v;
}

/// bEndpointAddress (bit 7 = direction, bits 3..0 = endpoint number), or -1
/// for an out-of-range index.
pub fn usb_endpoint_address(u: &Usb, e: Int) -> Int {
  if e < 0 || e >= u.ep_address.len() { return -1; }
  let v: Int = u.ep_address[e];
  return v;
}

/// bmAttributes (bits 1..0 = transfer type), or -1 for a bad index.
pub fn usb_endpoint_attributes(u: &Usb, e: Int) -> Int {
  if e < 0 || e >= u.ep_attrs.len() { return -1; }
  let v: Int = u.ep_attrs[e];
  return v;
}

/// wMaxPacketSize in bytes, or -1 for an out-of-range index.
pub fn usb_endpoint_max_packet(u: &Usb, e: Int) -> Int {
  if e < 0 || e >= u.ep_max_packet.len() { return -1; }
  let v: Int = u.ep_max_packet[e];
  return v;
}

/// bInterval in frames/microframes, or -1 for an out-of-range index.
pub fn usb_endpoint_interval(u: &Usb, e: Int) -> Int {
  if e < 0 || e >= u.ep_interval.len() { return -1; }
  let v: Int = u.ep_interval[e];
  return v;
}

/// Number of endpoints owned by interface `i` (same as
/// usb_interface_endpoint_count; -1 for a bad index).
pub fn usb_endpoint_count_for_interface(u: &Usb, i: Int) -> Int {
  return usb_interface_endpoint_count(u, i);
}

/// First endpoint of interface `i` with bEndpointAddress `address`, or -1
/// when none matches (also for a bad interface index).
pub fn usb_find_endpoint(u: &Usb, i: Int, address: Int) -> Int {
  if i < 0 || i >= u.if_desc.len() { return -1; }
  var e = 0;
  while e < u.ep_interface.len() {
    let owner: Int = u.ep_interface[e];
    let addr: Int = u.ep_address[e];
    if owner == i {
      if addr == address {
        return e;
      }
    }
    e = e + 1;
  }
  return -1;
}

// --------------------------------------------------
//  String-pool accessors
// --------------------------------------------------

/// Number of STRING descriptors in the pool (stream order).
pub fn usb_string_count(u: &Usb) -> Int {
  return u.str_desc.len();
}

/// bStringIndex of pool entry `i`, or -1 for an out-of-range index.
pub fn usb_string_index(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.str_id.len() { return -1; }
  let v: Int = u.str_id[i];
  return v;
}

/// Decoded printable-ASCII text of pool entry `i`; "" for a bad index.
pub fn usb_string_text(u: &Usb, i: Int) -> Str {
  if i < 0 || i >= u.str_text.len() { return ""; }
  let s: Str = u.str_text[i];
  return s;
}

/// Number of UTF-16LE code units replaced by '?' in pool entry `i`, or -1
/// for an out-of-range index.
pub fn usb_string_replacements(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.str_replaced.len() { return -1; }
  let v: Int = u.str_replaced[i];
  return v;
}

/// True when the pool contains a STRING descriptor with bStringIndex `sid`.
pub fn usb_string_present(u: &Usb, sid: Int) -> Bool {
  return _string_pool(u, sid) >= 0;
}

/// Decoded text of the first STRING descriptor with bStringIndex `sid`.
/// Err("usb: string index not found") when the pool has no such entry
/// (string index 0 is "no string" and is never in the pool unless a
/// descriptor declares it).
pub fn usb_string(u: &Usb, sid: Int) -> Result[Str, Str] {
  let at = _string_pool(u, sid);
  if at < 0 {
    return _err_str("usb: string index not found");
  }
  let s: Str = u.str_text[at];
  return _ok_str(s);
}

// --------------------------------------------------
//  Raw-preserved descriptor accessors
// --------------------------------------------------

/// Number of raw-preserved descriptors (DEVICE_QUALIFIER, BOS,
/// DEVICE_CAPABILITY and every unknown type) in stream order.
pub fn usb_raw_count(u: &Usb) -> Int {
  return u.raw_desc.len();
}

/// bDescriptorType of raw descriptor `i`, or -1 for a bad index.
pub fn usb_raw_type(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.raw_desc.len() { return -1; }
  let di: Int = u.raw_desc[i];
  let v: Int = u.desc_type[di];
  return v;
}

/// bLength of raw descriptor `i`, or -1 for a bad index.
pub fn usb_raw_length(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.raw_desc.len() { return -1; }
  let di: Int = u.raw_desc[i];
  let v: Int = u.desc_len[di];
  return v;
}

/// Absolute offset of raw descriptor `i`'s bLength byte, or -1 for a bad
/// index.
pub fn usb_raw_offset(u: &Usb, i: Int) -> Int {
  if i < 0 || i >= u.raw_desc.len() { return -1; }
  let di: Int = u.raw_desc[i];
  let v: Int = u.desc_off[di];
  return v;
}

/// Copy the bytes of raw descriptor `i` out of `data`.
/// Err("usb: raw index out of range") for a bad index and
/// Err("usb: raw span out of bounds") when the recorded span does not fit
/// `data`.
pub fn usb_raw_bytes(data: &Vec[UInt8], u: &Usb, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= u.raw_desc.len() {
    return _err_bytes("usb: raw index out of range");
  }
  let di: Int = u.raw_desc[i];
  let off: Int = u.desc_off[di];
  let len: Int = u.desc_len[di];
  if off < 0 || len < 0 || off + len > data.len() {
    return _err_bytes("usb: raw span out of bounds");
  }
  var out = Vec[UInt8].new();
  var k = 0;
  while k < len {
    out.push(data[off + k]);
    k = k + 1;
  }
  return _ok_bytes(out);
}

/// Raw ordinal of the first raw-preserved descriptor of type `desc_type`,
/// or -1 when absent.
pub fn usb_raw_find(u: &Usb, desc_type: Int) -> Int {
  var i = 0;
  while i < u.raw_desc.len() {
    let di: Int = u.raw_desc[i];
    let t: Int = u.desc_type[di];
    if t == desc_type {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Raw ordinal of the first raw descriptor of type `want` with bLength at
// least `min_len`, or -1.
fn _raw_at_least(u: &Usb, want: Int, min_len: Int) -> Int {
  var i = 0;
  while i < u.raw_desc.len() {
    let di: Int = u.raw_desc[i];
    let t: Int = u.desc_type[di];
    let l: Int = u.desc_len[di];
    if t == want && l >= min_len {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Raw ordinal of the k-th raw descriptor of type `want`, or -1.
fn _raw_nth(u: &Usb, want: Int, k: Int) -> Int {
  if k < 0 { return -1; }
  var n = 0;
  var i = 0;
  while i < u.raw_desc.len() {
    let di: Int = u.raw_desc[i];
    let t: Int = u.desc_type[di];
    if t == want {
      if n == k {
        return i;
      }
      n = n + 1;
    }
    i = i + 1;
  }
  return -1;
}

// Byte `at` (relative to bLength) of raw descriptor `i`, or -1 when out of
// range or out of the buffer.
fn _raw_byte(data: &Vec[UInt8], u: &Usb, i: Int, at: Int) -> Int {
  if i < 0 || i >= u.raw_desc.len() { return -1; }
  if at < 0 { return -1; }
  let di: Int = u.raw_desc[i];
  let off: Int = u.desc_off[di];
  let len: Int = u.desc_len[di];
  if at >= len { return -1; }
  if off + at >= data.len() { return -1; }
  return _byte(data, off + at);
}

// Little-endian word at relative offset `at` of raw descriptor `i`, or -1.
fn _raw_word(data: &Vec[UInt8], u: &Usb, i: Int, at: Int) -> Int {
  let lo = _raw_byte(data, u, i, at);
  let hi = _raw_byte(data, u, i, at + 1);
  if lo < 0 || hi < 0 { return -1; }
  return lo + hi * 256;
}

/// Raw ordinal of the first DEVICE_QUALIFIER descriptor with at least the
/// 10 documented bytes, or -1. Internal shape used by the field accessors.
fn _qualifier(u: &Usb) -> Int {
  return _raw_at_least(u, USB_DESC_DEVICE_QUALIFIER, 10);
}

/// Raw ordinal of the first BOS descriptor with at least its 5 header
/// bytes, or -1.
fn _bos(u: &Usb) -> Int {
  return _raw_at_least(u, USB_DESC_BOS, 5);
}

/// True when a DEVICE_QUALIFIER descriptor (>= 10 bytes) is present.
pub fn usb_qualifier_present(u: &Usb) -> Bool {
  return _qualifier(u) >= 0;
}

/// bcdUSB field of the DEVICE_QUALIFIER descriptor, or -1 when absent.
pub fn usb_qualifier_bcd_usb(data: &Vec[UInt8], u: &Usb) -> Int {
  return _raw_word(data, u, _qualifier(u), 2);
}

/// bDeviceClass of the DEVICE_QUALIFIER descriptor, or -1 when absent.
pub fn usb_qualifier_class(data: &Vec[UInt8], u: &Usb) -> Int {
  return _raw_byte(data, u, _qualifier(u), 4);
}

/// bDeviceSubClass of the DEVICE_QUALIFIER descriptor, or -1 when absent.
pub fn usb_qualifier_subclass(data: &Vec[UInt8], u: &Usb) -> Int {
  return _raw_byte(data, u, _qualifier(u), 5);
}

/// bDeviceProtocol of the DEVICE_QUALIFIER descriptor, or -1 when absent.
pub fn usb_qualifier_protocol(data: &Vec[UInt8], u: &Usb) -> Int {
  return _raw_byte(data, u, _qualifier(u), 6);
}

/// bMaxPacketSize0 of the DEVICE_QUALIFIER descriptor, or -1 when absent.
pub fn usb_qualifier_max_packet0(data: &Vec[UInt8], u: &Usb) -> Int {
  return _raw_byte(data, u, _qualifier(u), 7);
}

/// bNumConfigurations of the DEVICE_QUALIFIER descriptor, or -1 when
/// absent.
pub fn usb_qualifier_num_configs(data: &Vec[UInt8], u: &Usb) -> Int {
  return _raw_byte(data, u, _qualifier(u), 8);
}

/// True when a BOS descriptor (>= 5 bytes) is present.
pub fn usb_bos_present(u: &Usb) -> Bool {
  return _bos(u) >= 0;
}

/// wTotalLength of the BOS descriptor, or -1 when absent.
pub fn usb_bos_total_length(data: &Vec[UInt8], u: &Usb) -> Int {
  return _raw_word(data, u, _bos(u), 2);
}

/// bNumDeviceCaps of the BOS descriptor, or -1 when absent.
pub fn usb_bos_num_capabilities(data: &Vec[UInt8], u: &Usb) -> Int {
  return _raw_byte(data, u, _bos(u), 4);
}

/// Number of DEVICE_CAPABILITY descriptors in the stream.
pub fn usb_capability_count(u: &Usb) -> Int {
  var n = 0;
  var i = 0;
  while i < u.raw_desc.len() {
    let di: Int = u.raw_desc[i];
    let t: Int = u.desc_type[di];
    if t == USB_DESC_DEVICE_CAPABILITY {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// bDevCapabilityType (byte 2) of capability `k`, or -1 for a bad index.
pub fn usb_capability_type(data: &Vec[UInt8], u: &Usb, k: Int) -> Int {
  return _raw_byte(data, u, _raw_nth(u, USB_DESC_DEVICE_CAPABILITY, k), 2);
}

/// bLength of capability `k`, or -1 for a bad index.
pub fn usb_capability_length(u: &Usb, k: Int) -> Int {
  let i = _raw_nth(u, USB_DESC_DEVICE_CAPABILITY, k);
  if i < 0 { return -1; }
  let di: Int = u.raw_desc[i];
  let v: Int = u.desc_len[di];
  return v;
}

/// Copy the raw span of capability `k` out of `data`.
/// Err("usb: raw index out of range") for a bad index and
/// Err("usb: raw span out of bounds") when the span does not fit `data`.
pub fn usb_capability_bytes(data: &Vec[UInt8], u: &Usb, k: Int) -> Result[Vec[UInt8], Str] {
  let i = _raw_nth(u, USB_DESC_DEVICE_CAPABILITY, k);
  return usb_raw_bytes(data, u, i);
}

// --------------------------------------------------
//  Canonical emitter
// --------------------------------------------------

// True when descriptor `idx` exists with the given type and exact length.
fn _desc_is(u: &Usb, idx: Int, want_type: Int, want_len: Int) -> Bool {
  if idx < 0 || idx >= u.desc_type.len() { return false; }
  let t: Int = u.desc_type[idx];
  let l: Int = u.desc_len[idx];
  if t != want_type { return false; }
  if l != want_len { return false; }
  return true;
}

// Structural well-formedness of a store: parallel vectors aligned, every
// referenced descriptor present with its exact type/length, spans inside
// `data`, parent links in range, endpoint counts within claims, string
// lengths consistent with their decoded text, and scalar fields inside
// their byte/word ranges. A drifted store can otherwise produce a
// non-canonical stream or an access violation.
fn _well_formed(data: &Vec[UInt8], u: &Usb) -> Bool {
  let nd = u.desc_type.len();
  if u.desc_off.len() != nd { return false; }
  if u.desc_len.len() != nd { return false; }
  let nc = u.cfg_desc.len();
  if u.cfg_total_len.len() != nc { return false; }
  if u.cfg_num_interfaces.len() != nc { return false; }
  if u.cfg_value.len() != nc { return false; }
  if u.cfg_istring.len() != nc { return false; }
  if u.cfg_attrs.len() != nc { return false; }
  if u.cfg_max_power.len() != nc { return false; }
  let ni = u.if_desc.len();
  if u.if_config.len() != ni { return false; }
  if u.if_number.len() != ni { return false; }
  if u.if_alt.len() != ni { return false; }
  if u.if_endpoint_claim.len() != ni { return false; }
  if u.if_class.len() != ni { return false; }
  if u.if_subclass.len() != ni { return false; }
  if u.if_protocol.len() != ni { return false; }
  if u.if_istring.len() != ni { return false; }
  let ne = u.ep_desc.len();
  if u.ep_interface.len() != ne { return false; }
  if u.ep_address.len() != ne { return false; }
  if u.ep_attrs.len() != ne { return false; }
  if u.ep_max_packet.len() != ne { return false; }
  if u.ep_interval.len() != ne { return false; }
  let ns = u.str_desc.len();
  if u.str_id.len() != ns { return false; }
  if u.str_text.len() != ns { return false; }
  if u.str_replaced.len() != ns { return false; }
  // Every descriptor span fits the source buffer.
  var i = 0;
  while i < nd {
    let off: Int = u.desc_off[i];
    let len: Int = u.desc_len[i];
    if off < 0 || len < 2 || off + len > data.len() { return false; }
    i = i + 1;
  }
  // Device.
  if u.device_desc != -1 {
    if !_desc_is(u, u.device_desc, USB_DESC_DEVICE, 18) { return false; }
    if !_is_word(u.dev_bcd_usb) { return false; }
    if !_is_byte(u.dev_class) { return false; }
    if !_is_byte(u.dev_subclass) { return false; }
    if !_is_byte(u.dev_protocol) { return false; }
    if !_is_byte(u.dev_max_packet0) { return false; }
    if !_is_word(u.dev_vendor) { return false; }
    if !_is_word(u.dev_product) { return false; }
    if !_is_word(u.dev_bcd_device) { return false; }
    if !_is_byte(u.dev_imanufacturer) { return false; }
    if !_is_byte(u.dev_iproduct) { return false; }
    if !_is_byte(u.dev_iserial) { return false; }
    if !_is_byte(u.dev_num_configs) { return false; }
  }
  // Configurations.
  i = 0;
  while i < nc {
    let di: Int = u.cfg_desc[i];
    if !_desc_is(u, di, USB_DESC_CONFIGURATION, 9) { return false; }
    let tl: Int = u.cfg_total_len[i];
    if tl < 9 { return false; }
    if !_is_byte(u.cfg_num_interfaces[i]) { return false; }
    if !_is_byte(u.cfg_value[i]) { return false; }
    if !_is_byte(u.cfg_istring[i]) { return false; }
    if !_is_byte(u.cfg_attrs[i]) { return false; }
    if !_is_byte(u.cfg_max_power[i]) { return false; }
    i = i + 1;
  }
  // Interfaces: parent in range and parsed endpoint count within claim.
  i = 0;
  while i < ni {
    let di2: Int = u.if_desc[i];
    if !_desc_is(u, di2, USB_DESC_INTERFACE, 9) { return false; }
    let parent: Int = u.if_config[i];
    if parent < 0 || parent >= nc { return false; }
    if !_is_byte(u.if_number[i]) { return false; }
    if !_is_byte(u.if_alt[i]) { return false; }
    let claim: Int = u.if_endpoint_claim[i];
    if !_is_byte(claim) { return false; }
    if !_is_byte(u.if_class[i]) { return false; }
    if !_is_byte(u.if_subclass[i]) { return false; }
    if !_is_byte(u.if_protocol[i]) { return false; }
    if !_is_byte(u.if_istring[i]) { return false; }
    var actual = 0;
    var e = 0;
    while e < ne {
      let owner: Int = u.ep_interface[e];
      if owner == i {
        actual = actual + 1;
      }
      e = e + 1;
    }
    if actual > claim { return false; }
    i = i + 1;
  }
  // Endpoints.
  i = 0;
  while i < ne {
    let di3: Int = u.ep_desc[i];
    if !_desc_is(u, di3, USB_DESC_ENDPOINT, 7) { return false; }
    let owner2: Int = u.ep_interface[i];
    if owner2 < 0 || owner2 >= ni { return false; }
    if !_is_byte(u.ep_address[i]) { return false; }
    if !_is_byte(u.ep_attrs[i]) { return false; }
    if !_is_word(u.ep_max_packet[i]) { return false; }
    if !_is_byte(u.ep_interval[i]) { return false; }
    i = i + 1;
  }
  // Strings.
  i = 0;
  while i < ns {
    let di4: Int = u.str_desc[i];
    if di4 < 0 || di4 >= nd { return false; }
    let dt: Int = u.desc_type[di4];
    if dt != USB_DESC_STRING { return false; }
    let dl: Int = u.desc_len[di4];
    if dl < 2 || dl % 2 != 0 { return false; }
    if !_is_byte(u.str_id[i]) { return false; }
    let rep: Int = u.str_replaced[i];
    if rep < 0 { return false; }
    let st: Str = u.str_text[i];
    if 4 + string.str_len(st) * 2 != dl { return false; }
    i = i + 1;
  }
  // Raw references.
  i = 0;
  while i < u.raw_desc.len() {
    let dr: Int = u.raw_desc[i];
    if dr < 0 || dr >= nd { return false; }
    i = i + 1;
  }
  return true;
}

// Emit the string descriptors in pool order: bLength, type, the
// bStringIndex unit, then the decoded text as UTF-16LE units.
fn _emit_strings(u: &Usb, out: &mut Vec[UInt8]) {
  var s = 0;
  while s < u.str_desc.len() {
    let st: Str = u.str_text[s];
    let n = string.str_len(st);
    out.push((4 + n * 2) as UInt8);
    out.push(USB_DESC_STRING as UInt8);
    out.push(u.str_id[s] as UInt8);
    out.push(0 as UInt8);
    var k = 0;
    while k < n {
      out.push(string.byte_at(st, k));
      out.push(0 as UInt8);
      k = k + 1;
    }
    s = s + 1;
  }
}

/// Emit the canonical descriptor stream for a parsed store.
///
/// Canonical order: the DEVICE descriptor (when present), then every
/// configuration in order with each of its interfaces in order followed by
/// that interface's endpoints, then the string descriptors in pool order,
/// then the raw-preserved descriptors in recorded order (their spans are
/// copied verbatim from `data`). Configuration wTotalLength values are
/// recomputed as 9 + 9 per emitted interface + 7 per emitted endpoint;
/// interface bNumEndpoints is the preserved claim. Parsing a canonical
/// stream and emitting it again is byte-identical (this includes the
/// documented device+configuration+interface+endpoints+strings fixture).
///
/// `data` must be the buffer the store was parsed from. Err
/// ("usb: invalid store") when the parallel vectors have drifted apart, a
/// referenced descriptor is missing or mis-typed, a span does not fit
/// `data`, or a scalar field is outside its byte/word range.
/// Complexity: O(stream size + interfaces x endpoints).
pub fn usb_emit(data: &Vec[UInt8], u: &Usb) -> Result[Vec[UInt8], Str] {
  if !_well_formed(data, u) {
    return _err_bytes("usb: invalid store");
  }
  var out = Vec[UInt8].new();
  // DEVICE.
  if u.device_desc >= 0 {
    out.push(18 as UInt8);
    out.push(USB_DESC_DEVICE as UInt8);
    _push_le(&mut out, u.dev_bcd_usb, 2);
    out.push(u.dev_class as UInt8);
    out.push(u.dev_subclass as UInt8);
    out.push(u.dev_protocol as UInt8);
    out.push(u.dev_max_packet0 as UInt8);
    _push_le(&mut out, u.dev_vendor, 2);
    _push_le(&mut out, u.dev_product, 2);
    _push_le(&mut out, u.dev_bcd_device, 2);
    out.push(u.dev_imanufacturer as UInt8);
    out.push(u.dev_iproduct as UInt8);
    out.push(u.dev_iserial as UInt8);
    out.push(u.dev_num_configs as UInt8);
  }
  // Configurations, interfaces and endpoints.
  var c = 0;
  while c < u.cfg_desc.len() {
    var total = 9;
    var i = 0;
    while i < u.if_desc.len() {
      let owner: Int = u.if_config[i];
      if owner == c {
        total = total + 9;
        var e = 0;
        while e < u.ep_desc.len() {
          let eo: Int = u.ep_interface[e];
          if eo == i {
            total = total + 7;
          }
          e = e + 1;
        }
      }
      i = i + 1;
    }
    out.push(9 as UInt8);
    out.push(USB_DESC_CONFIGURATION as UInt8);
    _push_le(&mut out, total, 2);
    out.push(u.cfg_num_interfaces[c] as UInt8);
    out.push(u.cfg_value[c] as UInt8);
    out.push(u.cfg_istring[c] as UInt8);
    out.push(u.cfg_attrs[c] as UInt8);
    out.push(u.cfg_max_power[c] as UInt8);
    i = 0;
    while i < u.if_desc.len() {
      let owner2: Int = u.if_config[i];
      if owner2 == c {
        out.push(9 as UInt8);
        out.push(USB_DESC_INTERFACE as UInt8);
        out.push(u.if_number[i] as UInt8);
        out.push(u.if_alt[i] as UInt8);
        out.push(u.if_endpoint_claim[i] as UInt8);
        out.push(u.if_class[i] as UInt8);
        out.push(u.if_subclass[i] as UInt8);
        out.push(u.if_protocol[i] as UInt8);
        out.push(u.if_istring[i] as UInt8);
        var e2 = 0;
        while e2 < u.ep_desc.len() {
          let eo2: Int = u.ep_interface[e2];
          if eo2 == i {
            out.push(7 as UInt8);
            out.push(USB_DESC_ENDPOINT as UInt8);
            out.push(u.ep_address[e2] as UInt8);
            out.push(u.ep_attrs[e2] as UInt8);
            _push_le(&mut out, u.ep_max_packet[e2], 2);
            out.push(u.ep_interval[e2] as UInt8);
          }
          e2 = e2 + 1;
        }
      }
      i = i + 1;
    }
    c = c + 1;
  }
  // Strings.
  _emit_strings(u, &mut out);
  // Raw-preserved descriptors, verbatim.
  var r = 0;
  while r < u.raw_desc.len() {
    let di: Int = u.raw_desc[r];
    let off: Int = u.desc_off[di];
    let len: Int = u.desc_len[di];
    var k = 0;
    while k < len {
      out.push(data[off + k]);
      k = k + 1;
    }
    r = r + 1;
  }
  return _ok_bytes(out);
}
