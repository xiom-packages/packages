# xiom.monitoring

Prometheus / OpenMetrics **text exposition format parser** in pure XIOM
(no FFI). It turns an exposition payload -- the text returned by the
`/metrics` endpoint of a Prometheus client, or an OpenMetrics document --
into a flat, fully indexed value with families, samples, labels, values,
timestamps and exemplars.

> **Status:** implemented and covered by 24 conformance tests
> (`tests/test_conformance.xi`, run with
> `.\scripts\port.ps1 -Package xiom.monitoring`). Version 0.1.0.

## Scope (honest)

Implemented:

- both line-oriented formats: Prometheus `text/plain; version=0.0.4` and
  OpenMetrics `application/openmetrics-text`;
- `# HELP` (escape-aware), `# TYPE` (all eight metric types), `# UNIT`,
  `# EOF`, comments and blank lines;
- sample lines with labels, the bare form, integer/decimal/exponent values,
  `+Inf` / `-Inf` / `NaN`, optional millisecond timestamps;
- family grouping by metric name, including `_bucket` / `_sum` / `_count`
  resolution for declared histograms and summaries, and `_created` as a
  plain sample;
- histogram `le` validation and the strictly-increasing bucket-boundary
  check; summary quantile validation;
- OpenMetrics exemplars (` # {trace_id="..."} 1.5 1500000000000`);
- byte-exact spans (name/label/value/timestamp offsets) and deterministic
  errors with byte offsets;
- strict (`mon_parse`) and error-collecting (`mon_parse_lenient`) document
  walks, plus `mon_parse_line` for single-line use.

Not implemented (out of scope): HTTP scraping/transports, protobuf
exposition, metric rendering, timezone handling, UTF-8 validation, and the
"soft" consistency checks listed in SPEC.md section 7 (cumulative counts,
`+Inf` bucket presence, quantile ordering).

## Usage

```xiom
use xiom.monitoring;
use xiom.io;

let text =
  "# HELP http_requests_total Total requests.\n" +
  "# TYPE http_requests_total counter\n" +
  "http_requests_total{method=\"get\",code=\"200\"} 1027 1395066363000\n" +
  "# EOF\n";

let doc = mon_parse_lenient(text);

// families
let f = mon_doc_family_index(&doc, "http_requests_total");
if f >= 0 {
  io.println(mon_doc_family_type(&doc, f));      // counter
  io.println(mon_doc_family_help_text(&doc, f)); // Total requests.
}

// samples
let i = mon_doc_family_sample_at(&doc, f, 0);
io.println(mon_doc_sample_value_raw(&doc, i));   // 1027
io.println(mon_doc_sample_label_lookup(&doc, i, "code")); // 200
if mon_doc_sample_has_timestamp(&doc, i) {
  io.println("ts");
}
```

Strict parsing returns the first error:

```xiom
let r = mon_parse(text);
match r {
  Ok(d) => { io.println("ok"); },
  Err(e) => { io.println(e); },  // "monitoring: <reason> at <offset>"
}
```

Lenient parsing collects everything and keeps the valid rows:

```xiom
let bad = "# TYPE x counter\n# TYPE x gauge\nx 1\n";
let d = mon_parse_lenient(bad);
// mon_doc_error_count(&d) == 1
// mon_doc_error_msg(&d, 0) == "monitoring: duplicate TYPE for \"x\" at 24"
// mon_doc_sample_count(&d) == 1
```

Single line and single value:

```xiom
let line = mon_parse_line("m{a=\"1\",b=\"x\\\"y\"} 1.5 1500");
let v = mon_parse_value("1.5e-3");
let f = mon_parse_float("+Inf");
```

### Value model

Finite values are stored as `mant * 10^exp` (signed Int mantissa, Int
exponent, plus an overflow flag) so no `Vec[Float64]` is needed and no
binary floating point error is introduced by parsing:

- `mon_doc_sample_value_micro` scales to integer micro-units (1e-6),
  truncating toward zero and saturating at the Int range limits;
- `mon_doc_sample_value_float` returns a scalar `Float64` when floats are
  wanted;
- `+Inf` / `-Inf` / `NaN` are kind codes 1/2/3; the micro accessor returns
  0 for them, so check the kind (`mon_doc_sample_value_kind`).

### Histograms and summaries

```xiom
let hist =
  "# TYPE h histogram\n" +
  "h_bucket{le=\"0.5\"} 1\n" +
  "h_bucket{le=\"1\"} 2\n" +
  "h_bucket{le=\"+Inf\"} 3\n" +
  "h_sum 4.5\nh_count 3\n";

let d = mon_parse_lenient(hist);
// all five samples attach to family "h"; sample parts are
// 1, 1, 1, 2, 3; le is exposed via mon_doc_sample_le_micro /
// mon_doc_sample_le_inf / mon_doc_sample_le_raw.
```

Bucket boundaries must be strictly increasing; duplicates and regressions
are errors (`duplicate bucket le`, `bucket le out of order`), as are a
missing `le` on a declared histogram (`bucket without le`), a non-finite
`le` (`bad le`), a plain histogram sample, and a summary sample without
`quantile`. See `SPEC.md` for the full error catalog.

## Files

| file | purpose |
|------|---------|
| `package.xi` | package manifest (`xiom.monitoring` 0.1.0) |
| `src/monitoring.xi` | parser module |
| `tests/test_conformance.xi` | 24 self-contained conformance tests |
| `SPEC.md` | grammar, semantics, error catalog |
| `README.md` | this file |

## Testing

From the repository root:

```powershell
.\scripts\port.ps1 -Package xiom.monitoring
```

Expected tail: `port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.
