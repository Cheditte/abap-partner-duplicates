# Technical reference

> **English** | [Türkçe](tr/TECHNICAL.md) · [Walkthrough](WALKTHROUGH.md)

## Data path

`LCL_SCREEN` builds settings → `LCL_SOURCE_BP` reads authorized, eligible BPs → `LCL_NORMALIZER` builds keys → `LCL_MATCHER` generates/scores candidates → `LCL_FINDER` applies saved decisions and optional checksum findings → `LCL_APP` displays SALV output.

Only `src/zche_dupl_find.prog.abap` and its abapGit metadata are installable. The report includes all local classes and tests. No application-host software, external service or project-specific DDIC table is required. Manual installation needs **Fixed point arithmetic** enabled; abapGit metadata sets `FIXPT = X`. Keep Unicode checks and the standard/classic ABAP language version.

## Selection and access

The `S_PART` BP range applies to both initial BP queries before identifying details are read. Empty means no BP-number restriction. Both partners must be inside the selected scope. Role, grouping and country filters further restrict the scope.

The required `ZCHE_DUPL` object has field `ACTVT`: 03 runs a scan, 16 additionally permits raw identifiers, 02 additionally permits saved decisions. `B_BUPA_GRP` activity 03 checks each BP's `BUT000-AUGRP`, including blank groups, before detailed reads. This is a privileged aggregate-read grant and does not reproduce every BP dialog field/role/bank permission. See [SECURITY.md](../SECURITY.md).

| Data | Source |
|---|---|
| Names, authorization groups, deletion flags | `BUT000` |
| Valid roles | `BUT100` |
| Address assignments and standard address versions | `BUT020` + `ADRC` |
| Phone and email details | `ADR2` + `ADR6` |
| Identifiers in the selected tax category | `DFKKBPTAXNUM` |
| IBANs | `BUT0BK` |

Partners marked for deletion are excluded. Key-date validity filters apply to roles, addresses, communications and banks; initial/zero validity boundaries are open-ended. Timestamp validity is evaluated at **00:00 UTC**, not the current instant. Confirm this convention for intraday maintenance.

A BP qualifies for the country filter if it has a valid address there; its other valid addresses can still contribute evidence. A missing/empty eligible selection returns without unbounded FOR ALL ENTRIES reads. API/field availability requires target-system validation, especially on old releases.

## Candidate generation

Candidates must share a blocking key: normalized tax number, IBAN, address, phone, email, company email domain, first three characters of the first sorted name token, or longest name token. Disabled rules do not generate their keys.

A key with more than `P_MAXBLK` members is skipped and reported, including tax and IBAN keys. Stored membership is bounded to the limit plus one; the exact count is retained. This limit does not bound all selected partners or the total candidate set. Large selections can still consume substantial memory/time; no production-scale benchmark is claimed.

Blocking can miss a genuine duplicate with no shared key, even when its names look similar. An empty result is not proof of clean master data.

## Normalization and limits

- Explicit Turkish character folding precedes uppercase conversion. Name tokens ignore generic legal/trade words, single-letter words and user-supplied stop words; tokens are sorted/deduplicated.
- Name/address simplification keeps A–Z and digits and uses a 1,000-character buffer. Other scripts/accents and longer inputs may lose information. Tailor this for international data.
- Street abbreviations are normalized. A missing street cannot produce address evidence; house number alone is insufficient.
- Phones use the last ten digits and reject values shorter than seven. International country codes/extensions can collide.
- Email keys trim/normalize case and reject obvious malformed values: missing parts, multiple @ signs or embedded whitespace. This is not full RFC validation. The supplied public-domain list is finite.
- Tax keys retain letters/digits while normalizing formatting. IBAN keys normalize case/spaces; they do not verify IBAN ownership or checksum.
- Optional VKN/TCKN checks validate format/check digits only. They do not query registration. The option is off by default and must be used with an appropriate Turkish scope/category. A blank country does not establish that the selected identifiers are Turkish.

Shared addresses, group bank accounts or switchboards may produce false positives. Review actual BP records.

## Scores

For contributions `c1…cn`:

`score = 100 × (1 − (1 − c1/100) × (1 − c2/100) × …)`

Weights default to tax 95, IBAN 90, name 70, address 50, phone 40 and email 40. Zero disables a rule. Name contribution is weight × similarity / 100; name similarity must reach `P_MINSIM` (default 85). It uses the greater of edit-distance similarity and token overlap. Different normalized names are capped below 100 similarity.

An exact normalized name alone scores 70; address 50 plus phone 40 scores 70. A shared company email domain contributes half the email weight. The total threshold defaults to 60. These are heuristic contributions, not calibrated probabilities or statistically independent evidence. At least one rule or Turkish checking must remain enabled.

## Decisions and transactions

Decisions are stored per client in `INDX(ZC)`, ID `ZCHE_DUPL_DECISIONS`, with ordered BP numbers. Save requires scan/decision permissions and current access to both BPs.

An `ENQUEUE_E_TABLE` lock covers reloading the decisions, updating the pair and exporting. The operation commits immediately; handled failures roll back and release the lock. Only the latest decision's user/time is retained. There is no full audit history, deletion UI or transport mechanism.

Not-a-duplicate pairs remain in the current display and are hidden on later scans unless `P_DECID` includes them. Only pairs still found by current matching rules can be reconsidered through ALV. Review exclusions after material BP changes.

ALV reasons use a string so explanation data is not truncated at 255 characters. The visible column may still be abbreviated; adjust the layout/export. A SALV creation failure raises a job error in background. GUI decisions require foreground execution.

## Development and extension

Change `LCL_SOURCE_BP` to implement a different source, e.g. customer/vendor-only tables. Preserve access/eligibility policy. `LCL_NORMALIZER` and `LCL_MATCHER` are pure logic and do not merge data.

Use Node.js 22+, npm and Git for local development only:

```sh
npm ci --ignore-scripts
npm run test:gate
npm run lint
npm run test:logic
npm run check:docs
```

The pinned 7.00 and 7.58 lint targets use deliberately incomplete standard-object stand-ins. `check:classic` additionally rejects newer syntax and source lines exceeding 72 columns. Compile-time literal chaining (`&`) and classic table-body assignments (`table[]`) remain valid; modern `&&` is excluded.

The [logic harness](../tests/logic/README.md) extracts production method bodies and test classes and transpiles them to JavaScript. It excludes SAP authorization, SQL, ALV, INDX, locks and commits. JavaScript numeric/runtime behavior does not prove SAP parity. See [validation](../VALIDATION.md) and [SAP acceptance checks](../CONTRIBUTING.md#sap-acceptance-checks).
