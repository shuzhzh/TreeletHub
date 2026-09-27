#if os(iOS)
import Contacts
import SwiftUI
import UIKit

/// 添加 / 替换手机蜂巢应用。
///
/// 图标网格选常用应用，搜索走 App Store，拿到 bundle id 后才能在 App 内和桌面小组件里直接打开。
struct HubIOSAppPickerView: View {
    struct Copy {
        var title: String
        var cancelTitle: String
        var doneTitle: String
        var addCountFormat: String
        var segmentCatalog: String
        var segmentAll: String
        var searchPlaceholder: String
        var catalogEmpty: String
        var catalogInstalledHeader: String
        var catalogStoreHeader: String
        var catalogFooter: String
        var storeSearching: String
        var suggestedHeader: String
        var alreadyAdded: String
        var searchHint: String
        var unlaunchableHint: String
        var contactCallsHeader: String
        var contactNoPhone: String
    }

    let copy: Copy
    var occupiedBundleIds: Set<String> = []
    /// 一次可回传多个应用；调用方按空位依次写入。
    let onPick: ([HubIOSFamilyAppPick]) -> Void
    let onCancel: () -> Void

    @State private var suggested: [HubIOSInstalledApps.Record] = []
    @State private var installed: [HubIOSInstalledApps.Record] = []
    @State private var didLoadInstalled = false
    @State private var query = ""
    @State private var storeResults: [HubIOSAppStoreArtwork.StoreApp] = []
    @State private var isSearchingStore = false
    /// 已勾选的目录条目（保持勾选顺序）。
    @State private var selectedCatalog: [CatalogEntry] = []
    @State private var isSubmitting = false
    @State private var showContactPicker = false
    @State private var contactPickMessage: String?

    struct CatalogEntry: Identifiable, Hashable {
        let bundleIdentifier: String
        let displayName: String
        let artworkURL: URL?
        var launchURLString: String? = nil
        var iconPNG: Data? = nil

        var id: String { bundleIdentifier }
    }

    private var totalSelected: Int {
        selectedCatalog.count
    }

    private var doneLabel: String {
        if totalSelected <= 0 { return copy.doneTitle }
        return String(format: copy.addCountFormat, locale: Locale.current, totalSelected)
    }

    private var suggestedIds: Set<String> {
        Set(HubIOSInstalledApps.suggestedBundleIds)
    }

    private var extraInstalled: [HubIOSInstalledApps.Record] {
        installed.filter { !suggestedIds.contains($0.bundleIdentifier) }
    }

