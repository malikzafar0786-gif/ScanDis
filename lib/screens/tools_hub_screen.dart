import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/document_provider.dart';
import 'scanner_screen.dart';
import 'qr_scanner_screen.dart';
import 'ai_photo_tools_screen.dart';
import 'passport_photo_screen.dart';
import 'paper_maker_screen.dart';
import 'merge_documents_screen.dart';
import 'reminders_screen.dart';

class ToolsHubScreen extends StatelessWidget {
  const ToolsHubScreen({super.key});

  void _openScanner(BuildContext context, {int? pageLimit, String? presetTitle, String label = 'New Scan'}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(pageLimitOverride: pageLimit, presetTitlePrefix: presetTitle, appBarLabel: label),
      ),
    );
  }

  Future<void> _openQrScanner(BuildContext context) async {
    final result = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (result != null && context.mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Scanned Result'),
          content: SelectableText(result),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    }
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          const _SectionHeader('Scan'),
          _ToolGrid(items: [
            _ToolItem(Icons.document_scanner_outlined, 'Document',
                () => _openScanner(context, label: 'Scan Document')),
            _ToolItem(Icons.badge_outlined, 'ID Card',
                () => _openScanner(context, pageLimit: 2, presetTitle: 'ID_Card', label: 'Scan ID Card')),
            _ToolItem(Icons.menu_book_outlined, 'Multi-page',
                () => _openScanner(context, presetTitle: 'Document', label: 'Scan Multi-page')),
            _ToolItem(Icons.qr_code_scanner_outlined, 'QR / Barcode', () => _openQrScanner(context)),
          ]),

          const _SectionHeader('AI Tools'),
          _ToolGrid(items: [
            _ToolItem(Icons.auto_awesome, 'AI Photo\n(Enhance/Restore/Colorize)',
                () => _push(context, const AiPhotoToolsScreen())),
            _ToolItem(Icons.quiz_outlined, 'Paper Maker\n(exam papers from a book)',
                () => _push(context, const PaperMakerScreen())),
          ]),

          const _SectionHeader('ID & Print'),
          _ToolGrid(items: [
            _ToolItem(Icons.badge, 'Passport Photo Maker', () => _push(context, const PassportPhotoScreen())),
          ]),

          const _SectionHeader('Document Management'),
          _ToolGrid(items: [
            _ToolItem(Icons.merge_outlined, 'Merge Documents', () => _push(context, const MergeDocumentsScreen())),
            _ToolItem(Icons.notifications_active_outlined, 'Bill Reminders',
                () => _push(context, const RemindersScreen())),
          ]),

          const _SectionHeader('Organize'),
          Consumer<DocumentProvider>(
            builder: (context, docProvider, _) => _ToolGrid(items: [
              _ToolItem(Icons.star_outline, 'Favorites', () {
                docProvider.setFavoritesOnly(true);
                docProvider.setActiveFolder(null);
                Navigator.pop(context);
              }),
              for (final folder in docProvider.folders)
                _ToolItem(Icons.folder_outlined, folder, () {
                  docProvider.setFavoritesOnly(false);
                  docProvider.setActiveFolder(folder);
                  Navigator.pop(context);
                }),
            ]),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _ToolItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  _ToolItem(this.icon, this.label, this.onTap);
}

class _ToolGrid extends StatelessWidget {
  final List<_ToolItem> items;
  const _ToolGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text('None yet', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
    }
    final scheme = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: item.onTap,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.icon, color: scheme.primary, size: 26),
                  const SizedBox(height: 8),
                  Text(
                    item.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
