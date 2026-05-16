import 'dart:convert';

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
  BibleRepository({AssetBundle? assetBundle}) : _assetBundle = assetBundle ?? rootBundle;

  final AssetBundle _assetBundle;

  Future<List<BibleVersionRef>>? _versionsFuture;
  final Map<String, Future<_BibleSource>> _sourceByVersion = {};

  Future<List<BibleVersionRef>> listVersions() {
    return _versionsFuture ??= _loadVersions();
  }

  Future<List<BibleBookRef>> listBooks(String versionAbbreviation) async {
    final source = await _loadSource(versionAbbreviation);
    return source.books;
  }

  Future<List<BibleVersionRef>> _loadVersions() async {
    final raw = await _assetBundle.loadString('json/index.json');
    final normalized = _stripBom(raw);
    final dynamic decoded = json.decode(normalized);
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

  Future<List<String>> loadChapter({
    required String versionAbbreviation,
    required int bookIndex,
    required int chapterIndex,
  }) async {
    final source = await _loadSource(versionAbbreviation);
    if (bookIndex < 0 || bookIndex >= source.bookSpans.length) {
      throw RangeError.range(bookIndex, 0, source.bookSpans.length - 1, 'bookIndex');
    }

    final bookSpan = source.bookSpans[bookIndex];
    final bookObject = source.json.substring(bookSpan.start, bookSpan.end);
    final chaptersArraySpan = _JsonScanner.findArrayValueSpan(bookObject, 'chapters');
    final chaptersArray = bookObject.substring(chaptersArraySpan.start, chaptersArraySpan.end);
    final chapterSpan = _JsonScanner.nthTopLevelArrayItemSpan(chaptersArray, chapterIndex);
    final chapterJson = chaptersArray.substring(chapterSpan.start, chapterSpan.end);
    final dynamic decoded = json.decode(chapterJson);
    final List<dynamic> rawVerses = decoded as List<dynamic>;
    return rawVerses.map((v) => v.toString()).toList(growable: false);
  }

  Future<_BibleSource> _loadSource(String versionAbbreviation) {
    return _sourceByVersion[versionAbbreviation] ??=
        _loadSourceForVersion(versionAbbreviation);
  }

  Future<_BibleSource> _loadSourceForVersion(String versionAbbreviation) async {
    final raw = await _assetBundle.loadString('json/$versionAbbreviation.json');
    final normalized = _stripBom(raw);

    final bookSpans = _JsonScanner.topLevelArrayItemSpans(normalized);
    final books = <BibleBookRef>[];
    for (var i = 0; i < bookSpans.length; i++) {
      final span = bookSpans[i];
      final bookObject = normalized.substring(span.start, span.end);
      final abbrev = _JsonScanner.readStringField(bookObject, 'abbrev')?.trim() ?? '';
      final name = _JsonScanner.readStringField(bookObject, 'name')?.trim() ?? abbrev;
      final chaptersArraySpan = _JsonScanner.findArrayValueSpan(bookObject, 'chapters');
      final chaptersArray = bookObject.substring(chaptersArraySpan.start, chaptersArraySpan.end);
      final chapterCount = _JsonScanner.countTopLevelArrayItems(chaptersArray);
      books.add(BibleBookRef(index: i, abbrev: abbrev, name: name, chapterCount: chapterCount));
    }

    return _BibleSource(json: normalized, bookSpans: bookSpans, books: books);
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

class BibleBookRef {
  const BibleBookRef({
    required this.index,
    required this.abbrev,
    required this.name,
    required this.chapterCount,
  });

  final int index;
  final String abbrev;
  final String name;
  final int chapterCount;
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
  Future<List<BibleBookRef>>? _booksFuture;

  @override
  void initState() {
    super.initState();
    _versionsFuture = widget.repository.listVersions();
  }

  void _setSelected(BibleVersionRef version) {
    setState(() {
      _selectedVersion = version;
      _booksFuture = widget.repository.listBooks(version.abbreviation);
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
              if (!mounted || _selectedVersion != null) return;
              setState(() {
                _selectedVersion = preferred;
              });
              Future<void>.delayed(const Duration(milliseconds: 50), () {
                if (!mounted || _booksFuture != null) return;
                setState(() {
                  _booksFuture = widget.repository.listBooks(preferred.abbreviation);
                });
              });
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
              Expanded(
                child: _BooksList(
                  booksFuture: _booksFuture,
                  repository: widget.repository,
                  selectedVersion: _selectedVersion,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BooksList extends StatelessWidget {
  const _BooksList({
    required this.booksFuture,
    required this.repository,
    required this.selectedVersion,
  });

  final Future<List<BibleBookRef>>? booksFuture;
  final BibleRepository repository;
  final BibleVersionRef? selectedVersion;

  @override
  Widget build(BuildContext context) {
    final future = booksFuture;
    if (future == null) {
      return const Center(child: Text('Selecione uma versão para carregar os livros.'));
    }

    final version = selectedVersion;
    if (version == null) {
      return const Center(child: Text('Selecione uma versão para carregar os livros.'));
    }

    return FutureBuilder<List<BibleBookRef>>(
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
        final split = _TestamentBooks.fromBooks(books);
        final rows = <_TestamentRow>[];
        if (split.old.isNotEmpty) {
          rows.add(_TestamentRow(title: 'Velho Testamento', books: split.old));
        }
        if (split.newTestament.isNotEmpty) {
          rows.add(_TestamentRow(title: 'Novo Testamento', books: split.newTestament));
        }
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final row = rows[index];
            return ListTile(
              title: Text(row.title),
              subtitle: Text('${row.books.length} livro(s)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => TestamentBooksPage(
                      repository: repository,
                      versionAbbreviation: version.abbreviation,
                      title: row.title,
                      books: row.books,
                    ),
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

class _TestamentRow {
  const _TestamentRow({required this.title, required this.books});
  final String title;
  final List<BibleBookRef> books;
}

class _TestamentBooks {
  const _TestamentBooks({required this.old, required this.newTestament});

  final List<BibleBookRef> old;
  final List<BibleBookRef> newTestament;

  static const int _oldTestamentBookCount = 39;

  static _TestamentBooks fromBooks(List<BibleBookRef> books) {
    final old = <BibleBookRef>[];
    final newTestament = <BibleBookRef>[];

    for (final book in books) {
      if (book.index < _oldTestamentBookCount) {
        old.add(book);
      } else {
        newTestament.add(book);
      }
    }

    return _TestamentBooks(old: old, newTestament: newTestament);
  }
}

class TestamentBooksPage extends StatelessWidget {
  const TestamentBooksPage({
    super.key,
    required this.repository,
    required this.versionAbbreviation,
    required this.title,
    required this.books,
  });

  final BibleRepository repository;
  final String versionAbbreviation;
  final String title;
  final List<BibleBookRef> books;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        itemCount: books.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final book = books[index];
          return ListTile(
            title: Text(book.name),
            subtitle: Text('${book.chapterCount} capítulo(s)'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => ChaptersPage(
                    repository: repository,
                    versionAbbreviation: versionAbbreviation,
                    book: book,
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

class ChaptersPage extends StatelessWidget {
  const ChaptersPage({
    super.key,
    required this.repository,
    required this.versionAbbreviation,
    required this.book,
  });

  final BibleRepository repository;
  final String versionAbbreviation;
  final BibleBookRef book;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(book.name)),
      body: ListView.separated(
        itemCount: book.chapterCount,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final chapterNumber = index + 1;
          return ListTile(
            title: Text('Capítulo $chapterNumber'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => VersesPage(
                    repository: repository,
                    versionAbbreviation: versionAbbreviation,
                    book: book,
                    chapterIndex: index,
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

class VersesPage extends StatefulWidget {
  const VersesPage({
    super.key,
    required this.repository,
    required this.versionAbbreviation,
    required this.book,
    required this.chapterIndex,
  });

  final BibleRepository repository;
  final String versionAbbreviation;
  final BibleBookRef book;
  final int chapterIndex;

  @override
  State<VersesPage> createState() => _VersesPageState();
}

class _VersesPageState extends State<VersesPage> {
  late final Future<List<String>> _versesFuture;

  @override
  void initState() {
    super.initState();
    _versesFuture = widget.repository.loadChapter(
      versionAbbreviation: widget.versionAbbreviation,
      bookIndex: widget.book.index,
      chapterIndex: widget.chapterIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final chapterNumber = widget.chapterIndex + 1;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.book.name} $chapterNumber')),
      body: FutureBuilder<List<String>>(
        future: _versesFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _ErrorState(
              title: 'Falha ao carregar versículos',
              message: '${snapshot.error}',
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final verses = snapshot.data!;
          return ListView.separated(
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

class _BibleSource {
  const _BibleSource({required this.json, required this.bookSpans, required this.books});

  final String json;
  final List<_Span> bookSpans;
  final List<BibleBookRef> books;
}

class _Span {
  const _Span(this.start, this.end);
  final int start;
  final int end;
}

class _JsonScanner {
  static List<_Span> topLevelArrayItemSpans(String jsonArray) {
    var i = 0;
    while (i < jsonArray.length && jsonArray.codeUnitAt(i) != 0x5B) {
      i++;
    }
    if (i >= jsonArray.length) {
      throw FormatException('JSON array esperado');
    }

    var inString = false;
    var escaped = false;
    var depth = 0;
    int? itemStart;
    final spans = <_Span>[];

    for (; i < jsonArray.length; i++) {
      final c = jsonArray.codeUnitAt(i);

      if (inString) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (c == 0x5C) {
          escaped = true;
          continue;
        }
        if (c == 0x22) {
          inString = false;
        }
        continue;
      }

      if (c == 0x22) {
        inString = true;
        continue;
      }

      if (c == 0x5B || c == 0x7B) {
        depth++;
        if (depth == 1) {
          continue;
        }
        if (depth == 2 && itemStart == null) {
          itemStart = i;
        }
        continue;
      }

      if (c == 0x5D || c == 0x7D) {
        if (depth == 2 && itemStart != null) {
          spans.add(_Span(itemStart, i + 1));
          itemStart = null;
        }
        depth--;
        continue;
      }
    }

    return spans;
  }

  static int countTopLevelArrayItems(String jsonArray) {
    var i = 0;
    while (i < jsonArray.length && jsonArray.codeUnitAt(i) != 0x5B) {
      i++;
    }
    if (i >= jsonArray.length) {
      throw FormatException('JSON array esperado');
    }

    var inString = false;
    var escaped = false;
    var depth = 0;
    var count = 0;
    var expectingValueAtDepth1 = true;

    for (; i < jsonArray.length; i++) {
      final c = jsonArray.codeUnitAt(i);

      if (inString) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (c == 0x5C) {
          escaped = true;
          continue;
        }
        if (c == 0x22) {
          inString = false;
        }
        continue;
      }

      if (c == 0x22) {
        if (depth == 1 && expectingValueAtDepth1) {
          count++;
          expectingValueAtDepth1 = false;
        }
        inString = true;
        continue;
      }

      if (c == 0x5B || c == 0x7B) {
        depth++;
        if (depth == 2 && expectingValueAtDepth1) {
          count++;
          expectingValueAtDepth1 = false;
        }
        continue;
      }

      if (c == 0x5D || c == 0x7D) {
        if (c == 0x5D && depth == 1) {
          return count;
        }
        depth--;
        continue;
      }

      if (depth != 1) {
        continue;
      }

      if (c == 0x2C) {
        expectingValueAtDepth1 = true;
        continue;
      }

      if (c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09) {
        continue;
      }

      if (expectingValueAtDepth1) {
        count++;
        expectingValueAtDepth1 = false;
      }
    }

    return count;
  }

  static _Span nthTopLevelArrayItemSpan(String jsonArray, int index) {
    if (index < 0) {
      throw RangeError.range(index, 0, null, 'index');
    }

    var i = 0;
    while (i < jsonArray.length && jsonArray.codeUnitAt(i) != 0x5B) {
      i++;
    }
    if (i >= jsonArray.length) {
      throw FormatException('JSON array esperado');
    }

    var inString = false;
    var escaped = false;
    var depth = 0;
    int? itemStart;
    var current = -1;

    for (; i < jsonArray.length; i++) {
      final c = jsonArray.codeUnitAt(i);

      if (inString) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (c == 0x5C) {
          escaped = true;
          continue;
        }
        if (c == 0x22) {
          inString = false;
        }
        continue;
      }

      if (c == 0x22) {
        inString = true;
        continue;
      }

      if (c == 0x5B || c == 0x7B) {
        depth++;
        if (depth == 2 && itemStart == null) {
          current++;
          if (current == index) {
            itemStart = i;
          }
        }
        continue;
      }

      if (c == 0x5D || c == 0x7D) {
        if (depth == 2 && itemStart != null && current == index) {
          return _Span(itemStart, i + 1);
        }
        depth--;
        continue;
      }
    }

    throw RangeError.range(index, 0, current, 'index');
  }

  static String? readStringField(String objectJson, String key) {
    final keyToken = '"$key"';
    final keyIndex = objectJson.indexOf(keyToken);
    if (keyIndex < 0) return null;

    var i = keyIndex + keyToken.length;
    while (i < objectJson.length && objectJson.codeUnitAt(i) != 0x3A) {
      i++;
    }
    if (i >= objectJson.length) return null;
    i++;

    while (i < objectJson.length) {
      final c = objectJson.codeUnitAt(i);
      if (c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09) {
        i++;
        continue;
      }
      break;
    }
    if (i >= objectJson.length || objectJson.codeUnitAt(i) != 0x22) return null;

    final start = i;
    i++;
    var escaped = false;
    for (; i < objectJson.length; i++) {
      final c = objectJson.codeUnitAt(i);
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == 0x5C) {
        escaped = true;
        continue;
      }
      if (c == 0x22) {
        final rawStringLiteral = objectJson.substring(start, i + 1);
        return json.decode(rawStringLiteral) as String;
      }
    }
    return null;
  }

  static _Span findArrayValueSpan(String objectJson, String key) {
    final keyToken = '"$key"';
    final keyIndex = objectJson.indexOf(keyToken);
    if (keyIndex < 0) {
      throw FormatException('Campo "$key" não encontrado');
    }

    var i = keyIndex + keyToken.length;
    while (i < objectJson.length && objectJson.codeUnitAt(i) != 0x3A) {
      i++;
    }
    if (i >= objectJson.length) {
      throw FormatException('Campo "$key" inválido');
    }
    i++;

    while (i < objectJson.length) {
      final c = objectJson.codeUnitAt(i);
      if (c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09) {
        i++;
        continue;
      }
      break;
    }
    if (i >= objectJson.length || objectJson.codeUnitAt(i) != 0x5B) {
      throw FormatException('Campo "$key" não é um array');
    }

    final start = i;
    var inString = false;
    var escaped = false;
    var depth = 0;

    for (; i < objectJson.length; i++) {
      final c = objectJson.codeUnitAt(i);

      if (inString) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (c == 0x5C) {
          escaped = true;
          continue;
        }
        if (c == 0x22) {
          inString = false;
        }
        continue;
      }

      if (c == 0x22) {
        inString = true;
        continue;
      }

      if (c == 0x5B) {
        depth++;
        continue;
      }

      if (c == 0x5D) {
        depth--;
        if (depth == 0) {
          return _Span(start, i + 1);
        }
        continue;
      }
    }

    throw FormatException('Array "$key" não foi fechado');
  }
}
