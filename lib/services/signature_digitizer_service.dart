import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

class _DigitizeParams {
  final Uint8List bytes;
  final int darknessThreshold;
  _DigitizeParams(this.bytes, this.darknessThreshold);
}

/// Converts a photo of a signature made on paper into a clean, transparent
/// digital signature (ink strokes only, paper background removed) — ready
/// to composite onto scanned documents the same way a drawn signature is.
class SignatureDigitizerService {
  /// [darknessThreshold] (0-255): pixels darker than this are treated as
  /// ink and kept opaque; everything lighter becomes transparent. Lower it
  /// if faint pen strokes are being erased; raise it if paper shadows are
  /// showing up as ink.
  Future<Uint8List> digitizeFromPhoto(String photoPath, {int darknessThreshold = 140}) async {
    final bytes = await File(photoPath).readAsBytes();

    // The heavy per-pixel work runs on a separate isolate via compute() so
    // it can never freeze the UI thread / trigger an ANR ("app not
    // responding") crash, no matter how big the source photo is.
    return compute(_digitizeInBackground, _DigitizeParams(bytes, darknessThreshold));
  }
}

/// Runs on a background isolate (spawned by compute()). Must be a top-level
/// or static function — it cannot access `this` or any instance state.
Uint8List _digitizeInBackground(_DigitizeParams params) {
  img.Image? image = img.decodeImage(params.bytes);
  if (image == null) {
    throw Exception('Could not decode signature photo');
  }

  // Camera photos are commonly 12+ megapixels — far more detail than a
  // signature needs and expensive to process pixel-by-pixel. Downsizing
  // first is what actually prevents the freeze/crash: it cuts the pixel
  // loop below from tens of millions of iterations down to about a
  // million, which finishes in a fraction of a second.
  const maxDimension = 1000;
  if (image.width > maxDimension || image.height > maxDimension) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxDimension)
        : img.copyResize(image, height: maxDimension);
  }

  // Even out uneven lighting/shadows on the paper before thresholding.
  image = img.grayscale(image);
  image = img.normalize(image, min: 0, max: 255);

  final output = img.Image(width: image.width, height: image.height, numChannels: 4);

  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      final luminance = pixel.r; // grayscale, so r==g==b
      if (luminance < params.darknessThreshold) {
        // Ink: draw as a solid dark stroke, opacity scaled by darkness so
        // anti-aliased pen edges stay smooth instead of jagged.
        final alpha = (255 - luminance).clamp(0, 255);
        output.setPixelRgba(x, y, 20, 20, 20, alpha);
      } else {
        output.setPixelRgba(x, y, 0, 0, 0, 0); // fully transparent
      }
    }
  }

  return Uint8List.fromList(img.encodePng(output));
}
