module xiom.log.format

fn format_text(entry: &LogEntry, config: &LoggerConfig) -> Str {
  let prefix = format_text_prefix(entry, config);
  let message = prefix + ": " + entry.message;
  if entry.fields.len() > 0 {
    message + " " + format_fields(&entry.fields)
  } else {
    message
  }
}

fn format_text_prefix(entry: &LogEntry, config: &LoggerConfig) -> Str {
  let level_str = log_level_to_str(&entry.level);
  var result = "";
  if config.include_timestamp {
    result = result + Int_to_str(entry.timestamp) + " ";
  };
  result = result + "[" + level_str + "]";
  if config.include_module && entry.module.len() > 0 {
    result = result + " " + entry.module;
  };
  result
}

fn format_json(entry: &LogEntry) -> Str {
  var result = "{";
  result = result + "\"level\":\"" + log_level_to_str(&entry.level) + "\"";
  result = result + ",\"message\":\"" + entry.message + "\"";
  if entry.module.len() > 0 {
    result = result + ",\"module\":\"" + entry.module + "\"";
  };
  result = result + ",\"timestamp\":" + Int_to_str(entry.timestamp);
  if entry.fields.len() > 0 {
    result = result + ",\"fields\":" + format_fields_json(&entry.fields);
  };
  result + "}"
}

fn format_compact(entry: &LogEntry) -> Str {
  log_level_to_str(&entry.level) + " " + entry.message
}

fn format_fields(fields: &Vec[LogField]) -> Str {
  format_fields_iter(fields, 0, "")
}

fn format_fields_iter(fields: &Vec[LogField], idx: Int, acc: Str) -> Str {
  if idx >= fields.len() {
    acc
  } else {
    let field = &fields[idx];
    let pair = field.key + "=" + field.value;
    let new_acc = if acc.len() > 0 { acc + " " + pair } else { pair };
    format_fields_iter(fields, idx + 1, new_acc)
  }
}

fn format_fields_json(fields: &Vec[LogField]) -> Str {
  format_fields_json_iter(fields, 0, "{")
}

fn format_fields_json_iter(fields: &Vec[LogField], idx: Int, acc: Str) -> Str {
  if idx >= fields.len() {
    acc + "}"
  } else {
    let field = &fields[idx];
    let pair = "\"" + field.key + "\":\"" + field.value + "\"";
    let new_acc = if idx > 0 { acc + "," + pair } else { acc + pair };
    format_fields_json_iter(fields, idx + 1, new_acc)
  }
}
