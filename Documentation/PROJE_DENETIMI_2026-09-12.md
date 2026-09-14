# Norge360 — Güvenlik, Performans, Optimizasyon ve Clean Code Denetimi

**Tarih:** 13 Eylül 2026  
**İncelenen taban commit:** `4c735f3` + mevcut commit edilmemiş değişiklikler  
**Çıktı:** Uygulanan düzeltmeler, doğrulama sonuçları ve kalan yayın öncesi işler.

## Kapsam ve sonuç

- **36 bulgu:** 9 P1, 24 P2, 3 P3. P0 seviyesinde doğrulanmış bir açık tespit edilmedi.
- **P1:** Yayın öncesi ele alınması gereken crash, hesap/veri izolasyonu, veri kaybı veya kritik doğrulama boşluğu. **P2:** Güvenlik sınırı, güvenilirlik, performans ve üretim hazırlığı sorunu. **P3:** Daha düşük öncelikli kalite/sağlamlık iyileştirmesi.
- İnceleme iOS auth/store/service/cache/domain/UI yolları, Worker route/queue/provider akışları, ilgili migration/policy/grant tanımları, testler ve CI üzerinde yapıldı. Otomatik tarama bütün ilgili dosyaları kapsarken ayrıntılı elle inceleme riskli akışlara odaklandı.
- Bulgular aksi belirtilmedikçe kaynak kodun kontrol/veri akışına dayalıdır. Her maddede verilen doğrulama senaryosu çalıştırılmış test ile önerilen ileri doğrulamayı ayıracak şekilde güncellenmiştir.
- Çalışma ağacında denetim başlarken değişiklikler vardı ve inceleme sırasında export dosyaları da güncellendi. Satır bağlantıları rapor oluşturulurken mevcut dosyalardan üretildi; devam eden düzenlemeler satırları kaydırabilir.
- Yerel Supabase katalog sorgusu mevcut migration zincirinin tamamını uygulayamadan `20260912190000` sonrasında kalıyor; Docker/Postgres servisi bu turda erişilebilir değildi. Çalışma ağacındaki zincir `20260913180000_harden_group_scoped_content_visibility.sql` dahil statik olarak incelendi; SQL/RLS runtime kanıtı CI/disposable database çalışmasına bırakıldı.
- Canlı production hesapları/verileri, dış servis ayarları, penetration/load testi, Instruments ölçümü ve tam SQL/RLS test paketi çalıştırılmadı. Yerel DB yalnızca katalog sorgularıyla okundu; migration uygulanmadı. Bu rapor bütün olası hataların yokluğunu garanti eden bir güvenlik sertifikası değildir.

## Çalıştırılan kontroller

| Kontrol | Sonuç |
|---|---|
| iOS Debug build + Simulator test | iPhone 17 Pro / iOS 26.5 üzerinde son runner başarılı: 145 toplam test, 144 başarılı, 1 atlanan, 0 hata. |
| `npm run check` | TypeScript kontrolü başarılı. |
| `npm audit --omit=dev --audit-level=high` | 0 bilinen güvenlik açığı. Yalnız production npm bağımlılıkları. |
| `python3 scripts/check_worker_secrets.py` | 407 metin dosyası kontrol edildi; eşleşme yok. Git geçmişinin tam taraması yapılmadı. |
| `npm test` (Worker) | 16 statik/kontrat + 6 runtime handler testi başarılı. Provider/Queue/Supabase disposable integration kapsamı TEST-02’de. |
| Explicit Supabase select kontrolü | Başarılı. |
| Localization kontrolü | 16 dil, 1081 key: başarılı. Dil/editoryal doğruluk anlamına gelmez. |
| `make format-check` | Başarılı. |
| `swiftlint lint --strict` | Başarılı: 179 Swift dosyası, 0 ihlal. |
| `git diff --check` | Başarılı. |
| Yerel public tablo RLS kataloğu | RLS kapalı normal public tablo sayısı: 0. |
| Yerel SECURITY DEFINER kataloğu | Boş search_path sabiti olmayan: 0; anon tarafından çalıştırılabilen: 0. Politika mantığının tümü için güvenlik kanıtı değildir. |

## Madde madde düzeltme listesi

### BUG-01 — P1 — Aynı yazarın iki yorumu yorum ekranını çökertebilir

- [x] **✅ RESOLVED.** Yorum author profilleri userID bazında ilk kayıt korunacak şekilde tekilleştiriliyor; profile sözlüğü duplicate-safe oluşturuluyor. Yorum kayıtlarının kendisi değiştirilmeden korunuyor.
- **Kanıt:** [Norge360/Core/Persistence/CommunityFeedService.swift:484](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/CommunityFeedService.swift:484); [Norge360/Core/Persistence/CommunityProfileMediaSigner.swift:67](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/CommunityProfileMediaSigner.swift:67).
- **Uygulanan çözüm:** `orderedUniqueProfiles` ve `profilesByUserID` yardımcıları ile imzalama öncesi ve sonrası duplicate author kayıtları güvenli biçimde işleniyor. İlk author profili birleştirme politikasıdır; yorumlar aynen döndürülüyor.
- **Doğrulama:** Aynı author’ın iki kaydı ve farklı bir author içeren regression testi eklendi; duplicate author tekilleştiriliyor, distinct author korunuyor ve ilk kayıt seçiliyor.

### SEC-01 — P1 — Bekleyen plan kaydı hesaplar arasında taşınabilir

- [x] **✅ RESOLVED.** Plan senkronizasyonu beklenen userID ile sınırlandı; hesap değişiminde generation kontrolü eski persistence işinin yeni kullanıcıya gönderilmesini engelliyor.
- **Kanıt:** [Norge360/App/AppState.swift:139](/Users/macbook/Documents/Norge360/Norge360/App/AppState.swift:139); [Norge360/Core/Persistence/PlanSynchronizing.swift:38](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/PlanSynchronizing.swift:38).
- **Uygulanan çözüm:** `PlanSynchronizing` load/save API’leri beklenen userID alıyor; Supabase implementation token kullanıcısını bu ID ile doğruluyor. `AppState` hesap generation’ı değiştiğinde eski persistence işi remote save aşamasında durduruluyor.
- **Doğrulama:** Bekleyen A plan kaydı sırasında B hesabına geçişi simüle eden regression testi eklendi; network synchronizer yalnızca A userID’si ile çağrılıyor.

### SEC-02 — P1 — Veri dışa aktarımı kullanıcıyı engelleyen hesapları açığa çıkarıyor

- [x] **✅ RESOLVED.** Export RPC’si artık yalnızca veri sahibinin oluşturduğu blok kayıtlarını döndürüyor; karşı yöndeki blok ilişkisi ve bloklayan hesabın kimliği export’a dahil edilmiyor.
- **Kanıt:** [supabase/migrations/20260912200000_add_account_export_and_moderation_retention.sql:150](/Users/macbook/Documents/Norge360/supabase/migrations/20260912200000_add_account_export_and_moderation_retention.sql:150); [supabase/migrations/20260908230000_create_community_foundation.sql:244](/Users/macbook/Documents/Norge360/supabase/migrations/20260908230000_create_community_foundation.sql:244).
- **Uygulanan çözüm:** `blocks` export sorgusu yalnız `blocker_id = account_user_id` koşulunu kullanacak şekilde daraltıldı. A’nın B’yi, B’nin de A’yı engellediği fixture ile A export’unda yalnız A’nın oluşturduğu kayıt doğrulanıyor.
- **Doğrulama:** `supabase/tests/account_export_and_moderation_retention.sql` export’ta tek ve doğru yönlü block kaydını, ters yönlü incoming block ilişkisinin yokluğunu test ediyor.

