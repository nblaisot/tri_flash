import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tri_flash/services/ai/codex_auth_service.dart';

void main() {
  test('parses a device-code login session', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/accounts/deviceauth/usercode');
      return http.Response(
        jsonEncode({
          'device_auth_id': 'device-id',
          'user_code': 'ABCD-1234',
          'interval': 3,
        }),
        200,
      );
    });
    final service = CodexAuthService(client: client);

    final session = await service.startDeviceLogin();

    expect(session.userCode, 'ABCD-1234');
    expect(session.deviceAuthId, 'device-id');
    expect(session.pollIntervalSeconds, 3);
  });

  test('reports when device login is unavailable', () async {
    final service = CodexAuthService(
      client: MockClient((_) async => http.Response('', 404)),
    );

    expect(service.startDeviceLogin, throwsA(isA<CodexAuthException>()));
  });
}
