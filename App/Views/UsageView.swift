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
                    row(L("Total", "Toplam"), usage.totals(providerID: provider.id), emphasized: true)
                } header: {
                    header(provider.name)
                }
                .listRowBackground(Palette.surface)
            }

            Section {
                HStack {
                    Text(L("Searches", "Arama sayısı"))
                        .foregroundStyle(Palette.textBright)
                    Spacer()
                    Text(usage.tavilySearches.formatted())
                        .foregroundStyle(Palette.text)
                        .monospacedDigit()
                }
            } header: {
                header("Tavily")
            } footer: {
                footer(L("Each basic search uses 1 Tavily credit.", "Her temel arama Tavily'de 1 kredi kullanır."))
            }
            .listRowBackground(Palette.surface)

            Section {
                Button(L("Reset Counters", "Sayaçları sıfırla"), role: .destructive) { confirmingReset = true }
            } footer: {
                footer(L("Since \(usage.since.formatted(date: .abbreviated, time: .omitted)). Token counts are reported by the provider; if it doesn't report them, they aren't counted.", "\(usage.since.formatted(date: .abbreviated, time: .omitted)) tarihinden beri. Token sayıları sağlayıcının bildirdiği değerlerdir; sağlayıcı bildirmezse sayılmaz."))
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle(L("Usage", "Kullanım"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(L("Reset all usage counters?", "Tüm kullanım sayaçları sıfırlansın mı?"), isPresented: $confirmingReset, titleVisibility: .visible) {
            Button(L("Reset", "Sıfırla"), role: .destructive) { usage.reset() }
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
            Text(L("Input \(totals.promptTokens.formatted()) · Output \(totals.completionTokens.formatted()) · \(totals.requests.formatted()) requests", "Giriş \(totals.promptTokens.formatted()) · Çıkış \(totals.completionTokens.formatted()) · \(totals.requests.formatted()) istek"))
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
                .monospacedDigit()
        }
    }
}