### SEC-03 — P1 — Hesap silme açık raporun mesaj delilini ve diğer tarafın konuşmasını silebilir

- [x] **✅ RESOLVED.** Hesap silme artık direct conversation, mesaj gövdesi ve bağlı direct medya metadata/provider referanslarını cascade ile yok etmiyor. Silinen kullanıcının Auth/profil kayıtları kaldırılıyor; kalan katılımcı konuşma geçmişini genel bir “Deleted member” kimliğiyle görmeye devam ediyor.
- **Kanıt:** [supabase/migrations/20260912210000_preserve_direct_message_history_on_account_deletion.sql:5](/Users/macbook/Documents/Norge360/supabase/migrations/20260912210000_preserve_direct_message_history_on_account_deletion.sql:5); [workers/moderation/src/index.ts:1000](/Users/macbook/Documents/Norge360/workers/moderation/src/index.ts:1000); [supabase/tests/account_deletion_retention.sql:290](/Users/macbook/Documents/Norge360/supabase/tests/account_deletion_retention.sql:290).
- **Uygulanan çözüm:** Direct conversation/message/attachment tablolarındaki Auth cascade bağlantıları kaldırıldı. Conversation erişimi, kalan aktif membership ve silinmiş Auth kullanıcısı için generic fallback ile sınırlandı; inbox ve private-media RPC’leri bu senaryoyu destekliyor. Account deletion Worker bağlı direct medya varlıklarını silme listesinden çıkarıyor; yalnız unattached staged medya normal cleanup’a bırakılıyor.
- **Doğrulama:** İki katılımcılı aktif konuşma, iki mesaj, direct attachment ve açık message report fixture’ında hesap silindi. Auth/profile kayıtları silinirken conversation, iki mesajın geçmişi, attachment/provider referansı ve report target korundu; kalan kullanıcı inbox, mesaj ve medya RPC’leri üzerinden erişebildi. SQL testleri, local migration reset’i, schema lint’i ve Worker type/security testleri başarılı.

### SEC-04 — P1 — Hesap silme başarısız olduğunda geri döndürülemeyen ara değişiklikler kalıyor

- [x] **✅ RESOLVED.** Hesap silme artık HTTP isteği içinde provider/Auth temizliğini tamamlamaya çalışmıyor; kalıcı, service-role erişimli deletion job oluşturup `202 Accepted` döndürüyor. Job, beş dakikalık cron ile bounded media batch’leri halinde yeniden çalışıyor.
- **Kanıt:** [workers/moderation/src/index.ts:294](/Users/macbook/Documents/Norge360/workers/moderation/src/index.ts:294); [workers/moderation/src/index.ts:1167](/Users/macbook/Documents/Norge360/workers/moderation/src/index.ts:1167); [supabase/migrations/20260912220000_make_account_deletion_resumable.sql:1](/Users/macbook/Documents/Norge360/supabase/migrations/20260912220000_make_account_deletion_resumable.sql:1); [workers/moderation/wrangler.toml:6](/Users/macbook/Documents/Norge360/workers/moderation/wrangler.toml:6).
- **Uygulanan çözüm:** `community_account_deletion_jobs` ve per-object media inventory tabloları eklendi. Deletion-pending job varken authenticated client yazıları veritabanı trigger sınırında reddediliyor. Storage/provider envanteri kalıcılaştırılmadan `prepare_community_account_deletion` çağrılmıyor; her nesne idempotent olarak claim/complete/retry ediliyor. Başarısız provider çağrıları ve Worker çökmesi lease süresi sonrasında yeniden alınabiliyor; Auth silme yalnız cleanup tamamlandıktan sonra yapılıyor.
- **Doğrulama:** Local migration reset, `account_deletion_retention.sql`, account export/retention, client write-boundary ve security-definer SQL testleri; `supabase db lint --local`; Worker TypeScript check, Wrangler types check, static security test ve `git diff --check` başarılı.

### BUG-02 — P1 — Bildirimlerin hata geri alma kodu eski dizi indeksini kullanıyor

- [x] **✅ RESOLVED.** Bildirim mutation rollback’leri artık eski dizi indeksine veya eski hesap snapshot’ına koşulsuz dönmüyor. Hesap nesli ve liste state nesli doğrulanıyor; rollback yalnız aynı hesap ve aynı liste state’i hâlâ geçerliyse uygulanıyor.
- **Kanıt:** [Norge360/App/CommunityNotificationsStore.swift:95](/Users/macbook/Documents/Norge360/Norge360/App/CommunityNotificationsStore.swift:95); [Norge360/App/CommunityNotificationsStore.swift:123](/Users/macbook/Documents/Norge360/Norge360/App/CommunityNotificationsStore.swift:123); [Norge360/App/CommunityNotificationsStore.swift:152](/Users/macbook/Documents/Norge360/Norge360/App/CommunityNotificationsStore.swift:152); [Norge360/App/CommunityNotificationsStore.swift:190](/Users/macbook/Documents/Norge360/Norge360/App/CommunityNotificationsStore.swift:190).
- **Uygulanan çözüm:** `markRead` rollback’i notification ID ve optimistic timestamp ile yeniden doğruluyor. `delete` insertion index’ini yalnız değişmemiş aynı state’te kullanıyor. `markAllRead` eski snapshot’ı yalnız aynı kullanıcı/list state’i korunmuşsa geri yüklüyor. Reload, hesap değişimi ve profil propagation liste neslini ilerletiyor.
- **Doğrulama:** Hesap değişimi sırasında başarısız `markRead`/`delete`, aynı hesapta reload sırasında başarısız `markRead` ve eski snapshot’ın yeni hesaba geri yüklenmemesi için regression testleri eklendi. iOS Simulator’da 11 hedefli test, build ve test başarılı.

### BUG-03 — P1 — Plan senkronizasyonu çevrimdışı değişiklikleri ve son kaydı kaybedebilir

- [x] ✅ **RESOLVED.** Yerel plan snapshot’ı artık account-scoped `revision` ve `isDirty` metadata’sı ile korunuyor. Kirli yerel ilerleme uzak planla koşulsuz ezilmiyor; uzak kayıt monoton revision RPC’siyle stale snapshot’ları reddediyor. Hesap başına tek seri yazım kuyruğu, bounded retry ve kullanıcıya görünür sync/retry durumu eklendi.
- **Kanıt:** [Norge360/App/AppState.swift:7](/Users/macbook/Documents/Norge360/Norge360/App/AppState.swift:7); [Norge360/Core/Persistence/PlanStore.swift:3](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/PlanStore.swift:3); [Norge360/Core/Persistence/PlanSynchronizing.swift:4](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/PlanSynchronizing.swift:4); [supabase/migrations/20260912230000_add_versioned_relocation_plan_sync.sql](/Users/macbook/Documents/Norge360/supabase/migrations/20260912230000_add_versioned_relocation_plan_sync.sql).
- **Uygulanan çözüm:** Remote plan yalnızca temiz local snapshot varsa benimseniyor. Dirty local snapshot korunuyor ve queue üzerinden yeniden deneniyor. Her başarılı remote save sonrasında snapshot temiz işaretleniyor; conflict durumunda local son plan server revision üstüne rebased edilerek tekrar gönderiliyor. Anonymous → authenticated migration, account switch ve cancellation generation kontrolü ile scope dışına taşmıyor.
- **Doğrulama:** Offline dirty snapshot’ın yeniden açılışta korunması, fail-once retry, account switch sırasında eski scope’un korunması, iki ardışık remote save’in seri çalışması ve ikinci kaydın en güncel task durumunu taşıması regression testleriyle doğrulandı. Local Supabase `db reset --local --no-seed` ve `supabase db lint --local` başarılı; hedefli iOS testleri başarılı.

