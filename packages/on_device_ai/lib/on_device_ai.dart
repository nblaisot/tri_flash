import 'dart:async';

import 'package:flutter/services.dart';

enum OnDeviceAiStatus {
  unsupported,
  setupRequired,
  downloadRequired,
  downloading,
  temporarilyUnavailable,
  ready,
}

enum OnDeviceAiUnavailableReason {
  platformUnsupported,
  osVersionUnsupported,
  deviceNotEligible,
  appleIntelligenceNotEnabled,
  modelNotReady,
  modelDownloadRequired,
  systemUpdateRequired,
  featureUnavailable,
  unsupportedLanguage,
  unknown,
}

enum OnDeviceAiErrorCode {
  cancelled,
  busy,
  batteryQuotaExceeded,
  backgroundUseBlocked,
  insufficientStorage,
  systemUpdateRequired,
  requestTooLarge,
  unsupportedLanguage,
  guardrailViolation,
  refusal,
  structuredOutputFailure,
  unavailable,
  generationFailed,
  unknown,
}

enum OnDeviceAiResponseSchema {
  bilingualSentence,
  passageStart,
  passageSegment,
  quizBatch,
  translationCheck,
}

extension OnDeviceAiResponseSchemaValue on OnDeviceAiResponseSchema {
  String get value => switch (this) {
    OnDeviceAiResponseSchema.bilingualSentence => 'bilingualSentence',
    OnDeviceAiResponseSchema.passageStart => 'passageStart',
    OnDeviceAiResponseSchema.passageSegment => 'passageSegment',
    OnDeviceAiResponseSchema.quizBatch => 'quizBatch',
    OnDeviceAiResponseSchema.translationCheck => 'translationCheck',
  };
}

class OnDeviceAiException implements Exception {
  const OnDeviceAiException(
    this.code,
    this.message, {
    this.isTransient = false,
  });

  final OnDeviceAiErrorCode code;
  final String message;
  final bool isTransient;

  @override
  String toString() => message;

  factory OnDeviceAiException.fromPlatformException(PlatformException error) {
    final details = error.details;
    final nativeCode = details is Map ? details['errorCode']?.toString() : null;
    final code = _parseErrorCode(nativeCode ?? error.code);
    return OnDeviceAiException(
      code,
      error.message ?? 'On-device AI request failed.',
      isTransient: code == OnDeviceAiErrorCode.busy,
    );
  }

  static OnDeviceAiErrorCode _parseErrorCode(String? value) => switch (value) {
    'cancelled' => OnDeviceAiErrorCode.cancelled,
    'busy' => OnDeviceAiErrorCode.busy,
    'batteryQuotaExceeded' => OnDeviceAiErrorCode.batteryQuotaExceeded,
    'backgroundUseBlocked' => OnDeviceAiErrorCode.backgroundUseBlocked,
    'insufficientStorage' => OnDeviceAiErrorCode.insufficientStorage,
    'systemUpdateRequired' => OnDeviceAiErrorCode.systemUpdateRequired,
    'requestTooLarge' => OnDeviceAiErrorCode.requestTooLarge,
    'unsupportedLanguage' => OnDeviceAiErrorCode.unsupportedLanguage,
    'guardrailViolation' => OnDeviceAiErrorCode.guardrailViolation,
    'refusal' => OnDeviceAiErrorCode.refusal,
    'structuredOutputFailure' => OnDeviceAiErrorCode.structuredOutputFailure,
    'unavailable' => OnDeviceAiErrorCode.unavailable,
    'generationFailed' ||
    'generate_failed' => OnDeviceAiErrorCode.generationFailed,
    _ => OnDeviceAiErrorCode.unknown,
  };
}

class OnDeviceAiAvailability {
  const OnDeviceAiAvailability({
    required this.status,
    this.isEligible = false,
    this.reason = OnDeviceAiUnavailableReason.unknown,
    this.message,
    this.providerName,
    this.modelName,
    this.totalTokenLimit = 4096,
    this.supportsStructuredOutput = false,
    this.supportsSystemInstructions = false,
    this.supportsTokenCounting = false,
    this.supportsWarmup = false,
  });

