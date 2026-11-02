# Validation record

This record applies to the **0.4.0 development revision**, not a released SAP-validated build.

| Check | Result / scope |
|---|---|
| ABAP 7.00 and 7.58 static targets | Zero lint findings; incomplete standard-object stand-ins |
| Classic gate | Newer syntax rejected; all physical source lines fit 72 columns |
| Gate regression tests | 12 passing checks, including classic table-body assignments |
| Transpiled pure-logic tests | 42 passing methods from the current report |
| Documentation | Relative file/anchor/image checks: `npm run check:docs` |
| SAP activation and complete ABAP Unit | Not performed for this revision |
| Actual `S_PART` SQL scoping and role/date eligibility | Pending SAP acceptance |
| Missing object / restricted-user permissions | Pending SAP acceptance |
| SALV display/export, long reasons and background failure handling | Pending SAP acceptance |
| INDX save/reload, concurrency, lock failure and client isolation | Pending SAP acceptance |
| Real ABAP 7.00 runtime/API availability | Not verified |

Local checks ran on Windows on **3 November 2026**, using pinned dependencies. The logic harness records the exact source SHA-256, dependency revision and build/test logs under ignored `.logic-tests/runs/run-*`; see [harness documentation](tests/logic/README.md). CI repeats local checks on Linux. Neither establishes SAP execution.

Three new logic regressions cover malformed emails, preventing a false match from identical malformed emails, and refusing a run with all checks disabled. The BP-number filter is syntax-checked; its database behavior still requires SAP acceptance.

The v0.3 README reported 30 SAP ABAP Unit tests and a background run with 21 invented partners on “ABAP Platform 2023” on 2 November 2026. That historical report belongs to different code; it does not establish the current system or revision's behavior.

Record the exact source commit/hash, actual product/SAP_BASIS/SP, client, Unicode status, program attributes, permissions and observations in the [SAP acceptance checklist](CONTRIBUTING.md#sap-acceptance-checks). Add genuine screenshots with invented/sanitized data when available. Documentation diagrams explain the process; they are not SAP execution evidence.

## Türkçe

Bu kayıt **0.4.0 geliştirme revizyonu** içindir. Yerel 7.00/7.58 statik kontrolleri, 72 sütun kontrolü, 12 sözdizimi kontrol testi ve 42 dönüştürülmüş mantık testi başarılıdır. Bunlar SAP ABAP Unit veya hedef sistem kabul sonucu değildir.

Güncel kaynak SAP’de kurulup çalıştırılmadı. BP numarası SQL filtresi, gerçek yetki, geçerlilik seçimi, karar/kilit/commit, SALV ve job davranışı hedef sistemde doğrulanmalıdır. Eski v0.3 sonuçları bu revizyonu doğrulamaz.
