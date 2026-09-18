import SwiftUI

#if os(macOS)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// 跨端共用的 Watch App View 风格蜂巢画布：平移、捏合缩放、鱼眼大小、缩放持久化。
/// 可选编辑态：长按进入，支持拖拽换位；Mac 还可显示「-」删除角标。
/// 不自动把全部图标塞进一屏（那是变丑的主因）；默认以中心簇展示，拖动浏览其余。
public struct HubHoneycombLauncherCanvas<Item: Identifiable, Icon: View>: View {
    public let items: [Item]
    public let emptyHint: String
    public let persistenceKey: String
    public let reduceMotion: Bool
    public let baseIconSide: CGFloat
    public let animatingItemId: Item.ID?
    public let allowsEditing: Bool
    public let allowsDelete: Bool
    public let isEditableItem: (Item) -> Bool
    public let editDoneLabel: String
    public let icon: (Item, CGFloat) -> Icon
    public let onSelect: (Item) -> Void
    public let onSecondarySelect: ((Item) -> Void)?
    public let onDelete: ((Item) -> Void)?
    public let onReorder: ((Item, Item) -> Void)?
    public let itemAccessibilityLabel: (Item) -> String

    @AppStorage private var storedScale: Double
    @AppStorage private var storedOffsetX: Double
    @AppStorage private var storedOffsetY: Double
    @AppStorage private var hasStoredViewport: Bool
    @AppStorage private var storedLayoutRevision: Int

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var viewportSize: CGSize = .zero
    @State private var isPanning = false
    @State private var lastTapAt: Date?
    @State private var didLoadPersistence = false

    @State private var isEditing = false
    @State private var jiggleOn = false
    @State private var longPressWorkItem: DispatchWorkItem?
    @State private var pressCandidate: Item?
    @State private var draggingItem: Item?
    @State private var dragFinger: CGPoint = .zero
    @State private var dropTarget: Item?
    @State private var gestureKind: GestureKind = .undecided

    private let minScale: CGFloat = HubHoneycombLayout.defaultMinScale
    private let maxScale: CGFloat = HubHoneycombLayout.defaultMaxScale
    private let longPressDuration: TimeInterval = 0.48
    private let moveThreshold: CGFloat = 6

    private enum GestureKind {
        case undecided
        case pan
        case iconDrag
    }

    public init(
        items: [Item],
        emptyHint: String,
        persistenceKey: String,
        reduceMotion: Bool = false,
        baseIconSide: CGFloat = HubHoneycombLayout.defaultBaseIconSide,
        animatingItemId: Item.ID? = nil,
        allowsEditing: Bool = false,
        allowsDelete: Bool = false,
        isEditableItem: @escaping (Item) -> Bool = { _ in true },
        editDoneLabel: String = "Done",
        @ViewBuilder icon: @escaping (Item, CGFloat) -> Icon,
        onSelect: @escaping (Item) -> Void,
        onSecondarySelect: ((Item) -> Void)? = nil,
        onDelete: ((Item) -> Void)? = nil,
        onReorder: ((Item, Item) -> Void)? = nil,
        itemAccessibilityLabel: @escaping (Item) -> String
    ) {
        self.items = items
        self.emptyHint = emptyHint
        self.persistenceKey = persistenceKey
        self.reduceMotion = reduceMotion
        self.baseIconSide = baseIconSide
        self.animatingItemId = animatingItemId
        self.allowsEditing = allowsEditing
        self.allowsDelete = allowsDelete
        self.isEditableItem = isEditableItem
        self.editDoneLabel = editDoneLabel
        self.icon = icon
        self.onSelect = onSelect
        self.onSecondarySelect = onSecondarySelect
        self.onDelete = onDelete
        self.onReorder = onReorder
        self.itemAccessibilityLabel = itemAccessibilityLabel
        _storedScale = AppStorage(wrappedValue: 1.0, "\(persistenceKey).scale")
        _storedOffsetX = AppStorage(wrappedValue: 0.0, "\(persistenceKey).ox")
        _storedOffsetY = AppStorage(wrappedValue: 0.0, "\(persistenceKey).oy")
        _hasStoredViewport = AppStorage(wrappedValue: false, "\(persistenceKey).ready")
        _storedLayoutRevision = AppStorage(wrappedValue: 0, "\(persistenceKey).layoutRev")
    }

