package com.treelet.treelethub.hub

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

@Serializable
enum class HubCodexAgentStatus {
    @SerialName("idle")
    Idle,

    @SerialName("thinking")
    Thinking,

    @SerialName("complete")
    Complete,

    @SerialName("requiresInput")
    RequiresInput,

    @SerialName("error")
    Error,

    @SerialName("unassigned")
    Unassigned,
}

@Serializable
enum class HubCodexAgentSource {
    @SerialName("mostRecent")
    MostRecent,

    @SerialName("pinned")
    Pinned,

    @SerialName("priority")
    Priority,

    @SerialName("custom")
    Custom,
}

@Serializable
enum class HubCodexDialMode {
    @SerialName("composerNavigation")
    ComposerNavigation,

    @SerialName("reasoningOnly")
    ReasoningOnly,
}

@Serializable
enum class HubCodexJoystickDirection {
    @SerialName("up")
    Up,

    @SerialName("right")
    Right,

    @SerialName("down")
    Down,

    @SerialName("left")
    Left,
}

@Serializable
enum class HubCodexRecordingState {
    @SerialName("idle")
    Idle,

    @SerialName("recording")
    Recording,

    @SerialName("processing")
    Processing,

    @SerialName("ready")
    Ready,
}

@Serializable
enum class HubCodexControlTarget {
    @SerialName("chatGPT")
    ChatGPT,

    @SerialName("codex")
    Codex,

    @SerialName("chatGPTClassic")
    ChatGPTClassic,

    @SerialName("cursor")
    Cursor,
    ;

    val bundleIdentifier: String
        get() =
            when (this) {
                ChatGPT, Codex -> "com.openai.codex"
                ChatGPTClassic -> "com.openai.chat"
                Cursor -> "com.todesktop.230313mzl4w4u92"
            }

    val displayNameEN: String
        get() =
            when (this) {
                ChatGPT -> "ChatGPT"
                Codex -> "Codex"
                ChatGPTClassic -> "ChatGPT Classic"
                Cursor -> "Cursor"
            }

    val showsAgentKeys: Boolean
        get() =
            when (this) {
                Codex -> true
                ChatGPT, ChatGPTClassic, Cursor -> false
            }

    val defaultDialMode: HubCodexDialMode
        get() = HubCodexDialMode.ReasoningOnly

    companion object {
        /** Targets that open the virtual control pad. */
        val padSupportedTargets: Set<HubCodexControlTarget> = setOf(Codex)

        fun resolve(
            bundleIdentifier: String?,
            displayName: String?,
        ): HubCodexControlTarget? {
            val bid = bundleIdentifier?.trim()?.lowercase().orEmpty()
            val name = displayName?.trim()?.lowercase().orEmpty()

            // Only Codex opens the pad; ChatGPT / Cursor launch only.
            if (name.contains("codex")) return Codex
            if (bid == Codex.bundleIdentifier || bid == "com.openai.chatgpt") {
                return null
            }
            return null
        }
    }
}

@Serializable
data class HubCodexTargetAvailability(
    val target: HubCodexControlTarget,
    val installed: Boolean = false,
    val running: Boolean = false,
)

@Serializable
enum class HubCodexMicroAction {
    @SerialName("fastMode")
    FastMode,

    @SerialName("approve")
    Approve,

    @SerialName("decline")
    Decline,

    @SerialName("continueNewChat")
    ContinueNewChat,

    @SerialName("pushToTalk")
    PushToTalk,

    @SerialName("sendMessage")
    SendMessage,

    @SerialName("newChat")
    NewChat,

    @SerialName("openBrowser")
    OpenBrowser,

    @SerialName("openTerminal")
    OpenTerminal,

    @SerialName("reviewChanges")
    ReviewChanges,

    @SerialName("gitCommit")
    GitCommit,

    @SerialName("createPullRequest")
    CreatePullRequest,

    @SerialName("attachFiles")
    AttachFiles,

    @SerialName("scheduledTasks")
    ScheduledTasks,

    @SerialName("reasoningEffort")
    ReasoningEffort,

    @SerialName("openSkills")
    OpenSkills,

    @SerialName("planMode")
    PlanMode,

    @SerialName("historyBack")
    HistoryBack,

    @SerialName("historyForward")
    HistoryForward,

    @SerialName("toggleSidebar")
    ToggleSidebar,

    @SerialName("openSettings")
    OpenSettings,

    @SerialName("openCommandMenu")
    OpenCommandMenu,

    @SerialName("focusChatGPT")
    FocusChatGPT,

    @SerialName("none")
    None,
}

@Serializable
data class HubCodexAgentSlot(
    val id: Int,
    val status: HubCodexAgentStatus = HubCodexAgentStatus.Unassigned,
    val title: String? = null,
    val threadId: String? = null,
    val isSelected: Boolean = false,
)

