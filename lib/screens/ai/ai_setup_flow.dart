import 'dart:async';

import 'package:flutter/material.dart';
import 'package:on_device_ai/on_device_ai.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/screens/ai/codex_sign_in_screen.dart';
import 'package:tri_flash/services/ai/ai_feature_flags.dart';
import 'package:tri_flash/services/ai/ai_settings_service.dart';
import 'package:tri_flash/services/ai/codex_auth_service.dart';

class AiSetupFlow {
  AiSetupFlow._();

  static Future<bool> ensureReady(
    BuildContext context, {
    AiSettingsService? settings,
  }) async {
    final service = settings ?? AiSettingsService();
    var provider = await resolveStoredOrLocalDefault(service);
    if (provider == null) {
      if (!context.mounted) return false;
      provider = await chooseProvider(context);
      if (provider == null) return false;
      await service.setProvider(provider);
    }
    if (provider != AiProviderType.onDevice &&
        !await service.hasPrivacyConsent()) {
      if (!context.mounted) return false;
      final accepted = await _requestCloudConsent(context);
      if (!accepted) return false;
      await service.grantPrivacyConsent();
    }
    if (await service.isConfigured(provider)) {
      if (provider == AiProviderType.onDevice) {
        unawaited(service.warmupOnDeviceModel().catchError((_) {}));
      }
      return true;
    }
    if (!context.mounted) return false;
    return configureProvider(context, provider, settings: service);
  }

  static Future<AiProviderType?> resolveStoredOrLocalDefault(
    AiSettingsService service,
  ) async {
    final stored = await service.getProvider();
    if (stored != null) {
      if (stored == AiProviderType.onDevice) {
        if (!AiFeatureFlags.enableOnDeviceAi) return null;
        final availability = await service.getOnDeviceAvailability();
        if (!availability.isEligible) return null;
      }
      return stored;
    }
    if (!AiFeatureFlags.enableOnDeviceAi) return null;
    final availability = await service.getOnDeviceAvailability();
    if (!availability.isEligible) return null;
    await service.setProvider(AiProviderType.onDevice);
    return AiProviderType.onDevice;
  }

