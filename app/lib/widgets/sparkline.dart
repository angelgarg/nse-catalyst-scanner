import 'package:flutter/material.dart';

class Sparkline extends StatelessWidget {
  final List<double?> values;
  final Color color;
  const Sparkline({super.key, required this.values, required this.color});

  @override
  Widget build(BuildContext context) => CustomPaint(
      size: const Size(72, 28), painter: _SparkPainter(values, color));
}

class _SparkPainter extends CustomPainter {
  final List<double?> values;
  final Color color;
  _SparkPainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final pts = values.whereType<double>().toList();
    if (pts.length < 2) return;
    final lo = pts.reduce((a, b) => a < b ? a : b);
    final hi = pts.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo) == 0 ? 1 : hi - lo;
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final x = size.width * i / (pts.length - 1);
      final y = size.height - (pts[i] - lo) / span * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.values != values || old.color != color;
}
