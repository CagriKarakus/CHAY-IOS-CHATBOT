# CHAY — iOS için yapay zekâ asistanı

[English](README.md) · **Türkçe**

**Kendi LLM API key'inle** çalışan, native bir iOS asistanı. Web'de araştırma yapar, dosyalarını okur, doküman yazar, seninle ilgili şeyleri hatırlar, MCP sunucularına bağlanır ve OpenAI-uyumlu her endpoint ile çalışır. Tüm agent mantığı telefonda çalışır; arada bir sunucu yoktur ve verilerin sadece senin ayarladığın sağlayıcılara ve servislere gider.

## Özellikler

### Sohbet ve modeller
- OpenAI-uyumlu her `/chat/completions` endpoint'i ile **akışlı sohbet**; modelin **düşünme süreci** canlı görünür, araç günlüğü açılıp kapanabilir
- **Birden fazla sağlayıcı ve model**: yaygın router ve sağlayıcılar için hazır ayarlar, sunucudan model listesi çekme, sohbet ekranında model seçici ve **düşünme seviyesi** (düşük / orta / yüksek)
- Sunucu bildiriyorsa **yetenekler `/models`'tan otomatik algılanır** (ör. Evren `modalities`, OpenRouter `architecture`); elle de ayarlanabilir
- **Görsel, ses ve doküman**: fotoğraf (kamerayla da), ses kaydı, PDF, Word, Excel, PowerPoint ve metin dosyası eklenebilir; dokümanların metni telefonda çıkarıldığı için her modelle çalışır
- `/images/generations` destekleyen modellerle **görsel üretme**, telefonun kendi sesleriyle **sesli okuma**
- Mesajları **düzenleme ve yeniden üretme** (aynı veya başka bir modelle)
- **Uzun sohbetler**: bağlam büyüyünce eski araç sonuçları kısaltılır, eski mesajlar özetlenir

### Araçlar
- **Web araştırması**: Tavily, Brave Search, kendi SearXNG sunucun veya **key gerektirmeyen DuckDuckGo**. Tavily veya Brave key'i yoksa, geçersizse ya da kota bittiyse aramalar kendiliğinden DuckDuckGo ile yapılır
- **Sayfa ve akış okuma** (HTML, RSS, Atom); kaynaklar cevapta belirtilir
- Telefonun JavaScript motoruyla, sıkı bir izin listesi kontrolünden sonra çalışan **hesap makinesi**
- Uygulamada açılan ve Dosyalar uygulamasında görünen **Markdown dokümanları** ve **artifact'ler** (etkileşimli HTML sayfaları)
- **Bağlayıcılar (MCP)**: uzak MCP sunucuları (Streamable HTTP) kimlik doğrulamasız, erişim token'ıyla veya **tarayıcıyla giriş** (keşif, otomatik istemci kaydı, PKCE ve token yenilemeli OAuth) ile eklenir. Veri değiştirebilen araçlar, sen izin vermedikçe her çalışmadan önce sorar; bağlayıcılar ve araçları sohbet başına açılıp kapatılabilir
- Agent Skills biçiminde (`SKILL.md`) **skill'ler**: herhangi bir GitHub reposundan eklenir veya kendin yazarsın; model bir skill'i sadece uygun bir görevde yükler

### Düzen
- Claude'daki gibi **kenar menüsü**: sohbetin herhangi bir yerinden sağa çek veya menü düğmesine dokun. Projeleri (her biri açılıp sohbetleri listelenebilir), dokümanları, sabitlenen ve son sohbetleri gösterir; altta Ayarlar ve Yeni sohbet bulunur
- **Sohbet menüsü** (sağ üstte veya kenar menüsünde bir sohbete basılı tutunca): sabitle, Markdown veya PDF olarak paylaş, yeniden adlandır, projeye ekle, sil
- Sohbetleri ortak talimat ve dosyalarla gruplayan **projeler**
- Tüm sohbetlerde **arama**, sık istekler için **hazır komut kütüphanesi**
- Kaydedilmeyen ve hafızaya dokunmayan **gizli sohbetler**; gizli sohbet düğmesi yeni sohbette görünür

### Hafıza ve kişiselleştirme
- **Hafıza**: kalıcı bilgiler ve tercihler not olarak saklanır ve her sohbette kullanılır (Ayarlar → Hafıza); sohbete özel hafıza anahtarı
- Her sohbete eklenen **kişisel talimatlar** (ör. "emoji kullanma")
- **Görünüm**: sistem, açık veya koyu (Atom One paleti)
- **İngilizce ve Türkçe** arayüz

