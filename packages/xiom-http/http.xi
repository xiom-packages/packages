// XIOM -- HTTP Client Library (Production via libcurl + FFI Bridge)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.http

use xiom.ptr;
use xiom.string;
use xiom.encoding;
use xiom.convert.tostring;
use xiom.http.body;
use xiom.http.options;

// --- XIOM FFI Bridge --------------------------------------------------------

extern "C" {
  fn xiom_str_to_cstr(xiom_str: *UInt8, len: Int) -> *UInt8;
  fn xiom_free_cstr(cstr: *UInt8);
  fn xiom_alloc(size: Int) -> *UInt8;
  fn xiom_free_ptr(ptr: *UInt8);
  fn xiom_write_byte(ptr: *UInt8, offset: Int, value: Int);
  fn xiom_read_byte(ptr: *UInt8, offset: Int) -> Int;
  fn xiom_copy_from_vec(c_buf: *UInt8, vec_data: *UInt8, vec_len: Int, vec_cap: Int, offset: Int, count: Int);
  fn xiom_http_headers_build(blob: *UInt8) -> *UInt8;
  fn xiom_http_headers_free(list: *UInt8);
}

// --- libcurl FFI ------------------------------------------------------------

extern "C" {
  fn curl_easy_init() -> *UInt8;
  fn curl_easy_setopt(handle: *UInt8, option: Int, value: *UInt8) -> Int;
  fn curl_easy_perform(handle: *UInt8) -> Int;
  fn curl_easy_getinfo(handle: *UInt8, info: Int, arg: *UInt8) -> Int;
  fn curl_easy_cleanup(handle: *UInt8);
  fn curl_easy_strerror(code: Int) -> *UInt8;
}

// --- libc FFI (file I/O) ----------------------------------------------------

extern "C" {
  fn fopen(path: *UInt8, mode: *UInt8) -> *UInt8;
  fn fclose(file: *UInt8) -> Int32;
  fn fread(buf: *UInt8, size: UInt64, count: UInt64, file: *UInt8) -> UInt64;
  fn fwrite(buf: *UInt8, size: UInt64, count: UInt64, file: *UInt8) -> UInt64;
  fn fseek(file: *UInt8, offset: Int64, whence: Int32) -> Int32;
  fn ftell(file: *UInt8) -> Int64;
  fn remove(path: *UInt8) -> Int32;
}

// --- Types ------------------------------------------------------------------

pub type HttpClientResponse = {
  status: Int;
  body: Str;
  headers: Str;
} derive[Clone]

// Typed outcome of the raw-bytes request entry (0.1.9). Body validation
// happens before any FFI call, so a caller can distinguish a malformed
// body/length pair from an actual transport failure without parsing text.
pub enum HttpBytesRequestError {
  BodyLengthMismatch(declared: Int, actual: Int),
  BodyLengthNegative(declared: Int),
  InvalidConnectTimeout(value: Int),
  InvalidTotalTimeout(value: Int),
  UnsupportedMethod(method: Str),
  Transport(message: Str),
}

// Typed outcome of the per-call-options entries (0.1.10). Invalid timeout
// values are rejected before any FFI call, so a caller can tell a bad option
// from a transport failure without parsing text.
pub enum HttpOptionsRequestError {
  ConnectTimeoutNegative(value: Int),
  TotalTimeoutNegative(value: Int),
  UnsupportedMethod(method: Str),
  Transport(message: Str),
}

// A client session owns one libcurl easy handle across sequential requests.
// libcurl keeps its connection cache on the handle, so two requests to the
// same origin through one session reuse the established connection.
pub type HttpClientSession = {
  handle: *UInt8;
}

// --- CURL Option Constants --------------------------------------------------

fn CURLOPT_URL() -> Int
  ensures: result == 10002;
{
  return 10002;
}
fn CURLOPT_FOLLOWLOCATION() -> Int
  ensures: result == 52;
{
  return 52;
}
fn CURLOPT_TIMEOUT_MS() -> Int
  ensures: result == 155;
{
  return 155;
}
fn CURLOPT_CONNECTTIMEOUT_MS() -> Int
  ensures: result == 156;
{
  return 156;
}
fn CURLOPT_POST() -> Int
  ensures: result == 47;
{
  return 47;
}
fn CURLOPT_POSTFIELDS() -> Int
  ensures: result == 10015;
{
  return 10015;
}
fn CURLOPT_POSTFIELDSIZE() -> Int
  ensures: result == 60;
{
  return 60;
}
fn CURLOPT_CUSTOMREQUEST() -> Int
  ensures: result == 10036;
{
  return 10036;
}
fn CURLOPT_HTTPHEADER() -> Int
  ensures: result == 10023;
{
  return 10023;
}
fn CURLOPT_SSL_VERIFYPEER() -> Int
  ensures: result == 64;
{
  return 64;
}
fn CURLOPT_SSL_VERIFYHOST() -> Int
  ensures: result == 81;
{
  return 81;
}
fn CURLOPT_USERAGENT() -> Int
  ensures: result == 10018;
{
  return 10018;
}
fn CURLOPT_WRITEDATA() -> Int
  ensures: result == 10001;
{
  return 10001;
}
fn CURLOPT_HEADERDATA() -> Int
  ensures: result == 10029;
{
  return 10029;
}
fn CURLOPT_NOSIGNAL() -> Int
  ensures: result == 99;
{
  return 99;
}
fn CURLOPT_FAILONERROR() -> Int
  ensures: result == 45;
{
  return 45;
}
fn CURLOPT_ACCEPT_ENCODING() -> Int
  ensures: result == 10102;
{
  return 10102;
}
fn CURLOPT_TCP_KEEPALIVE() -> Int
  ensures: result == 213;
{
  return 213;
}
fn CURLOPT_TCP_KEEPIDLE() -> Int
  ensures: result == 214;
{
  return 214;
}
fn CURLOPT_TCP_KEEPINTVL() -> Int
  ensures: result == 215;
{
  return 215;
}
fn CURLOPT_BUFFERSIZE() -> Int
  ensures: result == 98;
{
  return 98;
}

fn CURLINFO_RESPONSE_CODE() -> Int
  ensures: result == 2097154;
{
  return 2097154;
}

// --- Internal Constants -----------------------------------------------------

fn SEEK_SET() -> Int
  ensures: result == 0;
{
  return 0;
}
fn SEEK_END() -> Int
  ensures: result == 2;
{
  return 2;
}
fn BUF_SIZE() -> Int
  ensures: result == 65536;
{
  return 65536;
}

fn TEMP_BODY() -> Str
  ensures: result.len() == 20;
{
  return "__xiom_http_body.tmp";
}
fn TEMP_HEADERS() -> Str
  ensures: result.len() == 23;
{
  return "__xiom_http_headers.tmp";
}

