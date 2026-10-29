import SwiftUI

@main
struct AIAssistantApp: App {
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environment(settings)
                .preferredColorScheme(.dark)
                .tint(Theme.blue)
        }
    }
}
