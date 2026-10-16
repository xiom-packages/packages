// XIOM -- xiom.gps: gpsd JSON-protocol client + NMEA 0183 sentence parsers.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM GPS/GNSS data path for a device fleet:
//   * the documented gpsd request/response protocol (line-JSON over a
//     TCP socket): typed parsers for the core classes VERSION, WATCH,
//     DEVICES, DEVICE, TPV, SKY and ERROR, a line dispatcher, the
//     `?WATCH`/`?VERSION` command builders and a small client session
//     (open/watch/read/next/close) that classifies "no daemon" as
//     GPS_ERR_ABSENT so a suite without a gpsd reports SKIP, never FAIL;
//   * NMEA 0183 sentence parsers for GGA, RMC, GSA and GSV with
//     gpsd-compatible checksum validation, coordinate/time/date
//     decoding and typed Result errors.
//
// Upstream reference (UPSTREAM-FIRST): gpsd, gitlab.com/gpsd/gpsd at
// a184c8a4c028dae94b7599ba01688fb3ddeddd97 (BSD-2-Clause). The JSON
// engine is the stdlib `xiom.serialize.json` module; this package owns
// the gpsd-profile typing on top of it. See SPEC.md for the byte-level
// rules, the divergence notes (strict-typed parse errors vs the
// daemon's tolerant C driver) and the declared non-goals; PROVENANCE.md
// for the clone pin and imported vectors; ROADMAP.md for later phases.
//
// Ownership note: JsonValue values are consumed on extraction (the
// compiler reports moves as warnings), so every message extractor walks
// the object entries exactly once; each consumed entry value is moved
// into at most one typed slot.
//
// G5 note: this module performs no FFI -- the only unsafe surface it
// touches is the stdlib socket module. Parsers never alias their input.

module xiom.gps

use xiom.net.socket;
use xiom.serialize.json;
use xiom.string;
use xiom.string.compare;
use xiom.string.split;
use xiom.string.builder;
use xiom.convert.parse;

// =========================================================================
// Protocol identity and classification
// =========================================================================

/// gpsd protocol major version this package speaks (oracle: upstream
/// SConstruct / android/gpsd_config.in, GPSD_PROTO_VERSION_MAJOR).
pub const GPSD_PROTO_MAJOR: Int = 3;

/// gpsd protocol minor version this package expects at minimum
/// (oracle: upstream pin, GPSD_PROTO_VERSION_MINOR = 15).
pub const GPSD_PROTO_MINOR: Int = 15;

/// TPV `mode`: unknown.
pub const GPS_MODE_UNKNOWN: Int = 0;
/// TPV `mode`: no fix.
pub const GPS_MODE_NO_FIX: Int = 1;
/// TPV `mode`: 2D fix.
pub const GPS_MODE_2D: Int = 2;
/// TPV `mode`: 3D fix.
pub const GPS_MODE_3D: Int = 3;

/// GpsError kind: nothing accepted the connection (no daemon) -> SKIP.
pub const GPS_ERR_ABSENT: Int = 0;
/// GpsError kind: socket I/O failure (closed peer, send failure).
pub const GPS_ERR_IO: Int = 1;
/// GpsError kind: no complete line within the receive deadline.
pub const GPS_ERR_TIMEOUT: Int = 2;
/// GpsError kind: malformed line (JSON, class or field).
pub const GPS_ERR_PARSE: Int = 3;

// =========================================================================
// Types -- gpsd JSON messages
// =========================================================================

/// A typed client-session failure. `kind` is one of the GPS_ERR_*
/// constants; `message` is human-readable and starts with "gps: ".
pub type GpsError = {
  kind: Int;
  message: Str;
}

/// Decoded TPV (time-position-velocity) report. `mode` is always present.
/// Optional fields are omitted attributes on the wire; see SPEC.md for
/// the field-by-field mapping against man/gpsd_json.adoc.
pub type GpsTpv = {
  mode: Int;
  status: Option[Int];
  time: Option[Str];
  device: Option[Str];
  lat: Option[Float64];
  lon: Option[Float64];
  alt_hae: Option[Float64];
  alt_msl: Option[Float64];
  speed: Option[Float64];
  track: Option[Float64];
  climb: Option[Float64];
  eph: Option[Float64];
  epv: Option[Float64];
  ept: Option[Float64];
  eps: Option[Float64];
  geoid_sep: Option[Float64];
  magvar: Option[Float64];
  dgps_age: Option[Float64];
  dgps_sta: Option[Int];
  leapseconds: Option[Int];
}

/// One satellite object inside a SKY report. `PRN` and `used` are always
/// present in daemon output; the rest are optional.
pub type GpsSatellite = {
  prn: Int;
  used: Bool;
  gnssid: Option[Int];
  svid: Option[Int];
  sigid: Option[Int];
  freqid: Option[Int];
  el: Option[Float64];
  az: Option[Float64];
  ss: Option[Float64];
  health: Option[Int];
}

/// Decoded SKY (sky-view) report.
pub type GpsSky = {
  device: Option[Str];
  time: Option[Str];
  gdop: Option[Float64];
  hdop: Option[Float64];
  pdop: Option[Float64];
  tdop: Option[Float64];
  vdop: Option[Float64];
  xdop: Option[Float64];
  ydop: Option[Float64];
  n_sat: Option[Int];
  u_sat: Option[Int];
  satellites: Vec[GpsSatellite];
}

/// Decoded VERSION response. `release` accepts either the "release"
/// attribute (current daemon) or the legacy "version" spelling.
pub type GpsVersion = {
  release: Str;
  rev: Option[Str];
  proto_major: Int;
  proto_minor: Int;
  remote: Option[Str];
}

/// Decoded DEVICE object. `activated` is the ISO-8601 string form;
/// `activated_num` the legacy numeric timestamp form (both exist in
/// upstream captures); at most one is set.
pub type GpsDevice = {
  path: Option[Str];
  driver: Option[Str];
  subtype: Option[Str];
  subtype1: Option[Str];
  activated: Option[Str];
  activated_num: Option[Float64];
  bps: Option[Int];
  parity: Option[Str];
  stopbits: Option[Int];
  native: Option[Int];
  cycle: Option[Float64];
  mincycle: Option[Float64];
  flags: Option[Int];
  readonly: Option[Bool];
  sernum: Option[Str];
}

/// Decoded DEVICES wrapper: the device fleet list.
pub type GpsDevices = {
  devices: Vec[GpsDevice];
  remote: Option[Str];
}

/// Decoded WATCH policy response. Every attribute is an optional
/// per-subscriber policy bit.
pub type GpsWatch = {
  enable: Option[Bool];
  json: Option[Bool];
  nmea: Option[Bool];
  raw: Option[Int];
  scaled: Option[Bool];
  split24: Option[Bool];
  pps: Option[Bool];
  timing: Option[Bool];
  device: Option[Str];
  remote: Option[Str];
}

/// Decoded ERROR notification.
pub type GpsErrorMsg = {
  message: Str;
}

/// One parsed gpsd response line. Classes outside the declared set
/// (GST, ATT, IMU, PPS, AIS, ...) arrive as `Other` with their class
/// name so a streaming client can skip them without failing.
pub type GpsMessage = enum {
  Version(v: GpsVersion),
  Watch(v: GpsWatch),
  Devices(v: GpsDevices),
  Device(v: GpsDevice),
  Tpv(v: GpsTpv),
  Sky(v: GpsSky),
  Error(v: GpsErrorMsg),
  Other(class_name: Str),
}

// =========================================================================
// Types -- NMEA 0183
// =========================================================================

/// UTC time decoded from hhmmss.ss. Fractional seconds are carried as
/// milliseconds (digits beyond the third are truncated).
pub type NmeaTime = {
  hour: Int;
  minute: Int;
  second: Int;
  millis: Int;
}

/// Date decoded from ddmmyy. `year` is the 4-digit windowed year: the
/// two-digit year yy maps to 2000+yy for yy < 69 and 1900+yy otherwise
/// (the upstream 1968 < year < 2069 window rule).
pub type NmeaDate = {
  day: Int;
  month: Int;
  year: Int;
}

/// Parsed GGA (global positioning system fix data).
pub type NmeaGga = {
  talker: Str;
  time: Option[NmeaTime];
  lat: Option[Float64];
  lon: Option[Float64];
  fix_quality: Option[Int];
  num_sats: Option[Int];
  hdop: Option[Float64];
  alt_msl: Option[Float64];
  geoid_sep: Option[Float64];
  dgps_age: Option[Float64];
  dgps_sta: Option[Int];
}