### SEC-05 — P2 — APNs deactivation başarısızken oturum yine kapatılıyor

- [x] ✅ **RESOLVED.** Device deactivation artık başarılı local sign-out için önkoşul. Deactivation başarısızsa oturum, private local state ve mevcut kullanıcı korunuyor; sign-out hazırlığı iptal edilerek retry mümkün kalıyor. Başarılı deactivation olmadan Supabase local sign-out çağrılmıyor.
- **Kanıt:** [Norge360/Core/Auth/SessionCoordinator.swift:70](/Users/macbook/Documents/Norge360/Norge360/Core/Auth/SessionCoordinator.swift:70); [Norge360/App/PushNotificationsStore.swift:70](/Users/macbook/Documents/Norge360/Norge360/App/PushNotificationsStore.swift:70).
- **Uygulanan çözüm:** `SessionCoordinator.signOut()` deactivation sonucunu auth sign-out ve private-state temizliğinden önce doğruluyor. Başarısızlıkta `abortSignOutPreparation()` çağrılıp hata döndürülüyor; başarılı akışın sırası korunuyor.
- **Doğrulama:** `SessionCoordinatorTests.testSignOutPreservesSessionWhenDeviceCleanupFails` deactivation hatasında auth sign-out ve private-state temizliğinin çağrılmadığını, sign-out hazırlığının iptal edildiğini doğruluyor. Targeted iOS testleri 4/4 başarılı.

### SEC-06 — P2 — Taslaklar ve dışa aktarılmış dosyalar hesap temizliğine dahil değil

- [x] **✅ RESOLVED.** Taslaklar owner-scoped Keychain purge ile sign-out/account-delete temizliğine dahil edildi; purge sonrasında gecikmiş SwiftUI save task’larının aynı taslağı yeniden yazmasını önlemek için owner session token’ı eklendi. Export dosyaları user-scoped protected klasörde `.atomic` + `.completeFileProtection` ile yazılıyor, legacy geçici export’lar lifecycle temizliğinde kaldırılıyor ve paylaşım tamamlandığında/cancel edildiğinde siliniyor.
- **Kanıt:** [Norge360/Core/Auth/SessionCoordinator.swift:57](/Users/macbook/Documents/Norge360/Norge360/Core/Auth/SessionCoordinator.swift:57); [Norge360/Core/Persistence/CommunityMessageDraftStore.swift:120](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/CommunityMessageDraftStore.swift:120); [Norge360/Core/Auth/AccountDataExportService.swift:32](/Users/macbook/Documents/Norge360/Norge360/Core/Auth/AccountDataExportService.swift:32).
- **Uygulanan çözüm:** `CommunityMessageDraftStore` owner hesaplarını enumerate edip yalnız ilgili kullanıcının Keychain kayıtlarını siliyor; `SessionCoordinator` mevcut kullanıcı kimliğiyle merkezi temizliği çağırıyor. `AccountDataExportFileStore` export’u kullanıcı klasörüne yazıyor, eski export formatını da temizliyor. Native share sheet completion/cancel callback’i export dosyasını siliyor.
- **Doğrulama:** `CommunityMessageDraftStoreTests` owner isolation ve purge sonrası stale save engelini; `AccountDataExportFileStoreTests` owner-scoped disk temizliğini; `SessionCoordinatorTests` cleanup sırasını doğruluyor. Targeted iOS testleri 7/7 başarılı; Swift Format lint, `git diff --check` ve iOS simulator build başarılı.

### SEC-07 — P2 — Özel medya URL cache’i yeni block/ban kararını atlıyor

- [x] **✅ RESOLVED.** Her private media view-url isteği artık cache değerlendirilmeden önce `issue_community_media_view` RPC’siyle güncel block/ban/membership/status ve rate-limit kararından geçiyor. Cache yalnız provider signing maliyetini azaltıyor; 30 saniyelik cache girdisi güncel `provider_asset_id` ile eşleşmeden kullanılmıyor.
- **Kanıt:** [workers/moderation/src/index.ts:1431](/Users/macbook/Documents/Norge360/workers/moderation/src/index.ts:1431); [workers/moderation/src/index.ts:1450](/Users/macbook/Documents/Norge360/workers/moderation/src/index.ts:1450); [supabase/migrations/20260912090000_optimize_private_media_view_authorization.sql:152](/Users/macbook/Documents/Norge360/supabase/migrations/20260912090000_optimize_private_media_view_authorization.sql:152).
- **Uygulanan çözüm:** Authorization ve cache sırası ayrıştırıldı. In-flight deduplication yalnız güncel authorization başarılı olduktan sonra provider imzalama bölümünde çalışıyor; böylece cache hit veya eşzamanlı provider isteği güncel yetki kontrolünü atlayamıyor.
- **Doğrulama:** Worker TypeScript check, Wrangler types check, secret scan ve 9 maddelik Worker security regression suite başarılı. Regression testi authorization RPC’nin cache lookup’tan önce kaldığını ve eski cache-hit bypass pattern’inin bulunmadığını doğruluyor.

### SEC-08 — P2 — Upload rate limit eşzamanlı isteklerle aşılabilir

- [x] **✅ RESOLVED.** Her iki upload-url yolu count sorgusu ile attachment insert’ünü ayrı yapıyor. Aynı anda gelen istekler aynı sayıyı görerek 6/dakika sınırını geçebilir. İptal/deletion attachment kaydını sildiği için kota geçmişi de silinir. Provider upload URL üretimi maliyetli bir yetkidir.
- **Kanıt:** [workers/moderation/src/index.ts:404](/Users/macbook/Documents/Norge360/workers/moderation/src/index.ts:404); [workers/moderation/src/index.ts:590](/Users/macbook/Documents/Norge360/workers/moderation/src/index.ts:590).
- **Önerilen düzeltme:** Kota rezervasyonu ve staging’i tek atomik RPC’ye taşı; attachment yaşam döngüsünden bağımsız kullanıcı bazlı sayaç kullan.
- **Doğrulama:** Aynı kullanıcıdan 20 eşzamanlı istek ve oluştur-sil-tekrar oluştur dizisiyle limitin gerçekten 6 olduğunu doğrula.
- **Çözüm notu:** `community_media_upload_rate_limits` tablosu ve service-role-only staging RPC’leri eklendi; group/direct upload endpoint’leri kota rezervasyonunu ve attachment staging’ini tek transaction’da yapıyor. SQL regression testi, SECURITY DEFINER grant testi ve local Postgres üzerinde 20 paralel istek doğrulaması başarılı.

### SEC-09 — P2 — Worker JSON gövdelerinde byte sınırı ve tutarlı runtime schema yok

