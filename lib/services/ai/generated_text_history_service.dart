import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:tri_flash/models/ai_models.dart';

class GeneratedTextHistoryService {
  static const _key = 'generated_text_history_v1';
  static const maxItems = 20;

  Future<List<GeneratedText>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const [];
    final items = <GeneratedText>[];
    for (final value in raw) {
      try {
        items.add(
          GeneratedText.fromJson(jsonDecode(value) as Map<String, dynamic>),
        );
      } catch (_) {}
    }
    return items;
  }

  Future<void> add(GeneratedText item) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await load();
    final updated =
        [
          item,
          ...items.where((old) => old.id != item.id),
        ].take(maxItems).map((entry) => entry.encode()).toList();
    await prefs.setStringList(_key, updated);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
