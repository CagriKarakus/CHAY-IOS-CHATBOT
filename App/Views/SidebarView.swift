import SwiftData
import SwiftUI

/// Claude tarzı kenar menüsü: arama, Projeler, Dokümanlar, sabitlenen ve son sohbetler; altta Ayarlar ve Yeni sohbet.
struct SidebarView<ChatMenu: View>: View {
    let currentID: UUID?
    /// Cevap yazılırken başka sohbete geçilemez.
    let isBusy: Bool
    let openChat: (ConversationRecord) -> Void
    let openProjects: () -> Void
    let openProject: (ProjectRecord) -> Void
    let openDocuments: () -> Void
    let openScheduled: () -> Void
    let search: () -> Void
    let openSettings: () -> Void
    let newChat: () -> Void
    /// Bir sohbete basılı tutunca açılan menü (sohbet ekranının sağ üst menüsüyle aynı).
    @ViewBuilder let chatMenu: (ConversationRecord) -> ChatMenu

    @Query(sort: \ConversationRecord.updatedAt, order: .reverse) private var conversations: [ConversationRecord]
    @Query(sort: \ProjectRecord.createdAt, order: .reverse) private var projects: [ProjectRecord]
    /// Sohbetleri kenar menüsünde açılmış projeler.
    @State private var expandedProjects: Set<UUID> = []

    private var pinned: [ConversationRecord] {
        conversations.filter(\.isPinned)
    }

    /// Projesiz, sabitlenmemiş sohbetler; proje sohbetleri projenin altında açılır.
    private var recents: [ConversationRecord] {
        conversations.filter { !$0.isPinned && $0.projectID == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("CHAY")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(Palette.textBright)
                Spacer()
                Button(action: search) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(Palette.textBright)
                        .frame(width: 44, height: 44)
                        .background(Palette.elevated, in: .circle)
                }
                .accessibilityLabel(L("Search chats", "Sohbetlerde ara"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    navigationRow(L("Projects", "Projeler"), systemImage: "folder", action: openProjects)
                    ForEach(projects) { project in
                        projectRow(project)
                        if expandedProjects.contains(project.id) {
                            let chats = conversations.filter { $0.projectID == project.id }
                            if chats.isEmpty {
                                Text(L("No chats yet", "Henüz sohbet yok"))
                                    .font(.subheadline)
                                    .foregroundStyle(Palette.textMuted)
                                    .padding(.leading, 56)
                                    .padding(.vertical, 8)
                            }
                            ForEach(chats) { chatRow($0, indented: true) }
                        }
                    }
                    navigationRow(L("Documents", "Dokümanlar"), systemImage: "doc.text", action: openDocuments)
                    navigationRow(L("Scheduled", "Zamanlanmış görevler"), systemImage: "clock", action: openScheduled)

                    if !pinned.isEmpty {
                        sectionTitle(L("Pinned", "Sabitlenenler"))
                        ForEach(pinned) { chatRow($0) }
                    }

                    sectionTitle(L("Recents", "Son sohbetler"))
                    if recents.isEmpty {
                        Text(L("No chats yet", "Henüz sohbet yok"))
                            .font(.subheadline)
                            .foregroundStyle(Palette.textMuted)
                            .padding(.horizontal, 12)
                    }
                    ForEach(recents) { chatRow($0) }
                }
                .padding(.horizontal, 8)
                // Alttaki düğmeler son sohbeti örtmesin.
                .padding(.bottom, 90)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .bottom) {
            HStack {
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundStyle(Palette.textBright)
                        .frame(width: 52, height: 52)
                        .background(Palette.elevated, in: .circle)
                }
                .accessibilityLabel(L("Settings", "Ayarlar"))
                Spacer()
                Button(action: newChat) {
                    Label(L("New chat", "Yeni sohbet"), systemImage: "plus")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Palette.background)
                        .padding(.horizontal, 22)
                        .frame(height: 52)
                        .background(Palette.textBright, in: .capsule)
                }
                .disabled(isBusy)
                .opacity(isBusy ? 0.5 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(Palette.surface)
    }

    private func navigationRow(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3)
                .foregroundStyle(Palette.textBright)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .contentShape(.rect)
        }
    }

    /// Proje adı projeyi açar; sağdaki ok sohbetlerini burada gösterir.
    private func projectRow(_ project: ProjectRecord) -> some View {
        let expanded = expandedProjects.contains(project.id)
        return HStack(spacing: 0) {
            Button {
                openProject(project)
            } label: {
                Text(project.name)
                    .lineLimit(1)
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .contentShape(.rect)
            }
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    if expanded {
                        expandedProjects.remove(project.id)
                    } else {
                        expandedProjects.insert(project.id)
                    }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.textMuted)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 44, height: 40)
                    .contentShape(.rect)
            }
            .accessibilityLabel(expanded ? L("Hide chats", "Sohbetleri gizle") : L("Show chats", "Sohbetleri göster"))
        }
        .padding(.leading, 44)
    }

    private func chatRow(_ record: ConversationRecord, indented: Bool = false) -> some View {
        Button {
            openChat(record)
        } label: {
            Text(record.title)
                .lineLimit(1)
                .foregroundStyle(Palette.textBright)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(record.id == currentID ? Palette.elevated : .clear, in: .rect(cornerRadius: 14))
                .contentShape(.rect)
        }
        .disabled(isBusy)
        .opacity(isBusy && record.id != currentID ? 0.5 : 1)
        .padding(.leading, indented ? 44 : 0)
        .contextMenu {
            chatMenu(record)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline)
            .foregroundStyle(Palette.textMuted)
            .padding(.horizontal, 12)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }
}
