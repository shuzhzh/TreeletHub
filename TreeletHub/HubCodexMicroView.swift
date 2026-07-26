import AudioToolbox
import SwiftUI
import UIKit

/// Virtual control pad for a single AI client opened from the hub grid.
struct HubCodexMicroView: View {
    @ObservedObject var client: HubIOSClient
    /// Locked by the grid slot that opened this page — no in-page target switching.
    let lockedTarget: HubCodexControlTarget
    @EnvironmentObject private var uiLanguage: HubIOSUILanguage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dialAngle: Double = 0
    @State private var previousDialAngle: Double?
    @State private var dialRotationAccumulator: Double = 0
    @State private var dialDidRotate = false
    @State private var joystickOffset: CGSize = .zero
    @State private var showMapper = false
    @State private var pulsePhase = false

    /// Actual rendered dial size; rotation math needs the real centre, not a guess.
    @State private var dialDiameter: CGFloat = 128
    private let dialDetentDegrees: Double = 30

    private var state: HubCodexMicroState { client.codexMicroState }
    private var mapping: HubCodexMicroMapping { state.mapping }

    private func L(_ key: String) -> String {
        HubBundleLocalizedString.localized(key, locale: uiLanguage.locale, bundle: .main)
    }

    var body: some View {
        GeometryReader { geo in
            let pad = max(12, min(24, geo.size.width * 0.04))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    connectionStatusCard
                    header
                    LiveTranscriptView(dictation: client.dictation, phase: client.localRecordingPhase)
                    if lockedTarget.showsAgentKeys {
                        agentRow
                    } else {
                        cursorHintRow
                    }
                    controlsRow(width: geo.size.width - pad * 2)
                    commandGrid
                    layerAndLegend
                }
                .padding(.horizontal, pad)
                .padding(.vertical, 16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMapper = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(L("ios.codex.settings"))
            }
        }
        .sheet(isPresented: $showMapper) {
            NavigationStack {
                HubCodexMicroSettingsView(client: client, lockedTarget: lockedTarget)
                    .environmentObject(uiLanguage)
            }
        }
        .onAppear {
            client.codexSetTarget(lockedTarget)
            client.requestCodexMicroState()
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulsePhase = true
                }
            }
        }
        .onDisappear {
            client.pttCancel()
        }
    }

    // MARK: - Sections

    private var connectionStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                statusDot(ok: client.phase == .paired)
                Text(L("ios.codex.link_phone_mac"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(client.phase == .paired ? L("ios.codex.status_ok") : L("ios.codex.status_bad"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(client.phase == .paired ? Color.green : Color.orange)
            }

            HStack {
                statusDot(ok: targetInstalled)
                Text(String(format: L("ios.codex.link_target_fmt"), lockedTarget.displayNameEN))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(targetRuntimeLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(targetRuntimeColor)
            }

            HStack {
                statusDot(ok: state.accessibilityGranted)
                Text(L("ios.codex.link_accessibility"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if state.accessibilityGranted {
                    Text(L("ios.codex.status_ok"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    Button(L("ios.codex.fix_permission")) {
                        client.codexOpenAccessibilitySettings()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }

            if let err = state.lastControlError ?? client.lastError, !err.isEmpty {
                if let query = Self.paletteHintQuery(from: err) {
                    paletteHintCard(query: query)
                } else {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if targetInstalled && state.accessibilityGranted {
                Text(L("ios.codex.ready_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L("ios.codex.blocked_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(padChassis)
    }

    private var targetInstalled: Bool {
        state.availableTargets.first(where: { $0.target.bundleIdentifier == lockedTarget.bundleIdentifier })?.installed
            ?? (state.controlTarget.bundleIdentifier == lockedTarget.bundleIdentifier && state.targetInstalled)
    }

    private func paletteHintCard(query: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("ios.codex.palette_hint_title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(String(format: L("ios.codex.palette_hint_body_fmt"), query))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(L("ios.codex.palette_enable_retry")) {
                    let action = Self.actionMatchingPaletteQuery(query)
                    client.codexEnableTextAutomationAndRetry(action)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(L("ios.codex.palette_dismiss")) {
                    client.codexDismissControlHint()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private static func paletteHintQuery(from message: String) -> String? {
        let prefix = "hint:palette:"
        guard message.hasPrefix(prefix) else { return nil }
        return String(message.dropFirst(prefix.count))
    }

    private static func actionMatchingPaletteQuery(_ query: String) -> HubCodexMicroAction? {
        let q = query.lowercased()
        if q.contains("fast") { return .fastMode }
        if q.contains("approve") { return .approve }
        if q.contains("decline") { return .decline }
        if q.contains("plan") { return .planMode }
        if q.contains("browser") { return .openBrowser }
        if q.contains("commit") { return .gitCommit }
        if q.contains("pull") { return .createPullRequest }
        if q.contains("skill") { return .openSkills }
        if q.contains("schedul") { return .scheduledTasks }
        if q.contains("reasoning") { return .reasoningEffort }
        return nil
    }

    private var cursorHintRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("ios.codex.cursor_pad_title"))
                .font(.subheadline.weight(.semibold))
            Text(L("ios.codex.cursor_pad_body"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(padChassis)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(lockedTarget.displayNameEN)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text(padSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            recordingBadge
        }
    }

    private var padSubtitle: String {
        switch lockedTarget {
        case .codex: return L("ios.codex.subtitle.codex")
        case .chatGPT, .chatGPTClassic: return L("ios.codex.subtitle.chatgpt")
        case .cursor: return L("ios.codex.subtitle.cursor")
        }
    }

    private var targetRuntimeLabel: String {
        let installed = state.availableTargets.first(where: { $0.target.bundleIdentifier == lockedTarget.bundleIdentifier })?.installed
            ?? state.targetInstalled
        let running = state.availableTargets.first(where: { $0.target.bundleIdentifier == lockedTarget.bundleIdentifier })?.running
            ?? state.targetRunning
        if !installed { return L("ios.codex.not_installed") }
        return running ? L("ios.codex.running") : L("ios.codex.installed_idle")
    }

    private var targetRuntimeColor: Color {
        let installed = state.availableTargets.first(where: { $0.target.bundleIdentifier == lockedTarget.bundleIdentifier })?.installed
            ?? state.targetInstalled
        let running = state.availableTargets.first(where: { $0.target.bundleIdentifier == lockedTarget.bundleIdentifier })?.running
            ?? state.targetRunning
        if !installed { return .orange }
        return running ? .green : .secondary
    }

    private func statusDot(ok: Bool) -> some View {
        Circle()
            .fill(ok ? Color.green : Color.orange)
            .frame(width: 8, height: 8)
    }

    /// PTT 录音识别发生在 iPhone 本地，优先展示本地阶段；Mac 粘贴完成后回传 .ready。
    private var effectiveRecording: HubCodexRecordingState {
        client.localRecordingPhase != .idle ? client.localRecordingPhase : state.recording
    }

    @ViewBuilder
    private var recordingBadge: some View {
        switch effectiveRecording {
        case .idle:
            EmptyView()
        case .recording:
            Label(L("ios.codex.recording"), systemImage: "waveform")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.teal.opacity(0.25)))
                .foregroundStyle(.teal)
        case .processing:
            Label(L("ios.codex.processing"), systemImage: "ellipsis")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        case .ready:
            Label(L("ios.codex.ready_to_send"), systemImage: "checkmark")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.18)))
        }
    }

    private var agentRow: some View {
        HStack(spacing: 10) {
            ForEach(normalizedAgents) { agent in
                Button {
                    haptic(.medium)
                    client.codexAgentTap(index: agent.id)
                } label: {
                    AgentKeyView(
                        agent: agent,
                        brightness: mapping.brightness,
                        pulse: agent.isSelected && pulsePhase && !reduceMotion,
                        cancelArmed: state.dialCancelArmed && agent.id == 0
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(agentAccessibility(agent))
            }
        }
        .padding(12)
        .background(padChassis)
    }

    private func controlsRow(width: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 16) {
            dialControl
                .frame(width: min(128, width * 0.32), height: min(128, width * 0.32))
            joystickControl
                .frame(width: min(128, width * 0.32), height: min(128, width * 0.32))
            VStack(alignment: .leading, spacing: 8) {
                Text(L("ios.codex.reasoning"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(reasoningLabel)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text(mapping.dialMode == .reasoningOnly ? L("ios.codex.dial_reasoning") : L("ios.codex.dial_composer"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if state.dialCancelArmed {
                    Button(L("ios.codex.cancel")) {
                        haptic(.light)
                        client.codexDialCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(padChassis)
    }

    private var commandGrid: some View {
        let keys = normalizedCommandKeys
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, action in
                if action == .pushToTalk {
                    PushToTalkKeyView(
                        isRecording: client.localRecordingPhase == .recording,
                        onPress: {
                            haptic(.medium)
                            client.pttStart()
                        },
                        onRelease: {
                            haptic(.light)
                            client.pttStopAndSend()
                        },
                        onDoubleTapHandsFree: {
                            haptic(.medium)
                            client.pttStart()
                        }
                    )
                } else {
                    CommandKeyView(action: action) {
                        handleCommand(action)
                    }
                }
            }
        }
        .padding(12)
        .background(padChassis)
    }

    private var layerAndLegend: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Button {
                    haptic(.light)
                    client.codexLayerCycle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                        Text(String(format: L("ios.codex.layer_fmt"), state.layer))
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 4) {
                            ForEach(1...6, id: \.self) { layer in
                                Circle()
                                    .fill(layer == state.layer ? Color.cyan : Color.white.opacity(0.2))
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    client.requestCodexMicroState()
                    haptic(.light)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .padding(10)
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(HubCodexAgentStatus.allCases.filter { $0 != .unassigned }, id: \.self) { status in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(AgentKeyView.color(for: status))
                                .frame(width: 8, height: 8)
                            Text(statusLabel(status))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Dial / Joystick

    private var dialControl: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.22), Color(white: 0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1.2))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)

            Circle()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 10)
                .padding(10)

            Capsule()
                .fill(Color.white.opacity(0.85))
                .frame(width: 4, height: 22)
                .offset(y: -34)
                .rotationEffect(.degrees(dialAngle))

            Circle()
                .fill(Color(white: 0.14))
                .frame(width: 42, height: 42)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
        }
        .contentShape(Circle())
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { dialDiameter = min(proxy.size.width, proxy.size.height) }
                    .onChange(of: proxy.size) { _, newValue in
                        dialDiameter = min(newValue.width, newValue.height)
                    }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    // Ignore the touch-down frame; it carries no rotation yet.
                    guard value.translation != .zero else { return }
                    let center = CGPoint(x: dialDiameter / 2, y: dialDiameter / 2)
                    let angle = atan2(value.location.y - center.y, value.location.x - center.x) * 180 / .pi
                    guard let previous = previousDialAngle else {
                        previousDialAngle = angle
                        return
                    }
                    // Normalise into (-180, 180] so crossing the 0°/360° seam is one small step.
                    var delta = angle - previous
                    if delta > 180 { delta -= 360 }
                    if delta < -180 { delta += 360 }
                    previousDialAngle = angle
                    dialAngle += delta
                    dialRotationAccumulator += delta
                    dialDidRotate = true

                    // One detent per 30°, and never more than one send per detent.
                    while abs(dialRotationAccumulator) >= dialDetentDegrees {
                        let direction = dialRotationAccumulator > 0 ? 1 : -1
                        dialRotationAccumulator -= Double(direction) * dialDetentDegrees
                        haptic(.soft)
                        client.codexDialTurn(steps: direction)
                    }
                }
                .onEnded { _ in
                    previousDialAngle = nil
                    dialRotationAccumulator = 0
                    // A touch with no rotation is a press.
                    if !dialDidRotate {
                        haptic(.medium)
                        client.codexDialPress()
                    }
                    dialDidRotate = false
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    guard !dialDidRotate else { return }
                    haptic(.medium)
                    client.codexDialLongPress()
                }
        )
        .accessibilityLabel(L("ios.codex.dial"))
        .accessibilityAdjustableAction { direction in
            client.codexDialTurn(steps: direction == .increment ? 1 : -1)
        }
    }

    private var joystickControl: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(white: 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.35), Color(white: 0.12)],
                        center: .center,
                        startRadius: 2,
                        endRadius: 36
                    )
                )
                .frame(width: 64, height: 64)
                .offset(joystickOffset)
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let limit: CGFloat = 28
                            let x = max(-limit, min(limit, value.translation.width))
                            let y = max(-limit, min(limit, value.translation.height))
                            joystickOffset = CGSize(width: x, height: y)
                        }
                        .onEnded { value in
                            let x = value.translation.width
                            let y = value.translation.height
                            let threshold: CGFloat = 24
                            if hypot(x, y) >= threshold {
                                let direction: HubCodexJoystickDirection
                                if abs(x) > abs(y) {
                                    direction = x > 0 ? .right : .left
                                } else {
                                    direction = y > 0 ? .down : .up
                                }
                                haptic(.medium)
                                client.codexJoystick(direction)
                            }
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                                joystickOffset = .zero
                            }
                        }
                )
        }
        .accessibilityLabel(L("ios.codex.joystick"))
    }

    // MARK: - Helpers

    private var padChassis: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.17, blue: 0.19),
                        Color(red: 0.08, green: 0.09, blue: 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.22), Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
    }

    private var normalizedAgents: [HubCodexAgentSlot] {
        var agents = state.agents
        while agents.count < 6 {
            agents.append(HubCodexAgentSlot(id: agents.count))
        }
        return Array(agents.prefix(6))
    }

    private var normalizedCommandKeys: [HubCodexMicroAction] {
        // Prefer Mac-pushed mapping once it matches this locked target.
        if state.controlTarget == lockedTarget, mapping.commandKeys.count == 6 {
            return mapping.commandKeys
        }
        return HubCodexMicroMapping.defaultCommandKeys(for: lockedTarget)
    }

    private var reasoningLabel: String {
        let labels = ["Minimal", "Low", "Medium", "High", "xHigh"]
        let idx = min(max(0, state.reasoningLevel), labels.count - 1)
        return labels[idx]
    }

    private func handleCommand(_ action: HubCodexMicroAction) {
        haptic(.medium)
        client.codexCommand(action)
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        AudioServicesPlaySystemSound(1104)
    }

    private func statusLabel(_ status: HubCodexAgentStatus) -> String {
        switch status {
        case .idle: return L("ios.codex.status.idle")
        case .thinking: return L("ios.codex.status.thinking")
        case .complete: return L("ios.codex.status.complete")
        case .requiresInput: return L("ios.codex.status.input")
        case .error: return L("ios.codex.status.error")
        case .unassigned: return L("ios.codex.status.off")
        }
    }

    private func agentAccessibility(_ agent: HubCodexAgentSlot) -> String {
        let title = agent.title ?? "Agent \(agent.id + 1)"
        return "\(title), \(statusLabel(agent.status))"
    }
}

// MARK: - Subviews

private struct AgentKeyView: View {
    let agent: HubCodexAgentSlot
    let brightness: Double
    let pulse: Bool
    let cancelArmed: Bool

    var body: some View {
        let glow = cancelArmed && agent.status != .unassigned
            ? Color.red
            : Self.color(for: agent.status)
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.18 * brightness),
                        Color.black.opacity(0.35)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(glow.opacity(agent.status == .unassigned ? 0.05 : 0.55 * brightness))
                    .blur(radius: pulse ? 1.5 : 0)
                    .opacity(pulse ? 0.85 : 1)
            }
            .overlay {
                VStack(spacing: 4) {
                    Text("\(agent.id + 1)")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                    if let title = agent.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 4)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(agent.isSelected ? 0.55 : 0.12), lineWidth: agent.isSelected ? 2 : 1)
            )
            .frame(maxWidth: .infinity)
            .frame(height: 72)
            .shadow(color: glow.opacity(agent.status == .unassigned ? 0 : 0.45 * brightness), radius: pulse ? 10 : 6)
    }

    static func color(for status: HubCodexAgentStatus) -> Color {
        switch status {
        case .idle: return Color(white: 0.92)
        case .thinking: return Color(red: 0.25, green: 0.55, blue: 1.0)
        case .complete: return Color(red: 0.25, green: 0.82, blue: 0.45)
        case .requiresInput: return Color(red: 1.0, green: 0.72, blue: 0.18)
        case .error: return Color(red: 0.95, green: 0.28, blue: 0.28)
        case .unassigned: return .clear
        }
    }
}

