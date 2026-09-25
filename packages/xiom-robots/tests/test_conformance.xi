// XIOM -- xiom.robots conformance tests (29 checks)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
// Greenfield package: prove the pure-XIOM xiom.robots module against its
// documented robots.txt grammar, matching algorithm, error catalog and
// canonical emitter.
//
// Coverage: one-group parse with rule order; several User-agent lines;
// group termination; empty Allow/Disallow; comments, blanks and CRLF;
// case-insensitive field names; Crawl-delay values, per-group scope and
// last-wins; document-global Sitemaps and their validation; the whole error
// catalog (rule before user-agent, empty token, bad delay, control bytes,
// unknown field, missing colon/name, bad sitemap); path matching (prefix,
// "*", "$"); is_allowed longest-match and allow-wins ties; group selection
// (longest token, "*" fallback, first duplicate wins); canonical emit and
// round-trip/idempotence; out-of-range accessors; empty documents.
//
// All Str equality goes through str_compare: BUG 17 lowers `==` on Str values
// read from Vec[Str] elements to a pointer comparison, so element
// comparisons below are routed through streq/d_path/a_is instead of `==`.

module robots_tests
use xiom.io; use xiom.test; use xiom.robots;
use xiom.string.compare;

// String equality through the stdlib comparator (never `==` on Str).
fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// True when rule (g, i) has exactly the path `want`.
fn d_path(r: &Robots, g: Int, i: Int, want: Str) -> Bool {
  return streq(robots_rule_path(r, g, i), want);
}

// True when rule (g, i) has exactly the Allow flag `want`.
fn d_allow(r: &Robots, g: Int, i: Int, want: Bool) -> Bool {
  return robots_rule_allow(r, g, i) == want;
}

// True when agent (g, i) is exactly `want`.
fn a_is(r: &Robots, g: Int, i: Int, want: Str) -> Bool {
  return streq(robots_agent(r, g, i), want);
}

// True when the Option is Some with exactly `want`.
fn opt_int_is(o: Option[Int], want: Int) -> Bool {
  match o {
    Some(v) => { return v == want; },
    None => { return false; },
  }
  return false;
}

// True when the Option is None.
fn opt_int_none(o: Option[Int]) -> Bool {
  match o {
    Some(_) => { return false; },
    None => { return true; },
  }
  return true;
}

// True when robots_parse(text) is Err with exactly `want`.
fn err_is(text: Str, want: Str) -> Bool {
  let r = robots_parse(text);
  match r {
    Ok(_) => { return false; },
    Err(e) => { return streq(e, want); },
  }
  return false;
}

fn t1() -> TestResult {
  let r = robots_parse("User-agent: *\nDisallow: /private\nAllow: /private/public\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = robots_group_count(&x) == 1;
      if robots_agent_count(&x, 0) != 1 { ok = false; }
      if !a_is(&x, 0, 0, "*") { ok = false; }
      if robots_rule_count(&x, 0) != 2 { ok = false; }
      if !d_path(&x, 0, 0, "/private") { ok = false; }
      if !d_allow(&x, 0, 0, false) { ok = false; }
      if !d_path(&x, 0, 1, "/private/public") { ok = false; }
      if !d_allow(&x, 0, 1, true) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "one group: agent, ordered Allow and Disallow rules");
}

fn t2() -> TestResult {
  let r = robots_parse("User-agent: a\nUSER-AGENT: b\nuser-Agent:\tc\nDisallow: /x\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = robots_group_count(&x) == 1;
      if robots_agent_count(&x, 0) != 3 { ok = false; }
      if !a_is(&x, 0, 0, "a") { ok = false; }
      if !a_is(&x, 0, 1, "b") { ok = false; }
      if !a_is(&x, 0, 2, "c") { ok = false; }
      if robots_rule_count(&x, 0) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "several User-agent lines share one group; names are case-insensitive");
}

