import SwiftUI
import UIKit

/// Sohbeti Markdown veya PDF olarak dışa aktarır.
enum ChatExport {
    static func markdown(title: String, items: [ChatItem]) -> String {
        var lines = ["# \(title)", "", "_\(L("Exported", "Dışa aktarıldı")) \(Date.now.formatted(date: .abbreviated, time: .shortened))_", ""]
        for item in items {
            switch item.role {
            case .user:
                lines.append("## \(L("You", "Sen"))")
                lines.append("")
                if !item.text.isEmpty { lines.append(item.text) }
                let attached = (item.attachments ?? []).map(attachmentLabel)
                if !attached.isEmpty {
                    lines.append("")
                    lines.append("_\(L("Attachments", "Ekler")): \(attached.joined(separator: ", "))_")
                }
            case .assistant:
                lines.append("## \(L("Assistant", "Asistan"))")
                lines.append("")
                lines.append(item.text)
                if !item.sources.isEmpty {
                    lines.append("")
                    lines.append("**\(L("Sources", "Kaynaklar")):**")
                    lines += item.sources.map { "- [\($0.title)](\($0.url.absoluteString))" }
                }
                if !item.files.isEmpty || !(item.images ?? []).isEmpty {
                    lines.append("")
                    lines.append("_\(L("Files", "Dosyalar")): \((item.files + (item.images ?? [])).joined(separator: ", "))_")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// A4, sayfalara bölünmüş, okunabilir düz metin PDF.
    @MainActor
    static func pdf(title: String, items: [ChatItem]) -> Data {
        let text = NSMutableAttributedString()
        func append(_ string: String, font: UIFont, color: UIColor = .black, spacing: CGFloat = 6) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = spacing
            text.append(NSAttributedString(string: string + "\n", attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph,
            ]))
        }

        append(title, font: .boldSystemFont(ofSize: 20), spacing: 4)
        append(Date.now.formatted(date: .abbreviated, time: .shortened), font: .systemFont(ofSize: 10), color: .gray, spacing: 16)
        for item in items {
            switch item.role {
            case .user:
                append(L("You", "Sen"), font: .boldSystemFont(ofSize: 13), color: UIColor(red: 0, green: 0.55, blue: 0.48, alpha: 1), spacing: 2)
                if !item.text.isEmpty { append(item.text, font: .systemFont(ofSize: 11)) }
                let attached = (item.attachments ?? []).map(attachmentLabel)
                if !attached.isEmpty {
                    append("\(L("Attachments", "Ekler")): \(attached.joined(separator: ", "))", font: .italicSystemFont(ofSize: 10), color: .gray)
                }
            case .assistant:
                append(L("Assistant", "Asistan"), font: .boldSystemFont(ofSize: 13), color: UIColor(red: 0.55, green: 0, blue: 0, alpha: 1), spacing: 2)
                append(plainText(fromMarkdown: item.text), font: .systemFont(ofSize: 11))
                if !item.sources.isEmpty {
                    append(L("Sources", "Kaynaklar") + ":\n" + item.sources.map { "• \($0.title) — \($0.url.absoluteString)" }.joined(separator: "\n"),
                           font: .systemFont(ofSize: 9), color: .darkGray)
                }
            }
            append("", font: .systemFont(ofSize: 6))
        }

        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(UISimpleTextPrintFormatter(attributedText: text), startingAtPageAt: 0)
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page.insetBy(dx: 48, dy: 56), forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, [kCGPDFContextTitle as String: title])
        for index in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: index, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    /// Paylaşmak için geçici bir dosyaya yazar.
    static func temporaryFile(named title: String, extension ext: String, data: Data) throws -> URL {
        let safe = title.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\n")).joined(separator: " ")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.prefix(60)).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func attachmentLabel(_ preview: AttachmentPreview) -> String {
        switch preview.kind {
        case .image: L("image", "görsel")
        case .audio: L("audio", "ses kaydı")
        case .document: preview.name ?? L("document", "doküman")
        }
    }
}

/// Paylaşılacak dosya.
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// iOS paylaşım menüsü (Dosyalar'a kaydet, AirDrop, Mail…).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
