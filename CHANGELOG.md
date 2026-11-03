# Changelog

## 0.4.0 — unreleased

### Review and onboarding — 2026-11-03

- Add a BP-number selection range so the first scan can use a few explicit partners. It restricts both sides of the candidate set before detail reads.
- Reject malformed email keys and refuse a run when every matching/check option is disabled. Add three logic regressions (42 methods total).
- Keep full ALV explanations instead of truncating them at 255 characters; report SALV creation failure as a background job error.
- Fit all source lines into 72 columns and extend the classic gate to enforce it. Accept classic empty table-body assignments; add the twelfth gate regression.
- Replace long landing pages with goal-oriented EN/TR READMEs, four process diagrams, step-by-step EN/TR guides and separate technical references. Document Fixed point arithmetic, permissions, immediate decision saves and dynamic job dates.
- Add security/data-handling guidance, a validation record, a sanitized bug-report form and CI checks for relative documentation links.

The new BP SQL filter, GUI/long-text behavior and background failure path still require SAP acceptance; no new SAP runtime claim is made.

This revision retains classic ABAP 7.00 syntax; actual 7.00 runtime/API support still requires SAP validation. It has local static and JavaScript-transpiled logic checks; it has not been activated or executed in SAP.

- Keep classic ABAP declarations, CREATE OBJECT, intermediate result variables, classic table/string statements and CL_AUNIT_ASSERT tests. Add an AST/token compatibility gate and 11 gate tests for newer syntax forms that the versioned parser can miss.
- Require the custom `ZCHE_DUPL` authorization object before scanning or saving decisions. Check BP authorization groups before reading identifying details; separately require full-identifier and decision permissions.
- Add a reference date, evaluated at midnight UTC, and filter valid roles, address assignments/records, communication and bank details. Apply country/role eligibility before detailed reads.
- Require explicit opt-in for Turkish VKN/TCKN validation, disabled by default. Preserve letters in foreign tax identifiers during matching.
- Reject address evidence when the street is absent, even when a house number exists.
- Bound stored members of crowded keys to the configured maximum plus one; retain the exact count for skipped-key messages without repeatedly scanning growing member lists.
- Preserve the existing INDX decision format; add read/write error handling and release the lock on handled save failures.
- Reset ALV result rows before another scan. Include reference date/version in the run log.
- Add nine regression tests, a reproducible 39-test logic harness, pinned lint targets and GitHub Actions.

### Migration from 0.3

Create/transport the authorization object and assign reviewed roles before activating/using the report. Recheck existing variants: the key date and Turkish-check option are new. Current-only selection and corrected matching can change candidate counts. Existing decisions remain client-local; review old exclusions when underlying master data changes.

Complete the [SAP acceptance checks](CONTRIBUTING.md#sap-acceptance-checks), including actual authorization, validity queries, GUI interactions and concurrent INDX writes, before release.
