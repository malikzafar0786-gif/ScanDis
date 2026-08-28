import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/scanned_document.dart';
import '../providers/document_provider.dart';
import '../services/image_filter_service.dart';
import '../services/pdf_service.dart';
import '../services/ocr_service.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final List<String> _capturedPages = [];
  ScanFilter _selectedFilter = ScanFilter.original;
  bool _processing = false;

  final _filterService = ImageFilterService();
  final _pdfService = PdfService();
  final _ocrService = OcrService();

  Future<void> _startScan() async {
    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      _showError('Camera permission is required to scan documents.');
      return;
    }

    try {
      // flutter_doc_scanner opens the native scanner UI with automatic
      // edge/border detection and returns cropped page image paths.
      final List<String>? scannedPaths =
          await FlutterDocScanner().getScannedDocumentAsImages(page: 4) as List<String>?;

      if (scannedPaths != null && scannedPaths.isNotEmpty) {
        setState(() => _capturedPages.addAll(scannedPaths));
      }
    } catch (e) {
      _showError('Scanning failed: $e');
    }
  }

  Future<void> _saveDocument() async {
    if (_capturedPages.isEmpty) {
      _showError('Please scan at least one page first.');
      return;
    }

    setState(() => _processing = true);
    try {
      // 1. Apply the chosen filter to every page
      final filteredPaths = <String>[];
      for (final path in _capturedPages) {
        final filtered = await _filterService.applyFilter(path, _selectedFilter);
        filteredPaths.add(filtered);
      }

      // 2. Generate PDF from filtered pages
      final title = 'Scan_${DateTime.now().millisecondsSinceEpoch}';
      final pdfPath = await _pdfService.generatePdfFromImages(filteredPaths, fileName: title);

      // 3. Run on-device OCR across all pages
      final ocrText = await _ocrService.extractTextFromPages(filteredPaths);

      // 4. Save to local storage (Hive)
      final doc = ScannedDocument(
        id: const Uuid().v4(),
        title: title,
        pageImagePaths: filteredPaths,
        pdfPath: pdfPath,
        ocrText: ocrText,
        createdAt: DateTime.now(),
        appliedFilter: _selectedFilter.name,
      );

      await context.read<DocumentProvider>().addDocument(doc);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError('Failed to save document: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Document')),
      body: Column(
        children: [
          Expanded(
            child: _capturedPages.isEmpty
                ? const Center(child: Text('Tap "Add Page" to start scanning'))
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: _capturedPages.length,
                    itemBuilder: (context, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(_capturedPages[i]), fit: BoxFit.cover),
                    ),
                  ),
          ),
          // Filter selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<ScanFilter>(
              segments: const [
                ButtonSegment(value: ScanFilter.original, label: Text('Original')),
                ButtonSegment(value: ScanFilter.grayscale, label: Text('Grayscale')),
                ButtonSegment(value: ScanFilter.magicColor, label: Text('Magic Color')),
              ],
              selected: {_selectedFilter},
              onSelectionChanged: (s) => setState(() => _selectedFilter = s.first),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('Add Page'),
                    onPressed: _processing ? null : _startScan,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: _processing
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: Text(_processing ? 'Saving...' : 'Save'),
                    onPressed: _processing ? null : _saveDocument,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
