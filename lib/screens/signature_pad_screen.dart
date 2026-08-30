import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class SignaturePadScreen extends StatefulWidget {
  const SignaturePadScreen({super.key});

  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  final List<Offset?> _points = [];
  final GlobalKey _repaintKey = GlobalKey();

  void _clear() => setState(() => _points.clear());

  Future<void> _done() async {
    if (_points.isEmpty) {
      Navigator.pop(context, null);
      return;
    }
    try {
      final boundary =
          _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      Navigator.pop(context, byteData?.buffer.asUint8List());
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Draw Your Signature'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clear),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Sign inside the box below with your finger'),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: RepaintBoundary(
                key: _repaintKey,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      // details.localPosition is already relative to this
                      // GestureDetector's own box — no manual conversion
                      // needed. (The previous version used context from
                      // the wrong ancestor widget, causing the drawn line
                      // to appear offset from the actual touch point.)
                      setState(() {
                        _points.add(details.localPosition);
                      });
                    },
                    onPanEnd: (_) => setState(() => _points.add(null)),
                    child: CustomPaint(
                      painter: _SignaturePainter(_points),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Use This Signature'),
              onPressed: _done,
            ),
          ),
        ],
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<Offset?> points;
  _SignaturePainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      if (p1 != null && p2 != null) {
        canvas.drawLine(p1, p2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