// --- Long-Option Value Helper -----------------------------------------------
// libcurl's curl_easy_setopt is variadic: for CURLOPTTYPE_LONG options (e.g.
// FOLLOWLOCATION, TIMEOUT, CONNECTTIMEOUT, NOSIGNAL, BUFFERSIZE, POST,
// POSTFIELDSIZE) the third argument is the long VALUE itself, read from the
// register -- not a pointer. XIOM's FFI surface types that parameter as
// *UInt8, so the raw value is passed through an Int -> *UInt8 value cast.
// The result is a bare value; it is NEVER dereferenced and needs no
// allocation or free (0.1.4 fix). STRINGPOINT/OBJECTPOINT sites (URL,
// USERAGENT, POSTFIELDS, CUSTOMREQUEST, WRITEDATA, ...) keep real pointers.

fn make_long_value(v: Int) -> *UInt8 {
  var p: *UInt8 = ptr_null();
  unsafe { p = v as *UInt8; }
  return p;
}

fn ptr_null() -> *UInt8 {
  var p: *UInt8 = ptr.null[UInt8]();
  unsafe { return p; }
}

// --- C String Helpers -------------------------------------------------------
// The XIOM runtime provides xiom_str_to_cstr. We pass the raw string pointer
// via the encoding module's utf8_encode, then to the FFI bridge.

fn str_to_cstr(s: Str) -> *UInt8 {
  var bytes: Vec[UInt8] = encoding.utf8_encode(s);
  var len: Int = bytes.len();
  var cstr: *UInt8 = ptr_null();
  if len == 0 {
    unsafe { cstr = xiom_str_to_cstr(ptr_null(), 0); }
    return cstr;
  };
  unsafe { cstr = xiom_str_to_cstr(&bytes[0], len); }
  return cstr;
}

fn str_to_cstr_or_err(s: Str, label: Str) -> Result[*UInt8, Str] {
  var c: *UInt8 = str_to_cstr(s);
  if ptr.is_null[UInt8](c) {
    return Err(label + ": xiom_str_to_cstr returned null");
  };
  return Ok(c);
}

// --- Error Helpers ----------------------------------------------------------

fn curl_error_string(code: Int) -> Str
  ensures: result.len() > 0;
{
  var err_ptr: *UInt8 = ptr_null();
  unsafe { err_ptr = curl_easy_strerror(code); }
  if ptr.is_null[UInt8](err_ptr) {
    return "unknown curl error";
  };
  return cstr_to_str(err_ptr);
}

// --- C String -> XIOM Str ---------------------------------------------------

fn cstr_to_str(cstr: *UInt8) -> Str
  ensures: result.len() <= 196608;
{
  var result: Str = "";
  var i: Int = 0;
  while i < 65536 {
    var b: Int = unsafe { xiom_read_byte(cstr, i) };
    if b == 0 as UInt8 { break; };
    var b_int: Int = b as Int;
    result = result + byte_to_char(b_int);
    i = i + 1;
  };
  return result;
}

fn byte_to_char(b: Int) -> Str
  ensures: b == 0 => result.len() == 0;
  ensures: b == 9 || b == 10 || b == 13 || b == 32 => result.len() == 1;
  ensures: b >= 33 && b <= 126 => result.len() == 1;
  ensures: b != 0 && b != 9 && b != 10 && b != 13 && b != 32 && (b < 33 || b > 126) => result.len() == 1;
{
  if b == 0 { return ""; };
  if b == 10 { return "\n"; };
  if b == 13 { return "\r"; };
  if b == 9 { return "\t"; };
  if b == 32 { return " "; };
  if b >= 33 && b <= 126 {
    var ch: Char = to_char(b);
    return char_to_str(ch);
  };
  return "?";
}

fn char_to_str(c: Char) -> Str
  ensures: result.len() <= 4;
{
  return tostring.to_string_char(c);
}

// --- Temp File Management ---------------------------------------------------

pub type TempFiles = {
  body: *UInt8;
  headers: *UInt8;
}

fn open_temp_files() -> Result[TempFiles, Str] {
  var body_path: *UInt8 = str_to_cstr(TEMP_BODY());
  var headers_path: *UInt8 = str_to_cstr(TEMP_HEADERS());
  var mode: *UInt8 = str_to_cstr("wb+");

  var body_c: *UInt8 = ptr_null();
  unsafe { body_c = fopen(body_path, mode); }
  if ptr.is_null[UInt8](body_c) {
    unsafe {
      xiom_free_cstr(body_path);
      xiom_free_cstr(headers_path);
      xiom_free_cstr(mode);
    }
    return Err("failed to open body temp file");
  };

  var headers_c: *UInt8 = ptr_null();
  unsafe { headers_c = fopen(headers_path, mode); }
  if ptr.is_null[UInt8](headers_c) {
    unsafe {
      xiom_free_cstr(body_path);
      xiom_free_cstr(headers_path);
      xiom_free_cstr(mode);
    }
    return Err("failed to open headers temp file");
  };

  unsafe {
    xiom_free_cstr(body_path);
    xiom_free_cstr(headers_path);
    xiom_free_cstr(mode);
  }

  return Ok(TempFiles{ body: body_c, headers: headers_c });
}

fn close_temp_files(body_f: *UInt8, headers_f: *UInt8) {
  unsafe { let _ = fclose(body_f); }
  unsafe { let _ = fclose(headers_f); }
}

fn cleanup_temp_files() {
  var body_path: *UInt8 = str_to_cstr(TEMP_BODY());
  var headers_path: *UInt8 = str_to_cstr(TEMP_HEADERS());
  unsafe { let _ = remove(body_path); }
  unsafe { let _ = remove(headers_path); }
  unsafe { xiom_free_cstr(body_path); }
  unsafe { xiom_free_cstr(headers_path); }
}

// --- File I/O Helpers -------------------------------------------------------

fn read_file_to_str(file: *UInt8) -> Str
  ensures: result.len() <= 196608;
{
  var file_size: Int;
  unsafe { let _ = fseek(file, 0 as Int64, SEEK_END() as Int32); }
  unsafe { file_size = ftell(file) as Int; }
  unsafe { let _ = fseek(file, 0 as Int64, SEEK_SET() as Int32); }

  if file_size <= 0 {
    return "";
  };

  var buf: *UInt8 = ptr_null();
  unsafe { buf = xiom_alloc(file_size + 1); }
  if ptr.is_null[UInt8](buf) {
    return "";
  };

  var read_count: Int = unsafe { fread(buf, 1 as UInt64, file_size as UInt64, file) as Int };
  var term: Int = read_count;
  if term < 0 { term = 0; };
  if term > file_size { term = file_size; };

  if term >= 0 {
    unsafe { xiom_write_byte(buf, term, 0); }
  };
  var result: Str = cstr_to_str(buf);
  unsafe { xiom_free_ptr(buf); }
  return result;
}

// --- Response Code Extraction -----------------------------------------------

