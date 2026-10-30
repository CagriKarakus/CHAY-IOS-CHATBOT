import SwiftUI
import UIKit

/// Zamanlanmış görevler: liste, hatırlatma ve Kestirmeler ile tam otomatik çalıştırma rehberi.
struct ScheduledTasksView: View {
    /// Görevi hemen yeni bir sohbette çalıştırır.
    let run: (ScheduledTask) -> Void

    @Environment(ScheduledTaskLibrary.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var notificationsDenied = false

    var body: some View {
        List {
            if notificationsDenied {
                Section {
                    Label(L("Notifications are off, so reminders can't arrive.", "Bildirimler kapalı olduğu için hatırlatmalar gelemez."),
                          systemImage: "bell.slash")
                        .foregroundStyle(Palette.yellow)
                    Button(L("Open Settings", "Ayarları aç")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                .listRowBackground(Palette.surface)
            }

            Section {
                ForEach(library.tasks) { task in
                    NavigationLink {
                        ScheduledTaskEditor(task: task, isNew: false, run: run)
                    } label: {
                        Toggle(isOn: Binding(
                            get: { task.enabled },
                            set: { library.setEnabled($0, for: task.id) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.name)
                                    .foregroundStyle(Palette.textBright)
                                Text(verbatim: "\(task.timeText) · \(task.daysText)")
                                    .font(.caption)
                                    .foregroundStyle(Palette.textMuted)
                                if let id = task.modelID, !settings.allModels.contains(where: { $0.model.id == id }) {
                                    Text(L("Its model was removed; the selected model is used.", "Modeli silinmiş; seçili model kullanılır."))
                                        .font(.caption)
                                        .foregroundStyle(Palette.yellow)
                                }
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { library.tasks[$0].id }.forEach(library.delete)
                }
                NavigationLink {
                    ScheduledTaskEditor(task: ScheduledTask(name: "", prompt: ""), isNew: true, run: run)
                } label: {
                    Label(L("New Task", "Yeni görev"), systemImage: "plus")
                        .foregroundStyle(Palette.blue)
                }
            } footer: {
                footer(L(
                    "At the set time you get a notification; tap it and the task runs in a new chat. The switch turns a task's reminder on or off.",
                    "Belirlediğin saatte bildirim gelir; dokununca görev yeni bir sohbette çalışır. Anahtar, görevin hatırlatmasını açıp kapatır."
                ))
            }
            .listRowBackground(Palette.surface)

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    step(1, L("Open Shortcuts and go to the Automation tab, then tap +.",
                              "Kestirmeler'i aç, Otomasyon sekmesine geç ve + simgesine dokun."))
                    step(2, L("Choose Time of Day, set the time and days, and select Run Immediately.",
                              "Günün Saati'ni seç, saati ve günleri ayarla, Hemen Çalıştır'ı seç."))
                    step(3, L("Add the Run CHAY Task action and pick your task.",
                              "CHAY Görevini Çalıştır (Run CHAY Task) eylemini ekle ve görevini seç."))
                }
                .padding(.vertical, 4)
                Button {
                    if let url = URL(string: "shortcuts://") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label(L("Open Shortcuts", "Kestirmeler'i aç"), systemImage: "arrow.up.forward.app")
                }
            } header: {
                header(L("Run automatically", "Tam otomatik çalıştırma"))
            } footer: {
                footer(L(
                    "iOS doesn't let apps create automations themselves, so this is set up once in Shortcuts. The automation opens CHAY at the set time and runs the task without a tap. If you use it, you can turn off the task's notification.",
                    "iOS uygulamaların otomasyonu kendisinin oluşturmasına izin vermez; bu yüzden Kestirmeler'de bir kez kurulur. Otomasyon belirlenen saatte CHAY'ı açar ve görevi dokunmadan çalıştırır. Bunu kullanırsan görevin bildirimini kapatabilirsin."
                ))
            }
            .listRowBackground(Palette.surface)
        }
        .foregroundStyle(Palette.textBright)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle(L("Scheduled Tasks", "Zamanlanmış görevler"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // Ayarlar'dan dönünce de yenilenir.
        .task(id: scenePhase) {
            notificationsDenied = await TurnNotifications.areDenied()
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(Palette.textMuted)
            Text(text)
        }
        .font(.subheadline)
    }
}

/// Görev ekleme/düzenleme.
private struct ScheduledTaskEditor: View {
    @Environment(ScheduledTaskLibrary.self) private var library
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ScheduledTask
    let isNew: Bool
    let run: (ScheduledTask) -> Void

    init(task: ScheduledTask, isNew: Bool, run: @escaping (ScheduledTask) -> Void) {
        _draft = State(initialValue: task)
        self.isNew = isNew
        self.run = run
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: draft.hour, minute: draft.minute)) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.hour = parts.hour ?? 0
                draft.minute = parts.minute ?? 0
            }
        )
    }

    var body: some View {
        Form {
            Section {
                TextField(L("Name", "Ad"), text: $draft.name, prompt: prompt(L("e.g. Morning news", "örn. Sabah haberleri")))
                TextField(L("Prompt", "Komut"), text: $draft.prompt,
                          prompt: prompt(L("e.g. Summarize today's news from these RSS feeds: …", "örn. Şu RSS akışlarından bugünün haberlerini özetle: …")),
                          axis: .vertical)
                    .lineLimit(3...10)
                Picker(L("Model", "Model"), selection: $draft.modelID) {
                    Text(L("Selected model", "Seçili model")).tag(UUID?.none)
                    if let id = draft.modelID, !settings.allModels.contains(where: { $0.model.id == id }) {
                        Text(L("Removed model", "Silinmiş model")).tag(Optional(id))
                    }
                    ForEach(settings.allModels) { option in
                        Text("\(option.model.name) · \(option.provider.name)").tag(Optional(option.model.id))
                    }
                }
            }
            .listRowBackground(Palette.surface)

            Section {
                DatePicker(L("Time", "Saat"), selection: time, displayedComponents: .hourAndMinute)
                HStack(spacing: 6) {
                    ForEach(ScheduledTask.orderedWeekdays, id: \.self) { day in
                        let selected = draft.weekdays.contains(day)
                        Button {
                            if selected {
                                draft.weekdays.removeAll { $0 == day }
                            } else {
                                draft.weekdays.append(day)
                            }
                        } label: {
                            Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .foregroundStyle(selected ? Palette.background : Palette.text)
                                .background(selected ? Palette.blue : Palette.elevated, in: .circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                Toggle(L("Remind with a notification", "Bildirimle hatırlat"), isOn: $draft.remind)
            } header: {
                header(L("When", "Ne zaman"))
            } footer: {
                footer(L("No day selected means every day. Tapping the notification runs the task.",
                         "Gün seçilmezse her gün. Bildirime dokununca görev çalışır."))
            }
            .listRowBackground(Palette.surface)

            Section {
                Button {
                    run(draft)
                } label: {
                    Label(L("Run Now", "Şimdi çalıştır"), systemImage: "play.fill")
                }
                .disabled(draft.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !isNew {
                    Button(L("Delete Task", "Görevi sil"), role: .destructive) {
                        library.delete(draft.id)
                        dismiss()
                    }
                }
            }
            .listRowBackground(Palette.surface)
        }
        .foregroundStyle(Palette.textBright)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle(isNew ? L("New Task", "Yeni görev") : draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Save", "Kaydet")) {
                    draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    library.save(draft)
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
    }
}
