# abap-partner-duplicates

> [English](README.md) | **Türkçe**

Vergi numarası, IBAN, isim, adres, telefon ve e-posta üzerinden olası mükerrer SAP iş ortaklarını bulur. Her adayı bir puan ve gerekçeyle gösterir; kararı ana veri ekibi verir.

**Ön sürüm v0.4.** On-premise/private sistemlerde standart ABAP içindir; hedef **7.40 SP08 ve üzeridir**. Değişen revizyon SAP'te aktifleştirilmedi veya çalıştırılmadı. Önceki v0.3 sürümünün Platform 2023 sonuçları bu değişiklikleri doğrulamaz. ABAP 7.00 desteği artık belirtilmiyor.

## Ne yapar?

- Seçilen BP ana verisini okur; Türkçe harfleri, şirket/sokak kelimelerini, telefon, e-posta ve IBAN değerlerini normalize eder.
- Ortak eşleştirme anahtarına sahip adayları karşılaştırır; kural ağırlıklarını 0–100 puanda birleştirir.
- SAP GUI ALV listesinde olası mükerrerleri gerekçeleriyle gösterir. İş ortaklarını birleştirmez, bloke etmez veya silmez.
- İstenirse Türk VKN/TCKN kontrol hanesini denetler. Bu seçenek açıkça seçilir ve varsayılan olarak kapalıdır; yabancı vergi numaraları Türk formatıyla değerlendirilmemelidir.
- Yetkili kullanıcının **Mükerrer / Mükerrer değil** kararını kaydeder. Kararlar `INDX`'e yazılır; BP ana verisi taramada yalnızca okunur.

Puan ayarlanabilir bir sezgisel ölçüdür; **iki kaydın aynı olmasının ölçülmüş olasılığı değildir**. Ortak santral, grup banka hesabı ve adres yanlış adaylar oluşturabilir. Aday oluşturma ve kalabalık anahtarların atlanması bazı mükerrerleri kaçırabilir; boş sonuç bütün verinin temiz olduğunu kanıtlamaz.

## Gereksinimler

| Konu | Gereksinim |
|---|---|
| Sistem | BP tabloları olan Unicode SAP, standart ABAP 7.40 SP08+. Yalnız müşteri/tedarikçi tablolarını kullanan eski ECC sistemleri için kaynak sınıfı uyarlanmalıdır. |
| Arayüz | Seçim ve karar tıklamaları için SAP GUI; arka planda spool ve job log'u. |
| Kurulum | Raporu kuracak ABAP geliştiricisi ve aşağıdaki yetki nesnesini tanımlayıp atayacak yetki yöneticisi. |
| Veri kapsamı | BP rolü, gruplama, ülke ve vergi kategorileri hedef sistemde doğrulanmalıdır. `TR2` yalnızca verilen örnek kategoridir. |
| Uyumluluk | Statik 7.40 SP08/7.58 kontrolleri SAP API varlığını veya çalışma zamanı uyumunu kanıtlamaz. ABAP Cloud uygulaması değildir. |

## Kurulum ve yetkilendirme

Çalıştırılabilir kod tek rapordur: `src/zche_dupl_find.prog.abap`. Projeye özel DDIC tablosu gerekmez. **İlk kullanımdan önce yetki kurulumu zorunludur.**

1. DEV sisteminde SE38/ADT ile `ZCHE_DUPL_FIND` yürütülebilir programını oluşturup kaynağın tamamını kaydedin. Transport edilebilir paket veya denemede yerel nesne seçin. Alternatif olarak abapGit ile içe aktarın. Programı aktifleştirmeden önce 2. adımdaki yetki nesnesini oluşturun.
2. Yetki yöneticisi **SU21**'de uygun müşteri nesne sınıfı altında **`ZCHE_DUPL`** nesnesini oluşturur. Standart **`ACTVT`** alanını ve izin verilen **`02`, `03`, `16`** aktivitelerini tanımlar. Nesne normal transport süreciyle taşınır.
3. **PFCG** rollerinde yalnızca gerekli uygulama aktivitelerini atayın:

   | `ZCHE_DUPL-ACTVT` | Bu uygulamadaki izin |
   |---|---|
   | `03` | Tarama çalıştırma |
   | `16` | Tarama iznine ek olarak vergi numarası ve IBAN'ı maskesiz görme |
   | `02` | Çift için karar kaydetme |

