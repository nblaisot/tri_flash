import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/models/ai_models.dart';

class GeneratedTextViewerScreen extends StatefulWidget {
  const GeneratedTextViewerScreen({required this.text, super.key});

  final GeneratedText text;

  @override
  State<GeneratedTextViewerScreen> createState() =>
      _GeneratedTextViewerScreenState();
}

class _GeneratedTextViewerScreenState extends State<GeneratedTextViewerScreen> {
  bool _translated = false;
  WordAnnotation? _selected;

  String get _visibleText =>
      _translated ? widget.text.translation : widget.text.source;

  List<WordAnnotation> get _annotations =>
      _translated
          ? widget.text.translationAnnotations
          : widget.text.sourceAnnotations;

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
              l10n.text('annotationHint'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: _buildAnnotatedText(context),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar:
          _selected == null ? null : _buildAnnotation(context, _selected!),
    );
  }

  Widget _buildAnnotatedText(BuildContext context) {
    final value = _visibleText;
    final textStyle = TextStyle(
      fontSize: 18,
      height: 1.5,
      color: Theme.of(context).colorScheme.onSurface,
      decoration: TextDecoration.none,
    );
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final annotation in _annotations) {
      if (annotation.start < cursor ||
          annotation.end > value.length ||
          value.substring(annotation.start, annotation.end) !=
              annotation.surface) {
        continue;
      }
      if (annotation.start > cursor) {
        spans.add(
          TextSpan(
            text: value.substring(cursor, annotation.start),
            style: textStyle,
          ),
        );
      }
      final selected = identical(_selected, annotation);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: InkWell(
            borderRadius: BorderRadius.circular(3),
            onTap: () => setState(() => _selected = annotation),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color:
                    selected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Text(annotation.surface, style: textStyle),
              ),
            ),
          ),
        ),
      );
      cursor = annotation.end;
    }
    if (cursor < value.length) {
      spans.add(TextSpan(text: value.substring(cursor), style: textStyle));
    }
    return Text.rich(TextSpan(style: textStyle, children: spans));
  }

  Widget _buildAnnotation(BuildContext context, WordAnnotation annotation) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.primaryContainer,
      elevation: 12,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      annotation.surface,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${l10n.text('pronunciation')}: ${annotation.pronunciation}',
                    ),
                    Text(
                      '${l10n.text('contextualTranslation')}: '
                      '${annotation.contextualTranslation}',
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.text('close'),
                onPressed: () => setState(() => _selected = null),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
