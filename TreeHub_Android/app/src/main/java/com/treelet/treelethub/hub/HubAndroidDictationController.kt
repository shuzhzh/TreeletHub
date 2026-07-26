package com.treelet.treelethub.hub

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import com.treelet.treelethub.R
import com.treelet.treelethub.locale.HubAndroidUILanguage
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale
import java.util.concurrent.atomic.AtomicReference
import kotlin.coroutines.resume

/**
 * On-device speech recognition for PTT: mic → transcript → Mac insertText.
 */
class HubAndroidDictationController(
    private val appContext: Context,
) {
    enum class DictationError {
        MicrophoneDenied,
        SpeechUnavailable,
        EmptyTranscript,
    }

    @Volatile
    var partialTranscript: String = ""
        private set

    @Volatile
    var isRecording: Boolean = false
        private set

    private val mainHandler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var latestTranscript = ""
    private val finalWaiter = AtomicReference<((String) -> Unit)?>(null)

    private fun localized(): Context = HubAndroidUILanguage.wrapContext(appContext)

    fun errorMessage(error: DictationError): String {
        val ctx = localized()
        return when (error) {
            DictationError.MicrophoneDenied -> ctx.getString(R.string.codex_mic_denied)
            DictationError.SpeechUnavailable -> ctx.getString(R.string.codex_speech_unavailable)
            DictationError.EmptyTranscript -> ctx.getString(R.string.codex_empty_transcript)
        }
    }

    suspend fun start() {
        cancel()
        if (!SpeechRecognizer.isRecognitionAvailable(appContext)) {
            throw DictationException(DictationError.SpeechUnavailable)
        }

        latestTranscript = ""
        partialTranscript = ""
        val started =
            suspendCancellableCoroutine { cont ->
                mainHandler.post {
                    try {
                        val r = SpeechRecognizer.createSpeechRecognizer(appContext)
                        recognizer = r
                        r.setRecognitionListener(
                            object : RecognitionListener {
                                override fun onReadyForSpeech(params: Bundle?) {
                                    isRecording = true
                                    if (cont.isActive) cont.resume(true)
                                }

                                override fun onBeginningOfSpeech() {}

                                override fun onRmsChanged(rmsdB: Float) {}

                                override fun onBufferReceived(buffer: ByteArray?) {}

                                override fun onEndOfSpeech() {}

                                override fun onError(error: Int) {
                                    isRecording = false
                                    finishWaiting()
                                    if (cont.isActive) {
                                        cont.resume(false)
                                    }
                                }

                                override fun onResults(results: Bundle?) {
                                    val texts = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                                    val best = texts?.firstOrNull().orEmpty()
                                    if (best.isNotBlank()) {
                                        latestTranscript = best
                                        partialTranscript = best
                                    }
                                    isRecording = false
                                    finishWaiting()
                                }

                                override fun onPartialResults(partialResults: Bundle?) {
                                    val texts =
                                        partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                                    val best = texts?.firstOrNull().orEmpty()
                                    if (best.isNotBlank()) {
                                        latestTranscript = best
                                        partialTranscript = best
                                    }
                                }

                                override fun onEvent(
                                    eventType: Int,
                                    params: Bundle?,
                                ) {}
                            },
                        )

                        val intent =
                            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                                putExtra(
                                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                                )
                                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                                putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
                                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                            }
                        r.startListening(intent)
                    } catch (_: Exception) {
                        if (cont.isActive) cont.resume(false)
                    }
                }
            }

        if (!started && !isRecording) {
            throw DictationException(DictationError.SpeechUnavailable)
        }
    }

    suspend fun stopAndFinalize(timeoutMs: Long = 1_800L): String {
        if (!isRecording && recognizer == null) {
            return latestTranscript.trim()
        }

        mainHandler.post {
            try {
                recognizer?.stopListening()
            } catch (_: Exception) {
            }
        }
        isRecording = false

        val text =
            withTimeoutOrNull(timeoutMs) {
                suspendCancellableCoroutine { cont ->
                    finalWaiter.set { value ->
                        if (cont.isActive) cont.resume(value)
                    }
                    // If results already arrived, finish immediately.
                    if (latestTranscript.isNotBlank() && recognizer == null) {
                        finishWaiting()
                    }
                }
            } ?: latestTranscript

        destroyRecognizer()
        return text.trim()
    }

    fun cancel() {
        mainHandler.post {
            try {
                recognizer?.cancel()
            } catch (_: Exception) {
            }
            destroyRecognizer()
        }
        isRecording = false
        latestTranscript = ""
        partialTranscript = ""
        finishWaiting()
    }

    private fun destroyRecognizer() {
        try {
            recognizer?.destroy()
        } catch (_: Exception) {
        }
        recognizer = null
    }

    private fun finishWaiting() {
        val waiter = finalWaiter.getAndSet(null)
        waiter?.invoke(latestTranscript)
    }

    class DictationException(
        val error: DictationError,
    ) : Exception()
}
