import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models.dart';
import '../motion.dart';
import '../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/format.dart';
import '../widgets/spike_mark.dart';
import 'explainers.dart';

/// "Spot the spike": a 20-day price + volume window from at least
/// [minAgeDays] ago, stock name hidden; the user taps the day they think the
/// stock moved on its own, then sees the answer. Detection of a known past
/// event only: no prediction, no prize, no leaderboard (growth + education
/// reviews; SEBI's education guidance asks for delayed price data).
const minAgeDays = 45;

class QuizQuestion {
  final StockDetail d;
  final int start; // index of the first day shown
  final int answer; // index (within the window) of the spike day
  final SpikeEvent event;
  const QuizQuestion(this.d, this.start, this.answer, this.event);

  int get length => 20;
}

/// Picks a window containing exactly one flagged day, old enough to be safe.
QuizQuestion? questionFrom(StockDetail d, DateTime now, math.Random rng) {
  final cutoff = now.subtract(const Duration(days: minAgeDays));
  final byDate = {for (final e in d.events) e.date: e};
  final candidates = <int>[];
  for (var i = 15; i < d.dates.length - 4; i++) {
    final dt = DateTime.tryParse(d.dates[i]);
    if (dt == null || dt.isAfter(cutoff) || i >= d.eventFlags.length || !d.eventFlags[i]) continue;
    if (!byDate.containsKey(d.dates[i])) continue;
    final others = [for (var j = i - 15; j <= i + 4; j++) if (j != i && d.eventFlags[j]) j];
    if (others.isEmpty && d.close.sublist(i - 15, i + 5).every((c) => c != null)) candidates.add(i);
  }
  if (candidates.isEmpty) return null;
  final i = candidates[rng.nextInt(candidates.length)];
  return QuizQuestion(d, i - 15, 15, byDate[d.dates[i]]!);
}

class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  final _rng = math.Random();
  QuizQuestion? _q;
  int? _pick;
  bool _revealed = false;
  bool _loading = true;
  Object? _error;
  int _asked = 0, _spotted = 0;

  @override
  void initState() {
    super.initState();
    _next();
  }

  Future<void> _next() async {
    setState(() {
      _loading = true;
      _error = null;
      _pick = null;
      _revealed = false;
    });
    try {
      final rows = (await ref.read(summaryProvider.future)).where((r) => r.catCount > 0).toList();
      for (var attempt = 0; attempt < 6 && rows.isNotEmpty; attempt++) {
        final row = rows[_rng.nextInt(rows.length)];
        final q = questionFrom(await ref.read(apiProvider).detail(row.ticker), DateTime.now(), _rng);
        if (q != null) {
          if (mounted) setState(() => _q = q);
          break;
        }
      }
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _check() {
    final q = _q!;
    setState(() {
      _revealed = true;
      _asked++;
      if ((_pick! - q.answer).abs() <= 1) _spotted++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Spot the spike'), actions: [
        if (_asked > 0)
          Center(
              child: Padding(padding: const EdgeInsets.only(right: 16), child: Text('$_spotted / $_asked spotted'))),
      ]),
      body: _loading
          ? const Center(child: SpikeMarkLoader(label: 'Finding a past spike…'))
          : _error != null || _q == null
              ? ErrorRetry(error: _error ?? 'No question found. Try again.', onRetry: _next)
              : ListView(padding: const EdgeInsets.all(16), children: [
                  Text('Which day did this stock move most on its own?', style: tt.titleMedium),
                  const SizedBox(height: 4),
                  Text('Mystery NSE stock · 20 trading days from at least $minAgeDays days ago. '
                      'Tap a day on the chart, then check.',
                      style: tt.bodySmall),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _QuizChart(
                        q: _q!,
                        pick: _pick,
                        revealed: _revealed,
                        onPick: _revealed ? null : (i) => setState(() => _pick = i),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (!_revealed)
                    FilledButton(onPressed: _pick == null ? null : _check, child: const Text('Check'))
                  else ...[
                    _Reveal(q: _q!, correct: (_pick! - _q!.answer).abs() <= 1),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _next, child: const Text('Next stock')),
                  ],
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, children: const [
                    WhyChip(label: 'What makes a spike?', explainer: 'spike_rule'),
                    WhyChip(label: 'Volume', explainer: 'volume'),
                  ]),
                  const Disclaimer(),
                ]),
    );
  }
}

