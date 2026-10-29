import SwiftUI

/// Modelin düşünme metni: düşünürken açık ve son satırlar görünür, bitince tek satıra kapanır (Claude'daki gibi).
struct ThinkingView: View {
    let text: String
    /// Model şu an düşünüyor mu (cevap ya da araç henüz başlamadı).
    let isActive: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    if isActive {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(Palette.purple)
                    } else {
                        Image(systemName: "brain")
                            .foregroundStyle(Palette.purple)
                    }
                    Text(isActive ? L("Thinking…", "Düşünüyor…") : L("Thought process", "Düşünme süreci"))
                    Image(systemName: expanded || isActive ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
            }
            .buttonStyle(.plain)

            if isActive || expanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        Text(text)
                            .font(.footnote)
                            .foregroundStyle(Palette.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id("end")
                    }
                    // Düşünürken son satırlar görünsün; açıldığında tamamı okunabilsin.
                    .frame(maxHeight: isActive ? 120 : 320)
                    .onChange(of: text) {
                        if isActive { proxy.scrollTo("end", anchor: .bottom) }
                    }
                }
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Palette.purple.opacity(0.5))
                        .frame(width: 2)
                }
            }
        }
    }
}

/// Model bir aracın içeriğini yazarken (ör. uzun bir sayfa) canlı ilerleme satırı.
struct PreparingRow: View {
    let preparing: PreparingTool

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .tint(Palette.textMuted)
                .frame(width: 16)
            Text(title)
                .monospacedDigit()
                .foregroundStyle(Palette.textMuted)
        }
        .font(.footnote)
    }

    private var title: String {
        let characters = preparing.characters.formatted(.number.notation(.compactName))
        let action = switch preparing.toolName {
        case "create_artifact": L("Writing page", "Sayfa yazılıyor")
        case "write_file": L("Writing file", "Dosya yazılıyor")
        default: L("Preparing \(preparing.toolName)", "\(preparing.toolName) hazırlanıyor")
        }
        return preparing.characters > 0
            ? L("\(action)… \(characters) characters", "\(action)… \(characters) karakter")
            : action + "…"
    }
}
