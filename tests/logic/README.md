# Transpiled logic checks

Run `npm run test:logic` from the repository root after `npm ci --ignore-scripts`.

The script reads the current `src/zche_dupl_find.prog.abap`, extracts its shared interface, pure local classes and test section, and builds an isolated global-class wrapper. Production method bodies and existing test bodies are copied without rewriting them. The wrapper contains:

- `LCX_ERROR` and shared `LIF_DUPL` types/constants;
- `LCL_TEXT` methods `GET` and `NUM`;
- the complete `LCL_TAX_ID`, `LCL_NORMALIZER` and `LCL_MATCHER` classes;
- `LCL_FINDER` methods `APPLY_DECISIONS` and `ADD_TAX_ID_FINDINGS`;
- `LCL_APP` method `CHECK_SETTINGS`;
- the report's `LTC_*` test classes and required forward declarations.

SAP I/O methods are excluded. Simplified local character types stand in for BP identifiers, roles, groupings and tax categories. The library provides other standard types and `CL_ABAP_UNIT_ASSERT`; a harness-only `CL_AUNIT_ASSERT` alias inherits that implementation so the report can keep classic test syntax. These fixtures are outside installable `src/` and must never be imported into SAP.

The transpiler and runtime are pinned to `2.14.15`; `open-abap/open-abap-core` is pinned to `f735eed652288c8ed85b3083a187cc3e7e4a9b97`. The script verifies the configured revision and the checkout revision reported by the transpiler. Git/network access is required for that public dependency.

Each run creates a new ignored `.logic-tests/runs/run-*` folder. It prints the evidence path and saves the report's SHA-256/expected test count, extracted source, transpiler configuration, generated code, build log and test log. Existing run folders are not deleted. The script fails if extraction fails, the build/test process fails, no tests are found, or the reported test count differs from the extracted method count.

This is JavaScript execution of transpiled ABAP logic, not SAP ABAP Unit execution. Numeric precision, rounding, overflow, code-page and runtime behavior can differ. It does not validate real authority checks, SQL/validity selection, `INDX`, locks/commit, SALV events or selection screens. Complete the SAP acceptance checklist before release.

The current v0.4 local suite contains 39 test methods, including regressions for incomplete addresses, alphanumeric identifiers, crowded blocks, explicit Turkish checksum checks and the required key date. All 39 completed in the transpiled harness. This is separate from the historical 30 SAP-executed v0.3 tests.
