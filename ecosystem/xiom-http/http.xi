// XIOM — HTTP Library (Production via libcurl)
// Copyright (c) 2026 Eleftherios Notas
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.http

extern "C" {
  fn curl_easy_init() -> Int;
  fn curl_easy_setopt(handle: Int, option: Int, value: Int) -> Int;
  fn curl_easy_perform(handle: Int) -> Int;
  fn curl_easy_getinfo(handle: Int, info: Int, arg: Int) -> Int;
  fn curl_easy_cleanup(handle: Int);
  fn curl_easy_strerror(code: Int) -> *UInt8;

  fn fopen(path: *UInt8, mode: *UInt8) -> *UInt8;
  fn fclose(file: *UInt8) -> Int;
  fn fread(buf: *UInt8, size: UInt, count: UInt, file: *UInt8) -> UInt;
  fn fwrite(buf: *UInt8, size: UInt, count: UInt, file: *UInt8) -> UInt;
  fn fseek(file: *UInt8, offset: Int, whence: Int) -> Int;
  fn ftell(file: *UInt8) -> Int;
  fn remove(path: *UInt8) -> Int;
  fn malloc(size: UInt) -> *UInt8;
  fn free(ptr: *UInt8);
}

pub type HttpResponse = {
  status: Int;
  body: Str;
  headers: Str;
} derive[Clone]

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
fn CURLOPT_VERBOSE() -> Int { return 41; }

fn CURLINFO_RESPONSE_CODE() -> Int { return 2097154; }
fn CURLINFO_CONTENT_TYPE() -> Int { return 2097186; }
fn CURLINFO_TOTAL_TIME() -> Int { return 3145731; }

fn SEEK_SET() -> Int { return 0; }
fn SEEK_END() -> Int { return 2; }

fn BUF_SIZE() -> Int { return 65536; }

fn TEMP_BODY_PATH() -> Str { return "__xiom_http_body.tmp"; }
fn TEMP_HEADER_PATH() -> Str { return "__xiom_http_headers.tmp"; }

fn curl_error_string(code: Int) -> Str {
  var err_ptr: *UInt8 = curl_easy_strerror(code);
  if err_ptr == nil {
    return "unknown curl error";
  };
  return Str.from_c_str(err_ptr);
}