/// Parsed RMC (recommended minimum navigation data). `speed_knots` is
/// in knots as transmitted; `track_deg` degrees true; `magvar_deg` is
/// signed (E positive, W negative) and absent when the value is 0.0
/// within 0.09 degrees (the upstream "some GPS set 0.0,E" rule).
pub type NmeaRmc = {
  talker: Str;
  status: Option[Str];
  time: Option[NmeaTime];
  date: Option[NmeaDate];
  lat: Option[Float64];
  lon: Option[Float64];
  speed_knots: Option[Float64];
  track_deg: Option[Float64];
  magvar_deg: Option[Float64];
  mode_ind: Option[Str];
  nav_status: Option[Str];
}

/// Parsed GSA (GNSS DOP and active satellites). `fix_type` follows the
/// upstream atoi reading (1 = no fix, 2 = 2D, 3 = 3D, anything else
/// reads as 0); `prns` holds the sentence-order satellite numbers with
/// the upstream gate (1..600 kept, zeros skipped) and no constellation
/// PRN re-mapping; DOP values outside 0.01..89.99 are treated as
/// absent (upstream sentinel rule); `system_id` is the NMEA 4.10 field
/// 18, present only in 19-field sentences.
pub type NmeaGsa = {
  talker: Str;
  mode: Option[Str];
  fix_type: Int;
  prns: Vec[Int];
  pdop: Option[Float64];
  hdop: Option[Float64];
  vdop: Option[Float64];
  system_id: Option[Int];
}

/// One satellite record inside a GSV sentence.
pub type NmeaGsvSat = {
  prn: Int;
  el: Option[Int];
  az: Option[Int];
  snr: Option[Int];
}

/// Parsed GSV (satellites in view). A satellite record with empty
/// elevation and azimuth keeps both absent (the upstream both-or-neither
/// rule); azimuth 360 normalizes to 0; elevations outside -90..90 and
/// azimuths outside 0..359 are treated as absent.
pub type NmeaGsv = {
  talker: Str;
  num_msgs: Int;
  msg_num: Int;
  sats_in_view: Int;
  signal_id: Option[Int];
  system_id: Option[Int];
  satellites: Vec[NmeaGsvSat];
}

/// One parsed NMEA sentence. Sentences outside the declared set (VTG,
/// ZDA, ...) arrive as `Other` with talker and sentence kind.
pub type NmeaMessage = enum {
  Gga(v: NmeaGga),
  Rmc(v: NmeaRmc),
  Gsa(v: NmeaGsa),
  Gsv(v: NmeaGsv),
  Other(talker: Str, kind: Str),
}

// =========================================================================
// Types -- gpsd client session
// =========================================================================

/// A live connection to a gpsd daemon. `fd` is -1 once closed. `buf`
/// holds received bytes not yet handed out as complete lines.
pub type GpsClient = {
  fd: Int;
  host: Str;
  port: Int;
  timeout_ms: Int;
  buf: Vec[UInt8];
}

// =========================================================================
// Small shared helpers
// =========================================================================

fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

fn _byte_is_digit(b: Int) -> Bool {
  if b < 48 { return false; }
  if b > 57 { return false; }
  return true;
}

fn _is_digit(s: Str, i: Int) -> Bool {
  return _byte_is_digit((string.byte_at(s, i) as Int) & 0xFF);
}

fn _digits_ok(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if !_is_digit(s, i) { return false; }
    i = i + 1;
  }
  return true;
}

fn _digits_value(s: Str, start: Int, count: Int) -> Int {
  var v = 0;
  var i = 0;
  while i < count {
    let b = (string.byte_at(s, start + i) as Int) & 0xFF;
    v = v * 10 + (b - 48);
    i = i + 1;
  }
  return v;
}

fn _atoi_like(s: Str) -> Int {
  // Upstream atoi reading: the leading digit run; no digits reads 0.
  var v = 0;
  var i = 0;
  while i < s.len() {
    if !_is_digit(s, i) { return v; }
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    v = v * 10 + (b - 48);
    i = i + 1;
  }
  return v;
}

fn _find_char(s: Str, b: Int) -> Int {
  var i = 0;
  while i < s.len() {
    if ((string.byte_at(s, i) as Int) & 0xFF) == b { return i; }
    i = i + 1;
  }
  return -1;
}

fn _in_char_set(s: Str, set: Str) -> Bool {
  if s.len() == 0 { return false; }
  let b = (string.byte_at(s, 0) as Int) & 0xFF;
  var i = 0;
  while i < set.len() {
    if ((string.byte_at(set, i) as Int) & 0xFF) == b { return true; }
    i = i + 1;
  }
  return false;
}

fn _hex_digit(b: Int) -> Int {
  if b >= 48 && b <= 57 { return b - 48; }
  if b >= 65 && b <= 70 { return b - 55; }
  if b >= 97 && b <= 102 { return b - 87; }
  return -1;
}