  static Future<bool> _requestCloudConsent(BuildContext context) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(context.l10n.text('privacyTitle')),
            content: Text(context.l10n.text('privacyBody')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.text('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.text('continueAction')),
              ),
            ],
          ),
    );
    return accepted == true;
  }

  static Future<AiProviderType?> chooseProvider(BuildContext context) {
    final l10n = context.l10n;
    return showModalBottomSheet<AiProviderType>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(title: Text(l10n.text('chooseProvider'))),
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: Text(l10n.text('chatgptProvider')),
                  subtitle: Text(l10n.text('chatgptExperimental')),
                  onTap: () => Navigator.pop(context, AiProviderType.chatGpt),
                ),
                ListTile(
                  leading: const Icon(Icons.key),
                  title: Text(l10n.text('openaiProvider')),
                  onTap: () => Navigator.pop(context, AiProviderType.openAi),
                ),
                ListTile(
                  leading: const Icon(Icons.key),
                  title: Text(l10n.text('mistralProvider')),
                  onTap: () => Navigator.pop(context, AiProviderType.mistral),
                ),
              ],
            ),
          ),
    );
  }

  static Future<bool> configureProvider(
    BuildContext context,
    AiProviderType provider, {
    AiSettingsService? settings,
  }) async {
    final service = settings ?? AiSettingsService();
    await service.setProvider(provider);
    if (!context.mounted) return false;
    switch (provider) {
      case AiProviderType.chatGpt:
        try {
          final auth = CodexAuthService();
          final session = await auth.startDeviceLogin();
          if (!context.mounted) return false;
          return await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder:
                      (_) => CodexSignInScreen(session: session, auth: auth),
                ),
              ) ==
              true;
        } catch (error) {
          if (context.mounted) _showError(context, error.toString());
          return false;
        }
      case AiProviderType.openAi:
      case AiProviderType.mistral:
        final controller = TextEditingController();
        final saved = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: Text(
                  provider == AiProviderType.openAi
                      ? context.l10n.text('openaiProvider')
                      : context.l10n.text('mistralProvider'),
                ),
                content: TextField(
                  controller: controller,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: context.l10n.text('apiKey'),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(context.l10n.text('cancel')),
                  ),
                  FilledButton(
                    onPressed:
                        () => Navigator.pop(
                          context,
                          controller.text.trim().isNotEmpty,
                        ),
                    child: Text(context.l10n.text('save')),
                  ),
                ],
              ),
        );
        final value = controller.text;
        controller.dispose();
        if (saved != true) return false;
        if (provider == AiProviderType.openAi) {
          await service.setOpenAiApiKey(value);
        } else {
          await service.setMistralApiKey(value);
        }
        return true;
      case AiProviderType.onDevice:
        return _configureOnDevice(context, service);
    }
  }

  static Future<bool> _configureOnDevice(
    BuildContext context,
    AiSettingsService service,
  ) async {
    var availability = await service.getOnDeviceAvailability();
    if (availability.isReady) return true;
    if (!context.mounted) return false;

    if (availability.status == OnDeviceAiStatus.unsupported) {
      _showError(context, _onDeviceStatusMessage(context, availability));
      return false;
    }

    if (availability.status == OnDeviceAiStatus.downloadRequired) {
      final accepted = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(context.l10n.text('onDeviceDownloadTitle')),
              content: Text(context.l10n.text('onDeviceDownloadBody')),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(context.l10n.text('cancel')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(context.l10n.text('onDeviceDownloadAction')),
                ),
              ],
            ),
      );
      if (accepted != true) return false;
      if (!context.mounted) return false;
      if (!await _downloadOnDevice(context, service)) return false;
      availability = await service.getOnDeviceAvailability();
    }

    if (availability.isReady) return true;
    if (context.mounted) {
      _showError(context, _onDeviceStatusMessage(context, availability));
    }
    return false;
  }

  static Future<bool> _downloadOnDevice(
    BuildContext context,
    AiSettingsService service,
  ) async {
    final progress = ValueNotifier<OnDeviceAiDownloadProgress?>(null);
    final subscription = service.onDeviceDownloadProgress.listen((event) {
      progress.value = event;
    });
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder:
            (dialogContext) => AlertDialog(
              content: ValueListenableBuilder<OnDeviceAiDownloadProgress?>(
                valueListenable: progress,
                builder: (context, value, _) {
                  final bytes = value?.bytesDownloaded;
                  final suffix =
                      bytes == null
                          ? ''
                          : ' ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
                  return Row(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Text(
                          '${dialogContext.l10n.text('onDeviceDownloading')}$suffix',
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    Object? failure;
    var succeeded = false;
    try {
      await service.downloadOnDeviceModel();
      succeeded = true;
    } catch (error) {
      failure = error;
    } finally {
      await subscription.cancel();
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progress.dispose();
    }
    if (!succeeded && context.mounted) {
      _showError(context, failure.toString());
    }
    return succeeded;
  }

  static String _onDeviceStatusMessage(
    BuildContext context,
    OnDeviceAiAvailability availability,
  ) {
    if (availability.reason ==
        OnDeviceAiUnavailableReason.appleIntelligenceNotEnabled) {
      return context.l10n.text('onDeviceAppleSetup');
    }
    if (availability.reason ==
        OnDeviceAiUnavailableReason.systemUpdateRequired) {
      return context.l10n.text('onDeviceSystemUpdate');
    }
    if (availability.reason == OnDeviceAiUnavailableReason.modelNotReady) {
      return context.l10n.text('onDeviceModelPreparing');
    }
    return switch (availability.status) {
      OnDeviceAiStatus.downloading => context.l10n.text('onDeviceDownloading'),
      OnDeviceAiStatus.temporarilyUnavailable => context.l10n.text(
        'onDeviceTemporarilyUnavailable',
      ),
      _ => availability.message ?? context.l10n.text('onDeviceUnavailable'),
    };
  }

  static void _showError(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(context.l10n.text('aiError')),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(context.l10n.text('close')),
              ),
            ],
          ),
    );
  }
}
