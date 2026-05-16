import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:bible_study/bible_app.dart';

void main() {
  testWidgets('Carrega a lista de livros', (WidgetTester tester) async {
    final bundle = _FakeAssetBundle();
    final repository = BibleRepository(assetBundle: bundle);

    await tester.pumpWidget(BibleApp(repository: repository));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      if (find.text('Velho Testamento').evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Velho Testamento'), findsOneWidget);

    await tester.tap(find.text('Velho Testamento'));
    await tester.pumpAndSettle();

    expect(find.text('Gênesis'), findsOneWidget);
    expect(find.text('2 capítulo(s)'), findsOneWidget);

    await tester.tap(find.text('Gênesis'));
    await tester.pumpAndSettle();

    expect(find.text('Capítulo 1'), findsOneWidget);
    expect(find.text('Capítulo 2'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Novo Testamento'), findsOneWidget);

    await tester.tap(find.text('Novo Testamento'));
    await tester.pumpAndSettle();

    expect(find.text('Mateus'), findsOneWidget);

    await tester.tap(find.text('Mateus'));
    await tester.pumpAndSettle();
    expect(find.text('Capítulo 1'), findsOneWidget);
    expect(find.text('Capítulo 2'), findsNothing);
  });
}

class _FakeAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final text = await loadString(key);
    final bytes = Uint8List.fromList(utf8.encode(text));
    return ByteData.sublistView(bytes);
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == 'json/index.json') {
      return jsonIndex;
    }
    if (key == 'json/pt_nvi.json') {
      return _buildPtNviJson();
    }
    throw FlutterError('Asset não encontrado: $key');
  }

  static const String jsonIndex = '''
[
  {
    "language": "Portuguese",
    "versions": [
      {"name": "Nova Versão Internacional", "abbreviation": "pt_nvi"}
    ]
  }
]
''';

  String _buildPtNviJson() {
    final books = <Map<String, dynamic>>[
      {
        'abbrev': 'gn',
        'name': 'Gênesis',
        'chapters': [
          ['No princípio...'],
          ['E no segundo capítulo...'],
        ],
      },
    ];

    for (var i = 1; i < 39; i++) {
      books.add({
        'abbrev': 'b$i',
        'name': 'Livro $i',
        'chapters': [
          ['Capítulo único...'],
        ],
      });
    }

    books.add({
      'abbrev': 'mt',
      'name': 'Mateus',
      'chapters': [
        ['Bem-aventurados...'],
      ],
    });

    return json.encode(books);
  }
}
