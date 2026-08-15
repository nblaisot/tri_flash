import 'package:flutter/material.dart';
import 'package:tri_flash/l10n/app_localizations.dart';
import 'package:tri_flash/models/ai_models.dart';
import 'package:tri_flash/services/ai/ai_generation_service.dart';

class TryTranslationDialog extends StatefulWidget {
  const TryTranslationDialog({
    required this.prompt,
    required this.expectedAnswer,
    this.aiGeneration,
    super.key,
  });

  final String prompt;
  final String expectedAnswer;
  final AiGenerationService? aiGeneration;

  @override
  State<TryTranslationDialog> createState() => _TryTranslationDialogState();
}

class _TryTranslationDialogState extends State<TryTranslationDialog> {
  late final AiGenerationService _aiGeneration;
  late final TextEditingController _answerController;
  var _checking = false;
  TranslationCheckResult? _result;

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
        prompt: widget.prompt,
        userAnswer: answer,
        expectedAnswer: widget.expectedAnswer,
        direction: TranslationQuizDirection.sourceToTranslation,
      );
      if (!mounted) return;
      setState(() => _result = result);
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

  void _tryAgain() {
    setState(() {
      _result = null;
      _answerController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = _result;

    return AlertDialog(
      title: Text(l10n.text('tryTranslationTitle')),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.text('translateThisWord'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Text(
                widget.prompt,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _answerController,
                enabled: result == null && !_checking,
                autofocus: true,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: l10n.text('yourTranslation'),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _checkAnswer(),
              ),
              if (result != null) ...[
                const SizedBox(height: 16),
                Card(
                  color:
                      result.isCorrect
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
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
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (result != null)
          TextButton(
            onPressed: _tryAgain,
            child: Text(l10n.text('tryAgain')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.text('close')),
        ),
        if (result == null)
          FilledButton(
            onPressed: _checking ? null : _checkAnswer,
            child:
                _checking
                    ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Text(l10n.text('checkingTranslation')),
                      ],
                    )
                    : Text(l10n.text('checkTranslation')),
          ),
      ],
    );
  }
}
