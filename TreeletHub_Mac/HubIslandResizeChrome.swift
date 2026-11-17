import AppKit
import SwiftUI

/// 灵动岛边缘拖拽热区：左右改宽度（水平居中故按 2× 位移），底边改高度。
/// 命中区只覆盖边缘本身，避免铺满胶囊后抢走收起、切页和点按应用。
struct HubIslandResizeHandleOverlay: View {
    let edges: [HubIslandResizeEdge]
    let isActive: Bool
    /// 收起态条很矮：加厚热区、缩小角落避让，避免左右命中高度被裁成 0。
    var compact: Bool = false
    var onHoverHandle: (Bool) -> Void
    var onResizeStart: (HubIslandResizeEdge) -> Void
    var onResizeChange: (HubIslandResizeEdge, CGSize) -> Void
    var onResizeEnd: () -> Void
    var onReset: (() -> Void)?

    @State private var hoveredEdge: HubIslandResizeEdge?
    @State private var draggingEdge: HubIslandResizeEdge?
    /// 用屏幕坐标记起点。窗口在拖拽中会重新居中，SwiftUI 的 translation 会因此跳变。
    @State private var dragOrigin: CGPoint?

    private var edgeThickness: CGFloat { compact ? 10 : 8 }
    private var cornerInset: CGFloat { compact ? 4 : 14 }

    var body: some View {
        ZStack {
            if edges.contains(.leading) {
                positionedEdge(.leading)
            }
            if edges.contains(.trailing) {
                positionedEdge(.trailing)
            }
            if edges.contains(.bottom) {
                positionedEdge(.bottom)
            }
            if edges.contains(.bottomTrailing) {
                cornerHandle
            }
        }
        .allowsHitTesting(true)
        .onChange(of: hoveredEdge) { _, edge in
            onHoverHandle(edge != nil || draggingEdge != nil)
            updateCursor(for: edge ?? draggingEdge)
        }
        .onChange(of: draggingEdge) { _, edge in
            onHoverHandle(edge != nil || hoveredEdge != nil)
            updateCursor(for: edge ?? hoveredEdge)
            if edge == nil {
                NSCursor.arrow.set()
            }
        }
    }

    @ViewBuilder
    private func positionedEdge(_ edge: HubIslandResizeEdge) -> some View {
        switch edge {
        case .leading:
            HStack(spacing: 0) {
                grabber(edge)
                    .frame(width: edgeThickness)
                    .padding(.vertical, cornerInset)
                Spacer(minLength: 0).allowsHitTesting(false)
            }
        case .trailing:
            HStack(spacing: 0) {
                Spacer(minLength: 0).allowsHitTesting(false)
                grabber(edge)
                    .frame(width: edgeThickness)
                    .padding(.vertical, cornerInset)
            }
        case .bottom:
            VStack(spacing: 0) {
                Spacer(minLength: 0).allowsHitTesting(false)
                grabber(edge)
                    .frame(height: edgeThickness)
                    .padding(.horizontal, cornerInset)
            }
        case .bottomTrailing:
            EmptyView()
        }
    }

    private func grabber(_ edge: HubIslandResizeEdge) -> some View {
        let isLit = hoveredEdge == edge || draggingEdge == edge
        return Rectangle()
            .fill(Color.white.opacity(isLit && isActive ? 0.22 : 0.001))
            .contentShape(Rectangle())
            .highPriorityGesture(dragGesture(for: edge))
            .onHover { hovering in
                if hovering {
                    hoveredEdge = edge
                } else if hoveredEdge == edge {
                    hoveredEdge = nil
                    finishDragIfMouseReleased()
                }
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { onReset?() }
            )
            .help(helpText(for: edge))
    }

    private var cornerHandle: some View {
        let edge = HubIslandResizeEdge.bottomTrailing
        let isLit = hoveredEdge == edge || draggingEdge == edge
        let side: CGFloat = compact ? 16 : 18
        return Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: compact ? 8 : 9, weight: .bold))
            .foregroundStyle(Color.white.opacity(isLit ? 0.85 : 0.35))
            .frame(width: side, height: side)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(isLit ? 0.2 : 0.08))
            )
            .contentShape(Rectangle())
            .highPriorityGesture(dragGesture(for: edge))
            .onHover { hovering in
                if hovering {
                    hoveredEdge = edge
                } else if hoveredEdge == edge {
                    hoveredEdge = nil
                    finishDragIfMouseReleased()
                }
            }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded { onReset?() }
            )
            .help(helpText(for: edge))
            .padding(.trailing, compact ? 2 : 6)
            .padding(.bottom, compact ? 2 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private func dragGesture(for edge: HubIslandResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { _ in
                let now = NSEvent.mouseLocation
                if draggingEdge != edge {
                    draggingEdge = edge
                    dragOrigin = now
                    onResizeStart(edge)
                }
                guard let dragOrigin else { return }
                onResizeChange(
                    edge,
                    CGSize(
                        width: now.x - dragOrigin.x,
                        height: dragOrigin.y - now.y
                    )
                )
            }
            .onEnded { _ in
                finishDrag()
            }
    }

    private func finishDragIfMouseReleased() {
        guard draggingEdge != nil, NSEvent.pressedMouseButtons & 1 == 0 else { return }
        finishDrag()
    }

    private func finishDrag() {
        let wasDragging = draggingEdge != nil
        draggingEdge = nil
        dragOrigin = nil
        if wasDragging {
            onResizeEnd()
        }
        updateCursor(for: hoveredEdge)
    }

    private func updateCursor(for edge: HubIslandResizeEdge?) {
        switch edge {
        case .leading, .trailing:
            NSCursor.resizeLeftRight.set()
        case .bottom:
            NSCursor.resizeUpDown.set()
        case .bottomTrailing:
            NSCursor.crosshair.set()
        case nil:
            NSCursor.arrow.set()
        }
    }

    private func helpText(for edge: HubIslandResizeEdge) -> String {
        switch edge {
        case .leading, .trailing:
            return HubMacL10n.string("mac.island.resize.width_help")
        case .bottom:
            return HubMacL10n.string("mac.island.resize.height_help")
        case .bottomTrailing:
            return HubMacL10n.string("mac.island.resize.corner_help")
        }
    }
}
