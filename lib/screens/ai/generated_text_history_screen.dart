import 'package:flutter/material.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/screens/ai/generated_text_viewer_screen.dart';
import 'package:tri_flash/services/ai/generated_text_history_service.dart';

class GeneratedTextHistoryScreen extends StatefulWidget {
  const GeneratedTextHistoryScreen({super.key});

  @override
  State<GeneratedTextHistoryScreen> createState() =>
      _GeneratedTextHistoryScreenState();
}

class _GeneratedTextHistoryScreenState
    extends State<GeneratedTextHistoryScreen> {
  final _history = GeneratedTextHistoryService();
  List<GeneratedText>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _history.load();
    if (mounted) setState(() => _items = items);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('textHistory')),
        actions: [
          IconButton(
            tooltip: l10n.text('deleteHistory'),
            onPressed:
                _items?.isNotEmpty == true
                    ? () async {
                      await _history.clear();
                      await _load();
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(content: Text(l10n.text('historyCleared'))),
                      );
                    }
                    : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body:
          _items == null
              ? const Center(child: CircularProgressIndicator())
              : _items!.isEmpty
              ? Center(child: Text(l10n.text('noHistory')))
              : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: _items!.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final item = _items![index];
                  return Card(
                    child: ListTile(
                      title: Text(
                        item.source,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${item.createdAt.toLocal()}\n${l10n.text('historyDetails', {'count': item.targetWordCount, 'percent': item.outsideVocabularyPercent})}',
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder:
                                  (_) => GeneratedTextViewerScreen(text: item),
                            ),
                          ),
                    ),
                  );
                },
              ),
    );
  }
}
