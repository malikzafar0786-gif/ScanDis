import 'dart:io';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class PdfService {
  final _uuid = const Uuid();

  /// Combines multiple page images into a single PDF file.
  /// Returns the saved PDF's local file path.
  Future<String> generatePdfFromImages(List<String> imagePaths, {String? fileName}) async {
    final pdf = pw.Document();

    for (final path in imagePaths) {
      final imageBytes = await File(path).readAsBytes();
      final image = pw.MemoryImage(imageBytes);
      pdf.addPage(
        pw.Page(
          build: (context) => pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final name = fileName ?? 'scan_${_uuid.v4()}';
    final outPath = '${dir.path}/$name.pdf';
    final file = File(outPath);
    await file.writeAsBytes(await pdf.save());
    return outPath;
  }
}
