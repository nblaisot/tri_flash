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

  Future<void> _confirmDelete(GeneratedText item) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(l10n.text('deleteGeneratedTextTitle')),
            content: Text(
              l10n.text('deleteGeneratedTextBody', {
                'title': item.title.isEmpty ? item.source : item.title,
              }),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(l10n.text('cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(l10n.text('delete')),
              ),
            ],
          ),
    );
    if (confirmed != true || !mounted) return;
    await _history.remove(item.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.text('textHistory'))),
      body: SafeArea(
        top: false,
        child:
            _items == null
                ? const Center(child: CircularProgressIndicator())
                : _items!.isEmpty
                ? Center(child: Text(l10n.text('noHistory')))
                : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: _items!.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _items![index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      title: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          item.titleTranslation,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize:
                                (theme.textTheme.bodyMedium?.fontSize ?? 14) *
                                0.92,
                          ),
                        ),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap:
                          () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder:
                                  (_) => GeneratedTextViewerScreen(text: item),
                            ),
                          ),
                      onLongPress: () => _confirmDelete(item),
                    );
                  },
                ),
      ),
    );
  }
}
