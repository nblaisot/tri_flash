import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/ai_settings_service.dart';
import 'package:tri_flash/services/ai/codex_auth_service.dart';
import 'package:tri_flash/services/ai/ai_feature_flags.dart';
import 'package:tri_flash/services/ai/on_device_ai_provider_client.dart';

enum AiResponseSchema {
  bilingualSentence,
  passageStart,
  passageSegment,
  quizBatch,
  translationCheck,
}

class AiProviderException implements Exception {
  const AiProviderException(this.message, {this.isTransient = false});
  final String message;
  final bool isTransient;
  @override
  String toString() => message;
}

class AiGenerationCancelled implements Exception {
  const AiGenerationCancelled();

  @override
  String toString() => 'Generation cancelled.';
}

class AiCancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _isCancelled;

  void throwIfCancelled() {
    if (_isCancelled) throw const AiGenerationCancelled();
  }

  void Function() listen(void Function() listener) {
    if (_isCancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
    _listeners.clear();
  }
}

abstract class AiProviderClient {
  Future<String> generate(
    String prompt, {
    required int maxOutputTokens,
    AiCancellationToken? cancellationToken,
    AiResponseSchema? responseSchema,
  });
}

class OpenAiProviderClient implements AiProviderClient {
  OpenAiProviderClient(this.apiKey, {http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  @override
  Future<String> generate(
    String prompt, {
    required int maxOutputTokens,
    AiCancellationToken? cancellationToken,
    AiResponseSchema? responseSchema,
  }) async {
    cancellationToken?.throwIfCancelled();
    final removeListener = cancellationToken?.listen(_client.close);
    try {
      final response = await _client
          .post(
            Uri.parse('https://api.openai.com/v1/responses'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': 'gpt-5.6-terra',
              'instructions':
                  'Return only the JSON object requested by the user. Do not use Markdown.',
              'input': prompt,
              'max_output_tokens': maxOutputTokens,
              'store': false,
            }),
          )
          .timeout(const Duration(seconds: 120));
      cancellationToken?.throwIfCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiProviderException(
          _errorMessage('OpenAI', response),
          isTransient: response.statusCode >= 500 || response.statusCode == 429,
        );
      }
      return _extractResponsesText(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
      );
    } on TimeoutException {
      _client.close();
      throw const AiProviderException(
        'OpenAI request timed out after 120 seconds.',
        isTransient: true,
      );
    } finally {
      removeListener?.call();
    }
  }
}

class MistralProviderClient implements AiProviderClient {
  MistralProviderClient(this.apiKey, {http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  @override
  Future<String> generate(
    String prompt, {
    required int maxOutputTokens,
    AiCancellationToken? cancellationToken,
    AiResponseSchema? responseSchema,
  }) async {
    cancellationToken?.throwIfCancelled();
    final removeListener = cancellationToken?.listen(_client.close);
    try {
      final response = await _client
          .post(
            Uri.parse('https://api.mistral.ai/v1/chat/completions'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': 'mistral-medium-3-5',
              'messages': [
                {
                  'role': 'system',
                  'content':
                      'Return only the JSON object requested by the user. Do not use Markdown.',
                },
                {'role': 'user', 'content': prompt},
              ],
              'response_format': {'type': 'json_object'},
              'max_tokens': maxOutputTokens,
              'temperature': 0.7,
            }),
          )
          .timeout(const Duration(seconds: 120));
      cancellationToken?.throwIfCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiProviderException(
          _errorMessage('Mistral', response),
          isTransient: response.statusCode >= 500 || response.statusCode == 429,
        );
      }
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>?;
      String? content;
      if (choices != null && choices.isNotEmpty && choices.first is Map) {
        final message = (choices.first as Map)['message'];
        if (message is Map && message['content'] is String) {
          content = message['content'] as String;
        }
      }
      if (content == null || content.trim().isEmpty) {
        throw const AiProviderException('Mistral returned an empty response.');
      }
      return content;
    } on TimeoutException {
      _client.close();
      throw const AiProviderException(
        'Mistral request timed out after 120 seconds.',
        isTransient: true,
      );
    } finally {
      removeListener?.call();
    }
  }
}

class CodexProviderClient implements AiProviderClient {
  CodexProviderClient(this.auth, {http.Client? client})
    : _client = client ?? http.Client();

  final CodexAuthService auth;
  final http.Client _client;