    private var hexSpacing: CGFloat {
        HubHoneycombLayout.spacing(forBaseIconSide: baseIconSide)
    }

    private var positions: [CGPoint] {
        HubHoneycombLayout.spiralPositions(count: max(items.count, 1), spacing: hexSpacing)
    }

    public var body: some View {
        GeometryReader { geo in
            let size = CGSize(
                width: geo.size.width.isFinite ? max(0, geo.size.width) : 0,
                height: geo.size.height.isFinite ? max(0, geo.size.height) : 0
            )
            ZStack {
                if items.isEmpty {
                    Text(emptyHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .allowsHitTesting(false)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let pos = positions[index]
                        let isDragSource = draggingItem?.id == item.id
                        let focus = HubHoneycombLayout.focusScale(
                            worldPosition: pos,
                            scale: scale,
                            offset: offset,
                            viewport: size,
                            spacing: hexSpacing
                        )
                        let side = max(22, baseIconSide * scale * focus)
                        let blurRadius = isDragSource
                            ? 0
                            : HubHoneycombLayout.focusBlurRadius(focus: focus, baseIconSide: baseIconSide * scale)
                        let isAnimating = animatingItemId == item.id
                        let isDropHighlight = dropTarget?.id == item.id && !isDragSource
                        let screenCenter = CGPoint(
                            x: size.width * 0.5 + pos.x * scale + offset.width,
                            y: size.height * 0.5 + pos.y * scale + offset.height
                        )
                        let drawCenter = isDragSource ? dragFinger : screenCenter

                        ZStack(alignment: .topLeading) {
                            icon(item, side)
                                .frame(width: side, height: side)
                                .scaleEffect(isAnimating ? 1.12 : (isDropHighlight ? 1.08 : 1))
                                .blur(radius: blurRadius)
                                .opacity(Double(isDragSource ? 0.92 : (0.28 + 0.72 * focus)))
                                .rotationEffect(jiggleRotation(for: item))
                                .shadow(
                                    color: .black.opacity(isDragSource ? 0.35 : (0.18 * Double(focus))),
                                    radius: isDragSource ? 10 : max(2, side * 0.08 * focus),
                                    y: isDragSource ? 4 : max(1, side * 0.04 * focus)
                                )

                            if isEditing, allowsDelete, isEditableItem(item) {
                                deleteBadge(side: side)
                                    .offset(x: -side * 0.06, y: -side * 0.06)
                            }
                        }
                        .frame(width: side, height: side)
                        .position(x: drawCenter.x, y: drawCenter.y)
                        .zIndex(isDragSource ? 1000 : (isDropHighlight ? 10 : Double(focus * 10)))
                        .allowsHitTesting(false)
                        .accessibilityElement()
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(Text(itemAccessibilityLabel(item)))
                        .accessibilityAction {
                            if isEditing, allowsDelete, isEditableItem(item) {
                                onDelete?(item)
                            } else if !isEditing {
                                onSelect(item)
                            }
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(panOrTapGesture(viewport: size))
            #if !os(watchOS)
            .simultaneousGesture(magnifyGesture)
            #endif
            #if os(macOS)
            .background(
                ScrollZoomMonitor { deltaY in
                    applyScrollZoom(deltaY: deltaY)
                }
            )
            #endif
            #if os(watchOS)
            .focusable(true)
            .digitalCrownRotation(
                Binding(
                    get: { scale },
                    set: { newValue in
                        scale = newValue
                        committedScale = newValue
                        persistViewport()
                    }
                ),
                from: minScale,
                through: maxScale,
                sensitivity: .medium,
                isContinuous: true,
                isHapticFeedbackEnabled: true
            )
            #endif
            .clipped()
            .overlay(alignment: .top) {
                if isEditing {
                    editToolbar
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.22), value: isEditing)
            .onAppear {
                viewportSize = size
                loadOrInitializeViewport(size: size)
            }
            .onChange(of: size) { _, newSize in
                viewportSize = newSize
                if !didLoadPersistence {
                    loadOrInitializeViewport(size: newSize)
                }
            }
            .onChange(of: items.count) { _, count in
                if count == 0, isEditing {
                    exitEditing()
                }
            }
            .onDisappear {
                cancelLongPress()
                persistViewport()
            }
            #if os(macOS)
            .background(EditModeKeyMonitor(isEditing: isEditing, onEscape: exitEditing))
            #endif
        }
    }

    private var editToolbar: some View {
        Button(action: exitEditing) {
            Text(editDoneLabel)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(editDoneLabel))
    }

    private func deleteBadge(side: CGFloat) -> some View {
        let badge = max(16, side * 0.28)
        return ZStack {
            Circle()
                .fill(Color.red)
            Image(systemName: "minus")
                .font(.system(size: badge * 0.55, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: badge, height: badge)
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .accessibilityHidden(true)
    }

    private func jiggleRotation(for item: Item) -> Angle {
        guard isEditing, !reduceMotion, isEditableItem(item), draggingItem?.id != item.id else {
            return .degrees(0)
        }
        return .degrees(jiggleOn ? 1.8 : -1.8)
    }

    #if !os(watchOS)
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let next = committedScale * value.magnification
                scale = min(maxScale, max(minScale, next))
            }
            .onEnded { _ in
                committedScale = scale
                softClampOffset(viewport: viewportSize)
                committedOffset = offset
                persistViewport()
            }
    }
    #endif

    #if os(macOS)
    /// 鼠标滚轮 / 触控板滚动 → 缩放（捏合仍走 MagnifyGesture）。
    private func applyScrollZoom(deltaY: CGFloat) {
        guard abs(deltaY) > 0.01 else { return }
        // 向上滚放大，向下滚缩小。
        let next = min(maxScale, max(minScale, scale * exp(deltaY * 0.008)))
        scale = next
        committedScale = next
        softClampOffset(viewport: viewportSize)
        committedOffset = offset
        persistViewport()
    }
    #endif

    private func panOrTapGesture(viewport: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleDragChanged(value, viewport: viewport)
            }
            .onEnded { value in
                handleDragEnded(value, viewport: viewport)
            }
    }

    private func handleDragChanged(_ value: DragGesture.Value, viewport: CGSize) {
        let distance = hypot(value.translation.width, value.translation.height)

        if gestureKind == .undecided {
            if pressCandidate == nil {
                pressCandidate = hitTest(at: value.startLocation, viewport: viewport)
                if allowsEditing,
                   let candidate = pressCandidate,
                   isEditableItem(candidate),
                   !isEditing {
                    scheduleLongPress(for: candidate, at: value.startLocation)
                }
            }

            if distance > moveThreshold {
                cancelLongPress()
                if isEditing,
                   let candidate = pressCandidate,
                   isEditableItem(candidate) {
                    gestureKind = .iconDrag
                    draggingItem = candidate
                    dragFinger = value.location
                    dropTarget = nil
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    #endif
                } else {
                    gestureKind = .pan
                    isPanning = true
                }
            }
        }

        switch gestureKind {
        case .pan:
            isPanning = true
            offset = CGSize(
                width: committedOffset.width + value.translation.width,
                height: committedOffset.height + value.translation.height
            )
        case .iconDrag:
            dragFinger = value.location
            if let hit = hitTest(at: value.location, viewport: viewport),
               hit.id != draggingItem?.id,
               isEditableItem(hit) {
                dropTarget = hit
            } else {
                dropTarget = nil
            }
        case .undecided:
            break
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, viewport: CGSize) {
        defer {
            cancelLongPress()
            pressCandidate = nil
            gestureKind = .undecided
            isPanning = false
            draggingItem = nil
            dropTarget = nil
        }

        let distance = hypot(value.translation.width, value.translation.height)

        if gestureKind == .iconDrag, let source = draggingItem {
            if let target = dropTarget ?? hitTest(at: value.location, viewport: viewport),
               target.id != source.id,
               isEditableItem(target) {
                onReorder?(source, target)
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
            }
            return
        }

        if gestureKind == .pan || isPanning || distance > moveThreshold {
            committedOffset = offset
            let predicted = value.predictedEndTranslation
            let velocity = CGSize(
                width: predicted.width - value.translation.width,
                height: predicted.height - value.translation.height
            )
            if !reduceMotion, hypot(velocity.width, velocity.height) > 12 {
                withAnimation(.interpolatingSpring(stiffness: 120, damping: 18)) {
                    offset = CGSize(
                        width: committedOffset.width + velocity.width * 0.28,
                        height: committedOffset.height + velocity.height * 0.28
                    )
                    softClampOffset(viewport: viewport)
                    committedOffset = offset
                }
                persistViewport()
            } else {
                softClampOffset(viewport: viewport)
                committedOffset = offset
                persistViewport()
            }
            return
        }

        // 轻点
        if isEditing {
            if allowsDelete,
               let item = hitTestDeleteBadge(at: value.startLocation, viewport: viewport) {
                onDelete?(item)
                return
            }
            if hitTest(at: value.startLocation, viewport: viewport) == nil {
                exitEditing()
            }
            return
        }

        if let item = hitTest(at: value.startLocation, viewport: viewport) {
            lastTapAt = nil
            #if os(macOS)
            if NSEvent.modifierFlags.contains(.control)
                || NSApp.currentEvent?.type == .rightMouseUp
                || NSApp.currentEvent?.type == .rightMouseDown {
                onSecondarySelect?(item)
                return
            }
            #endif
            onSelect(item)
            return
        }

        let now = Date()
        if let last = lastTapAt, now.timeIntervalSince(last) < 0.35 {
            lastTapAt = nil
            recenter(animated: !reduceMotion)
        } else {
            lastTapAt = now
        }
    }

    private func scheduleLongPress(for item: Item, at location: CGPoint) {
        cancelLongPress()
        let work = DispatchWorkItem {
            enterEditing(startingDrag: item, at: location)
        }
        longPressWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + longPressDuration, execute: work)
    }

    private func cancelLongPress() {
        longPressWorkItem?.cancel()
        longPressWorkItem = nil
    }

    private func enterEditing(startingDrag item: Item?, at location: CGPoint) {
        guard allowsEditing else { return }
        cancelLongPress()
        withAnimation(.snappy(duration: 0.2)) {
            isEditing = true
        }
        jiggleOn = false
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 0.12).repeatForever(autoreverses: true)) {
                jiggleOn = true
            }
        }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        #endif
        if let item, isEditableItem(item) {
            gestureKind = .iconDrag
            draggingItem = item
            dragFinger = location
            dropTarget = nil
        }
    }

