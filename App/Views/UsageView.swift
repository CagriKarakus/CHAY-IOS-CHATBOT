import SwiftUI

/// Sağlayıcı/model bazında token kullanımı ve Tavily arama sayısı.
struct UsageView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UsageTracker.self) private var usage
    @State private var confirmingReset = false

    var body: some View {
        List {
            ForEach(settings.providers) { provider in
                Section {
                    ForEach(provider.models) { model in
                        row(model.name, usage.totals(providerID: provider.id, model: model.name))
                    }
                    row("Toplam", usage.totals(providerID: provider.id), emphasized: true)
                } header: {
                    header(provider.name)
                }
                .listRowBackground(Palette.surface)
            }

            Section {
                HStack {
                    Text("Arama sayısı")
                        .foregroundStyle(Palette.textBright)
                    Spacer()
                    Text(usage.tavilySearches.formatted())
                        .foregroundStyle(Palette.text)
                        .monospacedDigit()
                }
            } header: {
                header("Tavily")
            } footer: {
                footer("Her temel arama Tavily'de 1 kredi kullanır.")
            }
            .listRowBackground(Palette.surface)

            Section {
                Button("Sayaçları sıfırla", role: .destructive) { confirmingReset = true }
            } footer: {
                footer("\(usage.since.formatted(date: .abbreviated, time: .omitted)) tarihinden beri. Token sayıları sağlayıcının bildirdiği değerlerdir; sağlayıcı bildirmezse sayılmaz.")
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Kullanım")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Tüm kullanım sayaçları sıfırlansın mı?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Sıfırla", role: .destructive) { usage.reset() }
        }
    }

    private func row(_ title: String, _ totals: UsageTracker.Totals, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .fontWeight(emphasized ? .semibold : .regular)
                    .foregroundStyle(Palette.textBright)
                    .lineLimit(1)
                Spacer()
                Text(totals.totalTokens.formatted() + " token")
                    .foregroundStyle(Palette.text)
                    .monospacedDigit()
            }
            Text("Giriş \(totals.promptTokens.formatted()) · Çıkış \(totals.completionTokens.formatted()) · \(totals.requests.formatted()) istek")
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
                .monospacedDigit()
        }
    }
}
