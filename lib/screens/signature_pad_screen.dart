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
  // Each stroke is its own list of points, so Undo can remove exactly one
  // pen stroke at a time (like Keep Notes / most sketch apps) instead of
  // wiping everything.
  final List<List<Offset>> _strokes = [];
  List<Offset>? _currentStroke;

  final GlobalKey _repaintKey = GlobalKey();

  void _undo() {
    if (_strokes.isEmpty) return;
    setState(() => _strokes.removeLast());
  }

  void _clear() => setState(() => _strokes.clear());

  Future<void> _done() async {
    if (_strokes.isEmpty) {
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
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo last stroke',
            onPressed: _strokes.isEmpty ? null : _undo,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear all',
            onPressed: _strokes.isEmpty ? null : _clear,
          ),
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
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  // GestureDetector and CustomPaint occupy the exact same
                  // box, so details.localPosition already lines up with
                  // where the stroke is drawn — no separate box lookup
                  // needed, which is what caused the previous touch/ink
                  // offset bug.
                  child: GestureDetector(
                    onPanStart: (details) {
                      setState(() {
                        _currentStroke = [details.localPosition];
                        _strokes.add(_currentStroke!);
                      });
                    },
                    onPanUpdate: (details) {
                      setState(() {
                        _currentStroke?.add(details.localPosition);
                      });
                    },
                    onPanEnd: (_) {
                      _currentStroke = null;
                    },
                    child: CustomPaint(
                      painter: _SignaturePainter(_strokes),
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
  final List<List<Offset>> strokes;
  _SignaturePainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    for (final stroke in strokes) {
      if (stroke.length == 1) {
        canvas.drawCircle(stroke[0], linePaint.strokeWidth / 2, dotPaint);
        continue;
      }
      if (stroke.length < 2) continue;

      // Smooth the raw touch points into a curved path using quadratic
      // Bezier segments through midpoints — this is what gives sketch
      // apps like Keep Notes their smooth-ink feel instead of a jagged
      // polyline of straight segments.
      final path = Path()..moveTo(stroke[0].dx, stroke[0].dy);
      for (int i = 1; i < stroke.length - 1; i++) {
        final mid = Offset(
          (stroke[i].dx + stroke[i + 1].dx) / 2,
          (stroke[i].dy + stroke[i + 1].dy) / 2,
        );
        path.quadraticBezierTo(stroke[i].dx, stroke[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(stroke.last.dx, stroke.last.dy);

      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
