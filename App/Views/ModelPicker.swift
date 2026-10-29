import AgentCore
import SwiftUI

/// Giriş kutusundaki model seçici; modeller sağlayıcıya göre gruplanır.
struct ModelMenu: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Menu {
            ForEach(settings.providers) { provider in
                Section(provider.name) {
                    ForEach(provider.models) { model in
                        Button {
                            settings.select(model.id)
                        } label: {
                            if model.id == settings.selected?.model.id {
                                Label(model.name, systemImage: "checkmark")
                            } else {
                                Text(model.name)
                            }
                        }
                    }
                }
            }
        } label: {
            Chip(title: settings.selected?.model.name ?? L("Choose Model", "Model seç"), systemImage: "cpu")
        }
        .disabled(settings.providers.allSatisfy(\.models.isEmpty))
    }
}

/// Seçili model efor destekliyorsa görünen efor seçici.
struct EffortMenu: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if let model = settings.selected?.model, model.supportsEffort {
            Menu {
                Picker(L("Effort", "Efor"), selection: Binding(
                    get: { model.effort },
                    set: { settings.setEffort($0, for: model.id) }
                )) {
                    Text(L("Default", "Varsayılan")).tag(ReasoningEffort?.none)
                    ForEach(ReasoningEffort.allCases, id: \.self) { effort in
                        Text(effort.title).tag(ReasoningEffort?.some(effort))
                    }
                }
            } label: {
                Chip(title: model.effort?.title ?? L("Effort", "Efor"), systemImage: "gauge.with.dots.needle.50percent")
            }
        }
    }
}

private struct Chip: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .font(.footnote)
        .foregroundStyle(Palette.textMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Palette.background, in: .capsule)
        .frame(maxWidth: 190, alignment: .leading)
    }
}
