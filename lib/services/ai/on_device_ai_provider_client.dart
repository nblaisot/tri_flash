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

  Future<OnDeviceAiAvailability> getAvailability() => _bridge.getAvailability();

  Future<void> warmup() => _bridge.warmup();

  Future<bool> supportsLanguages(List<String> languageCodes) =>
      _bridge.supportsLanguages(languageCodes);

  Future<int> countTokens(
    String prompt, {
    String? systemInstruction,
    AiResponseSchema? responseSchema,
  }) => _bridge.countTokens(
    prompt: prompt,
    systemInstruction: systemInstruction,
    responseSchema: _nativeSchema(responseSchema),
  );

  @override
  Future<String> generate(
    String prompt, {
    required int maxOutputTokens,
    AiCancellationToken? cancellationToken,
    AiResponseSchema? responseSchema,
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
      String? result;
      for (var attempt = 0; attempt < 3; attempt++) {
        cancellationToken?.throwIfCancelled();
        try {
          result = await _bridge.generate(
            prompt: prompt,
            systemInstruction: jsonSystemInstruction,
            maxOutputTokens: maxOutputTokens,
            responseSchema: _nativeSchema(responseSchema),
          );
          break;
        } on OnDeviceAiException catch (error) {
          if (error.code != OnDeviceAiErrorCode.busy || attempt == 2) rethrow;
          await _cancellableDelay(
            attempt == 0
                ? const Duration(milliseconds: 500)
                : const Duration(milliseconds: 1500),
            cancellationToken,
          );
        }
      }
      cancellationToken?.throwIfCancelled();
      return result!;
    } on OnDeviceAiException catch (error) {
      if (error.code == OnDeviceAiErrorCode.cancelled ||
          cancellationToken?.isCancelled == true) {
        throw const AiGenerationCancelled();
      }
      // BUSY has already received the only retries allowed for a local call.
      throw AiProviderException(error.message);
    } on PlatformException catch (error) {
      if (error.code == 'cancelled' || cancellationToken?.isCancelled == true) {
        throw const AiGenerationCancelled();
      }
      throw AiProviderException(
        error.message ?? 'On-device AI request failed.',
      );
    } finally {
      removeListener?.call();
    }
  }

  static Future<void> _cancellableDelay(
    Duration duration,
    AiCancellationToken? token,
  ) async {
    const slice = Duration(milliseconds: 100);
    var elapsed = Duration.zero;
    while (elapsed < duration) {
      token?.throwIfCancelled();
      await Future<void>.delayed(slice);
      elapsed += slice;
    }
  }

  static OnDeviceAiResponseSchema? _nativeSchema(
    AiResponseSchema? schema,
  ) => switch (schema) {
    AiResponseSchema.bilingualSentence =>
      OnDeviceAiResponseSchema.bilingualSentence,
    AiResponseSchema.passageStart => OnDeviceAiResponseSchema.passageStart,
    AiResponseSchema.passageSegment => OnDeviceAiResponseSchema.passageSegment,
    AiResponseSchema.quizBatch => OnDeviceAiResponseSchema.quizBatch,
    AiResponseSchema.translationCheck =>
      OnDeviceAiResponseSchema.translationCheck,
    null => null,
  };

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
      OnDeviceAiUnavailableReason.systemUpdateRequired =>
        'Update the device software before using on-device AI.',
      OnDeviceAiUnavailableReason.featureUnavailable =>
        'On-device AI is temporarily unavailable.',
      OnDeviceAiUnavailableReason.unsupportedLanguage =>
        'The selected language is not supported by the on-device model.',
      OnDeviceAiUnavailableReason.platformUnsupported ||
      OnDeviceAiUnavailableReason
          .unknown => 'On-device AI is not available on this platform.',
    };
  }
}
