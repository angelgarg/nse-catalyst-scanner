import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../state/providers.dart';
import '../widgets/common.dart';

class FeedbackScreen extends ConsumerStatefulWidget {
  final String? screen;
  final String? ticker;
  const FeedbackScreen({super.key, this.screen, this.ticker});

  @override
  ConsumerState<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends ConsumerState<FeedbackScreen> {
  final _msg = TextEditingController();
  String _kind = 'idea';
  int _rating = 0;
  bool _sending = false;

  @override
  void dispose() {
    _msg.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_msg.text.trim().length < 3) return;
    setState(() => _sending = true);
    final info = await PackageInfo.fromPlatform();
    try {
      await ref.read(apiProvider).sendFeedback({
        'message': _msg.text.trim(),
        'kind': _kind,
        if (_rating > 0) 'rating': _rating,
        'app_build': '${info.version}+${info.buildNumber}',
        'platform': 'android',
        'screen': widget.screen ?? 'more',
        'ticker': widget.ticker ?? '',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks! Your feedback was sent.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send feedback')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'idea', label: Text('Idea')),
            ButtonSegment(value: 'bug', label: Text('Bug')),
            ButtonSegment(value: 'data', label: Text('Wrong data')),
          ],
          selected: {_kind},
          onSelectionChanged: (v) => setState(() => _kind = v.first),
        ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(
              tooltip: '$i star${i > 1 ? 's' : ''}',
              icon: Icon(i <= _rating ? Icons.star : Icons.star_outline),
              onPressed: () => setState(() => _rating = i),
            ),
        ]),
        TextField(
          controller: _msg,
          maxLines: 6,
          maxLength: 4000,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'What should we fix or build next?',
          ),
          onChanged: (_) => setState(() {}),
        ),
        Text(
            'Feedback is posted publicly in our GitHub project so it can be fixed. Don\'t include '
            'your name, email, phone, or any bank or trading account details.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _sending || _msg.text.trim().length < 3 ? null : _send,
          child: Text(_sending ? 'Sending…' : 'Send'),
        ),
      ]),
    );
  }
}
