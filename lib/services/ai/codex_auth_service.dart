import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:tri_flash/services/ai/ai_settings_service.dart';

class CodexAuthException implements Exception {
  const CodexAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

class CodexDeviceSession {
  const CodexDeviceSession({
    required this.verificationUrl,
    required this.userCode,
    required this.deviceAuthId,
    required this.pollIntervalSeconds,
  });

  final String verificationUrl;
  final String userCode;
  final String deviceAuthId;
  final int pollIntervalSeconds;
}

class CodexCredentials {
  const CodexCredentials({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.accountId,
    this.email,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String? accountId;
  final String? email;

  bool get needsRefresh => DateTime.now().toUtc().isAfter(
    expiresAt.subtract(const Duration(seconds: 30)),
  );
}

class CodexAuthService {
  CodexAuthService({http.Client? client, FlutterSecureStorage? storage})
    : _client = client ?? http.Client(),
      _store = CodexCredentialStore(storage ?? const FlutterSecureStorage());

  static const clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static const issuer = 'https://auth.openai.com';
  static const verificationUrl = '$issuer/codex/device';
  static const responseUrl = 'https://chatgpt.com/backend-api/codex/responses';

  final http.Client _client;
  final CodexCredentialStore _store;

  Future<CodexDeviceSession> startDeviceLogin() async {
    final response = await _client.post(
      Uri.parse('$issuer/api/accounts/deviceauth/usercode'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'client_id': clientId}),
    );
    if (response.statusCode == 404) {
      throw const CodexAuthException(
        'Device-code login is not enabled for this ChatGPT account.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CodexAuthException(
        'Could not start ChatGPT sign-in (${response.statusCode}).',
      );
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final deviceId = data['device_auth_id'] as String?;
    final code = (data['user_code'] ?? data['usercode']) as String?;
    if (deviceId == null || code == null) {
      throw const CodexAuthException(
        'OpenAI returned an incomplete device code.',
      );
    }
    final rawInterval = data['interval'];
    final interval =
        rawInterval is int ? rawInterval : int.tryParse('$rawInterval') ?? 5;
    return CodexDeviceSession(
      verificationUrl: verificationUrl,
      userCode: code,
      deviceAuthId: deviceId,
      pollIntervalSeconds: interval.clamp(2, 30),
    );
  }

  Future<void> completeDeviceLogin(
    CodexDeviceSession session, {
    Duration timeout = const Duration(minutes: 15),
    bool Function()? isCancelled,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (isCancelled?.call() == true) return;
      final response = await _client.post(
        Uri.parse('$issuer/api/accounts/deviceauth/token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_auth_id': session.deviceAuthId,
          'user_code': session.userCode,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final code = data['authorization_code'] as String?;
        final verifier = data['code_verifier'] as String?;
        if (code == null || verifier == null) {
          throw const CodexAuthException(
            'OpenAI returned an incomplete login response.',
          );
        }
        await _exchangeCode(code, verifier);
        return;
      }
      if (response.statusCode != 403 && response.statusCode != 404) {
        throw CodexAuthException(
          'ChatGPT sign-in failed (${response.statusCode}).',
        );
      }
      await Future<void>.delayed(
        Duration(seconds: session.pollIntervalSeconds),
      );
    }
    throw const CodexAuthException(
      'ChatGPT sign-in timed out. Please try again.',
    );
  }

  Future<void> _exchangeCode(String code, String verifier) async {
    final response = await _client.post(
      Uri.parse('$issuer/oauth/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': '$issuer/deviceauth/callback',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw const CodexAuthException('Could not complete ChatGPT sign-in.');
    }
    await _persist(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> _persist(Map<String, dynamic> data) async {
    final access = data['access_token'] as String?;
    final refresh = data['refresh_token'] as String?;
    if (access == null || refresh == null) {
      throw const CodexAuthException('OpenAI token response is incomplete.');
    }
    final expires =
        data['expires_in'] is int
            ? data['expires_in'] as int
            : int.tryParse('${data['expires_in']}') ?? 3600;
    final idToken = data['id_token'] as String?;
    await _store.write(
      jsonEncode({
        'access_token': access,
        'refresh_token': refresh,
        'expires_at':
            DateTime.now()
                .toUtc()
                .add(Duration(seconds: expires))
                .toIso8601String(),
        'account_id': _claim(
          access,
          'https://api.openai.com/auth',
          'chatgpt_account_id',
        ),
        'email': _simpleClaim(idToken, 'email'),
      }),
    );
  }

  Future<CodexCredentials?> readCredentials() async {
    final raw = await _store.read();
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return CodexCredentials(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String,
        expiresAt: DateTime.parse(data['expires_at'] as String).toUtc(),
        accountId: data['account_id'] as String?,
        email: data['email'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  Future<CodexCredentials> validCredentials() async {
    final credentials = await readCredentials();
    if (credentials == null) {
      throw const CodexAuthException('ChatGPT is not signed in.');
    }
    return credentials.needsRefresh ? refresh(credentials) : credentials;
  }

  Future<CodexCredentials> refresh([CodexCredentials? existing]) async {
    final credentials = existing ?? await readCredentials();
    if (credentials == null) {
      throw const CodexAuthException('ChatGPT is not signed in.');
    }
    final response = await _client.post(
      Uri.parse('$issuer/oauth/token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'client_id': clientId,
        'grant_type': 'refresh_token',
        'refresh_token': credentials.refreshToken,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 400 || response.statusCode == 401) {
        await signOut();
      }
      throw const CodexAuthException('ChatGPT session expired. Sign in again.');
    }
    await _persist(jsonDecode(response.body) as Map<String, dynamic>);
    return (await readCredentials())!;
  }

  Future<bool> isConfigured() => _store.isConfigured();
  Future<void> signOut() => _store.clear();

  static String? _simpleClaim(String? token, String key) {
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length < 2) return null;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      return (jsonDecode(payload) as Map<String, dynamic>)[key] as String?;
    } catch (_) {
      return null;
    }
  }

  static String? _claim(String token, String parent, String key) {
    try {
      final parts = token.split('.');
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final root = jsonDecode(payload) as Map<String, dynamic>;
      final nested = root[parent];
      return nested is Map ? nested[key] as String? : null;
    } catch (_) {
      return null;
    }
  }
}
