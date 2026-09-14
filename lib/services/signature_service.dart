import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class SignatureService {
  final _uuid = const Uuid();

  /// Composites [signaturePngBytes] onto the bottom-right corner of the
  /// page image at [pagePath], and saves a new file (original untouched).
  Future<String> applySignature(String pagePath, Uint8List signaturePngBytes) async {
    final pageBytes = await File(pagePath).readAsBytes();
    img.Image? page = img.decodeImage(pageBytes);
    img.Image? signature = img.decodePng(signaturePngBytes);
    if (page == null || signature == null) return pagePath;

    // Scale signature to ~30% of page width, keep aspect ratio.
    final targetWidth = (page.width * 0.3).round();
    final scale = targetWidth / signature.width;
    signature = img.copyResize(
      signature,
      width: targetWidth,
      height: (signature.height * scale).round(),
    );

    final dstX = page.width - signature.width - 24;
    final dstY = page.height - signature.height - 24;

    img.compositeImage(page, signature, dstX: dstX, dstY: dstY);

    final dir = await getApplicationDocumentsDirectory();
    final outPath = '${dir.path}/${_uuid.v4()}_signed.jpg';
    await File(outPath).writeAsBytes(img.encodeJpg(page, quality: 95));
    return outPath;
  }
}