  final OnDeviceAiStatus status;
  final bool isEligible;
  final OnDeviceAiUnavailableReason reason;
  final String? message;
  final String? providerName;
  final String? modelName;
  final int totalTokenLimit;
  final bool supportsStructuredOutput;
  final bool supportsSystemInstructions;
  final bool supportsTokenCounting;
  final bool supportsWarmup;

  bool get isReady => status == OnDeviceAiStatus.ready;
  @Deprecated('Use totalTokenLimit')
  int get maxInputTokens => totalTokenLimit;
  @Deprecated('Use totalTokenLimit')
  int get maxOutputTokens => totalTokenLimit;

  factory OnDeviceAiAvailability.fromMap(Map<dynamic, dynamic> map) {
    return OnDeviceAiAvailability(
      status: _parseStatus(map['status'] as String?),
      isEligible: map['isEligible'] as bool? ?? false,
      reason: _parseReason(map['reason'] as String?),
      message: map['message'] as String?,
      providerName: map['providerName'] as String?,
      modelName: map['modelName'] as String?,
      totalTokenLimit:
          map['totalTokenLimit'] as int? ??
          map['maxInputTokens'] as int? ??
          4096,
      supportsStructuredOutput:
          map['supportsStructuredOutput'] as bool? ?? false,
      supportsSystemInstructions:
          map['supportsSystemInstructions'] as bool? ?? false,
      supportsTokenCounting: map['supportsTokenCounting'] as bool? ?? false,
      supportsWarmup: map['supportsWarmup'] as bool? ?? false,
    );
  }

  static OnDeviceAiStatus _parseStatus(String? value) => switch (value) {
    'ready' => OnDeviceAiStatus.ready,
    'setupRequired' => OnDeviceAiStatus.setupRequired,
    'downloadRequired' => OnDeviceAiStatus.downloadRequired,
    'downloading' => OnDeviceAiStatus.downloading,
    'temporarilyUnavailable' => OnDeviceAiStatus.temporarilyUnavailable,
    _ => OnDeviceAiStatus.unsupported,
  };

  static OnDeviceAiUnavailableReason _parseReason(
    String? value,
  ) => switch (value) {
    'platformUnsupported' => OnDeviceAiUnavailableReason.platformUnsupported,
    'osVersionUnsupported' => OnDeviceAiUnavailableReason.osVersionUnsupported,
    'deviceNotEligible' => OnDeviceAiUnavailableReason.deviceNotEligible,
    'appleIntelligenceNotEnabled' =>
      OnDeviceAiUnavailableReason.appleIntelligenceNotEnabled,
    'modelNotReady' => OnDeviceAiUnavailableReason.modelNotReady,
    'modelDownloadRequired' =>
      OnDeviceAiUnavailableReason.modelDownloadRequired,
    'systemUpdateRequired' => OnDeviceAiUnavailableReason.systemUpdateRequired,
    'featureUnavailable' => OnDeviceAiUnavailableReason.featureUnavailable,
    'unsupportedLanguage' => OnDeviceAiUnavailableReason.unsupportedLanguage,
    _ => OnDeviceAiUnavailableReason.unknown,
  };
}

class OnDeviceAiLimits {
  const OnDeviceAiLimits({required this.totalTokenLimit});

  final int totalTokenLimit;
  @Deprecated('Use totalTokenLimit')
  int get maxInputTokens => totalTokenLimit;
  @Deprecated('Use totalTokenLimit')
  int get maxOutputTokens => totalTokenLimit;

  factory OnDeviceAiLimits.fromMap(Map<dynamic, dynamic> map) {
    return OnDeviceAiLimits(
      totalTokenLimit:
          map['totalTokenLimit'] as int? ??
          map['maxInputTokens'] as int? ??
          4096,
    );
  }
}

