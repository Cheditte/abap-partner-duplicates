# abap-partner-duplicates

> [English](README.md) | **Türkçe**

SAP'de iki kez açılmış iş ortaklarını (carileri) yalnızca ABAP ile bulur. Bakılan sinyaller şunlar:
- aynı vergi numarası;
- aynı IBAN;
- benzer isim;
- aynı adres ya da telefon.

Her bulgu **neden** bulunduğunu söyler. Karar, carileri tanıyan kişilerindir.

**Tek program, başka hiçbir şey yok.** Tek bir kaynak dosyayı SE38'e yapıştırıp aktifleştirirsiniz. Tablo, sözlük (DDIC) nesnesi, metin öğesi ya da abapGit gerekmez.

> **Durum: v0.3, henüz yayınlanmadı.** SAP ABAP Platform 2023 deneme sisteminde, uydurma carilerle baştan sona çalışıyor (bkz. [Neler doğrulandı](#neler-doğrulandı)).

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

1. **Okur:** seçtiğiniz iş ortaklarını okur: isim, adres, telefon, e-posta, vergi numarası ve IBAN. Silinmek üzere işaretlenmiş cariler dahil edilmez.
2. **Normalize eder:**
   - **Türkçe harfler:** kendi tablosuyla A–Z'ye indirilir. Böylece sonuç oturum diline bağlı kalmaz (`İ`, `ı`, `i`, `I` hepsi `I` olur).
   - **İsimler:** `A.Ş.`, `Ltd. Şti.`, `San. ve Tic.` gibi şirket türü ve ticaret kelimeleri atılır; kelime sırasına bakılmaz.
   - **Adresler:** `Cad.` ile `Caddesi`, `Sok.` ile `Sokak` aynı kabul edilir.
   - **Telefonlar:** `0212 555 01 02` ile `+90 212 5550102` aynı telefondur.
3. **Karşılaştırır:** yalnızca ortak bir şeyi olan carileri karşılaştırır (vergi no, IBAN, adres, telefon, e-posta ya da bir isim kelimesi). 100.000 cari tek tek birbiriyle karşılaştırılmaz.
4. **Puanlar:** her çifte 0–100 arası puan verir ve nedenlerini yazar. Örnek: `Same tax number 123*****90; Same name; Same address`.
5. **Hatalı vergi numaralarını listeler:** VKN'nin (10 hane) ya da TCKN'nin (11 hane) kontrol hanesi tutmuyorsa ya da hane sayısı yanlışsa.
6. **Kararı saklar:** her çift için **Mükerrer** ya da **Mükerrer değil** kararı kaydedilir. "Mükerrer değil" denen çift sonraki taramalarda gösterilmez.

İş ortaklarını yalnızca okur; hiçbir şeyi birleştirmez, bloke etmez, silmez. Mükerrer kayda ne olacağı (bloke, arşivleme, açık kalemlerin taşınması) iş kararıdır ve standart SAP işlemleriyle yapılır.

## Neler gerekiyor

| Ne | Neden | Kimden |
|---|---|---|
| SAP_BASIS 7.00 ya da üstü (ECC 6.0 ve sonrası, S/4HANA), iş ortağı (BP) kullanan Unicode sistem | Kod bilerek ABAP 7.00 sözdizimiyle yazıldı, böylece eski sistemlerde de çalışır; BP tablolarını okur. Şimdiye kadar yalnızca ABAP Platform 2023'te çalıştırıldı (bkz. [Neler doğrulandı](#neler-doğrulandı)). | |
| Geliştirici anahtarı ve transport talebi (ya da deneme için yerel nesne) | Tek bir program oluşturmak için. | Basis ya da bir geliştirici |
| Programı çalıştıracak kullanıcıya BP tablolarını okuma yetkisi | Program `BUT000`, `BUT100`, `BUT020`, `ADRC`, `ADR2`, `ADR6`, `DFKKBPTAXNUM`, `BUT0BK` tablolarını okur. | Basis |
| **Sisteminizin kullandığı vergi numarası kategorisi** | Deneme sisteminde `TR2` "Turkey: Tax number", `TR1` "Turkey: Tax Office". Kendi sisteminizde BUP0 işlem kodundan ya da `TFKTAXNUMTYPE` görünümünden bakın. | SAP FI / ana veri ekibi |
| **Karar verecek biri** | Araç adayları bulur; carileri tanıyan biri karar verir. | Ana veri ekibi, satınalma, muhasebe |

## Kurulum (kopyala-yapıştır)

1. **Kaynağı kopyalayın.** GitHub'da [`src/zche_dupl_find.prog.abap`](src/zche_dupl_find.prog.abap) dosyasını açın, **Copy raw file** düğmesine basın (ya da **Raw** deyip tümünü seçin) ve hepsini kopyalayın.
2. **Programı oluşturun.** **SE38** işlem kodunda `ZCHE_DUPL_FIND` yazıp **Oluştur**'a basın.
   - Başlık: `Find likely duplicate business partners` (ya da Türkçe bir başlık)
   - Tür: **Yürütülebilir program** (Executable program)
   - Kaydedin. Paketinizi ve transport talebinizi seçin; ilk deneme için **Yerel nesne** (Local Object) de olur.
3. **Yapıştırıp aktifleştirin.** Editörün oluşturduğu satırları silin, yapıştırın ve aktifleştirin (**Ctrl+F3**).
4. **Kontrol (isteğe bağlı).** Birim testlerini çalıştırın: SE38'de **Program → Yürüt → Birim testleri** (Unit Tests), ADT'de **Ctrl+Shift+F10**. 30 testin geçmesi gerekir.

Bu kadar: tablo yok, SE11 yok, SM30 yok, metin öğesi yok. Ekran metinlerini program kendisi koyar (Türkçe oturumda Türkçe, diğerlerinde İngilizce).

**Aktifleştirirken "satır çok uzun" hatası alırsanız:** editörünüz eski 72 karakterlik satır ayarında. SE38'de **Yardımcı programlar → Ayarlar → ABAP Editor → Editör** altında **Downwards-compatible line length (72)** işaretini kaldırıp tekrar yapıştırın.

**Yeni sürüme geçmek:** yeni kaynağı eskisinin üzerine yapıştırıp aktifleştirin.

### Alternatif: abapGit

[abapGit](https://abapgit.org) kullanıyorsanız bu repoyu bir pakete de çekebilirsiniz (reponun adresiyle **New Online**, ya da **Code → Download ZIP** ile **New Offline**). Aynı tek program kurulur; seçim metinleri de metin öğesi olarak gelir.

## Ayarlar

Her şey seçim ekranında. Bir kez doldurup **varyant** olarak kaydedin (seçim ekranında **Ctrl+S**); başka araçlardaki "profil" bunun karşılığı. Birden fazla varyant tutabilirsiniz, örneğin ülke başına bir tane.

**Hangi cariler**

| Alan | Anlamı | Değer nereden gelir | Varsayılan |
|---|---|---|---|
| İş ortağı rolü | Yalnızca bu BP rolündeki cariler (S/4HANA'da örneğin tedarikçi rolü `FLVN00`, müşteri rolü `FLCU00`); boşsa hepsi | BP işlem kodu ya da `TB003` tablosu | boş |
| Gruplama | Yalnızca bu BP gruplaması; boşsa hepsi | BP işlem kodu ya da `TB001` tablosu | boş |
| Ülke | Yalnızca bu ülkede adresi olan cariler; boşsa hepsi | ISO ülke kodu, örneğin `TR` | boş |
| Vergi numarası kategorisi | Karşılaştırılacak vergi numarası kategorisi | BUP0 ya da `TFKTAXNUMTYPE`; bkz. [Neler gerekiyor](#neler-gerekiyor) | `TR2` |

**Kurallar**: her ağırlık (0–100), bir kuralın tek başına bir çifti ne kadar kesinleştirdiğini söyler. 0 kuralı kapatır.

| Alan | Varsayılan | Not |
|---|---|---|
| Ağırlık: aynı vergi no | 95 | |
| Ağırlık: aynı IBAN | 90 | Faktoring şirketleri ya da grup şirketleri aynı IBAN'ı paylaşabilir. |
| Ağırlık: benzer isim | 70 | Yalnızca bir sonraki alandaki orandan itibaren sayılır; benzerlik oranıyla çarpılır |
| İsim en az % kaç benzer | 85 | |
| Ağırlık: aynı adres | 50 | Aynı ülke, posta kodu (ya da şehir), sokak ve kapı no |
| Ağırlık: aynı telefon | 40 | |
| Ağırlık: aynı e-posta | 40 | Aynı şirket alan adı yarım sayılır. gmail.com gibi ücretsiz alan adları sayılmaz. |
| Gösterilecek en düşük puan | 60 | Listedeki en düşük puan (1–100) |
| Anahtar başına en çok cari | 200 | Bkz. [Puan nasıl hesaplanıyor](#puan-nasıl-hesaplanıyor) |
| Yok sayılacak ek kelimeler | boş | İsimlerde yerleşik listeye (`AS`, `ANONIM`, `SIRKETI`, `LTD`, `STI`, `SAN`, `TIC`, `VE`, `INC`, `GMBH`, ...) **ek olarak** yok sayılacak kelimeler, örneğin `HOLDING` |

**Çıktı**

| Alan | Anlamı |
|---|---|
| Vergi no ve IBAN tam görünsün | Vergi numaraları ve IBAN'lar tam gösterilir; boşsa maskeli (bkz. [Kişisel veri](#kişisel-veri-kvkk)) |
| Karar verilmiş çiftleri göster | "Mükerrer değil" denen çiftler de listelenir |

Yanlış değerler (100'ü aşan ağırlık, 0 olan en düşük puan, kuralı açıkken boş vergi numarası kategorisi) seçim ekranında bir mesajla reddedilir.

## Çalıştırma

Programı çalıştırın ya da **SM36**'da, adım olarak **ABAP programı** `ZCHE_DUPL_FIND` ve varyantınızla arka plan job'ı planlayın.

| Sütun | Anlamı |
|---|---|
| Bulgu | `DUPLICATE` (olası mükerrer çift) ya da `INVALID_TAX_ID` |
| Puan | 0–100 |
| Cari, Ad, Cari 2, Ad 2 | Çift; küçük numara önce |
| Nedenler | Neden, örneğin `Name 92% similar; Same phone` |
| Karar | `D` mükerrer, `N` mükerrer değil |
| Mükerrer / Değil | Tıklayınca kararınız kaydedilir |

Arka plan job'ında liste spool'a, `21 cari okundu: 6 olası mükerrer çift, 2 hatalı vergi numarası` gibi bir özet de job log'una yazılır. Nedenler ve job log'undaki dil, job'ı planlayan kullanıcının diline göre değişebilir; nedenler şimdilik yalnızca İngilizce.

### Kararlar nerede saklanıyor

SAP'nin standart `INDX` tablosunda (alan `ZC`, ID `ZCHE_DUPL_DECISIONS`), istemci başına bir kayıt; bu sayede programın kendine ait bir tabloya ihtiyacı yok. Kararlar, verildikleri sistemde ve istemcide kalır; transport edilmez. İki kişi aynı anda tıklarsa birbirinin kararını ezmez: kayıt sırasında kısa bir kilit alınır.

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

**Anahtar başına en çok cari** değerinden fazla carinin paylaştığı bir anahtar karşılaştırılmaz ve mesaj olarak raporlanır. Örnek: bir tekstil şirketinde `TEKSTIL` kelimesi.

## Kişisel veri (KVKK)

TCKN bir kişinin kimlik numarasıdır; şahıs şirketleri bunu vergi numarası olarak kullanır. Bu yüzden:
- **Maskeleme:** vergi numaraları ve IBAN'lar varsayılan olarak maskelenir (`100******46`); nedenlerde ve mesajlarda da.
- **Tam gösterim:** **Vergi no ve IBAN tam görünsün** işareti numaraları tam gösterir. Kimin kullanabileceğine siz karar verin, örneğin varyantları koruyarak.
- **Dışarıya sorgu yok:** yalnızca kontrol haneleri hesaplanır, hiçbir yerden sorgu yapılmaz.
- **Yalnızca okuma:** iş ortağı verisi değiştirilmez.

v0.3'te araca özel bir yetki kontrolü yok.

## Programın içi

Program tek bir dosya ve yerel sınıflara bölünmüş; okumak ve değiştirmek için tek yere bakarsınız:

| Bölüm | Görevi |
|---|---|
| `LIF_DUPL` | Tipler ve sabitler |
| `LCL_SOURCE_BP` | SAP iş ortaklarını okur. **Başka bir kaynak** için (örneğin BP kullanmayan bir ECC'de LFA1/KNA1) bu sınıfı değiştirin. |
| `LCL_NORMALIZER` | İsim, adres, telefon, e-posta |
| `LCL_TAX_ID` | VKN/TCKN kontrol haneleri ve maskeleme |
| `LCL_MATCHER` | Çiftleri bulur ve puanlar; veritabanına dokunmaz, testli |
| `LCL_DECISIONS` | Kararları `INDX`'ten okur ve oraya yazar |
| `LCL_FINDER` | Bir taramayı çalıştırır: kaynak, eşleştirme, kararlar, vergi no kontrolü |
| `LCL_APP`, `LCL_TEXT`, `LCL_SCREEN` | Seçim ekranı, metinler, liste |
| `LTC_*` | Birim testleri |

## Neler doğrulandı

2 Kasım 2026'da, SAP ABAP Platform 2023 deneme sisteminde (SAP_BASIS 816), 21 uydurma cariyle:

- **Tek başına çalışıyor:** program kendine ait hiçbir sözlük nesnesi ya da sınıf kullanmadan aktifleşiyor.
- **Birim testleri:** 30 ABAP Unit testi geçiyor. Kapsadıkları: Türkçe harfler, şirket türleri, kelime sırası, sokak kelimeleri, telefon, e-posta, VKN/TCKN kontrol haneleri, maskeleme, düzenleme mesafesi, puanlama, kalabalık anahtarlar, kapatılan kurallar, kararlar, ayar kontrolleri.
- **7.00 uyumu:** [abaplint](https://abaplint.org) 2.120, 7.00 ayarında ([abaplint.json](abaplint.json)) 7.00'da olmayan hiçbir sözdizimi bulmuyor. Kalan tek mesajı, SAP sözlüğü yüklü olmadığı için SAP'nin standart `CX_STATIC_CHECK` sınıfını tanımaması.
- **Uçtan uca (arka plan job'ı):** bilerek konulan 5 mükerrer çifti, bunlardan doğan bir çifti daha (puan 64–99) ve 2 hatalı vergi numarasını buldu, başka bir şey bulmadı.
- **Kararlar:** "mükerrer değil" kararı kayıtlıyken sonraki çalıştırma o çifti gizledi (`1 pairs hidden`). **Karar verilmiş çiftleri göster** ve **tam gösterim** işaretliyken çift `N` ile ve numaralar tam olarak listelendi.
- **Ayar kontrolü:** en düşük puan 0 girilince job başlamadan reddediliyor.

**Henüz doğrulanmadı:**
- **SAP GUI'de yapıştırma.** Program ADT üzerinden yüklendi, SE38'e yapıştırılmadı; seçim ekranına SAP GUI'de bakılmadı. Ekran metinlerini koyan çağrı hatasız çalışıyor.
- **Listedeki tıklama.** Kararın kaydedilmesi (kilit ve `INDX`'e yazma) SAP GUI'de denenmedi; kararların okunması aynı biçimde yazılmış veriyle test edildi.
- **IBAN kuralının gerçek veriyle çalışması.** Deneme sisteminde banka ana verisi yok; yalnızca IBAN ile banka bilgisi eklenemedi. Kural yalnızca birim testleriyle doğrulandı.
- **Gerçek bir 7.00 sistemi.** 7.00 sözdizimi yalnızca abaplint ile kontrol edildi; program yalnızca 7.58'de çalıştı. Kullandığı fonksiyon ve sınıfların (`SELECTION_TEXTS_MODIFY`, `ENQUEUE_E_TABLE`, `CL_SALV_TABLE`, `CL_AUNIT_ASSERT`) 7.00'da aynı arayüzle var olup olmadığı kontrol edilmedi.
- **Diğer kurulumlar:** büyük veri hacmi, abapGit yolu.
- **VKN kontrol hanesi algoritması.** Yaygın olarak yayımlanan yönteme göre yazıldı; resmî bir test setiyle karşılaştırılmadı.

## Lisans

MIT, bkz. [LICENSE](LICENSE). Copyright (c) 2026 Ali Emre Altuntaş.
