package com.triflash.on_device_ai

import android.os.Build
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.GenAiException
import com.google.mlkit.genai.prompt.GenerateContentRequest
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.ModelPreference
import com.google.mlkit.genai.prompt.ModelReleaseStage
import com.google.mlkit.genai.prompt.SystemInstruction
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.prompt.generateContentRequest
import com.google.mlkit.genai.prompt.generateTypedContentRequest
import com.google.mlkit.genai.prompt.generationConfig
import com.google.mlkit.genai.prompt.modelConfig
import com.google.mlkit.genai.schema.annotations.Generable
import com.google.mlkit.genai.schema.annotations.Guide
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

@Generable("A concise bilingual example sentence")
data class BilingualSentenceOutput(
    @Guide(description = "Sentence in the source language") val source: String,
    @Guide(description = "Learner-friendly pronunciation") val transcription: String,
    @Guide(description = "Faithful translated sentence") val translation: String,
)

@Generable("The opening segment of a bilingual passage")
data class PassageStartOutput(
    @Guide(description = "Short title in the source language") val title: String,
    @Guide(description = "Faithful translation of the title") val titleTranslation: String,
    @Guide(description = "Short theme used to continue the passage") val theme: String,
    @Guide(description = "Passage segment in the source language") val source: String,
    @Guide(description = "Faithful translation of the passage segment") val translation: String,
)

@Generable("A continuation segment of a bilingual passage")
data class PassageSegmentOutput(
    @Guide(description = "Passage segment in the source language") val source: String,
    @Guide(description = "Faithful translation of the passage segment") val translation: String,
)

@Generable("A bilingual sentence pair")
data class QuizPairOutput(
    @Guide(description = "Sentence in the source language") val source: String,
    @Guide(description = "Faithful translated sentence") val translation: String,
)

@Generable("Exactly five bilingual sentence pairs")
data class QuizBatchOutput(
    @Guide(description = "Five unique bilingual pairs", minItems = 5, maxItems = 5)
    val sentences: List<QuizPairOutput>,
)

@Generable("Assessment of a learner translation")
data class TranslationCheckOutput(
    @Guide(description = "Whether the answer preserves the expected meaning") val correct: Boolean,
    @Guide(description = "Short, helpful learner feedback") val feedback: String,
    @Guide(description = "Correct answer, or an empty string when unnecessary") val correctedAnswer: String,
    @Guide(description = "Learner-friendly pronunciation, or an empty string") val transcription: String,
)

class OnDeviceAiPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var downloadChannel: EventChannel
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var generativeModel: GenerativeModel? = null
    private var generateJob: Job? = null
    private var downloadSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(binding.binaryMessenger, "com.triflash/on_device_ai")
        methodChannel.setMethodCallHandler(this)
        downloadChannel = EventChannel(binding.binaryMessenger, "com.triflash/on_device_ai/download")
        downloadChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        downloadChannel.setStreamHandler(null)
        generateJob?.cancel()
        scope.cancel()
        generativeModel?.close()
        generativeModel = null
        downloadSink = null
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        downloadSink = events
    }

    override fun onCancel(arguments: Any?) {
        downloadSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getAvailability" -> launchResult(result) { getAvailabilityMap() }
            "getLimits" -> launchResult(result) { getLimitsMap() }
            "warmup" -> launchResult(result) {
                model().warmup()
                null
            }
            "supportsLanguages" -> result.success(mapOf("supported" to true))
            "countTokens" -> launchResult(result) {
                val args = requireArguments(call)
                val prompt = requirePrompt(args)
                val instruction = args["systemInstruction"] as? String
                val schema = args["responseSchema"] as? String
                mapOf("count" to countTokens(prompt, instruction, schema))
            }
            "downloadModel" -> launchResult(result) {
                downloadModel()
                null
            }
            "generate" -> startGeneration(call, result)
            "cancel" -> {
                generateJob?.cancel()
                generateJob = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startGeneration(call: MethodCall, result: MethodChannel.Result) {
        val args = try {
            requireArguments(call)
        } catch (error: Exception) {
            result.error("invalid_args", error.message, null)
            return
        }
        val prompt = try {
            requirePrompt(args)
        } catch (error: Exception) {
            result.error("invalid_args", error.message, null)
            return
        }
        val instruction = args["systemInstruction"] as? String
        val maxOutputTokens = args["maxOutputTokens"] as? Int ?: 4096
        val schema = args["responseSchema"] as? String
        generateJob?.cancel()
        generateJob = scope.launch {
            try {
                val text = generate(prompt, instruction, maxOutputTokens, schema)
                result.success(mapOf("text" to text))
            } catch (error: CancellationException) {
                result.nativeError("cancelled", "Generation cancelled.")
            } catch (error: Exception) {
                result.nativeError(errorCode(error), error.message ?: "On-device generation failed.")
            }
        }
    }

    private fun launchResult(
        result: MethodChannel.Result,
        block: suspend () -> Any?,
    ) {
        scope.launch {
            try {
                result.success(block())
            } catch (error: CancellationException) {
                result.nativeError("cancelled", "Operation cancelled.")
            } catch (error: Exception) {
                result.nativeError(errorCode(error), error.message ?: "On-device AI failed.")
            }
        }
    }

    private suspend fun resolveModel(): GenerativeModel {
        generativeModel?.let { return it }
        return withContext(Dispatchers.Default) {
            val candidates =
                listOf(
                    CandidateConfig(ModelPreference.FULL),
                    CandidateConfig(ModelPreference.FAST),
                )
            var fallback: GenerativeModel? = null
            for (candidate in candidates) {
                val client = clientFor(candidate)
                when (client.checkStatus()) {
                    FeatureStatus.AVAILABLE -> {
                        fallback?.close()
                        generativeModel = client
                        return@withContext client
                    }
                    FeatureStatus.DOWNLOADABLE, FeatureStatus.DOWNLOADING -> {
                        if (fallback == null) fallback = client else client.close()
                    }
                    else -> client.close()
                }
            }
            val resolved = fallback ?: Generation.getClient()
            generativeModel = resolved
            resolved
        }
    }

    private fun clientFor(candidate: CandidateConfig): GenerativeModel =
        Generation.getClient(
            generationConfig {
                modelConfig =
                    modelConfig {
                        releaseStage = ModelReleaseStage.STABLE
                        preference = candidate.preference
                    }
            },
        )

    private suspend fun model(): GenerativeModel = resolveModel()

    private suspend fun getAvailabilityMap(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < 26) {
            return unsupported("osVersionUnsupported", "Android API 26+ is required.")
        }
        return try {
            val model = model()
            val common = capabilityMap(model)
            when (model.checkStatus()) {
                FeatureStatus.AVAILABLE ->
                    common +
                        mapOf(
                            "status" to "ready",
                            "isEligible" to true,
                            "reason" to "unknown",
                        )
                FeatureStatus.DOWNLOADABLE ->
                    common +
                        mapOf(
                            "status" to "downloadRequired",
                            "isEligible" to true,
                            "reason" to "modelDownloadRequired",
                            "message" to "Gemini Nano must be downloaded before it can be used offline.",
                        )
                FeatureStatus.DOWNLOADING ->
                    common +
                        mapOf(
                            "status" to "downloading",
                            "isEligible" to true,
                            "reason" to "modelNotReady",
                            "message" to "Gemini Nano is downloading.",
                        )
                else -> unsupported(
                    "deviceNotEligible",
                    "On-device Gemini Nano is not available on this device.",
                )
            }
        } catch (error: GenAiException) {
            availabilityForException(error)
        }
    }

    private suspend fun capabilityMap(model: GenerativeModel): Map<String, Any?> {
        val limit = runCatching { model.getTokenLimit() }.getOrDefault(4096)
        return mapOf(
            "providerName" to "Gemini Nano",
            "modelName" to runCatching { model.getBaseModelName() }.getOrNull(),
            "totalTokenLimit" to limit,
            "supportsStructuredOutput" to
                runCatching { model.isStructuredOutputFeatureAvailable() }.getOrDefault(false),
            "supportsSystemInstructions" to
                runCatching { model.isSystemPromptAvailable() }.getOrDefault(false),
            "supportsTokenCounting" to true,
            "supportsWarmup" to true,
        )
    }

    private suspend fun getLimitsMap(): Map<String, Int> =
        mapOf("totalTokenLimit" to runCatching { model().getTokenLimit() }.getOrDefault(4096))

    private suspend fun downloadModel() {
        val model = model()
        when (model.checkStatus()) {
            FeatureStatus.AVAILABLE -> return
            FeatureStatus.DOWNLOADABLE, FeatureStatus.DOWNLOADING -> {
                model.download().collect { status ->
                    when (status) {
                        is DownloadStatus.DownloadStarted ->
                            downloadSink?.success(
                                mapOf(
                                    "status" to "downloading",
                                    "bytesToDownload" to status.bytesToDownload,
                                    "bytesDownloaded" to 0L,
                                ),
                            )
                        is DownloadStatus.DownloadProgress ->
                            downloadSink?.success(
                                mapOf(
                                    "status" to "downloading",
                                    "bytesDownloaded" to status.totalBytesDownloaded,
                                ),
                            )
                        DownloadStatus.DownloadCompleted ->
                            downloadSink?.success(mapOf("status" to "ready"))
                        is DownloadStatus.DownloadFailed -> throw status.e
                    }
                }
            }
            else -> throw IllegalStateException("Gemini Nano is not available on this device.")
        }
    }

    private suspend fun request(
        model: GenerativeModel,
        prompt: String,
        systemInstruction: String?,
        maxOutputTokens: Int,
    ): GenerateContentRequest {
        val supportsSystemInstruction =
            systemInstruction.isNullOrBlank() || model.isSystemPromptAvailable()
        val effectivePrompt =
            if (supportsSystemInstruction || systemInstruction.isNullOrBlank()) {
                prompt
            } else {
                "$systemInstruction\n\n$prompt"
            }
        return generateContentRequest(TextPart(effectivePrompt)) {
            this.maxOutputTokens = maxOutputTokens.coerceIn(1, 4096)
            if (supportsSystemInstruction && !systemInstruction.isNullOrBlank()) {
                this.systemInstruction = SystemInstruction(systemInstruction)
            }
        }
    }

    private suspend fun countTokens(
        prompt: String,
        systemInstruction: String?,
        schema: String?,
    ): Int {
        val model = model()
        val base = request(model, prompt, systemInstruction, 1)
        if (!model.isStructuredOutputFeatureAvailable() || schema == null) {
            return model.countTokens(base).totalTokens
        }
        return when (schema) {
            "bilingualSentence" ->
                model.countTokens(generateTypedContentRequest(base, BilingualSentenceOutput::class)).totalTokens
            "passageStart" ->
                model.countTokens(generateTypedContentRequest(base, PassageStartOutput::class)).totalTokens
            "passageSegment" ->
                model.countTokens(generateTypedContentRequest(base, PassageSegmentOutput::class)).totalTokens
            "quizBatch" ->
                model.countTokens(generateTypedContentRequest(base, QuizBatchOutput::class)).totalTokens
            "translationCheck" ->
                model.countTokens(generateTypedContentRequest(base, TranslationCheckOutput::class)).totalTokens
            else -> model.countTokens(base).totalTokens
        }
    }

    private suspend fun generate(
        prompt: String,
        systemInstruction: String?,
        maxOutputTokens: Int,
        schema: String?,
    ): String =
        withContext(Dispatchers.Default) {
            val model = model()
            if (model.checkStatus() != FeatureStatus.AVAILABLE) {
                throw IllegalStateException("Gemini Nano is not ready.")
            }
            val base = request(model, prompt, systemInstruction, maxOutputTokens)
            if (schema != null && model.isStructuredOutputFeatureAvailable()) {
                try {
                    return@withContext generateStructured(model, base, schema)
                } catch (error: GenAiException) {
                    if (!isStructuredOutputError(error.errorCode)) throw error
                }
            }
            val response = model.generateContent(base)
            response.candidates.firstOrNull()?.text?.trim().orEmpty().ifEmpty {
                throw IllegalStateException("Gemini Nano returned an empty response.")
            }
        }

    private suspend fun generateStructured(
        model: GenerativeModel,
        request: GenerateContentRequest,
        schema: String,
    ): String =
        when (schema) {
            "bilingualSentence" -> {
                val output = typed(model, request, BilingualSentenceOutput::class)
                JSONObject()
                    .put("source", output.source)
                    .put("transcription", output.transcription)
                    .put("translation", output.translation)
                    .toString()
            }
            "passageStart" -> {
                val output = typed(model, request, PassageStartOutput::class)
                JSONObject()
                    .put("title", output.title)
                    .put("titleTranslation", output.titleTranslation)
                    .put("theme", output.theme)
                    .put("source", output.source)
                    .put("translation", output.translation)
                    .toString()
            }
            "passageSegment" -> {
                val output = typed(model, request, PassageSegmentOutput::class)
                JSONObject()
                    .put("source", output.source)
                    .put("translation", output.translation)
                    .toString()
            }
            "quizBatch" -> {
                val output = typed(model, request, QuizBatchOutput::class)
                val sentences = JSONArray()
                output.sentences.forEach {
                    sentences.put(JSONObject().put("source", it.source).put("translation", it.translation))
                }
                JSONObject().put("sentences", sentences).toString()
            }
            "translationCheck" -> {
                val output = typed(model, request, TranslationCheckOutput::class)
                JSONObject()
                    .put("correct", output.correct)
                    .put("feedback", output.feedback)
                    .put("correctedAnswer", output.correctedAnswer)
                    .put("transcription", output.transcription)
                    .toString()
            }
            else -> throw IllegalArgumentException("Unknown response schema: $schema")
        }

    private suspend fun <T : Any> typed(
        model: GenerativeModel,
        request: GenerateContentRequest,
        outputClass: kotlin.reflect.KClass<T>,
    ): T =
        model.generateContent(generateTypedContentRequest(request, outputClass))
            .candidates.firstOrNull()?.response
            ?: throw IllegalStateException("Gemini Nano returned no structured response.")

    private fun availabilityForException(error: GenAiException): Map<String, Any?> =
        when (error.errorCode) {
            GenAiException.ErrorCode.NEEDS_SYSTEM_UPDATE,
            GenAiException.ErrorCode.AICORE_INCOMPATIBLE,
            -> eligibleUnavailable(
                "status" to "setupRequired",
                "reason" to "systemUpdateRequired",
                "message" to "Update Android system intelligence services to use Gemini Nano.",
            )
            GenAiException.ErrorCode.NOT_ENOUGH_DISK_SPACE ->
                eligibleUnavailable(
                    "status" to "setupRequired",
                    "reason" to "modelNotReady",
                    "message" to "Free device storage before downloading Gemini Nano.",
                )
            GenAiException.ErrorCode.NOT_SUPPORTED ->
                unsupported("deviceNotEligible", error.message ?: "Gemini Nano is unsupported.")
            else ->
                eligibleUnavailable(
                    "status" to "temporarilyUnavailable",
                    "reason" to "featureUnavailable",
                    "message" to (error.message ?: "Gemini Nano is temporarily unavailable."),
                )
        }

    private fun eligibleUnavailable(vararg entries: Pair<String, Any?>): Map<String, Any?> =
        mapOf(
            "isEligible" to true,
            "providerName" to "Gemini Nano",
            "totalTokenLimit" to 4096,
            "supportsStructuredOutput" to false,
            "supportsSystemInstructions" to false,
            "supportsTokenCounting" to false,
            "supportsWarmup" to true,
            *entries,
        )

    private fun unsupported(reason: String, message: String): Map<String, Any?> =
        mapOf(
            "status" to "unsupported",
            "isEligible" to false,
            "reason" to reason,
            "message" to message,
            "providerName" to "Gemini Nano",
            "totalTokenLimit" to 4096,
            "supportsStructuredOutput" to false,
            "supportsSystemInstructions" to false,
            "supportsTokenCounting" to false,
            "supportsWarmup" to false,
        )

    private fun errorCode(error: Exception): String {
        if (error is CancellationException) return "cancelled"
        if (error !is GenAiException) return "generationFailed"
        return when (error.errorCode) {
            GenAiException.ErrorCode.CANCELLED -> "cancelled"
            GenAiException.ErrorCode.BUSY -> "busy"
            GenAiException.ErrorCode.PER_APP_BATTERY_USE_QUOTA_EXCEEDED -> "batteryQuotaExceeded"
            GenAiException.ErrorCode.BACKGROUND_USE_BLOCKED -> "backgroundUseBlocked"
            GenAiException.ErrorCode.NOT_ENOUGH_DISK_SPACE -> "insufficientStorage"
            GenAiException.ErrorCode.NEEDS_SYSTEM_UPDATE,
            GenAiException.ErrorCode.AICORE_INCOMPATIBLE,
            -> "systemUpdateRequired"
            GenAiException.ErrorCode.REQUEST_TOO_LARGE,
            GenAiException.ErrorCode.STRUCTURED_OUTPUT_MAX_TOKENS_ERROR,
            -> "requestTooLarge"
            GenAiException.ErrorCode.STRUCTURED_OUTPUT_REQUEST_ERROR,
            GenAiException.ErrorCode.STRUCTURED_OUTPUT_RESPONSE_ERROR,
            -> "structuredOutputFailure"
            GenAiException.ErrorCode.NOT_AVAILABLE,
            GenAiException.ErrorCode.NOT_SUPPORTED,
            -> "unavailable"
            else -> "generationFailed"
        }
    }

    private fun isStructuredOutputError(code: Int): Boolean =
        code == GenAiException.ErrorCode.STRUCTURED_OUTPUT_REQUEST_ERROR ||
            code == GenAiException.ErrorCode.STRUCTURED_OUTPUT_RESPONSE_ERROR ||
            code == GenAiException.ErrorCode.STRUCTURED_OUTPUT_MAX_TOKENS_ERROR

    private fun requireArguments(call: MethodCall): Map<*, *> =
        call.arguments as? Map<*, *> ?: throw IllegalArgumentException("Arguments are required.")

    private fun requirePrompt(arguments: Map<*, *>): String =
        (arguments["prompt"] as? String)?.takeIf { it.isNotBlank() }
            ?: throw IllegalArgumentException("prompt is required")

    private fun MethodChannel.Result.nativeError(code: String, message: String) {
        error("on_device_ai", message, mapOf("errorCode" to code))
    }

    private data class CandidateConfig(val preference: Int)
}
