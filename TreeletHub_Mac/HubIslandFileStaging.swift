import AppKit
import Foundation

/// 灵动岛「文件暂存」：复制到应用容器内，便于拖拽导出、隔空投送且在沙盒内可读写。
struct HubIslandStagedItem: Identifiable, Equatable {
    let id: UUID
    /// 位于 Application Support/TreeletHub/Staging 下的副本。
    let storedURL: URL
    let displayName: String
}

enum HubIslandFileStaging {
    private static let folderComponent = "TreeletHub/Staging"

    static func stagingDirectoryURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent(folderComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 将用户拖入的文件复制进暂存目录（对来源 URL 尝试 security scope）。
    static func copyIntoStaging(from sourceURL: URL) throws -> HubIslandStagedItem {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scoped { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let fm = FileManager.default
        let staging = try stagingDirectoryURL()
        let baseName = sourceURL.lastPathComponent
        let destURL = uniqueDestination(in: staging, baseName: baseName)

        try fm.copyItem(at: sourceURL, to: destURL)
        return HubIslandStagedItem(id: UUID(), storedURL: destURL, displayName: baseName)
    }

    private static func uniqueDestination(in staging: URL, baseName: String) -> URL {
        let fm = FileManager.default
        var candidate = staging.appendingPathComponent(baseName)
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
        candidate = staging.appendingPathComponent(String(name))
        return candidate
    }

    static func removeFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

@MainActor
enum HubIslandStagingUIActions {
    static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    static func revealInFinder(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    /// 通过「存储为」复制到用户所选路径（默认打开「下载」文件夹）。
    static func presentExportCopy(stagedURL: URL, suggestedName: String) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            panel.directoryURL = downloads
        }
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: stagedURL, to: dest)
            } catch {
                // 静默失败；用户可改用拖拽导出。
            }
        }
    }
}