    private func exitEditing() {
        cancelLongPress()
        withAnimation(.snappy(duration: 0.2)) {
            isEditing = false
            jiggleOn = false
            draggingItem = nil
            dropTarget = nil
            gestureKind = .undecided
        }
    }

    private func hitTest(at location: CGPoint, viewport: CGSize) -> Item? {
        guard !items.isEmpty else { return nil }
        var best: (item: Item, dist: CGFloat)?
        for (index, item) in items.enumerated() {
            let pos = positions[index]
            let focus = HubHoneycombLayout.focusScale(
                worldPosition: pos,
                scale: scale,
                offset: offset,
                viewport: viewport,
                spacing: hexSpacing
            )
            let side = max(22, baseIconSide * scale * focus)
            let center = CGPoint(
                x: viewport.width * 0.5 + pos.x * scale + offset.width,
                y: viewport.height * 0.5 + pos.y * scale + offset.height
            )
            let dist = hypot(location.x - center.x, location.y - center.y)
            if dist <= side * 0.58 {
                if best == nil || dist < best!.dist {
                    best = (item, dist)
                }
            }
        }
        return best?.item
    }

    /// 编辑态下命中图标左上角「-」删除角标。
    private func hitTestDeleteBadge(at location: CGPoint, viewport: CGSize) -> Item? {
        guard allowsDelete else { return nil }
        for (index, item) in items.enumerated() where isEditableItem(item) {
            let pos = positions[index]
            let focus = HubHoneycombLayout.focusScale(
                worldPosition: pos,
                scale: scale,
                offset: offset,
                viewport: viewport,
                spacing: hexSpacing
            )
            let side = max(22, baseIconSide * scale * focus)
            let center = CGPoint(
                x: viewport.width * 0.5 + pos.x * scale + offset.width,
                y: viewport.height * 0.5 + pos.y * scale + offset.height
            )
            let badge = max(16, side * 0.28)
            let badgeCenter = CGPoint(
                x: center.x - side * 0.5 - side * 0.06 + badge * 0.5,
                y: center.y - side * 0.5 - side * 0.06 + badge * 0.5
            )
            let dist = hypot(location.x - badgeCenter.x, location.y - badgeCenter.y)
            if dist <= badge * 0.75 {
                return item
            }
        }
        return nil
    }

