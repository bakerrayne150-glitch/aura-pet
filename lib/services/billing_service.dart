import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'assistant_service.dart';

/// Play Billing client for Aura Pet subscriptions.
///
/// Flow:
///   1. [buy] launches the Play purchase sheet.
///   2. The result arrives on [InAppPurchase.purchaseStream] → [_onPurchases].
///   3. Purchased/restored → verified server-side via
///      [AssistantService.verifyPurchase] (Play Developer API).
///   4. Verified → [InAppPurchase.completePurchase] acknowledges it with Play.
///
/// Product IDs must match the subscriptions created in
/// Play Console → Monetize → Products → Subscriptions.
class BillingService extends ChangeNotifier {
  /// Keep in sync with Play Console product IDs.
  static const String monthlySubId = 'aura_pet_monthly';
  static const String yearlySubId = 'aura_pet_yearly';

  /// Must match the applicationId in android/app/build.gradle.
  static const String packageName = 'com.raynebaker.aura_pet';

  final AssistantService _assistant;
  final InAppPurchase _iap = InAppPurchase.instance;

  BillingService(this._assistant);

  bool _initialized = false;
  bool storeAvailable = false;
  bool loadingProducts = true;
  List<ProductDetails> products = [];
  bool purchasing = false;
  String? error;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  /// Idempotent — safe to call from a ProxyProvider update.
  Future<void> ensureInit() async {
    if (_initialized) return;
    _initialized = true;
    await init();
  }

  Future<void> init() async {
    storeAvailable = await _iap.isAvailable();
    if (!storeAvailable) {
      loadingProducts = false;
      notifyListeners();
      return;
    }
    // Listen app-wide: a purchase can complete while on any tab.
    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) {
        error = 'Store error: $e';
        notifyListeners();
      },
    );
    await loadProducts();
  }

  Future<void> loadProducts() async {
    loadingProducts = true;
    error = null;
    notifyListeners();
    try {
      final response =
          await _iap.queryProductDetails({monthlySubId, yearlySubId});
      if (response.error != null) {
        error = 'Could not load products: ${response.error!.message}';
        products = [];
      } else {
        products = response.productDetails.toList()
          ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
        if (response.notFoundIDs.isNotEmpty) {
          // This is the #1 setup bug: IDs don't match Play Console,
          // or the products aren't active yet.
          error =
              'Not yet active in Play Console: ${response.notFoundIDs.join(', ')}';
        }
      }
    } catch (e) {
      error = 'Could not load products: $e';
      products = [];
    }
    loadingProducts = false;
    notifyListeners();
  }

  /// Launches the Play purchase sheet. Result arrives via [_onPurchases].
  Future<void> buy(ProductDetails product) async {
    purchasing = true;
    error = null;
    notifyListeners();
    await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  /// Replays past purchases through [_onPurchases] (re-verifies each one).
  Future<void> restore() async {
    purchasing = true;
    error = null;
    notifyListeners();
    await _iap.restorePurchases();
  }

  Future<void> _onPurchases(List<PurchaseDetails> detailsList) async {
    for (final details in detailsList) {
      switch (details.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final ok = await _assistant.verifyPurchase(
            packageName: packageName,
            productId: details.productID,
            purchaseToken: details.verificationData.serverVerificationData,
          );
          if (ok) {
            if (details.pendingCompletePurchase) {
              await _iap.completePurchase(details);
            }
          } else {
            error =
                'Play could not verify that purchase. Try Restore purchase.';
          }
          break;
        case PurchaseStatus.error:
          final msg = details.error?.message;
          error =
              (msg == null || msg.isEmpty) ? 'Purchase failed.' : msg;
          if (details.pendingCompletePurchase) {
            await _iap.completePurchase(details);
          }
          break;
        case PurchaseStatus.canceled:
          error = null; // user backed out — not an error
          break;
        case PurchaseStatus.pending:
          break; // e.g. pending cash payment — wait for the update
      }
    }
    purchasing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }
}
