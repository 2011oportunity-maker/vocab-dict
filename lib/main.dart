import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VocabApp());
}

/* ========================================================================== */
/*                                   MODELS                                   */
/* ========================================================================== */

class WordEntry {
  final int? id;
  final String source;
  final String target;
  final String langFrom;
  final String langTo;
  final String date;

  WordEntry({
    this.id,
    required this.source,
    required this.target,
    required this.langFrom,
    required this.langTo,
    required this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'source': source,
      'target': target,
      'lang_from': langFrom,
      'lang_to': langTo,
      'date': date,
    };
  }

  factory WordEntry.fromMap(Map<String, dynamic> map) {
    return WordEntry(
      id: map['id'] as int?,
      source: map['source'] as String,
      target: map['target'] as String,
      langFrom: map['lang_from'] as String,
      langTo: map['lang_to'] as String,
      date: map['date'] as String,
    );
  }
}

/* ========================================================================== */
/*                               DATABASE HELPER                              */
/* ========================================================================== */

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('vocab_dictionary.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE words (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source TEXT NOT NULL,
        target TEXT NOT NULL,
        lang_from TEXT NOT NULL,
        lang_to TEXT NOT NULL,
        date TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertWord(WordEntry word) async {
    final db = await instance.database;
    return await db.insert('words', word.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<WordEntry>> getAllWords() async {
    final db = await instance.database;
    final maps = await db.query('words', orderBy: 'id DESC');
    return maps.map((map) => WordEntry.fromMap(map)).toList();
  }

  Future<int> deleteWord(int id) async {
    final db = await instance.database;
    return await db.delete('words', where: 'id = ?', whereArgs: [id]);
  }
}

/* ========================================================================== */
/*                            TRANSLATION SERVICE                             */
/* ========================================================================== */

class TranslationService {
  static Future<String> translate({
    required String text,
    required String from,
    required String to,
  }) async {
    final uri = Uri.parse(
      'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(text)}&langpair=$from|$to',
    );
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final translated = data['responseData']?['translatedText'];
      if (translated != null && translated.toString().trim().isNotEmpty) {
        return translated.toString();
      }
      throw Exception(data['responseDetails'] ?? 'Empty translation received');
    }
    throw Exception('Server error: HTTP ${response.statusCode}');
  }
}

/* ========================================================================== */
/*                                 TTS HELPER                                 */
/* ========================================================================== */

class TtsHelper {
  static final FlutterTts _tts = FlutterTts();

  static const Map<String, String> _localeMap = {
    'ru': 'ru-RU',
    'en': 'en-US',
    'ro': 'ro-RO',
  };

  static Future<void> speak(String text, String langCode) async {
    if (text.trim().isEmpty) return;
    final locale = _localeMap[langCode] ?? 'en-US';
    await _tts.stop();
    await _tts.setLanguage(locale);
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.speak(text);
  }

  static Future<void> stop() async {
    await _tts.stop();
  }
}

/* ========================================================================== */
/*                                MAIN APP & UI                               */
/* ========================================================================== */

class VocabApp extends StatelessWidget {
  const VocabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vocab Dictionary',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const MainHomeScreen(),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  final GlobalKey<_SavedWordsTabState> _savedWordsKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vocabulary & Flashcards'),
          bottom: TabBar(
            onTap: (index) {
              if (index == 1) {
                _savedWordsKey.currentState?.reloadWords();
              }
            },
            tabs: const [
              Tab(icon: Icon(Icons.translate), text: 'Translate'),
              Tab(icon: Icon(Icons.style), text: 'Saved & Cards'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            TranslateTab(
              onWordSaved: () {
                _savedWordsKey.currentState?.reloadWords();
              },
            ),
            SavedWordsTab(key: _savedWordsKey),
          ],
        ),
      ),
    );
  }
}

/* ========================================================================== */
/*                              TAB 1: TRANSLATE                              */
/* ========================================================================== */

class TranslateTab extends StatefulWidget {
  final VoidCallback onWordSaved;
  const TranslateTab({super.key, required this.onWordSaved});

  @override
  State<TranslateTab> createState() => _TranslateTabState();
}

class _TranslateTabState extends State<TranslateTab> {
  final TextEditingController _inputController = TextEditingController();
  final List<List<String>> _supportedPairs = const [
    ['ru', 'en'],
    ['ro', 'ru'],
    ['ro', 'en'],
  ];

  late String _selectedFrom;
  late String _selectedTo;
  String _translationResult = '';
  bool _isLoading = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _selectedFrom = _supportedPairs[0][0];
    _selectedTo = _supportedPairs[0][1];
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _swapLanguages() {
    setState(() {
      final temp = _selectedFrom;
      _selectedFrom = _selectedTo;
      _selectedTo = temp;
      _translationResult = '';
      _errorMessage = '';
    });
  }

  void _onPairSelected(List<String> pair) {
    setState(() {
      _selectedFrom = pair[0];
      _selectedTo = pair[1];
      _translationResult = '';
      _errorMessage = '';
    });
  }