    private func loadOrInitializeViewport(size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        let revisionMatches = storedLayoutRevision == HubHoneycombLayout.layoutRevision
        if hasStoredViewport, revisionMatches {
            scale = CGFloat(storedScale)
            committedScale = scale
            offset = CGSize(width: storedOffsetX, height: storedOffsetY)
            committedOffset = offset
            softClampOffset(viewport: size)
            committedOffset = offset
        } else {
            // Watch 默认：略放大中心簇，光学中心略偏上。
            scale = HubHoneycombLayout.defaultScale
            committedScale = HubHoneycombLayout.defaultScale
            offset = HubHoneycombLayout.defaultOffset(viewport: size)
            committedOffset = offset
            persistViewport()
        }
        didLoadPersistence = true
    }

    private func recenter(animated: Bool) {
        let apply = {
            scale = HubHoneycombLayout.defaultScale
            committedScale = HubHoneycombLayout.defaultScale
            offset = HubHoneycombLayout.defaultOffset(viewport: viewportSize)
            committedOffset = offset
            persistViewport()
        }
        if animated {
            withAnimation(.snappy(duration: 0.34)) { apply() }
        } else {
            apply()
        }
    }

    /// 软边界：可略微越界，但不把缩放重置。
    private func softClampOffset(viewport: CGSize) {
        guard viewport.width > 1, viewport.height > 1 else { return }
        let bounds = HubHoneycombLayout.contentBounds(positions: positions, pad: baseIconSide)
        let limitX = max(bounds.width * scale * 0.55, viewport.width * 0.35)
        let limitY = max(bounds.height * scale * 0.55, viewport.height * 0.35)
        offset = CGSize(
            width: min(limitX, max(-limitX, offset.width)),
            height: min(limitY, max(-limitY, offset.height))
        )
    }

