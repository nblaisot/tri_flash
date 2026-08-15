import 'dart:async';

import 'package:flutter/services.dart';

enum OnDeviceAiStatus {
  unsupported,
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
  featureUnavailable,
  unknown,
}

class OnDeviceAiAvailability {
  const OnDeviceAiAvailability({
    required this.status,
    this.reason = OnDeviceAiUnavailableReason.unknown,
    this.message,
    this.maxInputTokens,
    this.maxOutputTokens,
  });

  final OnDeviceAiStatus status;
  final OnDeviceAiUnavailableReason reason;
  final String? message;
  final int? maxInputTokens;
  final int? maxOutputTokens;

  bool get isReady => status == OnDeviceAiStatus.ready;

  factory OnDeviceAiAvailability.fromMap(Map<dynamic, dynamic> map) {
    return OnDeviceAiAvailability(
      status: _parseStatus(map['status'] as String?),
      reason: _parseReason(map['reason'] as String?),
      message: map['message'] as String?,
      maxInputTokens: map['maxInputTokens'] as int?,
      maxOutputTokens: map['maxOutputTokens'] as int?,
    );
  }

  static OnDeviceAiStatus _parseStatus(String? value) =>
      switch (value) {
        'ready' => OnDeviceAiStatus.ready,
        'downloadRequired' => OnDeviceAiStatus.downloadRequired,
        'downloading' => OnDeviceAiStatus.downloading,
        'temporarilyUnavailable' => OnDeviceAiStatus.temporarilyUnavailable,
        _ => OnDeviceAiStatus.unsupported,
      };

  static OnDeviceAiUnavailableReason _parseReason(String? value) =>
      switch (value) {
        'platformUnsupported' => OnDeviceAiUnavailableReason.platformUnsupported,
        'osVersionUnsupported' =>
          OnDeviceAiUnavailableReason.osVersionUnsupported,
        'deviceNotEligible' => OnDeviceAiUnavailableReason.deviceNotEligible,
        'appleIntelligenceNotEnabled' =>
          OnDeviceAiUnavailableReason.appleIntelligenceNotEnabled,
        'modelNotReady' => OnDeviceAiUnavailableReason.modelNotReady,
        'modelDownloadRequired' =>
          OnDeviceAiUnavailableReason.modelDownloadRequired,
        'featureUnavailable' => OnDeviceAiUnavailableReason.featureUnavailable,
        _ => OnDeviceAiUnavailableReason.unknown,
      };
}

class OnDeviceAiLimits {
  const OnDeviceAiLimits({
    required this.maxInputTokens,
    required this.maxOutputTokens,
  });

  final int maxInputTokens;
  final int maxOutputTokens;

  factory OnDeviceAiLimits.fromMap(Map<dynamic, dynamic> map) {
    return OnDeviceAiLimits(
      maxInputTokens: map['maxInputTokens'] as int? ?? 3500,
      maxOutputTokens: map['maxOutputTokens'] as int? ?? 4096,
    );
  }
}

class OnDeviceAiBridge {
  OnDeviceAiBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.triflash/on_device_ai');

  final MethodChannel _channel;

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
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getLimits',
    );
    return OnDeviceAiLimits.fromMap(result ?? const {});
  }

  Future<void> downloadModel() => _channel.invokeMethod<void>('downloadModel');

  Future<String> generate({
    required String prompt,
    String? systemInstruction,
    required int maxOutputTokens,
  }) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'generate',
      {
        'prompt': prompt,
        if (systemInstruction != null) 'systemInstruction': systemInstruction,
        'maxOutputTokens': maxOutputTokens,
      },
    );
    final text = result?['text'];
    if (text is! String || text.trim().isEmpty) {
      throw PlatformException(
        code: 'empty_response',
        message: 'On-device AI returned an empty response.',
      );
    }
    return text;
  }

  Future<void> cancel() => _channel.invokeMethod<void>('cancel');
}
