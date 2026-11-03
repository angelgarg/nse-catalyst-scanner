import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:spikewise/services/billing.dart';

ProductDetails _p(String id, double price) => ProductDetails(
  id: id,
  title: id,
  description: '',
  price: '₹${price.toStringAsFixed(0)}',
  rawPrice: price,
  currencyCode: 'INR',
  currencySymbol: '₹',
);

void main() {
  test('trial period text', () {
    expect(trialText('P7D'), '7-day free trial');
    expect(trialText('P1M'), '1-month free trial');
    expect(trialText('weird'), 'Free trial');
  });

  test('one plan per product, cheapest first, recurring price kept', () {
    final plans = plansFrom([
      _p('spikewise_pro_yearly', 799),
      _p('spikewise_pro_monthly', 99),
      _p('spikewise_pro_monthly', 99), // duplicate offer entry
    ]);
    expect(plans.map((p) => p.id), [
      'spikewise_pro_monthly',
      'spikewise_pro_yearly',
    ]);
    expect(plans.last.price, '₹799');
    expect(plans.every((p) => p.trial == null), isTrue);
  });

  test('manage subscription link points at this app', () {
    expect(
      manageSubscriptionUrl('spikewise_pro_yearly'),
      contains('package=com.angelgarg.spikewise&sku=spikewise_pro_yearly'),
    );
  });
}
