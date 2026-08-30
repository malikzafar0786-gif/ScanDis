import 'dart:io';
import 'dart:typed_data';
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
import '../services/watermark_service.dart';
import '../services/signature_service.dart';
import 'signature_pad_screen.dart';

// Raise this if you want more pages per document. flutter_doc_scanner has
// no hard cap of its own — 4 was just a value baked into the old code.
const int kMaxScanPages = 50;

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final List<String> _capturedPages = [];
  ScanFilter _selectedFilter = ScanFilter.original;
  bool _processing = false;

  // Manual adjustment sliders (-100..100), applied on top of the preset.
  double _brightness = 0;
  double _contrast = 0;
  double _saturation = 0;
  bool _showAdjustPanel = false;

  bool _addWatermark = false;
  final _watermarkController = TextEditingController();
  final _watermarkService = WatermarkService();
  final _signatureService = SignatureService();

  final _filterService = ImageFilterService();
  final _pdfService = PdfService();
  final _ocrService = OcrService();

  /// The plugin's native return shape varies by version/platform: it can
  /// come back as a Map (with an 'images'/'Uri' list inside), a plain
  /// List, or a single String path. This handles all three instead of
  /// assuming one shape and crashing on the others.
  List<String> _extractPaths(dynamic result) {
    if (result == null) return [];

    if (result is String) return [result];

    if (result is List) {
      return result.map((e) => e.toString()).toList();
    }

    if (result is Map) {
      for (final key in ['images', 'Uri', 'uri', 'paths', 'imagePaths']) {
        final value = result[key];
        if (value is List) {
          return value.map((e) => e.toString()).toList();
        }
        if (value is String) {
          return [value];
        }
      }
    }

    final asString = result.toString();
    return asString.isNotEmpty ? [asString] : [];
  }

  Future<void> _startScan() async {
    if (_capturedPages.length >= kMaxScanPages) {
      _showError('Maximum $kMaxScanPages pages reached for one document.');
      return;
    }

    final cameraStatus = await Permission.camera.request();
    if (!cameraStatus.isGranted) {
      _showError('Camera permission is required to scan documents.');
      return;
    }

    try {
      final remaining = kMaxScanPages - _capturedPages.length;
      final dynamic result =
          await FlutterDocScanner().getScannedDocumentAsImages(page: remaining);

      final paths = _extractPaths(result);
      if (paths.isNotEmpty) {
        setState(() => _capturedPages.addAll(paths));
      }
    } catch (e) {
      _showError('Scanning failed: $e');
    }
  }

  void _removePage(int index) {
    setState(() => _capturedPages.removeAt(index));
  }

  Future<void> _addSignatureToLastPage() async {
    if (_capturedPages.isEmpty) {
      _showError('Scan a page first, then add your signature to it.');
      return;
    }
    final bytes = await Navigator.push<Uint8List?>(
      context,
      MaterialPageRoute(builder: (_) => const SignaturePadScreen()),
    );
    if (bytes == null) return;

    setState(() => _processing = true);
    try {
      final lastIndex = _capturedPages.length - 1;
      final signedPath = await _signatureService.applySignature(_capturedPages[lastIndex], bytes);
      setState(() => _capturedPages[lastIndex] = signedPath);
    } catch (e) {
      _showError('Could not add signature: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _saveDocument() async {
    if (_capturedPages.isEmpty) {
      _showError('Please scan at least one page first.');
      return;
    }

    setState(() => _processing = true);
    try {
      final filteredPaths = <String>[];
      for (final path in _capturedPages) {
        var filtered = await _filterService.applyFilter(
          path,
          _selectedFilter,
          brightness: _brightness,
          contrast: _contrast,
          saturation: _saturation,
        );
        if (_addWatermark && _watermarkController.text.trim().isNotEmpty) {
          filtered = await _watermarkService.applyWatermark(filtered, _watermarkController.text.trim());
        }
        filteredPaths.add(filtered);
      }

      final title = 'Scan_${DateTime.now().millisecondsSinceEpoch}';
      final pdfPath = await _pdfService.generatePdfFromImages(filteredPaths, fileName: title);
      final ocrText = await _ocrService.extractTextFromPages(filteredPaths);

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
    _watermarkController.dispose();
    super.dispose();
  }

  Widget _buildSlider(String label, double value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(width: 80, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(
            value: value,
            min: -100,
            max: 100,
            divisions: 40,
            label: value.round().toString(),
            onChanged: onChanged,
          ),
        ),
        SizedBox(width: 34, child: Text(value.round().toString(), textAlign: TextAlign.end)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Scan Document (${_capturedPages.length}/$kMaxScanPages)'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _capturedPages.isEmpty
                ? const Center(child: Text('Tap "Add Page" to start scanning'))
                : ReorderableListView.builder(
                    padding: const EdgeInsets.all(12),
                    scrollDirection: Axis.horizontal,
                    itemCount: _capturedPages.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = _capturedPages.removeAt(oldIndex);
                        _capturedPages.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, i) => Padding(
                      key: ValueKey(_capturedPages[i]),
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 110,
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox.expand(
                                child: Image.file(File(_capturedPages[i]), fit: BoxFit.cover),
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () => _removePage(i),
                                child: const CircleAvatar(
                                  radius: 12,
                                  backgroundColor: Colors.black54,
                                  child: Icon(Icons.close, size: 14, color: Colors.white),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 2,
                              left: 2,
                              child: CircleAvatar(
                                radius: 10,
                                backgroundColor: Colors.black54,
                                child: Text('${i + 1}',
                                    style: const TextStyle(fontSize: 11, color: Colors.white)),
                              ),
                            ),
                            const Positioned(
                              bottom: 2,
                              right: 2,
                              child: Icon(Icons.drag_indicator, size: 16, color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<ScanFilter>(
                segments: const [
                  ButtonSegment(value: ScanFilter.original, label: Text('Original')),
                  ButtonSegment(value: ScanFilter.grayscale, label: Text('B&W')),
                  ButtonSegment(value: ScanFilter.magicColor, label: Text('Magic Color')),
                  ButtonSegment(
                    value: ScanFilter.autoEnhance,
                    label: Text('HD Enhance'),
                    icon: Icon(Icons.auto_awesome, size: 16),
                  ),
                ],
                selected: {_selectedFilter},
                onSelectionChanged: (s) => setState(() => _selectedFilter = s.first),
              ),
            ),
          ),

          TextButton.icon(
            onPressed: () => setState(() => _showAdjustPanel = !_showAdjustPanel),
            icon: Icon(_showAdjustPanel ? Icons.expand_less : Icons.tune),
            label: const Text('Manual Adjust (Brightness / Contrast / Color)'),
          ),
          if (_showAdjustPanel)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  _buildSlider('Brightness', _brightness, (v) => setState(() => _brightness = v)),
                  _buildSlider('Contrast', _contrast, (v) => setState(() => _contrast = v)),
                  _buildSlider('Color', _saturation, (v) => setState(() => _saturation = v)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() {
                        _brightness = 0;
                        _contrast = 0;
                        _saturation = 0;
                      }),
                      child: const Text('Reset'),
                    ),
                  ),
                ],
              ),
            ),

          // Watermark / stamp
          CheckboxListTile(
            dense: true,
            value: _addWatermark,
            onChanged: (v) => setState(() => _addWatermark = v ?? false),
            title: const Text('Add watermark / stamp (e.g. CONFIDENTIAL)'),
          ),
          if (_addWatermark)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _watermarkController,
                decoration: const InputDecoration(
                  hintText: 'Watermark text',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.draw_outlined),
                    label: const Text('Sign Last Page'),
                    onPressed: _processing ? null : _addSignatureToLastPage,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
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
