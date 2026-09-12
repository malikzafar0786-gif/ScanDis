import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Extracts text from a single image file (on-device, no internet needed).
  Future<String> extractTextFromImage(String imagePath) async {
    try {
      final inputImage = InputImage.fromFile(File(imagePath));
      final RecognizedText result = await _recognizer.processImage(inputImage);
      return result.text;
    } catch (e) {
      throw OcrException('OCR failed for $imagePath: $e');
    }
  }

  /// Extracts text from multiple pages and merges them with page separators.
  Future<String> extractTextFromPages(List<String> imagePaths) async {
    final buffer = StringBuffer();
    for (int i = 0; i < imagePaths.length; i++) {
      try {
        final text = await extractTextFromImage(imagePaths[i]);
        buffer.writeln('--- Page ${i + 1} ---');
        buffer.writeln(text);
        buffer.writeln();
      } catch (e) {
        buffer.writeln('--- Page ${i + 1} (OCR failed) ---');
      }
    }
    return buffer.toString().trim();
  }

  void dispose() => _recognizer.close();
}

class OcrException implements Exception {
  final String message;
  OcrException(this.message);
  @override
  String toString() => message;
}
