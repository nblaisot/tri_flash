import Flutter
import UIKit

#if canImport(FoundationModels)
import FoundationModels
#endif

public class OnDeviceAiPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var generateTask: Task<Void, Never>?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let methodChannel = FlutterMethodChannel(
      name: "com.triflash/on_device_ai",
      binaryMessenger: registrar.messenger()
    )
    let downloadChannel = FlutterEventChannel(
      name: "com.triflash/on_device_ai/download",
      binaryMessenger: registrar.messenger()
    )
    let instance = OnDeviceAiPlugin()
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    downloadChannel.setStreamHandler(instance)
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    nil
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getAvailability":
      result(Self.availabilityMap())
    case "getLimits":
      result(Self.limitsMap())
    case "downloadModel":
      // Apple Intelligence owns model downloads at the OS level.
      result(nil)
    case "warmup":
      Self.warmup()
      result(nil)
    case "supportsLanguages":
      let args = call.arguments as? [String: Any]
      let languageCodes = args?["languageCodes"] as? [String] ?? []
      result(["supported": Self.supportsLanguages(languageCodes)])
    case "countTokens":
      guard let args = call.arguments as? [String: Any],
            let prompt = args["prompt"] as? String,
            !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        result(FlutterError(code: "invalid_args", message: "prompt is required", details: nil))
        return
      }
      let instruction = args["systemInstruction"] as? String
      let schema = args["responseSchema"] as? String
      generateTask?.cancel()
      generateTask = Task {
        do {
          let count = try await Self.countTokens(
            prompt: prompt,
            systemInstruction: instruction,
            responseSchema: schema
          )
          result(["count": count])
        } catch {
          result(Self.flutterError(error))
        }
      }
    case "generate":
      guard let args = call.arguments as? [String: Any],
            let prompt = args["prompt"] as? String,
            !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        result(FlutterError(code: "invalid_args", message: "prompt is required", details: nil))
        return
      }
      let instruction = args["systemInstruction"] as? String
      let maxOutputTokens = args["maxOutputTokens"] as? Int ?? 4096
      let schema = args["responseSchema"] as? String
      generateTask?.cancel()
      generateTask = Task {
        do {
          let text = try await Self.generate(
            prompt: prompt,
            systemInstruction: instruction,
            maxOutputTokens: maxOutputTokens,
            responseSchema: schema
          )
          try Task.checkCancellation()
          result(["text": text])
        } catch {
          result(Self.flutterError(error))
        }
      }
    case "cancel":
      generateTask?.cancel()
      generateTask = nil
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func availabilityMap() -> [String: Any] {
#if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      let model = SystemLanguageModel.default
      let common: [String: Any] = [
        "providerName": "Apple Intelligence",
        "modelName": "System Language Model",
        "totalTokenLimit": model.contextSize,
        "supportsStructuredOutput": true,
        "supportsSystemInstructions": true,
        "supportsTokenCounting": tokenCountingAvailable,
        "supportsWarmup": true,
      ]
      switch model.availability {
      case .available:
        return common.merging([
          "status": "ready",
          "isEligible": true,
          "reason": "unknown",
        ]) { _, new in new }
      case .unavailable(.deviceNotEligible):
        return unsupportedMap(
          reason: "deviceNotEligible",
          message: "This device does not support Apple Intelligence."
        )
      case .unavailable(.appleIntelligenceNotEnabled):
        return common.merging([
          "status": "setupRequired",
          "isEligible": true,
          "reason": "appleIntelligenceNotEnabled",
          "message": "Enable Apple Intelligence in Settings to use local AI.",
        ]) { _, new in new }
      case .unavailable(.modelNotReady):
        return common.merging([
          "status": "temporarilyUnavailable",
          "isEligible": true,
          "reason": "modelNotReady",
          "message": "Apple Intelligence is preparing its on-device model.",
        ]) { _, new in new }
      @unknown default:
        return common.merging([
          "status": "temporarilyUnavailable",
          "isEligible": true,
          "reason": "featureUnavailable",
          "message": "Apple Intelligence is temporarily unavailable.",
        ]) { _, new in new }
      }
    }
#endif
    return unsupportedMap(reason: "osVersionUnsupported", message: "iOS 26+ is required.")
  }

  private static func limitsMap() -> [String: Int] {
#if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      return ["totalTokenLimit": SystemLanguageModel.default.contextSize]
    }
