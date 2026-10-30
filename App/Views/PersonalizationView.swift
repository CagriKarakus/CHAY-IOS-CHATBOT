import AgentCore
import SwiftUI

/// Asistanın üslubu, özel talimatlar ve doküman araması. Değişiklikler anında kaydedilir.
struct PersonalizationView: View {
    @Environment(AppSettings.self) private var settings
    @State private var personalization = Personalization()
    @State private var instructions = ""

    var body: some View {
        Form {
            Section {
                Picker(L("Base style and tone", "Temel üslup ve ton"), selection: $personalization.style) {
                    ForEach(Personalization.Style.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                levelPicker(L("Warmth", "Sıcaklık"), selection: $personalization.warmth)
                levelPicker(L("Enthusiasm", "Coşku"), selection: $personalization.enthusiasm)
                levelPicker("Emoji", selection: $personalization.emoji)
                levelPicker(L("Visual answers", "Görsel cevaplar"), selection: $personalization.visualAnswers)
            } footer: {
                footer(L("These work with every model and provider. Visual answers covers tables, charts and interactive pages.",
                         "Bunlar her model ve sağlayıcıyla çalışır. Görsel cevaplar; tablo, grafik ve etkileşimli sayfaları kapsar."))
            }
            .listRowBackground(Palette.surface)

            Section {
                TextField(L("Custom instructions", "Özel talimatlar"), text: $instructions,
                          prompt: prompt(L("E.g. Keep answers brief", "Örn. Kısa cevap ver")), axis: .vertical)
                    .lineLimit(3...12)
            } header: {
                header(L("Custom instructions", "Özel talimatlar"))
            } footer: {
                footer(L("Shared with the assistant in every chat. If they conflict with the choices above, these win.",
                         "Her sohbette asistana iletilir. Yukarıdaki seçimlerle çakışırsa bunlar geçerli olur."))
            }
            .listRowBackground(Palette.surface)

            Section {
                Toggle(L("Search documents", "Dokümanlarda ara"), isOn: $personalization.searchesDocuments)
            } footer: {
                footer(L("Lets the assistant search your saved documents for answers.",
                         "Asistan cevap için kayıtlı dokümanlarında arama yapabilir."))
            }
            .listRowBackground(Palette.surface)
        }
        .foregroundStyle(Palette.textBright)
        .tint(Palette.blue)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle(L("Personalization", "Kişiselleştirme"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            personalization = settings.personalization
            instructions = settings.userInstructions
        }
        .onChange(of: personalization) { settings.savePersonalization(personalization) }
        .onDisappear { settings.saveUserInstructions(instructions) }
    }

    private func levelPicker(_ title: String, selection: Binding<Personalization.Level>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Personalization.Level.allCases, id: \.self) { level in
                Text(level.title).tag(level)
            }
        }
    }
}

private extension Personalization.Style {
    var title: String {
        switch self {
        case .standard: L("Default", "Varsayılan")
        case .professional: L("Professional", "Profesyonel")
        case .friendly: L("Friendly", "Samimi")
        case .candid: L("Candid", "Açık sözlü")
        case .quirky: L("Quirky", "Eğlenceli")
        case .efficient: L("Efficient", "Verimli")
        case .nerdy: L("Nerdy", "Meraklı")
        }
    }
}

private extension Personalization.Level {
    var title: String {
        switch self {
        case .standard: L("Default", "Varsayılan")
        case .more: L("More", "Daha fazla")
        case .less: L("Less", "Daha az")
        }
    }
}
