import Flutter
import UIKit

#if canImport(FoundationModels)
import FoundationModels
#endif

public class OnDeviceAiPlugin: NSObject, FlutterPlugin {
  private var generateTask: Task<Void, Never>?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.triflash/on_device_ai",
      binaryMessenger: registrar.messenger()
    )
    let instance = OnDeviceAiPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getAvailability":
      result(Self.availabilityMap())
    case "getLimits":
      result(Self.limitsMap())
    case "downloadModel":
      result(nil)
    case "generate":
      guard let args = call.arguments as? [String: Any],
            let prompt = args["prompt"] as? String,
            !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        result(
          FlutterError(code: "invalid_args", message: "prompt is required", details: nil)
        )
        return
      }
      let systemInstruction = args["systemInstruction"] as? String
      let maxOutputTokens = args["maxOutputTokens"] as? Int ?? 4096
      generateTask?.cancel()
      generateTask = Task {
        do {
          let text = try await Self.generate(
            prompt: prompt,
            systemInstruction: systemInstruction,
            maxOutputTokens: maxOutputTokens
          )
          if Task.isCancelled {
            result(
              FlutterError(code: "cancelled", message: "Generation cancelled.", details: nil)
            )
            return
          }
          result(["text": text])
        } catch {
          if Task.isCancelled {
            result(
              FlutterError(code: "cancelled", message: "Generation cancelled.", details: nil)
            )
          } else {
            result(
              FlutterError(
                code: "generate_failed",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
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
      return FoundationModelsAvailability.currentMap()
    }
#endif
    return unsupportedMap(reason: "osVersionUnsupported", message: "iOS 26+ is required.")
  }

  private static func limitsMap() -> [String: Int] {
#if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      return FoundationModelsAvailability.currentLimits()
    }
#endif
    return ["maxInputTokens": 3500, "maxOutputTokens": 4096]
  }

  private static func generate(
    prompt: String,
    systemInstruction: String?,
    maxOutputTokens: Int
  ) async throws -> String {
#if canImport(FoundationModels)
    if #available(iOS 26.0, *) {
      return try await FoundationModelsGenerator.generate(
        prompt: prompt,
        systemInstruction: systemInstruction,
        maxOutputTokens: maxOutputTokens
      )
    }
#endif
    throw NSError(
      domain: "OnDeviceAi",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "On-device AI is not available on this device."]
    )
  }

  private static func unsupportedMap(reason: String, message: String) -> [String: Any] {
    [
      "status": "unsupported",
      "reason": reason,
      "message": message,
      "maxInputTokens": 3500,
      "maxOutputTokens": 4096,
    ]
  }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
private enum FoundationModelsAvailability {
  static func currentMap() -> [String: Any] {
    let model = SystemLanguageModel.default
    switch model.availability {
    case .available:
      return [
        "status": "ready",
        "reason": "unknown",
        "maxInputTokens": currentLimits()["maxInputTokens"] ?? 3500,
        "maxOutputTokens": currentLimits()["maxOutputTokens"] ?? 4096,
      ]
    case .unavailable(.deviceNotEligible):
      return unsupported(reason: "deviceNotEligible", message: "This device does not support Apple Intelligence.")
    case .unavailable(.appleIntelligenceNotEnabled):
      return unsupported(
        reason: "appleIntelligenceNotEnabled",
        message: "Apple Intelligence is disabled in Settings."
      )
    case .unavailable(.modelNotReady):
      return [
        "status": "temporarilyUnavailable",
        "reason": "modelNotReady",
        "message": "The on-device model is not ready yet.",
        "maxInputTokens": 3500,
        "maxOutputTokens": 4096,
      ]
    case .unavailable:
      return unsupported(reason: "featureUnavailable", message: "On-device AI is unavailable.")
    }
  }

  static func currentLimits() -> [String: Int] {
    let model = SystemLanguageModel.default
    let contextSize = model.contextSize
    let maxInput = min(contextSize > 0 ? contextSize - 512 : 3500, 3500)
    return ["maxInputTokens": maxInput, "maxOutputTokens": 4096]
  }

  private static func unsupported(reason: String, message: String) -> [String: Any] {
    [
      "status": "unsupported",
      "reason": reason,
      "message": message,
      "maxInputTokens": 3500,
      "maxOutputTokens": 4096,
    ]
  }
}

@available(iOS 26.0, *)
private enum FoundationModelsGenerator {
  static func generate(
    prompt: String,
    systemInstruction: String?,
    maxOutputTokens: Int
  ) async throws -> String {
    let model = SystemLanguageModel.default
    guard model.isAvailable else {
      throw NSError(
        domain: "OnDeviceAi",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "On-device AI is not available."]
      )
    }

    let instruction =
      systemInstruction
      ?? "Return only the JSON object requested by the user. Do not use Markdown."
    let session = LanguageModelSession {
      instruction
    }
    let cappedTokens = max(1, min(maxOutputTokens, 4096))
    _ = cappedTokens
    let response = try await session.respond(to: prompt)
    let text = String(describing: response.content).trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    if text.isEmpty {
      throw NSError(
        domain: "OnDeviceAi",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "On-device AI returned an empty response."]
      )
    }
    return text
  }
}
#endif
