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
            } else if preview.kind == .document {
                VStack(spacing: 3) {
                    Image(systemName: "doc.text")
                        .font(.title3)
                    Text(preview.name ?? "")
                        .font(.system(size: 9))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 3)
                }
                .foregroundStyle(Palette.yellow)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.background)
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

/// Tam ekran gösterilecek görsel.
struct ViewedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Görseli tam ekran gösterir: iki parmakla yakınlaştırma, sürükleme, çift dokunuşla sıfırlama.
struct ImageViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    MagnifyGesture()
                        .onChanged { scale = max(1, min(lastScale * $0.magnification, 6)) }
                        .onEnded { _ in
                            lastScale = scale
                            if scale == 1 { resetPosition() }
                        }
                        .simultaneously(with: DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height)
                            }
                            .onEnded { _ in lastOffset = offset })
                )
                .onTapGesture(count: 2) {
                    withAnimation(.snappy) {
                        if scale > 1 {
                            scale = 1
                            lastScale = 1
                            resetPosition()
                        } else {
                            scale = 2.5
                            lastScale = 2.5
                        }
                    }
                }

            HStack(spacing: 12) {
                ShareLink(item: Image(uiImage: image), preview: SharePreview(L("Image", "Görsel"), image: Image(uiImage: image))) {
                    Image(systemName: "square.and.arrow.up")
                }
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel(L("Close", "Kapat"))
            }
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .padding(12)
            .background(.black.opacity(0.5), in: .capsule)
            .padding()
        }
    }

    private func resetPosition() {
        offset = .zero
        lastOffset = .zero
    }
}

/// Kamerayla fotoğraf çekme (UIImagePickerController).
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
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

/// Üretilen görsel: dokununca tam ekran, uzun basınca Fotoğraflar'a kaydetme ve paylaşma.
struct GeneratedImageView: View {
    let name: String
    let show: (UIImage) -> Void
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
                    .onTapGesture { show(image) }
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
