import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppLocalizations {
  const AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('en'), Locale('fr')];

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  String text(String key, [Map<String, Object> values = const {}]) {
    final language = locale.languageCode == 'fr' ? 'fr' : 'en';
    var value = (_strings[language] ?? _strings['en']!)[key] ?? key;
    for (final entry in values.entries) {
      value = value.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return value;
  }

  static const Map<String, Map<String, String>> _strings = {
    'en': {
      'settings': 'Settings',
      'cancel': 'Cancel',
      'close': 'Close',
      'copy': 'Copy',
      'copyBoth': 'Copy both languages',
      'copied': 'Copied to clipboard',
      'regenerate': 'Regenerate',
      'ai': 'AI',
      'generateSentence': 'Generate example sentence',
      'exampleSentence': 'Example sentence',
      'generateText': 'Generate AI text',
      'textHistory': 'Generated text history',
      'noHistory': 'No generated texts yet',
      'sourceText': 'Original',
      'translationText': 'Translation',
      'selectCategories': 'Select categories',
      'done': 'Done',
      'targetWordCount': 'Target word count',
      'wordCountRange': '20–500',
      'unknownWords': 'Outside vocabulary',
      'generate': 'Generate',
      'generating': 'Generating…',
      'analyzingCorpus': 'Analyzing corpus ({current}/{total})…',
      'generatingBilingualText': 'Generating bilingual text…',
      'annotatingSource': 'Annotating original ({current}/{total})…',
      'annotatingTranslation': 'Annotating translation ({current}/{total})…',
      'savingGeneratedText': 'Saving…',
      'generationCancelled': 'Generation cancelled',
      'noCategories': 'Select at least one category.',
      'noWords': 'No active words were found in those categories.',
      'aiProvider': 'AI provider',
      'chooseProvider': 'Choose an AI provider',
      'chatgptProvider': 'ChatGPT / Codex subscription',
      'chatgptExperimental': 'Experimental subscription access',
      'openaiProvider': 'OpenAI API key',
      'mistralProvider': 'Mistral API key',
      'apiKey': 'API key',
      'save': 'Save',
      'configured': 'Configured',
      'notConfigured': 'Not configured',
      'signIn': 'Sign in with ChatGPT',
      'signOut': 'Sign out',
      'signedIn': 'Signed in',
      'deviceCode': 'One-time code',
      'copyCode': 'Copy code',
      'openBrowser': 'Open in browser',
      'waitingForSignIn': 'Waiting for sign-in…',
      'privacyTitle': 'AI privacy notice',
      'privacyBody':
          'Selected vocabulary and generation instructions will be sent to the AI provider you choose. ChatGPT/Codex subscription access is experimental; OpenAI and Mistral API usage is billed separately by those providers.',
      'continueAction': 'Continue',
      'aiError': 'AI request failed',
      'providerError':
          'The selected AI provider could not complete the request. Check its credentials, connection, and usage limits, then try again.',
      'appLanguage': 'Application language',
      'systemLanguage': 'System default',
      'english': 'English',
      'french': 'French',
      'wordLanguage': 'Word language',
      'translationLanguage': 'Translation language',
      'auto': 'Auto detect',
      'aiSettings': 'AI features',
      'aiSettingsHelp':
          'Choose a provider and the languages used by your vocabulary.',
      'historyDetails': '{count} words · {percent}% outside vocabulary',
      'deleteHistory': 'Clear history',
      'historyCleared': 'Generated text history cleared',
      'editWords': 'Edit words',
      'loadWords': 'Load words',
      'copyDatabase': 'Copy database as TSV',
      'categories': 'Categories:',
      'display': 'Display:',
      'word': 'Word',
      'transcription': 'Transcription',
      'translation': 'Translation',
      'wordsCount': 'Words: {active} / {total}',
      'annotationHint':
          'Tap any word to see its pronunciation and contextual translation.',
      'sourceWord': 'Source word',
      'pronunciation': 'Pronunciation',
      'contextualTranslation': 'Contextual translation',
    },
    'fr': {
      'settings': 'Réglages',
      'cancel': 'Annuler',
      'close': 'Fermer',
      'copy': 'Copier',
      'copyBoth': 'Copier les deux langues',
      'copied': 'Copié dans le presse-papiers',
      'regenerate': 'Régénérer',
      'ai': 'IA',
      'generateSentence': 'Générer une phrase d’exemple',
      'exampleSentence': 'Phrase d’exemple',
      'generateText': 'Générer un texte avec l’IA',
      'textHistory': 'Historique des textes générés',
      'noHistory': 'Aucun texte généré',
      'sourceText': 'Original',
      'translationText': 'Traduction',
      'selectCategories': 'Sélectionner les catégories',
      'done': 'Terminé',
      'targetWordCount': 'Nombre de mots cible',
      'wordCountRange': '20–500',
      'unknownWords': 'Vocabulaire extérieur',
      'generate': 'Générer',
      'generating': 'Génération…',
      'analyzingCorpus': 'Analyse du corpus ({current}/{total})…',
      'generatingBilingualText': 'Génération du texte bilingue…',
      'annotatingSource': 'Annotation de l’original ({current}/{total})…',
      'annotatingTranslation':
          'Annotation de la traduction ({current}/{total})…',
      'savingGeneratedText': 'Enregistrement…',
      'generationCancelled': 'Génération annulée',
      'noCategories': 'Sélectionnez au moins une catégorie.',
      'noWords': 'Aucun mot actif dans ces catégories.',
      'aiProvider': 'Fournisseur d’IA',
      'chooseProvider': 'Choisir un fournisseur d’IA',
      'chatgptProvider': 'Abonnement ChatGPT / Codex',
      'chatgptExperimental': 'Accès expérimental par abonnement',
      'openaiProvider': 'Clé API OpenAI',
      'mistralProvider': 'Clé API Mistral',
      'apiKey': 'Clé API',
      'save': 'Enregistrer',
      'configured': 'Configuré',
      'notConfigured': 'Non configuré',
      'signIn': 'Se connecter avec ChatGPT',
      'signOut': 'Se déconnecter',
      'signedIn': 'Connecté',
      'deviceCode': 'Code à usage unique',
      'copyCode': 'Copier le code',
      'openBrowser': 'Ouvrir dans le navigateur',
      'waitingForSignIn': 'En attente de connexion…',
      'privacyTitle': 'Confidentialité et IA',
      'privacyBody':
          'Le vocabulaire sélectionné et les instructions de génération seront envoyés au fournisseur d’IA choisi. L’accès par abonnement ChatGPT/Codex est expérimental ; les API OpenAI et Mistral sont facturées séparément par ces fournisseurs.',
      'continueAction': 'Continuer',
      'aiError': 'Échec de la requête IA',
      'providerError':
          'Le fournisseur d’IA sélectionné n’a pas pu terminer la requête. Vérifiez ses identifiants, la connexion et les limites d’utilisation, puis réessayez.',
      'appLanguage': 'Langue de l’application',
      'systemLanguage': 'Langue du système',
      'english': 'Anglais',
      'french': 'Français',
      'wordLanguage': 'Langue des mots',
      'translationLanguage': 'Langue des traductions',
      'auto': 'Détection automatique',
      'aiSettings': 'Fonctions d’IA',
      'aiSettingsHelp':
          'Choisissez un fournisseur et les langues de votre vocabulaire.',
      'historyDetails': '{count} mots · {percent}% hors vocabulaire',
      'deleteHistory': 'Effacer l’historique',
      'historyCleared': 'Historique des textes générés effacé',
      'editWords': 'Modifier les mots',
      'loadWords': 'Charger des mots',
      'copyDatabase': 'Copier la base en TSV',
      'categories': 'Catégories :',
      'display': 'Affichage :',
      'word': 'Mot',
      'transcription': 'Prononciation',
      'translation': 'Traduction',
      'wordsCount': 'Mots : {active} / {total}',
      'annotationHint':
          'Touchez un mot pour voir sa prononciation et sa traduction contextuelle.',
      'sourceWord': 'Mot source',
      'pronunciation': 'Prononciation',
      'contextualTranslation': 'Traduction contextuelle',
    },
  };
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.supportedLocales.any(
    (item) => item.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture(AppLocalizations(locale));

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
