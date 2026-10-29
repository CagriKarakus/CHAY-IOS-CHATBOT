import AgentCore
import SwiftUI

// Faz E: CI → .ipa → sideload zincirini doğrulamak için geçici ekran.
struct ContentView: View {
    private let greeting = ChatMessage(role: .assistant, content: "Merhaba! Kurulum çalışıyor.")

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
            Text(greeting.content ?? "")
                .font(.headline)
        }
        .padding()
    }
}
