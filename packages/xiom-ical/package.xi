// XIOM -- xiom.ical package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// RFC 5545-subset iCalendar codec: CRLF folding/unfolding, content-line
// parsing, TEXT escaping, BEGIN/END component trees and a minimal VCALENDAR
// builder. xiom.std is the standard library: a platform dependency, excluded
// from the registry install closure. The module imports xiom.string,
// xiom.string.builder and xiom.string.compare from it; the tests additionally
// use xiom.test and xiom.io.

package xiom_ical {
  name: "xiom.ical";
  version: "0.1.0";
  description: "RFC 5545-subset iCalendar codec: folding, content lines, TEXT escaping, component trees";
  categories: ["data"];
  keywords: ["ical", "calendar", "ics", "format"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.ical"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
