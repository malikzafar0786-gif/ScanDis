import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class WatermarkService {
  final _uuid = const Uuid();

  /// Stamps [text] diagonally across the image (like "CONFIDENTIAL" /
  /// "APPROVED" stamps) and saves a new file, returning its path.
  Future<String> applyWatermark(String sourcePath, String text) async {
    if (text.trim().isEmpty) return sourcePath;

    final bytes = await File(sourcePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return sourcePath;

    // Repeat the watermark a few times diagonally across the page so it's
    // visible regardless of document layout, similar to classic
    // "CONFIDENTIAL" document stamps.
    final font = img.arial48;
    final color = img.ColorRgba8(200, 30, 30, 110); // semi-transparent red

    final stepY = (image.height / 3).round();
    for (int y = -image.height ~/ 2; y < image.height; y += stepY) {
      img.drawString(
        image,
        text,
        font: font,
        x: 20,
        y: y.clamp(0, image.height),
        color: color,
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final outPath = '${dir.path}/${_uuid.v4()}_watermarked.jpg';
    await File(outPath).writeAsBytes(img.encodeJpg(image, quality: 95));
    return outPath;
  }
}