fn get_response_code(handle: *UInt8) -> Int
  ensures: result >= 0;
  ensures: result <= 65535;
{
  var status_buf: *UInt8 = ptr_null();
  unsafe { status_buf = xiom_alloc(8); }
  if ptr.is_null[UInt8](status_buf) {
    return 0;
  };

  var rc: Int = unsafe { curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE(), status_buf) };
  if rc != 0 {
    unsafe { xiom_free_ptr(status_buf); }
    return 0;
  };

  var lo: Int = status_buf[0] as Int;
  var hi: Int = status_buf[1] as Int;
  var status: Int = lo | (hi << 8);
  unsafe { xiom_free_ptr(status_buf); }
  return status;
}

// --- cURL Setup Helpers -----------------------------------------------------

fn setup_common_options(handle: *UInt8, url_cstr: *UInt8, opts: HttpRequestOptions) -> Result[Unit, Str] {
  var rc: Int;

  unsafe { rc = curl_easy_setopt(handle, CURLOPT_URL(), url_cstr); }
  if rc != 0 { return Err(string.str_concat("CURLOPT_URL failed: ", curl_error_string(rc))); };

  unsafe { rc = curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION(), make_long_value(1)); }
  if rc != 0 { return Err(string.str_concat("CURLOPT_FOLLOWLOCATION failed: ", curl_error_string(rc))); };

  unsafe { rc = curl_easy_setopt(handle, CURLOPT_TIMEOUT_MS(), make_long_value(options.effective_total_ms(&opts))); }
  if rc != 0 { return Err(string.str_concat("CURLOPT_TIMEOUT_MS failed: ", curl_error_string(rc))); };

  unsafe { rc = curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT_MS(), make_long_value(options.effective_connect_ms(&opts))); }
  if rc != 0 { return Err(string.str_concat("CURLOPT_CONNECTTIMEOUT_MS failed: ", curl_error_string(rc))); };

  unsafe { rc = curl_easy_setopt(handle, CURLOPT_NOSIGNAL(), make_long_value(1)); }
  if rc != 0 { return Err(string.str_concat("CURLOPT_NOSIGNAL failed: ", curl_error_string(rc))); };

  var encoding_cstr: *UInt8 = str_to_cstr("gzip, deflate");
  unsafe { rc = curl_easy_setopt(handle, CURLOPT_ACCEPT_ENCODING(), encoding_cstr); }
  unsafe { xiom_free_cstr(encoding_cstr); }
  if rc != 0 { return Err(string.str_concat("CURLOPT_ACCEPT_ENCODING failed: ", curl_error_string(rc))); };

  // User-Agent is deliberately pinned: SPEC documents "xiom.http/0.1.0" as the
  // stable client identifier and it has survived the 0.1.1..0.1.4 bumps, so it
  // tracks compatibility, not the package version.
  var ua_cstr: *UInt8 = str_to_cstr("xiom.http/0.1.0");
  unsafe { rc = curl_easy_setopt(handle, CURLOPT_USERAGENT(), ua_cstr); }
  unsafe { xiom_free_cstr(ua_cstr); }
  if rc != 0 { return Err(string.str_concat("CURLOPT_USERAGENT failed: ", curl_error_string(rc))); };

  unsafe { rc = curl_easy_setopt(handle, CURLOPT_BUFFERSIZE(), make_long_value(BUF_SIZE())); }
  if rc != 0 { return Err(string.str_concat("CURLOPT_BUFFERSIZE failed: ", curl_error_string(rc))); };

  return Ok(());
}

// setup_common_options_default applies the library defaults used by every
// pre-0.1.10 one-shot entry (30 s total / 10 s connect).
fn setup_common_options_default(handle: *UInt8, url_cstr: *UInt8) -> Result[Unit, Str] {
  return setup_common_options(handle, url_cstr, options.http_request_options_default());
}

fn perform_and_collect(handle: *UInt8, body_f: *UInt8, headers_f: *UInt8) -> Result[Unit, Str] {
  var rc: Int;
  unsafe { rc = curl_easy_setopt(handle, CURLOPT_WRITEDATA(), body_f); }
  if rc != 0 { return Err(string.str_concat("CURLOPT_WRITEDATA failed: ", curl_error_string(rc))); };
  unsafe { rc = curl_easy_setopt(handle, CURLOPT_HEADERDATA(), headers_f); }
  if rc != 0 { return Err(string.str_concat("CURLOPT_HEADERDATA failed: ", curl_error_string(rc))); };
  unsafe { rc = curl_easy_perform(handle); }
  if rc != 0 { return Err(string.str_concat("curl_easy_perform failed: ", curl_error_string(rc))); };
  return Ok(());
}

// --- Headers-Capable Request Helpers (0.1.8) --------------------------------

// cleanup_http_request releases every resource http_request may hold on any
// exit path, exactly once: the curl handle first, THEN the header slist
// (libcurl references the list until curl_easy_cleanup), then the C strings.
// Null pointers are skipped, so callers pass whatever they have.
fn cleanup_http_request(handle: *UInt8, header_list: *UInt8, url_cstr: *UInt8, body_cstr: *UInt8) {
  unsafe { curl_easy_cleanup(handle); }
  if !ptr.is_null[UInt8](header_list) {
    unsafe { xiom_http_headers_free(header_list); }
  };
  if !ptr.is_null[UInt8](url_cstr) {
    unsafe { xiom_free_cstr(url_cstr); }
  };
  if !ptr.is_null[UInt8](body_cstr) {
    unsafe { xiom_free_cstr(body_cstr); }
  };
}

// set_request_method maps a validated method string onto libcurl setup:
// POST uses CURLOPT_POST (same as http_post); GET leaves the default; every
// other supported method goes through CURLOPT_CUSTOMREQUEST.
fn set_request_method(handle: *UInt8, method: Str) -> Result[Unit, Str] {
  var rc: Int;
  if method == "POST" {
    unsafe { rc = curl_easy_setopt(handle, CURLOPT_POST(), make_long_value(1)); }
    if rc != 0 { return Err(string.str_concat("CURLOPT_POST failed: ", curl_error_string(rc))); };
    return Ok(());
  };
  if method == "GET" {
    return Ok(());
  };
  var method_cstr: *UInt8 = str_to_cstr(method);
  if ptr.is_null[UInt8](method_cstr) {
    return Err("xiom_str_to_cstr failed for method");
  };
  unsafe { rc = curl_easy_setopt(handle, CURLOPT_CUSTOMREQUEST(), method_cstr); }
  unsafe { xiom_free_cstr(method_cstr); }
  if rc != 0 { return Err(string.str_concat("CURLOPT_CUSTOMREQUEST failed: ", curl_error_string(rc))); };
  return Ok(());
}

fn is_supported_method(method: Str) -> Bool {
  return method == "GET" || method == "POST" || method == "PUT" || method == "PATCH" || method == "DELETE" || method == "HEAD" || method == "OPTIONS";
}

fn method_has_body(method: Str) -> Bool {
  return method == "POST" || method == "PUT" || method == "PATCH";
}

