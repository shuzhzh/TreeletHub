import Combine
import SwiftUI
import UIKit

/// 将用户从相册选择的单张背景图写入 Application Support，再次选择会覆盖同一文件。
@MainActor
final class HubCustomBackgroundStore: ObservableObject {
    @Published private(set) var image: UIImage?

    private let filename = "custom-background.jpg"
    private let maxPixelSide: CGFloat = 2048
    private let jpegQuality: CGFloat = 0.88

    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = base.appendingPathComponent("TreeletHub", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent(filename)
    }

    init() {
        reloadFromDisk()
    }

    func reloadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            image = nil
            return
        }
        guard let data = try? Data(contentsOf: fileURL), let ui = UIImage(data: data) else {
            image = nil
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        image = ui
    }

    /// 写入磁盘并更新内存中的图（覆盖旧文件）。
    func saveImageFromPicker(data: Data) {
        guard let ui = UIImage(data: data) else { return }
        let resized = resizeIfNeeded(ui, maxSide: maxPixelSide)
        guard let jpeg = resized.jpegData(compressionQuality: jpegQuality) else { return }
        do {
            try jpeg.write(to: fileURL, options: .atomic)
            image = UIImage(data: jpeg)
        } catch {
            image = nil
        }
    }

    func deleteCustomFile() {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        image = nil
    }

    private func resizeIfNeeded(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let longest = max(w, h)
        guard longest > maxSide, longest > 0 else { return image }
        let scale = maxSide / longest
        let newSize = CGSize(width: w * scale, height: h * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
