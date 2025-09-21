import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tts_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TtsService _ttsService = TtsService();

  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _ttsService.initialize();   // loads supported languages, sets awaitSpeakCompletion
      await _ttsService.loadFromPrefs(); // loads saved speed + forced language and applies them
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not initialize TTS: $e'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  @override
  void dispose() {
    _ttsService.dispose();
    super.dispose();
  }

  List<String> get _languageItems {
    final langs = _ttsService.supportedLanguages;
    if (langs.isEmpty) return const ['Auto'];
    return ['Auto', ...langs];
  }

  @override
  Widget build(BuildContext context) {
    final currentSpeed = _ttsService.speechRate;
    final currentLang = _languageItems.contains(_ttsService.forcedLanguage)
        ? _ttsService.forcedLanguage
        : 'Auto';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // TTS Speed Setting
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.speed, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Text-to-Speech Speed: ${currentSpeed.toStringAsFixed(1)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: currentSpeed,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9,
                    label: currentSpeed.toStringAsFixed(1),
                    activeColor: const Color(0xFFFFC107),
                    onChanged: (double value) async {
                      // Update engine immediately for audible feedback
                      await _ttsService.updateSettings(speed: value);
                      if (mounted) setState(() {});
                    },
                    onChangeEnd: (double _) async {
                      await _ttsService.saveToPrefs();
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: const [
                      Text('Slow', style: TextStyle(fontSize: 12)),
                      Text('Normal', style: TextStyle(fontSize: 12)),
                      Text('Fast', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Language Setting
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.language, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Force Language',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Select "Auto" to detect language automatically based on text characters, '
                        'or choose a specific language.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<String>(
                      value: currentLang,
                      isExpanded: true,
                      underline: const SizedBox(),
                      icon: const Icon(Icons.arrow_drop_down),
                      items: _languageItems.map((String lang) {
                        String displayText = lang;
                        if (lang == 'Auto') {
                          displayText = 'Auto (Detect automatically)';
                        } else if (lang.contains('-')) {
                          displayText = _formatLanguageCode(lang);
                        }
                        return DropdownMenuItem<String>(
                          value: lang,
                          child: Text(
                            displayText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (String? newValue) async {
                        if (newValue == null) return;
                        await _ttsService.updateSettings(forcedLang: newValue);
                        await _ttsService.saveToPrefs();
                        if (mounted) setState(() {});
                        // Confirmation
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Language changed to: ${newValue == "Auto" ? "Auto-detect" : newValue}',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Test TTS Button
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.volume_up, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Test Text-to-Speech',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        // A short English sentence works with Auto (will detect as en-US)
                        await _ttsService.stop();
                        await _ttsService.speak(
                          "Hello, this is a test of text to speech with current settings.",
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('TTS test failed: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play Test'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 40),

          // Reset Onboarding Button
          Center(
            child: ElevatedButton.icon(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('onboarding_done', false);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "Onboarding tips have been reset. They will show when you return to the main screen.",
                    ),
                    duration: Duration(seconds: 3),
                  ),
                );
              },
              icon: const Icon(Icons.restart_alt),
              label: const Text("Reset Onboarding Tips"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey.shade300,
                foregroundColor: Colors.black,
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Info Section
          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 20, color: Colors.blue),
                      SizedBox(width: 8),
                      Text(
                        'Tips',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Auto-detect works best for non-Latin scripts (Japanese, Chinese, Arabic, etc.)\n'
                        '• For Latin-based text, consider selecting a specific language\n'
                        '• If TTS fails, try installing additional language packs in your device settings',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to format language codes for display
  String _formatLanguageCode(String code) {
    final Map<String, String> languageNames = {
      'ar': 'Arabic',
      'en': 'English',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'it': 'Italian',
      'pt': 'Portuguese',
      'ru': 'Russian',
      'zh': 'Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'ar': 'Arabic',
      'hi': 'Hindi',
      'he': 'Hebrew',
      'th': 'Thai',
      'vi': 'Vietnamese',
      'pl': 'Polish',
      'nl': 'Dutch',
      'sv': 'Swedish',
      'da': 'Danish',
      'no': 'Norwegian',
      'fi': 'Finnish',
      'cs': 'Czech',
      'hu': 'Hungarian',
      'el': 'Greek',
      'tr': 'Turkish',
      'id': 'Indonesian',
      'ms': 'Malay',
      'uk': 'Ukrainian',
      'ro': 'Romanian',
      'bg': 'Bulgarian',
      'hr': 'Croatian',
      'sk': 'Slovak',
      'sl': 'Slovenian',
      'lt': 'Lithuanian',
      'lv': 'Latvian',
      'et': 'Estonian',
      'is': 'Icelandic',
      'sq': 'Albanian',
      'mk': 'Macedonian',
      'sr': 'Serbian',
      'bs': 'Bosnian',
      'ca': 'Catalan',
      'eu': 'Basque',
      'gl': 'Galician',
      'cy': 'Welsh',
      'ta': 'Tamil',
      'te': 'Telugu',
      'ml': 'Malayalam',
      'kn': 'Kannada',
      'mr': 'Marathi',
      'gu': 'Gujarati',
      'bn': 'Bengali',
      'pa': 'Punjabi',
      'ur': 'Urdu',
      'ne': 'Nepali',
      'si': 'Sinhala',
      'km': 'Khmer',
      'lo': 'Lao',
      'my': 'Burmese',
      'ka': 'Georgian',
      'am': 'Amharic',
      'sw': 'Swahili',
      'fil': 'Filipino',
      'jv': 'Javanese',
      'su': 'Sundanese',
    };

    final parts = code.split('-');
    if (parts.isEmpty) return code;

    final langCode = parts[0].toLowerCase();
    final regionCode = parts.length > 1 ? parts[1].toUpperCase() : null;

    final langName = languageNames[langCode] ?? langCode.toUpperCase();
    if (regionCode != null) return '$langName ($regionCode)';
    return langName;
  }
}