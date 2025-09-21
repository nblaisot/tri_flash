import 'package:flutter/material.dart';
import 'database_helper.dart';

class EditWordsScreen extends StatefulWidget {
  final String initialSearch;
  const EditWordsScreen({super.key, this.initialSearch = ""});

  @override
  _EditWordsScreenState createState() => _EditWordsScreenState();
}

class _EditWordsScreenState extends State<EditWordsScreen> {
  List<Map<String, dynamic>> words = [];
  List<Map<String, dynamic>> filteredWords = [];
  TextEditingController editingController = TextEditingController();
  String hiddenFilter = 'All'; // Options: All, Hidden, Non-hidden
  List<String> selectedCategories = [];
  List<String> allCategories = [];

  @override
  void initState() {
    super.initState();
    editingController = TextEditingController(text: widget.initialSearch);
    _loadCategories().then((_) => _loadWords());
  }

  // Load all available categories from the database
  Future<void> _loadCategories() async {
    var dbHelper = DatabaseHelper.instance;
    var categories = await dbHelper.queryCategories();
    categories.sort((a, b) => a == '!!' ? -1 : b == '!!' ? 1 : a.compareTo(b));

    setState(() {
      allCategories = categories;
      if (selectedCategories.isEmpty) selectedCategories = List.from(categories);
    });
  }

  // Load all words from the database
  Future<void> _loadWords() async {
    var dbHelper = DatabaseHelper.instance;
    var snapshots = await dbHelper.queryAllRows();

    setState(() {
      words = snapshots.map((snapshot) {
        var wordMap = Map<String, dynamic>.from(snapshot.value);
        wordMap['id'] = snapshot.key;
        return wordMap;
      }).toList();
      _applyFilters(query: editingController.text);
    });
  }

  // Update a word in the database
  void _updateWord(Map<String, dynamic> word) async {
    await DatabaseHelper.instance.update(word);
    await _loadWords();
  }

  // Toggle active status of a word
  void _toggleActive(int id, bool isActive) async {
    await DatabaseHelper.instance.toggleWordActive(id, !isActive);
    _loadWords();
  }

  // Delete a word from the database
  void _deleteWord(int id) async {
    await DatabaseHelper.instance.delete(id);
    _loadWords();
  }

  // Apply filters based on query, hidden status, and selected categories
  void _applyFilters({String query = ''}) {
    setState(() {
      filteredWords = words.where((word) {
        bool matchesQuery = query.isEmpty ||
            word['category'].toLowerCase().contains(query.toLowerCase()) ||
            word['word'].toLowerCase().contains(query.toLowerCase()) ||
            word['transcription'].toLowerCase().contains(query.toLowerCase()) ||
            word['translation'].toLowerCase().contains(query.toLowerCase());

        bool matchesHidden = hiddenFilter == 'All' ||
            (hiddenFilter == 'Hidden' && word['isActive'] == 0) ||
            (hiddenFilter == 'Non-hidden' && word['isActive'] == 1);

        bool matchesCategory = selectedCategories.contains(word['category']);

        return matchesQuery && matchesHidden && matchesCategory;
      }).toList();
    });
  }

  // Create a new word
  Future<void> _createWord(Map<String, dynamic> newWord) async {
    await DatabaseHelper.instance.insert(newWord);
    await _loadWords();
  }

  // Show filter options modal
  void _showFilterModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text("Filter list", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Column(
                children: ['All', 'Hidden', 'Non-hidden'].map((option) => RadioListTile(
                  title: Text(option),
                  value: option,
                  groupValue: hiddenFilter,
                  activeColor: const Color(0xFFFFC107),
                  onChanged: (value) => setModalState(() => hiddenFilter = value!),
                )).toList(),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Categories", style: TextStyle(fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      TextButton(onPressed: () => setModalState(() => selectedCategories = []), child: const Text('Unselect All')),
                      TextButton(onPressed: () => setModalState(() => selectedCategories = List.from(allCategories)), child: const Text('Select All')),
                    ],
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  children: allCategories.map((category) => CheckboxListTile(
                    activeColor: const Color(0xFFFFC107),
                    title: Text(category),
                    value: selectedCategories.contains(category),
                    onChanged: (checked) => setModalState(() =>
                    checked! ? selectedCategories.add(category) : selectedCategories.remove(category)),
                  )).toList(),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  _applyFilters(query: editingController.text);
                  Navigator.pop(context);
                },
                child: const Text("Apply"),
              ),
            ],
          ),
        ),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Edit Words")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (query) => _applyFilters(query: query),
                    controller: editingController,
                    decoration: const InputDecoration(
                      labelText: "Search",
                      hintText: "Filter by Category, Word, etc.",
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(25.0))),
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.filter_list), onPressed: _showFilterModal),
                IconButton(icon: const Icon(Icons.add), onPressed: () => _showEditDialog(null)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: filteredWords.length,
              itemBuilder: (context, index) {
                var word = filteredWords[index];
                bool isActive = word['isActive'] == 1;
                return ListTile(
                  title: Text(word['word']),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${word['transcription']} - ${word['translation']}"),
                      Text(word['category'], style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                    ],
                  ),
                  trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => _showEditDialog(word)),
                  tileColor: isActive ? Colors.white : Colors.grey[300],
                  onLongPress: () => _toggleActive(word['id'], isActive),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  // Show edit dialog for words
  // Show edit dialog for words
  void _showEditDialog(Map<String, dynamic>? word) {
    bool isNew = word == null;

    // Controllers to handle text fields
    TextEditingController categoryController = TextEditingController(text: word?['category'] ?? '');
    TextEditingController wordController = TextEditingController(text: word?['word'] ?? '');
    TextEditingController transcriptionController = TextEditingController(text: word?['transcription'] ?? '');
    TextEditingController translationController = TextEditingController(text: word?['translation'] ?? '');

    // Initially set the hidden state as the opposite of isActive
    bool isHidden = word?['isActive'] == 0;

    showDialog(
      context: context,
      builder: (context) {
        // StatefulBuilder to update the dialog's internal state
        return StatefulBuilder(builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(isNew ? 'Create New Word' : 'Edit Word'),
            content: SingleChildScrollView(
              child: Column(
                children: [
                  TextField(controller: categoryController, decoration: const InputDecoration(labelText: 'Category')),
                  TextField(controller: wordController, decoration: const InputDecoration(labelText: 'Word')),
                  TextField(controller: transcriptionController, decoration: const InputDecoration(labelText: 'Transcription')),
                  TextField(controller: translationController, decoration: const InputDecoration(labelText: 'Translation')),
                  if (!isNew)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Hidden'),
                        Switch(
                          activeColor: const Color(0xFFFFC107), // Yellow color
                          value: isHidden,
                          onChanged: (value) {
                            // Update the dialog internal state
                            setStateDialog(() {
                              isHidden = value;
                            });
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
            actions: [
              if (!isNew)
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _deleteWord(word['id']);
                  },
                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              TextButton(
                onPressed: () {
                  Map<String, dynamic> updatedWord = {
                    'category': categoryController.text,
                    'word': wordController.text,
                    'transcription': transcriptionController.text,
                    'translation': translationController.text,
                    // Important: save the opposite logic (active = not hidden)
                    'isActive': isHidden ? 0 : 1,
                  };
                  if (!isNew) updatedWord['id'] = word['id'];

                  isNew ? _createWord(updatedWord) : _updateWord(updatedWord);
                  Navigator.pop(context);
                },
                child: Text(isNew ? 'Create' : 'Update'),
              ),
            ],
          );
        });
      },
    );
  }
}