  @override
  Future<String> generate(
    String prompt, {
    required int maxOutputTokens,
    AiCancellationToken? cancellationToken,
    AiResponseSchema? responseSchema,
  }) async {
    cancellationToken?.throwIfCancelled();
    final removeListener = cancellationToken?.listen(_client.close);
    try {
      var credentials = await auth.validCredentials();
      var response = await _send(
        prompt,
        credentials,
      ).timeout(const Duration(seconds: 120));
      if (response.statusCode == 401) {
        credentials = await auth.refresh(credentials);
        response = await _send(
          prompt,
          credentials,
        ).timeout(const Duration(seconds: 120));
      }
      cancellationToken?.throwIfCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiProviderException(
          _errorMessage('ChatGPT/Codex', response),
          isTransient: response.statusCode >= 500 || response.statusCode == 429,
        );
      }
      final body = utf8.decode(response.bodyBytes);
      final contentType = response.headers['content-type'] ?? '';
      if (contentType.contains('text/event-stream') ||
          body.trimLeft().startsWith('event:')) {
        return _extractSseText(body);
      }
      return _extractResponsesText(jsonDecode(body) as Map<String, dynamic>);
    } on TimeoutException {
      _client.close();
      throw const AiProviderException(
        'ChatGPT/Codex request timed out after 120 seconds.',
        isTransient: true,
      );
    } finally {
      removeListener?.call();
    }
  }

  Future<http.Response> _send(String prompt, CodexCredentials credentials) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      'Authorization': 'Bearer ${credentials.accessToken}',
    };
    if (credentials.accountId?.isNotEmpty == true) {
      headers['ChatGPT-Account-Id'] = credentials.accountId!;
    }
    return _client.post(
      Uri.parse(CodexAuthService.responseUrl),
      headers: headers,
      body: jsonEncode({
        'model': 'gpt-5.6-terra',
        'instructions':
            'Return only the JSON object requested by the user. Do not use Markdown.',
        'input': [
          {'role': 'user', 'content': prompt},
        ],
        'store': false,
        'stream': true,
      }),
    );
  }
}

class AiProviderClientFactory {
  AiProviderClientFactory(this.settings);
  final AiSettingsService settings;

  Future<AiProviderClient> create(AiProviderType provider) async {
    switch (provider) {
      case AiProviderType.chatGpt:
        return CodexProviderClient(CodexAuthService());
      case AiProviderType.openAi:
        final key = await settings.getOpenAiApiKey();
        if (key == null || key.isEmpty) {
          throw const AiProviderException('OpenAI API key is not configured.');
        }
        return OpenAiProviderClient(key);
      case AiProviderType.mistral:
        final key = await settings.getMistralApiKey();
        if (key == null || key.isEmpty) {
          throw const AiProviderException('Mistral API key is not configured.');
        }
        return MistralProviderClient(key);
      case AiProviderType.onDevice:
        if (!AiFeatureFlags.enableOnDeviceAi) {
          throw const AiProviderException(
            'On-device AI is currently disabled.',
          );
        }
        return OnDeviceAiProviderClient();
    }
  }
}

String _extractResponsesText(Map<String, dynamic> data) {
  final direct = data['output_text'];
  if (direct is String && direct.trim().isNotEmpty) return direct;
  final buffer = StringBuffer();
  for (final item in data['output'] as List<dynamic>? ?? const []) {
    if (item is! Map) continue;
    for (final part in item['content'] as List<dynamic>? ?? const []) {
      if (part is Map &&
          part['type'] == 'output_text' &&
          part['text'] is String) {
        buffer.write(part['text']);
      }
    }
  }
  if (buffer.isEmpty) {
    throw const AiProviderException(
      'The AI provider returned an empty response.',
    );
  }
  return buffer.toString();
}

String _extractSseText(String body) {
  final buffer = StringBuffer();
  for (final line in const LineSplitter().convert(body)) {
    if (!line.startsWith('data:')) continue;
    final payload = line.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') continue;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      if ((data['type'] == 'response.output_text.delta' ||
              data['type'] == 'response.output_text.done') &&
          data['delta'] is String) {
        buffer.write(data['delta']);
      } else if (data['type'] == 'response.output_text.done' &&
          data['text'] is String) {
        if (buffer.isEmpty) buffer.write(data['text']);
      }
    } catch (_) {}
  }
  if (buffer.isEmpty) {
    throw const AiProviderException(
      'ChatGPT/Codex returned an empty response.',
    );
  }
  return buffer.toString();
}

String _errorMessage(String provider, http.Response response) {
  try {
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final error = data['error'];
    if (error is Map && error['message'] is String) {
      return '$provider: ${error['message']}';
    }
    if (data['detail'] is String) return '$provider: ${data['detail']}';
  } catch (_) {}
  return '$provider request failed (${response.statusCode}).';
}
