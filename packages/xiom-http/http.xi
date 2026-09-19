// XIOM -- HTTP Client Library (Production via libcurl + FFI Bridge)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.http

use xiom.ptr;
use xiom.string;
use xiom.encoding;

// --- XIOM FFI Bridge --------------------------------------------------------

extern "C" {
  fn xiom_str_to_cstr(xiom_str: *UInt8, len: Int) -> *UInt8;
  fn xiom_free_cstr(cstr: *UInt8);
  fn xiom_alloc(size: Int) -> *UInt8;
  fn xiom_free_ptr(ptr: *UInt8);
  fn xiom_write_byte(ptr: *UInt8, offset: Int, value: Int);
  fn xiom_read_byte(ptr: *UInt8, offset: Int) -> Int;
  fn xiom_copy_from_vec(c_buf: *UInt8, vec_data: *UInt8, vec_len: Int, vec_cap: Int, offset: Int, count: Int);
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
  fn fclose(file: *UInt8) -> Int;
  fn fread(buf: *UInt8, size: Int, count: Int, file: *UInt8) -> Int;
  fn fwrite(buf: *UInt8, size: Int, count: Int, file: *UInt8) -> Int;
  fn fseek(file: *UInt8, offset: Int, whence: Int) -> Int;
  fn ftell(file: *UInt8) -> Int;
  fn remove(path: *UInt8) -> Int;
}

// --- Types ------------------------------------------------------------------

pub type HttpClientResponse = {
  status: Int;
  body: Str;
  headers: Str;
} derive[Clone]

// --- CURL Option Constants --------------------------------------------------

fn CURLOPT_URL() -> Int { return 10002; }
fn CURLOPT_FOLLOWLOCATION() -> Int { return 52; }
fn CURLOPT_TIMEOUT() -> Int { return 13; }
fn CURLOPT_CONNECTTIMEOUT() -> Int { return 78; }
fn CURLOPT_POST() -> Int { return 47; }
fn CURLOPT_POSTFIELDS() -> Int { return 10015; }
fn CURLOPT_POSTFIELDSIZE() -> Int { return 60; }
fn CURLOPT_CUSTOMREQUEST() -> Int { return 10036; }
fn CURLOPT_HTTPHEADER() -> Int { return 10023; }
fn CURLOPT_SSL_VERIFYPEER() -> Int { return 64; }
fn CURLOPT_SSL_VERIFYHOST() -> Int { return 81; }
fn CURLOPT_USERAGENT() -> Int { return 10018; }
fn CURLOPT_WRITEDATA() -> Int { return 10001; }
fn CURLOPT_HEADERDATA() -> Int { return 10029; }
fn CURLOPT_NOSIGNAL() -> Int { return 99; }
fn CURLOPT_FAILONERROR() -> Int { return 45; }
fn CURLOPT_ACCEPT_ENCODING() -> Int { return 10102; }
fn CURLOPT_TCP_KEEPALIVE() -> Int { return 213; }
fn CURLOPT_TCP_KEEPIDLE() -> Int { return 214; }
fn CURLOPT_TCP_KEEPINTVL() -> Int { return 215; }
fn CURLOPT_BUFFERSIZE() -> Int { return 98; }

fn CURLINFO_RESPONSE_CODE() -> Int { return 2097154; }

// --- Internal Constants -----------------------------------------------------

fn SEEK_SET() -> Int { return 0; }
fn SEEK_END() -> Int { return 2; }
fn BUF_SIZE() -> Int { return 65536; }

fn TEMP_BODY() -> Str { return "__xiom_http_body.tmp"; }
fn TEMP_HEADERS() -> Str { return "__xiom_http_headers.tmp"; }

// --- Pointer-sized Value Helpers --------------------------------------------
// libcurl options take pointer-sized values. XIOM Int -> *UInt8 via xiom_alloc.

fn make_ptr_value(v: Int) -> *UInt8 {
  var p: *UInt8 = xiom_alloc(8);
  if ptr.is_null[UInt8](p) {
    return ptr.null[UInt8]();
  };
  xiom_write_byte(p, 0, v & 0xFF);
  xiom_write_byte(p, 1, (v >> 8) & 0xFF);
  xiom_write_byte(p, 2, (v >> 16) & 0xFF);
  xiom_write_byte(p, 3, (v >> 24) & 0xFF);
  xiom_write_byte(p, 4, 0);
  xiom_write_byte(p, 5, 0);
  xiom_write_byte(p, 6, 0);
  xiom_write_byte(p, 7, 0);
  return p;
}

