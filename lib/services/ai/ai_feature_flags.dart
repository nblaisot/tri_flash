/// Compile-time / runtime switches for AI features that are not ready to ship.
class AiFeatureFlags {
  const AiFeatureFlags._();

  /// On-device Gemini Nano / Foundation Models.
  /// Hidden until Google Prompt API allowlists more devices (e.g. Z Fold 8).
  static const enableOnDeviceAi = false;
}