fn _str_bytes(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(string.byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn _line_clean(line: Str) -> Str {
  var end = line.len();
  while end > 0 {
    let b = (string.byte_at(line, end - 1) as Int) & 0xFF;
    if b == 10 || b == 13 {
      end = end - 1;
    } else {
      break;
    }
  }
  return string.str_slice(line, 0, end);
}

// =========================================================================
// JSON object access helpers (typed extraction over xiom.serialize.json)
// =========================================================================

fn _parse_obj(line: Str) -> Result[JsonValue, Str] {
  let clean = _line_clean(line);
  if clean.len() == 0 { return Err("gps: empty line"); }
  let p = json.json_parse(clean);
  if !p.is_ok { return Err("gps: json: " + p.error); }
  return Ok(p.value);
}

// One entry value normalized into scalar slots. The entry's JsonValue is
// consumed exactly once by `_slot_of` (the ownership-clean extraction
// shape on the v0.64.5 move checker); the slot is then read by reference.
type JSlot = {
  kind: Int;
  sval: Str;
  fval: Float64;
  bval: Bool;
  aval: Vec[JsonValue];
}

const _JK_OTHER: Int = 0;
const _JK_STR: Int = 1;
const _JK_NUM: Int = 2;
const _JK_BOOL: Int = 3;
const _JK_ARR: Int = 4;

fn _slot_of(v: JsonValue) -> JSlot {
  return match v {
    JsonValue.String(s) => JSlot{
      kind: _JK_STR;
      sval: s;
      fval: 0.0;
      bval: false;
      aval: Vec[JsonValue].new();
    },
    JsonValue.Number(f) => JSlot{
      kind: _JK_NUM;
      sval: "";
      fval: f;
      bval: false;
      aval: Vec[JsonValue].new();
    },
    JsonValue.Bool(b) => JSlot{
      kind: _JK_BOOL;
      sval: "";
      fval: 0.0;
      bval: b;
      aval: Vec[JsonValue].new();
    },
    JsonValue.Array(items) => JSlot{
      kind: _JK_ARR;
      sval: "";
      fval: 0.0;
      bval: false;
      aval: items;
    },
    _ => JSlot{
      kind: _JK_OTHER;
      sval: "";
      fval: 0.0;
      bval: false;
      aval: Vec[JsonValue].new();
    },
  };
}

fn _mk_str(ok: Bool, s: Str) -> Option[Str] {
  if !ok { return None; }
  return Some(s);
}

fn _mk_num(ok: Bool, f: Float64) -> Option[Float64] {
  if !ok { return None; }
  return Some(f);
}

fn _mk_int(ok: Bool, f: Float64) -> Option[Int] {
  if !ok { return None; }
  let n = f as Int;
  if (n as Float64) != f { return None; }
  return Some(n);
}

fn _mk_bool(ok: Bool, b: Bool) -> Option[Bool] {
  if !ok { return None; }
  return Some(b);
}

// =========================================================================
// gpsd message parsers (single pass over each object's entries)
// =========================================================================

fn _tpv_of(j: JsonValue) -> Result[GpsTpv, Str] {
  var cls: Option[Str] = None;
  var mode: Option[Int] = None;
  var status: Option[Int] = None;
  var time: Option[Str] = None;
  var device: Option[Str] = None;
  var lat: Option[Float64] = None;
  var lon: Option[Float64] = None;
  var alt_hae: Option[Float64] = None;
  var alt_msl: Option[Float64] = None;
  var speed: Option[Float64] = None;
  var track: Option[Float64] = None;
  var climb: Option[Float64] = None;
  var eph: Option[Float64] = None;
  var epv: Option[Float64] = None;
  var ept: Option[Float64] = None;
  var eps: Option[Float64] = None;
  var geoid_sep: Option[Float64] = None;
  var magvar: Option[Float64] = None;
  var dgps_age: Option[Float64] = None;
  var dgps_sta: Option[Int] = None;
  var leapseconds: Option[Int] = None;

  match j {
    JsonValue.Object(entries) => {
      var i = 0;
      while i < entries.keys.len() {
        let k: Str = entries.keys[i];
        let sl = _slot_of(entries.values[i]);
        if _streq(k, "class") { cls = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "mode") { mode = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "status") { status = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "time") { time = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "device") { device = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "lat") { lat = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "lon") { lon = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "altHAE") { alt_hae = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "altMSL") { alt_msl = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "speed") { speed = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "track") { track = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "climb") { climb = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "eph") { eph = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "epv") { epv = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "ept") { ept = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "eps") { eps = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "geoidSep") { geoid_sep = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "magvar") { magvar = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "dgpsAge") { dgps_age = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "dgpsSta") { dgps_sta = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "leapseconds") { leapseconds = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        i = i + 1;
      }
    },
    _ => { return Err("gps: not a json object"); },
  }
  if !cls.is_some { return Err("gps: missing class"); }
  if !_streq(cls.value, "TPV") {
    return Err("gps: expected class TPV, got " + cls.value);
  }
  if !mode.is_some { return Err("gps: tpv missing mode"); }
  return Ok(GpsTpv{
    mode: mode.value;
    status: status;
    time: time;
    device: device;
    lat: lat;
    lon: lon;
    alt_hae: alt_hae;
    alt_msl: alt_msl;
    speed: speed;
    track: track;
    climb: climb;
    eph: eph;
    epv: epv;
    ept: ept;
    eps: eps;
    geoid_sep: geoid_sep;
    magvar: magvar;
    dgps_age: dgps_age;
    dgps_sta: dgps_sta;
    leapseconds: leapseconds;
  });
}

fn _sat_of(j: JsonValue) -> Result[GpsSatellite, Str] {
  var prn: Option[Int] = None;
  var used: Option[Bool] = None;
  var gnssid: Option[Int] = None;
  var svid: Option[Int] = None;
  var sigid: Option[Int] = None;
  var freqid: Option[Int] = None;
  var el: Option[Float64] = None;
  var az: Option[Float64] = None;
  var ss: Option[Float64] = None;
  var health: Option[Int] = None;

  match j {
    JsonValue.Object(entries) => {
      var i = 0;
      while i < entries.keys.len() {
        let k: Str = entries.keys[i];
        let sl = _slot_of(entries.values[i]);
        if _streq(k, "PRN") { prn = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "used") { used = _mk_bool(sl.kind == _JK_BOOL, sl.bval); }
        if _streq(k, "gnssid") { gnssid = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "svid") { svid = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "sigid") { sigid = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "freqid") { freqid = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "el") { el = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "az") { az = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "ss") { ss = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "health") { health = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        i = i + 1;
      }
    },
    _ => { return Err("gps: satellite entry is not an object"); }
  }
  if !prn.is_some { return Err("gps: satellite missing PRN"); }
  if !used.is_some { return Err("gps: satellite missing used"); }
  return Ok(GpsSatellite{
    prn: prn.value;
    used: used.value;
    gnssid: gnssid;
    svid: svid;
    sigid: sigid;
    freqid: freqid;
    el: el;
    az: az;
    ss: ss;
    health: health;
  });
}

fn _sats_of(items: Vec[JsonValue]) -> Result[Vec[GpsSatellite], Str] {
  var out = Vec[GpsSatellite].new();
  var i = 0;
  while i < items.len() {
    let el: JsonValue = items[i];
    let sr = _sat_of(el);
    if !sr.is_ok { return Err(sr.error); }
    out.push(sr.value);
    i = i + 1;
  }
  return Ok(out);
}

fn _sky_of(j: JsonValue) -> Result[GpsSky, Str] {
  var cls: Option[Str] = None;
  var device: Option[Str] = None;
  var time: Option[Str] = None;
  var gdop: Option[Float64] = None;
  var hdop: Option[Float64] = None;
  var pdop: Option[Float64] = None;
  var tdop: Option[Float64] = None;
  var vdop: Option[Float64] = None;
  var xdop: Option[Float64] = None;
  var ydop: Option[Float64] = None;
  var n_sat: Option[Int] = None;
  var u_sat: Option[Int] = None;
  var sats: Vec[GpsSatellite] = Vec[GpsSatellite].new();

  match j {
    JsonValue.Object(entries) => {
      var i = 0;
      while i < entries.keys.len() {
        let k: Str = entries.keys[i];
        let sl = _slot_of(entries.values[i]);
        if _streq(k, "class") { cls = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "device") { device = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "time") { time = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "gdop") { gdop = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "hdop") { hdop = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "pdop") { pdop = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "tdop") { tdop = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "vdop") { vdop = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "xdop") { xdop = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "ydop") { ydop = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "nSat") { n_sat = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "uSat") { u_sat = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "satellites") {
          if sl.kind != _JK_ARR {
            return Err("gps: satellites is not an array");
          }
          let sats_v: Vec[JsonValue] = sl.aval;
          let sr = _sats_of(sats_v);
          if !sr.is_ok { return Err(sr.error); }
          sats = sr.value;
        }
        i = i + 1;
      }
    },
    _ => { return Err("gps: not a json object"); },
  }
  if !cls.is_some { return Err("gps: missing class"); }
  if !_streq(cls.value, "SKY") {
    return Err("gps: expected class SKY, got " + cls.value);
  }
  return Ok(GpsSky{
    device: device;
    time: time;
    gdop: gdop;
    hdop: hdop;
    pdop: pdop;
    tdop: tdop;
    vdop: vdop;
    xdop: xdop;
    ydop: ydop;
    n_sat: n_sat;
    u_sat: u_sat;
    satellites: sats;
  });
}

fn _device_of(j: JsonValue) -> Result[GpsDevice, Str] {
  var path: Option[Str] = None;
  var driver: Option[Str] = None;
  var subtype: Option[Str] = None;
  var subtype1: Option[Str] = None;
  var activated: Option[Str] = None;
  var activated_num: Option[Float64] = None;
  var bps: Option[Int] = None;
  var parity: Option[Str] = None;
  var stopbits: Option[Int] = None;
  var native: Option[Int] = None;
  var cycle: Option[Float64] = None;
  var mincycle: Option[Float64] = None;
  var flags: Option[Int] = None;
  var readonly: Option[Bool] = None;
  var sernum: Option[Str] = None;

  match j {
    JsonValue.Object(entries) => {
      var i = 0;
      while i < entries.keys.len() {
        let k: Str = entries.keys[i];
        let sl = _slot_of(entries.values[i]);
        if _streq(k, "path") { path = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "driver") { driver = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "subtype") { subtype = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "subtype1") { subtype1 = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "activated") {
          activated = _mk_str(sl.kind == _JK_STR, sl.sval);
          activated_num = _mk_num(sl.kind == _JK_NUM, sl.fval);
        }
        if _streq(k, "bps") { bps = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "parity") { parity = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "stopbits") { stopbits = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "native") { native = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "cycle") { cycle = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "mincycle") { mincycle = _mk_num(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "flags") { flags = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "readonly") { readonly = _mk_bool(sl.kind == _JK_BOOL, sl.bval); }
        if _streq(k, "sernum") { sernum = _mk_str(sl.kind == _JK_STR, sl.sval); }
        i = i + 1;
      }
    },
    _ => { return Err("gps: not a json object"); },
  }
  return Ok(GpsDevice{
    path: path;
    driver: driver;
    subtype: subtype;
    subtype1: subtype1;
    activated: activated;
    activated_num: activated_num;
    bps: bps;
    parity: parity;
    stopbits: stopbits;
    native: native;
    cycle: cycle;
    mincycle: mincycle;
    flags: flags;
    readonly: readonly;
    sernum: sernum;
  });
}

fn _devices_of(j: JsonValue) -> Result[GpsDevices, Str] {
  var cls: Option[Str] = None;
  var remote: Option[Str] = None;
  var have_devices = false;
  var out: Vec[GpsDevice] = Vec[GpsDevice].new();

  match j {
    JsonValue.Object(entries) => {
      var i = 0;
      while i < entries.keys.len() {
        let k: Str = entries.keys[i];
        let sl = _slot_of(entries.values[i]);
        if _streq(k, "class") { cls = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "remote") { remote = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "devices") {
          if sl.kind != _JK_ARR {
            return Err("gps: devices is not an array");
          }
          have_devices = true;
          let devs_v: Vec[JsonValue] = sl.aval;
          var d = 0;
          while d < devs_v.len() {
            let el: JsonValue = devs_v[d];
            let dr = _device_of(el);
            if !dr.is_ok { return Err(dr.error); }
            out.push(dr.value);
            d = d + 1;
          }
        }
        i = i + 1;
      }
    },
    _ => { return Err("gps: not a json object"); },
  }
  if !cls.is_some { return Err("gps: missing class"); }
  if !_streq(cls.value, "DEVICES") {
    return Err("gps: expected class DEVICES, got " + cls.value);
  }
  if !have_devices { return Err("gps: missing devices"); }
  return Ok(GpsDevices{
    devices: out;
    remote: remote;
  });
}

fn _version_of(j: JsonValue) -> Result[GpsVersion, Str] {
  var cls: Option[Str] = None;
  var release: Option[Str] = None;
  var legacy: Option[Str] = None;
  var rev: Option[Str] = None;
  var proto_major: Option[Int] = None;
  var proto_minor: Option[Int] = None;
  var remote: Option[Str] = None;

  match j {
    JsonValue.Object(entries) => {
      var i = 0;
      while i < entries.keys.len() {
        let k: Str = entries.keys[i];
        let sl = _slot_of(entries.values[i]);
        if _streq(k, "class") { cls = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "release") { release = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "version") { legacy = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "rev") { rev = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "proto_major") { proto_major = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "proto_minor") { proto_minor = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "remote") { remote = _mk_str(sl.kind == _JK_STR, sl.sval); }
        i = i + 1;
      }
    },
    _ => { return Err("gps: not a json object"); },
  }
  if !cls.is_some { return Err("gps: missing class"); }
  if !_streq(cls.value, "VERSION") {
    return Err("gps: expected class VERSION, got " + cls.value);
  }
  var name: Option[Str] = release;
  if !name.is_some { name = legacy; }
  if !name.is_some { return Err("gps: version missing release"); }
  if !proto_major.is_some { return Err("gps: version missing proto_major"); }
  if !proto_minor.is_some { return Err("gps: version missing proto_minor"); }
  return Ok(GpsVersion{
    release: name.value;
    rev: rev;
    proto_major: proto_major.value;
    proto_minor: proto_minor.value;
    remote: remote;
  });
}

fn _watch_of(j: JsonValue) -> Result[GpsWatch, Str] {
  var cls: Option[Str] = None;
  var enable: Option[Bool] = None;
  var json_out: Option[Bool] = None;
  var nmea: Option[Bool] = None;
  var raw: Option[Int] = None;
  var scaled: Option[Bool] = None;
  var split24: Option[Bool] = None;
  var pps: Option[Bool] = None;
  var timing: Option[Bool] = None;
  var device: Option[Str] = None;
  var remote: Option[Str] = None;

  match j {
    JsonValue.Object(entries) => {
      var i = 0;
      while i < entries.keys.len() {
        let k: Str = entries.keys[i];
        let sl = _slot_of(entries.values[i]);
        if _streq(k, "class") { cls = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "enable") { enable = _mk_bool(sl.kind == _JK_BOOL, sl.bval); }
        if _streq(k, "json") { json_out = _mk_bool(sl.kind == _JK_BOOL, sl.bval); }
        if _streq(k, "nmea") { nmea = _mk_bool(sl.kind == _JK_BOOL, sl.bval); }
        if _streq(k, "raw") { raw = _mk_int(sl.kind == _JK_NUM, sl.fval); }
        if _streq(k, "scaled") { scaled = _mk_bool(sl.kind == _JK_BOOL, sl.bval); }
        if _streq(k, "split24") { split24 = _mk_bool(sl.kind == _JK_BOOL, sl.bval); }
        if _streq(k, "pps") { pps = _mk_bool(sl.kind == _JK_BOOL, sl.bval); }
        if _streq(k, "timing") { timing = _mk_bool(sl.kind == _JK_BOOL, sl.bval); }
        if _streq(k, "device") { device = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "remote") { remote = _mk_str(sl.kind == _JK_STR, sl.sval); }
        i = i + 1;
      }
    },
    _ => { return Err("gps: not a json object"); },
  }
  return Ok(GpsWatch{
    enable: enable;
    json: json_out;
    nmea: nmea;
    raw: raw;
    scaled: scaled;
    split24: split24;
    pps: pps;
    timing: timing;
    device: device;
    remote: remote;
  });
}

fn _error_of(j: JsonValue) -> Result[GpsErrorMsg, Str] {
  var cls: Option[Str] = None;
  var message: Option[Str] = None;

  match j {
    JsonValue.Object(entries) => {
      var i = 0;
      while i < entries.keys.len() {
        let k: Str = entries.keys[i];
        let sl = _slot_of(entries.values[i]);
        if _streq(k, "class") { cls = _mk_str(sl.kind == _JK_STR, sl.sval); }
        if _streq(k, "message") { message = _mk_str(sl.kind == _JK_STR, sl.sval); }
        i = i + 1;
      }
    },
    _ => { return Err("gps: not a json object"); },
  }
  if !cls.is_some { return Err("gps: missing class"); }
  if !_streq(cls.value, "ERROR") {
    return Err("gps: expected class ERROR, got " + cls.value);
  }
  if !message.is_some { return Err("gps: error missing message"); }
  return Ok(GpsErrorMsg{ message: message.value });
}

fn _class_of(j: JsonValue) -> Result[Str, Str] {
  var cls: Option[Str] = None;
  match j {
    JsonValue.Object(entries) => {
      var i = 0;
      while i < entries.keys.len() {
        let k: Str = entries.keys[i];
        if _streq(k, "class") {
          let sl = _slot_of(entries.values[i]);
          cls = _mk_str(sl.kind == _JK_STR, sl.sval);
        }
        i = i + 1;
      }
    },
    _ => { return Err("gps: not a json object"); },
  }
  if !cls.is_some { return Err("gps: missing class"); }
  return Ok(cls.value);
}

/// Parse one TPV response line.
pub fn gpsd_parse_tpv(line: Str) -> Result[GpsTpv, Str] {
  let jr = _parse_obj(line);
  if !jr.is_ok { return Err(jr.error); }
  return _tpv_of(jr.value);
}

/// Parse one SKY response line.
pub fn gpsd_parse_sky(line: Str) -> Result[GpsSky, Str] {
  let jr = _parse_obj(line);
  if !jr.is_ok { return Err(jr.error); }
  return _sky_of(jr.value);
}

/// Parse one VERSION response line.
pub fn gpsd_parse_version(line: Str) -> Result[GpsVersion, Str] {
  let jr = _parse_obj(line);
  if !jr.is_ok { return Err(jr.error); }
  return _version_of(jr.value);
}

/// Parse one DEVICES response line.
pub fn gpsd_parse_devices(line: Str) -> Result[GpsDevices, Str] {
  let jr = _parse_obj(line);
  if !jr.is_ok { return Err(jr.error); }
  return _devices_of(jr.value);
}

/// Parse one bare DEVICE object line.
pub fn gpsd_parse_device(line: Str) -> Result[GpsDevice, Str] {
  let jr = _parse_obj(line);
  if !jr.is_ok { return Err(jr.error); }
  let cr = _class_of(jr.value);
  if !cr.is_ok { return Err(cr.error); }
  if !_streq(cr.value, "DEVICE") {
    return Err("gps: expected class DEVICE, got " + cr.value);
  }
  let jr2 = _parse_obj(line);
  if !jr2.is_ok { return Err(jr2.error); }
  return _device_of(jr2.value);
}

/// Parse one WATCH policy response line.
pub fn gpsd_parse_watch(line: Str) -> Result[GpsWatch, Str] {
  let jr = _parse_obj(line);
  if !jr.is_ok { return Err(jr.error); }
  let cr = _class_of(jr.value);
  if !cr.is_ok { return Err(cr.error); }
  if !_streq(cr.value, "WATCH") {
    return Err("gps: expected class WATCH, got " + cr.value);
  }
  let jr2 = _parse_obj(line);
  if !jr2.is_ok { return Err(jr2.error); }
  return _watch_of(jr2.value);
}

/// Parse one ERROR notification line.
pub fn gpsd_parse_error(line: Str) -> Result[GpsErrorMsg, Str] {
  let jr = _parse_obj(line);
  if !jr.is_ok { return Err(jr.error); }
  return _error_of(jr.value);
}

/// The "class" attribute of a response line, without dispatching.
pub fn gpsd_message_class(line: Str) -> Result[Str, Str] {
  let jr = _parse_obj(line);
  if !jr.is_ok { return Err(jr.error); }
  return _class_of(jr.value);
}

/// Parse one gpsd response line and dispatch on its class. Classes in
/// the declared set are fully typed; any other class is returned as
/// `GpsMessage.Other(name)`.
pub fn gpsd_parse_line(line: Str) -> Result[GpsMessage, Str] {
  let cr = gpsd_message_class(line);
  if !cr.is_ok { return Err(cr.error); }
  let cls: Str = cr.value;
  if _streq(cls, "TPV") {
    let r = gpsd_parse_tpv(line);
    if !r.is_ok { return Err(r.error); }
    return Ok(GpsMessage.Tpv(r.value));
  }
  if _streq(cls, "SKY") {
    let r = gpsd_parse_sky(line);
    if !r.is_ok { return Err(r.error); }
    return Ok(GpsMessage.Sky(r.value));
  }
  if _streq(cls, "VERSION") {
    let r = gpsd_parse_version(line);
    if !r.is_ok { return Err(r.error); }
    return Ok(GpsMessage.Version(r.value));
  }
  if _streq(cls, "DEVICES") {
    let r = gpsd_parse_devices(line);
    if !r.is_ok { return Err(r.error); }
    return Ok(GpsMessage.Devices(r.value));
  }
  if _streq(cls, "DEVICE") {
    let r = gpsd_parse_device(line);
    if !r.is_ok { return Err(r.error); }
    return Ok(GpsMessage.Device(r.value));
  }
  if _streq(cls, "WATCH") {
    let r = gpsd_parse_watch(line);
    if !r.is_ok { return Err(r.error); }
    return Ok(GpsMessage.Watch(r.value));
  }
  if _streq(cls, "ERROR") {
    let r = gpsd_parse_error(line);
    if !r.is_ok { return Err(r.error); }
    return Ok(GpsMessage.Error(r.value));
  }
  return Ok(GpsMessage.Other(cls));
}

/// Protocol compatibility check following the upstream cgps rule: the
/// daemon major version must equal GPSD_PROTO_MAJOR and its minor must
/// be at least GPSD_PROTO_MINOR.
pub fn gpsd_proto_compatible(proto_major: Int, proto_minor: Int) -> Bool {
  if proto_major != GPSD_PROTO_MAJOR { return false; }
  if proto_minor < GPSD_PROTO_MINOR { return false; }
  return true;
}

/// The canonical `?WATCH` JSON-stream request line (no trailing newline;
/// the client appends CR-NL), matching the upstream libgps command.
pub fn gpsd_watch_command(enable: Bool) -> Str {
  if enable {
    return "?WATCH={\"enable\":true,\"json\":true};";
  }
  return "?WATCH={\"enable\":false,\"json\":false};";
}

/// The `?VERSION` request line (no trailing newline).
pub fn gpsd_version_command() -> Str {
  return "?VERSION;";
}

// =========================================================================
// gpsd client session
// =========================================================================

/// Open a TCP connection to a gpsd daemon. A connect failure (no daemon
/// listening, unreachable host) is classified GPS_ERR_ABSENT so callers
/// and suites can report SKIP instead of FAIL.
pub fn gpsd_client_open(host: Str, port: Int, timeout_ms: Int) -> Result[GpsClient, GpsError] {
  if port <= 0 || port > 65535 {
    return Err(GpsError{
      kind: GPS_ERR_IO;
      message: "gps: port out of range";
    });
  }
  if timeout_ms < 0 {
    return Err(GpsError{
      kind: GPS_ERR_IO;
      message: "gps: negative timeout";
    });
  }
  let fr = socket_tcp();
  if !fr.is_ok {
    return Err(GpsError{
      kind: GPS_ERR_IO;
      message: "gps: " + fr.error;
    });
  }
  let fd: Int = fr.value;
  let cr = socket_connect(fd, host, port);
  if !cr.is_ok {
    socket_close(fd);
    return Err(GpsError{
      kind: GPS_ERR_ABSENT;
      message: "gps: connect " + host + ":" + to_string(port) + " refused: " + cr.error;
    });
  }
  return Ok(GpsClient{
    fd: fd;
    host: host;
    port: port;
    timeout_ms: timeout_ms;
    buf: Vec[UInt8].new();
  });
}

/// Send one protocol command line (CR-NL terminated by this function).
pub fn gpsd_client_send(c: &mut GpsClient, cmd: Str) -> Result[Unit, GpsError] {
  if c.fd < 0 {
    return Err(GpsError{
      kind: GPS_ERR_IO;
      message: "gps: client is closed";
    });
  }
  let bytes = _str_bytes(cmd);
  bytes.push(13);
  bytes.push(10);
  let sr = socket_send_all(c.fd, &bytes);
  if !sr.is_ok {
    return Err(GpsError{
      kind: GPS_ERR_IO;
      message: "gps: send failed: " + sr.error;
    });
  }
  return Ok(());
}

/// Enable (or disable) JSON watch mode with the upstream command.
pub fn gpsd_client_watch(c: &mut GpsClient, enable: Bool) -> Result[Unit, GpsError] {
  return gpsd_client_send(c, gpsd_watch_command(enable));
}

fn _vec_drop_front(v: &mut Vec[UInt8], n: Int) {
  var nb = Vec[UInt8].new();
  var i = n;
  while i < v.len() {
    nb.push(v[i]);
    i = i + 1;
  }
  *v = nb;
}

fn _buf_find_nl(v: &Vec[UInt8]) -> Int {
  var i = 0;
  while i < v.len() {
    if ((v[i] as Int) & 0xFF) == 10 { return i; }
    i = i + 1;
  }
  return -1;
}

fn _bytes_range_str(v: &Vec[UInt8], from: Int, to: Int) -> Str {
  var sb = builder.sb_new();
  var i = from;
  while i < to {
    builder.sb_push_byte(&mut sb, v[i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

/// Read one complete CR-NL terminated line (without the terminator).
/// A receive failure or deadline expiry reports GPS_ERR_TIMEOUT; an
/// orderly peer close with a pending partial line reports GPS_ERR_IO.
pub fn gpsd_client_read_line(c: &mut GpsClient) -> Result[Str, GpsError] {
  if c.fd < 0 {
    return Err(GpsError{
      kind: GPS_ERR_IO;
      message: "gps: client is closed";
    });
  }
  // Work on a local copy of the pending-bytes buffer (field references
  // into a borrowed struct are not reliable on the current compiler);
  // it is written back before every exit.
  var buf: Vec[UInt8] = c.buf;
  var guard = 0;
  while guard < 1024 {
    let nl = _buf_find_nl(&buf);
    if nl >= 0 {
      var end = nl;
      if end > 0 {
        let last = (buf[end - 1] as Int) & 0xFF;
        if last == 13 { end = end - 1; }
      }
      let line = _bytes_range_str(&buf, 0, end);
      _vec_drop_front(&mut buf, nl + 1);
      c.buf = buf;
      return Ok(line);
    }
    if buf.len() > 65536 {
      c.buf = buf;
      return Err(GpsError{
        kind: GPS_ERR_PARSE;
        message: "gps: line longer than 65536 bytes";
      });
    }
    let rr = socket_recv_timeout(c.fd, 4096, c.timeout_ms);
    if !rr.is_ok {
      c.buf = buf;
      return Err(GpsError{
        kind: GPS_ERR_TIMEOUT;
        message: "gps: no complete line within " + to_string(c.timeout_ms) + " ms: " + rr.error;
      });
    }
    let chunk: Vec[UInt8] = rr.value;
    if chunk.len() == 0 {
      c.buf = buf;
      return Err(GpsError{
        kind: GPS_ERR_IO;
        message: "gps: connection closed by peer";
      });
    }
    var i = 0;
    while i < chunk.len() {
      buf.push(chunk[i]);
      i = i + 1;
    }
    guard = guard + 1;
  }
  c.buf = buf;
  return Err(GpsError{
    kind: GPS_ERR_TIMEOUT;
    message: "gps: line read exceeded 1024 receive cycles";
  });
}

/// Read lines until one parses as a gpsd JSON message. Empty lines are
/// skipped; malformed lines report GPS_ERR_PARSE.
pub fn gpsd_client_next(c: &mut GpsClient) -> Result[GpsMessage, GpsError] {
  var guard = 0;
  while guard < 1024 {
    let lr = gpsd_client_read_line(c);
    if !lr.is_ok { return Err(lr.error); }
    let line: Str = lr.value;
    if line.len() == 0 {
      guard = guard + 1;
    } else {
      let mr = gpsd_parse_line(line);
      if mr.is_ok {
        return Ok(mr.value);
      }
      return Err(GpsError{
        kind: GPS_ERR_PARSE;
        message: mr.error;
      });
    }
  }
  return Err(GpsError{
    kind: GPS_ERR_PARSE;
    message: "gps: no json line in 1024 lines";
  });
}

/// Clean close: shutdown and release the socket. Idempotent.
pub fn gpsd_client_close(c: &mut GpsClient) -> Result[Unit, GpsError] {
  if c.fd >= 0 {
    let fd = c.fd;
    let _sr = socket_shutdown(fd, 2);
    socket_close(fd);
    c.fd = -1;
  }
  return Ok(());
}

// =========================================================================
// NMEA 0183 -- checksum and field framing
// =========================================================================

fn _last_star(s: Str) -> Int {
  var i = s.len() - 1;
  while i >= 0 {
    if ((string.byte_at(s, i) as Int) & 0xFF) == 42 { return i; }
    i = i - 1;
  }
  return -1;
}

fn _xor_range(s: Str, from: Int, to: Int) -> Int {
  var x = 0;
  var i = from;
  while i < to {
    x = x ^ ((string.byte_at(s, i) as Int) & 0xFF);
    i = i + 1;
  }
  return x;
}

/// Validate and return the NMEA checksum of a sentence: the XOR of the
/// bytes between the leading '$' (or '!') and the last '*', compared
/// against the two hexadecimal digits after it (case-insensitive, the
/// upstream packet.c rule). Trailing bytes after the two digits are
/// ignored, like the daemon.
pub fn nmea_checksum(line: Str) -> Result[Int, Str] {
  let clean = _line_clean(line);
  let star = _last_star(clean);
  if star < 1 { return Err("gps: nmea checksum missing"); }
  if star + 3 > clean.len() { return Err("gps: nmea checksum truncated"); }
  let h1 = _hex_digit((string.byte_at(clean, star + 1) as Int) & 0xFF);
  let h2 = _hex_digit((string.byte_at(clean, star + 2) as Int) & 0xFF);
  if h1 < 0 || h2 < 0 { return Err("gps: nmea checksum not hex"); }
  let want = h1 * 16 + h2;
  let got = _xor_range(clean, 1, star);
  if want != got { return Err("gps: nmea checksum mismatch"); }
  return Ok(got);
}

/// True when the sentence carries a valid NMEA checksum.
pub fn nmea_checksum_valid(line: Str) -> Bool {
  let r = nmea_checksum(line);
  return r.is_ok;
}

fn _nmea_fields(line: Str) -> Result[Vec[Str], Str] {
  let clean = _line_clean(line);
  if clean.len() == 0 { return Err("gps: empty nmea line"); }
  if ((string.byte_at(clean, 0) as Int) & 0xFF) != 36 {
    return Err("gps: nmea line must start with $");
  }
  let cr = nmea_checksum(clean);
  if !cr.is_ok { return Err(cr.error); }
  let star = _last_star(clean);
  let body = string.str_slice(clean, 1, star);
  var f = split.str_split(body, ",");
  return Ok(f);
}

fn _fld(f: &Vec[Str], i: Int) -> Str {
  if i < f.len() { return f[i]; }
  return "";
}

fn _talker_of(tag: Str) -> Str {
  if tag.len() < 3 { return ""; }
  return string.str_slice(tag, 0, tag.len() - 3);
}

fn _kind_of(tag: Str) -> Str {
  if tag.len() < 3 { return ""; }
  return string.str_slice(tag, tag.len() - 3, tag.len());
}

fn _kind_is(tag: Str, kind: Str) -> Bool {
  return _streq(_kind_of(tag), kind);
}

/// The talker id of an NMEA line ("GP", "GN", "GL", ...).
pub fn nmea_talker(line: Str) -> Result[Str, Str] {
  let fr = _nmea_fields(line);
  if !fr.is_ok { return Err(fr.error); }
  let f: Vec[Str] = fr.value;
  let tag: Str = f[0];
  if tag.len() < 3 { return Err("gps: nmea id too short"); }
  return Ok(_talker_of(tag));
}

/// The sentence kind of an NMEA line ("GGA", "RMC", "GSA", "GSV", ...).
pub fn nmea_kind(line: Str) -> Result[Str, Str] {
  let fr = _nmea_fields(line);
  if !fr.is_ok { return Err(fr.error); }
  let f: Vec[Str] = fr.value;
  let tag: Str = f[0];
  if tag.len() < 3 { return Err("gps: nmea id too short"); }
  return Ok(_kind_of(tag));
}

// =========================================================================
// NMEA 0183 -- field decoding helpers
// =========================================================================

fn _time_state(f: Str) -> Int {
  // 0 = absent, 1 = well formed, -1 = malformed.
  if f.len() == 0 { return 0; }
  if f.len() < 6 { return -1; }
  var i = 0;
  while i < 6 {
    if !_is_digit(f, i) { return -1; }
    i = i + 1;
  }
  if f.len() > 6 {
    if ((string.byte_at(f, 6) as Int) & 0xFF) != 46 { return -1; }
    var j = 7;
    while j < f.len() {
      if !_is_digit(f, j) { return -1; }
      j = j + 1;
    }
  }
  let hh = _digits_value(f, 0, 2);
  let mm = _digits_value(f, 2, 2);
  let ss = _digits_value(f, 4, 2);
  if hh > 23 { return -1; }
  if mm > 59 { return -1; }
  if ss > 60 { return -1; }
  return 1;
}

fn _time_at(f: Str) -> NmeaTime {
  let hh = _digits_value(f, 0, 2);
  let mm = _digits_value(f, 2, 2);
  let ss = _digits_value(f, 4, 2);
  var millis = 0;
  if f.len() > 7 {
    let n = f.len() - 7;
    var take = n;
    if take > 3 { take = 3; }
    var v = _digits_value(f, 7, take);
    var k = take;
    while k < 3 {
      v = v * 10;
      k = k + 1;
    }
    millis = v;
  }
  return NmeaTime{
    hour: hh;
    minute: mm;
    second: ss;
    millis: millis;
  };
}

fn _date_state(f: Str) -> Int {
  // 0 = absent, 1 = well formed, -1 = malformed.
  if f.len() == 0 { return 0; }
  if f.len() != 6 { return -1; }
  if !_digits_ok(f) { return -1; }
  let day = _digits_value(f, 0, 2);
  let mon = _digits_value(f, 2, 2);
  if day < 1 || day > 31 { return -1; }
  if mon < 1 || mon > 12 { return -1; }
  return 1;
}

fn _date_at(f: Str) -> NmeaDate {
  let day = _digits_value(f, 0, 2);
  let mon = _digits_value(f, 2, 2);
  let yy = _digits_value(f, 4, 2);
  var year = 1900 + yy;
  if yy < 69 { year = 2000 + yy; }
  return NmeaDate{
    day: day;
    month: mon;
    year: year;
  };
}

fn _coord_ok(f: Str, is_lat: Bool) -> Bool {
  let dot = _find_char(f, 46);
  if dot < 3 { return false; }
  if dot > 6 { return false; }
  var i = 0;
  while i < dot {
    if !_is_digit(f, i) { return false; }
    i = i + 1;
  }
  var j = dot + 1;
  while j < f.len() {
    if !_is_digit(f, j) { return false; }
    j = j + 1;
  }
  let intpart = _digits_value(f, 0, dot);
  let deg = intpart / 100;
  let min = intpart % 100;
  if min >= 60 { return false; }
  if is_lat {
    if deg > 90 { return false; }
  } else {
    if deg > 180 { return false; }
  }
  return true;
}

fn _coord_deg(f: Str) -> Float64 {
  let dot = _find_char(f, 46);
  let intpart = _digits_value(f, 0, dot);
  let deg = intpart / 100;
  let min = intpart % 100;
  var frac = 0.0;
  if dot + 1 < f.len() {
    let fr = parse.parse_float("0." + string.str_slice(f, dot + 1, f.len()));
    if fr.is_ok { frac = fr.value; }
  }
  let total = ((deg * 60 + min) as Float64) + frac;
  return total / 60.0;
}

fn _pos_state(lat_f: Str, ns: Str, lon_f: Str, ew: Str) -> Int {
  // 0 = no position (all four absent), 1 = well formed, -1 = malformed.
  let la = lat_f.len() == 0;
  let lb = ns.len() == 0;
  let lc = lon_f.len() == 0;
  let ld = ew.len() == 0;
  if la && lb && lc && ld { return 0; }
  if la || lb || lc || ld { return -1; }
  if !_coord_ok(lat_f, true) { return -1; }
  if !_coord_ok(lon_f, false) { return -1; }
  if !_streq(ns, "N") && !_streq(ns, "S") { return -1; }
  if !_streq(ew, "E") && !_streq(ew, "W") { return -1; }
  return 1;
}

fn _pos_lat(lat_f: Str, ns: Str) -> Float64 {
  var v = _coord_deg(lat_f);
  if _streq(ns, "S") { v = -v; }
  return v;
}

fn _pos_lon(lon_f: Str, ew: Str) -> Float64 {
  var v = _coord_deg(lon_f);
  if _streq(ew, "W") { v = -v; }
  return v;
}

fn _num_ok(f: Str) -> Bool {
  if f.len() == 0 { return true; }
  let r = parse.parse_float(f);
  return r.is_ok;
}

fn _num_at(f: Str) -> Float64 {
  let r = parse.parse_float(f);
  if r.is_ok { return r.value; }
  return 0.0;
}

fn _num_opt(f: Str) -> Option[Float64] {
  if f.len() == 0 { return None; }
  return Some(_num_at(f));
}

fn _int_opt(f: Str) -> Option[Int] {
  if f.len() == 0 { return None; }
  return Some(_digits_value(f, 0, f.len()));
}

fn _gate_dop(v: Float64) -> Option[Float64] {
  // Upstream sentinel gate: devices send 0.00 / 99.99 for invalid DOPs.
  if v < 0.01 { return None; }
  if v > 89.99 { return None; }
  return Some(v);
}

fn _dop_opt(f: Str) -> Option[Float64] {
  if f.len() == 0 { return None; }
  return _gate_dop(_num_at(f));
}

// =========================================================================
// NMEA 0183 -- sentence parsers
// =========================================================================

/// Parse a GGA sentence: time, position, fix quality, satellites used,
/// HDOP, MSL altitude, geoid separation and DGPS age/station.
pub fn nmea_parse_gga(line: Str) -> Result[NmeaGga, Str] {
  let fr = _nmea_fields(line);
  if !fr.is_ok { return Err(fr.error); }
  let f: Vec[Str] = fr.value;
  if !_kind_is(f[0], "GGA") { return Err("gps: not a GGA sentence"); }

  let tf = _fld(&f, 1);
  let ts = _time_state(tf);
  if ts < 0 { return Err("gps: bad gga time"); }
  var time: Option[NmeaTime] = None;
  if ts == 1 { time = Some(_time_at(tf)); }

  let lat_f = _fld(&f, 2);
  let ns = _fld(&f, 3);
  let lon_f = _fld(&f, 4);
  let ew = _fld(&f, 5);
  let ps = _pos_state(lat_f, ns, lon_f, ew);
  if ps < 0 { return Err("gps: bad gga lat/lon"); }
  var lat: Option[Float64] = None;
  var lon: Option[Float64] = None;
  if ps == 1 {
    lat = Some(_pos_lat(lat_f, ns));
    lon = Some(_pos_lon(lon_f, ew));
  }

  let qf = _fld(&f, 6);
  if qf.len() > 0 && !_digits_ok(qf) { return Err("gps: bad gga fix quality"); }
  let nf = _fld(&f, 7);
  if nf.len() > 0 && !_digits_ok(nf) { return Err("gps: bad gga num sats"); }
  let hf = _fld(&f, 8);
  if !_num_ok(hf) { return Err("gps: bad gga hdop"); }
  let af = _fld(&f, 9);
  if !_num_ok(af) { return Err("gps: bad gga altitude"); }
  let gf = _fld(&f, 11);
  if !_num_ok(gf) { return Err("gps: bad gga geoid sep"); }
  let df = _fld(&f, 13);
  if !_num_ok(df) { return Err("gps: bad gga dgps age"); }
  let sf = _fld(&f, 14);
  if sf.len() > 0 && !_digits_ok(sf) { return Err("gps: bad gga dgps station"); }

  return Ok(NmeaGga{
    talker: _talker_of(f[0]);
    time: time;
    lat: lat;
    lon: lon;
    fix_quality: _int_opt(qf);
    num_sats: _int_opt(nf);
    hdop: _num_opt(hf);
    alt_msl: _num_opt(af);
    geoid_sep: _num_opt(gf);
    dgps_age: _num_opt(df);
    dgps_sta: _int_opt(sf);
  });
}

/// Parse an RMC sentence: validity, time/date, position, speed, track,
/// magnetic variation and the FAA mode / NMEA 4.1 navigation status.
pub fn nmea_parse_rmc(line: Str) -> Result[NmeaRmc, Str] {
  let fr = _nmea_fields(line);
  if !fr.is_ok { return Err(fr.error); }
  let f: Vec[Str] = fr.value;
  if !_kind_is(f[0], "RMC") { return Err("gps: not an RMC sentence"); }

  var status: Option[Str] = None;
  let sf = _fld(&f, 2);
  if sf.len() > 0 {
    if !_streq(sf, "A") && !_streq(sf, "V") {
      return Err("gps: bad rmc status");
    }
    status = Some(sf);
  }

  let tf = _fld(&f, 1);
  let ts = _time_state(tf);
  if ts < 0 { return Err("gps: bad rmc time"); }
  var time: Option[NmeaTime] = None;
  if ts == 1 { time = Some(_time_at(tf)); }

  let df = _fld(&f, 9);
  let ds = _date_state(df);
  if ds < 0 { return Err("gps: bad rmc date"); }
  var date: Option[NmeaDate] = None;
  if ds == 1 { date = Some(_date_at(df)); }

  let lat_f = _fld(&f, 3);
  let ns = _fld(&f, 4);
  let lon_f = _fld(&f, 5);
  let ew = _fld(&f, 6);
  let ps = _pos_state(lat_f, ns, lon_f, ew);
  if ps < 0 { return Err("gps: bad rmc lat/lon"); }
  var lat: Option[Float64] = None;
  var lon: Option[Float64] = None;
  if ps == 1 {
    lat = Some(_pos_lat(lat_f, ns));
    lon = Some(_pos_lon(lon_f, ew));
  }

  let spf = _fld(&f, 7);
  if !_num_ok(spf) { return Err("gps: bad rmc speed"); }
  let trf = _fld(&f, 8);
  if !_num_ok(trf) { return Err("gps: bad rmc track"); }

  var magvar: Option[Float64] = None;
  let mf = _fld(&f, 10);
  let hf = _fld(&f, 11);
  if mf.len() > 0 && hf.len() > 0 {
    if !_num_ok(mf) { return Err("gps: bad rmc magvar"); }
    if !_streq(hf, "E") && !_streq(hf, "W") {
      return Err("gps: bad rmc magvar hemisphere");
    }
    var mv = _num_at(mf);
    if _streq(hf, "W") { mv = -mv; }
    var av = mv;
    if av < 0.0 { av = -av; }
    if av > 0.09 { magvar = Some(mv); }
  }

  var mode_ind: Option[Str] = None;
  let mi = _fld(&f, 12);
  if mi.len() > 0 {
    if !_in_char_set(mi, "ACDEFMN0PRSUV") {
      return Err("gps: bad rmc mode indicator");
    }
    mode_ind = Some(mi);
  }

  var nav_status: Option[Str] = None;
  let nv = _fld(&f, 13);
  if nv.len() > 0 {
    if !_in_char_set(nv, "ADEFMNPRSV") {
      return Err("gps: bad rmc nav status");
    }
    nav_status = Some(nv);
  }

  return Ok(NmeaRmc{
    talker: _talker_of(f[0]);
    status: status;
    time: time;
    date: date;
    lat: lat;
    lon: lon;
    speed_knots: _num_opt(spf);
    track_deg: _num_opt(trf);
    magvar_deg: magvar;
    mode_ind: mode_ind;
    nav_status: nav_status;
  });
}

/// Parse a GSA sentence: fix mode, fix type, the used-satellite number
/// list and the PDOP/HDOP/VDOP triplet (+ the NMEA 4.10 system id).
pub fn nmea_parse_gsa(line: Str) -> Result[NmeaGsa, Str] {
  let fr = _nmea_fields(line);
  if !fr.is_ok { return Err(fr.error); }
  let f: Vec[Str] = fr.value;
  if !_kind_is(f[0], "GSA") { return Err("gps: not a GSA sentence"); }

  var mode: Option[Str] = None;
  let mf = _fld(&f, 1);
  if mf.len() > 0 {
    if !_streq(mf, "A") && !_streq(mf, "M") {
      return Err("gps: bad gsa mode");
    }
    mode = Some(mf);
  }

  let fix_type = _atoi_like(_fld(&f, 2));

  // PRN list: fields 3 .. len-4 (the last three are the DOP triplet);
  // the upstream loop stops at the first field containing '.' and
  // keeps sentence-order numbers 1..600.
  var prns = Vec[Int].new();
  var i = 0;
  let limit = f.len() - 6;
  while i < limit {
    let s = _fld(&f, i + 3);
    if s.len() > 0 {
      if string.str_contains(s, ".") { break; }
      if !_digits_ok(s) { return Err("gps: bad gsa prn"); }
      let v = _digits_value(s, 0, s.len());
      if v >= 1 && v <= 600 { prns.push(v); }
    }
    i = i + 1;
  }

  // DOP triplet at the standard positions 15..17; gated like upstream.
  var pdop: Option[Float64] = None;
  var hdop: Option[Float64] = None;
  var vdop: Option[Float64] = None;
  var system_id: Option[Int] = None;
  if f.len() <= 19 {
    let pf = _fld(&f, 15);
    let hf = _fld(&f, 16);
    let vf = _fld(&f, 17);
    if !_num_ok(pf) { return Err("gps: bad gsa pdop"); }
    if !_num_ok(hf) { return Err("gps: bad gsa hdop"); }
    if !_num_ok(vf) { return Err("gps: bad gsa vdop"); }
    pdop = _dop_opt(pf);
    hdop = _dop_opt(hf);
    vdop = _dop_opt(vf);
    if f.len() == 19 {
      let sif = _fld(&f, 18);
      if sif.len() > 0 && !string.str_contains(sif, ".") {
        if !_digits_ok(sif) { return Err("gps: bad gsa system id"); }
        system_id = _int_opt(sif);
      }
    }
  }

  return Ok(NmeaGsa{
    talker: _talker_of(f[0]);
    mode: mode;
    fix_type: fix_type;
    prns: prns;
    pdop: pdop;
    hdop: hdop;
    vdop: vdop;
    system_id: system_id;
  });
}

/// Parse a GSV sentence: message framing, satellites-in-view count and
/// up to four satellite records, plus the NMEA 4.1 signal id and the
/// Quectel system id where present.
pub fn nmea_parse_gsv(line: Str) -> Result[NmeaGsv, Str] {
  let fr = _nmea_fields(line);
  if !fr.is_ok { return Err(fr.error); }
  let f: Vec[Str] = fr.value;
  if !_kind_is(f[0], "GSV") { return Err("gps: not a GSV sentence"); }
  if f.len() < 4 { return Err("gps: bad gsv header"); }

  let nmf = _fld(&f, 1);
  let mmf = _fld(&f, 2);
  let svf = _fld(&f, 3);
  if nmf.len() == 0 || !_digits_ok(nmf) { return Err("gps: bad gsv num msgs"); }
  if mmf.len() == 0 || !_digits_ok(mmf) { return Err("gps: bad gsv msg num"); }
  if svf.len() > 0 && !_digits_ok(svf) { return Err("gps: bad gsv sv count"); }
  let num_msgs = _digits_value(nmf, 0, nmf.len());
  let msg_num = _digits_value(mmf, 0, mmf.len());
  if num_msgs < 1 || num_msgs > 10 { return Err("gps: bad gsv num msgs"); }
  if msg_num < 1 || msg_num > num_msgs { return Err("gps: bad gsv msg num"); }
  let sats_in_view = _atoi_like(svf);

  // Trailing-field shape: 0 extra (plain), 1 extra (NMEA 4.1 signal
  // id), 2 extra (Quectel $PQGSV signal id + system id).
  var signal_id: Option[Int] = None;
  var system_id: Option[Int] = None;
  let extra = f.len() % 4;
  if extra == 1 {
    let sgf = _fld(&f, f.len() - 1);
    let hd = _hex_digit((string.byte_at(sgf, 0) as Int) & 0xFF);
    if hd < 0 { return Err("gps: bad gsv signal id"); }
    signal_id = Some(hd);
  }
  if extra == 2 {
    let sgf = _fld(&f, f.len() - 2);
    let syf = _fld(&f, f.len() - 1);
    let hd = _hex_digit((string.byte_at(sgf, 0) as Int) & 0xFF);
    if hd < 0 { return Err("gps: bad gsv signal id"); }
    if syf.len() == 0 || !_digits_ok(syf) { return Err("gps: bad gsv system id"); }
    let sysv = _digits_value(syf, 0, syf.len());
    if sysv != 4 && sysv != 5 { return Err("gps: bad gsv system id"); }
    signal_id = Some(hd);
    system_id = Some(sysv);
  }
  if extra != 0 && extra != 1 && extra != 2 {
    return Err("gps: bad gsv field count");
  }

  var sats = Vec[NmeaGsvSat].new();
  var k = 1;
  while k < f.len() / 4 {
    let i = 4 * k;
    let pf = f[i];
    if pf.len() > 0 {
      if !_digits_ok(pf) { return Err("gps: bad gsv prn"); }
      let prn = _digits_value(pf, 0, pf.len());
      if prn != 0 {
        let elf = f[i + 1];
        let azf = f[i + 2];
        let snf = f[i + 3];
        if elf.len() > 0 && !_digits_ok(elf) { return Err("gps: bad gsv elevation"); }
        if azf.len() > 0 && !_digits_ok(azf) { return Err("gps: bad gsv azimuth"); }
        if snf.len() > 0 && !_digits_ok(snf) { return Err("gps: bad gsv snr"); }
        var el: Option[Int] = None;
        var az: Option[Int] = None;
        if elf.len() > 0 && azf.len() > 0 {
          let elv = _digits_value(elf, 0, elf.len());
          var azv = _digits_value(azf, 0, azf.len());
          if elv <= 90 { el = Some(elv); }
          if azv == 360 { azv = 0; }
          if azv >= 0 && azv < 360 { az = Some(azv); }
        }
        sats.push(NmeaGsvSat{
          prn: prn;
          el: el;
          az: az;
          snr: _int_opt(snf);
        });
      }
    }
    k = k + 1;
  }

  return Ok(NmeaGsv{
    talker: _talker_of(f[0]);
    num_msgs: num_msgs;
    msg_num: msg_num;
    sats_in_view: sats_in_view;
    signal_id: signal_id;
    system_id: system_id;
    satellites: sats;
  });
}

/// Parse one NMEA sentence line and dispatch on the sentence kind.
/// Kinds outside the declared set return `NmeaMessage.Other`.
pub fn nmea_parse_line(line: Str) -> Result[NmeaMessage, Str] {
  let kr = nmea_kind(line);
  if !kr.is_ok { return Err(kr.error); }
  let kind: Str = kr.value;
  if _streq(kind, "GGA") {
    let r = nmea_parse_gga(line);
    if !r.is_ok { return Err(r.error); }
    return Ok(NmeaMessage.Gga(r.value));
  }
  if _streq(kind, "RMC") {
    let r = nmea_parse_rmc(line);
    if !r.is_ok { return Err(r.error); }
    return Ok(NmeaMessage.Rmc(r.value));
  }
  if _streq(kind, "GSA") {
    let r = nmea_parse_gsa(line);
    if !r.is_ok { return Err(r.error); }
    return Ok(NmeaMessage.Gsa(r.value));
  }
  if _streq(kind, "GSV") {
    let r = nmea_parse_gsv(line);
    if !r.is_ok { return Err(r.error); }
    return Ok(NmeaMessage.Gsv(r.value));
  }
  let tr = nmea_talker(line);
  if !tr.is_ok { return Err(tr.error); }
  return Ok(NmeaMessage.Other(tr.value, kind));
}
