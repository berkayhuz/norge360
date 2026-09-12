# Norge360 — Performans, Backend Sorgu ve Güvenlik Denetimi

**Denetim tarihi:** 11 Eylül 2026  
**Kapsam:** Swift/SwiftUI iOS istemcisi, Supabase/PostgreSQL şeması ve RLS/RPC katmanı, Realtime, APNs akışı, Cloudflare Worker, medya işleme ve yerel önbellekler  
**Denetim türü:** Kaynak kodu üzerinden statik mimari/güvenlik/performans incelemesi ve yerel derleme-test kontrolleri  
**Durum:** Bu belge bir uygulama planıdır; uygulanan maddeler ilgili bölümde `✅ RESOLVED` olarak işaretlenir.

---

## 1. Yönetici özeti

Kod tabanı genel olarak iyi bir güvenlik yönüne sahip: Supabase RLS yaygın şekilde kullanılıyor, hassas Worker anahtarları iOS uygulamasına gömülmemiş, doğrudan ve grup mesajlaşmasında server-side yetkilendirme tercih edilmiş, push içeriği gizlilik odaklı tutulmuş ve Swift 6 sıkı eşzamanlılık açık. Derleme, lint, TypeScript ve mevcut testler başarılıdır.

Bununla birlikte üretim öncesi ele alınması gereken üç kritik risk vardır:

1. **Profil alanı gizliliği veritabanı sınırında uygulanmıyor.** `show_norway_status` ve `show_location` alanları yalnızca SwiftUI tarafından gizleniyor; public profil satırını okuyabilen yetkili bir istemci gerçek değerleri API cevabında alabilir.
2. **Özel sohbet görselleri hesap kapsamı olmayan ortak disk önbelleğine yazılıyor.** Aynı cihazda hesap değişimi sonrasında önceki hesabın özel medya dosyaları diskte kalabilir.
3. **Oturum kapatma tek bir güvenli akıştan geçmiyor.** Bir ekran APNs cihaz kaydını kaldırmadan doğrudan çıkış yapıyor; bu durum eski cihaz kaydının aktif kalmasına yol açabilir.

En büyük performans kazançları ise şu alanlardan gelecektir:

- Girişte bütün özellik mağazalarının aynı anda sorgu başlatmasını engellemek.
- Feed’i 5 ayrı ilişki sorgusu ve çok sayıda imzalı URL isteği yerine tek sayfalı RPC ile döndürmek.
- Yorum ekranının bütün görünür profilleri çekmesini düzeltmek.
- Explore aramasındaki gönderi başına seri sorgu zincirini kaldırmak.
- Realtime mesaj olayında bütün mesaj geçmişini, okundu durumunu ve makbuzu tekrar tekrar yüklememek.
- Etkinlik sayfasındaki sayfa dışı tüm RSVP/beğeni kayıtlarını çekmemek.
- Push fan-out ve görsel taramayı HTTP isteğinin sıcak yolundan Queue tabanlı arka plan işine taşımak.

### Önerilen yürütme sırası

| Aşama | Süre hedefi | Sonuç |
|---|---:|---|
| Acil güvenlik | 1–3 gün | Profil alanı sızıntısı, özel medya cache’i ve çıkış akışı kapatılır |
| Hızlı performans | 3–7 gün | Yorum, etkinlik, Explore N+1 ve token refresh yükü azaltılır |
| Veri erişim tasarımı | 1–2 hafta | Feed/event/inbox RPC’leri, cursor pagination, toplu URL imzalama |
| Ölçekleme | 2–4 hafta | Queue/outbox push, medya tarama kuyruğu, indeks ve arama iyileştirmeleri |
| Sürekli güvence | Devamlı | SLO, query budget, CI, RLS entegrasyon testleri, gözlemlenebilirlik |

---

## 2. Öncelik tanımları

- **P0 — Kritik:** Gizlilik veya yetkilendirme sınırı ihlali; üretim öncesi kapatılmalı.
- **P1 — Yüksek:** Belirgin kullanıcı gecikmesi, hızlı büyüyen backend maliyeti veya güvenlik açığına dönüşebilecek tasarım.
- **P2 — Orta:** Ölçek büyüdükçe sorun çıkaran, kaynak tüketen veya operasyon güvenilirliğini düşüren konu.
- **P3 — Düşük:** Bakım, paket boyutu, kod temizliği veya küçük verim iyileştirmesi.

---

## 3. Doğrulama sonucu ve mevcut kalite tabanı

### Başarılı kontroller

- iOS Debug Simulator derlemesi: **başarılı** (`BUILD SUCCEEDED`).
- XCTest: **66 test, 0 hata**.
- Swift Testing: **2 test, 0 hata**.
- SwiftLint strict: **145 Swift dosyası, 0 ihlal**.
- `swift-format --strict`: **başarılı**.
- Yerelleştirme kontrolü: **16 dil, 930 anahtar, başarılı**.
- Worker `tsc --noEmit`: **başarılı**.
- Worker production dependency audit: **0 bilinen güvenlik açığı**.
- Supabase Swift bağımlılığı kilitli: `2.55.1`.
- Worker uyumluluk tarihi güncel bir tarihe sabitlenmiş ve `observability` açık.

### Kontrollerin ortaya çıkardığı borçlar

- Periphery, eski/bağlantısız Plan/Calculator/Onboarding yüzeyleri ile çok sayıda kullanılmayan lokalizasyon erişimcisini işaretledi.
- UI testleri sırasında `navigationDestination` modifier’ının `List`/`LazyVStack` içinde olduğu ve gelecekte yok sayılacağı uyarısı tekrarlandı.
- Çalışma dizini bir Git repository kökü değil. Bu nedenle geçmiş güvenlik değişiklikleri, izlenen/izlenmeyen secret dosyaları ve CI dal koruması bu denetimde doğrulanamadı.
- Yerel ortamda Supabase CLI bulunmadığı için migration’lar temiz bir local veritabanına uygulanamadı; RLS testleri yalnızca mevcut SQL test dosyaları üzerinden statik incelendi.
- Üretim `pg_stat_statements`, Supabase query logları, Cloudflare Analytics, MetricKit ve Instruments ölçümleri mevcut değildi. Bu nedenle hız kazanımları tahmindir; uygulamadan önce/sonra ölçülmelidir.

---

## 4. P0 — Üretim öncesi kapatılması gereken güvenlik konuları

### SEC-001 — Profil alanı görünürlüğü yalnızca UI seviyesinde

✅ RESOLVED — Public profile reads now use the database-masked `community_public_profiles` projection; owner reads use `get_my_community_profile()`. Sensitive profile columns are no longer granted to the authenticated role, and a regression SQL test covers stranger/owner access.

**Kanıt**

- `supabase/migrations/20260911190000_add_profile_field_visibility.sql:3-7` yalnızca `show_norway_status` ve `show_location` boolean alanlarını ekliyor.
- `supabase/migrations/20260909020000_add_community_profile_visibility.sql:7-14` public profil için tüm satıra `SELECT` izni veriyor.
- `Norge360/Core/Persistence/CommunityProfileService.swift` ve diğer servisler `community_profiles.select()` ile tüm sütunları okuyor.
- `Norge360/Features/Profile/CommunityMemberProfileView.swift` alanları boolean’a göre yalnızca ekranda göstermiyor.

**Risk**

- Değiştirilmiş bir iOS istemcisi veya doğrudan PostgREST çağrısı, public profilde gizlenmiş şehir/konum ve Norway status değerlerini görebilir.
- Ürün kuralı olan “private fields database policy layer’da gizlenmeli” şartı karşılanmıyor.

**Düzeltme**

- Public tüketim için `community_public_profiles` adlı `security_invoker` view veya dar kapsamlı RPC oluştur.
- Gizli alanları `CASE WHEN show_location THEN city_or_region ELSE NULL END` şeklinde veritabanında maskele.
- Sahip ekranı için ayrı `get_my_community_profile()` RPC/view kullan.
- `authenticated` rolünün temel tablodaki doğrudan `SELECT` yetkisini kaldır; public projection/RPC’ye açıkça yetki ver.
- Feed, arama, yorum, etkinlik, bildirim, follow ve inbox DTO’larının yalnızca ihtiyaç duyduğu public sütunları döndür.
- `select()` yerine her ekrana özel explicit kolon listesi kullan.

**Doğrulama**

- Owner, public stranger, follower, blocked user ve private profile senaryolarıyla API/RLS entegrasyon testleri yaz.
- `show_location=false` iken ham REST/RPC cevabında gerçek konumun hiçbir sütunda bulunmadığını doğrula.
- Cache’lenmiş eski DTO’ların görünürlük değişiminden sonra temizlendiğini test et.

### SEC-002 — Özel sohbet medyası ortak ve hesap-bağımsız disk cache’inde

✅ RESOLVED — Özel sohbet görselleri artık `viewerID + attachmentID + contentVersion` ile namespaced, memory-only ve bounded `NSCache` üzerinden yükleniyor; signed URL indirmeleri ephemeral session kullanıyor, inline/tam ekran yolları private cache’e ayrılıyor ve authenticated user değişiminde cache temizleniyor. Public disk cache’i legacy ortak dizinden ayrıldı; stale dosyalar fiziksel olarak siliniyor ve item/byte sınırları uygulanıyor. Cache izolasyonu, kullanıcı bazlı purge ve item sınırı için regression testleri eklendi.

**Kanıt**

- `Norge360/Core/DesignSystem/CommunityImageCache.swift:10-20` tek global `shared` cache ve `Norge360Images` dizini kullanıyor.
- Cache anahtarı yalnızca URL host/path’inden üretiliyor (`:52-59`); kullanıcı kimliği veya görünürlük sınıfı yok.
- Dosya koruması `.completeUntilFirstUserAuthentication` (`:41-45`).
- Üç günlük retention yalnızca okumayı reddediyor; eski dosya fiziksel olarak silinmiyor (`:23-34`).
- `Norge360/Core/DesignSystem/CommunityChatAttachmentImage.swift:18` aynı cache bileşenini özel mesaj ekleri için kullanıyor.

**Risk**

- Aynı cihazda farklı hesaba geçildiğinde önceki hesabın özel görsel baytları diskte kalabilir.
- Sign-out veya hesap silme sonrasında özel medya temizlenmiyor.
- Disk kullanımı sınırsız büyüyebilir.

**Düzeltme**

- Public medya ve private chat medyasını iki ayrı cache politikasıyla ayır.
- Private cache anahtarını `userID + attachmentID + contentVersion` ile namespace et.
- Private görseller için tercihen memory-only cache kullan; disk gerekiyorsa `.complete` file protection, backup dışlama ve açık retention uygula.
- Sign-out, hesap silme ve hesap değişiminde o kullanıcıya ait private cache’i atomik olarak temizle.
- `NSCache<NSURL, UIImage>` ile byte-cost sınırlı bellek katmanı ekle.
- Disk katmanına maksimum byte/item sınırı, LRU temizlik ve startup/background bakım işi ekle.
- Devam eden aynı URL yüklemelerini tek bir in-flight task altında birleştir.

**Doğrulama**

- Hesap A görseli açar → çıkış → hesap B giriş yapar senaryosunda A’ya ait dosya ve bellek nesnesinin erişilemediğini test et.
- 500+ medya yükünde cache boyutunun belirlenen üst sınırı geçmediğini test et.

### SEC-003 — Oturum kapatma akışı merkezi değil; APNs kaydı atlanabiliyor

