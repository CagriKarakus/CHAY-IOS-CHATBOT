import SwiftData
import SwiftUI

@main
struct AIAssistantApp: App {
    @State private var settings = AppSettings()
    @State private var usage = UsageTracker()

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(settings)
                .environment(usage)
                .preferredColorScheme(.dark)
                .tint(Palette.blue)
        }
        .modelContainer(for: [NoteRecord.self, ConversationRecord.self])
    }
}
