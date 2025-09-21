import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'database_helper.dart';
import 'dart:convert';
import 'qr_scan_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class LoadCsvScreen extends StatefulWidget {
  final Function(List<Map<String, dynamic>>) onCsvLoaded;

  const LoadCsvScreen({super.key, required this.onCsvLoaded});

  @override
  _LoadCsvScreenState createState() => _LoadCsvScreenState();
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

  void _validateUrl() {
    final url = _controller.text;
    setState(() {
      _isUrlValid = url.startsWith("https");
    });
  }

  Future<void> _loadLastUrl() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() => _lastUrl = prefs.getString('lastCsvUrl'));
  }

  Future<void> _saveLastUrl(String url) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastCsvUrl', url);
  }

  void _openExampleSheet() async {
    const url = "https://docs.google.com/spreadsheets/d/1Mz4dDPhrtcGfKngEN9isu4E3PaTHlogUc5uAcLE9Eto/edit?gid=0#gid=0";
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
            ElevatedButton(
              onPressed: (_lastUrl != null && !_isLoading)
                  ? () => _loadCsvFromUrl(_lastUrl!)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: (_lastUrl != null) ? const Color(0xFFFFC107) : Colors.grey,
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Reload'),
            ),
            const SizedBox(height: 8),
            const Center(child: Text("From my Google Sheet")),
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
            ElevatedButton(
              onPressed: (_isUrlValid && !_isLoading)
                  ? () => _loadCsvFromUrl(_controller.text)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isUrlValid ? const Color(0xFFFFC107) : Colors.grey,
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Pair and load'),
            ),
            const SizedBox(height: 30),
            const Text('Load words from Clipboard (copied from Excel/Google Sheet - also 4 columns category | word | transcription| translation)', style: TextStyle(fontSize: 16)),
            ElevatedButton(
              onPressed: _isClipboardLoading ? null : _loadCsvFromClipboard,
              child: _isClipboardLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('Load from Clipboard'),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('How to load words'),
        content: const SingleChildScrollView(
          child: Text("""
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
"""),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  //Function to parse the csv data
  List<List<String>> parseCsvData(String csvData, {String delimiter = '\t', String eol = '\n'}) {
    List<List<String>> csvList = [];

    List<String> lines = csvData.split(eol).where((line) => line.trim().isNotEmpty).toList();
    if (lines.isNotEmpty) {
      lines = lines.sublist(1);
    }

    for (var line in lines) {
      List<String> fields = line.split(delimiter);
      while (fields.length < 4) {
        fields.add('');
      }
      fields = fields.map((field) => field.trim()).toList();
      csvList.add(fields);
    }

    return csvList;
  }


  void _scanQRCode() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => QRScanScreen(onUrlReceived: (url) => _loadCsvFromUrl(url))));
  }

  void _loadCsvFromClipboard() async {
    setState(() => _isClipboardLoading = true);
    ClipboardData? data = await Clipboard.getData('text/plain');
    if (data != null && data.text!.isNotEmpty) {
      List<List<String>> csvList = data.text!.split('\n').skip(1).map((e) => e.split('\t')).toList();
      _showImportDialog(csvList);
    }
    setState(() => _isClipboardLoading = false);
  }

  Future<void> _loadCsvFromUrl(String url) async {
    // Check for unsupported Google Sheet URL
    if (url.contains("/edit?gid=")) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error'),
          content: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyMedium,
              children: [
                const TextSpan(
                    text:
                    'URLs of google sheets is not supported. You should provide the URL of the "Published" Google Sheet (menu File / Share / Publish to web), in '),
                TextSpan(
                  text: 'tsv',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const TextSpan(text: ' format.'),
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
      return;
    }

    //Now that it's not a regular google sheet, carry on
    String processedUrl = _processUrl(url); // Pre-process the url

    setState(() {
      _isLoading = true;
    });
    try {
      final response = await http.get(Uri.parse(processedUrl));
      if (response.statusCode == 200) {
        final csvData = utf8.decode(response.bodyBytes);
        List<List<String>> csvList = parseCsvData(csvData);
        _showImportDialog(csvList);
        await _saveLastUrl(url);
      } else {
        throw Exception('Failed to download the CSV file.');
      }
    } catch (e) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Error'),
          content: Text('Failed to load CSV. Please check the URL and try again.\nError: $e'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

//Make this robust regardless of the URLs shared
  String _processUrl(String url) {
    if (url.endsWith("/pubhtml")) {
      return url.replaceFirst("/pubhtml", "/pub?output=tsv");
    } else if (RegExp(r"/pubhtml\?gid=[0-9]+&single=true$").hasMatch(url)) {
      return url.replaceFirst("pubhtml", "pub") + "&output=tsv";
    } else {
      return url;
    }
  }

  //Load the actual csv data into the database
  Future<void> _insertCsvDataIntoDatabase(List<List<String>> csvList, {bool clearExisting = false}) async {
    final dbHelper = DatabaseHelper.instance;
    if (clearExisting) {
      await dbHelper.clearTable();
    }
    for (var row in csvList) {
      Map<String, dynamic> rowData = {
        DatabaseHelper.columnCategory: row.isNotEmpty ? row[0].toString() : '',
        DatabaseHelper.columnWord: row.length > 1 ? row[1].toString() : '',
        DatabaseHelper.columnTranscription: row.length > 2 ? row[2].toString() : '',
        DatabaseHelper.columnTranslation: row.length > 3 ? row[3].toString() : '',
        DatabaseHelper.columnIsActive: 1
      };

      if (!clearExisting) {
        bool exists = await dbHelper.wordExists(rowData[DatabaseHelper.columnWord]);
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
        content: Text('Do you want to REPLACE the current list or MERGE to it? \n\nNumber of words: ${csvList.length}'),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await _insertCsvDataIntoDatabase(csvList, clearExisting: true);
              Navigator.pop(ctx);
              Navigator.pop(context, true);
            },
            child: const Text('Replace'),
          ),
          TextButton(
            onPressed: () async {
              await _insertCsvDataIntoDatabase(csvList, clearExisting: false);
              Navigator.pop(ctx);
              Navigator.pop(context, true);
            },
            child: const Text('Merge'),
          ),
        ],
      ),
    );
  }
}