✅ RESOLVED — Tüm UI sign-out yolları `SessionCoordinator.signOut()` kullanıyor. Akış bounded retry ile current device deactivation → private state purge → local auth sign-out sırasını uyguluyor; authentication lifecycle değişimi mevcut Realtime task’lerini merkezi olarak iptal ediyor. Deactivation başarısız olsa bile local session kapanıyor ve cleanup warning raporlanıyor. Mock sıralama regression testleri eklendi.

**Kanıt**

- Normal `SignOutButton`, çıkış işlemini doğrudan `sessionCoordinator.signOut()` üzerinden başlatıyor (`Norge360/Core/Auth/SignOutButton.swift:7,29-35`).
- Account setup iptal akışı da aynı merkezi coordinator’ı kullanıyor (`Norge360/Features/Onboarding/AccountSetupFlowView.swift:10,223-228`).
- `AuthenticationStore.signOut()` yalnızca `SessionCoordinator` içindeki auth adapter çağrısı olarak kullanılıyor; repository-wide call-site taramasında başka bir production çağrısı bulunmadı (`Norge360/App/AuthenticationStore.swift:60-64`, `Norge360/Core/Auth/SessionCoordinator.swift:46-59`).

**Risk**

- Server-side APNs device row aktif kalabilir ve çıkış yapan cihaz için gereksiz/gizlilik açısından riskli push denemeleri sürebilir.
- Yeni çıkış noktaları aynı güvenlik adımını unutabilir.

**Düzeltme**

- Tek `SessionCoordinator.signOut()` akışı oluştur: current device deactivate → Realtime unsubscribe → private caches/drafts temizliği → local session sign-out.
- Tüm UI çıkış noktaları yalnızca bu koordinatörü kullansın.
- Deaktivasyon ağ hatasında server-side güvenli yeniden atama/idempotency sağla; istemcinin sonsuza kadar oturumda kalmasına neden olma.
- Cihaz satırlarına `revoked_at`, `last_seen_at`, environment ve audit metadata ekle; token yeniden kaydı yalnızca authenticated RPC ile olsun.

**Doğrulama**

- Her çıkış yolu için mock service sıralama testi yaz.
- Çıkıştan sonra ilgili token için aktif device kaydı olmadığını SQL entegrasyon testiyle doğrula.

---

## 5. P1 — En yüksek getirili performans ve maliyet iyileştirmeleri

### PERF-001 — Girişte bütün feature store’ları aynı anda aktive oluyor

✅ RESOLVED — Auth transition artık feature store’larda yalnızca identity/reset işlemi yapıyor. Feed, groups, events, notifications, conversations, group-chat signals, moderation ve relocation plan yükleri görünür yüzeylerin `activate()` task’lerine taşındı; shared in-flight task’leri duplicate load’ları coalesce ediyor. Activation regression testleri eklendi; iOS full suite 63 test ile doğrulandı.

**Kanıt:** `Norge360/App/Norge360App.swift:142-155`, auth kullanıcısı değişince Plan, account setup, profil, grup, feed, follow, bildirim, push, conversation, group chat, event, moderation ve search history store’larını birlikte güncelliyor. Birçok store bu çağrıdan hemen sonra kendi `reload()` işini başlatıyor.

**Etkisi:** Login ve cold start sırasında birbirinden bağımsız Supabase/Worker çağrıları, imzalı URL üretimleri ve Realtime subscription’ları aynı anda yarışıyor. Ana ekran görünmeden Messages, Events, Moderation gibi sekmeler için veri harcanıyor.

**Öneri**

- Store `updateAuthenticatedUser` yalnızca identity/reset işlemi yapsın; ağ yükü başlatmasın.
- İlk görünür sekmeyi kritik yol kabul et; diğer sekmeleri kullanıcı seçtiğinde lazy-load et.
- Tek hafif `bootstrap` RPC ile yalnızca account completion, public self-profile özeti ve unread sayıları getir.
- Home interaktif olduktan sonra düşük öncelikli, iptal edilebilir prefetch yap.
- Moderation rol kontrolünü yalnızca moderation yüzeyi açıldığında çalıştır veya güvenli JWT custom claim ile taşı.
- Aynı resource için `inFlight Task`, `hasLoaded`, `lastFetchedAt` ve user/filter key kullan; eşzamanlı çağrıları coalesce et.

**Hedef:** Cold start/login kritik yolunda backend request sayısını ölçüp başlangıca göre en az %50 azaltmak; Home usable p95 süresini ayrı izlemek.

### PERF-002 — Feed sayfası çoklu fan-out ve tam kayıt sayımı yapıyor

✅ RESOLVED — Feed sayfası `list_community_feed_page` RPC’sine taşındı; görünürlük filtreleri ve aggregate like/comment/edit-history sayaçları PostgreSQL’de hesaplanıyor. iOS yalnızca bounded feed DTO’su alıyor; author avatar ve post-media signed URL’leri bucket başına batch imzalanıyor. RPC response decoding regression testi eklendi; iOS full suite 64 test ile doğrulandı.

**Kanıt:** `CommunityFeedService.swift:67-77` postları çektikten sonra `:215-280` profiller, medya, tüm like satırları, comment ID’leri ve edit-history ID’leri için ek sorgular yapıyor; ardından her profil ve medya için URL imzalanıyor.

**Etkisi:** Bir feed sayfası en az 5 DB round-trip ve O(like/comment/history row sayısı) payload üretir. Popüler gönderiler büyüdükçe yalnızca sayaç göstermek için binlerce satır indirilebilir.

**Öneri**

- `list_community_feed_page(cursor, limit, scope)` RPC oluştur.
- Tek cevapta post, public author projection, media metadata, aggregate `likes_count/comments_count/edit_history_count` ve yalnızca current-user `is_liked` döndür.
- Sayaçları transaction-safe trigger/counter tablosu veya doğru grouped subquery ile hesapla. Denormalize sayaç kullanılırsa periyodik reconciliation işi ekle.
- Ekranın ihtiyacı olmayan cover URL gibi alanları döndürme.
- Gerçekten public medya için CDN/public delivery değerlendir; private medya için toplu kısa ömürlü imzalama ve expiry-aware URL cache kullan.

**Hedef:** Feed ilk sayfa için 1 veri RPC + en fazla 1 toplu URL imzalama; payload ve p95 latency için bütçe belirlemek.

### PERF-003 — Yorum ekranı bütün görünür profilleri indiriyor

✅ RESOLVED — Yorumlar artık görünür comment ve author public projection’ını birlikte döndüren `list_community_post_comments` RPC’sinden geliyor. RPC comment/post moderation, group visibility ve iki taraflı block kontrollerini server-side uyguluyor. iOS yalnızca yorum yazarlarının avatar path’lerini batch olarak imzalıyor; cover URL’leri yorum akışında üretilmiyor. RPC response decoding ve database visibility regression testleri eklendi.

**Kanıt:** `CommunityFeedService.swift:379-398`; belirli post yorumlarıyla paralel olarak filtre uygulanmadan `community_profiles.select()` çağrılıyor, sonra tüm profil medya URL’leri imzalanıyor.

**Etkisi:** Kullanıcı sayısıyla doğrusal büyüyen, yorum sayısından bağımsız ağır sorgu. Bu dosyadaki en acil gereksiz backend sorgusudur.

**Öneri**

- Önce yorum author ID’lerini belirle ve profil sorgusuna `.in("user_id", authorIDs)` uygula; kısa vadeli düzeltme budur.
- Kalıcı çözüm olarak cursor’lı `list_post_comments(post_id, cursor, limit)` RPC’si author public projection ile birlikte dönsün.
- Yalnız avatar gereken yerde cover imzalama.

**Hedef:** Yorum sayfası için 1 RPC; 20 yorumda veri boyutunun toplam kullanıcı sayısından bağımsız kalması.

### PERF-004 — Explore araması gönderi başına seri veri yükleme yapıyor

✅ RESOLVED — Explore artık post sonuçlarını tekil `feedStore.post(id:)` çağrılarıyla seri yüklemek yerine mevcut batch pipeline üzerinden `loadPosts(ids:)` ile alıyor. Post author avatarları ve post medya signed URL’leri batch imzalanıyor; search ve Explore request generation kontrolleri eski query sonuçlarının yeni state’i ezmesini engelliyor. Batch loading ve stale-search regression testleri eklendi.

**Kanıt:** Arama service’i ayrı profile/group/post RPC’leri çalıştırıyor. Ardından `ExploreView.swift:113-121` her post sonucu için seri şekilde `feedStore.post(id:)` çağırıyor; her çağrı yeniden profil/medya/like/comment/history yükleyebiliyor.

**Etkisi:** 20 sonuçta onlarca sorgu ve seri ağ gecikmesi; en yavaş bağlantıda arama hissi belirgin biçimde bozulur.

**Öneri**

- Tek `search_community(query, cursor, sections)` RPC’si veya en azından `loadPosts(ids:)` batch metodu oluştur.
- Search post DTO’su ihtiyaç duyulan author/count/media özetini doğrudan taşısın.
- Mevcut debounce/cancellation mantığını koru; istek key’i `normalizedQuery + cursor` olsun.
- Eski sorgunun sonucu yeni sorgu state’ini değiştiremesin; generation token kullan.

**Hedef:** Bir arama etkileşiminde en fazla 1 search RPC ve gerekiyorsa 1 batch media call.

### PERF-005 — Etkinlik listesi sayfa dışındaki RSVP ve like kayıtlarını çekiyor

✅ RESOLVED — RSVP ve like sorguları artık yalnızca mevcut event sayfasındaki `eventIDs` ile filtreleniyor; boş event sayfasında ilişkili sorgular çalıştırılmıyor. Offset tabanlı kontrat korunarak gereksiz geçmiş/topluluk verisi transferi kaldırıldı. Build, test, lint ve format kontrolleriyle doğrulandı.

**Kanıt:** `CommunityEventsService.swift:41-80`; event listesi sayfalı ancak current user’ın bütün RSVP’leri ve RLS ile görünen tüm event likes sorgulanıyor.

**Etkisi:** Etkinlik sayfası sabit 20 öğe olsa bile hesap/geçmiş büyüdükçe payload artar.

**Öneri**

- Kısa vadede iki sorguyu yalnızca sayfadaki `eventIDs` ile filtrele.
- Kalıcı olarak `list_upcoming_events(cursor, limit, group_id)` RPC’si; event, host public projection, aggregate like count, current-user like ve RSVP durumunu tek cevapta dönsün.
- `(starts_at, id)` cursor pagination kullan.

### PERF-006 — Realtime mesaj olayı bütün pencereyi tekrar yükletiyor

✅ RESOLVED — Direct/group chat Realtime sinyalleri artık 200 ms debounce sonrasında server-authorized `(created_at,id)` delta RPC çağırıyor; yalnız yeni mesajlar ekleniyor ve yalnız incoming delta varsa mark-read ilerletiliyor. Delta RPC’leri ve SQL regression testi eklendi; build, full XCTest/Swift Testing, SwiftLint, swift-format ve localization kontrolleri geçti.

**Kanıt**

- Direct chat Realtime olayı detay ekranında full `reload` başlatıyor; reload mesaj listesi + mark-read + read-receipt çağrılarını tekrar yapıyor.
- Group chat aynı olayda mesajlar + mute preference + mark-read + receipt yükleyebiliyor.
- SQL fonksiyonları ilk/aynı 200 mesajı döndürüyor; cursor yok.

