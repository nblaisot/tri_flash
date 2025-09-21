// qr_scan_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:permission_handler/permission_handler.dart';

class QRScanScreen extends StatefulWidget {
  final Function(String) onUrlReceived;

  const QRScanScreen({Key? key, required this.onUrlReceived}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _QRScanScreenState();
}

class _QRScanScreenState extends State<QRScanScreen> {
  bool _permissionGranted = false;
  bool _permissionPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _ensureCameraPermission();
  }

  Future<void> _ensureCameraPermission() async {
    final status = await Permission.camera.status;
    if (status.isGranted) {
      setState(() => _permissionGranted = true);
      return;
    }
    final req = await Permission.camera.request();
    if (req.isGranted) {
      setState(() => _permissionGranted = true);
    } else {
      setState(() {
        _permissionGranted = false;
        _permissionPermanentlyDenied = req.isPermanentlyDenied;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;

    if (_permissionGranted) {
      body = ReaderWidget(
        // Optional: give the platform view a key to force rebuild after hot reload
        key: const ValueKey('qr-reader'),
        onScan: (result) async {
          final text = result?.text ?? '';
          if (text.isNotEmpty) {
            widget.onUrlReceived(text);
            if (mounted) Navigator.of(context).pop();
          }
        },
        // Helpful to capture errors:
        onScanFailure: (error) {
          // You can also show a SnackBar here
          debugPrint('QR scan failure: $error');
        },
      );
    } else if (_permissionPermanentlyDenied) {
      body = _PermissionInfo(
        message:
        "Camera access is blocked. Please enable it in Settings to scan QR codes.",
        onOpenSettings: () async {
          await openAppSettings();
          // When coming back, re-check:
          await _ensureCameraPermission();
        },
      );
    } else {
      body = const _PermissionInfo(
        message: "Requesting camera permission…",
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: body,
    );
  }
}

class _PermissionInfo extends StatelessWidget {
  final String message;
  final VoidCallback? onOpenSettings;

  const _PermissionInfo({required this.message, this.onOpenSettings, super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(message, textAlign: TextAlign.center),
        ),
        if (onOpenSettings != null)
          ElevatedButton(
            onPressed: onOpenSettings,
            child: const Text('Open Settings'),
          ),
      ]),
    );
  }
}