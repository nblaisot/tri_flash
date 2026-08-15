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
    if (!await service.hasPrivacyConsent()) {
      if (!context.mounted) return false;
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
      if (accepted != true) return false;
      await service.grantPrivacyConsent();
    }

    var provider = await service.getProvider();
    if (provider == AiProviderType.onDevice &&
        !AiFeatureFlags.enableOnDeviceAi) {
      provider = null;
    }
    if (provider == null) {
      if (!context.mounted) return false;
      provider = await chooseProvider(context);
      if (provider == null) return false;
      await service.setProvider(provider);
    }
    if (await service.isConfigured(provider)) return true;
    if (!context.mounted) return false;
    return configureProvider(context, provider, settings: service);
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
                if (AiFeatureFlags.enableOnDeviceAi)
                  ListTile(
                    leading: const Icon(Icons.phone_android),
                    title: Text(l10n.text('onDeviceProvider')),
                    subtitle: Text(l10n.text('onDeviceProviderHelp')),
                    onTap:
                        () => Navigator.pop(context, AiProviderType.onDevice),
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
    final bridge = OnDeviceAiBridge();
    var availability = await bridge.getAvailability();
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
      try {
        await bridge.downloadModel();
      } catch (error) {
        if (context.mounted) _showError(context, error.toString());
        return false;
      }
      availability = await bridge.getAvailability();
    }

    if (availability.isReady) return true;
    if (context.mounted) {
      _showError(context, _onDeviceStatusMessage(context, availability));
    }
    return false;
  }

  static String _onDeviceStatusMessage(
    BuildContext context,
    OnDeviceAiAvailability availability,
  ) {
    if (availability.message?.isNotEmpty == true) return availability.message!;
    return switch (availability.status) {
      OnDeviceAiStatus.downloading => context.l10n.text('onDeviceDownloading'),
      OnDeviceAiStatus.temporarilyUnavailable =>
        context.l10n.text('onDeviceTemporarilyUnavailable'),
      _ => context.l10n.text('onDeviceUnavailable'),
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
