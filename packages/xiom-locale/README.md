# xiom-locale

> **Status:** PLACEHOLDER — reserved, spec pending. No implementation yet.
> **Scope:** Locale identifiers: BCP-47 parsing, canonicalization, matching, and fallback resolution.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `locale_id` | Parse, validate, and canonicalize BCP-47 language tags. |
| `locale_matcher` | Best-fit locale matching between requested and available locales. |
| `locale_resolve` | Resolve locale fallback chains with default data. |
| `locale_registry` | Static registry of known locales and their metadata. |
