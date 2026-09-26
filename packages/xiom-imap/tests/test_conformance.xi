// XIOM -- xiom.imap conformance tests (18 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Port task: prove the pure-XIOM xiom.imap parser against its documented
// IMAP4rev1 (RFC 3501) command grammar, response grammar, literal handling,
// nested lists, response codes and error catalog.
//
// Coverage: every modelled command with its argument shape, command-name
// case folding and the UID prefix; atom / quoted / literal / NIL / nested
// parenthesized arguments; literals with embedded CRLF (synchronous,
// LITERAL+ and empty) and their byte accounting; tagged, untagged and
// continuation responses; response text codes and their flattened
// arguments; buffer consuming (consumed counts, parse_at streaming); and
// malformed inputs (bare CR/LF, missing CRLF, bad tags, unknown commands,
// unbalanced parentheses, bad literal sizes, unterminated quoted strings
// and codes, wrong number/status combinations).
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str
// values read from Vec[Str] elements to a pointer comparison, so every
// comparison below is routed through streq instead of `==`.

module imap_tests
use xiom.io; use xiom.test; use xiom.imap;
use xiom.string;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when `line` parses as a command with an "imap: " error.
fn cmd_err(line: Str) -> Bool {
  let r = imap_parse_command(line);
  var ok = false;
  match r {
    Ok(_) => { ok = false; },
    Err(e) => { ok = string.str_starts_with(e, "imap: "); },
  }
  return ok;
}

