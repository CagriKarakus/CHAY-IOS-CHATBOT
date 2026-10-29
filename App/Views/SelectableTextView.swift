import SwiftUI
import UIKit

/// "Metni seç" ekranında gösterilen metin.
struct SelectableTextItem: Identifiable {
    let id = UUID()
    let text: String
}

/// SwiftUI `Text` sadece bütün olarak kopyalanabildiği için kısmi seçim UITextView ile yapılır.
struct SelectableTextSheet: View {
    let item: SelectableTextItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableTextView(text: item.text)
                .ignoresSafeArea(edges: .bottom)
                .background(Palette.background)
                .navigationTitle(L("Select Text", "Metni seç"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Palette.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Done", "Bitti")) { dismiss() }
                    }
                }
        }
    }
}

private struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.dataDetectorTypes = .link
        view.backgroundColor = UIColor(Palette.background)
        view.textColor = UIColor(Palette.textBright)
        view.tintColor = UIColor(Palette.blue)
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 32, right: 16)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text {
            view.text = text
        }
    }
}

/// Markdown işaretlerini (##, **, ```) atıp okunabilir düz metin üretir; kopyalama ve seçim için.
func plainText(fromMarkdown markdown: String) -> String {
    let lines = markdown.components(separatedBy: "\n").compactMap { line -> String? in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") { return nil }
        return line.replacingOccurrences(of: #"^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
    }
    let joined = lines.joined(separator: "\n")
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    guard let attributed = try? AttributedString(markdown: joined, options: options) else { return joined }
    return String(attributed.characters)
}
