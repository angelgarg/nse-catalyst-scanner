import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../config.dart';
import '../state/providers.dart';

/// One purchasable plan. A subscription comes back from Play as one
/// ProductDetails per offer (base plan, free trial, ...): [buy] is the offer to
/// purchase, while [price] is always the recurring price, never a ₹0 trial phase.
class Plan {
  final String id;
  final ProductDetails buy;
  final String price;
  final double priceValue;
  final String currency;
  final String? trial; // e.g. "7-day free trial"

  const Plan({
    required this.id,
    required this.buy,
    required this.price,
    required this.priceValue,
    required this.currency,
    this.trial,
  });
}

class BillingState {
  final bool available;
  final bool loading;
  final bool pending;
  final List<Plan> plans;
  final String? error;

  const BillingState({
    this.available = false,
    this.loading = true,
    this.pending = false,
    this.plans = const [],
    this.error,
  });

  BillingState copyWith({
    bool? available,
    bool? loading,
    bool? pending,
    List<Plan>? plans,
    String? error,
  }) => BillingState(
    available: available ?? this.available,
    loading: loading ?? this.loading,
    pending: pending ?? this.pending,
    plans: plans ?? this.plans,
    error: error,
  );
}

/// 'P7D' -> '7-day free trial'.
String trialText(String isoPeriod) {
  final m = RegExp(r'^P(\d+)([DWM])$').firstMatch(isoPeriod);
  if (m == null) return 'Free trial';
  final n = int.parse(m.group(1)!);
  final unit = {'D': 'day', 'W': 'week', 'M': 'month'}[m.group(2)]!;
  return '$n-$unit free trial';
}

/// Builds one [Plan] per product id, preferring an offer with a free trial
/// (Play only returns offers the user is still eligible for).
List<Plan> plansFrom(List<ProductDetails> details) {
  final byId = <String, List<ProductDetails>>{};
  for (final d in details) {
    byId.putIfAbsent(d.id, () => []).add(d);
  }
  final plans = <Plan>[];
  for (final entry in byId.entries) {
    Plan? best;
    for (final d in entry.value) {
      var price = d.price, value = d.rawPrice;
      String? trial;
      if (d is GooglePlayProductDetails && d.subscriptionIndex != null) {
        final offer =
            d.productDetails.subscriptionOfferDetails![d.subscriptionIndex!];
        final phases = offer.pricingPhases;
        final recurring = phases.last;
        price = recurring.formattedPrice;
        value = recurring.priceAmountMicros / 1e6;
        if (phases.length > 1 && phases.first.priceAmountMicros == 0) {
          trial = trialText(phases.first.billingPeriod);
        }
      }
      final plan = Plan(
        id: entry.key,
        buy: d,
        price: price,
        priceValue: value,
        currency: d.currencySymbol,
        trial: trial,
      );
      if (best == null || (best.trial == null && trial != null)) best = plan;
    }
    plans.add(best!);
  }
  return plans..sort((a, b) => a.priceValue.compareTo(b.priceValue));
}

/// Google Play Billing via in_app_purchase. Entitlement is re-checked with Play
/// on every launch (queryPastPurchases), so a refunded or cancelled subscription
/// switches Pro off, while a network error keeps the last known state.
class BillingNotifier extends Notifier<BillingState> {
  StreamSubscription<List<PurchaseDetails>>? _sub;

  @override
  BillingState build() {
    ref.onDispose(() => _sub?.cancel());
    _init();
    return const BillingState();
  }

  Future<void> _init() async {
    final iap = InAppPurchase.instance;
    _sub = iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) {
        state = state.copyWith(error: 'Purchase failed. Please try again.');
      },
    );
    final available = await iap.isAvailable();
    if (!available) {
      state = state.copyWith(available: false, loading: false);
      return;
    }
    final res = await iap.queryProductDetails(kProductIds);
    state = state.copyWith(
      available: true,
      loading: false,
      plans: plansFrom(res.productDetails),
    );
    await refreshEntitlement();
  }

  Future<void> refreshEntitlement() async {
    final android = InAppPurchase.instance
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
    final res = await android.queryPastPurchases();
    // Offline or a Play hiccup: keep the cached state rather than revoking Pro.
    if (res.error != null) return;
    final owned = res.pastPurchases
        .where((p) => kProductIds.contains(p.productID))
        .toList();
    final active = owned.any(
      (p) =>
          p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored,
    );
    final pending = owned.any((p) => p.status == PurchaseStatus.pending);
    await ref.read(proProvider.notifier).set(active);
    state = state.copyWith(pending: pending && !active);
    for (final p in owned.where((p) => p.pendingCompletePurchase)) {
      await InAppPurchase.instance.completePurchase(p);
    }
  }

  Future<void> buy(Plan plan) async {
    state = state.copyWith(error: null);
    await InAppPurchase.instance.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: plan.buy),
    );
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      if (!kProductIds.contains(p.productID)) continue;
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          state = state.copyWith(pending: false);
          await ref.read(proProvider.notifier).set(true);
        case PurchaseStatus.pending:
          // UPI / bank approvals can take minutes; Pro turns on when Play confirms.
          state = state.copyWith(pending: true);
        case PurchaseStatus.error:
          state = state.copyWith(
            pending: false,
            error: 'Payment did not go through. You have not been charged.',
          );
        case PurchaseStatus.canceled:
          state = state.copyWith(pending: false);
      }
      if (p.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(p);
      }
    }
  }
}

final billingProvider = NotifierProvider<BillingNotifier, BillingState>(
  BillingNotifier.new,
);

/// Google Play's own "manage subscription" page for this app.
String manageSubscriptionUrl(String? productId) =>
    'https://play.google.com/store/account/subscriptions?package=com.angelgarg.spikewise'
    '${productId == null ? '' : '&sku=$productId'}';