**Etkisi:** Her yeni mesaj 3–4 backend çağrısı ve 200 satıra kadar yeniden transfer oluşturur. Burst mesajlarda katlanır.

**Öneri**

- Realtime insert payload’ını güvenilir minimal DTO olarak append et veya `after_message_id/created_at` delta RPC kullan.
- Event burst’lerini 100–250 ms debounce/batch et.
- `markRead` yalnızca son okunan mesaj ilerlediğinde ve görünür konuşmada debounce edilerek çağrılsın.
- Receipt yalnız ilgili karşı taraf read sinyali geldiğinde güncellensin.
- Eski geçmişi `(created_at,id)` keyset ile geriye doğru sayfala; en yeni 30–50 mesaj ilk yükte yeterli.
- Reconnect sonrasında bir defalık reconciliation yap.

### PERF-007 — Mesaj gönderimi birden fazla reload ile çoğalıyor

✅ RESOLVED — Direct conversation send artık inbox’ı yeniden yüklemiyor; server send başarılı olduktan sonra inbox preview/sıralama lokal olarak güncelleniyor. Direct ve group detail ekranları gönderim sonrası full mesaj reload’u yerine cursor’lı delta refresh kullanıyor. Regression testi eklendi; full XCTest/Swift Testing, SwiftLint, swift-format ve localization kontrolleri geçti.

**Kanıt:** Conversation store, send sonrasında inbox reload yapıyor; detay ekranı da reload ediyor; Realtime signal aynı anda ek reload tetikleyebilir.

**Öneri**

- İstemcide optimistic pending message oluştur; RPC server ID/timestamp döndürsün ve state reconcile edilsin.
- Inbox preview/unread state’i local olarak güncelle veya send RPC sonucuna summary ekle.
- Bir kaynak için tek authoritative refresh sahibi belirle.
- Retry yalnız idempotency key ile yapılsın; aynı mesajın iki kez gönderilmesini engelle.

### PERF-008 — İmzalı profil ve medya URL’lerinde çağrı patlaması

✅ RESOLVED — Feed/search/follows/notifications için avatar-only signer akışı, profil detayı için cover dahil akış ayrıştırıldı. Avatar, cover, inbox avatar, blocked-member avatar ve group-photo URL’leri bucket bazlı `createSignedURLs` batch çağrılarına taşındı; profil medyasında authenticated-user scope + `updatedAt` visibility version anahtarlı, expiry’den 60 saniye önce yenilenen bounded cache ve in-flight coalescing eklendi. Private chat medyası bu public-profile cache yoluna alınmadı. Build, full test, SwiftLint, swift-format ve localization kontrolleri geçti.

**Kanıt:** `CommunityProfileMediaSigner` profil başına avatar ve cover için ayrı çağrı yapıyor; feed, search, notifications, follows ve inbox yüzeyleri bunu tekrar kullanıyor. Conversation inbox da summary başına avatar imzalıyor.

**Öneri**

- Ekrana özel DTO kullan: feed/search/inbox için yalnız avatar; profil detayında cover.
- Storage SDK destekliyorsa toplu `createSignedURLs`; aksi halde dar bir server RPC/Worker batch endpoint.
- URL’yi `storagePath + transform + user visibility version` anahtarıyla, expiry’den 30–60 sn önce bitecek şekilde cache’le.
- Eşzamanlı aynı imza isteklerini coalesce et.
- Public profil medyasının gerçekten public olmasına ürün kararı verilirse CDN-cacheable public variant üret; private chat medya asla bu yola alınmasın.

### PERF-009 — Her özel medya isteğinde auth refresh yapılıyor

✅ RESOLVED — Private image transport artık her istekte zorunlu `refreshSession()` çağırmıyor; Supabase’in geçerli session erişimini kullanıyor. Yalnızca idempotent `view-url` GET akışında 401 sonrası tek kontrollü refresh+retry uygulanıyor; upload ve completion POST’ları otomatik retry edilmiyor. Worker’ın `exp` parametresi üzerinden viewer-scoped expiry-aware view URL cache, 60 saniyelik kısa client cache üst sınırı, bounded entry limiti, in-flight coalescing ve sign-out/account-change purge eklendi. URL cache ve expiry regression testleri eklendi; build, full test, SwiftLint, swift-format ve localization kontrolleri geçti.

**Önceki kanıt:** `CommunityPrivateImageTransport.swift:84-104` tüm JSON isteklerinde `client.auth.refreshSession()`; cancel akışında da `:47-55` refresh kullanıyordu. View URL her hücre görünümünde çağrılıyordu.

**Önceki etkisi:** Görsel açma/upload sırasında gereksiz Supabase Auth round-trip’leri ve token yarışları.

**Öneri**

- Geçerli session access token’ını kullan; yalnız expiry yaklaşınca SDK refresh veya 401 sonrası tek kontrollü refresh+retry yap.
- Attachment view URL’sini expiry-aware cache’le ve in-flight isteği birleştir.
- 401 retry’sini bir kezle sınırla; upload gibi non-idempotent çağrılarda idempotency anahtarı olmadan otomatik tekrar yapma.

### PERF-010 — Görsel decode/resize/compression MainActor’da

✅ RESOLVED — Image processing artık `@MainActor` değil; ImageIO/CoreGraphics tabanlı bounded thumbnail, crop, rotate ve JPEG encode işlemleri `userInitiated` öncelikli detached task’lerde çalışıyor. Girdi byte/pixel/decompression-bomb sınırları eklendi; editor preview/export akışı async oldu ve MainActor’da yalnız bounded preview/state güncellemeleri kalıyor. Kamera JPEG hazırlığı da aynı background pipeline’a taşındı. Büyük görsel downsample, çıktı byte/dimension ve crop regression testleri eklendi; build, full test, SwiftLint ve swift-format doğrulandı.

**Önceki kanıt:** `CommunityMediaService.swift` içindeki image processing `@MainActor`; JPEG kalite döngüsü, resize ve decode UI executor’ında çalışıyordu. Image editor da büyük görsel downsample işlemini UI oluşturulurken yapıyordu.

**Önceki etkisi:** Büyük kamera görsellerinde scroll/animasyon takılması, bellek sıçraması ve watchdog riski.

**Öneri**

- İşlemeyi ayrı `ImageProcessingActor` veya utility-priority detached task’a taşı.
- ImageIO ile tam bitmap decode etmeden thumbnail/downsample oluştur.
- Decode öncesi byte, pixel dimension ve decompression bomb sınırları uygula.
- `autoreleasepool` ile ara bitmap’leri erken bırak.
- MainActor’a yalnız son küçük UIImage/state atamasını getir.

---

## 6. Supabase/PostgreSQL sorgu ve şema optimizasyonları

### DB-001 — OFFSET pagination yerine keyset cursor

✅ RESOLVED — Feed RPC’si `(created_at DESC, id DESC)` composite keyset cursor ve `limit + 1` has-more davranışı kullanıyor; event listesi `(starts_at ASC, id ASC)`, group listesi `(name ASC, id ASC)` cursor’ına taşındı. iOS store’ları offset yerine opaque `nextCursor` saklıyor. Feed için cursor-aware RPC migration’ı, ilgili composite index’ler ve cursor round-trip/invalid-cursor regression testleri eklendi; build ve hedefli testler doğrulandı. Supabase CLI/local database bulunmadığı için migration SQL’i bu ortamda çalıştırılamadı.

**Bulunan kullanım:** Feed ve event servislerinde `.range(from: offset...)`; group listelerinde de aynı yaklaşım bulunuyor.

**Sorun:** Büyük offset maliyeti artar; yeni kayıt eklendiğinde duplicate/skip görülebilir.

**Uygulama**

- Feed: `(created_at DESC, id DESC)`.
- Upcoming events: `(starts_at ASC, id ASC)`.
- Comments/messages: yönüne göre `(created_at, id)`.
- `limit + 1` ile `has_more`, opaque `next_cursor` döndür.
- İndeks kolon sırası sorgu order/filter sırasıyla aynı olsun.

### DB-002 — Eksik veya doğrulanması gereken birleşik indeksler

✅ RESOLVED — Mevcut sorgu ve RPC desenleriyle doğrulanan yedi birleşik indeks eklendi: member post/reply listeleri, grup etkinlikleri, kullanıcı RSVP ve üyelik listeleri, iki yönlü block kontrolü ve liked-posts listesi. Attachment upload rate-limit ve host etkinliği için eşleşen aktif sorgu bulunmadığından indeks eklenmedi. `supabase/tests/composite_indexes.sql` ile indeks adları/kolon sıraları doğrulanıyor; staging `EXPLAIN (ANALYZE, BUFFERS)` ve production `pg_stat_statements` ölçümü deployment sonrası gereklidir.

Aşağıdaki indeksler mevcut sorgu desenleri için adaydır. **Körü körüne eklenmemeli**; staging veri hacminde `EXPLAIN (ANALYZE, BUFFERS)` ve üretimde `pg_stat_statements` ile doğrulanmalıdır.

- `community_posts (author_id, created_at DESC, id DESC)` — member posts.
- `community_comments (author_id, created_at DESC, id DESC)` — member replies.
- `community_events (group_id, starts_at, id)` — group upcoming events.
- `community_event_rsvps (user_id, event_id)` — mevcut PK’nin ilk kolonu `event_id`; user sorgusu için ters yön.
- `community_group_memberships (user_id, group_id)` — kullanıcının üyelikleri.
- `user_blocks (blocked_user_id, blocker_id)` — iki yönlü block kontrolünün ters tarafı.
- `community_post_likes (user_id, created_at DESC, post_id)` — liked posts tab’ı.
- Direct/group attachment tablolarında `(uploader_id, created_at DESC)` partial index — upload rate-limit sorguları.
- Gerekliyse `community_events (host_id, starts_at DESC)` — profil etkinlikleri.

**Not:** Her indeks INSERT/UPDATE ve storage maliyeti getirir. Kullanılmayan/örtüşen indeksleri aylık `pg_stat_user_indexes` kontrolüyle temizle.

### DB-003 — Search leading-wildcard ILIKE ile tam taramaya yakın

✅ RESOLVED — Search RPC’leri mevcut substring davranışını koruyacak şekilde `lower(...) LIKE` predicate’lerine taşındı ve `pg_trgm` GIN indeksleri eklendi. Username prefix araması için ayrıca `text_pattern_ops` indeksi eklendi. RLS/security-invoker sınırı, minimum uzunluk, debounce, cancellation ve bounded result limitleri korundu. `supabase/tests/community_search_indexes.sql` ile extension, indeks ifadeleri ve RPC predicate’leri doğrulanıyor; production plan doğrulaması için staging `EXPLAIN (ANALYZE, BUFFERS)` gereklidir.

**Kanıt:** `20260909069000_secure_community_search.sql` ve prefix sıralama migration’ı; display name, username, group ve post body’de `%query%` araması var.

**Öneri**

- `pg_trgm` GIN indekslerini `lower(username/display_name/name/slug)` üzerinde değerlendir.
- Uzun post metni için generated `tsvector` + GIN ve dil bağımsız `simple` config başlangıç olabilir; 16 dil için dil-aware strateji ayrıca tasarlanmalı.
- Username exact/prefix aramasını substring’den ayır; normalize edilmiş exact/prefix indeks kullan.
- Minimum uzunluk, debounce ve rate-limit mevcut tasarımla birlikte korunmalı.
- Search result’ları cursor ile sayfalanmalı ve RLS görünürlüğü query içinde korunmalı.

