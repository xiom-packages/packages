// XIOM — HTTP Client Library (Production via libcurl + FFI Bridge)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.http

// ─── XIOM FFI Bridge ────────────────────────────────────────────────────────

extern "C" {
  fn xiom_str_to_cstr(xiom_str: *UInt8, len: Int) -> *UInt8
    ensures: result != nil;

  fn xiom_free_cstr(cstr: *UInt8)
    ensures: true;

  fn xiom_alloc(size: Int) -> *UInt8
    ensures: result != nil;

  fn xiom_free_ptr(ptr: *UInt8)
    ensures: true;

  fn xiom_copy_from_vec(c_buf: *UInt8, vec_data: *UInt8, vec_len: Int, vec_cap: Int, offset: Int, count: Int);
}

// ─── libcurl FFI ────────────────────────────────────────────────────────────

extern "C" {
  fn curl_easy_init() -> *UInt8;
  fn curl_easy_setopt(handle: *UInt8, option: Int, value: *UInt8) -> Int;
  fn curl_easy_perform(handle: *UInt8) -> Int;
  fn curl_easy_getinfo(handle: *UInt8, info: Int, arg: *UInt8) -> Int;
  fn curl_easy_cleanup(handle: *UInt8);
  fn curl_easy_strerror(code: Int) -> *UInt8;
}

// ─── libc FFI (file I/O) ────────────────────────────────────────────────────

extern "C" {
  fn fopen(path: *UInt8, mode: *UInt8) -> *UInt8;
  fn fclose(file: *UInt8) -> Int;
  fn fread(buf: *UInt8, size: Int, count: Int, file: *UInt8) -> Int;
  fn fwrite(buf: *UInt8, size: Int, count: Int, file: *UInt8) -> Int;
  fn fseek(file: *UInt8, offset: Int, whence: Int) -> Int;
  fn ftell(file: *UInt8) -> Int;
  fn remove(path: *UInt8) -> Int;
}

// ─── Types ──────────────────────────────────────────────────────────────────

pub type HttpResponse = {
  status: Int;
  body: Str;
  headers: Str;
} derive[Clone]

// ─── CURL Option Constants ──────────────────────────────────────────────────

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

// ─── Internal Constants ─────────────────────────────────────────────────────

fn SEEK_SET() -> Int { return 0; }
fn SEEK_END() -> Int { return 2; }
fn BUF_SIZE() -> Int { return 65536; }

fn TEMP_BODY() -> Str { return "__xiom_http_body.tmp"; }
fn TEMP_HEADERS() -> Str { return "__xiom_http_headers.tmp"; }

// ─── C String Helpers ───────────────────────────────────────────────────────
// Converts a XIOM Str to a null-terminated C string via the FFI bridge.
// Caller must free the result with xiom_free_cstr.

fn str_to_cstr(s: Str) -> *UInt8 {
  return xiom_str_to_cstr(s.c_str(), s.len());
}

fn str_to_cstr_or_err(s: Str, label: Str) -> Result[*UInt8, Str] {
  var c: *UInt8 = xiom_str_to_cstr(s.c_str(), s.len());
  if c == nil {
    return Err(label + ": xiom_str_to_cstr returned null");
  };
  return Ok(c);
}

// ─── Error Helpers ──────────────────────────────────────────────────────────

fn curl_error_string(code: Int) -> Str {
  var err_ptr: *UInt8 = curl_easy_strerror(code);
  if err_ptr == nil {
    return "unknown curl error";
  };
  return Str.from_c_str(err_ptr);
}

// ─── Temp File Management ───────────────────────────────────────────────────

