import AgentCore
import SwiftUI

/// Araç günlüğü: cevap akarken adımlar açık görünür, bitince tek satırlık özete kapanır.
struct ToolLog: View {
    let activities: [ToolActivity]
    let isStreaming: Bool
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isStreaming || expanded {
                if !isStreaming {
                    header
                }
                ForEach(activities) { activity in
                    ActivityRow(activity: activity)
                }
            } else {
                header
            }
        }
    }

    private var header: some View {
        Button {
            withAnimation(.snappy) { expanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.indent")
                Text(summary)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
            }
            .font(.footnote)
            .foregroundStyle(Palette.textMuted)
        }
        .buttonStyle(.plain)
    }

    /// "2 arama · 1 sayfa · 1 not" gibi kısa özet.
    private var summary: String {
        let counts = Dictionary(grouping: activities, by: \.toolName).mapValues(\.count)
        let parts: [String] = [
            counts["web_search"].map { L($0 == 1 ? "1 search" : "\($0) searches", "\($0) arama") },
            counts["fetch_page"].map { L($0 == 1 ? "1 page" : "\($0) pages", "\($0) sayfa") },
            counts["write_file"].map { L($0 == 1 ? "1 file" : "\($0) files", "\($0) dosya") },
            counts["save_note"].map { L($0 == 1 ? "1 note" : "\($0) notes", "\($0) not") },
            counts["read_notes"].map { _ in L("notes read", "notlar okundu") },
            counts["compact"].map { _ in L("context summarized", "bağlam özetlendi") },
            counts["generate_image"].map { _ in L("image generated", "görsel üretildi") },
            counts["use_skill"].map { _ in L("skill used", "skill kullanıldı") },
            counts["calculate"].map { _ in L("calculated", "hesaplandı") },
            counts["create_artifact"].map { _ in L("page created", "sayfa oluşturuldu") },
        ].compactMap { $0 }
        let failed = activities.filter { $0.state == .failed }.count
        let steps = activities.count
        let text = parts.isEmpty ? L(steps == 1 ? "1 step" : "\(steps) steps", "\(steps) adım") : parts.joined(separator: " · ")
        return failed > 0 ? L("\(text) · \(failed) failed", "\(text) · \(failed) başarısız") : text
    }
}

struct ActivityRow: View {
    let activity: ToolActivity

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch activity.state {
                case .running:
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Palette.textMuted)
                case .done:
                    Image(systemName: icon)
                        .foregroundStyle(Palette.cyan)
                case .failed:
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Palette.red)
                }
            }
            .frame(width: 16)
            Text(activity.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Palette.textMuted)
        }
        .font(.footnote)
    }

    private var icon: String {
        switch activity.toolName {
        case "web_search": "magnifyingglass"
        case "fetch_page": "doc.text"
        case "write_file": "doc.badge.plus"
        case "save_note": "brain"
        case "read_notes": "list.bullet.rectangle"
        case "compact": "rectangle.compress.vertical"
        case "generate_image": "paintbrush"
        case "use_skill": "sparkles"
        case "calculate": "function"
        case "create_artifact": "play.rectangle"
        default: "wrench.and.screwdriver"
        }
    }
}

/// Cevabın altında token kullanımı, hız ve durdurma bilgisi.
struct MessageFooter: View {
    let usage: TokenUsage?
    let stopped: Bool

    var body: some View {
        HStack(spacing: 10) {
            if stopped {
                Label(L("Stopped", "Durduruldu"), systemImage: "stop.circle")
            }
            if let usage {
                Label("\(usage.promptTokens.formatted(.number.notation(.compactName))) → \(usage.completionTokens.formatted(.number.notation(.compactName))) token", systemImage: "number")
                if let speed = usage.tokensPerSecond {
                    Label(L("\(speed.formatted(.number.precision(.fractionLength(0)))) tok/s", "\(speed.formatted(.number.precision(.fractionLength(0)))) tok/sn"), systemImage: "speedometer")
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(Palette.textMuted)
        .labelStyle(.titleAndIcon)
        .monospacedDigit()
    }
}
