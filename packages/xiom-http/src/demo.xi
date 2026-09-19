module xiom.http.demo

use xiom.io;
use xiom.convert;

pub fn demo_get() -> Result[Unit, Str] {
  var result: Result[HttpResponse, Str] = xiom.http.http_get("https://httpbin.org/get");
  match result {
    Err(e) => {
      return Err("GET demo failed: " + e);
    };
    Ok(resp) => {
      if resp.status != 200 {
        return Err("GET demo: unexpected status " + xiom.convert.int_to_string(resp.status));
      };
      if resp.body.len() == 0 {
        return Err("GET demo: empty response body");
      };
      xiom.io.println("GET demo passed");
      return Ok(Unit);
    };
  };
}

pub fn demo_post() -> Result[Unit, Str] {
  var json_body: Str = "{\"name\":\"xiom.http\",\"version\":\"0.1.0\"}";
  var result: Result[HttpResponse, Str] = xiom.http.http_post(
    "https://httpbin.org/post",
    json_body,
    "application/json",
  );
  match result {
    Err(e) => {
      return Err("POST demo failed: " + e);
    };
    Ok(resp) => {
      if resp.status != 200 {
        return Err("POST demo: unexpected status " + xiom.convert.int_to_string(resp.status));
      };
      if resp.body.len() == 0 {
        return Err("POST demo: empty response body");
      };
      xiom.io.println("POST demo passed");
      return Ok(Unit);
    };
  };
}

pub fn demo_rest_api() -> Result[Unit, Str] {
  var base_url: Str = "https://httpbin.org";

  var get_result: Result[HttpResponse, Str] = xiom.http.http_get(base_url + "/get?demo=true");
  match get_result {
    Err(e) => {
      return Err("REST GET failed: " + e);
    };
    Ok(resp) => {
      if resp.status != 200 {
        return Err("REST GET: unexpected status " + xiom.convert.int_to_string(resp.status));
      };
    };
  };

  var post_body: Str = "{\"action\":\"create\",\"data\":{\"id\":1,\"label\":\"xiom-demo\"}}";
  var post_result: Result[HttpResponse, Str] = xiom.http.http_post(
    base_url + "/post",
    post_body,
    "application/json",
  );
  match post_result {
    Err(e) => {
      return Err("REST POST failed: " + e);
    };
    Ok(resp) => {
      if resp.status != 200 {
        return Err("REST POST: unexpected status " + xiom.convert.int_to_string(resp.status));
      };
    };
  };

  var put_body: Str = "{\"action\":\"update\",\"data\":{\"id\":1,\"label\":\"xiom-updated\"}}";
  var put_result: Result[HttpResponse, Str] = xiom.http.http_put(
    base_url + "/put",
    put_body,
  );
  match put_result {
    Err(e) => {
      return Err("REST PUT failed: " + e);
    };
    Ok(resp) => {
      if resp.status != 200 {
        return Err("REST PUT: unexpected status " + xiom.convert.int_to_string(resp.status));
      };
    };
  };

  var delete_result: Result[HttpResponse, Str] = xiom.http.http_delete(
    base_url + "/delete?id=1",
  );
  match delete_result {
    Err(e) => {
      return Err("REST DELETE failed: " + e);
    };
    Ok(resp) => {
      if resp.status != 200 {
        return Err("REST DELETE: unexpected status " + xiom.convert.int_to_string(resp.status));
      };
    };
  };

  var download_result: Result[Unit, Str] = xiom.http.http_download(
    "https://httpbin.org/image/png",
    "demo_download.png",
  );
  match download_result {
    Err(e) => {
      return Err("REST download failed: " + e);
    };
    Ok(_) => {
      var _: Int = cleanup_download("demo_download.png");
    };
  };

  xiom.io.println("REST API demo passed");
  return Ok(Unit);
}

fn cleanup_download(path: Str) -> Int {
  return 0;
}
