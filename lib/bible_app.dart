import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BibleApp extends StatefulWidget {
  const BibleApp({super.key, this.repository});

  final BibleRepository? repository;

  @override
  State<BibleApp> createState() => _BibleAppState();
}

class _BibleAppState extends State<BibleApp> {
  late final BibleRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? BibleRepository();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bíblia',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: HomePage(repository: _repository),
    );
  }
}

class BibleRepository {
  BibleRepository({AssetBundle? assetBundle, bool useCompute = true})
      : _assetBundle = assetBundle ?? rootBundle,
        _useCompute = useCompute;

  final AssetBundle _assetBundle;
  final bool _useCompute;

  Future<List<BibleVersionRef>>? _versionsFuture;
  final Map<String, Future<List<BibleBook>>> _booksByVersion = {};

  Future<List<BibleVersionRef>> listVersions() {
    return _versionsFuture ??= _loadVersions();
  }

  Future<List<BibleBook>> loadBooks(String versionAbbreviation) {
    return _booksByVersion[versionAbbreviation] ??=
        _loadBooksForVersion(versionAbbreviation);
  }

  Future<List<BibleVersionRef>> _loadVersions() async {
    final raw = await _assetBundle.loadString('json/index.json');
    final normalized = _stripBom(raw);
    final dynamic decoded = _useCompute ? await compute(_decodeJson, normalized) : _decodeJson(normalized);
    final List<dynamic> languages = decoded as List<dynamic>;

    final List<BibleVersionRef> versions = [];
    for (final dynamic languageEntry in languages) {
      final map = languageEntry as Map<String, dynamic>;
      final language = (map['language'] as String?)?.trim();
      final List<dynamic> rawVersions = (map['versions'] as List<dynamic>?) ?? [];
      for (final dynamic v in rawVersions) {
        final vMap = v as Map<String, dynamic>;
        final name = (vMap['name'] as String?)?.trim();
        final abbreviation = (vMap['abbreviation'] as String?)?.trim();
        if (name == null || name.isEmpty || abbreviation == null || abbreviation.isEmpty) {
          continue;
        }
        versions.add(
          BibleVersionRef(
            language: language ?? '',
            name: name,
            abbreviation: abbreviation,
          ),
        );
      }
    }

    versions.sort((a, b) => a.displayName.compareTo(b.displayName));
    return versions;
  }

  Future<List<BibleBook>> _loadBooksForVersion(String versionAbbreviation) async {
    final raw = await _assetBundle.loadString('json/$versionAbbreviation.json');
    final normalized = _stripBom(raw);
    final dynamic decoded = _useCompute ? await compute(_decodeJson, normalized) : _decodeJson(normalized);
    final List<dynamic> rawBooks = decoded as List<dynamic>;

    return rawBooks.map((dynamic item) {
      final map = item as Map<String, dynamic>;
      final abbrev = (map['abbrev'] as String?)?.trim() ?? '';
      final name = (map['name'] as String?)?.trim() ?? abbrev;
      final chapters = (map['chapters'] as List<dynamic>? ?? const [])
          .map(
            (dynamic c) =>
                (c as List<dynamic>).map((dynamic v) => v.toString()).toList(growable: false),
          )
          .toList(growable: false);
      return BibleBook(abbrev: abbrev, name: name, chapters: chapters);
    }).toList(growable: false);
  }
}

class BibleVersionRef {
  const BibleVersionRef({
    required this.language,
    required this.name,
    required this.abbreviation,
  });

  final String language;
  final String name;
  final String abbreviation;

  String get displayName {
    if (language.isEmpty) return name;
    return '$language • $name';
  }
}

class BibleBook {
  const BibleBook({
    required this.abbrev,
    required this.name,
    required this.chapters,
  });

  final String abbrev;
  final String name;
  final List<List<String>> chapters;
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.repository});

  final BibleRepository repository;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final Future<List<BibleVersionRef>> _versionsFuture;
  BibleVersionRef? _selectedVersion;
  Future<List<BibleBook>>? _booksFuture;

  @override
  void initState() {
    super.initState();
    _versionsFuture = widget.repository.listVersions();
  }

  void _setSelected(BibleVersionRef version) {
    setState(() {
      _selectedVersion = version;
      _booksFuture = widget.repository.loadBooks(version.abbreviation);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bíblia')),
      body: FutureBuilder<List<BibleVersionRef>>(
        future: _versionsFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorState(
              title: 'Falha ao carregar versões',
              message: '${snapshot.error}',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final versions = snapshot.data!;
          if (_selectedVersion == null && versions.isNotEmpty) {
            final preferred = versions.cast<BibleVersionRef?>().firstWhere(
                  (v) => v?.abbreviation == 'pt_nvi',
                  orElse: () => versions.first,
                )!;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _selectedVersion == null) _setSelected(preferred);
            });
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    const Text('Versão'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<BibleVersionRef>(
                        isExpanded: true,
                        value: _selectedVersion,
                        items: versions
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(v.displayName, overflow: TextOverflow.ellipsis),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (v) {
                          if (v != null) _setSelected(v);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _BooksList(booksFuture: _booksFuture)),
            ],
          );
        },
      ),
    );
  }
}

class _BooksList extends StatelessWidget {
  const _BooksList({required this.booksFuture});

  final Future<List<BibleBook>>? booksFuture;

  @override
  Widget build(BuildContext context) {
    final future = booksFuture;
    if (future == null) {
      return const Center(child: Text('Selecione uma versão para carregar os livros.'));
    }

    return FutureBuilder<List<BibleBook>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(
            title: 'Falha ao carregar livros',
            message: '${snapshot.error}',
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final books = snapshot.data!;
        return ListView.separated(
          itemCount: books.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final book = books[index];
            return ListTile(
              title: Text(book.name),
              subtitle: Text('${book.chapters.length} capítulo(s)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => ChaptersPage(book: book),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class ChaptersPage extends StatelessWidget {
  const ChaptersPage({super.key, required this.book});

  final BibleBook book;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(book.name)),
      body: ListView.separated(
        itemCount: book.chapters.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final chapterNumber = index + 1;
          return ListTile(
            title: Text('Capítulo $chapterNumber'),
            subtitle: Text('${book.chapters[index].length} versículo(s)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => VersesPage(
                    bookName: book.name,
                    chapterNumber: chapterNumber,
                    verses: book.chapters[index],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class VersesPage extends StatelessWidget {
  const VersesPage({
    super.key,
    required this.bookName,
    required this.chapterNumber,
    required this.verses,
  });

  final String bookName;
  final int chapterNumber;
  final List<String> verses;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$bookName $chapterNumber')),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: verses.length,
        separatorBuilder: (_, __) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final verseNumber = index + 1;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$verseNumber  ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  TextSpan(text: verses[index]),
                ],
              ),
              textAlign: TextAlign.start,
            ),
          );
        },
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

String _stripBom(String value) {
  if (value.isEmpty) return value;
  if (value.codeUnitAt(0) == 0xFEFF) return value.substring(1);
  return value;
}

dynamic _decodeJson(String raw) {
  return json.decode(raw);
}
