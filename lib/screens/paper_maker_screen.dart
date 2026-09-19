import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../services/ocr_service.dart';
import '../services/gemini_service.dart';
import '../services/pdf_service.dart';

class PaperMakerScreen extends StatefulWidget {
  const PaperMakerScreen({super.key});

  @override
  State<PaperMakerScreen> createState() => _PaperMakerScreenState();
}

class _PaperMakerScreenState extends State<PaperMakerScreen> {
  final _picker = ImagePicker();
  final _ocrService = OcrService();
  final _gemini = GeminiService();
  final _pdfService = PdfService();

  final List<String> _pagePaths = [];
  String? _extractedText;
  bool _extractingText = false;

  bool _includeObjective = true;
  final _objectiveCountController = TextEditingController(text: '10');

  bool _includeSubjective = true;
  final _totalMarksController = TextEditingController(text: '50');
  final _shortCountController = TextEditingController(text: '5');
  final _longCountController = TextEditingController(text: '3');

  bool _generating = false;
  String? _paperResult;
  final _titleController = TextEditingController(text: 'Exam Paper');

  @override
  void dispose() {
    _ocrService.dispose();
    _objectiveCountController.dispose();
    _totalMarksController.dispose();
    _shortCountController.dispose();
    _longCountController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _addPages() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo of Book Page'),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose Photos from Gallery'),
              onTap: () => Navigator.pop(sheetContext, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    if (choice == 'camera') {
      final photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 95);
      if (photo != null) setState(() => _pagePaths.add(photo.path));
    } else {
      final photos = await _picker.pickMultiImage(imageQuality: 95);
      if (photos.isNotEmpty) {
        setState(() => _pagePaths.addAll(photos.map((p) => p.path)));
      }
    }
    setState(() {
      _extractedText = null;
      _paperResult = null;
    });
  }

  void _removePage(int index) {
    setState(() {
      _pagePaths.removeAt(index);
      _extractedText = null;
      _paperResult = null;
    });
  }

  Future<void> _extractText() async {
    if (_pagePaths.isEmpty) return;
    setState(() => _extractingText = true);
    try {
      final text = await _ocrService.extractTextFromPages(_pagePaths);
      if (text.trim().isEmpty) {
        _showError('No readable text found in these pages. Try clearer, well-lit photos.');
      }
      setState(() => _extractedText = text);
    } catch (e) {
      _showError('Text extraction failed: $e');
    } finally {
      if (mounted) setState(() => _extractingText = false);
    }
  }

  Future<void> _generatePaper() async {
    if (_extractedText == null || _extractedText!.trim().isEmpty) {
      _showError('Extract text from the book pages first.');
      return;
    }
    if (!_includeObjective && !_includeSubjective) {
      _showError('Select at least one section (Objective or Subjective).');
      return;
    }

    setState(() {
      _generating = true;
      _paperResult = null;
    });
    try {
      final paper = await _gemini.generatePaper(
        bookText: _extractedText!,
        includeObjective: _includeObjective,
        objectiveCount: int.tryParse(_objectiveCountController.text) ?? 10,
        includeSubjective: _includeSubjective,
        totalMarks: int.tryParse(_totalMarksController.text) ?? 50,
        shortQuestionCount: int.tryParse(_shortCountController.text) ?? 5,
        longQuestionCount: int.tryParse(_longCountController.text) ?? 3,
      );
      setState(() => _paperResult = paper);
    } on GeminiException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _exportPdf() async {
    if (_paperResult == null) return;
    try {
      final path = await _pdfService.generateTextPdf(_titleController.text, _paperResult!);
      await Share.shareXFiles([XFile(path)], text: _titleController.text);
    } catch (e) {
      _showError('Export failed: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Paper Maker')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('1. Book / Chapter Pages', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_pagePaths.isNotEmpty)
              SizedBox(
                height: 90,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pagePaths.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(_pagePaths[i]), width: 70, height: 90, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => _removePage(i),
                            child: const CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.add_a_photo_outlined),
              label: Text(_pagePaths.isEmpty ? 'Add Book Pages' : 'Add More Pages'),
              onPressed: _addPages,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: _extractingText
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.text_fields),
              label: Text(_extractingText ? 'Reading pages...' : 'Extract Text from Pages'),
              onPressed: _pagePaths.isEmpty || _extractingText ? null : _extractText,
            ),
            if (_extractedText != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _extractedText!.isEmpty
                      ? 'No text found.'
                      : '${_extractedText!.substring(0, _extractedText!.length > 200 ? 200 : _extractedText!.length)}...',
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
            ],

            const SizedBox(height: 24),
            Text('2. Paper Structure', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _includeObjective,
              onChanged: (v) => setState(() => _includeObjective = v),
              title: const Text('Objective Section (معروضی)'),
            ),
            if (_includeObjective)
              TextField(
                controller: _objectiveCountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Number of objective questions',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            const SizedBox(height: 16),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _includeSubjective,
              onChanged: (v) => setState(() => _includeSubjective = v),
              title: const Text('Subjective Section (انشائیہ)'),
            ),
            if (_includeSubjective) ...[
              TextField(
                controller: _totalMarksController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Total marks',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _shortCountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Number of short questions',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _longCountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Number of detailed/long questions',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],

            const SizedBox(height: 20),
            FilledButton.icon(
              icon: _generating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              label: Text(_generating ? 'Generating Paper...' : 'Generate Paper with AI'),
              onPressed: _extractedText == null || _generating ? null : _generatePaper,
            ),

            if (_paperResult != null) ...[
              const SizedBox(height: 24),
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Paper title', border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(Icons.copy_outlined, size: 16),
                        label: const Text('Copy'),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _paperResult!));
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(content: Text('Copied to clipboard.')));
                        },
                      ),
                    ),
                    SelectableText(_paperResult!),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Export as PDF'),
                onPressed: _exportPdf,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
