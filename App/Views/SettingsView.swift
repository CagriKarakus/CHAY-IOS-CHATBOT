import AgentCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var tavilyKey = ""
    @State private var searchProvider = SearchProvider.tavily
    @State private var braveKey = ""
    @State private var searxngURL = ""
    @State private var language = AppLanguage.stored
    /// Ekran açıldığındaki seçim; değişirse yeniden başlatma uyarısı gösterilir.
    @State private var initialLanguage = AppLanguage.stored
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(settings.providers) { provider in
                        NavigationLink {
                            ProviderEditorView(provider: provider)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .foregroundStyle(Palette.textBright)
                                Text(verbatim: "\(URL(string: provider.baseURL)?.host ?? provider.baseURL) · " + L(
                                    provider.models.count == 1 ? "1 model" : "\(provider.models.count) models",
                                    "\(provider.models.count) model"
                                ))
                                    .font(.caption)
                                    .foregroundStyle(Palette.textMuted)
                            }
                        }
                    }
                    NavigationLink {
                        ProviderEditorView(provider: nil)
                    } label: {
                        Label(L("Add Provider", "Sağlayıcı ekle"), systemImage: "plus")
                            .foregroundStyle(Palette.blue)
                    }
                } header: {
                    header(L("Models and providers", "Modeller ve sağlayıcılar"))
                } footer: {
                    footer(L("Each provider is an OpenAI-compatible address and API key; add as many models under it as you like. The model is chosen in the chat screen.", "Her sağlayıcı bir OpenAI-uyumlu adres ve API key'dir; altına istediğin kadar model ekleyebilirsin. Model sohbet ekranından seçilir."))
                }
                .listRowBackground(Palette.surface)

                Section {
                    NavigationLink {
                        UsageView()
                    } label: {
                        Label(L("Token and search usage", "Token ve arama kullanımı"), systemImage: "chart.bar")
                            .foregroundStyle(Palette.textBright)
                    }
                    NavigationLink {
                        PersonalizationView()
                    } label: {
                        Label(L("Personalization", "Kişiselleştirme"), systemImage: "person.crop.circle")
                            .foregroundStyle(Palette.textBright)
                    }
                    NavigationLink {
                        NotesView()
                    } label: {
                        Label(L("Memory", "Hafıza"), systemImage: "brain")
                            .foregroundStyle(Palette.textBright)
                    }
                    NavigationLink {
                        SkillsView()
                    } label: {
                        Label(L("Skills", "Skill'ler"), systemImage: "sparkles")
                            .foregroundStyle(Palette.textBright)
                    }
                    NavigationLink {
                        ConnectorsView()
                    } label: {
                        Label(L("Connectors", "Bağlayıcılar"), systemImage: "point.3.connected.trianglepath.dotted")
                            .foregroundStyle(Palette.textBright)
                    }
                    NavigationLink {
                        PromptsView()
                    } label: {
                        Label(L("Prompts", "Hazır komutlar"), systemImage: "text.badge.star")
                            .foregroundStyle(Palette.textBright)
                    }
                    NavigationLink {
                        BackupView()
                    } label: {
                        Label(L("Backup", "Yedekleme"), systemImage: "externaldrive")
                            .foregroundStyle(Palette.textBright)
                    }
                }
                .listRowBackground(Palette.surface)

                Section {
                    Text(ContinuedTurn.lastStatus ?? L("No answer has run yet.", "Henüz bir cevap çalışmadı."))
                        .font(.footnote)
                        .foregroundStyle(Palette.text)
                } header: {
                    header(L("Background answers", "Arka planda cevaplar"))
                } footer: {
                    footer(L("Result of the last attempt to keep an answer running after leaving the app (iOS 26 and later). \"Started\" means iOS accepted it.",
                             "Bir cevabı uygulamadan çıkınca da sürdürme denemesinin son sonucu (iOS 26 ve sonrası). \"Başlatıldı\" iOS'un kabul ettiği anlamına gelir."))
                }
                .listRowBackground(Palette.surface)

                Section {
                    Picker(L("Appearance", "Görünüm"), selection: $appearance) {
                        ForEach(Appearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .foregroundStyle(Palette.textBright)
                } header: {
                    header(L("Appearance", "Görünüm"))
                } footer: {
                    footer(L("Light uses Atom One Light, dark uses Atom One Dark. System follows your iPhone.",
                             "Açık modda Atom One Light, koyu modda Atom One Dark kullanılır. Sistem, iPhone'unun ayarını izler."))
                }
                .listRowBackground(Palette.surface)

                Section {
                    Picker(L("Language", "Dil"), selection: $language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .foregroundStyle(Palette.textBright)
                    .onChange(of: language) { AppLanguage.store(language) }
                } header: {
                    header(L("Language", "Dil"))
                } footer: {
                    footer(language != initialLanguage
                        ? L("Close and reopen the app to apply the new language.", "Yeni dilin uygulanması için uygulamayı kapatıp yeniden aç.")
                        : L("System follows your iPhone's language.", "Sistem, iPhone'unun dilini kullanır."))
                }
                .listRowBackground(Palette.surface)

                Section {
                    Picker(L("Search service", "Arama servisi"), selection: $searchProvider) {
                        ForEach(SearchProvider.allCases) { provider in
                            Text(provider.title).tag(provider)
                        }
                    }
                    .foregroundStyle(Palette.textBright)
                    switch searchProvider {
                    case .tavily:
                        SecureField("Tavily API key", text: $tavilyKey, prompt: prompt("Tavily API key (tvly-…)"))
                    case .brave:
                        SecureField("Brave Search API key", text: $braveKey, prompt: prompt("Brave Search API key"))
                    case .searxng:
                        TextField("SearXNG URL", text: $searxngURL, prompt: prompt("https://search.example.com"))
                            .keyboardType(.URL)
                    case .duckduckgo:
                        EmptyView()
                    }
                } header: {
                    header(L("Web search", "Web araması"))
                } footer: {
                    footer(searchFooter)
                }
                .foregroundStyle(Palette.textBright)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .listRowBackground(Palette.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .tint(Palette.blue)
            .navigationTitle(L("Settings", "Ayarlar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done", "Bitti")) {
                        settings.saveTavilyKey(tavilyKey)
                        settings.saveSearch(provider: searchProvider, braveKey: braveKey, searxngURL: searxngURL)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                tavilyKey = settings.tavilyKey
                searchProvider = settings.searchProvider
                braveKey = settings.braveKey
                searxngURL = settings.searxngURL
            }
        }
    }
}

extension SettingsView {
    fileprivate var searchFooter: String {
        switch searchProvider {
        case .tavily:
            L("Free tier at tavily.com. If the key is empty, invalid or out of quota, searches fall back to DuckDuckGo.",
              "tavily.com'da ücretsiz plan var. Key boş, geçersiz veya kota bitmişse aramalar DuckDuckGo ile yapılır.")
        case .brave:
            L("Get a key at brave.com/search/api (free tier available). If the key is empty, invalid or out of quota, searches fall back to DuckDuckGo.",
              "Key'i brave.com/search/api adresinden alabilirsin (ücretsiz plan var). Key boş, geçersiz veya kota bitmişse aramalar DuckDuckGo ile yapılır.")
        case .searxng:
            L("Address of your own SearXNG instance (HTTPS). JSON output must be enabled in its settings (search.formats: json).",
              "Kendi SearXNG sunucunun adresi (HTTPS). Sunucu ayarlarında JSON çıktısı açık olmalı (search.formats: json).")
        case .duckduckgo:
            L("No key needed. It reads DuckDuckGo's plain HTML results, which is not an official API: it can break or be blocked for a while under heavy use. Good as a backup when your Tavily or Brave quota runs out.",
              "Key gerekmez. DuckDuckGo'nun sade HTML sonuçlarını okur; resmi bir API değildir, bozulabilir veya yoğun kullanımda bir süre engellenebilir. Tavily veya Brave kotan bittiğinde yedek olarak iyidir.")
        }
    }
}

/// Ayar ekranlarında ortak metin stilleri.
@MainActor func prompt(_ text: String) -> Text {
    Text(text).foregroundStyle(Palette.textMuted)
}

@MainActor func header(_ text: String) -> some View {
    Text(text).foregroundStyle(Palette.textMuted)
}

@MainActor func footer(_ text: String) -> some View {
    Text(text).foregroundStyle(Palette.textMuted)
}
