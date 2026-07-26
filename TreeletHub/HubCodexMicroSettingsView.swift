import SwiftUI

/// Remap Command Keys / joystick / dial for the locked AI client.
struct HubCodexMicroSettingsView: View {
    @ObservedObject var client: HubIOSClient
    let lockedTarget: HubCodexControlTarget
    @EnvironmentObject private var uiLanguage: HubIOSUILanguage
    @Environment(\.dismiss) private var dismiss

    @State private var mapping: HubCodexMicroMapping = .default
    @State private var editingCommandIndex: Int?
    @State private var editingJoystick: HubCodexJoystickDirection?
    @State private var showActionPicker = false

    private func L(_ key: String) -> String {
        HubBundleLocalizedString.localized(key, locale: uiLanguage.locale, bundle: .main)
    }

    var body: some View {
        List {
            Section {
                Text(lockedTarget.displayNameEN)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("ios.codex.control_target"))
            }

            Section {
                if lockedTarget.showsAgentKeys {
                    Picker(L("ios.codex.agent_source"), selection: $mapping.agentSource) {
                        Text(L("ios.codex.source.recent")).tag(HubCodexAgentSource.mostRecent)
                        Text(L("ios.codex.source.pinned")).tag(HubCodexAgentSource.pinned)
                        Text(L("ios.codex.source.priority")).tag(HubCodexAgentSource.priority)
                        Text(L("ios.codex.source.custom")).tag(HubCodexAgentSource.custom)
                    }
                }

                Picker(L("ios.codex.dial_mode"), selection: $mapping.dialMode) {
                    Text(L("ios.codex.dial_reasoning")).tag(HubCodexDialMode.reasoningOnly)
                    Text(L("ios.codex.dial_composer")).tag(HubCodexDialMode.composerNavigation)
                }

                VStack(alignment: .leading) {
                    Text(L("ios.codex.brightness"))
                    Slider(value: $mapping.brightness, in: 0.2...1.0)
                }

                Stepper(
                    value: $mapping.idleLightSeconds,
                    in: 30...600,
                    step: 30
                ) {
                    Text(String(format: L("ios.codex.idle_lights_fmt"), mapping.idleLightSeconds))
                }
            } header: {
                Text(L("ios.codex.settings_general"))
            } footer: {
                Text(L("ios.codex.settings_footer"))
            }

            Section {
                Toggle(L("ios.codex.text_automation"), isOn: $mapping.allowsTextAutomation)
            } footer: {
                Text(L("ios.codex.text_automation_footer"))
            }

            Section(L("ios.codex.command_keys")) {
                ForEach(Array(normalizedCommandKeys.enumerated()), id: \.offset) { index, action in
                    Button {
                        editingCommandIndex = index
                        editingJoystick = nil
                        showActionPicker = true
                    } label: {
                        HStack {
                            Image(systemName: action.defaultSymbolName)
                            Text(actionTitle(action))
                            Spacer()
                            Text("Key \(index + 1)")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Section(L("ios.codex.joystick_map")) {
                ForEach(HubCodexJoystickDirection.allCases, id: \.self) { direction in
                    Button {
                        editingJoystick = direction
                        editingCommandIndex = nil
                        showActionPicker = true
                    } label: {
                        HStack {
                            Text(directionTitle(direction))
                            Spacer()
                            let action = mapping.joystick[direction.rawValue]
                                ?? HubCodexMicroMapping.defaultJoystick(for: lockedTarget)[direction.rawValue]
                                ?? .none
                            Text(actionTitle(action))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Section {
                Button(L("ios.codex.reset_defaults")) {
                    mapping = .default(for: lockedTarget)
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle(L("ios.codex.settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L("ios.common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("ios.common.save")) {
                    client.codexSetMapping(mapping)
                    dismiss()
                }
            }
        }
        .onAppear {
            if client.codexMicroState.controlTarget == lockedTarget {
                mapping = client.codexMicroState.mapping
            } else {
                mapping = .default(for: lockedTarget)
            }
            if mapping.commandKeys.count != 6 {
                mapping.commandKeys = HubCodexMicroMapping.defaultCommandKeys(for: lockedTarget)
            }
        }
        .sheet(isPresented: $showActionPicker) {
            NavigationStack {
                List(HubCodexMicroMapping.remappableActions(for: lockedTarget)) { action in
                    Button {
                        if let index = editingCommandIndex {
                            var keys = normalizedCommandKeys
                            keys[index] = action
                            mapping.commandKeys = keys
                        } else if let direction = editingJoystick {
                            mapping.joystick[direction.rawValue] = action
                        }
                        showActionPicker = false
                    } label: {
                        Label(actionTitle(action), systemImage: action.defaultSymbolName)
                    }
                }
                .navigationTitle(pickerTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L("ios.common.cancel")) { showActionPicker = false }
                    }
                }
            }
        }
    }

    private var pickerTitle: String {
        if let index = editingCommandIndex {
            return "Key \(index + 1)"
        }
        if let direction = editingJoystick {
            return directionTitle(direction)
        }
        return L("ios.codex.settings")
    }

    private var normalizedCommandKeys: [HubCodexMicroAction] {
        var keys = mapping.commandKeys
        if keys.count != 6 {
            keys = HubCodexMicroMapping.defaultCommandKeys(for: lockedTarget)
        }
        return keys
    }

    private func directionTitle(_ d: HubCodexJoystickDirection) -> String {
        switch d {
        case .up: return L("ios.codex.joy.up")
        case .right: return L("ios.codex.joy.right")
        case .down: return L("ios.codex.joy.down")
        case .left: return L("ios.codex.joy.left")
        }
    }

    private func actionTitle(_ action: HubCodexMicroAction) -> String {
        switch action {
        case .fastMode: return L("ios.codex.action.fast")
        case .approve: return lockedTarget == .cursor ? L("ios.codex.action.accept") : L("ios.codex.action.approve")
        case .decline: return lockedTarget == .cursor ? L("ios.codex.action.reject") : L("ios.codex.action.decline")
        case .continueNewChat: return L("ios.codex.action.continue")
        case .pushToTalk: return L("ios.codex.action.ptt")
        case .sendMessage: return L("ios.codex.action.send")
        case .newChat: return L("ios.codex.action.new")
        case .openBrowser: return L("ios.codex.action.browser")
        case .openTerminal: return L("ios.codex.action.terminal")
        case .reviewChanges: return L("ios.codex.action.review")
        case .gitCommit: return L("ios.codex.action.commit")
        case .createPullRequest: return L("ios.codex.action.pr")
        case .attachFiles: return L("ios.codex.action.attach")
        case .scheduledTasks: return L("ios.codex.action.schedule")
        case .reasoningEffort: return L("ios.codex.action.reasoning")
        case .openSkills: return L("ios.codex.action.skills")
        case .planMode: return L("ios.codex.action.plan")
        case .historyBack: return L("ios.codex.action.back")
        case .historyForward: return L("ios.codex.action.forward")
        case .toggleSidebar: return L("ios.codex.action.sidebar")
        case .openSettings: return L("ios.codex.action.settings")
        case .openCommandMenu: return L("ios.codex.action.menu")
        case .focusChatGPT: return lockedTarget == .cursor ? L("ios.codex.action.chat") : L("ios.codex.action.focus")
        case .none: return "—"
        }
    }
}

extension HubCodexJoystickDirection: Identifiable {
    public var id: String { rawValue }
}
