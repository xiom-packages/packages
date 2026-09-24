// XIOM -- xiom.useragent conformance tests (19 checks)
// Port task: prove the pure-XIOM xiom.useragent module against its SPEC.md.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Coverage map: see SPEC.md section 5. Every check is a named
// assert(cond, "name") call and main returns the failure count (0 = green).
// All Str equality goes through streq (str_compare): BUG 17 lowers `==` on
// Str values read from Vec[Str] elements to a pointer comparison, and the
// suite stays on the safe path even though it uses no Vec at all.

module useragent_tests
use xiom.io; use xiom.test; use xiom.useragent;
use xiom.string.compare;

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// --------------------------------------------------
//  Realistic User-Agent fixtures
// --------------------------------------------------

fn ua_chrome_win() -> Str {
  return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";
}

fn ua_edge_win() -> Str {
  return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36 Edg/120.0.0.0";
}

fn ua_opera_win() -> Str {
  return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36 OPR/105.0.0.0";
}

fn ua_safari_mac() -> Str {
  return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Safari/605.1.15";
}

fn ua_firefox_linux() -> Str {
  return "Mozilla/5.0 (X11; Linux x86_64; rv:121.0) Gecko/20100101 Firefox/121.0";
}

fn ua_android_chrome() -> Str {
  return "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36";
}

fn ua_iphone() -> Str {
  return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Mobile/15E148 Safari/604.1";
}

fn ua_ipad() -> Str {
  return "Mozilla/5.0 (iPad; CPU OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";
}

fn ua_curl() -> Str {
  return "curl/8.4.0";
}

fn ua_requests() -> Str {
  return "python-requests/2.31.0";
}

fn ua_wget() -> Str {
  return "Wget/1.21.3 (linux-gnu)";
}

fn ua_googlebot() -> Str {
  return "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)";
}

fn ua_headless() -> Str {
  return "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) HeadlessChrome/120.0.0.0 Safari/537.36";
}

fn ua_windows_phone() -> Str {
  return "Mozilla/5.0 (Mobile; Windows Phone 8.1; Android 4.0; ARM; Trident/7.0; Touch; rv:11.0) like iPhone OS 7_0_3 Mac OS X AppleWebKit/537 (KHTML, like Gecko) Mobile Safari/537";
}

// --------------------------------------------------
//  Checks
// --------------------------------------------------

fn t1() -> TestResult {
  let ua = ua_chrome_win();
  var ok = streq(ua_browser(ua), "Chrome");
  if !streq(ua_version(ua), "120.0.0.0") { ok = false; }
  if !streq(ua_os(ua), "Windows") { ok = false; }
  if ua_is_bot(ua) { ok = false; }
  if ua_is_mobile(ua) { ok = false; }
  return assert(ok, "chrome on windows: browser, version, os, not bot/mobile");
}

fn t2() -> TestResult {
  let ua = ua_edge_win();
  var ok = streq(ua_browser(ua), "Edge");
  if !streq(ua_version(ua), "120.0.0.0") { ok = false; }
  if !streq(ua_os(ua), "Windows") { ok = false; }
  if ua_is_bot(ua) { ok = false; }
  return assert(ok, "edge beats chrome: Edg/ wins over the embedded Chrome/118");
}

fn t3() -> TestResult {
  let ua = ua_opera_win();
  var ok = streq(ua_browser(ua), "Opera");
  if !streq(ua_version(ua), "105.0.0.0") { ok = false; }
  if !streq(ua_os(ua), "Windows") { ok = false; }
  return assert(ok, "opera beats chrome: OPR/ wins over the embedded Chrome/118");
}

fn t4() -> TestResult {
  let ua = ua_safari_mac();
  var ok = streq(ua_browser(ua), "Safari");
  if !streq(ua_version(ua), "605.1.15") { ok = false; }
  if !streq(ua_os(ua), "macOS") { ok = false; }
  if ua_is_bot(ua) { ok = false; }
  if ua_is_mobile(ua) { ok = false; }
  return assert(ok, "safari on macos: no chrome token, mac os x detected");
}

