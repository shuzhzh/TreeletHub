import AppKit
import Combine
import Foundation

/// 剪贴板历史：纯文本 + 在 Finder 等处的「复制文件」，文本与归档文件均持久化（最多 10 条）。
@MainActor
final class HubIslandClipboardHistory: ObservableObject {
    struct ArchivedClipboardFile: Identifiable, Equatable {
        let id: UUID
        let displayName: String
        /// 沙盒内副本绝对路径（位于 Application Support/TreeletHub/ClipboardArchive/…）。
        let storedURL: URL
    }

    enum Payload: Equatable {
        case text(String)
        case files([ArchivedClipboardFile])
    }

    struct Entry: Identifiable, Equatable {
        let id: UUID
        let capturedAt: Date
        let payload: Payload

        /// 收起态摘要、「剪贴 …」用。
        var collapsedPreview: String {
            switch payload {
            case .text(let text):
                let collapsed = text.replacingOccurrences(of: "\n", with: " ")
                if collapsed.count > 34 {
                    return String(collapsed.prefix(33)) + "…"
                }
                return collapsed
            case .files(let files):
                guard !files.isEmpty else { return HubMacL10n.string("mac.clipboard.files_fallback") }
                if files.count == 1 {
                    let n = files[0].displayName
                    return n.count > 34 ? String(n.prefix(33)) + "…" : n
                }
                let joined = files.map(\.displayName).joined(separator: "、")
                let fmt = HubMacL10n.string("mac.clipboard.multi_files_head")
                let head = String(format: fmt, locale: HubMacL10n.displayLocale, files.count, joined)
                return head.count > 34 ? String(head.prefix(33)) + "…" : head
            }
        }

        var listPreviewLines: String {
            switch payload {
            case .text(let text):
                let collapsed = text.replacingOccurrences(of: "\n", with: " ")
                if collapsed.count > 180 {
                    return String(collapsed.prefix(180)) + "…"
                }
                return collapsed
            case .files(let files):
                return files.map(\.displayName).joined(separator: "\n")
            }
        }
    }

    private struct PersistedStore: Codable {
        var version: Int
        var entries: [PersistedEntry]
    }

    private struct PersistedEntry: Codable {
        enum Kind: String, Codable {
            case text
            case files
        }

        let kind: Kind
        let id: UUID
        let capturedAt: Date
        let text: String?
        let fileRefs: [PersistedFileRef]?
    }

    private struct PersistedFileRef: Codable {
        /// 相对于 `TreeletHub` 目录，例如 `ClipboardArchive/<uuid>/name.pdf`
        let relativePath: String
        let displayName: String
    }

    /// 旧版仅文本 JSON：`[{ id, text, capturedAt }]`
    private struct LegacyPersistedEntry: Codable {
        let id: UUID
        let text: String
        let capturedAt: Date
    }

    private let storeVersion = 2
    private let maxEntries = 10
    private let pollInterval: TimeInterval = 0.75
    private let clipboardArchiveFolder = "ClipboardArchive"

    @Published private(set) var entries: [Entry] = []

    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private var ignoreNextChange = false

    init() {
        loadPersistedEntries()
    }

    func start() {
        guard !started else { return }
        started = true
        lastChangeCount = NSPasteboard.general.changeCount
        seedFromCurrentPasteboard()

        Timer.publish(every: pollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.pollPasteboard()
            }
            .store(in: &cancellables)
    }

    func stop() {
        started = false
        cancellables.removeAll()
    }

    func copyTextToPasteboard(_ text: String) {
        ignoreNextChange = true
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChangeCount = pb.changeCount
    }

    /// 将本条归档的文件重新写回系统剪贴板（供用户在其它 App 粘贴）。
    func restoreFilesToPasteboard(entryID: UUID) {
        guard let entry = entries.first(where: { $0.id == entryID }),
              case .files(let files) = entry.payload,
              !files.isEmpty
        else {
            return
        }
        ignoreNextChange = true
        let pb = NSPasteboard.general
        pb.clearContents()
        let writings = files.map { $0.storedURL as NSURL }
        pb.writeObjects(writings)
        lastChangeCount = pb.changeCount
    }

    /// 删除单条历史（移除磁盘归档目录并写回 JSON）。
    func removeEntry(id: UUID) {
        if let entry = entries.first(where: { $0.id == id }) {
            deleteArchiveOnDisk(for: entry)
        }
        entries.removeAll { $0.id == id }
        persistEntries()
    }

    private func seedFromCurrentPasteboard() {
        let pb = NSPasteboard.general
        let fileURLs = readFileURLs(from: pb)
        if !fileURLs.isEmpty {
            insertCapturedFiles(sourceURLs: fileURLs)
            return
        }
        if let s = pb.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !s.isEmpty
        {
            insertCapturedText(s)
        }
    }

