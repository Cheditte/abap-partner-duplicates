# Changelog

## 0.4.0 — unreleased

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
