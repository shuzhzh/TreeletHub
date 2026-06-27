import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// 九宫格格子拖放：从 `canDrag` 的格子拖出索引，拖到另一格则 `onSwap(from, to)`（交换两格应用）。
public struct HubGridSlotDragDropModifier: ViewModifier {
    let slotIndex: Int
    let canDrag: Bool
    let onSwap: (Int, Int) -> Void

    public init(slotIndex: Int, canDrag: Bool, onSwap: @escaping (Int, Int) -> Void) {
        self.slotIndex = slotIndex
        self.canDrag = canDrag
        self.onSwap = onSwap
    }

    public func body(content: Content) -> some View {
        let withDrop = content.onDrop(of: [.plainText], isTargeted: nil) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadDataRepresentation(for: .plainText) { data, _ in
                guard let data,
                      let s = String(data: data, encoding: .utf8) else { return }
                let from = Int(s.trimmingCharacters(in: .whitespacesAndNewlines))
                guard let from, from != slotIndex, (0..<9).contains(from) else { return }
                Task { @MainActor in
                    onSwap(from, slotIndex)
                }
            }
            return true
        }
        return Group {
            if canDrag {
                withDrop.onDrag {
                    let provider = NSItemProvider()
                    provider.registerDataRepresentation(for: .plainText, visibility: .all) { completion in
                        let data = String(slotIndex).data(using: .utf8)!
                        completion(data, nil)
                        return nil
                    }
                    return provider
                }
            } else {
                withDrop
            }
        }
    }
}

public extension View {
    func hubGridSlotDragDrop(slotIndex: Int, canDrag: Bool, onSwap: @escaping (Int, Int) -> Void) -> some View {
        modifier(HubGridSlotDragDropModifier(slotIndex: slotIndex, canDrag: canDrag, onSwap: onSwap))
    }
}