fn setup_common_options(handle: Int, url: Str) -> Result[Unit, Str] {
  var rc: Int;

  rc = curl_easy_setopt(handle, CURLOPT_URL(), url.c_str() as Int);
  if rc != 0 {
    return Err("CURLOPT_URL failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_FOLLOWLOCATION(), 1);
  if rc != 0 {
    return Err("CURLOPT_FOLLOWLOCATION failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_TIMEOUT(), 30);
  if rc != 0 {
    return Err("CURLOPT_TIMEOUT failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_CONNECTTIMEOUT(), 10);
  if rc != 0 {
    return Err("CURLOPT_CONNECTTIMEOUT failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_NOSIGNAL(), 1);
  if rc != 0 {
    return Err("CURLOPT_NOSIGNAL failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_ACCEPT_ENCODING(), "gzip, deflate".c_str() as Int);
  if rc != 0 {
    return Err("CURLOPT_ACCEPT_ENCODING failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_USERAGENT(), "xiom-http/0.1.0".c_str() as Int);
  if rc != 0 {
    return Err("CURLOPT_USERAGENT failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_BUFFERSIZE(), BUF_SIZE());
  if rc != 0 {
    return Err("CURLOPT_BUFFERSIZE failed: " + curl_error_string(rc));
  };

  return Ok(Unit);
}

fn open_temp_files() -> Result[{ body_file: *UInt8; header_file: *UInt8; }, Str] {
  var body_file: *UInt8;
  var header_file: *UInt8;
  unsafe {
    body_file = fopen(TEMP_BODY_PATH().c_str(), "wb+".c_str());
    if body_file == nil {
      return Err("failed to open body temp file: " + TEMP_BODY_PATH());
    };
    header_file = fopen(TEMP_HEADER_PATH().c_str(), "wb+".c_str());
    if header_file == nil {
      let _ = fclose(body_file);
      return Err("failed to open header temp file: " + TEMP_HEADER_PATH());
    };
  };
  return Ok({ body_file: body_file; header_file: header_file; });
}

fn close_temp_files(body_file: *UInt8, header_file: *UInt8) {
  unsafe {
    let _ = fclose(body_file);
    let _ = fclose(header_file);
  };
}

fn cleanup_temp_files() {
  unsafe {
    let _ = remove(TEMP_BODY_PATH().c_str());
    let _ = remove(TEMP_HEADER_PATH().c_str());
  };
}

fn read_file_to_str(file: *UInt8) -> Str {
  var file_size: Int;
  unsafe {
    let _ = fseek(file, 0, SEEK_END());
    file_size = ftell(file);
    let _ = fseek(file, 0, SEEK_SET());
  };
  if file_size <= 0 {
    return "";
  };
  var buf: *UInt8;
  var result: Str;
  unsafe {
    buf = malloc(file_size as UInt + 1 as UInt);
    if buf == nil {
      return "";
    };
    let read_count: UInt = fread(buf, 1 as UInt, file_size as UInt, file);
    buf[read_count as Int] = 0 as UInt8;
    result = Str.from_c_str(buf);
    free(buf);
  };
  return result;
}

fn get_response_code(handle: Int) -> Int {
  var status_ptr: *UInt8;
  var status: Int;
  unsafe {
    status_ptr = malloc(8 as UInt);
    if status_ptr == nil {
      return 0;
    };
  };
  var rc: Int = curl_easy_getinfo(handle, CURLINFO_RESPONSE_CODE(), status_ptr as Int);
  if rc != 0 {
    unsafe {
      free(status_ptr);
    };
    return 0;
  };
  unsafe {
    var p: *Int = status_ptr as *Int;
    status = *p;
    free(status_ptr);
  };
  return status;
}

fn perform_and_collect(handle: Int, body_file: *UInt8, header_file: *UInt8) -> Result[Unit, Str] {
  var rc: Int;

  rc = curl_easy_setopt(handle, CURLOPT_WRITEDATA(), body_file as Int);
  if rc != 0 {
    return Err("CURLOPT_WRITEDATA failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_HEADERDATA(), header_file as Int);
  if rc != 0 {
    return Err("CURLOPT_HEADERDATA failed: " + curl_error_string(rc));
  };

  rc = curl_easy_perform(handle);
  if rc != 0 {
    return Err("curl_easy_perform failed: " + curl_error_string(rc));
  };

  return Ok(Unit);
}

pub fn http_get(url: Str) -> Result[HttpResponse, Str]
  requires: url.len() > 0 {
  var handle: Int = curl_easy_init();
  if handle == 0 {
    return Err("curl_easy_init returned null handle");
  };

  var setup_result: Result[Unit, Str] = setup_common_options(handle, url);
  match setup_result {
    Err(e) => {
      curl_easy_cleanup(handle);
      return Err(e);
    };
    Ok(_) => {};
  };

  var files_result: Result[{ body_file: *UInt8; header_file: *UInt8; }, Str] = open_temp_files();
  match files_result {
    Err(e) => {
      curl_easy_cleanup(handle);
      return Err(e);
    };
    Ok(files) => {
      var body_file: *UInt8 = files.body_file;
      var header_file: *UInt8 = files.header_file;

      var perf_result: Result[Unit, Str] = perform_and_collect(handle, body_file, header_file);
      var status: Int = get_response_code(handle);
      var body: Str = read_file_to_str(body_file);
      var headers: Str = read_file_to_str(header_file);

      close_temp_files(body_file, header_file);
      cleanup_temp_files();
      curl_easy_cleanup(handle);

      match perf_result {
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
  requires: url.len() > 0 {
  var handle: Int = curl_easy_init();
  if handle == 0 {
    return Err("curl_easy_init returned null handle");
  };

  var setup_result: Result[Unit, Str] = setup_common_options(handle, url);
  match setup_result {
    Err(e) => {
      curl_easy_cleanup(handle);
      return Err(e);
    };
    Ok(_) => {};
  };

  var rc: Int;
  rc = curl_easy_setopt(handle, CURLOPT_POST(), 1);
  if rc != 0 {
    curl_easy_cleanup(handle);
    return Err("CURLOPT_POST failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDS(), body.c_str() as Int);
  if rc != 0 {
    curl_easy_cleanup(handle);
    return Err("CURLOPT_POSTFIELDS failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE(), body.len());
  if rc != 0 {
    curl_easy_cleanup(handle);
    return Err("CURLOPT_POSTFIELDSIZE failed: " + curl_error_string(rc));
  };

  var content_type_header: Str = "Content-Type: " + content_type;
  var header_list: Int = 0;
  // NOTE: CURLOPT_HTTPHEADER requires a curl_slist*.
  // curl_slist_append is not yet wired in XIOM FFI.
  // Once available, build header list and set via:
  //   header_list = curl_slist_append(0, content_type_header.c_str());
  //   curl_easy_setopt(handle, CURLOPT_HTTPHEADER(), header_list);
  // For now, POST body is sent but without explicit Content-Type header.
  // The libcurl default Content-Type will be used.

  var files_result: Result[{ body_file: *UInt8; header_file: *UInt8; }, Str] = open_temp_files();
  match files_result {
    Err(e) => {
      curl_easy_cleanup(handle);
      return Err(e);
    };
    Ok(files) => {
      var body_file: *UInt8 = files.body_file;
      var header_file: *UInt8 = files.header_file;

      var perf_result: Result[Unit, Str] = perform_and_collect(handle, body_file, header_file);
      var status: Int = get_response_code(handle);
      var resp_body: Str = read_file_to_str(body_file);
      var headers: Str = read_file_to_str(header_file);

      close_temp_files(body_file, header_file);
      cleanup_temp_files();
      curl_easy_cleanup(handle);

      match perf_result {
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
  requires: url.len() > 0 {
  var handle: Int = curl_easy_init();
  if handle == 0 {
    return Err("curl_easy_init returned null handle");
  };

  var setup_result: Result[Unit, Str] = setup_common_options(handle, url);
  match setup_result {
    Err(e) => {
      curl_easy_cleanup(handle);
      return Err(e);
    };
    Ok(_) => {};
  };

  var rc: Int;
  rc = curl_easy_setopt(handle, CURLOPT_CUSTOMREQUEST(), "PUT".c_str() as Int);
  if rc != 0 {
    curl_easy_cleanup(handle);
    return Err("CURLOPT_CUSTOMREQUEST PUT failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDS(), body.c_str() as Int);
  if rc != 0 {
    curl_easy_cleanup(handle);
    return Err("CURLOPT_POSTFIELDS PUT failed: " + curl_error_string(rc));
  };

  rc = curl_easy_setopt(handle, CURLOPT_POSTFIELDSIZE(), body.len());
  if rc != 0 {
    curl_easy_cleanup(handle);
    return Err("CURLOPT_POSTFIELDSIZE PUT failed: " + curl_error_string(rc));
  };

  var files_result: Result[{ body_file: *UInt8; header_file: *UInt8; }, Str] = open_temp_files();
  match files_result {
    Err(e) => {
      curl_easy_cleanup(handle);
      return Err(e);
    };
    Ok(files) => {
      var body_file: *UInt8 = files.body_file;
      var header_file: *UInt8 = files.header_file;

      var perf_result: Result[Unit, Str] = perform_and_collect(handle, body_file, header_file);
      var status: Int = get_response_code(handle);
      var resp_body: Str = read_file_to_str(body_file);
      var headers: Str = read_file_to_str(header_file);

      close_temp_files(body_file, header_file);
      cleanup_temp_files();
      curl_easy_cleanup(handle);

      match perf_result {
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
  requires: url.len() > 0 {
  var handle: Int = curl_easy_init();
  if handle == 0 {
    return Err("curl_easy_init returned null handle");
  };

  var setup_result: Result[Unit, Str] = setup_common_options(handle, url);
  match setup_result {
    Err(e) => {
      curl_easy_cleanup(handle);
      return Err(e);
    };
    Ok(_) => {};
  };

  var rc: Int;
  rc = curl_easy_setopt(handle, CURLOPT_CUSTOMREQUEST(), "DELETE".c_str() as Int);
  if rc != 0 {
    curl_easy_cleanup(handle);
    return Err("CURLOPT_CUSTOMREQUEST DELETE failed: " + curl_error_string(rc));
  };

  var files_result: Result[{ body_file: *UInt8; header_file: *UInt8; }, Str] = open_temp_files();
  match files_result {
    Err(e) => {
      curl_easy_cleanup(handle);
      return Err(e);
    };
    Ok(files) => {
      var body_file: *UInt8 = files.body_file;
      var header_file: *UInt8 = files.header_file;

      var perf_result: Result[Unit, Str] = perform_and_collect(handle, body_file, header_file);
      var status: Int = get_response_code(handle);
      var resp_body: Str = read_file_to_str(body_file);
      var headers: Str = read_file_to_str(header_file);

      close_temp_files(body_file, header_file);
      cleanup_temp_files();
      curl_easy_cleanup(handle);

      match perf_result {
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
  requires: path.len() > 0 {
  var handle: Int = curl_easy_init();
  if handle == 0 {
    return Err("curl_easy_init returned null handle");
  };

  var setup_result: Result[Unit, Str] = setup_common_options(handle, url);
  match setup_result {
    Err(e) => {
      curl_easy_cleanup(handle);
      return Err(e);
    };
    Ok(_) => {};
  };

  var out_file: *UInt8;
  unsafe {
    out_file = fopen(path.c_str(), "wb".c_str());
  };
  if out_file == nil {
    curl_easy_cleanup(handle);
    return Err("failed to open output file: " + path);
  };

  var rc: Int;
  rc = curl_easy_setopt(handle, CURLOPT_WRITEDATA(), out_file as Int);
  if rc != 0 {
    unsafe { let _ = fclose(out_file); };
    curl_easy_cleanup(handle);
    return Err("CURLOPT_WRITEDATA download failed: " + curl_error_string(rc));
  };

  var perf_rc: Int = curl_easy_perform(handle);
  unsafe {
    let _ = fclose(out_file);
  };

  if perf_rc != 0 {
    var err_msg: Str = curl_error_string(perf_rc);
    curl_easy_cleanup(handle);
    unsafe { let _ = remove(path.c_str()); };
    return Err("download failed: " + err_msg);
  };

  var status: Int = get_response_code(handle);
  curl_easy_cleanup(handle);

  if status < 200 || status >= 300 {
    unsafe { let _ = remove(path.c_str()); };
    return Err("download failed with HTTP status: " + int_to_str(status));
  };

  return Ok(Unit);
}

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; };
  var digits: Vec[Str] = Vec[Str].new();
  var num: Int = n;
  if num < 0 { num = -num; };
  while num > 0 {
    var d: Int = num % 10;
    num = num / 10;
    if d == 0 { digits.push("0"); };
    elif d == 1 { digits.push("1"); };
    elif d == 2 { digits.push("2"); };
    elif d == 3 { digits.push("3"); };
    elif d == 4 { digits.push("4"); };
    elif d == 5 { digits.push("5"); };
    elif d == 6 { digits.push("6"); };
    elif d == 7 { digits.push("7"); };
    elif d == 8 { digits.push("8"); };
    elif d == 9 { digits.push("9"); };
  };
  var result: Str = "";
  if n < 0 { result = result + "-"; };
  var j: Int = digits.len() - 1;
  while j >= 0 {
    result = result + digits[j];
    j = j - 1;
  };
  return result;
}