class OnDeviceAiDownloadProgress {
  const OnDeviceAiDownloadProgress({
    required this.status,
    this.bytesDownloaded,
  });

  final OnDeviceAiStatus status;
  final int? bytesDownloaded;

  factory OnDeviceAiDownloadProgress.fromMap(Map<dynamic, dynamic> map) =>
      OnDeviceAiDownloadProgress(
        status: OnDeviceAiAvailability._parseStatus(map['status'] as String?),
        bytesDownloaded: map['bytesDownloaded'] as int?,
      );
}

class OnDeviceAiBridge {
  OnDeviceAiBridge({MethodChannel? channel, EventChannel? downloadChannel})
    : _channel = channel ?? const MethodChannel('com.triflash/on_device_ai'),
      _downloadChannel =
          downloadChannel ??
          const EventChannel('com.triflash/on_device_ai/download');

  final MethodChannel _channel;
  final EventChannel _downloadChannel;

  Future<OnDeviceAiAvailability> getAvailability() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getAvailability',
      );
      return OnDeviceAiAvailability.fromMap(result ?? const {});
    } on MissingPluginException {
      return const OnDeviceAiAvailability(
        status: OnDeviceAiStatus.unsupported,
        reason: OnDeviceAiUnavailableReason.platformUnsupported,
        message: 'On-device AI is not available on this platform.',
      );
    } on PlatformException catch (error) {
      return OnDeviceAiAvailability(
        status: OnDeviceAiStatus.unsupported,
        reason: OnDeviceAiUnavailableReason.platformUnsupported,
        message: error.message,
      );
    }
  }

  Future<OnDeviceAiLimits> getLimits() async {
    final result = await _invokeMap('getLimits');
    return OnDeviceAiLimits.fromMap(result);
  }

  Stream<OnDeviceAiDownloadProgress> get downloadProgress => _downloadChannel
      .receiveBroadcastStream()
      .map((event) => OnDeviceAiDownloadProgress.fromMap(event as Map));

  Future<void> downloadModel() => _channel.invokeMethod<void>('downloadModel');

  Future<void> warmup() => _channel.invokeMethod<void>('warmup');

  Future<bool> supportsLanguages(List<String> languageCodes) async {
    if (languageCodes.isEmpty) return true;
    final result = await _invokeMap('supportsLanguages', {
      'languageCodes': languageCodes,
    });
    return result['supported'] as bool? ?? true;
  }

  Future<int> countTokens({
    required String prompt,
    String? systemInstruction,
    OnDeviceAiResponseSchema? responseSchema,
  }) async {
    final result = await _invokeMap('countTokens', {
      'prompt': prompt,
      if (systemInstruction != null) 'systemInstruction': systemInstruction,
      if (responseSchema != null) 'responseSchema': responseSchema.value,
    });
    return result['count'] as int? ?? 0;
  }

  Future<String> generate({
    required String prompt,
    String? systemInstruction,
    required int maxOutputTokens,
    OnDeviceAiResponseSchema? responseSchema,
  }) async {
    try {
      final result = await _invokeMap('generate', {
        'prompt': prompt,
        if (systemInstruction != null) 'systemInstruction': systemInstruction,
        'maxOutputTokens': maxOutputTokens,
        if (responseSchema != null) 'responseSchema': responseSchema.value,
      });
      final text = result['text'];
      if (text is! String || text.trim().isEmpty) {
        throw const OnDeviceAiException(
          OnDeviceAiErrorCode.generationFailed,
          'On-device AI returned an empty response.',
        );
      }
      return text;
    } on PlatformException catch (error) {
      throw OnDeviceAiException.fromPlatformException(error);
    }
  }

  Future<void> cancel() => _channel.invokeMethod<void>('cancel');

  Future<Map<dynamic, dynamic>> _invokeMap(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    try {
      return await _channel.invokeMethod<Map<dynamic, dynamic>>(
            method,
            arguments,
          ) ??
          const {};
    } on PlatformException catch (error) {
      throw OnDeviceAiException.fromPlatformException(error);
    }
  }
}
