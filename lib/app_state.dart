import 'package:shared_preferences/shared_preferences.dart';

class AppState {
  // Words data
  List<Map<String, dynamic>> words = [];
  int currentIndex = 0;
  int totalWords = 0;
  int activeWords = 0;

  // Display settings
  bool showWord = true;
  bool showTranscription = false;
  bool showTranslation = false;
  String defaultVisibleLanguage = 'Word';

  // TTS settings
  double ttsSpeed = 0.6;
  String forcedLanguage = 'Auto';

  // Onboarding
  int onboardingStep = 0;
  bool showOnboarding = false;

  void updateWords(List<Map<String, dynamic>> newWords, int total, int active) {
    words = newWords;
    totalWords = total;
    activeWords = active;
  }

  void resetVisibility() {
    showWord = defaultVisibleLanguage == 'Word';
    showTranscription = defaultVisibleLanguage == 'Transcription';
    showTranslation = defaultVisibleLanguage == 'Translation';
  }

  void setDefaultVisibleLanguage(String value) {
    defaultVisibleLanguage = value;
    resetVisibility();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    ttsSpeed = prefs.getDouble('ttsSpeed') ?? 0.6;
    forcedLanguage = prefs.getString('forcedLanguage') ?? 'Auto';
  }

  Future<bool> shouldShowOnboarding() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('onboarding_done') ?? false);
  }

  void startOnboarding() {
    onboardingStep = 1;
    showOnboarding = true;
  }

  void nextOnboardingStep() {
    if (onboardingStep < 9) {
      onboardingStep++;
    }
  }

  Future<void> completeOnboarding() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    showOnboarding = false;
    onboardingStep = 0;
  }
}