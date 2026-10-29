import AgentCore
import SwiftUI

struct ChatView: View {
    @Environment(AppSettings.self) private var settings
    @State private var viewModel = ChatViewModel()
    @State private var showingSettings = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                composer
            }
            .background(Theme.background)
            .navigationTitle("AI Asistan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Theme.text)
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
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(viewModel.items) { item in
                        switch item.role {
                        case .user:
                            UserMessage(text: item.text)
                                .id(item.id)
                        case .assistant:
                            AssistantMessage(item: item, isStreaming: viewModel.isStreaming && item.id == viewModel.items.last?.id)
                                .id(item.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if viewModel.items.isEmpty {
                    emptyState
                }
            }
            .onChange(of: viewModel.items.last?.text) {
                if let id = viewModel.items.last?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkle")
                .font(.system(size: 36))
                .foregroundStyle(Theme.purple)
            if settings.isConfigured {
                Text("Bugün neye bakalım?")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Theme.textBright)
            } else {
                Text("Başlamak için API bilgilerini gir")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.textBright)
                Button("Ayarları aç") { showingSettings = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.blue)
            }
        }
        .padding()
    }

    /// Claude tarzı yuvarlak giriş kutusu.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Bir şey sor…", text: $viewModel.input, prompt: Text("Bir şey sor…").foregroundStyle(Theme.textMuted), axis: .vertical)
                .lineLimit(1...6)
                .focused($inputFocused)
                .foregroundStyle(Theme.textBright)
                .tint(Theme.blue)
            HStack {
                Spacer()
                Button {
                    viewModel.send(using: settings)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.background)
                        .frame(width: 32, height: 32)
                        .background(viewModel.canSend ? Theme.blue : Theme.border, in: .circle)
                }
                .disabled(!viewModel.canSend)
                .accessibilityLabel("Gönder")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(Theme.surface, in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onTapGesture { inputFocused = true }
    }
}

private struct UserMessage: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .foregroundStyle(Theme.textBright)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.elevated, in: .rect(cornerRadius: 18))
        }
    }
}

/// Balonsuz, tam genişlikte asistan cevabı; üstte araç etkinlikleri, altta kaynaklar.
private struct AssistantMessage: View {
    let item: ChatItem
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !item.activities.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.activities) { activity in
                        ActivityRow(activity: activity)
                    }
                }
            }

            if !item.text.isEmpty {
                Text(markdown(item.text))
                    .foregroundStyle(Theme.text)
                    .tint(Theme.blue)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if isStreaming, item.activities.allSatisfy({ $0.state != .running }) {
                ProgressView()
                    .tint(Theme.textMuted)
            }

            if !item.sources.isEmpty {
                SourceList(sources: item.sources)
            }
        }
    }

    /// Satır içi Markdown (kalın, italik, kod, link); başarısız olursa düz metin.
    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct ActivityRow: View {
    let activity: ToolActivity

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch activity.state {
                case .running:
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Theme.textMuted)
                case .done:
                    Image(systemName: icon)
                        .foregroundStyle(Theme.cyan)
                case .failed:
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Theme.red)
                }
            }
            .frame(width: 16)
            Text(activity.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Theme.textMuted)
        }
        .font(.footnote)
    }

    private var icon: String {
        switch activity.toolName {
        case "web_search": "magnifyingglass"
        case "fetch_page": "doc.text"
        default: "wrench.and.screwdriver"
        }
    }
}

private struct SourceList: View {
    let sources: [Source]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(sources.enumerated()), id: \.element.url) { index, source in
                    Link(destination: source.url) {
                        HStack(spacing: 6) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.background)
                                .frame(width: 16, height: 16)
                                .background(Theme.yellow, in: .circle)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(source.title)
                                    .lineLimit(1)
                                    .foregroundStyle(Theme.textBright)
                                Text(source.url.host ?? source.url.absoluteString)
                                    .lineLimit(1)
                                    .foregroundStyle(Theme.textMuted)
                            }
                            .font(.caption)
                        }
                        .frame(maxWidth: 200, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.surface, in: .rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                    }
                }
            }
        }
    }
}
