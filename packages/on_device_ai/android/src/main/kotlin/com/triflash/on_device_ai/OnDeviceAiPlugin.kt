package com.triflash.on_device_ai

import android.os.Build
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.ModelPreference
import com.google.mlkit.genai.prompt.ModelReleaseStage
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import com.google.mlkit.genai.prompt.generationConfig
import com.google.mlkit.genai.prompt.modelConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import android.util.Log
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class OnDeviceAiPlugin : FlutterPlugin, MethodCallHandler {
    companion object {
        private const val TAG = "OnDeviceAi"
    }
    private lateinit var channel: MethodChannel
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var generativeModel: GenerativeModel? = null
    private var generateJob: Job? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.triflash/on_device_ai")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        generateJob?.cancel()
        scope.cancel()
        generativeModel?.close()
        generativeModel = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getAvailability" -> scope.launch {
                try {
                    result.success(getAvailabilityMap())
                } catch (error: Exception) {
                    result.error("availability_failed", error.message, null)
                }
            }

            "getLimits" -> scope.launch {
                try {
                    result.success(getLimitsMap())
                } catch (error: Exception) {
                    result.error("limits_failed", error.message, null)
                }
            }

            "downloadModel" -> scope.launch {
                try {
                    downloadModel()
                    result.success(null)
                } catch (error: Exception) {
                    result.error("download_failed", error.message, null)
                }
            }

            "generate" -> {
                val prompt = call.argument<String>("prompt")
                if (prompt.isNullOrBlank()) {
                    result.error("invalid_args", "prompt is required", null)
                    return
                }
                val systemInstruction = call.argument<String>("systemInstruction")
                val maxOutputTokens = call.argument<Int>("maxOutputTokens") ?: 4096
                generateJob?.cancel()
                generateJob = scope.launch {
                    try {
                        val text = generate(prompt, systemInstruction, maxOutputTokens)
                        result.success(mapOf("text" to text))
                    } catch (error: Exception) {
                        result.error("generate_failed", error.message, null)
                    }
                }
            }

            "cancel" -> {
                generateJob?.cancel()
                generateJob = null
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Z Fold 8 / Nano 4 devices expose the model on the PREVIEW channel first.
     * Fall back through preferences and finally to STABLE (default Nano 2/3).
     */
    private suspend fun resolveModel(): ResolvedModel {
        generativeModel?.let { return ResolvedModel(it, cached = true) }

        return withContext(Dispatchers.Default) {
            val candidates =
                listOf(
                    CandidateConfig(ModelReleaseStage.PREVIEW, ModelPreference.FULL),
                    CandidateConfig(ModelReleaseStage.PREVIEW, ModelPreference.FAST),
                    CandidateConfig(ModelReleaseStage.STABLE, ModelPreference.FULL),
                    CandidateConfig(ModelReleaseStage.STABLE, ModelPreference.FAST),
                )

            var downloadable: GenerativeModel? = null
            var downloading: GenerativeModel? = null

            for (candidate in candidates) {
                val client = clientFor(candidate)
                val status = client.checkStatus()
                Log.i(
                    TAG,
                    "checkStatus stage=${candidate.releaseStage} " +
                        "pref=${candidate.preference} status=$status",
                )
                when (status) {
                    FeatureStatus.AVAILABLE -> {
                        generativeModel = client
                        return@withContext ResolvedModel(client)
                    }
                    FeatureStatus.DOWNLOADABLE -> {
                        if (downloadable == null) downloadable = client else client.close()
                    }
                    FeatureStatus.DOWNLOADING -> {
                        if (downloading == null) downloading = client else client.close()
                    }
                    else -> client.close()
                }
            }

            val fallback = downloadable ?: downloading ?: Generation.getClient()
            Log.w(
                TAG,
                "No AVAILABLE model. Using fallback status=${fallback.checkStatus()}",
            )
            generativeModel = fallback
            ResolvedModel(fallback)
        }
    }

    private fun clientFor(candidate: CandidateConfig): GenerativeModel =
        Generation.getClient(
            generationConfig {
                modelConfig =
                    modelConfig {
                        releaseStage = candidate.releaseStage
                        preference = candidate.preference
                    }
            },
        )

    private suspend fun model(): GenerativeModel = resolveModel().model

    private suspend fun getAvailabilityMap(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < 26) {
            return unsupported("osVersionUnsupported", "Android API 26+ is required.")
        }
        return try {
            when (model().checkStatus()) {
                FeatureStatus.AVAILABLE -> readyMap()
                FeatureStatus.DOWNLOADABLE ->
                    mapOf(
                        "status" to "downloadRequired",
                        "reason" to "modelDownloadRequired",
                        "message" to
                            "Gemini Nano can be downloaded on this device. Tap download to continue.",
                        "maxInputTokens" to 3500,
                        "maxOutputTokens" to 4096,
                    )

                FeatureStatus.DOWNLOADING ->
                    mapOf(
                        "status" to "downloading",
                        "reason" to "modelNotReady",
                        "message" to "Gemini Nano is downloading.",
                        "maxInputTokens" to 3500,
                        "maxOutputTokens" to 4096,
                    )

                FeatureStatus.UNAVAILABLE ->
                    unsupported(
                        "deviceNotEligible",
                        "Gemini Nano is not available for third-party apps on this device yet " +
                            "(Prompt API allowlist / AICore config). Cloud AI providers still work.",
                    )

                else -> temporarilyUnavailable("Gemini Nano status is unknown.")
            }
        } catch (error: GenAiException) {
            temporarilyUnavailable(error.message ?: error.toString())
        } catch (error: Exception) {
            temporarilyUnavailable(error.message ?: error.toString())
        }
    }

    private suspend fun getLimitsMap(): Map<String, Int> {
        val defaults = mapOf("maxInputTokens" to 3500, "maxOutputTokens" to 4096)
        if (Build.VERSION.SDK_INT < 26) return defaults
        return try {
            val tokenLimit = model().getTokenLimit()
            mapOf(
                "maxInputTokens" to minOf(tokenLimit, 3500),
                "maxOutputTokens" to 4096,
            )
        } catch (_: Exception) {
            defaults
        }
    }

    private suspend fun downloadModel() {
        if (Build.VERSION.SDK_INT < 26) {
            throw IllegalStateException("Android API 26+ is required.")
        }
        val model = model()
        when (model.checkStatus()) {
            FeatureStatus.AVAILABLE -> return
            FeatureStatus.DOWNLOADABLE, FeatureStatus.DOWNLOADING -> {
                model.download().collect { status ->
                    when (status) {
                        is DownloadStatus.DownloadFailed -> throw status.e
                        DownloadStatus.DownloadCompleted -> return@collect
                        else -> Unit
                    }
                }
            }

            FeatureStatus.UNAVAILABLE ->
                throw IllegalStateException(
                    "Gemini Nano is not available for third-party apps on this device yet.",
                )

            else -> throw IllegalStateException("Gemini Nano is not ready.")
        }
    }

    private suspend fun generate(
        prompt: String,
        systemInstruction: String?,
        maxOutputTokens: Int,
    ): String =
        withContext(Dispatchers.Default) {
            val model = model()
            when (model.checkStatus()) {
                FeatureStatus.AVAILABLE -> Unit
                FeatureStatus.DOWNLOADABLE ->
                    throw IllegalStateException("Gemini Nano must be downloaded first.")
                FeatureStatus.DOWNLOADING ->
                    throw IllegalStateException("Gemini Nano is still downloading.")
                FeatureStatus.UNAVAILABLE ->
                    throw IllegalStateException(
                        "Gemini Nano is not available for third-party apps on this device yet.",
                    )
                else -> throw IllegalStateException("Gemini Nano is not ready.")
            }

            val mergedPrompt =
                if (systemInstruction.isNullOrBlank()) {
                    prompt
                } else {
                    "$systemInstruction\n\n$prompt"
                }
            val cappedTokens = maxOutputTokens.coerceIn(1, 4096)
            val response =
                model.generateContent(
                    generateContentRequest(TextPart(mergedPrompt)) {
                        this.maxOutputTokens = cappedTokens
                    },
                )

            val text = response.candidates.firstOrNull()?.text?.trim().orEmpty()
            if (text.isEmpty()) {
                throw IllegalStateException("Gemini Nano returned an empty response.")
            }
            text
        }

    private fun readyMap(): Map<String, Any?> =
        mapOf(
            "status" to "ready",
            "reason" to "unknown",
            "maxInputTokens" to 3500,
            "maxOutputTokens" to 4096,
        )

    private fun unsupported(reason: String, message: String): Map<String, Any?> =
        mapOf(
            "status" to "unsupported",
            "reason" to reason,
            "message" to message,
            "maxInputTokens" to 3500,
            "maxOutputTokens" to 4096,
        )

    private fun temporarilyUnavailable(message: String): Map<String, Any?> =
        mapOf(
            "status" to "temporarilyUnavailable",
            "reason" to "featureUnavailable",
            "message" to message,
            "maxInputTokens" to 3500,
            "maxOutputTokens" to 4096,
        )

    private data class CandidateConfig(
        val releaseStage: Int,
        val preference: Int,
    )

    private data class ResolvedModel(
        val model: GenerativeModel,
        val cached: Boolean = false,
    )
}
