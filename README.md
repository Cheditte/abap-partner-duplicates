# abap-partner-duplicates

> **English** | [Türkçe](README.tr.md)

Find business partners that were created twice in SAP, from ABAP alone: same tax number, same IBAN, a similar name, the same address or phone. Every hit says **why** it was found, and the people who know the partners decide.

**One program, nothing else.** You paste one source file into SE38 and activate it. No tables, no dictionary objects, no text elements, no abapGit needed.

> **Status: v0.3, not released yet.** It works end to end on an SAP ABAP Platform 2023 trial system with made-up partners (see [What has been verified](#what-has-been-verified)).

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

1. Reads the business partners you select: names, addresses, phones, e-mails, tax numbers and IBANs. Partners marked for deletion are left out.
2. Normalizes them:
   - Turkish letters are folded to A–Z with its own table, so the result does not depend on the logon language (`İ`, `ı`, `i`, `I` are all `I`);
   - legal forms and trade words such as `A.Ş.`, `Ltd. Şti.`, `San. ve Tic.` are dropped from names, and word order is ignored;
   - `Cad.`/`Caddesi` and `Sok.`/`Sokak` are the same street word;
   - `0212 555 01 02` and `+90 212 5550102` are the same phone.
3. Compares only partners that share something: a tax number, an IBAN, an address, a phone, an e-mail, or a name word. 100,000 partners are not compared with each other one by one.
4. Scores each pair from 0 to 100 and lists the reasons, for example `Same tax number 123*****90; Same name; Same address`.
5. Lists tax numbers that cannot be right: the check digit of a VKN (10 digits) or TCKN (11 digits) is wrong, or the length is wrong.
6. Lets you record a decision per pair: **Duplicate** or **Not a duplicate**. A pair marked "not a duplicate" is hidden in later runs.

It only reads business partners. Nothing is merged, blocked or deleted: what happens to a duplicate (blocking, archiving, moving open items) is a business decision, and the standard SAP transactions do it.

## What you need

| What | Why | Who |
|---|---|---|
| SAP_BASIS 7.00 or higher (ECC 6.0 and later, S/4HANA) with business partners (BP), Unicode | The code is written in ABAP 7.00 syntax on purpose, so it also runs on older systems, and it reads the BP tables. It has only run on ABAP Platform 2023 so far (see [What has been verified](#what-has-been-verified)). | |
| A developer key and a transport request (or a local test object) | To create one program. | Basis or a developer |
| Read access to the BP tables for the user who runs it | The program reads `BUT000`, `BUT100`, `BUT020`, `ADRC`, `ADR2`, `ADR6`, `DFKKBPTAXNUM`, `BUT0BK`. | Basis |
| **The tax number category your system uses** | In the trial system, `TR2` is "Turkey: Tax number" and `TR1` is "Turkey: Tax Office". Check yours in transaction BUP0 or view `TFKTAXNUMTYPE`. | SAP FI / master data |
| **Someone who decides** | The tool finds candidates; someone who knows the partners decides. | Master data team, purchasing, accounting |

## Install (copy and paste)

1. **Copy the source.** Open [`src/zche_dupl_find.prog.abap`](src/zche_dupl_find.prog.abap) on GitHub, click **Copy raw file** (or **Raw**, then select all), and copy everything.
2. **Create the program.** In transaction **SE38**, enter `ZCHE_DUPL_FIND` and click **Create**.
   - Title: `Find likely duplicate business partners`
   - Type: **Executable program**
   - Save. Choose your package and transport request, or **Local Object** for a first test.
3. **Paste and activate.** Delete the lines the editor generated, paste, and activate (**Ctrl+F3**).
4. **Check (optional).** Run the unit tests: **Program → Execute → Unit Tests** in SE38, or **Ctrl+Shift+F10** in ADT. 30 tests should pass.

That is all: no tables, no SE11, no SM30, no text elements. The screen texts are set by the program itself (Turkish when you log on in Turkish, English otherwise).

**If activation says a line is too long:** your editor is set to the old 72-character lines. In SE38: **Utilities → Settings → ABAP Editor → Editor**, clear **Downwards-compatible line length (72)**, and paste again.

**Update to a new version:** paste the new source over the old one and activate.

### Alternative: abapGit

If you use [abapGit](https://abapgit.org), you can also pull this repository into a package (**New Online** with the repository URL, or **New Offline** with **Code → Download ZIP**). It installs the same single program, plus its selection texts as text elements.

## Settings

Everything is on the selection screen. Fill it once and save it as a **variant** (**Ctrl+S** on the selection screen); a variant is what other tools would call a profile. You can keep several, for example one per country.

**Which partners**

| Field | Meaning | Where the value comes from | Default |
|---|---|---|---|
| BP role | Only partners with this BP role (in S/4HANA, for example the supplier role `FLVN00` or customer role `FLCU00`); empty means all | Transaction BP, or table `TB003` | empty |
| BP grouping | Only this BP grouping; empty means all | Transaction BP, or table `TB001` | empty |
| Country | Only partners with an address in this country; empty means all | ISO country key, for example `TR` | empty |
| Tax number category | Tax number category to compare | BUP0 or view `TFKTAXNUMTYPE`; see [What you need](#what-you-need) | `TR2` |

**Rules**: each weight (0–100) says how sure one rule alone makes a pair. 0 switches the rule off.

| Field | Default | Note |
|---|---|---|
| Weight: same tax number | 95 | |
| Weight: same IBAN | 90 | Factoring companies or group companies can share an IBAN. |
| Weight: similar name | 70 | Counts only from the next field on; weighted by the similarity |
| Name similar at least (%) | 85 | |
| Weight: same address | 50 | Same country, post code (or city), street and house number |
| Weight: same phone | 40 | |
| Weight: same e-mail | 40 | The same company domain counts half. Free mail domains such as gmail.com do not count. |
| Show pairs from score | 60 | Lowest score in the list (1–100) |
| Max. partners per key | 200 | See [How the score works](#how-the-score-works) |
| Extra words to ignore | empty | Words ignored in names **in addition to** the built-in list of legal forms and trade words (`AS`, `ANONIM`, `SIRKETI`, `LTD`, `STI`, `SAN`, `TIC`, `VE`, `INC`, `GMBH`, ...), for example `HOLDING` |

**Output**

| Field | Meaning |
|---|---|
| Show full tax numbers | Tax numbers and IBANs in full; empty means masked (see [Personal data](#personal-data)) |
| Show decided pairs | Also list pairs marked "not a duplicate" |

Wrong values (a weight above 100, a lowest score of 0, no tax number category while its rule is on) are refused on the selection screen with a message.

## Run

Execute the program, or schedule it as a background job in **SM36** with step **ABAP program** `ZCHE_DUPL_FIND` and your variant.

| Column | Meaning |
|---|---|
| Finding | `DUPLICATE` (a likely duplicate pair) or `INVALID_TAX_ID` |
| Score | 0–100 |
| Partner, Name, Partner 2, Name 2 | The pair; the smaller number first |
| Reasons | Why, for example `Name 92% similar; Same phone` |
| Decision | `D` duplicate, `N` not a duplicate |
| Duplicate / Not dup. | Click to save your decision |

As a background job, the list goes to the spool and a summary such as `21 partners read: 6 likely duplicate pairs, 2 invalid tax numbers` to the job log.

### Where decisions are kept

In the standard SAP table `INDX` (area `ZC`, ID `ZCHE_DUPL_DECISIONS`), one entry per client, so the program needs no table of its own. Decisions stay in the system and client where they were made; they are not transported. Two people clicking at the same time do not overwrite each other: saving takes a short lock.

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

To stay fast, only partners that share a key are compared: tax number, IBAN, address, phone, e-mail, e-mail domain, the first three letters of the first name word, and the longest name word. A key shared by more than **Max. partners per key** partners (for example the word `TEKSTIL` in a textile company) is not compared and is reported as a message.

## Personal data

A TCKN is the identity number of a person; sole proprietors use it as their tax number. Therefore:

- tax numbers and IBANs are masked by default (`100******46`), also in reasons and messages;
- **Show full tax numbers** shows them in full; decide who may use it, for example by protecting variants;
- only check digits are calculated, nothing is looked up anywhere;
- business partners are only read.

There is no own authorization check in v0.3.

## Inside the program

The program is one file, organized as local classes, so you can read and change it in one place:

| Part | Purpose |
|---|---|
| `LIF_DUPL` | Types and constants |
| `LCL_SOURCE_BP` | Reads SAP business partners. **For another source**, for example LFA1/KNA1 in an ECC system without BP, change this class. |
| `LCL_NORMALIZER` | Names, addresses, phones, e-mails |
| `LCL_TAX_ID` | VKN/TCKN check digits and masking |
| `LCL_MATCHER` | Finds and scores pairs; no database access, unit tested |
| `LCL_DECISIONS` | Reads and saves decisions in `INDX` |
| `LCL_FINDER` | Runs a search: source, matcher, decisions, tax number check |
| `LCL_APP`, `LCL_TEXT`, `LCL_SCREEN` | Selection screen, texts, list |
| `LTC_*` | Unit tests |

## What has been verified

On an SAP ABAP Platform 2023 trial (SAP_BASIS 816), 2 November 2026, with 21 made-up partners:

- The program activates on its own; it uses no dictionary objects or classes of its own.
- 30 ABAP Unit tests pass: Turkish letters, legal forms, word order, street words, phones, e-mails, VKN/TCKN check digits, masking, edit distance, scoring, crowded keys, rules switched off, decisions, setting checks.
- [abaplint](https://abaplint.org) 2.120 in 7.00 mode ([abaplint.json](abaplint.json)) reports no issues. It knows a few standard SAP objects only through stand-ins in [.abaplint-deps](.abaplint-deps). abaplint does not catch everything that 7.00 lacks (for example method calls passed directly as parameters), so those rules were also checked by hand.
- As a background job, the search found the 5 planted duplicate pairs plus one pair that follows from them (scores 64–99) and the 2 wrong tax numbers, and nothing else.
- With a "not a duplicate" decision stored, the next run hid that pair (`1 pairs hidden`); with **Show decided pairs** and **Show full tax numbers** it was listed with `N` and full numbers.
- A lowest score of 0 is refused before the job starts.

**Not verified yet:**

- **Pasting in SAP GUI.** The program was uploaded through ADT, not pasted in SE38, and the selection screen was not looked at in SAP GUI. The call that sets the screen texts runs without errors.
- **The click in the list.** Saving a decision (lock and write to `INDX`) was not tried in SAP GUI; reading decisions was tested with data in the same format.
- **IBAN rule against real data.** The trial has no bank master data, so a bank detail with only an IBAN was refused. The rule is covered by unit tests only.
- **A real 7.00 system.** The 7.00 syntax was checked with abaplint only; the program has run only on 7.58. Whether every function module and class it uses (`SELECTION_TEXTS_MODIFY`, `ENQUEUE_E_TABLE`, `CL_SALV_TABLE`, `CL_AUNIT_ASSERT`) exists with the same interface on 7.00 was not checked.
- **Other setups:** large data volumes, the abapGit route.
- **VKN check-digit algorithm.** It follows the commonly published method; it was not checked against an official test set.

## License

MIT, see [LICENSE](LICENSE). Copyright (c) 2026 Ali Emre Altuntaş.