fn open_temp_files() -> Result[{ body: *UInt8; headers: *UInt8; }, Str] {
  var body_c: *UInt8;
  var headers_c: *UInt8;
  var body_path: *UInt8;
  var headers_path: *UInt8;
  var mode: *UInt8;

  body_path = str_to_cstr(TEMP_BODY());
  headers_path = str_to_cstr(TEMP_HEADERS());
  mode = str_to_cstr("wb+");

  body_c = fopen(body_path, mode);
  if body_c == nil {
    xiom_free_cstr(body_path);
    xiom_free_cstr(headers_path);
    xiom_free_cstr(mode);
    return Err("failed to open body temp file");
  };

  headers_c = fopen(headers_path, mode);
  if headers_c == nil {
    let _ = fclose(body_c);
    xiom_free_cstr(body_path);
    xiom_free_cstr(headers_path);
    xiom_free_cstr(mode);
    return Err("failed to open headers temp file");
  };

  xiom_free_cstr(body_path);
  xiom_free_cstr(headers_path);
  xiom_free_cstr(mode);

  return Ok({ body: body_c; headers: headers_c; });
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

// ─── File I/O Helpers ───────────────────────────────────────────────────────
// Reads file contents into a Str via xiom_alloc bridge buffer.

fn read_file_to_str(file: *UInt8) -> Str {
  var file_size: Int;
  let _ = fseek(file, 0, SEEK_END());
  file_size = ftell(file);
  let _ = fseek(file, 0, SEEK_SET());

  if file_size <= 0 {
    return "";
  };

  var buf: *UInt8 = xiom_alloc(file_size + 1);
  if buf == nil {
    return "";
  };

  let read_count: Int = fread(buf, 1, file_size, file);
  var termination_offset: Int = read_count;
  if termination_offset < 0 { termination_offset = 0; };
  if termination_offset > file_size { termination_offset = file_size; };

  // null-terminate in-place for Str.from_c_str
  unsafe {
    buf[termination_offset] = 0 as UInt8;
  };
  var result: Str = Str.from_c_str(buf);
  xiom_free_ptr(buf);
  return result;
}

// ─── Response Code Extraction ───────────────────────────────────────────────

fn get_response_code(handle: *UInt8) -> Int {
  var status_buf: *UInt8 = xiom_alloc(8);
  if status_buf == nil {
    return 0;
  };

  var rc: Int = curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE(), status_buf);
  if rc != 0 {
    xiom_free_ptr(status_buf);
    return 0;
  };

  var p: *Int = status_buf as *Int;
  var status: Int = *p;
  xiom_free_ptr(status_buf);
  return status;
}

// ─── cURL Setup Helpers ─────────────────────────────────────────────────────

