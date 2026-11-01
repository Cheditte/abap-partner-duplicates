# abap-partner-duplicates

> [English](README.md) | **Türkçe**

SAP'de iki kez açılmış iş ortaklarını (carileri) yalnızca ABAP ile bulur. Bakılan sinyaller şunlar:
- aynı vergi numarası;
- aynı IBAN;
- benzer isim;
- aynı adres ya da telefon.

Her bulgu **neden** bulunduğunu söyler. Karar, carileri tanıyan kişilerindir.

> **Durum: v0.1, henüz yayınlanmadı.** SAP ABAP Platform 2023 deneme sisteminde, uydurma carilerle baştan sona çalışıyor (bkz. [Neler doğrulandı](#neler-doğrulandı)). SM30 bakım ekranı henüz hazır değil.

## Neden

Aynı tedarikçi ya da müşteri sık sık iki kez açılır. Örneğin "ABC Tekstil San. ve Tic. A.Ş." ile "ABC TEKSTİL SANAYİ TİCARET AŞ"; iki kişi tarafından, iki farklı yılda girilmiş. Sonuçları:
- **çift ödeme:** bir fatura her iki kayıttan ayrı ayrı ödenebilir;
- **bölünmüş kredi limiti:** müşterinin limiti iki kayda bölünür;
- **yanlış raporlar:** "en büyük 10 tedarikçi" gibi listeler yanlış çıkar;
- **çift mutabakat:** mutabakat mektupları iki kez gider.

SAP'nin sundukları (bizim araştırmamız, tam bir liste değil):
- **Vergi numarası mükerrer kontrolü** (8B 013/014 mesajları, `V_TFKTAXNUMTYPEC` görünümü): yeni kayıtta aynı numara varsa uyarır ya da durdurur. Yalnızca birebir aynı numarayı karşılaştırır ve var olan veriye bakmaz.
- **Adres bazlı kontrol** (BAdI `ADDRESS_SEARCH`): benzer adres varsa pop-up gösterir. Kurulum ister. Hangi sürümde ne kadar iyi çalıştığını kontrol etmedik.
- **SAP HANA fuzzy search, SAP MDG ve ücretli eklentiler:** çok daha fazlasını yapar, ama HANA, MDG lisansı ya da satın alma gerektirir.

Bu araç:
- ücretsizdir;
- her veritabanında çalışır;
- elinizdeki veriyi tarar;
- her sonucu açıklar.

## Ne yapar

1. **Okur:** bir profilin iş ortaklarını okur: isim, adres, telefon, e-posta, vergi numarası ve IBAN. Silinmek üzere işaretlenmiş cariler dahil edilmez.
2. **Normalize eder:**
   - **Türkçe harfler:** kendi tablosuyla A–Z'ye indirilir. Böylece sonuç oturum diline bağlı kalmaz (`İ`, `ı`, `i`, `I` hepsi `I` olur).
   - **İsimler:** `A.Ş.`, `Ltd. Şti.`, `San. ve Tic.` gibi şirket türü ve ticaret kelimeleri atılır; kelime sırasına bakılmaz.
   - **Adresler:** `Cad.` ile `Caddesi`, `Sok.` ile `Sokak` aynı kabul edilir.
   - **Telefonlar:** `0212 555 01 02` ile `+90 212 5550102` aynı telefondur.
3. **Karşılaştırır:** yalnızca ortak bir şeyi olan carileri karşılaştırır (vergi no, IBAN, adres, telefon, e-posta ya da bir isim kelimesi). 100.000 cari tek tek birbiriyle karşılaştırılmaz.
4. **Puanlar:** her çifte 0–100 arası puan verir ve nedenlerini yazar. Örnek: `Same tax number 123*****90; Same name; Same address`.
5. **Hatalı vergi numaralarını listeler:** VKN'nin (10 hane) ya da TCKN'nin (11 hane) kontrol hanesi tutmuyorsa ya da hane sayısı yanlışsa.
6. **Kararı saklar:** her çift için **Mükerrer** ya da **Mükerrer değil** kararı kaydedilir. "Mükerrer değil" denen çift sonraki taramalarda gösterilmez.

Yalnızca okur; hiçbir şeyi birleştirmez, bloke etmez, silmez. Mükerrer kayda ne olacağı (bloke, arşivleme, açık kalemlerin taşınması) iş kararıdır ve standart SAP işlemleriyle yapılır.

## Neler gerekiyor

| Ne | Neden | Kimden |
|---|---|---|
| SAP_BASIS 7.40 SP08 ya da üstü, iş ortağı (BP) kullanan sistem (S/4HANA ya da BP kullanan ECC) | Kod modern ABAP kullanıyor ve BP tablolarını okuyor. Şimdiye kadar yalnızca ABAP Platform 2023'te test edildi. | |
| [abapGit](https://abapgit.org) | Kurulum için. Tek programlık standalone sürüm yeterli. | Basis ya da bir geliştirici |
| Raporu çalıştıracak kullanıcıya BP tablolarını okuma yetkisi | Rapor `BUT000`, `BUT020`, `ADRC`, `ADR2`, `ADR6`, `DFKKBPTAXNUM`, `BUT0BK` tablolarını okur. | Basis |
| **Sisteminizin kullandığı vergi numarası tipi** | Deneme sisteminde `TR2` "Turkey: Tax number", `TR1` "Turkey: Tax Office". Kendi sisteminizde BUP0 işlem kodundan ya da `TFKTAXNUMTYPE` görünümünden bakın. | SAP FI / ana veri ekibi |
| **Karar verecek biri** | Araç adayları bulur; carileri tanıyan biri karar verir. | Ana veri ekibi, satınalma, muhasebe |

## Kurulum

1. **Paket oluşturun:** örneğin `ZCHE_DUPL`. Transport kullanılan bir sistemde, Basis ekibinizin kullandığı software component ve transport katmanıyla oluşturun.
2. **abapGit'te reposu açın**, ikisinden biriyle:
   - **New Online:** bu reponun adresiyle.
   - **New Offline:** sonra GitHub'da **Code → Download ZIP** ile ZIP'i indirip içe aktarın.
3. **Pull** yapın ve transport talebinizi seçin.
4. **Kontrol edin:** paketin ABAP Unit testlerini çalıştırın (ADT'de pakete sağ tık → Run As → ABAP Unit Test). 25 testin geçmesi gerekir.

**Henüz denenmedi:** boş bir sisteme kurulum. Bu dosyaları abapGit deneme sisteminden yazdı.

## Ayarlar

### 1. Profil: `ZCHE_DUPL_PROF`

| Alan | Anlamı | Örnek |
|---|---|---|
| `PROFILE` | Sizin seçtiğiniz ad | `TR_ALL` |
| `DESCRIPTION` | Serbest metin | `Tüm Türkiye carileri` |
| `TAX_TYPE` | Karşılaştırılacak vergi numarası tipi; boşsa `TR2` | `TR2` |
| `COUNTRY` | Yalnızca bu ülkede adresi olan cariler; boşsa hepsi | `TR` |
| `BP_ROLE` | Yalnızca bu BP rolündeki cariler (örneğin S/4HANA'da tedarikçi rolü); boşsa hepsi | boş |
| `BP_GROUP` | Yalnızca bu BP gruplaması; boşsa hepsi | boş |
| `THRESHOLD` | Gösterilecek en düşük puan (0–100); boşsa 60 | `060` |
| `MAX_BLOCK` | Ortak bir anahtar başına karşılaştırılacak en fazla cari sayısı; boşsa 200 (bkz. [Puan nasıl hesaplanıyor](#puan-nasıl-hesaplanıyor)) | boş |
| `UNMASK` | Vergi numaralarını ve IBAN'ları tam göster; boşsa maskeli | boş |
| `SOURCE_CLASS` | Carilerin nereden okunacağı; boşsa SAP iş ortakları | boş |

### 2. İsteğe bağlı: kural ağırlıkları, `ZCHE_DUPL_RULES`

Satır yoksa aşağıdaki varsayılanlar geçerlidir. Bir satır, bir profil için tek bir kuralı değiştirir; ağırlık `000` kuralı kapatır.

| `RULE_ID` | Varsayılan ağırlık | Not |
|---|---|---|
| `TAX_ID` | 95 | Aynı vergi numarası |
| `IBAN` | 90 | Aynı IBAN. Faktoring şirketleri ya da grup şirketleri aynı IBAN'ı paylaşabilir. |
| `NAME` | 70 | Yalnızca `MIN_SIMILARITY` değerinden itibaren sayılır (varsayılan %85); benzerlik oranıyla çarpılır |
| `ADDRESS` | 50 | Aynı ülke, posta kodu (ya da şehir), sokak ve kapı no |
| `PHONE` | 40 | Aynı telefon |
| `EMAIL` | 40 | Aynı e-posta adresi; aynı şirket alan adı yarım sayılır. gmail.com gibi ücretsiz alan adları sayılmaz. |

### 3. İsteğe bağlı: isimlerde yok sayılan kelimeler, `ZCHE_DUPL_STOP`

Boşsa, şirket türü ve ticaret kelimelerinden oluşan yerleşik liste kullanılır: `AS`, `ANONIM`, `SIRKETI`, `LTD`, `STI`, `SAN`, `TIC`, `VE`, `INC`, `GMBH`, ...

Satır eklerseniz **yalnızca sizin satırlarınız** kullanılır. Yerleşik listeden kalmasını istediğiniz kelimeleri de ekleyin.

Bakım ekranı (SE54) hazır olunca tablolar SM30 ile bakılabilecek; bu adım henüz yapılmadı.

## Çalıştırma

`ZCHE_DUPL_FIND` programında profili girip çalıştırın. **Show decided pairs** işaretlenirse "mükerrer değil" denen çiftler de listelenir.

| Sütun | Anlamı |
|---|---|
| Finding | `DUPLICATE` (olası mükerrer çift) ya da `INVALID_TAX_ID` |
| Score | 0–100 |
| Partner, Name, Partner 2, Name 2 | Çift; küçük numara önce |
| Reasons | Neden, örneğin `Name 92% similar; Same phone` |
| Decision | `D` mükerrer, `N` mükerrer değil |
| Duplicate / Not dup. | Tıklayınca kararınız kaydedilir |

Arka plan job'ı olarak (SM36) çalışınca:
- liste spool'a gider;
- özet job log'una yazılır, örneğin `21 partners read: 5 likely duplicate pairs, 2 invalid tax numbers`;
- yanlış bir profil job'ı "Cancelled" olarak bitirir.

## Puan nasıl hesaplanıyor

Tutan her kural bir kanıt `c` ekler. Bu, kuralın ağırlığıdır; isimlerde ağırlık × benzerlik. Kanıtlar şöyle birleşir:

`puan = 100 × (1 − (1 − c1/100) × (1 − c2/100) × …)`

Böylece iki zayıf sinyal tek birinden daha çok sayılır ve puan 100'ü geçmez. Deneme sisteminden örnekler:

| Çift | Nedenler | Puan |
|---|---|---|
| Derya Tekstil San. ve Tic. A.Ş. / DERYA TEKSTİL SANAYİ TİCARET ANONİM ŞİRKETİ | Aynı vergi no; aynı isim; aynı adres | 99 |
| Derya Tekstil San. ve Tic. A.Ş. / Deria Tekstil AŞ | İsim %92 benzer; aynı telefon | 79 |
| Kuzey Lojistik A.Ş. / Güney Nakliyat Ltd. | Aynı adres; aynı telefon | 70 |

Son çift, kararı neden bir insanın vermesi gerektiğini gösteriyor: aynı binada, aynı santrali kullanan iki farklı şirket. "Mükerrer değil" denince bir daha görünmüyor.

İsim benzerliği iki ölçümden yüksek olanıdır:
- düzenleme mesafesi (ABAP'ın yerleşik `distance` fonksiyonu);
- ortak kelime oranı.

Hızlı kalmak için yalnızca ortak bir anahtarı olan cariler karşılaştırılır. Anahtarlar:
- vergi no, IBAN, adres, telefon;
- e-posta ve e-posta alan adı;
- ilk isim kelimesinin ilk üç harfi;
- en uzun isim kelimesi.

`MAX_BLOCK` değerinden fazla carinin paylaştığı bir anahtar karşılaştırılmaz ve mesaj olarak raporlanır. Örnek: bir tekstil şirketinde `TEKSTIL` kelimesi.

## Kişisel veri (KVKK)

TCKN bir kişinin kimlik numarasıdır; şahıs şirketleri bunu vergi numarası olarak kullanır. Bu yüzden:
- **Maskeleme:** vergi numaraları ve IBAN'lar varsayılan olarak maskelenir (`100******46`); nedenlerde ve mesajlarda da.
- **Tam gösterim:** profildeki `UNMASK` numaraları tam gösterir. Profillere kimin bakabileceğine siz karar verin.
- **Dışarıya sorgu yok:** yalnızca kontrol haneleri hesaplanır, hiçbir yerden sorgu yapılmaz.
- **Yalnızca okuma:** rapor hiçbir veriyi değiştirmez.

v0.1'de araca özel bir yetki nesnesi yok.

## Genişletme

- **Başka bir kaynak** (örneğin BP kullanmayan bir ECC'de LFA1/KNA1): `ZIF_CHE_DUPL_SOURCE` arayüzünü uygulayan bir sınıf yazıp `SOURCE_CLASS` alanına girin.

| Nesne | Görevi |
|---|---|
| `ZCHE_DUPL_FIND` | Program: seçim ekranı, liste, kararlar, job |
| `ZCL_CHE_DUPL_FINDER` | Profili okur, aramayı çalıştırır, kararları uygular |
| `ZCL_CHE_DUPL_SOURCE_BP` | SAP iş ortaklarını okur |
| `ZCL_CHE_DUPL_NORMALIZER` | İsim, adres, telefon, e-posta |
| `ZCL_CHE_DUPL_MATCHER` | Çiftleri bulur ve puanlar; veritabanına dokunmaz, testli |
| `ZCL_CHE_DUPL_TAX_ID` | VKN/TCKN kontrol haneleri ve maskeleme |

## Neler doğrulandı

2 Kasım 2026'da, SAP ABAP Platform 2023 deneme sisteminde (SAP_BASIS 816), 21 uydurma cariyle:

- **Birim testleri:** 25 ABAP Unit testi geçiyor. Kapsadıkları: Türkçe harfler, şirket türleri, kelime sırası, sokak kelimeleri, telefon, e-posta, VKN/TCKN kontrol haneleri, maskeleme, puanlama, kalabalık anahtarlar, kapatılan kurallar.
- **Uçtan uca tarama:** bilerek konulan 5 mükerrer çifti (puan 64–99) ve 2 hatalı vergi numarasını buldu, başka bir şey bulmadı.
- **Kararlar ve maskeleme:** "Mükerrer değil" denen çift sonraki taramada gizleniyor. Maskeli ve tam gösterim çalışıyor.
- **Arka plan job'ı:** "Finished" bitiyor; özet job log'unda.

**Henüz doğrulanmadı:**
- **IBAN kuralının gerçek veriyle çalışması.** Deneme sisteminde banka ana verisi yok; yalnızca IBAN ile banka bilgisi eklenemedi. Kural yalnızca birim testleriyle doğrulandı.
- **Listedeki tıklama.** SAP GUI'de denenmedi; arkasındaki karar kaydı test edildi.
- **Diğer kurulumlar:** abapGit ile boş sisteme kurulum, SM30, büyük veri hacmi, eski sürümler.
- **VKN kontrol hanesi algoritması.** Yaygın olarak yayımlanan yönteme göre yazıldı; resmî bir test setiyle karşılaştırılmadı.

## Lisans

MIT, bkz. [LICENSE](LICENSE). Copyright (c) 2026 Ali Emre Altuntaş.
