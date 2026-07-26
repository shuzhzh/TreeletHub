package com.treelet.treelethub.hub

import android.content.Context
import androidx.annotation.StringRes
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.provider.Settings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import com.treelet.treelethub.R
import com.treelet.treelethub.locale.HubAndroidUILanguage

enum class HubClientPhase {
    Idle,
    Browsing,
    Connecting,
    Paired,
}

data class HubAndroidUiState(
    val phase: HubClientPhase = HubClientPhase.Idle,
    val pages: List<HubPageConfig> = listOf(HubPageConfig(id = 0, title = "Apps").normalized()),
    val layoutApplyEpoch: Long = 0L,
    val serverReportsSubscriptionActive: Boolean = false,
    val pinInput: String = "",
    val lastError: String? = null,
    val serverDisconnectAlertMessage: String? = null,
    val didLoadCachedPairing: Boolean = false,
    val discoveredServiceNames: List<String> = emptyList(),
    val codexMicroState: HubCodexMicroState = HubCodexMicroState.empty,
    val localRecordingPhase: HubCodexRecordingState = HubCodexRecordingState.Idle,
    val dictationPartial: String = "",
)

class HubAndroidClient(
    private val appContext: Context,
    private val scope: CoroutineScope,
) {
    private val nsdManager = appContext.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var browser: NsdManager.DiscoveryListener? = null
    private var resolveListener: NsdManager.ResolveListener? = null

    private var socket: Socket? = null
    private var reader: BufferedReader? = null
    private var writer: BufferedWriter? = null
    private val writeMutex = Mutex()

    private var readJob: Job? = null
    private var heartbeatJob: Job? = null

    private var pendingBonjourName: String? = null
    private var cachedBonjourNameForRestore: String? = null
    private var wantsAutoConnectAfterBrowse = false
    private var isSilentReconnect = false
    private val lastSilentReceiveReconnectAt = AtomicLong(0L)

    private val discoveredByName = ConcurrentHashMap<String, NsdServiceInfo>()
    private val lastAgentTapAt = ConcurrentHashMap<Int, Long>()
    val dictation = HubAndroidDictationController(appContext)

    private val _state = MutableStateFlow(HubAndroidUiState())
    val state: StateFlow<HubAndroidUiState> = _state.asStateFlow()

    private fun update(transform: (HubAndroidUiState) -> HubAndroidUiState) {
        _state.value = transform(_state.value)
    }

    private fun localizedContext(): Context = HubAndroidUILanguage.wrapContext(appContext)

    private fun str(@StringRes id: Int): String = localizedContext().getString(id)

    private fun str(@StringRes id: Int, vararg args: Any): String = localizedContext().getString(id, *args)

    companion object {
        const val customDeviceNameKey = "treelethub.device.displayName"
        private const val AGENT_DOUBLE_TAP_WINDOW_MS = 350L
    }

    fun restorePairingFromDiskOnLaunch() {
        val cache = HubPairingStore.load(appContext) ?: return
        update {
            it.copy(
                pinInput = cache.pin,
                didLoadCachedPairing = true,
            )
        }
        cachedBonjourNameForRestore = cache.bonjourServiceName
        isSilentReconnect = true
        wantsAutoConnectAfterBrowse = true
        startBrowsing()
    }

    fun reconnectFromCacheIfNeededOnForeground() {
        if (_state.value.phase == HubClientPhase.Paired) {
            sendRequestLayoutToMac()
            return
        }
        if (_state.value.phase == HubClientPhase.Browsing || _state.value.phase == HubClientPhase.Connecting) {
            return
        }
        val cache = HubPairingStore.load(appContext) ?: return
        update { it.copy(pinInput = cache.pin) }
        cachedBonjourNameForRestore = cache.bonjourServiceName
        isSilentReconnect = true
        wantsAutoConnectAfterBrowse = true
        startBrowsing()
    }

    fun startBrowsing() {
        tearDownBrowserOnly()
        if (!isSilentReconnect) {
            update { it.copy(lastError = null) }
        }
        discoveredByName.clear()
        update { it.copy(phase = HubClientPhase.Browsing, discoveredServiceNames = emptyList()) }

        val listener =
            object : NsdManager.DiscoveryListener {
                override fun onDiscoveryStarted(regType: String) {}

                override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                    if (!isSilentReconnect) {
                        update { it.copy(lastError = str(R.string.error_discovery_failed, errorCode)) }
                    }
                }

                override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}

                override fun onDiscoveryStopped(serviceType: String) {}

                override fun onServiceFound(serviceInfo: NsdServiceInfo) {
                    if (!serviceTypeMatches(serviceInfo)) return
                    discoveredByName[serviceInfo.serviceName] = serviceInfo
                    scope.launch(Dispatchers.Main) {
                        val names = discoveredByName.keys.sorted()
                        update { it.copy(discoveredServiceNames = names) }
                        tryAutoConnectIfNeeded()
                    }
                }

                override fun onServiceLost(serviceInfo: NsdServiceInfo) {
                    discoveredByName.remove(serviceInfo.serviceName)
                    scope.launch(Dispatchers.Main) {
                        val names = discoveredByName.keys.sorted()
                        update { it.copy(discoveredServiceNames = names) }
                    }
                }
            }
        browser = listener
        nsdManager.discoverServices(HubService.bonjourType, NsdManager.PROTOCOL_DNS_SD, listener)
    }

    fun connectUsingEnteredPin() {
        val pin = _state.value.pinInput.trim()
        if (pin.length != 6 || !pin.all { it.isDigit() }) {
            update { it.copy(lastError = str(R.string.error_pin_format)) }
            return
        }
        isSilentReconnect = false
        wantsAutoConnectAfterBrowse = true
        cachedBonjourNameForRestore = null
        startBrowsing()
    }

    fun userStopScanning() {
        tearDownBrowserOnly()
        wantsAutoConnectAfterBrowse = false
        isSilentReconnect = false
        if (_state.value.phase == HubClientPhase.Browsing || _state.value.phase == HubClientPhase.Connecting) {
            update { it.copy(phase = HubClientPhase.Idle) }
        }
    }

    fun disconnect() {
        cancelHeartbeat()
        tearDownBrowserOnly()
        closeSocket()
        update {
            it.copy(
                phase = HubClientPhase.Idle,
                serverDisconnectAlertMessage = null,
                serverReportsSubscriptionActive = false,
                codexMicroState = HubCodexMicroState.empty,
                localRecordingPhase = HubCodexRecordingState.Idle,
                dictationPartial = "",
            )
        }
        pendingBonjourName = null
        wantsAutoConnectAfterBrowse = false
        isSilentReconnect = false
        HubPairingStore.clear(appContext)
        cachedBonjourNameForRestore = null
    }

    fun returnToPairingAfterServerDisconnect() {
        cancelHeartbeat()
        tearDownBrowserOnly()
        closeSocket()
        update {
            it.copy(
                phase = HubClientPhase.Idle,
                serverDisconnectAlertMessage = null,
                serverReportsSubscriptionActive = false,
                codexMicroState = HubCodexMicroState.empty,
                localRecordingPhase = HubCodexRecordingState.Idle,
                dictationPartial = "",
            )
        }
        pendingBonjourName = null
        wantsAutoConnectAfterBrowse = false
        isSilentReconnect = false
    }

    fun setPinInput(raw: String) {
        val digits = raw.filter { it.isDigit() }.take(6)
        update { it.copy(pinInput = digits) }
    }

    fun tap(page: Int, slot: Int) {
        if (_state.value.phase != HubClientPhase.Paired) return
        sendEnvelope(
            HubWireEnvelope(
                op = HubWireOps.tap,
                page = page,
                slot = slot,
            ),
        )
    }

    fun reorder(page: Int, from: Int, to: Int) {
        if (_state.value.phase != HubClientPhase.Paired) return
        if (from !in 0..8 || to !in 0..8 || from == to) return
        sendEnvelope(
            HubWireEnvelope(
                op = HubWireOps.reorder,
                page = page,
                from = from,
                to = to,
            ),
        )
    }

    fun control(page: Int, slot: Int, command: String? = null, value: Double? = null) {
        if (_state.value.phase != HubClientPhase.Paired) return
        sendEnvelope(
            HubWireEnvelope(
                op = HubWireOps.control,
                page = page,
                slot = slot,
                command = command,
                value = value,
            ),
        )
    }

    fun gesture(command: HubGestureCommand) {
        if (_state.value.phase != HubClientPhase.Paired) return
        sendEnvelope(
            HubWireEnvelope(
                op = HubWireOps.gesture,
                command = command.rawValue,
            ),
        )
    }

    fun requestCodexMicroState() {
        sendCodexMicro(HubCodexMicroCommand(kind = HubCodexMicroCommand.KIND_REQUEST_STATE))
    }

    fun codexAgentTap(index: Int) {
        val now = System.currentTimeMillis()
        val last = lastAgentTapAt[index]
        if (last != null && now - last <= AGENT_DOUBLE_TAP_WINDOW_MS) {
            lastAgentTapAt.remove(index)
            sendCodexMicro(
                HubCodexMicroCommand(
                    kind = HubCodexMicroCommand.KIND_AGENT_DOUBLE_TAP,
                    agentIndex = index,
                    bringToFront = true,
                ),
            )
            return
        }
        lastAgentTapAt[index] = now
        sendCodexMicro(
            HubCodexMicroCommand(
                kind = HubCodexMicroCommand.KIND_AGENT_TAP,
                agentIndex = index,
                bringToFront = false,
            ),
        )
    }

    fun codexCommand(
        action: HubCodexMicroAction,
        handsFree: Boolean = false,
    ) {
        sendCodexMicro(
            HubCodexMicroCommand(
                kind = HubCodexMicroCommand.KIND_COMMAND,
                action = action,
                handsFree = handsFree,
            ),
        )
    }

    fun codexJoystick(direction: HubCodexJoystickDirection) {
        sendCodexMicro(
            HubCodexMicroCommand(
                kind = HubCodexMicroCommand.KIND_JOYSTICK,
                direction = direction,
            ),
        )
    }

    fun codexDialTurn(steps: Int) {
        sendCodexMicro(
            HubCodexMicroCommand(
                kind = HubCodexMicroCommand.KIND_DIAL_TURN,
                steps = steps,
            ),
        )
    }

    fun codexDialPress() {
        sendCodexMicro(HubCodexMicroCommand(kind = HubCodexMicroCommand.KIND_DIAL_PRESS))
    }

    fun codexDialLongPress() {
        sendCodexMicro(HubCodexMicroCommand(kind = HubCodexMicroCommand.KIND_DIAL_LONG_PRESS))
    }

    fun codexDialCancel() {
        sendCodexMicro(HubCodexMicroCommand(kind = HubCodexMicroCommand.KIND_DIAL_CANCEL))
    }

    fun codexLayerCycle() {
        sendCodexMicro(HubCodexMicroCommand(kind = HubCodexMicroCommand.KIND_LAYER_CYCLE))
    }

    fun codexPushToTalkEnd() {
        sendCodexMicro(HubCodexMicroCommand(kind = HubCodexMicroCommand.KIND_PUSH_TO_TALK_END))
    }

    fun pttStart() {
        val phase = _state.value.localRecordingPhase
        if (phase == HubCodexRecordingState.Recording && dictation.isRecording) return
        update {
            it.copy(
                lastError = null,
                localRecordingPhase = HubCodexRecordingState.Recording,
                codexMicroState = it.codexMicroState.copy(lastControlError = null),
                dictationPartial = "",
            )
        }
        sendCodexMicro(
            HubCodexMicroCommand(
                kind = HubCodexMicroCommand.KIND_COMMAND,
                action = HubCodexMicroAction.PushToTalk,
            ),
        )
        scope.launch {
            try {
                dictation.start()
                while (_state.value.localRecordingPhase == HubCodexRecordingState.Recording) {
                    update { s -> s.copy(dictationPartial = dictation.partialTranscript) }
                    delay(120)
                }
            } catch (e: HubAndroidDictationController.DictationException) {
                update {
                    it.copy(
                        localRecordingPhase = HubCodexRecordingState.Idle,
                        codexMicroState =
                            it.codexMicroState.copy(
                                lastControlError = dictation.errorMessage(e.error),
                            ),
                    )
                }
                codexPushToTalkEnd()
            } catch (e: Exception) {
                update {
                    it.copy(
                        localRecordingPhase = HubCodexRecordingState.Idle,
                        codexMicroState =
                            it.codexMicroState.copy(
                                lastControlError =
                                    e.message
                                        ?: dictation.errorMessage(
                                            HubAndroidDictationController.DictationError.SpeechUnavailable,
                                        ),
                            ),
                    )
                }
                codexPushToTalkEnd()
            }
        }
    }

    fun pttStopAndSend() {
        if (_state.value.localRecordingPhase != HubCodexRecordingState.Recording) return
        update { it.copy(localRecordingPhase = HubCodexRecordingState.Processing) }
        scope.launch {
            val text = dictation.stopAndFinalize()
            if (text.isEmpty()) {
                update {
                    it.copy(
                        localRecordingPhase = HubCodexRecordingState.Idle,
                        dictationPartial = "",
                        codexMicroState =
                            it.codexMicroState.copy(
                                lastControlError =
                                    dictation.errorMessage(
                                        HubAndroidDictationController.DictationError.EmptyTranscript,
                                    ),
                            ),
                    )
                }
                codexPushToTalkEnd()
                return@launch
            }
            sendCodexMicro(
                HubCodexMicroCommand(
                    kind = HubCodexMicroCommand.KIND_INSERT_TEXT,
                    text = text,
                ),
            )
            update {
                it.copy(
                    localRecordingPhase = HubCodexRecordingState.Idle,
                    dictationPartial = "",
                )
            }
        }
    }

    fun pttCancel() {
        val wasActive = _state.value.localRecordingPhase != HubCodexRecordingState.Idle
        dictation.cancel()
        update {
            it.copy(
                localRecordingPhase = HubCodexRecordingState.Idle,
                dictationPartial = "",
            )
        }
        if (wasActive) {
            codexPushToTalkEnd()
        }
    }

    fun codexSetMapping(mapping: HubCodexMicroMapping) {
        sendCodexMicro(
            HubCodexMicroCommand(
                kind = HubCodexMicroCommand.KIND_SET_MAPPING,
                mapping = mapping,
            ),
        )
    }

    fun codexEnableTextAutomationAndRetry(action: HubCodexMicroAction?) {
        val mapping = _state.value.codexMicroState.mapping.copy(allowsTextAutomation = true)
        codexSetMapping(mapping)
        update {
            it.copy(
                lastError = null,
                codexMicroState =
                    it.codexMicroState.copy(
                        mapping = mapping,
                        lastControlError = null,
                    ),
            )
        }
        if (action != null) {
            scope.launch {
                delay(350)
                codexCommand(action)
            }
        }
    }

    fun codexDismissControlHint() {
        update {
            it.copy(
                lastError = null,
                codexMicroState = it.codexMicroState.copy(lastControlError = null),
            )
        }
    }

    fun codexSetTarget(target: HubCodexControlTarget) {
        sendCodexMicro(
            HubCodexMicroCommand(
                kind = HubCodexMicroCommand.KIND_SET_TARGET,
                target = target,
            ),
        )
    }

    fun codexOpenAccessibilitySettings() {
        sendCodexMicro(HubCodexMicroCommand(kind = HubCodexMicroCommand.KIND_OPEN_ACCESSIBILITY_SETTINGS))
    }

    private fun sendCodexMicro(command: HubCodexMicroCommand) {
        if (_state.value.phase != HubClientPhase.Paired) return
        val message = HubCodexMicroWire.encodeCommand(command) ?: return
        sendEnvelope(
            HubWireEnvelope(
                op = HubWireOps.codexMicro,
                message = message,
            ),
        )
    }

    fun onDestroy() {
        pttCancel()
        cancelHeartbeat()
        tearDownBrowserOnly()
        closeSocket()
    }

    private fun tearDownBrowserOnly() {
        val b = browser ?: return
        try {
            nsdManager.stopServiceDiscovery(b)
        } catch (_: Exception) {
        }
        browser = null
    }

    private fun closeSocket() {
        readJob?.cancel()
        readJob = null
        try {
            reader?.close()
        } catch (_: Exception) {
        }
        try {
            writer?.close()
        } catch (_: Exception) {
        }
        try {
            socket?.close()
        } catch (_: Exception) {
        }
        reader = null
        writer = null
        socket = null
    }

    private fun serviceTypeMatches(info: NsdServiceInfo): Boolean {
        val t = info.serviceType.trimEnd('.').lowercase()
        return t == "_treelethub._tcp"
    }

    private fun tryAutoConnectIfNeeded() {
        if (!wantsAutoConnectAfterBrowse || _state.value.phase != HubClientPhase.Browsing) return
        val pin = _state.value.pinInput.trim()
        if (pin.length != 6 || !pin.all { it.isDigit() }) return
        if (discoveredByName.isEmpty()) return

        val sorted = discoveredByName.keys.sorted()
        val cached = cachedBonjourNameForRestore
        val pickName: String =
            when {
                cached != null && sorted.contains(cached) -> cached
                cached != null -> return
                else -> sorted.first()
            }

        val info = discoveredByName[pickName] ?: return
        wantsAutoConnectAfterBrowse = false
        resolveAndConnect(info, pin)
    }

    private fun resolveAndConnect(serviceInfo: NsdServiceInfo, pin: String) {
        tearDownBrowserOnly()
        update { it.copy(phase = HubClientPhase.Connecting, lastError = null) }
        pendingBonjourName = serviceInfo.serviceName

        val listener =
            object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                    scope.launch(Dispatchers.Main) {
                        if (!isSilentReconnect) {
                            update { it.copy(lastError = str(R.string.error_resolve_mac_failed, errorCode), phase = HubClientPhase.Idle) }
                        } else {
                            update { it.copy(phase = HubClientPhase.Idle) }
                        }
                        endSilentIfNeeded()
                    }
                }

                override fun onServiceResolved(resolved: NsdServiceInfo) {
                    scope.launch(Dispatchers.IO) {
                        openTcpAndPair(resolved, pin)
                    }
                }
            }
        resolveListener = listener
        try {
            nsdManager.resolveService(serviceInfo, listener)
        } catch (e: Exception) {
            scope.launch(Dispatchers.Main) {
                if (!isSilentReconnect) {
                    update { it.copy(lastError = e.message ?: str(R.string.error_resolve_failed), phase = HubClientPhase.Idle) }
                } else {
                    update { it.copy(phase = HubClientPhase.Idle) }
                }
                endSilentIfNeeded()
            }
        }
    }

    private suspend fun openTcpAndPair(resolved: NsdServiceInfo, pin: String) {
        val host = resolved.host
        val port = resolved.port
        if (host == null || port <= 0) {
            withContext(Dispatchers.Main) {
                if (!isSilentReconnect) {
                    update { it.copy(lastError = str(R.string.error_invalid_port), phase = HubClientPhase.Idle) }
                } else {
                    update { it.copy(phase = HubClientPhase.Idle) }
                }
                endSilentIfNeeded()
            }
            return
        }

        try {
            val s = Socket()
            s.tcpNoDelay = true
            s.connect(InetSocketAddress(host, port), 12_000)
            val r = BufferedReader(InputStreamReader(s.getInputStream(), Charsets.UTF_8))
            val w = BufferedWriter(OutputStreamWriter(s.getOutputStream(), Charsets.UTF_8))
            socket = s
            reader = r
            writer = w
            sendPair(pin)
            startReadLoop()
        } catch (e: Exception) {
            withContext(Dispatchers.Main) {
                if (!isSilentReconnect) {
                    update { it.copy(lastError = e.message ?: str(R.string.error_connect_failed), phase = HubClientPhase.Idle) }
                } else {
                    update { it.copy(phase = HubClientPhase.Idle) }
                }
                endSilentIfNeeded()
            }
            closeSocket()
        }
    }

    private fun sendPair(pin: String) {
        val prefs = appContext.getSharedPreferences("treelethub.prefs", Context.MODE_PRIVATE)
        val customName = prefs.getString(customDeviceNameKey, null)?.trim().orEmpty()
        val deviceName =
            if (customName.isNotEmpty()) {
                customName.take(40)
            } else {
                Build.MODEL ?: "Android"
            }
        val deviceId =
            Settings.Secure.getString(appContext.contentResolver, Settings.Secure.ANDROID_ID)
                ?: "${Build.MANUFACTURER}-${Build.MODEL}"
        sendEnvelope(
            HubWireEnvelope(
                op = HubWireOps.pair,
                pin = pin,
                deviceName = deviceName,
                deviceId = deviceId,
            ),
        )
    }

    private fun sendEnvelope(env: HubWireEnvelope) {
        val w = writer ?: return
        scope.launch(Dispatchers.IO) {
            writeMutex.withLock {
                try {
                    w.write(HubWireCodec.encodeLine(env))
                    w.flush()
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun startReadLoop() {
        readJob?.cancel()
        val r = reader ?: return
        readJob =
            scope.launch(Dispatchers.IO) {
                while (isActive) {
                    val line =
                        try {
                            r.readLine()
                        } catch (_: Exception) {
                            null
                        }
                    if (line == null) {
                        withContext(Dispatchers.Main) {
                            if (_state.value.phase == HubClientPhase.Paired) {
                                scheduleSilentReconnectAfterReceiveLoss()
                            } else {
                                update { it.copy(phase = HubClientPhase.Idle) }
                                endSilentIfNeeded()
                            }
                        }
                        break
                    }
                    if (line.isBlank()) continue
                    withContext(Dispatchers.Main) {
                        handleLine(line)
                    }
                }
            }
    }

    private fun scheduleSilentReconnectAfterReceiveLoss() {
        val now = System.currentTimeMillis()
        if (now - lastSilentReceiveReconnectAt.get() < 1200) return
        lastSilentReceiveReconnectAt.set(now)

        cancelHeartbeat()
        update { it.copy(lastError = null) }
        tearDownBrowserOnly()
        closeSocket()
        pendingBonjourName = null
        update { it.copy(phase = HubClientPhase.Idle) }
        isSilentReconnect = true
        wantsAutoConnectAfterBrowse = true
        cachedBonjourNameForRestore = HubPairingStore.load(appContext)?.bonjourServiceName
        startBrowsing()
    }

    private fun cancelHeartbeat() {
        heartbeatJob?.cancel()
        heartbeatJob = null
    }

    private fun startLayoutPullHeartbeat() {
        cancelHeartbeat()
        heartbeatJob =
            scope.launch {
                while (isActive) {
                    delay(8_000)
                    if (_state.value.phase != HubClientPhase.Paired) break
                    sendRequestLayoutToMac()
                }
            }
    }

    private fun sendRequestLayoutToMac() {
        if (_state.value.phase != HubClientPhase.Paired) return
        sendEnvelope(HubWireEnvelope(op = HubWireOps.requestLayout))
    }

    private fun handleLine(line: String) {
        val env =
            try {
                HubWireCodec.decodeLine(line)
            } catch (_: Exception) {
                if (!isSilentReconnect) {
                    update { it.copy(lastError = str(R.string.error_parse_message)) }
                }
                return
            }
        when (env.op) {
            HubWireOps.pairResult -> {
                if (env.ok == true) {
                    update { it.copy(phase = HubClientPhase.Paired) }
                    savePairingToDisk()
                    pendingBonjourName = null
                    endSilentIfNeeded()
                    startLayoutPullHeartbeat()
                } else {
                    if (!isSilentReconnect) {
                        update { it.copy(lastError = str(R.string.error_wrong_pin)) }
                    }
                    update { it.copy(phase = HubClientPhase.Idle) }
                    closeSocket()
                    cancelHeartbeat()
                    endSilentIfNeeded()
                }
            }
            HubWireOps.layout -> {
                val sub = env.subscriptionActive ?: false
                val pages =
                    when {
                        !env.pages.isNullOrEmpty() -> env.pages.normalizedPages()
                        env.slots != null && env.slots.size == 9 ->
                            listOf(
                                HubPageConfig(id = 0, title = "Apps", slots = env.slots).normalized(),
                            )
                        else -> _state.value.pages
                    }
                update {
                    it.copy(
                        serverReportsSubscriptionActive = sub,
                        pages = pages,
                        layoutApplyEpoch = it.layoutApplyEpoch + 1,
                    )
                }
            }
            HubWireOps.error -> {
                val m = env.message.orEmpty()
                if (_state.value.phase == HubClientPhase.Paired &&
                    (m == "未知操作" || m.startsWith("unsupportedOp:"))
                ) {
                    return
                }
                if (!isSilentReconnect) {
                    update { it.copy(lastError = env.message ?: str(R.string.error_unknown)) }
                }
            }
            HubWireOps.disconnect -> {
                update {
                    it.copy(
                        serverDisconnectAlertMessage = env.message,
                    )
                }
                cancelHeartbeat()
                tearDownBrowserOnly()
                closeSocket()
                update {
                    it.copy(
                        phase = HubClientPhase.Idle,
                        serverReportsSubscriptionActive = false,
                        codexMicroState = HubCodexMicroState.empty,
                        localRecordingPhase = HubCodexRecordingState.Idle,
                        dictationPartial = "",
                    )
                }
                pendingBonjourName = null
                wantsAutoConnectAfterBrowse = false
                isSilentReconnect = false
            }
            HubWireOps.codexMicroState -> {
                val decoded = HubCodexMicroWire.decodeState(env.message)
                if (decoded != null) {
                    update { it.copy(codexMicroState = decoded) }
                } else {
                    val agents = env.slots?.mapIndexed { index, slot ->
                        HubCodexAgentSlot(
                            id = index,
                            title = slot.displayName,
                        )
                    }
                    if (agents != null) {
                        update {
                            it.copy(
                                codexMicroState =
                                    it.codexMicroState.copy(
                                        agents = agents,
                                    ),
                            )
                        }
                    }
                }
            }
        }
    }

    private fun savePairingToDisk() {
        val pin = _state.value.pinInput.trim()
        if (pin.length != 6) return
        val cache = HubPairingCache(pin = pin, bonjourServiceName = pendingBonjourName)
        HubPairingStore.save(appContext, cache)
    }

    private fun endSilentIfNeeded() {
        if (isSilentReconnect) {
            isSilentReconnect = false
        }
    }
}
