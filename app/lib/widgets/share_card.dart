import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../data/models.dart';
import '../theme.dart';
import 'format.dart';
import 'spike_mark.dart';

/// Share text that goes with the image. Neutral wording on purpose: it shows
/// what happened and where to read more, never what to do next.
String shareText(SpikeEvent e) => '${e.ticker} ${pct(e.ret, digits: 1)} on ${prettyDate(e.date)}: '
    '${vsMarket(e.z)}. ${e.category != null ? 'Filing near this date: ${e.category}.' : 'No company filing found near this date.'}\n'
    'Educational, not investment advice. Via Spikewise: $kPlayUrl';

/// Preview sheet with the card and a Share button (WhatsApp is the main target).
Future<void> shareSpike(BuildContext context, SpikeEvent e) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ShareSheet(e: e),
    );

class _ShareSheet extends StatefulWidget {
  final SpikeEvent e;
  const _ShareSheet({required this.e});

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _boundary = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final ro = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 1080 / ro.size.width);
      final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
      final file = File('${(await getTemporaryDirectory()).path}/spikewise-${widget.e.ticker}-${widget.e.date}.png');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: shareText(widget.e)));
    } catch (_) {
      // Image capture failed (very old GPU): fall back to text only.
      await SharePlus.instance.share(ShareParams(text: shareText(widget.e)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            RepaintBoundary(key: _boundary, child: SpikeShareCard(e: widget.e)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _share,
                icon: const Icon(Icons.share),
                label: Text(_busy ? 'Preparing…' : 'Share'),
              ),
            ),
          ]),
        ),
      );
}

/// The shareable image: a fixed 360x450 canvas (4:5) scaled to fit, captured at
/// 1080 px wide. Ignores the phone's font scale and always uses dark brand
/// colours, so it looks the same in every chat.
class SpikeShareCard extends StatelessWidget {
  final SpikeEvent e;
  const SpikeShareCard({super.key, required this.e});

  static const _bg = Color(0xFF0B1220), _fg = Color(0xFFE7ECF6), _muted = Color(0xFF93A1BD);
  static const _up = Color(0xFF4ADE80), _down = Color(0xFFF87171);

  @override
  Widget build(BuildContext context) {
    final c = (e.ret ?? 0) >= 0 ? _up : _down;
    return FittedBox(
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
        child: SizedBox(width: 360, height: 450, child: _card(c)),
      ),
    );
  }

  Widget _card(Color c) {
    const one = 1;
    return Container(
        decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.all(20),
        child: DefaultTextStyle(
          style: const TextStyle(color: _fg, fontSize: 14, height: 1.3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CustomPaint(size: const Size.square(30), painter: SpikeMarkPainter(progress: 1, line: _fg)),
              const SizedBox(width: 8),
              const Text('Spikewise', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const Spacer(),
              Text(prettyDate(e.date), style: const TextStyle(color: _muted)),
            ]),
            const Spacer(),
            Text(e.ticker,
                maxLines: one,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
            if (e.name.isNotEmpty && e.name != e.ticker)
              Text(e.name, maxLines: one, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted)),
            const SizedBox(height: 6),
            Text(pct(e.ret, digits: 1),
                maxLines: one,
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: c, fontFeatures: tabular)),
            Text('${vsMarket(e.z)[0].toUpperCase()}${vsMarket(e.z).substring(1)}',
                maxLines: 2, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text('${moveSize(e.z)} · ${volumeText(e.vr)}', maxLines: one, style: const TextStyle(color: _muted)),
            const Spacer(),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kSpike.withValues(alpha: 0.5)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e.category != null ? 'Filing near this date (${e.exchange ?? 'NSE/BSE'})' : 'No company filing found',
                    maxLines: one, style: const TextStyle(fontWeight: FontWeight.w700, color: kSpike, fontSize: 13)),
                if (e.category != null)
                  Text(e.category!, maxLines: one, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                const Text('May not be the cause of the move.',
                    maxLines: one, style: TextStyle(color: _muted, fontSize: 11)),
              ]),
            ),
            const SizedBox(height: 10),
            const Text('Educational, not investment advice · Not SEBI-registered',
                maxLines: 2, style: TextStyle(color: _muted, fontSize: 10)),
          ]),
        ),
    );
  }
}
