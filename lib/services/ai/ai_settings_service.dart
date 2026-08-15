import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:on_device_ai/on_device_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_flash/models/ai_models.dart';

class AiSettingsService {
  AiSettingsService({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _providerKey = 'ai_provider';
  static const _consentKey = 'ai_privacy_consent';
  static const _sourceLanguageKey = 'ai_source_language';
  static const _translationLanguageKey = 'ai_translation_language';
  static const _openAiKey = 'openai_api_key';
  static const _mistralKey = 'mistral_api_key';

  final FlutterSecureStorage _secureStorage;

  Future<AiProviderType?> getProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return AiProviderTypeValue.fromValue(prefs.getString(_providerKey));
  }

  Future<void> setProvider(AiProviderType provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_providerKey, provider.value);
  }

  Future<bool> hasPrivacyConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_consentKey) ?? false;
  }

  Future<void> grantPrivacyConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_consentKey, true);
  }

  Future<String> getSourceLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sourceLanguageKey) ?? 'Auto';
  }

  Future<String> getTranslationLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_translationLanguageKey) ?? 'Auto';
  }

  Future<void> setSourceLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sourceLanguageKey, language);
  }

  Future<void> setTranslationLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_translationLanguageKey, language);
  }

  Future<String?> getOpenAiApiKey() => _secureStorage.read(key: _openAiKey);
  Future<String?> getMistralApiKey() => _secureStorage.read(key: _mistralKey);

  Future<void> setOpenAiApiKey(String value) =>
      _writeOrDelete(_openAiKey, value);
  Future<void> setMistralApiKey(String value) =>
      _writeOrDelete(_mistralKey, value);

  Future<void> _writeOrDelete(String key, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _secureStorage.delete(key: key);
    } else {
      await _secureStorage.write(key: key, value: trimmed);
    }
  }

  Future<bool> isConfigured(
    AiProviderType provider,
  ) async => switch (provider) {
    AiProviderType.chatGpt =>
      await CodexCredentialStore(_secureStorage).isConfigured(),
    AiProviderType.openAi => (await getOpenAiApiKey())?.isNotEmpty == true,
    AiProviderType.mistral => (await getMistralApiKey())?.isNotEmpty == true,
    AiProviderType.onDevice =>
      (await OnDeviceAiBridge().getAvailability()).isReady,
  };

  Future<OnDeviceAiAvailability> getOnDeviceAvailability() =>
      OnDeviceAiBridge().getAvailability();
}

class CodexCredentialStore {
  CodexCredentialStore(this.storage);

  static const key = 'codex_chatgpt_oauth_tokens';
  final FlutterSecureStorage storage;

  Future<String?> read() => storage.read(key: key);
  Future<void> write(String value) => storage.write(key: key, value: value);
  Future<void> clear() => storage.delete(key: key);
  Future<bool> isConfigured() async => (await read())?.isNotEmpty == true;
}