4. Kullanıcının okuyabileceği BP yetki grupları için **`B_BUPA_GRP`**, aktivite `03`, tanımlayın. Kaynak, tanımlayıcı detayları okumadan önce her BP'nin `BUT000-AUGRP` alanını, boş grup dahil, kontrol eder. Sırf test geçsin diye geniş yetki vermeyin.
5. Aktivasyon, ATC ve bütün ABAP Unit testlerini çalıştırın. Yaygın kullanımdan önce kısıtlı kullanıcı ve eksik nesne dahil [SAP kabul testlerini](CONTRIBUTING.md#sap-acceptance-checks) tamamlayın.

Nesne veya izin eksikse işlem hata verir. Maskeleme ve seçim varyantı yetkilendirme yerine geçmez. Gerçek `AUTHORITY-CHECK` davranışı ve rol kurulumu hedef SAP sisteminde doğrulanmalıdır.

**Aktivite `03`, ayrıcalıklı toplu okuma iznidir.** İzin verilen `B_BUPA_GRP` grupları içinde tarayıcı adları, iletişim bilgilerini, vergi ve banka tanımlayıcılarını okuyabilir. Standart BP ekranındaki banka, rol veya alan grubu gibi bütün ayrıntılı kısıtları yeniden uygulamaz. Daha dar iş erişimi olan kullanıcılara verilmeden önce bu kapsamı Basis değerlendirmelidir. Aktivite `16`, aynı grup kapsamındaki vergi/IBAN değerlerinin maskesiz gösterimine izin verir.

## İlk tarama

Deneme sisteminde küçük bir veri kümesiyle başlayın; numaralar maskeli kalsın. Ayarlar seçim ekranındadır; tekrar kullanım/job için varyant kaydedebilirsiniz.

| Ayar | Anlamı |
|---|---|
| BP rolü / gruplama / ülke | İş ortağı seçimini sınırlar; boşsa ilgili filtre uygulanmaz. |
| Vergi numarası kategorisi | Okunup karşılaştırılacak vergi numarasının kategorisi; sisteminizde doğrulayın. |
| Anahtar tarih | Geçerli rol, adres, banka ve iletişim kayıtlarının seçildiği tarih; varsayılan güncel tarih. |
| Türk VKN/TCKN kontrolü | Yalnız Türk numaraları için açıkça seçilen kontrol hanesi denetimi; varsayılan kapalı. |
| Kural ağırlıkları | `0` kuralı kapatır; `1–100` kuralın katkısını belirtir. |
| En düşük isim benzerliği | Puanlamaya katılacak isim benzerliği eşiği. |
| Gösterilecek en düşük puan | Listelenecek çiftin toplam puan eşiği. |
| Anahtar başına en çok cari | Bu büyüklüğü aşan kalabalık anahtarlar atlanır ve raporlanır. |
| Yok sayılacak ek kelimeler | Yerleşik şirket/ticaret kelimelerine ek isim kelimeleri. |
| Numaralar tam görünsün | Aktivite `16` gerekir; aksi durumda numaralar neden ve mesajlarda maskelenir. |
| Karar verilmiş çiftleri göster | Önceden **Mükerrer değil** kararı verilen çiftleri de listeler. |

SAP'nin zaman damgalı geçerlilik alanlarında anahtar tarih **00:00:00 UTC** olarak değerlendirilir. Başlangıç/bitiş sınırının boş veya sıfır olması açık uç kabul edilir. Özellikle gün içi değişikliklerde bu yaklaşımı kendi ana veri sürecinizle doğrulayın.

Örnek varsayılan ağırlıklar: vergi no `95`, IBAN `90`, isim `70`, adres `50`, telefon/e-posta `40`; isim benzerliği `85`, toplam puan `60`, anahtar büyüklüğü `200`. Kendi sürecinizin etiketli örnekleriyle ayarlayın.

## Sonuçlar ve kararlar

ALV; bulgu türü, puan, iki cari numarası/adı, nedenler ve mevcut kararı gösterir. Karar öncesinde ilgili carileri inceleyin. Vergi numarası ve IBAN varsayılan maskeli olsa da adlar ve diğer açıklamalar iş/kişisel veri içerebilir; erişim ve paylaşımı buna göre yönetin.

**Mükerrer** ve **Değil** düğmeleri ana veriyi değiştirmez; karar kaydeder. **Mükerrer değil** çifti, **Karar verilmiş çiftleri göster** seçilmedikçe sonraki taramalarda gizlenir. Kararlar istemci bazında `INDX`, alan `ZC`, ID `ZCHE_DUPL_DECISIONS` altında tutulur; transport edilmez. Kaydetme kilit alır, güncel kararları tekrar okur ve son değişikliğin kullanıcısını/zamanını saklar. Gerçek kilit/kayıt davranışı yerel mantık testlerinin dışındadır; SAP'te doğrulanmalıdır.

SM36'da `ZCHE_DUPL_FIND` ve varyantıyla job planlanabilir. SM37, job log'u ve spool'u inceleyin. Etkileşimli karar tıklaması ön planda ALV oturumu gerektirir.

## Eşleştirme ve sınırlar

Kanıtlar şöyle birleştirilir:

`puan = 100 × (1 − (1 − c1/100) × (1 − c2/100) × …)`

İsim kuralında katkı, ağırlık × benzerliktir. Türkçe harfler açık bir dönüşüm tablosuyla işlenir; şirket kelimeleri ve kelime sırası normalize edilir. Vergi/IBAN/iletişim anahtarları ve normalize isim/adresler karşılaştırılır; eksik sokak bilgisi tam adres eşleşmesi sayılmamalıdır.

Kalabalık anahtarlar bütün çiftlere açılmak yerine dışarıda bırakılır. Sonucun kapsamını değerlendirirken atlanan anahtar mesajlarını okuyun. Büyük seçimlerde aday sayısı yine çok büyüyebilir; üretim ölçeğinde ölçüm veya genel performans garantisi yoktur. Küçük seçimlerle başlayıp kendi sisteminizde ölçün.

## Geliştirme kontrolleri

Node.js 22+, npm ve Git yalnız geliştirme içindir; raporun SAP'te çalışması için gerekmez.

```sh
npm ci --ignore-scripts
npm run lint
npm run test:logic
```

`lint:740` ve `lint:758` hedefleri ayrı çalıştırır. Araç sürümleri sabittir. Depodaki `.abaplint-deps/` dosyaları sınırlı standart nesne yer tutucularıdır; SAP'ye kurulmaz ve bütün DDIC/sınıf/fonksiyon arayüzlerini doğrulayamaz.

Mantık test aracı güncel rapordaki saf metotları ve test sınıflarını çıkarıp JavaScript'e dönüştürür. Gerçek yetki, SQL seçimi, ALV, `INDX`, kilit veya commit çalıştırmaz. JavaScript sayısal davranışı SAP ile eşdeğerlik kanıtı değildir. Ayrıntılar: [tests/logic/README.md](tests/logic/README.md).

## Doğrulama durumu

Değişen kod iki statik hedefte sıfır bulguyla kontrol edildi ve **39 dönüştürülmüş mantık testinin tamamı** geçti. Bunlar SAP ABAP Unit sonucu değildir; gerçek yetki, kaynak SQL'i, karar kaydı veya GUI davranışını doğrulamaz.

v0.3 README'si, 2 Kasım 2026'da ABAP Platform 2023 üzerinde 30 ABAP Unit testinin ve 21 uydurma cariyle arka plan çalışmasının geçtiğini bildirmişti. Bu geçmiş sonuçlar önceki koda aittir. Güncel modernizasyon, yetki ve geçerlilik değişiklikleri için yeni SAP aktivasyonu, ATC, bütün ABAP Unit testleri ve entegrasyon kabulü gerekir.

Gerekli kanıtlar için [CONTRIBUTING.md](CONTRIBUTING.md) dosyasına bakın. MIT lisansı: [LICENSE](LICENSE).
