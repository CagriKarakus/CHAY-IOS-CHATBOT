import AgentCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var tavilyKey = ""
    @State private var userInstructions = ""

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
                                Text("\(URL(string: provider.baseURL)?.host ?? provider.baseURL) · \(provider.models.count) model")
                                    .font(.caption)
                                    .foregroundStyle(Palette.textMuted)
                            }
                        }
                    }
                    NavigationLink {
                        ProviderEditorView(provider: nil)
                    } label: {
                        Label("Sağlayıcı ekle", systemImage: "plus")
                            .foregroundStyle(Palette.blue)
                    }
                } header: {
                    header("Modeller ve sağlayıcılar")
                } footer: {
                    footer("Her sağlayıcı bir OpenAI-uyumlu adres ve API key'dir; altına istediğin kadar model ekleyebilirsin. Model sohbet ekranından seçilir.")
                }
                .listRowBackground(Palette.surface)

                Section {
                    NavigationLink {
                        UsageView()
                    } label: {
                        Label("Token ve arama kullanımı", systemImage: "chart.bar")
                            .foregroundStyle(Palette.textBright)
                    }
                }
                .listRowBackground(Palette.surface)

                Section {
                    TextField("Kişisel talimatlar", text: $userInstructions, prompt: prompt("Örn. Emoji kullanma. Kısa cevap ver."), axis: .vertical)
                        .lineLimit(3...10)
                        .foregroundStyle(Palette.textBright)
                } header: {
                    header("Kişisel talimatlar")
                } footer: {
                    footer("Her sohbette asistana iletilir.")
                }
                .listRowBackground(Palette.surface)

                Section {
                    SecureField("Tavily API key", text: $tavilyKey, prompt: prompt("Tavily API key (tvly-…)"))
                        .foregroundStyle(Palette.textBright)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    header("Web araması")
                } footer: {
                    footer("tavily.com'dan ücretsiz alınır. Boş bırakılırsa asistan web'de arama yapamaz.")
                }
                .listRowBackground(Palette.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .tint(Palette.blue)
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") {
                        settings.saveGeneral(tavilyKey: tavilyKey, userInstructions: userInstructions)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                tavilyKey = settings.tavilyKey
                userInstructions = settings.userInstructions
            }
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