    var body: some View {
        NavigationStack {
            catalogGrid
            .navigationTitle(copy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copy.cancelTitle, action: onCancel)
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        submitSelection()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(doneLabel)
                        }
                    }
                    .disabled(totalSelected == 0 || isSubmitting)
                }
            }
            .onAppear {
                loadCatalogIfNeeded()
            }
            .sheet(isPresented: $showContactPicker) {
                HubIOSContactCallPicker(
                    onPick: { contacts in
                        showContactPicker = false
                        absorbContacts(contacts)
                    },
                    onCancel: {
                        showContactPicker = false
                    }
                )
                .ignoresSafeArea()
            }
            .alert(
                copy.title,
                isPresented: Binding(
                    get: { contactPickMessage != nil },
                    set: { if !$0 { contactPickMessage = nil } }
                )
            ) {
                Button(copy.doneTitle, role: .cancel) { contactPickMessage = nil }
            } message: {
                Text(contactPickMessage ?? "")
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private var filteredSuggested: [HubIOSInstalledApps.Record] {
        filterRecords(suggested)
    }

    private var filteredInstalled: [HubIOSInstalledApps.Record] {
        filterRecords(extraInstalled)
    }

    private var filteredStoreResults: [HubIOSAppStoreArtwork.StoreApp] {
        let localIds = Set(suggested.map(\.bundleIdentifier) + installed.map(\.bundleIdentifier))
        return storeResults.filter {
            !localIds.contains($0.bundleId) && HubIOSInstalledApps.canLaunch($0.bundleId)
        }
    }

    private var hasUnlaunchableStoreHits: Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isSearchingStore, !storeResults.isEmpty else { return false }
        return filteredStoreResults.isEmpty && filteredSuggested.isEmpty && filteredInstalled.isEmpty
    }

    private func filterRecords(_ records: [HubIOSInstalledApps.Record]) -> [HubIOSInstalledApps.Record] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return records }
        return records.filter {
            $0.displayName.localizedCaseInsensitiveContains(q)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(q)
        }
    }

    private var catalogGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hintBanner
                    if !selectedContactEntries.isEmpty {
                        section(title: copy.contactCallsHeader) {
                            appGrid(entries: selectedContactEntries)
                        }
                    }
                    if !suggested.isEmpty {
                        section(title: copy.suggestedHeader) {
                            appGrid(entries: suggested.map(catalogEntry(from:)))
                        }
                    }
                    if !extraInstalled.isEmpty {
                        section(title: copy.catalogInstalledHeader) {
                            appGrid(entries: extraInstalled.map(catalogEntry(from:)))
                        }
                    }
                    if suggested.isEmpty, extraInstalled.isEmpty, didLoadInstalled {
                        emptyLabel
                    }
                } else {
                    if !filteredSuggested.isEmpty {
                        section(title: copy.suggestedHeader) {
                            appGrid(entries: filteredSuggested.map(catalogEntry(from:)))
                        }
                    }
                    if !filteredInstalled.isEmpty {
                        section(title: copy.catalogInstalledHeader) {
                            appGrid(entries: filteredInstalled.map(catalogEntry(from:)))
                        }
                    }
                    section(title: copy.catalogStoreHeader) {
                        if isSearchingStore, filteredStoreResults.isEmpty {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(copy.storeSearching)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 4)
                        } else if hasUnlaunchableStoreHits {
                            Text(copy.unlaunchableHint)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                        } else if filteredStoreResults.isEmpty,
                                  filteredSuggested.isEmpty,
                                  filteredInstalled.isEmpty,
                                  !isSearchingStore {
                            emptyLabel
                        } else {
                            appGrid(entries: filteredStoreResults.map { app in
                                CatalogEntry(
                                    bundleIdentifier: app.bundleId,
                                    displayName: app.name,
                                    artworkURL: app.artworkURL
                                )
                            })
                        }
                    }
                }

                Text(copy.catalogFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: copy.searchPlaceholder
        )
        .autocorrectionDisabled()
        .task(id: query) {
            await searchStore(for: query)
        }
    }

    private var hintBanner: some View {
        Text(copy.searchHint)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private var emptyLabel: some View {
        Text(copy.catalogEmpty)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)
            content()
        }
    }

    private func appGrid(entries: [CatalogEntry]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 72, maximum: 92), spacing: 14, alignment: .top)]
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(entries) { entry in
                appCell(entry)
            }
        }
    }

    private var selectedContactEntries: [CatalogEntry] {
        selectedCatalog.filter { HubIOSInstalledApps.isContactCall($0.bundleIdentifier) }
    }

    private func appCell(_ entry: CatalogEntry) -> some View {
        let isPhoneSetup = HubIOSInstalledApps.needsContactCallSetup(entry.bundleIdentifier)
        let isSelected = selectedCatalog.contains(where: { $0.bundleIdentifier == entry.bundleIdentifier })
        let isOccupied = !isPhoneSetup && occupiedBundleIds.contains(entry.bundleIdentifier)
        let disabled = isOccupied && !isSelected
        return Button {
            guard !disabled else { return }
            if isPhoneSetup {
                beginAddContactCalls()
                return
            }
            toggleCatalog(entry)
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    HubIOSCatalogIconView(
                        bundleIdentifier: entry.bundleIdentifier,
                        displayName: entry.displayName,
                        artworkURL: entry.artworkURL,
                        initialPNG: entry.iconPNG
                    )
                    .frame(width: 64, height: 64)
                    .opacity(disabled ? 0.42 : 1)

                    if isSelected || isOccupied {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, isSelected ? Color.accentColor : Color.secondary)
                            .offset(x: 4, y: -4)
                    }
                }
                Text(isOccupied && !isSelected ? copy.alreadyAdded : entry.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(disabled ? .tertiary : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 76, minHeight: 28, alignment: .top)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(entry.displayName)
    }

    private func catalogEntry(from record: HubIOSInstalledApps.Record) -> CatalogEntry {
        CatalogEntry(
            bundleIdentifier: record.bundleIdentifier,
            displayName: record.displayName,
            artworkURL: nil
        )
    }

    private func toggleCatalog(_ entry: CatalogEntry) {
        if let index = selectedCatalog.firstIndex(where: { $0.bundleIdentifier == entry.bundleIdentifier }) {
            selectedCatalog.remove(at: index)
        } else {
            selectedCatalog.append(entry)
        }
    }

    private func beginAddContactCalls() {
        HubIOSContactCall.requestAccessThen {
            showContactPicker = true
        }
    }

    private func absorbContacts(_ contacts: [CNContact]) {
        let contactPicks = HubIOSContactCall.picks(from: contacts)
        guard !contactPicks.isEmpty else {
            contactPickMessage = copy.contactNoPhone
            return
        }
        isSubmitting = true
        let others = selectedCatalog.filter {
            !HubIOSInstalledApps.needsContactCallSetup($0.bundleIdentifier)
                && !HubIOSInstalledApps.isContactCall($0.bundleIdentifier)
        }
        Task {
            let otherPicks = await Self.resolveCatalogPicks(others)
            isSubmitting = false
            onPick(otherPicks + contactPicks)
        }
    }

    private func loadCatalogIfNeeded() {
        guard !didLoadInstalled else { return }
        didLoadInstalled = true
        suggested = HubIOSInstalledApps.suggestedLauncherApps()
        installed = HubIOSInstalledApps.locallyEnumeratedApps()
    }

    private func searchStore(for rawQuery: String) async {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 1 else {
            storeResults = []
            isSearchingStore = false
            return
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        isSearchingStore = true
        let results = await HubIOSAppStoreArtwork.search(term: q)
        guard !Task.isCancelled else { return }
        storeResults = results.filter {
            HubIOSInstalledApps.isLauncherCandidate(bundleIdentifier: $0.bundleId, displayName: $0.name)
        }
        isSearchingStore = false
    }

    private func submitSelection() {
        guard !isSubmitting, totalSelected > 0 else { return }
        isSubmitting = true
        let catalog = selectedCatalog
        Task {
            let catalogPicks = await Self.resolveCatalogPicks(catalog)
            isSubmitting = false
            guard !catalogPicks.isEmpty else { return }
            onPick(catalogPicks)
        }
    }

    /// 立刻回传已缓存的图标；缺的交给蜂巢后台补，避免多选时卡在选择页。
    private static func resolveCatalogPicks(_ entries: [CatalogEntry]) async -> [HubIOSFamilyAppPick] {
        guard !entries.isEmpty else { return [] }
        let bundleIds = entries.map(\.bundleIdentifier)
        Task.detached(priority: .utility) {
            for bundleId in bundleIds {
                HubIOSInstalledApps.rememberLaunchURL(for: bundleId)
            }
        }
        return entries.map { entry in
            if let launch = entry.launchURLString, !launch.isEmpty {
                HubIOSAppGroup.saveLaunchURL(launch, for: entry.bundleIdentifier)
            }
            let png = entry.iconPNG
                ?? HubIOSAppStoreArtwork.cachedImageCheap(for: entry.bundleIdentifier)?
                .hub_pngData(maxPixelSide: 192)
                ?? HubIOSAppGroup.loadIconRaw(for: entry.bundleIdentifier)
            return HubIOSFamilyAppPick(
                bundleIdentifier: entry.bundleIdentifier,
                displayName: entry.displayName,
                tokenData: nil,
                iconPNG: png,
                launchURLString: entry.launchURLString
            )
        }
    }

}

