import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/vocabulary_matcher.dart';

class GeneratedTextViewerScreen extends StatefulWidget {
  const GeneratedTextViewerScreen({required this.text, super.key});

  final GeneratedText text;

  @override
  State<GeneratedTextViewerScreen> createState() =>
      _GeneratedTextViewerScreenState();
}

class _GeneratedTextViewerScreenState extends State<GeneratedTextViewerScreen> {
  bool _translated = false;
  VocabularyEntry? _selected;

  String get _visibleText =>
      _translated ? widget.text.translation : widget.text.source;

  Future<void> _copy({required bool both}) async {
    final value =
        both
            ? '${widget.text.source}\n\n${widget.text.translation}'
            : _visibleText;
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.text('copied'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.text('generateText')),
        actions: [
          IconButton(
            tooltip: l10n.text('copy'),
            onPressed: () => _copy(both: false),
            icon: const Icon(Icons.copy),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'both') _copy(both: true);
            },
            itemBuilder:
                (_) => [
                  PopupMenuItem(
                    value: 'both',
                    child: Text(l10n.text('copyBoth')),
                  ),
                ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(l10n.text('sourceText')),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(l10n.text('translationText')),
                ),
              ],
              selected: {_translated},
              onSelectionChanged: (selection) {
                setState(() {
                  _translated = selection.first;
                  _selected = null;
                });
              },
            ),
            const SizedBox(height: 16),
            Text(
              l10n.text('firstMatchHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: _buildAnnotatedText(context),
              ),
            ),
            if (_selected != null) ...[
              const SizedBox(height: 12),
              _buildAnnotation(context, _selected!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnnotatedText(BuildContext context) {
    final value = _visibleText;
    final matches = VocabularyMatcher.findMatches(
      value,
      widget.text.vocabulary,
      translated: _translated,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: value.substring(cursor, match.start)));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => setState(() => _selected = match.entry),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE083),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                value.substring(match.start, match.end),
                style: const TextStyle(fontSize: 18, height: 1.5),
              ),
            ),
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor)));
    }
    return Text.rich(
      TextSpan(
        style: DefaultTextStyle.of(
          context,
        ).style.copyWith(fontSize: 18, height: 1.5),
        children: spans,
      ),
    );
  }

  Widget _buildAnnotation(BuildContext context, VocabularyEntry entry) {
    final l10n = context.l10n;
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _translated ? entry.translation : entry.word,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text('${l10n.text('pronunciation')}: ${entry.transcription}'),
            Text(
              '${_translated ? l10n.text('sourceWord') : l10n.text('translation')}: '
              '${_translated ? entry.word : entry.translation}',
            ),
          ],
        ),
      ),
    );
  }
}
