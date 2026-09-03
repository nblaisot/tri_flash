/// Compile-time / runtime switches for AI features that are not ready to ship.
class AiFeatureFlags {
  const AiFeatureFlags._();

  /// Emergency build-time kill switch. Availability is otherwise determined
  /// by the operating system and the installed system model.
  static const enableOnDeviceAi = bool.fromEnvironment(
    'ENABLE_ON_DEVICE_AI',
    defaultValue: true,
  );
}