    private func pollPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }

        let fileURLs = readFileURLs(from: pb)
        if !fileURLs.isEmpty {
            insertCapturedFiles(sourceURLs: fileURLs)
            return
        }

        guard let raw = pb.string(forType: .string) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        insertCapturedText(raw)
    }

    private func readFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        guard let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) else {
            return []
        }
        return objects.compactMap { $0 as? URL }.filter(\.isFileURL)
    }

    private func insertCapturedText(_ text: String) {
        entries.removeAll {
            if case .text(let t) = $0.payload { return t == text }
            return false
        }
        entries.insert(Entry(id: UUID(), capturedAt: Date(), payload: .text(text)), at: 0)
        trimEntriesAndCleanupArchives()
        persistEntries()
    }

    private func insertCapturedFiles(sourceURLs: [URL]) {
        let entryId = UUID()
        let fm = FileManager.default
        guard let treeletRoot = try? treeletHubDirectoryURL() else { return }
        let archiveRoot = treeletRoot.appendingPathComponent(clipboardArchiveFolder, isDirectory: true)
        try? fm.createDirectory(at: archiveRoot, withIntermediateDirectories: true)

        let entryDir = archiveRoot.appendingPathComponent(entryId.uuidString, isDirectory: true)
        try? fm.removeItem(at: entryDir)
        do {
            try fm.createDirectory(at: entryDir, withIntermediateDirectories: true)
        } catch {
            return
        }

        var archived: [ArchivedClipboardFile] = []
        for src in sourceURLs {
            let accessing = src.startAccessingSecurityScopedResource()
            defer {
                if accessing { src.stopAccessingSecurityScopedResource() }
            }
            do {
                let dest = uniqueDestination(in: entryDir, baseName: src.lastPathComponent)
                try fm.copyItem(at: src, to: dest)
                archived.append(
                    ArchivedClipboardFile(id: UUID(), displayName: src.lastPathComponent, storedURL: dest)
                )
            } catch {
                continue
            }
        }

        if archived.isEmpty {
            try? fm.removeItem(at: entryDir)
            return
        }

        entries.insert(Entry(id: entryId, capturedAt: Date(), payload: .files(archived)), at: 0)
        trimEntriesAndCleanupArchives()
        persistEntries()
    }

    private func uniqueDestination(in directory: URL, baseName: String) -> URL {
        let fm = FileManager.default
        var candidate = directory.appendingPathComponent(baseName)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let stem = (baseName as NSString).deletingPathExtension
        let ext = (baseName as NSString).pathExtension
        let suffix = UUID().uuidString.prefix(7)
        let name: String
        if ext.isEmpty {
            name = "\(stem)-\(suffix)"
        } else {
            name = "\(stem)-\(suffix).\(ext)"
        }
        candidate = directory.appendingPathComponent(String(name))
        return candidate
    }

    private func trimEntriesAndCleanupArchives() {
        guard entries.count > maxEntries else { return }
        let dropped = Array(entries[maxEntries...])
        entries = Array(entries.prefix(maxEntries))
        for e in dropped {
            deleteArchiveOnDisk(for: e)
        }
    }

    private func deleteArchiveOnDisk(for entry: Entry) {
        guard case .files(let files) = entry.payload, let first = files.first else { return }
        let folder = first.storedURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: folder)
    }

    private func treeletHubDirectoryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("TreeletHub", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func historyJSONURL() throws -> URL {
        try treeletHubDirectoryURL().appendingPathComponent("clipboard-history.json")
    }

    private func relativePath(treeletHub: URL, fileURL: URL) -> String {
        let root = treeletHub.standardizedFileURL.path
        let fp = fileURL.standardizedFileURL.path
        guard fp.hasPrefix(root) else {
            return (fileURL.lastPathComponent as NSString).lastPathComponent
        }
        var rel = String(fp.dropFirst(root.count))
        if rel.hasPrefix("/") { rel.removeFirst() }
        return rel
    }

    private func loadPersistedEntries() {
        do {
            let url = try historyJSONURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)

            if let store = try? JSONDecoder().decode(PersistedStore.self, from: data), store.version >= 2 {
                let tree = try treeletHubDirectoryURL()
                entries = store.entries.compactMap { pe -> Entry? in
                    switch pe.kind {
                    case .text:
                        guard let t = pe.text else { return nil }
                        return Entry(id: pe.id, capturedAt: pe.capturedAt, payload: .text(t))
                    case .files:
                        guard let refs = pe.fileRefs else { return nil }
                        var files: [ArchivedClipboardFile] = []
                        for ref in refs {
                            let abs = tree.appendingPathComponent(ref.relativePath)
                            guard FileManager.default.fileExists(atPath: abs.path) else { continue }
                            files.append(
                                ArchivedClipboardFile(id: UUID(), displayName: ref.displayName, storedURL: abs)
                            )
                        }
                        guard !files.isEmpty else { return nil }
                        return Entry(id: pe.id, capturedAt: pe.capturedAt, payload: .files(files))
                    }
                }
                .sorted { $0.capturedAt > $1.capturedAt }

                if entries.count > maxEntries {
                    trimEntriesAndCleanupArchives()
                    persistEntries()
                }
                return
            }

            let legacy = try JSONDecoder().decode([LegacyPersistedEntry].self, from: data)
            entries = legacy.map { Entry(id: $0.id, capturedAt: $0.capturedAt, payload: .text($0.text)) }
                .sorted { $0.capturedAt > $1.capturedAt }
            if entries.count > maxEntries {
                entries = Array(entries.prefix(maxEntries))
            }
            persistEntries()
        } catch {
            entries = []
        }
    }

    private func persistEntries() {
        do {
            let tree = try treeletHubDirectoryURL()
            let payload = entries.map { entry -> PersistedEntry in
                switch entry.payload {
                case .text(let t):
                    return PersistedEntry(kind: .text, id: entry.id, capturedAt: entry.capturedAt, text: t, fileRefs: nil)
                case .files(let files):
                    let refs: [PersistedFileRef] = files.map { f in
                        PersistedFileRef(
                            relativePath: relativePath(treeletHub: tree, fileURL: f.storedURL),
                            displayName: f.displayName
                        )
                    }
                    return PersistedEntry(kind: .files, id: entry.id, capturedAt: entry.capturedAt, text: nil, fileRefs: refs)
                }
            }
            let store = PersistedStore(version: storeVersion, entries: payload)
            let data = try JSONEncoder().encode(store)
            try data.write(to: historyJSONURL(), options: [.atomic])
        } catch {
            // 静默
        }
    }
}
