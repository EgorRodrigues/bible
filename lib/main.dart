import 'package:flutter/material.dart';

import 'bible_app.dart';

void main() {
  runApp(const BibleStudyApp());
}

class BibleStudyApp extends StatelessWidget {
  const BibleStudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const BibleApp();
  }
}
