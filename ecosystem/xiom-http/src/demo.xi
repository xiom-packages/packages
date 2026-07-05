module xiom.http.demo

pub fn demo_get() -> Result[Unit, Str] {
  var result: Result[HttpResponse, Str] = xiom.http.http_get("https://httpbin.org/get");
  match result {
    Err(e) => {
      return Err("GET demo failed: " + e);
    };
    Ok(resp) => {
      if resp.status != 200 {
        return Err("GET demo: unexpected status " + int_to_str(resp.status));
      };
      if resp.body.len() == 0 {
        return Err("GET demo: empty response body");
      };
      return Ok(Unit);
    };
  };
}

pub fn demo_post() -> Result[Unit, Str] {
  var json_body: Str = "{\"name\":\"xiom-http\",\"version\":\"0.1.0\"}";
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
        return Err("POST demo: unexpected status " + int_to_str(resp.status));
      };
      if resp.body.len() == 0 {
        return Err("POST demo: empty response body");
      };
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
        return Err("REST GET: unexpected status " + int_to_str(resp.status));
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
        return Err("REST POST: unexpected status " + int_to_str(resp.status));
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
        return Err("REST PUT: unexpected status " + int_to_str(resp.status));
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
        return Err("REST DELETE: unexpected status " + int_to_str(resp.status));
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

  return Ok(Unit);
}

fn cleanup_download(path: Str) -> Int {
  return 0;
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
