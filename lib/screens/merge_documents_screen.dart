import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/scanned_document.dart';
import '../providers/document_provider.dart';
import '../services/pdf_service.dart';
import '../services/ocr_service.dart';

class MergeDocumentsScreen extends StatefulWidget {
  const MergeDocumentsScreen({super.key});

  @override
  State<MergeDocumentsScreen> createState() => _MergeDocumentsScreenState();
}

class _MergeDocumentsScreenState extends State<MergeDocumentsScreen> {
  final Set<String> _selectedIds = {};
  final _pdfService = PdfService();
  final _ocrService = OcrService();
  bool _merging = false;

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  Future<void> _merge(List<ScannedDocument> allDocs) async {
    if (_selectedIds.length < 2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select at least 2 documents to merge.')));
      return;
    }
    setState(() => _merging = true);
    try {
      final selectedDocs = _selectedIds.map((id) => allDocs.firstWhere((d) => d.id == id)).toList();
      final mergedPages = <String>[for (final d in selectedDocs) ...d.pageImagePaths];
      final title = 'Merged_${DateTime.now().millisecondsSinceEpoch}';

      final pdfPath = await _pdfService.generatePdfFromImages(mergedPages, fileName: title);
      final ocrText = await _ocrService.extractTextFromPages(mergedPages);

      final merged = ScannedDocument(
        id: const Uuid().v4(),
        title: title,
        pageImagePaths: mergedPages,
        pdfPath: pdfPath,
        ocrText: ocrText,
        createdAt: DateTime.now(),
      );

      if (!mounted) return;
      await context.read<DocumentProvider>().addDocument(merged);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Merged into a new document.')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Merge failed: $e')));
    } finally {
      if (mounted) setState(() => _merging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = context.watch<DocumentProvider>().documents;

    return Scaffold(
      appBar: AppBar(title: Text('Merge Documents (${_selectedIds.length} selected)')),
      body: docs.isEmpty
          ? const Center(child: Text('No documents to merge yet.'))
          : ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, i) {
                final doc = docs[i];
                final selected = _selectedIds.contains(doc.id);
                final thumb = doc.pageImagePaths.isNotEmpty ? doc.pageImagePaths.first : null;
                return CheckboxListTile(
                  value: selected,
                  onChanged: (_) => setState(() {
                    selected ? _selectedIds.remove(doc.id) : _selectedIds.add(doc.id);
                  }),
                  secondary: thumb != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(File(thumb), width: 40, height: 50, fit: BoxFit.cover),
                        )
                      : const Icon(Icons.description_outlined),
                  title: Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${doc.pageImagePaths.length} pages'),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            icon: _merging
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.merge_outlined),
            label: Text(_merging ? 'Merging...' : 'Merge Selected'),
            onPressed: _merging || _selectedIds.length < 2 ? null : () => _merge(docs),
          ),
        ),
      ),
    );
  }
}
