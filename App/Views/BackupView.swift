import SwiftData
import SwiftUI

/// Tüm veriyi tek dosyaya yedekleme ve geri yükleme.
struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(SkillLibrary.self) private var skills
    @Environment(PromptLibrary.self) private var prompts
    @Environment(ConnectorLibrary.self) private var connectors
    @Environment(ScheduledTaskLibrary.self) private var scheduledTasks
    @State private var sharedFile: SharedFile?
    @State private var importing = false
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                Button {
                    do {
                        sharedFile = SharedFile(url: try BackupService.export(context: context, settings: settings, skills: skills, prompts: prompts, connectors: connectors, scheduledTasks: scheduledTasks))
                    } catch {
                        show(userFacingMessage(for: error), failed: true)
                    }
                } label: {
                    Label(L("Export Backup", "Yedeği dışa aktar"), systemImage: "square.and.arrow.up")
                }
                Button {
                    importing = true
                } label: {
                    Label(L("Import Backup", "Yedeği içe aktar"), systemImage: "square.and.arrow.down")
                }
            } footer: {
                footer(L(
                    "The backup is one file with your chats, memory notes, skills, prompts, documents, providers, connectors, scheduled tasks and personal instructions. Save it to iCloud Drive in the Files app to keep it off the phone. API keys, connector tokens and sign-ins are not included; enter them or sign in again after restoring. Importing adds what's missing and never deletes anything.",
                    "Yedek; sohbetlerin, hafıza notların, skill'ler, hazır komutlar, dokümanlar, sağlayıcılar, bağlayıcılar, zamanlanmış görevler ve kişisel talimatlarla tek bir dosyadır. Telefondan ayrı tutmak için Dosyalar'da iCloud Drive'a kaydet. API key'ler, bağlayıcı token'ları ve girişler dahil edilmez; geri yükledikten sonra yeniden gir veya giriş yap. İçe aktarma sadece eksikleri ekler, hiçbir şeyi silmez."
                ))
            }
            .listRowBackground(Palette.surface)

            if let message {
                Section {
                    Text(message)
                        .foregroundStyle(failed ? Palette.red : Palette.green)
                }
                .listRowBackground(Palette.surface)
            }
        }
        .foregroundStyle(Palette.textBright)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle(L("Backup", "Yedekleme"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sharedFile) { file in
            ShareSheet(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case let .success(url) = result else { return }
            do {
                let summary = try BackupService.importBackup(from: url, context: context, settings: settings, skills: skills, prompts: prompts, connectors: connectors, scheduledTasks: scheduledTasks)
                show(L(
                    "Imported: \(summary.projects) projects, \(summary.conversations) chats, \(summary.notes) notes, \(summary.skills) skills, \(summary.prompts) prompts, \(summary.documents) documents, \(summary.providers) providers, \(summary.connectors) connectors, \(summary.scheduledTasks) scheduled tasks.",
                    "İçe aktarıldı: \(summary.projects) proje, \(summary.conversations) sohbet, \(summary.notes) not, \(summary.skills) skill, \(summary.prompts) komut, \(summary.documents) doküman, \(summary.providers) sağlayıcı, \(summary.connectors) bağlayıcı, \(summary.scheduledTasks) zamanlanmış görev."
                ), failed: false)
            } catch {
                show(L("This file isn't a valid backup.", "Bu dosya geçerli bir yedek değil."), failed: true)
            }
        }
    }

    private func show(_ text: String, failed: Bool) {
        message = text
        self.failed = failed
    }
}