### DB-004 — Profil istatistik view’ı join çarpımı üretebilir

✅ RESOLVED — Profil istatistik view’ı post, like ve comment aggregate’lerini ayrı CTE’lerde hesaplayıp author bazında birleştiriyor; likes×comments ara satır çarpımı kaldırıldı. View adı, kolonları ve `security_invoker` davranışı korundu. `supabase/tests/profile_stats_aggregates.sql` ile aggregate şekli korunuyor; gerçek veri hacmindeki plan doğrulaması deployment sonrası `EXPLAIN (ANALYZE, BUFFERS)` ile yapılmalı.

**Kanıt:** `20260909030000_add_community_profile_covers_and_stats.sql:55-66`; posts → likes → comments iki one-to-many join ile bağlanıp `count(distinct ...)` hesaplanıyor.

**Sorun:** Bir postta L likes ve C comments olduğunda ara sonuç yaklaşık L×C satıra büyüyebilir.

**Öneri**

- Post count, like count ve comment count’u ayrı aggregate CTE/subquery’lerde hesaplayıp author bazında birleştir.
- Trafik artarsa transaction-safe sayaç tablosu ve reconciliation job kullan.
- `EXPLAIN ANALYZE` ile gerçek satır çoğalmasını ölç.

### DB-005 — Sayaç için kayıtların tamamı istemciye indiriliyor

✅ RESOLVED — Feed dışındaki post akışlarında like/comment/edit-history sayaçları ve current-user like state artık `list_community_post_counters(uuid[])` RPC’siyle PostgreSQL’de aggregate ediliyor. Event like sayaçları ve current-user state de `list_community_event_counters(uuid[])` RPC’sine taşındı; iOS artık ham sayaç satırlarını indirmiyor. RPC’ler `security invoker`, RLS görünürlüğünü koruyor ve kullanıcı ID’lerini response’a taşımıyor. Swift response contract testleri ve SQL RPC contract testi eklendi; production plan doğrulaması deployment sonrası yapılmalı.

Feed likes/comments/history ve event likes için ham satırlar çekiliyor. Sayaçlar DB’de `COUNT(*) FILTER (...)`, current-user state ise `EXISTS` ile hesaplanmalı. Kullanıcıya gerekmeyen user ID listeleri payload’a girmemeli.

### DB-006 — RLS helper fonksiyonları yüksek trafikte satır başına tekrar sorgu çalıştırabilir

✅ RESOLVED — `community_public_profiles` projection’ı ve keyset feed RPC’si artık viewer-scoped `blocked_users` materialized CTE ile iki yönlü block setini tek sefer üretip anti-join kullanıyor; feed author/comment satırlarından `can_view_community_user` çağrıları kaldırıldı. DB-002’de eklenen ters yönlü indeks yeniden kullanıldı. SQL contract/regression testi eklendi; production `EXPLAIN (ANALYZE, BUFFERS)` doğrulaması deployment sonrası yapılmalı.

`can_view_community_user` gibi iki yönlü block/profile kontrolleri feed/search satırlarının her birinde değerlendiriliyor. Önce ters block indeksini ekleyip planı ölç; yüksek trafikte viewer-scoped feed RPC içinde tek anti-join/CTE ile görünür author set’i üret. `security definer` fonksiyonlar dar, sabit `search_path=''`, explicit schema ve minimum `GRANT EXECUTE` ile kalmalı.

### DB-007 — Message signal prune işlemi sıcak write yolunda

✅ RESOLVED — Message request/direct-message insert trigger’larından synchronous prune kaldırıldı. Prune RPC’si service-role-only, bounded `batch_size` ve `FOR UPDATE SKIP LOCKED` ile scheduled maintenance’e taşındı; mevcut Worker scheduled akışına eklendi ve pg_cron uyumluluğu korundu. SQL regression testi eklendi; production retention/lock planı deployment sonrası ölçülmeli.

`20260910100000_add_conversation_preferences_and_message_signals.sql` içinde signal prune işlemi conversation request/message insert akışında tetikleniyor. Her mesajın eski satır silmeye çalışması write amplification ve lock üretir.

**Öneri:** Hot-path prune’ı kaldır; `pg_cron` veya Worker scheduled maintenance ile küçük cursor’lı batch silme yap. Retention indeksini expiry/status sırasına göre doğrula.

### DB-008 — Grup push fan-out aynı transaction’da 100 signal satırı üretiyor

`20260910110000_add_private_group_chat_push_signals.sql` bir grup mesajında üyeler için senkron fan-out yapıyor ve 100 üyede kesiyor.

✅ RESOLVED — Mesaj transaction’ı artık yalnızca tek bir fan-out job satırı oluşturuyor. Service-role RPC, recipient’ları UUID cursor ve bounded batch’lerle çözüp mevcut membership, ban ve block kontrollerini koruyarak idempotent signal satırları üretiyor. Cloudflare Worker webhook ve scheduled retry akışına bağlandı. Ana dosyalar: `supabase/migrations/20260912060000_move_group_chat_fanout_to_async_job.sql`, `workers/moderation/src/index.ts`, `supabase/tests/group_chat_push_fanout.sql`; mevcut push regression testi de yeni RPC akışına uyarlandı. Worker typecheck, iOS build/test, lint/format/localization kontrolleri başarılı; SQL testi eklendi ancak yerel Supabase CLI/`psql` olmadığı için çalıştırılamadı.

**Riskler**

- Mesaj gönderme latency’si üye sayısıyla artar.
- DB webhook sayısı patlar.
- 100’den sonraki üyeler UUID sırasına bağlı olarak push alamaz.
- Retry durumunda duplicate push riski vardır.

**Öneri:** Transaction’da tek outbox event yaz. Cloudflare Queue consumer, alıcıları sayfalı çözüp preference/block/active device filtresi uygulasın; toplu APNs gönderimi ve idempotent delivery ledger kullansın.

### DB-009 — Inbox ve mesaj listeleri sınırsız/uygunsuz pencere modeli

✅ RESOLVED — Direct/group chat okumaları newest-first bounded page ve `(created_at, id)` keyset cursor kullanıyor; legacy list RPC’leri de en yeni 50 satırla sınırlandı. Inbox için pinned/updated_at/id cursor, hidden DB filtresi, unread count ve conversation görünüm ayarlarını tek DTO’da döndüren page RPC eklendi. iOS üstten eski mesajları, alttan inbox sayfalarını yükleyip scroll anchor’ını koruyor. Ana dosyalar: `supabase/migrations/20260912070000_add_chat_windows_and_inbox_pagination.sql`, `Norge360/Core/Persistence/CommunityConversationService.swift`, `Norge360/Core/Persistence/CommunityGroupChatService.swift`, `Norge360/App/CommunityConversationsStore.swift`, `Norge360/Features/Community/CommunityConversationsView.swift`, `Norge360/Features/Community/CommunityGroupChatView.swift`; SQL regression testi eklendi.

- Direct ve group chat mesaj RPC’leri en eski→yeni `LIMIT 200` döndürüyor; yeni mesaj sayısı 200’ü aşınca doğru pencerenin gösterilmeme riski vardır.
- Inbox RPC tüm konuşmaları döndürüyor; client ayrıca bütün conversation preferences’ı ayrı okuyor.

**Öneri**

- İlk yükte en yeni 30–50 mesajı subquery ile DESC alıp ekranda ASC sırala.
- Önceki sayfaları cursor ile getir.
- Inbox’a limit/cursor, unread count ve görünüm ayarlarını aynı DTO’da ekle.
- Hidden/restricted filtreleri DB katmanında uygula.

### DB-010 — `.select()` kullanımını explicit kontrata çevir

✅ RESOLVED — First-party iOS Supabase reads now use named explicit projections backed by `SupabaseSelectColumns`; implicit `.select()` calls were removed from the app and Worker source. A `make explicit-select-check` guard prevents regressions, and Codable decoding is covered by the existing build/test suite.

Tam satır select’leri payload’ı büyütür, yeni eklenen hassas sütunları fark edilmeden istemciye taşır ve schema değişikliğine coupling yaratır. Her endpoint/screen için `Codable` DTO + explicit kolon veya RPC dönüş tipi kullanılmalı. Bu yalnız performans değil, SEC-001’in tekrarlanmasını önleyen güvenlik kontrolüdür.

---

## 7. iOS istemci, state ve cache optimizasyonları

### IOS-001 — Stale-while-revalidate ve request coalescing standardı

✅ RESOLVED — Feed/group cache’leri artık fresh snapshot’ı doğrudan gösteriyor, stale snapshot’ı arka planda revalidate ediyor ve aynı user/resource/filter için in-flight request’i paylaşıyor. Account/profile, events, notifications, search, follow, conversations ve moderation yüklemelerinde cancellation + generation guard eklendi; concurrent event reload regression testi ile doğrulandı.

Her store aynı davranışa sahip olmalı:

1. Account-scoped güvenli cache varsa anında göster.
2. TTL dolmadıysa gereksiz ağ çağrısı yapma.
3. TTL dolduysa mevcut içeriği korurken arka planda yenile.
4. Aynı user/resource/filter için tek in-flight task kullan.
5. User/filter değişince eski task’ı iptal et ve eski sonucun state yazmasını generation token ile engelle.
6. Pull-to-refresh gerçek zorunlu refresh olsun.
7. Mutation sonrası tüm listeyi çekmek yerine local patch + kontrollü reconciliation kullan.

### IOS-002 — CommunityContentCache gizlilik invalidation’ı

✅ RESOLVED — CommunityContentCache artık yalnızca sanitize edilmiş public profile/feed verisini diske yazar; üyelik ve join-request state’i ile private/approval-required group kayıtları disk cache’ine alınmaz. Member cache TTL’i 15 dakikaya indirildi, block/private profile değişimlerinde hedefli profile + member-content invalidation eklendi ve sign-out temizliği SessionCoordinator altında birleştirildi. Offline süresi dolmuş member içeriği gösterilmez; public cache DTO sınırları ve viewer cleanup regression testleri ile doğrulandı.

Mevcut feed/group/member cache’i iyi bir başlangıçtır; ancak üç günlük member content cache’i, başka cihazda profil private olduğunda veya block oluştuğunda eski içeriği göstermeye devam edebilir.

- Public cache DTO’ları hassas alan içermemeli.
- Visibility/block version veya kısa TTL kullanılmalı.
- Block/private değişiminde ilgili author/member cache kayıtları anında silinmeli.
- Sign-out cleanup tek SessionCoordinator’dan yönetilmeli.
- Offline modda “önceden görüntülenmiş” içerik gösterilecekse ürün/gizlilik politikası açıkça tanımlanmalı.

### IOS-003 — Plan verisi `UserDefaults` içinde

✅ RESOLVED — Relocation plan cache’i account-scoped `.complete` protected, backup dışı Application Support dosyalarına taşındı; legacy UserDefaults verisi güvenli migration ile kaldırılıyor, authenticated cache sign-out sırasında purge ediliyor ve 30 günlük local retention uygulanıyor. PlanStore migration, account isolation, sign-out cleanup, retention ve protected-file davranışı regression testleriyle doğrulandı.

`PlanStore.swift` relocation profilini JSON olarak account-key ile `UserDefaults`’a yazıyor. Passport/D-number gibi veriler tutulmasa da vatandaşlık, aile, iş teklifi ve hareket planı kişisel bağlamdır.