    private func persistViewport() {
        storedScale = Double(scale)
        storedOffsetX = Double(offset.width)
        storedOffsetY = Double(offset.height)
        hasStoredViewport = true
        storedLayoutRevision = HubHoneycombLayout.layoutRevision
    }
}

#if os(macOS)
/// 编辑态下按 Esc 退出。
private struct EditModeKeyMonitor: NSViewRepresentable {
    let isEditing: Bool
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? KeyView else { return }
        view.onEscape = onEscape
        view.monitorEnabled = isEditing
        if isEditing {
            DispatchQueue.main.async {
                view.window?.makeFirstResponder(view)
            }
        }
    }

    final class KeyView: NSView {
        var onEscape: (() -> Void)?
        var monitorEnabled = false

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            if monitorEnabled, event.keyCode == 53 {
                onEscape?()
                return
            }
            super.keyDown(with: event)
        }
    }
}

/// 在蜂巢区域内拦截滚轮，映射为缩放（不抢占拖拽点击）。
private struct ScrollZoomMonitor: NSViewRepresentable {
    let onZoomDelta: (CGFloat) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ScrollZoomView()
        view.onZoomDelta = onZoomDelta
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? ScrollZoomView)?.onZoomDelta = onZoomDelta
    }

    final class ScrollZoomView: NSView {
        var onZoomDelta: ((CGFloat) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                installMonitor()
            } else {
                removeMonitor()
            }
        }

        deinit {
            removeMonitor()
        }

        private func installMonitor() {
            removeMonitor()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window == window else {
                    return event
                }
                let local = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(local) else { return event }

                let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY * 8
                let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.deltaX * 8
                // 横向滚动为主时不拦截，留给系统/其它手势。
                if abs(dx) > abs(dy) * 1.25 { return event }
                guard abs(dy) > 0.04 else { return event }

                self.onZoomDelta?(dy)
                return nil
            }
        }

        private func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
#endif