fn t3() -> TestResult {
  let r = robots_parse("User-agent: a\nDisallow: /x\nUser-agent: b\nUser-agent: c\nAllow: /y\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = robots_group_count(&x) == 2;
      if robots_agent_count(&x, 0) != 1 { ok = false; }
      if robots_agent_count(&x, 1) != 2 { ok = false; }
      if !a_is(&x, 1, 0, "b") { ok = false; }
      if !a_is(&x, 1, 1, "c") { ok = false; }
      if robots_rule_count(&x, 0) != 1 { ok = false; }
      if robots_rule_count(&x, 1) != 1 { ok = false; }
      if !d_path(&x, 0, 0, "/x") { ok = false; }
      if !d_path(&x, 1, 0, "/y") { ok = false; }
      if !d_allow(&x, 1, 0, true) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a User-agent line after a rule starts a new group");
}

fn t4() -> TestResult {
  let r = robots_parse("User-agent: *\nDisallow:\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = robots_group_count(&x) == 1;
      if robots_rule_count(&x, 0) != 1 { ok = false; }
      if !d_path(&x, 0, 0, "") { ok = false; }
      if !d_allow(&x, 0, 0, false) { ok = false; }
      if !robots_is_allowed(&x, "*", "/anything") { ok = false; }
      if robots_path_matches("", "/anything") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = robots_parse("User-agent: *\nAllow:\n");
  match r2 {
    Ok(y) => {
      if robots_rule_count(&y, 0) != 1 { ok = false; }
      if !d_path(&y, 0, 0, "") { ok = false; }
      if !d_allow(&y, 0, 0, true) { ok = false; }
      if !robots_is_allowed(&y, "*", "/anything") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "empty Disallow/Allow is stored and matches nothing (allow-all)");
}

fn t5() -> TestResult {
  let r = robots_parse("# top\r\n\r\n  User-agent :   *   # inline\r\n\tDisallow:\t/blocked\t# tail\r\n\r\n# bottom\r\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = robots_group_count(&x) == 1;
      if !a_is(&x, 0, 0, "*") { ok = false; }
      if robots_rule_count(&x, 0) != 1 { ok = false; }
      if !d_path(&x, 0, 0, "/blocked") { ok = false; }
      if robots_sitemap_count(&x) != 0 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "comments, blank lines, CRLF and whitespace trimming");
}

fn t6() -> TestResult {
  let r = robots_parse("USER-AGENT: bot\nALLOW: /a\nDISALLOW: /b\nCrAwL-DeLaY: 3\nSiTeMaP: https://e.com/s.xml\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = robots_group_count(&x) == 1;
      if !a_is(&x, 0, 0, "bot") { ok = false; }
      if robots_rule_count(&x, 0) != 2 { ok = false; }
      if !d_path(&x, 0, 0, "/a") { ok = false; }
      if !d_allow(&x, 0, 0, true) { ok = false; }
      if !d_path(&x, 0, 1, "/b") { ok = false; }
      if !d_allow(&x, 0, 1, false) { ok = false; }
      if !opt_int_is(robots_crawl_delay(&x, 0), 3) { ok = false; }
      if robots_sitemap_count(&x) != 1 { ok = false; }
      if !streq(robots_sitemap(&x, 0), "https://e.com/s.xml") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "field names are ASCII case-insensitive");
}

fn t7() -> TestResult {
  let r0 = robots_parse("User-agent: *\nCrawl-delay: 0\n");
  var ok = false;
  match r0 {
    Ok(x0) => { ok = opt_int_is(robots_crawl_delay(&x0, 0), 0); },
    Err(_) => { ok = false; },
  }
  let r1 = robots_parse("User-agent: *\nCrawl-delay: 007\n");
  match r1 {
    Ok(x1) => {
      if !opt_int_is(robots_crawl_delay(&x1, 0), 7) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = robots_parse("User-agent: *\nCrawl-delay: 1\nCrawl-delay: 12\n");
  match r2 {
    Ok(x2) => {
      if !opt_int_is(robots_crawl_delay(&x2, 0), 12) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r3 = robots_parse("User-agent: *\nCrawl-delay: 2147483647\n");
  match r3 {
    Ok(x3) => {
      if !opt_int_is(robots_crawl_delay(&x3, 0), 2147483647) { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "Crawl-delay: 0, leading zeros, last-wins and the cap");
}

fn t8() -> TestResult {
  let r = robots_parse("User-agent: a\nCrawl-delay: 5\nUser-agent: b\nDisallow: /\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = robots_group_count(&x) == 2;
      if !opt_int_is(robots_crawl_delay(&x, 0), 5) { ok = false; }
      if !opt_int_none(robots_crawl_delay(&x, 1)) { ok = false; }
      if robots_rule_count(&x, 1) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "Crawl-delay is per group and does not leak");
}

fn t9() -> TestResult {
  let r = robots_parse("User-agent: *\nDisallow: /x\nSitemap: https://a/s.xml\nSitemap: HTTP://b/s.xml\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = robots_sitemap_count(&x) == 2;
      if !streq(robots_sitemap(&x, 0), "https://a/s.xml") { ok = false; }
      if !streq(robots_sitemap(&x, 1), "HTTP://b/s.xml") { ok = false; }
      if robots_rule_count(&x, 0) != 1 { ok = false; }
      if robots_group_count(&x) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "Sitemaps are recorded separately, in order, verbatim");
}

fn t10() -> TestResult {
  let r = robots_parse("Sitemap: https://a/s.xml\nUser-agent: *\nDisallow: /\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = robots_sitemap_count(&x) == 1;
      if robots_group_count(&x) != 1 { ok = false; }
      if robots_rule_count(&x, 0) != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a Sitemap before any User-agent is document-global");
}

fn t11() -> TestResult {
  var ok = err_is("Disallow: /x", "robots: rule before any user-agent: Disallow: /x");
  if !err_is("Allow: /x", "robots: rule before any user-agent: Allow: /x") { ok = false; }
  if !err_is("Crawl-delay: 5", "robots: rule before any user-agent: Crawl-delay: 5") { ok = false; }
  if !err_is("# c\n  Disallow: /x  ", "robots: rule before any user-agent: Disallow: /x") { ok = false; }
  return assert(ok, "Allow/Disallow/Crawl-delay before any User-agent are Err");
}

fn t12() -> TestResult {
  var ok = err_is("User-agent:", "robots: empty user-agent token: User-agent:");
  if !err_is("User-agent:   ", "robots: empty user-agent token: User-agent:") { ok = false; }
  if !err_is("User-agent:\t", "robots: empty user-agent token: User-agent:") { ok = false; }
  if !err_is("User-agent: # comment", "robots: empty user-agent token: User-agent:") { ok = false; }
  return assert(ok, "an empty User-agent token is Err");
}

fn t13() -> TestResult {
  var ok = err_is("User-agent: *\nCrawl-delay: abc", "robots: bad crawl-delay: abc");
  if !err_is("User-agent: *\nCrawl-delay: -1", "robots: bad crawl-delay: -1") { ok = false; }
  if !err_is("User-agent: *\nCrawl-delay: 1.5", "robots: bad crawl-delay: 1.5") { ok = false; }
  if !err_is("User-agent: *\nCrawl-delay: 5s", "robots: bad crawl-delay: 5s") { ok = false; }
  if !err_is("User-agent: *\nCrawl-delay:", "robots: bad crawl-delay: ") { ok = false; }
  if !err_is("User-agent: *\nCrawl-delay: 2147483648", "robots: bad crawl-delay: 2147483648") { ok = false; }
  if !err_is("User-agent: *\nCrawl-delay: 99999999999999999999", "robots: bad crawl-delay: 99999999999999999999") { ok = false; }
  return assert(ok, "a non-canonical or out-of-range Crawl-delay is Err");
}

fn t14() -> TestResult {
  var ok = err_is("User-agent: *\rDisallow: /", "robots: control byte in input");
  if !err_is("User-agent: \u{007F}x", "robots: control byte in input") { ok = false; }
  if !err_is("# comment \u{0001}", "robots: control byte in input") { ok = false; }
  if !err_is("User-agent: \u{000B}x", "robots: control byte in input") { ok = false; }
  if !err_is("\u{001F}", "robots: control byte in input") { ok = false; }
  return assert(ok, "lone CR, DEL and C0 control bytes are Err");
}

fn t15() -> TestResult {
  var ok = robots_path_matches("/fish", "/fish");
  if !robots_path_matches("/fish", "/fish.html") { ok = false; }
  if !robots_path_matches("/fish", "/fish/salmon.html") { ok = false; }
  if !robots_path_matches("/fish", "/fishheads") { ok = false; }
  if robots_path_matches("/fish", "/Fish") { ok = false; }
  if robots_path_matches("/fish", "/") { ok = false; }
  if !robots_path_matches("/", "/anything") { ok = false; }
  return assert(ok, "path matching: case-sensitive prefix semantics");
}

fn t16() -> TestResult {
  var ok = robots_path_matches("/*.php", "/index.php");
  if !robots_path_matches("/*.php", "/a/b/index.php") { ok = false; }
  if robots_path_matches("/*.php", "/index.html") { ok = false; }
  if !robots_path_matches("/fish*", "/fish") { ok = false; }
  if !robots_path_matches("/a*b*c", "/aXbYc") { ok = false; }
  if robots_path_matches("/a*b*c", "/aXc") { ok = false; }
  if !robots_path_matches("/*", "/") { ok = false; }
  if robots_path_matches("/*", "") { ok = false; }
  return assert(ok, "path matching: * matches any byte run, including empty");
}

fn t17() -> TestResult {
  var ok = robots_path_matches("/fish$", "/fish");
  if robots_path_matches("/fish$", "/fish.html") { ok = false; }
  if robots_path_matches("/fish$", "/fish/") { ok = false; }
  if !robots_path_matches("/fish*$", "/fishheads") { ok = false; }
  if !robots_path_matches("/fish*$", "/fish/heads") { ok = false; }
  if !robots_path_matches("$", "") { ok = false; }
  if robots_path_matches("$", "/") { ok = false; }
  if !robots_path_matches("/fish$$", "/fish$") { ok = false; }
  if robots_path_matches("/fish$$", "/fish") { ok = false; }
  if !robots_path_matches("/x$y", "/x$y") { ok = false; }
  if robots_path_matches("/x$y", "/xay") { ok = false; }
  return assert(ok, "path matching: trailing $ anchors, other $ is literal");
}

fn t18() -> TestResult {
  let r = robots_parse("User-agent: *\nDisallow: /\nAllow: /public\nAllow: /public/deep\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = !robots_is_allowed(&x, "*", "/");
      if robots_is_allowed(&x, "*", "/publ") { ok = false; }
      if !robots_is_allowed(&x, "*", "/public") { ok = false; }
      if !robots_is_allowed(&x, "*", "/public/x") { ok = false; }
      if !robots_is_allowed(&x, "*", "/public/deep/x") { ok = false; }
      if robots_is_allowed(&x, "*", "/private") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = robots_parse("User-agent: *\nDisallow: /*\nAllow: /public\n");
  match r2 {
    Ok(y) => {
      if !robots_is_allowed(&y, "*", "/public/x") { ok = false; }
      if robots_is_allowed(&y, "*", "/other") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "is_allowed uses the longest matching pattern");
}

fn t19() -> TestResult {
  let r1 = robots_parse("User-agent: *\nDisallow: /same\nAllow: /same\n");
  var ok = false;
  match r1 {
    Ok(x1) => {
      ok = robots_is_allowed(&x1, "*", "/same");
    },
    Err(_) => { ok = false; },
  }
  let r2 = robots_parse("User-agent: *\nAllow: /same\nDisallow: /same\n");
  match r2 {
    Ok(x2) => {
      if !robots_is_allowed(&x2, "*", "/same") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "equal-length ties: Allow wins in either source order");
}

fn t20() -> TestResult {
  let r = robots_parse("User-agent: bot\nDisallow: /\nUser-agent: googlebot\nAllow: /\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = robots_matching_group(&x, "Googlebot/2.1") == 1;
      if !robots_is_allowed(&x, "Googlebot/2.1", "/x") { ok = false; }
      if robots_is_allowed(&x, "bot/1.0", "/x") { ok = false; }
      if robots_matching_group(&x, "BOT/1.0") != 0 { ok = false; }
      if !robots_is_allowed(&x, "otherbot/1.0", "/x") { ok = false; }
      if robots_matching_group(&x, "Googlebot-Image/1.0") != 1 { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "group selection: longest case-insensitive token prefix wins");
}

fn t21() -> TestResult {
  let r1 = robots_parse("User-agent: bot\nDisallow: /bot-only\nUser-agent: *\nDisallow: /all\n");
  var ok = false;
  match r1 {
    Ok(x1) => {
      ok = robots_is_allowed(&x1, "bot/1", "/bot-only") == false;
      if !robots_is_allowed(&x1, "bot/1", "/all") { ok = false; }
      if robots_is_allowed(&x1, "other", "/all") { ok = false; }
      if !robots_is_allowed(&x1, "other", "/bot-only") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = robots_parse("User-agent: *\nDisallow: /a\nUser-agent: *\nDisallow: /b\n");
  match r2 {
    Ok(x2) => {
      if robots_matching_group(&x2, "x") != 0 { ok = false; }
      if !robots_is_allowed(&x2, "x", "/b") { ok = false; }
      if robots_is_allowed(&x2, "x", "/a") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a specific group replaces '*' and the first duplicate group wins");
}

fn t22() -> TestResult {
  let r = robots_parse("# top\nuser-agent:\t*\nDisallow: /private\nAllow: /private/public\n\nUSER-AGENT: BadBot\nCrawl-delay: 10\nDisallow: /\nSitemap: https://example.com/sitemap.xml\n");
  var ok = false;
  match r {
    Ok(x) => {
      let got = robots_emit(&x);
      let want = "User-agent: *\nDisallow: /private\nAllow: /private/public\n\nUser-agent: BadBot\nDisallow: /\nCrawl-delay: 10\n\nSitemap: https://example.com/sitemap.xml";
      ok = streq(got, want);
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "canonical emit: groups, blank-line blocks, sitemap last, LF only");
}

fn t23() -> TestResult {
  let r = robots_parse("Sitemap: https://a/s.xml\nUser-agent: a\nUser-agent: b\nAllow: /x\nDisallow: /y\nCrawl-delay: 4\nUser-agent: *\nDisallow:\n");
  var ok = false;
  match r {
    Ok(x) => {
      let e1 = robots_emit(&x);
      let r2 = robots_parse(e1);
      match r2 {
        Ok(y) => {
          ok = robots_group_count(&y) == 2;
          if !a_is(&y, 0, 0, "a") { ok = false; }
          if !a_is(&y, 0, 1, "b") { ok = false; }
          if !d_path(&y, 0, 0, "/x") { ok = false; }
          if !d_allow(&y, 0, 0, true) { ok = false; }
          if !d_path(&y, 0, 1, "/y") { ok = false; }
          if !d_allow(&y, 0, 1, false) { ok = false; }
          if !opt_int_is(robots_crawl_delay(&y, 0), 4) { ok = false; }
          if robots_rule_count(&y, 1) != 1 { ok = false; }
          if !d_path(&y, 1, 0, "") { ok = false; }
          if robots_sitemap_count(&y) != 1 { ok = false; }
          let e2 = robots_emit(&y);
          if !streq(e1, e2) { ok = false; }
        },
        Err(_) => { ok = false; },
      }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "emit then parse round-trips and emit is idempotent");
}

fn t24() -> TestResult {
  let r = robots_parse("");
  var ok = false;
  match r {
    Ok(x) => {
      ok = robots_group_count(&x) == 0;
      if robots_sitemap_count(&x) != 0 { ok = false; }
      if !streq(robots_emit(&x), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let r2 = robots_parse("# only a comment\n\n   \n# another\n");
  match r2 {
    Ok(y) => {
      if robots_group_count(&y) != 0 { ok = false; }
      if !streq(robots_emit(&y), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  let empty = robots_new();
  if robots_group_count(&empty) != 0 { ok = false; }
  if !streq(robots_emit(&empty), "") { ok = false; }
  return assert(ok, "empty and comment-only documents parse to empty and emit \"\"");
}

fn t25() -> TestResult {
  let r = robots_parse("User-agent: *\nDisallow: /x\nCrawl-delay: 2\nSitemap: https://a/s.xml\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = streq(robots_agent(&x, -1, 0), "");
      if !streq(robots_agent(&x, 9, 0), "") { ok = false; }
      if !streq(robots_agent(&x, 0, 5), "") { ok = false; }
      if !streq(robots_rule_path(&x, 0, 5), "") { ok = false; }
      if robots_rule_allow(&x, 0, 5) { ok = false; }
      if robots_agent_count(&x, 9) != 0 { ok = false; }
      if robots_rule_count(&x, 5) != 0 { ok = false; }
      if !opt_int_none(robots_crawl_delay(&x, 5)) { ok = false; }
      if !streq(robots_sitemap(&x, 5), "") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "out-of-range accessors return \"\"/false/None and never trap");
}

fn t26() -> TestResult {
  var ok = err_is("Sitemap: /sitemap.xml", "robots: sitemap must be an absolute http or https URL: /sitemap.xml");
  if !err_is("Sitemap: ftp://host/s.xml", "robots: sitemap must be an absolute http or https URL: ftp://host/s.xml") { ok = false; }
  if !err_is("Sitemap: https://", "robots: sitemap must be an absolute http or https URL: https://") { ok = false; }
  if !err_is("Sitemap:", "robots: sitemap must be an absolute http or https URL: ") { ok = false; }
  let r = robots_parse("Sitemap: HTTP://X/s.xml\n");
  match r {
    Ok(x) => {
      if robots_sitemap_count(&x) != 1 { ok = false; }
      if !streq(robots_sitemap(&x, 0), "HTTP://X/s.xml") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "a Sitemap must be an absolute http/https URL and is kept verbatim");
}

fn t27() -> TestResult {
  var ok = err_is("Foo: bar", "robots: unknown field: Foo");
  if !err_is("Host: example.com", "robots: unknown field: Host") { ok = false; }
  if !err_is("FOO: bar", "robots: unknown field: FOO") { ok = false; }
  if !err_is("User-agent *", "robots: missing ':' in line: User-agent *") { ok = false; }
  if !err_is("justtext", "robots: missing ':' in line: justtext") { ok = false; }
  if !err_is(": x", "robots: missing field name in line: : x") { ok = false; }
  return assert(ok, "unknown fields, missing colon and missing name are Err");
}

fn t28() -> TestResult {
  let r = robots_parse("User-agent: * # c\nDisallow: /a#b\nAllow: /a/b # tail\n");
  var ok = false;
  match r {
    Ok(x) => {
      ok = a_is(&x, 0, 0, "*");
      if robots_rule_count(&x, 0) != 2 { ok = false; }
      if !d_path(&x, 0, 0, "/a") { ok = false; }
      if !d_path(&x, 0, 1, "/a/b") { ok = false; }
    },
    Err(_) => { ok = false; },
  }
  return assert(ok, "# starts a comment anywhere on a line and is never data");
}

fn t29() -> TestResult {
  var ok = robots_agent_matches("*", "anything");
  if !robots_agent_matches("*", "") { ok = false; }
  if !robots_agent_matches("googlebot", "Googlebot/2.1") { ok = false; }
  if !robots_agent_matches("googlebot", "Googlebot-Image/1.0") { ok = false; }
  if !robots_agent_matches("GoogleBot", "googlebot") { ok = false; }
  if !robots_agent_matches("googlebot", "googlebot") { ok = false; }
  if robots_agent_matches("bot", "Googlebot") { ok = false; }
  if robots_agent_matches("googlebot", "bot") { ok = false; }
  if robots_agent_matches("", "x") { ok = false; }
  if robots_agent_matches("*xx", "anything") { ok = false; }
  return assert(ok, "agent matching: '*' always, otherwise a case-insensitive prefix");
}

fn main() -> Int {
  io.println("=== xiom.robots conformance tests ===");
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
  let r19 = t19();
  if r19.passed { io.println("  [PASS] " + r19.name); } else { io.println("  [FAIL] " + r19.name); failed = failed + 1; }
  let r20 = t20();
  if r20.passed { io.println("  [PASS] " + r20.name); } else { io.println("  [FAIL] " + r20.name); failed = failed + 1; }
  let r21 = t21();
  if r21.passed { io.println("  [PASS] " + r21.name); } else { io.println("  [FAIL] " + r21.name); failed = failed + 1; }
  let r22 = t22();
  if r22.passed { io.println("  [PASS] " + r22.name); } else { io.println("  [FAIL] " + r22.name); failed = failed + 1; }
  let r23 = t23();
  if r23.passed { io.println("  [PASS] " + r23.name); } else { io.println("  [FAIL] " + r23.name); failed = failed + 1; }
  let r24 = t24();
  if r24.passed { io.println("  [PASS] " + r24.name); } else { io.println("  [FAIL] " + r24.name); failed = failed + 1; }
  let r25 = t25();
  if r25.passed { io.println("  [PASS] " + r25.name); } else { io.println("  [FAIL] " + r25.name); failed = failed + 1; }
  let r26 = t26();
  if r26.passed { io.println("  [PASS] " + r26.name); } else { io.println("  [FAIL] " + r26.name); failed = failed + 1; }
  let r27 = t27();
  if r27.passed { io.println("  [PASS] " + r27.name); } else { io.println("  [FAIL] " + r27.name); failed = failed + 1; }
  let r28 = t28();
  if r28.passed { io.println("  [PASS] " + r28.name); } else { io.println("  [FAIL] " + r28.name); failed = failed + 1; }
  let r29 = t29();
  if r29.passed { io.println("  [PASS] " + r29.name); } else { io.println("  [FAIL] " + r29.name); failed = failed + 1; }
  if failed == 0 {
    io.println("xiom.robots: all tests passed");
  } else {
    io.println("xiom.robots: tests failed");
  }
  return failed;
}
