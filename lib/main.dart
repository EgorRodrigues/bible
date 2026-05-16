import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'bible_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Uncaught error: $error');
    debugPrint('$stack');
    return true;
  };

  runZonedGuarded(() {
    runApp(const BibleStudyApp());
  }, (error, stack) {
    debugPrint('Zone error: $error');
    debugPrint('$stack');
  });
}

class BibleStudyApp extends StatelessWidget {
  const BibleStudyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const BibleApp();
  }
}
