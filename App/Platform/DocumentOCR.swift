import Foundation
import PDFKit
import UIKit
import Vision

/// Okunan dokümanın metni.
struct DocumentReading: Sendable {
    let text: String
    /// Sınır nedeniyle okunmayan taranmış sayfa sayısı.
    var skippedPages = 0
}

/// PDF okuma: metin katmanı olan sayfalar doğrudan alınır, taranmış sayfalar telefonda Vision ile okunur.
/// Hiçbir şey sunucuya gitmez; her model ve sağlayıcıyla çalışır.
enum DocumentOCR {
    /// Metin tanımayla okunacak en fazla sayfa (uzun taramalar dakikalar sürebilir).
    static let pageLimit = 30
    /// Bundan kısa metin taşıyan sayfa taranmış sayılır (tarayıcıların bıraktığı damga vb.).
    private static let minimumPageText = 20
    /// Görüntünün uzun kenarı (piksel): küçük yazıların okunması için yeterli, bellek için güvenli.
    private static let imageSide: CGFloat = 2_200

    static func read(pdfAt url: URL) async -> DocumentReading? {
        await Task.detached(priority: .userInitiated) {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let document = PDFDocument(url: url) else { return nil }

            var pages: [String] = []
            var scannedPages = 0
            var skipped = 0
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let text = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if text.count >= minimumPageText {
                    pages.append(text)
                } else if scannedPages < pageLimit {
                    scannedPages += 1
                    pages.append(recognize(page) ?? text)
                } else {
                    skipped += 1
                }
            }
            let text = pages.filter { !$0.isEmpty }.joined(separator: "\n\n")
            return text.isEmpty ? nil : DocumentReading(text: text, skippedPages: skipped)
        }.value
    }

    private static func recognize(_ page: PDFPage) -> String? {
        let bounds = page.bounds(for: .mediaBox)
        let scale = imageSide / max(bounds.width, bounds.height, 1)
        let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        guard let cgImage = image.cgImage else { return nil }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        // Cihazın desteklediği diller arasından; desteklenmeyen dil istek hatasına yol açar.
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let languages = ["tr-TR", "en-US"].filter(supported.contains)
        if !languages.isEmpty {
            request.recognitionLanguages = languages
        }
        do {
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
        } catch {
            return nil
        }
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// Dokümanın modele gönderilecek metni; okunamıyor veya metin yoksa `nil`.
func readDocument(from url: URL) async -> DocumentReading? {
    if url.pathExtension.lowercased() == "pdf" {
        return await DocumentOCR.read(pdfAt: url)
    }
    guard let text = extractDocumentText(from: url), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }
    return DocumentReading(text: text)
}

/// Okunmayan sayfalar için kullanıcıya gösterilen not.
func skippedPagesNote(_ count: Int) -> String {
    L("Only the first \(DocumentOCR.pageLimit) scanned pages were read; \(count) more were skipped.",
      "Sadece ilk \(DocumentOCR.pageLimit) taranmış sayfa okundu; \(count) sayfa atlandı.")
}
