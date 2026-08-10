import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:tri_flash/screens/qr_scan/qr_scan_screen.dart';
import 'package:tri_flash/services/database_helper.dart';

/// Screen that handles importing CSV/TSV data from different sources.
class LoadCsvScreen extends StatefulWidget {
  const LoadCsvScreen({super.key, required this.onCsvLoaded});

  final Function(List<Map<String, dynamic>>) onCsvLoaded;

  @override
  State<LoadCsvScreen> createState() => _LoadCsvScreenState();
}

class _LoadCsvScreenState extends State<LoadCsvScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  bool _isClipboardLoading = false;
  String? _lastUrl;
  bool _isUrlValid = false;

  @override
  void initState() {
    super.initState();
    _loadLastUrl();
    _controller.addListener(_validateUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validateUrl() {
    final url = _controller.text;
    setState(() {
      _isUrlValid = url.startsWith('https');
    });
  }

  Future<void> _loadLastUrl() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _lastUrl = prefs.getString('lastCsvUrl'));
  }

  Future<void> _saveLastUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastCsvUrl', url);
  }

  void _openExampleSheet() async {
    const url =
        'https://docs.google.com/spreadsheets/d/1Mz4dDPhrtcGfKngEN9isu4E3PaTHlogUc5uAcLE9Eto/edit?gid=0#gid=0';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Load Words'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildReloadButton(),
            const SizedBox(height: 8),
            const Center(child: Text('From my Google Sheet')),
            const SizedBox(height: 20),
            TextButton(
              onPressed: _openExampleSheet,
              child: const Text(
                'Open an example',
                style: TextStyle(
                  decoration: TextDecoration.underline,
                  color: Colors.blue,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Pair my Google Sheet', style: TextStyle(fontSize: 18)),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Paste URL or scan QR Code',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.camera_alt),
                  onPressed: _scanQRCode,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildPairButton(),
            const SizedBox(height: 30),
            const Text(
              'Load words from Clipboard (copied from Excel/Google Sheet - also 4 columns category | word | transcription | translation)',
              style: TextStyle(fontSize: 16),
            ),
            ElevatedButton(
              onPressed: _isClipboardLoading ? null : _loadCsvFromClipboard,
              child: _isClipboardLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Load from Clipboard'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReloadButton() {
    return ElevatedButton(
      onPressed:
          (_lastUrl != null && !_isLoading) ? () => _loadCsvFromUrl(_lastUrl!) : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: (_lastUrl != null) ? const Color(0xFFFFC107) : Colors.grey,
      ),
      child: _isLoading
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text('Reload'),
    );
  }

  Widget _buildPairButton() {
    return ElevatedButton(
      onPressed:
          (_isUrlValid && !_isLoading) ? () => _loadCsvFromUrl(_controller.text) : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: _isUrlValid ? const Color(0xFFFFC107) : Colors.grey,
      ),
      child: _isLoading
          ? const CircularProgressIndicator(color: Colors.white)
          : const Text('Pair and load'),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How to load words'),
        content: const SingleChildScrollView(
          child: Text(
            """
This is where you can load a list of words or pair your own Google Sheet.

• 1st column: category
• 2nd column: word (supports TTS: Mandarin, Arabic, Korean, Hebrew, Greek, Russian)
• 3rd column: transcription
• 4th column: translation

To pair your Google Sheet:
• File > Share > Publish to Web
• Copy/paste URL or scan QR code
• Click Pair and load

When loading, you can "Replace" or "Merge" the new content.
""",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  /// Parse CSV/TSV payload into rows of strings.
  List<List<String>> parseCsvData(
    String csvData, {
    String delimiter = '\t',
    String eol = '\n',
  }) {
    final csvList = <List<String>>[];

    List<String> lines = csvData.split(eol).where((line) => line.trim().isNotEmpty).toList();
    if (lines.isNotEmpty) {
      lines = lines.sublist(1);
    }

    for (final line in lines) {
      final fields = line.split(delimiter);
      while (fields.length < 4) {
        fields.add('');
      }
      final trimmed = fields.map((field) => field.trim()).toList();
      csvList.add(trimmed);
    }

    return csvList;
  }

  void _scanQRCode() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QRScanScreen(
          onUrlReceived: (url) => _loadCsvFromUrl(url),
        ),
      ),
    );
  }

  Future<void> _loadCsvFromClipboard() async {
    setState(() => _isClipboardLoading = true);
    final data = await Clipboard.getData('text/plain');
    if (data != null && data.text!.isNotEmpty) {
      final csvList = data.text!
          .split('\n')
          .skip(1)
          .map((e) => e.split('\t'))
          .toList();
      _showImportDialog(csvList);
    }
    setState(() => _isClipboardLoading = false);
  }

  Future<void> _loadCsvFromUrl(String url) async {
    if (url.contains('/edit?gid=')) {
      _showUnsupportedUrlDialog();
      return;
    }

    final processedUrl = _processUrl(url);

    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.parse(processedUrl));
      if (response.statusCode == 200) {
        final csvData = utf8.decode(response.bodyBytes);
        final csvList = parseCsvData(csvData);
        _showImportDialog(csvList);
        await _saveLastUrl(url);
      } else {
        throw Exception('Failed to download the CSV file.');
      }
    } catch (e) {
      _showErrorDialog('Failed to load CSV. Please check the URL and try again.\nError: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showUnsupportedUrlDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Error'),
        content: RichText(
          text: TextSpan(
            style: Theme.of(context).textTheme.bodyMedium,
            children: const [
              TextSpan(
                text:
                    'URLs of google sheets is not supported. You should provide the URL of the "Published" Google Sheet (menu File / Share / Publish to web), in ',
              ),
              TextSpan(
                text: 'tsv',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              TextSpan(text: ' format.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  String _processUrl(String url) {
    if (url.endsWith('/pubhtml')) {
      return url.replaceFirst('/pubhtml', '/pub?output=tsv');
    } else if (RegExp(r'/pubhtml\\?gid=[0-9]+&single=true$').hasMatch(url)) {
      return '${url.replaceFirst('pubhtml', 'pub')}&output=tsv';
    }
    return url;
  }

  Future<void> _insertCsvDataIntoDatabase(
    List<List<String>> csvList, {
    bool clearExisting = false,
  }) async {
    final dbHelper = DatabaseHelper.instance;
    if (clearExisting) {
      await dbHelper.clearTable();
    }
    for (final row in csvList) {
      final Map<String, dynamic> rowData = {
        DatabaseHelper.columnCategory: row.isNotEmpty ? row[0].toString() : '',
        DatabaseHelper.columnWord: row.length > 1 ? row[1].toString() : '',
        DatabaseHelper.columnTranscription: row.length > 2 ? row[2].toString() : '',
        DatabaseHelper.columnTranslation: row.length > 3 ? row[3].toString() : '',
        DatabaseHelper.columnIsActive: 1,
      };

      if (!clearExisting) {
        final exists = await dbHelper.wordExists(
          rowData[DatabaseHelper.columnWord] as String,
        );
        if (!exists) {
          await dbHelper.insert(rowData);
        }
      } else {
        await dbHelper.insert(rowData);
      }
    }
  }

  void _showImportDialog(List<List<String>> csvList) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Import'),
        content: Text(
          'Do you want to REPLACE the current list or MERGE to it? \n\nNumber of words: ${csvList.length}',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await _insertCsvDataIntoDatabase(csvList, clearExisting: true);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              Navigator.pop(context, true);
            },
            child: const Text('Replace'),
          ),
          TextButton(
            onPressed: () async {
              await _insertCsvDataIntoDatabase(csvList, clearExisting: false);
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (!mounted) return;
              Navigator.pop(context, true);
            },
            child: const Text('Merge'),
          ),
        ],
      ),
    );
  }
}