#endif
    return ["totalTokenLimit": 4096]
  }

  private static var tokenCountingAvailable: Bool {
    if #available(iOS 26.4, *) { return true }
    return false
  }

  private static func warmup() {
#if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      LanguageModelSession(
        model: SystemLanguageModel.default,
        instructions: "Be concise and follow the requested output structure exactly."
      ).prewarm()
    }
#endif
  }

  private static func supportsLanguages(_ languageCodes: [String]) -> Bool {
#if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      let model = SystemLanguageModel.default
      return languageCodes.allSatisfy { model.supportsLocale(Locale(identifier: $0)) }
    }
#endif
    return false
  }

  private static func countTokens(
    prompt: String,
    systemInstruction: String?,
    responseSchema: String?
  ) async throws -> Int {
#if canImport(FoundationModels)
    if #available(iOS 26.4, *) {
      let model = SystemLanguageModel.default
      var count = try await model.tokenCount(for: prompt)
      if let instruction = systemInstruction, !instruction.isEmpty {
        count += try await model.tokenCount(for: instruction)
      }
      if let schema = responseSchema {
        count += try await schemaTokenCount(model: model, schema: schema)
      }
      return count
    }
#endif
    throw NSError(
      domain: "OnDeviceAi",
      code: 4,
      userInfo: [NSLocalizedDescriptionKey: "Token counting requires iOS 26.4 or later."]
    )
  }

  private static func generate(
    prompt: String,
    systemInstruction: String?,
    maxOutputTokens: Int,
    responseSchema: String?
  ) async throws -> String {
#if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      let model = SystemLanguageModel.default
      guard case .available = model.availability else {
        throw NSError(
          domain: "OnDeviceAiUnavailable",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence is not ready."]
        )
      }
      let session = LanguageModelSession(
        model: model,
        instructions: systemInstruction ?? "Follow the requested output structure exactly."
      )
      let options = GenerationOptions(
        sampling: .random(probabilityThreshold: 0.9),
        temperature: 0.3,
        maximumResponseTokens: max(1, min(maxOutputTokens, 4096))
      )
      let text: String
      switch responseSchema {
      case "bilingualSentence":
        let output = try await session.respond(
          to: prompt,
          generating: BilingualSentenceOutput.self,
          options: options
        ).content
        text = try jsonString(output.dictionary)
      case "passageStart":
        let output = try await session.respond(
          to: prompt,
          generating: PassageStartOutput.self,
          options: options
        ).content
        text = try jsonString(output.dictionary)
      case "passageSegment":
        let output = try await session.respond(
          to: prompt,
          generating: PassageSegmentOutput.self,
          options: options
        ).content
        text = try jsonString(output.dictionary)
      case "quizBatch":
        let output = try await session.respond(
          to: prompt,
          generating: QuizBatchOutput.self,
          options: options
        ).content
        text = try jsonString(output.dictionary)
      case "translationCheck":
        let output = try await session.respond(
          to: prompt,
          generating: TranslationCheckOutput.self,
          options: options
        ).content
        text = try jsonString(output.dictionary)
      default:
        text = try await session.respond(to: prompt, options: options).content
      }
      if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        throw NSError(
          domain: "OnDeviceAi",
          code: 3,
          userInfo: [NSLocalizedDescriptionKey: "Apple Intelligence returned an empty response."]
        )
      }
      return text
    }
#endif
    throw NSError(
      domain: "OnDeviceAiUnavailable",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "On-device AI is not available on this device."]
    )
  }

  private static func unsupportedMap(reason: String, message: String) -> [String: Any] {
    [
      "status": "unsupported",
      "isEligible": false,
      "reason": reason,
      "message": message,
      "providerName": "Apple Intelligence",
      "modelName": "System Language Model",
      "totalTokenLimit": 4096,
      "supportsStructuredOutput": false,
      "supportsSystemInstructions": false,
      "supportsTokenCounting": false,
      "supportsWarmup": false,
    ]
  }

  private static func flutterError(_ error: Error) -> FlutterError {
    if error is CancellationError {
      return nativeError(code: "cancelled", message: "Generation cancelled.")
    }
#if canImport(FoundationModels)
    if #available(iOS 26.0, *),
       let generationError = error as? LanguageModelSession.GenerationError {
      switch generationError {
      case .exceededContextWindowSize:
        return nativeError(code: "requestTooLarge", message: "The local AI request is too large.")
      case .guardrailViolation:
        return nativeError(code: "guardrailViolation", message: "The request was blocked by Apple Intelligence safety controls.")
      case .unsupportedLanguageOrLocale:
        return nativeError(code: "unsupportedLanguage", message: "Apple Intelligence does not support one of the selected languages.")
      case .rateLimited:
        return nativeError(code: "busy", message: "Apple Intelligence is busy. Try again shortly.")
      case .refusal:
        return nativeError(code: "refusal", message: "Apple Intelligence declined this request.")
      case .decodingFailure, .unsupportedGuide:
        return nativeError(code: "structuredOutputFailure", message: "Apple Intelligence could not create the required response structure.")
      case .assetsUnavailable:
        return nativeError(code: "unavailable", message: "Apple Intelligence model assets are unavailable.")
      case .concurrentRequests:
        return nativeError(code: "busy", message: "Apple Intelligence is already processing a request.")
      @unknown default:
        break
      }
    }
#endif
    let nsError = error as NSError
    let code = nsError.domain == "OnDeviceAiUnavailable" ? "unavailable" : "generationFailed"
    return nativeError(code: code, message: nsError.localizedDescription)
  }

  private static func nativeError(code: String, message: String) -> FlutterError {
    FlutterError(
      code: "on_device_ai",
      message: message,
      details: ["errorCode": code]
    )
  }

  private static func jsonString(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object)
    return String(decoding: data, as: UTF8.self)
  }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable(description: "A concise bilingual example sentence")
