import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/storage_service.dart';
import 'providers/document_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Catch Flutter framework errors (widget build errors etc.) and show
    // them on-screen instead of a silent crash / blank screen.
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
    };

    try {
      await StorageService.init(); // Hive init + box open
      runApp(const DocScannerApp());
    } catch (e, stack) {
      // If startup itself fails (e.g. storage init), show a readable error
      // screen instead of the app silently failing to launch.
      runApp(StartupErrorApp(error: e.toString(), stack: stack.toString()));
    }
  }, (error, stack) {
    // Catches any otherwise-uncaught async error during the app's lifetime.
    debugPrint('Uncaught error: $error\n$stack');
  });
}

class StartupErrorApp extends StatelessWidget {
  final String error;
  final String stack;
  const StartupErrorApp({super.key, required this.error, required this.stack});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('ScanDis — Startup Error')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The app failed to start:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              SelectableText(error),
              const SizedBox(height: 16),
              const Text('Details:', style: TextStyle(fontWeight: FontWeight.bold)),
              SelectableText(stack, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

class DocScannerApp extends StatelessWidget {
  const DocScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DocumentProvider()..loadDocuments()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'ScanDis',
            debugShowCheckedModeBanner: false,
            themeMode: themeProvider.mode,
            theme: ThemeData(
              brightness: Brightness.light,
              colorSchemeSeed: Colors.indigo,
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              colorSchemeSeed: Colors.indigo,
              useMaterial3: true,
            ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