class _Reveal extends StatelessWidget {
  final QuizQuestion q;
  final bool correct;
  const _Reveal({required this.q, required this.correct});

  @override
  Widget build(BuildContext context) {
    final e = q.event;
    final tt = Theme.of(context).textTheme;
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.short),
      child: Card(
        key: ValueKey(e.date),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(correct ? 'Spotted it.' : 'Not quite: it was the amber day.',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('${q.d.summary.name} (${e.ticker}), ${prettyDate(e.date)}: ${pct(e.ret, digits: 2)}.'),
            Text('${moveSize(e.z)}: ${vsMarket(e.z)} · ${volumeText(e.vr)}.'),
            const SizedBox(height: 6),
            Text(
                e.category != null
                    ? 'Filing near this date: ${e.category} (may not be the cause).'
                    : 'Company filings aren\'t checked for spikes this old.',
                style: tt.bodySmall),
            const SizedBox(height: 6),
            Text('Tip for next time: look for a big jump or drop together with a much taller volume bar.',
                style: tt.bodySmall),
          ]),
        ),
      ),
    );
  }
}

/// Price line + volume bars for the quiz window; tap selects the nearest day.
class _QuizChart extends StatelessWidget {
  final QuizQuestion q;
  final int? pick;
  final bool revealed;
  final ValueChanged<int>? onPick;
  const _QuizChart({required this.q, required this.pick, required this.revealed, this.onPick});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, box) {
      return GestureDetector(
        onTapDown: onPick == null
            ? null
            : (d) => onPick!((d.localPosition.dx / box.maxWidth * q.length).floor().clamp(0, q.length - 1)),
        child: Semantics(
          label: 'Quiz chart, ${q.length} days. ${pick == null ? 'No day selected' : 'Day ${pick! + 1} selected'}',
          child: CustomPaint(
            size: Size(box.maxWidth, 220),
            painter: _QuizPainter(
              close: [for (var i = 0; i < q.length; i++) q.d.close[q.start + i]!],
              volume: [
                for (var i = 0; i < q.length; i++)
                  q.start + i < q.d.dates.length ? _vol(q, q.start + i) : 0.0
              ],
              pick: pick,
              answer: revealed ? q.answer : null,
              line: cs.onSurface,
              bar: cs.onSurface.withValues(alpha: 0.18),
              pickColor: cs.primary,
            ),
          ),
        ),
      );
    });
  }

  static double _vol(QuizQuestion q, int i) => i < q.d.volume.length ? q.d.volume[i].toDouble() : 0;
}

class _QuizPainter extends CustomPainter {
  final List<double> close, volume;
  final int? pick, answer;
  final Color line, bar, pickColor;
  _QuizPainter(
      {required this.close,
      required this.volume,
      required this.pick,
      required this.answer,
      required this.line,
      required this.bar,
      required this.pickColor});

  @override
  void paint(Canvas canvas, Size size) {
    final n = close.length, w = size.width / n;
    final priceH = size.height * 0.62, volTop = size.height * 0.70, volH = size.height - volTop;
    final lo = close.reduce(math.min), hi = close.reduce(math.max), span = (hi - lo) == 0 ? 1 : hi - lo;
    final vMax = volume.fold<double>(1, math.max);

    void column(int i, Color c) => canvas.drawRect(
        Rect.fromLTWH(i * w, 0, w, size.height), Paint()..color = c.withValues(alpha: 0.16));
    if (answer != null) column(answer!, kSpike);
    if (pick != null && pick != answer) column(pick!, pickColor);

    for (var i = 0; i < n; i++) {
      final h = volume[i] / vMax * volH;
      canvas.drawRect(Rect.fromLTWH(i * w + w * 0.2, size.height - h, w * 0.6, h),
          Paint()..color = i == answer ? kSpike : bar);
    }
    final path = Path();
    for (var i = 0; i < n; i++) {
      final x = i * w + w / 2, y = priceH - (close[i] - lo) / span * (priceH - 8) + 4;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_QuizPainter old) => old.pick != pick || old.answer != answer || old.close != close;
}
