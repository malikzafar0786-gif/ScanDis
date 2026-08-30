import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/document_provider.dart';
import '../providers/theme_provider.dart';
import 'scanner_screen.dart';
import 'document_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ScannerScreen()),
        ),
      ),
    );
  }
}