fn ptr_null() -> *UInt8 { return ptr.null[UInt8](); }

// --- C String Helpers -------------------------------------------------------
// The XIOM runtime provides xiom_str_to_cstr. We pass the raw string pointer
// via the encoding module's utf8_encode, then to the FFI bridge.

fn str_to_cstr(s: Str) -> *UInt8 {
  var bytes: Vec[UInt8] = encoding.utf8_encode(s);
  var len: Int = bytes.len();
  if len == 0 {
    return xiom_str_to_cstr(ptr_null(), 0);
  };
  var cstr: *UInt8 = xiom_str_to_cstr(&bytes[0], len);
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

fn curl_error_string(code: Int) -> Str {
  var err_ptr: *UInt8 = curl_easy_strerror(code);
  if ptr.is_null[UInt8](err_ptr) {
    return "unknown curl error";
  };
  return cstr_to_str(err_ptr);
}

// --- C String -> XIOM Str ---------------------------------------------------

fn cstr_to_str(cstr: *UInt8) -> Str {
  var result: Str = "";
  var i: Int = 0;
  while i < 65536 {
    var b: Int = xiom_read_byte(cstr, i);
    if b == 0 as UInt8 { break; };
    var b_int: Int = b as Int;
    result = result + byte_to_char(b_int);
    i = i + 1;
  };
  return result;
}

fn byte_to_char(b: Int) -> Str {
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

fn char_to_str(c: Char) -> Str {
  return to_string(to_int_from_char(c));
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

  var body_c: *UInt8 = fopen(body_path, mode);
  if ptr.is_null[UInt8](body_c) {
    xiom_free_cstr(body_path);
    xiom_free_cstr(headers_path);
    xiom_free_cstr(mode);
    return Err("failed to open body temp file");
  };

  var headers_c: *UInt8 = fopen(headers_path, mode);
  if ptr.is_null[UInt8](headers_c) {
    xiom_free_cstr(body_path);
    xiom_free_cstr(headers_path);
    xiom_free_cstr(mode);
    return Err("failed to open headers temp file");
  };

  xiom_free_cstr(body_path);
  xiom_free_cstr(headers_path);
  xiom_free_cstr(mode);

  return Ok(TempFiles{ body: body_c, headers: headers_c });
}

fn close_temp_files(body_f: *UInt8, headers_f: *UInt8) {
  let _ = fclose(body_f);
  let _ = fclose(headers_f);
}

fn cleanup_temp_files() {
  var body_path: *UInt8 = str_to_cstr(TEMP_BODY());
  var headers_path: *UInt8 = str_to_cstr(TEMP_HEADERS());
  let _ = remove(body_path);
  let _ = remove(headers_path);
  xiom_free_cstr(body_path);
  xiom_free_cstr(headers_path);
}

// --- File I/O Helpers -------------------------------------------------------

fn read_file_to_str(file: *UInt8) -> Str {
  var file_size: Int;
  let _ = fseek(file, 0, SEEK_END());
  file_size = ftell(file);
  let _ = fseek(file, 0, SEEK_SET());

  if file_size <= 0 {
    return "";
  };

  var buf: *UInt8 = xiom_alloc(file_size + 1);
  if ptr.is_null[UInt8](buf) {
    return "";
  };

  var read_count: Int = fread(buf, 1, file_size, file);
  var term: Int = read_count;
  if term < 0 { term = 0; };
  if term > file_size { term = file_size; };

  if term >= 0 {
    xiom_write_byte(buf, term, 0);
  };
  var result: Str = cstr_to_str(buf);
  xiom_free_ptr(buf);
  return result;
}

// --- Response Code Extraction -----------------------------------------------

fn get_response_code(handle: *UInt8) -> Int {
  var status_buf: *UInt8 = xiom_alloc(8);
  if ptr.is_null[UInt8](status_buf) {
    return 0;
  };

  var rc: Int = curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE(), status_buf);
  if rc != 0 {
    xiom_free_ptr(status_buf);
    return 0;
  };

  var lo: Int = status_buf[0] as Int;
  var hi: Int = status_buf[1] as Int;
  var status: Int = lo | (hi << 8);
  xiom_free_ptr(status_buf);
  return status;
}

// --- cURL Setup Helpers -----------------------------------------------------

fn setup_common_options(handle: *UInt8, url_cstr: *UInt8) -> Result[Unit, Str] {
  var rc: Int;

  rc = curl_easy_setopt(handle, CURLOPT_URL(), url_cstr);
  if rc != 0 { return Err(string.str_concat("CURLOPT_URL failed: ", curl_error_string(rc))); };

  var p1: *UInt8 = make_ptr_value(1);
  rc = curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION(), p1);
  if rc != 0 { xiom_free_ptr(p1); return Err(string.str_concat("CURLOPT_FOLLOWLOCATION failed: ", curl_error_string(rc))); };
  xiom_free_ptr(p1);

  var p30: *UInt8 = make_ptr_value(30);
  rc = curl_easy_setopt(handle, CURLOPT_TIMEOUT(), p30);
  if rc != 0 { xiom_free_ptr(p30); return Err(string.str_concat("CURLOPT_TIMEOUT failed: ", curl_error_string(rc))); };
  xiom_free_ptr(p30);

  var p10: *UInt8 = make_ptr_value(10);
  rc = curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT(), p10);
  if rc != 0 { xiom_free_ptr(p10); return Err(string.str_concat("CURLOPT_CONNECTTIMEOUT failed: ", curl_error_string(rc))); };
  xiom_free_ptr(p10);

  rc = curl_easy_setopt(handle, CURLOPT_NOSIGNAL(), p1);
  if rc != 0 { xiom_free_ptr(p1); return Err(string.str_concat("CURLOPT_NOSIGNAL failed: ", curl_error_string(rc))); };
  xiom_free_ptr(p1);  // free our extra copy

  var encoding_cstr: *UInt8 = str_to_cstr("gzip, deflate");
  rc = curl_easy_setopt(handle, CURLOPT_ACCEPT_ENCODING(), encoding_cstr);
  xiom_free_cstr(encoding_cstr);
  if rc != 0 { return Err(string.str_concat("CURLOPT_ACCEPT_ENCODING failed: ", curl_error_string(rc))); };

  var ua_cstr: *UInt8 = str_to_cstr("xiom.http/0.1.0");
  rc = curl_easy_setopt(handle, CURLOPT_USERAGENT(), ua_cstr);
  xiom_free_cstr(ua_cstr);
  if rc != 0 { return Err(string.str_concat("CURLOPT_USERAGENT failed: ", curl_error_string(rc))); };

  var p_buf: *UInt8 = make_ptr_value(BUF_SIZE());
  rc = curl_easy_setopt(handle, CURLOPT_BUFFERSIZE(), p_buf);
  if rc != 0 { xiom_free_ptr(p_buf); return Err(string.str_concat("CURLOPT_BUFFERSIZE failed: ", curl_error_string(rc))); };
  xiom_free_ptr(p_buf);

  return Ok(());
}