fn t5() -> TestResult {
  let ua = ua_android_chrome();
  var ok = streq(ua_browser(ua), "Chrome");
  if !streq(ua_version(ua), "120.0.0.0") { ok = false; }
  if !streq(ua_os(ua), "Android") { ok = false; }
  if !ua_is_mobile(ua) { ok = false; }
  if ua_is_bot(ua) { ok = false; }
  return assert(ok, "android chrome: chrome beats safari, android and mobile");
}

fn t6() -> TestResult {
  let ua = ua_firefox_linux();
  var ok = streq(ua_browser(ua), "Firefox");
  if !streq(ua_version(ua), "121.0") { ok = false; }
  if !streq(ua_os(ua), "Linux") { ok = false; }
  if ua_is_bot(ua) { ok = false; }
  if ua_is_mobile(ua) { ok = false; }
  return assert(ok, "firefox on linux: browser, version, os, not bot/mobile");
}

fn t7() -> TestResult {
  let ua = ua_iphone();
  var ok = streq(ua_browser(ua), "Safari");
  if !streq(ua_version(ua), "604.1") { ok = false; }
  if !streq(ua_os(ua), "iOS") { ok = false; }
  if !ua_is_mobile(ua) { ok = false; }
  if ua_is_bot(ua) { ok = false; }
  return assert(ok, "iphone safari: iOS and mobile, version after Safari/");
}

fn t8() -> TestResult {
  let ua = ua_ipad();
  var ok = streq(ua_browser(ua), "Safari");
  if !streq(ua_os(ua), "iOS") { ok = false; }
  if !ua_is_mobile(ua) { ok = false; }
  if ua_is_bot(ua) { ok = false; }
  return assert(ok, "ipad: iOS and mobile tokens detected");
}

fn t9() -> TestResult {
  var ok = streq(ua_browser(ua_curl()), "curl");
  if !ua_is_bot(ua_curl()) { ok = false; }
  if !streq(ua_version(ua_curl()), "8.4.0") { ok = false; }
  if !streq(ua_browser(ua_requests()), "python-requests") { ok = false; }
  if !ua_is_bot(ua_requests()) { ok = false; }
  if !streq(ua_version(ua_requests()), "2.31.0") { ok = false; }
  if ua_is_mobile(ua_requests()) { ok = false; }
  return assert(ok, "curl and python-requests are scripted clients (bots)");
}

fn t10() -> TestResult {
  let ua = ua_wget();
  var ok = streq(ua_browser(ua), "wget");
  if !ua_is_bot(ua) { ok = false; }
  if !streq(ua_version(ua), "1.21.3") { ok = false; }
  if !streq(ua_os(ua), "Linux") { ok = false; }
  return assert(ok, "wget: wget/ token is a bot, linux-gnu maps to Linux");
}

fn t11() -> TestResult {
  let ua = ua_googlebot();
  var ok = ua_is_bot(ua);
  if !streq(ua_browser(ua), "") { ok = false; }
  if !streq(ua_version(ua), "") { ok = false; }
  if !streq(ua_os(ua), "") { ok = false; }
  if ua_is_mobile(ua) { ok = false; }
  return assert(ok, "googlebot: bot with no browser, version or os token");
}

fn t12() -> TestResult {
  let ua = ua_headless();
  var ok = ua_is_bot(ua);
  if !streq(ua_browser(ua), "Chrome") { ok = false; }
  if !streq(ua_os(ua), "Linux") { ok = false; }
  return assert(ok, "headless chrome: headless token is a bot, chrome detected");
}

