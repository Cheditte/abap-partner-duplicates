# Contributing

Keep duplicate detection explainable. A rule score is evidence, not a verified identity decision. Report concrete false positives/negatives with invented or sanitized inputs; do not upload production partner names, tax numbers, bank details, credentials or SAP dumps containing identifying data.

## Local checks

Use Node.js 22+, npm and Git:

```sh
npm ci --ignore-scripts
npm run test:gate
npm run lint
npm run test:logic
npm run check:docs
```

The npm manifest and lockfile pin abaplint CLI/core `2.120.92` and transpiler/runtime `2.14.15`. The logic library revision is fixed in `tests/logic/abap_transpile.json`. `lint:700` and `lint:758` run individual targets; both configs should keep the same rules. Dependency stand-ins are versioned in `.abaplint-deps/` and are deliberately incomplete.

The default lint command first runs `check:classic`. Its AST-based nested-call check supplements v700 parsing, which can miss method calls used directly as actual arguments. Token/AST checks also reject inline declarations, constructor expressions, string templates/chaining, table expressions and empty keys. Physical source lines must fit 72 columns; classic table-body assignments remain allowed. Built-in function availability remains the versioned parser’s responsibility. `test:gate` tests rejection and false-positive cases; neither gate guarantees complete 7.00 runtime support.

GitHub Actions runs the same checks with read-only repository permissions. Passing static checks and JavaScript-transpiled tests does not establish SAP activation, old-release compatibility, authorization enforcement, database selection or GUI behavior.

When changing pure logic, add a regression with expected reasons and score, not just a row count. Include missing inputs, disabled rules, non-Turkish identifiers and crowded keys where relevant. Do not weaken authority checks or remove failure handling to make a test pass. Preserve classic ABAP 7.00 syntax: explicit declarations, intermediate result variables, CREATE OBJECT and classic string/table statements. Do not introduce inline declarations, constructor expressions, templates, table expressions, empty table keys or nested method-call arguments. Actual 7.00 runtime/API compatibility still requires SAP testing.

## SAP acceptance checks

Use an authorized DEV/test client and invented partners. Record the exact Git commit, SAP_BASIS release/SP, kernel, abapGit version or copy/paste route, test configuration and results. Record pending work honestly.

- [ ] Install into a clean program/package with Fixed point arithmetic enabled, activate, run ATC and the complete ABAP Unit suite. Validate every standard API on the claimed target release.
- [ ] Verify `S_PART` using exact values, ranges, exclusions and a blank selection. Both pair members must be in scope. Combine it with role/grouping/country filters; verify SQL scoping before detail reads.
- [ ] Create/transport `ZCHE_DUPL` with `ACTVT` and assign separate scan (`03`), full identifier (`16`) and decision (`02`) permissions. A missing object or missing scan permission must prevent scanning.
- [ ] Test BP authorization groups through `B_BUPA_GRP`, including blank groups. Verify that unauthorized partners are excluded before identifying/contact/tax/bank details are read, and cannot leak through ALV, reasons, skipped-block messages or spool.
- [ ] Review the privileged aggregate-read scope of activity `03` with Basis. It is not equivalent to all standard BP dialog bank/role/field-group checks; do not assign it to ordinary users whose permitted data scope is narrower.
- [ ] Confirm that a scan-only user cannot request unmasked identifiers and cannot save decisions. Test both the visible UI action and the save method's authority check.
- [ ] Check roles, addresses, bank and communication records before/on/after validity boundaries, including future, expired, initial/zero and overlapping records. Verify the documented key-date midnight-UTC convention with intraday data.
- [ ] Run mixed-country data with Turkish checksum validation off, then explicitly enable it for a Turkish data set. Check valid/invalid VKN/TCKN separately from arbitrary foreign/alphanumeric tax identifiers.
- [ ] Verify missing street/house-number combinations, Turkish name variants, contact normalization, shared switchboards/bank accounts and the supplied company-word list. Review false positives as well as planted duplicates.
- [ ] Exercise crowded keys at the configured limit and above it. Check skipped-key counts/messages and measured memory/runtime on representative volumes; verify that duplicate partner membership does not distort the limit.
- [ ] Inspect SAP GUI selection texts, sorting/filtering/export, long explanations, masked/full identifiers and decision hotspots. Run the same variant in background and inspect the job log and spool; an ALV creation failure must fail the job.
- [ ] Save, reload and reverse decisions. Test two users saving simultaneously, lock denial and a failed database write. Confirm client isolation and user/time metadata in `INDX`; the local pure tests do not verify persistence.

## Pull requests and release evidence

Describe the failing input, before/after behavior and validation limits. Keep runtime claims tied to the commit actually tested. Update both READMEs when settings, permissions or support change. Historical v0.3 Platform 2023 results are useful context, not acceptance evidence for v0.4.