- [x] **✅ RESOLVED.** Kontrol route’ları JSON’u parse etmeden önce streaming byte limiti uyguluyor; eksik/geçersiz `Content-Length`, chunked büyük gövde ve nesne olmayan JSON reddediliyor. Route bazlı runtime alan doğrulamaları bozuk tipleri 400’e indiriyor. Medya güvenlik taraması da provider response gövdesini stream ederek 10 MiB üstünü erken kesiyor.
- **Kanıt:** [workers/moderation/src/index.ts](/Users/macbook/Documents/Norge360/workers/moderation/src/index.ts); [scripts/test_worker_security.py](/Users/macbook/Documents/Norge360/scripts/test_worker_security.py).
- **Doğrulama:** Worker testleri bounded request body, runtime schema ve bounded provider response sözleşmelerini kontrol ediyor; `npm run check`, Wrangler type check, test ve secret scan başarılı.

### SEC-10 — P2 — Arama ve export için uygulama düzeyinde server rate limit eksik

- [x] **✅ RESOLVED.** Arama, hashtag araması ve username availability kullanıcı başına transaction-safe bucket kotası kullanıyor. Account export aynı kota mekanizmasına bağlı; Worker metadata ve allowlisted section sayfalarını stream ederek DB/Worker belleğinde tek büyük JSON ağacı oluşturmuyor. Limit aşımında `429` + `Retry-After` döndürülüyor.
- **Kanıt:** [supabase/migrations/20260913110000_add_community_request_rate_limits.sql](/Users/macbook/Documents/Norge360/supabase/migrations/20260913110000_add_community_request_rate_limits.sql); [supabase/migrations/20260913120000_add_paginated_account_export.sql](/Users/macbook/Documents/Norge360/supabase/migrations/20260913120000_add_paginated_account_export.sql); [workers/moderation/src/index.ts:400](/Users/macbook/Documents/Norge360/workers/moderation/src/index.ts:400); [supabase/tests/community_request_rate_limits.sql](/Users/macbook/Documents/Norge360/supabase/tests/community_request_rate_limits.sql).
- **Kalan operasyonel kapsam:** Çok uzun export’lar için background job/short-lived download token ve production p95/RAM ölçümü ayrıca yapılmalı.
- **Doğrulama:** Worker security testleri ve migration contract testleri eklendi. Local SQL execution Docker yokluğu nedeniyle henüz çalıştırılamadı.

### SEC-11 — P2 — Approval/private grup içeriği bazı projection yollarında sızabiliyor

- [x] **✅ RESOLVED.** Grup görünürlüğü artık keşif metadata’sından bağımsız içerik yetkisi olarak uygulanıyor: `public` grup içeriği açık, `approval_required` ve `private` içerik yalnızca kabul edilmiş üyeye açık. Bekleyen istek ve davet içerik erişimi vermiyor.
- **Kanıt:** [supabase/migrations/20260913180000_harden_group_scoped_content_visibility.sql](/Users/macbook/Documents/Norge360/supabase/migrations/20260913180000_harden_group_scoped_content_visibility.sql); [supabase/tests/group_content_visibility.sql](/Users/macbook/Documents/Norge360/supabase/tests/group_content_visibility.sql); [supabase/tests/security_definer_grants.sql](/Users/macbook/Documents/Norge360/supabase/tests/security_definer_grants.sql).
- **Uygulanan çözüm:** Post/comment/media/like/edit-history/hashtag RLS politikaları üyelik kontrolüyle güncellendi; grup ve post-media Storage policy’leri aynı sınırı uyguluyor. Salt-okuma feed, comment, member-media ve search projection RPC’leri `SECURITY INVOKER` yapılarak RLS’nin son yetki sınırı olması sağlandı. SECURITY DEFINER like/save mutation ve liked/saved ID projection’larına da aynı grup yetkisi eklendi. Private profilde kullanıcının kendi içeriğini görme davranışı korunuyor.
- **Doğrulama:** Approval/private grup için stranger/member fixture testi eklendi. Docker daemon olmadığı için bu turda disposable Supabase runtime çalıştırılamadı; migration ve policy sözleşmesi statik olarak incelendi.

### BUG-04 — P2 — Medya iptali ve gönderi silme provider hatasında sahipsiz nesne bırakıyor

- [x] **✅ RESOLVED.** Direct/group preview iptali zaten attachment durumunu kalıcı cleanup kuyruğunda tutuyordu. Public gönderi medyası silme ve grup fotoğrafı değiştirme artık veritabanı transaction’ı içinde Storage outbox kaydı oluşturuyor; istemci Storage çağrısı beklemiyor. Server-only Worker bounded retry ile nesneyi siliyor ve başarılı kayıtları retention sonrası buduyor.
- **Kanıt:** [supabase/migrations/20260913130000_add_public_storage_cleanup_outbox.sql](/Users/macbook/Documents/Norge360/supabase/migrations/20260913130000_add_public_storage_cleanup_outbox.sql); [workers/moderation/src/index.ts](/Users/macbook/Documents/Norge360/workers/moderation/src/index.ts); [Norge360/Core/Persistence/CommunityFeedService.swift](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/CommunityFeedService.swift); [Norge360/Core/Persistence/CommunityGroupsService.swift](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/CommunityGroupsService.swift).
- **Doğrulama:** `supabase/tests/community_storage_cleanup.sql` post-media cascade ve group-photo replacement outbox davranışını; `security_definer_grants.sql` Worker-only purge yetkisini kapsıyor. Docker çalışmadığı için bu turda local SQL execution yapılamadı; migration statik olarak kontrol edildi.

### BUG-05 — P2 — Push lease ile Queue retry uyuşmazlığı bildirimi kaybettirebilir

- [x] **✅ RESOLVED.** Claim RPC artık `claimed`, `leased`, `terminal` ve `available` durumlarını ayırıyor. Aktif lease varken Worker mesajı ack etmiyor; kalan lease süresine göre retry ediyor. Süresi dolan ledger kayıtları scheduled recovery dispatcher tarafından bounded olarak `pending` durumuna alınıp yeniden kuyruğa gönderiliyor.
- **Kanıt:** [supabase/migrations/20260913100000_harden_push_delivery_leases.sql](/Users/macbook/Documents/Norge360/supabase/migrations/20260913100000_harden_push_delivery_leases.sql); [workers/moderation/src/index.ts](/Users/macbook/Documents/Norge360/workers/moderation/src/index.ts).
- **Doğrulama:** SQL grant/ledger contract testleri ve Worker check/test paketi başarılı; tam provider/APNs failure injection testi production dışı operasyonel kapsamda kalıyor.

### BUG-06 — P2 — Medya taraması kısa polling penceresini aşınca yükleme kimliği kayboluyor

- [x] **✅ RESOLVED.** Polling penceresi dolduğunda attachment kimliği kaybolmuyor; typed `pendingScan` hatası ile yerel owner/chat-scoped pending store’a kaydediliyor. Ekran yeniden açıldığında aynı attachment’ın status’ü sorgulanıyor; cancel ve expiration yolları da mevcut.
- **Kanıt:** [Norge360/Core/Persistence/CommunityPrivateImageTransport.swift](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/CommunityPrivateImageTransport.swift); [Norge360/Core/Persistence/CommunityPendingImageStore.swift](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/CommunityPendingImageStore.swift); [Norge360/Features/Community/CommunityConversationsView.swift](/Users/macbook/Documents/Norge360/Norge360/Features/Community/CommunityConversationsView.swift).
- **Doğrulama:** `CommunityPendingImageStoreTests` owner/chat izolasyonunu ve sınır davranışını; iOS test paketi 128 testte sıfır hata ile bu akışı derliyor.