- Protected file/Core Data/SwiftData tabanlı account-scoped storage kullan.
- File protection `.complete`; gerekiyorsa backup dışlama.
- Sign-out, hesap silme ve retention politikası tanımla.
- Analytics/loglara cevapları taşımama kuralını testle.
- Server sync kaynağı authoritative ise local dosya yalnız şifreli/korumalı cache olsun.

### IOS-004 — Chat arka plan görseli account-scoped değil

✅ RESOLVED — Chat arka plan görselleri `userID/conversationID` namespace’i altında actor-isolated protected files olarak tutuluyor; `.complete` file protection, backup exclusion, atomik yazım, 40 öğe/20 MiB quota ve legacy flat-file purge eklendi. Merkezi sign-out akışı tüm chat background dosyalarını siliyor; account deletion için kullanıcı namespace purge API’si hazır. Regression testleri hesap izolasyonu, legacy cleanup, quota, backup exclusion ve sign-out purge davranışını doğruluyor. Ana dosyalar: `Norge360/Core/Persistence/CommunityChatBackgroundImageStore.swift`, `Norge360/Core/Auth/SessionCoordinator.swift`, `Norge360/Features/Community/CommunityConversationSettingsView.swift`, `Norge360/Features/Community/CommunityConversationsView.swift`, `Norge360Tests/CommunityChatBackgroundImageStoreTests.swift`.

`CommunityChatBackgroundImageStore.swift` Application Support altında yalnız conversation UUID ile dosya tutuyor; explicit file protection, quota ve sign-out purge yok.

- Yol `userID/conversationID` ile namespace edilmeli.
- `.complete` protection ve backup exclusion uygulanmalı.
- I/O ayrı actor/queue’da yapılmalı.
- Sign-out/account deletion’da temizlenmeli.

### IOS-005 — Image cache gerçek LRU değil ve decode cache’i yok

✅ RESOLVED — Public image cache için periyodik bakım, 200 öğe/50 MiB bounded disk LRU, 100 öğe/32 MiB `NSCache`, stable URL başına in-flight network coalescing ve ImageIO tabanlı thumbnail/full decode varyantları eklendi. Liste/avatar/profile yüzeyleri downsample edilmiş thumbnail, fullscreen yalnız `.full` varyantını kullanıyor; `ProfileTabAvatarLoader` ortak cache yoluna taşındı. Stale purge, LRU eviction, eşzamanlı network coalescing ve decoded cache davranışları regression testleriyle doğrulandı. Ana dosyalar: `Norge360/Core/DesignSystem/CommunityImageCache.swift`, `Norge360/Core/DesignSystem/ProfileTabAvatarLoader.swift`, `Norge360/Core/DesignSystem/CommunityFullscreenImageView.swift`, `Norge360Tests/CommunityImageCacheTests.swift`.

- Okumada modification date dokunuluyor ama stale dosya silinmiyor.
- Byte/item üst sınırı yok.
- Her görünümde `Data(contentsOf:)` + `UIImage(data:)` tekrar edebilir.
- Aynı URL’yi aynı anda açan hücreler ayrı network request başlatabilir.

Memory `NSCache` + bounded disk LRU + in-flight task map üçlüsü uygulanmalı. Scroll listelerinde downsample edilmiş thumbnail variant kullanılmalı; tam çözünürlük yalnız fullscreen’de yüklenmeli.

### IOS-006 — App root `.id(language)` bütün view ağacını yeniden kuruyor

✅ RESOLVED — `Norge360App` root’undan `.id(languageSettings.language)` kaldırıldı. Locale ve layout direction environment güncellemeleri korunarak dil değişimi aynı view/store ağacında uygulanıyor; tab/navigation/view-local state ve gereksiz `.task` yeniden başlatmaları korunuyor. Mevcut store activation/reload coalescing davranışı değiştirilmedi. Build, lint ve full simulator test paketiyle doğrulandı. Ana dosya: `Norge360/App/Norge360App.swift`.

`Norge360App.swift:120-127` dil değişiminde RootView kimliğini değiştiriyor. Bu, view `.task` modifier’larını yeniden tetikleyerek sorgu tekrarına neden olabilir.

- Mümkünse locale/layoutDirection güncellemesini root identity reset olmadan uygula.
- Reset gerekiyorsa store-level `loadIfNeeded` ve in-flight coalescing ile ağ tekrarlarını engelle.

### IOS-007 — O(n²) küçük koleksiyon işlemleri

✅ RESOLVED — `CommunityFeedService` içindeki reply post ID ve post ID dedup akışları, ilk görülme sırasını koruyan `Set` tabanlı `orderedUniquePostIDs` helper’ına taşındı. Her iki akış O(n) çalışıyor; duplicate ID, sıra koruma ve boş input regression testleri eklendi. Ana dosyalar: `Norge360/Core/Persistence/CommunityFeedService.swift`, `Norge360Tests/CommunityFeedServiceTests.swift`.

`CommunityFeedService.swift:105-108` reply post ID dedup işleminde array `contains` kullanıyor. `Set<UUID>` ile O(n) yap. Benzer `map → contains`, nested loops ve Dictionary’nin sonradan üretildiği yerleri Instruments/Time Profiler sonuçlarına göre temizle.

### IOS-008 — Profil medya update akışında gereksiz eski profil yükü

Avatar/cover update, eski storage path’i bulmak için bütün profili ve imzalı avatar/cover’ı yükleyebiliyor. Yalnız old path kolonunu seç veya tek RPC ile path swap + cleanup outbox kaydı oluştur. Client-side best-effort storage cleanup orphan dosya bırakabileceği için server job ile reconcile et.

✅ RESOLVED — Profil medya path swap işlemi, eski path’i cleanup outbox’a atomik olarak ekleyen authenticated RPC’ye taşındı. iOS artık eski profili ve imzalı medyayı update öncesinde yüklemiyor; saatlik Worker job’ı bounded retry ile eski storage objelerini siliyor. SQL regression senaryosu ve mevcut deployment’lar için explicit `anon` ACL repair migration’ı eklendi; iOS build/test ve Worker typecheck doğrulandı.

### IOS-009 — Navigation uyarısını düzelt

Test çıktısında `navigationDestination(item:)` modifier’ının `List`/`LazyVStack` içinde olduğu ve gelecekte yok sayılacağı bildiriliyor. Modifier’ı lazy container dışındaki `NavigationStack` seviyesine taşı. Bu bugün performans hatası değil ama gelecekte navigation’ın çalışmamasına ve görünüm/task yeniden kurulumlarına yol açabilir.

✅ RESOLVED — Lazy feed row içindeki `navigationDestination(item:)` kaldırıldı. Üye profilleri doğrudan `NavigationLink` ile açılıyor; mevcut kullanıcı için `AppTabRouter` üzerinden profile deep-link davranışı korundu. `make build`, SwiftLint ve simulator XCTest/UI visual testleri ile doğrulandı; test çıktısında ilgili navigation warning’i oluşmadı.

### IOS-010 — Uygulama ve asset boyutu

- Asset catalog yaklaşık birkaç MB; `IntroductionNorway.png` tek başına yaklaşık 1.6 MB.
- Onboarding görselleri App Store asset slicing’e uygun olsa da doğru pixel boyutu, HEIF/WebP desteği bağlama göre değerlendirilmelidir; iOS asset catalog compression sonuçları Release archive üzerinden ölçülmeli.
- `.DS_Store` dosyalarını source/resource ağacından çıkar ve repository ignore kuralı ekle.
- Release archive’da App Thinning Size Report, launch dylib süresi ve symbol stripping kontrolü yap.
- Periphery bulgularındaki kullanılmayan ekranları gerçekten future-scope ise target dışında tut; gereksiz binary/code yüzeyini azalt.

⚠️ PARTIALLY RESOLVED — Swift kaynaklarında kullanılmayan `IntroductionNorway` asset’i ve repository/resource ağacındaki dört `.DS_Store` kaldırıldı; root `.gitignore` içine `.DS_Store` kuralı eklendi. Unsigned Release archive karşılaştırmasında archived app 15,012 KiB’den 13,816 KiB’ye, `Assets.car` 4,803,288 byte’tan 3,576,984 byte’a düştü. Release stripping ayarları doğrulandı. App Thinning export’ı archive’da signing team bulunmadığı için yerel ortamda üretilemedi; signed App Store/CI export’ında ayrıca doğrulanmalıdır. Periphery’nin Plan/relocation ekranı bulguları ürünün future-scope birinci sınıf alanı olduğu için silinmedi.

---

## 8. Cloudflare Worker optimizasyon ve güvenlik raporu

Bu bölüm güncel Cloudflare Workers üretim pratikleri esas alınarak incelenmiştir.

### WRK-001 — Private media view URL endpoint’i pahalı çoklu round-trip yapıyor

Tek view URL üretimi kabaca şunları yapabiliyor: Supabase `auth.getUser`, attachment lookup, conversation/group membership ve ban/message/hide kontrolleri, Cloudflare Images detail çağrısı ve signing key erişimi.

**Öneri**

- Yetki kontrollerini tek dar `security definer` RPC’de konsolide et; yalnız provider asset ID ve izin sonucu dönsün.
- Delivery variant/base URL türetilebiliyorsa her görüntülemede Images detail REST çağrısı yapma.
- Signing key’i global bounded config cache’inde tutmaya devam et; parse edilmiş `CryptoKey` de cache’lenebilir.
- Kullanıcı+attachment bazlı kısa TTL view URL cache ve istek coalescing uygula.
- View URL issuance için server-side rate limit ekle.

✅ RESOLVED — Group/direct private-media view yetkilendirmesi service-role-only `issue_community_media_view` RPC’sinde tek database sınırında birleştirildi; aktif üyelik, ban/block, mesaj görünürlüğü, hide ve tarama durumları server-side doğrulanıyor. Worker’da viewer+attachment anahtarlı 30 saniyelik bounded URL cache, in-flight coalescing, 10 dakikalık bounded Cloudflare delivery-detail cache, parsed HMAC key cache ve viewer başına dakikada 60 başarılı view issuance rate limit’i eklendi. Repository’de Cloudflare account hash/variant binding’i bulunmadığından delivery URL tahmini yapılmadı; mevcut provider-detail fallback’i cache’lendi. Worker typecheck ve Wrangler dry-run başarılıdır; SQL regression testi eklendi ancak yerel Supabase CLI/`psql` bulunmadığı için çalıştırılamadı.

### WRK-002 — Google Vision taraması upload completion isteğini blokluyor

Worker görseli indirip maksimum 10 MB buffer’lıyor, base64’e çeviriyor ve Vision cevabını bekliyor. Base64 yaklaşık %33 ek bellek getirir; kullanıcı isteği provider latency’sine bağlı kalır.

**Öneri**

- Completion endpoint `pending_scan` kaydını atomik oluşturup `202 Accepted` dönsün.
- Cloudflare Queue consumer görseli tarasın, normalize sonuç/audit kaydı yazsın ve passed/rejected state transition yapsın.
- Message’a attachment bağlanması yalnız `passed` state’inden server-side RPC ile mümkün olsun.
- Queue retry/dead-letter, idempotency ve maksimum deneme politikası tanımla.

