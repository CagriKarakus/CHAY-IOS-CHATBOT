import Foundation
import Testing
@testable import AgentCore

actor InMemoryNoteStore: NoteStore {
    private(set) var notes: [Note]

    init(_ contents: [String] = []) {
        notes = contents.map { Note(content: $0, createdAt: Date(timeIntervalSince1970: 0)) }
    }

    func allNotes() -> [Note] { notes }

    func addNote(_ content: String) {
        notes.append(Note(content: content, createdAt: Date()))
    }
}

/// Onay isteklerini sayan ve sabit cevap veren sahte kullanıcı.
final class ApprovalRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [ApprovalRequest] = []
    let answer: Bool

    init(answer: Bool) {
        self.answer = answer
    }

    var requests: [ApprovalRequest] { lock.withLock { recorded } }

    func approve(_ request: ApprovalRequest) -> Bool {
        lock.withLock { recorded.append(request) }
        return answer
    }
}

// MARK: - Araçlar

@Test func saveNoteStoresTrimmedNote() async throws {
    let store = InMemoryNoteStore()
    let tool = SaveNoteTool(store: store)

    let output = try await tool.run(arguments: #"{"content":"  Kullanıcı emoji sevmiyor. "}"#)

    #expect(output.content == "Saved to memory: Kullanıcı emoji sevmiyor.")
    #expect(await store.notes.map(\.content) == ["Kullanıcı emoji sevmiyor."])
    #expect(tool.activityDetail(for: #"{"content":"Not"}"#) == "Not")
    #expect(tool.requiresApprovalAfterUntrustedContent)
}

@Test func saveNoteSkipsDuplicates() async throws {
    let store = InMemoryNoteStore(["Kullanıcının adı Çağrı."])
    let tool = SaveNoteTool(store: store)

    let output = try await tool.run(arguments: #"{"content":"kullanıcının adı çağrı."}"#)

    #expect(output.content == "This note is already saved.")
    #expect(await store.notes.count == 1)
}

@Test func saveNoteRejectsEmptyAndLongNotes() async throws {
    let tool = SaveNoteTool(store: InMemoryNoteStore())

    await #expect(throws: ToolError.invalidArguments) {
        try await tool.run(arguments: #"{"content":"   "}"#)
    }
    let long = String(repeating: "a", count: SaveNoteTool.maxLength + 1)
    await #expect(throws: ToolError.tooLong(limit: SaveNoteTool.maxLength)) {
        try await tool.run(arguments: #"{"content":"\#(long)"}"#)
    }
}

@Test func readNotesListsNotes() async throws {
    #expect(try await ReadNotesTool(store: InMemoryNoteStore()).run(arguments: "").content == "No notes saved yet.")

    let output = try await ReadNotesTool(store: InMemoryNoteStore(["A", "B"])).run(arguments: "{}")

    #expect(output.content == "- A\n- B")
}

// MARK: - Onay

private let webResult = ChatMessage(role: .tool, content: "<untrusted_content source=\"x\">\nveri\n</untrusted_content>", toolCallID: "w1")

private func saveNoteRun(history: [ChatMessage], approver: ApprovalRecorder, store: InMemoryNoteStore) async throws -> [AgentEvent] {
    let transport = ScriptedTransport([
        toolCallLines(id: "n1", name: "save_note", arguments: #"{"content":"Kullanıcı kedi seviyor."}"#),
        [#"data: {"choices":[{"delta":{"content":"ok"}}]}"#, "data: [DONE]"],
    ])
    let loop = AgentLoop(
        client: LLMClient(configuration: try makeConfiguration(), transport: transport),
        tools: [SaveNoteTool(store: store)],
        approve: { approver.approve($0) }
    )
    return try await collect(loop.run(history))
}

@Test func savesWithoutApprovalWhenNoWebContent() async throws {
    let approver = ApprovalRecorder(answer: false)
    let store = InMemoryNoteStore()

    _ = try await saveNoteRun(history: [ChatMessage(role: .user, content: "Kedileri severim")], approver: approver, store: store)

    #expect(approver.requests.isEmpty)
    #expect(await store.notes.count == 1)
}

@Test func asksApprovalAfterWebContent() async throws {
    let approver = ApprovalRecorder(answer: true)
    let store = InMemoryNoteStore()

    _ = try await saveNoteRun(history: [ChatMessage(role: .user, content: "Ara"), webResult], approver: approver, store: store)

    #expect(approver.requests == [ApprovalRequest(toolName: "save_note", detail: "Kullanıcı kedi seviyor.")])
    #expect(await store.notes.count == 1)
}

@Test func deniedApprovalDoesNotSave() async throws {
    let approver = ApprovalRecorder(answer: false)
    let store = InMemoryNoteStore()

    let events = try await saveNoteRun(history: [ChatMessage(role: .user, content: "Ara"), webResult], approver: approver, store: store)

    #expect(approver.requests.count == 1)
    #expect(await store.notes.isEmpty)
    #expect(events.contains(.toolFinished(id: "n1", sources: [], files: [], failed: true)))
    #expect(events.contains(.message(ChatMessage(role: .tool, content: "The user declined this action; do not retry it.", toolCallID: "n1"))))
}

@Test func plainToolsNeverAskApproval() async throws {
    let approver = ApprovalRecorder(answer: false)
    let transport = ScriptedTransport([toolCallLines(id: "r1", name: "read_notes", arguments: "{}"), [#"data: {"choices":[{"delta":{"content":"ok"}}]}"#, "data: [DONE]"]])
    let loop = AgentLoop(
        client: LLMClient(configuration: try makeConfiguration(), transport: transport),
        tools: [ReadNotesTool(store: InMemoryNoteStore(["A"]))],
        approve: { approver.approve($0) }
    )

    let events = try await collect(loop.run([webResult]))

    #expect(approver.requests.isEmpty)
    #expect(events.contains(.message(ChatMessage(role: .tool, content: "- A", toolCallID: "r1"))))
}

// MARK: - System prompt

@Test func systemPromptListsNotesBeforeInstructions() {
    let notes = [Note(content: "Kullanıcının adı Çağrı.", createdAt: Date()), Note(content: "Emoji sevmiyor.", createdAt: Date())]

    let prompt = SystemPrompt.make(notes: notes, userInstructions: "Kısa yaz.")

    #expect(prompt.contains("Notes about the user from your memory (take them into account):\n- Kullanıcının adı Çağrı.\n- Emoji sevmiyor.\n\nThe user's personal instructions"))
    #expect(prompt.hasSuffix("Kısa yaz."))
}
