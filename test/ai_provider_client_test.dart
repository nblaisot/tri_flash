import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tri_flash/services/ai/ai_provider_client.dart';

void main() {
  test('OpenAI forwards the per-request output token limit', () async {
    final client = OpenAiProviderClient(
      'key',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['max_output_tokens'], 8000);
        return http.Response(
          jsonEncode({
            'output': [
              {
                'content': [
                  {'type': 'output_text', 'text': '{"ok":true}'},
                ],
              },
            ],
          }),
          200,
        );
      }),
    );

    expect(
      await client.generate('{prompt}', maxOutputTokens: 8000),
      '{"ok":true}',
    );
  });

  test('Mistral forwards the per-request output token limit', () async {
    final client = MistralProviderClient(
      'key',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['max_tokens'], 4000);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"ok":true}'},
              },
            ],
          }),
          200,
        );
      }),
    );

    expect(
      await client.generate('{prompt}', maxOutputTokens: 4000),
      '{"ok":true}',
    );
  });

  test('a cancelled request never reaches the network', () async {
    var requested = false;
    final client = OpenAiProviderClient(
      'key',
      client: MockClient((_) async {
        requested = true;
        return http.Response('{}', 200);
      }),
    );
    final token = AiCancellationToken()..cancel();

    await expectLater(
      client.generate(
        '{prompt}',
        maxOutputTokens: 4000,
        cancellationToken: token,
      ),
      throwsA(isA<AiGenerationCancelled>()),
    );
    expect(requested, isFalse);
  });
}
