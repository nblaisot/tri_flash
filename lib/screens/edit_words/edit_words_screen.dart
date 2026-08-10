import 'package:flutter/material.dart';

import 'package:tri_flash/screens/edit_words/controllers/edit_words_controller.dart';
import 'package:tri_flash/screens/edit_words/widgets/edit_word_dialog.dart';
import 'package:tri_flash/screens/edit_words/widgets/edit_words_filter_sheet.dart';

/// Screen used to browse, filter and edit the database content.
class EditWordsScreen extends StatefulWidget {
  const EditWordsScreen({super.key, this.initialSearch = ''});

  final String initialSearch;

  @override
  State<EditWordsScreen> createState() => _EditWordsScreenState();
}

class _EditWordsScreenState extends State<EditWordsScreen> {
  late final EditWordsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = EditWordsController(initialSearch: widget.initialSearch)
      ..initialise();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Edit Words')),
          body: Column(
            children: [
              _buildSearchBar(),
              Expanded(child: _buildWordList()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller.searchController,
              onChanged: _controller.updateQuery,
              decoration: const InputDecoration(
                labelText: 'Search',
                hintText: 'Filter by Category, Word, etc.',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(25.0)),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => EditWordsFilterSheet(controller: _controller),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => EditWordDialog(controller: _controller),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordList() {
    final words = _controller.filteredWords;
    if (words.isEmpty) {
      return const Center(child: Text('No words match the current filters.'));
    }

    return ListView.builder(
      itemCount: words.length,
      itemBuilder: (context, index) {
        final word = words[index];
        final bool isActive = word['isActive'] == 1;
        return ListTile(
          title: Text(word['word']),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${word['transcription']} - ${word['translation']}'),
              Text(
                word['category'],
                style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => EditWordDialog(
                controller: _controller,
                initialWord: word,
              ),
            ),
          ),
          tileColor: isActive ? Colors.white : Colors.grey[300],
          onLongPress: () => _controller.toggleWordActive(word['id'], isActive),
        );
      },
    );
  }
}
