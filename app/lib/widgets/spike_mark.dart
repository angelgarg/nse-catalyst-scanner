import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';

/// The Spikewise mark (same geometry as the launcher icon, 108-unit viewport):
/// a flat white market line with one amber spike breaking away.
class SpikeMarkPainter extends CustomPainter {
  /// 0 = flat line only, 1 = full spike + dot.
  final double progress;
  final Color line;
  final Listenable? repaintOn;
  SpikeMarkPainter({required this.progress, required this.line, this.repaintOn})
      : super(repaint: repaintOn);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 66,
        ox = (size.width - 66 * k) / 2,
        oy = (size.height - 66 * k) / 2;
    Offset p(double x, double y) =>
        Offset(ox + (x - 21) * k, oy + (y - 21) * k);
    final t = progress.clamp(0.0, 1.0);
    final base = Paint()
      ..color = line
      ..strokeWidth = 4 * k
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(p(28, 74), p(80, 74), base);
    if (t <= 0) return;
    final peakY = 74 - 31 * t;
    final spike = Path()
      ..moveTo(p(50, 74).dx, p(50, 74).dy)
      ..lineTo(p(59, peakY).dx, p(59, peakY).dy)
      ..lineTo(p(68, 74).dx, p(68, 74).dy);
    canvas.drawPath(
        spike,
        Paint()
          ..color = kSpike
          ..strokeWidth = 4.5 * k
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke);
    final dotT = ((t - 0.7) / 0.3).clamp(0.0, 1.0);
    if (dotT > 0) {
      canvas.drawCircle(p(59, 34 + 6 * (1 - dotT)), 3.5 * k,
          Paint()..color = kSpike.withValues(alpha: dotT));
    }
  }

  @override
  bool shouldRepaint(SpikeMarkPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.line != line;
}

/// Brand loader: the spike rises and settles back, replacing Material spinners.
class SpikeMarkLoader extends StatefulWidget {
  final double size;
  final String? label;
  const SpikeMarkLoader({super.key, this.size = 56, this.label});

  @override
  State<SpikeMarkLoader> createState() => _SpikeMarkLoaderState();
}

class _SpikeMarkLoaderState extends State<SpikeMarkLoader>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));
  // up 500ms, hold 300ms, down 400ms, rest 200ms
  late final _t = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 5),
    TweenSequenceItem(tween: ConstantTween(1.0), weight: 3),
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeInCubic)),
        weight: 4),
    TweenSequenceItem(tween: ConstantTween(0.0), weight: 2),
  ]).animate(_c);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Motion.reduced(context) ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.onSurface;
    final reduced = Motion.reduced(context);
    return Semantics(
      label: widget.label ?? 'Loading',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _t,
            builder: (_, __) => CustomPaint(
              size: Size.square(widget.size),
              painter: SpikeMarkPainter(
                  progress: reduced ? 1 : _t.value, line: line),
            ),
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 8),
          Text(widget.label!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
    );
  }
}

/// Grey placeholder shaped like a StockTile; one slow breathe for the whole list.
class SkeletonList extends StatefulWidget {
  final int count;
  const SkeletonList({super.key, this.count = 4});

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Motion.reduced(context) ? _c.value = 0.5 : _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fill =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
    Widget bar(double w, double h) => Container(
        width: w,
        height: h,
        decoration:
            BoxDecoration(color: fill, borderRadius: BorderRadius.circular(6)));
    return Semantics(
      label: 'Loading',
      child: FadeTransition(
        opacity: Tween(begin: 0.55, end: 0.9)
            .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOutSine)),
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            for (var i = 0; i < widget.count; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              bar(80, 14),
                              const SizedBox(height: 6),
                              bar(140, 10),
                              const SizedBox(height: 8),
                              bar(170, 10),
                            ]),
                      ),
                      bar(72, 2),
                      const SizedBox(width: 12),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            bar(64, 14),
                            const SizedBox(height: 6),
                            bar(44, 10)
                          ]),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One-time fade + 8px rise for the first few list items.
class FadeRiseIn extends StatelessWidget {
  final int index;
  final Widget child;
  const FadeRiseIn({super.key, required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    if (index > 5 || Motion.reduced(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 220 + 30 * index),
      curve: Interval(index * 0.1, 1, curve: Motion.curve),
      builder: (_, t, c) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 8 * (1 - t)), child: c)),
      child: child,
    );
  }
}
