import AgentCore
import Photos
import SwiftUI

/// Giriş kutusunun üstünde gönderilmeyi bekleyen ekler; her biri kaldırılabilir.
struct PendingAttachmentStrip: View {
    let attachments: [PendingAttachment]
    let remove: (PendingAttachment.ID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { pending in
                    AttachmentThumbnail(preview: pending.preview, size: 56)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                remove(pending.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(Palette.textBright, Palette.elevated)
                            }
                            .offset(x: 6, y: -6)
                            .accessibilityLabel(L("Remove", "Kaldır"))
                        }
                }
            }
            .padding(.top, 6)
        }
    }
}

/// Görsel için küçük resim, ses için süreli dalga simgesi.
struct AttachmentThumbnail: View {
    let preview: AttachmentPreview
    let size: CGFloat

    var body: some View {
        Group {
            if preview.kind == .image, let data = preview.thumbnail, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "waveform")
                    if let duration = preview.duration {
                        Text(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                            .font(.caption2)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(Palette.cyan)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1))
    }
}

/// Kayıt sürerken giriş kutusunda görünen çubuk.
struct RecordingBar: View {
    let elapsed: TimeInterval
    let cancel: () -> Void
    let finish: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Palette.red)
                .frame(width: 10, height: 10)
            Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                .monospacedDigit()
                .foregroundStyle(Palette.textBright)
            Text(L("Recording…", "Kaydediliyor…"))
                .foregroundStyle(Palette.textMuted)
            Spacer()
            Button(L("Cancel", "Vazgeç"), action: cancel)
                .foregroundStyle(Palette.textMuted)
            Button(L("Add", "Ekle"), action: finish)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.blue)
        }
        .font(.subheadline)
    }
}

/// Üretilen görsel: dokununca paylaşma, uzun basınca Fotoğraflar'a kaydetme.
struct GeneratedImageView: View {
    let name: String
    @State private var saved = false

    private var url: URL {
        DocumentFile.directory.appendingPathComponent(name)
    }

    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) {
            VStack(alignment: .leading, spacing: 6) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contextMenu {
                        Button(L("Save to Photos", "Fotoğraflar'a kaydet"), systemImage: "square.and.arrow.down") {
                            saveToPhotos(image)
                        }
                        ShareLink(item: url) {
                            Label(L("Share", "Paylaş"), systemImage: "square.and.arrow.up")
                        }
                    }
                if saved {
                    Label(L("Saved to Photos", "Fotoğraflar'a kaydedildi"), systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(Palette.green)
                }
            }
        } else {
            Label(L("Image not found", "Görsel bulunamadı"), systemImage: "photo")
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
        }
    }

    private func saveToPhotos(_ image: UIImage) {
        Task {
            guard await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized else { return }
            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            saved = true
        }
    }
}
