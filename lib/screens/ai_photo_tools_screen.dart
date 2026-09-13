import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';

import '../services/gemini_service.dart';

enum _AiPhotoMode { enhance, restore, colorize }

class AiPhotoToolsScreen extends StatefulWidget {
  const AiPhotoToolsScreen({super.key});

  @override
  State<AiPhotoToolsScreen> createState() => _AiPhotoToolsScreenState();
}

class _AiPhotoToolsScreenState extends State<AiPhotoToolsScreen> {
  final _picker = ImagePicker();
  final _gemini = GeminiService();

  String? _sourcePath;
  Uint8List? _resultBytes;
  bool _processing = false;
  String? _error;

  static const Map<_AiPhotoMode, String> _prompts = {
    _AiPhotoMode.enhance:
        'Enhance this photo: sharpen details, correct lighting and color balance, '
        'reduce noise and blur, and make it look crisp and high-resolution. '
        'Keep every subject, face, and detail exactly the same — do not add, '
        'remove, or change any content, only improve image quality.',
    _AiPhotoMode.restore:
        'Restore this old, damaged, or faded photo: repair scratches, tears, '
        'creases, and discoloration, and recover lost detail and sharpness. '
        'Keep faces, likeness, clothing, and composition exactly the same — '
        'do not invent new details, only repair damage.',
    _AiPhotoMode.colorize:
        'Colorize this black-and-white photo with natural, historically '
        'plausible colors appropriate to the scene, skin tones, and setting. '
        'Keep every detail, face, and composition exactly the same as the '
        'original — only add realistic color.',
  };

  Future<void> _pickImage() async {
    final choice = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return;

    final photo = await _picker.pickImage(source: choice, imageQuality: 90);
    if (photo == null) return;

    setState(() {
      _sourcePath = photo.path;
      _resultBytes = null;
      _error = null;
    });
  }

  Future<void> _run(_AiPhotoMode mode) async {
    if (_sourcePath == null) return;
    setState(() {
      _processing = true;
      _error = null;
      _resultBytes = null;
    });
    try {
      final bytes = await _gemini.editImage(_sourcePath!, _prompts[mode]!);
      setState(() => _resultBytes = bytes);
    } on GeminiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Unexpected error: $e');
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _saveAndShare() async {
    if (_resultBytes == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/${const Uuid().v4()}_ai_photo.png';
    await File(path).writeAsBytes(_resultBytes!);
    await Share.shareXFiles([XFile(path)], text: 'AI-processed photo — ScanDis');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('AI Photo Tools')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 280,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _processing
                  ? const Center(child: CircularProgressIndicator())
                  : _resultBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(_resultBytes!, fit: BoxFit.contain),
                        )
                      : _sourcePath != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.file(File(_sourcePath!), fit: BoxFit.contain),
                            )
                          : Center(
                              child: TextButton.icon(
                                icon: const Icon(Icons.add_photo_alternate_outlined),
                                label: const Text('Choose a Photo'),
                                onPressed: _pickImage,
                              ),
                            ),
            ),
            if (_sourcePath != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: const Text('Change Photo'),
                  onPressed: _processing ? null : _pickImage,
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('⚠️ $_error', style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 8),
            Text('Choose an AI action', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            _actionTile(
              icon: Icons.auto_awesome,
              title: 'AI Enhance',
              subtitle: 'Sharpen, fix lighting, reduce noise',
              onTap: () => _run(_AiPhotoMode.enhance),
            ),
            const SizedBox(height: 8),
            _actionTile(
              icon: Icons.healing_outlined,
              title: 'Restore Old Photo',
              subtitle: 'Repair scratches, damage, fading',
              onTap: () => _run(_AiPhotoMode.restore),
            ),
            const SizedBox(height: 8),
            _actionTile(
              icon: Icons.palette_outlined,
              title: 'Colorize B&W Photo',
              subtitle: 'Add realistic color to black & white photos',
              onTap: () => _run(_AiPhotoMode.colorize),
            ),
            if (_resultBytes != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('Save & Share Result'),
                onPressed: _saveAndShare,
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Each AI action uses Gemini\'s image model and may take up to a minute. '
              'Results are AI-generated approximations — always review before relying on them.',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      tileColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      leading: Icon(icon, color: scheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      enabled: _sourcePath != null && !_processing,
      onTap: onTap,
    );
  }
}
