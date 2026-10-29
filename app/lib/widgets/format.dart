import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

final _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

String inr(double? v) => v == null ? '—' : _inr.format(v);

String pct(double? v, {int digits = 1}) =>
    v == null ? '—' : '${v >= 0 ? '+' : ''}${(v * 100).toStringAsFixed(digits)}%';

String num2(double? v, {int digits = 2}) => v == null ? '—' : v.toStringAsFixed(digits);

Color signColor(BuildContext context, double? v) => v == null
    ? Theme.of(context).colorScheme.onSurfaceVariant
    : (v >= 0 ? kUp : kDown);

String prettyDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  return d == null ? iso : DateFormat('d MMM yyyy').format(d);
}
