import 'package:flutter/material.dart';
import 'package:tri_flash/l10n/app_localizations.dart';

/// Custom [AppBar] used on the main screen.
///
/// The widget exposes callbacks for the category selector, display selector and
/// overflow menu so the parent can handle navigation/state changes.
class MainScreenAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MainScreenAppBar({
    required this.categoryButtonText,
    required this.displayLabel,
    required this.onShowCategorySelection,
    required this.onShowDisplaySelection,
    required this.onMenuSelected,
    required this.menuButtonKey,
    required this.categoriesButtonKey,
    required this.displayButtonKey,
    super.key,
  });

  final String categoryButtonText;
  final String displayLabel;

  final VoidCallback onShowCategorySelection;
  final VoidCallback onShowDisplaySelection;
  final void Function(String) onMenuSelected;

  final GlobalKey menuButtonKey;
  final GlobalKey categoriesButtonKey;
  final GlobalKey displayButtonKey;

  @override
  Size get preferredSize => const Size.fromHeight(156); // AppBar + extra controls.

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('Tri Flash'),
      actions: [
        Container(
          key: menuButtonKey,
          child: PopupMenuButton<String>(
            onSelected: onMenuSelected,
            itemBuilder:
                (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'generate_text',
                    child: ListTile(
                      leading: const Icon(Icons.auto_stories),
                      title: Text(context.l10n.text('generateText')),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'translation_quiz',
                    child: ListTile(
                      leading: const Icon(Icons.quiz_outlined),
                      title: Text(context.l10n.text('translationQuiz')),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'text_history',
                    child: ListTile(
                      leading: const Icon(Icons.history),
                      title: Text(context.l10n.text('textHistory')),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Text(context.l10n.text('editWords')),
                  ),
                  PopupMenuItem<String>(
                    value: 'load',
                    child: Text(context.l10n.text('loadWords')),
                  ),
                  PopupMenuItem<String>(
                    value: 'copy_csv',
                    child: Text(context.l10n.text('copyDatabase')),
                  ),
                  PopupMenuItem<String>(
                    value: 'settings',
                    child: Text(context.l10n.text('settings')),
                  ),
                ],
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          alignment: Alignment.centerLeft,
          height: 100.0,
          child: Padding(
            padding: const EdgeInsets.only(top: 20.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.text('categories'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        key: categoriesButtonKey,
                        child: ElevatedButton(
                          onPressed: onShowCategorySelection,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).scaffoldBackgroundColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          child: Text(
                            categoryButtonText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.text('display'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        key: displayButtonKey,
                        child: ElevatedButton(
                          onPressed: onShowDisplaySelection,
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).scaffoldBackgroundColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            minimumSize: const Size(double.infinity, 48),
                          ),
                          child: Text(
                            displayLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