// setup_request_headers builds and installs the curl_slist for the CRLF blob
// produced by xiom.http.headers.http_headers_blob. An empty blob returns a
// null list and makes no CURLOPT_HTTPHEADER call (exact wrapper behavior).
// On failure the partial list is released here; callers only ever receive a
// fully installed list.
fn setup_request_headers(handle: *UInt8, headers: Str) -> Result[*UInt8, Str] {
  var header_list: *UInt8 = ptr_null();
  if string.str_len(headers) == 0 {
    return Ok(header_list);
  };
  var headers_cstr: *UInt8 = str_to_cstr(headers);
  if ptr.is_null[UInt8](headers_cstr) {
    return Err("xiom_str_to_cstr failed for headers");
  };
  unsafe { header_list = xiom_http_headers_build(headers_cstr); }
  unsafe { xiom_free_cstr(headers_cstr); }
  if ptr.is_null[UInt8](header_list) {
    return Err("failed to build curl_slist from header blob");
  };
  var rc_h: Int = unsafe { curl_easy_setopt(handle, CURLOPT_HTTPHEADER(), header_list) };
  if rc_h != 0 {
    unsafe { xiom_http_headers_free(header_list); }
    return Err(string.str_concat("CURLOPT_HTTPHEADER failed: ", curl_error_string(rc_h)));
  };
  return Ok(header_list);
}

// perform_and_capture executes one transfer and captures status/body/headers
// without releasing the handle. The caller owns handle lifetime, which lets a
// session reuse the same easy handle (and therefore libcurl's connection
// cache) across sequential requests.
fn perform_and_capture(handle: *UInt8) -> Result[HttpClientResponse, Str] {
  var files = open_temp_files();
  match files {
    Err(e) => { return Err(e); },
    Ok(fds) => {
      var perf = perform_and_collect(handle, fds.body, fds.headers);
      var status: Int = get_response_code(handle);
      var resp_body: Str = read_file_to_str(fds.body);
      var resp_headers: Str = read_file_to_str(fds.headers);
      close_temp_files(fds.body, fds.headers);
      cleanup_temp_files();
      match perf { Err(e) => { return Err(e); }, Ok(_) => {}, };
      return Ok(HttpClientResponse{ status: status, body: resp_body, headers: resp_headers });
    },
  };
  return Err("unreachable");
}

// perform_request_common executes the transfer and captures status/body/
// headers, then releases every request resource exactly once. Shared by the
// Str-body http_request and the raw-bytes http_request_bytes entries.
fn perform_request_common(handle: *UInt8, header_list: *UInt8, url_cstr: *UInt8, body_cstr: *UInt8) -> Result[HttpClientResponse, Str] {
  var result = perform_and_capture(handle);
  cleanup_http_request(handle, header_list, url_cstr, body_cstr);
  return result;
}

// cleanup_session_request releases only the per-request resources of a
// session-owned handle. The handle itself stays open for connection reuse.
// CURLOPT_HTTPHEADER is cleared before the list is freed so libcurl never
// holds a dangling pointer between requests.
fn cleanup_session_request(handle: *UInt8, header_list: *UInt8, url_cstr: *UInt8, body_cstr: *UInt8) {
  if !ptr.is_null[UInt8](header_list) {
    unsafe { let _ = curl_easy_setopt(handle, CURLOPT_HTTPHEADER(), ptr_null()); }
    unsafe { xiom_http_headers_free(header_list); }
  };
  if !ptr.is_null[UInt8](url_cstr) {
    unsafe { xiom_free_cstr(url_cstr); }
  };
  if !ptr.is_null[UInt8](body_cstr) {
    unsafe { xiom_free_cstr(body_cstr); }
  };
}

// reset_request_state clears request-specific options that otherwise persist
// on a reused easy handle (a prior POST would leak into a later GET). The
// common options, URL, and connection cache are re-established per call.
fn reset_request_state(handle: *UInt8) -> Result[Unit, Str] {
  var rc: Int;
  unsafe { rc = curl_easy_setopt(handle, CURLOPT_POST(), make_long_value(0)); }
  if rc != 0 { return Err(string.str_concat("CURLOPT_POST reset failed: ", curl_error_string(rc))); };
  unsafe { rc = curl_easy_setopt(handle, CURLOPT_CUSTOMREQUEST(), ptr_null()); }
  if rc != 0 { return Err(string.str_concat("CURLOPT_CUSTOMREQUEST reset failed: ", curl_error_string(rc))); };
  unsafe { rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDS(), ptr_null()); }
  if rc != 0 { return Err(string.str_concat("CURLOPT_POSTFIELDS reset failed: ", curl_error_string(rc))); };
  unsafe { rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE(), make_long_value(0)); }
  if rc != 0 { return Err(string.str_concat("CURLOPT_POSTFIELDSIZE reset failed: ", curl_error_string(rc))); };
  return Ok(());
}

fn bytes_request_body_error(e: HttpBodyError) -> HttpBytesRequestError {
  match e {
    HttpBodyError.LengthMismatch(declared, actual) => {
      return HttpBytesRequestError.BodyLengthMismatch(declared, actual);
    },
    HttpBodyError.NegativeLength(declared) => {
      return HttpBytesRequestError.BodyLengthNegative(declared);
    },
  };
}

// --- URL Checking -----------------------------------------------------------

fn check_url(url_cstr: *UInt8, handle: *UInt8) -> Bool {
  return !ptr.is_null[UInt8](url_cstr) && !ptr.is_null[UInt8](handle);
}

// --- Public HTTP API --------------------------------------------------------

pub fn http_get(url: Str) -> Result[HttpClientResponse, Str]
  requires: string.str_len(url) > 0
{
  var url_cstr: *UInt8 = str_to_cstr(url);
  if ptr.is_null[UInt8](url_cstr) {
    return Err("xiom_str_to_cstr failed for URL");
  };

  var handle: *UInt8 = ptr_null();
  unsafe { handle = curl_easy_init(); }
  if ptr.is_null[UInt8](handle) {
    unsafe { xiom_free_cstr(url_cstr); }
    return Err("curl_easy_init returned null handle");
  };

  var setup = setup_common_options_default(handle, url_cstr);
  match setup {
    Err(e) => { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); }; return Err(e); },
    Ok(_) => {},
  };

  var files = open_temp_files();
  match files {
    Err(e) => { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); }; return Err(e); },
    Ok(fds) => {
      var perf = perform_and_collect(handle, fds.body, fds.headers);
      var status: Int = get_response_code(handle);
      var body: Str = read_file_to_str(fds.body);
      var headers: Str = read_file_to_str(fds.headers);
      close_temp_files(fds.body, fds.headers);
      cleanup_temp_files();
      unsafe { curl_easy_cleanup(handle); }
      unsafe { xiom_free_cstr(url_cstr); }
      match perf { Err(e) => { return Err(e); }, Ok(_) => {}, };
      return Ok(HttpClientResponse{ status: status, body: body, headers: headers });
    },
  };
}

