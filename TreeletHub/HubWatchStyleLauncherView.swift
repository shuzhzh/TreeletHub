import SwiftUI

/// iOS 入口：圆形图标蜂巢墙（Watch App View 风格）。
/// 支持长按进入编辑态后拖拽换位；不可添加/删除 App。
struct HubWatchStyleLauncherView: View {
    let items: [HubLauncherItem]
    let emptyHint: String
    let reduceMotion: Bool
    let animatingItemId: String?
    let persistenceKey: String
    let editDoneLabel: String
    let onSelect: (HubLauncherItem) -> Void
    let onReorder: (HubLauncherItem, HubLauncherItem) -> Void

    init(
        items: [HubLauncherItem],
        emptyHint: String,
        reduceMotion: Bool,
        animatingItemId: String?,
        persistenceKey: String = "treelethub.launcher.ios",
        editDoneLabel: String = "Done",
        onSelect: @escaping (HubLauncherItem) -> Void,
        onReorder: @escaping (HubLauncherItem, HubLauncherItem) -> Void = { _, _ in }
    ) {
        self.items = items
        self.emptyHint = emptyHint
        self.reduceMotion = reduceMotion
        self.animatingItemId = animatingItemId
        self.persistenceKey = persistenceKey
        self.editDoneLabel = editDoneLabel
        self.onSelect = onSelect
        self.onReorder = onReorder
    }

    var body: some View {
        HubHoneycombLauncherCanvas(
            items: items,
            emptyHint: emptyHint,
            persistenceKey: persistenceKey,
            reduceMotion: reduceMotion,
            animatingItemId: animatingItemId,
            allowsEditing: true,
            allowsDelete: false,
            isEditableItem: { !$0.isAddAffordance && !$0.slot.isEmpty },
            editDoneLabel: editDoneLabel,
            icon: { item, side in
                HubHoneycombRoundIcon(item: item, side: side)
            },
            onSelect: onSelect,
            onReorder: onReorder,
            itemAccessibilityLabel: { item in
                item.slot.displayName
                    ?? item.slot.shortcutKind?.rawValue
                    ?? "App"
            }
        )
        .overlay(alignment: .center) {
            if items.isEmpty {
                Image(systemName: "hexagon")
                    .font(.system(size: 40, weight: .ultraLight))
                    .foregroundStyle(.tertiary)
                    .offset(y: -52)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