fn setup_common_options(handle: *UInt8, url_cstr: *UInt8) -> Result[Unit, Str] {
  var rc: Int;

  rc = curl_easy_setopt(handle, CURLOPT_URL(), url_cstr);
  if rc != 0 {
    return Err("CURLOPT_URL failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION(), 1 as *UInt8);
  if rc != 0 {
    return Err("CURLOPT_FOLLOWLOCATION failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_TIMEOUT(), 30 as *UInt8);
  if rc != 0 {
    return Err("CURLOPT_TIMEOUT failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT(), 10 as *UInt8);
  if rc != 0 {
    return Err("CURLOPT_CONNECTTIMEOUT failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_NOSIGNAL(), 1 as *UInt8);
  if rc != 0 {
    return Err("CURLOPT_NOSIGNAL failed: " + curl_error_string(rc));
  };

  var encoding_cstr: *UInt8 = str_to_cstr("gzip, deflate");
  rc = curl_easy_setopt(handle, CURLOPT_ACCEPT_ENCODING(), encoding_cstr);
  xiom_free_cstr(encoding_cstr);
  if rc != 0 {
    return Err("CURLOPT_ACCEPT_ENCODING failed: " + curl_error_string(rc));
  };

  var ua_cstr: *UInt8 = str_to_cstr("xiom-http/0.1.0");
  rc = curl_easy_setopt(handle, CURLOPT_USERAGENT(), ua_cstr);
  xiom_free_cstr(ua_cstr);
  if rc != 0 {
    return Err("CURLOPT_USERAGENT failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_BUFFERSIZE(), BUF_SIZE() as *UInt8);
  if rc != 0 {
    return Err("CURLOPT_BUFFERSIZE failed: " + curl_error_string(rc));
  };

  return Ok(Unit);
}

fn perform_and_collect(handle: *UInt8, body_f: *UInt8, headers_f: *UInt8) -> Result[Unit, Str] {
  var rc: Int;

  rc = curl_easy_setopt(handle, CURLOPT_WRITEDATA(), body_f);
  if rc != 0 {
    return Err("CURLOPT_WRITEDATA failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_HEADERDATA(), headers_f);
  if rc != 0 {
    return Err("CURLOPT_HEADERDATA failed: " + curl_error_string(rc));
  };

  rc = curl_easy_perform(handle);
  if rc != 0 {
    return Err("curl_easy_perform failed: " + curl_error_string(rc));
  };

  return Ok(Unit);
}

// ─── Public HTTP API ────────────────────────────────────────────────────────

pub fn http_get(url: Str) -> Result[HttpResponse, Str]
  requires: url.len() > 0
{
  var url_cstr: *UInt8 = str_to_cstr(url);
  if url_cstr == nil {
    return Err("xiom_str_to_cstr failed for URL");
  };

  var handle: *UInt8 = curl_easy_init();
  if handle == nil {
    xiom_free_cstr(url_cstr);
    return Err("curl_easy_init returned null handle");
  };

  var setup = setup_common_options(handle, url_cstr);
  match setup {
    Err(e) => {
      curl_easy_cleanup(handle);
      xiom_free_cstr(url_cstr);
      return Err(e);
    };
    Ok(_) => {};
  };

  var files = open_temp_files();
  match files {
    Err(e) => {
      curl_easy_cleanup(handle);
      xiom_free_cstr(url_cstr);
      return Err(e);
    };
    Ok(fds) => {
      var perf = perform_and_collect(handle, fds.body, fds.headers);
      var status: Int = get_response_code(handle);
      var body: Str = read_file_to_str(fds.body);
      var headers: Str = read_file_to_str(fds.headers);

      close_temp_files(fds.body, fds.headers);
      cleanup_temp_files();
      curl_easy_cleanup(handle);
      xiom_free_cstr(url_cstr);

      match perf {
        Err(e) => { return Err(e); };
        Ok(_) => {};
      };

      return Ok(HttpResponse{
        status: status,
        body: body,
        headers: headers,
      });
    };
  };
}

pub fn http_post(url: Str, body: Str, content_type: Str) -> Result[HttpResponse, Str]
  requires: url.len() > 0
{
  var url_cstr: *UInt8 = str_to_cstr(url);
  if url_cstr == nil {
    return Err("xiom_str_to_cstr failed for URL");
  };

  var handle: *UInt8 = curl_easy_init();
  if handle == nil {
    xiom_free_cstr(url_cstr);
    return Err("curl_easy_init returned null handle");
  };

  var setup = setup_common_options(handle, url_cstr);
  match setup {
    Err(e) => {
      curl_easy_cleanup(handle);
      xiom_free_cstr(url_cstr);
      return Err(e);
    };
    Ok(_) => {};
  };

  var rc: Int;
  rc = curl_easy_setopt(handle, CURLOPT_POST(), 1 as *UInt8);
  if rc != 0 {
    curl_easy_cleanup(handle);
    xiom_free_cstr(url_cstr);
    return Err("CURLOPT_POST failed: " + curl_error_string(rc));
  };

  var body_cstr: *UInt8 = str_to_cstr(body);
  if body_cstr == nil {
    curl_easy_cleanup(handle);
    xiom_free_cstr(url_cstr);
    return Err("xiom_str_to_cstr failed for body");
  };

  rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDS(), body_cstr);
  if rc != 0 {
    curl_easy_cleanup(handle);
    xiom_free_cstr(url_cstr);
    xiom_free_cstr(body_cstr);
    return Err("CURLOPT_POSTFIELDS failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE(), body.len() as *UInt8);
  if rc != 0 {
    curl_easy_cleanup(handle);
    xiom_free_cstr(url_cstr);
    xiom_free_cstr(body_cstr);
    return Err("CURLOPT_POSTFIELDSIZE failed: " + curl_error_string(rc));
  };

  // LIMITATION: CURLOPT_HTTPHEADER requires curl_slist_append which is not
  // yet wired in the XIOM FFI. When available, build a curl_slist* for
  // Content-Type and set via curl_easy_setopt(handle, CURLOPT_HTTPHEADER, ...).
  // Currently libcurl will use its default Content-Type for POST bodies.

  var files = open_temp_files();
  match files {
    Err(e) => {
      curl_easy_cleanup(handle);
      xiom_free_cstr(url_cstr);
      xiom_free_cstr(body_cstr);
      return Err(e);
    };
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

      match perf {
        Err(e) => { return Err(e); };
        Ok(_) => {};
      };

      return Ok(HttpResponse{
        status: status,
        body: resp_body,
        headers: headers,
      });
    };
  };
}

pub fn http_put(url: Str, body: Str) -> Result[HttpResponse, Str]
  requires: url.len() > 0
{
  var url_cstr: *UInt8 = str_to_cstr(url);
  if url_cstr == nil {
    return Err("xiom_str_to_cstr failed for URL");
  };

  var handle: *UInt8 = curl_easy_init();
  if handle == nil {
    xiom_free_cstr(url_cstr);
    return Err("curl_easy_init returned null handle");
  };

  var setup = setup_common_options(handle, url_cstr);
  match setup {
    Err(e) => {
      curl_easy_cleanup(handle);
      xiom_free_cstr(url_cstr);
      return Err(e);
    };
    Ok(_) => {};
  };

  var rc: Int;
  var method_cstr: *UInt8 = str_to_cstr("PUT");
  rc = curl_easy_setopt(handle, CURLOPT_CUSTOMREQUEST(), method_cstr);
  if rc != 0 {
    curl_easy_cleanup(handle);
    xiom_free_cstr(url_cstr);
    xiom_free_cstr(method_cstr);
    return Err("CURLOPT_CUSTOMREQUEST PUT failed: " + curl_error_string(rc));
  };
  xiom_free_cstr(method_cstr);

  var body_cstr: *UInt8 = str_to_cstr(body);
  if body_cstr == nil {
    curl_easy_cleanup(handle);
    xiom_free_cstr(url_cstr);
    return Err("xiom_str_to_cstr failed for body");
  };

  rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDS(), body_cstr);
  if rc != 0 {
    curl_easy_cleanup(handle);
    xiom_free_cstr(url_cstr);
    xiom_free_cstr(body_cstr);
    return Err("CURLOPT_POSTFIELDS PUT failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE(), body.len() as *UInt8);
  if rc != 0 {
    curl_easy_cleanup(handle);
    xiom_free_cstr(url_cstr);
    xiom_free_cstr(body_cstr);
    return Err("CURLOPT_POSTFIELDSIZE PUT failed: " + curl_error_string(rc));
  };

  var files = open_temp_files();
  match files {
    Err(e) => {
      curl_easy_cleanup(handle);
      xiom_free_cstr(url_cstr);
      xiom_free_cstr(body_cstr);
      return Err(e);
    };
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

      match perf {
        Err(e) => { return Err(e); };
        Ok(_) => {};
      };

      return Ok(HttpResponse{
        status: status,
        body: resp_body,
        headers: headers,
      });
    };
  };
}

pub fn http_delete(url: Str) -> Result[HttpResponse, Str]
  requires: url.len() > 0
{
  var url_cstr: *UInt8 = str_to_cstr(url);
  if url_cstr == nil {
    return Err("xiom_str_to_cstr failed for URL");
  };

  var handle: *UInt8 = curl_easy_init();
  if handle == nil {
    xiom_free_cstr(url_cstr);
    return Err("curl_easy_init returned null handle");
  };

  var setup = setup_common_options(handle, url_cstr);
  match setup {
    Err(e) => {
      curl_easy_cleanup(handle);
      xiom_free_cstr(url_cstr);
      return Err(e);
    };
    Ok(_) => {};
  };

  var rc: Int;
  var method_cstr: *UInt8 = str_to_cstr("DELETE");
  rc = curl_easy_setopt(handle, CURLOPT_CUSTOMREQUEST(), method_cstr);
  if rc != 0 {
    curl_easy_cleanup(handle);
    xiom_free_cstr(url_cstr);
    xiom_free_cstr(method_cstr);
    return Err("CURLOPT_CUSTOMREQUEST DELETE failed: " + curl_error_string(rc));
  };
  xiom_free_cstr(method_cstr);

  var files = open_temp_files();
  match files {
    Err(e) => {
      curl_easy_cleanup(handle);
      xiom_free_cstr(url_cstr);
      return Err(e);
    };
    Ok(fds) => {
      var perf = perform_and_collect(handle, fds.body, fds.headers);
      var status: Int = get_response_code(handle);
      var resp_body: Str = read_file_to_str(fds.body);
      var headers: Str = read_file_to_str(fds.headers);

      close_temp_files(fds.body, fds.headers);
      cleanup_temp_files();
      curl_easy_cleanup(handle);
      xiom_free_cstr(url_cstr);

      match perf {
        Err(e) => { return Err(e); };
        Ok(_) => {};
      };

      return Ok(HttpResponse{
        status: status,
        body: resp_body,
        headers: headers,
      });
    };
  };
}

pub fn http_download(url: Str, path: Str) -> Result[Unit, Str]
  requires: url.len() > 0
  requires: path.len() > 0
{
  var url_cstr: *UInt8 = str_to_cstr(url);
  if url_cstr == nil {
    return Err("xiom_str_to_cstr failed for URL");
  };

  var handle: *UInt8 = curl_easy_init();
  if handle == nil {
    xiom_free_cstr(url_cstr);
    return Err("curl_easy_init returned null handle");
  };

  var setup = setup_common_options(handle, url_cstr);
  match setup {
    Err(e) => {
      curl_easy_cleanup(handle);
      xiom_free_cstr(url_cstr);
      return Err(e);
    };
    Ok(_) => {};
  };

  var path_cstr: *UInt8 = str_to_cstr(path);
  var mode_cstr: *UInt8 = str_to_cstr("wb");
  var out_file: *UInt8 = fopen(path_cstr, mode_cstr);
  if out_file == nil {
    curl_easy_cleanup(handle);
    xiom_free_cstr(url_cstr);
    xiom_free_cstr(path_cstr);
    xiom_free_cstr(mode_cstr);
    return Err("failed to open output file: " + path);
  };

  var rc: Int = curl_easy_setopt(handle, CURLOPT_WRITEDATA(), out_file);
  if rc != 0 {
    let _ = fclose(out_file);
    curl_easy_cleanup(handle);
    xiom_free_cstr(url_cstr);
    xiom_free_cstr(path_cstr);
    xiom_free_cstr(mode_cstr);
    return Err("CURLOPT_WRITEDATA download failed: " + curl_error_string(rc));
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
    return Err("download failed: " + err_msg);
  };

  var status: Int = get_response_code(handle);
  curl_easy_cleanup(handle);
  xiom_free_cstr(url_cstr);
  xiom_free_cstr(path_cstr);
  xiom_free_cstr(mode_cstr);

  if status < 200 || status >= 300 {
    let _ = remove(path_cstr);
    return Err("download failed with HTTP status " + int_to_str(status));
  };

  return Ok(Unit);
}

// ─── Utility ────────────────────────────────────────────────────────────────

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; };
  var digits: Vec[Str] = Vec[Str].new();
  var num: Int = n;
  var is_neg: Bool = false;
  if num < 0 {
    is_neg = true;
    num = -num;
  };
  while num > 0 {
    var d: Int = num % 10;
    num = num / 10;
    if d == 0 { digits.push("0"); }
    elif d == 1 { digits.push("1"); }
    elif d == 2 { digits.push("2"); }
    elif d == 3 { digits.push("3"); }
    elif d == 4 { digits.push("4"); }
    elif d == 5 { digits.push("5"); }
    elif d == 6 { digits.push("6"); }
    elif d == 7 { digits.push("7"); }
    elif d == 8 { digits.push("8"); }
    elif d == 9 { digits.push("9"); };
  };
  var result: Str = "";
  if is_neg { result = "-"; };
  var j: Int = digits.len() - 1;
  while j >= 0 {
    result = result + digits[j];
    j = j - 1;
  };
  return result;
}