pub fn http_post(url: Str, body: Str, content_type: Str) -> Result[HttpClientResponse, Str]
  requires: string.str_len(url) > 0
{
  var url_cstr: *UInt8 = str_to_cstr(url);
  if ptr.is_null[UInt8](url_cstr) { return Err("xiom_str_to_cstr failed for URL"); };

  var handle: *UInt8 = ptr_null();
  unsafe { handle = curl_easy_init(); }
  if ptr.is_null[UInt8](handle) { unsafe { xiom_free_cstr(url_cstr); }; return Err("curl_easy_init returned null handle"); };

  var setup = setup_common_options_default(handle, url_cstr);
  match setup { Err(e) => { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); }; return Err(e); }, Ok(_) => {}, };

  var rc: Int;
  unsafe { rc = curl_easy_setopt(handle, CURLOPT_POST(), make_long_value(1)); }
  if rc != 0 { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); }; return Err(string.str_concat("CURLOPT_POST failed: ", curl_error_string(rc))); };

  var body_cstr: *UInt8 = str_to_cstr(body);
  if ptr.is_null[UInt8](body_cstr) { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); }; return Err("xiom_str_to_cstr failed for body"); };

  unsafe { rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDS(), body_cstr); }
  if rc != 0 { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); xiom_free_cstr(body_cstr); }; return Err(string.str_concat("CURLOPT_POSTFIELDS failed: ", curl_error_string(rc))); };

  var body_bytes: Vec[UInt8] = encoding.utf8_encode(body);
  unsafe { rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE(), make_long_value(body_bytes.len())); }
  if rc != 0 { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); xiom_free_cstr(body_cstr); }; return Err(string.str_concat("CURLOPT_POSTFIELDSIZE failed: ", curl_error_string(rc))); };

  var files = open_temp_files();
  match files {
    Err(e) => { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); xiom_free_cstr(body_cstr); }; return Err(e); },
    Ok(fds) => {
      var perf = perform_and_collect(handle, fds.body, fds.headers);
      var status: Int = get_response_code(handle);
      var resp_body: Str = read_file_to_str(fds.body);
      var headers: Str = read_file_to_str(fds.headers);
      close_temp_files(fds.body, fds.headers);
      cleanup_temp_files();
      unsafe { curl_easy_cleanup(handle); }
      unsafe { xiom_free_cstr(url_cstr); }
      unsafe { xiom_free_cstr(body_cstr); }
      match perf { Err(e) => { return Err(e); }, Ok(_) => {}, };
      return Ok(HttpClientResponse{ status: status, body: resp_body, headers: headers });
    },
  };
  return Err("unreachable");
}

pub fn http_put(url: Str, body: Str) -> Result[HttpClientResponse, Str]
  requires: string.str_len(url) > 0
{
  var url_cstr: *UInt8 = str_to_cstr(url);
  if ptr.is_null[UInt8](url_cstr) { return Err("xiom_str_to_cstr failed for URL"); };

  var handle: *UInt8 = ptr_null();
  unsafe { handle = curl_easy_init(); }
  if ptr.is_null[UInt8](handle) { unsafe { xiom_free_cstr(url_cstr); }; return Err("curl_easy_init returned null handle"); };

  var setup = setup_common_options_default(handle, url_cstr);
  match setup { Err(e) => { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); }; return Err(e); }, Ok(_) => {}, };

  var rc: Int;
  var method_cstr: *UInt8 = str_to_cstr("PUT");
  unsafe { rc = curl_easy_setopt(handle, CURLOPT_CUSTOMREQUEST(), method_cstr); }
  unsafe { xiom_free_cstr(method_cstr); }
  if rc != 0 { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); }; return Err(string.str_concat("CURLOPT_CUSTOMREQUEST PUT failed: ", curl_error_string(rc))); };

  var body_cstr: *UInt8 = str_to_cstr(body);
  if ptr.is_null[UInt8](body_cstr) { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); }; return Err("xiom_str_to_cstr failed for body"); };

  unsafe { rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDS(), body_cstr); }
  if rc != 0 { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); xiom_free_cstr(body_cstr); }; return Err(string.str_concat("CURLOPT_POSTFIELDS PUT failed: ", curl_error_string(rc))); };

  var body_bytes: Vec[UInt8] = encoding.utf8_encode(body);
  unsafe { rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE(), make_long_value(body_bytes.len())); }
  if rc != 0 { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); xiom_free_cstr(body_cstr); }; return Err(string.str_concat("CURLOPT_POSTFIELDSIZE PUT failed: ", curl_error_string(rc))); };

  var files = open_temp_files();
  match files {
    Err(e) => { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); xiom_free_cstr(body_cstr); }; return Err(e); },
    Ok(fds) => {
      var perf = perform_and_collect(handle, fds.body, fds.headers);
      var status: Int = get_response_code(handle);
      var resp_body: Str = read_file_to_str(fds.body);
      var headers: Str = read_file_to_str(fds.headers);
      close_temp_files(fds.body, fds.headers);
      cleanup_temp_files();
      unsafe { curl_easy_cleanup(handle); }
      unsafe { xiom_free_cstr(url_cstr); }
      unsafe { xiom_free_cstr(body_cstr); }
      match perf { Err(e) => { return Err(e); }, Ok(_) => {}, };
      return Ok(HttpClientResponse{ status: status, body: resp_body, headers: headers });
    },
  };
  return Err("unreachable");
}

pub fn http_delete(url: Str) -> Result[HttpClientResponse, Str]
  requires: string.str_len(url) > 0
{
  var url_cstr: *UInt8 = str_to_cstr(url);
  if ptr.is_null[UInt8](url_cstr) { return Err("xiom_str_to_cstr failed for URL"); };

  var handle: *UInt8 = ptr_null();
  unsafe { handle = curl_easy_init(); }
  if ptr.is_null[UInt8](handle) { unsafe { xiom_free_cstr(url_cstr); }; return Err("curl_easy_init returned null handle"); };

  var setup = setup_common_options_default(handle, url_cstr);
  match setup { Err(e) => { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); }; return Err(e); }, Ok(_) => {}, };

  var rc: Int;
  var method_cstr: *UInt8 = str_to_cstr("DELETE");
  unsafe { rc = curl_easy_setopt(handle, CURLOPT_CUSTOMREQUEST(), method_cstr); }
  unsafe { xiom_free_cstr(method_cstr); }
  if rc != 0 { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); }; return Err(string.str_concat("CURLOPT_CUSTOMREQUEST DELETE failed: ", curl_error_string(rc))); };

  var files = open_temp_files();
  match files {
    Err(e) => { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); }; return Err(e); },
    Ok(fds) => {
      var perf = perform_and_collect(handle, fds.body, fds.headers);
      var status: Int = get_response_code(handle);
      var resp_body: Str = read_file_to_str(fds.body);
      var headers: Str = read_file_to_str(fds.headers);
      close_temp_files(fds.body, fds.headers);
      cleanup_temp_files();
      unsafe { curl_easy_cleanup(handle); }
      unsafe { xiom_free_cstr(url_cstr); }
      match perf { Err(e) => { return Err(e); }, Ok(_) => {}, };
      return Ok(HttpClientResponse{ status: status, body: resp_body, headers: headers });
    },
  };
  return Err("unreachable");
}

