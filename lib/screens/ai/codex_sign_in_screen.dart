import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/services/ai/codex_auth_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CodexSignInScreen extends StatefulWidget {
  const CodexSignInScreen({
    required this.session,
    required this.auth,
    super.key,
  });

  final CodexDeviceSession session;
  final CodexAuthService auth;

  @override
  State<CodexSignInScreen> createState() => _CodexSignInScreenState();
}

class _CodexSignInScreenState extends State<CodexSignInScreen> {
  late final WebViewController _webView;
  bool _pageLoading = true;
  bool _cancelled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _webView =
        WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageFinished: (_) {
                if (mounted) setState(() => _pageLoading = false);
              },
              onWebResourceError: (error) {
                if (mounted && error.isForMainFrame == true) {
                  setState(() => _error = error.description);
                }
              },
            ),
          )
          ..loadRequest(Uri.parse(widget.session.verificationUrl));
    _poll();
  }

  Future<void> _poll() async {
    try {
      await widget.auth.completeDeviceLogin(
        widget.session,
        isCancelled: () => _cancelled,
      );
      if (mounted && !_cancelled) Navigator.of(context).pop(true);
    } on CodexAuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = context.l10n.text('providerError'));
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('signIn'))),
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.text('deviceCode')),
                          SelectableText(
                            widget.session.userCode,
                            style: Theme.of(
                              context,
                            ).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.text('copyCode'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: widget.session.userCode),
                        );
                        if (!mounted) return;
                        messenger.showSnackBar(
                          SnackBar(content: Text(l10n.text('copied'))),
                        );
                      },
                      icon: const Icon(Icons.copy),
                    ),
                    IconButton(
                      tooltip: l10n.text('openBrowser'),
                      onPressed:
                          () => launchUrl(
                            Uri.parse(widget.session.verificationUrl),
                            mode: LaunchMode.externalApplication,
                          ),
                      icon: const Icon(Icons.open_in_browser),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              MaterialBanner(
                content: Text(_error!),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _error = null),
                    child: Text(l10n.text('close')),
                  ),
                ],
              ),
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _webView),
                  if (_pageLoading)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(l10n.text('waitingForSignIn')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