### PERF-01 — P2 — Hesap export’u verinin tamamını DB, Worker ve iOS belleğinde çoğaltıyor

- [~] **Büyük ölçüde düzeltildi.** Yeni export yolu scalar metadata + allowlisted, bounded section sayfaları döndürüyor; Worker JSON’u parça parça stream ediyor; iOS `download(for:)` ile geçici dosyayı protected owner-scoped klasöre taşıyor. Eski all-at-once RPC yalnız geriye dönük uyumluluk için tutuluyor ve HTTP route tarafından kullanılmıyor.
- **Kanıt:** [supabase/migrations/20260913120000_add_paginated_account_export.sql](/Users/macbook/Documents/Norge360/supabase/migrations/20260913120000_add_paginated_account_export.sql); [workers/moderation/src/index.ts:400](/Users/macbook/Documents/Norge360/workers/moderation/src/index.ts:400); [Norge360/Core/Auth/AccountDataExportService.swift:32](/Users/macbook/Documents/Norge360/Norge360/Core/Auth/AccountDataExportService.swift:32).
- **Kalan kapsam:** Çok büyük/veri yoğun hesaplarda background job + kısa ömürlü indirme token’ı ve production peak memory/p95 ölçümü.
- **Önerilen düzeltme:** Export’u gerektiğinde background job olarak üret; bounded sayfalar/stream ve kısa ömürlü yetkili indirme kullan. Geniş `table.*` alanları yalnız explicit allowlist ile eklenmeye devam etmeli.
- **Doğrulama:** Çok sayıda gönderi/mesajı olan fixture ile export boyutu, peak memory, süre ve retry davranışını ölç.

### PERF-02 — P2 — Özel görsellerde indirme ve decode sınırı eksik

- [~] **Büyük ölçüde düzeltildi.** iOS private loader akış halinde 12 MiB byte budget uyguluyor; ImageIO source pixel/dimension doğrulaması ve variant’a göre downsample decode’u kullanıyor. Editable preview `@State` içinde hazır thumbnail tutuyor. Worker provider blob’u `arrayBuffer()` ile kontrol sonrası değil, bounded stream ile 10 MiB sınırını aşınca erken reddediyor.
- **Kalan kapsam:** Görsel decode için gerekli üst sınırdaki Data ve ImageIO geçici pik belleği tamamen sıfırlanamaz; production Instruments peak-memory/hitch baseline’ı ayrıca alınmalı.
- **Kanıt:** [Norge360/Core/Persistence/CommunityMediaService.swift](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/CommunityMediaService.swift); [Norge360/Core/DesignSystem/CommunityPrivateImageCache.swift](/Users/macbook/Documents/Norge360/Norge360/Core/DesignSystem/CommunityPrivateImageCache.swift); [Norge360/Core/DesignSystem/NorgeEditableImagePreview.swift](/Users/macbook/Documents/Norge360/Norge360/Core/DesignSystem/NorgeEditableImagePreview.swift); [workers/moderation/src/index.ts](/Users/macbook/Documents/Norge360/workers/moderation/src/index.ts).

### PERF-03 — P2 — Yorumlar sınırsız, profil ve grup listeleri devam sayfası olmadan kesiliyor

- [x] **✅ Büyük ölçüde çözüldü.** Yorumlar, grup gönderileri, profil gönderi/yanıt sekmeleri, medya sekmesi ve bildirimler artık server-side keyset cursor + `nextCursor/hasMore` kontratıyla sayfalanıyor; iOS yalnız listenin sonuna gelindiğinde devam sayfasını yüklüyor. Medya akışı, son 30 gönderiyi çekip sonradan filtrelemek yerine yalnızca görünür ve gerçekten medyası olan post kimliklerini RPC ile alıyor.
- **Kalan operasyonel kapsam:** Production p95/byte/peak-memory ölçümleri ve cursor RPC’lerinin disposable Supabase/RLS runtime testi.
- **Kanıt:** [supabase/migrations/20260913160000_add_paginated_community_post_comments.sql](/Users/macbook/Documents/Norge360/supabase/migrations/20260913160000_add_paginated_community_post_comments.sql); [supabase/migrations/20260913170000_add_paginated_community_member_media.sql](/Users/macbook/Documents/Norge360/supabase/migrations/20260913170000_add_paginated_community_member_media.sql); [Norge360/Core/Persistence/CommunityFeedService.swift](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/CommunityFeedService.swift); [Norge360/App/CommunityFeedStore.swift](/Users/macbook/Documents/Norge360/Norge360/App/CommunityFeedStore.swift); [Norge360/Core/Persistence/CommunityNotificationService.swift](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/CommunityNotificationService.swift); [Norge360/App/CommunityNotificationsStore.swift](/Users/macbook/Documents/Norge360/Norge360/App/CommunityNotificationsStore.swift); [Norge360/Features/Community/CommunityNotificationsView.swift](/Users/macbook/Documents/Norge360/Norge360/Features/Community/CommunityNotificationsView.swift); [Norge360/Features/Community/CommunityPostCommentsView.swift](/Users/macbook/Documents/Norge360/Norge360/Features/Community/CommunityPostCommentsView.swift); [Norge360/Features/Groups/CommunityGroupsView.swift](/Users/macbook/Documents/Norge360/Norge360/Features/Groups/CommunityGroupsView.swift); [Norge360/Features/Profile/CommunityMemberProfileView.swift](/Users/macbook/Documents/Norge360/Norge360/Features/Profile/CommunityMemberProfileView.swift).
- **Doğrulama:** format/strict lint, explicit select ve SQL/security contract kontrolleri başarılı. Güncel iOS simulator runner 145 testte 144 başarılı, 1 atlanan, 0 hatayla tamamlandı. Supabase RLS/runtime doğrulaması Docker daemon yokluğu nedeniyle CI/disposable database işine bağlıdır.

### PERF-04 — P2 — Explore araması aynı gönderileri tekrar yükleyen çok aşamalı bir ağ yolu kullanıyor

- [x] **✅ RESOLVED.** Explore post araması artık ID listesini alıp ikinci bir `loadPosts` hydration turu başlatmıyor. Yeni viewer-authorized enriched RPC post, public author, media metadata ve sayaçları bounded tek sonuç kontratında döndürüyor; iOS yalnız toplu avatar/media signed URL çağrılarını yapıyor. İptal/generation koruması korunuyor.
- **Kanıt:** [supabase/migrations/20260913140000_add_enriched_community_post_search.sql](/Users/macbook/Documents/Norge360/supabase/migrations/20260913140000_add_enriched_community_post_search.sql); [Norge360/Core/Persistence/CommunitySearchService.swift](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/CommunitySearchService.swift); [Norge360/Features/Community/ExploreView.swift](/Users/macbook/Documents/Norge360/Norge360/Features/Community/ExploreView.swift).
- **Doğrulama:** iOS simulator test paketi 128 testte sıfır hata verdi; Worker/static kontroller ve explicit select kontrolü başarılı. SQL execution Docker yokluğu nedeniyle bu turda çalıştırılamadı.

### PERF-05 — P2 — Cache sınırları tüm bellek ve disk kayıtlarını kapsamıyor

