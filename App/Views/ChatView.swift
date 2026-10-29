import AgentCore
import SwiftUI

struct ChatView: View {
    @Environment(AppSettings.self) private var settings
    @State private var viewModel = ChatViewModel()
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
                inputBar
            }
            .navigationTitle("AI Asistan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Ayarlar")
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .onAppear {
                if !settings.isConfigured {
                    showingSettings = true
                }
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.items) { item in
                        MessageBubble(message: item.message)
                            .id(item.id)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if viewModel.items.isEmpty {
                    emptyState
                }
            }
            .onChange(of: viewModel.items.last?.message.content) {
                if let id = viewModel.items.last?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if settings.isConfigured {
            ContentUnavailableView("Ne sormak istersin?", systemImage: "sparkles")
        } else {
            ContentUnavailableView {
                Label("Ayarlar eksik", systemImage: "key")
            } description: {
                Text("Başlamak için base URL, model adı ve API key gir.")
            } actions: {
                Button("Ayarları aç") { showingSettings = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Mesaj yaz…", text: $viewModel.input, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
            Button {
                viewModel.send(using: settings)
            } label: {
                Image(systemName: viewModel.isStreaming ? "ellipsis.circle.fill" : "arrow.up.circle.fill")
                    .font(.title)
            }
            .disabled(!viewModel.canSend)
            .accessibilityLabel("Gönder")
        }
        .padding()
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }
            Group {
                if let content = message.content, !content.isEmpty {
                    Text(markdown(content))
                        .textSelection(.enabled)
                } else {
                    ProgressView()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isUser ? Color.accentColor : Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
            .foregroundStyle(isUser ? .white : .primary)
            if !isUser { Spacer(minLength: 40) }
        }
    }

    /// Satır içi Markdown (kalın, italik, kod, link); başarısız olursa düz metin.
    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}
