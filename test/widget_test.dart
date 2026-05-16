import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:bible_study/bible_app.dart';

void main() {
  testWidgets('Carrega a lista de livros', (WidgetTester tester) async {
    final bundle = _FakeAssetBundle();
    final repository = BibleRepository(assetBundle: bundle, useCompute: false);

    await tester.pumpWidget(BibleApp(repository: repository));
    await tester.pump();
    for (var i = 0; i < 40; i++) {
      if (find.text('Gênesis').evaluate().isNotEmpty) break;
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Gênesis'), findsOneWidget);
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
      return ptNvi;
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

  static const String ptNvi = '''
[
  {
    "abbrev": "gn",
    "name": "Gênesis",
    "chapters": [["No princípio..."]]
  }
]
''';
}