✅ RESOLVED — Group/direct upload completion artık attachment’ı atomik olarak `pending_scan` durumuna geçirip opaque Queue mesajı publish ediyor ve `202 {outcome:"pending_scan"}` dönüyor. Queue consumer `max_batch_size=1`, bounded concurrency ve 5 denemelik retry/DLQ politikasıyla Cloudflare asset doğrulaması ve Google Vision taramasını request dışına taşıyor; yalnız `passed` sonucunda attachment `ready` durumuna geçiriliyor. Service-role-only claim/status/finalize RPC’leri, 2 dakikalık claim lease, idempotent state transition ve scheduled durable outbox dispatcher eklendi. iOS mevcut completion contract’ını koruyarak bounded scan-status polling yapıyor. Worker typecheck, Wrangler dry-run ve iOS simulator build başarılı; SQL regression testi eklendi ancak yerel Supabase CLI/`psql` bulunmadığı için çalıştırılamadı.

### WRK-003 — Saatlik cleanup seri ve çok subrequest’li

Scheduled handler yaklaşık 200 kayıt üzerinde DB update + provider delete + DB delete işlemlerini seri yapıyor.

- DB’de `claim_expired_attachments(batch_size)` RPC ile satırları atomik claim et.
- Queue’ya küçük işler dağıt veya bounded concurrency (ör. 5–10) kullan.
- Cursor/continuation ile bitene kadar sonraki batch’i planla.
- Provider delete idempotent kabul edilen status’ları açıkça işle.
- Açık safety report/audit retention’ı olan medyayı purge etme.

✅ RESOLVED — Unattached direct/group media cleanup artık service-role-only `claim_expired_community_media_attachments` RPC’siyle atomik ve `SKIP LOCKED` kullanarak claim ediliyor; küçük batch’ler ayrı Cloudflare Queue’ya aktarılıyor. Consumer provider deletion’ı en fazla 10 eşzamanlı iş ile yürütüyor, `404` sonucunu idempotent başarı kabul ediyor ve yalnız başarılı/404 deletion sonrasında `finalize_community_media_cleanup` RPC’siyle metadata’yı siliyor. Provider hataları retry/DLQ’ya gidiyor; scheduled dispatcher bounded continuation round’larıyla backlog’u ilerletiyor. `pending_review` ve message’a bağlanmış medya retention nedeniyle kapsam dışında bırakılıyor. Worker typecheck ve Wrangler dry-run başarılı; SQL regression testi eklendi ancak yerel Supabase CLI/`psql` bulunmadığı için çalıştırılamadı.

### WRK-004 — Push webhook senkron teslimat yapıyor

DB webhook → Worker → eligibility/preference/devices → APNs → her device update zinciri request içinde tamamlanıyor. Webhook retry’si duplicate push üretebilir.

- Webhook sadece HMAC/secret doğrula, event ID’yi idempotency tablosunda kaydet ve Queue’ya at; hızlı 2xx dön.
- Consumer batch recipient/device sorgusu ve APNs gönderimi yapsın.
- `(event_id, device_id)` unique delivery ledger kullan.
- APNs invalid/unregistered token’larını batch RPC ile deactivate et.
- Mesaj gövdesi, sender identity, attachment URL veya conversation ID push payload’a eklenmemeli; mevcut privacy-safe yaklaşım korunmalı.

✅ RESOLVED — Webhook artık secret doğrulaması ve opaque event pointer’ı Cloudflare Queue’ya publish etmekle sınırlı; eligibility, preference, active-device lookup ve APNs teslimatı Queue consumer’a taşındı. `community_push_delivery_ledger` `(event_id, device_id)` primary key, lease, bounded attempts ve terminal outcome’larla duplicate push’ları engelliyor. `finalize_community_push_deliveries` tek batch RPC ile delivered timestamp’lerini ve invalid/unregistered cihaz deaktivasyonunu yazıyor. APNs development/production endpoint ayrımı ve generic privacy-safe payload korunuyor. Local migration reset, SQL regression testi, local/linked schema lint, Worker typecheck ve Wrangler dry-run başarılı; linked dev database migration history up to date.

### WRK-005 — Structured logging ve request correlation eksik

Worker’da çoğunlukla string tabanlı `console.error` kullanılıyor.

- Her request’e `request_id` üret/aktar.
- JSON structured log: route, status, duration_ms, operation, outcome, retry_count; user-generated text, token, contact data ve URL query signature loglanmamalı.
- Hono `onError` ile tek hata haritalama noktası oluştur.
- Provider fetch’lerinde `AbortSignal.timeout`, yalnız güvenli/idempotent operasyonlarda exponential backoff+jitter kullan.
- Environment bazında log/trace sampling belirle; `head_sampling_rate=1` üretimde maliyet ve veri hacmi açısından ölçülmeli.

⚠️ PARTIALLY RESOLVED — Worker’a UUID tabanlı request correlation middleware’i eklendi; `X-Request-ID` güvenli UUID ise korunuyor, değilse yeni ID üretiliyor ve response header’a aktarılıyor. Her HTTP isteği route, status, duration_ms, outcome ve retry_count alanlarını içeren JSON log üretiyor. Hono `onError` merkezi ve teknik detayları sızdırmayan `500` response’a taşındı. String tabanlı Worker logları structured logger’a dönüştürüldü; user-generated text, token, contact data ve query string loglanmıyor. Provider çağrılarına 10 saniye `AbortSignal.timeout` eklendi; yalnız GET/HEAD/DELETE için bounded exponential backoff+jitter kullanılıyor, APNs/POST çağrıları duplicate riskinden dolayı otomatik retry edilmiyor. Wrangler observability için query redaction açıldı. Production’a özel sampling oranı ve ayrı staging/production deployment environment’ları WRK-006 kapsamında ayrıca ele alınmaktadır. Worker typecheck, Wrangler dry-run ve local `/health` request-correlation smoke testi başarılıdır.

### WRK-006 — Type-safe binding ve config modernizasyonu

- El yazımı `Bindings` yerine `wrangler types` ile üretilen `Env` tipini kullan.
- `wrangler.toml` çalışıyor; yeni yapılandırmalarda güncel `wrangler.jsonc` formatına kontrollü geçiş değerlendir.
- `nodejs_compat` yalnız gerçekten ihtiyaç varsa eklenmeli; gereksiz compatibility yüzeyi açılmamalı.
- Dev/staging/prod env ve APNs sandbox/production kesin ayrılmalı.
- Secrets sadece `wrangler secret`/secret store üzerinden kalmalı; `.dev.vars` repository’ye girmemeli.

⚠️ PARTIALLY RESOLVED — `wrangler types` ile üretilen `worker-configuration.d.ts` source of truth olarak kullanılmaya başlandı; Worker’daki el yazımı `Bindings` kaldırılarak generated `Env` kullanıldı. Wrangler’ın config’e dahil etmediği secret binding kontratı `src/env.d.ts` ile yalnızca tip seviyesinde tamamlandı; secret değerleri repository’ye yazılmadı. `@cloudflare/workers-types` doğrudan dev dependency ve tsconfig referansı kaldırıldı. Node.js built-in API kullanımı bulunmadığı doğrulandığı için `nodejs_compat` eklenmedi. `.dev.vars`, env dosyaları ve environment-specific local variants `.gitignore` ile korunuyor; `.dev.vars.example` istisna tutuluyor. Mevcut çalışan `wrangler.toml` kontrollü geçiş riski nedeniyle korunmuştur. Gerçek staging/production Supabase URL’leri, Queue isimleri ve secret setleri henüz provision edilmediği için named environment blokları ve production-specific observability sampling bu maddede tamamlanmamıştır. APNs sandbox/production endpoint seçimi device kaydındaki server-side environment alanına göre ayrıdır. Generated types check, Worker typecheck ve Wrangler deploy dry-run başarılıdır.

### WRK-007 — Global cache kullanımı doğru sınırda tutulmalı

Worker’daki bounded APNs token ve Cloudflare key cache’leri request’e özel mutable state değildir ve uygun bir optimizasyondur. Kullanıcı/session/veri sonucu global değişkende cache’lenmemeli; isolate’lar arasında tutarlılık varsayılmamalıdır.

✅ RESOLVED — Repository doğrulamasında request-scoped kullanıcı/session state’inin module-level değişkende tutulduğu bir kullanım bulunmadı. APNs JWT cache’i deployment/provider konfigürasyonu kapsamlı ve 45 dakika ile sınırlı; Cloudflare Images signing key cache’i provider konfigürasyonu kapsamlı ve 10 dakika ile sınırlı. Private media view URL cache’i kullanıcı + attachment + media type anahtarıyla izole, 30 saniye TTL ve 256 kayıt sınırıyla bounded; aynı anahtar için in-flight istekler tamamlandığında temizleniyor. Cloudflare delivery metadata cache’i yalnız image ID metadata’sı içeriyor, 10 dakika TTL ve 256 kayıt sınırı kullanıyor. Bu cache’ler kaynak doğruluğu için değil, provider çağrısı ve imzalama maliyetini azaltmak için best-effort isolate-local optimizasyon olarak kullanılıyor; isolate’lar arası tutarlılık varsayılmıyor. Kod değişikliği gerekmedi. Worker typecheck, generated types check, Wrangler deploy dry-run ve module-level cache kapsamı statik kontrolleri başarılıdır.

### WRK-008 — Supply-chain ve deployment korumaları

- `package-lock.json` ile CI’da `npm ci` kullan.
- `npm audit --omit=dev` şu anda temiz; haftalık otomatik tarama ve Dependabot/Renovate ekle.
- Deploy öncesi `npm run check`, unit test ve secret scan zorunlu olsun.
- Production deploy için ayrı service token, minimum Cloudflare/Supabase yetkisi ve audit log kullan.
- Worker service-role key rotasyon prosedürünü ve olay müdahale runbook’unu yaz.

⚠️ PARTIALLY RESOLVED — Worker’a `npm ci`, `npm audit --omit=dev --audit-level=high`, `npm run check`, `npm run types:check`, `npm test`, secret scan ve `wrangler deploy --dry-run` kapılarını ekleyen pinned GitHub Actions workflow’u oluşturuldu. `actions/checkout` ve `actions/setup-node` tam commit SHA ile sabitlendi; workflow yalnız `contents: read` yetkisi kullanıyor ve production credential taşımıyor. `package-lock.json` ile npm Dependabot ve GitHub Actions Dependabot güncellemeleri haftalık etkinleştirildi. Repository-level secret scanner; gerçek env dosyalarını, private key material’ını ve secret-like assignment’ları değerleri loglamadan reddediyor; Supabase CLI’nin local `supabase/.temp` state’i root `.gitignore` ile korunuyor. Scanner için dört regression testi eklendi. Worker README’sindeki `SUPABASE_URL` secret kurulumu düzeltildi; tüm Worker secret’ları, minimum-scope CI token yaklaşımı, rotation/rollback ve audit-log prosedürü dokümante edildi. `npm ci`, production dependency audit (0 vulnerability), secret scan, 4 test, typecheck, generated types check ve Wrangler dry-run başarılıdır. GitHub repository branch protection, gerçek CI çalıştırması, Cloudflare API token permission set’i, Supabase/Cloudflare audit log erişimi ve production secret rotation dış sistemlerde doğrulanamadığı için bu maddenin operasyonel kısmı açık bırakılmıştır.

---

## 9. Güvenlik sertleştirme kontrol listesi

### Kimlik doğrulama ve oturum

- [x] Tüm sign-out yollarını SessionCoordinator’a taşı.
  - ✅ VERIFIED — `SignOutButton` ve account setup çıkışı `SessionCoordinator.signOut()` kullanıyor; coordinator device deactivation, private-state cleanup ve local auth sign-out sırasını merkezi olarak yönetiyor.
