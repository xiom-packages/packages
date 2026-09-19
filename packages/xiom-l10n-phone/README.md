# xiom.l10n-phone

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** International phone number parsing, formatting, and validation (E.164 / ITU rules).
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `phone_parse` | Parse raw strings into structured phone numbers. |
| `phone_format` | Format numbers in national, international, and E.164 forms. |
| `phone_validate` | Validate numbers against country dial plans. |
| `phone_metadata` | Country dialing and numbering-plan metadata registry. |
