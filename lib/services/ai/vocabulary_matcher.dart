import 'package:tri_flash/models/ai_models.dart';

class VocabularyMatch {
  const VocabularyMatch({
    required this.start,
    required this.end,
    required this.entry,
  });

  final int start;
  final int end;
  final VocabularyEntry entry;
}

class VocabularyMatcher {
  static List<VocabularyMatch> findMatches(
    String text,
    List<VocabularyEntry> vocabulary, {
    required bool translated,
  }) {
    final firstByTerm = <String, VocabularyEntry>{};
    for (final entry in vocabulary) {
      final term = (translated ? entry.translation : entry.word).trim();
      if (term.isNotEmpty) {
        firstByTerm.putIfAbsent(term.toLowerCase(), () => entry);
      }
    }
    final terms =
        firstByTerm.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    final occupied = List<bool>.filled(text.length, false);
    final matches = <VocabularyMatch>[];
    for (final term in terms) {
      final entry = firstByTerm[term]!;
      final expression = RegExp(
        RegExp.escape(term),
        caseSensitive: false,
        unicode: true,
      );
      for (final match in expression.allMatches(text)) {
        if (!_hasWordBoundaries(text, match.start, match.end, term)) continue;
        if (occupied.sublist(match.start, match.end).any((value) => value)) {
          continue;
        }
        for (var index = match.start; index < match.end; index++) {
          occupied[index] = true;
        }
        matches.add(
          VocabularyMatch(start: match.start, end: match.end, entry: entry),
        );
      }
    }
    matches.sort((a, b) => a.start.compareTo(b.start));
    return matches;
  }

  static bool _hasWordBoundaries(String text, int start, int end, String term) {
    if (RegExp(r'[\u3400-\u9FFF\u3040-\u30FF\uAC00-\uD7AF]').hasMatch(term)) {
      return true;
    }
    final word = RegExp(r'[A-Za-zÀ-ÖØ-öø-ÿĀ-žА-Яа-я0-9]');
    final beforeOk = start == 0 || !word.hasMatch(text[start - 1]);
    final afterOk = end == text.length || !word.hasMatch(text[end]);
    return beforeOk && afterOk;
  }
}
