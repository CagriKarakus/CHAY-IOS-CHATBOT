import AgentCore
import AVFoundation
import Foundation
import ImageIO
import NaturalLanguage
import Observation
import UniformTypeIdentifiers
import ZIPFoundation
import UIKit

/// Modele gönderilecek görseli küçültür (uzun kenar en fazla 1568 px, JPEG) ve küçük bir önizleme üretir.
/// Ana iş parçacığında çağrılmamalı; `ChatViewModel.addImage` arka planda çalıştırır.
func preparedImage(from data: Data) -> (jpeg: Data, thumbnail: Data)? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let jpeg = downsampled(source, maxSide: 1568, quality: 0.8),
          let thumbnail = downsampled(source, maxSide: 240, quality: 0.7)
    else { return nil }
    return (jpeg, thumbnail)
}

/// Fotoğrafın tamamını belleğe açmadan küçültür; EXIF yönünü uygular.
private func downsampled(_ source: CGImageSource, maxSide: Int, quality: CGFloat) -> Data? {
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxSide,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: image).jpegData(compressionQuality: quality)
}

/// Ses girdisi için 16 kHz mono WAV kaydı (OpenAI `input_audio` wav kabul eder). En fazla 2 dakika.
@Observable @MainActor
final class AudioRecorder {
    static let maxDuration: TimeInterval = 120

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    /// Kayıt kendiliğinden durdu: telefon araması gibi bir kesinti veya süre sınırı. Alınan kısım eklenebilir.
    private(set) var stoppedEarly = false
    private var recorder: AVAudioRecorder?
    private var timer: Task<Void, Never>?

    private var fileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("recording.wav")
    }

    /// Mikrofon izni yoksa `false`.
    func start() async throws -> Bool {
        guard await AVAudioApplication.requestRecordPermission() else { return false }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.record(forDuration: Self.maxDuration)
        self.recorder = recorder
        isRecording = true
        stoppedEarly = false
        elapsed = 0
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let recorder = self.recorder else { return }
                guard recorder.isRecording else {
                    self.stoppedEarly = true
                    return
                }
                self.elapsed = recorder.currentTime
            }
        }
        return true
    }

    /// Kaydı bitirip WAV verisini döndürür.
    func stop() -> (data: Data, duration: TimeInterval)? {
        guard let recorder else { return nil }
        let duration = max(recorder.currentTime, elapsed)
        recorder.stop()
        finish()
        guard let data = try? Data(contentsOf: fileURL), duration > 0.3 else { return nil }
        return (data, duration)
    }

    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        finish()
    }

    private func finish() {
        timer?.cancel()
        timer = nil
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Cevapları telefonun kendi sesiyle okur; dil metinden tahmin edilir. Her modelde çalışır.
@Observable @MainActor
final class SpeechReader: NSObject, AVSpeechSynthesizerDelegate {
    /// Okunmakta olan mesajın kimliği.
    private(set) var speakingID: UUID?
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(_ id: UUID, text: String) {
        if speakingID == id {
            stop()
            return
        }
        stop()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        if let language = NLLanguageRecognizer.dominantLanguage(for: text) {
            utterance.voice = AVSpeechSynthesisVoice(language: language.rawValue)
        }
        speakingID = id
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speakingID = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished() }
    }

    private func finished() {
        guard !synthesizer.isSpeaking else { return }
        speakingID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Gönderilen görsellerin tam boyutlu kopyaları (büyütüp bakabilmek için); sohbet silinince silinir.
enum AttachmentFiles {
    static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Attachments")
    }

    static func save(_ data: Data) -> String? {
        let name = UUID().uuidString + ".jpg"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (try? data.write(to: directory.appendingPathComponent(name), options: .atomic)) == nil ? nil : name
    }

    static func image(named name: String) -> UIImage? {
        UIImage(contentsOfFile: directory.appendingPathComponent(name).path)
    }

    static func delete(_ names: [String]) {
        for name in names {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}

/// Metin veya Office dosyasından modele gönderilecek metni çıkarır. PDF'ler için `readDocument` kullanılır.
func extractDocumentText(from url: URL) -> String? {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }

    let fileExtension = url.pathExtension.lowercased()
    if let kind = OfficeText.Kind(rawValue: fileExtension) {
        // docx/xlsx/pptx: ZIP arşivini aç, içteki XML'lerden metni çıkar.
        guard let archive = try? Archive(url: url, accessMode: .read) else { return nil }
        let entries = archive.map(\.path)
        return OfficeText.extract(kind: kind, entries: entries) { path in
            guard let entry = archive[path] else { return nil }
            var data = Data()
            _ = try? archive.extract(entry, skipCRC32: true) { data.append($0) }
            return data
        }
    }
    return try? String(contentsOf: url, encoding: .utf8)
}

/// Eklenebilen doküman türleri: PDF, düz metin ve Office (Word, Excel, PowerPoint).
let documentContentTypes: [UTType] = [.pdf, .plainText, .text]
    + ["org.openxmlformats.wordprocessingml.document",
       "org.openxmlformats.spreadsheetml.sheet",
       "org.openxmlformats.presentationml.presentation"].compactMap { UTType($0) }

/// Üretilen görseli Documents klasörüne kaydeder (Dosyalar uygulamasında görünür); dosya adını döndürür.
func saveGeneratedImage(_ data: Data) throws -> String {
    let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let name = "image-\(formatter.string(from: .now)).\(isPNG ? "png" : "jpg")"
    try FileManager.default.createDirectory(at: DocumentFile.directory, withIntermediateDirectories: true)
    try data.write(to: DocumentFile.directory.appendingPathComponent(name), options: .atomic)
    return name
}