fn t13() -> TestResult {
  let spider = "Mozilla/5.0 (compatible; Baiduspider/2.0; +http://www.baidu.com/search/spider.html)";
  let slurp = "Mozilla/5.0 (compatible; Yahoo! Slurp; http://help.yahoo.com/help/us/ysearch/slurp)";
  let crawler = "ExampleCrawler/1.0 (+http://example.com/crawler)";
  var ok = ua_is_bot(spider);
  if !ua_is_bot(slurp) { ok = false; }
  if !ua_is_bot(crawler) { ok = false; }
  if !ua_is_bot("Mozilla/5.0 (compatible; bingbot/2.0)") { ok = false; }
  if ua_is_bot(ua_chrome_win()) { ok = false; }
  return assert(ok, "bot tokens: spider, slurp, crawler and bot match");
}

fn t14() -> TestResult {
  var ok = streq(ua_version(ua_chrome_win()), "120.0.0.0");
  if !streq(ua_version(ua_firefox_linux()), "121.0") { ok = false; }
  if !streq(ua_version(ua_curl()), "8.4.0") { ok = false; }
  if !streq(ua_version(ua_googlebot()), "") { ok = false; }
  return assert(ok, "version extraction pinned for chrome, firefox, curl and unknown");
}

fn t15() -> TestResult {
  let ua = "CustomClient/1.2.3";
  var ok = streq(ua_browser(ua), "");
  if !streq(ua_version(ua), "") { ok = false; }
  if !streq(ua_os(ua), "") { ok = false; }
  if ua_is_bot(ua) { ok = false; }
  if ua_is_mobile(ua) { ok = false; }
  return assert(ok, "unknown UA: browser, version and os empty, no flags");
}

fn t16() -> TestResult {
  let ua = "";
  var ok = streq(ua_browser(ua), "");
  if !streq(ua_version(ua), "") { ok = false; }
  if !streq(ua_os(ua), "") { ok = false; }
  if ua_is_bot(ua) { ok = false; }
  if ua_is_mobile(ua) { ok = false; }
  if !streq(ua_version("curl/8"), "") { ok = false; }
  return assert(ok, "empty UA is unknown everywhere; bare integer is not a version");
}

fn t17() -> TestResult {
  let ua = "mOzIlLa/5.0 (WiNdOwS nT 10.0; Win64; x64) aPpLeWeBkIt/537.36 (KHTML, like Gecko) cHrOmE/120.0.0.0 sAfArI/537.36";
  var ok = streq(ua_browser(ua), "Chrome");
  if !streq(ua_version(ua), "120.0.0.0") { ok = false; }
  if !streq(ua_os(ua), "Windows") { ok = false; }
  if !ua_is_bot("CURL/8.4.0") { ok = false; }
  if !streq(ua_browser("WGET/1.21.3"), "wget") { ok = false; }
  if !streq(ua_os("X11; LINUX x86_64"), "Linux") { ok = false; }
  if !ua_is_mobile("IPHONE; CPU IPHONE OS 17_1") { ok = false; }
  return assert(ok, "mixed-case tokens match through the lowercased copy");
}

fn t18() -> TestResult {
  var ok = streq(ua_version("curl/unknown"), "");
  if !ua_is_bot("curl/unknown") { ok = false; }
  if !streq(ua_version("Firefox/121.0"), "121.0") { ok = false; }
  if !streq(ua_browser("Edg/120.0.0.0"), "Edge") { ok = false; }
  return assert(ok, "version scan needs a dotted number after the token");
}

fn t19() -> TestResult {
  let ua = ua_windows_phone();
  var ok = ua_is_mobile(ua);
  if !streq(ua_browser(ua), "Safari") { ok = false; }
  if !streq(ua_os(ua), "Android") { ok = false; }
  return assert(ok, "windows phone: mobile token, android outranks the rest");
}

fn main() -> Int {
  io.println("=== xiom.useragent conformance tests ===");
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
  if failed == 0 {
    io.println("xiom.useragent: all tests passed");
  } else {
    io.println("xiom.useragent: tests failed");
  }
  return failed;
}
