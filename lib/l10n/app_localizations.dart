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
      'textHistory': 'Past generated texts',
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
      'generatingBilingualText': 'Generating bilingual text…',
      'annotatingSource': 'Annotating original…',
      'savingGeneratedText': 'Saving…',
      'generationCancelled': 'Generation cancelled',
      'corpusTooLarge':
          'Corpus is too large for one generation request. Select fewer categories and try again.',
      'noCategories': 'Select at least one category.',
      'noWords': 'No active words were found in those categories.',
      'aiProvider': 'AI provider',
      'chooseProvider': 'Choose an AI provider',
      'chatgptProvider': 'ChatGPT / Codex subscription',
      'chatgptExperimental': 'Experimental subscription access',
      'openaiProvider': 'OpenAI API key',
      'mistralProvider': 'Mistral API key',
      'onDeviceProvider': 'On-device AI (private)',
      'onDeviceProviderHelp': 'Runs on your phone. Vocabulary stays on the device.',
      'onDeviceSetupAction': 'Set up',
      'onDeviceDownloadTitle': 'Download on-device model',
      'onDeviceDownloadBody':
          'Tri Flash needs to download the on-device AI model once. After that, generation works offline and your prompts stay on this device.',
      'onDeviceDownloadAction': 'Download model',
      'onDeviceDownloading': 'The on-device model is downloading…',
      'onDeviceUnavailable': 'On-device AI is not available on this device.',
      'onDeviceTemporarilyUnavailable':
          'On-device AI is temporarily unavailable. Try again later.',
      'onDeviceReady': 'On-device AI is ready.',
      'onDeviceDownloadRequired': 'Download the on-device model to continue.',
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
      'waitingForSignIn': 'Waiting for you to complete sign-in…',
      'waitingForSignInHint':
          'This is normal and does not mean your internet connection is down.',
      'privacyTitle': 'AI privacy notice',
      'privacyBody':
          'Selected vocabulary and generation instructions will be sent to the AI provider you choose. ChatGPT/Codex subscription access is experimental; OpenAI and Mistral API usage is billed separately by those providers. If you choose on-device AI, prompts stay on your phone and are not sent to a cloud provider.',
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
      'delete': 'Delete',
      'deleteGeneratedTextTitle': 'Delete this text?',
      'deleteGeneratedTextBody':
          '“{title}” will be removed from your history. This cannot be undone.',
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
      'textHistory': 'Textes générés',
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
      'generatingBilingualText': 'Génération du texte bilingue…',
      'annotatingSource': 'Annotation de l’original…',
      'savingGeneratedText': 'Enregistrement…',
      'generationCancelled': 'Génération annulée',
      'corpusTooLarge':
          'Le corpus est trop grand pour une seule requête. Sélectionnez moins de catégories et réessayez.',
      'noCategories': 'Sélectionnez au moins une catégorie.',
      'noWords': 'Aucun mot actif dans ces catégories.',
      'aiProvider': 'Fournisseur d’IA',
      'chooseProvider': 'Choisir un fournisseur d’IA',
      'chatgptProvider': 'Abonnement ChatGPT / Codex',
      'chatgptExperimental': 'Accès expérimental par abonnement',
      'openaiProvider': 'Clé API OpenAI',
      'mistralProvider': 'Clé API Mistral',
      'onDeviceProvider': 'IA locale (confidentielle)',
      'onDeviceProviderHelp':
          'S’exécute sur votre téléphone. Le vocabulaire reste sur l’appareil.',
      'onDeviceSetupAction': 'Configurer',
      'onDeviceDownloadTitle': 'Télécharger le modèle local',
      'onDeviceDownloadBody':
          'Tri Flash doit télécharger une fois le modèle d’IA local. Ensuite, la génération fonctionne hors ligne et vos prompts restent sur cet appareil.',
      'onDeviceDownloadAction': 'Télécharger le modèle',
      'onDeviceDownloading': 'Le modèle local est en cours de téléchargement…',
      'onDeviceUnavailable':
          'L’IA locale n’est pas disponible sur cet appareil.',
      'onDeviceTemporarilyUnavailable':
          'L’IA locale est temporairement indisponible. Réessayez plus tard.',
      'onDeviceReady': 'L’IA locale est prête.',
      'onDeviceDownloadRequired':
          'Téléchargez le modèle local pour continuer.',
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
      'waitingForSignIn': 'En attente de la validation ChatGPT…',
      'waitingForSignInHint':
          'C’est normal : l’application attend que vous vous connectiez ci-dessus, pas que le réseau fonctionne.',
      'privacyTitle': 'Confidentialité et IA',
      'privacyBody':
          'Le vocabulaire sélectionné et les instructions de génération seront envoyés au fournisseur d’IA choisi. L’accès par abonnement ChatGPT/Codex est expérimental ; les API OpenAI et Mistral sont facturées séparément par ces fournisseurs. Si vous choisissez l’IA locale, les prompts restent sur votre téléphone et ne sont pas envoyés à un fournisseur cloud.',
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
      'delete': 'Supprimer',
      'deleteGeneratedTextTitle': 'Supprimer ce texte ?',
      'deleteGeneratedTextBody':
          '« {title} » sera retiré de votre historique. Cette action est irréversible.',
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
