import 'dart:io';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../providers/document_provider.dart';
import '../services/gemini_service.dart';

class DocumentDetailScreen extends StatefulWidget {
  final String documentId;
  const DocumentDetailScreen({super.key, required this.documentId});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  final _gemini = GeminiService();
  final _chatController = TextEditingController();

  bool _aiLoading = false;
  String? _aiResult;

  Future<void> _runAiAction(Future<String> Function() action) async {
    setState(() {
      _aiLoading = true;
      _aiResult = null;
    });
    try {
      final result = await action();
      setState(() => _aiResult = result);
    } on GeminiException catch (e) {
      setState(() => _aiResult = '⚠️ ${e.message}');
    } catch (e) {
      setState(() => _aiResult = '⚠️ Unexpected error: $e');
    } finally {
      setState(() => _aiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docProvider = context.watch<DocumentProvider>();
    final matches = docProvider.documents.where((d) => d.id == widget.documentId);
    final doc = matches.isNotEmpty ? matches.first : null;

    if (doc == null) {
      return const Scaffold(body: Center(child: Text('Document not found')));
    }

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(doc.title),
          bottom: const TabBar(tabs: [
            Tab(text: 'Preview'),
            Tab(text: 'OCR Text'),
            Tab(text: 'AI Actions'),
          ]),
          actions: [
            if (doc.pdfPath != null)
              IconButton(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: 'Export / Share PDF',
                onPressed: () => Printing.sharePdf(
                  bytes: File(doc.pdfPath!).readAsBytesSync(),
                  filename: '${doc.title}.pdf',
                ),
              ),
          ],
        ),
        body: TabBarView(
          children: [
            // ---- Preview tab ----
            ListView.builder(
              itemCount: doc.pageImagePaths.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.all(8),
                child: Image.file(File(doc.pageImagePaths[i])),
              ),
            ),

            // ---- OCR Text tab ----
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                doc.ocrText.isEmpty ? 'No text detected.' : doc.ocrText,
              ),
            ),

            // ---- AI Actions tab ----
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.summarize_outlined),
                        label: const Text('Summarize'),
                        onPressed: _aiLoading
                            ? null
                            : () => _runAiAction(() => _gemini.summarize(doc.ocrText)),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.translate_outlined),
                        label: const Text('Translate → Urdu'),
                        onPressed: _aiLoading
                            ? null
                            : () => _runAiAction(() => _gemini.translate(doc.ocrText, 'Urdu')),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.translate_outlined),
                        label: const Text('Translate → English'),
                        onPressed: _aiLoading
                            ? null
                            : () => _runAiAction(() => _gemini.translate(doc.ocrText, 'English')),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.translate_outlined),
                        label: const Text('Translate → Spanish'),
                        onPressed: _aiLoading
                            ? null
                            : () => _runAiAction(() => _gemini.translate(doc.ocrText, 'Spanish')),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  const Text('Chat with this document', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          decoration: const InputDecoration(
                            hintText: 'Ask a question about this document...',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _aiLoading || _chatController.text.trim().isEmpty
                            ? null
                            : () => _runAiAction(
                                () => _gemini.chatWithDocument(doc.ocrText, _chatController.text.trim())),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_aiLoading) const Center(child: CircularProgressIndicator()),
                  if (_aiResult != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SelectableText(_aiResult!),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
