import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:on_device_ai/on_device_ai.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/screens/ai/ai_setup_flow.dart';
import 'package:tri_flash/services/ai/ai_feature_flags.dart';
import 'package:tri_flash/services/ai/ai_settings_service.dart';
import 'package:tri_flash/services/ai/codex_auth_service.dart';
import 'package:tri_flash/state/app_preferences.dart';

import 'package:tri_flash/services/tts_service.dart';

/// Settings screen that exposes text-to-speech configuration and onboarding reset.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TtsService _ttsService = TtsService();
  final AiSettingsService _aiSettings = AiSettingsService();

  bool _isInitializing = true;
  AiProviderType? _provider;
  bool _providerConfigured = false;
  OnDeviceAiAvailability? _onDeviceAvailability;
  String _sourceLanguage = 'Auto';
  String _translationLanguage = 'Auto';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _ttsService.initialize();
      await _ttsService.loadFromPrefs();
      _provider = await _aiSettings.getProvider();
      if (_provider == AiProviderType.onDevice &&
          !AiFeatureFlags.enableOnDeviceAi) {
        _provider = null;
      }
      _sourceLanguage = await _aiSettings.getSourceLanguage();
      _translationLanguage = await _aiSettings.getTranslationLanguage();
      if (_provider != null) {
        _providerConfigured = await _aiSettings.isConfigured(_provider!);
      }
      if (AiFeatureFlags.enableOnDeviceAi) {
        _onDeviceAvailability = await _aiSettings.getOnDeviceAvailability();
        if (_provider == AiProviderType.onDevice &&
            _onDeviceAvailability?.isEligible != true) {
          _provider = null;
          _providerConfigured = false;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not initialize TTS: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  @override
  void dispose() {
    _ttsService.dispose();
    super.dispose();
  }

  List<String> get _languageItems {
    final langs = _ttsService.supportedLanguages;
    if (langs.isEmpty) return const ['Auto'];
    return ['Auto', ...langs];
  }

  @override
  Widget build(BuildContext context) {
    final currentSpeed = _ttsService.speechRate;
    final currentLang =
        _languageItems.contains(_ttsService.forcedLanguage)
            ? _ttsService.forcedLanguage
            : 'Auto';

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('settings'))),
      body:
          _isInitializing
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildAppLanguageCard(),
                  const SizedBox(height: 16),
                  _buildAiCard(),
                  const SizedBox(height: 16),
                  _buildSpeedCard(currentSpeed),
                  const SizedBox(height: 16),
                  _buildLanguageCard(currentLang),
                  const SizedBox(height: 16),
                  _buildTestButton(),
                  const SizedBox(height: 40),
                  _buildResetOnboardingButton(),
                  const SizedBox(height: 20),
                  _buildTipsCard(),
                ],
              ),
    );
  }

  Widget _buildAppLanguageCard() {
    final current = AppPreferences.instance.locale?.languageCode ?? 'system';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DropdownButtonFormField<String>(
          initialValue: current,
          decoration: InputDecoration(
            labelText: context.l10n.text('appLanguage'),
            prefixIcon: const Icon(Icons.translate),
          ),
          items: [
            DropdownMenuItem(
              value: 'system',
              child: Text(context.l10n.text('systemLanguage')),
            ),
            DropdownMenuItem(
              value: 'en',
              child: Text(context.l10n.text('english')),
            ),
            DropdownMenuItem(
              value: 'fr',
              child: Text(context.l10n.text('french')),
            ),
          ],
          onChanged: (value) async {
            if (value == null) return;
            await AppPreferences.instance.setLocale(
              value == 'system' ? null : Locale(value),
            );
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  Widget _buildAiCard() {
    final l10n = context.l10n;
    const languages = [
      'Auto',
      'English',
      'French',
      'Spanish',
      'German',
      'Italian',
      'Portuguese',
      'Chinese',
      'Japanese',
      'Korean',
      'Russian',
      'Arabic',
    ];
    String providerLabel(AiProviderType value) => switch (value) {
      AiProviderType.chatGpt => l10n.text('chatgptProvider'),
      AiProviderType.openAi => l10n.text('openaiProvider'),
      AiProviderType.mistral => l10n.text('mistralProvider'),
      AiProviderType.onDevice => l10n.text('onDeviceProvider'),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.text('aiSettings'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.text('aiSettingsHelp'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<AiProviderType>(
              initialValue: _provider,
              decoration: InputDecoration(labelText: l10n.text('aiProvider')),
              items:
                  AiProviderType.values
                      .where(
                        (provider) =>
                            provider != AiProviderType.onDevice ||
                            (AiFeatureFlags.enableOnDeviceAi &&
                                _onDeviceAvailability?.isEligible == true),
                      )
                      .map(
                        (provider) => DropdownMenuItem(
                          value: provider,
                          child: Text(providerLabel(provider)),
                        ),
                      )
                      .toList(),
              onChanged: (provider) async {
                if (provider == null) return;
                await _aiSettings.setProvider(provider);
                final configured = await _aiSettings.isConfigured(provider);
                final onDeviceAvailability =
                    AiFeatureFlags.enableOnDeviceAi
                        ? await _aiSettings.getOnDeviceAvailability()
                        : null;
                if (mounted) {
                  setState(() {
                    _provider = provider;
                    _providerConfigured = configured;
                    _onDeviceAvailability = onDeviceAvailability;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  _providerConfigured ? Icons.check_circle : Icons.info_outline,
                  color:
                      _providerConfigured
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _providerConfigured
                        ? l10n.text('configured')
                        : l10n.text('notConfigured'),
                  ),
                ),
                if (_provider != null)
                  FilledButton.tonal(
                    onPressed: () async {
                      final configured = await AiSetupFlow.configureProvider(
                        context,
                        _provider!,
                        settings: _aiSettings,
                      );
                      final availability =
                          await _aiSettings.getOnDeviceAvailability();
                      if (mounted) {
                        setState(() {
                          _providerConfigured = configured;
                          _onDeviceAvailability = availability;
                        });
                      }
                    },
                    child: Text(
                      _provider == AiProviderType.chatGpt
                          ? l10n.text('signIn')
                          : _provider == AiProviderType.onDevice
                          ? l10n.text('onDeviceSetupAction')
                          : l10n.text('save'),
                    ),
                  ),
              ],
            ),
            if (_provider == AiProviderType.onDevice &&
                _onDeviceAvailability != null) ...[
              const SizedBox(height: 8),
              Text(
                _onDeviceStatusLabel(l10n, _onDeviceAvailability!),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_onDeviceAvailability!.providerName?.isNotEmpty == true ||
                  _onDeviceAvailability!.modelName?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  [
                        _onDeviceAvailability!.providerName,
                        _onDeviceAvailability!.modelName,
                        if (_onDeviceAvailability!.providerName ==
                            'Gemini Nano')
                          'Stable',
                      ]
                      .whereType<String>()
                      .where((value) => value.isNotEmpty)
                      .join(' · '),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
              if (_onDeviceAvailability!.status ==
                  OnDeviceAiStatus.downloadRequired) ...[
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () async {
                    final configured = await AiSetupFlow.configureProvider(
                      context,
                      AiProviderType.onDevice,
                      settings: _aiSettings,
                    );
                    final availability =
                        await _aiSettings.getOnDeviceAvailability();
                    if (mounted) {
                      setState(() {
                        _providerConfigured = configured;
                        _onDeviceAvailability = availability;
                      });
                    }
                  },
                  child: Text(l10n.text('onDeviceDownloadAction')),
                ),
              ],
            ],
            if (_providerConfigured &&
                _provider != AiProviderType.onDevice) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  if (_provider == AiProviderType.chatGpt) {
                    await CodexAuthService().signOut();
                  } else if (_provider == AiProviderType.openAi) {
                    await _aiSettings.setOpenAiApiKey('');
                  } else if (_provider == AiProviderType.mistral) {
                    await _aiSettings.setMistralApiKey('');
                  }
                  if (mounted) setState(() => _providerConfigured = false);
                },
                child: Text(l10n.text('signOut')),
              ),
            ],
            const Divider(height: 28),
            DropdownButtonFormField<String>(
              initialValue: _sourceLanguage,
              decoration: InputDecoration(labelText: l10n.text('wordLanguage')),
              items:
                  languages
                      .map(
                        (language) => DropdownMenuItem(
                          value: language,
                          child: Text(
                            language == 'Auto' ? l10n.text('auto') : language,
                          ),
                        ),
                      )
                      .toList(),
              onChanged: (language) async {
                if (language == null) return;
                await _aiSettings.setSourceLanguage(language);
                setState(() => _sourceLanguage = language);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _translationLanguage,
              decoration: InputDecoration(
                labelText: l10n.text('translationLanguage'),
              ),
              items:
                  languages
                      .map(
                        (language) => DropdownMenuItem(
                          value: language,
                          child: Text(
                            language == 'Auto' ? l10n.text('auto') : language,
                          ),
                        ),
                      )
                      .toList(),
              onChanged: (language) async {
                if (language == null) return;
                await _aiSettings.setTranslationLanguage(language);
                setState(() => _translationLanguage = language);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpeedCard(double currentSpeed) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Text-to-Speech Speed: ${currentSpeed.toStringAsFixed(1)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Slider(
              value: currentSpeed,
              min: 0.1,
              max: 1.0,
              divisions: 9,
              label: currentSpeed.toStringAsFixed(1),
              onChanged: (double value) async {
                await _ttsService.updateSettings(speed: value);
                if (mounted) setState(() {});
              },
              onChangeEnd: (double _) async {
                await _ttsService.saveToPrefs();
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text('Slow', style: TextStyle(fontSize: 12)),
                Text('Normal', style: TextStyle(fontSize: 12)),
                Text('Fast', style: TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageCard(String currentLang) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.language, size: 20),
                SizedBox(width: 8),
                Text(
                  'Force Language',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Select "Auto" to detect language automatically based on text characters, '
              'or choose a specific language.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<String>(
                value: currentLang,
                isExpanded: true,
                underline: const SizedBox(),
                icon: const Icon(Icons.arrow_drop_down),
                items:
                    _languageItems.map((String lang) {
                      String displayText = lang;
                      if (lang == 'Auto') {
                        displayText = 'Auto (Detect automatically)';
                      } else if (lang.contains('-')) {
                        displayText = _formatLanguageCode(lang);
                      }
                      return DropdownMenuItem<String>(
                        value: lang,
                        child: Text(
                          displayText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                onChanged: (String? newValue) async {
                  if (newValue == null) return;
                  await _ttsService.updateSettings(forcedLang: newValue);
                  await _ttsService.saveToPrefs();
                  if (mounted) setState(() {});
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Language changed to: ${newValue == "Auto" ? "Auto-detect" : newValue}',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTestButton() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.volume_up, size: 20),
                SizedBox(width: 8),
                Text(
                  'Test Text-to-Speech',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  await _ttsService.stop();
                  await _ttsService.speak(
                    'Hello, this is a test of text to speech with current settings.',
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('TTS test failed: $e')),
                  );
                }
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play Test'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResetOnboardingButton() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('onboarding_done', false);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Onboarding tips have been reset. They will show when you return to the main screen.',
              ),
              duration: Duration(seconds: 3),
            ),
          );
        },
        icon: const Icon(Icons.restart_alt),
        label: const Text('Reset Onboarding Tips'),
      ),
    );
  }

  Widget _buildTipsCard() {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 20,
                  color: colors.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'Tips',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '• Auto-detect works best for non-Latin scripts (Japanese, Chinese, Arabic, etc.)\n'
              '• For Latin-based text, consider selecting a specific language\n'
              '• If TTS fails, try installing additional language packs in your device settings',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  String _formatLanguageCode(String code) {
    final Map<String, String> languageNames = {
      'ar': 'Arabic',
      'en': 'English',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'it': 'Italian',
      'pt': 'Portuguese',
      'ru': 'Russian',
      'zh': 'Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'hi': 'Hindi',
      'he': 'Hebrew',
      'th': 'Thai',
      'vi': 'Vietnamese',
      'pl': 'Polish',
      'nl': 'Dutch',
      'sv': 'Swedish',
      'da': 'Danish',
      'no': 'Norwegian',
      'fi': 'Finnish',
      'cs': 'Czech',
      'hu': 'Hungarian',
      'el': 'Greek',
      'tr': 'Turkish',
      'id': 'Indonesian',
      'ms': 'Malay',
      'uk': 'Ukrainian',
      'ro': 'Romanian',
      'bg': 'Bulgarian',
      'hr': 'Croatian',
      'sk': 'Slovak',
      'sl': 'Slovenian',
      'lt': 'Lithuanian',
      'lv': 'Latvian',
      'et': 'Estonian',
      'is': 'Icelandic',
      'sq': 'Albanian',
      'mk': 'Macedonian',
      'sr': 'Serbian',
      'bs': 'Bosnian',
      'ca': 'Catalan',
      'eu': 'Basque',
      'gl': 'Galician',
      'cy': 'Welsh',
      'ta': 'Tamil',
      'te': 'Telugu',
      'ml': 'Malayalam',
      'kn': 'Kannada',
      'mr': 'Marathi',
      'gu': 'Gujarati',
      'bn': 'Bengali',
      'pa': 'Punjabi',
      'ur': 'Urdu',
      'ne': 'Nepali',
      'si': 'Sinhala',
      'km': 'Khmer',
      'lo': 'Lao',
      'my': 'Burmese',
      'ka': 'Georgian',
      'am': 'Amharic',
      'sw': 'Swahili',
      'fil': 'Filipino',
      'jv': 'Javanese',
      'su': 'Sundanese',
    };

    final parts = code.split('-');
    if (parts.isEmpty) return code;

    final langCode = parts[0].toLowerCase();
    final regionCode = parts.length > 1 ? parts[1].toUpperCase() : null;

    final langName = languageNames[langCode] ?? langCode.toUpperCase();
    if (regionCode != null) return '$langName ($regionCode)';
    return langName;
  }

  String _onDeviceStatusLabel(
    AppLocalizations l10n,
    OnDeviceAiAvailability availability,
  ) {
    if (availability.reason ==
        OnDeviceAiUnavailableReason.appleIntelligenceNotEnabled) {
      return l10n.text('onDeviceAppleSetup');
    }
    if (availability.reason ==
        OnDeviceAiUnavailableReason.systemUpdateRequired) {
      return l10n.text('onDeviceSystemUpdate');
    }
    if (availability.reason == OnDeviceAiUnavailableReason.modelNotReady) {
      return l10n.text('onDeviceModelPreparing');
    }
    return switch (availability.status) {
      OnDeviceAiStatus.ready => l10n.text('onDeviceReady'),
      OnDeviceAiStatus.setupRequired => l10n.text('onDeviceUnavailable'),
      OnDeviceAiStatus.downloadRequired => l10n.text(
        'onDeviceDownloadRequired',
      ),
      OnDeviceAiStatus.downloading => l10n.text('onDeviceDownloading'),
      OnDeviceAiStatus.temporarilyUnavailable => l10n.text(
        'onDeviceTemporarilyUnavailable',
      ),
      OnDeviceAiStatus.unsupported =>
        availability.message ?? l10n.text('onDeviceUnavailable'),
    };
  }
}