/// 选择页图标：先出字母占位，后台限流补 App Store 官方图。
private struct HubIOSCatalogIconView: View {
    let bundleIdentifier: String
    let displayName: String
    let artworkURL: URL?
    var initialPNG: Data? = nil

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                Text(String(displayName.prefix(1)).uppercased())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .onAppear {
            if image == nil, let initialPNG, let seeded = UIImage(data: initialPNG) {
                image = seeded
            }
        }
        .task(id: bundleIdentifier) {
            if image == nil, let initialPNG, let seeded = UIImage(data: initialPNG) {
                image = seeded
            }
            if HubIOSInstalledApps.isContactCall(bundleIdentifier) { return }
            let bid = bundleIdentifier
            let name = displayName
            let url = artworkURL
            let fetched = await Task.detached(priority: .utility) {
                await HubIOSPickerIconLoader.shared.image(
                    bundleId: bid,
                    displayName: name,
                    artworkURL: url
                )
            }.value
            guard !Task.isCancelled else { return }
            image = fetched
        }
    }
}

/// 最多 3 路同时补图，避免打开选择页时几十个网络请求把 UI 堵住。
private actor HubIOSPickerIconLoader {
    static let shared = HubIOSPickerIconLoader()

    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let limit = 3

    func image(bundleId: String, displayName: String, artworkURL: URL?) async -> UIImage? {
        await acquire()
        defer { release() }
        if let cached = HubIOSAppStoreArtwork.cachedImageCheap(for: bundleId) {
            return cached
        }
        if let data = HubIOSAppGroup.loadIcon(for: bundleId), let image = UIImage(data: data) {
            return image
        }
        if let artworkURL {
            return await HubIOSAppStoreArtwork.displayImage(for: bundleId, artworkURL: artworkURL)
        }
        if let store = await HubIOSAppStoreArtwork.displayImage(for: bundleId, displayName: displayName) {
            return store
        }
        return HubIOSAppSymbol.fallbackIcon(for: bundleId)
    }

    private func acquire() async {
        if running >= limit {
            await withCheckedContinuation { waiters.append($0) }
        }
        running += 1
    }

    private func release() {
        running = max(0, running - 1)
        guard !waiters.isEmpty else { return }
        waiters.removeFirst().resume()
    }
}
#endif
