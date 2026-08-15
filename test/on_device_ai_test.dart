import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_device_ai/on_device_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/ai_provider_client.dart';
import 'package:tri_flash/services/ai/ai_settings_service.dart';
import 'package:tri_flash/services/ai/on_device_ai_provider_client.dart';

class _FakeBridge extends OnDeviceAiBridge {
  _FakeBridge(this.availability, this.response);

  final OnDeviceAiAvailability availability;
  final String response;
  var cancelled = false;
  var generateCalls = 0;

  @override
  Future<OnDeviceAiAvailability> getAvailability() async => availability;

  @override
  Future<String> generate({
    required String prompt,
    String? systemInstruction,
    required int maxOutputTokens,
  }) async {
    generateCalls++;
    return response;
  }

  @override
  Future<void> cancel() async {
    cancelled = true;
  }
}

class _CompletingBridge extends _FakeBridge {
  _CompletingBridge(super.availability, super.response);

  @override
  Future<String> generate({
    required String prompt,
    String? systemInstruction,
    required int maxOutputTokens,
  }) async {
    generateCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('factory blocks on-device client while the feature flag is off', () async {
    SharedPreferences.setMockInitialValues({});
    final factory = AiProviderClientFactory(AiSettingsService());
    await expectLater(
      factory.create(AiProviderType.onDevice),
      throwsA(
        isA<AiProviderException>().having(
          (error) => error.message,
          'message',
          'On-device AI is currently disabled.',
        ),
      ),
    );
  });

  test('on-device client forwards prompt and system instruction', () async {
    final bridge = _FakeBridge(
      const OnDeviceAiAvailability(status: OnDeviceAiStatus.ready),
      '{"ok":true}',
    );
    final client = OnDeviceAiProviderClient(bridge: bridge);

    expect(
      await client.generate('{prompt}', maxOutputTokens: 2048),
      '{"ok":true}',
    );
    expect(bridge.generateCalls, 1);
  });

  test('on-device client rejects unavailable engine', () async {
    final bridge = _FakeBridge(
      const OnDeviceAiAvailability(
        status: OnDeviceAiStatus.unsupported,
        reason: OnDeviceAiUnavailableReason.deviceNotEligible,
        message: 'Unsupported device',
      ),
      '',
    );
    final client = OnDeviceAiProviderClient(bridge: bridge);

    await expectLater(
      client.generate('{prompt}', maxOutputTokens: 2048),
      throwsA(
        isA<AiProviderException>().having(
          (error) => error.message,
          'message',
          'Unsupported device',
        ),
      ),
    );
  });

  test('on-device client cancels native generation', () async {
    final bridge = _CompletingBridge(
      const OnDeviceAiAvailability(status: OnDeviceAiStatus.ready),
      '{"ok":true}',
    );
    final client = OnDeviceAiProviderClient(bridge: bridge);
    final token = AiCancellationToken();
    final future = client.generate(
      '{prompt}',
      maxOutputTokens: 2048,
      cancellationToken: token,
    );
    token.cancel();
    await expectLater(future, throwsA(isA<AiGenerationCancelled>()));
    expect(bridge.cancelled, isTrue);
  });

  test('availability parses native map', () {
    final availability = OnDeviceAiAvailability.fromMap({
      'status': 'downloadRequired',
      'reason': 'modelDownloadRequired',
      'message': 'Download required',
      'maxInputTokens': 3500,
      'maxOutputTokens': 4096,
    });

    expect(availability.status, OnDeviceAiStatus.downloadRequired);
    expect(availability.reason, OnDeviceAiUnavailableReason.modelDownloadRequired);
    expect(availability.maxOutputTokens, 4096);
  });

  test('missing plugin channel reports unsupported availability', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.triflash/on_device_ai'),
          (_) async => throw MissingPluginException('missing'),
        );

    final availability = await OnDeviceAiBridge().getAvailability();
    expect(availability.status, OnDeviceAiStatus.unsupported);
  });
}