pub fn http_download(url: Str, path: Str) -> Result[Unit, Str]
  requires: string.str_len(url) > 0
  requires: string.str_len(path) > 0
{
  var url_cstr: *UInt8 = str_to_cstr(url);
  if ptr.is_null[UInt8](url_cstr) { return Err("xiom_str_to_cstr failed for URL"); };

  var handle: *UInt8 = ptr_null();
  unsafe { handle = curl_easy_init(); }
  if ptr.is_null[UInt8](handle) { unsafe { xiom_free_cstr(url_cstr); }; return Err("curl_easy_init returned null handle"); };

  var setup = setup_common_options_default(handle, url_cstr);
  match setup { Err(e) => { unsafe { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); }; return Err(e); }, Ok(_) => {}, };

  var path_cstr: *UInt8 = str_to_cstr(path);
  var mode_cstr: *UInt8 = str_to_cstr("wb");
  var out_file: *UInt8 = ptr_null();
  unsafe { out_file = fopen(path_cstr, mode_cstr); }
  if ptr.is_null[UInt8](out_file) {
    unsafe { curl_easy_cleanup(handle); }
    unsafe { xiom_free_cstr(url_cstr); }
    unsafe { xiom_free_cstr(path_cstr); }
    unsafe { xiom_free_cstr(mode_cstr); }
    return Err(string.str_concat("failed to open output file: ", path));
  };

  var rc: Int = unsafe { curl_easy_setopt(handle, CURLOPT_WRITEDATA(), out_file) };
  if rc != 0 {
    unsafe { let _ = fclose(out_file); }
    unsafe { curl_easy_cleanup(handle); }
    unsafe { xiom_free_cstr(url_cstr); }
    unsafe { xiom_free_cstr(path_cstr); }
    unsafe { xiom_free_cstr(mode_cstr); }
    return Err(string.str_concat("CURLOPT_WRITEDATA download failed: ", curl_error_string(rc)));
  };

  var perf_rc: Int = unsafe { curl_easy_perform(handle) };
  unsafe { let _ = fclose(out_file); }

  if perf_rc != 0 {
    var err_msg: Str = curl_error_string(perf_rc);
    unsafe { curl_easy_cleanup(handle); }
    unsafe { xiom_free_cstr(url_cstr); }
    unsafe { let _ = remove(path_cstr); }
    unsafe { xiom_free_cstr(path_cstr); }
    unsafe { xiom_free_cstr(mode_cstr); }
    return Err(string.str_concat("download failed: ", err_msg));
  };

  var status: Int = get_response_code(handle);
  unsafe { curl_easy_cleanup(handle); }
  unsafe { xiom_free_cstr(url_cstr); }
  unsafe { xiom_free_cstr(mode_cstr); }

  if status < 200 || status >= 300 {
    unsafe { let _ = remove(path_cstr); }
    unsafe { xiom_free_cstr(path_cstr); }
    return Err(string.str_concat("download failed with HTTP status ", to_string(status)));
  };
  unsafe { xiom_free_cstr(path_cstr); }

  return Ok(());
}

// --- Headers-Capable Request Entry (0.1.8) ----------------------------------
//
// http_request is the ONE new client entry added in 0.1.8. The five existing
// wrappers (http_get / http_post / http_put / http_delete / http_download)
// are unchanged; this entry adds custom request headers (including
// `Authorization: Bearer ...`) on top of the same libcurl flow.
//
//   url     -- request URL (same handling as the wrappers).
//   method  -- one of GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS
//              (upper-case; anything else returns Err before any FFI call).
//   body    -- request body for POST, PUT and PATCH (exact UTF-8 bytes);
//              ignored for GET, DELETE, HEAD and OPTIONS, which send no
//              body -- matching the wrappers' behavior.
//   headers -- the CRLF-joined blob produced by
//              xiom.http.headers.http_headers_blob; "" means no custom
//              headers. Each CRLF-terminated line becomes one curl_slist
//              node via the bridge helper xiom_http_headers_build; the list
//              is freed with xiom_http_headers_free after curl_easy_cleanup
//              (libcurl references it until then). Header values are never
//              logged or echoed in error messages.
//
// Mirrors the wrapper flow: common options -> headers/method/body ->
// WRITEDATA/HEADERDATA temp files -> perform -> status/body/headers capture
// -> cleanup.
pub fn http_request(url: Str, method: Str, body: Str, headers: Str) -> Result[HttpClientResponse, Str]
  requires: string.str_len(url) > 0
  requires: string.str_len(method) > 0
{
  return http_request_core(url, method, body, headers, options.http_request_options_default());
}

fn http_request_core(url: Str, method: Str, body: Str, headers: Str, opts: HttpRequestOptions) -> Result[HttpClientResponse, Str]
  requires: string.str_len(url) > 0
  requires: string.str_len(method) > 0
{
  if !is_supported_method(method) {
    return Err(string.str_concat("http_request: unsupported method ", method));
  };
  var has_body: Bool = method_has_body(method);

  var url_cstr: *UInt8 = str_to_cstr(url);
  if ptr.is_null[UInt8](url_cstr) {
    return Err("xiom_str_to_cstr failed for URL");
  };

  var handle: *UInt8 = ptr_null();
  unsafe { handle = curl_easy_init(); }
  if ptr.is_null[UInt8](handle) {
    unsafe { xiom_free_cstr(url_cstr); }
    return Err("curl_easy_init returned null handle");
  };

  var header_list: *UInt8 = ptr_null();
  var body_cstr: *UInt8 = ptr_null();

  var setup = setup_common_options(handle, url_cstr, opts);
  match setup {
    Err(e) => { cleanup_http_request(handle, header_list, url_cstr, body_cstr); return Err(e); },
    Ok(_) => {},
  };

  // Custom headers: an empty blob keeps the exact wrapper behavior (no
  // CURLOPT_HTTPHEADER call at all); a non-empty blob must build a list.
  var header_res = setup_request_headers(handle, headers);
  match header_res {
    Err(e) => { cleanup_http_request(handle, header_list, url_cstr, body_cstr); return Err(e); },
    Ok(list) => { header_list = list; },
  };

  var method_res = set_request_method(handle, method);
  match method_res {
    Err(e) => { cleanup_http_request(handle, header_list, url_cstr, body_cstr); return Err(e); },
    Ok(_) => {},
  };

  if has_body {
    body_cstr = str_to_cstr(body);
    if ptr.is_null[UInt8](body_cstr) {
      cleanup_http_request(handle, header_list, url_cstr, body_cstr);
      return Err("xiom_str_to_cstr failed for body");
    };
    var rc_b: Int = unsafe { curl_easy_setopt(handle, CURLOPT_POSTFIELDS(), body_cstr) };
    if rc_b != 0 {
      cleanup_http_request(handle, header_list, url_cstr, body_cstr);
      return Err(string.str_concat("CURLOPT_POSTFIELDS failed: ", curl_error_string(rc_b)));
    };
    var body_bytes: Vec[UInt8] = encoding.utf8_encode(body);
    var rc_s: Int = unsafe { curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE(), make_long_value(body_bytes.len())) };
    if rc_s != 0 {
      cleanup_http_request(handle, header_list, url_cstr, body_cstr);
      return Err(string.str_concat("CURLOPT_POSTFIELDSIZE failed: ", curl_error_string(rc_s)));
    };
  };

  return perform_request_common(handle, header_list, url_cstr, body_cstr);
}

