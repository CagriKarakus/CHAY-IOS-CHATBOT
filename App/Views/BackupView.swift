import SwiftData
import SwiftUI

/// Tüm veriyi tek dosyaya yedekleme ve geri yükleme.
struct BackupView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(SkillLibrary.self) private var skills
    @Environment(PromptLibrary.self) private var prompts
    @State private var sharedFile: SharedFile?
    @State private var importing = false
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        Form {
            Section {
                Button {
                    do {
                        sharedFile = SharedFile(url: try BackupService.export(context: context, settings: settings, skills: skills, prompts: prompts))
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
                    "The backup is one file with your chats, memory notes, skills, prompts, documents, providers and personal instructions. Save it to iCloud Drive in the Files app to keep it off the phone. API keys are not included; enter them again after restoring. Importing adds what's missing and never deletes anything.",
                    "Yedek; sohbetlerin, hafıza notların, skill'ler, hazır komutlar, dokümanlar, sağlayıcılar ve kişisel talimatlarla tek bir dosyadır. Telefondan ayrı tutmak için Dosyalar'da iCloud Drive'a kaydet. API key'ler dahil edilmez; geri yükledikten sonra yeniden gir. İçe aktarma sadece eksikleri ekler, hiçbir şeyi silmez."
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
                let summary = try BackupService.importBackup(from: url, context: context, settings: settings, skills: skills, prompts: prompts)
                show(L(
                    "Imported: \(summary.conversations) chats, \(summary.notes) notes, \(summary.skills) skills, \(summary.prompts) prompts, \(summary.documents) documents, \(summary.providers) providers.",
                    "İçe aktarıldı: \(summary.conversations) sohbet, \(summary.notes) not, \(summary.skills) skill, \(summary.prompts) komut, \(summary.documents) doküman, \(summary.providers) sağlayıcı."
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