@Serializable
data class HubCodexMicroMapping(
    val commandKeys: List<HubCodexMicroAction> = defaultCommandKeys(HubCodexControlTarget.Codex),
    val joystick: Map<String, HubCodexMicroAction> = defaultJoystick(HubCodexControlTarget.Codex),
    val agentSource: HubCodexAgentSource = HubCodexAgentSource.MostRecent,
    val dialMode: HubCodexDialMode = HubCodexDialMode.ReasoningOnly,
    val customAgentThreadIds: List<String?> = List(6) { null },
    val brightness: Double = 1.0,
    val idleLightSeconds: Int = 180,
    val allowsTextAutomation: Boolean = false,
) {
    companion object {
        fun default(forTarget: HubCodexControlTarget): HubCodexMicroMapping =
            HubCodexMicroMapping(
                commandKeys = defaultCommandKeys(forTarget),
                joystick = defaultJoystick(forTarget),
                agentSource = HubCodexAgentSource.MostRecent,
                dialMode = forTarget.defaultDialMode,
                allowsTextAutomation = false,
            )

        fun defaultCommandKeys(target: HubCodexControlTarget): List<HubCodexMicroAction> =
            listOf(
                HubCodexMicroAction.PushToTalk,
                HubCodexMicroAction.NewChat,
                HubCodexMicroAction.OpenSkills,
                HubCodexMicroAction.ScheduledTasks,
                HubCodexMicroAction.OpenSettings,
                HubCodexMicroAction.FocusChatGPT,
            )

        fun defaultJoystick(target: HubCodexControlTarget): Map<String, HubCodexMicroAction> =
            mapOf(
                "up" to HubCodexMicroAction.NewChat,
                "right" to HubCodexMicroAction.OpenSkills,
                "down" to HubCodexMicroAction.OpenSettings,
                "left" to HubCodexMicroAction.ScheduledTasks,
            )

        fun remappableActions(target: HubCodexControlTarget): List<HubCodexMicroAction> =
            listOf(
                HubCodexMicroAction.PushToTalk,
                HubCodexMicroAction.NewChat,
                HubCodexMicroAction.ContinueNewChat,
                HubCodexMicroAction.OpenSkills,
                HubCodexMicroAction.ScheduledTasks,
                HubCodexMicroAction.OpenSettings,
                HubCodexMicroAction.FocusChatGPT,
                HubCodexMicroAction.None,
            )
    }
}

@Serializable
data class HubCodexMicroState(
    val agents: List<HubCodexAgentSlot> = (0 until 6).map { HubCodexAgentSlot(id = it) },
    val selectedAgentIndex: Int? = null,
    val recording: HubCodexRecordingState = HubCodexRecordingState.Idle,
    val reasoningLevel: Int = 2,
    val layer: Int = 1,
    val dialCancelArmed: Boolean = false,
    val chatGPTRunning: Boolean = false,
    val chatGPTBundleId: String? = null,
    val mapping: HubCodexMicroMapping = HubCodexMicroMapping.default(HubCodexControlTarget.Codex),
    val updatedAt: Double = 0.0,
    val controlTarget: HubCodexControlTarget = HubCodexControlTarget.ChatGPT,
    val targetInstalled: Boolean = false,
    val targetRunning: Boolean = false,
    val targetDisplayName: String = HubCodexControlTarget.ChatGPT.displayNameEN,
    val accessibilityGranted: Boolean = false,
    val automationReady: Boolean = false,
    val lastControlError: String? = null,
    val availableTargets: List<HubCodexTargetAvailability> = emptyList(),
) {
    val canControl: Boolean
        get() = targetInstalled || accessibilityGranted || automationReady

    companion object {
        val empty = HubCodexMicroState()
    }
}

@Serializable
data class HubCodexMicroCommand(
    val kind: String,
    val agentIndex: Int? = null,
    val action: HubCodexMicroAction? = null,
    val direction: HubCodexJoystickDirection? = null,
    val steps: Int? = null,
    val bringToFront: Boolean? = null,
    val mapping: HubCodexMicroMapping? = null,
    val handsFree: Boolean? = null,
    val target: HubCodexControlTarget? = null,
    val text: String? = null,
) {
    companion object {
        const val KIND_AGENT_TAP = "agentTap"
        const val KIND_AGENT_DOUBLE_TAP = "agentDoubleTap"
        const val KIND_COMMAND = "command"
        const val KIND_JOYSTICK = "joystick"
        const val KIND_DIAL_TURN = "dialTurn"
        const val KIND_DIAL_PRESS = "dialPress"
        const val KIND_DIAL_LONG_PRESS = "dialLongPress"
        const val KIND_DIAL_CANCEL = "dialCancel"
        const val KIND_LAYER_CYCLE = "layerCycle"
        const val KIND_REQUEST_STATE = "requestState"
        const val KIND_SET_MAPPING = "setMapping"
        const val KIND_SET_TARGET = "setTarget"
        const val KIND_OPEN_ACCESSIBILITY_SETTINGS = "openAccessibilitySettings"
        const val KIND_PUSH_TO_TALK_END = "pushToTalkEnd"
        const val KIND_INSERT_TEXT = "insertText"
    }
}

object HubCodexMicroWire {
    private val json =
        Json {
            ignoreUnknownKeys = true
            isLenient = true
            encodeDefaults = false
        }

    fun encodeCommand(command: HubCodexMicroCommand): String? =
        try {
            json.encodeToString(HubCodexMicroCommand.serializer(), command)
        } catch (_: Exception) {
            null
        }

    fun decodeState(message: String?): HubCodexMicroState? {
        if (message.isNullOrBlank()) return null
        return try {
            json.decodeFromString(HubCodexMicroState.serializer(), message)
        } catch (_: Exception) {
            null
        }
    }
}

enum class HubGestureCommand(
    val rawValue: String,
) {
    ShowDesktop("showDesktop"),
}
