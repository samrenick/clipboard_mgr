import AppKit
import Foundation

struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var date: Date
    var pinned: Bool

    init(text: String, date: Date = .now, pinned: Bool = false) {
        self.id = UUID()
        self.text = text
        self.date = date
        self.pinned = pinned
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    static let shared = ClipboardStore()

    @Published private(set) var items: [ClipItem] = []

    private var lastChangeCount: Int
    private var timer: Timer?
    private let maxItems = 500
    // Password managers mark sensitive entries with these types; skip them.
    private static let concealedTypes = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
    ]

    private let saveURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipboardMgr", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
        load()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            // The timer is scheduled on the main run loop, so this is main-thread.
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Pasteboard polling

    func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if let types = pb.types, Self.concealedTypes.contains(where: types.contains) { return }
        guard let text = pb.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        add(text)
    }

    private func add(_ text: String) {
        if let existing = items.firstIndex(where: { $0.text == text }) {
            // Re-copied an old entry: bump it to the top, keep its pin state.
            var item = items.remove(at: existing)
            item.date = .now
            items.insert(item, at: 0)
        } else {
            items.insert(ClipItem(text: text), at: 0)
            if items.count > maxItems {
                // Trim oldest unpinned entries first.
                if let victim = items.lastIndex(where: { !$0.pinned }) {
                    items.remove(at: victim)
                } else {
                    items.removeLast()
                }
            }
        }
        save()
    }

    // MARK: - Actions

    func copyToPasteboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
        lastChangeCount = pb.changeCount
        add(item.text)
    }

    func togglePin(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].pinned.toggle()
        save()
    }

    func delete(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearUnpinned() {
        items.removeAll { !$0.pinned }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data)
        else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }
}