### Günlük kullanım
- **Kestirmeler**: *Ask CHAY* eylemi bir komutu (ve ekran görüntüsü gibi dosyaları) seçtiğin modelle gönderir; ör. her sabah 07:00'de haber özeti
- **Arka plan**: cevap arka planda bir süre devam eder, uygulamaya dönünce kaldığı yerden sürer ve hazır olunca bildirim gönderir
- **Kullanım**: cevap başına token ve token/saniye, sağlayıcı ve model başına toplamlar, destekleyen sağlayıcılarda bakiye, servis başına arama sayısı
- **Yedekleme**: her şeyi tek dosyaya dışa aktarıp geri yükleme (API key'ler, token'lar ve girişler asla dahil edilmez)

## Güvenlik

- API key'ler, bağlayıcı token'ları ve OAuth bilgileri sadece Keychain'de (`WhenUnlockedThisDeviceOnly`) saklanır ve hiçbir zaman loglanmaz
- Sadece HTTPS; App Transport Security istisnası yok
- Web sayfaları ve bağlayıcı sonuçları modele açıkça işaretlenmiş veri olarak, içindeki talimatlara uymaması söylenerek verilir
- Web içeriği okunduktan sonra hafızaya kayıt senin onayını ister; veri değiştirebilen bağlayıcı araçları çalışmadan önce sorar
- Dosya araçları sadece uygulamanın Documents klasörüne düz adlarla yazabilir
- Her istekte model çağrısı sayısı sabit bir sınırla kısıtlıdır

## Mimari

| Klasör | İçerik | Nerede derlenir ve test edilir |
| --- | --- | --- |
| `Packages/AgentCore/` | LLM istemcisi (SSE), agent döngüsü, araçlar, web araması, MCP istemcisi ve OAuth, bağlam sıkıştırma. Apple'a özel framework yok. | Windows (`swift test`) ve CI |
| `App/` | SwiftUI, SwiftData, Keychain, App Intents ve iOS'a özel diğer kodlar | CI (macOS) |
| `project.yml` | [XcodeGen](https://github.com/yonaskolb/XcodeGen) proje tanımı (`.xcodeproj` repoda yok) | CI |
| `.github/workflows/ios.yml` | Testler ve imzasız `.ipa` derlemesi | GitHub Actions |
| `scripts/faz0.ps1` | Bir endpoint'in akış ve araç çağırma desteğini kontrol eder, SSE fixture'larını kaydeder | Windows |

## Mac olmadan geliştirme

Proje Windows'ta geliştirilir. Mantık `AgentCore`'dadır ve yerelde test edilir; iOS uygulaması GitHub Actions'ta macOS üzerinde derlenir ve telefona sideload edilir.

1. **Git** ve **GitHub CLI** kur, sonra `gh auth login` çalıştır.
2. *MSVC x64/x86* ve *Windows 11 SDK* ile **Visual Studio Build Tools**'u, ardından **Swift toolchain**'i kur:
   ```powershell
   winget install --id Swift.Toolchain
   ```
3. Testleri çalıştır:
   ```powershell
   swift test --package-path Packages/AgentCore
   ```
4. **iTunes** (Microsoft Store'dan değil, apple.com'dan) ve **Sideloadly** kur. Geliştirme için ayrı bir Apple ID kullan.

### iPhone'a yükleme

1. `main`'e push et (veya *iOS* workflow'unu elle çalıştır).
2. Derlemeyi indir:
   ```powershell
   gh run download <run-id> --name AIAssistant-ipa
   ```
   CI derlemeleri 14 gün saklanır. Sağlam sürümler [Releases](https://github.com/CagriKarakus/CHAY-IOS-CHATBOT/releases) sayfasına eklenir ve silinmez:
   ```powershell
   gh release download v1.0 --pattern "CHAY-v1.0.ipa"
   ```
3. `.ipa`'yı Sideloadly ile yükle. Mevcut uygulamanın üstüne yüklemek ayarlarını ve verilerini korur. Daha eski bir sürüme dönmeden önce yedek al.
4. İlk kurulumda *Ayarlar → Gizlilik ve Güvenlik → Geliştirici Modu*'nu aç ve *Ayarlar → Genel → VPN ve Aygıt Yönetimi*'nde geliştirici profiline güven.

Ücretsiz Apple hesabıyla imza 7 gün geçerlidir; yeniden yüklemek yeniler. Ücretli geliştirici hesabı gerektiren özellikler (iCloud senkronizasyonu, Share Extension) dahil değildir.

### Bir endpoint'i kontrol etme

```powershell
$env:LLM_BASE_URL = "https://<router>/v1"
$env:LLM_API_KEY  = "<api-key>"
powershell -ExecutionPolicy Bypass -File scripts\faz0.ps1 -Model "<model>"
```

## Yol haritası

- iCloud senkronizasyonu ve Share Extension (ücretli geliştirici hesabı gerekir)
- Face ID kilidi
- Cihaz üzerinde çalışan modeller
