import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 真机读不到 LaunchServices 图标时，用系统符号作为内置 App 的可读回退。
enum HubIOSAppSymbol {
    static func systemImage(for bundleIdentifier: String?) -> String? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return nil }
        return symbols[bundleIdentifier]
    }

    private static let symbols: [String: String] = [
        "com.apple.mobilephone": "phone.fill",
        "com.apple.MobileSMS": "message.fill",
        "com.apple.mobilesafari": "safari.fill",
        "com.apple.camera": "camera.fill",
        "com.apple.mobileslideshow": "photo.fill",
        "com.apple.mobilemail": "envelope.fill",
        "com.apple.Maps": "map.fill",
        "com.apple.Music": "music.note",
        "com.apple.mobilecal": "calendar",
        "com.apple.mobilenotes": "note.text",
        "com.apple.Preferences": "gearshape.fill",
        "com.apple.AppStore": "bag.fill",
        "com.apple.weather": "cloud.sun.fill",
        "com.apple.mobiletimer": "clock.fill",
        "com.apple.facetime": "video.fill",
        "com.apple.DocumentsApp": "folder.fill",
        "com.apple.Passbook": "wallet.pass.fill",
        "com.apple.MobileAddressBook": "person.crop.circle.fill",
        "com.apple.Health": "heart.fill",
        "com.apple.shortcuts": "square.stack.3d.up.fill",
        "com.apple.reminders": "checklist",
        "com.apple.news": "newspaper.fill",
        "com.apple.Fitness": "figure.run",
        "com.apple.Bridge": "applewatch",
        "com.apple.Home": "house.fill",
        "com.apple.Translate": "character.bubble.fill",
        "com.apple.measure": "ruler.fill",
        "com.apple.calculator": "plus.forwardslash.minus",
        "com.apple.compass": "location.north.circle.fill",
        "com.apple.VoiceMemos": "waveform",
        "com.apple.tips": "lightbulb.fill",
        "com.apple.tv": "appletv.fill",
        "com.apple.podcasts": "mic.fill",
        "com.apple.iBooks": "book.fill",
        "com.apple.FindMy": "location.circle.fill",
        "com.apple.freeform": "pencil.and.ruler.fill",
        "com.apple.Journal": "book.pages.fill",
        "com.apple.Passwords": "key.fill",
    ]

    #if os(iOS)
    /// App Store 查不到官方图时（系统 App），用符号画一枚可读图标。
    static func fallbackIcon(for bundleIdentifier: String, side: CGFloat = 128) -> UIImage? {
        guard let name = systemImage(for: bundleIdentifier) else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { _ in
            UIColor.secondarySystemFill.setFill()
            UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side), cornerRadius: side * 0.225).fill()
            let config = UIImage.SymbolConfiguration(pointSize: side * 0.42, weight: .semibold)
            guard let symbol = UIImage(systemName: name, withConfiguration: config)?
                .withTintColor(.label, renderingMode: .alwaysOriginal)
            else { return }
            let size = symbol.size
            let rect = CGRect(
                x: (side - size.width) / 2,
                y: (side - size.height) / 2,
                width: size.width,
                height: size.height
            )
            symbol.draw(in: rect)
        }
    }
    #endif
}