- [x] **Çözüldü.** Görsel cache’inde decoded metadata artık ters sahiplik ve erişim sırası ile NSCache sınırına bağlı tutuluyor; tahliye edilen veya sınır dışı bırakılan anahtarlar metadata’dan da siliniyor. Disk cache’leri TTL, kayıt sayısı ve toplam byte kotasıyla bounded LRU davranışı uyguluyor; diskten okuma öncesinde kota dışı dosyalar reddediliyor. Community content cache de aynı kayıt/byte kotasını bakım sırasında tekrar uyguluyor.
- **Kanıt:** [Norge360/Core/DesignSystem/CommunityImageCache.swift](/Users/macbook/Documents/Norge360/Norge360/Core/DesignSystem/CommunityImageCache.swift); [Norge360/Core/Persistence/CommunityContentCache.swift](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/CommunityContentCache.swift); [Norge360Tests/CommunityImageCacheTests.swift](/Users/macbook/Documents/Norge360/Norge360Tests/CommunityImageCacheTests.swift).
- **Doğrulama:** Metadata sınırı, oversized disk girdisinin okunmadan reddedilmesi, TTL ve LRU testleri eklendi. iOS simulator test paketi 130 testte sıfır hata verdi; üretim cihazı Instruments profili ayrıca yapılmalıdır.

### PERF-06 — P2 — Supabase ağ istekleri provider timeout politikasının dışında

- [x] **Çözüldü.** Worker’ın service-role ve anonim Auth doğrulama client’ları ortak 10 saniyelik cancellation/deadline fetch’i kullanıyor. PostgREST timeout’u aynı bütçeye bağlandı ve SDK retry’ları kapatıldı; mutation’ların otomatik tekrar edilmesi ve her retry ile timeout’un katlanması engellendi. Auth doğrulaması kaldırılmadı.
- **Kanıt:** [workers/moderation/src/index.ts](/Users/macbook/Documents/Norge360/workers/moderation/src/index.ts); [scripts/test_worker_security.py](/Users/macbook/Documents/Norge360/scripts/test_worker_security.py).
- **Doğrulama:** Worker `check`, Wrangler types, 15 güvenlik/kontrat testi ve secret scan başarılı. Gerçek Supabase outage/latency testi staging ortamında ayrıca yapılmalı.

### PERF-07 — P2 — Push ledger ve tamamlanmış cleanup outbox kayıtları süresiz büyüyor

- [x] **Çözüldü.** Push ledger için 30 günlük idempotency/replay penceresi tanımlandı; pending, delivered, invalid/failed ve beş denemede terminalleşmiş stale processing kayıtları küçük `FOR UPDATE SKIP LOCKED` partileriyle temizleniyor. Profile/Storage cleanup outbox ve tamamlanmış group fan-out job’ları 7 günlük operasyon penceresinden sonra aynı service-only bounded purge ile siliniyor. Aktif lease ve işlenmemiş cleanup kayıtları korunuyor.
- **Kanıt:** [supabase/migrations/20260913150000_add_transport_retention_purge.sql](/Users/macbook/Documents/Norge360/supabase/migrations/20260913150000_add_transport_retention_purge.sql); [workers/moderation/src/index.ts](/Users/macbook/Documents/Norge360/workers/moderation/src/index.ts); [scripts/test_worker_security.py](/Users/macbook/Documents/Norge360/scripts/test_worker_security.py).
- **Doğrulama:** Worker check, Wrangler types, 16 güvenlik/kontrat testi ve secret scan başarılı. Migration runtime testi Docker daemon yokluğu nedeniyle bu ortamda çalıştırılamadı.

### BUG-07 — P2 — Account setup yükleme hatası yeni kullanıcı olarak yorumlanıyor

- [x] **Çözüldü.** Account setup store artık `loaded(nil)` durumunu gerçek eksik profil olarak, transport/auth/decode hatasını ayrı `failed` durumu olarak taşıyor. `requiresSetup` yalnızca başarılı ve boş okuma sonrasında true olur; mevcut hesap bağlantı hatasında onboarding’e yönlendirilmez.
- **Kanıt:** [Norge360/App/AccountSetupStore.swift](/Users/macbook/Documents/Norge360/Norge360/App/AccountSetupStore.swift); [Norge360Tests/AccountSetupStoreTests.swift](/Users/macbook/Documents/Norge360/Norge360Tests/AccountSetupStoreTests.swift).
- **Doğrulama:** Başarısız yükleme ve gerçek boş profil için ayrı testler mevcut; iOS simulator test paketi 130 testte sıfır hata verdi.

### BUG-08 — P2 — Yerel planın başarısız kaydı ve 30 günlük silinmesi kullanıcıya yansımıyor

- [x] **Çözüldü.** Anonymous plan artık cache gibi 30 günlük retention’a tabi değil; kullanıcının oturum açmadan oluşturduğu tek yerel kopya süresiz korunuyor. Authenticated yerel snapshot’lar için 30 günlük temizlik devam ediyor. Plan store yazma sonucunu `Bool` olarak döndürüyor; AppState başarısız yerel yazmayı `planSyncStatus = .failed` ile üst katmana taşıyor ve anonymous planı yalnız authenticated kopya başarıyla yazıldıktan sonra siliyor.
- **Kanıt:** [Norge360/Core/Persistence/PlanStore.swift](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/PlanStore.swift); [Norge360/App/AppState.swift](/Users/macbook/Documents/Norge360/Norge360/App/AppState.swift); [Norge360Tests/UserDefaultsPlanStoreTests.swift](/Users/macbook/Documents/Norge360/Norge360Tests/UserDefaultsPlanStoreTests.swift); [Norge360Tests/AppStateTests.swift](/Users/macbook/Documents/Norge360/Norge360Tests/AppStateTests.swift).
- **Doğrulama:** Eski anonymous snapshot korunması ve başarısız local write görünürlüğü testleri eklendi; hedefli test ve biçim doğrulaması başarılı. Tam iOS test paketi değişiklik grubunun sonunda tekrar çalıştırılacaktır.

### CLEAN-01 — P2 — Görev içeriği, çeviri ve ilerleme tek kalıcı nesnede birleşmiş

- [x] **Çözüldü.** Canonical `RelocationTaskDefinition` artık localization key’leri, resmi kaynak metadata’sı ve content/rules version alanlarını taşıyor; `RelocationTaskProgress` yalnız status ve completedAt bilgisini taşıyor. UI’nin kullandığı mevcut computed alanlar korunarak tasarım/API etkilenmedi. Eski düz JSON task formatı geriye dönük okunabiliyor.
- **Kanıt:** [Norge360/Domain/Models/RelocationTask.swift](/Users/macbook/Documents/Norge360/Norge360/Domain/Models/RelocationTask.swift); [Norge360/Domain/Rules/RelocationRulesEngine.swift](/Users/macbook/Documents/Norge360/Norge360/Domain/Rules/RelocationRulesEngine.swift); [Norge360/App/AppState.swift](/Users/macbook/Documents/Norge360/Norge360/App/AppState.swift).
- **Uygulanan çözüm:** Görev başlık/açıklama/disclaimer metinleri artık oluşturulurken çevrilmiş metin olarak saklanmıyor; key üzerinden mevcut dilde hesaplanıyor. Profil değişiminde eşleşen görevin UUID’si, status’ü ve completedAt zamanı korunuyor. İçerik ve kural sürümleri ileride kontrollü katalog migrasyonuna izin veriyor.
- **Doğrulama:** Localization key/version, stable task ID, completion timestamp koruması ve hedefli iOS testleri başarılı. UI görsel testi bu değişiklikte tasarım farkı göstermedi.

