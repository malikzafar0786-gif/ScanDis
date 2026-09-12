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

  /// Stamps a small "Scanned on <date/time>" badge in the bottom-right
  /// corner — unlike [applyWatermark], this is a single unobtrusive tag,
  /// not a repeated diagonal stamp.
  Future<String> applyTimestamp(String sourcePath, DateTime timestamp) async {
    final bytes = await File(sourcePath).readAsBytes();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return sourcePath;

    final label =
        '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} '
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

    final font = img.arial24;
    final textWidth = label.length * 13; // rough estimate for arial24
    final x = (image.width - textWidth - 16).clamp(0, image.width);
    final y = image.height - 34;

    // Small dark backing so the timestamp stays legible on any page color.
    img.fillRect(
      image,
      x1: x - 8,
      y1: y - 4,
      x2: image.width - 8,
      y2: y + 26,
      color: img.ColorRgba8(0, 0, 0, 140),
    );
    img.drawString(image, label, font: font, x: x, y: y, color: img.ColorRgba8(255, 255, 255, 255));

    final dir = await getApplicationDocumentsDirectory();
    final outPath = '${dir.path}/${_uuid.v4()}_timestamped.jpg';
    await File(outPath).writeAsBytes(img.encodeJpg(image, quality: 95));
    return outPath;
  }
}
