import SwiftUI

/// iOS 入口：圆形图标蜂巢墙（Watch App View 风格）。
/// 电脑页：长按换位。手机页：与 Mac 一致，可添加 / 删除 / 编辑态点按替换。
struct HubWatchStyleLauncherView: View {
    let items: [HubLauncherItem]
    let emptyHint: String
    let reduceMotion: Bool
    let animatingItemId: String?
    let persistenceKey: String
    let editDoneLabel: String
    let allowsDelete: Bool
    let onSelect: (HubLauncherItem) -> Void
    let onDelete: (HubLauncherItem) -> Void
    let onReplace: (HubLauncherItem) -> Void
    let onReorder: (HubLauncherItem, HubLauncherItem) -> Void
    let onViewportChange: ((CGFloat, CGSize, CGFloat) -> Void)?
    let iconShape: HubLauncherIconShape

    init(
        items: [HubLauncherItem],
        emptyHint: String,
        reduceMotion: Bool,
        animatingItemId: String?,
        persistenceKey: String = "treelethub.launcher.ios",
        editDoneLabel: String = "Done",
        allowsDelete: Bool = false,
        onSelect: @escaping (HubLauncherItem) -> Void,
        onDelete: @escaping (HubLauncherItem) -> Void = { _ in },
        onReplace: @escaping (HubLauncherItem) -> Void = { _ in },
        onReorder: @escaping (HubLauncherItem, HubLauncherItem) -> Void = { _, _ in },
        onViewportChange: ((CGFloat, CGSize, CGFloat) -> Void)? = nil,
        iconShape: HubLauncherIconShape = .circle
    ) {
        self.items = items
        self.emptyHint = emptyHint
        self.reduceMotion = reduceMotion
        self.animatingItemId = animatingItemId
        self.persistenceKey = persistenceKey
        self.editDoneLabel = editDoneLabel
        self.allowsDelete = allowsDelete
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onReplace = onReplace
        self.onReorder = onReorder
        self.onViewportChange = onViewportChange
        self.iconShape = iconShape
    }

    var body: some View {
        HubHoneycombLauncherCanvas(
            items: items,
            emptyHint: emptyHint,
            persistenceKey: persistenceKey,
            reduceMotion: reduceMotion,
            animatingItemId: animatingItemId,
            allowsEditing: true,
            allowsDelete: allowsDelete,
            isEditableItem: { !$0.isAddAffordance && !$0.slot.isEmpty },
            editDoneLabel: editDoneLabel,
            icon: { item, side in
                HubHoneycombRoundIcon(item: item, side: side, shape: iconShape)
            },
            onSelect: onSelect,
            onDelete: { item in
                guard !item.isAddAffordance else { return }
                onDelete(item)
            },
            onReplace: { item in
                guard !item.isAddAffordance else { return }
                onReplace(item)
            },
            onReorder: onReorder,
            itemAccessibilityLabel: { item in
                if item.isAddAffordance {
                    return HubIOSL10n.string("ios.phone.empty_cta")
                }
                return item.slot.displayName
                    ?? item.slot.shortcutKind?.rawValue
                    ?? "App"
            },
            onViewportChange: onViewportChange
        )
        .overlay(alignment: .center) {
            if items.filter({ !$0.isAddAffordance }).isEmpty {
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
