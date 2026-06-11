import AppKit
import Foundation
import CryptoKit

struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String?           // nil for image items
    var imageFilename: String?  // relative filename in imagesDir
    var imageHash: String?      // SHA-256 hex, used for deduplication
    var date: Date
    var pinned: Bool

    var isImage: Bool { imageFilename != nil }

    init(text: String, date: Date = .now, pinned: Bool = false) {
        id = UUID()
        self.text = text
        self.date = date
        self.pinned = pinned
    }

    init(imageFilename: String, hash: String, date: Date = .now, pinned: Bool = false) {
        id = UUID()
        self.imageFilename = imageFilename
        self.imageHash = hash
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
    private let maxItems = 200
    private let maxImageBytes = 15 * 1024 * 1024  // skip images >15 MB

    private static let concealedTypes = [
        NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"),
        NSPasteboard.PasteboardType("org.nspasteboard.TransientType"),
    ]
    private static let imageTypes: [NSPasteboard.PasteboardType] = [
        .init("public.png"), .init("public.tiff"), .tiff,
        .init("public.jpeg"), .init("com.adobe.pdf"),
    ]

    private let appSupportDir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipboardMgr", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private lazy var saveURL: URL  = { appSupportDir.appendingPathComponent("history.json") }()
    private(set) lazy var imagesDir: URL = {
        let dir = appSupportDir.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
        load()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Polling

    func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard let types = pb.types else { return }
        if Self.concealedTypes.contains(where: types.contains) { return }

        // Images take priority over text (a copied image cell in Excel has both).
        if let imageType = Self.imageTypes.first(where: { types.contains($0) }),
           let data = pb.data(forType: imageType) {
            addImage(data)
            return
        }

        if let text = pb.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addText(text)
        }
    }

    // MARK: - Add helpers

    private func addText(_ text: String) {
        if let idx = items.firstIndex(where: { $0.text == text }) {
            var item = items.remove(at: idx)
            item.date = .now
            items.insert(item, at: 0)
        } else {
            items.insert(ClipItem(text: text), at: 0)
            trimIfNeeded()
        }
        save()
    }

    private func addImage(_ data: Data) {
        guard data.count <= maxImageBytes else { return }

        // Normalise to PNG so we store one format and can dedup by hash.
        guard let nsImage = NSImage(data: data),
              let tiff = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return }

        let hash = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()

        if let idx = items.firstIndex(where: { $0.imageHash == hash }) {
            var item = items.remove(at: idx)
            item.date = .now
            items.insert(item, at: 0)
            save()
            return
        }

        let filename = UUID().uuidString + ".png"
        let fileURL = imagesDir.appendingPathComponent(filename)
        guard (try? png.write(to: fileURL)) != nil else { return }

        items.insert(ClipItem(imageFilename: filename, hash: hash), at: 0)
        trimIfNeeded()
        save()
    }

    private func trimIfNeeded() {
        while items.count > maxItems {
            if let victim = items.lastIndex(where: { !$0.pinned }) {
                deleteImageFile(for: items[victim])
                items.remove(at: victim)
            } else {
                deleteImageFile(for: items.last!)
                items.removeLast()
            }
        }
    }

    // MARK: - Actions

    func copyToPasteboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        if let filename = item.imageFilename,
           let data = try? Data(contentsOf: imagesDir.appendingPathComponent(filename)) {
            pb.setData(data, forType: NSPasteboard.PasteboardType("public.png"))
        } else if let text = item.text {
            pb.setString(text, forType: .string)
        }
        lastChangeCount = pb.changeCount
        bumpToTop(item)
    }

    func togglePin(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].pinned.toggle()
        save()
    }

    func delete(_ item: ClipItem) {
        deleteImageFile(for: item)
        items.removeAll { $0.id == item.id }
        save()
    }

    func clearUnpinned() {
        items.filter { !$0.pinned }.forEach { deleteImageFile(for: $0) }
        items.removeAll { !$0.pinned }
        save()
    }

    // MARK: - Helpers

    private func bumpToTop(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var updated = items.remove(at: idx)
        updated.date = .now
        items.insert(updated, at: 0)
        save()
    }

    private func deleteImageFile(for item: ClipItem) {
        guard let filename = item.imageFilename else { return }
        try? FileManager.default.removeItem(at: imagesDir.appendingPathComponent(filename))
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
