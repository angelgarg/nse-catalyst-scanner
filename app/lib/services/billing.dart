import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../config.dart';
import '../state/providers.dart';

class BillingState {
  final bool available;
  final bool loading;
  final List<ProductDetails> products;
  final String? error;

  const BillingState({
    this.available = false,
    this.loading = true,
    this.products = const [],
    this.error,
  });

  BillingState copyWith(
          {bool? available,
          bool? loading,
          List<ProductDetails>? products,
          String? error}) =>
      BillingState(
        available: available ?? this.available,
        loading: loading ?? this.loading,
        products: products ?? this.products,
        error: error,
      );
}

/// Google Play Billing via in_app_purchase. Entitlement is re-derived from
/// Play on every launch (restorePurchases), so a refunded or cancelled
/// subscription switches Pro off on the next start.
class BillingNotifier extends Notifier<BillingState> {
  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _sawActive = false;

  @override
  BillingState build() {
    ref.onDispose(() => _sub?.cancel());
    _init();
    return const BillingState();
  }

  Future<void> _init() async {
    final iap = InAppPurchase.instance;
    _sub = iap.purchaseStream.listen(_onPurchases, onError: (Object e) {
      state = state.copyWith(error: 'Purchase failed: $e');
    });
    final available = await iap.isAvailable();
    if (!available) {
      state = state.copyWith(available: false, loading: false);
      return;
    }
    final res = await iap.queryProductDetails(kProductIds);
    final byId = <String, ProductDetails>{};
    for (final p in res.productDetails) {
      byId.putIfAbsent(p.id, () => p);
    }
    final products = byId.values.toList()
      ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    state = state.copyWith(available: true, loading: false, products: products);
    await refreshEntitlement();
  }

  Future<void> refreshEntitlement() async {
    _sawActive = false;
    await InAppPurchase.instance.restorePurchases();
    // Restore replays owned subscriptions through the stream; if none arrive
    // shortly, the user has no active subscription.
    Future.delayed(const Duration(seconds: 6), () {
      if (!_sawActive) ref.read(proProvider.notifier).set(false);
    });
  }

  Future<void> buy(ProductDetails p) async {
    state = state.copyWith(error: null);
    await InAppPurchase.instance
        .buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p));
  }

  Future<void> _onPurchases(List<PurchaseDetails> list) async {
    for (final p in list) {
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (kProductIds.contains(p.productID)) {
            _sawActive = true;
            await ref.read(proProvider.notifier).set(true);
          }
        case PurchaseStatus.error:
          state = state.copyWith(error: p.error?.message ?? 'Purchase failed');
        case PurchaseStatus.canceled:
        case PurchaseStatus.pending:
          break;
      }
      if (p.pendingCompletePurchase) {
        await InAppPurchase.instance.completePurchase(p);
      }
    }
  }
}

final billingProvider =
    NotifierProvider<BillingNotifier, BillingState>(BillingNotifier.new);
