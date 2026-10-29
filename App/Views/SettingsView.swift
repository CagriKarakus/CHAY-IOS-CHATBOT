import AgentCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var tavilyKey = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("https://router.example.com/v1", text: $baseURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                    field("Model adı", text: $model)
                    SecureField("API key", text: $apiKey, prompt: prompt("API key"))
                        .foregroundStyle(Theme.textBright)
                } header: {
                    header("LLM sağlayıcısı")
                } footer: {
                    footer("OpenAI-uyumlu endpoint'in /v1 dahil adresi. Sadece HTTPS. Key yalnızca bu cihazın Keychain'inde saklanır.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    SecureField("Tavily API key", text: $tavilyKey, prompt: prompt("Tavily API key (tvly-…)"))
                        .foregroundStyle(Theme.textBright)
                } header: {
                    header("Web araması")
                } footer: {
                    footer("tavily.com'dan ücretsiz alınır. Boş bırakılırsa asistan web'de arama yapamaz.")
                }
                .listRowBackground(Theme.surface)

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Theme.red)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .tint(Theme.blue)
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                baseURL = settings.baseURL
                model = settings.model
                apiKey = settings.apiKey
                tavilyKey = settings.tavilyKey
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text, prompt: prompt(placeholder))
            .foregroundStyle(Theme.textBright)
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(Theme.textMuted)
    }

    private func header(_ text: String) -> some View {
        Text(text).foregroundStyle(Theme.textMuted)
    }

    private func footer(_ text: String) -> some View {
        Text(text).foregroundStyle(Theme.textMuted)
    }

    private func save() {
        do {
            settings.save(try LLMConfiguration(baseURL: baseURL, apiKey: apiKey, model: model), tavilyKey: tavilyKey)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
