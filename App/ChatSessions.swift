import Foundation
import Observation
import SwiftData

/// Ekrandaki sohbet ve arkada süren cevaplar. Her cevap kendi `ChatViewModel`'inde çalışır; bu sayede
/// cevap yazılırken başka sohbete geçilebilir, cevap arkada sürer ve kaydedilir.
@Observable @MainActor
final class ChatSessions {
    private(set) var active = ChatViewModel()
    /// Ekranda olmayan sohbetler: cevabı sürenler ve hatayla bitip henüz açılmayanlar.
    private var parked: [ChatViewModel] = []
    private var dependencies: (context: ModelContext, usage: UsageTracker, skills: SkillLibrary, connectors: ConnectorLibrary)?
    private var isInBackground = false

    private var all: [ChatViewModel] {
        [active] + parked
    }

    /// Gizli sohbet kaydedilmediği için cevabı sürerken bırakılamaz: geri dönülecek bir kaydı yok.
    var isLocked: Bool {
        active.isStreaming && active.isIncognito
    }

    /// Cevabı süren sohbetler.
    var streamingIDs: Set<UUID> {
        Set(all.filter { $0.isStreaming }.compactMap { $0.conversationID })
    }

    /// Arkada kalıp kullanıcının onayını bekleyen sohbetler.
    var waitingIDs: Set<UUID> {
        Set(parked.filter { $0.isWaitingForUser }.compactMap { $0.conversationID })
    }

    var firstWaiting: ChatViewModel? {
        parked.first { $0.isWaitingForUser }
    }

    func attach(_ context: ModelContext, usage: UsageTracker, skills: SkillLibrary, connectors: ConnectorLibrary) {
        dependencies = (context, usage, skills, connectors)
        all.forEach { $0.attach(context, usage: usage, skills: skills, connectors: connectors) }
    }

    /// Kaydı açık bir oturumda olan sohbet.
    func session(for id: UUID) -> ChatViewModel? {
        all.first { $0.conversationID == id }
    }

    func open(_ record: ConversationRecord) {
        guard !isLocked, record.id != active.conversationID || !active.isStreaming else { return }
        if let session = parked.first(where: { $0.conversationID == record.id }) {
            show(session)
        } else {
            if active.isStreaming { replaceActive(with: makeSession()) }
            active.open(record)
        }
        removeFinished()
    }

    func startNewChat(incognito: Bool = false, project: ProjectRecord? = nil, modelOverride: UUID? = nil) {
        guard !isLocked else { return }
        if active.isStreaming { replaceActive(with: makeSession()) }
        active.startNewChat(incognito: incognito, project: project, modelOverride: modelOverride)
        removeFinished()
    }

    /// Arkadaki oturumu ekrana getirir.
    func show(_ session: ChatViewModel) {
        guard !isLocked, session !== active else { return }
        parked.removeAll { $0 === session }
        replaceActive(with: session)
    }

    /// Kaydı silinen sohbetin oturumunu kapatır.
    func forget(_ id: UUID) {
        if active.conversationID == id { active.startNewChat() }
        parked.removeAll { $0.conversationID == id }
    }

    func appMovedToBackground() {
        isInBackground = true
        all.forEach { $0.appMovedToBackground() }
    }

    func appBecameActive() {
        isInBackground = false
        all.forEach { $0.appBecameActive() }
        removeFinished()
    }

    private func replaceActive(with session: ChatViewModel) {
        let previous = active
        if previous.isStreaming {
            parked.append(previous)
        } else {
            // Yazılmakta olan metin kullanıcıyla gelir; `startNewChat` gizli sohbetin dosyalarını temizler.
            session.restoreDraft(previous.setAsideDraft())
            previous.startNewChat()
        }
        active = session
    }

    private func makeSession() -> ChatViewModel {
        let session = ChatViewModel()
        if let dependencies {
            session.attach(dependencies.context, usage: dependencies.usage, skills: dependencies.skills, connectors: dependencies.connectors)
        }
        if isInBackground { session.appMovedToBackground() }
        return session
    }

    /// Sorunsuz biten cevap zaten kayıtlıdır; hatası görülmemiş olanlar açılana kadar bekler.
    private func removeFinished() {
        parked.removeAll { !$0.isStreaming && $0.errorMessage == nil }
    }
}
