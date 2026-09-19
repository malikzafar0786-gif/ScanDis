import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.brightness_6_outlined),
            title: const Text('Dark theme'),
            value: themeProvider.mode == ThemeMode.dark,
            onChanged: (_) => context.read<ThemeProvider>().toggle(),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('100% Local & Offline'),
            subtitle: Text(
              'Your scans, PDFs, and OCR text stay on this device. Nothing is uploaded '
              'unless you explicitly use an AI feature (Summarize, Translate, AI Photo, etc.), '
              'which sends only that specific content to Google\'s Gemini API for that one request.',
            ),
          ),
          const ListTile(
            leading: Icon(Icons.camera_alt_outlined),
            title: Text('Permissions used'),
            subtitle: Text('Camera (scanning), Notifications (bill reminders). No contacts, no location.'),
          ),
          const Divider(),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'ScanDis',
            applicationLegalese: '© ScanDis',
            child: Text('About'),
          ),
        ],
      ),
    );
  }
}
