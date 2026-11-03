# Security and data handling

## Reporting an issue privately

Do not put real BP names, tax/identity numbers, IBANs, addresses, contact details, credentials or identifying SAP dumps in an issue or attachment. Use **Security → Report a vulnerability** if that option is available on the repository. Otherwise request a private contact channel from the maintainer without disclosing the vulnerability details publicly.

Security fixes are assessed for the current development revision; no older release support window is promised. Provide the affected source revision, SAP_BASIS, permission setup and a reproduction with invented records.

## Access model

The required customer authorization object **`ZCHE_DUPL`** has field **`ACTVT`**:

| Activity | Application permission |
|---|---|
| `03` | Run a scan and read identifying/contact/bank details within authorized BP groups |
| `16` | Additionally display tax numbers and IBANs without masking |
| `02` | Additionally save a pair decision |

A missing object or missing activity is an error. `B_BUPA_GRP` activity 03 checks `BUT000-AUGRP` before detailed reads and again for both partners when a decision is saved. Include blank authorization groups only when that scope is approved.

**Activity 03 is a privileged aggregate-read grant.** The report does not reproduce all bank, role or field-group restrictions of the standard BP dialog. Do not assign it to an ordinary user whose approved data access is narrower. Screen filters and masked output do not replace permissions.

## Stored data and output

Scanning does not update BP master data. Clicking a decision immediately commits the pair's current decision, BP numbers and last user/time into client-local `INDX(ZC)` under `ZCHE_DUPL_DECISIONS`. No full decision history or retention/deletion UI is provided; agree a retention/cleanup procedure with your administrator. Do not remove unrelated INDX content.

Tax numbers and IBANs are masked by default. Names, BP IDs, contact/address keys in skipped-key messages and other reasons can still identify people or companies. Treat ALV exports, spool and job logs as business data; restrict access and retention. Full-identifier variants can expose raw identifiers to spool/export.

The application makes no external network calls or server-file exports. Normal SAP GUI/ALV export capabilities remain available according to your system's controls.

Review access with a restricted user before rollout. Local transpiled tests do not exercise real authorization or persistence; see [acceptance checks](CONTRIBUTING.md#sap-acceptance-checks).

<a id="turkce"></a>
## Türkçe

Gerçek BP adlarını, VKN/TCKN’yi, IBAN’ı, adres/iletişim bilgisini, parolayı veya kişisel veri içeren SAP dump’ını issue/ek olarak paylaşmayın. Varsa **Security → Report a vulnerability** ile gizli bildirin. Yoksa açık ayrıntı paylaşmadan geliştiriciden özel iletişim yolu isteyin.

`ZCHE_DUPL-ACTVT` için **03** tarama/toplu okuma; buna ek **16** maskesiz numara; **02** karar kaydı iznidir. Nesne/izin eksikse hata verilir. `B_BUPA_GRP` aktivite 03 ile `BUT000-AUGRP`, detay okumadan önce ve karar kaydında tekrar kontrol edilir. Boş gruba yalnız onaylıysa izin verin.

**03 ayrıcalıklı toplu erişimdir.** Standart BP ekranının bütün banka, rol ve alan grubu kısıtları uygulanmaz. Daha dar iş erişimi olan kullanıcıya doğrudan atamayın. Filtre ve maskeleme yetki yerine geçmez.

Tarama BP ana verisini değiştirmez. Karara tıklamak, çiftin son kararını/BP numaralarını/kullanıcı-zamanını istemciye özel `INDX(ZC) / ZCHE_DUPL_DECISIONS` kaydına hemen commit eder. Tam geçmiş, saklama süresi veya silme ekranı yoktur. Yöneticiyle temizleme planı belirleyin; ilgisiz INDX verisine dokunmayın.

Maskeli numaraların yanında adlar, BP ID’leri, atlanan anahtar mesajlarındaki iletişim/adresler yine kişisel/kurumsal veri olabilir. ALV export, spool ve job log’una erişimi ve saklamayı yönetin. Tam numara seçeneği bu çıktılarda ham numara gösterebilir.

Program dış ağ çağrısı veya sunucu dosya export’u yapmaz; sistemin standart GUI/ALV export yetenekleri geçerlidir. Yaygın kullanımdan önce kısıtlı kullanıcıyla doğrulayın. Yerel testler gerçek yetki veya karar kaydını sınamaz: [kabul adımları](CONTRIBUTING.md#sap-acceptance-checks).
