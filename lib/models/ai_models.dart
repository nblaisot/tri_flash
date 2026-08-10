import 'dart:convert';

enum AiProviderType { chatGpt, openAi, mistral }

extension AiProviderTypeValue on AiProviderType {
  String get value => switch (this) {
    AiProviderType.chatGpt => 'chatgpt',
    AiProviderType.openAi => 'openai',
    AiProviderType.mistral => 'mistral',
  };

  static AiProviderType? fromValue(String? value) {
    for (final provider in AiProviderType.values) {
      if (provider.value == value) return provider;
    }
    return null;
  }
}

class VocabularyEntry {
  const VocabularyEntry({
    required this.id,
    required this.category,
    required this.word,
    required this.transcription,
    required this.translation,
  });

  factory VocabularyEntry.fromMap(Map<String, dynamic> map) => VocabularyEntry(
    id: map['id'] as int? ?? -1,
    category: map['category']?.toString() ?? '',
    word: map['word']?.toString() ?? '',
    transcription: map['transcription']?.toString() ?? '',
    translation: map['translation']?.toString() ?? '',
  );

  factory VocabularyEntry.fromJson(Map<String, dynamic> json) =>
      VocabularyEntry(
        id: json['id'] as int? ?? -1,
        category: json['category']?.toString() ?? '',
        word: json['word']?.toString() ?? '',
        transcription: json['transcription']?.toString() ?? '',
        translation: json['translation']?.toString() ?? '',
      );

  final int id;
  final String category;
  final String word;
  final String transcription;
  final String translation;

  Map<String, dynamic> toJson() => {
    'id': id,
    'category': category,
    'word': word,
    'transcription': transcription,
    'translation': translation,
  };
}

class BilingualSentence {
  const BilingualSentence({required this.source, required this.translation});

  final String source;
  final String translation;
}

class GeneratedText {
  const GeneratedText({
    required this.id,
    required this.source,
    required this.translation,
    required this.createdAt,
    required this.categories,
    required this.targetWordCount,
    required this.outsideVocabularyPercent,
    required this.provider,
    required this.vocabulary,
  });

  factory GeneratedText.fromJson(Map<String, dynamic> json) => GeneratedText(
    id: json['id'] as String,
    source: json['source'] as String,
    translation: json['translation'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    categories: (json['categories'] as List<dynamic>).cast<String>(),
    targetWordCount: json['targetWordCount'] as int,
    outsideVocabularyPercent: json['outsideVocabularyPercent'] as int,
    provider:
        AiProviderTypeValue.fromValue(json['provider'] as String?) ??
        AiProviderType.openAi,
    vocabulary:
        (json['vocabulary'] as List<dynamic>)
            .map(
              (item) => VocabularyEntry.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
  );

  final String id;
  final String source;
  final String translation;
  final DateTime createdAt;
  final List<String> categories;
  final int targetWordCount;
  final int outsideVocabularyPercent;
  final AiProviderType provider;
  final List<VocabularyEntry> vocabulary;

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'translation': translation,
    'createdAt': createdAt.toIso8601String(),
    'categories': categories,
    'targetWordCount': targetWordCount,
    'outsideVocabularyPercent': outsideVocabularyPercent,
    'provider': provider.value,
    'vocabulary': vocabulary.map((item) => item.toJson()).toList(),
  };

  String encode() => jsonEncode(toJson());
}