// True when the whole buffer is exactly one parsed command.
fn cmd_all(line: Str) -> Bool {
  let r = imap_parse_command(line);
  var ok = false;
  match r {
    Ok(c) => { ok = imap_command_consumed(&c) == line.len(); },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn tag_is(line: Str, want: Str) -> Bool {
  let r = imap_parse_command(line);
  var ok = false;
  match r {
    Ok(c) => { ok = streq(c.tag, want); },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn name_is(line: Str, want: Str) -> Bool {
  let r = imap_parse_command(line);
  var ok = false;
  match r {
    Ok(c) => { ok = streq(c.name, want); },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn kind_is(line: Str, want: Int) -> Bool {
  let r = imap_parse_command(line);
  var ok = false;
  match r {
    Ok(c) => { ok = c.kind == want; },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn uid_is(line: Str, want: Bool) -> Bool {
  let r = imap_parse_command(line);
  var ok = false;
  match r {
    Ok(c) => { ok = c.uid == want; },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn argc_is(line: Str, want: Int) -> Bool {
  let r = imap_parse_command(line);
  var ok = false;
  match r {
    Ok(c) => { ok = imap_command_arg_count(&c) == want; },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn argk_is(line: Str, index: Int, want: Int) -> Bool {
  let r = imap_parse_command(line);
  var ok = false;
  match r {
    Ok(c) => { ok = imap_command_arg_kind(&c, index) == want; },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn argt_is(line: Str, index: Int, want: Str) -> Bool {
  let r = imap_parse_command(line);
  var ok = false;
  match r {
    Ok(c) => { ok = streq(imap_command_arg_text(&c, index), want); },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn elem_is(line: Str, index: Int, kind: Int, text: Str, depth: Int) -> Bool {
  let r = imap_parse_command(line);
  var ok = false;
  match r {
    Ok(c) => {
      ok = true;
      if imap_command_element_kind(&c, index) != kind { ok = false; }
      if !streq(imap_command_element_text(&c, index), text) { ok = false; }
      if imap_command_element_depth(&c, index) != depth { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return ok;
}

// True when `text` parses as a response with an "imap: " error.
fn resp_err(text: Str) -> Bool {
  let r = imap_parse_response(text);
  var ok = false;
  match r {
    Ok(_) => { ok = false; },
    Err(e) => { ok = string.str_starts_with(e, "imap: "); },
  }
  return ok;
}

// True when the whole buffer is exactly one parsed response.
fn resp_all(text: Str) -> Bool {
  let r = imap_parse_response(text);
  var ok = false;
  match r {
    Ok(p) => { ok = imap_response_consumed(&p) == text.len(); },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn resp_kind_is(text: Str, want: Int) -> Bool {
  let r = imap_parse_response(text);
  var ok = false;
  match r {
    Ok(p) => { ok = imap_response_kind(&p) == want; },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn resp_status_is(text: Str, want: Str) -> Bool {
  let r = imap_parse_response(text);
  var ok = false;
  match r {
    Ok(p) => { ok = streq(imap_response_status(&p), want); },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn resp_number_is(text: Str, want: Int) -> Bool {
  let r = imap_parse_response(text);
  var ok = false;
  match r {
    Ok(p) => { ok = imap_response_number(&p) == want; },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn resp_text_is(text: Str, want: Str) -> Bool {
  let r = imap_parse_response(text);
  var ok = false;
  match r {
    Ok(p) => { ok = streq(imap_response_text(&p), want); },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn resp_code_is(text: Str, want: Str) -> Bool {
  let r = imap_parse_response(text);
  var ok = false;
  match r {
    Ok(p) => { ok = streq(imap_response_code(&p), want); },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn resp_code_arg_is(text: Str, index: Int, want: Str) -> Bool {
  let r = imap_parse_response(text);
  var ok = false;
  match r {
    Ok(p) => { ok = streq(imap_response_code_arg(&p, index), want); },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn resp_code_argc_is(text: Str, want: Int) -> Bool {
  let r = imap_parse_response(text);
  var ok = false;
  match r {
    Ok(p) => { ok = imap_response_code_arg_count(&p) == want; },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn resp_elemc_is(text: Str, want: Int) -> Bool {
  let r = imap_parse_response(text);
  var ok = false;
  match r {
    Ok(p) => { ok = imap_response_element_count(&p) == want; },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn resp_elem_is(text: Str, index: Int, kind: Int, want: Str, depth: Int) -> Bool {
  let r = imap_parse_response(text);
  var ok = false;
  match r {
    Ok(p) => {
      ok = true;
      if imap_response_element_kind(&p, index) != kind { ok = false; }
      if !streq(imap_response_element_text(&p, index), want) { ok = false; }
      if imap_response_element_depth(&p, index) != depth { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return ok;
}

fn t1() -> TestResult {
  var ok = true;
  if !tag_is("A1 CAPABILITY\r\n", "A1") { ok = false; }
  if !name_is("A1 CAPABILITY\r\n", "CAPABILITY") { ok = false; }
  if !kind_is("A1 CAPABILITY\r\n", IMAP_CMD_CAPABILITY) { ok = false; }
  if !uid_is("A1 CAPABILITY\r\n", false) { ok = false; }
  if !argc_is("A1 CAPABILITY\r\n", 0) { ok = false; }
  if !cmd_all("A1 CAPABILITY\r\n") { ok = false; }
  if !kind_is("b2 noop\r\n", IMAP_CMD_NOOP) { ok = false; }
  if !name_is("b2 noop\r\n", "NOOP") { ok = false; }
  if !kind_is("C3 LOGOUT\r\n", IMAP_CMD_LOGOUT) { ok = false; }
  if !kind_is("D4 CLOSE\r\n", IMAP_CMD_CLOSE) { ok = false; }
  if !kind_is("E5 EXPUNGE\r\n", IMAP_CMD_EXPUNGE) { ok = false; }
  if !cmd_err("A1 NOOP extra\r\n") { ok = false; }
  if !cmd_err("A1\r\n") { ok = false; }
  return assert(ok, "zero-argument commands parse with tags, kinds and byte counts");
}

fn t2() -> TestResult {
  var ok = true;
  if !kind_is("A1 LOGIN alice secret\r\n", IMAP_CMD_LOGIN) { ok = false; }
  if !argc_is("A1 LOGIN alice secret\r\n", 2) { ok = false; }
  if !argk_is("A1 LOGIN alice secret\r\n", 0, IMAP_ARG_ATOM) { ok = false; }
  if !argt_is("A1 LOGIN alice secret\r\n", 0, "alice") { ok = false; }
  if !argt_is("A1 LOGIN alice secret\r\n", 1, "secret") { ok = false; }
  if !kind_is("A2 login Bob s3cr3t\r\n", IMAP_CMD_LOGIN) { ok = false; }
  if !argt_is("A2 login Bob s3cr3t\r\n", 0, "Bob") { ok = false; }
  if !argk_is("A3 LOGIN {5}\r\nalice {6}\r\nsecret\r\n", IMAP_ARG_LITERAL) { ok = false; }
  if !argt_is("A3 LOGIN {5}\r\nalice {6}\r\nsecret\r\n", 0, "alice") { ok = false; }
  if !argt_is("A3 LOGIN {5}\r\nalice {6}\r\nsecret\r\n", 1, "secret") { ok = false; }
  if !kind_is("A3 LOGIN {5}\r\nalice {6}\r\nsecret\r\n", IMAP_CMD_LOGIN) { ok = false; }
  if !cmd_err("A4 LOGIN NIL NIL\r\n") { ok = false; }
  if !cmd_err("A5 LOGIN alice\r\n") { ok = false; }
  if !cmd_err("A6 LOGIN (alice) secret\r\n") { ok = false; }
  return assert(ok, "LOGIN takes two string arguments (atoms, quoted, literals) and rejects NIL");
}

fn t3() -> TestResult {
  var ok = true;
  let wire = "A1 LOGIN \"al\\\"ice\" \"p\\\\ss\"\r\n";
  if !kind_is(wire, IMAP_CMD_LOGIN) { ok = false; }
  if !argt_is(wire, 0, "al\"ice") { ok = false; }
  if !argt_is(wire, 1, "p\\ss") { ok = false; }
  if !argk_is(wire, 0, IMAP_ARG_QUOTED) { ok = false; }
  if !cmd_all(wire) { ok = false; }
  if !argt_is("A2 SELECT \"My Box\"\r\n", 0, "My Box") { ok = false; }
  if !argk_is("A2 SELECT \"My Box\"\r\n", 0, IMAP_ARG_QUOTED) { ok = false; }
  if !cmd_err("A3 SELECT \"unterminated\r\n") { ok = false; }
  if !cmd_err("A4 SELECT \"bad\\escape\"\r\n") { ok = false; }
  if !cmd_err("A5 SELECT \"a\tb\"\r\n") { ok = false; }
  return assert(ok, "quoted strings unescape \\\\ and \\\" and reject bad forms");
}

fn t4() -> TestResult {
  var ok = true;
  if !kind_is("A1 SELECT INBOX\r\n", IMAP_CMD_SELECT) { ok = false; }
  if !argt_is("A1 SELECT INBOX\r\n", 0, "INBOX") { ok = false; }
  if !argc_is("A1 SELECT INBOX\r\n", 1) { ok = false; }
  if !kind_is("A2 EXAMINE \"My Box\"\r\n", IMAP_CMD_EXAMINE) { ok = false; }
  if !kind_is("A3 CREATE foo/bar\r\n", IMAP_CMD_CREATE) { ok = false; }
  if !kind_is("A4 DELETE baz\r\n", IMAP_CMD_DELETE) { ok = false; }
  if !kind_is("A5 RENAME old new\r\n", IMAP_CMD_RENAME) { ok = false; }
  if !argc_is("A5 RENAME old new\r\n", 2) { ok = false; }
  if !argt_is("A5 RENAME old new\r\n", 1, "new") { ok = false; }
  if !cmd_err("A6 SELECT\r\n") { ok = false; }
  if !cmd_err("A7 RENAME only\r\n") { ok = false; }
  if !cmd_err("A8 SELECT (a)\r\n") { ok = false; }
  if !cmd_err("A9 CREATE a b\r\n") { ok = false; }
  return assert(ok, "mailbox commands SELECT/EXAMINE/CREATE/DELETE/RENAME validate arity");
}

fn t5() -> TestResult {
  var ok = true;
  if !kind_is("A1 LIST \"\" \"*\"\r\n", IMAP_CMD_LIST) { ok = false; }
  if !argt_is("A1 LIST \"\" \"*\"\r\n", 0, "") { ok = false; }
  if !argt_is("A1 LIST \"\" \"*\"\r\n", 1, "*") { ok = false; }
  if !argk_is("A2 LIST NIL \"%\"\r\n", 0, IMAP_ARG_NIL) { ok = false; }
  if !argk_is("A3 list ~/mail %\r\n", 1, IMAP_ARG_ATOM) { ok = false; }
  if !cmd_err("A4 LIST \"\"\r\n") { ok = false; }
  if !cmd_err("A5 LIST\r\n") { ok = false; }
  let st = "A6 STATUS INBOX (MESSAGES 231 UIDNEXT 44292)\r\n";
  if !kind_is(st, IMAP_CMD_STATUS) { ok = false; }
  if !argc_is(st, 2) { ok = false; }
  if !argk_is(st, 1, IMAP_ARG_LIST_OPEN) { ok = false; }
  if !elem_is(st, 2, IMAP_ARG_ATOM, "MESSAGES", 1) { ok = false; }
  if !elem_is(st, 3, IMAP_ARG_ATOM, "231", 1) { ok = false; }
  if !elem_is(st, 4, IMAP_ARG_ATOM, "UIDNEXT", 1) { ok = false; }
  if !elem_is(st, 6, IMAP_ARG_LIST_CLOSE, "", 0) { ok = false; }
  if !cmd_err("A7 STATUS INBOX MESSAGES\r\n") { ok = false; }
  if !cmd_err("A8 STATUS INBOX ()\r\n") { ok = false; }
  if !cmd_err("A9 STATUS INBOX (A B\r\n") { ok = false; }
  return assert(ok, "LIST accepts NIL references and STATUS carries a nested item list");
}

fn t6() -> TestResult {
  var ok = true;
  if !kind_is("A1 FETCH 1:5 (FLAGS RFC822.SIZE)\r\n", IMAP_CMD_FETCH) { ok = false; }
  if !argc_is("A1 FETCH 1:5 (FLAGS RFC822.SIZE)\r\n", 2) { ok = false; }
  if !argt_is("A1 FETCH 1:5 (FLAGS RFC822.SIZE)\r\n", 0, "1:5") { ok = false; }
  let nested = "A2 FETCH 2 (BODY.PEEK[HEADER.FIELDS (DATE FROM)] UID)\r\n";
  if !kind_is(nested, IMAP_CMD_FETCH) { ok = false; }
  if !elem_is(nested, 2, IMAP_ARG_ATOM, "BODY.PEEK[HEADER.FIELDS", 1) { ok = false; }
  if !elem_is(nested, 4, IMAP_ARG_ATOM, "DATE", 2) { ok = false; }
  if !elem_is(nested, 5, IMAP_ARG_ATOM, "FROM", 2) { ok = false; }
  if !elem_is(nested, 7, IMAP_ARG_ATOM, "]", 1) { ok = false; }
  if !elem_is(nested, 8, IMAP_ARG_ATOM, "UID", 1) { ok = false; }
  let uid = "A3 UID FETCH 100 (UID FLAGS)\r\n";
  if !kind_is(uid, IMAP_CMD_FETCH) { ok = false; }
  if !uid_is(uid, true) { ok = false; }
  if !name_is(uid, "UID FETCH") { ok = false; }
  if !kind_is("A4 FETCH 1 ALL\r\n", IMAP_CMD_FETCH) { ok = false; }
  if !cmd_err("A5 UID COPY 1:2 INBOX\r\n") { ok = false; }
  if !cmd_err("A6 UID\r\n") { ok = false; }
  if !cmd_err("A7 FETCH 1 ()\r\n") { ok = false; }
  if !cmd_err("A8 FETCH (a) b\r\n") { ok = false; }
  return assert(ok, "FETCH parses nested attribute lists and UID FETCH sets the uid flag");
}

fn t7() -> TestResult {
  var ok = true;
  let st = "A1 STORE 1:3 +FLAGS (\\Seen \\Deleted)\r\n";
  if !kind_is(st, IMAP_CMD_STORE) { ok = false; }
  if !argc_is(st, 3) { ok = false; }
  if !argt_is(st, 1, "+FLAGS") { ok = false; }
  if !elem_is(st, 3, IMAP_ARG_ATOM, "\\Seen", 1) { ok = false; }
  if !argc_is("A2 STORE 4 FLAGS\r\n", 2) { ok = false; }
  if !kind_is("A3 store 5 -flags (\\Deleted)\r\n", IMAP_CMD_STORE) { ok = false; }
  if !name_is("A3 store 5 -flags (\\Deleted)\r\n", "STORE") { ok = false; }
  if !cmd_err("A4 STORE 1 SETTINGS (x)\r\n") { ok = false; }
  if !cmd_err("A5 STORE 1:3\r\n") { ok = false; }
  if !kind_is("A6 SEARCH ALL\r\n", IMAP_CMD_SEARCH) { ok = false; }
  if !kind_is("A7 SEARCH SINCE 1-Feb-1994 NOT FROM \"Smith\"\r\n", IMAP_CMD_SEARCH) { ok = false; }
  if !argc_is("A7 SEARCH SINCE 1-Feb-1994 NOT FROM \"Smith\"\r\n", 5) { ok = false; }
  if !name_is("A8 UID SEARCH UNSEEN\r\n", "UID SEARCH") { ok = false; }
  if !uid_is("A8 UID SEARCH UNSEEN\r\n", true) { ok = false; }
  if !cmd_err("A9 SEARCH\r\n") { ok = false; }
  return assert(ok, "STORE flag items and SEARCH criteria validate while staying opaque");
}

fn t8() -> TestResult {
  var ok = true;
  let app = "A1 APPEND INBOX {12}\r\nHello\r\nWorld\r\n";
  if !kind_is(app, IMAP_CMD_APPEND) { ok = false; }
  if !argc_is(app, 2) { ok = false; }
  if !elem_is(app, 1, IMAP_ARG_LITERAL, "Hello\r\nWorld", 0) { ok = false; }
  if !cmd_all(app) { ok = false; }
  let app2 = "A2 APPEND INBOX (\\Seen) \"25-Oct-2024 12:00:00 +0000\" {3+}\r\nXYZ\r\n";
  if !kind_is(app2, IMAP_CMD_APPEND) { ok = false; }
  if !argc_is(app2, 4) { ok = false; }
  if !argk_is(app2, 1, IMAP_ARG_LIST_OPEN) { ok = false; }
  if !argk_is(app2, 2, IMAP_ARG_QUOTED) { ok = false; }
  if !argk_is(app2, 3, IMAP_ARG_LITERAL_PLUS) { ok = false; }
  if !argt_is(app2, 3, "XYZ") { ok = false; }
  if !cmd_all(app2) { ok = false; }
  let app3 = "A3 APPEND \"Saved\" {0}\r\n\r\n";
  if !argk_is(app3, 1, IMAP_ARG_LITERAL) { ok = false; }
  if !argt_is(app3, 1, "") { ok = false; }
  if !cmd_all(app3) { ok = false; }
  if !cmd_err("A4 APPEND INBOX \"no literal\"\r\n") { ok = false; }
  if !cmd_err("A5 APPEND INBOX (\\Seen) {5}\r\nhi\r\n") { ok = false; }
  if !cmd_err("A6 APPEND INBOX \\Seen {3}\r\nabc\r\n") { ok = false; }
  return assert(ok, "APPEND consumes literals with embedded CRLF and LITERAL+ markers");
}

fn t9() -> TestResult {
  var ok = true;
  if !cmd_err("A1 APPEND INBOX {abc}\r\n") { ok = false; }
  if !cmd_err("A2 APPEND INBOX {2}x\r\n") { ok = false; }
  if !cmd_err("A3 APPEND INBOX {99999999999}\r\n") { ok = false; }
  if !cmd_err("A4 APPEND INBOX {5}\r\n") { ok = false; }
  if !cmd_err("A5 APPEND INBOX {3}\r\nabcX\r\n") { ok = false; }
  if !cmd_err("A6 APPEND INBOX { }\r\n") { ok = false; }
  if !argt_is("A7 APPEND INBOX {003}\r\nabc\r\n", 1, "abc") { ok = false; }
  if !argk_is("A7 APPEND INBOX {003}\r\nabc\r\n", 1, IMAP_ARG_LITERAL) { ok = false; }
  if !argk_is("A8 LOGIN {5+}\r\nalice {6}\r\nsecret\r\n", 0, IMAP_ARG_LITERAL_PLUS) { ok = false; }
  if !argk_is("A8 LOGIN {5+}\r\nalice {6}\r\nsecret\r\n", 1, IMAP_ARG_LITERAL) { ok = false; }
  if !elem_is("A9 FETCH 1 (BODY[] {4}\r\ntext)\r\n", 3, IMAP_ARG_LITERAL, "text", 1) { ok = false; }
  if !cmd_all("A9 FETCH 1 (BODY[] {4}\r\ntext)\r\n") { ok = false; }
  return assert(ok, "literal sizes are validated and literals work inside lists");
}

fn t10() -> TestResult {
  var ok = true;
  if !cmd_err("") { ok = false; }
  if !cmd_err("A1 NOOP") { ok = false; }
  if !cmd_err("A1 NOOP\n") { ok = false; }
  if !cmd_err("A1 NOOP\rX") { ok = false; }
  if !cmd_err("* NOOP\r\n") { ok = false; }
  if !cmd_err("+ NOOP\r\n") { ok = false; }
  if !cmd_err("A]1 NOOP\r\n") { ok = false; }
  if !cmd_err("A1 BOGUS\r\n") { ok = false; }
  if !cmd_err("A1 FETCH 1 (FLAGS\r\n") { ok = false; }
  if !cmd_err("A1 FETCH 1 FLAGS)\r\n") { ok = false; }
  if !cmd_err("A1 FETCH 1 FOO)\r\n") { ok = false; }
  return assert(ok, "command framing rejects bare line ends, bad tags, unknown names and unbalanced lists");
}

fn t11() -> TestResult {
  var ok = true;
  let t = "A1 OK Completed\r\n";
  if !resp_kind_is(t, IMAP_RESPONSE_TAGGED) { ok = false; }
  if !resp_status_is(t, "OK") { ok = false; }
  if !resp_text_is(t, "Completed") { ok = false; }
  if !resp_code_is(t, "") { ok = false; }
  if !resp_code_argc_is(t, 0) { ok = false; }
  if !resp_all(t) { ok = false; }
  let no = "A2 NO [ALERT] Try again later\r\n";
  if !resp_status_is(no, "NO") { ok = false; }
  if !resp_code_is(no, "ALERT") { ok = false; }
  if !resp_code_argc_is(no, 0) { ok = false; }
  if !resp_text_is(no, "Try again later") { ok = false; }
  let badcs = "B3 BAD [BADCHARSET (US-ASCII)] Bad charset\r\n";
  if !resp_status_is(badcs, "BAD") { ok = false; }
  if !resp_code_is(badcs, "BADCHARSET") { ok = false; }
  if !resp_code_arg_is(badcs, 0, "US-ASCII") { ok = false; }
  if !resp_text_is(badcs, "Bad charset") { ok = false; }
  let uidv = "A4 OK [UIDVALIDITY 3857529045]\r\n";
  if !resp_code_is(uidv, "UIDVALIDITY") { ok = false; }
  if !resp_code_arg_is(uidv, 0, "3857529045") { ok = false; }
  if !resp_text_is(uidv, "") { ok = false; }
  let pf = "A5 OK [PERMANENTFLAGS (\\Seen \\Deleted \\*)] Done\r\n";
  if !resp_code_is(pf, "PERMANENTFLAGS") { ok = false; }
  if !resp_code_argc_is(pf, 3) { ok = false; }
  if !resp_code_arg_is(pf, 0, "\\Seen") { ok = false; }
  if !resp_code_arg_is(pf, 2, "\\*") { ok = false; }
  if !resp_code_is("A6 OK [READ-ONLY] SELECT completed\r\n", "READ-ONLY") { ok = false; }
  if !resp_err("A7 FINE Completed\r\n") { ok = false; }
  if !resp_err("A9 OK [unterminated\r\n") { ok = false; }
  if !resp_err("A10 OK []\r\n") { ok = false; }
  return assert(ok, "tagged completions expose status, text and bracketed response codes");
}

fn t12() -> TestResult {
  var ok = true;
  let cap = "* CAPABILITY IMAP4rev1 AUTH=PLAIN STARTTLS\r\n";
  if !resp_kind_is(cap, IMAP_RESPONSE_UNTAGGED) { ok = false; }
  if !resp_status_is(cap, "CAPABILITY") { ok = false; }
  if !resp_number_is(cap, -1) { ok = false; }
  if !resp_elem_is(cap, 0, IMAP_ARG_ATOM, "IMAP4rev1", 0) { ok = false; }
  if !resp_elem_is(cap, 2, IMAP_ARG_ATOM, "STARTTLS", 0) { ok = false; }
  if !resp_all(cap) { ok = false; }
  let fl = "* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)\r\n";
  if !resp_status_is(fl, "FLAGS") { ok = false; }
  if !resp_elem_is(fl, 1, IMAP_ARG_ATOM, "\\Answered", 1) { ok = false; }
  if !resp_elem_is(fl, 5, IMAP_ARG_ATOM, "\\Draft", 1) { ok = false; }
  if !resp_status_is("* SEARCH 2 84 882\r\n", "SEARCH") { ok = false; }
  if !resp_elem_is("* SEARCH 2 84 882\r\n", 1, IMAP_ARG_ATOM, "84", 0) { ok = false; }
  if !resp_status_is("* SEARCH\r\n", "SEARCH") { ok = false; }
  if !resp_text_is("* BYE Autologout; idle for too long\r\n", "Autologout; idle for too long") { ok = false; }
  let un = "* OK [UNSEEN 12] Message 12 is first unseen\r\n";
  if !resp_status_is(un, "OK") { ok = false; }
  if !resp_code_is(un, "UNSEEN") { ok = false; }
  if !resp_code_arg_is(un, 0, "12") { ok = false; }
  if !resp_text_is(un, "Message 12 is first unseen") { ok = false; }
  let pre = "* PREAUTH [CAPABILITY IMAP4rev1] Logged in\r\n";
  if !resp_status_is(pre, "PREAUTH") { ok = false; }
  if !resp_code_is(pre, "CAPABILITY") { ok = false; }
  if !resp_code_arg_is(pre, 0, "IMAP4rev1") { ok = false; }
  if !resp_text_is(pre, "Logged in") { ok = false; }
  return assert(ok, "untagged CAPABILITY/FLAGS/SEARCH/BYE/OK/PREAUTH responses parse");
}

fn t13() -> TestResult {
  var ok = true;
  if !resp_number_is("* 23 EXISTS\r\n", 23) { ok = false; }
  if !resp_status_is("* 23 EXISTS\r\n", "EXISTS") { ok = false; }
  if !resp_elemc_is("* 23 EXISTS\r\n", 0) { ok = false; }
  if !resp_number_is("* 5 RECENT\r\n", 5) { ok = false; }
  if !resp_status_is("* 5 RECENT\r\n", "RECENT") { ok = false; }
  if !resp_number_is("* 44 EXPUNGE\r\n", 44) { ok = false; }
  if !resp_status_is("* 44 EXPUNGE\r\n", "EXPUNGE") { ok = false; }
  if !resp_err("* 23 FOO\r\n") { ok = false; }
  if !resp_err("* EXISTS\r\n") { ok = false; }
  if !resp_err("* 3 FETCH FLAGS\r\n") { ok = false; }
  if !resp_err("* CAPABILITY") { ok = false; }
  return assert(ok, "numbered untagged responses require EXISTS/RECENT/EXPUNGE/FETCH");
}

fn t14() -> TestResult {
  var ok = true;
  let f = "* 12 FETCH (FLAGS (\\Seen) RFC822.SIZE 44827)\r\n";
  if !resp_kind_is(f, IMAP_RESPONSE_UNTAGGED) { ok = false; }
  if !resp_number_is(f, 12) { ok = false; }
  if !resp_status_is(f, "FETCH") { ok = false; }
  if !resp_elem_is(f, 3, IMAP_ARG_ATOM, "\\Seen", 2) { ok = false; }
  if !resp_elem_is(f, 5, IMAP_ARG_ATOM, "RFC822.SIZE", 1) { ok = false; }
  if !resp_all(f) { ok = false; }
  let lit = "* 18 FETCH (BODY[] {18}\r\nSubject: hi\r\nBody!)\r\n";
  if !resp_number_is(lit, 18) { ok = false; }
  if !resp_elem_is(lit, 2, IMAP_ARG_LITERAL, "Subject: hi\r\nBody!", 1) { ok = false; }
  if !resp_all(lit) { ok = false; }
  if !resp_elem_is("* 1 FETCH (UID 100 FLAGS ())\r\n", 1, IMAP_ARG_ATOM, "UID", 1) { ok = false; }
  if !resp_err("* 1 FETCH FLAGS\r\n") { ok = false; }
  if !resp_err("* 1 FETCH (FLAGS\r\n") { ok = false; }
  if !resp_err("* 1 FETCH (X {5}\r\nabc\r\n") { ok = false; }
  return assert(ok, "FETCH responses parse attribute lists, flags and multi-line literals");
}

fn t15() -> TestResult {
  var ok = true;
  let li = "* LIST (\\HasNoChildren) \".\" \"INBOX\"\r\n";
  if !resp_status_is(li, "LIST") { ok = false; }
  if !resp_elem_is(li, 1, IMAP_ARG_ATOM, "\\HasNoChildren", 1) { ok = false; }
  if !resp_elem_is(li, 3, IMAP_ARG_QUOTED, ".", 0) { ok = false; }
  if !resp_elem_is(li, 4, IMAP_ARG_QUOTED, "INBOX", 0) { ok = false; }
  if !resp_all(li) { ok = false; }
  let ls = "* LSUB () NIL \"Saved\"\r\n";
  if !resp_status_is(ls, "LSUB") { ok = false; }
  if !resp_elem_is(ls, 2, IMAP_ARG_NIL, "NIL", 0) { ok = false; }
  if !resp_elem_is(ls, 3, IMAP_ARG_QUOTED, "Saved", 0) { ok = false; }
  let st = "* STATUS \"INBOX\" (MESSAGES 231 RECENT 2 UIDNEXT 44292)\r\n";
  if !resp_status_is(st, "STATUS") { ok = false; }
  if !resp_elem_is(st, 0, IMAP_ARG_QUOTED, "INBOX", 0) { ok = false; }
  if !resp_elem_is(st, 2, IMAP_ARG_ATOM, "MESSAGES", 1) { ok = false; }
  if !resp_elem_is(st, 7, IMAP_ARG_ATOM, "44292", 1) { ok = false; }
  if !resp_err("* STATUS INBOX (MESSAGES)\r\n") { ok = false; }
  if !resp_err("* LIST () \".\"\r\n") { ok = false; }
  if !resp_err("* STATUS INBOX MESSAGES\r\n") { ok = false; }
  return assert(ok, "LIST/LSUB/STATUS responses validate their mailbox argument shapes");
}

fn t16() -> TestResult {
  var ok = true;
  if !resp_kind_is("+ Ready to receive literal\r\n", IMAP_RESPONSE_CONTINUATION) { ok = false; }
  if !resp_text_is("+ Ready to receive literal\r\n", "Ready to receive literal") { ok = false; }
  if !resp_text_is("+\r\n", "") { ok = false; }
  let plus = "+ [READ-ONLY] go\r\n";
  if !resp_code_is(plus, "READ-ONLY") { ok = false; }
  if !resp_text_is(plus, "go") { ok = false; }
  if !resp_err("+x\r\n") { ok = false; }
  return assert(ok, "continuation responses parse with and without text and codes");
}

fn cmd_err_at(line: Str, pos: Int) -> Bool {
  let r = imap_parse_command_at(line, pos);
  var ok = false;
  match r {
    Ok(_) => { ok = false; },
    Err(e) => { ok = string.str_starts_with(e, "imap: "); },
  }
  return ok;
}

fn t17() -> TestResult {
  var ok = true;
  let stream = "A1 NOOP\r\nA2 LOGOUT\r\n";
  let r1 = imap_parse_command(stream);
  match r1 {
    Ok(c) => {
      if imap_command_consumed(&c) != 9 { ok = false; }
      if !streq(imap_command_tag(&c), "A1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = imap_parse_command_at(stream, 9);
  match r2 {
    Ok(c) => {
      if imap_command_consumed(&c) != 11 { ok = false; }
      if !streq(imap_command_tag(&c), "A2") { ok = false; }
      if c.kind != IMAP_CMD_LOGOUT { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !cmd_err_at(stream, 20) { ok = false; }
  let rstream = "A1 OK done\r\n* 3 EXISTS\r\n";
  let s1 = imap_parse_response(rstream);
  match s1 {
    Ok(p) => {
      if imap_response_consumed(&p) != 12 { ok = false; }
      if !streq(imap_response_status(&p), "OK") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let s2 = imap_parse_response_at(rstream, 12);
  match s2 {
    Ok(p) => {
      if imap_response_consumed(&p) != 12 { ok = false; }
      if imap_response_number(&p) != 3 { ok = false; }
      if !streq(imap_response_status(&p), "EXISTS") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "consumed counts bytes and parse_at resumes mid-buffer");
}

fn t18() -> TestResult {
  var ok = true;
  let r = imap_parse_command("A1 LIST \"\" \"*\"\r\n");
  match r {
    Ok(c) => {
      if imap_command_element_count(&c) != 2 { ok = false; }
      if imap_command_element_kind(&c, -1) != -1 { ok = false; }
      if imap_command_element_kind(&c, 99) != -1 { ok = false; }
      if !streq(imap_command_element_text(&c, 99), "") { ok = false; }
      if imap_command_element_depth(&c, -1) != -1 { ok = false; }
      if imap_command_element_offset(&c, 99) != -1 { ok = false; }
      if imap_command_element_offset(&c, 0) != 8 { ok = false; }
      if imap_command_element_offset(&c, 1) != 11 { ok = false; }
      if imap_command_arg_kind(&c, 99) != 0 { ok = false; }
      if !streq(imap_command_arg_text(&c, 99), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let p = imap_parse_response("A1 OK [UIDVALIDITY 7] Done\r\n");
  match p {
    Ok(resp) => {
      if imap_response_element_count(&resp) != 0 { ok = false; }
      if imap_response_element_kind(&resp, 0) != -1 { ok = false; }
      if !streq(imap_response_element_text(&resp, 5), "") { ok = false; }
      if imap_response_element_depth(&resp, -1) != -1 { ok = false; }
      if imap_response_element_offset(&resp, 5) != -1 { ok = false; }
      if imap_response_arg_count(&resp) != 0 { ok = false; }
      if imap_response_arg_kind(&resp, 0) != 0 { ok = false; }
      if !streq(imap_response_code_arg(&resp, 9), "") { ok = false; }
      if imap_response_code_arg_count(&resp) != 1 { ok = false; }
      if !streq(imap_response_tag(&resp), "A1") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  if !resp_err("A1 OK [BAD\r\n") { ok = false; }
  if !resp_err("A1 OK\rX") { ok = false; }
  if !resp_err("A1 OK done\n") { ok = false; }
  return assert(ok, "accessors are bounds-safe and malformed responses are rejected");
}

fn main() -> Int {
  io.println("=== xiom.imap conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.imap: all tests passed");
  } else {
    io.println("xiom.imap: tests failed");
  }
  return failed;
}
