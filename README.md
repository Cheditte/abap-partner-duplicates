# abap-partner-duplicates

> **English** | [Türkçe](README.tr.md)

Find likely duplicate SAP business partners using tax numbers, IBANs, names, addresses, phones and e-mail addresses. Each candidate has a score and an explanation; the master-data team makes the decision.

**Pre-release v0.4.** Classic ABAP for on-premise/private systems, targeting **ABAP 7.00 syntax**. The changed revision has not been activated or executed in SAP. Historical Platform 2023 results from v0.3 do not validate these changes. Actual API and runtime compatibility on a real 7.00 system remains unverified.

## What it does

- Reads the selected BP master data and normalizes Turkish letters, company words, street words, phone numbers, e-mails and IBANs.
- Compares candidates sharing a configured matching key, then combines independent rule weights into a score from 0 to 100.
- Displays likely duplicates and their reasons in an SAP GUI ALV list. It does not merge, block or delete business partners.
- Optionally checks Turkish VKN/TCKN check digits. This is an explicit option, disabled by default; foreign tax identifiers must not be assessed as Turkish numbers.
- Lets an authorized reviewer record **Duplicate** or **Not a duplicate**. These decisions are written to `INDX`; scanning BP master data is read-only.

A score is a configurable heuristic, **not a measured probability** that two partners are identical. Shared switchboards, group bank accounts and common addresses can create false positives. Candidate blocking and crowded-key exclusions can miss duplicates; an empty result does not prove that the database is duplicate-free.

## Requirements

| Area | Requirement |
|---|---|
| Runtime | Unicode SAP system with BP tables and the BP APIs required by the report; older ECC customer/vendor-only systems need a different source implementation. |
| UI | SAP GUI for selection and ALV decision clicks; background execution produces spool/job-log output. |
| Setup | An ABAP developer to install the report and an authorization administrator to define and assign the custom authorization object below. |
| Data scope | Relevant BP roles, groupings, countries and tax categories must be checked in the target system. `TR2` is only the supplied example category. |
| Compatibility | Static 7.00/7.58 checks do not establish SAP API availability or runtime compatibility. This is not ABAP Cloud code. |

## Install and authorize

The executable code is one report, `src/zche_dupl_find.prog.abap`. No project-specific DDIC tables are required. **Authorization setup is required before first use.**

1. In DEV, create executable program `ZCHE_DUPL_FIND` in SE38/ADT and save the complete source in a transportable package, or a local object for a sandbox. Alternatively import it with abapGit. Create the authorization object in step 2 before activating the report.
2. In **SU21**, an authorization administrator creates customer object **`ZCHE_DUPL`** in a suitable customer authorization class. Add the standard field **`ACTVT`** and maintain permitted activities **`02`, `03`, `16`**. Transport the object through the normal landscape.
3. In **PFCG**, assign the required application activities to approved roles:

   | `ZCHE_DUPL-ACTVT` | Permission in this application |
   |---|---|
   | `03` | Run a scan |
   | `16` | Display unmasked tax numbers and IBANs, in addition to scan permission |
   | `02` | Save a pair decision |

