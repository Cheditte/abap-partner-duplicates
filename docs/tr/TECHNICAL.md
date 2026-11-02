# Teknik başvuru

> [English](../TECHNICAL.md) | **Türkçe** · [Kullanım rehberi](WALKTHROUGH.md)

## Veri akışı

`LCL_SCREEN` ayarları hazırlar → `LCL_SOURCE_BP` yetkili ve uygun BP’leri okur → `LCL_NORMALIZER` anahtarları üretir → `LCL_MATCHER` adayları puanlar → `LCL_FINDER` kararları ve isteğe bağlı kontrol bulgularını uygular → `LCL_APP` SALV listesini gösterir.

Kurulacak kaynak `src/zche_dupl_find.prog.abap` ve abapGit tanımıdır. Yerel sınıflar/testler raporun içindedir. Sunucu yazılımı, dış servis veya özel DDIC tablosu gerekmez. SE38 kurulumunda **Fixed point arithmetic / Sabit noktalı aritmetik** açık olmalıdır; abapGit tanımında `FIXPT = X` bulunur. Unicode kontrolü ve klasik/standart ABAP dili korunur.

## Seçim ve erişim

`S_PART` BP aralığı iki ilk BP sorgusunda da detaylar okunmadan uygulanır. Boşsa BP numarası kısıtı yoktur. Çiftin iki tarafı da seçime dahil olmalıdır. Rol, gruplama ve ülke filtreleri kapsamı ayrıca daraltır.