fn perform_and_collect(handle: *UInt8, body_f: *UInt8, headers_f: *UInt8) -> Result[Unit, Str] {
  var rc: Int;
  rc = curl_easy_setopt(handle, CURLOPT_WRITEDATA(), body_f);
  if rc != 0 { return Err(string.str_concat("CURLOPT_WRITEDATA failed: ", curl_error_string(rc))); };
  rc = curl_easy_setopt(handle, CURLOPT_HEADERDATA(), headers_f);
  if rc != 0 { return Err(string.str_concat("CURLOPT_HEADERDATA failed: ", curl_error_string(rc))); };
  rc = curl_easy_perform(handle);
  if rc != 0 { return Err(string.str_concat("curl_easy_perform failed: ", curl_error_string(rc))); };
  return Ok(());
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

  var handle: *UInt8 = curl_easy_init();
  if ptr.is_null[UInt8](handle) {
    xiom_free_cstr(url_cstr);
    return Err("curl_easy_init returned null handle");
  };

  var setup = setup_common_options(handle, url_cstr);
  match setup {
    Err(e) => { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); return Err(e); },
    Ok(_) => {},
  };

  var files = open_temp_files();
  match files {
    Err(e) => { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); return Err(e); },
    Ok(fds) => {
      var perf = perform_and_collect(handle, fds.body, fds.headers);
      var status: Int = get_response_code(handle);
      var body: Str = read_file_to_str(fds.body);
      var headers: Str = read_file_to_str(fds.headers);
      close_temp_files(fds.body, fds.headers);
      cleanup_temp_files();
      curl_easy_cleanup(handle);
      xiom_free_cstr(url_cstr);
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

  var handle: *UInt8 = curl_easy_init();
  if ptr.is_null[UInt8](handle) { xiom_free_cstr(url_cstr); return Err("curl_easy_init returned null handle"); };

  var setup = setup_common_options(handle, url_cstr);
  match setup { Err(e) => { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); return Err(e); }, Ok(_) => {}, };

  var rc: Int;
  var p1: *UInt8 = make_ptr_value(1);
  rc = curl_easy_setopt(handle, CURLOPT_POST(), p1);
  xiom_free_ptr(p1);
  if rc != 0 { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); return Err(string.str_concat("CURLOPT_POST failed: ", curl_error_string(rc))); };

  var body_cstr: *UInt8 = str_to_cstr(body);
  if ptr.is_null[UInt8](body_cstr) { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); return Err("xiom_str_to_cstr failed for body"); };

  rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDS(), body_cstr);
  if rc != 0 { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); xiom_free_cstr(body_cstr); return Err(string.str_concat("CURLOPT_POSTFIELDS failed: ", curl_error_string(rc))); };

  var body_bytes: Vec[UInt8] = encoding.utf8_encode(body);
  var p_size: *UInt8 = make_ptr_value(body_bytes.len());
  rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE(), p_size);
  xiom_free_ptr(p_size);
  if rc != 0 { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); xiom_free_cstr(body_cstr); return Err(string.str_concat("CURLOPT_POSTFIELDSIZE failed: ", curl_error_string(rc))); };

  var files = open_temp_files();
  match files {
    Err(e) => { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); xiom_free_cstr(body_cstr); return Err(e); },
    Ok(fds) => {
      var perf = perform_and_collect(handle, fds.body, fds.headers);
      var status: Int = get_response_code(handle);
      var resp_body: Str = read_file_to_str(fds.body);
      var headers: Str = read_file_to_str(fds.headers);
      close_temp_files(fds.body, fds.headers);
      cleanup_temp_files();
      curl_easy_cleanup(handle);
      xiom_free_cstr(url_cstr);
      xiom_free_cstr(body_cstr);
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

  var handle: *UInt8 = curl_easy_init();
  if ptr.is_null[UInt8](handle) { xiom_free_cstr(url_cstr); return Err("curl_easy_init returned null handle"); };

  var setup = setup_common_options(handle, url_cstr);
  match setup { Err(e) => { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); return Err(e); }, Ok(_) => {}, };

  var rc: Int;
  var method_cstr: *UInt8 = str_to_cstr("PUT");
  rc = curl_easy_setopt(handle, CURLOPT_CUSTOMREQUEST(), method_cstr);
  xiom_free_cstr(method_cstr);
  if rc != 0 { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); return Err(string.str_concat("CURLOPT_CUSTOMREQUEST PUT failed: ", curl_error_string(rc))); };

  var body_cstr: *UInt8 = str_to_cstr(body);
  if ptr.is_null[UInt8](body_cstr) { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); return Err("xiom_str_to_cstr failed for body"); };

  rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDS(), body_cstr);
  if rc != 0 { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); xiom_free_cstr(body_cstr); return Err(string.str_concat("CURLOPT_POSTFIELDS PUT failed: ", curl_error_string(rc))); };

  var body_bytes: Vec[UInt8] = encoding.utf8_encode(body);
  var p_size: *UInt8 = make_ptr_value(body_bytes.len());
  rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE(), p_size);
  xiom_free_ptr(p_size);
  if rc != 0 { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); xiom_free_cstr(body_cstr); return Err(string.str_concat("CURLOPT_POSTFIELDSIZE PUT failed: ", curl_error_string(rc))); };

  var files = open_temp_files();
  match files {
    Err(e) => { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); xiom_free_cstr(body_cstr); return Err(e); },
    Ok(fds) => {
      var perf = perform_and_collect(handle, fds.body, fds.headers);
      var status: Int = get_response_code(handle);
      var resp_body: Str = read_file_to_str(fds.body);
      var headers: Str = read_file_to_str(fds.headers);
      close_temp_files(fds.body, fds.headers);
      cleanup_temp_files();
      curl_easy_cleanup(handle);
      xiom_free_cstr(url_cstr);
      xiom_free_cstr(body_cstr);
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

  var handle: *UInt8 = curl_easy_init();
  if ptr.is_null[UInt8](handle) { xiom_free_cstr(url_cstr); return Err("curl_easy_init returned null handle"); };

  var setup = setup_common_options(handle, url_cstr);
  match setup { Err(e) => { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); return Err(e); }, Ok(_) => {}, };

  var rc: Int;
  var method_cstr: *UInt8 = str_to_cstr("DELETE");
  rc = curl_easy_setopt(handle, CURLOPT_CUSTOMREQUEST(), method_cstr);
  xiom_free_cstr(method_cstr);
  if rc != 0 { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); return Err(string.str_concat("CURLOPT_CUSTOMREQUEST DELETE failed: ", curl_error_string(rc))); };

  var files = open_temp_files();
  match files {
    Err(e) => { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); return Err(e); },
    Ok(fds) => {
      var perf = perform_and_collect(handle, fds.body, fds.headers);
      var status: Int = get_response_code(handle);
      var resp_body: Str = read_file_to_str(fds.body);
      var headers: Str = read_file_to_str(fds.headers);
      close_temp_files(fds.body, fds.headers);
      cleanup_temp_files();
      curl_easy_cleanup(handle);
      xiom_free_cstr(url_cstr);
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

  var handle: *UInt8 = curl_easy_init();
  if ptr.is_null[UInt8](handle) { xiom_free_cstr(url_cstr); return Err("curl_easy_init returned null handle"); };

  var setup = setup_common_options(handle, url_cstr);
  match setup { Err(e) => { curl_easy_cleanup(handle); xiom_free_cstr(url_cstr); return Err(e); }, Ok(_) => {}, };

  var path_cstr: *UInt8 = str_to_cstr(path);
  var mode_cstr: *UInt8 = str_to_cstr("wb");
  var out_file: *UInt8 = fopen(path_cstr, mode_cstr);
  if ptr.is_null[UInt8](out_file) {
    curl_easy_cleanup(handle);
    xiom_free_cstr(url_cstr);
    xiom_free_cstr(path_cstr);
    xiom_free_cstr(mode_cstr);
    return Err(string.str_concat("failed to open output file: ", path));
  };

  var rc: Int = curl_easy_setopt(handle, CURLOPT_WRITEDATA(), out_file);
  if rc != 0 {
    let _ = fclose(out_file);
    curl_easy_cleanup(handle);
    xiom_free_cstr(url_cstr);
    xiom_free_cstr(path_cstr);
    xiom_free_cstr(mode_cstr);
    return Err(string.str_concat("CURLOPT_WRITEDATA download failed: ", curl_error_string(rc)));
  };

  var perf_rc: Int = curl_easy_perform(handle);
  let _ = fclose(out_file);

  if perf_rc != 0 {
    var err_msg: Str = curl_error_string(perf_rc);
    curl_easy_cleanup(handle);
    xiom_free_cstr(url_cstr);
    xiom_free_cstr(path_cstr);
    xiom_free_cstr(mode_cstr);
    let _ = remove(path_cstr);
    return Err(string.str_concat("download failed: ", err_msg));
  };

  var status: Int = get_response_code(handle);
  curl_easy_cleanup(handle);
  xiom_free_cstr(url_cstr);
  xiom_free_cstr(path_cstr);
  xiom_free_cstr(mode_cstr);

  if status < 200 || status >= 300 {
    let _ = remove(path_cstr);
    return Err(string.str_concat("download failed with HTTP status ", to_string(status)));
  };

  return Ok(());
}
