# Norge360 code quality araçları

Bu proje Swift 6 ile derlenir. Kod kalitesi dört ayrı katmanda kontrol edilir:

1. `swift-format`: biçimlendirme ve biçim kontrolü.
2. `SwiftLint`: ekip kuralları ve okunabilirlik kontrolleri.
3. `Periphery`: kullanılmayan Swift kodunu raporlama.
4. Swift compiler + Strict Concurrency: veri yarışı ve actor-isolation hatalarını derleme sırasında yakalama.

## Kurulum

`swift-format`, Xcode toolchain içinden çalıştırılır. Bu nedenle ayrıca Homebrew paketi gerekmez. Diğer iki CLI aracı için:

```sh
brew install swiftlint periphery
```

Komut satırı araçlarının tam Xcode toolchain'ini kullanması için bir kez şu ayarı yapın:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
xcode-select -p
```

Çıktı `/Applications/Xcode.app/Contents/Developer` olmalıdır. Makefile da `DEVELOPER_DIR` değerini bu Xcode yoluna sabitler; farklı bir Xcode kullanıyorsanız `XCODE_DEVELOPER_DIR=/path/to/Xcode.app/Contents/Developer make build` şeklinde geçersiniz.

Bu repo `swift-format` kullanır. `swiftformat` adlı üçüncü taraf SwiftFormat aracı ayrıca kurulup aynı projede birlikte çalıştırılmamalıdır; iki formatter farklı kararlar vererek dosyaları tekrar tekrar değiştirebilir.

## Günlük kullanım

Repo kökünden:

```sh
make format          # Swift dosyalarını düzeltir
make format-check    # Format farkı varsa başarısız olur
make lint            # SwiftLint raporu
make lint-strict     # Uyarıları da başarısızlık sayar
make periphery       # Kullanılmayan kod raporu
make build           # Strict Concurrency dahil Xcode derlemesi
make quality         # CI için birleşik kontrol
```

`make format` dosyaları değiştirir. Pull request veya CI içinde `format-check` kullanılmalıdır.

## Strict Concurrency

Uygulama ve test target'larında `SWIFT_STRICT_CONCURRENCY = complete` ayarlıdır. Proje ayrıca Swift 6 dil modundadır. Yeni concurrency hatalarında genellikle şu çözümler değerlendirilir:

- UI/state sahibi kodu `@MainActor` ile sınırlandırmak
- actor sınırlarından geçen değerleri `Sendable` yapmak
- paylaşılan mutable state'i actor veya immutable değere taşımak
- yalnızca gerçekten güvenli olduğunda `@preconcurrency` veya `nonisolated` kullanmak

Compiler uyarılarını susturmak için doğrudan `@unchecked Sendable` eklenmemelidir; önce veri sahipliği ve yaşam döngüsü incelenmelidir.

## Periphery kullanımı

Periphery önce scheme'i build edip index store üretir, sonra referans grafiğini tarar. Bu nedenle raporu kod silme komutu gibi değil, inceleme listesi gibi ele alıyoruz. SwiftUI preview'ları, Objective-C runtime erişimlerini ve test target'ını başlangıçta koruyan ayarlar `.periphery.yml` içindedir. Test target'ı açık tutulur; böylece yalnızca testlerde kullanılan domain API'leri yanlışlıkla ölü kod olarak raporlanmaz. Periphery 3.x'te eski `targets` ayarı kullanılmaz; tarama scheme üzerinden yapılır.

Dinamik erişim, reflection, storyboard bağlantısı veya gelecekte kullanılacak public API için gerekirse dar kapsamlı bir `// periphery:ignore` açıklaması eklenebilir.

## Kural politikası

Verdiğiniz `opt_in_rules` ve cyclomatic eşikleri `.swiftlint.yml` içine alındı. İlk geçişte yerel lint uyarıları bilgi amaçlıdır; mevcut baseline temizlendikten sonra CI `make lint-strict` ve `make format-check` ile merge'i engelleyebilir.