/// Shows what the iPhone hears while push-to-talk is active.
private struct LiveTranscriptView: View {
    @ObservedObject var dictation: HubIOSDictationController
    let phase: HubCodexRecordingState

    var body: some View {
        if phase == .recording || phase == .processing {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: phase == .recording ? "waveform" : "ellipsis.circle")
                    .foregroundStyle(.teal)
                Text(dictation.partialTranscript.isEmpty ? "正在聆听…" : dictation.partialTranscript)
                    .font(.callout)
                    .foregroundStyle(dictation.partialTranscript.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.teal.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.teal.opacity(0.4), lineWidth: 1)
                    )
            )
            .transition(.opacity)
        }
    }
}

private struct PushToTalkKeyView: View {
    let isRecording: Bool
    let onPress: () -> Void
    let onRelease: () -> Void
    let onDoubleTapHandsFree: () -> Void

    /// Official Codex Micro window is 350ms between taps; we keep that, but give the first
    /// short-tap release enough time to wait for the second tap before ending.
    private static let doubleTapWindow: TimeInterval = 0.35
    /// Press shorter than this is a "tap" (may become double-tap); longer is hold-to-talk.
    private static let holdThreshold: TimeInterval = 0.28

    @State private var lastDownAt: Date?
    @State private var pressBeganAt: Date?
    @State private var pressed = false
    @State private var handsFreeSession = false
    @State private var localActive = false
    @State private var pendingReleaseTask: Task<Void, Never>?