// --- Per-Call Options Entry (0.1.10) ----------------------------------------
//
// http_request_with_options is the additive form of http_request: identical
// wire behavior, but connect_ms / total_ms come from HttpRequestOptions
// (0 means the library default, 10000 / 30000 ms). Negative values are
// rejected as typed errors before any FFI call.
pub fn http_request_with_options(url: Str, method: Str, body: Str, headers: Str, opts: HttpRequestOptions) -> Result[HttpClientResponse, HttpOptionsRequestError]
  requires: string.str_len(url) > 0
  requires: string.str_len(method) > 0
{
  if !is_supported_method(method) {
    return Err(HttpOptionsRequestError.UnsupportedMethod(method));
  };
  var connect_ms: Int = opts.connect_ms;
  var total_ms: Int = opts.total_ms;
  var checked = options.validate_request_options(&opts);
  match checked {
    Err(HttpRequestOptionError.ConnectTimeoutNegative(_)) => {
      return Err(HttpOptionsRequestError.ConnectTimeoutNegative(connect_ms));
    },
    Err(HttpRequestOptionError.TotalTimeoutNegative(_)) => {
      return Err(HttpOptionsRequestError.TotalTimeoutNegative(total_ms));
    },
    Ok(_) => {
      match http_request_core(url, method, body, headers, opts) {
        Ok(resp) => { return Ok(resp); },
        Err(e) => { return Err(HttpOptionsRequestError.Transport(e)); },
      };
    },
  };
  return Err(HttpOptionsRequestError.Transport("unreachable"));
}

// --- Client Sessions (0.1.10) -----------------------------------------------
//
// A session is an explicit handle-lifetime object for keep-alive / connection
// reuse. The one-shot entries above keep their exact per-call
// init/cleanup behavior; only session_request* reuse the handle.
//
// Lifecycle (frozen):
//   - session_new()  -> allocates one easy handle (Err on failure).
//   - session_request(&session, ...) -> one transfer on that handle. The
//       handle is NOT cleaned up on success or failure; per-request resources
//       (header slist, C-string copies) are released after every call, and
//       request-specific options are reset so a POST cannot leak into a later
//       GET.
//   - session_close(session) -> curl_easy_cleanup exactly once. After that
//       the handle (and the borrower) must not be used.
// Connections to the same origin are reused automatically by libcurl within
// one handle; no separate pool is maintained by this library.
pub fn session_new() -> Result[HttpClientSession, Str] {
  var handle: *UInt8 = ptr_null();
  unsafe { handle = curl_easy_init(); }
  if ptr.is_null[UInt8](handle) {
    return Err("curl_easy_init returned null handle");
  };
  return Ok(HttpClientSession{ handle: handle });
}

pub fn session_close(session: HttpClientSession) {
  if !ptr.is_null[UInt8](session.handle) {
    unsafe { curl_easy_cleanup(session.handle); }
  };
}

fn session_request_core(session: &HttpClientSession, url: Str, method: Str, body: Str, headers: Str, opts: HttpRequestOptions) -> Result[HttpClientResponse, Str]
  requires: string.str_len(url) > 0
  requires: string.str_len(method) > 0
{
  if !is_supported_method(method) {
    return Err(string.str_concat("session_request: unsupported method ", method));
  };
  var has_body: Bool = method_has_body(method);
  var handle: *UInt8 = session.handle;
  if ptr.is_null[UInt8](handle) {
    return Err("session handle is closed");
  };

  var url_cstr: *UInt8 = str_to_cstr(url);
  if ptr.is_null[UInt8](url_cstr) {
    return Err("xiom_str_to_cstr failed for URL");
  };
  var header_list: *UInt8 = ptr_null();
  var body_cstr: *UInt8 = ptr_null();

  var reset = reset_request_state(handle);
  match reset {
    Err(e) => { cleanup_session_request(handle, header_list, url_cstr, body_cstr); return Err(e); },
    Ok(_) => {},
  };

  var setup = setup_common_options(handle, url_cstr, opts);
  match setup {
    Err(e) => { cleanup_session_request(handle, header_list, url_cstr, body_cstr); return Err(e); },
    Ok(_) => {},
  };

  var header_res = setup_request_headers(handle, headers);
  match header_res {
    Err(e) => { cleanup_session_request(handle, header_list, url_cstr, body_cstr); return Err(e); },
    Ok(list) => { header_list = list; },
  };

  var method_res = set_request_method(handle, method);
  match method_res {
    Err(e) => { cleanup_session_request(handle, header_list, url_cstr, body_cstr); return Err(e); },
    Ok(_) => {},
  };

  if has_body {
    body_cstr = str_to_cstr(body);
    if ptr.is_null[UInt8](body_cstr) {
      cleanup_session_request(handle, header_list, url_cstr, body_cstr);
      return Err("xiom_str_to_cstr failed for body");
    };
    var rc_b: Int = unsafe { curl_easy_setopt(handle, CURLOPT_POSTFIELDS(), body_cstr) };
    if rc_b != 0 {
      cleanup_session_request(handle, header_list, url_cstr, body_cstr);
      return Err(string.str_concat("CURLOPT_POSTFIELDS failed: ", curl_error_string(rc_b)));
    };
    var body_bytes: Vec[UInt8] = encoding.utf8_encode(body);
    var rc_s: Int = unsafe { curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE(), make_long_value(body_bytes.len())) };
    if rc_s != 0 {
      cleanup_session_request(handle, header_list, url_cstr, body_cstr);
      return Err(string.str_concat("CURLOPT_POSTFIELDSIZE failed: ", curl_error_string(rc_s)));
    };
  };

  var result = perform_and_capture(handle);
  cleanup_session_request(handle, header_list, url_cstr, body_cstr);
  return result;
}

pub fn session_request(session: &HttpClientSession, url: Str, method: Str, body: Str, headers: Str) -> Result[HttpClientResponse, Str]
  requires: string.str_len(url) > 0
  requires: string.str_len(method) > 0
{
  return session_request_core(session, url, method, body, headers, options.http_request_options_default());
}

