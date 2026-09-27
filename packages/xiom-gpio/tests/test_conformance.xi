// XIOM -- xiom.gpio conformance tests (21 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Proves the pure-XIOM xiom.gpio structure codec against the Linux GPIO
// character-device uAPI v2 byte layouts: gpiochip_info (68 bytes),
// gpio_v2_line_attribute (16), gpio_v2_line_config (272),
// gpio_v2_line_request (592), gpio_v2_line_info (256),
// gpio_v2_line_event (48) and gpio_v2_line_values (16).
//
// Every synthetic buffer is built in-test byte by byte (or from a pinned
// hex string) independently of the module's encoders, so the decode and
// encode paths are cross-checked against each other and against explicit
// little-endian expectations. Every error message is compared exactly
// through xiom.string.compare (no Str value is compared with `==` and none
// is read from a Vec). All Vec element reads are bound to widened typed
// locals, and the 64-bit vectors pin both composition and the bit-63
// rejection.

module gpio_tests
use xiom.io; use xiom.test;
use xiom.gpio;
use xiom.string;
use xiom.string.compare;
use xiom.convert.int;
use xiom.encoding.hex;

// --------------------------------------------------
//  Fixture helpers (independent of src/gpio.xi)
// --------------------------------------------------

// Bytes for a hex string; "" on malformed input (the test then fails on
// the byte comparison). Lowercase or uppercase digits both parse.
fn hb(hexstr: Str) -> Vec[UInt8] {
  let r = hex.hex_decode(hexstr);
  match r {
    Ok(v) => { return v; },
    Err(_) => {},
  }
  return Vec[UInt8].new();
}