    private var showListening: Bool { localActive || isRecording }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: showListening ? "waveform.circle.fill" : "mic.fill")
                .font(.system(size: 20, weight: .semibold))
            Text(showListening ? (handsFreeSession ? "免提中" : "Listening") : "PTT")
                .font(.caption2.weight(.semibold))
            Text(handsFreeSession ? "轻点结束" : "按住说话 · 双击免提")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white.opacity(0.92))
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(showListening ? Color.teal.opacity(0.35) : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(showListening ? Color.teal.opacity(0.8) : Color.white.opacity(0.14), lineWidth: 1)
                )
        )
        .scaleEffect(pressed ? 0.96 : 1)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    let now = Date()
                    pressBeganAt = now

                    // Tap while already in hands-free → stop (ignore the following onEnded).
                    if handsFreeSession, localActive || isRecording {
                        pendingReleaseTask?.cancel()
                        pendingReleaseTask = nil
                        handsFreeSession = false
                        localActive = false
                        lastDownAt = nil
                        pressBeganAt = nil
                        onRelease()
                        return
                    }

                    // Second tap within the double-tap window → promote to hands-free.
                    if let last = lastDownAt, now.timeIntervalSince(last) < Self.doubleTapWindow {
                        pendingReleaseTask?.cancel()
                        pendingReleaseTask = nil
                        handsFreeSession = true
                        if !localActive {
                            localActive = true
                            onDoubleTapHandsFree()
                        }
                        lastDownAt = now
                        return
                    }

                    // Fresh press: start recording. Release will decide hold vs wait-for-double-tap.
                    pendingReleaseTask?.cancel()
                    pendingReleaseTask = nil
                    lastDownAt = now
                    handsFreeSession = false
                    localActive = true
                    onPress()
                }
                .onEnded { _ in
                    pressed = false
                    // Hands-free (or the tap that just ended it) must not schedule another stop.
                    guard !handsFreeSession else { return }
                    guard localActive else { return }

                    let heldFor = pressBeganAt.map { Date().timeIntervalSince($0) } ?? 0
                    pressBeganAt = nil

                    // Long press = classic hold-to-talk: end as soon as the finger lifts.
                    if heldFor >= Self.holdThreshold {
                        pendingReleaseTask?.cancel()
                        pendingReleaseTask = nil
                        localActive = false
                        lastDownAt = nil
                        onRelease()
                        return
                    }

                    // Short tap: wait for a possible second tap before ending.
                    pendingReleaseTask?.cancel()
                    pendingReleaseTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(Self.doubleTapWindow * 1_000_000_000))
                        guard !Task.isCancelled, !handsFreeSession, localActive else { return }
                        localActive = false
                        lastDownAt = nil
                        onRelease()
                    }
                }
        )
        .accessibilityLabel("Push to talk")
        .accessibilityHint("Press and hold to dictate. Double tap for hands-free, then tap once to stop.")
    }
}

private struct CommandKeyView: View {
    let action: HubCodexMicroAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: action.defaultSymbolName)
                    .font(.system(size: 20, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.92))
            .frame(maxWidth: .infinity)
            .frame(height: 78)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var label: String {
        switch action {
        case .fastMode: return "Fast"
        case .approve: return "Approve"
        case .decline: return "Decline"
        case .continueNewChat: return "Continue"
        case .pushToTalk: return "PTT"
        case .sendMessage: return "Send"
        case .newChat: return "New"
        case .openBrowser: return "Browser"
        case .openTerminal: return "Terminal"
        case .reviewChanges: return "Review"
        case .gitCommit: return "Commit"
        case .createPullRequest: return "PR"
        case .attachFiles: return "Attach"
        case .scheduledTasks: return "Schedule"
        case .reasoningEffort: return "Reason"
        case .openSkills: return "Skills"
        case .planMode: return "Plan"
        case .historyBack: return "Back"
        case .historyForward: return "Forward"
        case .toggleSidebar: return "Sidebar"
        case .openSettings: return "Settings"
        case .openCommandMenu: return "Menu"
        case .focusChatGPT: return "Chat"
        case .none: return "—"
        }
    }
}