pub fn session_request_with_options(session: &HttpClientSession, url: Str, method: Str, body: Str, headers: Str, opts: HttpRequestOptions) -> Result[HttpClientResponse, HttpOptionsRequestError]
  requires: string.str_len(url) > 0
  requires: string.str_len(method) > 0
{
  if !is_supported_method(method) {
    return Err(HttpOptionsRequestError.UnsupportedMethod(method));
  };
  var connect_ms: Int = opts.connect_ms;
  var total_ms: Int = opts.total_ms;
  var checked = options.validate_request_options(&opts);
  match checked {
    Err(HttpRequestOptionError.ConnectTimeoutNegative(_)) => {
      return Err(HttpOptionsRequestError.ConnectTimeoutNegative(connect_ms));
    },
    Err(HttpRequestOptionError.TotalTimeoutNegative(_)) => {
      return Err(HttpOptionsRequestError.TotalTimeoutNegative(total_ms));
    },
    Ok(_) => {
      match session_request_core(session, url, method, body, headers, opts) {
        Ok(resp) => { return Ok(resp); },
        Err(e) => { return Err(HttpOptionsRequestError.Transport(e)); },
      };
    },
  };
  return Err(HttpOptionsRequestError.Transport("unreachable"));
}

// --- Raw-Bytes Request Entry (0.1.9) ----------------------------------------
//
// http_request_bytes is the binary-safe companion of http_request. It takes
// the request body as a byte span (Vec[UInt8]) plus the caller-declared
// Content-Length, and transmits those bytes EXACTLY: the vector's data pointer
// goes to CURLOPT_POSTFIELDS with an explicit CURLOPT_POSTFIELDSIZE, so there
// is no UTF-8 re-encode, no cstr conversion, and no NUL truncation. A frame
// containing 0x00 and 0x80..0xFF reaches libcurl unchanged.
//
// Validation happens before any FFI call:
//   - the method must be one of GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS
//     (otherwise HttpBytesRequestError.UnsupportedMethod);
//   - content_length must be non-negative (BodyLengthNegative);
//   - content_length must equal body.len() (BodyLengthMismatch).
// Transport failures are reported as HttpBytesRequestError.Transport(text).
// Header bytes are the unchanged CRLF blob from http_headers_blob; callers set
// Content-Type / Content-Encoding themselves.
//
// The body is sent for POST/PUT/PATCH and ignored (but still length-checked)
// for the bodyless methods, matching http_request.
fn http_request_bytes_raw(url: Str, method: Str, body: Vec[UInt8], content_length: Int, headers: Str, opts: HttpRequestOptions) -> Result[HttpClientResponse, Str]
  requires: string.str_len(url) > 0
{
  var has_body: Bool = method_has_body(method);

  var url_cstr: *UInt8 = str_to_cstr(url);
  if ptr.is_null[UInt8](url_cstr) {
    return Err("xiom_str_to_cstr failed for URL");
  };

  var handle: *UInt8 = ptr_null();
  unsafe { handle = curl_easy_init(); }
  if ptr.is_null[UInt8](handle) {
    unsafe { xiom_free_cstr(url_cstr); }
    return Err("curl_easy_init returned null handle");
  };

  var header_list: *UInt8 = ptr_null();
  var no_body_cstr: *UInt8 = ptr_null();

  var setup = setup_common_options(handle, url_cstr, opts);
  match setup {
    Err(e) => { cleanup_http_request(handle, header_list, url_cstr, no_body_cstr); return Err(e); },
    Ok(_) => {},
  };

  var header_res = setup_request_headers(handle, headers);
  match header_res {
    Err(e) => { cleanup_http_request(handle, header_list, url_cstr, no_body_cstr); return Err(e); },
    Ok(list) => { header_list = list; },
  };

  var method_res = set_request_method(handle, method);
  match method_res {
    Err(e) => { cleanup_http_request(handle, header_list, url_cstr, no_body_cstr); return Err(e); },
    Ok(_) => {},
  };

  var body_bytes: Vec[UInt8] = body;
  if has_body {
    var body_ptr: *UInt8 = ptr_null();
    unsafe { body_ptr = body_bytes.as_mut_ptr(); }
    var rc_b: Int = unsafe { curl_easy_setopt(handle, CURLOPT_POSTFIELDS(), body_ptr) };
    if rc_b != 0 {
      cleanup_http_request(handle, header_list, url_cstr, no_body_cstr);
      return Err(string.str_concat("CURLOPT_POSTFIELDS failed: ", curl_error_string(rc_b)));
    };
    var rc_s: Int = unsafe { curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE(), make_long_value(content_length)) };
    if rc_s != 0 {
      cleanup_http_request(handle, header_list, url_cstr, no_body_cstr);
      return Err(string.str_concat("CURLOPT_POSTFIELDSIZE failed: ", curl_error_string(rc_s)));
    };
  };

  return perform_request_common(handle, header_list, url_cstr, no_body_cstr);
}

pub fn http_request_bytes(url: Str, method: Str, body: Vec[UInt8], content_length: Int, headers: Str) -> Result[HttpClientResponse, HttpBytesRequestError]
  requires: string.str_len(url) > 0
  requires: string.str_len(method) > 0
{
  if !is_supported_method(method) {
    return Err(HttpBytesRequestError.UnsupportedMethod(method));
  };
  var checked = http_bytes_body(body, content_length);
  match checked {
    Ok(request_body) => {
      match http_request_bytes_raw(url, method, request_body.bytes, request_body.content_length, headers, options.http_request_options_default()) {
        Ok(resp) => { return Ok(resp); },
        Err(e) => { return Err(HttpBytesRequestError.Transport(e)); },
      };
    },
    Err(e) => { return Err(bytes_request_body_error(e)); },
  };
  return Err(HttpBytesRequestError.Transport("unreachable"));
}

// http_request_bytes_with_options is the additive per-call-timeout form of
// http_request_bytes. Body/length validation happens first, then options
// validation; an invalid timeout is reported as
// HttpBytesRequestError.InvalidOptions (mapped from the typed option error).
pub fn http_request_bytes_with_options(url: Str, method: Str, body: Vec[UInt8], content_length: Int, headers: Str, opts: HttpRequestOptions) -> Result[HttpClientResponse, HttpBytesRequestError]
  requires: string.str_len(url) > 0
  requires: string.str_len(method) > 0
{
  if !is_supported_method(method) {
    return Err(HttpBytesRequestError.UnsupportedMethod(method));
  };
  var checked = http_bytes_body(body, content_length);
  match checked {
    Ok(request_body) => {
      var valid = options.validate_request_options(&opts);
      match valid {
        Err(HttpRequestOptionError.ConnectTimeoutNegative(_)) => {
          return Err(HttpBytesRequestError.InvalidConnectTimeout(opts.connect_ms));
        },
        Err(HttpRequestOptionError.TotalTimeoutNegative(_)) => {
          return Err(HttpBytesRequestError.InvalidTotalTimeout(opts.total_ms));
        },
        Ok(_) => {
          match http_request_bytes_raw(url, method, request_body.bytes, request_body.content_length, headers, opts) {
            Ok(resp) => { return Ok(resp); },
            Err(e) => { return Err(HttpBytesRequestError.Transport(e)); },
          };
        },
      };
    },
    Err(e) => { return Err(bytes_request_body_error(e)); },
  };
  return Err(HttpBytesRequestError.Transport("unreachable"));
}