private struct BilingualSentenceOutput {
  @Guide(description: "Sentence in the source language")
  var source: String
  @Guide(description: "Learner-friendly pronunciation")
  var transcription: String
  @Guide(description: "Faithful translated sentence")
  var translation: String

  var dictionary: [String: Any] {
    ["source": source, "transcription": transcription, "translation": translation]
  }
}

@available(iOS 26.0, *)
@Generable(description: "The opening segment of a bilingual passage")
private struct PassageStartOutput {
  @Guide(description: "Short title in the source language")
  var title: String
  @Guide(description: "Faithful translation of the title")
  var titleTranslation: String
  @Guide(description: "Short theme used to continue the passage")
  var theme: String
  @Guide(description: "Passage segment in the source language")
  var source: String
  @Guide(description: "Faithful translation of the passage segment")
  var translation: String

  var dictionary: [String: Any] {
    [
      "title": title,
      "titleTranslation": titleTranslation,
      "theme": theme,
      "source": source,
      "translation": translation,
    ]
  }
}

@available(iOS 26.0, *)
@Generable(description: "A continuation segment of a bilingual passage")
private struct PassageSegmentOutput {
  @Guide(description: "Passage segment in the source language")
  var source: String
  @Guide(description: "Faithful translation of the passage segment")
  var translation: String

  var dictionary: [String: Any] { ["source": source, "translation": translation] }
}

@available(iOS 26.0, *)
@Generable(description: "A bilingual sentence pair")
private struct QuizPairOutput {
  @Guide(description: "Sentence in the source language")
  var source: String
  @Guide(description: "Faithful translated sentence")
  var translation: String

  var dictionary: [String: Any] { ["source": source, "translation": translation] }
}

@available(iOS 26.0, *)
@Generable(description: "Exactly five bilingual sentence pairs")
private struct QuizBatchOutput {
  @Guide(description: "Five unique bilingual pairs", .count(5))
  var sentences: [QuizPairOutput]

  var dictionary: [String: Any] { ["sentences": sentences.map(\.dictionary)] }
}

@available(iOS 26.0, *)
@Generable(description: "Assessment of a learner translation")
private struct TranslationCheckOutput {
  @Guide(description: "Whether the answer preserves the expected meaning")
  var correct: Bool
  @Guide(description: "Short, helpful learner feedback")
  var feedback: String
  @Guide(description: "Correct answer, or an empty string when unnecessary")
  var correctedAnswer: String
  @Guide(description: "Learner-friendly pronunciation, or an empty string")
  var transcription: String

  var dictionary: [String: Any] {
    [
      "correct": correct,
      "feedback": feedback,
      "correctedAnswer": correctedAnswer,
      "transcription": transcription,
    ]
  }
}

@available(iOS 26.4, *)
private func schemaTokenCount(model: SystemLanguageModel, schema: String) async throws -> Int {
  let generationSchema: GenerationSchema
  switch schema {
  case "bilingualSentence": generationSchema = BilingualSentenceOutput.generationSchema
  case "passageStart": generationSchema = PassageStartOutput.generationSchema
  case "passageSegment": generationSchema = PassageSegmentOutput.generationSchema
  case "quizBatch": generationSchema = QuizBatchOutput.generationSchema
  case "translationCheck": generationSchema = TranslationCheckOutput.generationSchema
  default: return 0
  }
  return try await model.tokenCount(for: generationSchema)
}
#endif