  Future<void> _performTranslation() async {
    final query = _inputController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _translationResult = '';
      _errorMessage = '';
    });

    try {
      final res = await TranslationService.translate(
        text: query,
        from: _selectedFrom,
        to: _selectedTo,
      );
      setState(() {
        _translationResult = res;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveWord() async {
    final query = _inputController.text.trim();
    if (query.isEmpty || _translationResult.isEmpty) return;

    final entry = WordEntry(
      source: query,
      target: _translationResult,
      langFrom: _selectedFrom,
      langTo: _selectedTo,
      date: DateTime.now().toIso8601String(),
    );

    await DatabaseHelper.instance.insertWord(entry);
    widget.onWordSaved();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved to list'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 8.0,
                children: _supportedPairs.map((pair) {
                  final isCurrentPair =
                      (_selectedFrom == pair[0] && _selectedTo == pair[1]) ||
                      (_selectedFrom == pair[1] && _selectedTo == pair[0]);
                  return ChoiceChip(
                    label: Text(
                        '${pair[0].toUpperCase()} - ${pair[1].toUpperCase()}'),
                    selected: isCurrentPair,
                    onSelected: (selected) {
                      if (selected) _onPairSelected(pair);
                    },
                  );
                }).toList(),
              ),
              IconButton.filledTonal(
                tooltip: 'Reverse direction',
                icon: const Icon(Icons.swap_horiz),
                onPressed: _swapLanguages,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '${_selectedFrom.toUpperCase()} ➔ ${_selectedTo.toUpperCase()}',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _inputController,
            decoration: InputDecoration(
              labelText: 'Enter word or phrase',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => _inputController.clear(),
              ),
            ),
            onSubmitted: (_) => _performTranslation(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isLoading ? null : _performTranslation,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search),
            label: const Text('Translate'),
          ),
          if (_errorMessage.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          if (_translationResult.isNotEmpty) ...[
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _inputController.text.trim(),
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                _selectedFrom.toUpperCase(),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.volume_up),
                          onPressed: () => TtsHelper.speak(
                            _inputController.text.trim(),
                            _selectedFrom,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _translationResult,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              Text(
                                _selectedTo.toUpperCase(),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.volume_up),
                          onPressed: () => TtsHelper.speak(
                            _translationResult,
                            _selectedTo,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.bookmark_add),
                        label: const Text('Save to List'),
                        onPressed: _saveWord,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* ========================================================================== */
/*                        TAB 2: SAVED WORDS & CARDS                          */
/* ========================================================================== */

class SavedWordsTab extends StatefulWidget {
  const SavedWordsTab({super.key});

  @override
  State<SavedWordsTab> createState() => _SavedWordsTabState();
}

class _SavedWordsTabState extends State<SavedWordsTab> {
  List<WordEntry> _words = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    reloadWords();
  }

  Future<void> reloadWords() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getAllWords();
    setState(() {
      _words = data;
      _isLoading = false;
    });
  }

  Future<void> _delete(int id) async {
    await DatabaseHelper.instance.deleteWord(id);
    reloadWords();
  }

  void _openReviewMode() {
    if (_words.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FlashcardReviewScreen(words: _words),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_words.isEmpty) {
      return const Center(
        child: Text('No words saved yet. Translate and save words first!'),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Saved: ${_words.length}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              FilledButton.icon(
                icon: const Icon(Icons.school),
                label: const Text('Review Flashcards'),
                onPressed: _openReviewMode,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: _words.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = _words[index];
              return ListTile(
                title: Text(item.source,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  '${item.target} (${item.langFrom.toUpperCase()} ➔ ${item.langTo.toUpperCase()})',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.volume_up, size: 20),
                      onPressed: () =>
                          TtsHelper.speak(item.source, item.langFrom),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      color: Theme.of(context).colorScheme.error,
                      onPressed: () => _delete(item.id!),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/* ========================================================================== */
/*                          FLASHCARD REVIEW SCREEN                           */
/* ========================================================================== */

class FlashcardReviewScreen extends StatefulWidget {
  final List<WordEntry> words;
  const FlashcardReviewScreen({super.key, required this.words});

  @override
  State<FlashcardReviewScreen> createState() => _FlashcardReviewScreenState();
}

class _FlashcardReviewScreenState extends State<FlashcardReviewScreen> {
  int _currentIndex = 0;
  bool _revealed = false;

  void _nextCard() {
    if (_currentIndex < widget.words.length - 1) {
      setState(() {
        _currentIndex++;
        _revealed = false;
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prevCard() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _revealed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.words[_currentIndex];
    final progress = '${_currentIndex + 1} / ${widget.words.length}';

    return Scaffold(
      appBar: AppBar(
        title: Text('Review Flashcards ($progress)'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            LinearProgressIndicator(
              value: (_currentIndex + 1) / widget.words.length,
            ),
            const SizedBox(height: 32),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _revealed = !_revealed;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _revealed
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          current.langFrom.toUpperCase(),
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          current.source,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.volume_up),
                          onPressed: () => TtsHelper.speak(
                              current.source, current.langFrom),
                        ),
                        const SizedBox(height: 24),
                        const Divider(),
                        const SizedBox(height: 24),
                        if (_revealed) ...[
                          Text(
                            current.langTo.toUpperCase(),
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            current.target,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                                ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.volume_up),
                            onPressed: () => TtsHelper.speak(
                                current.target, current.langTo),
                          ),
                        ] else ...[
                          const Icon(Icons.touch_app,
                              size: 32, color: Colors.grey),
                          const SizedBox(height: 8),
                          const Text(
                            'Tap card to reveal translation',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Previous'),
                  onPressed: _currentIndex > 0 ? _prevCard : null,
                ),
                FilledButton.icon(
                  label: Text(_currentIndex == widget.words.length - 1
                      ? 'Finish'
                      : 'Next'),
                  icon: Icon(_currentIndex == widget.words.length - 1
                      ? Icons.check
                      : Icons.arrow_forward),
                  onPressed: _nextCard,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
