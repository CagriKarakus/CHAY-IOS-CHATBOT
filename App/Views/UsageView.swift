import AgentCore
import SwiftUI

/// Sağlayıcı/model bazında token kullanımı ve Tavily arama sayısı.
struct UsageView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(UsageTracker.self) private var usage
    @State private var confirmingReset = false
    @State private var tavily: TavilyState = .loading
    /// Bakiye sorgusunu destekleyen sağlayıcıların sonucu (başarısızsa hata metni).
    @State private var balances: [UUID: Result<ProviderBalance, BalanceError>] = [:]

    struct BalanceError: Error {
        let message: String
    }

    private enum TavilyState {
        case loading, noKey
        case loaded(TavilyUsage)
        case failed(String)
    }

    var body: some View {
        List {
            ForEach(settings.providers) { provider in
                Section {
                    ForEach(provider.models) { model in
                        row(model.name, usage.totals(providerID: provider.id, model: model.name))
                    }
                    row(L("Total", "Toplam"), usage.totals(providerID: provider.id), emphasized: true)
                    if ProviderBalance.supportedPresets.contains(balancePreset(provider) ?? "") {
                        balanceRows(balances[provider.id])
                    }
                } header: {
                    header(provider.name)
                }
                .listRowBackground(Palette.surface)
            }

            Section {
                switch tavily {
                case .loading:
                    HStack {
                        Text(L("Loading account usage…", "Hesap kullanımı yükleniyor…"))
                            .foregroundStyle(Palette.textMuted)
                        Spacer()
                        ProgressView()
                    }
                case let .loaded(account):
                    if let plan = account.account?.currentPlan {
                        valueRow(L("Plan", "Plan"), plan)
                    }
                    if let used = account.account?.planUsage {
                        valueRow(L("Account credits", "Hesap kredisi"), credits(used, of: account.account?.planLimit))
                    }
                    if let used = account.key?.usage {
                        valueRow(L("This key", "Bu key"), credits(used, of: account.key?.limit))
                    }
                case let .failed(message):
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Palette.red)
                case .noKey:
                    EmptyView()
                }
                valueRow(L("Searches from this device", "Bu cihazdan aramalar"), usage.tavilySearches.formatted())
            } header: {
                header("Tavily")
            } footer: {
                footer(L(
                    "Account credits come from Tavily and include all apps and devices. Each basic search uses 1 credit.",
                    "Hesap kredisi Tavily'den alınır ve tüm uygulama ve cihazları kapsar. Her temel arama 1 kredi kullanır."
                ))
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
        .task {
            await loadTavily()
            await loadBalances()
        }
        .refreshable {
            await loadTavily()
            await loadBalances()
        }
    }

    @ViewBuilder
    private func balanceRows(_ result: Result<ProviderBalance, BalanceError>?) -> some View {
        switch result {
        case nil:
            HStack {
                Text(L("Loading balance…", "Bakiye yükleniyor…"))
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                ProgressView()
            }
        case let .success(balance):
            if let remaining = balance.remaining {
                valueRow(L("Remaining", "Kalan"), money(remaining, balance.currency))
            }
            if let used = balance.used {
                valueRow(L("Used", "Kullanılan"), money(used, balance.currency))
            }
            if let limit = balance.limit {
                valueRow(L("Limit", "Limit"), money(limit, balance.currency))
            }
        case let .failure(error):
            Text(error.message)
                .font(.footnote)
                .foregroundStyle(Palette.red)
        }
    }

    /// Hazır ayarla eklenmemiş sağlayıcılar adreslerinden tanınır.
    private func balancePreset(_ provider: Provider) -> String? {
        provider.preset ?? ProviderPreset.matching(baseURL: provider.baseURL)?.id
    }

    private func money(_ value: Double, _ currency: String?) -> String {
        value.formatted(.currency(code: currency ?? "USD").precision(.fractionLength(2...4)))
    }

    /// OpenRouter, DeepSeek ve LiteLLM için hesap bakiyesi.
    private func loadBalances() async {
        for provider in settings.providers where ProviderBalance.supportedPresets.contains(balancePreset(provider) ?? "") {
            do {
                if let balance = try await ProviderBalance.fetch(
                    preset: balancePreset(provider),
                    baseURL: provider.baseURL,
                    apiKey: settings.apiKey(for: provider.id),
                    transport: URLSessionTransport()
                ) {
                    balances[provider.id] = .success(balance)
                }
            } catch {
                balances[provider.id] = .failure(BalanceError(
                    message: L("Couldn't load the balance: ", "Bakiye alınamadı: ") + userFacingMessage(for: error)
                ))
            }
        }
    }

    private func loadTavily() async {
        guard !settings.tavilyKey.isEmpty else {
            tavily = .noKey
            return
        }
        do {
            tavily = .loaded(try await TavilyUsage.fetch(apiKey: settings.tavilyKey, transport: URLSessionTransport()))
        } catch {
            tavily = .failed(L("Couldn't load Tavily usage: ", "Tavily kullanımı alınamadı: ") + userFacingMessage(for: error))
        }
    }

    private func credits(_ used: Int, of limit: Int?) -> String {
        guard let limit else { return used.formatted() }
        return "\(used.formatted()) / \(limit.formatted())"
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(Palette.textBright)
            Spacer()
            Text(value)
                .foregroundStyle(Palette.text)
                .monospacedDigit()
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
