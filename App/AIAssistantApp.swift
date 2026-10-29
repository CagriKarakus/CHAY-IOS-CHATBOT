import SwiftData
import SwiftUI
import UIKit

@main
struct AIAssistantApp: App {
    @State private var settings = AppSettings()
    @State private var usage = UsageTracker()
    @State private var speech = SpeechReader()
    @State private var skills = SkillLibrary()
    @State private var connectors = ConnectorLibrary()
    @State private var prompts = PromptLibrary()
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(settings)
                .environment(usage)
                .environment(speech)
                .environment(skills)
                .environment(connectors)
                .environment(prompts)
                .tint(Palette.blue)
                .onAppear { apply(appearance) }
                .onChange(of: appearance) { apply(appearance) }
        }
        .modelContainer(for: [NoteRecord.self, ConversationRecord.self, ProjectRecord.self])
    }

    /// Pencere düzeyinde uygulanır ki açık sayfalar (sheet) da hemen değişsin ve "Sistem"e dönüş çalışsın.
    private func apply(_ appearance: Appearance) {
        let style: UIUserInterfaceStyle = switch appearance {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach { $0.overrideUserInterfaceStyle = style }
        }
    }
}