### CLEAN-02 — P2 — Toplanan bazı relocation cevapları kural motorunda kullanılmıyor

- [x] **Çözüldü.** Citizenship, current Norway status, stay duration, moving reason ve job-offer cevapları artık deterministik görev yönlendirmelerinde kullanılıyor. Non-EEA study/family/self-employment/other senaryoları ayrı resmi UDI rehberlerine yönlendiriliyor; uygulama bunlardan hukuki uygunluk sonucu çıkarmıyor.
- **Kanıt:** [Norge360/Domain/Models/RelocationProfile.swift](/Users/macbook/Documents/Norge360/Norge360/Domain/Models/RelocationProfile.swift); [Norge360/Domain/Rules/RelocationRulesEngine.swift](/Users/macbook/Documents/Norge360/Norge360/Domain/Rules/RelocationRulesEngine.swift); [Norge360/Domain/Services/OfficialSourceCatalog.swift](/Users/macbook/Documents/Norge360/Norge360/Domain/Services/OfficialSourceCatalog.swift).
- **Uygulanan çözüm:** Nationality-specific, stay-duration, current-status ve work-offer görevleri yalnız ilgili cevaplarda üretiliyor. UDI study permit, family immigration, self-employed/work immigration ve genel başvuru kaynakları source metadata’sıyla saklanıyor; resmi kaynak, son doğrulama ve disclaimer akışı korunuyor.
- **Doğrulama:** Dört non-EEA moving reason, mevcut Norveç durumu, 3–12 ay kalış, iş teklifi yokluğu ve boş vatandaşlık girdisi için hedefli kurallar testi eklendi; localization kontrolü çalışma ağacındaki önceki eksik anahtarlar nedeniyle ayrıca ele alınacak.

### CLEAN-03 — P2 — Ham backend hataları kullanıcıya taşınıyor

- [x] **Çözüldü.** iOS kullanıcı yüzeylerindeki ham `localizedDescription` kullanımları kaldırıldı. Ortak `UserFacingErrorMapper`, kullanıcıya yerelleştirilebilir güvenli fallback döndürüyor; loglara yalnızca operasyon adı ve hata türü yazılıyor. APNs debug yolu da altyapı metnini göstermiyor.
- **Kanıt:** [Norge360/Core/Networking/UserFacingErrorMapper.swift](/Users/macbook/Documents/Norge360/Norge360/Core/Networking/UserFacingErrorMapper.swift); [Norge360/App/CommunityFeedStore.swift](/Users/macbook/Documents/Norge360/Norge360/App/CommunityFeedStore.swift); [Norge360/App/CommunityGroupsStore.swift](/Users/macbook/Documents/Norge360/Norge360/App/CommunityGroupsStore.swift); [Norge360/Features/Auth/AuthFlowView.swift](/Users/macbook/Documents/Norge360/Norge360/Features/Auth/AuthFlowView.swift).
- **Doğrulama:** `UserFacingErrorTests` backend hata gövdesinin kullanıcı mesajına taşınmadığını doğruluyor; localization kontrolü 16 dil / 1081 anahtarla başarılı; format ve diff kontrolleri başarılı.

### CLEAN-04 — P2 — Çeviri inceleme kayıtları yayın kapısı olarak uygulanmıyor

- [x] **Çözüldü.** Genel UI kaynakları bundled resource üzerinden çalışmaya devam ediyor; `legal.*`, `task.*`, `plan.*`, `calculator.*`, `source.*`, `onboarding.*` ve `account_setup.*` anahtarları ilgili inceleme scope’una bağlandı. `approved + reviewer + reviewedAt` olmadan prosedürel içerik seçili dilde gösterilmiyor ve İngilizce kanonik metne düşüyor.
- **Kanıt:** [Norge360/Core/Localization/TranslationReviewRegistry.swift](/Users/macbook/Documents/Norge360/Norge360/Core/Localization/TranslationReviewRegistry.swift); [Norge360/Core/Localization/AppStrings.swift](/Users/macbook/Documents/Norge360/Norge360/Core/Localization/AppStrings.swift); [Norge360Tests/TranslationReviewRegistryTests.swift](/Users/macbook/Documents/Norge360/Norge360Tests/TranslationReviewRegistryTests.swift).
- **Doğrulama:** Scope eşleme, pending dillerin tüm prosedürel alanlarda engellenmesi ve genel UI bundle kontrolü hedefli Swift Testing ile doğrulandı.

### CLEAN-05 — P3 — Büyük dosyalar ve geniş servisler değişikliklerin etki alanını büyütüyor

- [~] **Büyük ölçüde çözüldü.** Etkinlik DTO/katalog, AppState plan persistence, fullscreen image/page/details ve profile completion view sorumlulukları davranış korunarak ayrıldı; strict lint artık temiz. Worker’ın büyük route/queue/provider modülü ve bazı feature servisleri hâlâ daha ileri ayrıştırma adımı olarak kaldı.
- **Kanıt:** [Norge360/App/AppState+PlanPersistence.swift](/Users/macbook/Documents/Norge360/Norge360/App/AppState+PlanPersistence.swift); [Norge360/Core/Persistence/CommunityEventModels.swift](/Users/macbook/Documents/Norge360/Norge360/Core/Persistence/CommunityEventModels.swift); [Norge360/Core/DesignSystem/CommunityFullscreenImagePage.swift](/Users/macbook/Documents/Norge360/Norge360/Core/DesignSystem/CommunityFullscreenImagePage.swift); [Norge360/Core/DesignSystem/CommunityFullscreenPostDetails.swift](/Users/macbook/Documents/Norge360/Norge360/Core/DesignSystem/CommunityFullscreenPostDetails.swift); [Norge360/Features/Profile/CommunityMemberProfileView.swift](/Users/macbook/Documents/Norge360/Norge360/Features/Profile/CommunityMemberProfileView.swift).
- **Kalan iş:** Worker route/queue/provider modülleri daha küçük dosyalara davranış testleri korunarak bölünebilir; bu adım yayın güvenliği için zorunlu değildir.

### CLEAN-06 — P3 — Format ve strict lint kalite kapısı mevcut çalışma ağacında kırık

- [x] **Çözüldü.** `make format-check`, localization, explicit-select, `git diff --check` ve strict lint başarılı. 179 Swift dosyasında 0 lint ihlali var; iOS workflow’u bu kapıları CI’da çalıştırıyor.
- **Kanıt:** [Makefile](/Users/macbook/Documents/Norge360/Makefile); [.github/workflows/ios-quality.yml](/Users/macbook/Documents/Norge360/.github/workflows/ios-quality.yml); [Norge360/App/AppState+PlanPersistence.swift](/Users/macbook/Documents/Norge360/Norge360/App/AppState+PlanPersistence.swift).

### TEST-01 — P1 — Depodaki CI iOS ve SQL güvenlik regresyonlarını çalıştırmıyor

