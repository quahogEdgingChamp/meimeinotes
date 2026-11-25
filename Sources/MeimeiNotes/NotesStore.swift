import Combine
import Foundation

struct Note: Codable, Identifiable {
    let id: UUID
    var text: String
    private var pinned: Bool?

    var isPinned: Bool {
        get { pinned ?? false }
        set { pinned = newValue ? true : nil }
    }

    init(id: UUID = UUID(), text: String = "") {
        self.id = id
        self.text = text
    }

    var title: String {
        let firstLine = text.split(whereSeparator: \.isNewline)
            .lazy.map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let firstLine else { return "Untitled" }
        return firstLine.count > 44 ? String(firstLine.prefix(44)) + "…" : firstLine
    }
}

@MainActor
final class NotesStore: ObservableObject {
    private struct Notebook: Codable {
        var notes: [Note]
        var selectedID: UUID
    }

    @Published private var notebook: Notebook {
        didSet {
            if let data = try? JSONEncoder().encode(notebook) {
                defaults.set(data, forKey: Self.key)
            }
        }
    }

    private static let key = "notebook"
    private let defaults: UserDefaults

    var notes: [Note] { notebook.notes }
    var current: Note { notes.first { $0.id == notebook.selectedID } ?? notes[0] }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let restored = try? JSONDecoder().decode(Notebook.self, from: data),
           !restored.notes.isEmpty {
            notebook = restored
        } else {
            let first = Note()
            notebook = Notebook(notes: [first], selectedID: first.id)
        }
    }

    func create() {
        let note = Note()
        notebook = Notebook(notes: [note] + notes, selectedID: note.id)
    }

    func select(_ id: UUID) {
        guard notebook.selectedID != id, notes.contains(where: { $0.id == id }) else { return }
        notebook.selectedID = id
    }

    func matching(_ query: String) -> [Note] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = term.isEmpty ? notes : notes.filter {
            $0.title.localizedStandardContains(term) || $0.text.localizedStandardContains(term)
        }
        return matches.filter(\.isPinned) + matches.filter { !$0.isPinned }
    }

    func togglePin(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notebook.notes[index].isPinned.toggle()
    }

    func text(for id: UUID) -> String {
        notes.first { $0.id == id }?.text ?? ""
    }

    func update(_ id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        notebook.notes[index].text = text
    }

    func delete(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var remaining = notes
        remaining.remove(at: index)
        if remaining.isEmpty { remaining = [Note()] }
        let selection = id == current.id ? remaining[min(index, remaining.count - 1)].id : current.id
        notebook = Notebook(notes: remaining, selectedID: selection)
    }

    func export(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(notebook).write(to: url, options: .atomic)
    }
}

