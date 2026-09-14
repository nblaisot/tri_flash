import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:tri_flash/models/ai_models.dart';

enum LocalTextCorpusBudgetReason {
  allowed,
  tooManyEntries,
  tokenEstimateExceeded,
}

@immutable
class LocalTextCorpusBudget {
  const LocalTextCorpusBudget({
    required this.entryCount,
    required this.entryLimit,
    required this.estimatedSegmentTokens,
    required this.tokenBudget,
    required this.segmentCount,
    required this.reason,
  });

  final int entryCount;
  final int entryLimit;
  final int estimatedSegmentTokens;
  final int tokenBudget;
  final int segmentCount;
  final LocalTextCorpusBudgetReason reason;

  bool get isAllowed => reason == LocalTextCorpusBudgetReason.allowed;
}

class LocalTextCorpusLimitException implements Exception {
  const LocalTextCorpusLimitException(this.budget);

  final LocalTextCorpusBudget budget;

  @override
  String toString() =>
      'Local text generation corpus exceeds its safe on-device budget.';
}

class LocalTextCorpusBudgetEvaluator {
  const LocalTextCorpusBudgetEvaluator._();

  static const portableTokenLimit = 4096;
  static const outputReserve = 1536;
  static const safetyReserve = 256;
  static const maxInputTokens = 2800;
  static const passageWordsPerSegment = 75;

  // Covers passage instructions, response schema, and later-segment continuity.
  static const promptAndContinuityReserve = 700;

  static int entryLimitFor(int targetWordCount) {
    final segments = max(1, (targetWordCount / passageWordsPerSegment).ceil());
    return min(2 * targetWordCount, 100 * segments);
  }

  static LocalTextCorpusBudget evaluate({
    required int targetWordCount,
    required List<VocabularyEntry> vocabulary,
    required int deviceTokenLimit,
  }) {
    final segmentCount = max(
      1,
      (targetWordCount / passageWordsPerSegment).ceil(),
    );
    final entryLimit = entryLimitFor(targetWordCount);
    final totalLimit = min(portableTokenLimit, max(1, deviceTokenLimit));
    final inputBudget = min(
      maxInputTokens,
      max(256, totalLimit - outputReserve - safetyReserve),
    );
    final vocabularyTokenBudget = max(
      0,
      inputBudget - promptAndContinuityReserve,
    );
    final segmentTokens = List<int>.filled(segmentCount, 0);
    final byCategory = <String, List<VocabularyEntry>>{};
    for (final entry in vocabulary) {
      byCategory.putIfAbsent(entry.category, () => []).add(entry);
    }
    final interleaved = <VocabularyEntry>[];
    var added = true;
    for (var offset = 0; added; offset++) {
      added = false;
      for (final entries in byCategory.values) {
        if (offset < entries.length) {
          interleaved.add(entries[offset]);
          added = true;
        }
      }
    }
    for (var index = 0; index < interleaved.length; index++) {
      final entry = interleaved[index];
      final serialized = jsonEncode({
        'source': entry.word,
        'translation': entry.translation,
        'category': entry.category,
      });
      segmentTokens[index % segmentCount] += estimateTokens(serialized);
    }
    final estimatedSegmentTokens = segmentTokens.fold<int>(0, max);
    final reason =
        vocabulary.length > entryLimit
            ? LocalTextCorpusBudgetReason.tooManyEntries
            : estimatedSegmentTokens > vocabularyTokenBudget
            ? LocalTextCorpusBudgetReason.tokenEstimateExceeded
            : LocalTextCorpusBudgetReason.allowed;
    return LocalTextCorpusBudget(
      entryCount: vocabulary.length,
      entryLimit: entryLimit,
      estimatedSegmentTokens: estimatedSegmentTokens,
      tokenBudget: vocabularyTokenBudget,
      segmentCount: segmentCount,
      reason: reason,
    );
  }

  static int estimateTokens(String value) {
    var units = 0.0;
    for (final rune in value.runes) {
      final isCjk =
          (rune >= 0x3400 && rune <= 0x9fff) ||
          (rune >= 0x3040 && rune <= 0x30ff) ||
          (rune >= 0xac00 && rune <= 0xd7af);
      units += isCjk ? 1 : 1 / 3;
    }
    return (units * 1.2).ceil();
  }
}