Zorunlu `ZCHE_DUPL` nesnesinin `ACTVT` alanında 03 tarama, buna ek 16 maskesiz numara ve 02 karar kaydı içindir. `B_BUPA_GRP` aktivite 03, detay okumadan önce her BP’nin `BUT000-AUGRP` grubunu boş grup dahil denetler. Bu toplu okuma izni, standart BP ekranının bütün alan/rol/banka yetkilerini yeniden uygulamaz: [güvenlik](../../SECURITY.md#turkce).

| Veri | Kaynak |
|---|---|
| Ad, yetki grubu, silme işareti | `BUT000` |
| Geçerli roller | `BUT100` |
| Adres ataması ve standart adres sürümü | `BUT020` + `ADRC` |
| Telefon ve e-posta | `ADR2` + `ADR6` |
| Seçilen kategorideki vergi numarası | `DFKKBPTAXNUM` |
| IBAN | `BUT0BK` |

Silme işaretli BP’ler dışlanır. Tarih koşulları rol, adres, iletişim ve banka kayıtlarına uygulanır; boş/sıfır sınırlar açık uç kabul edilir. Zaman damgası **00:00 UTC** için değerlendirilir. Gün içi değişikliklerde bu yaklaşımı doğrulayın.

Ülke filtresi geçerli bir adresle BP’yi seçer; BP’nin diğer geçerli adresleri de karşılaştırmaya katılabilir. Boş uygun seçimde sınırsız FOR ALL ENTRIES sorgusu yapılmaz. Özellikle eski SAP sürümlerinde standart alan/API varlığı hedef sistemde doğrulanmalıdır.

## Aday üretme

Aday çiftler ortak bir anahtar paylaşmalıdır: normalize vergi no, IBAN, adres, telefon, e-posta, şirket e-posta alanı, sıralanmış ilk isim kelimesinin ilk üç harfi veya en uzun isim kelimesi. Kapalı kurallar kendi anahtarlarını üretmez.

`P_MAXBLK` sınırından fazla üyesi olan anahtar atlanır ve bildirilir; buna vergi/IBAN anahtarları da dahildir. Üye listesi sınır+1 ile tutulur; tam üye sayısı korunur. Bu sınır toplam BP veya aday sayısını sınırlamaz. Büyük seçimler yine yüksek bellek/süre kullanabilir; üretim ölçeği performans iddiası yoktur.

Ortak anahtar üretmeyen gerçek mükerrerler kaçabilir. Boş sonuç ana verinin temiz olduğunu kanıtlamaz.

## Normalizasyon ve sınırlar

- Türkçe karakterler açık tabloyla dönüştürülür, ardından büyük harf yapılır. Genel şirket/ticaret kelimeleri, tek harfler ve ek durak kelimeleri isimden çıkarılır; kelimeler sıralanıp tekilleştirilir.
- İsim/adres sadeleştirmesi A–Z ve rakamları, 1.000 karakterlik tamponu kullanır. Diğer alfabe/aksanlarda ve uzun girdilerde bilgi kaybı olabilir.
- Sokak kısaltmaları eşitlenir. Sokak yoksa adres katkısı oluşmaz; yalnız kapı numarası yeterli değildir.
- Telefonda son on rakam kullanılır; yediden kısa değerler elenir. Ülke kodları ve dahili numaralar çakışabilir.
- E-postada boş kısım, birden fazla @ veya aradaki boşluk gibi bariz hatalar elenir. Tam RFC doğrulaması yapılmaz; ücretsiz sağlayıcı listesi sınırlıdır.
- Vergi anahtarı harf/rakamları koruyup biçimi sadeleştirir. IBAN anahtarı büyük harf/boşlukları düzenler; sahiplik veya kontrol hanesi doğrulamaz.
- İsteğe bağlı VKN/TCKN kontrolü biçim/kontrol hanesini denetler, kayıt sorgulamaz. Varsayılan kapalıdır. Doğru Türk kapsamı/kategorisiyle kullanılmalıdır; ülkenin boş olması tüm numaraların Türk numarası olduğunu göstermez.

Ortak adres, grup banka hesabı veya santral yanlış aday üretebilir. Gerçek BP kayıtlarını inceleyin.

## Puan

Katkılar `c1…cn` için:

`puan = 100 × (1 − (1 − c1/100) × (1 − c2/100) × …)`

Varsayılanlar vergi 95, IBAN 90, isim 70, adres 50, telefon 40 ve e-posta 40’tır. Sıfır kuralı kapatır. İsim katkısı ağırlık × benzerlik / 100’dür; benzerlik `P_MINSIM` eşiğine (varsayılan 85) ulaşmalıdır. Düzenleme uzaklığı ile kelime örtüşmesinin daha büyüğü kullanılır. Farklı normalize isimler 100 benzerliğe yuvarlanmaz.

Tam normalize isim tek başına 70; adres 50 ve telefon 40 birlikte 70 verir. Ortak şirket e-posta alanı, e-posta ağırlığının yarısını katkı yapar. Toplam eşik varsayılan 60’tır. Bunlar sezgisel katkılardır; ölçülmüş olasılık veya istatistiksel bağımsız kanıt değildir. En az bir kural veya Türk kontrolü açık olmalıdır.

## Kararlar ve işlemler

Kararlar istemci bazında `INDX(ZC)`, `ZCHE_DUPL_DECISIONS` ID’sinde, sıralanmış iki BP numarasıyla tutulur. Kayıt için tarama/karar izinleri ile iki BP’ye güncel erişim gerekir.

`ENQUEUE_E_TABLE` kilidi altında kararlar yeniden okunur, çift güncellenir ve yazılır. Hemen commit edilir; ele alınan hatalarda rollback/kilit bırakma yapılır. Son kararın kullanıcı/zamanı tutulur; tam geçmiş, silme ekranı veya transport mekanizması yoktur.

Mükerrer değil çifti mevcut ekranda kalır, sonraki taramalarda `P_DECID` açılmadıkça gizlenir. ALV’den yalnız güncel kurallarla hâlâ bulunan çiftler yeniden değerlendirilebilir. Ana veri değişikliklerinde eski dışlamaları kontrol edin.

ALV neden alanı string olduğundan açıklama verisi 255 karakterde kesilmez. Görünen sütun kısa olabilir; düzeni/export’u kullanın. SALV oluşturma hatası arka planda job hatası üretir. Karar tıklamaları ön planda çalışır.

## Geliştirme ve uyarlama

BP olmayan müşteri/tedarikçi gibi başka bir kaynak için `LCL_SOURCE_BP` uyarlanır; erişim/geçerlilik politikası korunur. `LCL_NORMALIZER` ve `LCL_MATCHER` saf mantıktır; ana veriyi birleştirmez.

Node.js 22+, npm ve Git yalnız yerel geliştirme içindir:

```sh
npm ci --ignore-scripts
npm run test:gate
npm run lint
npm run test:logic
npm run check:docs
```

Sabit sürümlü 7.00/7.58 lint kontrolleri eksik standart nesne yer tutucuları kullanır. `check:classic` yeni sözdizimi yanında 72 sütun sınırını da denetler. Derleme zamanı literal birleştirme (`&`) ve klasik tablo gövdesi ataması (`table[]`) geçerlidir; modern `&&` kullanılmaz.

[Mantık aracı](../../tests/logic/README.md) güncel üretim metotları/testleri çıkarıp JavaScript’e dönüştürür. Gerçek yetki, SQL, ALV, INDX, kilit veya commit’i çalıştırmaz. JavaScript sayısal davranışı SAP eşdeğerlik kanıtı değildir: [doğrulama](../../VALIDATION.md) ve [SAP kabul adımları](../../CONTRIBUTING.md#sap-acceptance-checks).
