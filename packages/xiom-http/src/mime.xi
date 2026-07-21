module xiom.http.mime

pub type MimeType = {
  main_type: Str;
  sub_type: Str;
}

pub fn mime_from_ext(ext: Str) -> MimeType {
  if ext == ".html" || ext == ".htm" { return MimeType{ main_type: "text", sub_type: "html" }; }
  elif ext == ".css" { return MimeType{ main_type: "text", sub_type: "css" }; }
  elif ext == ".js" || ext == ".mjs" { return MimeType{ main_type: "application", sub_type: "javascript" }; }
  elif ext == ".json" { return MimeType{ main_type: "application", sub_type: "json" }; }
  elif ext == ".xml" { return MimeType{ main_type: "application", sub_type: "xml" }; }
  elif ext == ".png" { return MimeType{ main_type: "image", sub_type: "png" }; }
  elif ext == ".jpg" || ext == ".jpeg" { return MimeType{ main_type: "image", sub_type: "jpeg" }; }
  elif ext == ".gif" { return MimeType{ main_type: "image", sub_type: "gif" }; }
  elif ext == ".svg" { return MimeType{ main_type: "image", sub_type: "svg+xml" }; }
  elif ext == ".pdf" { return MimeType{ main_type: "application", sub_type: "pdf" }; }
  elif ext == ".txt" { return MimeType{ main_type: "text", sub_type: "plain" }; }
  elif ext == ".csv" { return MimeType{ main_type: "text", sub_type: "csv" }; }
  elif ext == ".zip" { return MimeType{ main_type: "application", sub_type: "zip" }; }
  elif ext == ".mp3" { return MimeType{ main_type: "audio", sub_type: "mpeg" }; }
  elif ext == ".mp4" { return MimeType{ main_type: "video", sub_type: "mp4" }; }
  elif ext == ".wasm" { return MimeType{ main_type: "application", sub_type: "wasm" }; }
  elif ext == ".woff" { return MimeType{ main_type: "font", sub_type: "woff" }; }
  elif ext == ".woff2" { return MimeType{ main_type: "font", sub_type: "woff2" }; }
  elif ext == ".ico" { return MimeType{ main_type: "image", sub_type: "x-icon" }; }
  elif ext == ".webp" { return MimeType{ main_type: "image", sub_type: "webp" }; }
  elif ext == ".ogg" { return MimeType{ main_type: "audio", sub_type: "ogg" }; }
  return MimeType{ main_type: "application", sub_type: "octet-stream" };
}

pub fn mime_to_str(mime: &MimeType) -> Str {
  return mime.main_type + "/" + mime.sub_type;
}
