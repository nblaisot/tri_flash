import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/ai_settings_service.dart';
import 'package:tri_flash/services/ai/codex_auth_service.dart';

class AiProviderException implements Exception {
  const AiProviderException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class AiProviderClient {
  Future<String> generate(String prompt);
}

class OpenAiProviderClient implements AiProviderClient {
  OpenAiProviderClient(this.apiKey, {http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  @override
  Future<String> generate(String prompt) async {
    final response = await _client.post(
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
        'max_output_tokens': 4000,
        'store': false,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiProviderException(_errorMessage('OpenAI', response));
    }
    return _extractResponsesText(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }
}

class MistralProviderClient implements AiProviderClient {
  MistralProviderClient(this.apiKey, {http.Client? client})
    : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  @override
  Future<String> generate(String prompt) async {
    final response = await _client.post(
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
        'max_tokens': 4000,
        'temperature': 0.7,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiProviderException(_errorMessage('Mistral', response));
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
  }
}

class CodexProviderClient implements AiProviderClient {
  CodexProviderClient(this.auth, {http.Client? client})
    : _client = client ?? http.Client();

  final CodexAuthService auth;
  final http.Client _client;

  @override
  Future<String> generate(String prompt) async {
    var credentials = await auth.validCredentials();
    var response = await _send(prompt, credentials);
    if (response.statusCode == 401) {
      credentials = await auth.refresh(credentials);
      response = await _send(prompt, credentials);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiProviderException(_errorMessage('ChatGPT/Codex', response));
    }
    final body = utf8.decode(response.bodyBytes);
    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('text/event-stream') ||
        body.trimLeft().startsWith('event:')) {
      return _extractSseText(body);
    }
    return _extractResponsesText(jsonDecode(body) as Map<String, dynamic>);
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
