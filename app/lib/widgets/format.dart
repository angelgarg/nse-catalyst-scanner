import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

final _inr2 =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);
final _inr0 =
    NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
final _compact =
    NumberFormat.compactCurrency(locale: 'en_IN', symbol: '', decimalDigits: 1);
final _ist = const Duration(hours: 5, minutes: 30);

const tabular = [FontFeature.tabularFigures()];

String inr(double? v) =>
    v == null ? '—' : (v.abs() >= 1000 ? _inr0 : _inr2).format(v);

String compactNum(double v) =>
    v.abs() >= 1000 ? _compact.format(v).trim() : v.toStringAsFixed(0);

String pct(double? v, {int digits = 1}) {
  if (v == null) return '—';
  final s = (v * 100).toStringAsFixed(digits);
  if (double.parse(s) == 0) return '${(0).toStringAsFixed(digits)}%';
  return '${v > 0 ? '+' : ''}$s%';
}

String num2(double? v, {int digits = 2}) =>
    v == null ? '—' : v.toStringAsFixed(digits);

Color signColor(BuildContext context, double? v) {
  if (v == null || (v * 10000).round() == 0) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }
  return v > 0 ? upColor(context) : downColor(context);
}

/// Plain-language size of a market-adjusted move (|z|).
String moveSize(double? z) {
  final a = z?.abs();
  if (a == null) return 'Unusual move';
  if (a >= 3) return 'Rare move';
  if (a >= 2) return 'Very big move';
  return 'Big move';
}

String volumeText(double? vr) =>
    vr == null ? '' : '${vr.toStringAsFixed(1)}× usual volume';

String prettyDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final now = DateTime.now().toUtc().add(_ist);
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return DateFormat(d.year == now.year ? 'd MMM' : 'd MMM yyyy').format(d);
}

/// '2026-10-29T14:02:23Z' -> '29 Oct, 7:32 pm IST'
String istTime(String? isoUtc) {
  final d = DateTime.tryParse(isoUtc ?? '');
  if (d == null) return '';
  return '${DateFormat('d MMM, h:mm a').format(d.toUtc().add(_ist)).replaceAll('AM', 'am').replaceAll('PM', 'pm')} IST';
}
