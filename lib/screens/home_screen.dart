import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/document_provider.dart';
import '../providers/theme_provider.dart';
import 'scanner_screen.dart';
import 'document_detail_screen.dart';
import 'qr_scanner_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _showScanOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan Document'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ScannerScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner_outlined),
              title: const Text('Scan QR / Barcode'),
              onTap: () async {
                Navigator.pop(sheetContext);
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
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final docProvider = context.watch<DocumentProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Scans'),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6_outlined),
            onPressed: () => context.read<ThemeProvider>().toggle(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search documents or text...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: (v) => context.read<DocumentProvider>().setSearchQuery(v),
            ),
          ),
          Expanded(
            child: docProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : docProvider.documents.isEmpty
                    ? const Center(child: Text('No scans yet. Tap + to scan a document.'))
                    : ListView.builder(
                        itemCount: docProvider.documents.length,
                        itemBuilder: (context, index) {
                          final doc = docProvider.documents[index];
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
                            title: Text(doc.title),
                            subtitle: Text(DateFormat.yMMMd().add_jm().format(doc.createdAt)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => context.read<DocumentProvider>().deleteDocument(doc.id),
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => DocumentDetailScreen(documentId: doc.id)),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Scan'),
        onPressed: () => _showScanOptions(context),
      ),
    );
  }
}
