import 'dart:async';

import 'package:flutter/services.dart';
import 'package:on_device_ai/on_device_ai.dart';
import 'package:tri_flash/services/ai/ai_provider_client.dart';

class OnDeviceAiProviderClient implements AiProviderClient {
  OnDeviceAiProviderClient({OnDeviceAiBridge? bridge})
    : _bridge = bridge ?? OnDeviceAiBridge();

  static const jsonSystemInstruction =
      'Return only the JSON object requested by the user. Do not use Markdown.';

  final OnDeviceAiBridge _bridge;

  @override
  Future<String> generate(
    String prompt, {
    required int maxOutputTokens,
    AiCancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    void Function()? removeListener;
    removeListener = cancellationToken?.listen(() {
      unawaited(_bridge.cancel());
    });
    try {
      final availability = await _bridge.getAvailability();
      if (!availability.isReady) {
        throw AiProviderException(_messageFor(availability));
      }
      final result = await _bridge.generate(
        prompt: prompt,
        systemInstruction: jsonSystemInstruction,
        maxOutputTokens: maxOutputTokens,
      );
      cancellationToken?.throwIfCancelled();
      return result;
    } on PlatformException catch (error) {
      if (error.code == 'cancelled' ||
          cancellationToken?.isCancelled == true) {
        throw const AiGenerationCancelled();
      }
      throw AiProviderException(
        error.message ?? 'On-device AI request failed.',
        isTransient: error.code == 'generate_failed',
      );
    } finally {
      removeListener?.call();
    }
  }

  static String _messageFor(OnDeviceAiAvailability availability) {
    if (availability.message?.isNotEmpty == true) {
      return availability.message!;
    }
    return switch (availability.reason) {
      OnDeviceAiUnavailableReason.osVersionUnsupported =>
        'On-device AI requires a newer OS version.',
      OnDeviceAiUnavailableReason.deviceNotEligible =>
        'This device does not support on-device AI.',
      OnDeviceAiUnavailableReason.appleIntelligenceNotEnabled =>
        'Enable Apple Intelligence in Settings to use on-device AI.',
      OnDeviceAiUnavailableReason.modelNotReady =>
        'The on-device model is not ready yet.',
      OnDeviceAiUnavailableReason.modelDownloadRequired =>
        'Download the on-device model before generating text.',
      OnDeviceAiUnavailableReason.featureUnavailable =>
        'On-device AI is temporarily unavailable.',
      OnDeviceAiUnavailableReason.platformUnsupported ||
      OnDeviceAiUnavailableReason.unknown =>
        'On-device AI is not available on this platform.',
    };
  }
}
