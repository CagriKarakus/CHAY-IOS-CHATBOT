import SwiftUI
import WebKit

extension DocumentFile {
    /// Asistanın `create_artifact` ile oluşturduğu etkileşimli sayfa.
    var isArtifact: Bool {
        url.pathExtension.lowercased() == "html"
    }
}

/// Sohbetten açılan artifact: kendi navigasyonu ve Kapat butonuyla.
struct ArtifactView: View {
    let document: DocumentFile
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ArtifactPage(document: document)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("Close", "Kapat")) { dismiss() }
                    }
                }
        }
    }
}

/// Artifact'ı (HTML/JS) izole bir web görünümünde gösterir.
/// Sayfa sadece kendi dosyasını okuyabilir; dış linkler Safari'de açılır, uygulamanın verilerine erişemez.
/// Dosyadaki güvenlik politikası (`CreateArtifactTool`) ağ isteklerini kapatır.
struct ArtifactPage: View {
    let document: DocumentFile
    @State private var reloadToken = UUID()

    var body: some View {
        ArtifactWebView(url: document.url, reloadToken: reloadToken)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(document.name.replacingOccurrences(of: ".html", with: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        reloadToken = UUID()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel(L("Reload", "Yenile"))
                    ShareLink(item: document.url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel(L("Share", "Paylaş"))
                }
            }
    }
}

private struct ArtifactWebView: UIViewRepresentable {
    let url: URL
    let reloadToken: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Çerez ve önbellek kalıcı değil; artifact'lar birbirinin verisini göremez.
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        load(webView)
        context.coordinator.lastToken = reloadToken
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastToken != reloadToken {
            context.coordinator.lastToken = reloadToken
            load(webView)
        }
    }

    private func load(_ webView: WKWebView) {
        // Okuma izni sadece bu dosyaya; Documents'taki diğer dosyalar okunamaz.
        webView.loadFileURL(url, allowingReadAccessTo: url)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastToken: UUID?

        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let target = navigationAction.request.url else { return .cancel }
            // Kullanıcının dokunduğu dış linkler sayfadan çıkmak yerine Safari'de açılır.
            if navigationAction.navigationType == .linkActivated, target.scheme == "http" || target.scheme == "https" {
                await UIApplication.shared.open(target)
                return .cancel
            }
            // Ana çerçeve sadece artifact dosyasında kalabilir; alt çerçeveler ve kaynaklar (CDN kütüphaneleri) serbest.
            if navigationAction.targetFrame?.isMainFrame ?? true, !target.isFileURL, target.scheme != "about" {
                return .cancel
            }
            return .allow
        }
    }
}
