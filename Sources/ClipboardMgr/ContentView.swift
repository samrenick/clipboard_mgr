import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var store: ClipboardStore
    var isFloating = false
    var onClose: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var copiedID: ClipItem.ID?
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @FocusState private var searchFocused: Bool

    private var filtered: [ClipItem] {
        let base = query.isEmpty
            ? store.items
            : store.items.filter { $0.text.localizedCaseInsensitiveContains(query) }
        // Pinned entries float to the top, otherwise newest first.
        return base.sorted { ($0.pinned ? 1 : 0, $0.date) > ($1.pinned ? 1 : 0, $1.date) }
    }

    var body: some View {
        let stack = VStack(spacing: 0) {
            searchBar
            Divider()
            if filtered.isEmpty {
                emptyState
            } else {
                list
            }
            Divider()
            footer
        }
        .onExitCommand { close() }

        if isFloating {
            stack
                .frame(width: 420, height: 500)
                .background(VisualEffectBackground())
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
        } else {
            stack.frame(width: 380, height: 480)
        }
    }

    private func close() {
        dismiss()   // closes the MenuBarExtra popover
        onClose()   // closes the floating panel
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter clipboard history…", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onSubmit {
                    if let first = filtered.first { copy(first) }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .onAppear {
            // Slight delay so the window is key before we request focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                searchFocused = true
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filtered) { item in
                    ClipRow(
                        item: item,
                        justCopied: copiedID == item.id,
                        onCopy: { copy(item) },
                        onPin: { store.togglePin(item) },
                        onDelete: { store.delete(item) }
                    )
                }
            }
            .padding(6)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(query.isEmpty ? "Nothing copied yet" : "No matches for “\(query)”")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("\(store.items.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if !accessibilityGranted {
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                } label: {
                    Label("Enable auto-paste", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .help("Accessibility permission needed to paste automatically — click to open System Settings")
                .onAppear { accessibilityGranted = AXIsProcessTrusted() }
            }
            Button("Clear") { store.clearUnpinned() }
                .help("Remove all unpinned items")
            Button("Quit") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
        .padding(8)
    }

    private func copy(_ item: ClipItem) {
        store.copyToPasteboard(item)
        copiedID = item.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            copiedID = nil
            query = ""
            close()
            if isFloating {
                PasteHelper.paste(into: FloatingPanelController.shared.previousApp)
            }
        }
    }
}

/// AppKit blur backing for the borderless floating panel (the panel window
/// itself is transparent).
private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct ClipRow: View {
    let item: ClipItem
    let justCopied: Bool
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    private var preview: String {
        let firstLines = item.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .prefix(2)
            .joined(separator: " ⏎ ")
        return String(firstLines.prefix(200))
    }

    var body: some View {
        Button(action: onCopy) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(preview)
                        .lineLimit(2)
                        .font(.system(.body, design: item.text.contains("\n") ? .monospaced : .default))
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        if item.pinned {
                            Image(systemName: "pin.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        Text(item.date, format: .relative(presentation: .named))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if item.text.count > 200 {
                            Text("\(item.text.count) chars")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
                if justCopied {
                    Label("Copied", systemImage: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .labelStyle(.titleAndIcon)
                } else if hovering {
                    HStack(spacing: 2) {
                        Button(action: onPin) {
                            Image(systemName: item.pinned ? "pin.slash" : "pin")
                        }
                        .help(item.pinned ? "Unpin" : "Pin")
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                        }
                        .help("Delete")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Color.primary.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Copy", action: onCopy)
            Button(item.pinned ? "Unpin" : "Pin", action: onPin)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}