- [x] Supabase session/token yalnız Keychain-uygun SDK storage’da kalsın.
  - ✅ VERIFIED — `SupabaseClientFactory` auth client’ı `KeychainLocalStorage()` ile açıkça oluşturuyor; uygulama tarafında session/token için `UserDefaults`, düz dosya veya log kullanımı bulunmadı.
- [x] Her Worker request’inde bearer token expiry/audience/issuer doğrulansın.
  - ✅ VERIFIED — Worker’ın ortak bearer-auth helper’ı `exp`, `aud=authenticated`, Supabase `iss` ve UUID `sub` claim’lerini Supabase Auth `getUser` çağrısından önce doğruluyor. Staff ve private-media akışları aynı helper’ı kullanıyor; `getUser` imza, session ve revocation için son otorite olarak korunuyor.
- [x] Local JWT doğrulama düşünülürse JWKS rotasyonu ve revocation gecikmesi tehdit modeli yazılsın.
  - ✅ RESOLVED — `Documentation/worker-auth-jwt-threat-model.md` mevcut remote `getUser` kararını, local claim pre-check sınırını, JWKS rotation/stale-key tehditlerini, revocation latency kontrollerini ve local verification için karar kapısını dokümante ediyor. Local JWKS doğrulaması bu maddede eklenmedi.
- [x] 401 sonrası refresh tek-flight olsun; token refresh fırtınası önlensin.
- [x] Deep link/callback URL scheme ve redirect allow-list daraltılsın.
  - ⚠️ PARTIALLY RESOLVED — iOS callback scheme reverse-DNS `com.norge360.app.auth` olarak daraltıldı; yalnızca exact `auth/callback` route’u (OAuth query/fragment parametreleriyle) kabul ediliyor. Supabase local config’e wildcard kullanmadan exact native redirect eklendi; regression testleri yanlış scheme/host/path/userinfo/port değerlerini reddediyor. Hosted Supabase Dashboard allow-list’inde aynı exact URI’nin eklenmesi ve eski `norge360://` URI’sinin kaldırılması dış sistem adımı olarak kaldı.

### Yetkilendirme ve RLS

- [x] Her tablo için anon/authenticated/service-role GRANT matrisi dokümante edilsin.
  - ✅ RESOLVED — `Documentation/supabase-grant-matrix.md` public şemasındaki 51 tablo ve 2 view için local migration baseline’ındaki effective CRUD grant’lerini, RLS durumunu, `community_profiles` column-level istisnasını ve tekrar çalıştırılabilir doğrulama sorgusunu içeriyor. Yeni tabloların migration ile birlikte matrise eklenmesi kuralı belgelendi.
- [x] Public/private projection ayrımı DB seviyesinde yapılsın.
  - ✅ RESOLVED — `community_public_profiles` public alanları DB view’ında maskeliyor; owner için `get_my_community_profile()` RPC kullanılıyor; private source table’de broad authenticated `SELECT` kaldırıldı. Public profile ve aggregate stats view’ları yalnızca authenticated `SELECT` ile sınırlandı; regression SQL testi eklendi.
- [x] Owner, stranger, follower, blocked, group member/admin/owner, moderator test fixture’ları oluşturulsun.
  - ✅ RESOLVED — `supabase/tests/authorization_role_fixtures.sql` tek transaction içinde owner, stranger, follower, blocked user, group member/admin/owner/group moderator ve platform moderator fixture’larını oluşturuyor; public profile/feed visibility, follow-list, group roster/management ve service-side moderation audit akışını doğruluyor. `resolve_community_report` execute-grant hardening’i aşağıdaki security-definer maddesinde tamamlandı. Test sonunda rollback yapılıyor.
- [x] `security definer` fonksiyonların tümünde `search_path=''`, schema-qualified adlar, actor’ın `auth.uid()` ile alınması ve minimum execute grant doğrulansın.
  - ✅ RESOLVED — Local catalog audit’teki 111 public `SECURITY DEFINER` fonksiyonun tamamında boş `search_path` sabit ve schema-qualified referanslar korunuyor. Kullanıcı RPC’leri için authenticated allowlist’i yeniden verildi; Worker/moderation RPC’leri yalnızca `service_role` ile sınırlandı; `anon` için SECURITY DEFINER execute sayısı 0’a indirildi. `supabase/tests/security_definer_grants.sql` ile search_path, allowlist ve server-only sınırları regression olarak doğrulanıyor.
- [x] İstemciden gelen author/user/member/status alanlarına güvenilmesin.
  - ✅ RESOLVED — Authenticated client write grants are now least-privilege: event RSVP, event/group lifecycle, join-request, and moderation mutations are RPC/server-only; report moderation fields cannot be client-inserted; notification actor/target/type fields and post/comment authorship, associations, moderation state, and timestamps cannot be client-updated. Existing RLS checks remain authoritative for caller identity, with `supabase/tests/client_write_boundaries.sql` regression coverage.
- [x] Block iki yönde discovery/read/send sınırında test edilsin.
  - ✅ RESOLVED — `can_view_community_user` ve direct-message erişim sınırının viewer→target ve target→viewer block yönlerinde profil/post discovery, profile search, conversation discovery, message read ve message send davranışları `supabase/tests/block_visibility_and_messaging.sql` ile regression olarak doğrulanıyor. Discovery RPC’sinin column-level grant’lerle kırılmaması için `20260912170000_fix_block_aware_profile_search.sql` aramayı block-aware public profile projection’ına taşıyor.

### Veri minimizasyonu

- [x] `user_account_profiles` içindeki full name, gender ve exact birth date için somut ürün gereksinimi yeniden değerlendirilsin.
  - ✅ RESOLVED — MVP gereksinimi yalnızca seçilebilir public display name ve preferred locale gerektiriyor; full name ayrı tutulmuyor, gender ve exact birth date için hiçbir ürün/backend consumer bulunmadı. Bu alanlar onboarding, Swift account contract ve `user_account_profiles` şemasından kaldırıldı; display name `community_profiles` içinde korunuyor.
- [x] Gerekmiyorsa exact doğum tarihi yerine yaş aralığı/18+ gibi daha az hassas bilgi kullanılsın.
  - ✅ RESOLVED — Exact doğum tarihi önceki veri minimizasyonu değişikliğiyle tamamen kaldırıldı. Yaş aralığı veya 18+ bilgisi gerektiren doğrulanmış bir ürün ihtiyacı bulunmadığından yeni bir hassas alan eklenmedi; mevcut account-profile regression testi alanın saklanmadığını doğruluyor.
- [x] Relocation answers, exact location, private message ve contact data analytics’e gönderilmesin.
  - ✅ RESOLVED — iOS target’ında ürün analytics SDK’sı, `track`/`logEvent` çağrısı veya analytics endpoint’i bulunmuyor. Relocation cevapları plan storage/sync akışında, private message ve contact bilgileri ise yalnızca Auth/Supabase ürün akışlarında kullanılıyor; Cloudflare Worker’da da analytics write çağrısı yok.
- [ ] Hesap silme; profil, plan, device, draft, cache, public content ve retention istisnelerini kapsasın.
- [ ] Veri export/delete ve moderation retention süreleri privacy policy ile eşleşsin.

### Dosya ve medya

- [ ] Private media account-scoped ve `.complete` protected olsun.
- [ ] Backup dışlama, disk quota, LRU ve purge testleri eklensin.
- [ ] MIME header’a güvenmeden magic bytes ve decode doğrulaması yapılsın.
- [ ] Pixel/byte/dimension sınırı ve decompression bomb savunması olsun.
- [ ] EXIF/GPS metadata server veya client’ta strip edilsin.
- [ ] Signed URL’ler log/analytics/clipboard’a istemsiz sızmasın.
- [ ] Quarantine → scan → passed → attached state machine server-enforced olsun.

### API ve abuse prevention

- [ ] Search, username availability, message send, request create, report, upload ve view-url için server-side rate limits.
- [ ] Mutating endpoint’lerde idempotency key.
- [ ] Request body ve response body üst sınırları.
- [ ] Provider çağrılarında timeout/circuit-breaker/dead-letter stratejisi.
- [ ] Moderation ve destructive işlemlerde append-only audit trail.
- [ ] Webhook secret sabit zamanlı karşılaştırma ve rotasyon desteği.

---

## 10. Gözlemlenebilirlik ve ölçüm planı

Optimizasyon “hızlı hissediyor” şeklinde değil, ölçülebilir bütçelerle yönetilmelidir.

### iOS metrikleri

- Cold launch → ilk çizim ve Home usable p50/p95.
- Login → feed visible p50/p95.
- Feed/search/comments/events request count, transferred bytes ve duration.
- Scroll hitch rate, hang rate, peak memory, image decode süresi.
- Crash-free sessions ve MetricKit hang/CPU/memory raporları.
- Realtime reconnect sayısı ve full reconciliation sıklığı.
- Cache hit ratio: decoded memory, disk, URL signature, network.

### Backend metrikleri

- RPC bazında calls, mean/p95/p99, rows returned, bytes.
- `pg_stat_statements`: total_exec_time, mean_exec_time, rows, shared block hit/read.
- Slow query planları ve RLS overhead.
- DB connections, Realtime channel sayısı, WAL/egress.
- Feed page başına ham like/comment satırı transferi sıfıra indirilmeli.
- Search sonuç süresi ve timeout oranı.

### Worker metrikleri

- Route p50/p95/p99, status/error code, subrequest count.
- Queue lag, retry, dead-letter, scan duration/outcome.
- Push event → APNs kabul süresi; duplicate/invalid token oranı.
- View URL cache hit oranı ve rate-limit sayısı.
- Cleanup claimed/deleted/failed/orphan sayısı.

### Başlangıç SLO/query budget önerisi

Bu değerler ilk production ölçümüyle kalibre edilmelidir:

- Home/feed ilk sayfa: istemci açısından en fazla 2 data request, p95 API < 800 ms.
- Comments ilk sayfa: 1 RPC, p95 < 600 ms.
- Explore search: 1 RPC, p95 < 700 ms.
- Event page: 1 RPC, p95 < 600 ms.
- Chat yeni mesaj: full history transferi yok; UI append p95 < 500 ms.
- Private media view URL: auth dahil p95 < 500 ms, cache hit’te backend çağrısı yok.
- Cold login kritik yol: gerekli olmayan sekmeler için 0 request.

Analytics event’leri PII içermemeli; request count ve süre metrikleri içerik gövdesinden tamamen ayrılmalıdır.

---

## 11. Test ve CI’de kapatılması gereken boşluklar

### Mevcut güçlü taraf

Domain kuralları, relocation, calculator, username/search/group kuralları ve görsel review testleri var. 58 test yerelde geçti.

### Eksik test katmanları

- Network/service testleri: pagination, cancellation, request coalescing, stale response suppression.
- Store testleri: login query storm, tab lazy load, mutation sonrası local reconciliation.
- Image cache testleri: account isolation, retention, LRU, sign-out purge, file protection.
- Auth testleri: token refresh single-flight ve 401 retry sınırı.
- SQL/RLS integration: tüm roller ve block yönleri.
- Query plan regression: önemli RPC’ler için staging dataset + maksimum süre/row bütçesi.
- Worker unit/integration: webhook idempotency, APNs 410 deactivation, Queue retry/DLQ, media state transitions.
- Load test: grup push fan-out, feed hot post, search ve chat burst.
- Security test: direct PostgREST ile hidden profile fields’ın okunamaması.

