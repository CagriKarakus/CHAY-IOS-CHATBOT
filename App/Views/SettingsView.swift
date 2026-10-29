import AgentCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://router.example.com/v1", text: $baseURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Model adı", text: $model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("LLM sağlayıcısı")
                } footer: {
                    Text("OpenAI-uyumlu endpoint'in /v1 dahil adresi. Sadece HTTPS.")
                }

                Section {
                    SecureField("API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Key sadece bu cihazın Keychain'inde saklanır ve yalnızca yukarıdaki adrese gönderilir.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                }
            }
            .onAppear {
                baseURL = settings.baseURL
                model = settings.model
                apiKey = settings.apiKey
            }
        }
    }

    private func save() {
        do {
            settings.save(try LLMConfiguration(baseURL: baseURL, apiKey: apiKey, model: model))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
