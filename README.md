# AI Asistan (iOS)

Kullanıcının kendi LLM key'iyle çalışan, web araştırması yapan, Markdown doküman üreten ve hafıza tutan native iOS asistanı. Geliştirme **Windows** üzerinde yapılır; iOS build'i GitHub Actions'taki macOS runner'ında alınır ve `.ipa` telefona sideload edilir.

## Yapı

| Klasör | İçerik | Nerede derlenir/test edilir |
| --- | --- | --- |
| `Packages/AgentCore/` | LLM istemcisi, agent loop, araçlar. Apple'a özel framework yok. | Windows (`swift test`) + CI |
| `App/` | SwiftUI, SwiftData, Keychain gibi iOS'a özel katman | Sadece CI (macOS) |
| `project.yml` | XcodeGen proje tanımı (`.xcodeproj` repoda tutulmaz) | CI |
| `.github/workflows/ios.yml` | Test + imzasız `.ipa` üretimi | GitHub Actions |
| `scripts/faz0.ps1` | LLM endpoint doğrulaması ve SSE fixture kaydı | Windows |

## Geliştirme ortamı (Windows)

1. **Git ve GitHub CLI** (kurulu): `gh auth login`
2. **Visual Studio Build Tools**, "Desktop development with C++" iş yüküyle:
   ```powershell
   winget install --id Microsoft.VisualStudio.2022.BuildTools
   ```
   Kurulumdan sonra Visual Studio Installer'da *Desktop development with C++* iş yükünü işaretle.
3. **Swift toolchain:**
   ```powershell
   winget install --id Swift.Toolchain
   ```
   Yeni bir terminalde `swift --version` çalışmalı.
4. **VS Code** + **Swift** eklentisi (`swiftlang.swift-vscode`).
5. **iTunes**: Apple'ın sitesinden indirilen sürüm (Microsoft Store sürümü değil). iPhone'u USB'den tanıyan sürücüleri getirir.
6. **Sideloadly** (veya AltServer + AltStore): `.ipa`'yı Apple ID ile imzalayıp telefona yükler. Ana Apple ID'n yerine **sadece geliştirme için ayrı bir Apple ID** kullan.

Kontrol:

```powershell
swift test --package-path Packages/AgentCore
```

## Telefona yükleme

1. `main`'e push et (veya Actions sekmesinden *iOS* workflow'unu elle çalıştır).
2. Workflow bitince `.ipa`'yı indir:
   ```powershell
   gh run download --name AIAssistant-ipa
   ```
3. iPhone'u USB ile bağla, Sideloadly'de `AIAssistant.ipa`'yı seçip geliştirme Apple ID'nle yükle.
4. İlk yüklemede iPhone'da:
   - *Ayarlar → Gizlilik ve Güvenlik → Geliştirici Modu* → aç (telefon yeniden başlar)
   - *Ayarlar → Genel → VPN ve Aygıt Yönetimi* → geliştirici profiline güven

Ücretsiz Apple hesabıyla imza **7 gün** geçerlidir; Sideloadly/AltStore ile yenilenir. Aynı anda en fazla 3 sideload uygulama olabilir.

## Faz 0: Endpoint doğrulama

Key'ler sadece kendi terminalinde kalır; repoya veya log'lara girmez.

```powershell
$env:LLM_BASE_URL = "https://<router-adresi>/v1"
$env:LLM_API_KEY  = "<api-key>"
.\scripts\faz0.ps1 -Model "<model-adi>"
```

Script şunları yapar: model listesini çeker, `tools` içeren bir istekte `tool_calls` geldiğini kontrol eder, streaming metin ve streaming tool call yanıtlarını `Packages/AgentCore/Tests/AgentCoreTests/Fixtures/` altına `.sse` olarak kaydeder. Bu dosyalar Faz 1–2'deki parser testlerinin girdisidir.

## Plan

Faz E (ortam) → Faz 0 (endpoint) → Faz 1 (streaming sohbet) → Faz 2 (agent loop + web) → Faz 3 (Markdown) → Faz 4 (hafıza) → Faz 5 (kalıcılık) → Faz 6 (kontrol) → Faz 7 (iOS entegrasyonları).

Her faz şu üç kontrolden geçmeden bir sonrakine geçilmez: Windows'ta `swift test` geçer, CI yeşil olur, telefonda o fazın doğrulama kriteri sağlanır.
