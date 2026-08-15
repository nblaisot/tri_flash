import 'package:flutter/material.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/ai_generation_service.dart';

class TranslationQuizSessionScreen extends StatefulWidget {
  const TranslationQuizSessionScreen({
    required this.quiz,
    this.aiGeneration,
    super.key,
  });

  final TranslationQuiz quiz;
  final AiGenerationService? aiGeneration;

  @override
  State<TranslationQuizSessionScreen> createState() =>
      _TranslationQuizSessionScreenState();
}

class _TranslationQuizSessionScreenState
    extends State<TranslationQuizSessionScreen> {
  late final AiGenerationService _aiGeneration;
  late final TextEditingController _answerController;
  var _index = 0;
  var _correctCount = 0;
  var _checking = false;
  var _finished = false;
  TranslationCheckResult? _result;

  TranslationQuizItem get _current => widget.quiz.items[_index];

  @override
  void initState() {
    super.initState();
    _aiGeneration = widget.aiGeneration ?? AiGenerationService();
    _answerController = TextEditingController();
  }

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _checkAnswer() async {
    final answer = _answerController.text.trim();
    if (answer.isEmpty || _checking || _result != null) return;

    setState(() => _checking = true);
    try {
      final result = await _aiGeneration.checkTranslation(
        prompt: _current.prompt,
        userAnswer: answer,
        expectedAnswer: _current.expectedAnswer,
        direction: widget.quiz.direction,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        if (result.isCorrect) _correctCount++;
      });
    } catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(context.l10n.text('aiError')),
              content: Text('$error'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(context.l10n.text('close')),
                ),
              ],
            ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _advance() {
    if (_result == null) return;
    if (_index >= widget.quiz.items.length - 1) {
      setState(() => _finished = true);
      return;
    }
    setState(() {
      _index++;
      _result = null;
      _answerController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      // Keyboard overlays the UI; do not shrink the layout or push content.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(l10n.text('translationQuiz')),
      ),
      body: SafeArea(
        child:
            _finished
                ? _buildSummary(context)
                : _buildQuestion(context),
      ),
    );
  }

  Widget _buildQuestion(BuildContext context) {
    final l10n = context.l10n;
    final total = widget.quiz.items.length;
    final result = _result;
    final isLast = _index >= total - 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.text('quizProgress', {
              'current': _index + 1,
              'total': total,
            }),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: (_index + 1) / total),
          const SizedBox(height: 24),
          Text(
            l10n.text('translateThisSentence'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            _current.prompt,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _answerController,
            enabled: result == null && !_checking,
            minLines: 2,
            maxLines: 5,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.text('yourTranslation'),
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _checkAnswer(),
          ),
          const SizedBox(height: 16),
          if (result == null)
            FilledButton.icon(
              onPressed: _checking ? null : _checkAnswer,
              icon:
                  _checking
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.check),
              label: Text(
                _checking
                    ? l10n.text('checkingTranslation')
                    : l10n.text('checkTranslation'),
              ),
            )
          else ...[
            Card(
              color:
                  result.isCorrect
                      ? Theme.of(context).colorScheme.primaryContainer
                      : Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.isCorrect
                          ? l10n.text('quizCorrect')
                          : l10n.text('quizIncorrect'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(result.feedback),
                    if (!result.isCorrect &&
                        (result.correctedAnswer?.isNotEmpty ?? false)) ...[
                      const SizedBox(height: 12),
                      Text(
                        l10n.text('suggestedCorrection'),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(result.correctedAnswer!),
                      if (result.transcription?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 8),
                        Text(
                          l10n.text('transcription'),
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        SelectableText(result.transcription!),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _advance,
              child: Text(
                isLast ? l10n.text('finishQuiz') : l10n.text('nextSentence'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final l10n = context.l10n;
    final total = widget.quiz.items.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.text('quizSummaryTitle'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.text('quizSummaryBody', {
              'correct': _correctCount,
              'total': total,
            }),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.text('done')),
          ),
        ],
      ),
    );
  }
}
