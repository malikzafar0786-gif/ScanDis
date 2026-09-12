import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/storage_service.dart';
import 'services/reminder_service.dart';
import 'providers/document_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/home_screen.dart';
import 'theme/app_colors.dart';

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
      await ReminderService.init(); // local notification setup (bill reminders)
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
              colorSchemeSeed: const Color(0xFF0E7C86),
              useMaterial3: true,
              appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0, scrolledUnderElevation: 2),
              cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
              inputDecorationTheme: const InputDecorationTheme(
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
              ),
            ),
            // Dark glassmorphism theme — background #0B131F, cyan accent
            // #00F2FE, as specified in the project design brief. This is
            // the app's primary look (default themeMode below).
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              useMaterial3: true,
              scaffoldBackgroundColor: AppColors.background,
              colorScheme: const ColorScheme.dark(
                surface: AppColors.background,
                primary: AppColors.cyan,
                onPrimary: Color(0xFF00303A),
                secondary: AppColors.cyanDim,
                primaryContainer: Color(0xFF0E3A42),
                onPrimaryContainer: AppColors.cyan,
                secondaryContainer: Color(0xFF12303A),
                onSecondaryContainer: AppColors.cyan,
                surfaceContainerLow: Color(0xFF101A28),
                surfaceContainerHighest: Color(0xFF1A2635),
                onSurface: AppColors.textPrimary,
                onSurfaceVariant: AppColors.textSecondary,
                outline: Color(0xFF2A3A4C),
                outlineVariant: Color(0xFF223244),
              ),
              appBarTheme: const AppBarTheme(
                backgroundColor: AppColors.background,
                centerTitle: false,
                elevation: 0,
                scrolledUnderElevation: 2,
              ),
              cardTheme: const CardThemeData(
                elevation: 0,
                margin: EdgeInsets.zero,
                color: AppColors.surface,
              ),
              inputDecorationTheme: InputDecorationTheme(
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                hintStyle: const TextStyle(color: AppColors.textSecondary),
              ),
              floatingActionButtonTheme: const FloatingActionButtonThemeData(
                backgroundColor: AppColors.cyan,
                foregroundColor: Color(0xFF00303A),
              ),
              textTheme: const TextTheme(
                bodyMedium: TextStyle(color: AppColors.textPrimary),
              ).apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary),
            ),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }
}