4. Maintain **`B_BUPA_GRP`**, activity `03`, for the BP authorization groups the user may read. The source checks each partner's `BUT000-AUGRP`, including blank groups, before reading its identifying details. Do not grant broad access merely to make a test pass.
5. Run activation, ATC and all package ABAP Unit tests. Complete the [SAP acceptance checks](CONTRIBUTING.md#sap-acceptance-checks), including a restricted user and missing-object test, before wider rollout.

A missing object or missing permission is an error; masking and selection variants are not substitutes for authorization. The real `AUTHORITY-CHECK` behavior and role setup require verification in your SAP system.

**Activity `03` is a privileged aggregate-read grant.** Within the allowed `B_BUPA_GRP` groups, the scanner can read names, contact details, tax identifiers and bank identifiers. It does not reproduce every restriction of the standard BP dialog, such as separate bank, role or field-group permissions. Basis must review that scope before granting it to users with narrower business access. Activity `16` permits raw tax/IBAN display within the same group scope.

## First scan

Start with a limited sandbox data set and keep identifiers masked. Settings are on the selection screen; save them as a variant for reuse or a background job.

| Setting | Meaning |
|---|---|
| BP role / grouping / country | Limit the selected business partners; blank means no restriction for that filter. |
| Tax number category | The category used to retrieve and compare tax identifiers; confirm the value in your system. |
| Key date | Date used to select valid roles, addresses, bank and communication records; defaults to the current date. |
| Check Turkish VKN/TCKN | Explicit checksum validation for Turkish identifiers only; off by default. |
| Rule weights | `0` disables a rule; other values express its contribution from `1` to `100`. |
| Minimum name similarity | Lowest name similarity that contributes evidence. |
| Lowest score shown | Minimum combined score to display a pair. |
| Maximum partners per key | Crowded matching keys above this size are skipped and reported. |
| Extra words to ignore | Additional name words ignored alongside the supplied company/trade words. |
| Show full identifiers | Requires activity `16`; identifiers otherwise remain masked in reasons and messages. |
| Show decided pairs | Includes pairs previously marked **Not a duplicate**. |

The key date is evaluated as **00:00:00 UTC** where SAP stores timestamp validity. Initial/zero boundaries are treated as open-ended. Confirm that convention against your master-data maintenance process, especially intraday changes.

Defaults are example weights: tax number `95`, IBAN `90`, name `70`, address `50`, phone/e-mail `40`, minimum name similarity `85`, minimum score `60`, maximum key size `200`. Tune them with labelled examples from your own process.

## Results and decisions

ALV shows finding type, score, both partner numbers/names, reasons and the current decision. Inspect the underlying partners before deciding. Tax numbers and IBANs are masked by default; names and other explanatory details remain business/personal data and must be handled accordingly.

**Duplicate** and **Not dup.** are decision actions, not master-data changes. A **Not a duplicate** decision hides that pair in later scans unless **Show decided pairs** is selected. Decisions are stored per client in `INDX`, area `ZC`, ID `ZCHE_DUPL_DECISIONS`; they are not transported. Saving takes a lock, rereads the current decisions and records the user/time of the last change. Validate the actual lock/save behavior in SAP; it is outside the local logic suite.

Schedule `ZCHE_DUPL_FIND` with a variant in SM36 if background output is needed. Check SM37, the job log and spool. Interactive decision clicks need a foreground ALV session.

## Matching and limits

The score combines evidence as:

`score = 100 × (1 − (1 − c1/100) × (1 − c2/100) × …)`

For name matching, evidence is the configured weight multiplied by similarity. Normalization folds Turkish letters explicitly and ignores configured company words/word order. Matching compares exact tax/IBAN/contact keys and normalized names/addresses; incomplete address information must not establish a full-address match.

Crowded keys are excluded rather than expanded into every possible pair. Review the skipped-key messages when assessing completeness. Candidate count can still grow substantially for large selections; there is no production-scale benchmark or universal performance guarantee. Start narrow and measure in your own system.

## Development checks

Node.js 22+, npm and Git are development tools only; they are not needed to execute the report in SAP.

```sh
npm ci --ignore-scripts
npm run test:gate
npm run lint
npm run test:logic
```

`lint:700` and `lint:758` run the static targets separately. Tool versions are pinned. The committed `.abaplint-deps/` files are limited standard-object stand-ins, not installable SAP source; they cannot validate every DDIC/class/function interface.

The logic harness extracts pure methods and existing test classes from the current report, then transpiles them to JavaScript. It does not exercise real authorization, SQL selection, ALV, `INDX`, locks or commits. JavaScript numeric behavior does not establish SAP runtime parity. See [tests/logic/README.md](tests/logic/README.md) for extraction and evidence details.

`npm run check:classic` is an extra project gate, also run by `lint`. It parses the report with pinned abaplint core, ignores comments/quoted examples, and rejects inline declarations, constructor expressions, templates, table expressions, `&&`, empty keys and method calls nested in actual arguments. Versioned abaplint still checks the rest of the syntax; the gate does not certify SAP API availability on 7.00. `test:gate` tests accepted classic statements and rejected examples.

## Verification status

Local checks for the changed code passed both static targets with zero findings and completed all **39 transpiled logic tests**. These are not SAP ABAP Unit results and do not validate authorization, source SQL, decision persistence or GUI behavior.

The v0.3 README reported 30 passing SAP ABAP Unit tests and a background run with 21 invented partners on ABAP Platform 2023, on 2 November 2026. Those historical results belong to the earlier code. Current matching, authorization and validity changes require fresh SAP activation, ATC, complete ABAP Unit and integration acceptance.

See [CONTRIBUTING.md](CONTRIBUTING.md) for required evidence and [CHANGELOG.md](CHANGELOG.md) for migration notes. MIT licensed; see [LICENSE](LICENSE).