### CI minimum pipeline

1. Secret scan ve repository hygiene.
2. `swift-format --strict`.
3. `swiftlint --strict`.
4. iOS build + 64 mevcut test.
5. Periphery; allow-list dışı yeni warning’de fail.
6. `npm ci`, TypeScript check, Worker tests, production dependency audit.
7. Supabase local start/reset, bütün migrations ve SQL/RLS tests.
8. Migration lint ve destructive-change gate.
9. Release archive smoke test ve artifact size diff.
10. Staging deploy sonrası sentetik feed/search/chat/media testleri.

---

## 12. Uygulama yol haritası

### Faz 0 — 0–3 gün: Güvenlik kapıları

- [x] SEC-001 public profile projection/RPC ve base-table revoke.
- [x] SEC-002 private/public image cache ayrımı ve account purge.
- [x] SEC-003 merkezi sign-out.
- [ ] Gizlilik için entegrasyon testleri.
- [ ] Yorum ekranında tüm profilleri çeken sorguya acil author-ID filtresi.

**Çıkış koşulu:** Ham API testinde hidden field görünmez; hesaplar arası özel medya cache erişimi yok; bütün sign-out yolları device deactivation akışından geçer.

### Faz 1 — 3–7 gün: En hızlı maliyet düşüşleri

- [x] Feed sayfası fan-out ve istemci tarafı tam kayıt sayımlarını aggregate RPC ile kaldır.
- [x] Event likes/RSVP’yi page event IDs ile filtrele.
- [ ] Explore post N+1’i batch load ile kaldır.
- [x] `refreshSession()` per request davranışını düzelt.
- [ ] Avatar/cover imzalama kullanımını ekran bazında ayır ve URL cache ekle.
- [ ] Store in-flight coalescing ve `loadIfNeeded` standardı.
- [x] Image processing’i MainActor dışına taşı.
- [ ] SwiftUI navigation warning’ini düzelt.

### Faz 2 — 1–2 hafta: Veri erişim kontratları

- [ ] Cursor’lı feed RPC.
- [ ] Cursor’lı comments RPC.
- [ ] Cursor’lı event RPC.
- [ ] Enriched/batched search RPC.
- [ ] Cursor’lı inbox/message RPC.
- [ ] Aggregate count ve current-user state’leri server response’a taşı.
- [ ] Explicit DTO/column dönüşümü.

### Faz 3 — 2–4 hafta: Mesajlaşma ve medya ölçekleme

- [x] Realtime delta append + debounce uygulandı; reconnect reconciliation ayrıca izlenmeli.
- [ ] Optimistic send + idempotency.
- [x] Tek-event outbox + Cloudflare Queue push fan-out.
- [ ] Asenkron media scanning queue.
- [ ] Bounded cleanup worker.
- [x] APNs delivery ledger ve batch device updates.

### Faz 4 — Ölçüme dayalı DB tuning

- [ ] `pg_stat_statements` baseline al.
- [ ] Aday indeksleri tek tek staging’de test et.
- [ ] Search trigram/FTS tasarımını gerçek çok dilli veriyle benchmark et.
- [ ] RLS helper planlarını büyük dataset’te ölç.
- [ ] Kullanılmayan/örtüşen indeksleri kaldır.
- [ ] Autovacuum/analyze, connection pool ve Realtime kapasite alarm eşiklerini belirle.

---

## 13. Kabul kriterleri — iş tamamlandı mı?

### Güvenlik

- [x] Public bir kullanıcı hidden location/status değerini hiçbir REST/RPC yolundan alamıyor.
- [ ] Private profil post/media/stats’i stranger tarafından DB seviyesinde okunamıyor.
- [ ] Block iki yönde discovery/request/read/send’i engelliyor.
- [ ] Sign-out sonrası APNs device deaktif ve private local cache temiz.
- [ ] Hiçbir iOS binary/config içinde service-role, APNs key, webhook secret veya provider secret yok.
- [ ] Push payload’ında message body, sender identity, attachment URL veya conversation ID yok.

### Performans

- [ ] Login sırasında yalnız görünür ekran ve bootstrap çağrıları var.
- [ ] Feed/comments/events/search için query budget otomatik test veya telemetry ile izleniyor.
- [x] Realtime event full 200-message reload oluşturmuyor.
- [x] Mesaj gönderimi inbox ve detail için duplicate full reload zinciri oluşturmuyor.
- [ ] Popular post sayaçları için ham likes/comments satırları istemciye inmiyor.
- [x] Signed URL üretimi listelerde öğe sayısıyla birebir büyümüyor veya cache/batch ile kontrol altında.
- [x] Image resize/compress MainActor’da çalışmıyor.
- [ ] Disk cache boyutu sınırlı ve hesap izolasyonu test edilmiş.

### Operasyon

- [ ] Queue retry/DLQ ve idempotency dashboard’u var.
- [ ] Slow query, Worker error, APNs invalid token ve cleanup orphan alarmları var.
- [ ] CI migrations + RLS tests çalıştırıyor.
- [x] Release için rollback/runbook ve secret rotation prosedürü mevcut.

---

## 14. Korunması gereken mevcut iyi uygulamalar

- Supabase service-role ve provider secret’larının iOS istemcisinde bulunmaması.
- RLS ve server-side RPC tercih edilmesi.
- Direct/group messaging’de plain-text limit, reporting, blocking ve staged media yaklaşımı.
- Push bildirimlerinin generic ve privacy-safe tutulması.
- APNs development/production ayrımının tasarlanmış olması.
- Security-definer fonksiyonlarda sabit/boş search path yaklaşımı.
- Swift 6 strict concurrency ve actor tabanlı service sınırları.
- Search debounce/cancellation için mevcut temel.
- Account-scoped community content cache fikri.
- Derleme, strict lint, format ve geniş domain test tabanının temiz olması.
- Worker dependency audit sonucunun temiz olması.

Bu öğeler optimizasyon sırasında zayıflatılmamalıdır. Özellikle “daha hızlı olsun” gerekçesiyle RLS’nin istemciye taşınması, private medyanın public CDN’e açılması, JWT’nin doğrulanmadan decode edilmesi veya push içine mesaj önizlemesi eklenmesi kabul edilebilir optimizasyon değildir.

---

## 15. Referans dosyalar ve dış kaynaklar

### En önemli repository kanıtları

- `Norge360/App/Norge360App.swift`
- `Norge360/Core/Persistence/CommunityFeedService.swift`
- `Norge360/Core/Persistence/CommunityEventsService.swift`
- `Norge360/Core/Persistence/CommunityConversationService.swift`
- `Norge360/Core/Persistence/CommunityGroupChatService.swift`
- `Norge360/Core/Persistence/CommunityPrivateImageTransport.swift`
- `Norge360/Core/DesignSystem/CommunityImageCache.swift`
- `Norge360/Core/DesignSystem/CommunityChatAttachmentImage.swift`
- `Norge360/Features/Community/ExploreView.swift`
- `Norge360/Features/Onboarding/AccountSetupFlowView.swift`
- `Norge360/Core/Auth/SignOutButton.swift`
- `supabase/migrations/20260909020000_add_community_profile_visibility.sql`
- `supabase/migrations/20260909030000_add_community_profile_covers_and_stats.sql`
- `supabase/migrations/20260910100000_add_conversation_preferences_and_message_signals.sql`
- `supabase/migrations/20260910110000_add_private_group_chat_push_signals.sql`
- `supabase/migrations/20260910230000_add_safe_direct_message_image_attachments.sql`
- `supabase/migrations/20260911190000_add_profile_field_visibility.sql`
- `workers/moderation/src/index.ts`
- `workers/moderation/wrangler.toml`

### Resmî teknik kaynaklar

- Cloudflare Workers Best Practices: <https://developers.cloudflare.com/workers/best-practices/workers-best-practices/>
- Cloudflare Queues: <https://developers.cloudflare.com/queues/>
- Supabase Row Level Security: <https://supabase.com/docs/guides/database/postgres/row-level-security>
- Supabase Database Advisors: <https://supabase.com/docs/guides/database/database-advisors>
- Apple Reducing Your App’s Memory Use: <https://developer.apple.com/documentation/xcode/reducing-your-app-s-memory-use>
- Apple Improving Your App’s Performance: <https://developer.apple.com/documentation/xcode/improving-your-app-s-performance>

---

## Son karar

Norge360’ın ana mimari yönü üretime taşınabilir niteliktedir. SEC-001 database projection/RPC, SEC-002 private media cache izolasyonu, SEC-003 merkezi sign-out, PERF-001 login activation storm, PERF-002 feed aggregate RPC, PERF-003 yorum author projection RPC, PERF-004 Explore batch loading, PERF-005 event sayfası ilişkili sorgu filtrelemesi, PERF-006 Realtime delta refresh/debounce, PERF-007 mesaj gönderimi duplicate reload zinciri, PERF-008 signed URL batch/cache kontrolü, PERF-009 özel medya auth refresh kontrolü, PERF-010 background image processing, DB-001 keyset pagination, DB-002 doğrulanmış birleşik indeksler, DB-003 trigram arama indeksleri, DB-004 ayrıştırılmış profil aggregate view, DB-005 server-side sayaç RPC’leri, DB-006 viewer-scoped block anti-join/CTE optimizasyonu, DB-007 scheduled bounded message-signal prune, DB-008 asynchronous bounded group push fan-out, DB-009 bounded chat windows/inbox pagination, DB-010 explicit Supabase select contracts, IOS-001 stale-while-revalidate/request coalescing standardı, IOS-002 CommunityContentCache gizlilik invalidation’ı, IOS-003 protected plan storage, IOS-004 account-scoped chat background storage, IOS-005 bounded image cache/decode/network coalescing, IOS-006 root identity reset düzeltmesi, IOS-007 ordered Set dedup, IOS-008 server-side profile media cleanup outbox, IOS-009 lazy-container navigation düzeltmesi, IOS-010 ölçülebilir asset/metadata temizliği, WRK-001 private media view authorization/cache/rate limit iyileştirmesi, WRK-002 asynchronous community media safety scan, WRK-003 asynchronous bounded community media cleanup ve WRK-004 asynchronous idempotent push delivery ile kapatılmıştır. WRK-005 kapsamında structured logging, request correlation, merkezi error handling ve provider timeout/retry iyileştirmeleri uygulanmıştır. WRK-006 kapsamında generated Env, secret contract augmentation ve local secret dosyası koruması uygulanmış; gerçek staging/production resource provisioning, named environments ve production-specific sampling açık bırakılmıştır. WRK-007 incelemesinde global cache kullanımı doğru sınırlar içinde doğrulanmış ve ek kod değişikliği gerekmemiştir. WRK-008 kapsamında Worker supply-chain/deployment kalite kapısı, secret scan, dependency otomasyonu ve rotation/rollback runbook’u eklenmiş; dış sistem yetkileri ve production provisioning açık bırakılmıştır. 41 isimlendirilmiş audit maddesinin tamamı işlendi. Section 9’daki genel güvenlik checklist’i ve Section 10’daki production ölçüm kalibrasyonu ayrı operasyonel backlog olarak kalmaktadır. IOS-010 kapsamındaki signing gerektiren App Thinning doğrulaması da açık bırakılmıştır. En kalıcı kazanım, istemcinin tablo satırlarını birleştirmesi yerine public/private sınırları açık, cursor’lı ve aggregate sonuçlar üreten küçük server RPC kontratlarına geçmekten gelecektir.