- [~] **Kısmen çözüldü.** Yeni iOS workflow’u Swift formatı, localization, explicit Supabase projection kontrolü ve simulator unit/UI testlerini çalıştırıyor; Worker workflow’u da artık `scripts/test_worker_security.py` değişikliklerinde tetikleniyor. Supabase migration/RLS testleri için disposable database job’ı henüz eklenmedi; local Docker daemon bu ortamda da mevcut değil.
- **Kanıt:** [.github/workflows/ios-quality.yml](/Users/macbook/Documents/Norge360/.github/workflows/ios-quality.yml); [.github/workflows/moderation-worker-quality.yml](/Users/macbook/Documents/Norge360/.github/workflows/moderation-worker-quality.yml).
- **Kalan iş:** CI sağlayıcısında Supabase CLI + disposable database kurulumu onaylandıktan sonra migration/RLS job’ı ve zorunlu branch check’i eklenmeli.
- **Doğrulama:** iOS workflow dosyası kaynak/test/config değişikliklerini kapsıyor; Worker path filtresi security test script’ini kapsıyor.

### TEST-02 — P1 — Worker testleri kritik runtime davranışlarını test etmiyor

- [~] **Kısmen çözüldü.** `npm test` artık 16 statik/kontrat testine ek olarak Hono handler’ını doğrudan çağıran 6 runtime testini çalıştırıyor: health, missing token, Supabase Auth revocation, moderator role authorization ve account deletion group-ownership guard. Provider/APNs/Images hata yolları, queue lease/retry ve disposable Supabase/RLS hâlâ tam entegrasyon kapsamına alınmadı.
- **Kanıt:** [workers/moderation/src/index.runtime.test.ts](/Users/macbook/Documents/Norge360/workers/moderation/src/index.runtime.test.ts); [workers/moderation/package.json](/Users/macbook/Documents/Norge360/workers/moderation/package.json); [scripts/test_worker_security.py](/Users/macbook/Documents/Norge360/scripts/test_worker_security.py).
- **Kalan iş:** Mock’lu provider/Queue senaryoları ve disposable Supabase/RLS job’ı eklenmeli; mevcut runtime testleri bu iş tamamlanana kadar P1 doğrulama tabanının ilk katmanıdır.
- **Doğrulama:** `npm run check`, `npm run types:check`, `npm test`, `npm run secret-scan` ve production dependency audit başarılı.

### OPS-01 — P2 — Production/staging kaynak ayrımı depoda tamamlanmamış

- [ ] **Düzeltilmeli.** Wrangler yalnız varsayılan development Supabase projesi ve sabit queue adları içeriyor; named staging/production yapılandırması yok. Sampling 1. Cihaz satırında APNs ortam ayrımı olması backend/queue/secret ayrımını sağlamaz. Bu bir production yapılandırması eksikliğidir; canlı ortamların yanlış kurulduğu iddia edilmiyor.
- **Kanıt:** [workers/moderation/wrangler.toml:50](/Users/macbook/Documents/Norge360/workers/moderation/wrangler.toml:50); [workers/moderation/wrangler.toml:54](/Users/macbook/Documents/Norge360/workers/moderation/wrangler.toml:54).
- **Önerilen düzeltme:** Yayın öncesi her ortamın Supabase/Queue/secret/webhook/deploy target eşleşmesini açık yapılandır; log sampling ve alarm eşiklerini ölçüme göre belirle.
- **Doğrulama:** Deployment smoke test yanlış ortam kaynağına erişimi engellemeli; DLQ, Auth/provider hata oranı ve cleanup backlog alarmları doğrulanmalı.

### BUG-09 — P3 — Hesaplayıcı sonsuz değerleri ve geçersiz varsayımları kabul edebiliyor

- [x] **Çözüldü.** Maaş, kira ve aylık gider girdileri sonlu, negatif olmayan ve geniş ürün üst sınırları içinde doğrulanıyor. Gelir azaltma oranı 0–1 aralığına; yapılandırılmış gider varsayımları da sonluluk, negatiflik ve üst sınıra göre kontrol ediliyor. Hesap sonucu sonlu değilse güvenli biçimde `nil` dönüyor.
- **Kanıt:** [Norge360/Domain/Services/CostOfLivingCalculator.swift](/Users/macbook/Documents/Norge360/Norge360/Domain/Services/CostOfLivingCalculator.swift); [Norge360Tests/CostOfLivingCalculatorTests.swift](/Users/macbook/Documents/Norge360/Norge360Tests/CostOfLivingCalculatorTests.swift).
- **Doğrulama:** `infinity`, `NaN`, negatif/geçersiz oranlar, geçersiz gider varsayımları ve aşırı büyük planlama değerleri için testler eklendi; hedefli ve tam iOS simulator testlerinde çalıştırıldı.

## Önerilen uygulama sırası

1. BUG-01 ve BUG-02 crash’lerini; SEC-01 hesap izolasyonunu; SEC-02 export mahremiyetini düzelt.
2. SEC-03/04 hesap silme ve retention sınırını, BUG-03 plan veri kaybını davranış testleriyle güvenceye al.
3. TEST-01/02 ile bu yolları CI’a bağla; SEC-05–11 ve BUG-04–06 için hata/eşzamanlılık testlerini tamamla.
4. PERF-01–07 için önce request sayısı, byte, peak memory ve p95 baseline al; ardından bounded veri/queue/cache kontratlarını iyileştir.
5. Clean Code ayrıştırmasını küçük davranış-koruyan değişikliklerle yap; production ortam kapısını yayın öncesinde tamamla.

## Mevcut iyi uygulamalar ve eski raporla ilişki

- Native SwiftUI, actor tabanlı servisler, deterministic kurallar, bazı ana listelerde keyset sayfalama, batch profile imzalama, özel chat görselleri için ephemeral indirme, merkezi sign-out, RLS/security-definer sınırları ve Queue temelleri mevcut.
- Önceki `PERFORMANCE_SECURITY_OPTIMIZATION_AUDIT.md` raporundaki kapalı maddeler otomatik olarak yeniden açık sayılmadı. Bu rapor mevcut kodda kalan boşlukları veya farklı hata senaryolarını listeler; örneğin private cache hesabı ayırsa da Worker cache hit yetki iptalini atlayabiliyor.
- Başarılı build/test ve secret scan sonuçları, davranış testlerinin kapsamadığı açıkları kapatmaz. Buna karşılık test edilmemiş bir production ayarı da doğrulanmış canlı açık olarak etiketlenmedi.

## Teknik kaynak ve ölçüm kayıtları

Worker incelemesinde bounded payload, queue ve hata yönetimi ilkeleri [Cloudflare Workers Best Practices](https://developers.cloudflare.com/workers/best-practices/workers-best-practices/) ile karşılaştırıldı. Güncel `@cloudflare/workers-types` paketi `5.20260911.1` alındı; queue `ack`/`retry` ve handler tanımları kontrol edildi. Bulguların asıl kanıtı yukarıdaki yerel kod referanslarıdır.

- [Xcode test günlüğü](/tmp/norge360-audit-xcode.log)
- [Format kontrol günlüğü](/tmp/norge360-audit-lint.log)
- [Strict lint günlüğü](/tmp/norge360-audit-swiftlint.log)
- [Xcode test sonucu](/tmp/norge360-audit-derived/Logs/Test/Test-Norge360-2026.09.12_19-30-31-+0300.xcresult)

Geçici ölçüm dosyaları `/tmp` altında olduğundan sistem temizliğiyle silinebilir; test özeti bu raporda kalıcı olarak kaydedilmiştir.
