import SwiftUI
import UIKit

/// 仅当 PNG 数据能形成有效位图时才显示，避免触发 CGImageDestination / 空白渲染问题。
enum SlotIconHelper {
    static func validatedImage(data: Data?) -> UIImage? {
        guard let data, data.count >= 32 else { return nil }
        guard let img = UIImage(data: data), img.cgImage != nil else { return nil }
        return img
    }
}

struct SlotAppIconView: View {
    let iconPNG: Data?
    let isEmptySlot: Bool
    var iconSide: CGFloat = 64

    private var corner: CGFloat { max(10, iconSide * 0.22) }

    var body: some View {
        Group {
            if isEmptySlot {
                Image(systemName: "square.dashed")
                    .font(.system(size: iconSide * 0.4))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            } else if let ui = SlotIconHelper.validatedImage(data: iconPNG) {
                Image(uiImage: ui)
                    .renderingMode(.original)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSide, height: iconSide)
                    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            } else {
                Image(systemName: "app.fill")
                    .font(.system(size: iconSide * 0.45))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: iconSide, height: iconSide)
    }
}
