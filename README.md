# abap-partner-duplicates

> **English** | [Türkçe](README.tr.md)

Find business partners that were created twice in SAP, from ABAP alone: same tax number, same IBAN, a similar name, the same address or phone. Every hit says **why** it was found, and the people who know the partners decide.

> **Status: v0.1, not released yet.** It works end to end on an SAP ABAP Platform 2023 trial system with made-up partners (see [What has been verified](#what-has-been-verified)). The SM30 maintenance view is still to come.

## Why

The same supplier or customer often exists twice: "ABC Tekstil San. ve Tic. A.Ş." and "ABC TEKSTİL SANAYİ TİCARET AŞ", typed by two people in two years. The result:

- an invoice can be paid twice, once to each record;
- a customer's credit limit is split over two records;
- reports such as "top 10 suppliers" are wrong;
- balance confirmations go out twice.

What SAP offers (our research, not a complete list):

- **Tax number duplicate check.** When a partner is created with a tax number that already exists, SAP warns or stops (messages 8B 013/014, view `V_TFKTAXNUMTYPEC`). It only compares exact numbers and does not look at data that is already there.
- **Address duplicate check.** Through BAdI `ADDRESS_SEARCH`, it shows a pop-up when a similar address exists. It needs setup, and we have not checked how well it works on each release.
- **SAP HANA fuzzy search, SAP Master Data Governance and third-party add-ons.** They do much more, but they need HANA, an MDG license or a purchase.

This tool is free, runs on any database, scans the data you already have and explains every result.

## What it does

1. Reads the business partners of a profile: names, addresses, phones, e-mails, tax numbers and IBANs. Partners marked for deletion are left out.
2. Normalizes them:
   - Turkish letters are folded to A–Z with its own table, so the result does not depend on the logon language (`İ`, `ı`, `i`, `I` are all `I`);
   - legal forms and trade words such as `A.Ş.`, `Ltd. Şti.`, `San. ve Tic.` are dropped from names, and word order is ignored;
   - `Cad.`/`Caddesi` and `Sok.`/`Sokak` are the same street word;
   - `0212 555 01 02` and `+90 212 5550102` are the same phone.
3. Compares only partners that share something: a tax number, an IBAN, an address, a phone, an e-mail, or a name word. 100,000 partners are not compared with each other one by one.
4. Scores each pair from 0 to 100 and lists the reasons, for example `Same tax number 123*****90; Same name; Same address`.
5. Lists tax numbers that cannot be right: the check digit of a VKN (10 digits) or TCKN (11 digits) is wrong, or the length is wrong.
6. Lets you record a decision per pair: **Duplicate** or **Not a duplicate**. A pair marked "not a duplicate" is hidden in later runs.

It only reads. Nothing is merged, blocked or deleted: what happens to a duplicate (blocking, archiving, moving open items) is a business decision, and the standard SAP transactions do it.

## What you need

| What | Why | Who |
|---|---|---|
| SAP_BASIS 7.40 SP08 or higher with business partners (S/4HANA, or ECC that uses BP) | The code uses modern ABAP and reads the BP tables. Tested only on ABAP Platform 2023 so far. | |
| [abapGit](https://abapgit.org) | To install. The standalone version (one program) is enough. | Basis or a developer |
| Read access to the BP tables for the user who runs it | The report reads `BUT000`, `BUT020`, `ADRC`, `ADR2`, `ADR6`, `DFKKBPTAXNUM`, `BUT0BK`. | Basis |
| **The tax number type your system uses** | In the trial system, type `TR2` is "Turkey: Tax number" and `TR1` is "Turkey: Tax Office". Check yours in transaction BUP0 or view `TFKTAXNUMTYPE`. | SAP FI / master data |
| **Someone who decides** | The tool finds candidates; someone who knows the partners decides. | Master data team, purchasing, accounting |

## Install

1. Create a package, for example `ZCHE_DUPL`. In a system with transports, give it the software component and transport layer your Basis team uses.
2. In abapGit, either:
   - **New Online** with the URL of this repository, or
   - **New Offline**, then on GitHub **Code → Download ZIP**, and import the ZIP.
3. **Pull** and choose your transport request.
4. Check: run the ABAP Unit tests of the package (in ADT: right-click the package → Run As → ABAP Unit Test). 25 tests should pass.

**Not tried yet:** installing into a fresh system. abapGit wrote these files from the trial system.

## Set up

### 1. A profile: `ZCHE_DUPL_PROF`

| Field | Meaning | Example |
|---|---|---|
| `PROFILE` | Name you choose | `TR_ALL` |
| `DESCRIPTION` | Free text | `All Turkish partners` |
| `TAX_TYPE` | Tax number type to compare; empty means `TR2` | `TR2` |
| `COUNTRY` | Only partners with an address in this country; empty means all | `TR` |
| `BP_ROLE` | Only partners with this BP role, for example the supplier role in S/4HANA; empty means all | empty |
| `BP_GROUP` | Only this BP grouping; empty means all | empty |
| `THRESHOLD` | Lowest score shown (0–100); empty means 60 | `060` |
| `MAX_BLOCK` | Most partners compared per shared key; empty means 200 (see [How the score works](#how-the-score-works)) | empty |
| `UNMASK` | Show full tax numbers and IBANs; empty means masked | empty |
| `SOURCE_CLASS` | Where partners come from; empty means SAP business partners | empty |

### 2. Optional: rule weights, `ZCHE_DUPL_RULES`

Without rows the defaults below apply. A row changes one rule for one profile; weight `000` switches the rule off.

| `RULE_ID` | Default weight | Note |
|---|---|---|
| `TAX_ID` | 95 | Same tax number |
| `IBAN` | 90 | Same IBAN. Factoring companies or group companies can share an IBAN. |
| `NAME` | 70 | Counts only from `MIN_SIMILARITY` on (default 85%); weighted by the similarity |
| `ADDRESS` | 50 | Same country, post code (or city), street and house number |
| `PHONE` | 40 | Same phone |
| `EMAIL` | 40 | Same e-mail address; the same company domain counts half. Free mail domains such as gmail.com do not count. |

### 3. Optional: words ignored in names, `ZCHE_DUPL_STOP`

Empty: a built-in list of legal forms and trade words is used (`AS`, `ANONIM`, `SIRKETI`, `LTD`, `STI`, `SAN`, `TIC`, `VE`, `INC`, `GMBH`, ...). If you add rows, **only your rows** are used, so copy the words you want to keep.

The tables can be maintained with SM30 once the maintenance view exists (SE54; still to come).

## Run

`ZCHE_DUPL_FIND`: enter the profile and execute. **Show decided pairs** also lists pairs marked "not a duplicate".

| Column | Meaning |
|---|---|
| Finding | `DUPLICATE` (a likely duplicate pair) or `INVALID_TAX_ID` |
| Score | 0–100 |
| Partner, Name, Partner 2, Name 2 | The pair; the smaller number first |
| Reasons | Why, for example `Name 92% similar; Same phone` |
| Decision | `D` duplicate, `N` not a duplicate |
| Duplicate / Not dup. | Click to save your decision |

As a background job (SM36), the list goes to the spool and a summary such as `21 partners read: 5 likely duplicate pairs, 2 invalid tax numbers` to the job log. A wrong profile ends the job as "Cancelled".

## How the score works

Each rule that fires adds evidence `c` (its weight; for names, the weight times the similarity). The evidence is combined as

`score = 100 × (1 − (1 − c1/100) × (1 − c2/100) × …)`

so two weak signals count more than one, and the score never exceeds 100. Examples from the trial:

| Pair | Reasons | Score |
|---|---|---|
| Derya Tekstil San. ve Tic. A.Ş. / DERYA TEKSTİL SANAYİ TİCARET ANONİM ŞİRKETİ | Same tax number; Same name; Same address | 99 |
| Derya Tekstil San. ve Tic. A.Ş. / Deria Tekstil AŞ | Name 92% similar; Same phone | 79 |
| Kuzey Lojistik A.Ş. / Güney Nakliyat Ltd. | Same address; Same phone | 70 |

The last pair shows why a person decides: two different companies in the same building with the same switchboard. After "Not a duplicate" it no longer appears.

Name similarity is the better of two measures: edit distance (ABAP's built-in `distance`) and the share of common words.

To stay fast, only partners that share a key are compared: tax number, IBAN, address, phone, e-mail, e-mail domain, the first three letters of the first name word, and the longest name word. A key shared by more than `MAX_BLOCK` partners (for example the word `TEKSTIL` in a textile company) is not compared and is reported as a message.

## Personal data

A TCKN is the identity number of a person; sole proprietors use it as their tax number. Therefore:

- tax numbers and IBANs are masked by default (`100******46`), also in reasons and messages;
- `UNMASK` in the profile shows them in full; decide who may maintain profiles;
- only check digits are calculated, nothing is looked up anywhere;
- the report only reads.

There is no own authorization object in v0.1.

## Extending

- **Another source**, for example LFA1/KNA1 in an ECC system without BP: a class implementing `ZIF_CHE_DUPL_SOURCE`, entered in `SOURCE_CLASS`.

| Object | Purpose |
|---|---|
| `ZCHE_DUPL_FIND` | Program: selection, list, decisions, job |
| `ZCL_CHE_DUPL_FINDER` | Reads the profile, runs the search, applies decisions |
| `ZCL_CHE_DUPL_SOURCE_BP` | Reads SAP business partners |
| `ZCL_CHE_DUPL_NORMALIZER` | Names, addresses, phones, e-mails |
| `ZCL_CHE_DUPL_MATCHER` | Finds and scores pairs; no database access, unit tested |
| `ZCL_CHE_DUPL_TAX_ID` | VKN/TCKN check digits and masking |

## What has been verified

On an SAP ABAP Platform 2023 trial (SAP_BASIS 816), 2 November 2026, with 21 made-up partners:

- 25 ABAP Unit tests pass: Turkish letters, legal forms, word order, street words, phones, e-mails, VKN/TCKN check digits, masking, scoring, crowded keys, rules switched off.
- The search found the 5 planted duplicate pairs (scores 64–99) and the 2 wrong tax numbers, and nothing else.
- "Not a duplicate" hides the pair in the next run; the masked and the full display both work.
- Background job: finishes, with the summary in the job log.

**Not verified yet:**

- **IBAN rule against real data.** The trial has no bank master data, so a bank detail with only an IBAN was refused. The rule is covered by unit tests only.
- **The click in the list.** It was not tried in SAP GUI; the decision saving behind it was tested.
- **Other setups:** a fresh install with abapGit, SM30, large data volumes, older releases.
- **VKN check-digit algorithm.** It follows the commonly published method; it was not checked against an official test set.

## License

MIT, see [LICENSE](LICENSE). Copyright (c) 2026 Ali Emre Altuntaş.
