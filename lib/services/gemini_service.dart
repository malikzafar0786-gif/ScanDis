import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

/// ============================================================
/// 🔑 INSERT YOUR GEMINI API KEY HERE
/// Get one free at: https://aistudio.google.com/app/apikey
/// ⚠️ For production, do NOT hardcode the key in the app binary.
/// Use --dart-define=GEMINI_API_KEY=xxxx at build time, or better,
/// proxy requests through your own backend so the key never ships
/// inside the APK.
/// ============================================================
const String _geminiApiKey = String.fromEnvironment(
  'GEMINI_API_KEY',
  defaultValue: 'PASTE_YOUR_GEMINI_API_KEY_HERE',
);

class GeminiService {
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  Future<String> _callGemini(String prompt) async {
    if (_geminiApiKey == 'PASTE_YOUR_GEMINI_API_KEY_HERE') {
      throw GeminiException('Gemini API key not configured. Add it in gemini_service.dart');
    }

    final uri = Uri.parse('$_baseUrl?key=$_geminiApiKey');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
          'generationConfig': {'temperature': 0.4, 'maxOutputTokens': 1024},
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        throw GeminiException('Gemini API error ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
      if (text == null) throw GeminiException('Empty response from Gemini');
      return text.toString().trim();
    } on GeminiException {
      rethrow;
    } catch (e) {
      throw GeminiException('Network/parse error calling Gemini: $e');
    }
  }

  Future<String> summarize(String documentText) {
    final prompt =
        'Summarize the following document text into 5-8 concise bullet points. '
        'Keep it factual and short.\n\nDocument:\n$documentText';
    return _callGemini(prompt);
  }

  /// language: 'English' | 'Urdu' | 'Spanish'
  Future<String> translate(String documentText, String targetLanguage) {
    final prompt =
        'Translate the following document text into $targetLanguage. '
        'Preserve meaning and structure. Only output the translation.\n\n'
        'Document:\n$documentText';
    return _callGemini(prompt);
  }

  Future<String> chatWithDocument(String documentText, String userQuestion) {
    final prompt =
        'You are answering questions strictly based on the following document. '
        'If the answer is not in the document, say so clearly.\n\n'
        'Document:\n$documentText\n\nQuestion: $userQuestion\nAnswer:';
    return _callGemini(prompt);
  }

  /// Multilingual OCR using Gemini's vision capability — use this for
  /// scripts on-device ML Kit does not support (e.g. Urdu, Arabic, Persian).
  /// Sends the page image directly instead of text.
  Future<String> extractTextFromImage(String imagePath, {String? language}) async {
    if (_geminiApiKey == 'PASTE_YOUR_GEMINI_API_KEY_HERE') {
      throw GeminiException('Gemini API key not configured. Add it in gemini_service.dart');
    }

    final bytes = await File(imagePath).readAsBytes();
    final base64Image = base64Encode(bytes);

    final languageHint = language != null && language.isNotEmpty
        ? ' The document is primarily in $language.'
        : '';

    final prompt =
        'Extract ALL text from this scanned document image exactly as written, '
        'preserving line breaks and paragraph structure.$languageHint '
        'Do not translate, summarize, or add commentary — output only the '
        'raw extracted text, with correct spelling and no distortion of words.';

    final uri = Uri.parse('$_baseUrl?key=$_geminiApiKey');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
                {
                  'inline_data': {'mime_type': 'image/jpeg', 'data': base64Image}
                },
              ]
            }
          ],
          'generationConfig': {'temperature': 0.1, 'maxOutputTokens': 2048},
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        throw GeminiException('Gemini API error ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
      if (text == null) throw GeminiException('Empty response from Gemini');
      return text.toString().trim();
    } on GeminiException {
      rethrow;
    } catch (e) {
      throw GeminiException('Network/parse error calling Gemini vision OCR: $e');
    }
  }
}

class GeminiException implements Exception {
  final String message;
  GeminiException(this.message);
  @override
  String toString() => message;
}