fn str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn bytes_equal(a: Vec[UInt8], b: Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn clone_bytes(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
  return out;
}

fn push_u32(v: &mut Vec[UInt8], x: Int) {
  v.push((x % 256) as UInt8);
  v.push(((x / 256) % 256) as UInt8);
  v.push(((x / 65536) % 256) as UInt8);
  v.push(((x / 16777216) % 256) as UInt8);
}

fn push_u64(v: &mut Vec[UInt8], x: Int) {
  push_u32(v, x % 4294967296);
  push_u32(v, x / 4294967296);
}

fn push_zeros(v: &mut Vec[UInt8], n: Int) {
  var i = 0;
  while i < n {
    v.push(0);
    i = i + 1;
  }
}

fn push_cstr32(v: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  push_zeros(v, 32 - s.len());
}

fn set_byte(v: &mut Vec[UInt8], pos: Int, val: Int) {
  v[pos] = val as UInt8;
}

fn iv_eq(a: Vec[Int], b: Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = a[i];
    let y: Int = b[i];
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn err_unit_is(r: Result[Unit, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_bytes_is(r: Result[Vec[UInt8], Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_str_is(r: Result[Str, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_chip_is(r: Result[GpioChipInfo, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_attr_is(r: Result[GpioLineAttribute, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_config_is(r: Result[GpioLineConfig, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_request_is(r: Result[GpioLineRequest, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_info_is(r: Result[GpioLineInfo, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_event_is(r: Result[GpioLineEvent, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

fn err_values_is(r: Result[GpioLineValues, Str], want: Str) -> Bool {
  if r.is_ok {
    return false;
  }
  let e: Str = r.error;
  return str_eq(e, want);
}

// --------------------------------------------------
//  Synthetic buffer builders (independent layouts)
// --------------------------------------------------

fn chip_bytes(name: Str, label: Str, lines: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_cstr32(&mut v, name);
  push_cstr32(&mut v, label);
  push_u32(&mut v, lines);
  return v;
}

fn attr16(id: Int, value: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_u32(&mut v, id);
  push_zeros(&mut v, 4);
  push_u64(&mut v, value);
  return v;
}

fn attr16_dead(id: Int, value: Int, dead: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_u32(&mut v, id);
  push_zeros(&mut v, 4);
  push_u32(&mut v, value);
  push_u32(&mut v, dead);
  return v;
}

fn iv1(a: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  return v;
}

fn iv2(a: Int, b: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  return v;
}

fn iv3(a: Int, b: Int, c: Int) -> Vec[Int] {
  var v = Vec[Int].new();
  v.push(a);
  v.push(b);
  v.push(c);
  return v;
}

// One 24-byte config attribute (16-byte attribute plus 8-byte mask); a
// DEBOUNCE attribute writes its 32-bit period and zeroes the union's top
// half, the other ids write a full u64 union value.
fn push_config_attr(v: &mut Vec[UInt8], id: Int, val: Int, mask: Int) {
  push_u32(v, id);
  push_zeros(v, 4);
  if id == GPIO_V2_LINE_ATTR_ID_DEBOUNCE {
    push_u32(v, val);
    push_zeros(v, 4);
  } else {
    push_u64(v, val);
  }
  push_u64(v, mask);
}

fn config_bytes(flags: Int, ids: Vec[Int], vals: Vec[Int], masks: Vec[Int]) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_u64(&mut v, flags);
  push_u32(&mut v, ids.len());
  push_zeros(&mut v, 20);
  var i = 0;
  while i < ids.len() {
    let id: Int = ids[i];
    let val: Int = vals[i];
    let m: Int = masks[i];
    push_config_attr(&mut v, id, val, m);
    i = i + 1;
  }
  let rest = GPIO_V2_LINE_NUM_ATTRS_MAX - ids.len();
  push_zeros(&mut v, rest * GPIO_V2_LINE_CONFIG_ATTRIBUTE_SIZE);
  return v;
}

fn request_bytes(offsets: Vec[Int], consumer: Str, flags: Int, ids: Vec[Int], vals: Vec[Int], masks: Vec[Int], num_lines: Int, ebs: Int, fd: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < offsets.len() {
    let o: Int = offsets[i];
    push_u32(&mut v, o);
    i = i + 1;
  }
  push_zeros(&mut v, (GPIO_V2_LINES_MAX - offsets.len()) * 4);
  push_cstr32(&mut v, consumer);
  let cfg = config_bytes(flags, ids, vals, masks);
  i = 0;
  while i < cfg.len() {
    v.push(cfg[i]);
    i = i + 1;
  }
  push_u32(&mut v, num_lines);
  push_u32(&mut v, ebs);
  push_zeros(&mut v, 20);
  push_u32(&mut v, fd);
  return v;
}

fn push_info_attr(v: &mut Vec[UInt8], id: Int, val: Int) {
  push_u32(v, id);
  push_zeros(v, 4);
  if id == GPIO_V2_LINE_ATTR_ID_DEBOUNCE {
    push_u32(v, val);
    push_zeros(v, 4);
  } else {
    push_u64(v, val);
  }
}

fn info_bytes(name: Str, consumer: Str, line_offset: Int, flags: Int, ids: Vec[Int], vals: Vec[Int], num_attrs: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_cstr32(&mut v, name);
  push_cstr32(&mut v, consumer);
  push_u32(&mut v, line_offset);
  push_u32(&mut v, num_attrs);
  push_u64(&mut v, flags);
  var i = 0;
  while i < ids.len() {
    let id: Int = ids[i];
    let val: Int = vals[i];
    push_info_attr(&mut v, id, val);
    i = i + 1;
  }
  push_zeros(&mut v, (GPIO_V2_LINE_NUM_ATTRS_MAX - ids.len()) * GPIO_V2_LINE_ATTRIBUTE_SIZE);
  push_zeros(&mut v, 16);
  return v;
}

fn event_bytes(ts: Int, id: Int, line_offset: Int, seqno: Int, line_seqno: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_u64(&mut v, ts);
  push_u32(&mut v, id);
  push_u32(&mut v, line_offset);
  push_u32(&mut v, seqno);
  push_u32(&mut v, line_seqno);
  push_zeros(&mut v, 24);
  return v;
}

fn values_bytes(bits: Int, mask: Int) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  push_u64(&mut v, bits);
  push_u64(&mut v, mask);
  return v;
}

fn cfg_of(flags: Int, ids: Vec[Int], vals: Vec[Int], masks: Vec[Int]) -> GpioLineConfig {
  return GpioLineConfig{ flags: flags; attr_ids: ids; attr_values: vals; attr_masks: masks; };
}

// --------------------------------------------------
//  gpiochip_info tests
// --------------------------------------------------

fn t1() -> TestResult {
  let b = chip_bytes("gpiochip0", "pinctrl-bcm2711", 58);
  let r = gpio_chip_info_decode(&b);
  if !r.is_ok {
    return assert(false, "chip info must decode");
  }
  let c: GpioChipInfo = r.value;
  var ok = str_eq(c.name, "gpiochip0");
  if !str_eq(c.label, "pinctrl-bcm2711") { ok = false; }
  if c.lines != 58 { ok = false; }
  var b2 = clone_bytes(&b);
  set_byte(&mut b2, 10, 200);
  let r2 = gpio_chip_info_decode(&b2);
  if !r2.is_ok { ok = false; } else {
    let c2: GpioChipInfo = r2.value;
    if !str_eq(c2.name, "gpiochip0") { ok = false; }
  }
  let maxb = chip_bytes("", "", 4294967295);
  let r3 = gpio_chip_info_decode(&maxb);
  if !r3.is_ok { ok = false; } else {
    let c3: GpioChipInfo = r3.value;
    if c3.lines != 4294967295 { ok = false; }
    if c3.name.len() != 0 { ok = false; }
    if c3.label.len() != 0 { ok = false; }
  }
  return assert(ok, "gpiochip_info decode trims at NUL and reads the u32 line count");
}

fn t2() -> TestResult {
  let short = chip_bytes("gpiochip0", "lab", 8);
  var small = Vec[UInt8].new();
  var i = 0;
  while i < 67 {
    small.push(short[i]);
    i = i + 1;
  }
  var ok = err_chip_is(gpio_chip_info_decode(&small), "gpio: gpiochip_info: truncated at offset 67: need 68 bytes, have 67");
  var fat = clone_bytes(&short);
  fat.push(0);
  if !err_chip_is(gpio_chip_info_decode(&fat), "gpio: gpiochip_info: buffer has 69 bytes, expected exactly 68") { ok = false; }
  var noname = Vec[UInt8].new();
  i = 0;
  while i < 32 {
    noname.push(65);
    i = i + 1;
  }
  push_cstr32(&mut noname, "label");
  push_u32(&mut noname, 1);
  if !err_chip_is(gpio_chip_info_decode(&noname), "gpio: name at offset 0 has no NUL within 32 bytes") { ok = false; }
  var nolabel = Vec[UInt8].new();
  push_cstr32(&mut nolabel, "n");
  i = 0;
  while i < 32 {
    nolabel.push(66);
    i = i + 1;
  }
  push_u32(&mut nolabel, 1);
  if !err_chip_is(gpio_chip_info_decode(&nolabel), "gpio: label at offset 32 has no NUL within 32 bytes") { ok = false; }
  let name5 = hb("6e616d6500");
  if !err_str_is(gpio_name_decode(&name5, 4), "gpio: name at offset 4: truncated: need 32 bytes, have 1") { ok = false; }
  if !gpio_name_fits("abcdefghij0123456789abcdefghijk") { ok = false; }
  if gpio_name_fits("abcdefghij0123456789abcdefghijkl") { ok = false; }
  if !gpio_consumer_name_ok("abcdefghij0123456789abcdefghijk") { ok = false; }
  if gpio_consumer_name_ok("abcdefghij0123456789abcdefghijkl") { ok = false; }
  let longname = "abcdefghij0123456789abcdefghijkl";
  let enc = gpio_chip_info_encode(&GpioChipInfo{ name: longname; label: "x"; lines: 1; });
  if !err_bytes_is(enc, "gpio: name is 32 bytes, needs at most 31 plus NUL within 32") { ok = false; }
  let biglines = gpio_chip_info_encode(&GpioChipInfo{ name: "n"; label: "l"; lines: 4294967296; });
  if !err_bytes_is(biglines, "gpio: gpiochip_info: lines 4294967296 does not fit in u32") { ok = false; }
  return assert(ok, "gpiochip_info size/name/range errors carry the exact offsets");
}

fn t3() -> TestResult {
  let b = chip_bytes("gpiochip2", "gpio-bank-b", 40);
  let r = gpio_chip_info_decode(&b);
  if !r.is_ok {
    return assert(false, "chip info must decode");
  }
  let c: GpioChipInfo = r.value;
  let e = gpio_chip_info_encode(&c);
  if !e.is_ok {
    return assert(false, "chip info must encode");
  }
  let eb: Vec[UInt8] = e.value;
  var ok = bytes_equal(eb, b);
  var out = Vec[UInt8].new();
  out.push(170);
  let r2 = gpio_chip_info_encode_into(&mut out, &c);
  if !r2.is_ok { ok = false; }
  if out.len() != 69 { ok = false; }
  let b0: Int = (out[0] as Int) & 0xFF;
  if b0 != 170 { ok = false; }
  let bad = gpio_chip_info_encode(&GpioChipInfo{ name: "abcdefghij0123456789abcdefghijkl"; label: "x"; lines: 1; });
  if bad.is_ok { ok = false; }
  let r3 = gpio_chip_info_encode_into(&mut out, &GpioChipInfo{ name: "abcdefghij0123456789abcdefghijkl"; label: "x"; lines: 1; });
  if r3.is_ok { ok = false; }
  if out.len() != 69 { ok = false; }
  return assert(ok, "gpiochip_info encode round-trips and encode_into is atomic");
}

// --------------------------------------------------
//  Flag tests
// --------------------------------------------------

fn t4() -> TestResult {
  var ok = GPIO_V2_LINE_FLAG_USED == 1;
  if GPIO_V2_LINE_FLAG_ACTIVE_LOW != 2 { ok = false; }
  if GPIO_V2_LINE_FLAG_INPUT != 4 { ok = false; }
  if GPIO_V2_LINE_FLAG_OUTPUT != 8 { ok = false; }
  if GPIO_V2_LINE_FLAG_EDGE_RISING != 16 { ok = false; }
  if GPIO_V2_LINE_FLAG_EDGE_FALLING != 32 { ok = false; }
  if GPIO_V2_LINE_FLAG_OPEN_DRAIN != 64 { ok = false; }
  if GPIO_V2_LINE_FLAG_OPEN_SOURCE != 128 { ok = false; }
  if GPIO_V2_LINE_FLAG_BIAS_PULL_UP != 256 { ok = false; }
  if GPIO_V2_LINE_FLAG_BIAS_PULL_DOWN != 512 { ok = false; }
  if GPIO_V2_LINE_FLAG_BIAS_DISABLED != 1024 { ok = false; }
  if GPIO_V2_LINE_FLAG_EVENT_CLOCK_REALTIME != 2048 { ok = false; }
  if GPIO_V2_LINE_FLAG_EVENT_CLOCK_HTE != 4096 { ok = false; }
  if GPIO_V2_LINE_FLAG_KNOWN_MASK != 8191 { ok = false; }
  if GPIO_V2_LINE_FLAGS_BITS != 13 { ok = false; }
  let flags = GPIO_V2_LINE_FLAG_INPUT + GPIO_V2_LINE_FLAG_EDGE_RISING + GPIO_V2_LINE_FLAG_BIAS_PULL_UP;
  if !gpio_line_flag_set(flags, GPIO_V2_LINE_FLAG_INPUT) { ok = false; }
  if !gpio_line_flag_set(flags, GPIO_V2_LINE_FLAG_EDGE_RISING) { ok = false; }
  if !gpio_line_flag_set(flags, GPIO_V2_LINE_FLAG_BIAS_PULL_UP) { ok = false; }
  if gpio_line_flag_set(flags, GPIO_V2_LINE_FLAG_OUTPUT) { ok = false; }
  if gpio_line_flag_set(flags, GPIO_V2_LINE_FLAG_EDGE_FALLING) { ok = false; }
  if gpio_line_flag_set(flags, GPIO_V2_LINE_FLAG_BIAS_PULL_DOWN) { ok = false; }
  if gpio_line_flag_set(flags, 0) { ok = false; }
  if gpio_line_flag_set(flags, 3) { ok = false; }
  if gpio_line_flag_set(flags, 8192) { ok = false; }
  if gpio_line_flag_set(-1, GPIO_V2_LINE_FLAG_INPUT) { ok = false; }
  if !gpio_line_flag_known(GPIO_V2_LINE_FLAG_EVENT_CLOCK_HTE) { ok = false; }
  if gpio_line_flag_known(0) { ok = false; }
  if gpio_line_flag_known(8192) { ok = false; }
  return assert(ok, "all 13 flag constants are pinned and the set matrix is exact");
}

fn t5() -> TestResult {
  let three = gpio_line_flags_decode(GPIO_V2_LINE_FLAG_USED + GPIO_V2_LINE_FLAG_EVENT_CLOCK_REALTIME + GPIO_V2_LINE_FLAG_EVENT_CLOCK_HTE);
  var ok = iv_eq(three, iv3(GPIO_V2_LINE_FLAG_USED, GPIO_V2_LINE_FLAG_EVENT_CLOCK_REALTIME, GPIO_V2_LINE_FLAG_EVENT_CLOCK_HTE));
  let none = gpio_line_flags_decode(0);
  if none.len() != 0 { ok = false; }
  let neg = gpio_line_flags_decode(-5);
  if neg.len() != 0 { ok = false; }
  let big = GPIO_V2_LINE_FLAG_KNOWN_MASK + 24576 + 65536;
  if gpio_line_flags_known(big) != GPIO_V2_LINE_FLAG_KNOWN_MASK { ok = false; }
  if gpio_line_flags_unknown(big) != 90112 { ok = false; }
  if gpio_line_flags_known(-1) != 0 { ok = false; }
  if gpio_line_flags_unknown(-1) != 0 { ok = false; }
  return assert(ok, "flag set decode order, known mask and unknown-bit split");
}

fn t6() -> TestResult {
  var ok = str_eq(gpio_line_flag_name(GPIO_V2_LINE_FLAG_USED), "used");
  if !str_eq(gpio_line_flag_name(GPIO_V2_LINE_FLAG_ACTIVE_LOW), "active_low") { ok = false; }
  if !str_eq(gpio_line_flag_name(GPIO_V2_LINE_FLAG_INPUT), "input") { ok = false; }
  if !str_eq(gpio_line_flag_name(GPIO_V2_LINE_FLAG_OUTPUT), "output") { ok = false; }
  if !str_eq(gpio_line_flag_name(GPIO_V2_LINE_FLAG_EDGE_RISING), "edge_rising") { ok = false; }
  if !str_eq(gpio_line_flag_name(GPIO_V2_LINE_FLAG_EDGE_FALLING), "edge_falling") { ok = false; }
  if !str_eq(gpio_line_flag_name(GPIO_V2_LINE_FLAG_OPEN_DRAIN), "open_drain") { ok = false; }
  if !str_eq(gpio_line_flag_name(GPIO_V2_LINE_FLAG_OPEN_SOURCE), "open_source") { ok = false; }
  if !str_eq(gpio_line_flag_name(GPIO_V2_LINE_FLAG_BIAS_PULL_UP), "bias_pull_up") { ok = false; }
  if !str_eq(gpio_line_flag_name(GPIO_V2_LINE_FLAG_BIAS_PULL_DOWN), "bias_pull_down") { ok = false; }
  if !str_eq(gpio_line_flag_name(GPIO_V2_LINE_FLAG_BIAS_DISABLED), "bias_disabled") { ok = false; }
  if !str_eq(gpio_line_flag_name(GPIO_V2_LINE_FLAG_EVENT_CLOCK_REALTIME), "event_clock_realtime") { ok = false; }
  if !str_eq(gpio_line_flag_name(GPIO_V2_LINE_FLAG_EVENT_CLOCK_HTE), "event_clock_hte") { ok = false; }
  if !str_eq(gpio_line_flag_name(0), "unknown") { ok = false; }
  if !str_eq(gpio_line_flag_name(8192), "unknown") { ok = false; }
  if !str_eq(gpio_line_flag_name(12), "unknown") { ok = false; }
  if !str_eq(gpio_attr_id_name(GPIO_V2_LINE_ATTR_ID_FLAGS), "flags") { ok = false; }
  if !str_eq(gpio_attr_id_name(GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES), "output_values") { ok = false; }
  if !str_eq(gpio_attr_id_name(GPIO_V2_LINE_ATTR_ID_DEBOUNCE), "debounce") { ok = false; }
  if !str_eq(gpio_attr_id_name(0), "unknown") { ok = false; }
  if !str_eq(gpio_line_changed_type_name(GPIO_V2_LINE_CHANGED_REQUESTED), "requested") { ok = false; }
  if !str_eq(gpio_line_changed_type_name(GPIO_V2_LINE_CHANGED_RELEASED), "released") { ok = false; }
  if !str_eq(gpio_line_changed_type_name(GPIO_V2_LINE_CHANGED_CONFIG), "config") { ok = false; }
  if !str_eq(gpio_line_changed_type_name(9), "unknown") { ok = false; }
  if !str_eq(gpio_event_type_name(GPIO_V2_LINE_EVENT_RISING_EDGE), "rising edge") { ok = false; }
  if !str_eq(gpio_event_type_name(GPIO_V2_LINE_EVENT_FALLING_EDGE), "falling edge") { ok = false; }
  if !str_eq(gpio_event_type_name(0), "unknown") { ok = false; }
  if !gpio_attr_id_ok(1) { ok = false; }
  if !gpio_attr_id_ok(3) { ok = false; }
  if gpio_attr_id_ok(0) { ok = false; }
  if gpio_attr_id_ok(4) { ok = false; }
  if !gpio_num_attrs_ok(0) { ok = false; }
  if !gpio_num_attrs_ok(10) { ok = false; }
  if gpio_num_attrs_ok(11) { ok = false; }
  if gpio_num_attrs_ok(-1) { ok = false; }
  if !gpio_num_lines_ok(1) { ok = false; }
  if !gpio_num_lines_ok(64) { ok = false; }
  if gpio_num_lines_ok(0) { ok = false; }
  if gpio_num_lines_ok(65) { ok = false; }
  if !gpio_event_type_ok(1) { ok = false; }
  if gpio_event_type_ok(0) { ok = false; }
  if !gpio_attr_offset_aligned(288) { ok = false; }
  if gpio_attr_offset_aligned(289) { ok = false; }
  if gpio_attr_offset_aligned(-8) { ok = false; }
  if !gpio_attr_fits(288, 592) { ok = false; }
  if gpio_attr_fits(580, 592) { ok = false; }
  if gpio_u32_to_i32(4294967295) != -1 { ok = false; }
  if gpio_u32_to_i32(2147483648) != 0 - 2147483648 { ok = false; }
  if gpio_u32_to_i32(7) != 7 { ok = false; }
  return assert(ok, "names, predicates and alignment/size helpers");
}

// --------------------------------------------------
//  Attribute tests
// --------------------------------------------------

fn t7() -> TestResult {
  let a1 = hb("01000000000000000807060504030201");
  let r1 = gpio_line_attribute_decode(&a1, 0);
  if !r1.is_ok {
    return assert(false, "flags attribute must decode");
  }
  let at1: GpioLineAttribute = r1.value;
  var ok = at1.id == GPIO_V2_LINE_ATTR_ID_FLAGS;
  if at1.value != 72623859790382856 { ok = false; }
  let a2 = attr16(GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES, 258);
  let r2 = gpio_line_attribute_decode(&a2, 0);
  if !r2.is_ok { ok = false; } else {
    let at2: GpioLineAttribute = r2.value;
    if at2.id != GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES { ok = false; }
    if at2.value != 258 { ok = false; }
  }
  let a3 = attr16_dead(GPIO_V2_LINE_ATTR_ID_DEBOUNCE, 100000, 3735928559);
  let r3 = gpio_line_attribute_decode(&a3, 0);
  if !r3.is_ok { ok = false; } else {
    let at3: GpioLineAttribute = r3.value;
    if at3.id != GPIO_V2_LINE_ATTR_ID_DEBOUNCE { ok = false; }
    if at3.value != 100000 { ok = false; }
  }
  var prefixed = Vec[UInt8].new();
  push_zeros(&mut prefixed, 4);
  let a0 = attr16(GPIO_V2_LINE_ATTR_ID_FLAGS, 0);
  var k = 0;
  while k < a0.len() {
    prefixed.push(a0[k]);
    k = k + 1;
  }
  let r4 = gpio_line_attribute_decode(&prefixed, 4);
  if !r4.is_ok { ok = false; } else {
    let at4: GpioLineAttribute = r4.value;
    if at4.value != 0 { ok = false; }
  }
  return assert(ok, "attribute decode: hex-pinned u64, OUTPUT_VALUES and DEBOUNCE top half");
}

fn t8() -> TestResult {
  var badpad = attr16(GPIO_V2_LINE_ATTR_ID_FLAGS, 3);
  set_byte(&mut badpad, 4, 255);
  var ok = err_attr_is(gpio_line_attribute_decode(&badpad, 0), "gpio: line attribute at offset 0: bad padding at offset 4: expected zero byte, found 255");
  let badid = attr16(9, 0);
  if !err_attr_is(gpio_line_attribute_decode(&badid, 0), "gpio: line attribute at offset 0: unknown id 9") { ok = false; }
  var trunc = Vec[UInt8].new();
  var i = 0;
  while i < 15 {
    trunc.push(1);
    i = i + 1;
  }
  if !err_attr_is(gpio_line_attribute_decode(&trunc, 0), "gpio: line attribute at offset 0: truncated at offset 15: need 16 bytes, have 15") { ok = false; }
  if !err_attr_is(gpio_line_attribute_decode(&badid, 8), "gpio: line attribute at offset 8: truncated at offset 16: need 16 bytes, have 8") { ok = false; }
  var bit63 = attr16(GPIO_V2_LINE_ATTR_ID_FLAGS, 1);
  set_byte(&mut bit63, 15, 128);
  if !err_attr_is(gpio_line_attribute_decode(&bit63, 0), "gpio: line attribute value: 64-bit value at offset 8 has bit 63 set (not representable as Int)") { ok = false; }
  var out = Vec[UInt8].new();
  let e1 = gpio_line_attribute_encode_into(&mut out, 0, 0);
  if !err_unit_is(e1, "gpio: line attribute: unknown id 0") { ok = false; }
  if out.len() != 0 { ok = false; }
  let e2 = gpio_line_attribute_encode_into(&mut out, 1, -1);
  if !err_unit_is(e2, "gpio: line attribute: value -1 is negative") { ok = false; }
  let e3 = gpio_line_attribute_encode_into(&mut out, 3, 4294967296);
  if !err_unit_is(e3, "gpio: line attribute: debounce period 4294967296 does not fit in u32") { ok = false; }
  let e4 = gpio_line_attribute_encode_into(&mut out, 1, 5);
  if !e4.is_ok { ok = false; }
  if out.len() != 16 { ok = false; }
  if !bytes_equal(out, attr16(1, 5)) { ok = false; }
  let e5 = gpio_line_attribute_encode_into(&mut out, 3, 7);
  if !e5.is_ok { ok = false; }
  var expected = Vec[UInt8].new();
  push_u32(&mut expected, 1);
  push_zeros(&mut expected, 4);
  push_u64(&mut expected, 5);
  push_u32(&mut expected, 3);
  push_zeros(&mut expected, 4);
  push_u32(&mut expected, 7);
  push_zeros(&mut expected, 4);
  if !bytes_equal(out, expected) { ok = false; }
  return assert(ok, "attribute padding/id/bit63 errors and atomic encode");
}

// --------------------------------------------------
//  Config tests
// --------------------------------------------------

fn t9() -> TestResult {
  let ids = iv3(GPIO_V2_LINE_ATTR_ID_FLAGS, GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES, GPIO_V2_LINE_ATTR_ID_DEBOUNCE);
  let vals = iv3(20, 1, 50000);
  let masks = iv3(3, 3, 3);
  let b = config_bytes(24, ids, vals, masks);
  let r = gpio_line_config_decode(&b);
  if !r.is_ok {
    return assert(false, "config must decode");
  }
  let c: GpioLineConfig = r.value;
  var ok = c.flags == 24;
  if !iv_eq(c.attr_ids, ids) { ok = false; }
  if !iv_eq(c.attr_values, vals) { ok = false; }
  if !iv_eq(c.attr_masks, masks) { ok = false; }
  var b2 = clone_bytes(&b);
  set_byte(&mut b2, 92, 171);
  set_byte(&mut b2, 93, 205);
  set_byte(&mut b2, 94, 239);
  set_byte(&mut b2, 95, 18);
  let r2 = gpio_line_config_decode(&b2);
  if !r2.is_ok { ok = false; } else {
    let c2: GpioLineConfig = r2.value;
    let v2: Int = c2.attr_values[2];
    if v2 != 50000 { ok = false; }
  }
  return assert(ok, "config decode: flags, three attribute kinds, DEBOUNCE top half ignored");
}

fn t10() -> TestResult {
  let ids = iv1(GPIO_V2_LINE_ATTR_ID_FLAGS);
  let vals = iv1(4);
  let masks = iv1(1);
  let base = config_bytes(8, ids, vals, masks);
  var small = Vec[UInt8].new();
  var i = 0;
  while i < 271 {
    small.push(base[i]);
    i = i + 1;
  }
  var ok = err_config_is(gpio_line_config_decode(&small), "gpio: line config: truncated at offset 271: need 272 bytes, have 271");
  var fat = clone_bytes(&base);
  fat.push(0);
  if !err_config_is(gpio_line_config_decode(&fat), "gpio: line config: buffer has 273 bytes, expected exactly 272") { ok = false; }
  var many = clone_bytes(&base);
  set_byte(&mut many, 8, 11);
  if !err_config_is(gpio_line_config_decode(&many), "gpio: line config: num_attrs 11 out of range 0..10 at offset 8") { ok = false; }
  var badpad = clone_bytes(&base);
  set_byte(&mut badpad, 12, 255);
  if !err_config_is(gpio_line_config_decode(&badpad), "gpio: line config: bad padding at offset 12: expected zero byte, found 255") { ok = false; }
  var badattr = clone_bytes(&base);
  set_byte(&mut badattr, 36, 7);
  if !err_config_is(gpio_line_config_decode(&badattr), "gpio: line attribute at offset 32: bad padding at offset 36: expected zero byte, found 7") { ok = false; }
  let outside = config_bytes(8, iv1(GPIO_V2_LINE_ATTR_ID_OUTPUT_VALUES), iv1(4), iv1(3));
  if !err_config_is(gpio_line_config_decode(&outside), "gpio: line config: attr 0 output values 4 have bits outside mask 3") { ok = false; }
  let badid = config_bytes(8, iv1(9), iv1(0), iv1(1));
  if !err_config_is(gpio_line_config_decode(&badid), "gpio: line attribute at offset 32: unknown id 9") { ok = false; }
  var bit63 = clone_bytes(&base);
  set_byte(&mut bit63, 55, 128);
  if !err_config_is(gpio_line_config_decode(&bit63), "gpio: line config attr mask: 64-bit value at offset 48 has bit 63 set (not representable as Int)") { ok = false; }
  return assert(ok, "config decode rejections: size, num_attrs, padding, values/mask, bit63");
}

fn t11() -> TestResult {
  let ids = iv2(GPIO_V2_LINE_ATTR_ID_FLAGS, GPIO_V2_LINE_ATTR_ID_DEBOUNCE);
  let vals = iv2(20, 2500);
  let masks = iv2(1, 1);
  let b = config_bytes(20, ids, vals, masks);
  let r = gpio_line_config_decode(&b);
  if !r.is_ok {
    return assert(false, "config must decode");
  }
  let c: GpioLineConfig = r.value;
  let e = gpio_line_config_encode(&c);
  if !e.is_ok {
    return assert(false, "config must encode");
  }
  let eb: Vec[UInt8] = e.value;
  var ok = bytes_equal(eb, b);
  var fresh = gpio_line_config_new();
  if fresh.flags != 0 { ok = false; }
  if fresh.attr_ids.len() != 0 { ok = false; }
  let f1 = gpio_line_config_set_flags(&mut fresh, 7);
  if !f1.is_ok { ok = false; }
  let f2 = gpio_line_config_set_flags(&mut fresh, -1);
  if !err_unit_is(f2, "gpio: line config: flags -1 are negative (64-bit fields are unsigned)") { ok = false; }
  let a1 = gpio_line_config_add_attr(&mut fresh, GPIO_V2_LINE_ATTR_ID_FLAGS, 3, 1);
  let a2 = gpio_line_config_add_attr(&mut fresh, GPIO_V2_LINE_ATTR_ID_DEBOUNCE, 1000, 1);
  if !a1.is_ok || !a2.is_ok { ok = false; }
  let a3 = gpio_line_config_add_attr(&mut fresh, 9, 0, 1);
  if !err_unit_is(a3, "gpio: line config: attr 2 has unknown id 9") { ok = false; }
  if fresh.attr_ids.len() != 2 { ok = false; }
  let fr = gpio_line_config_encode(&fresh);
  if !fr.is_ok { ok = false; } else {
    let fb: Vec[UInt8] = fr.value;
    let fd = gpio_line_config_decode(&fb);
    if !fd.is_ok { ok = false; } else {
      let fc: GpioLineConfig = fd.value;
      if fc.flags != 7 { ok = false; }
      if !iv_eq(fc.attr_values, iv2(3, 1000)) { ok = false; }
    }
  }
  let manyids = iv3(1, 1, 1);
  var cfg11 = cfg_of(0, manyids, iv3(1, 1, 1), iv3(1, 1, 1));
  var k = 3;
  while k < 11 {
    cfg11.attr_ids.push(GPIO_V2_LINE_ATTR_ID_FLAGS);
    cfg11.attr_values.push(1);
    cfg11.attr_masks.push(1);
    k = k + 1;
  }
  if !err_bytes_is(gpio_line_config_encode(&cfg11), "gpio: line config: 11 attributes exceed the maximum of 10") { ok = false; }
  let skew = cfg_of(0, iv1(1), iv2(1, 2), iv1(1));
  if !err_bytes_is(gpio_line_config_encode(&skew), "gpio: line config: attribute arrays out of step (1 ids, 2 values, 1 masks)") { ok = false; }
  let minus = cfg_of(-1, Vec[Int].new(), Vec[Int].new(), Vec[Int].new());
  if !err_bytes_is(gpio_line_config_encode(&minus), "gpio: line config: flags -1 are negative (64-bit fields are unsigned)") { ok = false; }
  var out = Vec[UInt8].new();
  out.push(99);
  let er = gpio_line_config_encode_into(&mut out, &minus);
  if er.is_ok { ok = false; }
  if out.len() != 1 { ok = false; }
  return assert(ok, "config encode round-trip, builder and rejection catalog");
}

fn req_of(offsets: Vec[Int], consumer: Str, num_lines: Int, ebs: Int, fd: Int, flags: Int, ids: Vec[Int], vals: Vec[Int], masks: Vec[Int]) -> GpioLineRequest {
  return GpioLineRequest{
    offsets: offsets;
    consumer: consumer;
    num_lines: num_lines;
    event_buffer_size: ebs;
    fd: fd;
    config_flags: flags;
    attr_ids: ids;
    attr_values: vals;
    attr_masks: masks;
  };
}

fn ev_of(ts: Int, id: Int, line_offset: Int, seqno: Int, line_seqno: Int) -> GpioLineEvent {
  return GpioLineEvent{ timestamp_ns: ts; event_type: id; line_offset: line_offset; global_seqno: seqno; line_seqno: line_seqno; };
}

fn info_of(name: Str, consumer: Str, line_offset: Int, flags: Int, ids: Vec[Int], vals: Vec[Int], num_attrs: Int) -> GpioLineInfo {
  return GpioLineInfo{ name: name; consumer: consumer; line_offset: line_offset; num_attrs: num_attrs; flags: flags; attr_ids: ids; attr_values: vals; };
}

// --------------------------------------------------
//  Line request tests
// --------------------------------------------------

fn t12() -> TestResult {
  let offsets = iv2(3, 17);
  let ids = iv2(GPIO_V2_LINE_ATTR_ID_FLAGS, GPIO_V2_LINE_ATTR_ID_DEBOUNCE);
  let vals = iv2(20, 2000);
  let masks = iv2(3, 3);
  let b = request_bytes(offsets, "gpio-test", 20, ids, vals, masks, 2, 16, 4294967295);
  let r = gpio_line_request_decode(&b);
  if !r.is_ok {
    return assert(false, "line request must decode");
  }
  let q: GpioLineRequest = r.value;
  var ok = iv_eq(q.offsets, offsets);
  if !str_eq(q.consumer, "gpio-test") { ok = false; }
  if q.num_lines != 2 { ok = false; }
  if q.event_buffer_size != 16 { ok = false; }
  if q.fd != 4294967295 { ok = false; }
  if gpio_u32_to_i32(q.fd) != -1 { ok = false; }
  if q.config_flags != 20 { ok = false; }
  if !iv_eq(q.attr_ids, ids) { ok = false; }
  if !iv_eq(q.attr_values, vals) { ok = false; }
  if !iv_eq(q.attr_masks, masks) { ok = false; }
  var b2 = clone_bytes(&b);
  set_byte(&mut b2, 8, 99);
  let r2 = gpio_line_request_decode(&b2);
  if !r2.is_ok { ok = false; } else {
    let q2: GpioLineRequest = r2.value;
    if !iv_eq(q2.offsets, offsets) { ok = false; }
  }
  return assert(ok, "line request decode: offsets, consumer, config, fd and unused tail");
}

fn t13() -> TestResult {
  let b = request_bytes(iv1(5), "c", 4, Vec[Int].new(), Vec[Int].new(), Vec[Int].new(), 1, 0, 0);
  var small = Vec[UInt8].new();
  var i = 0;
  while i < 591 {
    small.push(b[i]);
    i = i + 1;
  }
  var ok = err_request_is(gpio_line_request_decode(&small), "gpio: line request: truncated at offset 591: need 592 bytes, have 591");
  var fat = clone_bytes(&b);
  fat.push(0);
  if !err_request_is(gpio_line_request_decode(&fat), "gpio: line request: buffer has 593 bytes, expected exactly 592") { ok = false; }
  var zero = clone_bytes(&b);
  set_byte(&mut zero, 560, 0);
  if !err_request_is(gpio_line_request_decode(&zero), "gpio: line request: num_lines 0 out of range 1..64 at offset 560") { ok = false; }
  var big = clone_bytes(&b);
  set_byte(&mut big, 560, 65);
  if !err_request_is(gpio_line_request_decode(&big), "gpio: line request: num_lines 65 out of range 1..64 at offset 560") { ok = false; }
  let dup = request_bytes(iv2(5, 5), "c", 4, Vec[Int].new(), Vec[Int].new(), Vec[Int].new(), 2, 0, 0);
  let want_dup = "gpio: line request: duplicate line offset " + int_to_string(5) + " at offsets entry 1 (byte offset 4)";
  if !err_request_is(gpio_line_request_decode(&dup), want_dup) { ok = false; }
  var pad = clone_bytes(&b);
  set_byte(&mut pad, 568, 1);
  if !err_request_is(gpio_line_request_decode(&pad), "gpio: line request: bad padding at offset 568: expected zero byte, found 1") { ok = false; }
  var cfgpad = clone_bytes(&b);
  set_byte(&mut cfgpad, 300, 255);
  if !err_request_is(gpio_line_request_decode(&cfgpad), "gpio: line config: bad padding at offset 300: expected zero byte, found 255") { ok = false; }
  let none = req_of(iv3(1, 2, 3), "c", 2, 0, 0, 4, Vec[Int].new(), Vec[Int].new(), Vec[Int].new());
  if !err_bytes_is(gpio_line_request_encode(&none), "gpio: line request: offsets length 3 does not match num_lines 2") { ok = false; }
  let nolines = req_of(Vec[Int].new(), "c", 0, 0, 0, 4, Vec[Int].new(), Vec[Int].new(), Vec[Int].new());
  if !err_bytes_is(gpio_line_request_encode(&nolines), "gpio: line request: num_lines 0 out of range 1..64") { ok = false; }
  let longconsumer = "abcdefghij0123456789abcdefghijkl";
  let badc = req_of(iv1(1), longconsumer, 1, 0, 0, 4, Vec[Int].new(), Vec[Int].new(), Vec[Int].new());
  if !err_bytes_is(gpio_line_request_encode(&badc), "gpio: consumer is 32 bytes, needs at most 31 plus NUL within 32") { ok = false; }
  let badfd = req_of(iv1(1), "c", 1, 0, 4294967296, 4, Vec[Int].new(), Vec[Int].new(), Vec[Int].new());
  if !err_bytes_is(gpio_line_request_encode(&badfd), "gpio: line request: fd 4294967296 does not fit in u32") { ok = false; }
  let negfd = req_of(iv1(1), "c", 1, 0, -1, 4, Vec[Int].new(), Vec[Int].new(), Vec[Int].new());
  if !err_bytes_is(gpio_line_request_encode(&negfd), "gpio: line request: fd -1 does not fit in u32") { ok = false; }
  let dupe = req_of(iv2(5, 5), "c", 2, 0, 0, 4, Vec[Int].new(), Vec[Int].new(), Vec[Int].new());
  if !err_bytes_is(gpio_line_request_encode(&dupe), "gpio: line request: duplicate line offset 5 at offsets entry 1") { ok = false; }
  let huge = req_of(iv1(4294967296), "c", 1, 0, 0, 4, Vec[Int].new(), Vec[Int].new(), Vec[Int].new());
  if !err_bytes_is(gpio_line_request_encode(&huge), "gpio: line request: line offset 4294967296 at offsets entry 0 does not fit in u32") { ok = false; }
  return assert(ok, "line request rejection catalog: sizes, num_lines, duplicates, padding, encode ranges");
}

// --------------------------------------------------
//  Line event tests
// --------------------------------------------------

fn t14() -> TestResult {
  let b = event_bytes(72623859790382856, GPIO_V2_LINE_EVENT_RISING_EDGE, 10, 2, 1);
  let r = gpio_line_event_decode(&b);
  if !r.is_ok {
    return assert(false, "line event must decode");
  }
  let ev: GpioLineEvent = r.value;
  var ok = ev.timestamp_ns == 72623859790382856;
  if ev.event_type != GPIO_V2_LINE_EVENT_RISING_EDGE { ok = false; }
  if ev.line_offset != 10 { ok = false; }
  if ev.global_seqno != 2 { ok = false; }
  if ev.line_seqno != 1 { ok = false; }
  if !str_eq(gpio_event_type_name(ev.event_type), "rising edge") { ok = false; }
  let e = gpio_line_event_encode(&ev);
  if !e.is_ok { ok = false; } else {
    let eb: Vec[UInt8] = e.value;
    if !bytes_equal(eb, b) { ok = false; }
  }
  var pinned = hb("0807060504030201010000000a0000000200000001000000");
  push_zeros(&mut pinned, 24);
  if !bytes_equal(b, pinned) { ok = false; }
  let maxev = event_bytes(9223372036854775807, GPIO_V2_LINE_EVENT_FALLING_EDGE, 0, 4294967295, 4294967295);
  let r2 = gpio_line_event_decode(&maxev);
  if !r2.is_ok { ok = false; } else {
    let ev2: GpioLineEvent = r2.value;
    if ev2.timestamp_ns != 9223372036854775807 { ok = false; }
    if ev2.event_type != GPIO_V2_LINE_EVENT_FALLING_EDGE { ok = false; }
    if ev2.global_seqno != 4294967295 { ok = false; }
  }
  return assert(ok, "line event: 64-bit timestamp, ids, seqnos and pinned LE bytes");
}

fn t15() -> TestResult {
  let b = event_bytes(1, 1, 0, 0, 0);
  var small = Vec[UInt8].new();
  var i = 0;
  while i < 47 {
    small.push(b[i]);
    i = i + 1;
  }
  var ok = err_event_is(gpio_line_event_decode(&small), "gpio: line event: truncated at offset 47: need 48 bytes, have 47");
  var fat = clone_bytes(&b);
  fat.push(0);
  if !err_event_is(gpio_line_event_decode(&fat), "gpio: line event: buffer has 49 bytes, expected exactly 48") { ok = false; }
  let badid = event_bytes(1, 3, 0, 0, 0);
  if !err_event_is(gpio_line_event_decode(&badid), "gpio: line event: unknown event id 3 at offset 8") { ok = false; }
  var badpad = clone_bytes(&b);
  set_byte(&mut badpad, 24, 9);
  if !err_event_is(gpio_line_event_decode(&badpad), "gpio: line event: bad padding at offset 24: expected zero byte, found 9") { ok = false; }
  var bit63 = clone_bytes(&b);
  set_byte(&mut bit63, 7, 128);
  if !err_event_is(gpio_line_event_decode(&bit63), "gpio: line event: 64-bit value at offset 0 has bit 63 set (not representable as Int)") { ok = false; }
  if !err_bytes_is(gpio_line_event_encode(&ev_of(-1, 1, 0, 0, 0)), "gpio: line event: timestamp -1 is negative") { ok = false; }
  if !err_bytes_is(gpio_line_event_encode(&ev_of(1, 0, 0, 0, 0)), "gpio: line event: event id 0 is not 1 (rising) or 2 (falling)") { ok = false; }
  if !err_bytes_is(gpio_line_event_encode(&ev_of(1, 1, -1, 0, 0)), "gpio: line event: line offset -1 does not fit in u32") { ok = false; }
  if !err_bytes_is(gpio_line_event_encode(&ev_of(1, 1, 0, 4294967296, 0)), "gpio: line event: global_seqno 4294967296 does not fit in u32") { ok = false; }
  return assert(ok, "line event rejection catalog: size, id, padding, bit63, encode ranges");
}

// --------------------------------------------------
//  Line info tests
// --------------------------------------------------

fn t16() -> TestResult {
  let ids = iv2(GPIO_V2_LINE_ATTR_ID_FLAGS, GPIO_V2_LINE_ATTR_ID_DEBOUNCE);
  let vals = iv2(4, 1000);
  let b = info_bytes("GPIO17", "sysfs", 17, GPIO_V2_LINE_FLAG_USED + GPIO_V2_LINE_FLAG_INPUT + GPIO_V2_LINE_FLAG_ACTIVE_LOW, ids, vals, 2);
  let r = gpio_line_info_decode(&b);
  if !r.is_ok {
    return assert(false, "line info must decode");
  }
  let inf: GpioLineInfo = r.value;
  var ok = str_eq(inf.name, "GPIO17");
  if !str_eq(inf.consumer, "sysfs") { ok = false; }
  if inf.line_offset != 17 { ok = false; }
  if inf.num_attrs != 2 { ok = false; }
  if inf.flags != 7 { ok = false; }
  if !iv_eq(inf.attr_ids, ids) { ok = false; }
  if !iv_eq(inf.attr_values, vals) { ok = false; }
  if !gpio_line_flag_set(inf.flags, GPIO_V2_LINE_FLAG_USED) { ok = false; }
  if !gpio_line_flag_set(inf.flags, GPIO_V2_LINE_FLAG_INPUT) { ok = false; }
  if gpio_line_flag_set(inf.flags, GPIO_V2_LINE_FLAG_OUTPUT) { ok = false; }
  var b2 = clone_bytes(&b);
  set_byte(&mut b2, 112, 77);
  let r2 = gpio_line_info_decode(&b2);
  if !r2.is_ok { ok = false; }
  let e = gpio_line_info_encode(&inf);
  if !e.is_ok { ok = false; } else {
    let eb: Vec[UInt8] = e.value;
    if !bytes_equal(eb, b) { ok = false; }
  }
  return assert(ok, "line info decode: names, offset, flags and attribute array");
}

fn t17() -> TestResult {
  let ids = iv1(GPIO_V2_LINE_ATTR_ID_FLAGS);
  let vals = iv1(4);
  let b = info_bytes("GPIO17", "sysfs", 17, 7, ids, vals, 1);
  var small = Vec[UInt8].new();
  var i = 0;
  while i < 255 {
    small.push(b[i]);
    i = i + 1;
  }
  var ok = err_info_is(gpio_line_info_decode(&small), "gpio: line info: truncated at offset 255: need 256 bytes, have 255");
  var fat = clone_bytes(&b);
  fat.push(0);
  if !err_info_is(gpio_line_info_decode(&fat), "gpio: line info: buffer has 257 bytes, expected exactly 256") { ok = false; }
  var many = clone_bytes(&b);
  set_byte(&mut many, 68, 11);
  if !err_info_is(gpio_line_info_decode(&many), "gpio: line info: num_attrs 11 out of range 0..10 at offset 68") { ok = false; }
  var noname = Vec[UInt8].new();
  i = 0;
  while i < 32 {
    noname.push(65);
    i = i + 1;
  }
  push_cstr32(&mut noname, "c");
  push_zeros(&mut noname, 192);
  if !err_info_is(gpio_line_info_decode(&noname), "gpio: name at offset 0 has no NUL within 32 bytes") { ok = false; }
  var badattr = clone_bytes(&b);
  set_byte(&mut badattr, 84, 3);
  if !err_info_is(gpio_line_info_decode(&badattr), "gpio: line attribute at offset 80: bad padding at offset 84: expected zero byte, found 3") { ok = false; }
  var badpad = clone_bytes(&b);
  set_byte(&mut badpad, 240, 1);
  if !err_info_is(gpio_line_info_decode(&badpad), "gpio: line info: bad padding at offset 240: expected zero byte, found 1") { ok = false; }
  let longname = "abcdefghij0123456789abcdefghijkl";
  if !err_bytes_is(gpio_line_info_encode(&info_of(longname, "c", 0, 0, Vec[Int].new(), Vec[Int].new(), 0)), "gpio: name is 32 bytes, needs at most 31 plus NUL within 32") { ok = false; }
  if !err_bytes_is(gpio_line_info_encode(&info_of("n", "c", 0, 0, iv2(1, 3), iv2(1, 2), 3)), "gpio: line info: num_attrs 3 does not match 2 id / 2 value entries") { ok = false; }
  if !err_bytes_is(gpio_line_info_encode(&info_of("n", "c", 0, 0, iv1(9), iv1(0), 1)), "gpio: line info: attr 0 has unknown id 9") { ok = false; }
  if !err_bytes_is(gpio_line_info_encode(&info_of("n", "c", 0, -1, Vec[Int].new(), Vec[Int].new(), 0)), "gpio: line info: flags -1 are negative (64-bit fields are unsigned)") { ok = false; }
  var out = Vec[UInt8].new();
  out.push(7);
  let er = gpio_line_info_encode_into(&mut out, &info_of(longname, "c", 0, 0, Vec[Int].new(), Vec[Int].new(), 0));
  if er.is_ok { ok = false; }
  if out.len() != 1 { ok = false; }
  return assert(ok, "line info rejection catalog: size, num_attrs, names, padding, encode ranges");
}

// --------------------------------------------------
//  Line values tests
// --------------------------------------------------

fn t18() -> TestResult {
  let pinned = hb("05000000000000000700000000000000");
  let r = gpio_line_values_decode(&pinned);
  if !r.is_ok {
    return assert(false, "line values must decode");
  }
  let lv: GpioLineValues = r.value;
  var ok = lv.bits == 5;
  if lv.mask != 7 { ok = false; }
  let e = gpio_line_values_encode(&lv);
  if !e.is_ok { ok = false; } else {
    let eb: Vec[UInt8] = e.value;
    if !bytes_equal(eb, pinned) { ok = false; }
  }
  var small = Vec[UInt8].new();
  var i = 0;
  while i < 15 {
    small.push(pinned[i]);
    i = i + 1;
  }
  if !err_values_is(gpio_line_values_decode(&small), "gpio: line values: truncated at offset 15: need 16 bytes, have 15") { ok = false; }
  var fat = clone_bytes(&pinned);
  fat.push(0);
  if !err_values_is(gpio_line_values_decode(&fat), "gpio: line values: buffer has 17 bytes, expected exactly 16") { ok = false; }
  var bit63 = clone_bytes(&pinned);
  set_byte(&mut bit63, 7, 128);
  if !err_values_is(gpio_line_values_decode(&bit63), "gpio: line values bits: 64-bit value at offset 0 has bit 63 set (not representable as Int)") { ok = false; }
  var mask63 = clone_bytes(&pinned);
  set_byte(&mut mask63, 15, 128);
  if !err_values_is(gpio_line_values_decode(&mask63), "gpio: line values mask: 64-bit value at offset 8 has bit 63 set (not representable as Int)") { ok = false; }
  if !err_bytes_is(gpio_line_values_encode(&GpioLineValues{ bits: -1; mask: 1; }), "gpio: line values: bits -1 are negative (64-bit fields are unsigned)") { ok = false; }
  if !err_bytes_is(gpio_line_values_encode(&GpioLineValues{ bits: 1; mask: -1; }), "gpio: line values: mask -1 are negative (64-bit fields are unsigned)") { ok = false; }
  return assert(ok, "line values: hex-pinned bits/mask, bit63 rejection and encode ranges");
}

// --------------------------------------------------
//  Zero-buffer classification and determinism
// --------------------------------------------------

fn t19() -> TestResult {
  var chip0 = Vec[UInt8].new();
  push_zeros(&mut chip0, 68);
  let cr = gpio_chip_info_decode(&chip0);
  var ok = cr.is_ok;
  if cr.is_ok {
    let c: GpioChipInfo = cr.value;
    if c.name.len() != 0 { ok = false; }
    if c.lines != 0 { ok = false; }
  }
  var cfg0 = Vec[UInt8].new();
  push_zeros(&mut cfg0, 272);
  let cfr = gpio_line_config_decode(&cfg0);
  if !cfr.is_ok { ok = false; } else {
    let c: GpioLineConfig = cfr.value;
    if c.flags != 0 { ok = false; }
    if c.attr_ids.len() != 0 { ok = false; }
  }
  var info0 = Vec[UInt8].new();
  push_zeros(&mut info0, 256);
  let ir = gpio_line_info_decode(&info0);
  if !ir.is_ok { ok = false; } else {
    let inf: GpioLineInfo = ir.value;
    if inf.num_attrs != 0 { ok = false; }
    if inf.flags != 0 { ok = false; }
  }
  var val0 = Vec[UInt8].new();
  push_zeros(&mut val0, 16);
  let vr = gpio_line_values_decode(&val0);
  if !vr.is_ok { ok = false; }
  var ev0 = Vec[UInt8].new();
  push_zeros(&mut ev0, 48);
  if !err_event_is(gpio_line_event_decode(&ev0), "gpio: line event: unknown event id 0 at offset 8") { ok = false; }
  var req0 = Vec[UInt8].new();
  push_zeros(&mut req0, 592);
  if !err_request_is(gpio_line_request_decode(&req0), "gpio: line request: num_lines 0 out of range 1..64 at offset 560") { ok = false; }
  var attr0 = Vec[UInt8].new();
  push_zeros(&mut attr0, 16);
  if !err_attr_is(gpio_line_attribute_decode(&attr0, 0), "gpio: line attribute at offset 0: unknown id 0") { ok = false; }
  let b = request_bytes(iv2(1, 2), "d", 4, Vec[Int].new(), Vec[Int].new(), Vec[Int].new(), 2, 0, 0);
  let d1 = gpio_line_request_decode(&b);
  let d2 = gpio_line_request_decode(&b);
  if !d1.is_ok || !d2.is_ok { ok = false; } else {
    let q1: GpioLineRequest = d1.value;
    let q2: GpioLineRequest = d2.value;
    if !iv_eq(q1.offsets, q2.offsets) { ok = false; }
    let e1 = gpio_line_request_encode(&q1);
    let e2 = gpio_line_request_encode(&q2);
    if !e1.is_ok || !e2.is_ok { ok = false; } else {
      let x1: Vec[UInt8] = e1.value;
      let x2: Vec[UInt8] = e2.value;
      if !bytes_equal(x1, x2) { ok = false; }
    }
  }
  return assert(ok, "all-zero buffers classify as documented and decoding is deterministic");
}

// --------------------------------------------------
//  Pipeline and hex-pinned vectors
// --------------------------------------------------

fn t20() -> TestResult {
  var req = gpio_line_request_new();
  var ok = req.num_lines == 0;
  let o1 = gpio_line_request_add_offset(&mut req, 7);
  let o2 = gpio_line_request_add_offset(&mut req, 21);
  let o3 = gpio_line_request_add_offset(&mut req, 7);
  if !o1.is_ok || !o2.is_ok { ok = false; }
  if !err_unit_is(o3, "gpio: line request: duplicate line offset 7") { ok = false; }
  if req.num_lines != 2 { ok = false; }
  let c1 = gpio_line_request_set_consumer(&mut req, "xiom-gpio-test");
  if !c1.is_ok { ok = false; }
  let c2 = gpio_line_request_set_consumer(&mut req, "abcdefghij0123456789abcdefghijkl");
  if !err_unit_is(c2, "gpio: consumer is 32 bytes, needs at most 31 plus NUL within 32") { ok = false; }
  let g1 = gpio_line_request_set_config_flags(&mut req, GPIO_V2_LINE_FLAG_INPUT + GPIO_V2_LINE_FLAG_EDGE_RISING);
  if !g1.is_ok { ok = false; }
  let g2 = gpio_line_request_set_config_flags(&mut req, -1);
  if !err_unit_is(g2, "gpio: line config: flags -1 are negative (64-bit fields are unsigned)") { ok = false; }
  req.attr_ids.push(GPIO_V2_LINE_ATTR_ID_DEBOUNCE);
  req.attr_values.push(5000);
  req.attr_masks.push(3);
  req.event_buffer_size = 64;
  req.fd = 12;
  let e = gpio_line_request_encode(&req);
  if !e.is_ok {
    return assert(false, "request must encode");
  }
  let eb: Vec[UInt8] = e.value;
  let d = gpio_line_request_decode(&eb);
  if !d.is_ok {
    return assert(false, "encoded request must decode");
  }
  let q: GpioLineRequest = d.value;
  if !iv_eq(q.offsets, iv2(7, 21)) { ok = false; }
  if !str_eq(q.consumer, "xiom-gpio-test") { ok = false; }
  if q.num_lines != 2 { ok = false; }
  if q.event_buffer_size != 64 { ok = false; }
  if q.fd != 12 { ok = false; }
  if q.config_flags != 20 { ok = false; }
  if !iv_eq(q.attr_values, iv1(5000)) { ok = false; }
  let e2 = gpio_line_request_encode(&q);
  if !e2.is_ok { ok = false; } else {
    let eb2: Vec[UInt8] = e2.value;
    if !bytes_equal(eb, eb2) { ok = false; }
  }
  return assert(ok, "request builder pipeline: add/validate/encode/decode round-trip");
}

fn t21() -> TestResult {
  let want = hb("6770696f" + "00000000000000000000000000000000000000000000000000000000" + "6c626c" + "0000000000000000000000000000000000000000000000000000000000" + "03000000");
  let got = chip_bytes("gpio", "lbl", 3);
  var ok = bytes_equal(got, want);
  let a = hb("01000000000000000000000000000000");
  let ar = gpio_line_attribute_decode(&a, 0);
  if !ar.is_ok { ok = false; } else {
    let at: GpioLineAttribute = ar.value;
    if at.id != GPIO_V2_LINE_ATTR_ID_FLAGS { ok = false; }
    if at.value != 0 { ok = false; }
  }
  let vp = hb("ff000000000000000300000000000000");
  let vpr = gpio_line_values_decode(&vp);
  if !vpr.is_ok { ok = false; } else {
    let lv: GpioLineValues = vpr.value;
    if lv.bits != 255 { ok = false; }
    if lv.mask != 3 { ok = false; }
  }
  let flaghex = hb("0000000000000000");
  if flaghex.len() != 8 { ok = false; }
  return assert(ok, "hex-pinned chip_info, zero attribute and values vectors");
}

fn main() -> Int {
  io.println("=== xiom.gpio conformance tests ===");
  var failed: Int = 0;
  let r1 = t1();
  if r1.passed { io.println("  [PASS] " + r1.name); } else { io.println("  [FAIL] " + r1.name); failed = failed + 1; }
  let r2 = t2();
  if r2.passed { io.println("  [PASS] " + r2.name); } else { io.println("  [FAIL] " + r2.name); failed = failed + 1; }
  let r3 = t3();
  if r3.passed { io.println("  [PASS] " + r3.name); } else { io.println("  [FAIL] " + r3.name); failed = failed + 1; }
  let r4 = t4();
  if r4.passed { io.println("  [PASS] " + r4.name); } else { io.println("  [FAIL] " + r4.name); failed = failed + 1; }
  let r5 = t5();
  if r5.passed { io.println("  [PASS] " + r5.name); } else { io.println("  [FAIL] " + r5.name); failed = failed + 1; }
  let r6 = t6();
  if r6.passed { io.println("  [PASS] " + r6.name); } else { io.println("  [FAIL] " + r6.name); failed = failed + 1; }
  let r7 = t7();
  if r7.passed { io.println("  [PASS] " + r7.name); } else { io.println("  [FAIL] " + r7.name); failed = failed + 1; }
  let r8 = t8();
  if r8.passed { io.println("  [PASS] " + r8.name); } else { io.println("  [FAIL] " + r8.name); failed = failed + 1; }
  let r9 = t9();
  if r9.passed { io.println("  [PASS] " + r9.name); } else { io.println("  [FAIL] " + r9.name); failed = failed + 1; }
  let r10 = t10();
  if r10.passed { io.println("  [PASS] " + r10.name); } else { io.println("  [FAIL] " + r10.name); failed = failed + 1; }
  let r11 = t11();
  if r11.passed { io.println("  [PASS] " + r11.name); } else { io.println("  [FAIL] " + r11.name); failed = failed + 1; }
  let r12 = t12();
  if r12.passed { io.println("  [PASS] " + r12.name); } else { io.println("  [FAIL] " + r12.name); failed = failed + 1; }
  let r13 = t13();
  if r13.passed { io.println("  [PASS] " + r13.name); } else { io.println("  [FAIL] " + r13.name); failed = failed + 1; }
  let r14 = t14();
  if r14.passed { io.println("  [PASS] " + r14.name); } else { io.println("  [FAIL] " + r14.name); failed = failed + 1; }
  let r15 = t15();
  if r15.passed { io.println("  [PASS] " + r15.name); } else { io.println("  [FAIL] " + r15.name); failed = failed + 1; }
  let r16 = t16();
  if r16.passed { io.println("  [PASS] " + r16.name); } else { io.println("  [FAIL] " + r16.name); failed = failed + 1; }
  let r17 = t17();
  if r17.passed { io.println("  [PASS] " + r17.name); } else { io.println("  [FAIL] " + r17.name); failed = failed + 1; }
  let r18 = t18();
  if r18.passed { io.println("  [PASS] " + r18.name); } else { io.println("  [FAIL] " + r18.name); failed = failed + 1; }
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.gpio: all tests passed");
  } else {
    io.println("xiom.gpio: tests failed");
  }
  return failed;
}
