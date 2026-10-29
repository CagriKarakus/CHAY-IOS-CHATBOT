import SwiftData
import SwiftUI

@main
struct AIAssistantApp: App {
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(settings)
                .preferredColorScheme(.dark)
                .tint(Palette.blue)
        }
        .modelContainer(for: NoteRecord.self)
    }
}
