import 'dart:io';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/document_provider.dart';
import '../services/gemini_service.dart';
import '../services/export_service.dart';

class DocumentDetailScreen extends StatefulWidget {
  final String documentId;
  const DocumentDetailScreen({super.key, required this.documentId});

  @override
  State<DocumentDetailScreen> createState() => _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends State<DocumentDetailScreen> {
  final _gemini = GeminiService();
  final _chatController = TextEditingController();
  final _exportService = ExportService();

  bool _aiLoading = false;
  String? _aiResult;
  bool _exporting = false;

  Future<void> _exportZip(String title, List<String> pagePaths) async {
    setState(() => _exporting = true);
    try {
      final zipPath = await _exportService.exportPagesAsZip(title, pagePaths);
      await Share.shareXFiles([XFile(zipPath)], text: '$title — scanned pages');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

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
            IconButton(
              icon: _exporting
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.folder_zip_outlined),
              tooltip: 'Export pages as ZIP',
              onPressed: _exporting ? null : () => _exportZip(doc.title, doc.pageImagePaths),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            // ---- Preview tab ----
            ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: doc.pageImagePaths.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(File(doc.pageImagePaths[i])),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black54,
                        child: Text('${i + 1}',
                            style: const TextStyle(fontSize: 11, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ---- OCR Text tab ----
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SelectableText(
                  doc.ocrText.isEmpty ? 'No text detected.' : doc.ocrText,
                ),
              ),
            ),

            // ---- AI Actions tab ----
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('AI Tools', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 2.6,
                    children: [
                      _AiActionCard(
                        icon: Icons.summarize_outlined,
                        label: 'Summarize',
                        enabled: !_aiLoading,
                        onTap: () => _runAiAction(() => _gemini.summarize(doc.ocrText)),
                      ),
                      _AiActionCard(
                        icon: Icons.language,
                        label: 'AI OCR (Urdu/Arabic)',
                        enabled: !_aiLoading && doc.pageImagePaths.isNotEmpty,
                        onTap: () =>
                            _runAiAction(() => _gemini.extractTextFromImage(doc.pageImagePaths.first)),
                      ),
                      _AiActionCard(
                        icon: Icons.translate_outlined,
                        label: 'Translate → Urdu',
                        enabled: !_aiLoading,
                        onTap: () => _runAiAction(() => _gemini.translate(doc.ocrText, 'Urdu')),
                      ),
                      _AiActionCard(
                        icon: Icons.translate_outlined,
                        label: 'Translate → English',
                        enabled: !_aiLoading,
                        onTap: () => _runAiAction(() => _gemini.translate(doc.ocrText, 'English')),
                      ),
                      _AiActionCard(
                        icon: Icons.translate_outlined,
                        label: 'Translate → Spanish',
                        enabled: !_aiLoading,
                        onTap: () => _runAiAction(() => _gemini.translate(doc.ocrText, 'Spanish')),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  Text('Chat with this document', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          decoration: InputDecoration(
                            hintText: 'Ask a question about this document...',
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
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
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
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

class _AiActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  const _AiActionCard({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon, size: 20, color: enabled ? scheme.primary : scheme.outline),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: enabled ? scheme.onSurface : scheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
